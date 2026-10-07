// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: `part of 'iade_ekrani.dart'` + `extension ... on _IadeEkraniState`
// (bkz. iade_ekrani_fis.dart başındaki açıklama) — setState aynı State
// üzerinde çağrılır, analizci yalnız extension'dan "korumalı üye" uyarısı verir.
// lib/ekranlar/satis/iade_ekrani_arama.dart
//
// İade sekmesinin ÜRÜN ve CARİ SEÇİMİ: ürün arama, barkod, seçilen ürünün
// cari tipine göre iade fiyatı önizlemesi, cari seç/kaldır (2026-10-07
// refactor — iade_ekrani.dart'tan davranış birebir korunarak taşındı).
part of 'iade_ekrani.dart';

extension _IadeAramaExt on _IadeEkraniState {
  // ── Ürün arama ────────────────────────────────────────────────────────────
  void _aramaDebounce() {
    _debounce?.cancel();
    final q = _aramaCtrl.text.trim();
    if (q.isEmpty) {
      _aramaListesi = [];
      if (mounted) setState(() {});
      return;
    }
    if (q.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 280), () => _ara(q));
  }

  void _ara(String q) {
    final ql = aramaNormalize(q);
    final res = _tumUrunler
        .where((u) =>
            aramaNormalize(u.ad).contains(ql) ||
            aramaNormalize(u.barkod ?? '').contains(ql))
        .toList();
    if (!mounted) return;
    _aramaListesi = res;
    setState(() {});
    if (res.length == 1) _secilenUrunAyarla(res.first);
  }

  void _aramayiTemizle() {
    _aramaCtrl.clear();
    _aramaListesi = [];
    if (mounted) setState(() {});
  }

  /// Arama kutusunda Enter: barkoda benziyorsa barkod gibi işle, tek sonuç
  /// varsa onu seç.
  void _aramaGonder(String q) {
    final b = q.trim();
    if (barkodaBenziyor(b)) {
      _barkodIsle(b);
    } else if (_aramaListesi.length == 1) {
      _secilenUrunAyarla(_aramaListesi.first);
    }
  }

  // ── Ürün seçimi ───────────────────────────────────────────────────────────
  void _secilenUrunAyarla(UrunModel u) {
    // Aynı ürün bu oturumda iade edilmişse öne çek
    final mevcutIdx = _iadeListesi.indexWhere((i) => i['urun_id'] == u.id);
    if (mevcutIdx > 0) {
      final mevcut = _iadeListesi.removeAt(mevcutIdx);
      _iadeListesi.insert(0, mevcut);
      _msg('${u.urunAdi} daha önce iade edildi — öne çekildi', err: false);
    }
    setState(() {
      _secilenUrun = u;
      _aramaListesi = [];
      _miktar = 1;
      _miktarCtrl.text = '1';
    });
    _aramaCtrl.clear();
    _tab.animateTo(0);
    _iadeFiyatiniGuncelle(); // fiyat cari tipine göre
    // Mevcut stok BAYAT görünmesin (başka kasada/ekranda satış/iade olmuş
    // olabilir): seçimden sonra güncel kaydı okuyup yerine koy.
    _guncelStoguYukle(u);
  }

  Future<void> _guncelStoguYukle(UrunModel u) async {
    if (u.id == null) return;
    try {
      final guncel = await _urunDepo.idileGetir(u.id!);
      if (guncel == null || !mounted) return;
      if (_secilenUrun?.id == u.id) setState(() => _secilenUrun = guncel);
    } catch (_) {/* eldeki değerle devam */}
  }

  /// Bu iadede aynı üründen daha önce eklenmiş miktar (formda gösterilir).
  double get _oncekiIadeMiktari => _iadeListesi
      .where((x) => x['urun_id'] == _secilenUrun?.id)
      .fold<double>(0, (s, x) => s + ((x['miktar'] as num?)?.toDouble() ?? 0));

  // ── Cari tipine göre fiyat ────────────────────────────────────────────────
  CariIadeTuru get _cariIadeTuru => CariIadeTuru.belirle(_secilenCari);

  /// Seçili ürün için formdaki iade fiyatını cari tipine göre yeniler (bkz.
  /// CariIadeTuru.onizlemeFiyati). Asenkron sonuç gelene kadar ürün
  /// değiştiyse sonuç yok sayılır.
  Future<void> _iadeFiyatiniGuncelle() async {
    final urun = _secilenUrun;
    if (urun == null) return;
    final tur = _cariIadeTuru;
    final double fiyat;
    try {
      fiyat = await tur.onizlemeFiyati(urun, cari: _secilenCari, miktar: _miktar);
    } catch (e) {
      _msg('İade fiyatı hesaplanamadı: ${kullaniciyaHataMetni(e)}', err: true);
      return;
    }
    if (!mounted || _secilenUrun?.id != urun.id) return;
    setState(() {
      _orijinalFiyat = fiyat;
      _fiyatCtrl.text = fiyat.toStringAsFixed(2);
      if (tur.fiyatKuralli) _iskontoCtrl.text = '0';
    });
  }

  // ── Barkod ────────────────────────────────────────────────────────────────
  Future<void> _barkodOku() async {
    final barkod = await _barkodSrv.barkodTara(context);
    if (barkod == null || barkod.isEmpty) return;
    await _barkodIsle(barkod);
  }

  /// Kamera, arama kutusunda Enter ve el terminali / USB okuyucu (bkz.
  /// DonanimBarkodDinleyici) buradan geçer.
  Future<void> _barkodIsle(String barkod) async {
    try {
      _aramaCtrl.clear();
      if (mounted) setState(() => _aramaListesi = []);

      // 🔴 DÜZELTME (Madde 34 — Barkod/POS denetimi, 2026-09-20): terazi
      // barkodu (13 hane, prefix 20-29, gömülü ürün kodu+ağırlık) iadede de
      // çözülür — önceden literal aranıp hiç eşleşmiyordu.
      final tartim = BarkodServisi.tartimBarkodCoz(barkod);
      final aranacakKod = tartim?.urunKodu ?? barkod;
      final urun = await _urunDepo.barkodlaGetir(aranacakKod);
      if (!mounted) return;
      if (urun == null) {
        _msg('Ürün bulunamadı: $barkod', err: true);
        return;
      }
      _secilenUrunAyarla(urun);
      // Terazi barkodundaki gömülü ağırlığı ön-doldur (satıştaki AYNI
      // davranış) — kasiyer yine de elle düzeltebilir.
      if (tartim != null && mounted) {
        setState(() {
          _miktar = tartim.miktarKg;
          _miktarCtrl.text = tartim.miktarKg.toStringAsFixed(3);
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
    }
  }

  // ── Cari seçimi ───────────────────────────────────────────────────────────
  /// AppBar'daki "Müşteri Seç". Kayıtlı müşteride varsayılan iade yöntemi
  /// 'Cari' (borcundan düşülür — profesyonel ERP davranışı); elden para
  /// verilecekse formdaki "İade Yöntemi"nden Nakit seçilir.
  Future<void> _musteriSec() async {
    final secilen = await showDialog<CariModel?>(
        context: context, builder: (ctx) => CariSecDialog(cariler: _cariler));
    if (secilen == null || !mounted) return;
    setState(() {
      _secilenCari = secilen;
      if (secilen.id == null && _iadeOdemeYontemi == 'Cari') {
        _iadeOdemeYontemi = 'Nakit';
      } else if (secilen.id != null) {
        _iadeOdemeYontemi = 'Cari';
      }
    });
    _iadeFiyatiniGuncelle(); // fiyat kuralı cari tipine bağlı
  }

  void _cariyiKaldir() {
    setState(() {
      _secilenCari = null;
      // 'Cari' ödeme seçeneği artık dropdown'da yok — seçili kalırsa
      // DropdownButtonFormField geçersiz değerle çöker.
      if (_iadeOdemeYontemi == 'Cari') _iadeOdemeYontemi = 'Nakit';
    });
    _iadeFiyatiniGuncelle();
  }

  Future<CariModel?> _cariSecimDialog() => showDialog<CariModel>(
        context: context,
        builder: (ctx) => CariSecDialog(cariler: _cariler),
      );

  /// Kayıtlı müşteriye iade: borcundan mı düşülsün, elden mi ödensin?
  /// null = vazgeçti.
  Future<String?> _cariIadeYontemiSor(String unvan) => showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('İade nasıl yapılsın?'),
          content: Text('$unvan için iade tutarı:'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'Nakit'),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Nakit ver (kasadan)'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'Cari'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Borcundan düş (Cari)'),
            ),
          ],
        ),
      );
}
