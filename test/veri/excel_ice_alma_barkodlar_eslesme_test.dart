// test/veri/excel_ice_alma_barkodlar_eslesme_test.dart
//
// Kullanıcı bulgusu (devamı): stokSayimExcelIceAl / promosyonExcelIceAl
// gibi Excel içe alma akışlarındaki "bu barkod/kod zaten kayıtlı mı"
// eşleştirme sorguları da (arama kutularıyla AYNI şekilde) sadece
// 'barkod' sütununu kontrol ediyordu, alternatif barkodları
// ('barkodlar' — virgülle ayrılmış) hiç görmüyordu. Excel sayım/
// promosyon dosyasında bir ürünün ALTERNATİF barkodu yazılıysa, ürün
// "bulunamadı" sayılıp satır sessizce atlanıyordu.
//
// Bu sorgular TAM/kesin bir kod eşleştirmesi olduğundan (metin arama
// kutusu değil), UrunDeposu.barkodlaGetir() ile AYNI sıkı virgül-
// sınırlı desen kullanıldı — serbest LIKE '%kod%' yanlış pozitif
// üretebilirdi (ör. "12" kodu "5123" içinde eşleşirdi).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<Map<String, dynamic>?> _eslesenUrunuBul(String kod) async {
    final rows = await db.rawQuery(
      "SELECT id, stok FROM urunler"
      " WHERE (barkod=? OR (',' || barkodlar || ',') LIKE ? OR kod=?)"
      "   AND is_deleted=0 LIMIT 1",
      [kod, '%,$kod,%', kod],
    );
    return rows.isEmpty ? null : rows.first;
  }

  test('Excel satırındaki kod SADECE alternatif barkodlar\'da varsa '
      'artık ürün bulunuyor (önceden "bulunamadı" sayılıp satır atlanıyordu)',
      () async {
    final urunId = await db.insert('urunler', {
      'urun_adi': 'Kola 1L', 'barkod': '8690000000001',
      'barkodlar': '8690000000099,8690000000098',
      'satis_fiyati': 100.0, 'stok': 5.0, 'birim_adi': 'Adet',
      'kdv_oran': '20', 'aktif': 1, 'is_deleted': 0,
    });

    final bulunan = await _eslesenUrunuBul('8690000000099');
    expect(bulunan, isNotNull);
    expect(bulunan!['id'], urunId);
  });

  test('kısmi/alt-string eşleşme YANLIŞ POZİTİF üretmiyor (sıkı virgül '
      'sınırlı desen)', () async {
    await db.insert('urunler', {
      'urun_adi': 'Ürün A', 'barkod': '999',
      'barkodlar': '5123456789',
      'satis_fiyati': 10.0, 'stok': 1.0, 'birim_adi': 'Adet',
      'kdv_oran': '20', 'aktif': 1, 'is_deleted': 0,
    });

    // "123" kodu "5123456789" İÇİNDE geçiyor ama AYRI bir barkod DEĞİL
    // — serbest LIKE ile yanlışlıkla eşleşirdi, virgül-sınırlı desen
    // eşleşmemeli.
    final bulunan = await _eslesenUrunuBul('123');
    expect(bulunan, isNull);
  });

  test('primer barkod ve kod eşleşmesi BOZULMADI (geriye dönük uyumluluk)',
      () async {
    final urunId = await db.insert('urunler', {
      'urun_adi': 'Ürün B', 'barkod': '8690000000002', 'kod': 'SKU-002',
      'satis_fiyati': 50.0, 'stok': 2.0, 'birim_adi': 'Adet',
      'kdv_oran': '20', 'aktif': 1, 'is_deleted': 0,
    });

    expect((await _eslesenUrunuBul('8690000000002'))!['id'], urunId);
    expect((await _eslesenUrunuBul('SKU-002'))!['id'], urunId);
  });
}
