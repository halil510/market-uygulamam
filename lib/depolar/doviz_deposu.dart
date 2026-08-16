// lib/depolar/doviz_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../modeller/doviz_model.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/tcmb_servisi.dart';

class DovizDeposu {
  Future<Database> get _d async => Veritabani().db;

  Future<List<DovizModel>> tumunuGetir({bool sadeceAktif = true}) async {
    try {
      final db = await _d;
      final rows = await db.query(
        DbSabitler.dovizKurlari,
        where: sadeceAktif ? 'aktif = 1' : null,
        orderBy: 'kod ASC',
      );
      return rows.map(DovizModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('DovizDeposu.tumunuGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<DovizModel?> koduIleGetir(String kod) async {
    try {
      final db = await _d;
      final rows = await db.query(DbSabitler.dovizKurlari,
          where: 'kod = ?', whereArgs: [kod], limit: 1);
      if (rows.isEmpty) return null;
      return DovizModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('DovizDeposu.koduIleGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Kuru günceller (kullanıcının Kur Ayarları ekranından elle girdiği
  /// değer). guncelleme_tarihi otomatik olarak "şimdi" yapılır.
  Future<void> kuruGuncelle(String kod, {required double alisKuru, required double satisKuru}) async {
    try {
      final db = await _d;
      await db.update(
        DbSabitler.dovizKurlari,
        {
          'alis_kuru': alisKuru,
          'satis_kuru': satisKuru,
          'guncelleme_tarihi': DateTime.now().toIso8601String(),
        },
        where: 'kod = ?',
        whereArgs: [kod],
      );
    } catch (e, st) {
      LogServisi().hata('DovizDeposu.kuruGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Kullanıcı isteği: "güncelle dediğimizde merkez bankasından para
  /// birimlerini çeker" — TCMB'den gelen tüm kurları, veritabanında
  /// KAYITLI OLAN (aktif ya da pasif) para birimleriyle eşleştirip tek
  /// bir transaction içinde günceller. Kayıtlı olmayan bir kur TCMB
  /// listesinde varsa ekstra bir şey yapılmaz — "Para Birimi Ekle"
  /// akışından ayrı bırakılıyor (kullanıcı hangi dövizleri takip etmek
  /// istediğini kendisi seçsin).
  Future<int> tcmbdenTopluGuncelle(List<TcmbDovizSonuc> tcmbKurlari) async {
    try {
      final db = await _d;
      var guncellenen = 0;
      await db.transaction((txn) async {
        for (final k in tcmbKurlari) {
          final n = await txn.update(
            DbSabitler.dovizKurlari,
            {
              'alis_kuru': k.birimForexAlis,
              'satis_kuru': k.birimForexSatis,
              'guncelleme_tarihi': DateTime.now().toIso8601String(),
            },
            where: 'kod = ?',
            whereArgs: [k.kod],
          );
          guncellenen += n;
        }
      });
      return guncellenen;
    } catch (e, st) {
      LogServisi().hata('DovizDeposu.tcmbdenTopluGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// "Para Birimi Ekle" ekranından, TCMB listesinden seçilen bir dövizi
  /// takip edilecekler listesine ekler (kur değerleriyle birlikte,
  /// böylece eklendiği anda güncel kur zaten hazır olur).
  Future<void> paraBirimiEkle(TcmbDovizSonuc tcmbDoviz, {required String sembol}) async {
    try {
      final db = await _d;
      final mevcut = await koduIleGetir(tcmbDoviz.kod);
      if (mevcut != null) {
        await db.update(DbSabitler.dovizKurlari, {
          'aktif': 1,
          'alis_kuru': tcmbDoviz.birimForexAlis,
          'satis_kuru': tcmbDoviz.birimForexSatis,
          'guncelleme_tarihi': DateTime.now().toIso8601String(),
        }, where: 'kod = ?', whereArgs: [tcmbDoviz.kod]);
        return;
      }
      await db.insert(DbSabitler.dovizKurlari, {
        'kod': tcmbDoviz.kod,
        'ad': tcmbDoviz.ad.isNotEmpty ? tcmbDoviz.ad : tcmbDoviz.kod,
        'sembol': sembol,
        'alis_kuru': tcmbDoviz.birimForexAlis,
        'satis_kuru': tcmbDoviz.birimForexSatis,
        'guncelleme_tarihi': DateTime.now().toIso8601String(),
        'aktif': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      LogServisi().hata('DovizDeposu.paraBirimiEkle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Bir para birimini takip listesinden kaldırır (silmez, pasif yapar
  /// — geçmiş ürün kayıtlarındaki referanslar bozulmasın diye).
  Future<void> pasifYap(String kod) async {
    try {
      final db = await _d;
      await db.update(DbSabitler.dovizKurlari, {'aktif': 0},
          where: 'kod = ?', whereArgs: [kod]);
    } catch (e, st) {
      LogServisi().hata('DovizDeposu.pasifYap', hata: e, yigin: st);
      rethrow;
    }
  }
}
