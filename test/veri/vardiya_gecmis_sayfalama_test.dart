// test/veri/vardiya_gecmis_sayfalama_test.dart
//
// DEEP_AUDIT_REPORT FAZ 6 (2026-09-21): Vardiya Geçmişi sekmesi önceden
// SADECE en son 30 kaydı gösterip daha eskilere ulaşmanın hiçbir yolunu
// sunmuyordu. VardiyaDeposu.gecmisVardiyalarGetir()'e eklenen [offset]
// parametresinin doğru sayfaladığını doğrular.
//
// VardiyaDeposu Veritabani() singleton'ı üzerinden çalıştığı için
// (diğer depo testlerinde olduğu gibi) burada AYNI SQL gerçek şema
// üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<List<Map<String, dynamic>>> _gecmisVardiyalarGetir(
  Database db, {
  int? subeId,
  int limit = 30,
  int offset = 0,
}) async {
  final subeSarti = subeId != null ? ' AND v.sube_id = ?' : '';
  final args = <Object?>[if (subeId != null) subeId, limit, offset];
  final rows = await db.rawQuery(
      'SELECT v.*, k.ad_soyad, o.ad_soyad AS onaylayan_adi FROM vardiyalar v '
      'LEFT JOIN kullanicilar k ON v.kullanici_id = k.id '
      'LEFT JOIN kullanicilar o ON v.onaylayan_kullanici_id = o.id '
      'WHERE v.kapanis_tarihi IS NOT NULL$subeSarti ORDER BY v.id DESC LIMIT ? OFFSET ?',
      args);
  return rows.map((r) => Map<String, dynamic>.from(r)).toList();
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('VardiyaDeposu.gecmisVardiyalarGetir — sayfalama', () {
    test('offset ile ikinci sayfa BİRİNCİ sayfayla ÇAKIŞMADAN gelir',
        () async {
      for (var i = 0; i < 5; i++) {
        await db.insert('vardiyalar', {
          'kullanici_id': 1,
          'acilis_tarihi': DateTime(2026, 1, i + 1).toIso8601String(),
          'kapanis_tarihi': DateTime(2026, 1, i + 1, 20).toIso8601String(),
        });
      }

      final sayfa1 = await _gecmisVardiyalarGetir(db, limit: 2, offset: 0);
      final sayfa2 = await _gecmisVardiyalarGetir(db, limit: 2, offset: 2);
      final sayfa3 = await _gecmisVardiyalarGetir(db, limit: 2, offset: 4);

      expect(sayfa1, hasLength(2));
      expect(sayfa2, hasLength(2));
      expect(sayfa3, hasLength(1)); // 5 kayıt, son sayfada 1 kalır

      final tumIdler = [...sayfa1, ...sayfa2, ...sayfa3].map((v) => v['id']);
      expect(tumIdler.toSet(), hasLength(5)); // hiç tekrar/çakışma yok
    });

    test('açık (kapanmamış) vardiyalar geçmişe dahil edilmez', () async {
      await db.insert('vardiyalar', {
        'kullanici_id': 1,
        'acilis_tarihi': DateTime(2026, 1, 1).toIso8601String(),
        'kapanis_tarihi': null,
      });
      await db.insert('vardiyalar', {
        'kullanici_id': 1,
        'acilis_tarihi': DateTime(2026, 1, 2).toIso8601String(),
        'kapanis_tarihi': DateTime(2026, 1, 2, 20).toIso8601String(),
      });

      final gecmis = await _gecmisVardiyalarGetir(db);
      expect(gecmis, hasLength(1));
    });
  });
}
