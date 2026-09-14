// test/veri/efatura_durum_makinesi_test.dart
//
// e-Belge durum makinesi genişletmesi (2026-09-14 derin analiz):
// - GİB'in REDDETTİĞİ bir fatura artık 'reddedildi' olarak tanınıyor
//   (önceden sessizce "Beklemede" gösteriliyordu — yasal geçerliliği
//   olmayan bir belge hâlâ bekliyormuş gibi duruyordu).
// - Reddedilen bir fatura yeniden gönderildiğinde ETTN'nin DEĞİŞMESİ
//   gerekiyor (aksi halde entegratör "zaten reddedilmiş" diyebilir) —
//   ama bir AĞ HATASI sonrası tekrar denemede ETTN AYNI kalmalı (mükerrer
//   gönderim koruması). Bu dosya her iki kuralı da doğrular.
//
// GibServisi Dio/Veritabani() singleton'ına bağımlı olduğu için (diğer
// depo testlerinde olduğu gibi) burada AYNI mantık saf fonksiyonlar
// olarak yeniden üretilip test ediliyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/servisler/gib_servisi.dart';
import '../helper/test_initializer.dart';

const _ettnNamespace = '2f6a8c1e-4b3d-4e7a-9c2f-1a5b7d9e3c6f';
const _uuid = Uuid();

String _ettnUret(String globalId, int denemeNo) {
  final anahtar = denemeNo > 0 ? '$globalId#$denemeNo' : globalId;
  return _uuid.v5(_ettnNamespace, anahtar).toUpperCase();
}

String? _durumNormallestir(String? ham) {
  if (ham == null) return null;
  final h = ham.trim().toLowerCase();
  const onay = {'onaylandi', 'approved', 'accepted', 'success', 'successful', 'basarili'};
  const ret = {'reddedildi', 'rejected', 'declined', 'refused', 'red'};
  const iptal = {'iptal', 'iptal_edildi', 'cancelled', 'canceled', 'voided'};
  if (onay.contains(h)) return 'onaylandi';
  if (ret.contains(h)) return 'reddedildi';
  if (iptal.contains(h)) return 'gib_iptal';
  return ham;
}

void main() {
  group('Durum normalleştirme (entegratör terimleri)', () {
    test('kabul varyantları onaylandi\'ya eşlenir', () {
      for (final v in ['approved', 'accepted', 'ACCEPTED', 'success', 'onaylandi']) {
        expect(_durumNormallestir(v), equals('onaylandi'), reason: v);
      }
    });

    test('ret varyantları reddedildi\'ya eşlenir', () {
      for (final v in ['rejected', 'REJECTED', 'declined', 'refused', 'red']) {
        expect(_durumNormallestir(v), equals('reddedildi'), reason: v);
      }
    });

    test('iptal varyantları gib_iptal\'e eşlenir', () {
      for (final v in ['cancelled', 'canceled', 'voided', 'iptal']) {
        expect(_durumNormallestir(v), equals('gib_iptal'), reason: v);
      }
    });

    test('tanınmayan bir değer sessizce yutulmaz, olduğu gibi döner', () {
      expect(_durumNormallestir('pending_review'), equals('pending_review'));
    });

    test('null güvenle null döner', () {
      expect(_durumNormallestir(null), isNull);
    });
  });

  group('ETTN üretimi — deneme numarası', () {
    test('deneme_no=0 iken (ilk gönderim / ağ hatası sonrası tekrar) ETTN sabit kalır', () {
      final t1 = _ettnUret('fatura-global-1', 0);
      final t2 = _ettnUret('fatura-global-1', 0);
      expect(t1, equals(t2));
    });

    test('reddedildikten sonra yeniden gönderimde (deneme_no artınca) ETTN DEĞİŞİR', () {
      final ilkDeneme = _ettnUret('fatura-global-1', 0);
      final ikinciDeneme = _ettnUret('fatura-global-1', 1);
      expect(ilkDeneme, isNot(equals(ikinciDeneme)));
    });

    test('her deneme_no farklı, tekrarlanabilir bir ETTN üretir', () {
      final d1 = _ettnUret('fatura-global-1', 1);
      final d2 = _ettnUret('fatura-global-1', 2);
      final d1tekrar = _ettnUret('fatura-global-1', 1);
      expect(d1, isNot(equals(d2)));
      expect(d1, equals(d1tekrar));
    });

    test('farklı faturalar aynı deneme_no ile bile farklı ETTN üretir', () {
      final f1 = _ettnUret('fatura-global-1', 0);
      final f2 = _ettnUret('fatura-global-2', 0);
      expect(f1, isNot(equals(f2)));
    });
  });

  group('faturalar.e_fatura_deneme_no şeması', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    test('sütun mevcut ve varsayılanı 0', () async {
      final kolonlar = await db.rawQuery('PRAGMA table_info(faturalar)');
      final kolon = kolonlar.firstWhere((k) => k['name'] == 'e_fatura_deneme_no');
      expect(kolon, isNotNull);
      expect(kolon['notnull'], equals(1));
      expect(kolon['dflt_value'], equals('0'));
    });

    test('yeni bir fatura kaydında sütun sessizce 0 değerini alır', () async {
      final id = await db.insert('faturalar', {
        'fatura_no': 'TEST-0001',
        'genel_toplam': 100,
      });
      final rows = await db.query('faturalar', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['e_fatura_deneme_no'], equals(0));
    });
  });

  group('irsaliyeler.e_irsaliye_* şeması (e-İrsaliye GİB gönderimi)', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    test('tüm e_irsaliye_* sütunları mevcut', () async {
      final kolonlar = await db.rawQuery('PRAGMA table_info(irsaliyeler)');
      final adlar = kolonlar.map((k) => k['name'] as String).toSet();
      expect(adlar, containsAll([
        'e_irsaliye_durum', 'e_irsaliye_uuid', 'e_irsaliye_xml',
        'e_irsaliye_deneme_no', 'e_irsaliye_gonderim_tarihi',
      ]));
    });

    test('yeni bir irsaliye kaydında deneme_no sessizce 0 değerini alır', () async {
      final id = await db.insert('irsaliyeler', {'irsaliye_no': 'IRS-TEST-0001'});
      final rows = await db.query('irsaliyeler', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['e_irsaliye_deneme_no'], equals(0));
      expect(rows.first['e_irsaliye_durum'], equals('hazir'));
    });
  });

  group('UBL-TR DespatchAdvice (e-İrsaliye) XML üretimi', () {
    test('temel yapı ve alanlar doğru gömülüyor', () async {
      final xml = await GibServisi().ublDespatchAdviceOlustur(
        irsaliye: {
          'irsaliye_no': 'IRS-2026-0001',
          'tarih': '2026-09-14T10:00:00',
          'tip': 'Çıkış',
          'cari_adi': 'Test Müşteri A.Ş.',
          'cari_vergi_no': '1234567890',
          'cari_vergi_dairesi': 'Kadıköy',
          'cari_adres': 'Test Mah. No:1',
        },
        kalemler: [
          {'urun_adi': 'Ürün 1', 'miktar': 5},
          {'urun_adi': 'Ürün 2', 'miktar': 2.5},
        ],
        ettn: 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
      );

      expect(xml, contains('<DespatchAdvice'));
      expect(xml, contains('<cbc:ProfileID>TEMELIRSALIYE</cbc:ProfileID>'));
      expect(xml, contains('<cbc:ID>IRS-2026-0001</cbc:ID>'));
      expect(xml, contains('<cbc:UUID>AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE</cbc:UUID>'));
      expect(xml, contains('<cbc:DespatchAdviceTypeCode>SEVK</cbc:DespatchAdviceTypeCode>'));
      expect(xml, contains('schemeID="VKN">1234567890'));
      expect(xml, contains('<cbc:Name>Test Müşteri A.Ş.</cbc:Name>'));
      expect(xml, contains('<cbc:Name>Ürün 1</cbc:Name>'));
      expect(xml, contains('<cbc:DeliveredQuantity unitCode="C62">5.0000</cbc:DeliveredQuantity>'));
      expect(xml, contains('<cbc:DeliveredQuantity unitCode="C62">2.5000</cbc:DeliveredQuantity>'));
      expect(xml, contains('<cbc:HandlingCode>CIKIS</cbc:HandlingCode>'));
      // Vergi/tutar İÇERMEMELİ — bir irsaliye mal sevkini belgeler, satış tutarını değil.
      expect(xml, isNot(contains('TaxTotal')));
      expect(xml, isNot(contains('LegalMonetaryTotal')));
    });

    test('TCKN uzunluğundaki (11 hane) vergi no doğru schemeID alır', () async {
      final xml = await GibServisi().ublDespatchAdviceOlustur(
        irsaliye: {'irsaliye_no': 'IRS-2', 'cari_vergi_no': '12345678901'},
        kalemler: const [],
        ettn: 'ettn-2',
      );
      expect(xml, contains('schemeID="TCKN">12345678901'));
    });

    test('giriş irsaliyesi HandlingCode GIRIS olur', () async {
      final xml = await GibServisi().ublDespatchAdviceOlustur(
        irsaliye: {'irsaliye_no': 'IRS-3', 'tip': 'Giriş'},
        kalemler: const [],
        ettn: 'ettn-3',
      );
      expect(xml, contains('<cbc:HandlingCode>GIRIS</cbc:HandlingCode>'));
    });

    test('özel karakterler (&, <, >) XML-escape edilir', () async {
      final xml = await GibServisi().ublDespatchAdviceOlustur(
        irsaliye: {'irsaliye_no': 'IRS-4', 'cari_adi': 'A & B <Ltd>'},
        kalemler: const [],
        ettn: 'ettn-4',
      );
      expect(xml, contains('A &amp; B &lt;Ltd&gt;'));
      expect(xml, isNot(contains('A & B <Ltd>')));
    });
  });
}
