// test/servisler/stok_hareket_subesi_test.dart
//
// DERİN DENETİM (2026-11-09, #83): stok_hareket satırlarında sube_id hiç
// yazılmıyordu; dönem arşivi (sube_id = ?) onları arşivleyemiyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/aktif_sube_servisi.dart';

void main() {
  test('boş sube_id verilen şubeyle doldurulur, aynı harita döner', () {
    final m = <String, dynamic>{'urun_id': 1};
    final r = stokHareketSubesi(m, subeId: 7);
    expect(identical(r, m), isTrue, reason: 'kuyruk kopyası da sube_id taşımalı');
    expect(m['sube_id'], 7);
  });

  test('dolu sube_id ezilmez', () {
    final m = <String, dynamic>{'sube_id': 3};
    expect(stokHareketSubesi(m, subeId: 7)['sube_id'], 3);
  });

  test('şube bilinmiyorsa merkez (1) yazılır, null kalmaz', () {
    final m = stokHareketSubesi(<String, dynamic>{});
    expect(m['sube_id'], isNotNull);
  });
}
