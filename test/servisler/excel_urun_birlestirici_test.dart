// test/servisler/excel_urun_birlestirici_test.dart
//
// Excel içe aktarımının GÜNCELLEME (mevcut ürünü bulup üzerine yazma)
// yolunu test eder. ÖNCEDEN bu yolda, Excel'de bulunmayan HER alan
// varsayılan değerlerle sıfırdan kuruluyor ve mevcut ürünün üzerine
// yazılıyordu — birkaç sütunlu tipik bir fiyat/stok Excel'i, global_id
// (bulut kimliği), qr_menude (QR Menüde Göster), minimum/maksimum stok,
// seri/lot takibi, toptan satış ayarları, puan oranı gibi Excel'in hiç
// bilmediği alanları SESSİZCE SIFIRLIYORDU.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/urun_model.dart';
import 'package:market_plus/servisler/excel_urun_birlestirici.dart';

void main() {
  group('ExcelUrunBirlestirici.guncellemeIcinBirlestir', () {
    final mevcut = UrunModel(
      id: 7,
      globalId: 'gid-orijinal-123',
      kod: 'K1',
      barkod: '8690000000001',
      urunAdi: 'Eski Ad',
      birimAdi: 'Adet',
      alisFiyat: 50,
      alisFiyatKdvDahil: 59,
      satisFiyati: 100,
      stok: 40,
      alisKdvOran: 18,
      kdvOran: '18',
      aktif: true,
      qrMenude: true,
      minimumStok: 5,
      maksimumStok: 200,
      seriNoTakibi: true,
      lotTakibi: true,
      toptanFiyat: 80,
      koliIciMiktar: 12,
      puanOrani: 2.5,
      resimUrl: 'https://ornek.com/resim.png',
      muhasebeKodu: '153.01',
    );

    test('Excel sadece fiyat+stok içeriyorsa (diğer tüm sütunlar YOK) — '
        'global_id, qr_menude, min/maks stok, seri/lot takibi, toptan '
        'ayarları, puan oranı ve resim OLDUĞU GİBİ korunur', () {
      final sonuc = ExcelUrunBirlestirici.guncellemeIcinBirlestir(
        mevcut: mevcut,
        urunAdi: 'Eski Ad', // Excel'de ürün adı sütunu zorunlu, aynı geldi
        satisFiyat: 120, // Excel'den güncellenen satış fiyatı
        stok: 65, // Excel'de Stok sütunu VARDI
        // Diğer HER ŞEY null geçiliyor — yani Excel'de o sütun YOKTU.
      );

      expect(sonuc.globalId, equals('gid-orijinal-123'),
          reason: 'bulut senkron kimliği DEĞİŞMEMELİ');
      expect(sonuc.qrMenude, isTrue,
          reason: 'QR Menüde Göster ayarı KORUNMALI');
      expect(sonuc.minimumStok, equals(5));
      expect(sonuc.maksimumStok, equals(200));
      expect(sonuc.seriNoTakibi, isTrue);
      expect(sonuc.lotTakibi, isTrue);
      expect(sonuc.toptanFiyat, equals(80));
      expect(sonuc.koliIciMiktar, equals(12));
      expect(sonuc.puanOrani, equals(2.5));
      expect(sonuc.resimUrl, equals('https://ornek.com/resim.png'));
      expect(sonuc.muhasebeKodu, equals('153.01'));

      // Excel'de GERÇEKTEN verilenler uygulanmalı:
      expect(sonuc.satisFiyati, equals(120));
      expect(sonuc.stok, equals(65));
    });

    test('Excel\'de Stok sütunu YOKSA (fiyat listesi Excel\'i) mevcut '
        'stok SIFIRLANMAZ, olduğu gibi kalır', () {
      final sonuc = ExcelUrunBirlestirici.guncellemeIcinBirlestir(
        mevcut: mevcut,
        urunAdi: 'Eski Ad',
        satisFiyat: 150,
        stok: null, // Excel'de Stok sütunu yok
      );
      expect(sonuc.stok, equals(40),
          reason: 'stok sütunu Excel\'de yoksa mevcut stok korunmalı');
    });

    test('Excel\'de Aktif sütunu YOKSA, elle pasifleştirilmiş bir ürün '
        'tekrar aktif hale GELMEZ', () {
      final pasifUrun = mevcut.copyWith(aktif: false);
      final sonuc = ExcelUrunBirlestirici.guncellemeIcinBirlestir(
        mevcut: pasifUrun,
        urunAdi: 'Eski Ad',
        satisFiyat: 100,
        aktif: null, // Excel'de Aktif sütunu yok
      );
      expect(sonuc.aktif, isFalse,
          reason: 'Excel\'de sütun yoksa elle pasifleştirme geri alınmamalı');
    });

    test('Excel\'de Alış Fiyatı sütunu YOKSA maliyet SIFIRLANMAZ', () {
      final sonuc = ExcelUrunBirlestirici.guncellemeIcinBirlestir(
        mevcut: mevcut,
        urunAdi: 'Eski Ad',
        satisFiyat: 100,
        alisFiyat: null,
        alisFiyatKdvDahil: null,
      );
      expect(sonuc.alisFiyat, equals(50));
      expect(sonuc.alisFiyatKdvDahil, equals(59));
    });

    test('Excel\'de İndirim Oranı/İndirimli Fiyat sütunu YOKSA, mevcut '
        'otomatik indirim ayarı SIFIRLANMAZ', () {
      final indirimliUrun = mevcut.copyWith(
          indirimOrani: 15, otomatikIndirim: true, indirimliFiyatKayitli: 85);
      final sonuc = ExcelUrunBirlestirici.guncellemeIcinBirlestir(
        mevcut: indirimliUrun,
        urunAdi: 'Eski Ad',
        satisFiyat: 100,
        indirimOrani: null,
        otomatikIndirim: null,
        indirimliFiyatKayitli: null,
      );
      expect(sonuc.indirimOrani, equals(15));
      expect(sonuc.otomatikIndirim, isTrue);
      expect(sonuc.indirimliFiyatKayitli, equals(85));
    });

    test('Excel\'de VERİLEN alanlar (kod/barkod/kategori/marka) doğru '
        'şekilde günceller', () {
      final sonuc = ExcelUrunBirlestirici.guncellemeIcinBirlestir(
        mevcut: mevcut,
        urunAdi: 'Yeni Ad',
        satisFiyat: 100,
        kod: 'K2',
        barkod: '8690000000002',
        anaGrup: 'İçecek',
        marka: 'YeniMarka',
      );
      expect(sonuc.urunAdi, equals('Yeni Ad'));
      expect(sonuc.kod, equals('K2'));
      expect(sonuc.barkod, equals('8690000000002'));
      expect(sonuc.anaGrup, equals('İçecek'));
      expect(sonuc.marka, equals('YeniMarka'));
    });
  });
}
