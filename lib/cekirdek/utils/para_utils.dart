// lib/cekirdek/utils/para_utils.dart
import 'package:intl/intl.dart';

class ParaUtils {
  /// GIB formatındaki fiş nosunu kısa gösterim için dönüştürür
  /// MKP2026000000001 → MKP-000001
  static String kisaFisNo(String? fisNo) {
    if (fisNo == null || fisNo.isEmpty) return 'FİŞ';
    // 🔴 KULLANICI BULGUSU (ekran görüntüsü — Satış Listesi'nde "NC2ec87b"
    // gibi anlamsız kodlar): Veritabani._cakismaKorumasiUygula() aynı
    // fis_no'da GERÇEKTEN farklı bir global_id çakışırsa (ör. bu cihaz
    // "Veritabanını Temizle" ile yerelini sıfırlayıp buluta hâlâ bağlıyken
    // eski bulut kaydı geri iniyor — bkz. o ekrandaki bulut uyarısı) veri
    // kaybetmemek için gelen kaydı '<orijinal>-SYNC<kısaId>' diye yeniden
    // adlandırıp AYRI bir satır olarak saklıyordu. Bu fisNo 16 karakterden
    // uzun olduğundan aşağıdaki "son 8 karakter" yoluna düşüp kullanıcıya
    // rastgele görünen bir kod gösteriyordu. Artık bu biçim tanınıp
    // okunabilir hale getiriliyor: "MKP-000003 ⚠" — kullanıcı bunun bir
    // senkron çakışması kopyası olduğunu anlayabilir.
    final syncIdx = fisNo.indexOf('-SYNC');
    if (syncIdx > 0) {
      return '${kisaFisNo(fisNo.substring(0, syncIdx))} ⚠';
    }
    if (fisNo.length == 16 && RegExp(r'^[A-Z]{3}[0-9]{13}$').hasMatch(fisNo)) {
      final prefix = fisNo.substring(0, 3);
      final sira   = int.tryParse(fisNo.substring(7)) ?? 0;
      return '$prefix-${sira.toString().padLeft(6, '0')}';
    }
    if (fisNo.length > 12) return fisNo.substring(fisNo.length - 8);
    return fisNo;
  }

  static final _fmt   = NumberFormat('#,##0.00', 'tr_TR');
  static final _fmtK  = NumberFormat('#,##0', 'tr_TR');

  static String formatla(double tutar, {String simge = '₺'}) =>
      '$simge${_fmt.format(tutar)}';

  static String formatlaK(double tutar) => _fmtK.format(tutar);

  static double kdvHesapla(double fiyat, double oran) =>
      fiyat * (oran / 100);

  static double kdvDahilFiyat(double fiyat, double oran) =>
      fiyat * (1 + oran / 100);

  static double kdvHaricFiyat(double kdvliFiyat, double oran) =>
      kdvliFiyat / (1 + oran / 100);

  /// [kdvliTutar] KDV DAHİL bir tutarın İÇİNDEKİ KDV payını döner.
  /// Projede satış fiyatları KDV DAHİL saklanır (bkz. sepet_model.dart
  /// baş yorumu, 2026-09-16 kullanıcı onayıyla doğrulandı) — KDV tutarı,
  /// fiyatın ÜZERİNE eklenerek değil, İÇİNDEN ayıklanarak (bölünerek)
  /// hesaplanır. `kdvHesapla` (çarpma tabanlı) KDV HARİÇ bir taban
  /// fiyattan KDV üretmek içindir, KDV DAHİL bir tutardan kırılım
  /// çıkarmak için KULLANILMAMALIDIR — karıştırılmasınlar diye ayrı
  /// bir fonksiyon olarak tanımlandı.
  static double kdvPayiCikar(double kdvliTutar, double oran) =>
      kdvliTutar - kdvHaricFiyat(kdvliTutar, oran);

  static double karOrani(double alis, double satis) {
    if (alis <= 0) return 0;
    return ((satis - alis) / alis) * 100;
  }

  static double iskontoUygula(double fiyat, double iskontoOran) =>
      fiyat * (1 - iskontoOran / 100);

  // ══════════════════════════════════════════════════════════════════════
  // 🔴 KRİTİK DÜZELTME — TÜRKÇE ONDALIK AYIRICI
  //
  // SORUN: Türkçe klavyede ondalık tuşu VİRGÜLDÜR. Kasiyer 12,50 yazdığında
  //   double.tryParse('12,50')  →  null
  // döner. Projede 56 yerde bu sonuç `?? 0` ile yutuluyordu; yani:
  //
  //   • urun_ekle_ekrani  → ürün SATIŞ FİYATI 0 olarak kaydediliyordu
  //   • promosyon_ekrani  → indirim oranı %0 oluyordu
  //   • iade_ekrani       → girilen fiyat sessizce yok sayılıyordu
  //   • tahsilat_odeme    → "Geçerli tutar girin" deyip engelliyordu
  //
  // Hiçbiri kullanıcıya "virgül yerine nokta kullan" demiyordu. Sessiz
  // veri bozulmasıydı.
  //
  // ÇÖZÜM: tüm sayı girdileri artık bu tek fonksiyondan geçer.
  // ══════════════════════════════════════════════════════════════════════

  /// Kullanıcının yazdığı metni sayıya çevirir. Türkçe (12,50) ve
  /// İngilizce (12.50) biçimlerin ikisini de anlar.
  ///
  /// Kurallar:
  ///   • Hem `.` hem `,` varsa → SONDA olan ondalık ayırıcıdır,
  ///     diğeri binlik ayırıcı sayılır.
  ///       "1.234,56" → 1234.56   (Türkçe)
  ///       "1,234.56" → 1234.56   (İngilizce)
  ///   • Sadece `,` varsa → ondalık ayırıcı        "12,50" → 12.5
  ///   • Sadece `.` varsa → ondalık ayırıcı        "12.50" → 12.5
  ///     (binlik olarak YORUMLANMAZ — "12.50" markette fiyattır,
  ///      12500 değil. Bu bilinçli bir tercih.)
  ///   • Para simgesi, boşluk, tırnak temizlenir   "₺ 12,50" → 12.5
  ///   • Boş / anlamsız girdi → null (çağıran karar versin)
  static double? sayiCoz(String? metin) {
    if (metin == null) return null;
    var s = metin.trim();
    if (s.isEmpty) return null;

    // Para simgeleri, boşluklar, binlik tırnak
    s = s.replaceAll(RegExp(r"[₺\$€£\s'’]"), '');
    if (s.isEmpty) return null;

    final negatif = s.startsWith('-');
    if (negatif || s.startsWith('+')) s = s.substring(1);

    final sonNokta  = s.lastIndexOf('.');
    final sonVirgul = s.lastIndexOf(',');

    if (sonNokta >= 0 && sonVirgul >= 0) {
      // İkisi de var → sonda olan ondalık
      if (sonVirgul > sonNokta) {
        s = s.replaceAll('.', '').replaceFirst(',', '.');   // 1.234,56
      } else {
        s = s.replaceAll(',', '');                          // 1,234.56
      }
    } else if (sonVirgul >= 0) {
      // Sadece virgül → ondalık ayırıcı. Birden fazlaysa ilki hariç sil.
      s = s.replaceAll(',', '.');
      final ilk = s.indexOf('.');
      if (s.indexOf('.', ilk + 1) > 0) {
        s = s.substring(0, ilk + 1) + s.substring(ilk + 1).replaceAll('.', '');
      }
    }
    // Sadece nokta varsa dokunma — zaten Dart'ın anladığı biçim.

    final d = double.tryParse(s);
    if (d == null) return null;
    return negatif ? -d : d;
  }

  /// [sayiCoz] + varsayılan. Çağrı yerlerini kısaltmak için.
  static double sayi(String? metin, {double varsayilan = 0}) =>
      sayiCoz(metin) ?? varsayilan;

  /// Tam sayı karşılığı (adet, taksit sayısı vb.)
  static int? tamSayiCoz(String? metin) {
    final d = sayiCoz(metin);
    return d?.round();
  }
}
