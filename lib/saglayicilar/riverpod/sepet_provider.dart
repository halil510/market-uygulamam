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
import '../../servisler/fiyat_hesaplama_servisi.dart';
import '../../modeller/fiyat_grubu_model.dart';
import '../../modeller/fiyat_kademesi_model.dart';
import 'dart:async';

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
  //
  // Bayi/Toptan müşteri seçiliyse Toptan Satış ekranıyla AYNI kural
  // (FiyatHesaplamaServisi.kuralUygula — kademe → gruba özel fiyat → ürün
  // toptan fiyatı → grup iskontosu). Kullanıcı bulgusu 2026-10-08: Hızlı
  // Satış'ta bayi seçilince toptan fiyatı 107 olan ürün 120'den satılıyordu.
  double _fiyatHesapla(UrunModel urun, double miktar) =>
      _bazFiyatHesapla(urun, miktar) ??
      UrunFiyatHesaplayici.hesapla(urun, miktar, _promoCache[urun.id]);

  /// Müşterinin liste fiyatı: bayi/toptanda toptan kuralı, perakendede null
  /// (= etiket fiyatı; promosyon perakendede "indirim" olarak görünür).
  double? _bazFiyatHesapla(UrunModel urun, double miktar) {
    final cari = state.musteri;
    if (!toptanMusteriMi(cari)) return null;
    final v = urun.id == null ? null : _toptanCache[urun.id];
    return FiyatHesaplamaServisi.kuralUygula(
      urun: urun,
      cari: cari,
      miktar: miktar,
      kademeler: v?.kademeler ?? const [],
      grupOzelFiyat: v?.grupOzelFiyat,
      grup: v?.grup,
    ).birimFiyat;
  }

  /// Kalemlerin müşteriye göre liste fiyatını (bazFiyat) güncel tutar —
  /// ekrandaki "İndirim", F6 iskontosu ve kayıttaki kalem indirimi bu
  /// fiyatı esas alır.
  List<SepetKalem> _bazla(List<SepetKalem> liste) => [
        for (final k in liste)
          () {
            final baz = _bazFiyatHesapla(k.urun, k.miktar);
            final ayni = baz == null
                ? k.bazFiyat == null
                : (k.bazFiyat != null && (k.bazFiyat! - baz).abs() < 0.0001);
            return ayni ? k : k.copyWith(bazFiyat: () => baz);
          }(),
      ];

  // Seçili bayi için ürün başına toptan verisi (kademe, gruba özel fiyat,
  // grup). Müşteri değişince temizlenir.
  final Map<int, ({List<FiyatKademesiModel> kademeler, double? grupOzelFiyat, FiyatGrubuModel? grup})>
      _toptanCache = {};

  Future<void> _toptanCacheYukle(UrunModel urun) async {
    final cari = state.musteri;
    if (!toptanMusteriMi(cari) || urun.id == null || _toptanCache.containsKey(urun.id)) return;
    try {
      final v = await FiyatHesaplamaServisi().toptanVerisiGetir(urun, cari!);
      if (state.musteri?.id == cari.id) _toptanCache[urun.id!] = v;
    } catch (_) {/* veri yoksa ürün toptan fiyatı / perakende kullanılır */}
  }

  /// Verilen ürünlerin toptan verisini yükleyip, elle değiştirilmemiş
  /// kalemleri yeni kurala göre yeniden fiyatlar.
  // Süren bayi fiyat yüklemeleri — ödeme başlamadan beklenir (fiyat,
  // ödeme penceresi açıkken değişip tutarlar uyuşmasın diye).
  final Set<Future<void>> _bekleyenTazelemeler = {};

  /// Bekleyen bayi fiyat güncellemeleri bitene kadar bekler (ödeme öncesi).
  Future<void> fiyatlarHazir() async {
    while (_bekleyenTazelemeler.isNotEmpty) {
      await Future.wait(_bekleyenTazelemeler.toList());
    }
  }

  void _tazelemeBaslat(Iterable<UrunModel> urunler) {
    late final Future<void> f;
    f = _toptanFiyatlariTazele(urunler)
        .catchError((_) {})
        .whenComplete(() => _bekleyenTazelemeler.remove(f));
    _bekleyenTazelemeler.add(f);
  }

  Future<void> _toptanFiyatlariTazele(Iterable<UrunModel> urunler) async {
    final cari = state.musteri;
    if (!toptanMusteriMi(cari)) return;
    // Yüklemeden ÖNCE otomatik fiyatta olan kalemler (sonra elle
    // değiştirilenlere dokunulmaz).
    final otomatik = _otomatikKalemler();
    for (final u in urunler) {
      await _toptanCacheYukle(u);
    }
    if (state.musteri?.id != cari!.id) return;
    _yenidenFiyatla(otomatik);
  }

  /// Elle fiyatı değiştirilmemiş kalemler (nesne kimliğiyle — kalem
  /// sonradan değişirse yeni nesne olur, eşleşmez; serbest ürünler de dahil).
  Set<SepetKalem> _otomatikKalemler() => Set<SepetKalem>.identity()
    ..addAll(state.kalemler.where((k) => !_elleDegistirilmisMi(k)));

  /// [otomatik] içindeki ve o zamandan beri değişmemiş kalemleri güncel
  /// kurala göre yeniden fiyatlar.
  void _yenidenFiyatla(Set<SepetKalem> otomatik) {
    var degisti = false;
    final liste = List<SepetKalem>.from(state.kalemler);
    for (var i = 0; i < liste.length; i++) {
      final k = liste[i];
      if (!otomatik.contains(k)) continue;
      final yeni = _fiyatHesapla(k.urun, k.miktar);
      if ((yeni - k.birimFiyat).abs() > 0.001) {
        liste[i] = k.copyWith(birimFiyat: yeni);
        degisti = true;
      }
    }
    // Fiyatı değişmese de (elle değiştirilmiş kalem) liste fiyatı yeni
    // müşteriye göre güncellenir.
    state = state.copyWith(kalemler: _bazla(degisti ? liste : state.kalemler));
  }

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
    await _toptanCacheYukle(urun);
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
    state = state.copyWith(kalemler: _bazla(liste));
    // Senkron eklemede (ör. miktar diyaloğu) bayi verisi henüz yoksa yükle
    // ve fiyatı düzelt.
    if (fiyatOverride == null &&
        toptanMusteriMi(state.musteri) &&
        urun.id != null &&
        !_toptanCache.containsKey(urun.id)) {
      _tazelemeBaslat([urun]);
    }
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
    state = state.copyWith(kalemler: _bazla(liste));
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
    state = state.copyWith(kalemler: _bazla(liste));
  }

  void iskontoGuncelle(double yuzde) =>
      state = state.copyWith(genelIskontoYuzde: yuzde.clamp(0, 100));
  /// Müşteri değişince elle değiştirilmemiş kalemler yeni müşterinin
  /// fiyat kuralına göre yeniden fiyatlanır (perakende ↔ bayi).
  void musteriSec(CariModel? m) {
    // Eski müşterinin kuralıyla otomatik fiyatta olan kalemler.
    final otomatik = _otomatikKalemler();
    final eskiId = state.musteri?.id;
    state = state.copyWith(musteri: () => m);
    if (eskiId != m?.id) _toptanCache.clear();
    _yenidenFiyatla(otomatik);
    if (toptanMusteriMi(m)) {
      _tazelemeBaslat(state.kalemler.map((k) => k.urun).toList());
    }
  }
  void temizle() {
    _toptanCache.clear();
    state = const SepetDurum();
  }

  // ── Çoklu alışveriş sekmesi (masaüstü, 2026-10-09) ────────────────────
  // Kasada aynı anda birden çok müşteri: her sekmenin kendi sepeti ve
  // müşterisi var. [state] her zaman AKTİF sekmedir — mevcut tüm ekranlar
  // değişmeden çalışır; diğer sekmeler burada saklanır. Sekme 1 kalıcıdır,
  // diğerleri satışı bitince kapanır. En fazla [maksSekme].
  static const int maksSekme = 10;
  final List<SepetDurum> _sekmeler = [const SepetDurum()];
  final List<int> _sekmeNo = [1];
  int _aktif = 0;

  int get aktifSekme => _aktif;

  /// Sekme özetleri (sekme çubuğu için). Aktif sekme canlı [state]'ten okunur.
  List<({int no, int urunSayisi, double toplam, String? musteri})> get sekmeler => [
        for (var i = 0; i < _sekmeler.length; i++)
          () {
            final d = i == _aktif ? state : _sekmeler[i];
            return (
              no: _sekmeNo[i],
              urunSayisi: d.kalemler.length,
              toplam: d.genelToplam,
              musteri: d.musteri?.unvan,
            );
          }(),
      ];

  /// Satış kaydedilirken sekme değiştirilemez (satış sonrası temizlik
  /// yanlış sekmeyi boşaltmasın).
  bool get _sekmeDegisebilir => !state.satisIsleniyor;

  void _aktifiDegistir(int yeni) {
    _sekmeler[_aktif] = state;
    _aktif = yeni;
    // Bayi fiyat önbelleği müşteriye özgü: sekme değişince sıfırlanır.
    _toptanCache.clear();
    // Yeni nesne: aynı içerikli (boş) sekmeye geçişte de ekran yenilensin.
    state = _sekmeler[yeni].copyWith();
  }

  /// F10: yeni alışveriş sekmesi açar ve ona geçer. Açılamazsa false.
  bool yeniSekme() {
    if (!_sekmeDegisebilir || _sekmeler.length >= maksSekme) return false;
    var no = 2;
    while (_sekmeNo.contains(no)) {
      no++;
    }
    _sekmeler.add(const SepetDurum());
    _sekmeNo.add(no);
    _aktifiDegistir(_sekmeler.length - 1);
    return true;
  }

  /// Sekmeye geç. Satış işlenirken false.
  bool sekmeSec(int i) {
    if (i < 0 || i >= _sekmeler.length || i == _aktif) return i == _aktif;
    if (!_sekmeDegisebilir) return false;
    _aktifiDegistir(i);
    return true;
  }

  /// Sekmeyi kapatır (sekme 1 kapanmaz, boşaltılır). Aktifse sekme 1'e geçer.
  void sekmeKapat(int i) {
    if (i < 0 || i >= _sekmeler.length || !_sekmeDegisebilir) return;
    if (i == 0) {
      if (_aktif == 0) {
        temizle();
      } else {
        _sekmeler[0] = const SepetDurum();
        state = state.copyWith(); // sekme çubuğu yenilensin
      }
      return;
    }
    final aktifti = i == _aktif;
    if (aktifti) _sekmeler[_aktif] = state;
    _sekmeler.removeAt(i);
    _sekmeNo.removeAt(i);
    if (aktifti) {
      _aktif = 0;
      _toptanCache.clear();
      state = _sekmeler[0].copyWith();
    } else {
      if (i < _aktif) _aktif--;
      // Sekme listesi değişti — çubuk yenilensin.
      state = state.copyWith();
    }
  }

  /// Satış bittiğinde: ek sekmeyse kapanır (sekme 1'e dönülür), sekme 1 ise
  /// boşaltılır ve hazır bekler.
  void satisTamamlandi() {
    if (_aktif == 0) {
      temizle();
      return;
    }
    final i = _aktif;
    _sekmeler.removeAt(i);
    _sekmeNo.removeAt(i);
    _aktif = 0;
    _toptanCache.clear();
    state = _sekmeler[0].copyWith();
  }
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
