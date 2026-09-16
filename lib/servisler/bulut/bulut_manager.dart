// lib/servisler/bulut/bulut_manager.dart
// ─────────────────────────────────────────────────────────────────────────────
// Merkezi bulut yöneticisi — singleton, provider-agnostic.
// İşlem yapıldığında otomatik kuyruk, retry, batch gönderimi.
//
// 🔴🔴🔴 MASTER ERP DEEP AUDIT — Madde 5 SERTLEŞTİRMESİ: bu sınıf
// ÖNCEDEN kuyruğu SADECE RAM'de (`final _kuyruk = <_SyncKayit>[];`)
// tutuyordu — uygulama çökerse veya öldürülürse, henüz Supabase'e
// gönderilmemiş TÜM bekleyen kayıtlar KALICI OLARAK kayboluyordu (satış/
// stok/kasa/cari verisi SQLite'ta güvendeydi, ama senkron sinyali bir
// daha asla üretilmiyordu). Artık kuyruk tamamen `sync_queue` SQLite
// tablosunda tutuluyor — tek doğruluk kaynağı bu tablo. RAM'de hiçbir
// bekleyen kayıt YAŞAMIYOR; `upsert()`/`sil()` çağrıldığı anda kuyruk
// satırı diske yazılıyor (fire-and-forget ama artık KALICI), gerçek ağ
// gönderimi ayrı bir worker turunda bu tabloyu okuyarak yapılıyor.
//
// Davranış değişikliği (bilinçli): eski kod bir kayıt 3 denemeden sonra
// SESSİZCE kuyruktan düşürüyordu (`if (denemeSayisi < 3)`) — bu, "veri
// kaybı riskini sıfıra indir" hedefiyle çelişiyordu. Artık bir kayıt
// ASLA düşürülmüyor; satır zaten diskte kalıcı olduğu için süresiz
// yeniden deneniyor, sadece deneme_sayisi/hata_mesaji görünürlük için
// güncelleniyor.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'bulut_saglayici.dart';
import 'supabase_saglayici.dart';
import 'supabase_ayarlari.dart';
import 'sync_kuyruk_yazici.dart';
import '../kolon_haritalama.dart';
import '../../cekirdek/sabitler/db_sabitleri.dart';
import '../../veri/database/veritabani.dart';
import '../audit_log_servisi.dart';

// ── Bulut durum ───────────────────────────────────────────────────────────────
enum BulutDurum {
  bagli_degil,
  yapilandirilmamis,
  baglaniyor,
  bagli,
  bekliyor,
  gonderiliyor,
  hata;

  String get metin => switch (this) {
    bagli_degil           => 'Bulut bağlı değil',
    yapilandirilmamis     => 'Bulut yapılandırılmamış',
    baglaniyor            => 'Bağlanıyor…',
    bagli                 => 'Bulut bağlı ✓',
    bekliyor              => '${BulutManager._instance?._bekleyenSayisiCache ?? 0} kayıt bekliyor',
    gonderiliyor          => 'Senkronize ediliyor…',
    hata                  => 'Bağlantı hatası',
  };
  bool get aktif => this == bagli || this == bekliyor || this == gonderiliyor;
  bool get sorun => this == hata || this == bagli_degil;
}

// ── BulutManager ──────────────────────────────────────────────────────────────
class BulutManager {
  static BulutManager? _instance;
  factory BulutManager() => _instance ??= BulutManager._();
  BulutManager._();

  IBulutSaglayici? _saglayici;
  Timer? _timer;
  bool _gonderiliyor = false;
  int _bekleyenSayisiCache = 0;

  final durum    = ValueNotifier<BulutDurum>(BulutDurum.bagli_degil);
  final istatistik = ValueNotifier<_Istatistik>(const _Istatistik());

  IBulutSaglayici? get mevcutSaglayici => _saglayici;
  int get bekleyenSayisi => _bekleyenSayisiCache;

  // ── Başlat ─────────────────────────────────────────────────────────────────
  Future<void> baslat() async {
    final p = await SharedPreferences.getInstance();
    final tip = p.getString('mp_bulut_tip') ?? 'supabase';

    if (tip == 'supabase') {
      // 🔴 KRİTİK MANTIK DÜZELTMESİ: Önceden SADECE 'mp_supa_url' /
      // 'mp_supa_key' okunuyordu — ama o anahtarları yazan fonksiyon
      // (SupabaseSaglayici.ayarlariKaydet) uygulamanın HİÇBİR yerinden
      // çağrılmıyordu! Ayarlar ekranı bağlantı bilgilerini
      // SupabaseAyarlari üzerinden (artık güvenli depoda) kaydediyor.
      // Sonuç önceden: baslat() her açılışta boş değer bulup
      // "yapılandırılmamış" durumuna düşüyordu → OTOMATİK (kuyruk)
      // SENKRON HİÇ ÇALIŞMIYORDU. SupabaseAyarlari eski düz metin
      // anahtarları da (varsa) otomatik geriye dönük taşır.
      final url = await SupabaseAyarlari.urlOku() ?? '';
      final key = await SupabaseAyarlari.keyOku() ?? '';
      if (url.isNotEmpty && key.isNotEmpty) {
        await saglayiciAyarla(SupabaseSaglayici(url: url, key: key));
        return;
      }
    }
    durum.value = BulutDurum.yapilandirilmamis;
  }

  // ── Sağlayıcı değiştir ─────────────────────────────────────────────────────
  Future<BaglantiSonuc> saglayiciAyarla(IBulutSaglayici s) async {
    _saglayici = s;
    durum.value = BulutDurum.baglaniyor;
    final sonuc = await s.baglantiTest();
    durum.value = sonuc.basarili ? BulutDurum.bagli : BulutDurum.hata;
    if (sonuc.basarili) {
      _workerBaslat();
      // 🔴 KURTARMA: bağlantı kurulduğu anda, önceki bir çökme/kapanmadan
      // KALMIŞ olabilecek bekleyen kuyruk satırlarını hemen işlemeye
      // başla — 8 saniyelik periyodik timer'ı beklemeden.
      unawaited(_isle());
    }
    return sonuc;
  }

  // ── Kuyruğa ekle ───────────────────────────────────────────────────────────
  void upsert(String tablo, Map<String,dynamic> ham) {
    // Kullanıcı isteği: "audit sistemi — kim ne yaptı ne zaman."
    // BulutManager.upsert() artık projedeki NEREDEYSE TÜM anlamlı veri
    // değişikliğinin geçtiği merkezi nokta — audit log'u buraya
    // kancalıyoruz. Bulut yapılandırılmamış olsa bile (aşağıdaki
    // _saglayici==null kontrolünden ÖNCE) audit log çalışsın diye en
    // başa konuldu — audit, tamamen YEREL bir özellik olarak da
    // değerli.
    AuditLogServisi().kaydet(tablo, ham);

    if (_saglayici == null) return;
    final veri = Map<String, dynamic>.from(ham);

    // 🔴 ÇOĞALMA SIZINTISI DÜZELTMESİ: Bazı kayıtlar (stok_hareket vb.)
    // lokalde global_id'siz oluşturuluyor. Kimliksiz kayda burada kalıcı
    // bir kimlik üretilip LOKALE yazılıyor, kuyruğa kimlikli hali
    // giriyor — iki yol da hep AYNI kimliği kullanır, on_conflict
    // eşleşir, çoğalma biter. (Kolon adı dönüşümü — KolonHaritalama.cevir
    // — artık push anında, BulutManager._veriCoz() içinde yapılıyor;
    // burada SADECE yerel/ham satır üzerinde çalışıyoruz.)
    final gid = veri['global_id']?.toString();
    if ((gid == null || gid.isEmpty) && veri['id'] != null) {
      final yeniGid = const Uuid().v4();
      veri['global_id'] = yeniGid;
      // Lokale kalıcı yaz (beklemeden, arka planda — kuyruk akışını
      // yavaşlatmasın; yazım bitmeden uygulama kapanırsa bir sonraki
      // manuel senkronun backfill'i zaten tamamlar).
      Veritabani().db.then((db) => db.update(
            tablo, {'global_id': yeniGid},
            where: 'id = ?', whereArgs: [veri['id']],
          )).catchError((_) => 0);
    }

    unawaited(_kuyrukaYaz(tablo, 'UPSERT', veri));
  }

  void sil(String tablo, String globalId) {
    if (_saglayici == null) return;
    unawaited(_kuyrukaYaz(tablo, 'DELETE', {'global_id': globalId}));
  }

  /// Genel (fire-and-forget) giriş noktası — [upsert]/[sil] tarafından
  /// kullanılır. Kendi kısa transaction'ını açar (çağıranın business-data
  /// transaction'ı ZATEN commit olmuş durumda — bkz. tüm çağrı
  /// noktalarındaki "transaction kapandıktan sonra bildir" yorumları).
  /// Satış/İade/hareket depolarındaki TAM ATOMİK yol için bkz.
  /// [SyncKuyrukYazici.ekleTxn] — o, business-data transaction'ının
  /// TAM İÇİNDE çağrılır, burası değil.
  Future<void> _kuyrukaYaz(
      String tablo, String islem, Map<String, dynamic> veri) async {
    try {
      final db = await Veritabani().db;
      await db.transaction((txn) async {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: tablo, veri: veri, islemTipi: islem);
      });
      _bekleyenSayisiCache++;
      if (durum.value != BulutDurum.gonderiliyor) {
        durum.value = BulutDurum.bekliyor;
      }
      _workerTetikle();
    } catch (e) {
      if (kDebugMode) debugPrint('BulutManager._kuyrukaYaz hatası ($tablo): $e');
    }
  }

  // ── Worker ─────────────────────────────────────────────────────────────────
  void _workerBaslat() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _isle());
  }

  void _workerTetikle() {
    if (!_gonderiliyor) {
      Future.delayed(const Duration(milliseconds: 800), _isle);
    }
  }

  /// Yerel satırı (sync_queue.veri_json) Supabase'e gönderilecek hale
  /// çevirir — kolon adı dönüşümü (KolonHaritalama.cevir) ve tabloya
  /// özel temizlikler TEK burada uygulanır (hem [upsert] hem
  /// [SyncKuyrukYazici.ekleTxn] ile txn-içi yazılan satırlar için AYNI
  /// merkezi nokta — push anına kadar ertelenir ki dönüşüm mantığı iki
  /// yerde tekrarlanmasın).
  Map<String, dynamic> _veriCoz(String tablo, Map<String, dynamic> kuyrukSatiri) {
    final hamJson = jsonDecode(kuyrukSatiri['veri_json'] as String);
    final ham = Map<String, dynamic>.from(hamJson as Map);
    final veri = KolonHaritalama.cevir(tablo, ham);

    // 🔴🔴🔴 KAPSAMLI DERİN ANALİZ: eski, yerini yeni isimli bir sütunun
    // aldığı ama hiç silinmemiş sütunlar buluta gitmemeli — aksi hâlde
    // PostgREST bu tabloların TÜM gönderimini reddeder.
    if (tablo == 'faturalar') {
      veri.remove('efatura_uuid');
      veri.remove('efatura_durum');
      veri.remove('efatura_tipi');
    }
    if (tablo == 'personel') {
      veri.remove('ise_baslama_tarihi');
    }
    // 🔴🔴 KRİTİK, SON HAT DÜZELTMESİ (kullanıcı bulgusu — AYNI Supabase
    // hatası tekrar tekrar geldi: "kredi_kartlari NOT NULL ihlali,
    // kart_no_maskeli"): bu alan ASLA null/boş olarak buluta
    // gönderilemez; kaynağı ne olursa olsun burada düzeltilir.
    if (tablo == 'kredi_kartlari') {
      final knm = veri['kart_no_maskeli'];
      if (knm == null || (knm is String && knm.isEmpty)) {
        veri['kart_no_maskeli'] = '**** **** **** ????';
        if (ham['id'] != null) {
          Veritabani().db.then((db) => db.update(
                'kredi_kartlari', {'kart_no_maskeli': '**** **** **** ????'},
                where: 'id = ?', whereArgs: [ham['id']],
              )).catchError((_) => 0);
        }
      }
    }
    return veri;
  }

  Future<void> _kuyrukSatiriBasarisizIsaretle(
      Database db, int id, Object hata, String zaman) async {
    try {
      await db.rawUpdate(
        'UPDATE ${DbSabitler.syncQueue} SET deneme_sayisi = deneme_sayisi + 1, '
        'son_deneme = ?, hata_mesaji = ? WHERE id = ?',
        [zaman, hata.toString(), id],
      );
    } catch (_) {
      // best-effort — görünürlük içindir, ana akışı bloklamamalı
    }
  }

  Future<void> _bekleyenSayisiniYenile(Database db) async {
    try {
      final r = await db.rawQuery(
          "SELECT COUNT(*) as c FROM ${DbSabitler.syncQueue} WHERE durum = 'beklemede'");
      _bekleyenSayisiCache = (r.first['c'] as int?) ?? 0;
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _isle() async {
    if (_gonderiliyor || _saglayici == null) return;
    _gonderiliyor = true;
    durum.value = BulutDurum.gonderiliyor;

    int toplamBasarili = 0, toplamHata = 0;
    final tumHatalar = <String>[];
    final db = await Veritabani().db;

    try {
      // Kalıcı kuyruktan bekleyen satırları oku — RAM'de HİÇBİR ŞEY
      // tutulmuyor, tek doğruluk kaynağı bu sorgu. Tek turda en fazla
      // 500 satır işlenir (bellek/performans için); kalan varsa turun
      // sonunda hemen yeni bir tur tetiklenir.
      final bekleyenSatirlar = await db.query(
        DbSabitler.syncQueue,
        where: 'durum = ?',
        whereArgs: ['beklemede'],
        orderBy: 'id ASC',
        limit: 500,
      );

      if (bekleyenSatirlar.isEmpty) {
        _bekleyenSayisiCache = 0;
        return;
      }

      final gruplar = <String, List<Map<String, dynamic>>>{};
      for (final satir in bekleyenSatirlar) {
        gruplar.putIfAbsent(satir['tablo_adi'] as String, () => []).add(satir);
      }

      final now = DateTime.now().toIso8601String();

      for (final entry in gruplar.entries) {
        final tablo = entry.key;
        final satirlar = entry.value;
        final uniqueAlan = KolonHaritalama.uniqueAlan(tablo) ?? 'id';

        // DELETE işlemleri
        final silinenler =
            satirlar.where((s) => s['islem_tipi'] == 'DELETE').toList();
        for (final s in silinenler) {
          final veri = _veriCoz(tablo, s);
          try {
            await _saglayici!.sil(
              tablo: tablo,
              uniqueAlan: uniqueAlan,
              deger: veri['global_id']?.toString() ?? '',
            );
            await db.delete(DbSabitler.syncQueue,
                where: 'id = ?', whereArgs: [s['id']]);
            toplamBasarili++;
          } catch (e) {
            toplamHata++;
            tumHatalar.add('❌ $tablo DELETE: $e');
            await _kuyrukSatiriBasarisizIsaretle(db, s['id'] as int, e, now);
          }
        }

        // UPSERT işlemleri — batch
        final upsertSatirlari =
            satirlar.where((s) => s['islem_tipi'] == 'UPSERT').toList();
        if (upsertSatirlari.isNotEmpty) {
          final upsertler =
              upsertSatirlari.map((s) => _veriCoz(tablo, s)).toList();
          try {
            final sonuc = await _saglayici!.topluUpsert(
              tablo: tablo,
              veriler: upsertler,
              uniqueAlan: uniqueAlan,
            );
            toplamBasarili += sonuc.basarili;
            toplamHata += sonuc.hata;
            tumHatalar.addAll(sonuc.hataMesajlari);

            // 🔴 DÜZELTME (eski RAM kuyruğunda bulunan gizli veri kaybı):
            // topluUpsert satır-bazlı başarı/hata döndürmüyor (sadece
            // toplam sayaç) — bir satırı güvenle "gitti" sayıp
            // kuyruktan silebileceğimiz TEK durum, TÜM grubun hatasız
            // tamamlanmasıdır. Kısmi hata varsa (sonuc.hata>0) hangi
            // satırın gerçekten gittiği bilinemez — veri kaybetmemek
            // için TÜMÜ kuyrukta bırakılır (upsert idempotent olduğu
            // için yeniden denemek güvenlidir, mükerrer satır oluşmaz).
            if (sonuc.tamam) {
              final idler = upsertSatirlari.map((s) => s['id'] as int).toList();
              final ph = idler.map((_) => '?').join(',');
              await db.delete(DbSabitler.syncQueue,
                  where: 'id IN ($ph)', whereArgs: idler);
            } else {
              for (final s in upsertSatirlari) {
                await _kuyrukSatiriBasarisizIsaretle(
                    db, s['id'] as int, 'toplu upsert kısmi hata', now);
              }
            }
          } catch (e) {
            toplamHata += upsertler.length;
            tumHatalar.add('❌ $tablo toplu upsert: $e');
            for (final s in upsertSatirlari) {
              await _kuyrukSatiriBasarisizIsaretle(db, s['id'] as int, e, now);
            }
          }
        }
      }
    } finally {
      _gonderiliyor = false;
    }

    // İstatistik güncelle
    final mevcut = istatistik.value;
    istatistik.value = _Istatistik(
      toplamGonderilen: mevcut.toplamGonderilen + toplamBasarili,
      toplamHata:       mevcut.toplamHata + toplamHata,
      sonHatalar:       tumHatalar.take(20).toList(),
      sonGonderim:      DateTime.now(),
    );

    await _bekleyenSayisiniYenile(db);
    durum.value = _bekleyenSayisiCache == 0
        ? (toplamHata > 0 ? BulutDurum.hata : BulutDurum.bagli)
        : BulutDurum.bekliyor;

    if (kDebugMode && toplamBasarili > 0) {
      debugPrint('BulutManager: ✅$toplamBasarili ❌$toplamHata bekleyen:$_bekleyenSayisiCache');
    }

    // Kuyrukta hâlâ satır varsa (bu turda 500 limitine çarpıldıysa ya da
    // hatalar nedeniyle kalan varsa) hemen bir tur daha dene.
    if (_bekleyenSayisiCache > 0) _workerTetikle();
  }

  // ── Zorla gönder ───────────────────────────────────────────────────────────
  Future<void> zorlaGonder() async => _isle();

  // ── Temizlik ───────────────────────────────────────────────────────────────
  void dispose() { _timer?.cancel(); durum.dispose(); istatistik.dispose(); }
}

class _Istatistik {
  final int toplamGonderilen;
  final int toplamHata;
  final List<String> sonHatalar;
  final DateTime? sonGonderim;

  const _Istatistik({
    this.toplamGonderilen = 0,
    this.toplamHata = 0,
    this.sonHatalar = const [],
    this.sonGonderim,
  });
}
