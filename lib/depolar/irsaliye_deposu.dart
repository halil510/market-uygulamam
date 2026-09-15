// lib/depolar/irsaliye_deposu.dart
//
// İrsaliye ekranının db.transaction() mantığını SCREEN→SERVICE→
// REPOSITORY mimarisine taşıyan depo. Davranış, önceden ekranın kendi
// _kaydet()'inde yürüttüğü mantıkla birebir aynıdır: irsaliye + kalemler
// + stok hareketi TEK transaction içinde, commit sonrası bulut senkronu.
import 'package:uuid/uuid.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

/// Bir irsaliye kaleminin DB yazımı için gereken minimal bilgisi.
class IrsaliyeKalemGirdi {
  final int urunId;
  final String urunAdi;
  final double miktar;
  final double birimFiyat;
  const IrsaliyeKalemGirdi({
    required this.urunId,
    required this.urunAdi,
    required this.miktar,
    required this.birimFiyat,
  });
}

class IrsaliyeDeposu {
  /// Bekleyen Sipariş onaylandıktan SONRA (satış zaten oluşturulmuş,
  /// stok ZATEN düşürülmüş — bkz. BekleyenSiparisDeposu.onaylaVeSatisaCevir)
  /// kayıt amaçlı sevk belgesi oluşturur. [olustur]'un aksine STOĞA HİÇ
  /// DOKUNMAZ (aksi halde stok iki kez düşerdi) ve bulut senkronu
  /// tetiklemez — davranış, taşındığı
  /// bekleyen_siparisler_ekrani.dart._irsaliyeOlustur ile birebir aynı.
  ///
  /// Döner: yeni irsaliyenin id'si.
  Future<int> olusturSevkKaydi({
    required List<IrsaliyeKalemGirdi> kalemler,
    required int? cariId,
    required int? kullaniciId,
    required String irsaliyeNo,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    final toplam = kalemler.fold(0.0, (s, k) => s + k.miktar * k.birimFiyat);
    late int irsaliyeId;

    await db.transaction((txn) async {
      irsaliyeId = await txn.insert('irsaliyeler', {
        'global_id': const Uuid().v4(),
        'irsaliye_no': irsaliyeNo,
        'cari_id': cariId,
        'tarih': now,
        'tip': 'Çıkış',
        'toplam_tutar': toplam,
        'durum': 'Hazırlanıyor',
        'kullanici_id': kullaniciId,
        'created_at': now,
        'last_updated': now,
      });
      for (final k in kalemler) {
        await txn.insert('irsaliye_kalem', {
          'global_id': const Uuid().v4(),
          'irsaliye_id': irsaliyeId,
          'urun_id': k.urunId,
          'urun_adi': k.urunAdi,
          'miktar': k.miktar,
          'birim_fiyat': k.birimFiyat,
          'toplam_tutar': k.miktar * k.birimFiyat,
          'last_updated': now,
        });
      }
    });

    return irsaliyeId;
  }

  /// [tip]: 'Çıkış' | 'Giriş' | 'Transfer' — 'Çıkış' stoktan düşer,
  /// diğerleri stoğa ekler (davranış ekranla birebir aynı).
  ///
  /// Döner: yeni irsaliyenin id'si.
  Future<int> olustur({
    required List<IrsaliyeKalemGirdi> kalemler,
    required int? cariId,
    required DateTime tarih,
    required String tip,
    required String irsaliyeNo,
    required int? kullaniciId,
  }) async {
    final db = await Veritabani().db;
    final toplam = kalemler.fold(0.0, (s, k) => s + k.miktar * k.birimFiyat);
    final now = DateTime.now().toIso8601String();
    final irsaliyeGid = const Uuid().v4();
    late int irsaliyeId;
    final kalemGidler = <String>[];
    final stokHareketGidler = <String>[];
    final etkilenenUrunIdler = <int>{};

    await db.transaction((txn) async {
      irsaliyeId = await txn.insert('irsaliyeler', {
        'global_id': irsaliyeGid,
        'irsaliye_no': irsaliyeNo,
        'cari_id': cariId,
        'tarih': tarih.toIso8601String(),
        'tip': tip,
        'toplam_tutar': toplam,
        'durum': 'Hazırlanıyor',
        'kullanici_id': kullaniciId,
        'created_at': now,
        'last_updated': now,
      });
      for (final k in kalemler) {
        final kalemGid = const Uuid().v4();
        kalemGidler.add(kalemGid);
        await txn.insert('irsaliye_kalem', {
          'global_id': kalemGid,
          'irsaliye_id': irsaliyeId,
          'urun_id': k.urunId,
          'urun_adi': k.urunAdi,
          'miktar': k.miktar,
          'birim_fiyat': k.birimFiyat,
          'toplam_tutar': k.miktar * k.birimFiyat,
          'last_updated': now,
        });
        final hareketMiktar = tip == 'Çıkış' ? -k.miktar : k.miktar;
        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [k.urunId]);
        if (urunRows.isNotEmpty) {
          final onceki = (urunRows.first['stok'] as num).toDouble();
          final sonraki = onceki + hareketMiktar;
          await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
              where: 'id = ?', whereArgs: [k.urunId]);
          etkilenenUrunIdler.add(k.urunId);
          final stokGid = const Uuid().v4();
          stokHareketGidler.add(stokGid);
          await txn.insert('stok_hareket', {
            'global_id': stokGid,
            'urun_id': k.urunId,
            'hareket_turu': 'İrsaliye $tip',
            'miktar': k.miktar,
            'onceki_stok': onceki,
            'sonraki_stok': sonraki,
            'tarih': now,
            'last_updated': now,
            'referans_id': irsaliyeId,
            'referans_turu': 'irsaliye',
          });
        }
      }
    });

    // Transaction kapandıktan (veri kalıcı olduktan) sonra buluta bildir.
    try {
      final irsSatir = await db.query('irsaliyeler',
          where: 'id = ?', whereArgs: [irsaliyeId], limit: 1);
      if (irsSatir.isNotEmpty) {
        BulutManager()
            .upsert('irsaliyeler', Map<String, dynamic>.from(irsSatir.first));
      }
      for (final gid in kalemGidler) {
        final s = await db.query('irsaliye_kalem',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager()
              .upsert('irsaliye_kalem', Map<String, dynamic>.from(s.first));
        }
      }
      for (final urunId in etkilenenUrunIdler) {
        final s = await db.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (s.isNotEmpty) {
          BulutManager().upsert('urunler', Map<String, dynamic>.from(s.first));
        }
      }
      for (final gid in stokHareketGidler) {
        final s = await db.query('stok_hareket',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager()
              .upsert('stok_hareket', Map<String, dynamic>.from(s.first));
        }
      }
    } catch (_) {
      // Bulut bildirimi hatası asıl işlemi engellemez — orijinal ekran
      // davranışıyla aynı (sessizce yutulur).
    }

    return irsaliyeId;
  }
}
