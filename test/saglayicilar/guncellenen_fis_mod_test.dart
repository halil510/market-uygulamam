// test/saglayicilar/guncellenen_fis_mod_test.dart
//
// Derin denetim (2026-11-09) #23 #24: fiş güncelleme modu ekran State'inde
// tutuluyordu — ekrandan çıkınca kayboluyor (aynı ürünler yeni satış olarak
// tekrar satılıyordu), sepeti boşaltan akışlar (askıya al vb.) modu
// kapatmıyordu (sonraki sepet eski fişin üzerine yazılıyordu).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:market_plus/modeller/satis_model.dart';
import 'package:market_plus/saglayicilar/riverpod/guncellenen_fis_provider.dart';
import 'package:market_plus/saglayicilar/riverpod/sepet_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final fis = SatisModel(
      id: 7, fisNo: 'MKP2026010000007', tarih: DateTime(2026, 11, 9),
      toplamTutar: 100, genelToplam: 100, odenenTutar: 100, odemeYontemi: 'Nakit');

  test('mod ekrandan bağımsız yaşar (ekran kapanıp açılınca kaybolmaz)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(guncellenenFisProvider.notifier).ayarla(fis);
    // Ekranın yeniden açılması = sağlayıcıyı yeniden okumak.
    expect(c.read(guncellenenFisProvider)?.id, 7);
  });

  test('sepet boşaltılınca (askıya al, tedarikçiye aktar, satış sonu) mod kapanır', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(sepetProvider);
    c.read(guncellenenFisProvider.notifier).ayarla(fis);
    c.read(sepetProvider.notifier).temizle();
    expect(c.read(guncellenenFisProvider), isNull);
  });
}
