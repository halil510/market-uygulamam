// lib/servisler/donem_arsiv_servisi.dart
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — GERÇEK ARŞİVLEME,
// SADECE KOPYALAMA AŞAMASI (2026-09-16, kullanıcı onayı: "Aktif verinin
// arşive kopyalanmasını (SADECE kopyalama, silme yok) tasarlayıp
// kodlamaya başla — üretim verisini SİLMEDEN önce ayrıca onay isteyeceğim").
//
// 🔴🔴 KESİN KAPSAM SINIRI: Bu servis 5 "hareket" tablosundan (satislar,
// stok_hareket, cari_hareket, kasa_hareketleri, banka_hareketler) o
// dönemin tarih aralığına düşen satırları arsiv/<YIL>/barkopro_<YIL>.db
// dosyasına KOPYALAR ve Madde 19'a göre DOĞRULAR (satır sayısı + toplam
// tutar aktif/arşiv arasında eşleşmeli). AKTİF TABLOLARDAN HİÇBİR SATIRI
// SİLMEZ/ÇIKARMAZ. "Gerçek arşivleme"nin silme/taşıma alt-fazı (mimari
// plan §3b, DB şişmesini gerçekten azaltan adım) BİLİNÇLİ olarak KAPSAM
// DIŞI — üretim finansal verisini etkiler, ayrı ve açık bir onay turu
// gerektirir. Doğrulama başarısız olursa checkpoint FAILED olur, hiçbir
// "arşiv tamamlandı" işareti konmaz.
//
// Master tablolar (urunler, cariler, subeler, kasalar, bankalar,
// kullanicilar...) Madde 7 gereği HİÇ kopyalanmaz — sadece bu 5 tablo +
// satis_kalem (satislar'ın çocuk tablosu, kendi tarih/sube_id'si yoktur
// — WHERE'ü satis_id üzerinden JOIN ile satislar'a bağlanır, bkz.
// _satisKalemArsivle). satis_kalem, satislar'dan SONRA arşivlenir —
// verifikasyon sorgusu arşivdeki satislar'a bakar, bu yüzden sıra önemli.
// Diğer detay/child tablolar (ör. fatura kalemleri) bu increment'e
// BİLEREK DAHİL EDİLMEDİ — ileriki bir artışta eklenmeli.
//
// Şema replikasyonu: arşiv tablosu, aktif DB'deki CREATE TABLE SQL'i
// (sqlite_master.sql) BİREBİR çalıştırılarak oluşturulur — elle
// kopyalanan bir şema tanımı zamanla driftler, bu yaklaşım drift
// edemez. Şemadaki FOREIGN KEY cümleleri (ör. satislar.cari_id → cari)
// arşiv dosyasında da yazılır ama hiçbir zaman UYGULANMAZ, çünkü bu
// servisin açtığı arşiv bağlantısında `PRAGMA foreign_keys` HİÇ
// çalıştırılmıyor (sqflite varsayılanı zaten OFF) — bu KASITLI, master
// tablolar (cari, urunler...) arşive kopyalanmadığından FK'ler orada
// zaten karşılıksız kalacaktı.
//
// Batch/performans (Madde 24): sayfalama OFFSET ile değil, "id > son_id"
// keyset deseniyle yapılır (büyük tablolarda O(n²) taramaya düşmez),
// her sayfa kendi arsiv.batch()'inde COMMIT edilir — tek dev transaction
// yok, tüm tablo tek seferde RAM'e alınmıyor.
//
// Idempotency: ConflictAlgorithm.replace ile INSERT edildiğinden, bir
// devir yarıda kesilip tekrar çalıştırılırsa (checkpoint resume) aynı
// satırlar tekrar kopyalansa bile veri çoğalmaz — aynı id'li satır
// üzerine yazılır.
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'arsiv_veritabani_yoneticisi.dart';
import 'bulut/sync_kuyruk_yazici.dart';
import '../veri/database/veritabani.dart';

/// Tek bir tablonun arşivleme+doğrulama sonucu.
class DonemArsivTabloSonucu {
  final String tablo;
  final int kopyalanan;
  final int aktifSayim;
  final int arsivSayim;
  final double aktifToplam;
  final double arsivToplam;

  const DonemArsivTabloSonucu({
    required this.tablo,
    required this.kopyalanan,
    required this.aktifSayim,
    required this.arsivSayim,
    required this.aktifToplam,
    required this.arsivToplam,
  });

  /// Madde 19: satır sayısı VE toplam tutar aktif/arşiv arasında
  /// eşleşmeli (ondalık REAL toplamlar için küçük bir tolerans).
  bool get dogrulandiMi =>
      aktifSayim == arsivSayim && (aktifToplam - arsivToplam).abs() < 0.01;
}

class _TabloKurali {
  final String tablo;
  final String tarihKolonu;
  final String? subeKolonu; // null → şirket geneli (cari_hareket, banka_hareketler)
  final List<String> toplamKolonlari; // doğrulama SUM'u için

  const _TabloKurali({
    required this.tablo,
    required this.tarihKolonu,
    this.subeKolonu,
    required this.toplamKolonlari,
  });
}

class DonemArsivServisi {
  static const _kurallar = [
    _TabloKurali(
        tablo: 'satislar',
        tarihKolonu: 'tarih',
        subeKolonu: 'sube_id',
        toplamKolonlari: ['genel_toplam']),
    _TabloKurali(
        tablo: 'stok_hareket',
        tarihKolonu: 'tarih',
        subeKolonu: 'sube_id',
        toplamKolonlari: ['miktar']),
    _TabloKurali(
        tablo: 'cari_hareket',
        tarihKolonu: 'tarih',
        subeKolonu: null,
        toplamKolonlari: ['borc', 'alacak']),
    _TabloKurali(
        tablo: 'kasa_hareketleri',
        tarihKolonu: 'tarih',
        subeKolonu: 'sube_id',
        toplamKolonlari: ['tutar']),
    _TabloKurali(
        tablo: 'banka_hareketler',
        tarihKolonu: 'tarih',
        subeKolonu: null,
        toplamKolonlari: ['tutar']),
  ];

  static const _sayfaBoyutu = 1000;

  /// [donemYili] arşiv dosyasını (gerekirse) oluşturur, [subeId] ve
  /// [baslangic]..[bitis] tarih aralığındaki 5 hareket tablosunun
  /// satırlarını kopyalar, her tablo için doğrular. Herhangi bir tablo
  /// doğrulanamazsa StateError fırlatır (çağıran devir FAILED yapmalı).
  ///
  /// [aktifDbTest] ve [arsivDosyaYoluTest] SADECE testler için — gerçek
  /// `Veritabani()` singleton'ına ve `ArsivVeritabaniYoneticisi`'nin
  /// path_provider'a bağımlı yoluna ihtiyaç duymadan, gerçek geçici
  /// dosyalara karşı uçtan uca test edilebilmesi için (bkz.
  /// `ArsivVeritabaniYoneticisi.test` ile AYNI desen). Üretim kodu bu
  /// parametreleri HİÇ vermemeli.
  Future<List<DonemArsivTabloSonucu>> arsivleVeDogrula({
    required int donemYili,
    required int subeId,
    required DateTime baslangic,
    required DateTime bitis,
    void Function(String mesaj)? ilerlemeBildir,
    Database? aktifDbTest,
    String? arsivDosyaYoluTest,
  }) async {
    final aktif = aktifDbTest ?? await Veritabani().db;
    final arsivYolu = arsivDosyaYoluTest ??
        await ArsivVeritabaniYoneticisi().arsivDosyaYolu(donemYili);
    await Directory(arsivYolu).parent.create(recursive: true);
    // Bu servis, ArsivVeritabaniYoneticisi'nden (SADECE OKUMA) TAMAMEN
    // ayrı, kendi yazılabilir bağlantısını açar ve işi bitince kapatır —
    // salt-okunur yöneticinin FIFO önbelleğiyle karışmaz.
    final arsiv = await openDatabase(arsivYolu);

    try {
      final sonuclar = <DonemArsivTabloSonucu>[];
      for (final kural in _kurallar) {
        final sonuc = await _tabloyuArsivle(
          aktif: aktif,
          arsiv: arsiv,
          kural: kural,
          subeId: subeId,
          baslangic: baslangic,
          bitis: bitis,
          ilerlemeBildir: ilerlemeBildir,
        );
        sonuclar.add(sonuc);
        _dogrulamaKontrolEt(sonuc);
      }

      // satis_kalem, satislar'ın çocuğudur (kendi tarih/sube_id'si yok)
      // — satislar'dan SONRA, satis_id JOIN'iyle arşivlenir.
      final kalemSonuc = await _satisKalemArsivle(
        aktif: aktif,
        arsiv: arsiv,
        subeId: subeId,
        baslangic: baslangic,
        bitis: bitis,
        ilerlemeBildir: ilerlemeBildir,
      );
      sonuclar.add(kalemSonuc);
      _dogrulamaKontrolEt(kalemSonuc);

      return sonuclar;
    } finally {
      await arsiv.close();
    }
  }

  void _dogrulamaKontrolEt(DonemArsivTabloSonucu sonuc) {
    if (!sonuc.dogrulandiMi) {
      throw StateError(
        '${sonuc.tablo} arşiv doğrulaması başarısız — '
        'aktif: ${sonuc.aktifSayim} satır / ${sonuc.aktifToplam}, '
        'arşiv: ${sonuc.arsivSayim} satır / ${sonuc.arsivToplam}.',
      );
    }
  }

  /// Aktif DB'deki [tablo]'nun CREATE TABLE SQL'ini sqlite_master'dan
  /// alıp [arsiv]'a birebir uygular (IF NOT EXISTS garantisiyle, bkz.
  /// aşağıdaki not). Tablo [arsiv]'da zaten varsa no-op.
  Future<void> _semaKopyala(Database aktif, Database arsiv, String tablo) async {
    final semaSatirlari = await aktif.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?", [tablo]);
    if (semaSatirlari.isEmpty) {
      throw StateError('Aktif veritabanında $tablo tablosu bulunamadı.');
    }
    // 🔴 ÖNEMLİ: sqlite_master.sql, orijinal CREATE TABLE metnini DEĞİL,
    // SQLite'ın YENİDEN SERİLEŞTİRDİĞİ halini döner — "IF NOT EXISTS"
    // ifadesi bu serileştirmede KAYBOLUR (test bunu kanıtladı: devir bir
    // dönem için ikinci kez çalıştırılınca "table already exists"
    // hatası). Bu yüzden burada AÇIKÇA ekleniyor — devir resumable/
    // idempotent olmalı (Madde 17/28), arşiv tablosu her fazda yeniden
    // oluşturulmaya çalışılabilir.
    var semaSql = semaSatirlari.first['sql'] as String;
    if (!RegExp(r'CREATE TABLE\s+IF NOT EXISTS', caseSensitive: false).hasMatch(semaSql)) {
      semaSql = semaSql.replaceFirst(
          RegExp(r'CREATE TABLE', caseSensitive: false), 'CREATE TABLE IF NOT EXISTS');
    }
    await arsiv.execute(semaSql);
  }

  Future<DonemArsivTabloSonucu> _tabloyuArsivle({
    required Database aktif,
    required Database arsiv,
    required _TabloKurali kural,
    required int subeId,
    required DateTime baslangic,
    required DateTime bitis,
    void Function(String mesaj)? ilerlemeBildir,
  }) async {
    await _semaKopyala(aktif, arsiv, kural.tablo);

    final whereParts = <String>['${kural.tarihKolonu} >= ?', '${kural.tarihKolonu} <= ?'];
    final args = <Object?>[baslangic.toIso8601String(), bitis.toIso8601String()];
    if (kural.subeKolonu != null) {
      whereParts.add('${kural.subeKolonu} = ?');
      args.add(subeId);
    }
    final where = whereParts.join(' AND ');

    var islenen = 0;
    int? sonId;
    while (true) {
      final sayfaWhere = sonId == null ? where : '$where AND id > ?';
      final sayfaArgs = sonId == null ? args : [...args, sonId];
      final satirlar = await aktif.query(
        kural.tablo,
        where: sayfaWhere,
        whereArgs: sayfaArgs,
        orderBy: 'id ASC',
        limit: _sayfaBoyutu,
      );
      if (satirlar.isEmpty) break;

      final batch = arsiv.batch();
      for (final satir in satirlar) {
        batch.insert(kural.tablo, satir, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);

      islenen += satirlar.length;
      sonId = satirlar.last['id'] as int;
      ilerlemeBildir?.call('${kural.tablo} arşivleniyor: $islenen satır');
      if (satirlar.length < _sayfaBoyutu) break;
    }

    final toplamIfadesi = kural.toplamKolonlari.map((k) => 'COALESCE(SUM($k),0)').join(' + ');
    final aktifOzet = await aktif
        .rawQuery('SELECT COUNT(*) AS n, $toplamIfadesi AS t FROM ${kural.tablo} WHERE $where', args);
    final arsivOzet = await arsiv
        .rawQuery('SELECT COUNT(*) AS n, $toplamIfadesi AS t FROM ${kural.tablo} WHERE $where', args);

    return DonemArsivTabloSonucu(
      tablo: kural.tablo,
      kopyalanan: islenen,
      aktifSayim: (aktifOzet.first['n'] as int?) ?? 0,
      arsivSayim: (arsivOzet.first['n'] as int?) ?? 0,
      aktifToplam: (aktifOzet.first['t'] as num?)?.toDouble() ?? 0,
      arsivToplam: (arsivOzet.first['t'] as num?)?.toDouble() ?? 0,
    );
  }

  /// satis_kalem'in kendi tarih/sube_id'si yok — satis_id üzerinden
  /// satislar'a JOIN edilerek aynı dönem+şube filtresiyle arşivlenir.
  /// ÖNKOŞUL: satislar bu [arsiv] bağlantısında ZATEN arşivlenmiş
  /// olmalı — doğrulama sorgusu arşivdeki satislar'a bakar (bkz. dosya
  /// başı yorumu, _kurallar sırası).
  Future<DonemArsivTabloSonucu> _satisKalemArsivle({
    required Database aktif,
    required Database arsiv,
    required int subeId,
    required DateTime baslangic,
    required DateTime bitis,
    void Function(String mesaj)? ilerlemeBildir,
  }) async {
    const tablo = 'satis_kalem';
    await _semaKopyala(aktif, arsiv, tablo);

    const subSorgu =
        'satis_id IN (SELECT id FROM satislar WHERE tarih >= ? AND tarih <= ? AND sube_id = ?)';
    final args = <Object?>[
      baslangic.toIso8601String(), bitis.toIso8601String(), subeId,
    ];

    var islenen = 0;
    int? sonId;
    while (true) {
      final sayfaWhere = sonId == null ? subSorgu : '$subSorgu AND id > ?';
      final sayfaArgs = sonId == null ? args : [...args, sonId];
      final satirlar = await aktif.query(
        tablo,
        where: sayfaWhere,
        whereArgs: sayfaArgs,
        orderBy: 'id ASC',
        limit: _sayfaBoyutu,
      );
      if (satirlar.isEmpty) break;

      final batch = arsiv.batch();
      for (final satir in satirlar) {
        batch.insert(tablo, satir, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);

      islenen += satirlar.length;
      sonId = satirlar.last['id'] as int;
      ilerlemeBildir?.call('$tablo arşivleniyor: $islenen satır');
      if (satirlar.length < _sayfaBoyutu) break;
    }

    const toplamIfadesi = 'COALESCE(SUM(toplam_tutar),0)';
    final aktifOzet = await aktif.rawQuery(
        'SELECT COUNT(*) AS n, $toplamIfadesi AS t FROM $tablo WHERE $subSorgu', args);
    final arsivOzet = await arsiv.rawQuery(
        'SELECT COUNT(*) AS n, $toplamIfadesi AS t FROM $tablo WHERE $subSorgu', args);

    return DonemArsivTabloSonucu(
      tablo: tablo,
      kopyalanan: islenen,
      aktifSayim: (aktifOzet.first['n'] as int?) ?? 0,
      arsivSayim: (arsivOzet.first['n'] as int?) ?? 0,
      aktifToplam: (aktifOzet.first['t'] as num?)?.toDouble() ?? 0,
      arsivToplam: (arsivOzet.first['t'] as num?)?.toDouble() ?? 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // GERÇEK TEMİZLEME (kullanıcı onayı, 2026-09-21): "veritabanı temizleme
  // işlemini de yap" + "cariler de sade bakiye kalan devir gözükecek".
  // Bu metod DEVİR MOTORUNUN FAZ 8'i (Açılış Kayıtları) tarafından,
  // arşivleme (yukarıdaki arsivleVeDogrula — kopyala+doğrula) VE TÜM
  // kapanış snapshot'ları (FAZ 4-7: stok/cari/kasa/banka) ZATEN
  // yazıldıktan SONRA çağrılmalı — sıra kritik: kasa snapshot'ı kendi
  // hareket zincirinin SON satırını okur, silme ondan ÖNCE yapılırsa
  // yanlış (sıfır) bakiye yakalanır.
  //
  // 🔴 KRİTİK TASARIM: bu uygulamada stok/cari/kasa bakiyeleri event-
  // sourcing ile hesaplanıyor — SİLME işlemi TEK BAŞINA yapılırsa
  // sonraki bir mutabakat turu (stokMutabakatYap/bakiyeMutabakatYap gibi
  // TÜM geçmişi yeniden toplayan fonksiyonlar) yanlış (eksik) bir bakiye
  // üretir. Bu yüzden her tablo için silme, o tablonun mutabakat
  // formülünü BOZMAYACAK bir "açılış" kaydıyla birlikte yapılır:
  //   - STOK: silinen satırların net etkisi (SUM(sonraki-onceki))
  //     ÖNCEDEN hesaplanıp TEK bir 'Devir Açılış' satırıyla korunur —
  //     stokMutabakatYap()'ın SUM'u matematiksel olarak DEĞİŞMEZ.
  //   - CARİ: kapanış snapshot'ındaki (cari_kapanis_snapshot.bakiye —
  //     cari.bakiye'nin snapshot anındaki, ayrıca tutulan, kendi kendini
  //     iyileştiren otoriter değeri) "kalan bakiye" TEK bir 'Devir'
  //     hareketiyle yazılır — kullanıcının istediği "sade kalan bakiye"
  //     görünümü budur.
  //   - KASA: kapanış snapshot'ındaki bakiye TEK bir 'AçılışKasa'
  //     satırıyla yazılır (kasa'da cari/stok'un aksine "SUM" değil "SON
  //     SATIR" mantığı var — silme sonrası zincir boş kalırsa
  //     _sonBakiyeTxn sıfır döner, bu satır onu önler).
  //   - BANKA: hiçbir açılış satırına GEREK YOK — BankaHareketDeposu.
  //     _sonBakiyeTxn zaten "hiç hareket yoksa banka_hesaplar.bakiye'ye
  //     düş" fallback'ine sahip (kanıtlanmış, kod okunarak doğrulandı).
  //   - SATIŞ/SATIŞ KALEMİ: saf geçmiş kaydı — hiçbir mutabakat
  //     formülü bunlardan "güncel durum" hesaplamıyor, açılış GEREKMEZ.
  //
  // SADECE YEREL: bu silme SyncKuyrukYazici'ye YAZILMAZ — Supabase'deki
  // veri KORUNUR (supabase_arsiv_plani.sql BÖLÜM 6'nın zaten bilinçli
  // olarak kapsam dışı bıraktığı "cloud'da da sil" adımı bu değil, ayrı
  // ve onaylanmamış bir karar olarak kalıyor). Açılış satırları ise
  // NORMAL iş verisi gibi senkronlanır (SyncKuyrukYazici.ekleTxn).
  Future<void> aktifTablolardanSilVeAcilisYaz({
    required int donemId,
    required int donemYili,
    required int subeId,
    required DateTime baslangic,
    required DateTime bitis,
    Database? aktifDbTest,
  }) async {
    final aktif = aktifDbTest ?? await Veritabani().db;
    final acilisTarihi = bitis.add(const Duration(seconds: 1)).toIso8601String();
    final simdi = DateTime.now().toIso8601String();
    final bas = baslangic.toIso8601String();
    final bit = bitis.toIso8601String();

    // ── SATIŞ + SATIŞ KALEM: saf log, sadece sil ────────────────────
    // 🔴 ÖNEMLİ: `iade.satis_id` ve `masa_siparisleri.satis_id` gerçek
    // FOREIGN KEY (CASCADE'siz) — bu iki tablodan HÂLÂ referans edilen
    // bir satislar satırını silmeye çalışmak `PRAGMA foreign_keys = ON`
    // altında hata fırlatırdı. Bu yüzden sadece HİÇBİR yerden referans
    // edilmeyen satışlar silinir; referanslı olanlar bu turda ATLANIR
    // (bir sonraki devirde, o iade/sipariş de arşivlendiğinde temizlenir).
    await aktif.transaction((txn) async {
      final satisIdler = (await txn.rawQuery('''
        SELECT id FROM satislar
        WHERE tarih >= ? AND tarih <= ? AND sube_id = ?
          AND id NOT IN (SELECT satis_id FROM iade WHERE satis_id IS NOT NULL)
          AND id NOT IN (SELECT satis_id FROM masa_siparisleri WHERE satis_id IS NOT NULL)
      ''', [bas, bit, subeId]))
          .map((r) => r['id'] as int)
          .toList();
      if (satisIdler.isEmpty) return;
      final yerTutucu = List.filled(satisIdler.length, '?').join(',');
      // satis_kalem'de ON DELETE CASCADE var — açık silme sadece netlik
      // için, CASCADE'e sessizce güvenmek yerine.
      await txn.delete('satis_kalem',
          where: 'satis_id IN ($yerTutucu)', whereArgs: satisIdler);
      await txn.delete(
          'satislar', where: 'id IN ($yerTutucu)', whereArgs: satisIdler);
    });

    // ── STOK: net etkiyi TEK satırda KORUYARAK sil ──────────────────
    await aktif.transaction((txn) async {
      final netler = await txn.rawQuery('''
        SELECT urun_id, SUM(sonraki_stok - onceki_stok) AS net
        FROM stok_hareket WHERE tarih >= ? AND tarih <= ? AND sube_id = ?
        GROUP BY urun_id
      ''', [bas, bit, subeId]);
      await txn.delete('stok_hareket',
          where: 'tarih >= ? AND tarih <= ? AND sube_id = ?',
          whereArgs: [bas, bit, subeId]);
      for (final r in netler) {
        final urunId = r['urun_id'] as int?;
        final net = (r['net'] as num?)?.toDouble() ?? 0;
        if (urunId == null || net.abs() < 0.0001) continue;
        final satir = {
          'global_id': const Uuid().v4(),
          'urun_id': urunId,
          'hareket_turu': 'Devir Açılış',
          'miktar': net.abs(),
          'onceki_stok': 0.0,
          'sonraki_stok': net,
          'tarih': acilisTarihi,
          'sube_id': subeId,
          'referans_turu': 'devir_acilis',
          'aciklama': '$donemYili yıl sonu devri — açılış',
          'last_updated': simdi,
        };
        final id = await txn.insert('stok_hareket', satir);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'stok_hareket', veri: {...satir, 'id': id});
      }
    });

    // ── CARİ (şirket geneli): kapanış snapshot'ındaki "kalan bakiye" ─
    await aktif.transaction((txn) async {
      final silinenCariIdler = (await txn.rawQuery(
              'SELECT DISTINCT cari_id FROM cari_hareket WHERE tarih >= ? AND tarih <= ?',
              [bas, bit]))
          .map((r) => r['cari_id'] as int?)
          .whereType<int>()
          .toSet();
      await txn.delete('cari_hareket',
          where: 'tarih >= ? AND tarih <= ?', whereArgs: [bas, bit]);
      // Boşsa bu dönem/aralık başka bir şubenin devri sırasında ZATEN
      // temizlenmiş demektir (cari şirket geneli — bkz. dosya başı
      // "BİLİNÇLİ TASARIM SINIRLAMASI") — idempotent, tekrar açılış
      // satırı YAZILMAZ (mükerrer olurdu).
      if (silinenCariIdler.isEmpty) return;

      final snapshotlar = await txn.query('cari_kapanis_snapshot',
          where: 'donem_id = ?', whereArgs: [donemId]);
      for (final s in snapshotlar) {
        final cariId = s['cari_id'] as int?;
        if (cariId == null || !silinenCariIdler.contains(cariId)) continue;
        final bakiye = (s['bakiye'] as num?)?.toDouble() ?? 0;
        if (bakiye.abs() < 0.005) continue;
        final satir = {
          'global_id': const Uuid().v4(),
          'cari_id': cariId,
          'tarih': acilisTarihi,
          'fis_tipi': 'Devir',
          'aciklama': '$donemYili yıl sonu devri — kapanış bakiyesi',
          'borc': bakiye > 0 ? bakiye : 0.0,
          'alacak': bakiye < 0 ? -bakiye : 0.0,
          'is_deleted': 0,
          'last_updated': simdi,
        };
        final id = await txn.insert('cari_hareket', satir);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'cari_hareket', veri: {...satir, 'id': id});
      }
    });

    // ── KASA (şube bazlı): kapanış snapshot'ındaki bakiye TEK satır ──
    await aktif.transaction((txn) async {
      final oncekiVarMi = await txn.query('kasa_hareketleri',
          where: 'tarih >= ? AND tarih <= ? AND sube_id = ?',
          whereArgs: [bas, bit, subeId], limit: 1);
      await txn.delete('kasa_hareketleri',
          where: 'tarih >= ? AND tarih <= ? AND sube_id = ?',
          whereArgs: [bas, bit, subeId]);
      if (oncekiVarMi.isEmpty) return;

      final snapshotlar = await txn.query('kasa_kapanis_snapshot',
          where: 'donem_id = ? AND sube_id = ?',
          whereArgs: [donemId, subeId], limit: 1);
      final bakiye = snapshotlar.isEmpty
          ? 0.0
          : (snapshotlar.first['bakiye'] as num?)?.toDouble() ?? 0.0;
      final satir = {
        'global_id': const Uuid().v4(),
        'hareket_tipi': 'AçılışKasa',
        'tutar': bakiye,
        'bakiye_sonrasi': bakiye,
        'tarih': acilisTarihi,
        'sube_id': subeId,
        'referans_turu': 'devir_acilis',
        'aciklama': '$donemYili yıl sonu devri — açılış',
        'last_updated': simdi,
      };
      final id = await txn.insert('kasa_hareketleri', satir);
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'kasa_hareketleri', veri: {...satir, 'id': id});
    });

    // ── BANKA (şirket geneli): açılış satırı GEREKMEZ, sadece sil ────
    await aktif.transaction((txn) async {
      await txn.delete('banka_hareketler',
          where: 'tarih >= ? AND tarih <= ?', whereArgs: [bas, bit]);
    });
  }
}
