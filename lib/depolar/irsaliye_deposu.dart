// lib/depolar/irsaliye_deposu.dart
//
// İrsaliye ekranının db.transaction() mantığını SCREEN→SERVICE→
// REPOSITORY mimarisine taşıyan depo. Davranış, önceden ekranın kendi
// _kaydet()'inde yürüttüğü mantıkla birebir aynıdır: irsaliye + kalemler
// + stok hareketi TEK transaction içinde, commit sonrası bulut senkronu.
import 'package:uuid/uuid.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';
import 'stok_deposu.dart';

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
  final _stokDepo = StokDeposu();

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
    final subePayiFarklari = <int, double>{};

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
          // 🔴 Derin analizde bulundu: 'Çıkış' irsaliyesinde negatif stok
          // engeli (clamp) yoktu — StokDeposu.stokDusTxn'in her zaman
          // uyguladığı `.clamp(0, double.infinity)` burada eksikti, mevcut
          // stoktan fazlası sevk edilirse urunler.stok negatife düşebiliyordu.
          final sonraki =
              (onceki + hareketMiktar).clamp(0, double.infinity);
          await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
              where: 'id = ?', whereArgs: [k.urunId]);
          etkilenenUrunIdler.add(k.urunId);
          // subeStokPayiUygula "ana stok yönü"nü pozitif=düştü olarak
          // bekliyor — hareketMiktar 'Çıkış' için negatif (stok düştü).
          subePayiFarklari[k.urunId] =
              (subePayiFarklari[k.urunId] ?? 0) - hareketMiktar;
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

    // 🔴 Derin analizde bulundu: çok şubeli stok payı (sube_urun) hiç
    // güncellenmiyordu.
    for (final girdi in subePayiFarklari.entries) {
      await _stokDepo.subeStokPayiUygula(girdi.key, girdi.value);
    }

    return irsaliyeId;
  }

  // ── Madde 2 sertleştirmesi (irsaliye_ekrani.dart — detay ekranı) ────────

  /// İrsaliye başlığını (cari/adres bilgileriyle birlikte) ve kalemlerini
  /// döner — detay ekranının açılışında kullanılır.
  Future<(Map<String, dynamic>?, List<Map<String, dynamic>>)> detayGetir(
      int irsaliyeId) async {
    final db = await Veritabani().db;
    final basRows = await db.rawQuery('''
      SELECT i.*, c.unvan as cari_adi,
        COALESCE(NULLIF(c.vergi_no, ''), c.tc_kimlik) as cari_vergi_no,
        c.vergi_dairesi as cari_vergi_dairesi,
        ca.adres as cari_adres
      FROM irsaliyeler i
      LEFT JOIN cari c ON i.cari_id = c.id
      LEFT JOIN cari_adres ca ON ca.cari_id = i.cari_id AND ca.varsayilan = 1
      WHERE i.id = ?
    ''', [irsaliyeId]);
    final kalemler = await db.rawQuery('''
      SELECT ik.*, u.urun_adi as urun_adi_db FROM irsaliye_kalem ik
      LEFT JOIN urunler u ON ik.urun_id = u.id
      WHERE ik.irsaliye_id = ?
    ''', [irsaliyeId]);
    return (basRows.isNotEmpty ? basRows.first : null, kalemler);
  }

  /// Bir cariye ait irsaliyeleri (en yeni önce) getirir — cari 360
  /// panelinin "İrsaliyeler" sekmesi için (bkz. cari_detay_paneli.dart).
  Future<List<Map<String, dynamic>>> cariIrsaliyeleriGetir(int cariId, {int limit = 50}) async {
    final db = await Veritabani().db;
    return db.rawQuery(
      "SELECT * FROM irsaliyeler WHERE cari_id = ? AND deleted_at IS NULL "
      "ORDER BY tarih DESC LIMIT ?",
      [cariId, limit],
    );
  }

  /// İrsaliye durumunu (beklemede/onaylandi/iptal vb.) günceller.
  Future<void> durumGuncelle(int irsaliyeId, String yeniDurum) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    await db.update('irsaliyeler', {'durum': yeniDurum, 'last_updated': now},
        where: 'id=?', whereArgs: [irsaliyeId]);
    await _bildir(db, irsaliyeId);
  }

  /// e-İrsaliye gönderim denemesini başlatmadan önce, daha önce
  /// reddedilmiş bir denemeyse deneme sayacını artırır ve durumu
  /// 'gonderiliyor' işaretler.
  Future<void> eIrsaliyeGonderimeHazirla(
      int irsaliyeId, {required bool oncekiReddedildi, required int mevcutDenemeNo}) async {
    final db = await Veritabani().db;
    if (oncekiReddedildi) {
      await db.update('irsaliyeler', {'e_irsaliye_deneme_no': mevcutDenemeNo + 1},
          where: 'id = ?', whereArgs: [irsaliyeId]);
    }
    await db.update('irsaliyeler', {'e_irsaliye_durum': 'gonderiliyor'},
        where: 'id = ?', whereArgs: [irsaliyeId]);
  }

  /// e-İrsaliye gönderim sonucunu (başarılı/başarısız) kaydeder.
  Future<void> eIrsaliyeSonucKaydet(
    int irsaliyeId, {
    required bool basarili,
    String? uuid,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    if (basarili) {
      await db.update('irsaliyeler', {
        'e_irsaliye_durum': 'gonderildi',
        'e_irsaliye_uuid': uuid,
        'e_irsaliye_gonderim_tarihi': now,
        'last_updated': now,
      }, where: 'id = ?', whereArgs: [irsaliyeId]);
    } else {
      await db.update('irsaliyeler', {'e_irsaliye_durum': 'hata', 'last_updated': now},
          where: 'id = ?', whereArgs: [irsaliyeId]);
    }
    await _bildir(db, irsaliyeId);
  }

  /// GİB'den sorgulanan güncel e-İrsaliye durumunu yazar.
  Future<void> eIrsaliyeDurumGuncelle(int irsaliyeId, String durum) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    await db.update('irsaliyeler', {'e_irsaliye_durum': durum, 'last_updated': now},
        where: 'id = ?', whereArgs: [irsaliyeId]);
    await _bildir(db, irsaliyeId);
  }

  Future<void> _bildir(dynamic db, int irsaliyeId) async {
    final satir = await db.query('irsaliyeler', where: 'id = ?', whereArgs: [irsaliyeId], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('irsaliyeler', Map<String, dynamic>.from(satir.first));
    }
  }
}
