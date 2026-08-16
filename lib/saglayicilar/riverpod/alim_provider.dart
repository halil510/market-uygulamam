// lib/saglayicilar/riverpod/alim_provider.dart
import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/sepet_model.dart';
import '../../modeller/cari_model.dart';

part 'alim_provider.g.dart';

class AlimDurum {
  final List<SepetKalem> kalemler;
  final List<UrunModel>  aramaSonuclari;
  final CariModel?       tedarikci;
  final bool             kameraAcik, kayitIsleniyor;
  final String           odemeYontemi;

  const AlimDurum({
    this.kalemler       = const [],
    this.aramaSonuclari = const [],
    this.tedarikci,
    this.kameraAcik     = false,
    this.kayitIsleniyor = false,
    this.odemeYontemi   = 'Nakit',
  });

  bool   get sepetBos    => kalemler.isEmpty;
  double get genelToplam => kalemler.fold(0.0, (s, k) => s + k.toplamTutar);

  AlimDurum copyWith({
    List<SepetKalem>?    kalemler,
    List<UrunModel>?     aramaSonuclari,
    CariModel? Function()? tedarikci,
    bool?                kameraAcik,
    bool?                kayitIsleniyor,
    String?              odemeYontemi,
  }) => AlimDurum(
    kalemler:       kalemler       ?? this.kalemler,
    aramaSonuclari: aramaSonuclari ?? this.aramaSonuclari,
    tedarikci:      tedarikci      != null ? tedarikci()  : this.tedarikci,
    kameraAcik:     kameraAcik     ?? this.kameraAcik,
    kayitIsleniyor: kayitIsleniyor ?? this.kayitIsleniyor,
    odemeYontemi:   odemeYontemi   ?? this.odemeYontemi,
  );
}

@riverpod
class Alim extends _$Alim {
  final _urunDepo = UrunDeposu();
  Timer? _debounce;

  @override
  AlimDurum build() => const AlimDurum();

  void araDebounce(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { state = state.copyWith(aramaSonuclari: []); return; }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final s = await _urunDepo.ara(q.trim(), limit: 12);
      state = state.copyWith(aramaSonuclari: s);
    });
  }

  void urunEkle(UrunModel u, {double? alisFiyat}) {
    final fiyat  = alisFiyat ?? u.alisFiyat;
    final liste  = List<SepetKalem>.from(state.kalemler);
    final idx    = liste.indexWhere((k) => k.urun.id == u.id);
    if (idx >= 0) liste[idx] = liste[idx].copyWith(miktar: liste[idx].miktar + 1);
    else liste.add(SepetKalem(urun: u, birimFiyat: fiyat));
    state = state.copyWith(kalemler: liste, aramaSonuclari: []);
  }

  void miktarDegistir(int i, double miktar) {
    final liste = List<SepetKalem>.from(state.kalemler);
    if (miktar <= 0) liste.removeAt(i); else liste[i] = liste[i].copyWith(miktar: miktar);
    state = state.copyWith(kalemler: liste);
  }

  void sil(int i) => state = state.copyWith(
      kalemler: List<SepetKalem>.from(state.kalemler)..removeAt(i));
  void tedarikciSec(CariModel? c) => state = state.copyWith(tedarikci: () => c);
  void odemeYontemiAyarla(String v) => state = state.copyWith(odemeYontemi: v);
  void kameraToggle() => state = state.copyWith(kameraAcik: !state.kameraAcik);
  void temizle()      => state = const AlimDurum();
}
