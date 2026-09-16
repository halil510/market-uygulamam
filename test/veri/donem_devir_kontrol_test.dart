// test/veri/donem_devir_kontrol_test.dart
//
// Yıl Sonu Devir motoru FAZ 2 (2026-09-16) — DonemDevirServisi
// Veritabani() singleton'ı üzerinden çalıştığı için (diğer depo
// testlerinde olduğu gibi, bkz. vardiya_nakit_mutabakat_test.dart
// yorumu) burada SADECE genuinely YENİ olan SQL mantığı (açık masa
// siparişi tespiti) gerçek şema üzerinde doğrulanıyor. Açık vardiya
// (VardiyaDeposu) ve bekleyen onay (OnayMerkeziServisi) kontrolleri
// zaten var olan, başka yerlerde test edilmiş depo metodlarını
// çağırıyor — burada tekrar test edilmiyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<int> _acikMasaSiparisiSayisi(Database db, {int? subeId}) async {
  final subeSarti = subeId != null ? ' AND m.sube_id = ?' : '';
  final args = <Object?>['acik', if (subeId != null) subeId];
  final rows = await db.rawQuery('''
    SELECT COUNT(*) AS n FROM masa_siparisleri ms
    JOIN masalar m ON m.id = ms.masa_id
    WHERE ms.durum = ? AND (ms.is_deleted IS NULL OR ms.is_deleted = 0)$subeSarti
  ''', args);
  return (rows.first['n'] as int?) ?? 0;
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<int> masaEkle({int subeId = 1}) => db.insert('masalar', {
        'ad': 'Masa $subeId-${DateTime.now().microsecondsSinceEpoch}',
        'sube_id': subeId,
        'is_deleted': 0,
      });

  group('Açık masa siparişi kontrolü (Madde 4 — devir öncesi kontrol)', () {
    test('açık (durum=acik) sipariş sayılır', () async {
      final masaId = await masaEkle();
      await db.insert('masa_siparisleri', {
        'masa_id': masaId,
        'durum': 'acik',
        'is_deleted': 0,
      });
      expect(await _acikMasaSiparisiSayisi(db), 1);
    });

    test('kapalı (durum=kapali) sipariş sayılmaz', () async {
      final masaId = await masaEkle();
      await db.insert('masa_siparisleri', {
        'masa_id': masaId,
        'durum': 'kapali',
        'is_deleted': 0,
      });
      expect(await _acikMasaSiparisiSayisi(db), 0);
    });

    test('soft-delete edilmiş açık sipariş sayılmaz', () async {
      final masaId = await masaEkle();
      await db.insert('masa_siparisleri', {
        'masa_id': masaId,
        'durum': 'acik',
        'is_deleted': 1,
      });
      expect(await _acikMasaSiparisiSayisi(db), 0);
    });

    test('şube filtresi doğru çalışır', () async {
      final masaSube1 = await masaEkle(subeId: 1);
      final masaSube2 = await masaEkle(subeId: 2);
      await db.insert('masa_siparisleri', {'masa_id': masaSube1, 'durum': 'acik', 'is_deleted': 0});
      await db.insert('masa_siparisleri', {'masa_id': masaSube2, 'durum': 'acik', 'is_deleted': 0});

      expect(await _acikMasaSiparisiSayisi(db), 2); // şube filtresi yok — ikisi de sayılır
      expect(await _acikMasaSiparisiSayisi(db, subeId: 1), 1);
      expect(await _acikMasaSiparisiSayisi(db, subeId: 2), 1);
      expect(await _acikMasaSiparisiSayisi(db, subeId: 3), 0);
    });

    test('hiç sipariş yoksa 0 döner', () async {
      expect(await _acikMasaSiparisiSayisi(db), 0);
    });
  });
}
