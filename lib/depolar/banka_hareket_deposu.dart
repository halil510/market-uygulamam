// lib/depolar/banka_hareket_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../modeller/banka_hareket_model.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import 'package:uuid/uuid.dart';
import '../cekirdek/utils/tarih_utils.dart';
import '../cekirdek/utils/para_utils.dart';

/// NOT: Hesap bakiyesi güncellemesi BURADA, uygulama kodu seviyesinde
/// yapılır (transaction güvenliği ve test edilebilirlik için).
/// DİKKAT: veritabanında ayrıca `trg_banka_hareket_bakiye` adlı bir
/// trigger da AYNI işi yapıyordu (migrasyon_yonetici.dart, v16→v17).
/// İkisi birlikte çalışınca sonuç yanlış olmaz (trigger da SELECT ile
/// son sonraki_bakiye'yi okuyup yazdığından idempotent), ama gereksiz
/// çift güncelleme ve mimari karmaşa yaratıyordu. Trigger'ın migrasyon
/// dosyasından kaldırılması önerilir — tek doğruluk kaynağı bu sınıf olsun.
class BankaHareketDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(BankaHareketModel hareket) async {
    final db = await _d;
    try {
      final id = await db.transaction((txn) => ekleTxn(txn, hareket));
      // 🔴 Derin analizde bulundu: bu dosyada TEK BİR BulutManager
      // çağrısı bile yoktu — banka hareketleri ve bakiye güncellemeleri
      // sadece manuel "Buluta Gönder" ile gidiyordu, otomatik/anlık
      // senkron hiç çalışmıyordu. Transaction kapandıktan SONRA (veri
      // kalıcı olduktan sonra) her iki tablo için de bildirim gönderiliyor.
      await BulutManager().satiriBildir(db, 'banka_hareketler', id);
      await BulutManager().satiriBildir(db, 'banka_hesaplar', hareket.bankaHesapId);
      return id;
    } catch (e, st) {
      LogServisi().hata('BankaHareketDeposu.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// [ekle] ile aynı mantık, VERİLEN transaction içinde çalışır — kendi
  /// transaction'ını açmaz. BulutManager bildirimini BURADA YAPMAZ (bkz.
  /// KasaDeposu.hareketEkleTxn'deki aynı gerekçe): çağıranın transaction'ı
  /// kapandıktan sonra kendi sorumluluğundadır.
  Future<int> ekleTxn(Transaction txn, BankaHareketModel hareket) async {
    final sonBakiye = await _sonBakiyeTxn(txn, hareket.bankaHesapId);
    final yeniBakiye = sonBakiye + isaretliTutar(hareket.islemTipi, hareket.tutar);

    final m = hareket.toMap();
    m.remove('id');
    m['global_id'] ??= const Uuid().v4();
    m['onceki_bakiye'] = sonBakiye;
    m['sonraki_bakiye'] = yeniBakiye;

    final id = await txn.insert('banka_hareketler', m);
    // Madde 5 sertleştirmesi: senkron kuyruğu kaydı business data ile
    // AYNI transaction içinde, atomik olarak yazılıyor (bkz.
    // SyncKuyrukYazici yorumu).
    await SyncKuyrukYazici.ekleTxn(txn,
        tablo: 'banka_hareketler', veri: {...m, 'id': id});

    await txn.update(
      'banka_hesaplar',
      {
        'bakiye': yeniBakiye,
        // Bu uygulamada "bloke/rezerve tutar" kavramı henüz yok — bu
        // yüzden kullanılabilir bakiye her zaman gerçek bakiyeyle
        // aynı tutulur. Önceden bu alan HİÇ güncellenmiyordu, hesap
        // oluşturulduğu andaki (genelde 0) değerde donup kalıyordu.
        'kullanilabilir_bakiye': yeniBakiye,
        'last_updated': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [hareket.bankaHesapId],
    );
    final guncelHesapSatiri = await txn.query('banka_hesaplar',
        where: 'id = ?', whereArgs: [hareket.bankaHesapId], limit: 1);
    if (guncelHesapSatiri.isNotEmpty) {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'banka_hesaplar',
          veri: Map<String, dynamic>.from(guncelHesapSatiri.first));
    }
    return id;
  }

  Future<double> _sonBakiyeTxn(Transaction txn, int hesapId) async {
    // 🔴 Derin analizde bulundu: KasaDeposu._sonBakiyeTxn ve tüm cari
    // bakiye sorgularının aksine burada 'is_deleted = 0' filtresi yoktu —
    // buluttan bir tombstone (silinmiş kayıt) senkronize olursa, yeni bir
    // yerel işlem yanlışlıkla silinmiş bir satırın bakiyesi üzerinden
    // zincire devam edebilirdi.
    final rows = await txn.rawQuery(
      'SELECT sonraki_bakiye FROM banka_hareketler '
      'WHERE banka_hesap_id = ? AND is_deleted = 0 ORDER BY tarih DESC, id DESC LIMIT 1',
      [hesapId],
    );
    if (rows.isEmpty) {
      final hesap = await txn.query('banka_hesaplar',
          columns: ['bakiye'], where: 'id = ?', whereArgs: [hesapId]);
      return hesap.isNotEmpty
          ? (hesap.first['bakiye'] as num?)?.toDouble() ?? 0
          : 0;
    }
    return (rows.first['sonraki_bakiye'] as num?)?.toDouble() ?? 0;
  }

  Future<List<BankaHareketModel>> hareketleriGetir({
    int? hesapId,
    int? krediKartiId,
    DateTime? baslangic,
    DateTime? bitis,
    int limit = 50,
  }) async {
    try {
      final db = await _d;
      final whereParts = <String>[];
      final args = <dynamic>[];

      if (hesapId != null) {
        whereParts.add('banka_hesap_id = ?');
        args.add(hesapId);
      }
      if (krediKartiId != null) {
        whereParts.add('kredi_karti_id = ?');
        args.add(krediKartiId);
      }
      if (baslangic != null) {
        whereParts.add(TarihUtils.sonrasiSql('tarih', baslangic));
        args.add(baslangic.toIso8601String());
      }
      if (bitis != null) {
        whereParts.add(TarihUtils.oncesiSql('tarih', bitis));
        args.add(bitis.toIso8601String());
      }

      final where = whereParts.isEmpty ? null : whereParts.join(' AND ');
      final rows = await db.query(
        'banka_hareketler',
        where: where,
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'tarih DESC, id DESC',
        limit: limit,
      );
      var sonuc = rows.map(BankaHareketModel.fromMap).toList();

      // 🔥 ÖNCEDEN BURADA "kredi_karti_hareket" tablosu HİÇ
      // SORGULANMIYORDU — bu yüzden bir kredi kartına yapılan
      // ödeme/harcama işlemleri "Hareketler" ekranında HİÇ
      // GÖRÜNMÜYORDU (limit doğru güncelleniyordu ama görüntüleme
      // tarafı bundan habersizdi, çünkü kredi kartının illa bağlı bir
      // banka HESABI olması gerekmiyor — "banka_hareketler" tablosu
      // bunu zorunlu kılıyor). Artık kredi kartı ID'si verildiğinde
      // kendi hareket tablosundan da veri çekilip birleştiriliyor.
      if (krediKartiId != null) {
        final kkRows = await db.query('kredi_karti_hareket',
            where: 'kredi_karti_id = ? AND is_deleted = 0',
            whereArgs: [krediKartiId],
            orderBy: 'tarih DESC, id DESC',
            limit: limit);
        final kkHareketler = kkRows.map((h) => BankaHareketModel(
              id: h['id'] as int?,
              bankaHesapId: 0, // kredi kartı hareketi — banka hesabına bağlı değil
              krediKartiId: krediKartiId,
              islemTipi: (h['yon'] as String?) == 'odeme' ? 'Gelen' : 'Giden',
              tutar: (h['tutar'] as num).toDouble(),
              aciklama: h['aciklama'] as String?,
              tarih: DateTime.tryParse(h['tarih'] as String? ?? '') ?? DateTime.now(),
            )).toList();
        sonuc = [...sonuc, ...kkHareketler];
        sonuc.sort((a, b) => b.tarih.compareTo(a.tarih));
        if (sonuc.length > limit) sonuc = sonuc.sublist(0, limit);
      }

      return sonuc;
    } catch (e, st) {
      LogServisi().hata('BankaHareketDeposu.hareketleriGetir', hata: e, yigin: st);
      return [];
    }
  }

  Future<Map<String, double>> ozetGetir(int hesapId) async {
    try {
      final db = await _d;
      // 🔴 DEEP_AUDIT_REPORT madde 10: is_deleted filtresi eksikti — bu
      // özet, silinmiş (ör. virman/gider iptal edilmiş) hareketleri de
      // toplama dahil ediyordu, gelen/giden diğer sorgulardan (hareketleri
      // Getir, bakiye zinciri) daha yüksek görünebiliyordu.
      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN islem_tipi = 'Gelen' THEN tutar ELSE 0 END), 0) as gelen,
          COALESCE(SUM(CASE WHEN islem_tipi != 'Gelen' THEN tutar ELSE 0 END), 0) as giden
        FROM banka_hareketler
        WHERE banka_hesap_id = ? AND is_deleted = 0
      ''', [hesapId]);
      if (rows.isEmpty) return {'gelen': 0, 'giden': 0};
      return {
        'gelen': (rows.first['gelen'] as num?)?.toDouble() ?? 0,
        'giden': (rows.first['giden'] as num?)?.toDouble() ?? 0,
      };
    } catch (e, st) {
      LogServisi().hata('BankaHareketDeposu.ozetGetir', hata: e, yigin: st);
      return {'gelen': 0, 'giden': 0};
    }
  }

  /// Hareketin bakiyeye etkisi — [ekleTxn] ile AYNI kural (tek kaynak).
  static double isaretliTutar(String? islemTipi, double tutar) =>
      islemTipi == 'Gelen' ? tutar : -tutar;

  /// Her hesabın hareket zincirini (tarih, id sırasıyla) baştan yürütür:
  /// onceki/sonraki_bakiye ve hesabın bakiyesi hareketlerden yeniden
  /// hesaplanır. Açılış = en eski hareketin onceki_bakiye'si.
  ///
  /// 🔴 ÇOKLU CİHAZ (2026-11-08): bakiye "son hareketin sonraki_bakiye'si"
  /// zinciriyle tutuluyor. İki cihaz internetsizken aynı hesaba hareket
  /// yazınca ikisi de kendi zincirini sürdürüyordu: 1000'lik hesaba biri
  /// +100, diğeri −50 yazınca birleşmeden sonra bakiye 1050 yerine 950
  /// görünüyordu ve senkron sonrası hiçbir adım düzeltmiyordu. Sıra
  /// cihazdan cihaza farklı olsa da son bakiye (açılış + Σ) her cihazda
  /// aynıdır. Hareket satırlarının bakiye alanları türetilmiştir —
  /// last_updated ilerletilmez (bkz. KolonHaritalama.turetilmisAlanlar).
  /// Döner: düzeltilen satır + hesap sayısı.
  Future<int> zincirMutabakatYap() async {
    try {
      final db = await _d;
      final duzeltilenHesaplar = <int>[];
      var duzeltilenSatir = 0;
      await db.transaction((txn) async {
        final hesaplar = await txn.rawQuery(
            'SELECT DISTINCT banka_hesap_id AS id FROM banka_hareketler '
            'WHERE banka_hesap_id IS NOT NULL AND is_deleted = 0');
        for (final h in hesaplar) {
          final hesapId = h['id'] as int;
          final satirlar = await txn.query('banka_hareketler',
              columns: ['id', 'islem_tipi', 'tutar', 'onceki_bakiye', 'sonraki_bakiye'],
              where: 'banka_hesap_id = ? AND is_deleted = 0',
              whereArgs: [hesapId],
              orderBy: 'tarih ASC, id ASC');
          var bakiye = (satirlar.first['onceki_bakiye'] as num?)?.toDouble() ?? 0;
          for (final s in satirlar) {
            final onceki = bakiye;
            final sonraki = ParaUtils.yuvarla(onceki +
                isaretliTutar(s['islem_tipi'] as String?,
                    (s['tutar'] as num?)?.toDouble() ?? 0));
            final eskiOnceki = (s['onceki_bakiye'] as num?)?.toDouble();
            final eskiSonraki = (s['sonraki_bakiye'] as num?)?.toDouble();
            if (eskiOnceki == null || eskiSonraki == null ||
                (eskiOnceki - onceki).abs() > 0.005 ||
                (eskiSonraki - sonraki).abs() > 0.005) {
              await txn.update('banka_hareketler',
                  {'onceki_bakiye': onceki, 'sonraki_bakiye': sonraki},
                  where: 'id = ?', whereArgs: [s['id']]);
              duzeltilenSatir++;
            }
            bakiye = sonraki;
          }
          final hesap = await txn.query('banka_hesaplar',
              columns: ['bakiye'], where: 'id = ?', whereArgs: [hesapId], limit: 1);
          if (hesap.isEmpty) continue;
          final mevcut = (hesap.first['bakiye'] as num?)?.toDouble() ?? 0;
          if ((mevcut - bakiye).abs() > 0.005) {
            await txn.update('banka_hesaplar', {
              'bakiye': bakiye,
              'kullanilabilir_bakiye': bakiye,
              'last_updated': DateTime.now().toIso8601String(),
            }, where: 'id = ?', whereArgs: [hesapId]);
            duzeltilenHesaplar.add(hesapId);
          }
        }
      });
      for (final id in duzeltilenHesaplar) {
        await BulutManager().satiriBildir(db, 'banka_hesaplar', id);
      }
      if (duzeltilenSatir + duzeltilenHesaplar.length > 0) {
        LogServisi().bilgi('Banka zincir mutabakatı: $duzeltilenSatir hareket, '
            '${duzeltilenHesaplar.length} hesap düzeltildi');
      }
      return duzeltilenSatir + duzeltilenHesaplar.length;
    } catch (e, st) {
      LogServisi().hata('BankaHareketDeposu.zincirMutabakatYap', hata: e, yigin: st);
      rethrow;
    }
  }
}
