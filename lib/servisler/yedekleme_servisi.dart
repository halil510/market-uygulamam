// lib/servisler/yedekleme_servisi.dart
// Otomatik + manuel yedekleme servisi
// - Günlük veya haftalık otomatik yedek
// - Eski yedekleri otomatik temizle (max 10 adet tut)
// - Yedek durumu: son yedek tarihi, boyutu
// - Paylaş / geri yükle
import '../cekirdek/utils/dosya_paylasim.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_servisi.dart';
import 'veritabani_dosya_servisi.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../veri/database/veritabani.dart';

class YedekBilgi {
  final String yol;
  final String dosyaAdi;
  final DateTime tarih;
  final int boyutByte;
  final bool otomatik;
  /// Yalnızca kullanıcının seçtiği ek klasörde bulunan (ör. USB) yedek.
  final bool ekKlasorde;

  const YedekBilgi({
    required this.yol,
    required this.dosyaAdi,
    required this.tarih,
    required this.boyutByte,
    required this.otomatik,
    this.ekKlasorde = false,
  });

  String get boyutStr {
    if (boyutByte < 1024) return '$boyutByte B';
    if (boyutByte < 1024 * 1024) return '${(boyutByte / 1024).toStringAsFixed(1)} KB';
    return '${(boyutByte / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get tarihStr =>
      DateFormat('dd.MM.yyyy HH:mm').format(tarih);
}

class YedeklemeServisi {
  static final YedeklemeServisi _i = YedeklemeServisi._();
  factory YedeklemeServisi() => _i;
  YedeklemeServisi._();

  static const _maxYedekSayisi = 10; // Maksimum tutulacak yedek
  static const _sonYedekKey    = 'son_otomatik_yedek';
  // Cihaza özgü yol → SharedPreferences (ayarlar tablosu buluta/diğer
  // cihazlara gider, oradaki USB yolu başka bilgisayarda anlamsız).
  static const _ekKlasorKey    = 'yedek_ek_klasor';

  /// Son yedekte ek klasöre kopyalama başarısızsa sebebi (ör. USB takılı
  /// değil). Yedeğin kendisi yine de varsayılan klasöre alınmıştır.
  String? sonEkKopyaHatasi;

  // ── Yedek dizini ──────────────────────────────────────────────────────
  Future<Directory> _yedekDizini() async {
    final dir = await getApplicationDocumentsDirectory();
    final yedekDir = Directory(p.join(dir.path, 'yedekler'));
    await yedekDir.create(recursive: true);
    return yedekDir;
  }

  /// Varsayılan yedek klasörünün yolu (ekranda göstermek için).
  Future<String> yedekKlasoru() async => (await _yedekDizini()).path;

  // ── Ek yedek klasörü (USB / ikinci disk) ──────────────────────────────
  // Yedek HER ZAMAN önce varsayılan klasöre alınır, sonra buraya kopyalanır:
  // bilgisayarın diski bozulsa / çalınsa da yedek ayrı yerde durur; USB
  // takılı değilse yedek yine alınmış olur.
  Future<String?> ekKlasor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final yol = prefs.getString(_ekKlasorKey);
      return (yol == null || yol.trim().isEmpty) ? null : yol;
    } catch (_) {
      return null;
    }
  }

  Future<void> ekKlasorKaydet(String? yol) async {
    final prefs = await SharedPreferences.getInstance();
    if (yol == null || yol.trim().isEmpty) {
      await prefs.remove(_ekKlasorKey);
    } else {
      await prefs.setString(_ekKlasorKey, yol);
    }
  }

  Future<void> _ekKlasoreKopyala(String zipYolu) async {
    sonEkKopyaHatasi = null;
    final ek = await ekKlasor();
    if (ek == null) return;
    try {
      if (p.equals(p.dirname(zipYolu), ek)) return;
      final dizin = Directory(ek);
      await dizin.create(recursive: true);
      final hedef = p.join(ek, p.basename(zipYolu));
      final gecici = '$hedef.tmp';
      await File(zipYolu).copy(gecici);
      await File(gecici).rename(hedef);
      await _klasoruTemizle(dizin);
    } catch (e, st) {
      sonEkKopyaHatasi = 'Ek klasöre ($ek) kopyalanamadı: $e';
      LogServisi().hata('YedeklemeServisi.ekKlasoreKopyala', hata: e, yigin: st);
    }
  }

  // ── Manuel yedek al ───────────────────────────────────────────────────
  Future<String> yedekAl({bool otomatik = false}) async {
    try {
      final dbPath = await getDatabasesPath();
      final kaynak = File(p.join(dbPath, 'market.db'));
      if (!await kaynak.exists()) throw Exception('Veritabanı bulunamadı');

      // 🔴🔴 KRİTİK VERİ KAYBI RİSKİ (derin analizde bulundu): veritabanı
      // WAL (Write-Ahead Log) modunda çalışıyor — son commit edilmiş
      // satış/stok hareketleri bir süre 'market.db-wal' dosyasında bekleyip
      // ANA market.db dosyasına HENÜZ YAZILMAMIŞ olabilir. Yedekleme
      // önceden sadece market.db'yi zip'liyordu — bu, GEÇERLİ ama EKSİK
      // (son işlemleri kaybetmiş) bir yedek üretebiliyordu ve hiçbir hata
      // vermiyordu. TRUNCATE checkpoint, WAL'daki her şeyi ana dosyaya
      // yazıp WAL'ı sıfırlar — böylece zip'lenen dosya her zaman TAM ve
      // kendi başına tutarlı olur.
      final db = await Veritabani().db;
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

      final yedekDir = await _yedekDizini();
      final tarih    = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final prefix   = otomatik ? 'oto' : 'manuel';
      final zipYolu  = '${yedekDir.path}/barkopro_${prefix}_$tarih.zip';

      final encoder = ZipFileEncoder();
      encoder.create(zipYolu);
      encoder.addFile(kaynak);
      // Ayarlar tablosunu da yedekle (meta bilgi)
      encoder.close();

      // Son yedek tarihini kaydet
      if (otomatik) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_sonYedekKey, DateTime.now().toIso8601String());
      }

      // Eski yedekleri temizle
      await _klasoruTemizle(yedekDir);
      await _ekKlasoreKopyala(zipYolu);

      if (kDebugMode) debugPrint('Yedek alındı: $zipYolu');
      return zipYolu;
    } catch (e, st) {
      LogServisi().hata('YedeklemeServisi.yedekAl', hata: e, yigin: st);
      rethrow;
    }
  }

  // ── Eski yedekleri temizle ────────────────────────────────────────────
  // Yalnızca uygulamanın ürettiği barkopro_*.zip dosyalarına dokunur (ek
  // klasör kullanıcının başka dosyalarını da içerebilir).
  Future<void> _klasoruTemizle(Directory dizin) async {
    try {
      final liste = _klasordekiYedekler(dizin)
          .where((y) => y.dosyaAdi.startsWith('barkopro_'))
          .toList();
      if (liste.length <= _maxYedekSayisi) return;

      // En eskiden başlayarak sil
      final silinecekler = liste.sublist(_maxYedekSayisi);
      for (final yedek in silinecekler) {
        await File(yedek.yol).delete();
        if (kDebugMode) debugPrint('Eski yedek silindi: ${yedek.dosyaAdi}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Eski yedek temizleme hatası: $e');
    }
  }

  // ── Geri yükle ────────────────────────────────────────────────────────
  /// ZIP içindeki .db dosyasını geri yükler. İmza, güvenlik kopyası,
  /// -wal/-shm temizliği, PRAGMA integrity_check ve bozuksa geri alma
  /// VeritabaniDosyaServisi.dosyayiDegistir()'de (Veritabanını İçe Al ile
  /// aynı yol) — bozuk yedekte mevcut veri DEĞİŞMEZ.
  Future<void> yedekiGeriYukle(String zipYolu) async {
    try {
      final bytes   = await File(zipYolu).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      List<int>? dbIcerik;
      for (final file in archive) {
        if (file.name.endsWith('.db')) {
          dbIcerik = file.content as List<int>;
          break;
        }
      }
      if (dbIcerik == null) {
        throw Exception('Yedek dosyasında geçerli bir veritabanı bulunamadı.');
      }

      await VeritabaniDosyaServisi().dosyayiDegistir(
        hedef: p.join(await getDatabasesPath(), DbSabitler.dbAdi),
        yeniIcerik: dbIcerik,
        yedekOneki: 'geri_yukleme_oncesi',
        kapat: Veritabani().kapat,
      );
      await cekmeFiligranlariniSifirla();
    } catch (e, st) {
      LogServisi().hata('YedeklemeServisi.geriYukle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Buluttan çekme filigranlarını (mp_sync_al_*, mp_sync_al_sz_*) siler →
  /// sonraki senkron tabloları baştan çeker.
  ///
  /// Neden: yedek 10:00'da alındı, 10:00-17:00 arası satışlar buluta gitti,
  /// çekme filigranı 17:00. Yedek geri yüklenince bu satışlar yerelde yok
  /// ama filigran "17:00'a kadar aldım" dediği için bir daha çekilmezdi
  /// (yalnız açılıştaki 48 saatlik geniş pencere kısmen kurtarıyordu).
  /// Bulut kullanmayan cihazda anahtar yoktur, etkisizdir.
  @visibleForTesting
  static Future<void> cekmeFiligranlariniSifirla() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith('mp_sync_al_')).toList()) {
        await prefs.remove(k);
      }
    } catch (e, st) {
      LogServisi().hata('YedeklemeServisi.cekmeFiligranlariniSifirla', hata: e, yigin: st);
    }
  }

  // ── Paylaş ────────────────────────────────────────────────────────────
  Future<void> paylasYedek(String zipYolu) async {
    final tarih = DateFormat('dd.MM.yyyy').format(DateTime.now());
    await DosyaPaylasim.paylas(ShareParams(files: [XFile(zipYolu)],
      text: 'BarkoPro Yedek — $tarih',
    ));
  }

  // ── Yedek listesi ─────────────────────────────────────────────────────
  /// Varsayılan klasördeki yedekler + ek klasörde olup burada olmayanlar
  /// (ör. bilgisayar yenilendi, yedek yalnız USB'de kaldı).
  Future<List<YedekBilgi>> yedekListesi() async {
    try {
      final liste = _klasordekiYedekler(await _yedekDizini());
      final ek = await ekKlasor();
      if (ek != null && Directory(ek).existsSync()) {
        final adlar = liste.map((y) => y.dosyaAdi).toSet();
        liste.addAll(_klasordekiYedekler(Directory(ek), ekKlasorde: true)
            .where((y) => !adlar.contains(y.dosyaAdi)));
        liste.sort((a, b) => b.tarih.compareTo(a.tarih));
      }
      return liste;
    } catch (e) {
      return [];
    }
  }

  List<YedekBilgi> _klasordekiYedekler(Directory dir, {bool ekKlasorde = false}) {
    try {
      final dosyalar = dir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.zip'))
          .where((f) => !ekKlasorde || p.basename(f.path).startsWith('barkopro_'))
          .toList();

      final liste = dosyalar.map((f) {
        final adi  = p.basename(f.path);
        final stat = f.statSync();
        // Tarih: dosya adından parse et (yyyyMMdd_HHmmss)
        DateTime tarih;
        try {
          final match = RegExp(r'(\d{8}_\d{6})').firstMatch(adi);
          tarih = match != null
              ? DateFormat('yyyyMMdd_HHmmss').parse(match.group(1)!)
              : stat.modified;
        } catch (_) {
          tarih = stat.modified;
        }
        return YedekBilgi(
          yol:       f.path,
          dosyaAdi:  adi,
          tarih:     tarih,
          boyutByte: stat.size,
          otomatik:  adi.contains('_oto_'),
          ekKlasorde: ekKlasorde,
        );
      }).toList();

      // En yeniden eskiye sırala
      liste.sort((a, b) => b.tarih.compareTo(a.tarih));
      return liste;
    } catch (e) {
      return [];
    }
  }

  // ── Son otomatik yedek bilgisi ────────────────────────────────────────
  Future<DateTime?> sonOtomatikYedekTarihi() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str   = prefs.getString(_sonYedekKey);
      if (str == null) return null;
      return DateTime.parse(str);
    } catch (_) {
      return null;
    }
  }

  // ── Yedek alınması gerekiyor mu? ──────────────────────────────────────
  Future<bool> yedekGerekliMi({int gunAralik = 1}) async {
    final son = await sonOtomatikYedekTarihi();
    if (son == null) return true;
    return yedekGunuGeldiMi(son, DateTime.now(), gunAralik: gunAralik);
  }

  /// Takvim günüyle karşılaştırır. Önceden "24 saat geçti mi" (inDays)
  /// bakılıyordu: market her sabah ~10:00'da açılıp önceki yedek 10:16'da
  /// alındıysa 23 sa 54 dk → yedek atlanıyor, yedekler gün aşırı kalıyordu.
  @visibleForTesting
  static bool yedekGunuGeldiMi(DateTime son, DateTime simdi, {int gunAralik = 1}) {
    final sonGun = DateTime(son.year, son.month, son.day);
    final bugun = DateTime(simdi.year, simdi.month, simdi.day);
    return bugun.difference(sonGun).inDays >= gunAralik;
  }
}
