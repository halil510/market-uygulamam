// lib/depolar/tedarikci_siparis_deposu.dart
//
// Tedarikçi Siparişi Oluştur ekranının db.transaction() mantığını
// SCREEN→SERVICE→REPOSITORY mimarisine taşıyan depo. Davranış, önceden
// ekranın kendi _siparisKaydet()'inde yürüttüğü mantıkla birebir aynıdır:
// 'beklemede' sipariş + kalemler TEK transaction içinde (stok/kasa/cari
// HİÇ ETKİLENMEZ — gerçek mal kabul AlimEkrani'nda ayrıca yapılır),
// commit sonrası bulut senkronu.
import 'package:uuid/uuid.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

/// Bir sipariş kaleminin DB yazımı için gereken minimal bilgisi.
class TedarikciSiparisKalemGirdi {
  final int urunId;
  final double miktar;
  final double birimFiyat;
  const TedarikciSiparisKalemGirdi({
    required this.urunId,
    required this.miktar,
    required this.birimFiyat,
  });
}

class TedarikciSiparisDeposu {
  /// Döner: yeni siparişin id'si.
  Future<int> olustur({
    required int tedarikciId,
    required String tedarikciUnvan,
    required List<TedarikciSiparisKalemGirdi> kalemler,
    required double genelToplam,
    required String siparisNo,
    required int? olusturanId,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    final siparisGid = const Uuid().v4();
    late int siparisId;
    final kalemGidler = <String>[];

    await db.transaction((txn) async {
      siparisId = await txn.insert('tedarikci_siparisler', {
        'global_id': siparisGid,
        'cari_id': tedarikciId,
        'siparis_no': siparisNo,
        'siparis_tarihi': now,
        'toplam_tutar': genelToplam,
        'durum': 'beklemede',
        'notlar': 'Sipariş: $tedarikciUnvan',
        'olusturan_id': olusturanId,
        'last_updated': now,
      });
      for (final k in kalemler) {
        final kalemGid = const Uuid().v4();
        kalemGidler.add(kalemGid);
        await txn.insert('tedarikci_siparis_kalem', {
          'global_id': kalemGid,
          'siparis_id': siparisId,
          'urun_id': k.urunId,
          'siparis_mik': k.miktar,
          'teslim_mik': 0,
          'birim_fiyat': k.birimFiyat,
          'kdv_oran': 0,
          'toplam_tutar': k.miktar * k.birimFiyat,
          'last_updated': now,
        });
      }
    });

    try {
      final siparisSatir = await db.query('tedarikci_siparisler',
          where: 'id = ?', whereArgs: [siparisId], limit: 1);
      if (siparisSatir.isNotEmpty) {
        BulutManager().upsert(
            'tedarikci_siparisler', Map<String, dynamic>.from(siparisSatir.first));
      }
      for (final gid in kalemGidler) {
        final s = await db.query('tedarikci_siparis_kalem',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager().upsert(
              'tedarikci_siparis_kalem', Map<String, dynamic>.from(s.first));
        }
      }
    } catch (_) {
      // Bulut bildirimi hatası asıl işlemi engellemez — orijinal ekran
      // davranışıyla aynı (sessizce yutulur).
    }

    return siparisId;
  }

  // ── Madde 2 sertleştirmesi (tedarik_siparis_ekrani.dart) ────────────────

  /// Belirli durumdaki siparişleri (tedarikçi unvanıyla birlikte) döner.
  Future<List<Map<String, dynamic>>> durumaGoreListele(String durum) async {
    final db = await Veritabani().db;
    return db.rawQuery(
      'SELECT ts.*, c.unvan as tedarikci_adi '
      'FROM tedarikci_siparisler ts '
      'LEFT JOIN cari c ON ts.cari_id = c.id '
      'WHERE ts.durum = ? '
      'ORDER BY ts.siparis_tarihi DESC',
      [durum],
    );
  }

  /// Bir siparişin ham kalemlerini döner (teslim alma akışı için).
  Future<List<Map<String, dynamic>>> kalemleriGetir(int siparisId) async {
    final db = await Veritabani().db;
    return db.rawQuery(
      'SELECT * FROM tedarikci_siparis_kalem WHERE siparis_id = ?',
      [siparisId],
    );
  }

  /// Bir siparişin kalemlerini ürün adı/birimiyle birlikte döner (detay
  /// paneli için).
  Future<List<Map<String, dynamic>>> kalemleriDetayliGetir(int siparisId) async {
    final db = await Veritabani().db;
    return db.rawQuery(
      'SELECT tsk.*, u.urun_adi, u.birim_adi '
      'FROM tedarikci_siparis_kalem tsk '
      'LEFT JOIN urunler u ON tsk.urun_id = u.id '
      'WHERE tsk.siparis_id = ?',
      [siparisId],
    );
  }

  /// Sipariş durumunu günceller (beklemede/teslim_alindi/iptal).
  Future<void> durumGuncelle(int siparisId, String yeniDurum) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    await db.update('tedarikci_siparisler',
        {'durum': yeniDurum, 'last_updated': now},
        where: 'id = ?', whereArgs: [siparisId]);
    final satir = await db.query('tedarikci_siparisler',
        where: 'id = ?', whereArgs: [siparisId], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert(
          'tedarikci_siparisler', Map<String, dynamic>.from(satir.first));
    }
  }
}
