// lib/saglayicilar/riverpod/satis_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/satis_deposu.dart';
import '../../modeller/satis_model.dart';
import '../../servisler/faturalandirma_servisi.dart';

part 'satis_provider.g.dart';

class SatisFiltre {
  final DateTime basTarih, bitTarih;
  final String aramaMetni;
  SatisFiltre({required this.basTarih, required this.bitTarih, this.aramaMetni = ''});
  SatisFiltre copyWith({DateTime? basTarih, DateTime? bitTarih, String? aramaMetni}) =>
      SatisFiltre(
        basTarih:   basTarih   ?? this.basTarih,
        bitTarih:   bitTarih   ?? this.bitTarih,
        aramaMetni: aramaMetni ?? this.aramaMetni,
      );
}

@riverpod
class SatisFiltresi extends _$SatisFiltresi {
  @override
  SatisFiltre build() {
    final now = DateTime.now();
    return SatisFiltre(
      basTarih: now.subtract(const Duration(days: 7)),
      bitTarih: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }
  void aramaGuncelle(String v) => state = state.copyWith(aramaMetni: v);
  void tarihAyarla(DateTime bas, DateTime bit) =>
      state = state.copyWith(basTarih: bas, bitTarih: bit);
}

class SatisListeDurum {
  final List<SatisModel> satislar;
  final bool yukleniyor, secimModu;
  final Set<int> seciliIds;
  const SatisListeDurum({
    this.satislar  = const [],
    this.yukleniyor= false,
    this.secimModu = false,
    this.seciliIds = const {},
  });
  int    get seciliSayisi => seciliIds.length;
  double get seciliToplam => satislar
      .where((s) => seciliIds.contains(s.id))
      .fold(0.0, (s, m) => s + m.genelToplam);
  SatisListeDurum copyWith({
    List<SatisModel>? satislar, bool? yukleniyor,
    bool? secimModu, Set<int>? seciliIds,
  }) => SatisListeDurum(
    satislar:  satislar  ?? this.satislar,
    yukleniyor:yukleniyor?? this.yukleniyor,
    secimModu: secimModu ?? this.secimModu,
    seciliIds: seciliIds ?? this.seciliIds,
  );
}

@riverpod
class Satislar extends _$Satislar {
  final _depo = SatisDeposu();

  @override
  SatisListeDurum build() {
    ref.listen(satisFiltresiProvider, (_, __) => yukle());
    Future.microtask(yukle);
    return const SatisListeDurum(yukleniyor: true);
  }

  Future<void> yukle() async {
    state = state.copyWith(yukleniyor: true);
    try {
      final f = ref.read(satisFiltresiProvider);
      var liste = await _depo.tariheGoreGetir(f.basTarih, f.bitTarih);
      if (f.aramaMetni.isNotEmpty) {
        final q = f.aramaMetni.toLowerCase();
        liste = liste.where((s) =>
          (s.fisNo?.toLowerCase().contains(q) ?? false) ||
          (s.cariAdi?.toLowerCase().contains(q) ?? false)).toList();
      }
      state = state.copyWith(satislar: liste, yukleniyor: false);
    } catch (_) { state = state.copyWith(yukleniyor: false); }
  }

  void secimToggle(int id) {
    final s = Set<int>.from(state.seciliIds);
    s.contains(id) ? s.remove(id) : s.add(id);
    state = state.copyWith(secimModu: s.isNotEmpty, seciliIds: s);
  }

  void tumunuSec() => state = state.copyWith(
    secimModu: true,
    seciliIds: state.satislar.map((s) => s.id!).toSet(),
  );

  void secimTemizle() =>
      state = state.copyWith(secimModu: false, seciliIds: {});

  /// Döndürdüğü sayı, faturalandırılmış olduğu için ATLANIP silinmeyen
  /// satış adedidir (arayüz bunu kullanıcıya bildirmeli).
  Future<int> seciliSil() async {
    if (state.seciliIds.isEmpty) return 0;
    // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu fonksiyon
    // önceden _depo.satisIptal() çağırıyordu — bu, sadece satışın
    // 'iptal' bayrağını işaretler; STOK GERİ YÜKLEMEZ, MÜŞTERİNİN
    // CARİ BORCUNU GERİ ALMAZ, KASA HAREKETİNİ GERİ ALMAZ. Oysa aynı
    // dosyadaki _depo.sil() TAM OLARAK bunları yapan, kapsamlı geri
    // alma fonksiyonu. Bu ekrandan toplu satış silme yapıldığında,
    // stok yapay olarak düşük kalıyor, müşteri iptal edilmiş bir
    // satış için hâlâ borçlu görünüyor, kasa iptal edilmiş bir satış
    // için hâlâ para almış gibi duruyordu.
    //
    // 🔴 DÜZELTME (kritik — derin denetimde bulundu): Bu toplu silme,
    // codebase'in her yerinde uygulanan "faturalandırılmış bir satış
    // doğrudan silinemez" kuralını HİÇ kontrol etmiyordu — GİB'e
    // gönderilmiş/onaylanmış bir faturası olan satışlar bile sessizce
    // silinebiliyordu. Artık faturası olan satışlar ATLANIYOR.
    var atlanan = 0;
    for (final id in state.seciliIds) {
      try {
        final faturaId = await FaturalandirmaServisi.mevcutFaturaId(satisId: id);
        if (faturaId != null) { atlanan++; continue; }
        await _depo.sil(id);
      } catch (e) { /* ignore */ }
    }
    secimTemizle();
    await yukle();
    return atlanan;
  }
}

@riverpod
Future<Map<String, dynamic>> gunlukSatisOzeti(GunlukSatisOzetiRef ref) =>
    SatisDeposu().gunlukIstatistik();

@riverpod
Future<SatisModel?> satisDetayi(SatisDetayiRef ref, int id) =>
    SatisDeposu().idileGetir(id);
