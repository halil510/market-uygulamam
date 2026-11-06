// test/servisler/iade_olustur_cift_iade_fix_test.dart
//
// Kullanıcı kararı (2026-09-22): İade oluştururken cari seçimi (hangi
// müşterinin iade ettiğini kaydetmek için) ile ödeme yöntemi (Nakit/
// Kart) birbirinden TAMAMEN BAĞIMSIZ iki seçimdi. Kasiyer "Nakit" iade
// seçip AYRICA kayıtlı bir müşteri de seçerse, kod HEM kasadan nakit
// veriyor HEM DE müşterinin cari hesabından düşüyordu (borcu varsa
// azalıyor, yoksa "fazla ödedi" durumuna geçiyor) — aynı iade iki kere
// işlenmiş oluyordu. Kullanıcı kararı: cari seçimi SADECE "kim iade
// etti" takibi için — para her zaman nakit/kart yoluyla gerçekten geri
// veriliyor, cari_hareket kaydı artık HER ZAMAN bakiyeyi etkilemeyen
// (borc=alacak) salt-kayıt.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN
// topluIadeKaydet()'in cari_hareket yazımını kopyalayan bir yardımcı
// çağırıyordu — üretim kodu bozulsa bile yeşil kalırdı. Artık GERÇEK
// IadeIslemServisi().topluIadeKaydet() çağrılıyor. İade fiyatı gerçek
// akıştaki gibi müşterinin önceki satışından okunur; bu yüzden kurulum
// önce o ürün için bir satış yazar.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// Müşteriye [birimFiyat]'tan 1 adet satış yazar (iade fiyat dayanağı),
/// sonra GERÇEK topluIadeKaydet ile 1 adet Nakit iade alır. Dönen değer
/// iade id'si.
Future<int> _nakitIadeAl(Database db, {
  required int cariId,
  required double birimFiyat,
}) async {
  final urunId = await TestVeritabani.ornekUrunEkle(db, satisFiyati: birimFiyat);
  final satisId = await db.insert('satislar', {
    'global_id': const Uuid().v4(),
    'fis_no': 'S-$urunId',
    'tarih': DateTime.now().toIso8601String(),
    'cari_id': cariId,
    'genel_toplam': birimFiyat,
    'odenen_tutar': birimFiyat,
    'odeme_yontemi': 'Nakit',
    'is_deleted': 0,
  });
  await db.insert('satis_kalem', {
    'global_id': const Uuid().v4(),
    'satis_id': satisId,
    'urun_id': urunId,
    'urun_adi': 'Test Ürün',
    'miktar': 1,
    'birim_fiyat': birimFiyat,
    'net_fiyat': birimFiyat,
    'toplam_tutar': birimFiyat,
  });
  final urun = (await UrunDeposu().idileGetir(urunId))!;
  final cari = (await CariDeposu().idileGetir(cariId))!;
  final (iadeId, _, _) = await IadeIslemServisi().topluIadeKaydet(
    kalemler: [IadeKalemGirdi(urun: urun, adet: 1)],
    odemeYontemi: 'Nakit',
    kullaniciId: null,
    kullaniciAdi: 'Test',
    cari: cari,
  );
  return iadeId;
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

  test('Nakit iade edilip AYRICA bir müşteri seçilirse, müşterinin bakiyesi DEĞİŞMEZ (çift iade önlenir)', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    await db.update('cari', {'bakiye': 0}, where: 'id = ?', whereArgs: [cariId]);

    // Kasadan zaten 60 TL nakit verildi (bu test kasa tarafını kapsamıyor,
    // sadece cari tarafını doğruluyor) — kasiyer AYRICA müşteriyi de seçti.
    await _nakitIadeAl(db, cariId: cariId, birimFiyat: 60.0);

    final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
    expect((cari['bakiye'] as num).toDouble(), equals(0.0),
        reason: 'Nakit zaten elden verildiği için cari bakiyesi hiç etkilenmemeli');
  });

  test('cari_hareket satırı YİNE de yazılır (takip/audit için), sadece net etkisi sıfırdır', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    final iadeId = await _nakitIadeAl(db, cariId: cariId, birimFiyat: 45.0);

    final satir = (await db.query('cari_hareket', where: 'fis_id = ? AND fis_tipi = ?', whereArgs: [iadeId, 'İade'])).first;
    expect((satir['borc'] as num).toDouble(), equals(45.0));
    expect((satir['alacak'] as num).toDouble(), equals(45.0));

    // CLAUDE.md §3.2: cari hareketi aynı transaction'da senkron kuyruğuna yazılır.
    final kuyruk = await db.query('sync_queue',
        where: 'tablo_adi = ? AND kayit_global_id = ?',
        whereArgs: ['cari_hareket', satir['global_id']]);
    expect(kuyruk, isNotEmpty);
  });

  test('mevcut borcu olan bir müşteride bile Nakit+Cari birlikte seçilince borç YANLIŞLIKLA azalmaz', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    // Müşterinin önceden 200 TL veresiye borcu var.
    await db.insert('cari_hareket', {
      'global_id': const Uuid().v4(), 'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
      'fis_tipi': 'Satış', 'borc': 200.0, 'alacak': 0.0, 'odeme_turu': 'Cari',
    });
    await db.update('cari', {'bakiye': 200.0}, where: 'id = ?', whereArgs: [cariId]);

    // Müşteri bir ürünü Nakit olarak iade ediyor (60 TL elden verildi),
    // kasiyer takip için aynı müşteriyi cari olarak da seçiyor.
    await _nakitIadeAl(db, cariId: cariId, birimFiyat: 60.0);

    final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
    expect((cari['bakiye'] as num).toDouble(), equals(200.0),
        reason: 'Nakit iade ile veresiye borcu birbirinden bağımsız — borç yanlışlıkla 140\'a düşmemeli');
  });
}
