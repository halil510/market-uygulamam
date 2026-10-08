// lib/servisler/fiyat_hesaplama_servisi.dart
//
// Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
// profesyonel sistem, hepsi (fiyat grubu + miktar kademesi birlikte)."
//
// Bir ürün + cari + miktar + birim için toptan/bayi satış fiyatı, "en
// spesifikten en genele" öncelik zinciriyle:
//
//   1) Perakende müşteri (veya cari seçilmemiş) → perakende fiyatı.
//   2) Miktar bazlı kademe (cari'nin grubuna özel VEYA genel) — eşiği
//      aşan EN YÜKSEK kademe kazanır.
//   3) Cari'nin fiyat grubuna özel ÜRÜN fiyatı (grup → "Ürün Fiyatları").
//   4) Ürünün GENEL toptan fiyatı.
//   5) Cari'nin fiyat grubunun varsayılan iskonto oranı (perakendeye).
//   6) Hiçbiri yoksa perakende fiyatı.
//
// 2026-10-08 kullanıcı kararı: ürünün toptan fiyatı grup iskontosundan
// ÖNCE gelir (önceden grup iskontosu öncelikliydi: toptan fiyatı 107 olan
// ürün %10 gruplu bayiye 108'den satılıyordu). Kural tek yerde
// ([kuralUygula], saf/senkron): Toptan Satış ekranı bu servisle, Hızlı Satış
// sepeti ise önbelleğe aldığı verilerle AYNI fonksiyonu kullanır — iki
// ekran aynı bayiye aynı fiyatı verir.
import '../modeller/urun_model.dart';
import '../modeller/cari_model.dart';
import '../modeller/fiyat_grubu_model.dart';
import '../modeller/fiyat_kademesi_model.dart';
import '../depolar/toptan_fiyat_deposu.dart';

class FiyatSonucu {
  final double birimFiyat;
  final String aciklama; // Kullanıcıya şeffaflık için: "Neden bu fiyat?"
  final String kaynak;   // 'perakende' | 'kademe' | 'grup_ozel' | 'toptan_genel' | 'grup_iskonto'

  const FiyatSonucu({required this.birimFiyat, required this.aciklama, required this.kaynak});
}

/// Cari toptan kurallarına tabi mi (Bayi/Toptan müşteri tipi)?
bool toptanMusteriMi(CariModel? cari) =>
    cari != null && cari.musteriTipi != 'Perakende';

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
    if (!toptanMusteriMi(cari)) {
      return kuralUygula(urun: urun, cari: cari, miktar: miktar, birim: birim);
    }
    final v = await toptanVerisiGetir(urun, cari!);
    return kuralUygula(
      urun: urun,
      cari: cari,
      miktar: miktar,
      birim: birim,
      kademeler: v.kademeler,
      grupOzelFiyat: v.grupOzelFiyat,
      grup: v.grup,
    );
  }

  /// Kuralın ihtiyaç duyduğu veritabanı verileri (Hızlı Satış önbelleğe alır).
  Future<({List<FiyatKademesiModel> kademeler, double? grupOzelFiyat, FiyatGrubuModel? grup})>
      toptanVerisiGetir(UrunModel urun, CariModel cari) async {
    final kademeler =
        urun.id == null ? <FiyatKademesiModel>[] : await _depo.kademeleriGetir(urun.id!);
    double? ozel;
    FiyatGrubuModel? grup;
    if (cari.fiyatGrubuId != null) {
      if (urun.id != null) ozel = await _depo.urunGrupFiyatiGetir(urun.id!, cari.fiyatGrubuId!);
      grup = await _depo.grupGetir(cari.fiyatGrubuId!);
    }
    return (kademeler: kademeler, grupOzelFiyat: ozel, grup: grup);
  }

  /// Saf fiyat kuralı (veritabanına gitmez) — bkz. dosya başı öncelik sırası.
  static FiyatSonucu kuralUygula({
    required UrunModel urun,
    required CariModel? cari,
    required double miktar,
    String birim = 'adet',
    List<FiyatKademesiModel> kademeler = const [],
    double? grupOzelFiyat,
    FiyatGrubuModel? grup,
  }) {
    // 1) Perakende müşteri veya cari seçilmemiş → düz perakende fiyatı.
    if (!toptanMusteriMi(cari)) {
      return FiyatSonucu(
          birimFiyat: urun.satisFiyati, aciklama: 'Perakende fiyatı', kaynak: 'perakende');
    }

    // Kademe karşılaştırması için miktarı ADET cinsine çevir (koli
    // satışıysa koli_ici_miktar ile çarp; kg ise zaten doğrudan kg).
    final adetCinsindenMiktar = (birim == 'koli' && urun.koliIciMiktar > 0)
        ? miktar * urun.koliIciMiktar
        : miktar;

    // 2) Miktar kademesi — cari'nin grubuna özel VEYA genel; eşiği aşan
    //    EN YÜKSEK kademe.
    FiyatKademesiModel? enUygun;
    for (final k in kademeler) {
      if (k.fiyatGrubuId != null && k.fiyatGrubuId != cari!.fiyatGrubuId) continue;
      final double karsilastirma;
      if (k.birim == 'koli' && urun.koliIciMiktar > 0) {
        karsilastirma = adetCinsindenMiktar / urun.koliIciMiktar;
      } else if (k.birim == 'kg') {
        karsilastirma = miktar;
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

    // 3) Gruba özel ürün fiyatı.
    if (grupOzelFiyat != null) {
      return FiyatSonucu(
          birimFiyat: grupOzelFiyat, aciklama: 'Bayi grubuna özel ürün fiyatı', kaynak: 'grup_ozel');
    }

    // 4) Ürünün genel toptan fiyatı (grup iskontosundan ÖNCE — kullanıcı kararı).
    if (urun.toptanFiyat > 0) {
      return FiyatSonucu(
          birimFiyat: urun.toptanFiyat, aciklama: 'Toptan fiyatı', kaynak: 'toptan_genel');
    }

    // 5) Grubun varsayılan iskonto oranı (perakende fiyata uygulanır).
    if (grup != null && grup.varsayilanIskontoOrani > 0) {
      return FiyatSonucu(
        birimFiyat: urun.satisFiyati * (1 - grup.varsayilanIskontoOrani / 100),
        aciklama: '${grup.ad} iskontosu (%${grup.varsayilanIskontoOrani.toStringAsFixed(0)})',
        kaynak: 'grup_iskonto',
      );
    }

    // 6) Güvenli varsayılan: perakende fiyatı (asla sıfır/hatalı fiyat verilmez).
    return FiyatSonucu(
        birimFiyat: urun.satisFiyati,
        aciklama: 'Perakende fiyatı (toptan fiyatı tanımlı değil)',
        kaynak: 'perakende');
  }

  static String _sayiFormat(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
}
