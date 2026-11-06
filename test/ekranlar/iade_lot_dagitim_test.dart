// test/ekranlar/iade_lot_dagitim_test.dart
//
// "İade → Lot geri ekleme" (FAZ 5'in devamı): fişten iade akışında
// (lib/ekranlar/satis/iade_ekrani_fis.dart, _fisKalemIade) artık
// lot_takibi=1 ürünlerde iade edilen miktar, orijinal satışın (FAZ 5
// FEFO tüketiminin bıraktığı stok_hareket.lot_id'li satırlardan) hangi
// lot(lar)dan geldiği bulunup AYNI lotlara geri ekleniyor.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN dağıtım
// algoritmasının BİREBİR kopyasını (_iadeDagilimiHesapla) çağırıyordu —
// üretim kodu bozulsa bile yeşil kalırdı. Algoritma üretimde
// IadeIslemServisi.fisKalemIadeKaydet() içinde satır içi olduğundan (ayrı
// fonksiyon değil) ve iade_islem_servisi*.dart CLAUDE.md §10 "dokunma"
// listesinde olduğundan, üretim koduna HİÇ dokunulmadı: artık GERÇEK
// fisKalemIadeKaydet() uçtan uca çağrılıyor ve dağılım, iadenin yazdığı
// stok_hareket satırlarından (lot_id, miktar) okunarak doğrulanıyor.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// GERÇEK fisKalemIadeKaydet() ile iade alır (Kart/Banka — kasa etkilenmez),
/// iadenin lotlara dağılımını yazılan stok hareketlerinden döner.
Future<List<(int?, double)>> _iadeAlVeDagilimiOku(
  Database db, {
  required int satisId,
  required int urunId,
  required double oncekiIadeMiktar,
  required double kalanMiktar,
}) async {
  final (iadeId, _, _) = await IadeIslemServisi().fisKalemIadeKaydet(
    satisId: satisId,
    cariId: null,
    urunId: urunId,
    urunAdi: 'Test Ürün',
    birimFiyat: 10,
    kalanMiktar: kalanMiktar,
    oncekiIadeMiktar: oncekiIadeMiktar,
    odemeYontemi: 'Kart/Banka',
    kullaniciId: null,
    kullaniciAdi: 'Test',
  );
  final satirlar = await db.query('stok_hareket',
      where: 'referans_id = ? AND referans_turu = ?',
      whereArgs: [iadeId, 'iade'],
      orderBy: 'id ASC');
  return satirlar
      .map((s) => (s['lot_id'] as int?, (s['miktar'] as num).toDouble()))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  /// Lot takipli ürün + [miktar] adetlik satış (satis_kalem — iade
  /// edilebilir miktar sınırı buradan hesaplanır).
  Future<(int, int)> lotluUrunVeSatis(String fisNo, double miktar) async {
    final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
    await db.update('urunler', {'lot_takibi': 1}, where: 'id = ?', whereArgs: [urunId]);
    final satisId = await db.insert('satislar',
        {'fis_no': fisNo, 'genel_toplam': miktar * 10, 'odenen_tutar': miktar * 10});
    await db.insert('satis_kalem', {
      'global_id': const Uuid().v4(),
      'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Test Ürün',
      'miktar': miktar, 'birim_fiyat': 10, 'toplam_tutar': miktar * 10,
    });
    return (urunId, satisId);
  }

  group('İade → Lot dağıtımı (fişten iade)', () {
    test('Tek lottan tüketilmiş satışın tamamı o lota geri döner', () async {
      final (urunId, satisId) = await lotluUrunVeSatis('F1', 10);
      final lotId = await db.insert('lot_seri', {'urun_id': urunId, 'miktar': 0});
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Çıkış', 'miktar': 10,
        'referans_id': satisId, 'referans_turu': 'satis', 'lot_id': lotId,
      });

      final dagilim = await _iadeAlVeDagilimiOku(db,
          satisId: satisId, urunId: urunId, oncekiIadeMiktar: 0, kalanMiktar: 10);

      expect(dagilim, [(lotId, 10.0)]);
    });

    test('İki lottan (FEFO) tüketilmiş satışın kısmi iadesi ilk (SKT\'si yakın) lottan düşer', () async {
      final (urunId, satisId) = await lotluUrunVeSatis('F2', 15);
      final lotA = await db.insert('lot_seri', {'urun_id': urunId, 'miktar': 0, 'lot_no': 'A'});
      final lotB = await db.insert('lot_seri', {'urun_id': urunId, 'miktar': 5, 'lot_no': 'B'});
      // FEFO tüketimi: 15 adet satış → Lot A'dan 10, Lot B'den 5 (stokDusFefoTxn'in ürettiği sıra).
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Çıkış', 'miktar': 10,
        'referans_id': satisId, 'referans_turu': 'satis', 'lot_id': lotA,
      });
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Çıkış', 'miktar': 5,
        'referans_id': satisId, 'referans_turu': 'satis', 'lot_id': lotB,
      });

      // 1. kısmi iade: 8 adet → tamamı Lot A'dan (A'nın 10 kapasitesi içinde).
      final ilkIade = await _iadeAlVeDagilimiOku(db,
          satisId: satisId, urunId: urunId, oncekiIadeMiktar: 0, kalanMiktar: 8);
      expect(ilkIade, [(lotA, 8.0)]);

      // 2. kısmi iade: kalan 7 adet → önceki 8 atlanır (Lot A'nın kalan 2'si + Lot B'nin 5'i).
      final ikinciIade = await _iadeAlVeDagilimiOku(db,
          satisId: satisId, urunId: urunId, oncekiIadeMiktar: 8, kalanMiktar: 7);
      expect(ikinciIade, [(lotA, 2.0), (lotB, 5.0)]);

      // Lot miktarları gerçekten geri eklendi.
      final a = (await db.query('lot_seri', where: 'id = ?', whereArgs: [lotA])).first;
      final b = (await db.query('lot_seri', where: 'id = ?', whereArgs: [lotB])).first;
      expect((a['miktar'] as num).toDouble(), 10.0);
      expect((b['miktar'] as num).toDouble(), 10.0);
    });

    test('Ledger yetersizse (ör. lot özelliğinden önceki eski satış) kalan lot_id=null ile döner', () async {
      final (urunId, satisId) = await lotluUrunVeSatis('F3', 5);
      // Bu satış için hiç stok_hareket kaydı yok (eski/lot-öncesi satış).

      final dagilim = await _iadeAlVeDagilimiOku(db,
          satisId: satisId, urunId: urunId, oncekiIadeMiktar: 0, kalanMiktar: 5);

      expect(dagilim, [(null, 5.0)]);
    });
  });
}
