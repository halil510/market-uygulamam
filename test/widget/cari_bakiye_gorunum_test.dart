// test/widget/cari_bakiye_gorunum_test.dart
//
// Regresyon (canlı test 2026-11-08): Tahsilat/Ödeme ekranı müşterinin bize
// borcunu (bakiye > 0) KIRMIZI, Cari Liste aynı tutarı YEŞİL gösteriyordu.
// Renk/etiket artık tek kaynakta (cariBakiyeRengi / cariBakiyeEtiketi).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/tasarim_sistemi/ts_token.dart';
import 'package:market_plus/widgetlar/ortak/cari_bakiye_gorunum.dart';

CariModel _c(String tip, double bakiye) =>
    CariModel(unvan: 'T', cariTipi: tip, bakiye: bakiye);

void main() {
  test('etiket: müşteri/tedarikçi, kısa ve uzun biçim', () {
    expect(cariBakiyeEtiketi(_c('Müşteri', 1882)), 'Alacağımız');
    expect(cariBakiyeEtiketi(_c('Müşteri', 1882), kisa: true), 'Alacak');
    expect(cariBakiyeEtiketi(_c('Müşteri', -5)), 'Fazla Ödedi');
    expect(cariBakiyeEtiketi(_c('Tedarikçi', -10)), 'Borcumuz');
    expect(cariBakiyeEtiketi(_c('Tedarikçi', -10), kisa: true), 'Borç');
    expect(cariBakiyeEtiketi(_c('Tedarikçi', 3)), 'Fazla Ödedik');
    expect(cariBakiyeEtiketi(_c('Müşteri', 0)), 'Dengede');
    expect(cariBakiyeEtiketi(_c('Hem Müşteri Hem Tedarikçi', 7), kisa: true), 'Alacak');
  });

  testWidgets('renk: müşteri alacağı yeşil, bizim borcumuz kırmızı', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(cariBakiyeRengi(ctx, _c('Müşteri', 1882)), TsRenk.basarili);
    expect(cariBakiyeRengi(ctx, _c('Müşteri', -1)), TsRenk.bilgi);
    expect(cariBakiyeRengi(ctx, _c('Tedarikçi', -1)), TsRenk.hata);
    expect(cariBakiyeRengi(ctx, _c('Tedarikçi', 1)), TsRenk.bilgi);
  });
}
