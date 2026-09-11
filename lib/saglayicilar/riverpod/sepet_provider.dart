// lib/saglayicilar/riverpod/sepet_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/sepet_model.dart';
import '../../modeller/promosyon_model.dart';
import '../../depolar/promosyon_deposu.dart';

part 'sepet_provider.g.dart';

class SepetDurum {
  final List<SepetKalem> kalemler;
  final CariModel? musteri;
  final double genelIskontoYuzde;
  final bool satisIsleniyor;

  const SepetDurum({
    this.kalemler           = const [],
    this.musteri,
    this.genelIskontoYuzde  = 0,
    this.satisIsleniyor     = false,
  });

  bool   get bos          => kalemler.isEmpty;
  int    get kalemSayisi  => kalemler.length;
  int    get toplamAdet   => kalemler.fold(0, (s, k) => s + k.miktar.round());
  double get araToplam    => kalemler.fold(0.0, (s, k) => s + k.toplamTutar);
  double get iskontoTutar => araToplam * (genelIskontoYuzde / 100);
  double get genelToplam  => araToplam - iskontoTutar;
  double get kdvToplam    => kalemler.fold(0.0, (s, k) => s + k.kdvTutar);

  SepetDurum copyWith({
    List<SepetKalem>?    kalemler,
    CariModel? Function()? musteri,
    double?              genelIskontoYuzde,
    bool?                satisIsleniyor,
  }) => SepetDurum(
    kalemler:          kalemler          ?? this.kalemler,
    musteri:           musteri           != null ? musteri()  : this.musteri,
    genelIskontoYuzde: genelIskontoYuzde ?? this.genelIskontoYuzde,
    satisIsleniyor:    satisIsleniyor    ?? this.satisIsleniyor,
  );
}

@riverpod
Future<Map<int, List<PromosyonModel>>> aktifPromosyonlar(
    AktifPromosyonlarRef ref) async {
  try {
    final tum = await PromosyonDeposu().tumunuGetir(sadecaAktif: true);
    final map = <int, List<PromosyonModel>>{};
    for (final p in tum.where((p) => p.aktif && p.gecerli)) {
      map.putIfAbsent(p.urunId, () => []).add(p);
    }
    return map;
  } catch (_) { return {}; }
}

@Riverpod(keepAlive: true)
class Sepet extends _$Sepet {
  @override
  SepetDurum build() => const SepetDurum();

  double _fiyatHesapla(UrunModel urun, double miktar) {
    final bazFiyat = urun.satisFiyati;

    // 1. Promosyon eşik kontrolü — artık önbelleğe bağlı değil:
    //    PromosyonDeposu'ndan ürüne ait aktif promosyonlar zaten
    //    _urunPromoCache'te tutulur (ilk eklemede yüklenir).
    //    Bu sayede "provider henüz yüklenmedi" yarış durumu ortadan kalkar.
    final promoList = _promoCache[urun.id];
    if (promoList != null && promoList.isNotEmpty) {
      // ÖNCEDEN BURADA en yüksek minimum miktar eşiğine sahip promosyon
      // seçiliyordu (indirim yüzdesine BAKILMAKSIZIN) — bu, müşteri
      // DAHA ÇOK ürün aldığında DAHA AZ indirim alabileceği, kafa
      // karıştırıcı bir sonuca yol açabiliyordu (örn. 1 adette %10,
      // 5 adette %5 gibi iki promosyon varsa, 5 adet alan müşteri
      // yanlışlıkla %5'i alıyordu). Artık, geçerli tüm promosyonlar
      // arasından HER ZAMAN en yüksek indirim yüzdesi seçiliyor —
      // müşteri asla "daha az" indirim almıyor.
      PromosyonModel? best;
      for (final p in promoList) {
        if (p.gecerli && miktar >= p.minMiktar) {
          if (best == null || p.iskontoOran > best.iskontoOran) best = p;
        }
      }
      if (best != null) {
        return bazFiyat * (1 - best.iskontoOran / 100);
      }
    }

    // 2. DB'ye kayıtlı indirimli fiyat
    if (urun.indirimliFiyatKayitli > 0 && urun.indirimliFiyatKayitli < bazFiyat) {
      return urun.indirimliFiyatKayitli;
    }

    // 3. Ürün indirim oranı
    if (urun.indirimOrani > 0) {
      return bazFiyat * (1 - urun.indirimOrani / 100);
    }

    // 4. Normal satış fiyatı
    return bazFiyat;
  }

  // Ürün bazlı promosyon cache: {urunId → [PromosyonModel, ...]}
  // Her ürün ilk kez sepete eklendiğinde DB'den doldurulur.
  final Map<int, List<PromosyonModel>> _promoCache = {};

  Future<void> _promoCacheYukle(int urunId) async {
    if (_promoCache.containsKey(urunId)) return;
    try {
      final liste = await PromosyonDeposu().urunPromosyonlari(urunId);
      _promoCache[urunId] = liste;
    } catch (_) {
      _promoCache[urunId] = [];
    }
  }

  Future<void> ekleAsync(UrunModel urun, {double? miktar, double? fiyatOverride}) async {
    final adet = miktar ?? 1.0;
    if (urun.id != null) await _promoCacheYukle(urun.id!);
    ekle(urun, miktar: adet, fiyatOverride: fiyatOverride);
  }

  void ekle(UrunModel urun, {double? miktar, double? fiyatOverride}) {
    final adet  = miktar ?? 1.0;
    final fiyat = fiyatOverride ?? _fiyatHesapla(urun, adet);
    final liste = List<SepetKalem>.from(state.kalemler);
    // id'si olmayan (kaydedilmemiş/serbest) ürünlerde eşleşmeyi id yerine
    // aynı referansa bakarak yapıyoruz — aksi halde id'si null olan farklı
    // ürünler yanlışlıkla aynı sepet kalemine birleşir.
    final idx   = urun.id != null
        ? liste.indexWhere((k) => k.urun.id == urun.id)
        : liste.indexWhere((k) => identical(k.urun, urun));
    if (idx >= 0) {
      final yeniMiktar = liste[idx].miktar + adet;
      final yeniFiyat  = _fiyatHesapla(urun, yeniMiktar);
      final yeniKalem  = liste[idx].copyWith(miktar: yeniMiktar, birimFiyat: yeniFiyat);
      liste.removeAt(idx);
      liste.insert(0, yeniKalem);
    } else {
      liste.insert(0, SepetKalem(urun: urun, birimFiyat: fiyat, miktar: adet));
    }
    state = state.copyWith(kalemler: liste);
  }

  void miktarGuncelle(int i, double yeniMiktar) {
    if (i < 0 || i >= state.kalemler.length) return;
    final liste = List<SepetKalem>.from(state.kalemler);
    if (yeniMiktar <= 0) {
      liste.removeAt(i);
    } else {
      final yeniFiyat = _fiyatHesapla(liste[i].urun, yeniMiktar);
      liste[i] = liste[i].copyWith(miktar: yeniMiktar, birimFiyat: yeniFiyat);
    }
    state = state.copyWith(kalemler: liste);
  }

  void sil(int i) {
    if (i < 0 || i >= state.kalemler.length) return;
    state = state.copyWith(
        kalemler: List<SepetKalem>.from(state.kalemler)..removeAt(i));
  }

  void fiyatGuncelle(int i, double yeniFiyat) {
    if (i < 0 || i >= state.kalemler.length) return;
    final liste = List<SepetKalem>.from(state.kalemler);
    liste[i] = liste[i].copyWith(birimFiyat: yeniFiyat);
    state = state.copyWith(kalemler: liste);
  }

  void iskontoGuncelle(double yuzde) =>
      state = state.copyWith(genelIskontoYuzde: yuzde.clamp(0, 100));
  void musteriSec(CariModel? m) => state = state.copyWith(musteri: () => m);
  void temizle()     => state = const SepetDurum();
  void satisBasladi()=> state = state.copyWith(satisIsleniyor: true);
  void satisGitti()  => state = state.copyWith(satisIsleniyor: false);
}

// Granular — sadece ilgili parça rebuild olur
@riverpod
int sepetKalemSayisi(SepetKalemSayisiRef ref) =>
    ref.watch(sepetProvider.select((s) => s.kalemSayisi));

@riverpod
double sepetToplamTutar(SepetToplamTutarRef ref) =>
    ref.watch(sepetProvider.select((s) => s.genelToplam));

@riverpod
bool sepetBos(SepetBosRef ref) =>
    ref.watch(sepetProvider.select((s) => s.bos));

@riverpod
CariModel? sepetMusteri(SepetMusteriRef ref) =>
    ref.watch(sepetProvider.select((s) => s.musteri));
