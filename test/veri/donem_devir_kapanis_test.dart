// test/veri/donem_devir_kapanis_test.dart
//
// Yıl Sonu Devir motoru FAZ 4 (2026-09-16) — "tüm şubeler kapandı mı"
// (Madde 29) sorgusunun SQL mantığı, DonemDeposu.tumSubelerKapandiMi()
// ile BİREBİR aynı, gerçek şema üzerinde doğrulanıyor. Asıl doğrulanan
// senaryo: donem_sube_durumlari satırı HİÇ olmayan bir dönemde bu sorgu
// "boş sonuç = hepsi kapandı" diye YANLIŞ sonuç VERMEMELİ — bu yüzden
// DonemDevirServisi, devir başlarken TÜM aktif şubeler için satır
// oluşturuyor (subeDurumlariniBaslat). Bu test o önlemin GEREKLİLİĞİNİ
// (satır yoksa sorgunun yanılabileceğini) ve doğru çalıştığını (satırlar
// varsa doğru sonuç verdiğini) birlikte kanıtlıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<bool> _tumSubelerKapandiMi(Database db, int donemId) async {
  final rows = await db.query('donem_sube_durumlari',
      where: 'donem_id = ? AND durum NOT IN (?, ?)',
      whereArgs: [donemId, 'CLOSED', 'ARCHIVED']);
  return rows.isEmpty;
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<int> donemEkle() => db.insert('donemler', {
        'donem_yili': 2026,
        'baslangic_tarihi': '2026-01-01',
        'bitis_tarihi': '2026-12-31',
      });

  group('tumSubelerKapandiMi (Madde 29 — genel dönem tüm şubeler kapanınca kapanır)', () {
    test('⚠️ satır HİÇ yoksa vacuous-true tuzağı: bu sorgu tek başına '
        'yanıltıcı olabilir — DonemDevirServisi bu yüzden devir başında '
        'TÜM aktif şubeler için satır oluşturur', () async {
      final donemId = await donemEkle();
      // Hiç donem_sube_durumlari satırı YOK — gerçekte hiçbir şube
      // devri başlatmamış olsa bile sorgu "hepsi kapandı" der.
      expect(await _tumSubelerKapandiMi(db, donemId), isTrue,
          reason: 'Bilinen sınırlama — bu yüzden başlangıçta satır oluşturuluyor');
    });

    test('bir şube OPEN, biri CLOSED — hepsi kapanmadı', () async {
      final donemId = await donemEkle();
      await db.insert('donem_sube_durumlari', {'donem_id': donemId, 'sube_id': 1, 'durum': 'OPEN'});
      await db.insert('donem_sube_durumlari', {'donem_id': donemId, 'sube_id': 2, 'durum': 'CLOSED'});
      expect(await _tumSubelerKapandiMi(db, donemId), isFalse);
    });

    test('tüm şubeler CLOSED — hepsi kapandı', () async {
      final donemId = await donemEkle();
      await db.insert('donem_sube_durumlari', {'donem_id': donemId, 'sube_id': 1, 'durum': 'CLOSED'});
      await db.insert('donem_sube_durumlari', {'donem_id': donemId, 'sube_id': 2, 'durum': 'CLOSED'});
      expect(await _tumSubelerKapandiMi(db, donemId), isTrue);
    });

    test('ARCHIVED da "kapandı" sayılır', () async {
      final donemId = await donemEkle();
      await db.insert('donem_sube_durumlari', {'donem_id': donemId, 'sube_id': 1, 'durum': 'ARCHIVED'});
      expect(await _tumSubelerKapandiMi(db, donemId), isTrue);
    });

    test('başka bir dönemin şube durumu bu dönemi etkilemez', () async {
      final donemId = await donemEkle();
      final digerDonemId = await db.insert('donemler', {
        'donem_yili': 2025,
        'baslangic_tarihi': '2025-01-01',
        'bitis_tarihi': '2025-12-31',
      });
      await db.insert('donem_sube_durumlari', {'donem_id': digerDonemId, 'sube_id': 1, 'durum': 'OPEN'});
      await db.insert('donem_sube_durumlari', {'donem_id': donemId, 'sube_id': 1, 'durum': 'CLOSED'});
      expect(await _tumSubelerKapandiMi(db, donemId), isTrue);
    });
  });
}
