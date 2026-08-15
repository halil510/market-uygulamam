// lib/servisler/yedekleme_servisi.dart
// Otomatik + manuel yedekleme servisi
// - Günlük veya haftalık otomatik yedek
// - Eski yedekleri otomatik temizle (max 10 adet tut)
// - Yedek durumu: son yedek tarihi, boyutu
// - Paylaş / geri yükle
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
import '../veri/database/veritabani.dart';

class YedekBilgi {
  final String yol;
  final String dosyaAdi;
  final DateTime tarih;
  final int boyutByte;
  final bool otomatik;

  const YedekBilgi({
    required this.yol,
    required this.dosyaAdi,
    required this.tarih,
    required this.boyutByte,
    required this.otomatik,
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

  // ── Yedek dizini ──────────────────────────────────────────────────────
  Future<Directory> _yedekDizini() async {
    final dir = await getApplicationDocumentsDirectory();
    final yedekDir = Directory('${dir.path}/yedekler');
    await yedekDir.create(recursive: true);
    return yedekDir;
  }

  // ── Manuel yedek al ───────────────────────────────────────────────────
  Future<String> yedekAl({bool otomatik = false}) async {
    try {
      final dbPath = await getDatabasesPath();
      final kaynak = File(p.join(dbPath, 'market.db'));
      if (!await kaynak.exists()) throw Exception('Veritabanı bulunamadı');

      final yedekDir = await _yedekDizini();
      final tarih    = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final prefix   = otomatik ? 'oto' : 'manuel';
      final zipYolu  = '${yedekDir.path}/marketplus_${prefix}_$tarih.zip';

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
      await _eskiYedekleriTemizle();

      if (kDebugMode) debugPrint('Yedek alındı: $zipYolu');
      return zipYolu;
    } catch (e, st) {
      LogServisi().hata('YedeklemeServisi.yedekAl', hata: e, yigin: st);
      rethrow;
    }
  }

  // ── Eski yedekleri temizle ────────────────────────────────────────────
  Future<void> _eskiYedekleriTemizle() async {
    try {
      final liste = await yedekListesi();
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
  Future<void> yedekiGeriYukle(String zipYolu) async {
    // ÖNCEDEN BURADA CİDDİ BİR VERİ GÜVENLİĞİ AÇIĞI VARDI: mevcut
    // veritabanı hiçbir güvenlik yedeği alınmadan, dosyanın gerçekten
    // geçerli bir SQLite veritabanı olup olmadığı hiç doğrulanmadan
    // doğrudan üzerine yazılıyordu. Bozuk bir ZIP, yanlış bir dosya veya
    // yarıda kesilen bir işlem, kullanıcının MEVCUT (belki yedekten daha
    // güncel) verisini GERİ DÖNÜŞSÜZ şekilde kaybetmesine yol açabilirdi
    // — yedekleme özelliğinin kendisi bir veri kaybı riskine dönüşüyordu.
    try {
      final dbPath = await getDatabasesPath();
      final hedef  = p.join(dbPath, 'market.db');

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

      // 1) Dosyanın GERÇEKTEN bir SQLite veritabanı olduğunu doğrula —
      // SQLite dosyaları her zaman "SQLite format 3\0" (16 bayt) ile
      // başlar. Bu kontrol olmadan bozuk/yanlış bir dosya sessizce
      // market.db'nin üzerine yazılabilirdi.
      const sqliteImza = 'SQLite format 3';
      if (dbIcerik.length < 16 ||
          String.fromCharCodes(dbIcerik.sublist(0, 15)) != sqliteImza) {
        throw Exception(
            'Yedek dosyası geçerli bir SQLite veritabanı değil — geri '
            'yükleme iptal edildi, mevcut verileriniz DEĞİŞTİRİLMEDİ.');
      }

      // 2) Geri yüklemeden ÖNCE mevcut veritabanının bir güvenlik
      // kopyasını al — geri yükleme başarısız olursa veya yanlışlıkla
      // yapıldıysa geri dönebilmek için.
      final guvenlikYedegi = '$hedef.geri_yukleme_oncesi_${DateTime.now().millisecondsSinceEpoch}.bak';
      if (await File(hedef).exists()) {
        await File(hedef).copy(guvenlikYedegi);
      }

      // 3) Mevcut veritabanı bağlantısını düzgün kapat — açık bir
      // bağlantı varken dosyayı değiştirmek veri bozulmasına yol
      // açabilir.
      await Veritabani().kapat();

      try {
        await File(hedef).writeAsBytes(dbIcerik);
      } catch (e) {
        // Yazma başarısız oldu — güvenlik yedeğinden geri al
        if (await File(guvenlikYedegi).exists()) {
          await File(guvenlikYedegi).copy(hedef);
        }
        rethrow;
      }
    } catch (e, st) {
      LogServisi().hata('YedeklemeServisi.geriYukle', hata: e, yigin: st);
      rethrow;
    }
  }

  // ── Paylaş ────────────────────────────────────────────────────────────
  Future<void> paylasYedek(String zipYolu) async {
    final tarih = DateFormat('dd.MM.yyyy').format(DateTime.now());
    await Share.shareXFiles(
      [XFile(zipYolu)],
      text: 'MarketPlus Yedek — $tarih',
    );
  }

  // ── Yedek listesi ─────────────────────────────────────────────────────
  Future<List<YedekBilgi>> yedekListesi() async {
    try {
      final dir = await _yedekDizini();
      final dosyalar = dir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.zip'))
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
    return DateTime.now().difference(son).inDays >= gunAralik;
  }
}
