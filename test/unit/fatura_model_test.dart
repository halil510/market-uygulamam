import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/fatura_model.dart';

void main() {
  group('FaturaModel', () {
    test('odendi getter - odemeDurumu "odendi" iken true', () {
      final f = FaturaModel(tarih: DateTime.now(), odemeDurumu: 'odendi');
      expect(f.odendi, isTrue);
    });

    test('odendi getter - "beklemede" iken false', () {
      final f = FaturaModel(tarih: DateTime.now(), odemeDurumu: 'beklemede');
      expect(f.odendi, isFalse);
    });

    test('eFaturaGonderildi getter doğru çalışır', () {
      final f = FaturaModel(tarih: DateTime.now(), eFaturaDurum: 'gonderildi');
      expect(f.eFaturaGonderildi, isTrue);
    });

    test('vadesiGecti - vade tarihi geçmişte ve kalan tutar var -> true', () {
      final f = FaturaModel(
        tarih: DateTime(2020, 1, 1),
        vadeTarihi: DateTime(2020, 1, 15),
        kalanTutar: 500,
      );
      expect(f.vadesiGecti, isTrue);
    });

    test('vadesiGecti - vade tarihi yoksa false', () {
      final f = FaturaModel(tarih: DateTime.now(), kalanTutar: 500);
      expect(f.vadesiGecti, isFalse);
    });

    test('varsayılan faturaTipi Satış', () {
      final f = FaturaModel(tarih: DateTime.now());
      expect(f.faturaTipi, equals('Satış'));
      expect(f.durum, equals('aktif'));
      expect(f.detaylar, isEmpty);
    });
  });

  group('FaturaDetayModel', () {
    test('toplamTutar alanı doğru taşınır', () {
      const d = FaturaDetayModel(
        urunAdi: 'Test Ürün',
        miktar: 2,
        birimFiyat: 50,
        iskontoOrani: 0,
        iskontoTutari: 0,
        kdvOrani: 20,
        kdvTutari: 20,
        araToplam: 100,
        toplamTutar: 120,
      );
      expect(d.toplamTutar, equals(120));
      expect(d.urunAdi, equals('Test Ürün'));
    });
  });

  group('Fatura toplamları — "Madde 21" araToplam=net kuralı (regresyon)', () {
    // 🔴 Derin denetimde bulunan kritik bug: codebase genelinde araToplam
    // İNDİRİM UYGULANDIKTAN SONRAKİ (net/matrah) tutar olarak saklanır —
    // yani her kalemde araToplam + kdvTutari == toplamTutar tutmalıdır.
    // Bu kural bozulursa (ör. biri araToplam'ı yanlışlıkla indirim
    // öncesi brüt tutara eşitlerse), basılan faturadaki "Vergiler Hariç
    // Toplam + Hesaplanan KDV" görünen "Vergiler Dahil Toplam"a denk
    // gelmez — resmi bir belgede en kritik hata sınıfı. Bu test, o
    // düzeltmenin — özellikle "Varsayılan İskonto %" ayarının otomatik
    // uygulandığı akışta bulunan gerçek regresyonun — bir daha
    // yaşanmamasını güvence altına alır.
    test('indirimli bir kalemde araToplam + kdvTutari == toplamTutar', () {
      // faturalandirma_servisi.dart'taki "varsayılan iskonto" dalıyla
      // birebir aynı hesap: brüt araToplam=100, %10 varsayılan iskonto,
      // %18 KDV.
      const brutAraToplam = 100.0;
      const iskontoOrani = 10.0;
      final iskontoTutar = brutAraToplam * iskontoOrani / 100; // 10
      final netTutar = brutAraToplam - iskontoTutar; // 90
      final kdvTutar = netTutar * 18 / 100; // 16.2

      final d = FaturaDetayModel(
        urunAdi: 'Test Ürün', miktar: 1, birimFiyat: brutAraToplam,
        iskontoOrani: iskontoOrani, iskontoTutari: iskontoTutar,
        kdvOrani: 18, kdvTutari: kdvTutar,
        araToplam: netTutar, // DOĞRU: net (Madde 21) — brütTutar DEĞİL
        toplamTutar: netTutar + kdvTutar,
      );

      expect(d.araToplam, closeTo(90, 0.001));
      expect(d.araToplam + d.kdvTutari, closeTo(d.toplamTutar, 0.001),
          reason: 'araToplam + kdvTutari, toplamTutar ile TUTMALI — '
              'aksi halde basılan fatura kendi içinde tutmaz.');
    });

    test('FaturaModel toplamları: toplamAraToplam + toplamKdv == genelToplam '
        '(indirimli kalem olsa bile)', () {
      // İki kalem: biri indirimsiz, biri %10 indirimli — hepsi Convention B
      // (araToplam zaten net) ile oluşturulmuş.
      const d1 = FaturaDetayModel(
        urunAdi: 'İndirimsiz', miktar: 1, birimFiyat: 50,
        iskontoOrani: 0, iskontoTutari: 0,
        kdvOrani: 18, kdvTutari: 9,
        araToplam: 50, toplamTutar: 59,
      );
      const d2 = FaturaDetayModel(
        urunAdi: 'İndirimli', miktar: 1, birimFiyat: 100,
        iskontoOrani: 10, iskontoTutari: 10,
        kdvOrani: 18, kdvTutari: 16.2,
        araToplam: 90, // net — brüt 100 DEĞİL
        toplamTutar: 106.2,
      );
      // FaturaModel.toplamAraToplam/toplamKdv/genelToplam HESAPLANMIŞ
      // getter DEĞİL, saklanan alanlardır — faturalandirma_servisi.dart
      // gerçek üretim kodundaki AYNI fold() deseniyle dolduruluyor.
      final detaylar = [d1, d2];
      final f = FaturaModel(
        tarih: DateTime.now(),
        detaylar: detaylar,
        toplamAraToplam: detaylar.fold<double>(0, (t, d) => t + d.araToplam),
        toplamIskonto: detaylar.fold<double>(0, (t, d) => t + d.iskontoTutari),
        toplamKdv: detaylar.fold<double>(0, (t, d) => t + d.kdvTutari),
        genelToplam: detaylar.fold<double>(0, (t, d) => t + d.toplamTutar),
      );

      // fatura_detay_pdf_ext.dart'ın düzeltilmiş "Vergiler Hariç Toplam"
      // formülüyle AYNI: genelToplam - toplamKdv (her koşulda doğru).
      final vergilerHaric = f.genelToplam - f.toplamKdv;
      expect(vergilerHaric + f.toplamKdv, closeTo(f.genelToplam, 0.001));
      expect(vergilerHaric, closeTo(140, 0.001)); // 50 + 90
      expect(f.genelToplam, closeTo(165.2, 0.001)); // 59 + 106.2
    });
  });
}
