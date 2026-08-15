// lib/depolar/banka_hareket_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../modeller/banka_hareket_model.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';

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
      int? id;
      await db.transaction((txn) async {
        final sonBakiye = await _sonBakiyeTxn(txn, hareket.bankaHesapId);
        final yeniBakiye = sonBakiye +
            (hareket.islemTipi == 'Gelen' ? hareket.tutar : -hareket.tutar);

        final m = hareket.toMap();
        m.remove('id');
        m['global_id'] ??= const Uuid().v4();
        m['onceki_bakiye'] = sonBakiye;
        m['sonraki_bakiye'] = yeniBakiye;

        id = await txn.insert('banka_hareketler', m);

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
      });
      // 🔴 Derin analizde bulundu: bu dosyada TEK BİR BulutManager
      // çağrısı bile yoktu — banka hareketleri ve bakiye güncellemeleri
      // sadece manuel "Buluta Gönder" ile gidiyordu, otomatik/anlık
      // senkron hiç çalışmıyordu. Transaction kapandıktan SONRA (veri
      // kalıcı olduktan sonra) her iki tablo için de bildirim gönderiliyor.
      final hareketSatir = await db.query('banka_hareketler', where: 'id = ?', whereArgs: [id], limit: 1);
      if (hareketSatir.isNotEmpty) {
        BulutManager().upsert('banka_hareketler', Map<String, dynamic>.from(hareketSatir.first));
      }
      final hesapSatir = await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hareket.bankaHesapId], limit: 1);
      if (hesapSatir.isNotEmpty) {
        BulutManager().upsert('banka_hesaplar', Map<String, dynamic>.from(hesapSatir.first));
      }
      return id!;
    } catch (e, st) {
      LogServisi().hata('BankaHareketDeposu.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<double> _sonBakiyeTxn(Transaction txn, int hesapId) async {
    final rows = await txn.rawQuery(
      'SELECT sonraki_bakiye FROM banka_hareketler '
      'WHERE banka_hesap_id = ? ORDER BY tarih DESC, id DESC LIMIT 1',
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
        whereParts.add('datetime(tarih) >= datetime(?)');
        args.add(baslangic.toIso8601String());
      }
      if (bitis != null) {
        whereParts.add('datetime(tarih) <= datetime(?)');
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
      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN islem_tipi = 'Gelen' THEN tutar ELSE 0 END), 0) as gelen,
          COALESCE(SUM(CASE WHEN islem_tipi != 'Gelen' THEN tutar ELSE 0 END), 0) as giden
        FROM banka_hareketler
        WHERE banka_hesap_id = ?
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
}
