// lib/servisler/bulut/bulut_manager.dart
// ─────────────────────────────────────────────────────────────────────────────
// Merkezi bulut yöneticisi — singleton, provider-agnostic.
// İşlem yapıldığında otomatik kuyruk, retry, batch gönderimi.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'bulut_saglayici.dart';
import 'supabase_saglayici.dart';
import 'supabase_ayarlari.dart';
import '../kolon_haritalama.dart';
import '../../veri/database/veritabani.dart';
import '../audit_log_servisi.dart';

// ── Sync kaydı ────────────────────────────────────────────────────────────────
class _SyncKayit {
  final String tablo;
  final String islem;   // UPSERT | DELETE
  final Map<String,dynamic> veri;
  int denemeSayisi;
  DateTime zaman;

  _SyncKayit({
    required this.tablo,
    required this.islem,
    required this.veri,
    this.denemeSayisi = 0,
  }) : zaman = DateTime.now();
}

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
    bekliyor              => '${BulutManager._instance?._kuyruk.length ?? 0} kayıt bekliyor',
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
  final _kuyruk = <_SyncKayit>[];
  Timer? _timer;
  bool _gonderiliyor = false;

  final durum    = ValueNotifier<BulutDurum>(BulutDurum.bagli_degil);
  final istatistik = ValueNotifier<_Istatistik>(const _Istatistik());

  IBulutSaglayici? get mevcutSaglayici => _saglayici;
  int get bekleyenSayisi => _kuyruk.length;

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
    if (sonuc.basarili) _workerBaslat();
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
    final veri = KolonHaritalama.cevir(tablo, ham);
    // 🔴🔴🔴 KAPSAMLI DERİN ANALİZ (bkz. SupabaseSyncServisi._hazirla()
    // içindeki aynı düzeltme, aynı gerekçeyle): eski, yerini yeni isimli
    // bir sütunun aldığı ama hiç silinmemiş sütunlar buluta gitmemeli —
    // aksi hâlde PostgREST bu tabloların TÜM gönderimini reddeder.
    if (tablo == 'faturalar') {
      veri.remove('efatura_uuid');
      veri.remove('efatura_durum');
      veri.remove('efatura_tipi');
    }
    if (tablo == 'personel') {
      veri.remove('ise_baslama_tarihi');
    }
    // 🔴🔴 KRİTİK, SON HAT DÜZELTMESİ (kullanıcı bulgusu — AYNI
    // Supabase hatası tekrar tekrar geldi: "kredi_kartlari NOT NULL
    // ihlali, kart_no_maskeli"): Daha önce bu alanı SADECE
    // KrediKartiDeposu.ekle()/guncelle()'de ve bir migrasyon ile
    // düzelttim — ama bu kayıt hâlâ null geliyor. Bu, verinin BAŞKA
    // bir yoldan (ör. buluttan_al'ın genel/ham senkron ekleme yolu,
    // ya da migrasyonun henüz çalışmadığı eski bir cihaz) geldiğini
    // gösteriyor. Artık bu kontrol, TÜM upsert() çağrılarının geçtiği
    // TEK merkezi noktaya kondu — kaynağı ne olursa olsun, bu alan
    // ASLA null/boş olarak buluta gönderilemez.
    if (tablo == 'kredi_kartlari') {
      final knm = veri['kart_no_maskeli'];
      if (knm == null || (knm is String && knm.isEmpty)) {
        veri['kart_no_maskeli'] = '**** **** **** ????';
        // Sadece gönderilen veriyi değil, YEREL kaydı da kalıcı olarak
        // düzelt — aksi hâlde bu yama her senkron denemesinde tekrar
        // tekrar (ama en azından artık başarıyla) uygulanır.
        if (ham['id'] != null) {
          Veritabani().db.then((db) => db.update(
                'kredi_kartlari', {'kart_no_maskeli': '**** **** **** ????'},
                where: 'id = ?', whereArgs: [ham['id']],
              )).catchError((_) => 0);
        }
      }
    }
    final gid  = veri['global_id']?.toString();

    // 🔴 ÇOĞALMA SIZINTISI DÜZELTMESİ: Bazı kayıtlar (stok_hareket vb.)
    // lokalde global_id'siz oluşturuluyor. Bu yol önceden onları NULL
    // kimlikle buluta basıyordu (null, UNIQUE kısıtına takılmaz — her
    // seferinde YENİ satır); manuel gönderim de aynı kaydı kimlik
    // atayıp İKİNCİ kez basıyordu → bulut sürekli çoğalıyordu. Artık:
    // kimliksiz kayda burada kalıcı kimlik üretilip LOKALE yazılıyor,
    // kuyruğa kimlikli hali giriyor — iki yol da hep AYNI kimliği
    // kullanır, on_conflict eşleşir, çoğalma biter.
    if ((gid == null || gid.isEmpty) && ham['id'] != null) {
      final yeniGid = const Uuid().v4();
      veri['global_id'] = yeniGid;
      // Lokale kalıcı yaz (beklemeden, arka planda — kuyruk akışını
      // yavaşlatmasın; yazım bitmeden uygulama kapanırsa bir sonraki
      // manuel senkronun backfill'i zaten tamamlar).
      Veritabani().db.then((db) => db.update(
            tablo, {'global_id': yeniGid},
            where: 'id = ?', whereArgs: [ham['id']],
          )).catchError((_) => 0);
    }
    final gidSon = veri['global_id']?.toString();

    // Aynı global_id varsa güncelle
    if (gidSon != null) {
      final idx = _kuyruk.indexWhere(
          (k) => k.tablo == tablo && k.veri['global_id'] == gidSon);
      if (idx >= 0) {
        _kuyruk[idx] = _SyncKayit(tablo: tablo, islem: 'UPSERT', veri: veri);
        _workerTetikle();
        return;
      }
    }
    _kuyruk.add(_SyncKayit(tablo: tablo, islem: 'UPSERT', veri: veri));
    if (_kuyruk.length == 1) durum.value = BulutDurum.bekliyor;
    _workerTetikle();
  }

  void sil(String tablo, String globalId) {
    if (_saglayici == null) return;
    _kuyruk.removeWhere(
        (k) => k.tablo == tablo && k.veri['global_id'] == globalId);
    _kuyruk.add(_SyncKayit(
      tablo: tablo, islem: 'DELETE',
      veri: {'global_id': globalId},
    ));
    _workerTetikle();
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

  Future<void> _isle() async {
    if (_gonderiliyor || _saglayici == null || _kuyruk.isEmpty) return;
    _gonderiliyor = true;
    durum.value = BulutDurum.gonderiliyor;

    final islenecek = List<_SyncKayit>.from(_kuyruk);
    _kuyruk.clear();

    // Tablo bazlı grupla — toplu batch gönder
    final gruplar = <String, List<_SyncKayit>>{};
    for (final k in islenecek) {
      gruplar.putIfAbsent(k.tablo, () => []).add(k);
    }

    int toplamBasarili = 0, toplamHata = 0;
    final tumHatalar = <String>[];

    for (final entry in gruplar.entries) {
      final tablo = entry.key;
      final kayitlar = entry.value;
      final uniqueAlan = KolonHaritalama.uniqueAlan(tablo) ?? 'id';

      // DELETE işlemleri
      final silinenler = kayitlar.where((k) => k.islem == 'DELETE').toList();
      for (final k in silinenler) {
        try {
          await _saglayici!.sil(
            tablo: tablo,
            uniqueAlan: uniqueAlan,
            deger: k.veri['global_id']?.toString() ?? '',
          );
          toplamBasarili++;
        } catch (e) {
          toplamHata++;
          tumHatalar.add('❌ $tablo DELETE: $e');
          if (k.denemeSayisi < 3) {
            k.denemeSayisi++;
            _kuyruk.add(k);
          }
        }
      }

      // UPSERT işlemleri — batch
      final upsertKayitlari = kayitlar.where((k) => k.islem == 'UPSERT').toList();
      final upsertler = upsertKayitlari.map((k) => k.veri).toList();
      if (upsertler.isNotEmpty) {
        try {
          final sonuc = await _saglayici!.topluUpsert(
            tablo: tablo,
            veriler: upsertler,
            uniqueAlan: uniqueAlan,
          );
          toplamBasarili += sonuc.basarili;
          toplamHata     += sonuc.hata;
          tumHatalar.addAll(sonuc.hataMesajlari);
        } catch (e) {
          // 🔴 DÜZELTME: DELETE başarısız olursa 3 kez yeniden
          // denenmek üzere kuyruğa geri ekleniyordu — ama UPSERT
          // (çok daha sık kullanılan işlem) için bu YOKTU. Geçici bir
          // ağ hatasında bu kayıtlar SESSİZCE kayboluyordu, kullanıcı
          // manuel "Buluta Gönder" yapana kadar bir daha hiç
          // denenmiyordu. Artık DELETE ile tutarlı şekilde yeniden
          // deneniyor.
          toplamHata += upsertler.length;
          tumHatalar.add('❌ $tablo toplu upsert: $e');
          for (final k in upsertKayitlari) {
            if (k.denemeSayisi < 3) {
              k.denemeSayisi++;
              _kuyruk.add(k);
            }
          }
        }
      }
    }

    // İstatistik güncelle
    final mevcut = istatistik.value;
    istatistik.value = _Istatistik(
      toplamGonderilen: mevcut.toplamGonderilen + toplamBasarili,
      toplamHata:       mevcut.toplamHata + toplamHata,
      sonHatalar:       tumHatalar.take(20).toList(),
      sonGonderim:      DateTime.now(),
    );

    _gonderiliyor = false;
    durum.value = _kuyruk.isEmpty
        ? (toplamHata > 0 ? BulutDurum.hata : BulutDurum.bagli)
        : BulutDurum.bekliyor;

    if (kDebugMode && toplamBasarili > 0) {
      debugPrint('BulutManager: ✅$toplamBasarili ❌$toplamHata bekleyen:${_kuyruk.length}');
    }
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
