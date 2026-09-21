// test/veri/excel_toplu_ekle_hatalar_test.dart
//
// Kendi-keşif turu (Excel modülü denetimi): UrunDeposu.
// topluEkleGuncelle() ÖNCEDEN bir satır transaction içinde hata
// verince (ör. mükerrer barkod → ConflictAlgorithm.abort) bu satırı
// sadece LogServisi'ne yazıp SESSİZCE atlıyordu — dönen
// {'eklenen','guncellenen'} sayıları bu başarısızlığı hiç
// YANSITMIYORDU. Kullanıcı "480 eklendi, 5 hatalı" görürken aslında
// başka satırlar da sessizce kaybolmuş olabiliyordu. Artık başarısız
// satırlar da 'hatalar' listesiyle döndürülüyor (ExcelServisi bunu
// IceriAktarSonuc.hatalar'a ekliyor).
//
// UrunDeposu.topluEkleGuncelle() Veritabani() singleton'ı üzerinden
// çalıştığı için (diğer depo testlerindeki AYNI gerekçe), burada
// BİREBİR AYNI satır-başına-transaction + hata-toplama mantığı gerçek
// şema üzerinde doğrudan doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

/// UrunDeposu.topluEkleGuncelle()'nin catch-bloğu davranışıyla BİREBİR
/// AYNI: her satır kendi transaction'ında denenir, hata verirse
/// atlanır AMA artık 'hatalar' listesine de kaydedilir.
Future<Map<String, dynamic>> _topluEkleGuncelle(
    Database db, List<Map<String, dynamic>> satirlar) async {
  var eklenen = 0;
  final basarisizSatirlar = <String>[];
  for (final s in satirlar) {
    try {
      await db.transaction((txn) async {
        await txn.insert('urunler', s, conflictAlgorithm: ConflictAlgorithm.abort);
      });
      eklenen++;
    } catch (e) {
      final barkod = s['barkod'] as String?;
      final tanimlayici = (barkod?.isNotEmpty ?? false)
          ? barkod!
          : (s['urun_adi'] as String? ?? '?');
      basarisizSatirlar.add('$tanimlayici: $e');
    }
  }
  return {'eklenen': eklenen, 'guncellenen': 0, 'hatalar': basarisizSatirlar};
}

Map<String, dynamic> _urunSatiri(String barkod, {String ad = 'Test Ürün'}) => {
      'urun_adi': ad,
      'barkod': barkod,
      'satis_fiyati': 100.0,
      'alis_fiyat': 80.0,
      'stok': 10.0,
      'birim_adi': 'Adet',
      'kdv_oran': '20',
      'aktif': 1,
      'is_deleted': 0,
    };

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  test('mükerrer barkodlu bir satır transaction içinde hata verince '
      'artık SESSİZCE kaybolmuyor — hatalar listesine düşüyor', () async {
    final satirlar = [
      _urunSatiri('8690000000001', ad: 'Ürün A'),
      _urunSatiri('8690000000001', ad: 'Ürün B (mükerrer barkod)'),
      _urunSatiri('8690000000002', ad: 'Ürün C'),
    ];

    final sonuc = await _topluEkleGuncelle(db, satirlar);

    expect(sonuc['eklenen'], 2,
        reason: 'sadece 2 satır GERÇEKTEN eklenebildi (biri çakıştı)');
    final hatalar = sonuc['hatalar'] as List<String>;
    expect(hatalar.length, 1,
        reason: 'ÖNCEDEN bu satır hiçbir yerde görünmezdi — artık görünüyor');
    expect(hatalar.first, contains('8690000000001'));

    final tumUrunler = await db.query('urunler');
    expect(tumUrunler.length, 2,
        reason: 'diğer satırlar etkilenmemeli (per-satır izolasyon korunur)');
  });

  test('hiçbir çakışma yoksa hatalar listesi boş döner', () async {
    final satirlar = [
      _urunSatiri('8690000000010'),
      _urunSatiri('8690000000011'),
    ];
    final sonuc = await _topluEkleGuncelle(db, satirlar);
    expect(sonuc['eklenen'], 2);
    expect(sonuc['hatalar'], isEmpty);
  });
}
