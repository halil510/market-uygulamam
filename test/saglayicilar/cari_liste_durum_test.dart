import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/saglayicilar/riverpod/cari_provider.dart';

void main() {
  // Canlı test 2026-10-08: Cariler ekranında üst çipler yalnız müşteri(+) /
  // tedarikçi(−) topluyordu, alt şerit tüm carileri — iki farklı rakam.
  test('alacak/borç tüm carilerden işarete göre, ortak cari bir kez sayılır', () {
    const ortak = CariModel(id: 3, unvan: 'Ortak', cariTipi: 'Hem Müşteri Hem Tedarikçi', bakiye: 50);
    const durum = CariListeDurum(
      musteriler: [
        CariModel(id: 1, unvan: 'M+', bakiye: 100),
        CariModel(id: 2, unvan: 'M-', bakiye: -20),
        ortak,
      ],
      tedarikciler: [
        CariModel(id: 4, unvan: 'T-', cariTipi: 'Tedarikçi', bakiye: -300),
        CariModel(id: 5, unvan: 'T+', cariTipi: 'Tedarikçi', bakiye: 7),
        ortak,
      ],
    );
    expect(durum.toplamAlacak, 157); // 100 + 50 + 7 (ortak bir kez)
    expect(durum.toplamBorc, 320); // 20 + 300
  });
}
