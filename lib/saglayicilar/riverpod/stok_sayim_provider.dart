// lib/saglayicilar/riverpod/stok_sayim_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/stok_deposu.dart';
import '../../depolar/sube_urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/aktif_sube_servisi.dart';

part 'stok_sayim_provider.g.dart';

class StokSayimDurum {
  final List<UrunModel>  urunler, kritikler;
  final Map<int, double> sayimMiktarlari;
  // 🔴 YENİ (derin analizde bulunan eksiklik): Bu ekran ÖNCEDEN her
  // zaman TOPLAM stoğu (urun.stok — tüm şubelerin toplamı) "Mevcut"
  // olarak gösteriyordu. Çok şubeli bir işletmede, biri fiziksel sayımı
  // TEK bir şubede yapar — karşılaştırma tabanı o şubenin GERÇEK payı
  // olmalı, toplam değil. Bu harita, ürün id'sine göre AKTİF ŞUBENİN
  // stok payını tutar.
  final Map<int, double> subeStoklari;
  final bool   yukleniyor, dahaFazla, sadeceSayilan, uygulamaIsleniyor;
  final String aramaMetni;
  final int    sayfa;

  const StokSayimDurum({
    this.urunler           = const [],
    this.kritikler         = const [],
    this.sayimMiktarlari   = const {},
    this.subeStoklari      = const {},
    this.yukleniyor        = false,
    this.dahaFazla         = true,
    this.sadeceSayilan     = false,
    this.uygulamaIsleniyor = false,
    this.aramaMetni        = '',
    this.sayfa             = 0,
  });

  int get sayilanUrunSayisi => sayimMiktarlari.length;
  List<UrunModel> get gosterilenler => sadeceSayilan
      ? urunler.where((u) => sayimMiktarlari.containsKey(u.id)).toList()
      : urunler;

  /// Bir ürün için karşılaştırma tabanı: aktif şubenin bilinen stoğu
  /// varsa onu, yoksa (tek şubeli kurulum / henüz hareket görmemiş
  /// ürün) toplam stoğu döner.
  double mevcutStok(UrunModel u) => subeStoklari[u.id] ?? u.stok;

  StokSayimDurum copyWith({
    List<UrunModel>? urunler, List<UrunModel>? kritikler,
    Map<int, double>? sayimMiktarlari, Map<int, double>? subeStoklari,
    bool? yukleniyor, bool? dahaFazla, bool? sadeceSayilan, bool? uygulamaIsleniyor,
    String? aramaMetni, int? sayfa,
  }) => StokSayimDurum(
    urunler:           urunler           ?? this.urunler,
    kritikler:         kritikler         ?? this.kritikler,
    sayimMiktarlari:   sayimMiktarlari   ?? this.sayimMiktarlari,
    subeStoklari:      subeStoklari      ?? this.subeStoklari,
    yukleniyor:        yukleniyor        ?? this.yukleniyor,
    dahaFazla:         dahaFazla         ?? this.dahaFazla,
    sadeceSayilan:     sadeceSayilan     ?? this.sadeceSayilan,
    uygulamaIsleniyor: uygulamaIsleniyor ?? this.uygulamaIsleniyor,
    aramaMetni:        aramaMetni        ?? this.aramaMetni,
    sayfa:             sayfa             ?? this.sayfa,
  );
}

class SayimSonucu {
  final bool basarili; final String mesaj; final int guncellenen;
  // Madde 13 denetimi (2026-09-16): true ise stok HENÜZ değişmedi —
  // sayım Müdür onayına gönderildi, stok ancak onaylandığında değişir.
  final bool onayaGonderildi;
  const SayimSonucu({
    required this.basarili, required this.mesaj, this.guncellenen = 0,
    this.onayaGonderildi = false,
  });
}

/// Saf/statik yardımcılar — DB/Riverpod'dan bağımsız, doğrudan test edilebilir.
class StokSayimHesap {
  /// Çok şubeli kurulumda kullanıcı SADECE aktif şubenin fiziksel sayımını
  /// girer ([sayilan]); [stokDuzelt] ise urunler.stok'u (TÜM şubelerin
  /// TOPLAMI) mutlak değer olarak yazar. Bu yüzden [stokDuzelt]'e verilecek
  /// yeni TOPLAM, mevcut toplam - eski şube payı + yeni şube sayımı olarak
  /// hesaplanmalı — aksi halde diğer şubelerin stoğu sessizce silinir.
  /// [subeStok] null ise (tek şubeli kurulum / şube seçilmemiş), [sayilan]
  /// doğrudan yeni toplam olarak kabul edilir (eski davranış, değişmedi).
  static double yeniToplamHesapla({
    required double toplamStok,
    required double? subeStok,
    required double sayilan,
  }) => subeStok != null ? (toplamStok - subeStok + sayilan) : sayilan;
}

@riverpod
Future<List<Map<String, dynamic>>> sayimGecmis(SayimGecmisRef ref) =>
    StokDeposu().geciciSayimListesi();

@riverpod
class StokSayim extends _$StokSayim {
  static const _limit = 50;
  final _urunDepo = UrunDeposu();
  final _stokDepo = StokDeposu();
  final _subeUrunDepo = SubeUrunDeposu();

  @override
  StokSayimDurum build() {
    Future.microtask(() => yukle(sifirla: true));
    return const StokSayimDurum(yukleniyor: true);
  }

  Future<void> yukle({bool sifirla = false}) async {
    if (!sifirla && (!state.dahaFazla || state.yukleniyor)) return;
    final sayfa = sifirla ? 0 : state.sayfa;
    state = state.copyWith(yukleniyor: true, sayfa: sayfa,
        urunler: sifirla ? [] : null);
    try {
      final results = await Future.wait([
        state.aramaMetni.length >= 2
            ? _urunDepo.ara(state.aramaMetni, limit: _limit, sadecaAktif: false)
            : _urunDepo.sayfaliGetir(sayfa * _limit, _limit,
                aramaMetni: state.aramaMetni.isEmpty ? null : state.aramaMetni),
        _urunDepo.kritikStoklar(),
      ]);
      final yeni = results[0];

      // 🔴 Derin analizde bulunan eksikliğin düzeltmesi: aktif olarak
      // belirli bir şube seçiliyse (Tüm Şubeler değil), bu sayfadaki
      // her ürün için o şubenin GERÇEK stok payını çekiyoruz — sayım
      // ekranı artık toplam yerine doğru karşılaştırma tabanını
      // gösterebiliyor. Şube seçili değilse (tek şubeli kurulum veya
      // "Tüm Şubeler" görünümü), mevcut davranış (toplam) korunuyor.
      final subeId = AktifSubeServisi().subeId;
      Map<int, double> yeniSubeStoklari = state.subeStoklari;
      if (subeId != null) {
        try {
          final girdiler = await Future.wait(yeni.map((u) async {
            final s = await _subeUrunDepo.stokGetir(u.id!, subeId);
            return MapEntry(u.id!, s);
          }));
          yeniSubeStoklari = {
            if (!sifirla) ...state.subeStoklari,
            ...Map.fromEntries(girdiler),
          };
        } catch (_) {
          // Şube stoğu çekilemezse sessizce geç — toplam stokla devam edilir.
        }
      }

      state = state.copyWith(
        urunler:   sifirla ? yeni : [...state.urunler, ...yeni],
        kritikler: results[1],
        subeStoklari: yeniSubeStoklari,
        dahaFazla: yeni.length >= _limit,
        sayfa:     sayfa + 1,
        yukleniyor:false,
      );
    } catch (_) { state = state.copyWith(yukleniyor: false); }
  }

  void aramaGuncelle(String v) {
    state = state.copyWith(aramaMetni: v, sayfa: 0);
    yukle(sifirla: true);
  }

  void miktarGuncelle(int urunId, double miktar) {
    final yeni = Map<int, double>.from(state.sayimMiktarlari);
    if (miktar < 0) yeni.remove(urunId); else yeni[urunId] = miktar;
    state = state.copyWith(sayimMiktarlari: yeni);
  }

  void urunEkle(UrunModel u) {
    if (state.urunler.any((x) => x.id == u.id)) return;
    state = state.copyWith(urunler: [u, ...state.urunler]);
  }

  void sadeceSayilanToggle() =>
      state = state.copyWith(sadeceSayilan: !state.sadeceSayilan);

  void sayimiSifirla() => state = state.copyWith(sayimMiktarlari: {});

  // 🔴🔴 DÜZELTME (Madde 13 — Sayım Onay Sistemi denetimi, 2026-09-16):
  // ÖNCEDEN her kullanıcı "Uygula"ya bastığı anda stok DOĞRUDAN
  // değişiyordu — hiçbir onay adımı yoktu (dokümanın kendi sözleriyle
  // tam olarak kaçınılması gereken anti-pattern: "Stok sayımı
  // yapıldığında doğrudan stok değiştirme"). Artık: Müdür/Admin
  // sayıyorsa (zaten yetkili kişi) doğrudan uygulanır — ama sıradan bir
  // kullanıcı (kasiyer/personel) sayıyorsa, sayım SADECE 'gecici_sayim'
  // tablosunda BEKLER (stok DEĞİŞMEZ), bir Müdür/Admin Sayım Onayı
  // ekranından ("Onaya gönder → Yetkili onayı → Stok düzeltme hareketi
  // → Audit → Sync" akışı) açıkça onaylamadan hiçbir şey yazılmaz.
  Future<SayimSonucu> uygula() async {
    if (state.sayimMiktarlari.isEmpty) {
      return const SayimSonucu(basarili: false, mesaj: 'Sayım girişi yapılmadı');
    }
    state = state.copyWith(uygulamaIsleniyor: true);
    try {
      final kullaniciId = AuthServisi().aktifKullanici?.id ?? 0;
      final yetkili = AuthServisi().isMudur;
      for (final e in state.sayimMiktarlari.entries) {
        final u = state.urunler.firstWhere((x) => x.id == e.key,
            orElse: () => throw Exception('Ürün bulunamadı'));
        // 🔴🔴 KRİTİK VERİ KAYBI DÜZELTMESİ (komple derin analizde
        // bulundu): bkz. StokSayimHesap.yeniToplamHesapla dokümantasyonu.
        final subeStok = state.subeStoklari[u.id];
        final yeniToplam = StokSayimHesap.yeniToplamHesapla(
            toplamStok: u.stok, subeStok: subeStok, sayilan: e.value);
        await _stokDepo.geciciSayimEkleGuncelle(
            e.key, state.mevcutStok(u), yeniToplam, kullaniciId: kullaniciId);
      }
      final count = state.sayimMiktarlari.length;
      if (yetkili) {
        await _stokDepo.geciciSayimUygula(kullaniciId);
        state = state.copyWith(uygulamaIsleniyor: false, sayimMiktarlari: {});
        await yukle(sifirla: true);
        return SayimSonucu(basarili: true, mesaj: '$count ürün güncellendi', guncellenen: count);
      } else {
        // Stoğa HİÇ dokunulmadı — sadece 'gecici_sayim'de bekliyor.
        state = state.copyWith(uygulamaIsleniyor: false, sayimMiktarlari: {});
        await yukle(sifirla: true);
        return SayimSonucu(
          basarili: true,
          mesaj: '$count ürün Müdür onayına gönderildi — onaylanana kadar stok değişmedi',
          guncellenen: count,
          onayaGonderildi: true,
        );
      }
    } catch (e) {
      state = state.copyWith(uygulamaIsleniyor: false);
      return SayimSonucu(basarili: false, mesaj: e.toString());
    }
  }
}

@riverpod
int sayilanSayisi(SayilanSayisiRef ref) =>
    ref.watch(stokSayimProvider.select((s) => s.sayilanUrunSayisi));
