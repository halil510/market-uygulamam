// test/fatura_gib_hesap_test.dart
//
// Fatura + GİB UBL-TR hesap tutarlılığı (2026-10-03). Rastgele (sabit
// tohumlu) faturalar için ÜRETİLEN XML ayrıştırılır ve şematron'un aradığı
// toplam ilişkileri kuruşu kuruşuna doğrulanır:
//   • Σ satır LineExtensionAmount = LegalMonetaryTotal.LineExtensionAmount
//   • TaxExclusive + TaxTotal = TaxInclusive = Payable
//   • Σ TaxSubtotal.TaxAmount = TaxTotal.TaxAmount (oran grupları)
//   • Σ TaxSubtotal.TaxableAmount = matrah
//   • satır: matrah × oran ≈ KDV (±1 kuruş), PriceAmount × miktar ≈ matrah
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';
import 'package:market_plus/modeller/fatura_model.dart';
import 'package:market_plus/servisler/gib/gib_ayar_yoneticisi.dart';
import 'package:market_plus/servisler/gib/gib_ubl_olusturucu.dart';

double _t(XmlElement e, String ad) =>
    double.parse(e.findAllElements(ad).first.innerText);

GibUblOlusturucu _uretici() {
  final ayar = GibAyarYoneticisi()
    ..firmaVkn = '1234567890'
    ..firmaAdi = 'Test Market'
    ..firmaAdres = 'Adres 1'
    ..firmaVergiDairesi = 'Merkez';
  return GibUblOlusturucu(ayar);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('FaturaDetayModel.kdvDahilKalemden', () {
    test('2000 rastgele satır: matrah + KDV = KDV dahil toplam KURUŞU KURUŞUNA', () {
      final r = Random(21);
      for (var n = 0; n < 2000; n++) {
        final oran = [0.0, 1.0, 10.0, 20.0][r.nextInt(4)];
        final toplamHam = (1 + r.nextInt(2000000)) / 1000; // kuruş-altı da gelir
        final isk = r.nextBool() ? 0.0 : (r.nextInt(5000)) / 100;
        final d = FaturaDetayModel.kdvDahilKalemden(
            urunAdi: 'x', miktar: 1.5, birimFiyat: 10,
            kdvOrani: oran, kdvDahilToplam: toplamHam,
            kdvDahilIskontoTutari: isk);
        expect(ParaUtils.yuvarla(d.araToplam + d.kdvTutari), d.toplamTutar);
        expect(ParaUtils.yuvarla(d.toplamTutar), d.toplamTutar, reason: 'kuruş');
        expect(d.kdvTutari, lessThanOrEqualTo(d.toplamTutar + 1e-9));
        // iskonto KDV HARİÇ: brüt matrah = matrah + iskonto
        expect(d.iskontoTutari, lessThanOrEqualTo(isk + 1e-9));
        final matrahBeklenen = d.toplamTutar / (1 + oran / 100);
        expect((d.araToplam - matrahBeklenen).abs(), lessThanOrEqualTo(0.0051));
      }
    });

    test('örnek: 100 TL katalog, 80 TL satış, %20 KDV', () {
      final d = FaturaDetayModel.kdvDahilKalemden(
          urunAdi: 'x', miktar: 1, birimFiyat: 80, iskontoOrani: 20,
          kdvDahilIskontoTutari: 20, kdvOrani: 20, kdvDahilToplam: 80);
      expect(d.toplamTutar, 80);
      expect(d.kdvTutari, 13.33);
      expect(d.araToplam, 66.67);
      expect(d.iskontoTutari, 16.67, reason: 'iskonto KDV hariç: 20 / 1,2');
      // brüt matrah 83,33 = 66,67 + 16,67 → 100 / 1,2
      expect(d.araToplam + d.iskontoTutari, closeTo(83.34, 0.011));
    });
  });

  group('GİB UBL-TR XML toplamları', () {
    test('1500 rastgele fatura (karışık KDV, eski/yuvarlanmamış veri dahil)', () async {
      final r = Random(99);
      final olusturucu = _uretici();
      for (var n = 0; n < 1500; n++) {
        final satirSayisi = 1 + r.nextInt(7);
        final detaylar = <FaturaDetayModel>[];
        for (var i = 0; i < satirSayisi; i++) {
          final oran = [0.0, 1.0, 10.0, 20.0][r.nextInt(4)];
          final toplam = (1 + r.nextInt(500000)) / 100;
          final kdv = ParaUtils.kdvPayiCikar(toplam, oran);
          // %30: ESKİ yuvarlanmamış kayıt gibi (kuruş-altı kalıntılı)
          final eski = r.nextInt(10) < 3;
          detaylar.add(FaturaDetayModel(
            urunAdi: 'Ürün $i', miktar: [1.0, 2.0, 3.0, 0.5][r.nextInt(4)],
            birimFiyat: toplam, kdvOrani: oran,
            kdvTutari: eski ? kdv : ParaUtils.yuvarla(kdv),
            araToplam: eski ? toplam - kdv : ParaUtils.yuvarla(toplam - kdv),
            toplamTutar: toplam,
          ));
        }
        final fatura = FaturaModel(
          faturaNo: 'TST2026${n.toString().padLeft(9, '0')}',
          tarih: DateTime(2026, 10, 3),
          cariUnvan: 'Müşteri', cariVergiNo: '1234567890',
          detaylar: detaylar,
          // saklı başlık toplamı BİLEREK 1 kuruş yanlış (eski/bozuk veri)
          genelToplam: detaylar.fold<double>(0, (t, d) => t + d.toplamTutar) + 0.01,
          toplamKdv: detaylar.fold<double>(0, (t, d) => t + d.kdvTutari),
        );
        final xml = await olusturucu.ublXmlOlustur(fatura: fatura, ettn: 'ettn-$n');
        final doc = XmlDocument.parse(xml);
        final kok = doc.rootElement;

        final lmt = kok.findAllElements('cac:LegalMonetaryTotal').first;
        final lineExt = _t(lmt, 'cbc:LineExtensionAmount');
        final taxExcl = _t(lmt, 'cbc:TaxExclusiveAmount');
        final taxIncl = _t(lmt, 'cbc:TaxInclusiveAmount');
        final payable = _t(lmt, 'cbc:PayableAmount');

        // Başlık TaxTotal: doğrudan Invoice çocuğu olan
        final basTax = kok.children
            .whereType<XmlElement>()
            .firstWhere((e) => e.name.qualified == 'cac:TaxTotal');
        final basKdv = _t(basTax, 'cbc:TaxAmount');
        final altlar = basTax.findElements('cac:TaxSubtotal').toList();
        final altKdv = altlar.fold<double>(0, (t, e) => t + _t(e, 'cbc:TaxAmount'));
        final altMatrah = altlar.fold<double>(0, (t, e) => t + _t(e, 'cbc:TaxableAmount'));

        final satirlar = kok.findAllElements('cac:InvoiceLine').toList();
        final satirToplami = satirlar.fold<double>(
            0, (t, e) => t + _t(e, 'cbc:LineExtensionAmount'));
        final satirKdv = satirlar.fold<double>(0, (t, e) {
          final tt = e.findElements('cac:TaxTotal').first;
          return t + _t(tt, 'cbc:TaxAmount');
        });

        expect(satirToplami, closeTo(lineExt, 0.0001), reason: 'Σ satır ≠ LineExtension (fatura $n)');
        expect(lineExt, taxExcl);
        expect(taxExcl + basKdv, closeTo(taxIncl, 0.0001), reason: 'TaxExcl + Tax ≠ TaxIncl (fatura $n)');
        expect(taxIncl, payable);
        expect(altKdv, closeTo(basKdv, 0.0001), reason: 'Σ oran grubu KDV ≠ toplam KDV (fatura $n)');
        expect(altMatrah, closeTo(lineExt, 0.0001), reason: 'Σ oran grubu matrah ≠ matrah (fatura $n)');
        expect(satirKdv, closeTo(basKdv, 0.0001), reason: 'Σ satır KDV ≠ başlık KDV (fatura $n)');

        // Satır içi tutarlılık
        for (final s in satirlar) {
          final tt = s.findElements('cac:TaxTotal').first;
          final alt = tt.findElements('cac:TaxSubtotal').first;
          final matrah = _t(alt, 'cbc:TaxableAmount');
          final kdv = _t(alt, 'cbc:TaxAmount');
          final oran = double.parse(alt.findElements('cbc:Percent').first.innerText);
          expect((matrah * oran / 100 - kdv).abs(), lessThanOrEqualTo(0.0101),
              reason: 'satır KDV oranı tutmuyor (fatura $n)');
          final miktar = double.parse(s.findElements('cbc:InvoicedQuantity').first.innerText);
          final fiyat = _t(s, 'cbc:PriceAmount');
          expect((fiyat * miktar - matrah).abs(), lessThanOrEqualTo(0.011),
              reason: 'PriceAmount × miktar ≠ LineExtension (fatura $n)');
        }
      }
    });

    test('tek oranlı fatura: oran grubu sayısı = 1; karışık: farklı oran sayısı kadar', () async {
      FaturaDetayModel d(double oran, double toplam) =>
          FaturaDetayModel.kdvDahilKalemden(
              urunAdi: 'x', miktar: 1, birimFiyat: toplam,
              kdvOrani: oran, kdvDahilToplam: toplam);
      final olusturucu = _uretici();
      Future<int> grupSayisi(List<FaturaDetayModel> l) async {
        final f = FaturaModel(
            faturaNo: 'T1', tarih: DateTime(2026, 10, 3),
            cariUnvan: 'x', cariVergiNo: '1234567890', detaylar: l);
        final kok = XmlDocument.parse(await olusturucu.ublXmlOlustur(fatura: f, ettn: 'e'))
            .rootElement;
        return kok.children
            .whereType<XmlElement>()
            .firstWhere((e) => e.name.qualified == 'cac:TaxTotal')
            .findElements('cac:TaxSubtotal')
            .length;
      }

      expect(await grupSayisi([d(20, 120), d(20, 60)]), 1);
      expect(await grupSayisi([d(1, 101), d(10, 110), d(20, 120), d(20, 12)]), 3);
    });
  });
}
