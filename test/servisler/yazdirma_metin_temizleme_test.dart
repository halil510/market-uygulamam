import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/yazdirma_servisi.dart';

void main() {
  test('Türkçe ve Latin-1 dışı karakterler yazıcı için güvenli hale gelir', () {
    expect(YazdirmaServisi.temizleYaziciMetni('İşğı Şeker'), 'Isgi Seker');
    expect(YazdirmaServisi.temizleYaziciMetni('Çay “büyük” – 5₺…'),
        'Çay "büyük" - 5TL...');
    final t = YazdirmaServisi.temizleYaziciMetni('Elma 🍎 1kg');
    expect(t.codeUnits.every((c) => c <= 255), isTrue);
  });
}
