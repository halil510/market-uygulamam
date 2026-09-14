// lib/servisler/excel_urun_birlestirici.dart
//
// Saf (DB'siz) birleştirme mantığı — ExcelServisi.exceldenurunleriBytesIceriAl()
// GÜNCELLEME dalından ayrıldı ki DB/singleton'a bağımlı olmadan izole test
// edilebilsin (bkz. sync_cakisma_tespit.dart'taki aynı desen).
import '../modeller/urun_model.dart';

class ExcelUrunBirlestirici {
  /// Var olan bir ürünü ([mevcut]), Excel satırından okunan alanlarla
  /// birleştirir. Excel'de GERÇEKTEN VAR OLAN (sütunu bulunan) alanlar
  /// [null] OLMAYAN parametreler olarak verilir ve uygulanır; bir
  /// parametre [null] geçilirse (o sütun Excel'de yoktu/boştu demektir)
  /// [mevcut] kayıttaki değer OLDUĞU GİBİ korunur.
  ///
  /// KASITLI OLARAK parametre listesinde OLMAYAN alanlar (global_id,
  /// qr_menude, minimum/maksimum stok, seri/lot takibi, toptan satış
  /// alanları, puan oranı, resim, PLU, ölçüler, muhasebe kodu vb.) —
  /// bunlar Excel içe aktarımının hiç bilmediği/dokunmaması gereken
  /// alanlardır ve copyWith() onları otomatik olarak [mevcut]'tan
  /// korur. Bkz. exceldenurunleriBytesIceriAl() içindeki kök neden
  /// notu: bu ayrım yapılmadan önce, birkaç sütunlu tipik bir fiyat/
  /// stok güncelleme Excel'i, bu alanların TÜMÜNÜ sessizce sıfırlıyordu.
  static UrunModel guncellemeIcinBirlestir({
    required UrunModel mevcut,
    required String urunAdi,
    required double satisFiyat,
    String? kod,
    String? barkod,
    String? barkodlar,
    String? birim,
    double? alisFiyat,
    double? alisFiyatKdvDahil,
    double? stok,
    double? kdvOran,
    String? anaGrup,
    bool? aktif,
    String? marka,
    String? alan1,
    double? indirimOrani,
    bool? otomatikIndirim,
    double? indirimliFiyatKayitli,
    double? eskiFiyat,
    DateTime? eskiFiyatTarih,
    String? promosyonGrup,
    bool? promosyonAktif,
    double? receteKatsayi,
    String? lotAciklama,
    double? hacim,
    bool? evrakKontrolAktif,
    double? netAlisFiyat,
    String? lastUpdated,
  }) =>
      mevcut.copyWith(
        kod: kod,
        barkod: barkod,
        barkodlar: barkodlar,
        urunAdi: urunAdi,
        birimAdi: birim,
        alisFiyat: alisFiyat,
        alisFiyatKdvDahil: alisFiyatKdvDahil,
        satisFiyati: satisFiyat,
        stok: stok,
        alisKdvOran: kdvOran,
        kdvOran: kdvOran?.toStringAsFixed(0),
        anaGrup: anaGrup,
        aktif: aktif,
        marka: marka,
        alan1: alan1,
        indirimOrani: indirimOrani,
        otomatikIndirim: otomatikIndirim,
        indirimliFiyatKayitli: indirimliFiyatKayitli,
        eskiFiyat: eskiFiyat,
        eskiFiyatTarih: eskiFiyatTarih,
        promosyonGrup: promosyonGrup,
        promosyonAktif: promosyonAktif,
        receteKatsayi: receteKatsayi,
        lotAciklama: lotAciklama,
        hacim: hacim,
        evrakKontrolAktif: evrakKontrolAktif,
        netAlisFiyat: netAlisFiyat,
        lastUpdated: lastUpdated,
      );
}
