// test/servisler/iade_excel_iskonto_test.dart
//
// Kullanıcı bulgusu: "excelden içe alırken iskonto var ama o alınmamış".
// Fiyat sütunları (Fiyat / Net Fiyat / Kdv li fiyat) kaynak programa göre
// indirimli de indirimsiz de gelebilir; çözümleyici birbirleriyle
// karşılaştırıp doğru brüt/indirimli birim fiyatı ve indirim oranını verir.
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/excel_servisi.dart';

void main() {
  double? n(({double brut, double indirimli})? r, bool brut) =>
      r == null ? null : (brut ? r.brut : r.indirimli);

  group('iadeFiyatCoz', () {
    test('indirimli "Kdv li fiyat" + Net Fiyat tutarlı → brüt geri hesaplanır', () {
      final r = ExcelServisiIadeGunsonu.iadeFiyatCoz(
          fiyat: 100, netFiyat: 90, kdvliFiyat: 108, kdvOran: 20, iskontoOran: 10);
      expect(n(r, true), closeTo(120, 0.001));
      expect(n(r, false), closeTo(108, 0.001));
    });

    test('"Kdv li fiyat" İNDİRİMSİZ (brüt) gelmişse indirim UYGULANIR (asıl hata)', () {
      final r = ExcelServisiIadeGunsonu.iadeFiyatCoz(
          fiyat: 100, netFiyat: 90, kdvliFiyat: 120, kdvOran: 20, iskontoOran: 10);
      expect(n(r, true), closeTo(120, 0.001));
      expect(n(r, false), closeTo(108, 0.001), reason: '120 × %10 indirim = 108');
    });

    test('yalnız "Kdv li fiyat" + indirim: ödenecek fiyat kabul edilir (çifte indirim yok)', () {
      final r = ExcelServisiIadeGunsonu.iadeFiyatCoz(kdvliFiyat: 108, kdvOran: 20, iskontoOran: 10);
      expect(n(r, false), closeTo(108, 0.001));
      expect(n(r, true), closeTo(120, 0.001));
    });

    test('yalnız Fiyat (KDV hariç) + indirim', () {
      final r = ExcelServisiIadeGunsonu.iadeFiyatCoz(fiyat: 100, kdvOran: 20, iskontoOran: 25);
      expect(n(r, true), closeTo(120, 0.001));
      expect(n(r, false), closeTo(90, 0.001));
    });

    test('Fiyat zaten Net Fiyat ile aynıysa (indirimli gelmiş) brüte çevrilir', () {
      final r = ExcelServisiIadeGunsonu.iadeFiyatCoz(
          fiyat: 90, netFiyat: 90, kdvOran: 20, iskontoOran: 10);
      expect(n(r, true), closeTo(120, 0.001));
      expect(n(r, false), closeTo(108, 0.001));
    });

    test('indirim yok: eski davranış korunur', () {
      final r = ExcelServisiIadeGunsonu.iadeFiyatCoz(
          fiyat: 19.8019801980198, netFiyat: 19.8019801980198, kdvliFiyat: 20, kdvOran: 1, iskontoOran: 0);
      expect(n(r, true), 20);
      expect(n(r, false), 20);
    });

    test('hiç fiyat yok → null (ürün kartı fiyatı kullanılır)', () {
      expect(ExcelServisiIadeGunsonu.iadeFiyatCoz(kdvOran: 20, iskontoOran: 10), isNull);
      expect(ExcelServisiIadeGunsonu.iadeFiyatCoz(kdvOran: 20, iskontoOran: 0), isNull);
    });

    test('geçersiz indirim (%100+) yok sayılır', () {
      final r = ExcelServisiIadeGunsonu.iadeFiyatCoz(kdvliFiyat: 50, kdvOran: 0, iskontoOran: 100);
      expect(n(r, false), 50);
    });
  });

  group('iadeExcelIceAl (gerçek .xlsx)', () {
    Uint8List xlsx(List<List<CellValue?>> satirlar) {
      final excel = Excel.createExcel();
      final sheet = excel['Sayfa1'];
      excel.delete('Sheet1');
      for (final s in satirlar) {
        sheet.appendRow(s);
      }
      return Uint8List.fromList(excel.encode()!);
    }

    TextCellValue t(String s) => TextCellValue(s);
    DoubleCellValue d(double v) => DoubleCellValue(v);

    final baslik = [
      t('Kod'), t('Barkod'), t('Ürün Adı'), t('Miktar'), t('Fiyat'), t('Tutarı'),
      t('Net Fiyat'), t('Kdv li fiyat'), t('Indirim (%)'), t('İndirim'), t('Kdv (%)'),
    ];

    test('indirim oranı okunur, brüt ve indirimli fiyat ayrı döner', () async {
      final rows = await ExcelServisi().iadeExcelIceAl(xlsx([
        baslik,
        // %10 indirim, Kdv li fiyat brüt (120) gelmiş
        [t('A1'), t('869'), t('Ürün A'), d(2), d(100), d(200), d(90), d(120), d(10), d(20), d(20)],
        // indirim %'si boş ama İndirim tutarı var: 12 / 100 → %12
        [t('B1'), t('870'), t('Ürün B'), d(1), d(100), d(100), null, d(120), null, d(12), d(20)],
        // indirimsiz
        [t('C1'), t('871'), t('Ürün C'), d(3), d(10), d(30), d(10), d(12), d(0), d(0), d(20)],
      ]));
      expect(rows.length, 3);
      expect(rows[0]['iskonto_oran'], 10);
      expect((rows[0]['brut_fiyat'] as double), closeTo(120, 0.001));
      expect((rows[0]['birim_fiyat'] as double), closeTo(108, 0.001));
      expect((rows[1]['iskonto_oran'] as double), closeTo(12, 0.001));
      expect(rows[2]['iskonto_oran'], 0);
      expect((rows[2]['birim_fiyat'] as double), closeTo(12, 0.001));
    });
  });
}
