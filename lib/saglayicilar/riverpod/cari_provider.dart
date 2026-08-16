// lib/saglayicilar/riverpod/cari_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/cari_deposu.dart';
import '../../modeller/cari_model.dart';

part 'cari_provider.g.dart';

class CariFiltre {
  final String aramaMetni, tip, bakiyeFiltre;
  const CariFiltre({this.aramaMetni='', this.tip='Tümü', this.bakiyeFiltre='Tümü'});
  CariFiltre copyWith({String? aramaMetni, String? tip, String? bakiyeFiltre}) =>
      CariFiltre(aramaMetni: aramaMetni ?? this.aramaMetni,
          tip: tip ?? this.tip, bakiyeFiltre: bakiyeFiltre ?? this.bakiyeFiltre);
}

@riverpod
class CariFiltresi extends _$CariFiltresi {
  @override CariFiltre build() => const CariFiltre();
  void aramaGuncelle(String v)     => state = state.copyWith(aramaMetni: v);
  void tipAyarla(String v)          => state = state.copyWith(tip: v);
  void bakiyeFiltreAyarla(String v) => state = state.copyWith(bakiyeFiltre: v);
  void sifirla()                    => state = const CariFiltre();
}

class CariListeDurum {
  final List<CariModel> musteriler, tedarikciler;
  final bool yukleniyor;
  const CariListeDurum({this.musteriler=const[], this.tedarikciler=const[], this.yukleniyor=false});
  int    get musteriSayisi    => musteriler.length;
  int    get tedarikciSayisi  => tedarikciler.length;
  double get toplamAlacak     => musteriler.where((c) => c.bakiye > 0).fold(0.0, (s, c) => s + c.bakiye);
  double get toplamBorc       => tedarikciler.where((c) => c.bakiye < 0).fold(0.0, (s, c) => s + c.bakiye.abs());
  CariListeDurum copyWith({List<CariModel>? musteriler, List<CariModel>? tedarikciler, bool? yukleniyor}) =>
      CariListeDurum(musteriler: musteriler ?? this.musteriler,
          tedarikciler: tedarikciler ?? this.tedarikciler, yukleniyor: yukleniyor ?? this.yukleniyor);
}

@riverpod
class Cariler extends _$Cariler {
  final _depo = CariDeposu();

  @override
  CariListeDurum build() {
    ref.listen(cariFiltresiProvider, (_, __) => yukle());
    Future.microtask(yukle);
    return const CariListeDurum(yukleniyor: true);
  }

  Future<void> yukle() async {
    state = state.copyWith(yukleniyor: true);
    try {
      final f = ref.read(cariFiltresiProvider);
      final metin = f.aramaMetni;
      List<CariModel> m, t;
      if (f.tip == 'Müşteri') {
        m = metin.length >= 2 ? await _depo.ara(metin, tip:'Müşteri') : await _depo.tumunuGetir(tip:'Müşteri');
        t = [];
      } else if (f.tip == 'Tedarikçi') {
        m = [];
        t = metin.length >= 2 ? await _depo.ara(metin, tip:'Tedarikçi') : await _depo.tumunuGetir(tip:'Tedarikçi');
      } else {
        final r = await Future.wait([
          metin.length >= 2 ? _depo.ara(metin, tip:'Müşteri')   : _depo.tumunuGetir(tip:'Müşteri'),
          metin.length >= 2 ? _depo.ara(metin, tip:'Tedarikçi') : _depo.tumunuGetir(tip:'Tedarikçi'),
        ]);
        m = r[0]; t = r[1];
      }
      state = state.copyWith(musteriler: m, tedarikciler: t, yukleniyor: false);
    } catch (_) { state = state.copyWith(yukleniyor: false); }
  }

  Future<List<CariModel>> musterileriGetir() async {
  return _depo.tumunuGetir(tip: 'Müşteri');
}

  Future<void> bakiyeYenidenYukle(int cariId) async {
    try { await _depo.bakiyeYenidenHesapla(cariId); } finally { await yukle(); }
  }

  Future<void> ekle(CariModel c) async { await _depo.ekle(c); await yukle(); }
  Future<void> guncelle(CariModel c) async { await _depo.guncelle(c); await yukle(); }

  Future<void> sil(int id) async {
    await _depo.sil(id);
    state = state.copyWith(
      musteriler:  state.musteriler.where((c)  => c.id != id).toList(),
      tedarikciler: state.tedarikciler.where((c) => c.id != id).toList(),
    );
  }
}

// Granular
@riverpod
List<CariModel> filtreliMusteriler(FiltreliMusterilerRef ref) {
  final d = ref.watch(carilerProvider);
  final f = ref.watch(cariFiltresiProvider);
  return switch (f.bakiyeFiltre) {
    'Alacaklı' => d.musteriler.where((c) => c.bakiye > 0).toList(),
    'Borçlu'   => d.musteriler.where((c) => c.bakiye < 0).toList(),
    'Dengede'  => d.musteriler.where((c) => c.bakiye == 0).toList(),
    _          => d.musteriler,
  };
}

@riverpod
List<CariModel> filtreliTedarikciler(FiltreliTedarikcilerRef ref) {
  final d = ref.watch(carilerProvider);
  final f = ref.watch(cariFiltresiProvider);
  return switch (f.bakiyeFiltre) {
    'Alacaklı' => d.tedarikciler.where((c) => c.bakiye > 0).toList(),
    'Borçlu'   => d.tedarikciler.where((c) => c.bakiye < 0).toList(),
    'Dengede'  => d.tedarikciler.where((c) => c.bakiye == 0).toList(),
    _          => d.tedarikciler,
  };
}

@riverpod
Future<CariModel?> cariDetay(CariDetayRef ref, int id) =>
    CariDeposu().idileGetir(id);

@riverpod
bool cariYukleniyor(CariYukleniyorRef ref) =>
    ref.watch(carilerProvider.select((s) => s.yukleniyor));
