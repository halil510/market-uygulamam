// test/servisler/ai_niyet_yonlendirici_test.dart
//
// Kullanıcı bulgusu — "Akıllı Analiz'de AI asistanı konuşmama göre
// herşeyi getiremiyor, tam pro hale getir": AiAnlayici'nin saf
// anahtar-kelime eşleştirmesi (ai_anlayici.dart) tanımadığı sorularda,
// AiNiyetYonlendirici Gemini function-calling ile AYNI rapor/sorgu
// fonksiyonlarını "araç" olarak sunup en uygununu seçtiriyor. Bu test
// DB/ağ/Gemini API'sine hiç dokunmadan, saf/izole edilebilen iki
// kritik parçayı doğrular:
//   1) Her tanımlı aracın (FunctionDeclaration) gerçekten bir AiIntent'e
//      eşlendiğini (bir araç adı unutulup haritada karşılıksız
//      kalmadığını) — aksi halde Gemini o aracı seçtiğinde sessizce
//      hiçbir şey olmaz (null döner, kullanıcı yine cevap alamaz).
//   2) Gemini'den gelen ham argümanların (tarih/periyot/limit/ürün-
//      müşteri adı) AiSoru.params sözleşmesine doğru çevrildiğini.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/ai/ai_niyet_yonlendirici.dart';

void main() {
  group('AiNiyetYonlendirici — araç/intent eşleme bütünlüğü', () {
    test('tanımlı HER aracın karşılığı fonksiyonIntent haritasında var '
        '— unutulan bir araç sessizce "cevapsız" kalmaz', () {
      final tumAracAdlari = AiNiyetYonlendirici.araclar
          .expand((t) => t.functionDeclarations ?? [])
          .map((f) => f.name)
          .toSet();

      expect(tumAracAdlari, isNotEmpty);
      for (final ad in tumAracAdlari) {
        expect(AiNiyetYonlendirici.fonksiyonIntent.containsKey(ad), isTrue,
            reason: '"$ad" aracı tanımlı ama fonksiyonIntent haritasında '
                'karşılığı yok — Gemini bu aracı seçerse kullanıcı '
                'yine cevap alamaz.');
      }
    });

    test('haritadaki HER intent, tanımlı bir araca karşılık geliyor — '
        'yazım hatasıyla eklenmiş, hiçbir aracın işaret etmediği bir '
        'giriş yok', () {
      final tumAracAdlari = AiNiyetYonlendirici.araclar
          .expand((t) => t.functionDeclarations ?? [])
          .map((f) => f.name)
          .toSet();
      for (final ad in AiNiyetYonlendirici.fonksiyonIntent.keys) {
        expect(tumAracAdlari.contains(ad), isTrue,
            reason: '"$ad" haritada var ama tanımlı bir araç değil.');
      }
    });
  });

  group('AiNiyetYonlendirici.paramlariCoz', () {
    test('baslangic_tarih/bitis_tarih doğru DateTime\'a çevrilir '
        '(bitiş günün SONUNA damgalanır)', () {
      final p = AiNiyetYonlendirici.paramlariCoz({
        'baslangic_tarih': '2026-03-01',
        'bitis_tarih': '2026-03-15',
      });
      expect(p['bas'], equals(DateTime(2026, 3, 1)));
      expect(p['bit'], equals(DateTime(2026, 3, 15, 23, 59, 59)));
    });

    test('tek "tarih" alanı hem bas hem bit için kullanılır (tek günlük '
        'raporlar — z raporu gibi)', () {
      final p = AiNiyetYonlendirici.paramlariCoz({'tarih': '2026-05-10'});
      expect(p['bas'], equals(DateTime(2026, 5, 10)));
      expect(p['bit'], equals(DateTime(2026, 5, 10, 23, 59, 59)));
    });

    test('limit ve gun_sayisi ikisi de "sayi" parametresine eşlenir', () {
      expect(AiNiyetYonlendirici.paramlariCoz({'limit': 5})['sayi'], equals(5));
      expect(
          AiNiyetYonlendirici.paramlariCoz({'gun_sayisi': 14})['sayi'], equals(14));
    });

    test('arama_metni ve urun_adi ikisi de "urunAdi" parametresine eşlenir '
        '— dispatch katmanının okuduğu ANAHTAR budur', () {
      expect(AiNiyetYonlendirici.paramlariCoz({'urun_adi': 'süt'})['urunAdi'],
          equals('süt'));
      expect(
          AiNiyetYonlendirici.paramlariCoz({'arama_metni': 'ekmek'})['urunAdi'],
          equals('ekmek'));
    });

    test('musteri_adi "musteriAdi" parametresine eşlenir', () {
      expect(
          AiNiyetYonlendirici.paramlariCoz({'musteri_adi': 'Ahmet'})['musteriAdi'],
          equals('Ahmet'));
    });

    test('boş/eksik argümanlarda çökmeden boş bir params döner', () {
      final p = AiNiyetYonlendirici.paramlariCoz({});
      expect(p, isEmpty);
    });

    test('geçersiz tarih string\'i sessizce yok sayılır (çökme yok)', () {
      final p = AiNiyetYonlendirici.paramlariCoz({'tarih': 'geçen hafta filan'});
      expect(p.containsKey('bas'), isFalse);
      expect(p.containsKey('bit'), isFalse);
    });
  });
}
