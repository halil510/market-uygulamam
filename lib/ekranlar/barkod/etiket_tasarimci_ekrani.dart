// lib/ekranlar/barkod/etiket_tasarimci_ekrani.dart
//
// Kendi etiket tasarımını görerek düzenleme. Tuvalde gösterilen resim, yazıcıya giden çıktının AYNISIDIR
// (aynı PDF çizimi, yazıcı çözünürlüğünde): ne görülüyorsa o basılır.
//   • Öğeyi sürükleyerek taşı, sağ alt köşedeki tutamaçla boyutlandır; boş yere dokununca seçim kalkar.
//   • Klavye (masaüstü): ok tuşları 0,5 mm (Shift: 2 mm), Delete sil, Ctrl+D çoğalt, Ctrl+Z / Ctrl+Y geri / ileri, Ctrl+S kaydet.
//   • Sağdaki panel: etiket adı / ölçüsü, öğe listesi ve ekleme, seçili öğenin tüm ayarları, tasarım uyarıları.
// Hazır (BarTender) şablonlar burada değiştirilmez: "Kopyasını düzenle" ile kendi tasarım olarak açılır.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cekirdek/etiket/etiket_tasarimi.dart';
import '../../cekirdek/etiket/raf_etiket_sablonlari.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/etiket_ayarlari.dart';
import '../../servisler/etiket_baski_servisi.dart';
import '../../widgetlar/masaustu/ekran_ustte.dart';

/// Tasarımcıyı açar; kaydedilirse kaydedilen tasarımı döner (cihaza zaten yazılmıştır).
Future<EtiketSablonu?> etiketTasarimciAc(BuildContext context, EtiketSablonu tasarim, {EtiketVeri? ornek}) async {
  assert(tasarim.kendi, 'Yalnız kendi tasarımlar düzenlenir');
  final ayar = await EtiketAyarlari.yaziciYukle();
  final firma = await EtiketBaskiServisi.firmaAdi();
  if (!context.mounted) return null;
  return Navigator.of(context).push<EtiketSablonu>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => EtiketTasarimciEkrani(tasarim: tasarim, ornek: ornek, mensei: ayar.mensei, firma: firma),
  ));
}

class EtiketTasarimciEkrani extends StatefulWidget {
  final EtiketSablonu tasarim;
  final EtiketVeri? ornek;
  final String mensei, firma;
  const EtiketTasarimciEkrani({super.key, required this.tasarim, this.ornek, this.mensei = 'Türkiye', this.firma = ''});

  @override
  State<EtiketTasarimciEkrani> createState() => _EtiketTasarimciEkraniState();
}

class _EtiketTasarimciEkraniState extends State<EtiketTasarimciEkrani> {
  late EtiketSablonu _s = widget.tasarim;
  int? _sec;
  final _geri = <EtiketSablonu>[], _ileri = <EtiketSablonu>[];
  bool _degisti = false, _kaydediliyor = false;
  bool _kutular = true; // öğe sınırlarını göster
  bool _olcekle = true; // etiket boyu değişince öğeleri de ölçekle
  int _disRev = 0; // geri al / yinele: alanlar yeniden kurulsun
  final _panelKaydirma = ScrollController();
  late final _adCtrl = TextEditingController(text: widget.tasarim.ad);
  late final _veri = widget.ornek ?? ornekEtiketVerisi();

  Uint8List? _png;
  bool _cizimHatasi = false;
  Timer? _cizZamani;
  int _cizNo = 0;

  // sürükleme / boyutlandırma başlangıcı
  Oge? _bas;
  Offset _toplam = Offset.zero;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tus);
    IcGeri.ekle(_icGeri);
    _ciz(hemen: true);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tus);
    IcGeri.cikar(_icGeri);
    _cizZamani?.cancel();
    _adCtrl.dispose();
    _panelKaydirma.dispose();
    super.dispose();
  }

  // ── Durum ──

  void _gecmiseEkle() {
    _geri.add(_s);
    if (_geri.length > 80) _geri.removeAt(0);
    _ileri.clear();
  }

  void _guncelle(EtiketSablonu yeni, {bool gecmise = true}) {
    if (gecmise) _gecmiseEkle();
    setState(() {
      _s = yeni;
      _degisti = true;
      if (_sec != null && _sec! >= _s.ogeler.length) _sec = null;
    });
    _ciz();
  }

  void _ogeDegistir(int i, Oge o, {bool gecmise = true}) {
    final l = [..._s.ogeler];
    l[i] = o;
    _guncelle(_s.kopya(ogeler: l), gecmise: gecmise);
  }

  void _geriAl() {
    if (_geri.isEmpty) return;
    _ileri.add(_s);
    setState(() {
      _s = _geri.removeLast();
      _degisti = true;
      _disRev++;
      if (_sec != null && _sec! >= _s.ogeler.length) _sec = null;
    });
    _ciz();
  }

  void _yinele() {
    if (_ileri.isEmpty) return;
    _geri.add(_s);
    setState(() {
      _s = _ileri.removeLast();
      _degisti = true;
      _disRev++;
      if (_sec != null && _sec! >= _s.ogeler.length) _sec = null;
    });
    _ciz();
  }

  void _ciz({bool hemen = false}) {
    _cizZamani?.cancel();
    _cizZamani = Timer(Duration(milliseconds: hemen ? 0 : 140), () async {
      final no = ++_cizNo;
      try {
        final png = await EtiketBaskiServisi.onizlemePng(_s, _veri, mensei: widget.mensei, firma: widget.firma, dpi: 203);
        if (mounted && no == _cizNo) {
          setState(() {
            _png = png;
            _cizimHatasi = false;
          });
        }
      } catch (e) {
        if (mounted && no == _cizNo) setState(() => _cizimHatasi = true);
      }
    });
  }

  // ── Öğe işlemleri ──

  /// Öğe seç (null: seçimi kaldır). Yeni öğe seçilince ayarları en üstte olduğundan panel başa kaydırılır.
  void _secim(int? i) {
    if (i == _sec) return;
    setState(() => _sec = i);
    if (i != null && _panelKaydirma.hasClients && _panelKaydirma.offset > 0) {
      _panelKaydirma.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _ekle(Oge o) {
    final yeni = sigdir(o, _s);
    _guncelle(_s.kopya(ogeler: [..._s.ogeler, yeni]));
    _secim(_s.ogeler.length - 1);
  }

  void _sil() {
    final i = _sec;
    if (i == null) return;
    final l = [..._s.ogeler]..removeAt(i);
    _guncelle(_s.kopya(ogeler: l));
    setState(() => _sec = null);
  }

  void _cogalt() {
    final i = _sec;
    if (i == null) return;
    final o = _s.ogeler[i];
    _ekle(o.konumla(x: mm1(o.x + 1.5), y: mm1(o.y + 1.5)));
  }

  /// Seçili öğeyi bir öne / arkaya (üstte çizilen sonra gelir).
  void _sira(int yon) {
    final i = _sec;
    if (i == null) return;
    final j = i + yon;
    if (j < 0 || j >= _s.ogeler.length) return;
    final l = [..._s.ogeler];
    final t = l[i];
    l[i] = l[j];
    l[j] = t;
    _guncelle(_s.kopya(ogeler: l));
    setState(() => _sec = j);
  }

  void _kaydir(double dx, double dy) {
    final i = _sec;
    if (i == null) return;
    final o = _s.ogeler[i];
    _ogeDegistir(i, o.konumla(x: mm1(_sinirla(o.x + dx, 0, _s.genislik - o.g)), y: mm1(_sinirla(o.y + dy, 0, _s.yukseklik - o.h))));
  }

  static double _sinirla(double v, double a, double b) => b < a ? a : v.clamp(a, b).toDouble();

  void _olcuDegistir(double g, double h) {
    g = g.clamp(enKucukOlcu, enBuyukOlcu).toDouble();
    h = h.clamp(enKucukOlcu, enBuyukOlcu).toDouble();
    if ((g - _s.genislik).abs() < 0.01 && (h - _s.yukseklik).abs() < 0.01) return;
    _guncelle(_olcekle ? olcekle(_s, g, h) : _s.kopya(genislik: g, yukseklik: h));
  }

  // ── Klavye ──

  bool _tus(KeyEvent e) {
    if (e is KeyUpEvent || !mounted || !ekranUstte(context)) return false;
    if (yaziAlaniOdakta()) return false;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final adim = HardwareKeyboard.instance.isShiftPressed ? 2.0 : 0.5;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      _geriAl();
    } else if (ctrl && k == LogicalKeyboardKey.keyY) {
      _yinele();
    } else if (ctrl && k == LogicalKeyboardKey.keyS) {
      _kaydet();
    } else if (ctrl && k == LogicalKeyboardKey.keyD) {
      _cogalt();
    } else if (_sec != null && k == LogicalKeyboardKey.arrowLeft) {
      _kaydir(-adim, 0);
    } else if (_sec != null && k == LogicalKeyboardKey.arrowRight) {
      _kaydir(adim, 0);
    } else if (_sec != null && k == LogicalKeyboardKey.arrowUp) {
      _kaydir(0, -adim);
    } else if (_sec != null && k == LogicalKeyboardKey.arrowDown) {
      _kaydir(0, adim);
    } else if (_sec != null && k == LogicalKeyboardKey.delete && e is KeyDownEvent) {
      _sil();
    } else {
      return false;
    }
    return true;
  }

  /// Masaüstünde Esc / üst şeritteki "Geri" sayfayı doğrudan kapatır (PopScope'u görmez): önce seçimi kaldırır,
  /// kaydedilmemiş değişiklik varsa sorar — tasarım sorusuz kaybolmaz.
  bool _icGeri() {
    if (!mounted || !ekranUstte(context)) return false;
    if (_sec != null) {
      _secim(null);
      return true;
    }
    if (!_degisti) return false; // değişiklik yok: normal geri
    () async {
      if (await _cikisOnayi() && mounted) {
        _degisti = false;
        Navigator.of(context).pop();
      }
    }();
    return true;
  }

  // ── Kaydet / çık ──

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    final ad = _adCtrl.text.trim();
    if (ad.isEmpty) {
      BildirimServisi.uyari(context, 'Tasarıma bir ad verin');
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final t = _s.kopya(ad: ad);
      await EtiketAyarlari.tasarimKaydet(t);
      if (!mounted) return;
      _degisti = false;
      Navigator.of(context).pop(t);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Tasarım kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  Future<bool> _cikisOnayi() async {
    if (!_degisti) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Değişiklikler kaydedilmedi'),
        content: const Text('Tasarımda yaptığınız değişiklikler kaydedilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'vazgec'), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(c, 'at'), child: const Text('Kaydetmeden çık')),
          FilledButton(onPressed: () => Navigator.pop(c, 'kaydet'), child: const Text('Kaydet')),
        ],
      ),
    );
    if (r == 'kaydet') {
      await _kaydet();
      return false; // _kaydet kendisi kapatır
    }
    return r == 'at';
  }

  // ── Görünüm ──

  @override
  Widget build(BuildContext context) {
    final genis = MediaQuery.sizeOf(context).width >= 980;
    return PopScope(
      canPop: !_degisti,
      onPopInvokedWithResult: (cikti, _) async {
        if (cikti) return;
        if (await _cikisOnayi() && context.mounted) {
          _degisti = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Etiket tasarımı · ${_s.olcu}'),
          actions: [
            IconButton(tooltip: 'Geri al (Ctrl+Z)', icon: const Icon(Icons.undo), onPressed: _geri.isEmpty ? null : _geriAl),
            IconButton(tooltip: 'Yinele (Ctrl+Y)', icon: const Icon(Icons.redo), onPressed: _ileri.isEmpty ? null : _yinele),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: FilledButton.icon(
                onPressed: _kaydediliyor ? null : _kaydet,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Kaydet'),
              ),
            ),
          ],
        ),
        body: genis
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _tuvalBolumu()),
                const VerticalDivider(width: 1),
                SizedBox(width: 420, child: _panel()),
              ])
            : Column(children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * .36, child: _tuvalBolumu()),
                const Divider(height: 1),
                Expanded(child: _panel()),
              ]),
      ),
    );
  }

  Widget _tuvalBolumu() {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(children: [
            Expanded(
              child: Text(
                'Sürükleyerek taşıyın, sağ alt köşeden boyutlandırın. Ok tuşları 0,5 mm (Shift: 2 mm).',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            FilterChip(
              label: const Text('Sınırlar', style: TextStyle(fontSize: 12)),
              selected: _kutular,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setState(() => _kutular = v),
            ),
          ]),
        ),
        Expanded(child: _tuval()),
      ]),
    );
  }

  Widget _tuval() => LayoutBuilder(builder: (c, k) {
        final olcek = math.max(1.0, math.min((k.maxWidth - 40) / _s.genislik, (k.maxHeight - 40) / _s.yukseklik));
        final w = _s.genislik * olcek, h = _s.yukseklik * olcek;
        final cs = Theme.of(context).colorScheme;
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => _secim(null),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black38, width: 0.8),
                      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                  ),
                ),
              ),
              if (_png != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Image.memory(_png!, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                  ),
                ),
              if (_cizimHatasi)
                const Positioned(right: 4, top: 4, child: Icon(Icons.error_outline, color: Colors.red, size: 18)),
              for (var i = 0; i < _s.ogeler.length; i++) _ogeKutusu(i, olcek, cs),
            ]),
          ),
        );
      });

  Widget _ogeKutusu(int i, double olcek, ColorScheme cs) {
    final o = _s.ogeler[i];
    final secili = _sec == i;
    return Positioned(
      left: o.x * olcek,
      top: o.y * olcek,
      width: math.max(4, o.g * olcek),
      height: math.max(4, o.h * olcek),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _secim(i),
              onPanStart: (_) {
                _secim(i);
                _gecmiseEkle();
                _bas = _s.ogeler[i];
                _toplam = Offset.zero;
              },
              onPanUpdate: (d) {
                final b = _bas;
                if (b == null) return;
                _toplam += d.delta;
                _ogeDegistir(
                  i,
                  b.konumla(
                    x: mm1(_sinirla(b.x + _toplam.dx / olcek, 0, _s.genislik - b.g)),
                    y: mm1(_sinirla(b.y + _toplam.dy / olcek, 0, _s.yukseklik - b.h)),
                  ),
                  gecmise: false,
                );
              },
              onPanEnd: (_) => _bas = null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: secili ? cs.primary.withValues(alpha: 0.08) : null,
                  border: secili
                      ? Border.all(color: cs.primary, width: 1.6)
                      : (_kutular ? Border.all(color: Colors.blue.withValues(alpha: 0.35), width: 0.8) : null),
                ),
              ),
            ),
          ),
        ),
        if (secili)
          Positioned(
            right: -7,
            bottom: -7,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeDownRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  _gecmiseEkle();
                  _bas = _s.ogeler[i];
                  _toplam = Offset.zero;
                },
                onPanUpdate: (d) {
                  final b = _bas;
                  if (b == null) return;
                  _toplam += d.delta;
                  _ogeDegistir(
                    i,
                    b.konumla(
                      g: mm1(_sinirla(b.g + _toplam.dx / olcek, 1, _s.genislik - b.x)),
                      h: mm1(_sinirla(b.h + _toplam.dy / olcek, 1, _s.yukseklik - b.y)),
                    ),
                    gecmise: false,
                  );
                },
                onPanEnd: (_) => _bas = null,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  // ── Panel ──

  Widget _panel() {
    final sorunlar = tasarimSorunlari(_s);
    return ListView(controller: _panelKaydirma, padding: const EdgeInsets.all(14), children: [
      // Seçili öğenin ayarları en üstte (telefonda tuvalin hemen altında görünsün).
      if (_sec != null) ...[
        // Seçim / geri al değişince alanlar (açılır listeler dahil) yeni öğeyle kurulsun.
        KeyedSubtree(key: ValueKey('secili-$_sec-$_disRev'), child: _seciliOgePaneli(_sec!)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.done, size: 18),
            label: const Text('Seçimi bitir'),
            onPressed: () => _secim(null),
          ),
        ),
        const Divider(height: 24),
      ],
      _baslik('Etiket'),
      TextField(
        controller: _adCtrl,
        decoration: const InputDecoration(labelText: 'Tasarım adı', border: OutlineInputBorder(), isDense: true),
        onChanged: (_) => _degisti = true,
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: SayiAlani(
            etiket: 'Genişlik (mm)',
            deger: _s.genislik,
            min: enKucukOlcu,
            max: enBuyukOlcu,
            adim: 1,
            onChanged: (v) => _olcuDegistir(v, _s.yukseklik),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SayiAlani(
            etiket: 'Yükseklik (mm)',
            deger: _s.yukseklik,
            min: enKucukOlcu,
            max: enBuyukOlcu,
            adim: 1,
            onChanged: (v) => _olcuDegistir(_s.genislik, v),
          ),
        ),
        PopupMenuButton<(double, double)>(
          tooltip: 'Hazır ölçüler',
          icon: const Icon(Icons.straighten),
          onSelected: (o) => _olcuDegistir(o.$1, o.$2),
          itemBuilder: (_) => [
            for (final o in hazirOlculer) PopupMenuItem(value: o, child: Text('${mmYaz(o.$1)} × ${mmYaz(o.$2)} mm')),
          ],
        ),
      ]),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Ölçü değişince öğeleri de orantılı büyüt / küçült'),
        value: _olcekle,
        onChanged: (v) => setState(() => _olcekle = v ?? true),
      ),
      Row(children: [
        const Text('Para simgesi:  '),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: '₺', label: Text('₺')), ButtonSegment(value: 'TL', label: Text('TL'))],
          selected: {_s.para},
          showSelectedIcon: false,
          onSelectionChanged: (v) => _guncelle(_s.kopya(para: v.first)),
        ),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('İndirimli etiket'),
        subtitle: const Text('İndirimi olmayan ürünün etiketi basılmaz'),
        value: _s.tur == SablonTuru.indirimli,
        onChanged: (v) => _guncelle(_s.kopya(tur: v ? SablonTuru.indirimli : SablonTuru.normal)),
      ),
      const Divider(height: 24),
      Row(children: [
        Expanded(child: _baslik('Öğeler (${_s.ogeler.length})')),
        _ekleMenusu(),
      ]),
      if (_s.ogeler.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Etiket boş. "Öğe ekle" ile ürün adı, fiyat, barkod… ekleyin.'),
        ),
      for (var i = 0; i < _s.ogeler.length; i++) _ogeSatiri(i),
      if (sorunlar.isNotEmpty) ...[
        const Divider(height: 24),
        _baslik('Dikkat'),
        for (final s in sorunlar)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber, size: 16, color: Colors.orange.shade800),
              const SizedBox(width: 6),
              Expanded(child: Text(s, style: const TextStyle(fontSize: 12))),
            ]),
          ),
      ],
      const SizedBox(height: 24),
    ]);
  }

  Widget _baslik(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
      );

  Widget _ekleMenusu() => PopupMenuButton<VoidCallback>(
        tooltip: 'Öğe ekle',
        onSelected: (f) => f(),
        itemBuilder: (_) => [
          for (final a in hazirAlanlar)
            PopupMenuItem(value: () => _ekle(hazirAlanOgesi(a, _s)), child: Text(a.ad)),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: () => _ekle(hazirAlanOgesi(const HazirAlan('Sabit yazı', 'Yazı', kalin: false, payH: 0.12), _s)),
            child: const Text('Sabit yazı (kendi metniniz)'),
          ),
          PopupMenuItem(value: () => _ekle(yeniBarkodOgesi(_s)), child: const Text('Barkod')),
          PopupMenuItem(value: () => _ekle(yeniKutuOgesi(_s)), child: const Text('Çerçeve (kutu)')),
          PopupMenuItem(value: () => _ekle(yeniLogoOgesi(_s)), child: const Text('Yerli Üretim logosu')),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 18), SizedBox(width: 4), Text('Öğe ekle')]),
        ),
      );

  IconData _ikon(Oge o) => switch (o) {
        BarkodOge() => Icons.view_week_outlined,
        KutuOge() => Icons.crop_square,
        LogoOge() => Icons.flag_outlined,
        YaziOge() => Icons.text_fields,
      };

  Widget _ogeSatiri(int i) {
    final o = _s.ogeler[i];
    final secili = _sec == i;
    return ListTile(
      dense: true,
      selected: secili,
      selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(_ikon(o), size: 20),
      title: Text(ogeAdi(o), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${mmYaz(o.x)}, ${mmYaz(o.y)} · ${mmYaz(o.g)} × ${mmYaz(o.h)} mm', style: const TextStyle(fontSize: 11)),
      onTap: () => _secim(secili ? null : i),
    );
  }

  Widget _seciliOgePaneli(int i) {
    final o = _s.ogeler[i];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _baslik('Seçili: ${ogeAdi(o)}')),
        IconButton(tooltip: 'Arkaya', icon: const Icon(Icons.flip_to_back, size: 20), onPressed: i > 0 ? () => _sira(-1) : null),
        IconButton(
            tooltip: 'Öne', icon: const Icon(Icons.flip_to_front, size: 20), onPressed: i < _s.ogeler.length - 1 ? () => _sira(1) : null),
        IconButton(tooltip: 'Çoğalt (Ctrl+D)', icon: const Icon(Icons.copy, size: 20), onPressed: _cogalt),
        IconButton(tooltip: 'Sil (Delete)', icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error), onPressed: _sil),
      ]),
      Row(children: [
        Expanded(
          child: SayiAlani(
            etiket: 'Soldan (mm)',
            deger: o.x,
            min: 0,
            max: _s.genislik,
            onChanged: (v) => _ogeDegistir(i, o.konumla(x: mm1(v))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SayiAlani(
            etiket: 'Üstten (mm)',
            deger: o.y,
            min: 0,
            max: _s.yukseklik,
            onChanged: (v) => _ogeDegistir(i, o.konumla(y: mm1(v))),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: SayiAlani(
            etiket: 'Genişlik (mm)',
            deger: o.g,
            min: 1,
            max: _s.genislik,
            onChanged: (v) => _ogeDegistir(i, o.konumla(g: mm1(v))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SayiAlani(
            etiket: 'Yükseklik (mm)',
            deger: o.h,
            min: 1,
            max: _s.yukseklik,
            onChanged: (v) => _ogeDegistir(i, o.konumla(h: mm1(v))),
          ),
        ),
      ]),
      Wrap(spacing: 4, children: [
        TextButton.icon(
          icon: const Icon(Icons.align_horizontal_center, size: 16),
          label: const Text('Yatay ortala'),
          onPressed: () => _ogeDegistir(i, o.konumla(x: mm1(math.max(0, (_s.genislik - o.g) / 2)))),
        ),
        TextButton.icon(
          icon: const Icon(Icons.align_vertical_center, size: 16),
          label: const Text('Dikey ortala'),
          onPressed: () => _ogeDegistir(i, o.konumla(y: mm1(math.max(0, (_s.yukseklik - o.h) / 2)))),
        ),
        TextButton.icon(
          icon: const Icon(Icons.width_full, size: 16),
          label: const Text('Tam genişlik'),
          onPressed: () {
            final k = math.min(1.5, _s.genislik * 0.03);
            _ogeDegistir(i, o.konumla(x: mm1(k), g: mm1(_s.genislik - 2 * k)));
          },
        ),
      ]),
      const SizedBox(height: 6),
      ...switch (o) {
        YaziOge() => _yaziAyarlari(i, o),
        BarkodOge() => _barkodAyarlari(i, o),
        KutuOge() => [
            SayiAlani(
              etiket: 'Çizgi kalınlığı (mm)',
              deger: o.kalinlik,
              min: 0.1,
              max: 3,
              adim: 0.1,
              onChanged: (v) => _ogeDegistir(i, o.kopya(kalinlik: v)),
            ),
          ],
        LogoOge() => [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dikey (90° döndür)'),
              value: o.dikey,
              onChanged: (v) => _ogeDegistir(i, o.kopya(dikey: v)),
            ),
          ],
      },
    ]);
  }

  List<Widget> _yaziAyarlari(int i, YaziOge o) => [
        IcerikAlani(
          key: ValueKey('icerik-$i-$_disRev'),
          icerik: o.icerik,
          onChanged: (v) => _ogeDegistir(i, o.kopya(icerik: v)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: SayiAlani(
              etiket: 'Yazı boyu (punto)',
              deger: o.punto,
              min: 3,
              max: 120,
              adim: 1,
              onChanged: (v) => _ogeDegistir(i, o.kopya(punto: v)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<YaziTipi>(
              initialValue: o.yazi,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Yazı tipi', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: YaziTipi.arial, child: Text('Arial')),
                DropdownMenuItem(value: YaziTipi.arialNarrow, child: Text('Arial Narrow (dar)')),
                DropdownMenuItem(value: YaziTipi.arialBlack, child: Text('Arial Black (iri)')),
                DropdownMenuItem(value: YaziTipi.antikva, child: Text('Book Antiqua')),
              ],
              onChanged: (v) {
                if (v != null) _ogeDegistir(i, o.kopya(yazi: v));
              },
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text('Yazı kutuya sığmazsa kendiliğinden küçülür; punto en büyük boydur.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Row(children: [
          SegmentedButton<Hiza>(
            segments: const [
              ButtonSegment(value: Hiza.sol, icon: Icon(Icons.format_align_left, size: 18)),
              ButtonSegment(value: Hiza.orta, icon: Icon(Icons.format_align_center, size: 18)),
              ButtonSegment(value: Hiza.sag, icon: Icon(Icons.format_align_right, size: 18)),
            ],
            selected: {o.hiza},
            showSelectedIcon: false,
            onSelectionChanged: (v) => _ogeDegistir(i, o.kopya(hiza: v.first)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<Cizik>(
              initialValue: o.cizik,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Üstü çizili', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: Cizik.yok, child: Text('Hayır')),
                DropdownMenuItem(value: Cizik.duz, child: Text('Düz çizgi')),
                DropdownMenuItem(value: Cizik.capraz, child: Text('Çapraz çizgi')),
              ],
              onChanged: (v) {
                if (v != null) _ogeDegistir(i, o.kopya(cizik: v));
              },
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          FilterChip(label: const Text('Kalın'), selected: o.kalin, onSelected: (v) => _ogeDegistir(i, o.kopya(kalin: v))),
          FilterChip(
              label: const Text('Altı çizili'), selected: o.altiCizili, onSelected: (v) => _ogeDegistir(i, o.kopya(altiCizili: v))),
          FilterChip(
              label: const Text('İki satıra böl'),
              selected: o.satir == 2,
              onSelected: (v) => _ogeDegistir(i, o.kopya(satir: v ? 2 : 1))),
          FilterChip(label: const Text('Üste yasla'), selected: o.ustten, onSelected: (v) => _ogeDegistir(i, o.kopya(ustten: v))),
          FilterChip(label: const Text('Dikey (90°)'), selected: o.dikey, onSelected: (v) => _ogeDegistir(i, o.kopya(dikey: v))),
        ]),
      ];

  List<Widget> _barkodAyarlari(int i, BarkodOge o) => [
        SayiAlani(
          etiket: 'Çubuk inceliği (mm)',
          deger: o.modul,
          min: 0.15,
          max: 1,
          adim: 0.05,
          ondalik: 3,
          yardim: 'Yazıcı noktasına yuvarlanır (203 dpi: 0,25 · 0,375 · 0,5 mm). Kutuya sığmazsa incelir.',
          onChanged: (v) => _ogeDegistir(i, o.kopya(modul: v)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: SayiAlani(
              etiket: 'Numara yazı boyu (punto)',
              deger: o.yaziPunto,
              min: 4,
              max: 20,
              adim: 0.5,
              onChanged: (v) => _ogeDegistir(i, o.kopya(yaziPunto: v)),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(label: const Text('Kalın numara'), selected: o.kalinYazi, onSelected: (v) => _ogeDegistir(i, o.kopya(kalinYazi: v))),
        ]),
      ];
}

// ───────────────────────── Küçük alanlar ─────────────────────────

/// Sayı girişi (virgül / nokta) + / − düğmeleri. Dışarıdan değer değişince (sürükleme) kutu, odakta değilse güncellenir.
class SayiAlani extends StatefulWidget {
  final String etiket;
  final double deger, min, max, adim;
  final int ondalik;
  final String? yardim;
  final ValueChanged<double> onChanged;
  const SayiAlani({
    super.key,
    required this.etiket,
    required this.deger,
    required this.onChanged,
    this.min = 0,
    this.max = 1000,
    this.adim = 0.5,
    this.ondalik = 1,
    this.yardim,
  });

  @override
  State<SayiAlani> createState() => _SayiAlaniState();
}

class _SayiAlaniState extends State<SayiAlani> {
  late final _ctrl = TextEditingController(text: _yaz(widget.deger));
  final _odak = FocusNode();

  String _yaz(double v) {
    var s = v.toStringAsFixed(widget.ondalik);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s.replaceAll('.', ',');
  }

  @override
  void didUpdateWidget(SayiAlani eski) {
    super.didUpdateWidget(eski);
    if (!_odak.hasFocus && (ParaUtils.sayiCoz(_ctrl.text) ?? double.nan) != widget.deger) _ctrl.text = _yaz(widget.deger);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _odak.dispose();
    super.dispose();
  }

  void _adim(double yon) {
    final v = (widget.deger + yon * widget.adim).clamp(widget.min, widget.max).toDouble();
    final k = math.pow(10, widget.ondalik).toDouble();
    final r = (v * k).roundToDouble() / k;
    _ctrl.text = _yaz(r);
    widget.onChanged(r);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        focusNode: _odak,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(
          labelText: widget.etiket,
          helperText: widget.yardim,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            InkWell(onTap: () => _adim(-1), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.remove, size: 16))),
            InkWell(onTap: () => _adim(1), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add, size: 16))),
            const SizedBox(width: 4),
          ]),
        ),
        onChanged: (t) {
          final v = ParaUtils.sayiCoz(t);
          if (v != null && v >= widget.min && v <= widget.max) widget.onChanged(v);
        },
        onSubmitted: (_) => _ctrl.text = _yaz(widget.deger),
      );
}

/// Yazı içeriği: serbest metin + alan ({ad}, {fiyat} …) ekleme düğmeleri (imlecin olduğu yere).
class IcerikAlani extends StatefulWidget {
  final String icerik;
  final ValueChanged<String> onChanged;
  const IcerikAlani({super.key, required this.icerik, required this.onChanged});

  @override
  State<IcerikAlani> createState() => _IcerikAlaniState();
}

class _IcerikAlaniState extends State<IcerikAlani> {
  late final _ctrl = TextEditingController(text: widget.icerik);
  Timer? _bekle;

  @override
  void dispose() {
    _bekle?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _bildir() {
    _bekle?.cancel();
    _bekle = Timer(const Duration(milliseconds: 250), () => widget.onChanged(_ctrl.text));
  }

  void _ekle(String yt) {
    final sec = _ctrl.selection;
    final t = _ctrl.text;
    final bas = sec.isValid ? sec.start : t.length, son = sec.isValid ? sec.end : t.length;
    _ctrl.value = TextEditingValue(
      text: t.replaceRange(bas, son, yt),
      selection: TextSelection.collapsed(offset: bas + yt.length),
    );
    _bekle?.cancel();
    widget.onChanged(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _ctrl,
          decoration: const InputDecoration(
            labelText: 'Yazı',
            helperText: 'Süslü parantezli alanlar ürüne göre dolar: {ad}, {fiyat} {para} …',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => _bildir(),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final (yt, ad) in yerTutucular)
            ActionChip(
              label: Text(ad, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              tooltip: yt,
              onPressed: () => _ekle(yt),
            ),
        ]),
      ]);
}
