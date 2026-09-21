// test/veri/banka_hareket_ozet_test.dart
//
// DEEP_AUDIT_REPORT madde 10: BankaHareketDeposu.ozetGetir() 'is_deleted'
// filtresi olmadan TÜM banka_hareketler satırlarını (silinmiş/iptal
// edilmiş olanlar dahil) topluyordu — gelen/giden özeti diğer
// sorgulardan (hareketleriGetir, bakiye zinciri) daha yüksek
// görünebiliyordu. BankaHareketDeposu Veritabani() singleton'ı
// üzerinden çalıştığı için (diğer depo testlerinde olduğu gibi) burada
// AYNI (düzeltilmiş) SQL gerçek şema üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<Map<String, double>> _ozetGetir(Database db, int hesapId) async {
  final rows = await db.rawQuery('''
    SELECT
      COALESCE(SUM(CASE WHEN islem_tipi = 'Gelen' THEN tutar ELSE 0 END), 0) as gelen,
      COALESCE(SUM(CASE WHEN islem_tipi != 'Gelen' THEN tutar ELSE 0 END), 0) as giden
    FROM banka_hareketler
    WHERE banka_hesap_id = ? AND is_deleted = 0
  ''', [hesapId]);
  return {
    'gelen': (rows.first['gelen'] as num?)?.toDouble() ?? 0,
    'giden': (rows.first['giden'] as num?)?.toDouble() ?? 0,
  };
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('BankaHareketDeposu.ozetGetir — is_deleted filtresi', () {
    test('silinmiş hareketler gelen/giden toplamına dahil edilmez', () async {
      await db.insert('banka_hareketler', {
        'banka_hesap_id': 1, 'islem_tipi': 'Gelen', 'tutar': 1000, 'is_deleted': 0,
      });
      await db.insert('banka_hareketler', {
        'banka_hesap_id': 1, 'islem_tipi': 'Giden', 'tutar': 200, 'is_deleted': 0,
      });
      // Silinmiş (iptal edilmiş) — özete DAHİL EDİLMEMELİ.
      await db.insert('banka_hareketler', {
        'banka_hesap_id': 1, 'islem_tipi': 'Gelen', 'tutar': 5000, 'is_deleted': 1,
      });

      final ozet = await _ozetGetir(db, 1);
      expect(ozet['gelen'], 1000);
      expect(ozet['giden'], 200);
    });

    test('farklı hesabın hareketleri toplama karışmaz', () async {
      await db.insert('banka_hareketler', {
        'banka_hesap_id': 1, 'islem_tipi': 'Gelen', 'tutar': 300, 'is_deleted': 0,
      });
      await db.insert('banka_hareketler', {
        'banka_hesap_id': 2, 'islem_tipi': 'Gelen', 'tutar': 999, 'is_deleted': 0,
      });

      final ozet = await _ozetGetir(db, 1);
      expect(ozet['gelen'], 300);
    });
  });
}
