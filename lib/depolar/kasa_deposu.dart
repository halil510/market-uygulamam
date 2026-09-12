import '../servisler/bulut/bulut_manager.dart'; // sync hook
// lib/depolar/kasa_deposu.dart ✅ GELİŞTİRİLDİ - nakit/kart ayrımı, vardiya desteği
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../veri/database/veritabani.dart';
import '../modeller/kasa_hareket_model.dart';
import '../servisler/aktif_sube_servisi.dart';

class KasaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> hareketEkle(KasaHareketModel h) async {
    try {
      final db = await _d;
      final kid = await db.transaction((txn) => hareketEkleTxn(txn, h));
      // 🔴 KRİTİK REGRESYON DÜZELTMESİ: hareketEkle() daha önceki bir
      // turda hareketEkleTxn()'e bölünürken, transaction bittikten
      // sonraki BulutManager bildirimi YANLIŞLIKLA eklenmemişti — bu
      // fonksiyonun kullanıldığı HER YER (tahsilat, ödeme, vardiya
      // açma/kapama, uygulamadaki neredeyse tüm kasa hareketi giriş
      // noktası) o zamandan beri buluta hiç senkron olmuyordu.
      final satir = await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [kid], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('kasa_hareketleri', Map<String, dynamic>.from(satir.first));
      return kid;
    } catch (e, st) {
      LogServisi().hata('Kasa.hareketEkle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// [hareketEkle] ile AYNI mantık, ama VERİLEN transaction içinde çalışır
  /// — kendi transaction'ını açmaz. Birden çok tabloyu (satış/iade akışı
  /// gibi) TEK atomik transaction'da güncellemek isteyen çağıranlar için.
  /// 🔴 ÖNEMLİ: BulutManager bildirimini BURADA YAPMAZ — dış transaction
  /// henüz commit olmamışken buluta göndermek, transaction sonradan
  /// (başka bir adımda hata olursa) geri alınırsa buluta VAR OLMAYAN bir
  /// satırı senkronlamış olur. Bildirim, çağıranın transaction'ı
  /// kapandıktan SONRA kendi sorumluluğundadır (bkz. çağrı noktaları).
  Future<int> hareketEkleTxn(dynamic txn, KasaHareketModel h) async {
    final sonBakiye = await _sonBakiyeTxn(txn);
    final girisler = KasaHareketModel.girisTipleri; // merkezi kaynak
    final yeniBakiye = girisler.contains(h.hareketTipi)
        ? sonBakiye + h.tutar
        : sonBakiye - h.tutar;
    final hm = h.toMap();
    hm.remove('id');
    // 🔴 Derin analizde bulundu: KasaHareketModel'de global_id alanı
    // hiç yoktu — bu modelle eklenen HER kasa hareketi kimliksiz
    // (global_id=NULL) gidiyordu, bulutta düzgün eşleşmiyordu.
    hm['global_id'] ??= const Uuid().v4();
    hm['sube_id'] ??= AktifSubeServisi().subeId;
    hm['bakiye_sonrasi'] = yeniBakiye;
    return await txn.insert('kasa_hareketleri', hm);
  }

  /// Verilen transaction içinde en son kasa bakiyesini döndürür.
  /// Herkese açık — İade Düzeltme gibi doğrudan 'kasa_hareketleri'ne
  /// yazan başka ekranlar da bakiye_sonrasi'nı DOĞRU hesaplayabilsin
  /// diye (önceden bazı yerler bunu atlayıp NULL bırakıyordu).
  Future<double> sonBakiyeTxn(dynamic txn) => _sonBakiyeTxn(txn);

  Future<double> _sonBakiyeTxn(dynamic txn) async {
    try {
      final rows = await txn.rawQuery(
        'SELECT bakiye_sonrasi FROM kasa_hareketleri WHERE deleted_at IS NULL ORDER BY tarih DESC, id DESC LIMIT 1',
      );
      if (rows.isEmpty) return 0;
      return (rows.first['bakiye_sonrasi'] as num?)?.toDouble() ?? 0;
    } catch (e, st) {
      LogServisi().hata('Kasa._sonBakiyeTxn', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<double> guncelBakiye() async {
    try {
      final db = await _d;
      return _sonBakiyeTxn(db);
    } catch (e, st) {
      LogServisi().hata('Kasa.guncelBakiye', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<KasaHareketModel>> hareketleriniGetir({
    int limit = 100,
    DateTime? baslangic,
    DateTime? bitis,
    String? hareketTipi,
  }) async {
    final db = await _d;
    final whereParts = <String>[];
    final args = <dynamic>[];

    if (baslangic != null) {
      whereParts.add('datetime(tarih) >= datetime(?)');
      args.add(baslangic.toIso8601String());
    }
    if (bitis != null) {
      whereParts.add('datetime(tarih) <= datetime(?)');
      args.add(bitis.toIso8601String());
    }
    if (hareketTipi != null) {
      whereParts.add('hareket_tipi = ?');
      args.add(hareketTipi);
    }
    // ÖNCEDEN BURADA HİÇ ŞUBE FİLTRESİ YOKTU — birden fazla şubeniz
    // varsa TÜM şubelerin kasa hareketleri karışık gösteriliyordu.
    // Artık aktif şube seçiliyse (Tüm Şubeler modunda değilse) sadece
    // o şubenin hareketleri getiriliyor.
    if (AktifSubeServisi().subeId != null) {
      whereParts.add('sube_id = ?');
      args.add(AktifSubeServisi().subeId);
    }

    final where = whereParts.isEmpty ? null : whereParts.join(' AND ');
    final rows = await db.query(
      'kasa_hareketleri',
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'tarih DESC, id DESC',
      limit: limit,
    );
    return rows.map(KasaHareketModel.fromMap).toList();
  }

  /// ✅ GELİŞTİRİLDİ: Nakit/Kart/Tahsilat ayrımlı günlük özet
  Future<Map<String, double>> gunlukOzet() async {
    try {
      final db = await _d;
      // ÖNCEDEN şube filtresi yoktu — birden fazla şubeniz varsa
      // Dashboard'daki günlük özet TÜM şubelerin toplamını gösteriyordu.
      final subeId = AktifSubeServisi().subeId;
      final subeKosulu = subeId != null ? 'AND sube_id = ?' : '';
      final subeArgs = subeId != null ? [subeId] : <Object?>[];
      // 🔴 Derin analizde bulundu: bu SQL'deki giriş tipleri listesi,
      // merkezi KasaHareketModel.girisTipleri'nin EKSİK bir kopyasıydı
      // ('Iade Iptali','İade İptali','Ödeme Girişi' unutulmuştu) — bu
      // hareket tipleri günlük özet toplamına hiç dahil edilmiyordu.
      final res = await db.rawQuery("""
        SELECT 
          COALESCE(SUM(CASE WHEN hareket_tipi IN ('Satış','Tahsilat','AçılışKasa','Giriş','Virman Giriş','Iade Iptali','İade İptali','Ödeme Girişi') THEN tutar ELSE 0 END), 0) as giris,
          COALESCE(SUM(CASE WHEN hareket_tipi IN ('Gider','Ödeme','KapanışKasa') THEN tutar ELSE 0 END), 0) as cikis,
          COALESCE(SUM(CASE WHEN hareket_tipi = 'Satış' AND referans_turu = 'satis' THEN tutar ELSE 0 END), 0) as nakit_satis,
          COALESCE(SUM(CASE WHEN hareket_tipi = 'Tahsilat' THEN tutar ELSE 0 END), 0) as tahsilat
        FROM kasa_hareketleri 
        // 🔴 KRİTİK DÜZELTME (derin analiz — gün sonu raporu / kasa özeti):
      // SQLite'ın DATE('now') fonksiyonu VARSAYILAN OLARAK UTC kullanır.
      // Ama `tarih` sütunu DateTime.now().toIso8601String() ile YEREL
      // saatle yazılıyor (satis_model.dart, gider_model.dart, kasa
      // hareketleri — hepsi aynı desen).
      //
      // Türkiye UTC+3 olduğu için, YEREL saatle 00:00–03:00 arasında
      // (yani UTC henüz bir önceki güne ait sayılırken) yapılan HER
      // satış/gider/kasa hareketi bu sorgudan DÜŞÜYORDU:
      //
      //   Yerel 01:00 (27 Tem) → tarih sütunu: '2026-07-27T01:00:00'
      //   O ANDA UTC saati     : 26 Tem 22:00 → DATE('now') = '2026-07-26'
      //   DATE(tarih)='2026-07-27' ≠ DATE('now')='2026-07-26' → KAYIP
      //
      // 24 saat açık ya da gece geç saatlere çalışan bir markette, gece
      // yarısından sonraki 3 saatlik satışlar "Gün Sonu Raporu"na hiç
      // girmiyordu. 'localtime' değiştiricisi SQLite'a cihazın kendi
      // saat dilimini kullanmasını söyler — POS cihazı zaten işletmenin
      // kendi lokasyonunda olduğu için bu doğru varsayımdır.
        WHERE DATE(tarih) = DATE('now','localtime') AND deleted_at IS NULL $subeKosulu
      """, subeArgs);
      if (res.isEmpty) return {'giris': 0, 'cikis': 0};
      final r = res.first;
      return {
        'giris': (r['giris'] as num?)?.toDouble() ?? 0,
        'cikis': (r['cikis'] as num?)?.toDouble() ?? 0,
        'nakit_satis': (r['nakit_satis'] as num?)?.toDouble() ?? 0,
        'kart_satis': 0, // Kart satışları kasa kaydı değil, ayrı takip
        'tahsilat': (r['tahsilat'] as num?)?.toDouble() ?? 0,
      };
    } catch (e, st) {
      LogServisi().hata('Kasa.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<Map<String, double>> aralikOzet(DateTime bas, DateTime bit) async {
    try {
      final db = await _d;
      // 🔴 Derin analizde bulundu: aynı eksik kopya burada da vardı.
      final res = await db.rawQuery("""
        SELECT 
          COALESCE(SUM(CASE WHEN hareket_tipi IN ('Satış','Tahsilat','AçılışKasa','Giriş','Virman Giriş','Iade Iptali','İade İptali','Ödeme Girişi') THEN tutar ELSE 0 END), 0) as giris,
          COALESCE(SUM(CASE WHEN hareket_tipi IN ('Gider','Ödeme','KapanışKasa') THEN tutar ELSE 0 END), 0) as cikis
        FROM kasa_hareketleri 
        WHERE datetime(tarih) BETWEEN datetime(?) AND datetime(?) AND deleted_at IS NULL
      """, [bas.toIso8601String(), bit.toIso8601String()]);
      if (res.isEmpty) return {'giris': 0, 'cikis': 0};
      final r = res.first;
      return {
        'giris': (r['giris'] as num?)?.toDouble() ?? 0,
        'cikis': (r['cikis'] as num?)?.toDouble() ?? 0,
      };
    } catch (e, st) {
      LogServisi().hata('Kasa.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> hareketSil(int id) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final etkilenenIdler = <int>[];
      await db.transaction((txn) async {
        // 🔴🔴 ÖNEMLİ DÜZELTME: Önceden GERÇEK (hard) silme
        // kullanılıyordu — diğer tüm tablolardaki soft-delete
        // deseninin aksine. Artık tablonun zaten sahip olduğu
        // 'deleted_at' sütunuyla soft-delete yapılıyor.
        await txn.update('kasa_hareketleri',
            {'deleted_at': now, 'last_updated': now},
            where: 'id = ?', whereArgs: [id]);
        etkilenenIdler.add(id);

        // Sonraki bakiyeleri yeniden hesapla (silinenler hariç)
        final rows = await txn.query('kasa_hareketleri',
            where: 'deleted_at IS NULL', orderBy: 'tarih ASC, id ASC');
        double bakiye = 0;
        final girisler = KasaHareketModel.girisTipleri; // merkezi kaynak
        for (final r in rows) {
          final tip = r['hareket_tipi'] as String? ?? '';
          final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
          bakiye = girisler.contains(tip) ? bakiye + tutar : bakiye - tutar;
          // 🔴🔴 ÖNEMLİ DÜZELTME 2: Bu döngü, bir silme sonrası TÜM
          // sonraki kayıtların bakiyesini yeniden hesaplıyor —
          // potansiyel olarak YÜZLERCE kayıt. Önceden last_updated
          // HİÇ bümlenmiyordu.
          await txn.update('kasa_hareketleri',
              {'bakiye_sonrasi': bakiye, 'last_updated': now},
              where: 'id = ?', whereArgs: [r['id']]);
          etkilenenIdler.add(r['id'] as int);
        }
      });
      for (final eid in etkilenenIdler) {
        final satir = await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [eid], limit: 1);
        if (satir.isNotEmpty) {
          BulutManager().upsert('kasa_hareketleri', Map<String, dynamic>.from(satir.first));
        }
      }
    } catch (e, st) {
      LogServisi().hata('Kasa.hareketSil', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Veri Sağlığı Merkezi (protokol §10/§13): 'bakiye_sonrasi' sütununu
  /// baştan yeniden hesaplayıp gerçek değerden sapan varsa düzeltir —
  /// hareketSil()'deki aynı, kanıtlanmış yeniden-hesaplama algoritması.
  Future<int> bakiyeMutabakatYap() async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      var duzeltilen = 0;
      final duzeltilenIdler = <int>[];
      await db.transaction((txn) async {
        final rows = await txn.query('kasa_hareketleri',
            where: 'deleted_at IS NULL', orderBy: 'tarih ASC, id ASC');
        double bakiye = 0;
        final girisler = KasaHareketModel.girisTipleri;
        for (final r in rows) {
          final tip = r['hareket_tipi'] as String? ?? '';
          final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
          bakiye = girisler.contains(tip) ? bakiye + tutar : bakiye - tutar;
          final mevcut = (r['bakiye_sonrasi'] as num?)?.toDouble();
          if (mevcut == null || (mevcut - bakiye).abs() > 0.01) {
            await txn.update('kasa_hareketleri',
                {'bakiye_sonrasi': bakiye, 'last_updated': now},
                where: 'id = ?', whereArgs: [r['id']]);
            duzeltilen++;
            duzeltilenIdler.add(r['id'] as int);
          }
        }
      });
      for (final id in duzeltilenIdler) {
        final satir = await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [id], limit: 1);
        if (satir.isNotEmpty) BulutManager().upsert('kasa_hareketleri', Map<String, dynamic>.from(satir.first));
      }
      return duzeltilen;
    } catch (e, st) {
      LogServisi().hata('Kasa.bakiyeMutabakatYap', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Sadece SAYIYI döner, düzeltme yapmaz (bkz. [bakiyeMutabakatYap]).
  Future<int> bakiyeUyumsuzlukSayisi() async {
    try {
      final db = await _d;
      final rows = await db.query('kasa_hareketleri',
          where: 'deleted_at IS NULL', orderBy: 'tarih ASC, id ASC');
      double bakiye = 0;
      var uyumsuz = 0;
      final girisler = KasaHareketModel.girisTipleri;
      for (final r in rows) {
        final tip = r['hareket_tipi'] as String? ?? '';
        final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
        bakiye = girisler.contains(tip) ? bakiye + tutar : bakiye - tutar;
        final mevcut = (r['bakiye_sonrasi'] as num?)?.toDouble();
        if (mevcut == null || (mevcut - bakiye).abs() > 0.01) uyumsuz++;
      }
      return uyumsuz;
    } catch (e, st) {
      LogServisi().hata('Kasa.bakiyeUyumsuzlukSayisi', hata: e, yigin: st);
      return 0;
    }
  }
}
