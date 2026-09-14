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
}
