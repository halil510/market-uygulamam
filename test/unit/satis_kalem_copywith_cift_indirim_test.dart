import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/satis_kalem_model.dart';

// Regresyon: kaydetme anındaki `copyWith(satisId: id).toMap()` tutarları
// yeniden hesaplayıp indirimi ikinci kez uyguluyordu (100 TL → 71,43 TL).
void main() {
  test('copyWith(satisId) tutarları DEĞİŞTİRMEZ (çift indirim yok)', () {
    final k = const SatisKalemModel(
      satisId: 0, urunId: 1, urunAdi: 'Makarna',
      miktar: 1, birimFiyat: 100,
      iskontoOran: 28.5714285714286, iskontoTutar: 40,
      kdvOran: 20, kdvTutar: 16.6667,
      netFiyat: 100, toplamTutar: 100,
    );
    final m = k.copyWith(satisId: 55).toMap();
    expect(m['satis_id'], 55);
    expect((m['toplam_tutar'] as num).toDouble(), 100);
    expect((m['net_fiyat'] as num).toDouble(), 100);
    expect((m['iskonto_tutar'] as num).toDouble(), 40);
    // Kayıt anında kuruşa yuvarlanır (16,6667 → 16,67).
    expect((m['kdv_tutar'] as num).toDouble(), 16.67);
  });

  test('miktar/fiyat verilirse yeniden hesaplanır (mevcut davranış)', () {
    final k = const SatisKalemModel(
      satisId: 1, urunId: 1, urunAdi: 'X', miktar: 1, birimFiyat: 10,
      kdvOran: 10, netFiyat: 10, toplamTutar: 10,
    );
    final y = k.copyWith(miktar: 3);
    expect(y.toplamTutar, 30);
  });
}
