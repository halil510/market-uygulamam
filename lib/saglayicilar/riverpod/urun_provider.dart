// lib/saglayicilar/riverpod/urun_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';

part 'urun_provider.g.dart';

// ── Filtre ──────────────────────────────────────────────────────
class UrunFiltre {
  final String aramaMetni, siralama;
  final bool? sadecKritikler;
  // Kullanıcı isteği: filtreleme ekranına grup (kategori) filtresi
  // de eklenmesi.
  final String? grupFiltre;
  const UrunFiltre({
    this.aramaMetni   = '',
    this.siralama     = 'isim',
    this.sadecKritikler,
    this.grupFiltre,
  });
  UrunFiltre copyWith({String? aramaMetni, String? siralama, bool? sadecKritikler,
      String? grupFiltre, bool grupuTemizle = false}) =>
      UrunFiltre(
        aramaMetni:     aramaMetni     ?? this.aramaMetni,
        siralama:       siralama       ?? this.siralama,
        sadecKritikler: sadecKritikler ?? this.sadecKritikler,
        grupFiltre:     grupuTemizle ? null : (grupFiltre ?? this.grupFiltre),
      );
}

@riverpod
class UrunFiltresi extends _$UrunFiltresi {
  @override UrunFiltre build() => const UrunFiltre();
  void aramaGuncelle(String v) => state = state.copyWith(aramaMetni: v);
  void kritikToggle()          => state = state.copyWith(sadecKritikler: !(state.sadecKritikler ?? false));
  void siralamaGuncelle(String v) => state = state.copyWith(siralama: v);
  void grupGuncelle(String? v) => state = v == null
      ? state.copyWith(grupuTemizle: true)
      : state.copyWith(grupFiltre: v);
  void sifirla()               => state = const UrunFiltre();
}

// ── Liste durumu ─────────────────────────────────────────────────
class UrunListeDurum {
  final List<UrunModel> urunler;
  final bool yukleniyor, dahaSonraVar, secimModu;
  final Set<int> seciliIds;
  final int sayfa;

  const UrunListeDurum({
    this.urunler      = const [],
    this.yukleniyor   = false,
    this.dahaSonraVar = true,
    this.secimModu    = false,
    this.seciliIds    = const {},
    this.sayfa        = 0,
  });

  UrunListeDurum copyWith({
    List<UrunModel>? urunler, bool? yukleniyor,
    bool? dahaSonraVar, bool? secimModu,
    Set<int>? seciliIds, int? sayfa,
  }) => UrunListeDurum(
    urunler:      urunler      ?? this.urunler,
    yukleniyor:   yukleniyor   ?? this.yukleniyor,
    dahaSonraVar: dahaSonraVar ?? this.dahaSonraVar,
    secimModu:    secimModu    ?? this.secimModu,
    seciliIds:    seciliIds    ?? this.seciliIds,
    sayfa:        sayfa        ?? this.sayfa,
  );
}

@riverpod
class Urunler extends _$Urunler {
  static const _limit = 50;
  final _depo = UrunDeposu();

  @override
  UrunListeDurum build() {
    ref.listen(urunFiltresiProvider, (_, __) => yukle(sifirla: true));
    Future.microtask(() => yukle(sifirla: true));
    return const UrunListeDurum(yukleniyor: true);
  }

  Future<void> yukle({bool sifirla = false}) async {
    if (!sifirla && (!state.dahaSonraVar || state.yukleniyor)) return;
    final sayfa = sifirla ? 0 : state.sayfa;
    state = state.copyWith(yukleniyor: true, sayfa: sayfa,
        urunler: sifirla ? [] : null);
    try {
      final f = ref.read(urunFiltresiProvider);
      List<UrunModel> yeni;
      if (f.aramaMetni.length >= 2) {
        // ÖNCEDEN burada offset hiç verilmiyordu — "daha fazla yükle"
        // her zaman aynı ilk 50 sonucu tekrar getirip listeye tekrar
        // ekliyordu (50'den fazla eşleşme varsa sonsuz, yinelenen
        // kaydırma). Artık sayfa numarasına göre doğru offset veriliyor.
        yeni = await _depo.ara(f.aramaMetni, limit: _limit, offset: sayfa * _limit);
      } else {
        yeni = await _depo.sayfaliGetir(sayfa * _limit, _limit,
            aramaMetni: f.aramaMetni.isEmpty ? null : f.aramaMetni,
            grup: f.grupFiltre,
            siralama: f.siralama);
      }
      final hamUzunluk = yeni.length;
      if (f.sadecKritikler == true) {
        yeni = yeni.where((u) => u.kritikStok).toList();
      }
      final mevcut = sifirla ? <UrunModel>[] : state.urunler;
      state = state.copyWith(
        urunler:      [...mevcut, ...yeni],
        yukleniyor:   false,
        // 🔴 DÜZELTME: "sadece kritik stoklar" filtresi aktifken,
        // dahaSonraVar HESABI filtrelenmiş (küçük) 'yeni' listesinin
        // uzunluğuna bakıyordu — bir sayfada (50 üründen) sadece 3
        // kritik ürün varsa 3 != 50 olduğu için "daha fazla yükle"
        // HEMEN durur, sonraki sayfalardaki kritik ürünler asla
        // yüklenmezdi. Artık ham (filtrelenmemiş) sayfa boyutuna göre
        // hesaplanıyor.
        dahaSonraVar: hamUzunluk == _limit,
        sayfa:        sayfa + 1,
      );
    } catch (e) {
      state = state.copyWith(yukleniyor: false);
      if (kDebugMode) debugPrint('Urunler.yukle: $e');
    }
  }

  Future<void> ekle(UrunModel u) async {
    final id = await _depo.ekle(u);
    state = state.copyWith(urunler: [u.copyWith(id: id), ...state.urunler]);
  }

  Future<void> guncelle(UrunModel u) async {
    await _depo.guncelle(u);
    state = state.copyWith(
        urunler: state.urunler.map((x) => x.id == u.id ? u : x).toList());
  }

  Future<void> sil(int id) async {
    await _depo.sil(id);
    state = state.copyWith(urunler: state.urunler.where((u) => u.id != id).toList());
  }

  void secimToggle(int id) {
    final s = Set<int>.from(state.seciliIds);
    s.contains(id) ? s.remove(id) : s.add(id);
    state = state.copyWith(secimModu: s.isNotEmpty, seciliIds: s);
  }

  void tumunuSec() => state = state.copyWith(
      secimModu: true, seciliIds: state.urunler.map((u) => u.id!).toSet());

  void secimTemizle() => state = state.copyWith(secimModu: false, seciliIds: {});
}

// ── Granular ─────────────────────────────────────────────────────
@riverpod
bool urunYukleniyor(UrunYukleniyorRef ref) =>
    ref.watch(urunlerProvider.select((s) => s.yukleniyor));

@riverpod
bool urunSecimModu(UrunSecimModuRef ref) =>
    ref.watch(urunlerProvider.select((s) => s.secimModu));

@riverpod
int urunSeciliSayisi(UrunSeciliSayisiRef ref) =>
    ref.watch(urunlerProvider.select((s) => s.seciliIds.length));

@riverpod
int kritikStokSayisi(KritikStokSayisiRef ref) =>
    ref.watch(urunlerProvider.select(
        (s) => s.urunler.where((u) => u.kritikStok).length));

@riverpod
Future<UrunModel?> urunDetay(UrunDetayRef ref, int id) =>
    UrunDeposu().idileGetir(id);

@riverpod
Future<UrunModel?> barkodileUrunBul(BarkodileUrunBulRef ref, String barkod) =>
    UrunDeposu().barkodlaGetir(barkod);
