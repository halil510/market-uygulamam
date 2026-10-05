// lib/saglayicilar/riverpod/sepet_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/sepet_model.dart';
import '../../modeller/promosyon_model.dart';
import '../../depolar/promosyon_deposu.dart';
import '../../servisler/urun_fiyat_hesaplayici.dart';

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
  double get araToplam    => ParaUtils.yuvarla(kalemler.fold(0.0, (s, k) => s + k.toplamTutar));
  double get iskontoTutar => ParaUtils.yuvarla(araToplam * (genelIskontoYuzde / 100));
  double get genelToplam  => ParaUtils.yuvarla(araToplam - iskontoTutar);
  /// KDV payı: satır KDV'leri toplamı, genel iskonto oranında küçülür
  /// (genel iskonto matrahı da düşürür).
  double get kdvToplam    => ParaUtils.yuvarla(
      kalemler.fold(0.0, (s, k) => s + k.kdvTutar) * (1 - genelIskontoYuzde / 100));

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
    Ref ref) async {
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

  // Fiyat kuralı (promosyon → kayıtlı indirimli fiyat → ürün indirimi →
  // liste fiyatı) masa siparişiyle paylaşılır: UrunFiyatHesaplayici.
  double _fiyatHesapla(UrunModel urun, double miktar) =>
      UrunFiyatHesaplayici.hesapla(urun, miktar, _promoCache[urun.id]);

  // Ürün bazlı promosyon cache: {urunId → [PromosyonModel, ...]}
  // Her ürün ilk kez sepete eklendiğinde DB'den doldurulur.
  //
  // 🔴 Derin analizde bulundu (kendi-keşif turu, Promosyon modülü
  // denetimi): Sepet @Riverpod(keepAlive:true) olduğu için bu cache
  // ÖNCEDEN sonsuza dek (uygulama yeniden başlatılana kadar) yaşıyordu
  // — bir ürün BİR KEZ sepete eklenip promosyonu önbelleğe alındıktan
  // sonra, yönetici o promosyonu Promosyon ekranından kapatsa/değiştirse
  // bile, POS ekranı kapatılıp açılsa DAHİ fiyat hesaplaması eski
  // (bayat) promosyonu uygulamaya devam ediyordu. Artık her girdinin
  // BİR SÜRE geçerliliği var — süresi dolduysa DB'den yeniden okunur.
  // Anlık değil ama sınırlı (en fazla birkaç dakikalık) bayatlık kabul
  // edilebilir bir ödünleşim (her sepete-ekleme'de DB'ye gitmek yerine).
  final Map<int, List<PromosyonModel>> _promoCache = {};
  final Map<int, DateTime> _promoCacheZaman = {};
  static const _promoCacheGecerlilik = Duration(minutes: 5);

  Future<void> _promoCacheYukle(int urunId) async {
    final sonYukleme = _promoCacheZaman[urunId];
    if (sonYukleme != null &&
        DateTime.now().difference(sonYukleme) < _promoCacheGecerlilik) {
      return;
    }
    try {
      final liste = await PromosyonDeposu().urunPromosyonlari(urunId);
      _promoCache[urunId] = liste;
    } catch (_) {
      _promoCache[urunId] = [];
    }
    _promoCacheZaman[urunId] = DateTime.now();
  }

  Future<void> ekleAsync(UrunModel urun, {double? miktar, double? fiyatOverride}) async {
    final adet = miktar ?? 1.0;
    if (urun.id != null) await _promoCacheYukle(urun.id!);
    ekle(urun, miktar: adet, fiyatOverride: fiyatOverride);
  }

  // 🔴🔴 KRİTİK DÜZELTME (hızlı satış derin analizi, 2026-09-14): bir
  // kalemin fiyatı elle indirimliDüzenle() (_indirimDuzenle ekranda)
  // ile değiştirildikten SONRA aynı ürün TEKRAR barkodla okutulursa
  // (miktar artışı) veya sepet kartından miktarı elle düzenlenirse, bu
  // iki fonksiyon fiyatı KOŞULSUZ _fiyatHesapla() ile YENİDEN
  // hesaplıyordu — kasiyerin biraz önce uyguladığı manuel indirim
  // SESSİZCE KAYBOLUYOR, müşteri fark etmeden standart fiyattan
  // faturalandırılıyordu. Artık: kalemin GEÇERLİ fiyatı, O ANKİ
  // miktarı için otomatik hesaplanacak fiyattan FARKLIYSA (yani elle
  // değiştirilmişse) bu fiyat KORUNUYOR — sadece hiç elle dokunulmamış
  // kalemlerde miktar artışında (ör. bir promosyon eşiği aşıldığında)
  // otomatik yeniden hesaplama devam ediyor.
  bool _elleDegistirilmisMi(SepetKalem k) =>
      (k.birimFiyat - _fiyatHesapla(k.urun, k.miktar)).abs() > 0.001;

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
      final mevcut = liste[idx];
      final yeniMiktar = mevcut.miktar + adet;
      final yeniFiyat = fiyatOverride ??
          (_elleDegistirilmisMi(mevcut)
              ? mevcut.birimFiyat
              : _fiyatHesapla(urun, yeniMiktar));
      final yeniKalem  = mevcut.copyWith(miktar: yeniMiktar, birimFiyat: yeniFiyat);
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
      final mevcut = liste[i];
      final yeniFiyat = _elleDegistirilmisMi(mevcut)
          ? mevcut.birimFiyat
          : _fiyatHesapla(mevcut.urun, yeniMiktar);
      liste[i] = mevcut.copyWith(miktar: yeniMiktar, birimFiyat: yeniFiyat);
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
int sepetKalemSayisi(Ref ref) =>
    ref.watch(sepetProvider.select((s) => s.kalemSayisi));

@riverpod
double sepetToplamTutar(Ref ref) =>
    ref.watch(sepetProvider.select((s) => s.genelToplam));

@riverpod
bool sepetBos(Ref ref) =>
    ref.watch(sepetProvider.select((s) => s.bos));

@riverpod
CariModel? sepetMusteri(Ref ref) =>
    ref.watch(sepetProvider.select((s) => s.musteri));
