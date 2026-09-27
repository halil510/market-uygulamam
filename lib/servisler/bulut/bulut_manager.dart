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
import 'sync_backoff.dart';
import '../kolon_haritalama.dart';
import '../../cekirdek/sabitler/db_sabitleri.dart';
import '../../veri/database/veritabani.dart';
import '../audit_log_servisi.dart';
import '../log_servisi.dart';
import '../fatura_seri/terminal_servisi.dart';

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
      await _kaliciHatalariKuyrugaGeriAl(otomatik: true);
      // Kasa bazlı fiş numarası için bu cihazın Terminal kaydı olsun
      // (bkz. Veritabani.fisNoUret) — ilk bağlantıda bir kez, arka planda.
      if (s is SupabaseSaglayici) {
        unawaited(TerminalServisi().terminalGarantiEt().then((_) {}, onError: (Object e) {
          LogServisi().uyari('Terminal kaydı yapılamadı (fiş no eski biçimde devam eder)', hata: e);
        }));
      }
      _workerBaslat();
      // 🔴 KURTARMA: bağlantı kurulduğu anda, önceki bir çökme/kapanmadan
      // KALMIŞ olabilecek bekleyen kuyruk satırlarını hemen işlemeye
      // başla — 8 saniyelik periyodik timer'ı beklemeden.
      unawaited(_isle());
    }
    return sonuc;
  }

  // ── Kuyruğa ekle ───────────────────────────────────────────────────────────
  /// [eskiVeri] SADECE audit log zenginleştirmesi için — ör. fiyat
  /// değişikliğinde eski değeri de kaydedebilmek (Madde 18/14 denetimi,
  /// 2026-09-16). Opsiyonel — çağıranların ÇOĞU bunu hiç vermez, geriye
  /// dönük uyumlu.
  void upsert(String tablo, Map<String,dynamic> ham, {Map<String, dynamic>? eskiVeri}) {
    // Kullanıcı isteği: "audit sistemi — kim ne yaptı ne zaman."
    // BulutManager.upsert() artık projedeki NEREDEYSE TÜM anlamlı veri
    // değişikliğinin geçtiği merkezi nokta — audit log'u buraya
    // kancalıyoruz. Bulut yapılandırılmamış olsa bile (aşağıdaki
    // _saglayici==null kontrolünden ÖNCE) audit log çalışsın diye en
    // başa konuldu — audit, tamamen YEREL bir özellik olarak da
    // değerli.
    AuditLogServisi().kaydet(tablo, ham, eskiVeri: eskiVeri);

    if (_saglayici == null) return;
    unawaited(_kimlikliKuyrugaYaz(tablo, Map<String, dynamic>.from(ham)));
  }

  /// [upsert]'ün asenkron gövdesi: satırın kalıcı kimliğini (global_id)
  /// garanti eder, sonra kuyruğa yazar.
  ///
  /// 🔴🔴 KÖK NEDEN DÜZELTMESİ (2026-09-27 — "sync çakışması" /
  /// hayalet -SYNC satış): ÖNCEDEN global_id'siz gelen her satıra
  /// KOŞULSUZ yeni bir UUID üretilip yereldeki kayda YAZILIYORDU. Ama
  /// çağıranların bir kısmı satırı DB'den değil bellekteki modelden
  /// kuruyordu (`{...satis.toMap(), 'id': satisId, 'global_id':
  /// satis.globalId}` — globalId hep null). Oysa satış, satisEkleTxn
  /// içinde ZATEN bir global_id (G1) ile yazılmış ve G1 kuyruğa
  /// girmişti. Sonuç: her satış buluta İKİ KEZ gidiyordu (G1 ve yeni
  /// G2), yerel kaydın kimliği G2'ye çevriliyordu; bir sonraki
  /// "Buluttan Al"da G1 aynı fiş no ile geri inip "-SYNC" kopyası
  /// oluyordu. Artık önce yereldeki GERÇEK global_id okunuyor; yalnızca
  /// kayıtta gerçekten yoksa yeni kimlik üretiliyor.
  Future<void> _kimlikliKuyrugaYaz(String tablo, Map<String, dynamic> veri) async {
    final gid = veri['global_id']?.toString();
    // Doğal anahtarla eşleşen tablolar (subeler→sube_kodu, kullanicilar→
    // kullanici_adi, fis_seri…) global_id'ye dayanmaz — olduğu gibi git.
    final globalIdTablosu =
        (KolonHaritalama.uniqueAlan(tablo) ?? 'global_id') == 'global_id';
    // 🔴 DÜZELTME (2026-09-28, bulut kontrolü: yeni kullanıcı 'ahmet'
    // global_id'siz gitmişti): doğal anahtarlı tablolar (kullanicilar,
    // subeler, kategoriler…) da global_id sütunu taşıyor ve diğer tabloların
    // FK dönüşümü onları global_id ile arıyor. Yerel id'si olan satırda
    // kimlik bu tablolarda da çözülür/üretilir; yalnızca global_id sütunu
    // hiç olmayan tabloda (okuma hatası) dokunulmaz.
    final kimlikCozulmeli = globalIdTablosu || veri['id'] != null;
    if (kimlikCozulmeli && (gid == null || gid.isEmpty)) {
      final id = veri['id'];
      if (id == null) {
        // Ne yerel id ne global_id: bu satır bulutta HİÇBİR ZAMAN
        // eşleşemez (on_conflict=global_id NULL ile her gönderimde yeni
        // satır açar) — ör. eskiden satış kalemleri bellekteki modelden
        // satis_id=0 ve kimliksiz gönderiliyordu. Göndermek yerine
        // kaydedip reddediyoruz.
        LogServisi().hata(
            'BulutManager.upsert($tablo): kimliksiz satır (id ve global_id yok) buluta gönderilmedi',
            ek: veri.keys.join(','));
        return;
      }
      try {
        final db = await Veritabani().db;
        final r = await db.query(tablo,
            columns: ['global_id'], where: 'id = ?', whereArgs: [id], limit: 1);
        final yerelGid = r.isNotEmpty ? r.first['global_id']?.toString() : null;
        if (yerelGid != null && yerelGid.isNotEmpty) {
          veri['global_id'] = yerelGid;
        } else {
          // Kayıt gerçekten kimliksiz (ör. eski stok_hareket satırları):
          // kalıcı kimlik üretip LOKALE yaz — hep aynı kimlikle gider.
          final yeniGid = const Uuid().v4();
          veri['global_id'] = yeniGid;
          await db.update(tablo, {'global_id': yeniGid},
              where: 'id = ? AND (global_id IS NULL OR global_id = \'\')',
              whereArgs: [id]);
        }
      } catch (e, st) {
        // Okuma başarısız: global_id eşleşmeli tabloda bu gönderim için
        // kimlik üret; doğal anahtarlı tabloda sütun hiç olmayabilir —
        // eklemek PGRST204'e yol açar, dokunma.
        if (globalIdTablosu) {
          LogServisi().uyari('BulutManager.upsert($tablo) kimlik çözümü', hata: e, yigin: st);
          veri['global_id'] ??= const Uuid().v4();
        }
      }
    }
    await _kuyrukaYaz(tablo, 'UPSERT', veri);
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
    } catch (e, st) {
      // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 8): bu hata ÖNCEDEN sadece
      // kDebugMode'da debugPrint ile yazılıyordu — release build'de
      // sync kuyruğuna yazım sessizce başarısız olabiliyor, hiçbir
      // yerde iz bırakmıyordu (kullanıcı "senkron olmuyor" derse teşhis
      // imkansızdı). Artık LogServisi'ne (release'de de kalıcı) düşüyor.
      if (kDebugMode) debugPrint('BulutManager._kuyrukaYaz hatası ($tablo): $e');
      LogServisi().hata('BulutManager._kuyrukaYaz($tablo)', hata: e, yigin: st);
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

    // Yalnızca yerelde olan / eski adıyla kalmış sütunlar buluta gitmemeli —
    // aksi hâlde PostgREST tablonun TÜM gönderimini reddeder (PGRST204).
    // Tek liste: KolonHaritalama.yereleOzguSutunlar (manuel yol da kullanır).
    KolonHaritalama.yereleOzguSutunlariAyikla(tablo, veri);
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

  // ── Madde 5 sertleştirmesi: exponential backoff + hata sınıflandırması ──
  // Saf hesaplama mantığı (test edilebilirlik için) sync_backoff.dart'ta
  // — bkz. backoffSuresiSaniyeHesapla/syncSatiriSimdiDenenebilirMi.

  /// Bir kuyruk satırını başarısız olarak işaretler. [tur] == kalici ise
  /// (validation/auth — 4xx) durum 'kalici_hata'ya çevrilir: bu satır
  /// `WHERE durum='beklemede'` sorgusundan bir daha HİÇ dönmez, yani
  /// otomatik olarak süresiz yeniden denenip kuyruğu (ve gerçek ağ
  /// hatalarının önünü) tıkamaz — ama satır SİLİNMEZ, kalıcı olarak
  /// diskte durur (veri kaybı yok, sadece insan müdahalesi bekler) ve
  /// LogServisi'ne düşer (görünürlük). Geçici (gecici — ağ/5xx) hata ise
  /// durum 'beklemede' kalır, bir sonraki backoff penceresinde tekrar
  /// denenir.
  Future<void> _kuyrukSatiriBasarisizIsaretle(
    Database db,
    int id,
    Object hata,
    String zaman, {
    BulutHataTuru tur = BulutHataTuru.gecici,
    String? tablo,
  }) async {
    try {
      if (tur == BulutHataTuru.kalici) {
        await db.rawUpdate(
          'UPDATE ${DbSabitler.syncQueue} SET deneme_sayisi = deneme_sayisi + 1, '
          "son_deneme = ?, hata_mesaji = ?, durum = 'kalici_hata' WHERE id = ?",
          [zaman, hata.toString(), id],
        );
        LogServisi().hata(
          'BulutManager: kalıcı senkron hatası (${tablo ?? "?"}, sync_queue#$id) — otomatik yeniden denenmeyecek',
          hata: hata,
          ek: 'Uygulama her açıldığında otomatik yeniden denenir (en fazla $kaliciHataOtomatikDenemeSiniri kez); ayrıca Bulut Senkronizasyon > Kalıcı Hatalar > Yeniden Dene.',
        );
      } else {
        await db.rawUpdate(
          'UPDATE ${DbSabitler.syncQueue} SET deneme_sayisi = deneme_sayisi + 1, '
          'son_deneme = ?, hata_mesaji = ? WHERE id = ?',
          [zaman, hata.toString(), id],
        );
      }
    } catch (_) {
      // best-effort — görünürlük içindir, ana akışı bloklamamalı
    }
  }

  /// 'kalici_hata' satırları için GENEL kurtarma (2026-09-23). Önceden bu
  /// satırlar bir daha HİÇ denenmiyordu — kod/şema/anahtar düzeltilse bile
  /// (ör. sync_cakisma_kopyasi PGRST204 olayı, yanlış anahtar 401'i)
  /// her seferinde özel bir onarım UPDATE'i yazmak gerekiyordu.
  ///
  /// [otomatik]: bağlantı her kurulduğunda (uygulama açılışı, anahtar
  /// kaydı) çağrılır; yalnızca [kaliciHataOtomatikDenemeSiniri]'nin altındaki
  /// satırları geri alır ve deneme sayısını KORUR (backoff geçerli kalır) —
  /// gerçekten bozuk bir satır sınırsız yeniden denenmez. Elle çağrıda
  /// (Bulut Senkronizasyon ekranı) tümü sıfırdan denenir.
  Future<int> _kaliciHatalariKuyrugaGeriAl({required bool otomatik}) async {
    try {
      final db = await Veritabani().db;
      final adet = otomatik
          ? await db.rawUpdate(
              "UPDATE ${DbSabitler.syncQueue} SET durum = 'beklemede' "
              "WHERE durum = 'kalici_hata' AND deneme_sayisi < ?",
              [kaliciHataOtomatikDenemeSiniri])
          : await db.rawUpdate(
              "UPDATE ${DbSabitler.syncQueue} SET durum = 'beklemede', deneme_sayisi = 0 "
              "WHERE durum = 'kalici_hata'");
      if (adet > 0) {
        LogServisi().bilgi(
            'BulutManager: $adet kalıcı-hatalı senkron satırı yeniden kuyruğa alındı'
            '${otomatik ? ' (otomatik)' : ' (elle)'}');
        await _bekleyenSayisiniYenile(db);
      }
      return adet;
    } catch (_) {
      return 0; // best-effort — bağlantı akışını bloklamamalı
    }
  }

  /// Bulut Senkronizasyon ekranı için: kalıcı hatalı satırların tablo
  /// bazında özeti (adet + örnek hata mesajı).
  Future<List<({String tablo, int adet, String? ornekHata})>> kaliciHataOzeti() async {
    final db = await Veritabani().db;
    final rows = await db.rawQuery(
        'SELECT tablo_adi, COUNT(*) AS adet, MAX(hata_mesaji) AS ornek '
        "FROM ${DbSabitler.syncQueue} WHERE durum = 'kalici_hata' "
        'GROUP BY tablo_adi ORDER BY adet DESC');
    return rows
        .map((r) => (
              tablo: r['tablo_adi']?.toString() ?? '?',
              adet: (r['adet'] as int?) ?? 0,
              ornekHata: r['ornek']?.toString(),
            ))
        .toList();
  }

  /// Tüm kalıcı hatalı satırları deneme sayısı sıfırlanarak yeniden
  /// kuyruğa alır ve hemen bir gönderim turu başlatır. Geri alınan satır
  /// sayısını döner.
  @visibleForTesting
  Future<int> kaliciHatalariOtomatikGeriAl() => _kaliciHatalariKuyrugaGeriAl(otomatik: true);

  Future<int> kaliciHatalariYenidenDene() async {
    final adet = await _kaliciHatalariKuyrugaGeriAl(otomatik: false);
    if (adet > 0) unawaited(_isle());
    return adet;
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

    int toplamBasarili = 0, toplamHata = 0;
    var isYapildiMi = false;
    final tumHatalar = <String>[];
    final db = await Veritabani().db;

    try {
      // 🔴 KENDİ KENDİNİ ONARAN DÜZELTME (2026-09-22): satislar.
      // sync_cakisma_kopyasi'nin buluta gönderilmeden önce ayıklanması
      // bir önceki commit'te eklendi (bkz. aşağıdaki _veriCoz'daki
      // 'satislar' bloğu) — ama o düzeltmeden ÖNCE senkronize olmaya
      // çalışmış satışlar zaten HTTP 400 (PGRST204) aldığı için
      // 'kalici_hata'ya damgalanmıştı. Aşağıdaki sorgu SADECE
      // durum='beklemede' okur, yani o satışlar kod düzeltilse bile
      // SONSUZA KADAR senkronize olmayacaktı (bkz. _kuyrukSatiriBasarisiz
      // İsaretle — 4xx kalıcıdır, bir daha asla otomatik denenmez). Bu ÇOK
      // DAR kapsamlı, idempotent onarım SADECE bu tanınan/artık-düzeltilmiş
      // hata imzasıyla eşleşen satırları 'beklemede'ye geri döndürür —
      // genel bir "tüm kalıcı hataları yeniden dene" mekanizması DEĞİL;
      // gerçek validation hataları (ör. NOT NULL ihlali) hâlâ kalici_hata
      // olarak kalmalı.
      try {
        await db.rawUpdate(
          "UPDATE ${DbSabitler.syncQueue} SET durum = 'beklemede', deneme_sayisi = 0 "
          "WHERE durum = 'kalici_hata' AND tablo_adi = 'satislar' "
          "AND hata_mesaji LIKE '%sync_cakisma_kopyasi%'",
        );
      } catch (_) {
        // best-effort — ana akışı bloklamamalı
      }

      // Kalıcı kuyruktan bekleyen satırları oku — RAM'de HİÇBİR ŞEY
      // tutulmuyor, tek doğruluk kaynağı bu sorgu. Tek turda en fazla
      // 500 satır işlenir (bellek/performans için); kalan varsa turun
      // sonunda hemen yeni bir tur tetiklenir.
      // Bu turda okunacak satırların hepsi bu andan önce kuyruğa girdi —
      // grup başarıyla gidince "otomatik gönderim zamanı" olarak yazılır.
      final turBasi = DateTime.now().toUtc();
      final bekleyenSatirlar = await db.query(
        DbSabitler.syncQueue,
        where: 'durum = ?',
        whereArgs: ['beklemede'],
        orderBy: 'id ASC',
        limit: 500,
      );

      // Exponential backoff: daha önce en az bir kez başarısız olmuş bir
      // satır, kendi bekleme penceresi dolmadan tekrar denenmez (bkz.
      // _backoffSuresiSaniye). Henüz hiç denenmemiş satırlar (yeni
      // eklenenler) her zaman bu turda işlenir. NOT: "işlenecek satır
      // yok" durumunda erken return YAPILMAZ — bu, fonksiyonun altındaki
      // paylaşılan durum.value/istatistik güncellemesini atlayıp
      // durum'u kalıcı olarak "Senkronize ediliyor…"da bırakırdı.
      final denenecekler =
          bekleyenSatirlar.where(syncSatiriSimdiDenenebilirMi).toList();

      if (denenecekler.isNotEmpty) {
        isYapildiMi = true;
        durum.value = BulutDurum.gonderiliyor;
        final gruplar = <String, List<Map<String, dynamic>>>{};
        for (final satir in denenecekler) {
          gruplar.putIfAbsent(satir['tablo_adi'] as String, () => []).add(satir);
        }

        final now = DateTime.now().toIso8601String();

        // Ebeveyn tablolar çocuklarından ÖNCE gönderilir (satislar →
        // satis_kalem, cari → cari_hareket …) — çocuğun FK'sı aynı turda
        // çözülebilsin, bekletilmesin.
        final sirali = gruplar.entries.toList()
          ..sort((a, b) =>
              KolonHaritalama.derinlik(a.key).compareTo(KolonHaritalama.derinlik(b.key)));

        for (final entry in sirali) {
          final tablo = entry.key;
          final satirlar = entry.value;
          final uniqueAlan = KolonHaritalama.uniqueAlan(tablo) ?? 'id';

          // DELETE işlemleri
          final silinenler = satirlar
              .where((s) =>
                  s['islem_tipi'] == 'DELETE' || s['islem_tipi'] == 'HARD_DELETE')
              .toList();
          for (final s in silinenler) {
            final veri = _veriCoz(tablo, s);
            final deger = veri['global_id']?.toString() ?? '';
            try {
              if (s['islem_tipi'] == 'HARD_DELETE') {
                await _saglayici!.kaliciSil(
                    tablo: tablo, uniqueAlan: uniqueAlan, deger: deger);
              } else {
                await _saglayici!.sil(
                    tablo: tablo, uniqueAlan: uniqueAlan, deger: deger);
              }
              await db.delete(DbSabitler.syncQueue,
                  where: 'id = ?', whereArgs: [s['id']]);
              toplamBasarili++;
            } catch (e) {
              toplamHata++;
              tumHatalar.add('❌ $tablo DELETE: $e');
              final tur = e is BulutIstekHatasi ? e.tur : BulutHataTuru.gecici;
              await _kuyrukSatiriBasarisizIsaretle(
                  db, s['id'] as int, e, now, tur: tur, tablo: tablo);
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
              // Hata sınıflandırması (Madde 5): sonuc.tur — 4xx (kalıcı,
              // ör. validation/auth) ise satırlar 'kalici_hata'ya
              // geçirilip otomatik denemeden çıkarılır; 5xx/ağ hatası
              // (geçici) ise backoff'la tekrar denenmek üzere kuyrukta
              // kalır.
              if (sonuc.tamam) {
                // Ebeveyni henüz bulutta olmadığı için gönderilmeyen
                // (bekletilen) satırlar kuyrukta kalır; gerisi gitti.
                final idler = <int>[];
                for (var j = 0; j < upsertSatirlari.length; j++) {
                  final kuyrukId = upsertSatirlari[j]['id'] as int;
                  if (sonuc.bekletilenler.contains(j)) {
                    await _kuyrukSatiriBasarisizIsaretle(db, kuyrukId,
                        'ebeveyn kayıt henüz bulutta yok — bekletildi', now,
                        tablo: tablo);
                  } else {
                    idler.add(kuyrukId);
                  }
                }
                if (idler.isNotEmpty) {
                  final ph = idler.map((_) => '?').join(',');
                  await db.delete(DbSabitler.syncQueue,
                      where: 'id IN ($ph)', whereArgs: idler);
                }
                await _otoGonderZamaniYaz(tablo, turBasi);
              } else {
                for (final s in upsertSatirlari) {
                  await _kuyrukSatiriBasarisizIsaretle(
                      db, s['id'] as int, 'toplu upsert hata (HTTP ${sonuc.sonStatusKodu ?? "-"})', now,
                      tur: sonuc.tur, tablo: tablo);
                }
              }
            } catch (e) {
              toplamHata += upsertler.length;
              tumHatalar.add('❌ $tablo toplu upsert: $e');
              final tur = e is BulutIstekHatasi ? e.tur : BulutHataTuru.gecici;
              for (final s in upsertSatirlari) {
                await _kuyrukSatiriBasarisizIsaretle(
                    db, s['id'] as int, e, now, tur: tur, tablo: tablo);
              }
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
    // İşlenecek bir şey yoktu (kuyruk boş ya da tamamen backoff
    // penceresinde) — durum HİÇ 'gonderiliyor'a geçmedi, olduğu gibi
    // (bagli/bekliyor/hata) bırakılır. Sadece bu turda gerçekten bir
    // şey denendiyse yeni sonuca göre güncellenir.
    if (isYapildiMi) {
      durum.value = _bekleyenSayisiCache == 0
          ? (toplamHata > 0 ? BulutDurum.hata : BulutDurum.bagli)
          : BulutDurum.bekliyor;
    }

    if (kDebugMode && toplamBasarili > 0) {
      debugPrint('BulutManager: ✅$toplamBasarili ❌$toplamHata bekleyen:$_bekleyenSayisiCache');
    }

    // Kuyrukta hâlâ satır varsa VE bu turda gerçekten bir şey denendiyse
    // (500 limitine çarpıldıysa ya da hatalar nedeniyle kalan varsa)
    // hemen bir tur daha dene. Sadece backoff nedeniyle bekleyen satırlar
    // için 800ms'de bir gereksiz DB sorgusu yapmayı önler — onlar zaten
    // periyodik 8 saniyelik timer'da tekrar değerlendirilecek.
    if (isYapildiMi && _bekleyenSayisiCache > 0) _workerTetikle();
  }

  /// Tablonun otomatik kuyrukla EN SON başarıyla gönderildiği an —
  /// Veritabani._sonGonderFiligrani çakışma tespitinde manuel gönderim
  /// zamanıyla birlikte okur (anahtar sözleşmesi orada da aynı).
  static String otoGonderAnahtari(String tablo) => 'mp_sync_otogonder_$tablo';

  Future<void> _otoGonderZamaniYaz(String tablo, DateTime zaman) async {
    try {
      final p = await SharedPreferences.getInstance();
      final mevcut = DateTime.tryParse(p.getString(otoGonderAnahtari(tablo)) ?? '');
      if (mevcut == null || zaman.isAfter(mevcut)) {
        await p.setString(otoGonderAnahtari(tablo), zaman.toIso8601String());
      }
    } catch (_) {
      // best-effort — yalnızca çakışma sezgisini besler
    }
  }

  /// Testler için: sağlayıcıyı ve periyodik worker'ı kaldırır.
  @visibleForTesting
  void testIcinSifirla() {
    _timer?.cancel();
    _timer = null;
    _saglayici = null;
    _gonderiliyor = false;
    _bekleyenSayisiCache = 0;
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
