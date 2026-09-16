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
// kullanicilar...) Madde 7 gereği HİÇ kopyalanmaz — sadece bu 5 tablo.
// satis_kalemleri ve diğer detay/child tablolar bu ilk kopyalama
// increment'ine BİLEREK DAHİL EDİLMEDİ (satislar'ın ana kaydı arşivde
// olsa bile kalemleri henüz yok) — kapsamı dar tutup doğrulanabilir
// başlamak için, ileriki bir artışta eklenmeli.
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
import 'arsiv_veritabani_yoneticisi.dart';
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
        if (!sonuc.dogrulandiMi) {
          throw StateError(
            '${kural.tablo} arşiv doğrulaması başarısız — '
            'aktif: ${sonuc.aktifSayim} satır / ${sonuc.aktifToplam}, '
            'arşiv: ${sonuc.arsivSayim} satır / ${sonuc.arsivToplam}.',
          );
        }
      }
      return sonuclar;
    } finally {
      await arsiv.close();
    }
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
    final semaSatirlari = await aktif.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?", [kural.tablo]);
    if (semaSatirlari.isEmpty) {
      throw StateError('Aktif veritabanında ${kural.tablo} tablosu bulunamadı.');
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
}
