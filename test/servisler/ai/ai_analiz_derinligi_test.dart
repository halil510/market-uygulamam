// test/servisler/ai/ai_analiz_derinligi_test.dart
//
// FAZ 10 — AI analiz derinliği (erp_roadmap madde 24): "anormal işlem
// tespiti" için kullanılan z-skoru saf fonksiyonunun doğrulanması (bkz.
// lib/servisler/ai/ai_rapor_servisi.dart). Kâr değişim açıklaması ve
// stok tükenme tahmini DB sorgularına dayalı, bu dosya sadece bağımsız
// test edilebilen istatistik çekirdeğini kapsıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/ai/ai_rapor_servisi.dart';

void main() {
  group('zSkoruAnormalDegerleriBul', () {
    test('5 değerden az veri varsa güvenilir tespit için boş liste döner', () {
      expect(zSkoruAnormalDegerleriBul(<double>[10, 20, 30, 9999]), isEmpty);
    });

    test('tüm değerler aynıysa (sapma=0) boş liste döner (sıfıra bölme yok)', () {
      expect(zSkoruAnormalDegerleriBul(<double>[50, 50, 50, 50, 50]), isEmpty);
    });

    test('normal dağılımdaki tek bir aşırı değeri doğru yakalar', () {
      // 100 TL civarı 9 satış + 1 tane 5000 TL'lik uç değer.
      final degerler = <double>[95, 100, 105, 98, 102, 97, 101, 99, 103, 5000];
      final anormal = zSkoruAnormalDegerleriBul(degerler);
      expect(anormal, [5000.0]);
    });

    test('sıra dışı değer yoksa boş liste döner', () {
      final degerler = <double>[95, 100, 105, 98, 102, 97, 101, 99, 103, 104];
      expect(zSkoruAnormalDegerleriBul(degerler), isEmpty);
    });

    test('daha katı bir eşik (yüksek esikZSkoru) daha az sonuç döner', () {
      final degerler = <double>[95, 100, 105, 98, 102, 97, 101, 99, 103, 300];
      final gevsek = zSkoruAnormalDegerleriBul(degerler, esikZSkoru: 1.5);
      final siki = zSkoruAnormalDegerleriBul(degerler, esikZSkoru: 5.0);
      expect(gevsek, isNotEmpty);
      expect(siki, isEmpty);
    });
  });
}
