// lib/servisler/veri_sagligi_servisi.dart
//
// VERİ SAĞLIĞI MERKEZİ (protokol §13) — uygulamanın kritik veri
// bütünlüğü göstergelerini TEK bir yerde toplar. Her kontrol salt
// okunur bir SAYIM yapar (durum: yeşil/sarı/kırmızı); bazı kontroller
// için kanıtlanmış "mutabakat" fonksiyonlarını çağıran bir DÜZELT
// aksiyonu da sunulur.
//
// Kasıtlı olarak yapmadığımız şey: hiçbir kontrol otomatik olarak
// (kullanıcı onayı olmadan) veri değiştirmez — ekran her zaman önce
// SAYIYI gösterir, düzeltme ayrı bir buton/onaydır.
//
// 🔴 YAPI (derin analiz 2026-10-07):
//  • Her kontrol bir [_Kontrol] tanımıdır; hata TEK yerde ([_Kontrol.calistir])
//    "Kontrol edilemedi" sonucuna çevrilir. Önceden 6 kontrolde try/catch
//    yoktu — biri hata atınca Future.wait TÜM sonuçları çöpe atıyor, ekran
//    boş "0/0/0" gösteriyordu. Depolar ise hatada 0 döndürüp kontrolü
//    YEŞİL gösteriyordu (artık hatayı iletiyorlar).
//  • Finansal mutabakatlar çalıştırılamazsa KIRMIZI döner: doğrulanamayan
//    bakiyelerle Yıl Sonu Devri'nin sessizce geçmesi engellenir.
//  • [kontrolleriAkisla] sonuçları geldikçe verir — ekran ağır kontrolleri
//    (PRAGMA integrity_check vb.) beklerken boş "yükleniyor"da kalmaz.
import 'package:sqflite/sqflite.dart';

import '../cekirdek/utils/hata_utils.dart';
import '../depolar/banka_hesap_deposu.dart';
import '../depolar/cari_deposu.dart';
import '../depolar/kasa_deposu.dart';
import '../depolar/kredi_karti_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../depolar/sync_cakisma_deposu.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/supabase_saglayici.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../servisler/log_servisi.dart';
import '../servisler/yedekleme_servisi.dart';
import '../veri/database/veritabani.dart';

enum SaglikDurum { yesil, sari, kirmizi }

class SaglikKontrolSonucu {
  final String id;
  final String baslik;
  final String kategori;
  final SaglikDurum durum;
  final String mesaj;

  /// Sorunlu kayıt sayısı; kontrol çalıştırılamadıysa -1.
  final int sayi;

  /// null ise otomatik düzeltme yok (ör. manuel inceleme gerekir).
  final Future<int> Function()? duzelt;

  /// Düzelt onayında gösterilecek, bu kontrole özgü açıklama. null ise
  /// ekran genel "hareket geçmişinden yeniden hesaplar" metnini kullanır.
  final String? duzeltAciklama;

  const SaglikKontrolSonucu({
    required this.id,
    required this.baslik,
    required this.kategori,
    required this.durum,
    required this.mesaj,
    required this.sayi,
    this.duzelt,
    this.duzeltAciklama,
  });

  bool get calistirilamadi => sayi < 0 && mesaj.startsWith(_Kontrol.hataOneki);
}

/// Tek bir sağlık kontrolünün kimliği ve gövdesi.
class _Kontrol {
  static const hataOneki = 'Kontrol edilemedi';

  final String id;
  final String baslik;
  final String kategori;

  /// Gövde hata atarsa sonucun durumu (finansal mutabakat/SQLite: kırmızı).
  final SaglikDurum hataDurumu;
  final Future<SaglikKontrolSonucu> Function(_Kontrol k) govde;

  const _Kontrol(this.id, this.baslik, this.kategori, this.govde,
      {this.hataDurumu = SaglikDurum.sari});

  SaglikKontrolSonucu sonuc(
    SaglikDurum durum,
    String mesaj, {
    int sayi = 0,
    Future<int> Function()? duzelt,
    String? duzeltAciklama,
  }) =>
      SaglikKontrolSonucu(
        id: id,
        baslik: baslik,
        kategori: kategori,
        durum: durum,
        mesaj: mesaj,
        sayi: sayi,
        duzelt: duzelt,
        duzeltAciklama: duzeltAciklama,
      );

  Future<SaglikKontrolSonucu> calistir() async {
    try {
      return await govde(this);
    } catch (e, st) {
      LogServisi().hata('VeriSagligi.$id', hata: e, yigin: st);
      return sonuc(hataDurumu, '$hataOneki: ${kullaniciyaHataMetni(e)}', sayi: -1);
    }
  }
}

/// Sayıya göre durum: 0 → yeşil, ≤ [sariEnFazla] → sarı, aksi → [ust].
SaglikDurum _kademe(int sayi,
    {int sariEnFazla = 0, SaglikDurum ust = SaglikDurum.kirmizi}) {
  if (sayi == 0) return SaglikDurum.yesil;
  if (sayi <= sariEnFazla) return SaglikDurum.sari;
  return ust;
}

int _sayiOku(List<Map<String, Object?>> rows, [String sutun = 'n']) =>
    rows.isEmpty ? 0 : (rows.first[sutun] as num?)?.toInt() ?? 0;

class VeriSagligiServisi {
  Future<Database> get _db async => Veritabani().db;

  /// Hafiften ağıra sıralı: akışta ilk sonuçlar hemen görünür, en pahalı
  /// kontrol (PRAGMA integrity_check) en sonda çalışır.
  late final List<_Kontrol> _kontroller = [
    _Kontrol('sync_kuyruk', 'Sync Kuyruğu', 'Senkronizasyon', _syncKuyrugu),
    _Kontrol('bulut_sema', 'Bulut Şema Uyumu', 'Senkron', _bulutSemaUyumu),
    _Kontrol('yedekleme', 'Yedekleme', 'Sistem', _yedeklemeDurumu),
    _Kontrol('sync_cakisma', 'Sync Çakışmaları', 'Senkronizasyon', _syncCakismalari),
    _Kontrol('negatif_stok', 'Negatif Stok', 'Ürün', _negatifStok),
    _Kontrol('dup_barkod', 'Mükerrer Barkod', 'Ürün', _duplicateBarkod),
    _Kontrol('mukerrer_cari', 'Aynı Unvanlı Cari', 'Veritabanı', _mukerrerCariUnvan),
    _Kontrol('cari_mutabakat', 'Cari Mutabakat', 'Mutabakat', _cariMutabakat,
        hataDurumu: SaglikDurum.kirmizi),
    _Kontrol('stok_mutabakat', 'Stok Mutabakat', 'Mutabakat', _stokMutabakat,
        hataDurumu: SaglikDurum.kirmizi),
    _Kontrol('kasa_mutabakat', 'Kasa Mutabakat', 'Mutabakat', _kasaMutabakat,
        hataDurumu: SaglikDurum.kirmizi),
    _Kontrol('banka_mutabakat', 'Banka Mutabakat', 'Mutabakat', _bankaMutabakat,
        hataDurumu: SaglikDurum.kirmizi),
    _Kontrol('kredi_karti_mutabakat', 'Kredi Kartı Mutabakat', 'Mutabakat',
        _krediKartiMutabakat, hataDurumu: SaglikDurum.kirmizi),
    _Kontrol('satis_kasa', 'Satış-Kasa Tutarlılığı', 'Mutabakat', _satisKasaTutarliligi),
    _Kontrol('satis_stok', 'Satış-Stok Tutarlılığı', 'Mutabakat', _satisStokTutarliligi),
    _Kontrol('iade_kalem_stok', 'İade Kalem Miktarı', 'Mutabakat',
        _iadeKalemStokTutarliligi),
    _Kontrol('baslik_kalem', 'Satış Başlık/Kalem Toplamı', 'Finans',
        _baslikKalemTutarlilik),
    _Kontrol('yetim', 'Yetim Kayıtlar', 'Veritabanı', _yetimKayitlar),
    _Kontrol('mukerrer_gid', 'Mükerrer Sync Kimliği', 'Senkronizasyon', _mukerrerGlobalId),
    _Kontrol('fk', 'Foreign Key Bütünlüğü', 'Veritabanı', _foreignKeyKontrol),
    _Kontrol('sqlite', 'SQLite Bütünlüğü', 'Veritabanı', _sqliteButunluk,
        hataDurumu: SaglikDurum.kirmizi),
  ];

  /// Toplam kontrol sayısı (ekrandaki ilerleme göstergesi için).
  int get kontrolSayisi => _kontroller.length;

  /// Tüm kontroller; hiçbir zaman hata fırlatmaz (her kontrol kendi
  /// hatasını sonuca çevirir). Yıl Sonu Devri ve testler kullanır.
  Future<List<SaglikKontrolSonucu>> tumKontrolleriCalistir() =>
      Future.wait(_kontroller.map((k) => k.calistir()));

  /// Sonuçları tamamlandıkça verir. Tek SQLite bağlantısı sorguları zaten
  /// sıraya koyduğundan sıralı çalıştırmak toplam süreyi uzatmaz, ama
  /// ekranın ilk sonuçları beklemeden göstermesini sağlar.
  Stream<SaglikKontrolSonucu> kontrolleriAkisla() async* {
    for (final k in _kontroller) {
      yield await k.calistir();
    }
  }

  // ── SQLite bütünlüğü ────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _sqliteButunluk(_Kontrol k) async {
    final db = await _db;
    final rows = await db.rawQuery('PRAGMA integrity_check');
    final sonuc = rows.isNotEmpty ? rows.first.values.first.toString() : 'unknown';
    if (sonuc == 'ok') return k.sonuc(SaglikDurum.yesil, 'Veritabanı dosyası sağlam.');
    return k.sonuc(SaglikDurum.kirmizi, 'SQLite bütünlük hatası: $sonuc', sayi: 1);
  }

  // ── Foreign Key ─────────────────────────────────────────────────────
  // 🔴 DÜZELTME (2026-09-21): bu kontrol ÖNCEDEN sadece SAYIYORDU —
  // düzelt callback'i yoktu. Yıl Sonu Devir'in FAZ 1 kontrolü bu sonucu
  // CRITICAL bulduğunda devri anında durduruyordu (haklı olarak — bu
  // GERÇEK bir bütünlük sorunu), ama kullanıcının bunu DÜZELTECEK hiçbir
  // aracı yoktu — devir kalıcı olarak tıkanıyordu.
  Future<SaglikKontrolSonucu> _foreignKeyKontrol(_Kontrol k) async {
    final db = await _db;
    final rows = await db.rawQuery('PRAGMA foreign_key_check');
    if (rows.isEmpty) return k.sonuc(SaglikDurum.yesil, 'İlişkisel bütünlük ihlali yok.');
    return k.sonuc(SaglikDurum.kirmizi, '${rows.length} foreign key ihlali bulundu.',
        sayi: rows.length,
        duzelt: _yabanciAnahtarTemizle,
        duzeltAciklama: 'Geçersiz referans taşıyan kolonlar NULL yapılır; '
            'zorunlu üst kaydı hiç olmayan yetim satırlar içerikleriyle '
            'loglanıp silinir.');
  }

  /// `PRAGMA foreign_key_check`'in bulduğu her ihlali TEK TEK, kolon
  /// bazında en güvenli yöntemle giderir:
  /// - Kolon NULL'a izin veriyorsa: sadece o kolonu NULL yapar (satır
  ///   KORUNUR, sadece geçersiz referans koparılır — veri kaybı yok).
  /// - Kolon NOT NULL ise (satır zorunlu bir üst kayda bağlı ama o kayıt
  ///   artık yok): `is_deleted` işaretlemek `PRAGMA foreign_key_check`'i
  ///   TATMİN ETMEZ (pragma ham kolon değerine bakar) — satır LogServisi'ne
  ///   TAM içeriğiyle kaydedilip (denetim izi) ardından silinir. Bu,
  ///   geçerli bir işlemi geri almak DEĞİL — hiçbir zaman doğru
  ///   hesaplanamayacak, bozuk bir satırı temizlemektir.
  Future<int> _yabanciAnahtarTemizle() async {
    final db = await _db;
    var duzeltilen = 0;
    await db.transaction((txn) async {
      final ihlaller = await txn.rawQuery('PRAGMA foreign_key_check');
      for (final ihlal in ihlaller) {
        final tablo = ihlal['table'] as String?;
        final rowid = ihlal['rowid'];
        final fkid = ihlal['fkid'] as int?;
        if (tablo == null || rowid == null || fkid == null) continue;

        final fkListesi = await txn.rawQuery('PRAGMA foreign_key_list("$tablo")');
        final fkEslesme = fkListesi.where((f) => (f['id'] as int?) == fkid);
        if (fkEslesme.isEmpty) continue;
        final kolon = fkEslesme.first['from'] as String?;
        if (kolon == null) continue;

        final tabloBilgisi = await txn.rawQuery('PRAGMA table_info("$tablo")');
        final kolonBilgisiListesi = tabloBilgisi.where((c) => c['name'] == kolon);
        final notNull = kolonBilgisiListesi.isNotEmpty &&
            (kolonBilgisiListesi.first['notnull'] as int?) == 1;

        if (!notNull) {
          await txn.rawUpdate(
              'UPDATE "$tablo" SET "$kolon" = NULL WHERE rowid = ?', [rowid]);
        } else {
          final satirlar =
              await txn.rawQuery('SELECT * FROM "$tablo" WHERE rowid = ?', [rowid]);
          if (satirlar.isNotEmpty) {
            LogServisi().hata(
                'VeriSagligi.fkTemizle — yetim satır silindi ($tablo.$kolon)',
                hata: satirlar.first);
          }
          await txn.rawDelete('DELETE FROM "$tablo" WHERE rowid = ?', [rowid]);
        }
        duzeltilen++;
      }
    });
    return duzeltilen;
  }

  // ── Mutabakatlar (hareket geçmişi ↔ özet alan) ──────────────────────
  Future<SaglikKontrolSonucu> _cariMutabakat(_Kontrol k) async {
    final sayi = await CariDeposu().bakiyeUyumsuzlukSayisi();
    return k.sonuc(
      _kademe(sayi, sariEnFazla: 3),
      sayi == 0
          ? 'Tüm cari bakiyeleri hareket geçmişiyle uyumlu.'
          : '$sayi carinin bakiyesi hareket geçmişiyle uyuşmuyor.',
      sayi: sayi,
      duzelt: sayi > 0 ? () => CariDeposu().bakiyeMutabakatYap() : null,
    );
  }

  Future<SaglikKontrolSonucu> _stokMutabakat(_Kontrol k) async {
    final sayi = await StokDeposu().mutabakatUyumsuzlukSayisi();
    return k.sonuc(
      _kademe(sayi, sariEnFazla: 3),
      sayi == 0
          ? 'Tüm ürün stokları hareket geçmişiyle uyumlu.'
          : '$sayi ürünün stoğu hareket geçmişiyle uyuşmuyor.',
      sayi: sayi,
      duzelt: sayi > 0 ? () => StokDeposu().stokMutabakatYap() : null,
    );
  }

  Future<SaglikKontrolSonucu> _kasaMutabakat(_Kontrol k) async {
    final sayi = await KasaDeposu().bakiyeUyumsuzlukSayisi();
    return k.sonuc(
      _kademe(sayi),
      sayi == 0
          ? 'Kasa hareketleri sırayla tutarlı.'
          : '$sayi kasa hareketinin bakiyesi hatalı hesaplanmış.',
      sayi: sayi,
      duzelt: sayi > 0 ? () => KasaDeposu().bakiyeMutabakatYap() : null,
    );
  }

  Future<SaglikKontrolSonucu> _bankaMutabakat(_Kontrol k) async {
    final sayi = await BankaHesapDeposu().bakiyeUyumsuzlukSayisi();
    return k.sonuc(
      _kademe(sayi),
      sayi == 0
          ? 'Banka hesap bakiyeleri hareket geçmişiyle uyumlu.'
          : '$sayi banka hesabının bakiyesi kendi hareket geçmişiyle uyuşmuyor.',
      sayi: sayi,
      duzelt: sayi > 0 ? () => BankaHesapDeposu().bakiyeMutabakatYap() : null,
    );
  }

  // Madde 11 (2026-09-16): limitMutabakatYap() önceden sadece senkron
  // sonrası akışlardan çağrılıyordu, Veri Sağlığı Merkezi'nde görünmüyordu.
  Future<SaglikKontrolSonucu> _krediKartiMutabakat(_Kontrol k) async {
    final sayi = await KrediKartiDeposu().uyumsuzlukSayisi();
    return k.sonuc(
      _kademe(sayi, sariEnFazla: 3),
      sayi == 0
          ? 'Tüm kredi kartı limit kullanımları hareket geçmişiyle uyumlu.'
          : '$sayi kredi kartının kullanılan limiti hareket geçmişiyle uyuşmuyor.',
      sayi: sayi,
      duzelt: sayi > 0 ? () => KrediKartiDeposu().limitMutabakatYap() : null,
    );
  }

  // ── Satış-Kasa tutarlılığı ──────────────────────────────────────────
  // 'Cari' hariç TÜM ödeme yöntemleri (Nakit/Kart/Karma — karma her yöntem
  // için ayrı kasa hareketi açar) en az bir kasa hareketine sahip olmalı.
  Future<SaglikKontrolSonucu> _satisKasaTutarliligi(_Kontrol k) async {
    final db = await _db;
    final sayi = _sayiOku(await db.rawQuery('''
      SELECT COUNT(*) as n FROM satislar s
      WHERE s.is_deleted = 0 AND s.odeme_yontemi != 'Cari' AND s.odenen_tutar > 0.005
        AND NOT EXISTS (
          SELECT 1 FROM kasa_hareketleri k
          WHERE k.referans_id = s.id AND k.referans_turu = 'satis' AND k.deleted_at IS NULL
        )
    '''));
    return k.sonuc(
        _kademe(sayi),
        sayi == 0
            ? 'Her nakit/kart/karma satışın kasa karşılığı var.'
            : '$sayi satışın (nakit/kart/karma) kasa hareketi eksik.',
        sayi: sayi);
  }

  // ── Satış-Stok tutarlılığı ──────────────────────────────────────────
  Future<SaglikKontrolSonucu> _satisStokTutarliligi(_Kontrol k) async {
    final db = await _db;
    final sayi = _sayiOku(await db.rawQuery('''
      SELECT COUNT(*) as n FROM satis_kalem sk
      JOIN satislar s ON s.id = sk.satis_id AND s.is_deleted = 0
      WHERE NOT EXISTS (
        SELECT 1 FROM stok_hareket sh
        WHERE sh.referans_id = sk.satis_id AND sh.referans_turu = 'satis' AND sh.urun_id = sk.urun_id
      )
    '''));
    return k.sonuc(
        _kademe(sayi, sariEnFazla: 5),
        sayi == 0
            ? 'Her satış kalemi bir stok hareketiyle eşleşiyor.'
            : '$sayi satış kaleminin stok hareketi bulunamadı.',
        sayi: sayi);
  }

  // ── Duplicate barkod ────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _duplicateBarkod(_Kontrol k) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT barkod, COUNT(*) as c FROM urunler
      WHERE barkod IS NOT NULL AND barkod != '' AND is_deleted = 0
      GROUP BY barkod HAVING c > 1
    ''');
    final sayi = rows.length;
    return k.sonuc(
        _kademe(sayi, ust: SaglikDurum.sari),
        sayi == 0
            ? 'Aynı barkodu paylaşan ürün yok.'
            : '$sayi barkod birden fazla üründe kullanılıyor.',
        sayi: sayi);
  }

  // ── Yetim kayıtlar ──────────────────────────────────────────────────
  static const _yetimSorgulari = [
    'SELECT COUNT(*) as n FROM satis_kalem sk WHERE NOT EXISTS (SELECT 1 FROM satislar s WHERE s.id = sk.satis_id)',
    'SELECT COUNT(*) as n FROM cari_hareket ch WHERE NOT EXISTS (SELECT 1 FROM cari c WHERE c.id = ch.cari_id)',
    'SELECT COUNT(*) as n FROM stok_hareket sh WHERE NOT EXISTS (SELECT 1 FROM urunler u WHERE u.id = sh.urun_id)',
    'SELECT COUNT(*) as n FROM iade_kalem ik WHERE NOT EXISTS (SELECT 1 FROM iade i WHERE i.id = ik.iade_id)',
    'SELECT COUNT(*) as n FROM fatura_detaylari fd WHERE NOT EXISTS (SELECT 1 FROM faturalar f WHERE f.id = fd.fatura_id)',
    'SELECT COUNT(*) as n FROM tedarikci_siparis_kalem k WHERE NOT EXISTS (SELECT 1 FROM tedarikci_siparisler t WHERE t.id = k.siparis_id)',
    'SELECT COUNT(*) as n FROM satis_kalem sk WHERE NOT EXISTS (SELECT 1 FROM urunler u WHERE u.id = sk.urun_id)',
    'SELECT COUNT(*) as n FROM sube_urun su WHERE NOT EXISTS (SELECT 1 FROM urunler u WHERE u.id = su.urun_id)',
  ];

  Future<SaglikKontrolSonucu> _yetimKayitlar(_Kontrol k) async {
    final db = await _db;
    final sonuclar = await Future.wait(_yetimSorgulari.map(db.rawQuery));
    final sayi = sonuclar.fold<int>(0, (t, r) => t + _sayiOku(r));
    return k.sonuc(
        _kademe(sayi, ust: SaglikDurum.sari),
        sayi == 0
            ? 'Sahipsiz (referansı silinmiş) kayıt yok.'
            : '$sayi kayıt, artık var olmayan bir ana kayda bağlı (satış/cari/ürün silinmiş olabilir).',
        sayi: sayi);
  }

  // ── Satış başlık toplamı ↔ kalem toplamı ────────────────────────────
  // İki cihazda aynı satışın başlığı/kalemleri ayrı ayrı senkronlanınca
  // (fiş güncelleme + çakışma) başlıkla kalemler ayrışabilir. Salt okunur
  // uyarı (sarı — devri engellemez); düzeltme kararı kullanıcıda.
  Future<SaglikKontrolSonucu> _baslikKalemTutarlilik(_Kontrol k) async {
    final db = await _db;
    final sayi = _sayiOku(await db.rawQuery('''
      SELECT COUNT(*) AS n FROM (
        SELECT s.id
        FROM satislar s
        JOIN satis_kalem k ON k.satis_id = s.id
        WHERE s.is_deleted = 0 AND s.iptal = 0 AND s.sync_cakisma_kopyasi = 0
        GROUP BY s.id
        HAVING ABS(MAX(s.genel_toplam)
                   - COALESCE(MAX(s.kargo_ucreti), 0)
                   - COALESCE(MAX(s.servis_ucreti), 0)
                   - SUM(k.toplam_tutar)) > 0.10
      )
    '''));
    return k.sonuc(
        _kademe(sayi, ust: SaglikDurum.sari),
        sayi == 0
            ? 'Satış toplamları kalemlerle uyumlu.'
            : '$sayi satışın genel toplamı kalem toplamından farklı '
                '(fiş güncelleme / senkron çakışması olabilir).',
        sayi: sayi,
        duzelt: sayi > 0 ? _kalemToplamlariniOnar : null,
        duzeltAciklama: 'Yalnız başlık toplamı "birim fiyat × miktar" ile '
            'uyuşan satışlarda kalem tutarları birim fiyattan yeniden '
            'yazılır; başka sebeple uyuşmayan satışlara dokunulmaz.');
  }

  /// Çift-indirim hatasıyla (kalem toplamı birimFiyat × (1 − iskontoOran)
  /// olarak yeniden hesaplanmış) bozulan kalemleri onarır: SADECE başlık
  /// toplamı ile `birim_fiyat × miktar` toplamı uyuşan satışlarda kalem
  /// net/toplam/KDV/iskonto tutarı `birim_fiyat` üzerinden yeniden yazılır
  /// ve buluta gönderilmek üzere kuyruğa alınır. Uyuşmayan (başka sebepli)
  /// satışlara DOKUNULMAZ.
  Future<int> _kalemToplamlariniOnar() async {
    final db = await _db;
    var duzeltilen = 0;
    await db.transaction((txn) async {
      final satislar = await txn.rawQuery('''
        SELECT s.id, s.genel_toplam,
               COALESCE(s.kargo_ucreti,0) + COALESCE(s.servis_ucreti,0) AS ek
        FROM satislar s
        WHERE s.is_deleted = 0 AND s.iptal = 0 AND s.sync_cakisma_kopyasi = 0
      ''');
      final now = DateTime.now().toUtc().toIso8601String();
      for (final s in satislar) {
        final sid = s['id'] as int;
        final kalemler = await txn.query('satis_kalem',
            where: 'satis_id = ?', whereArgs: [sid]);
        if (kalemler.isEmpty) continue;
        double kayitliToplam = 0, olmasiGereken = 0;
        for (final k in kalemler) {
          kayitliToplam += (k['toplam_tutar'] as num?)?.toDouble() ?? 0;
          olmasiGereken += ((k['birim_fiyat'] as num?)?.toDouble() ?? 0) *
              ((k['miktar'] as num?)?.toDouble() ?? 0);
        }
        final baslik = ((s['genel_toplam'] as num?)?.toDouble() ?? 0) -
            ((s['ek'] as num?)?.toDouble() ?? 0);
        if ((baslik - kayitliToplam).abs() <= 0.10) continue;
        if ((baslik - olmasiGereken).abs() > 0.10) continue;
        for (final k in kalemler) {
          final birim = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
          final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
          final oran = (k['iskonto_oran'] as num?)?.toDouble() ?? 0;
          final kdvOran = (k['kdv_oran'] as num?)?.toDouble() ?? 0;
          final toplam = birim * miktar;
          // Katalog fiyatı = birim / (1 − oran); iskonto = fark × miktar.
          final iskTutar = (oran > 0 && oran < 100)
              ? (birim / (1 - oran / 100) - birim) * miktar
              : 0.0;
          final kdv = kdvOran > 0 ? toplam * kdvOran / (100 + kdvOran) : 0.0;
          await txn.update(
              'satis_kalem',
              {
                'net_fiyat': birim,
                'toplam_tutar': toplam,
                'iskonto_tutar': iskTutar,
                'kdv_tutar': kdv,
                'last_updated': now,
              },
              where: 'id = ?',
              whereArgs: [k['id']]);
          final yeni = await txn.query('satis_kalem',
              where: 'id = ?', whereArgs: [k['id']], limit: 1);
          if (yeni.isNotEmpty) {
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'satis_kalem', veri: Map<String, dynamic>.from(yeni.first));
          }
          duzeltilen++;
        }
      }
    });
    return duzeltilen;
  }

  // ── İade kalem miktarı ↔ stok hareketi ──────────────────────────────
  // Eski bir hata (iade fişinde bir ürün düzenlenince fişteki TÜM kalemlerin
  // aynı miktara ezilmesi) kalem miktarlarını bozmuş olabilir. Stok hareketleri
  // (iade girişi + iade düzeltmesi) her ürünün GERÇEK iade miktarını tutar ve
  // o hatadan etkilenmemiştir: net = Σ(sonraki_stok − önceki_stok). Kayıtlı
  // kalem miktarı bundan farklıysa uyarılır; düzeltme YALNIZ miktarı stok
  // hareketine göre yazar (tutar/cari için fişin elle kontrolü gerekir).
  static const String _iadeKalemFarkSql = '''
    SELECT ik.id AS kalem_id, ik.iade_id, ik.urun_id, ik.miktar AS kayitli,
           i.fis_no AS fis_no, ik.urun_adi AS urun_adi,
           (SELECT COALESCE(SUM(sh.sonraki_stok - sh.onceki_stok), 0)
              FROM stok_hareket sh
             WHERE sh.referans_id = ik.iade_id
               AND sh.referans_turu IN ('iade', 'iade_duzenle')
               AND sh.urun_id = ik.urun_id) AS gercek
      FROM iade_kalem ik
      JOIN iade i ON i.id = ik.iade_id
     WHERE i.deleted_at IS NULL
       AND ik.urun_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM stok_hareket x
                        WHERE x.referans_id = ik.iade_id AND x.referans_turu = 'iade_iptal')
       AND EXISTS (SELECT 1 FROM stok_hareket y
                    WHERE y.referans_id = ik.iade_id
                      AND y.referans_turu IN ('iade', 'iade_duzenle')
                      AND y.urun_id = ik.urun_id)
       AND ABS(ik.miktar - (SELECT COALESCE(SUM(sh2.sonraki_stok - sh2.onceki_stok), 0)
                              FROM stok_hareket sh2
                             WHERE sh2.referans_id = ik.iade_id
                               AND sh2.referans_turu IN ('iade', 'iade_duzenle')
                               AND sh2.urun_id = ik.urun_id)) > 0.0005
  ''';

  static String _miktarYaz(Object? v) {
    final d = (v as num?)?.toDouble() ?? 0;
    return d == d.truncateToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  Future<SaglikKontrolSonucu> _iadeKalemStokTutarliligi(_Kontrol k) async {
    final db = await _db;
    final rows = await db.rawQuery(_iadeKalemFarkSql);
    final sayi = rows.length;
    if (sayi == 0) {
      return k.sonuc(SaglikDurum.yesil, 'İade kalem miktarları stok hareketleriyle uyumlu.');
    }
    final ayrinti = rows.take(3).map((r) =>
        '${r['fis_no'] ?? '#${r['iade_id']}'} ${r['urun_adi'] ?? ''}: '
        'kayıtlı ${_miktarYaz(r['kayitli'])} / stok hareketine göre ${_miktarYaz(r['gercek'])}');
    return k.sonuc(
        SaglikDurum.sari,
        '$sayi iade kaleminin miktarı stok hareketinden farklı (${ayrinti.join('; ')}'
        '${sayi > 3 ? ' …' : ''}). Düzelt yalnız MİKTARI onarır; '
        'tutar/cari için ilgili fişi açıp kontrol edin.',
        sayi: sayi,
        duzelt: _iadeKalemMiktarlariniOnar,
        duzeltAciklama: 'İade kalem MİKTARI stok hareketlerindeki gerçek '
            'iade miktarına göre yazılır. Tutar ve cari etkisi değişmez.');
  }

  Future<int> _iadeKalemMiktarlariniOnar() async {
    final db = await _db;
    var duzeltilen = 0;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(_iadeKalemFarkSql);
      final now = DateTime.now().toUtc().toIso8601String();
      for (final r in rows) {
        final gercek = (r['gercek'] as num?)?.toDouble() ?? 0;
        if (gercek <= 0) continue; // net sıfır/eksi → manuel inceleme
        await txn.update('iade_kalem', {'miktar': gercek, 'last_updated': now},
            where: 'id = ?', whereArgs: [r['kalem_id']]);
        final yeni = await txn.query('iade_kalem',
            where: 'id = ?', whereArgs: [r['kalem_id']], limit: 1);
        if (yeni.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'iade_kalem', veri: Map<String, dynamic>.from(yeni.first));
        }
        LogServisi().bilgi('İade kalem miktarı onarıldı: iade ${r['iade_id']} '
            'ürün ${r['urun_id']} ${r['kayitli']} → $gercek');
        duzeltilen++;
      }
    });
    return duzeltilen;
  }

  // ── Bulut şema uyumu ────────────────────────────────────────────────
  // Gönderim sırasında bulutta bulunmadığı için ATLANAN sütunlar (yerelde
  // eklenmiş ama supabase_tam_sema.sql henüz çalıştırılmamış). Bu sütunlardaki
  // veri diğer cihazlara ULAŞMAZ; SQL çalıştırılınca kendiliğinden düzelir.
  Future<SaglikKontrolSonucu> _bulutSemaUyumu(_Kontrol k) async {
    final eksik = SupabaseSaglayici.eksikBulutSutunlari.toList()..sort();
    return k.sonuc(
      _kademe(eksik.length, ust: SaglikDurum.sari),
      eksik.isEmpty
          ? 'Bilinen eksik bulut sütunu yok (bulut bağlantısı kurulup gönderim yapıldıkça güncellenir).'
          : '${eksik.length} yerel sütun bulut şemasında YOK ve gönderilmiyor '
              '(${eksik.take(4).join(', ')}${eksik.length > 4 ? ' …' : ''}). '
              'supabase_tam_sema.sql dosyasını Supabase SQL Editor\'de çalıştırın.',
      sayi: eksik.length,
    );
  }

  // ── Aynı unvanlı cari kopyaları ─────────────────────────────────────
  // Senkron/içe aktarma hatasıyla tüm cari listesi ikinci kez oluşabiliyor
  // (yeni global_id + yeni kod). Bakiye toplamları iki katına çıkar.
  Future<SaglikKontrolSonucu> _mukerrerCariUnvan(_Kontrol k) async {
    final db = await _db;
    final sayi = _sayiOku(await db.rawQuery('''
      SELECT COUNT(*) AS n FROM (
        SELECT UPPER(TRIM(unvan)) AS u FROM cari
        WHERE is_deleted = 0 AND unvan IS NOT NULL AND TRIM(unvan) != ''
        GROUP BY u HAVING COUNT(*) > 1
      )
    '''));
    return k.sonuc(
        _kademe(sayi, ust: SaglikDurum.sari),
        sayi == 0
            ? 'Aynı unvanı taşıyan birden fazla cari yok.'
            : '$sayi unvan birden fazla cari kartında var — mükerrer '
                'aktarım olabilir (bakiye toplamları şişer).',
        sayi: sayi);
  }

  // ── Mükerrer global_id ──────────────────────────────────────────────
  // Sync kimliği tekil olmalı: yükseltilmiş cihazlarda UNIQUE indeks yoksa
  // aynı kayıt iki satır olarak toplamlara girebilir.
  static const _gidTablolari = [
    'satislar', 'satis_kalem', 'cari', 'cari_hareket', 'stok_hareket',
    'kasa_hareketleri', 'urunler', 'iade', 'iade_kalem', 'faturalar',
    'fatura_detaylari', 'giderler',
  ];

  Future<SaglikKontrolSonucu> _mukerrerGlobalId(_Kontrol k) async {
    final db = await _db;
    var toplam = 0;
    final ayrinti = <String>[];
    for (final t in _gidTablolari) {
      final int n;
      try {
        n = _sayiOku(await db.rawQuery(
            'SELECT COUNT(*) AS n FROM (SELECT global_id FROM $t '
            "WHERE global_id IS NOT NULL AND global_id != '' "
            'GROUP BY global_id HAVING COUNT(*) > 1)'));
      } on DatabaseException {
        continue; // eski şemada tablo/sütun yok — bu tablo atlanır
      }
      if (n > 0) {
        toplam += n;
        ayrinti.add('$t: $n');
      }
    }
    return k.sonuc(
        _kademe(toplam, ust: SaglikDurum.sari),
        toplam == 0
            ? 'Mükerrer sync kimliği yok.'
            : '$toplam mükerrer kimlik (${ayrinti.join(', ')}).',
        sayi: toplam);
  }

  // ── Negatif stok ────────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _negatifStok(_Kontrol k) async {
    final db = await _db;
    final sayi = _sayiOku(await db.rawQuery(
        'SELECT COUNT(*) as n FROM urunler WHERE stok < 0 AND is_deleted = 0'));
    // B2 kararı (2026-10-07): negatif stok GEÇERLİ bir durum (mal girişi
    // yapılmadan satılmış) — hata değil, takip edilmesi gereken bir UYARI;
    // Yıl Sonu Devri'ni engellemez.
    return k.sonuc(
        _kademe(sayi, ust: SaglikDurum.sari),
        sayi == 0
            ? 'Negatif stoklu ürün yok.'
            : '$sayi ürünün stoğu negatif (mal girişi yapılmadan satılmış olabilir).',
        sayi: sayi);
  }

  // ── Sync kuyruğu (BulutManager'ın CANLI bekleyen listesi) ───────────
  Future<SaglikKontrolSonucu> _syncKuyrugu(_Kontrol k) async {
    final sayi = BulutManager().bekleyenSayisi;
    return k.sonuc(
        _kademe(sayi, sariEnFazla: 20),
        sayi == 0
            ? 'Gönderilmeyi bekleyen değişiklik yok.'
            : '$sayi değişiklik henüz buluta gönderilmedi.',
        sayi: sayi);
  }

  // ── Sync çakışmaları (protokol §12) ─────────────────────────────────
  // Salt okunur sayım; "sahte" çakışmaları (biçim farkı, cihaz kimliği,
  // yalnız boş alan dolması) kapatmak artık AÇIK bir Düzelt aksiyonu.
  Future<SaglikKontrolSonucu> _syncCakismalari(_Kontrol k) async {
    final depo = SyncCakismaDeposu();
    final sayi = await depo.cozulmemisSayisi();
    return k.sonuc(
      _kademe(sayi, ust: SaglikDurum.sari),
      sayi == 0
          ? 'Çözülmemiş senkron çakışması yok.'
          : '$sayi çözülmemiş senkron çakışması var.',
      sayi: sayi,
      duzelt: sayi > 0 ? depo.sahteleriTemizle : null,
      duzeltAciklama: 'Gerçek çakışma olmayan kayıtlar (ondalık/tarih biçimi '
          'farkı, cihaz kimliği, yalnız boş alan dolması) otomatik kapatılır. '
          'Gerçek çakışmalar Sync Çakışmaları ekranında incelenmeye devam eder.',
    );
  }

  // ── Yedekleme durumu ────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _yedeklemeDurumu(_Kontrol k) async {
    final liste = await YedeklemeServisi().yedekListesi();
    if (liste.isEmpty) {
      return k.sonuc(SaglikDurum.kirmizi, 'Hiç yedek alınmamış.', sayi: -1);
    }
    final sonYedek = liste.first.tarih; // yedekListesi tarihe göre azalan sıralı
    final gecenGun = DateTime.now().difference(sonYedek).inDays;
    return k.sonuc(
        _kademe(gecenGun <= 3 ? 0 : gecenGun, sariEnFazla: 14),
        'Son yedek $gecenGun gün önce alındı.',
        sayi: gecenGun);
  }
}
