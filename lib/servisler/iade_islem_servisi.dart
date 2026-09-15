// lib/servisler/iade_islem_servisi.dart
//
// İade ekranlarının (iade_ekrani.dart + part dosyaları) db.transaction()
// mantığını SCREEN→SERVICE→REPOSITORY mimarisine taşıyan servis. Her
// metod, taşındığı ekranın orijinal mantığını davranış olarak birebir
// korur — sadece sorumluluk UI katmanından buraya kaydırılmıştır.
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../depolar/kasa_deposu.dart';
import '../modeller/urun_model.dart';
import '../modeller/cari_model.dart';
import '../servisler/aktif_sube_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

/// Hızlı (barkod) iade sekmesinde biriken tek bir kalem.
class IadeKalemGirdi {
  final UrunModel urun;
  final int adet;
  const IadeKalemGirdi({required this.urun, required this.adet});
}

class IadeIslemServisi {
  final _kasaDepo = KasaDeposu();

  /// Hızlı Barkod İade sekmesindeki "Toplu iade" akışı — bkz.
  /// iade_ekrani_hizli.dart._hizliOnaylaVeKaydet (taşındığı yer).
  /// iade + tüm kalemler + stok + (varsa) kasa + (varsa) cari TEK
  /// transaction içinde: ya hep birden yazılır ya hiç.
  /// Döner: (iadeId, fisNo) — çağıran taraf ekran içi görüntüleme listesi
  /// için fişNo'ya ihtiyaç duyuyor.
  Future<(int, String)> topluIadeKaydet({
    required List<IadeKalemGirdi> kalemler,
    required bool nakitIade,
    required int? kullaniciId,
    required String kullaniciAdi,
    CariModel? cari,
  }) async {
    final db = await Veritabani().db;
    final fisNo = await Veritabani()
        .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);
    final iadeGlobalId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final toplamIade =
        kalemler.fold<double>(0.0, (s, i) => s + i.adet * i.urun.satisFiyati);
    late final int iadeId;

    await db.transaction((txn) async {
      iadeId = await txn.insert('iade', {
        'global_id': iadeGlobalId,
        'cari_id': cari?.id,
        'fis_no': fisNo,
        'tarih': now,
        'toplam_tutar': toplamIade,
        'iade_nedeni': 'Toplu iade',
        'durum': 'tamamlandi',
        'kasiyer_id': kullaniciId,
      });

      for (final item in kalemler) {
        final fiyat = item.urun.satisFiyati;
        final toplam = item.adet * fiyat;

        await txn.insert('iade_kalem', {
          'global_id': const Uuid().v4(),
          'iade_id': iadeId,
          'urun_id': item.urun.id,
          'urun_adi': item.urun.urunAdi,
          'miktar': item.adet.toDouble(),
          'birim_fiyat': fiyat,
          'toplam': toplam,
        });

        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [item.urun.id]);
        if (urunRows.isNotEmpty) {
          final onceki = (urunRows.first['stok'] as num).toDouble();
          await txn.update(
              'urunler', {'stok': onceki + item.adet, 'last_updated': now},
              where: 'id = ?', whereArgs: [item.urun.id]);
          await txn.insert('stok_hareket', {
            'global_id': const Uuid().v4(),
            'urun_id': item.urun.id,
            'hareket_turu': 'Iade Giris',
            'miktar': item.adet.toDouble(),
            'onceki_stok': onceki,
            'sonraki_stok': onceki + item.adet,
            'tarih': now,
            'referans_id': iadeId,
            'referans_turu': 'iade',
            'kullanici_id': kullaniciId,
            'aciklama': 'Toplu iade: $fisNo',
          });
        }
      }

      // Kasa — SADECE Nakit iade seçildiyse oluşturulur.
      if (nakitIade && toplamIade > 0) {
        final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) - toplamIade;
        await txn.insert('kasa_hareketleri', {
          'global_id': const Uuid().v4(),
          'hareket_tipi': 'İade',
          'tutar': toplamIade,
          'bakiye_sonrasi': kasaBakiye,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'tarih': now,
          'sube_id': AktifSubeServisi().subeId,
          'aciklama': 'Toplu iade: $fisNo',
          'kullanici_id': kullaniciId,
        });
      }

      if (cari != null && toplamIade > 0) {
        await txn.insert('cari_hareket', {
          'global_id': const Uuid().v4(),
          'cari_id': cari.id,
          'tarih': now,
          'fis_tipi': 'İade',
          'fis_id': iadeId,
          'fis_no': fisNo,
          'aciklama': 'Toplu iade: $fisNo',
          'borc': 0,
          'alacak': toplamIade,
          'odeme_turu': 'Nakit',
          'kullanici': kullaniciAdi,
        });
        // 'is_deleted = 0' filtresi — kanonik bakiye kuralı.
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
            [cari.id, cari.id]);
      }
    });

    // Transaction kalıcı olduktan sonra buluta bildir — best-effort,
    // sync hatası ana işlemi geri almaz (orijinal ekran davranışıyla aynı).
    try {
      final iadeSatir =
          await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (iadeSatir.isNotEmpty) {
        BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
      }
      for (final item in kalemler) {
        final kalemSatir = await db.query('iade_kalem',
            where: 'iade_id = ? AND urun_id = ?',
            whereArgs: [iadeId, item.urun.id],
            limit: 1);
        if (kalemSatir.isNotEmpty) {
          BulutManager().upsert(
              'iade_kalem', Map<String, dynamic>.from(kalemSatir.first));
        }
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [item.urun.id], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        final stokSatir = await db.query('stok_hareket',
            where: 'referans_id = ? AND referans_turu = ? AND urun_id = ?',
            whereArgs: [iadeId, 'iade', item.urun.id],
            orderBy: 'id DESC',
            limit: 1);
        if (stokSatir.isNotEmpty) {
          BulutManager().upsert(
              'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        }
      }
      if (toplamIade > 0) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade'],
            orderBy: 'id DESC',
            limit: 1);
        if (kasaSatir.isNotEmpty) {
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
      }
      if (cari != null && toplamIade > 0) {
        final cariHareketSatir = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi = 'İade'",
            whereArgs: [iadeId, cari.id],
            limit: 1);
        if (cariHareketSatir.isNotEmpty) {
          BulutManager().upsert(
              'cari_hareket', Map<String, dynamic>.from(cariHareketSatir.first));
        }
        final cariSatir =
            await db.query('cari', where: 'id = ?', whereArgs: [cari.id], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Toplu iade bulut bildirimi hatası: $e');
    }

    return (iadeId, fisNo);
  }
}
