// lib/servisler/veri_sagligi_servisi.dart
//
// VERİ SAĞLIĞI MERKEZİ (protokol §13) — uygulamanın kritik veri
// bütünlüğü göstergelerini TEK bir yerde toplar. Her kontrol salt
// okunur bir SAYIM yapar (durum: yeşil/sarı/kırmızı); bazı kontroller
// için, bu oturumda zaten var olan/eklenen kanıtlanmış "mutabakat"
// fonksiyonlarını (StokDeposu, CariDeposu, KasaDeposu, BankaHesapDeposu)
// çağıran bir DÜZELT aksiyonu da sunulur.
//
// Kasıtlı olarak yapmadığımız şey: hiçbir kontrol otomatik olarak
// (kullanıcı onayı olmadan) veri değiştirmez — ekran her zaman önce
// SAYIYI gösterir, düzeltme ayrı bir buton/onaydır.
import 'package:sqflite/sqflite.dart';
import '../depolar/banka_hesap_deposu.dart';
import '../depolar/cari_deposu.dart';
import '../depolar/kasa_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../depolar/sync_cakisma_deposu.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/yedekleme_servisi.dart';
import '../veri/database/veritabani.dart';

enum SaglikDurum { yesil, sari, kirmizi }

class SaglikKontrolSonucu {
  final String id;
  final String baslik;
  final String kategori;
  final SaglikDurum durum;
  final String mesaj;
  final int sayi;
  /// null ise otomatik düzeltme yok (ör. manuel inceleme gerekir).
  final Future<int> Function()? duzelt;

  const SaglikKontrolSonucu({
    required this.id,
    required this.baslik,
    required this.kategori,
    required this.durum,
    required this.mesaj,
    required this.sayi,
    this.duzelt,
  });

  SaglikKontrolSonucu kopyala({SaglikDurum? durum, String? mesaj, int? sayi}) =>
      SaglikKontrolSonucu(
        id: id, baslik: baslik, kategori: kategori,
        durum: durum ?? this.durum, mesaj: mesaj ?? this.mesaj,
        sayi: sayi ?? this.sayi, duzelt: duzelt,
      );
}

class VeriSagligiServisi {
  Future<Database> get _db async => Veritabani().db;

  Future<List<SaglikKontrolSonucu>> tumKontrolleriCalistir() async {
    final sonuclar = await Future.wait([
      _sqliteButunluk(),
      _foreignKeyKontrol(),
      _cariMutabakat(),
      _stokMutabakat(),
      _kasaMutabakat(),
      _bankaMutabakat(),
      _satisKasaTutarliligi(),
      _satisStokTutarliligi(),
      _duplicateBarkod(),
      _yetimKayitlar(),
      _negatifStok(),
      _syncKuyrugu(),
      _syncCakismalari(),
      _yedeklemeDurumu(),
    ]);
    return sonuclar;
  }

  // ── SQLite bütünlüğü ────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _sqliteButunluk() async {
    const id = 'sqlite';
    const baslik = 'SQLite Bütünlüğü';
    const kategori = 'Veritabanı';
    try {
      final db = await _db;
      final rows = await db.rawQuery('PRAGMA integrity_check');
      final sonuc = rows.isNotEmpty ? rows.first.values.first.toString() : 'unknown';
      if (sonuc == 'ok') {
        return const SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
            durum: SaglikDurum.yesil, mesaj: 'Veritabanı dosyası sağlam.', sayi: 0);
      }
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.kirmizi, mesaj: 'SQLite bütünlük hatası: $sonuc', sayi: 1);
    } catch (e) {
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.kirmizi, mesaj: 'Kontrol edilemedi: $e', sayi: -1);
    }
  }

  // ── Foreign Key ─────────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _foreignKeyKontrol() async {
    const id = 'fk';
    const baslik = 'Foreign Key Bütünlüğü';
    const kategori = 'Veritabanı';
    try {
      final db = await _db;
      final rows = await db.rawQuery('PRAGMA foreign_key_check');
      if (rows.isEmpty) {
        return const SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
            durum: SaglikDurum.yesil, mesaj: 'İlişkisel bütünlük ihlali yok.', sayi: 0);
      }
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.kirmizi, mesaj: '${rows.length} foreign key ihlali bulundu.', sayi: rows.length);
    } catch (e) {
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1);
    }
  }

  // ── Cari Mutabakat ──────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _cariMutabakat() async {
    final sayi = await CariDeposu().bakiyeUyumsuzlukSayisi();
    return SaglikKontrolSonucu(
      id: 'cari_mutabakat', baslik: 'Cari Mutabakat', kategori: 'Mutabakat',
      durum: sayi == 0 ? SaglikDurum.yesil : (sayi <= 3 ? SaglikDurum.sari : SaglikDurum.kirmizi),
      mesaj: sayi == 0 ? 'Tüm cari bakiyeleri hareket geçmişiyle uyumlu.'
          : '$sayi carinin bakiyesi hareket geçmişiyle uyuşmuyor.',
      sayi: sayi,
      duzelt: sayi > 0 ? () => CariDeposu().bakiyeMutabakatYap() : null,
    );
  }

  // ── Stok Mutabakat ──────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _stokMutabakat() async {
    final sayi = await StokDeposu().mutabakatUyumsuzlukSayisi();
    return SaglikKontrolSonucu(
      id: 'stok_mutabakat', baslik: 'Stok Mutabakat', kategori: 'Mutabakat',
      durum: sayi == 0 ? SaglikDurum.yesil : (sayi <= 3 ? SaglikDurum.sari : SaglikDurum.kirmizi),
      mesaj: sayi == 0 ? 'Tüm ürün stokları hareket geçmişiyle uyumlu.'
          : '$sayi ürünün stoğu hareket geçmişiyle uyuşmuyor.',
      sayi: sayi,
      duzelt: sayi > 0 ? () => StokDeposu().stokMutabakatYap() : null,
    );
  }

  // ── Kasa Mutabakat ──────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _kasaMutabakat() async {
    final sayi = await KasaDeposu().bakiyeUyumsuzlukSayisi();
    return SaglikKontrolSonucu(
      id: 'kasa_mutabakat', baslik: 'Kasa Mutabakat', kategori: 'Mutabakat',
      durum: sayi == 0 ? SaglikDurum.yesil : SaglikDurum.kirmizi,
      mesaj: sayi == 0 ? 'Kasa hareketleri sırayla tutarlı.'
          : '$sayi kasa hareketinin bakiyesi hatalı hesaplanmış.',
      sayi: sayi,
      duzelt: sayi > 0 ? () => KasaDeposu().bakiyeMutabakatYap() : null,
    );
  }

  // ── Banka Mutabakat ─────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _bankaMutabakat() async {
    final sayi = await BankaHesapDeposu().bakiyeUyumsuzlukSayisi();
    return SaglikKontrolSonucu(
      id: 'banka_mutabakat', baslik: 'Banka Mutabakat', kategori: 'Mutabakat',
      durum: sayi == 0 ? SaglikDurum.yesil : SaglikDurum.kirmizi,
      mesaj: sayi == 0 ? 'Banka hesap bakiyeleri hareket geçmişiyle uyumlu.'
          : '$sayi banka hesabının bakiyesi kendi hareket geçmişiyle uyuşmuyor.',
      sayi: sayi,
      duzelt: sayi > 0 ? () => BankaHesapDeposu().bakiyeMutabakatYap() : null,
    );
  }

  // ── Satış-Kasa tutarlılığı ──────────────────────────────────────────
  Future<SaglikKontrolSonucu> _satisKasaTutarliligi() async {
    const id = 'satis_kasa';
    const baslik = 'Satış-Kasa Tutarlılığı';
    const kategori = 'Mutabakat';
    try {
      final db = await _db;
      final rows = await db.rawQuery('''
        SELECT COUNT(*) as n FROM satislar s
        WHERE s.is_deleted = 0 AND s.odeme_yontemi = 'Nakit' AND s.odenen_tutar > 0.005
          AND NOT EXISTS (
            SELECT 1 FROM kasa_hareketleri k
            WHERE k.referans_id = s.id AND k.referans_turu = 'satis' AND k.deleted_at IS NULL
          )
      ''');
      final sayi = (rows.first['n'] as int?) ?? 0;
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: sayi == 0 ? SaglikDurum.yesil : SaglikDurum.kirmizi,
          mesaj: sayi == 0 ? 'Her nakit satışın kasa karşılığı var.'
              : '$sayi nakit satışın kasa hareketi eksik.',
          sayi: sayi);
    } catch (e) {
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1);
    }
  }

  // ── Satış-Stok tutarlılığı ──────────────────────────────────────────
  Future<SaglikKontrolSonucu> _satisStokTutarliligi() async {
    const id = 'satis_stok';
    const baslik = 'Satış-Stok Tutarlılığı';
    const kategori = 'Mutabakat';
    try {
      final db = await _db;
      final rows = await db.rawQuery('''
        SELECT COUNT(*) as n FROM satis_kalem sk
        JOIN satislar s ON s.id = sk.satis_id AND s.is_deleted = 0
        WHERE NOT EXISTS (
          SELECT 1 FROM stok_hareket sh
          WHERE sh.referans_id = sk.satis_id AND sh.referans_turu = 'satis' AND sh.urun_id = sk.urun_id
        )
      ''');
      final sayi = (rows.first['n'] as int?) ?? 0;
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: sayi == 0 ? SaglikDurum.yesil : (sayi <= 5 ? SaglikDurum.sari : SaglikDurum.kirmizi),
          mesaj: sayi == 0 ? 'Her satış kalemi bir stok hareketiyle eşleşiyor.'
              : '$sayi satış kaleminin stok hareketi bulunamadı.',
          sayi: sayi);
    } catch (e) {
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1);
    }
  }

  // ── Duplicate barkod ────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _duplicateBarkod() async {
    const id = 'dup_barkod';
    const baslik = 'Mükerrer Barkod';
    const kategori = 'Ürün';
    try {
      final db = await _db;
      final rows = await db.rawQuery('''
        SELECT barkod, COUNT(*) as c FROM urunler
        WHERE barkod IS NOT NULL AND barkod != '' AND is_deleted = 0
        GROUP BY barkod HAVING c > 1
      ''');
      final sayi = rows.length;
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: sayi == 0 ? SaglikDurum.yesil : SaglikDurum.sari,
          mesaj: sayi == 0 ? 'Aynı barkodu paylaşan ürün yok.'
              : '$sayi barkod birden fazla üründe kullanılıyor.',
          sayi: sayi);
    } catch (e) {
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1);
    }
  }

  // ── Yetim kayıtlar ──────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _yetimKayitlar() async {
    const id = 'yetim';
    const baslik = 'Yetim Kayıtlar';
    const kategori = 'Veritabanı';
    try {
      final db = await _db;
      final sonuclar = await Future.wait([
        db.rawQuery("SELECT COUNT(*) as n FROM satis_kalem sk WHERE NOT EXISTS (SELECT 1 FROM satislar s WHERE s.id = sk.satis_id)"),
        db.rawQuery("SELECT COUNT(*) as n FROM cari_hareket ch WHERE NOT EXISTS (SELECT 1 FROM cari c WHERE c.id = ch.cari_id)"),
        db.rawQuery("SELECT COUNT(*) as n FROM stok_hareket sh WHERE NOT EXISTS (SELECT 1 FROM urunler u WHERE u.id = sh.urun_id)"),
      ]);
      final sayi = sonuclar.fold<int>(0, (t, r) => t + ((r.first['n'] as int?) ?? 0));
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: sayi == 0 ? SaglikDurum.yesil : SaglikDurum.sari,
          mesaj: sayi == 0 ? 'Sahipsiz (referansı silinmiş) kayıt yok.'
              : '$sayi kayıt, artık var olmayan bir ana kayda bağlı (satış/cari/ürün silinmiş olabilir).',
          sayi: sayi);
    } catch (e) {
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1);
    }
  }

  // ── Negatif stok ────────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _negatifStok() async {
    const id = 'negatif_stok';
    const baslik = 'Negatif Stok';
    const kategori = 'Ürün';
    try {
      final db = await _db;
      final rows = await db.rawQuery(
          "SELECT COUNT(*) as n FROM urunler WHERE stok < 0 AND is_deleted = 0");
      final sayi = (rows.first['n'] as int?) ?? 0;
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: sayi == 0 ? SaglikDurum.yesil : SaglikDurum.kirmizi,
          mesaj: sayi == 0 ? 'Negatif stoklu ürün yok.' : '$sayi ürünün stoğu negatif.',
          sayi: sayi);
    } catch (e) {
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1);
    }
  }

  // ── Sync kuyruğu (BulutManager'ın CANLI bekleyen listesi) ───────────
  Future<SaglikKontrolSonucu> _syncKuyrugu() async {
    const id = 'sync_kuyruk';
    const baslik = 'Sync Kuyruğu';
    const kategori = 'Senkronizasyon';
    try {
      final sayi = BulutManager().bekleyenSayisi;
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: sayi == 0 ? SaglikDurum.yesil : (sayi <= 20 ? SaglikDurum.sari : SaglikDurum.kirmizi),
          mesaj: sayi == 0 ? 'Gönderilmeyi bekleyen değişiklik yok.'
              : '$sayi değişiklik henüz buluta gönderilmedi.',
          sayi: sayi);
    } catch (e) {
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1);
    }
  }

  // ── Sync çakışmaları (protokol §12) ─────────────────────────────────
  Future<SaglikKontrolSonucu> _syncCakismalari() async {
    final sayi = await SyncCakismaDeposu().cozulmemisSayisi();
    return SaglikKontrolSonucu(
      id: 'sync_cakisma', baslik: 'Sync Çakışmaları', kategori: 'Senkronizasyon',
      durum: sayi == 0 ? SaglikDurum.yesil : SaglikDurum.sari,
      mesaj: sayi == 0 ? 'Çözülmemiş senkron çakışması yok.'
          : '$sayi çözülmemiş senkron çakışması var.',
      sayi: sayi,
    );
  }

  // ── Yedekleme durumu ────────────────────────────────────────────────
  Future<SaglikKontrolSonucu> _yedeklemeDurumu() async {
    const id = 'yedekleme';
    const baslik = 'Yedekleme';
    const kategori = 'Sistem';
    try {
      final liste = await YedeklemeServisi().yedekListesi();
      if (liste.isEmpty) {
        return const SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
            durum: SaglikDurum.kirmizi, mesaj: 'Hiç yedek alınmamış.', sayi: -1);
      }
      final sonYedek = liste.first.tarih; // yedekListesi tarihe göre azalan sıralı
      final gecenGun = DateTime.now().difference(sonYedek).inDays;
      final durum = gecenGun <= 3
          ? SaglikDurum.yesil
          : (gecenGun <= 14 ? SaglikDurum.sari : SaglikDurum.kirmizi);
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: durum, mesaj: 'Son yedek $gecenGun gün önce alındı.', sayi: gecenGun);
    } catch (e) {
      return SaglikKontrolSonucu(id: id, baslik: baslik, kategori: kategori,
          durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1);
    }
  }
}
