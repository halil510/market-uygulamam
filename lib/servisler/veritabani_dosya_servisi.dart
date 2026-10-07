// lib/servisler/veritabani_dosya_servisi.dart
//
// Yerel SQLite DOSYASI üzerindeki işlemler (açma, yol, içe alma, cihazı
// sıfırlama) — ekranlar artık Veritabani()'na doğrudan dokunmuyor
// (DEEP_AUDIT madde 24: katman ihlali).
//
// dosyayiDegistir() hem "Yedekten Geri Yükle" hem "Veritabanını İçe Al"
// tarafından kullanılan TEK güvenli yoldur. Önceden bu iki akış ayrı ayrı
// yazılmıştı ve birbirinin düzeltmesini almamıştı:
//   • İçe Al: PRAGMA integrity_check YOKTU — imzası doğru ama içi bozuk
//     bir dosya kabul ediliyor, uygulama bozuk veritabanıyla açılıyordu.
//   • Geri Yükle: -wal/-shm dosyaları SİLİNMİYORDU — eski WAL kayıtları
//     yeni dosyaya karışabiliyordu (İçe Al'da daha önce düzeltilen hata).
//   • İçe Al'ın '.import_oncesi_*.bak' güvenlik kopyaları hiç
//     temizlenmiyordu (her içe almada veritabanı boyutunda bir dosya).
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../veri/database/veritabani.dart';
import 'log_servisi.dart';

class VeritabaniDosyaServisi {
  static final VeritabaniDosyaServisi _i = VeritabaniDosyaServisi._();
  factory VeritabaniDosyaServisi() => _i;
  VeritabaniDosyaServisi._();

  static const _sqliteImza = 'SQLite format 3';
  static const _maxGuvenlikYedegi = 3;

  /// Açılışta veritabanını hazırlar (migrasyonlar dahil).
  Future<void> hazirla() async {
    await Veritabani().db;
  }

  /// Açık veritabanı dosyasının tam yolu (dışa aktarma/paylaşma için).
  Future<String> dosyaYolu() => Veritabani().dbYolu();

  Future<String> _hedefYol() async =>
      p.join(await getDatabasesPath(), DbSabitler.dbAdi);

  /// Seçilen .db dosyasını cihazın veritabanı yapar. Bozuksa hiçbir şey
  /// değişmez ve [Exception] fırlatılır. Başarılıysa ayarlar (tema hariç)
  /// sıfırlanır — çağıran uygulamayı yeniden başlatmalıdır.
  Future<void> iceAktar(String dosyaYolu) async {
    final bytes = await File(dosyaYolu).readAsBytes();
    await dosyayiDegistir(
      hedef: await _hedefYol(),
      yeniIcerik: bytes,
      yedekOneki: 'import_oncesi',
      kapat: Veritabani().kapat,
    );
    await _ayarlariTemaHaricTemizle();
  }

  /// Bu cihazdaki TÜM yerel veriyi siler: veritabanı (+wal/shm), ürün
  /// resimleri, yedekler, raporlar, ayarlar (tema hariç) ve güvenli depo.
  /// Buluttaki veriye dokunmaz.
  Future<void> cihaziSifirla() async {
    await Veritabani().kapat();
    await _dbDosyalariniSil(await _hedefYol());

    final appDir = await getApplicationDocumentsDirectory();
    for (final dir in ['urun_resimleri', 'yedekler', 'raporlar']) {
      final d = Directory('${appDir.path}/$dir');
      if (await d.exists()) await d.delete(recursive: true);
    }

    await _ayarlariTemaHaricTemizle();
    // GİB şifresi, oturum token'ı gibi hassas bilgiler de "tam temizlik"te
    // silinmeli.
    await const FlutterSecureStorage().deleteAll();
  }

  Future<void> _ayarlariTemaHaricTemizle() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('tema_adi');
    await prefs.clear();
    if (savedTheme != null) await prefs.setString('tema_adi', savedTheme);
  }

  /// [hedef] veritabanı dosyasını [yeniIcerik] ile güvenli şekilde
  /// değiştirir:
  ///  1) SQLite imzası doğrulanır (değilse hiçbir şeye dokunulmaz),
  ///  2) mevcut dosyanın `[hedef].[yedekOneki]_<ms>.bak` kopyası alınır,
  ///  3) bağlantı kapatılır, .db + -wal + -shm silinir, yeni içerik yazılır,
  ///  4) PRAGMA integrity_check — bozuksa güvenlik kopyası geri konur,
  ///  5) aynı önekli eski güvenlik kopyalarının son [_maxGuvenlikYedegi]
  ///     tanesi dışındakiler silinir.
  /// [kapat] testte enjekte edilebilsin diye parametre.
  Future<void> dosyayiDegistir({
    required String hedef,
    required List<int> yeniIcerik,
    required String yedekOneki,
    required Future<void> Function() kapat,
  }) async {
    if (yeniIcerik.length < 16 ||
        String.fromCharCodes(yeniIcerik.sublist(0, 15)) != _sqliteImza) {
      throw Exception('Seçilen dosya geçerli bir SQLite veritabanı değil — '
          'işlem iptal edildi, mevcut verileriniz DEĞİŞTİRİLMEDİ.');
    }

    final hedefDosya = File(hedef);
    final guvenlikYedegi =
        '$hedef.${yedekOneki}_${DateTime.now().millisecondsSinceEpoch}.bak';
    final yedekVar = await hedefDosya.exists();
    if (yedekVar) await hedefDosya.copy(guvenlikYedegi);

    await kapat();

    Future<void> geriAl() async {
      await _dbDosyalariniSil(hedef);
      if (yedekVar) await File(guvenlikYedegi).copy(hedef);
    }

    try {
      await _dbDosyalariniSil(hedef);
      await hedefDosya.writeAsBytes(yeniIcerik, flush: true);
    } catch (_) {
      await geriAl();
      rethrow;
    }

    if (!await butunlukKontrolEt(hedef)) {
      await geriAl();
      throw Exception('Dosya bozuk (bütünlük kontrolü başarısız) — işlem '
          'İPTAL edildi, önceki verileriniz korundu.');
    }

    await _eskiGuvenlikYedekleriniTemizle(hedef, yedekOneki);
  }

  Future<void> _dbDosyalariniSil(String hedef) async {
    for (final yol in [hedef, '$hedef-wal', '$hedef-shm']) {
      final f = File(yol);
      if (await f.exists()) await f.delete();
    }
  }

  /// [dbYolu]'ndaki dosyayı SALT-OKUNUR, İZOLE bir bağlantıyla açıp
  /// PRAGMA integrity_check çalıştırır — paylaşılan Veritabani()
  /// singleton'ına dokunmaz (migrasyonları erken tetiklemez).
  @visibleForTesting
  Future<bool> butunlukKontrolEt(String dbYolu) async {
    Database? kontrolDb;
    try {
      kontrolDb = await openDatabase(dbYolu, readOnly: true);
      final rows = await kontrolDb.rawQuery('PRAGMA integrity_check');
      final sonuc =
          rows.isNotEmpty ? rows.first.values.first.toString() : 'unknown';
      return sonuc == 'ok';
    } catch (e) {
      LogServisi().hata('VeritabaniDosyaServisi.butunlukKontrolEt', hata: e);
      return false;
    } finally {
      await kontrolDb?.close();
    }
  }

  Future<void> _eskiGuvenlikYedekleriniTemizle(
      String hedef, String yedekOneki) async {
    try {
      final onek = '${p.basename(hedef)}.${yedekOneki}_';
      final dosyalar = Directory(p.dirname(hedef))
          .listSync()
          .whereType<File>()
          .where((f) =>
              p.basename(f.path).startsWith(onek) && f.path.endsWith('.bak'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path)); // en yeni ilk
      if (dosyalar.length <= _maxGuvenlikYedegi) return;
      for (final f in dosyalar.sublist(_maxGuvenlikYedegi)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Güvenlik yedeği temizleme hatası: $e');
    }
  }
}
