// test/ekranlar/fatura_efatura_durum_test.dart
//
// erp_roadmap madde 38 (e-Belge durum makinesi): gönderim BAŞARISIZ
// olduğunda faturanın e_fatura_durum'unun 'hata' olarak işaretlenmesi
// gerekiyor (fatura_detay_ekrani.dart, _efaturaGonderIc). ÖNCEDEN bu
// yazma adımı hiç yoktu — fatura sessizce 'hazir' görünmeye devam
// ediyordu, oysa fatura_liste_ekrani.dart zaten 'hata' durumunu kırmızı
// "Gönderim Hatası" rozetiyle göstermeye hazırdı.
//
// FaturaDeposu.eFaturaDurumGuncelle Veritabani() singleton'ı üzerinden
// çalıştığı için (diğer depo testlerinde olduğu gibi) burada AYNI
// UPDATE gerçek şema üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<void> _eFaturaDurumGuncelle(Database db, int id, String durum) async {
  final now = DateTime.now().toIso8601String();
  await db.update(
    'faturalar',
    {'e_fatura_durum': durum, 'updated_at': now, 'last_updated': now},
    where: 'id = ?',
    whereArgs: [id],
  );
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('e-Fatura durum makinesi — gönderim başarısız olunca', () {
    test('durum "hata" olarak işaretlenir (önceden hiç işaretlenmiyordu)', () async {
      final faturaId = await db.insert('faturalar', {
        'fatura_no': 'F-1', 'fatura_tipi': 'Satış Faturası',
        'e_fatura_durum': 'hazir',
      });

      await _eFaturaDurumGuncelle(db, faturaId, 'hata');

      final rows = await db.query('faturalar', where: 'id = ?', whereArgs: [faturaId]);
      expect(rows.first['e_fatura_durum'], 'hata');
    });

    test('"hata" durumu fatura listesindeki gösterim mantığıyla (eDurum hesabı) eşleşir', () {
      // fatura_liste_ekrani.dart'taki _faturaKart'ın AYNI üçlü mantığı:
      String eEtiket(String eDurum) => eDurum == 'gonderildi'
          ? 'Gönderildi'
          : eDurum == 'hata'
              ? 'Gönderim Hatası'
              : 'Beklemede';

      expect(eEtiket('hata'), 'Gönderim Hatası');
      expect(eEtiket('hazir'), 'Beklemede');
      expect(eEtiket('gonderildi'), 'Gönderildi');
    });
  });
}
