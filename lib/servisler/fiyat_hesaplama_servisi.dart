// lib/servisler/fiyat_hesaplama_servisi.dart
//
// Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
// profesyonel sistem, hepsi (fiyat grubu + miktar kademesi birlikte)."
//
// Bu servis, bir ürün + cari + miktar + birim verildiğinde, GERÇEK
// profesyonel toptan sistemlerinin kullandığı "en spesifikten en
// genele" öncelik zinciriyle doğru satış fiyatını belirler:
//
//   1) Perakende müşteri (veya cari seçilmemiş) → doğrudan perakende
//      fiyatı, hiçbir toptan kuralı uygulanmaz.
//   2) Miktar bazlı kademe (cari'nin grubuna özel VEYA genel kademe,
//      hangisi varsa) — en yüksek eşiği aşan kademe kazanır.
//   3) Cari'nin fiyat grubuna özel ÜRÜN fiyatı (varsa).
//   4) Cari'nin fiyat grubunun VARSAYILAN iskonto oranı (perakende
//      fiyata uygulanır).
//   5) Ürünün GENEL toptan fiyatı (fiyat grubu tanımlı değilse).
//   6) Hiçbiri yoksa: perakende fiyatına geri düş (güvenli varsayılan).
import '../modeller/urun_model.dart';
import '../modeller/cari_model.dart';
import '../modeller/fiyat_kademesi_model.dart';
import '../depolar/toptan_fiyat_deposu.dart';

class FiyatSonucu {
  final double birimFiyat;
  final String aciklama; // Kullanıcıya şeffaflık için: "Neden bu fiyat?"
  final String kaynak;   // 'perakende' | 'kademe' | 'grup_ozel' | 'grup_iskonto' | 'toptan_genel'

  const FiyatSonucu({required this.birimFiyat, required this.aciklama, required this.kaynak});
}

class FiyatHesaplamaServisi {
  static final FiyatHesaplamaServisi _instance = FiyatHesaplamaServisi._();
  factory FiyatHesaplamaServisi() => _instance;
  FiyatHesaplamaServisi._();

  final _depo = ToptanFiyatDeposu();

  Future<FiyatSonucu> hesapla({
    required UrunModel urun,
    CariModel? cari,
    required double miktar,
    String birim = 'adet', // 'adet' | 'koli' | 'kg'
  }) async {
    // 1) Perakende müşteri veya cari seçilmemiş → düz perakende fiyatı.
    if (cari == null || cari.musteriTipi == 'Perakende') {
      return FiyatSonucu(
          birimFiyat: urun.satisFiyati, aciklama: 'Perakende fiyatı', kaynak: 'perakende');
    }

    // Kademe karşılaştırması için miktarı ADET cinsine çevir (koli
    // satışıysa koli_ici_miktar ile çarp; kg ise zaten doğrudan kg).
    final adetCinsindenMiktar = (birim == 'koli' && urun.koliIciMiktar > 0)
        ? miktar * urun.koliIciMiktar
        : miktar;

    // 2) Miktar bazlı kademe ara — cari'nin grubuna özel VEYA genel
    //    (fiyat_grubu_id = null) kademeler arasından, eşiği aşan EN
    //    YÜKSEK kademeyi seç (en avantajlı/en spesifik kademe kazanır).
    if (urun.id != null) {
      final kademeler = await _depo.kademeleriGetir(urun.id!);
      FiyatKademesiModel? enUygun;
      for (final k in kademeler) {
        // Bu kademe başka bir gruba özelse VE cari o grupta değilse atla.
        if (k.fiyatGrubuId != null && k.fiyatGrubuId != cari.fiyatGrubuId) continue;

        // Karşılaştırma miktarını kademenin KENDİ birimine çevir.
        final double karsilastirma;
        if (k.birim == 'koli' && urun.koliIciMiktar > 0) {
          karsilastirma = adetCinsindenMiktar / urun.koliIciMiktar;
        } else if (k.birim == 'kg') {
          karsilastirma = miktar; // kg bazlı ürünlerde miktar zaten kg
        } else {
          karsilastirma = adetCinsindenMiktar;
        }

        if (karsilastirma >= k.minMiktar) {
          if (enUygun == null || k.minMiktar > enUygun.minMiktar) enUygun = k;
        }
      }
      if (enUygun != null) {
        final kademeTuru = enUygun.fiyatGrubuId != null ? 'gruba özel kademe' : 'genel kademe';
        return FiyatSonucu(
          birimFiyat: enUygun.fiyat,
          aciklama: 'Kademeli fiyat ($kademeTuru, ${_sayiFormat(enUygun.minMiktar)}+ ${enUygun.birim})',
          kaynak: 'kademe',
        );
      }
    }

    // 3) Cari'nin fiyat grubuna özel ÜRÜN fiyatı.
    if (cari.fiyatGrubuId != null && urun.id != null) {
      final ozelFiyat = await _depo.urunGrupFiyatiGetir(urun.id!, cari.fiyatGrubuId!);
      if (ozelFiyat != null) {
        return FiyatSonucu(
            birimFiyat: ozelFiyat, aciklama: 'Bayi grubuna özel ürün fiyatı', kaynak: 'grup_ozel');
      }

      // 4) Grubun varsayılan iskonto oranı (perakende fiyata uygulanır).
      final grup = await _depo.grupGetir(cari.fiyatGrubuId!);
      if (grup != null && grup.varsayilanIskontoOrani > 0) {
        final fiyat = urun.satisFiyati * (1 - grup.varsayilanIskontoOrani / 100);
        return FiyatSonucu(
          birimFiyat: fiyat,
          aciklama: '${grup.ad} iskontosu (%${grup.varsayilanIskontoOrani.toStringAsFixed(0)})',
          kaynak: 'grup_iskonto',
        );
      }
    }

    // 5) Ürünün genel toptan fiyatı (fiyat grubu tanımlı değilse veya
    //    grubun özel/iskonto ayarı yoksa).
    if (urun.toptanFiyat > 0) {
      return FiyatSonucu(
          birimFiyat: urun.toptanFiyat, aciklama: 'Toptan fiyatı', kaynak: 'toptan_genel');
    }

    // 6) Güvenli varsayılan: hiçbir toptan kuralı tanımlı değilse
    //    perakende fiyatına geri düş (asla sıfır/hatalı fiyat verilmez).
    return FiyatSonucu(
        birimFiyat: urun.satisFiyati,
        aciklama: 'Perakende fiyatı (toptan fiyatı tanımlı değil)',
        kaynak: 'perakende');
  }

  String _sayiFormat(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
}
