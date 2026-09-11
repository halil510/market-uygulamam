// lib/depolar/stok_deposu.dart
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/aktif_sube_servisi.dart';
import '../veri/database/veritabani.dart';
import '../modeller/stok_hareket_model.dart';
import 'sube_urun_deposu.dart';

class StokDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;
  final SubeUrunDeposu _subeUrunDeposu = SubeUrunDeposu();

  /// Kullanıcı isteği: "aynı ürünü başka cihazdan güncelleme nasıl
  /// olacak, tam profesyonel, hatasız çözelim" — araştırma (Event
  /// Sourcing deseni — bkz. "Building a Stock System That Cannot Be
  /// Wrong") şunu doğruladı: profesyonel sistemlerde stok SAYISI asla
  /// doğrudan güvenilir bir "gerçek" değer olarak saklanmaz — HER ZAMAN
  /// hareketlerin (movements) toplamından yeniden hesaplanır. Toplama
  /// işlemi matematiksel olarak DEĞİŞMEZ (commutative) olduğu için,
  /// farklı cihazlardan gelen hareketler HANGİ SIRAYLA senkronize
  /// olursa olsun, sonuç HER ZAMAN doğru olur — "son yazan kazanır"
  /// riskinin aksine.
  ///
  /// Bu fonksiyon, HER ürünün stoğunu `stok_hareket` tablosundaki TÜM
  /// kayıtlarının (onceki_stok/sonraki_stok farkının toplamı) üzerinden
  /// yeniden hesaplar. Senkronizasyon sonrası çağrılması önerilir.
  Future<int> stokMutabakatYap({void Function(String)? log}) async {
    try {
      final db = await _d;
      // Her ürün için, hareketlerinin net etkisini (sonraki-onceki farkı)
      // topla — bu, "miktar" alanının hareket_turu'na göre değişen
      // işaretinden BAĞIMSIZ, her zaman güvenilir bir yöntemdir.
      final sonuclar = await db.rawQuery('''
        SELECT urun_id, SUM(sonraki_stok - onceki_stok) as net_degisim
        FROM stok_hareket
        GROUP BY urun_id
      ''');

      var duzeltilen = 0;
      final now = DateTime.now().toIso8601String();
      final duzeltilenIdler = <int>[];
      await db.transaction((txn) async {
        for (final r in sonuclar) {
          final urunId = r['urun_id'] as int?;
          if (urunId == null) continue;
          final netDegisim = (r['net_degisim'] as num?)?.toDouble() ?? 0;
          // Doğru stok = 0 (başlangıç varsayımı) + TÜM hareketlerin net
          // etkisi. "İlk Stok" hareketi zaten 0'dan başladığı için bu
          // tutarlı.
          final dogruStok = netDegisim < 0 ? 0.0 : netDegisim; // negatif stok olmaz

          final mevcut = await txn.query('urunler',
              columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
          if (mevcut.isEmpty) continue;
          final suankiStok = (mevcut.first['stok'] as num?)?.toDouble() ?? 0;

          // Kayda değer bir fark varsa (yuvarlama hatalarını es geçmek
          // için 0.001 tolerans) düzelt.
          if ((suankiStok - dogruStok).abs() > 0.001) {
            // 🔴 Derin analizde bulundu: last_updated hiç bump
            // edilmiyordu — bu, manuel "Buluta Gönder" senkronunun bile
            // bu düzeltmeleri hiç yakalayamamasına yol açıyordu (delta
            // senkron last_updated'a bakıyor).
            await txn.update('urunler', {'stok': dogruStok, 'last_updated': now},
                where: 'id = ?', whereArgs: [urunId]);
            duzeltilen++;
            duzeltilenIdler.add(urunId);
            log?.call('Ürün #$urunId: $suankiStok → $dogruStok');
          }
        }
      });
      for (final urunId in duzeltilenIdler) {
        final satir = await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (satir.isNotEmpty) {
          BulutManager().upsert('urunler', Map<String, dynamic>.from(satir.first));
        }
      }
      if (duzeltilen > 0) {
        LogServisi().bilgi('Stok mutabakatı: $duzeltilen ürün düzeltildi');
      }
      return duzeltilen;
    } catch (e, st) {
      LogServisi().hata('Stok.stokMutabakatYap', hata: e, yigin: st);
      return 0;
    }
  }

  Future<void> stokDus({
    required int urunId,
    required double miktar,
    int? kullaniciId,
    int? referansId,
    String? referansTuru,
    String? aciklama,
  }) async {
    final db = await _d;
    final hareketGid = const Uuid().v4();
    await db.transaction((txn) => stokDusTxn(txn, hareketGid,
        urunId: urunId, miktar: miktar, kullaniciId: kullaniciId,
        referansId: referansId, referansTuru: referansTuru, aciklama: aciklama));
    // 🔴 Derin analizde bulundu: bu fonksiyon (uygulamanın EN SIK
    // çağrılan stok fonksiyonlarından biri — her satış, iade, alım
    // buradan geçiyor) 'stok_hareket' kaydına hiç global_id atamıyordu
    // ve bu kayıt için BulutManager'ı hiç çağırmıyordu — sadece
    // 'urunler' güncellemesi bildiriliyordu. Stok hareket geçmişi
    // sadece manuel senkronla buluta gidiyordu.
    final db2 = await _d;
    final guncelUrun = await db2.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
    if (guncelUrun.isNotEmpty) {
      BulutManager().upsert('urunler', Map<String, dynamic>.from(guncelUrun.first));
    }
    final hareketSatir = await db2.query('stok_hareket', where: 'global_id = ?', whereArgs: [hareketGid], limit: 1);
    if (hareketSatir.isNotEmpty) {
      BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
    }
    // 🔴 Derin analizde bulundu: 'sube_urun' (per-şube stok) tablosu
    // şemada vardı ama hiç kullanılmıyordu — urunler.stok TEK, GLOBAL
    // bir alan olarak kalıyordu, çok şubeli işletmelerde şubeler arası
    // stok ayrımı yapılamıyordu. Artık aktif şubenin payı da ayrıca
    // düşülüyor (urunler.stok TOPLAM olarak korunuyor, mevcut hiçbir
    // ekran/rapor bozulmuyor). try-catch ile sarılı: bu ek kayıt
    // başarısız olsa bile ANA stok işlemi (yukarıda zaten tamamlandı)
    // etkilenmemeli.
    try {
      final subeId = AktifSubeServisi().subeId;
      if (subeId != null) await _subeUrunDeposu.stokDus(urunId, subeId, miktar);
    } catch (e) {
      if (kDebugMode) debugPrint('sube_urun güncellenemedi (ana işlem etkilenmedi): $e');
    }
  }

  /// [stokDus] ile AYNI mantık, VERİLEN transaction içinde çalışır —
  /// kendi transaction'ını açmaz. BulutManager bildirimini ve sube_urun
  /// güncellemesini YAPMAZ (bkz. KasaDeposu.hareketEkleTxn'deki aynı not
  /// — dış transaction commit olmadan buluta göndermek riskli). Çağıran,
  /// dış transaction kapandıktan sonra [hareketGid] ile 'stok_hareket'
  /// satırını sorgulayıp buluta bildirebilir.
  Future<void> stokDusTxn(dynamic txn, String hareketGid, {
    required int urunId,
    required double miktar,
    int? kullaniciId,
    int? referansId,
    String? referansTuru,
    String? aciklama,
  }) async {
    final now = DateTime.now().toIso8601String();
    final rows = await txn.query('urunler', where: 'id = ?', whereArgs: [urunId]);
    if (rows.isEmpty) return;
    final onceki = (rows.first['stok'] as num).toDouble();
    final sonraki = (onceki - miktar).clamp(0, double.infinity);

    await txn.update('urunler', {'stok': sonraki, 'last_updated': now}, where: 'id = ?', whereArgs: [urunId]);
    await txn.insert('stok_hareket', {
      'global_id': hareketGid,
      'urun_id': urunId,
      'hareket_turu': 'Çıkış',
      'miktar': miktar,
      'onceki_stok': onceki,
      'sonraki_stok': sonraki,
      'tarih': now,
      'last_updated': now,
      if (referansId != null) 'referans_id': referansId,
      if (referansTuru != null) 'referans_turu': referansTuru,
      if (kullaniciId != null) 'kullanici_id': kullaniciId,
      if (aciklama != null) 'aciklama': aciklama,
    });
  }

  Future<void> stokGir({
    required int urunId,
    required double miktar,
    double birimMaliyet = 0,
    int? kullaniciId,
    String? aciklama,
    int? referansId,
    String? referansTuru,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final hareketGid = const Uuid().v4();
    await db.transaction((txn) async {
      final rows = await txn.query('urunler', where: 'id = ?', whereArgs: [urunId]);
      if (rows.isEmpty) return;
      final onceki = (rows.first['stok'] as num).toDouble();
      final sonraki = onceki + miktar;

      await txn.update('urunler', {'stok': sonraki, 'last_updated': now}, where: 'id = ?', whereArgs: [urunId]);
      await txn.insert('stok_hareket', {
        'global_id': hareketGid,
        'urun_id': urunId,
        'hareket_turu': 'Giriş',
        'miktar': miktar,
        'onceki_stok': onceki,
        'sonraki_stok': sonraki,
        'birim_maliyet': birimMaliyet,
        'tarih': now,
        'last_updated': now,
        if (kullaniciId != null) 'kullanici_id': kullaniciId,
        if (aciklama != null) 'aciklama': aciklama,
        if (referansId != null) 'referans_id': referansId,
        if (referansTuru != null) 'referans_turu': referansTuru,
      });
    });
    final db2 = await _d;
    final guncelUrun = await db2.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
    if (guncelUrun.isNotEmpty) {
      BulutManager().upsert('urunler', Map<String, dynamic>.from(guncelUrun.first));
    }
    final hareketSatir = await db2.query('stok_hareket', where: 'global_id = ?', whereArgs: [hareketGid], limit: 1);
    if (hareketSatir.isNotEmpty) {
      BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
    }
    try {
      final subeId = AktifSubeServisi().subeId;
      if (subeId != null) await _subeUrunDeposu.stokGir(urunId, subeId, miktar);
    } catch (e) {
      if (kDebugMode) debugPrint('sube_urun güncellenemedi (ana işlem etkilenmedi): $e');
    }
  }

  /// [stokGir] ile AYNI mantık, VERİLEN transaction içinde çalışır —
  /// kendi transaction'ını açmaz. BulutManager bildirimini ve sube_urun
  /// güncellemesini YAPMAZ (bkz. stokDusTxn'deki aynı not). Çağıran, dış
  /// transaction kapandıktan sonra [hareketGid] ile 'stok_hareket'
  /// satırını sorgulayıp buluta bildirebilir, ve isterse
  /// [subeStokPayiUygula] ile şube payını güncelleyebilir.
  Future<void> stokGirTxn(dynamic txn, String hareketGid, {
    required int urunId,
    required double miktar,
    double birimMaliyet = 0,
    int? kullaniciId,
    String? aciklama,
    int? referansId,
    String? referansTuru,
  }) async {
    final now = DateTime.now().toIso8601String();
    final rows = await txn.query('urunler', where: 'id = ?', whereArgs: [urunId]);
    if (rows.isEmpty) return;
    final onceki = (rows.first['stok'] as num).toDouble();
    final sonraki = onceki + miktar;

    await txn.update('urunler', {'stok': sonraki, 'last_updated': now}, where: 'id = ?', whereArgs: [urunId]);
    await txn.insert('stok_hareket', {
      'global_id': hareketGid,
      'urun_id': urunId,
      'hareket_turu': 'Giriş',
      'miktar': miktar,
      'onceki_stok': onceki,
      'sonraki_stok': sonraki,
      'birim_maliyet': birimMaliyet,
      'tarih': now,
      'last_updated': now,
      if (kullaniciId != null) 'kullanici_id': kullaniciId,
      if (aciklama != null) 'aciklama': aciklama,
      if (referansId != null) 'referans_id': referansId,
      if (referansTuru != null) 'referans_turu': referansTuru,
    });
  }

  /// [stokDusTxn]/[stokGirTxn] sonrası şube bazlı stok payını günceller.
  /// Best-effort: ana stok işlemi zaten kalıcı olduğu için bu adım
  /// başarısız olsa bile geri alınmaz (mevcut stokDus()/stokGir()
  /// davranışıyla aynı — bkz. oradaki try-catch).
  /// [fark] > 0 ise azalma (stokDus yönü), < 0 ise artış (stokGir yönü).
  Future<void> subeStokPayiUygula(int urunId, double fark) async {
    try {
      final subeId = AktifSubeServisi().subeId;
      if (subeId == null || fark == 0) return;
      if (fark > 0) {
        await _subeUrunDeposu.stokDus(urunId, subeId, fark);
      } else {
        await _subeUrunDeposu.stokGir(urunId, subeId, -fark);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('sube_urun güncellenemedi (ana işlem etkilenmedi): $e');
    }
  }

  Future<void> stokDuzelt(int urunId, double yeniMiktar, int kullaniciId) async {
    // 🔴 Not: 'onceki' burada (transaction dışında) tanımlanıyor ki
    // fonksiyonun SONUNDA (sube_urun güncellemesi için) da kullanılabilsin
    // — bu oturumda satis_deposu.dart'ta bulduğum "transaction içinde
    // tanımlanan değişkene dışarıdan erişme" hatasının AYNISINI burada
    // yapmamak için.
    double onceki = 0;
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final hareketGid = const Uuid().v4();
      await db.transaction((txn) async {
        final rows = await txn.query('urunler', where: 'id = ?', whereArgs: [urunId]);
        if (rows.isEmpty) return;
        onceki = (rows.first['stok'] as num).toDouble();

        await txn.update('urunler', {'stok': yeniMiktar, 'last_updated': now}, where: 'id = ?', whereArgs: [urunId]);
        await txn.insert('stok_hareket', {
          'global_id': hareketGid,
          'urun_id': urunId,
          'hareket_turu': 'Sayım',
          'miktar': yeniMiktar - onceki,
          'onceki_stok': onceki,
          'sonraki_stok': yeniMiktar,
          'tarih': now,
          'last_updated': now,
          'kullanici_id': kullaniciId,
          'aciklama': 'Stok sayım düzeltme',
        });
      });
      final guncelUrun = await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (guncelUrun.isNotEmpty) {
        BulutManager().upsert('urunler', Map<String, dynamic>.from(guncelUrun.first));
      }
      final hareketSatir = await db.query('stok_hareket', where: 'global_id = ?', whereArgs: [hareketGid], limit: 1);
      if (hareketSatir.isNotEmpty) {
        BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
      }
      // Sayım fiziksel olarak TEK bir konumda yapıldığı için fark
      // (yeni-eski) aktif şubenin payına uygulanır.
      try {
        final subeId = AktifSubeServisi().subeId;
        final fark = yeniMiktar - onceki;
        if (subeId != null && fark != 0) await _subeUrunDeposu.stokGir(urunId, subeId, fark);
      } catch (e) {
        if (kDebugMode) debugPrint('sube_urun güncellenemedi (ana işlem etkilenmedi): $e');
      }
    } catch (e, st) {
      LogServisi().hata('Stok.stokDuzelt', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<StokHareketModel>> hareketleriGetir(int urunId, {int limit = 50}) async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        'SELECT h.*, u.urun_adi FROM stok_hareket h LEFT JOIN urunler u ON h.urun_id = u.id '
        'WHERE h.urun_id = ? ORDER BY h.tarih DESC LIMIT ?',
        [urunId, limit],
      );
      return rows.map(StokHareketModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Stok.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<StokHareketModel>> tumHareketler({int limit = 100}) async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        'SELECT h.*, u.urun_adi FROM stok_hareket h LEFT JOIN urunler u ON h.urun_id = u.id '
        'ORDER BY h.tarih DESC LIMIT ?',
        [limit],
      );
      return rows.map(StokHareketModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Stok.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> geciciSayimEkleGuncelle(int urunId, double mevcutStok, double yeniStok) async {
    try {
      final db = await _d;
      await db.insert('gecici_sayim', {
        'urun_id': urunId,
        'mevcut_stok': mevcutStok,
        'yeni_stok': yeniStok,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      LogServisi().hata('Stok.geciciSayimEkleGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> geciciSayimListesi() async {
    try {
      final db = await _d;
      return await db.rawQuery(
        'SELECT g.*, u.urun_adi, u.barkod, u.birim_adi FROM gecici_sayim g JOIN urunler u ON g.urun_id = u.id',
      );
    } catch (e, st) {
      LogServisi().hata('Stok.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> geciciSayimUygula(int kullaniciId) async {
    try {
      final liste = await geciciSayimListesi();
      for (final row in liste) {
        await stokDuzelt(row['urun_id'] as int, (row['yeni_stok'] as num).toDouble(), kullaniciId);
      }
      await geciciSayimTemizle();
    } catch (e, st) {
      LogServisi().hata('Stok.geciciSayimUygula', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> geciciSayimTemizle() async {
    try {
      final db = await _d;
      await db.delete('gecici_sayim');
    } catch (e, st) {
      LogServisi().hata('Stok.geciciSayimTemizle', hata: e, yigin: st);
      rethrow;
    }
  }
}
