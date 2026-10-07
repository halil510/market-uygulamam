// lib/depolar/stok_deposu.dart
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
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
      final now = DateTime.now().toIso8601String();
      final duzeltilenIdler = <int>[];
      // 🔴 YARIŞ DÜZELTMESİ (derin analiz 2026-10-07): "doğru stok"
      // hesabı ÖNCEDEN transaction'ın DIŞINDA yapılıyordu. Hesap ile yazma
      // arasında kaydedilen bir satış (stok 10→8) eski değerle (10)
      // ezilebiliyordu. Artık okuma ve yazma aynı transaction'da —
      // sqflite transaction'ları sıraya koyduğu için araya yazma giremez.
      await db.transaction((txn) async {
        final uyumsuzlar = await txn.rawQuery(_stokUyumsuzSql);
        for (final r in uyumsuzlar) {
          final urunId = r['urun_id'] as int?;
          if (urunId == null) continue;
          final dogruStok = (r['dogru_stok'] as num?)?.toDouble() ?? 0;
          // last_updated güncellenir — delta senkron düzeltmeyi yakalasın.
          await txn.update('urunler', {'stok': dogruStok, 'last_updated': now},
              where: 'id = ?', whereArgs: [urunId]);
          duzeltilenIdler.add(urunId);
          log?.call('Ürün #$urunId: ${r['mevcut']} → $dogruStok');
        }
      });
      final duzeltilen = duzeltilenIdler.length;
      for (final urunId in duzeltilenIdler) {
        final satir = await db.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (satir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(satir.first));
        }
      }
      if (duzeltilen > 0) {
        LogServisi().bilgi('Stok mutabakatı: $duzeltilen ürün düzeltildi');
      }
      return duzeltilen;
    } catch (e, st) {
      LogServisi().hata('Stok.stokMutabakatYap', hata: e, yigin: st);
      // 0 dönmek başarısız düzeltmeyi "0 kayıt düzeltildi ✓" gösteriyordu.
      rethrow;
    }
  }

  /// [stokMutabakatYap] ile AYNI mantık ama HİÇBİR ŞEY YAZMAZ — Veri
  /// Sağlığı Merkezi'nde "kontrol et" adımında (düzeltme onayı almadan)
  /// kaç ürünün uyumsuz olduğunu göstermek için.
  Future<int> mutabakatUyumsuzlukSayisi() async {
    try {
      final db = await _d;
      // Ürün başına ayrı SELECT (N+1) yerine tek sorgu.
      final rows =
          await db.rawQuery('SELECT COUNT(*) AS n FROM ($_stokUyumsuzSql)');
      return (rows.first['n'] as num?)?.toInt() ?? 0;
    } catch (e, st) {
      LogServisi().hata('Stok.mutabakatUyumsuzlukSayisi', hata: e, yigin: st);
      // 0 döndürmek "uyumlu" ile "kontrol edilemedi"yi ayırt edilemez
      // kılıyordu (Veri Sağlığı yeşil gösteriyordu) — hata iletilir.
      rethrow;
    }
  }

  /// Stoğu, hareketlerinin net etkisinden (Σ sonraki − önceki; "miktar"
  /// alanının türe göre değişen işaretinden bağımsız) farklı olan ürünler.
  /// Doğru stok = net (başlangıç 0 varsayımı, "İlk Stok" hareketi 0'dan
  /// başlar). Negatif stok GEÇERLİ (B2 kararı) — önceden max(net, 0) ile
  /// kırpılıyor, negatif stoklu ürün her senkronda yanlışça "düzeltiliyordu".
  /// Sayım ve düzeltme aynı tanımı kullanır.
  static const String _stokUyumsuzSql = '''
    SELECT u.id AS urun_id, u.stok AS mevcut, t.net_degisim AS dogru_stok
    FROM (
      SELECT urun_id, COALESCE(SUM(sonraki_stok - onceki_stok), 0) AS net_degisim
      FROM stok_hareket
      WHERE urun_id IS NOT NULL
      GROUP BY urun_id
    ) t
    JOIN urunler u ON u.id = t.urun_id
    WHERE ABS(COALESCE(u.stok, 0) - t.net_degisim) > 0.001
  ''';

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
        urunId: urunId,
        miktar: miktar,
        kullaniciId: kullaniciId,
        referansId: referansId,
        referansTuru: referansTuru,
        aciklama: aciklama));
    // 🔴 Derin analizde bulundu: bu fonksiyon (uygulamanın EN SIK
    // çağrılan stok fonksiyonlarından biri — her satış, iade, alım
    // buradan geçiyor) 'stok_hareket' kaydına hiç global_id atamıyordu
    // ve bu kayıt için BulutManager'ı hiç çağırmıyordu — sadece
    // 'urunler' güncellemesi bildiriliyordu. Stok hareket geçmişi
    // sadece manuel senkronla buluta gidiyordu.
    final db2 = await _d;
    final guncelUrun = await db2.query('urunler',
        where: 'id = ?', whereArgs: [urunId], limit: 1);
    if (guncelUrun.isNotEmpty) {
      BulutManager()
          .upsert('urunler', Map<String, dynamic>.from(guncelUrun.first));
    }
    final hareketSatir = await db2.query('stok_hareket',
        where: 'global_id = ?', whereArgs: [hareketGid], limit: 1);
    if (hareketSatir.isNotEmpty) {
      BulutManager().upsert(
          'stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
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
      if (kDebugMode) {
        debugPrint('sube_urun güncellenemedi (ana işlem etkilenmedi): $e');
      }
    }
  }

  /// [stokDus] ile AYNI mantık, VERİLEN transaction içinde çalışır —
  /// kendi transaction'ını açmaz. BulutManager bildirimini ve sube_urun
  /// güncellemesini YAPMAZ (bkz. KasaDeposu.hareketEkleTxn'deki aynı not
  /// — dış transaction commit olmadan buluta göndermek riskli). Çağıran,
  /// dış transaction kapandıktan sonra [hareketGid] ile 'stok_hareket'
  /// satırını sorgulayıp buluta bildirebilir.
  Future<void> stokDusTxn(
    dynamic txn,
    String hareketGid, {
    required int urunId,
    required double miktar,
    int? kullaniciId,
    int? referansId,
    String? referansTuru,
    String? aciklama,
    // FAZ 1 madde 3 (Lot/Seri) için eklendi: varsayılan 'Çıkış' — mevcut
    // TÜM çağıranlar davranışını korur. lot_seri_ekrani.dart bir lotun
    // miktarını azalttığında hareketTuru:'Lot Düzeltme', lotId:<id> geçer.
    String? hareketTuru,
    int? lotId,
  }) async {
    final now = DateTime.now().toIso8601String();
    final rows =
        await txn.query('urunler', where: 'id = ?', whereArgs: [urunId]);
    if (rows.isEmpty) return;
    final onceki = (rows.first['stok'] as num).toDouble();
    // KARAR (kullanıcı, 2026-10-07 — B2): stok EKSİYE DÜŞEBİLİR. Önceden 0'a
    // kırpılıyordu: stok 2 iken 5 satılınca stok 0, hareket farkı −2 oluyor;
    // 5'in iadesi stoğu 5'e çıkarıyordu (+3 hayalet stok). Artık −3'e düşer,
    // iade gerçek değeri (2) verir; hareket farkı her zaman satılan miktardır.
    final sonraki = onceki - miktar;

    await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
        where: 'id = ?', whereArgs: [urunId]);
    final hareketSatiri = {
      'global_id': hareketGid,
      'urun_id': urunId,
      'hareket_turu': hareketTuru ?? 'Çıkış',
      'miktar': miktar,
      'onceki_stok': onceki,
      'sonraki_stok': sonraki,
      'tarih': now,
      'last_updated': now,
      'referans_id': ?referansId,
      'referans_turu': ?referansTuru,
      'kullanici_id': ?kullaniciId,
      'aciklama': ?aciklama,
      'lot_id': ?lotId,
    };
    await txn.insert('stok_hareket', hareketSatiri);
    // Madde 5 sertleştirmesi: senkron kuyruğu kaydı AYNI transaction
    // içinde, business data ile atomik yazılıyor — dış transaction
    // rollback olursa ikisi de birlikte geri alınır, commit olursa
    // ikisi de birlikte kalıcı olur (bkz. SyncKuyrukYazici yorumu).
    await SyncKuyrukYazici.ekleTxn(txn,
        tablo: 'stok_hareket', veri: hareketSatiri);
    final guncelUrunSatiri = await txn.query('urunler',
        where: 'id = ?', whereArgs: [urunId], limit: 1);
    if (guncelUrunSatiri.isNotEmpty) {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler',
          veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
    }
  }

  /// FAZ 5 (Lot/SKT — kullanıcı onayıyla): satış anında `lot_takibi=1`
  /// olan bir üründe stok düşümünü FEFO (First-Expired-First-Out)
  /// mantığıyla, GERÇEK lotlardan yapar — ÖNCEDEN satış hangi lotun
  /// tükendiğini hiç bilmiyordu, lot_seri.miktar sadece elle (Lot
  /// ekranından) değişiyordu.
  ///
  /// `lot_takibi=0` ürünlerde davranış BİREBİR [stokDusTxn] ile aynıdır
  /// (tek satır, lot_id yok) — geriye dönük uyumlu, mevcut çağıranlar
  /// etkilenmez çünkü bu YENİ bir metod, [stokDusTxn]'e dokunulmadı.
  ///
  /// `lot_takibi=1` ürünlerde: aktif (aktif=1, miktar>0) lotlar SKT'si en
  /// yakın olandan başlanarak (SKT'si olmayanlar en sona) tüketilir; her
  /// tüketilen lot için AYRI bir stok_hareket satırı açılır (lot_id dolu),
  /// lot_seri.miktar aynı transaction'da düşülür. Lotların toplamı satılan
  /// miktarı karşılamıyorsa (eksik lot girişi/veri tutarsızlığı) KALAN
  /// kısım lot_id=NULL ile düşülür — satış hiçbir zaman engellenmez.
  ///
  /// Dönüş: oluşturulan HER stok_hareket satırının global_id'si (çağıran
  /// bunları transaction commit sonrası tek tek buluta bildirmeli — bkz.
  /// satis_tamamlama_servisi.dart'taki kasaGlobalIdleri ile AYNI desen).
  Future<List<String>> stokDusFefoTxn(
    dynamic txn, {
    required int urunId,
    required double miktar,
    int? kullaniciId,
    int? referansId,
    String? referansTuru,
    String? aciklama,
    // Varsayılan 'Çıkış' (satış). Tedarikçiye iade 'Tedarikçi İadesi' verir.
    String? hareketTuru,
  }) async {
    final urunRows = await txn.query('urunler',
        columns: ['lot_takibi'], where: 'id = ?', whereArgs: [urunId]);
    final lotTakibi =
        urunRows.isNotEmpty && (urunRows.first['lot_takibi'] as int? ?? 0) == 1;

    if (!lotTakibi) {
      final gid = const Uuid().v4();
      await stokDusTxn(txn, gid,
          urunId: urunId,
          miktar: miktar,
          kullaniciId: kullaniciId,
          referansId: referansId,
          referansTuru: referansTuru,
          aciklama: aciklama,
          hareketTuru: hareketTuru);
      return [gid];
    }

    final lotlar = await txn.query('lot_seri',
        where: 'urun_id = ? AND aktif = 1 AND miktar > 0',
        whereArgs: [urunId],
        // SKT'si OLAN lotlar önce (en yakın SKT ilk), SKT'si olmayanlar en sona.
        orderBy: 'CASE WHEN son_kullanma_tarihi IS NULL THEN 1 ELSE 0 END, '
            'son_kullanma_tarihi ASC');

    final gidler = <String>[];
    var kalan = miktar;
    final now = DateTime.now().toIso8601String();

    for (final lot in lotlar) {
      if (kalan <= 0.005) break;
      final lotId = lot['id'] as int;
      final lotMiktar = (lot['miktar'] as num?)?.toDouble() ?? 0;
      final tuketilen = kalan < lotMiktar ? kalan : lotMiktar;
      if (tuketilen <= 0.005) continue;

      await txn.update(
          'lot_seri', {'miktar': lotMiktar - tuketilen, 'last_updated': now},
          where: 'id = ?', whereArgs: [lotId]);

      final gid = const Uuid().v4();
      await stokDusTxn(txn, gid,
          urunId: urunId,
          miktar: tuketilen,
          kullaniciId: kullaniciId,
          referansId: referansId,
          referansTuru: referansTuru,
          aciklama: aciklama,
          hareketTuru: hareketTuru,
          lotId: lotId);
      gidler.add(gid);
      kalan -= tuketilen;
    }

    // Lotların toplamı yetersizse (veri tutarsızlığı) — satışı ASLA
    // engelleme, kalan kısmı lot bilgisi olmadan düş.
    if (kalan > 0.005) {
      final gid = const Uuid().v4();
      await stokDusTxn(txn, gid,
          urunId: urunId,
          miktar: kalan,
          kullaniciId: kullaniciId,
          referansId: referansId,
          referansTuru: referansTuru,
          aciklama: aciklama == null
              ? 'Lot stoğu yetersiz kaldı'
              : '$aciklama (lot stoğu yetersiz kaldı)',
          hareketTuru: hareketTuru);
      gidler.add(gid);
    }

    return gidler;
  }

  // 🔴 DEEP_AUDIT (kendi-keşif turu, 2026-09-21): bu fonksiyon mantığını
  // stokGirTxn() ile elle kopyalayıp senkron kuyruğu yazımını
  // (SyncKuyrukYazici.ekleTxn) UNUTMUŞTU — stokDus()'un stokDusTxn()'e
  // delege ettiği AYNI desenin (bu oturumda urun_deposu.dart/stokDuzelt'e
  // uygulanan atomiklik düzeltmesiyle aynı sınıf) kardeş fonksiyonda
  // eksik kalmış hali. Artık stokGirTxn()'e delege ediyor — kuyruk kaydı
  // artık business data ile AYNI transaction'da.
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
    final hareketGid = const Uuid().v4();
    await db.transaction((txn) => stokGirTxn(txn, hareketGid,
        urunId: urunId,
        miktar: miktar,
        birimMaliyet: birimMaliyet,
        kullaniciId: kullaniciId,
        aciklama: aciklama,
        referansId: referansId,
        referansTuru: referansTuru));
    final db2 = await _d;
    final guncelUrun = await db2.query('urunler',
        where: 'id = ?', whereArgs: [urunId], limit: 1);
    if (guncelUrun.isNotEmpty) {
      BulutManager()
          .upsert('urunler', Map<String, dynamic>.from(guncelUrun.first));
    }
    final hareketSatir = await db2.query('stok_hareket',
        where: 'global_id = ?', whereArgs: [hareketGid], limit: 1);
    if (hareketSatir.isNotEmpty) {
      BulutManager().upsert(
          'stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
    }
    try {
      final subeId = AktifSubeServisi().subeId;
      if (subeId != null) await _subeUrunDeposu.stokGir(urunId, subeId, miktar);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('sube_urun güncellenemedi (ana işlem etkilenmedi): $e');
      }
    }
  }

  /// [stokGir] ile AYNI mantık, VERİLEN transaction içinde çalışır —
  /// kendi transaction'ını açmaz. BulutManager bildirimini ve sube_urun
  /// güncellemesini YAPMAZ (bkz. stokDusTxn'deki aynı not). Çağıran, dış
  /// transaction kapandıktan sonra [hareketGid] ile 'stok_hareket'
  /// satırını sorgulayıp buluta bildirebilir, ve isterse
  /// [subeStokPayiUygula] ile şube payını güncelleyebilir.
  Future<void> stokGirTxn(
    dynamic txn,
    String hareketGid, {
    required int urunId,
    required double miktar,
    double birimMaliyet = 0,
    int? kullaniciId,
    String? aciklama,
    int? referansId,
    String? referansTuru,
    // FAZ 1 madde 3 (Lot/Seri) için eklendi: varsayılan 'Giriş' — mevcut
    // TÜM çağıranlar davranışını korur. lot_seri_ekrani.dart bir lotun
    // miktarını artırdığında hareketTuru:'Lot Düzeltme', lotId:<id> geçer.
    String? hareketTuru,
    int? lotId,
  }) async {
    final now = DateTime.now().toIso8601String();
    final rows =
        await txn.query('urunler', where: 'id = ?', whereArgs: [urunId]);
    if (rows.isEmpty) return;
    final onceki = (rows.first['stok'] as num).toDouble();
    final sonraki = onceki + miktar;

    await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
        where: 'id = ?', whereArgs: [urunId]);
    final hareketSatiri = {
      'global_id': hareketGid,
      'urun_id': urunId,
      'hareket_turu': hareketTuru ?? 'Giriş',
      'miktar': miktar,
      'onceki_stok': onceki,
      'sonraki_stok': sonraki,
      'birim_maliyet': birimMaliyet,
      'tarih': now,
      'last_updated': now,
      'kullanici_id': ?kullaniciId,
      'aciklama': ?aciklama,
      'referans_id': ?referansId,
      'referans_turu': ?referansTuru,
      'lot_id': ?lotId,
    };
    await txn.insert('stok_hareket', hareketSatiri);
    // Madde 5 sertleştirmesi (bkz. stokDusTxn'deki aynı gerekçe).
    await SyncKuyrukYazici.ekleTxn(txn,
        tablo: 'stok_hareket', veri: hareketSatiri);
    final guncelUrunSatiri = await txn.query('urunler',
        where: 'id = ?', whereArgs: [urunId], limit: 1);
    if (guncelUrunSatiri.isNotEmpty) {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler',
          veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
    }
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
      if (kDebugMode) {
        debugPrint('sube_urun güncellenemedi (ana işlem etkilenmedi): $e');
      }
    }
  }

  Future<void> stokDuzelt(
      int urunId, double yeniMiktar, int kullaniciId, {String? aciklama}) async {
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
      // 🔴 DEEP_AUDIT_REPORT madde 3 (Ürün yönetimi sync-atomikliği):
      // kuyruk kaydı artık business data ile AYNI transaction'da yazılıyor
      // (bkz. UrunDeposu.guncelle'deki aynı gerekçe).
      await db.transaction((txn) async {
        final rows =
            await txn.query('urunler', where: 'id = ?', whereArgs: [urunId]);
        if (rows.isEmpty) return;
        onceki = (rows.first['stok'] as num).toDouble();

        final urunGuncelleme = {'stok': yeniMiktar, 'last_updated': now};
        await txn.update('urunler', urunGuncelleme,
            where: 'id = ?', whereArgs: [urunId]);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'urunler', veri: {...urunGuncelleme, 'id': urunId});

        final stokSatiri = {
          'global_id': hareketGid,
          'urun_id': urunId,
          'hareket_turu': 'Sayım',
          'miktar': yeniMiktar - onceki,
          'onceki_stok': onceki,
          'sonraki_stok': yeniMiktar,
          'tarih': now,
          'last_updated': now,
          'kullanici_id': kullaniciId,
          'aciklama': aciklama ?? 'Stok sayım düzeltme',
        };
        await txn.insert('stok_hareket', stokSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'stok_hareket', veri: stokSatiri);
      });
      final guncelUrun = await db.query('urunler',
          where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (guncelUrun.isNotEmpty) {
        BulutManager()
            .upsert('urunler', Map<String, dynamic>.from(guncelUrun.first));
      }
      final hareketSatir = await db.query('stok_hareket',
          where: 'global_id = ?', whereArgs: [hareketGid], limit: 1);
      if (hareketSatir.isNotEmpty) {
        BulutManager().upsert(
            'stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
      }
      // Sayım fiziksel olarak TEK bir konumda yapıldığı için fark
      // (yeni-eski) aktif şubenin payına uygulanır.
      try {
        final subeId = AktifSubeServisi().subeId;
        final fark = yeniMiktar - onceki;
        if (subeId != null && fark != 0) {
          await _subeUrunDeposu.stokGir(urunId, subeId, fark);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('sube_urun güncellenemedi (ana işlem etkilenmedi): $e');
        }
      }
    } catch (e, st) {
      LogServisi().hata('Stok.stokDuzelt', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<StokHareketModel>> hareketleriGetir(int urunId,
      {int limit = 50}) async {
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

  /// [kullaniciId] SADECE bu satırı SAYAN kişiyi kaydeder — sayımı
  /// UYGULAYAN (onaylayan) kişi DEĞİL. Madde 13 denetimi (2026-09-16):
  /// bu sütun şemada zaten VARDI ama hiç doldurulmuyordu, "kim saydı"
  /// bilgisi kayboluyordu.
  Future<void> geciciSayimEkleGuncelle(
      int urunId, double mevcutStok, double yeniStok, {int? kullaniciId}) async {
    try {
      final db = await _d;
      await db.insert(
          'gecici_sayim',
          {
            'urun_id': urunId,
            'mevcut_stok': mevcutStok,
            'yeni_stok': yeniStok,
            'kullanici_id': kullaniciId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      LogServisi().hata('Stok.geciciSayimEkleGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Sayan kullanıcının adını da döner (Madde 13 — Sayım Onay ekranı
  /// "kim saydı" göstermek için).
  Future<List<Map<String, dynamic>>> geciciSayimListesi() async {
    try {
      final db = await _d;
      return await db.rawQuery(
        'SELECT g.*, u.urun_adi, u.barkod, u.birim_adi, k.ad_soyad AS sayan_adi '
        'FROM gecici_sayim g '
        'JOIN urunler u ON g.urun_id = u.id '
        'LEFT JOIN kullanicilar k ON g.kullanici_id = k.id',
      );
    } catch (e, st) {
      LogServisi().hata('Stok.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  /// [onaylayanKullaniciId]: bekleyen sayımı UYGULAYAN (onaylayan) kişi.
  /// Madde 13 denetimi (2026-09-16): her hareketin aciklama'sına, o
  /// satırı SAYAN kişi de yazılır ("Sayan: X, Onaylayan: Y") — sayan ve
  /// onaylayan farklı kişilerse tam denetim izi (audit trail) korunur.
  Future<void> geciciSayimUygula(int onaylayanKullaniciId) async {
    try {
      final liste = await geciciSayimListesi();
      for (final row in liste) {
        final sayanAdi = row['sayan_adi'] as String?;
        final aciklama = (sayanAdi != null && sayanAdi.trim().isNotEmpty)
            ? 'Stok sayım düzeltme (Sayan: $sayanAdi)'
            : null;
        await stokDuzelt(row['urun_id'] as int,
            (row['yeni_stok'] as num).toDouble(), onaylayanKullaniciId,
            aciklama: aciklama);
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

  /// Bekleyen (onaya sunulmuş) sayımı, HİÇBİR stok değişikliği yapmadan
  /// temizler — Madde 13: yetkili sayımı reddedebilmeli.
  Future<void> geciciSayimReddet() => geciciSayimTemizle();
}
