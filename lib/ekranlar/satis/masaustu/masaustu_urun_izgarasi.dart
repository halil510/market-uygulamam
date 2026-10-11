// lib/ekranlar/satis/masaustu/masaustu_urun_izgarasi.dart
//
// Masaüstü Hızlı Satış — alt bölüm: grup sekmeleri + resimli ürün tuşları.
// Kaynak: PLU panelindeki ürünler (ana_grup'a göre sekmeler). PLU'da ürün
// yoksa "Hızlı Tuşlar" (favoriler) gösterilir.
//
// Tuşlar yatay kayar (fare tekerleği → yatay). Sağ tık → Düzenle ile
// kartlar sürükle-bırak yer değiştirir, kenarından/köşesinden çekilerek
// boyutlanır; sağ tık → Kaydet ile sıra (plu_sira / favori sira) ve kart
// boyutu (bu bilgisayara özel) kalıcı olur.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../cekirdek/utils/para_utils.dart';
import '../../../depolar/favori_urun_deposu.dart';
import '../../../depolar/urun_deposu.dart';
import '../../../modeller/urun_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/ortak/app_widgetlar.dart'
    show basariMesaji, hataMesaji;
import '../widgets/hizli_tus_paneli.dart' show tusRengi;

class MasaustuUrunIzgarasi extends StatefulWidget {
  final void Function(UrunModel urun) onUrunSec;
  const MasaustuUrunIzgarasi({super.key, required this.onUrunSec});

  @override
  State<MasaustuUrunIzgarasi> createState() => _MasaustuUrunIzgarasiState();
}

class _MasaustuUrunIzgarasiState extends State<MasaustuUrunIzgarasi> {
  static const _tumu = 'Tümü';
  // Kart boyutu bu bilgisayara özel (SharedPreferences) saklanır.
  static const _prefGenislik = 'masaustu_plu_kart_genislik';
  static const _prefYukseklik = 'masaustu_plu_kart_yukseklik';
  static const _varsayilanG = 124.0, _varsayilanY = 135.0;
  static const _bosluk = 8.0;

  List<UrunModel> _urunler = [];
  bool _yukleniyor = true;
  bool _favoriModu = false;
  String _grup = _tumu;
  bool _isleniyor = false;
  final ScrollController _yatayController = ScrollController();

  double _kartG = _varsayilanG, _kartY = _varsayilanY;

  // Düzenleme modu (sağ tık → Düzenle). İptal'de bu yedeklere dönülür.
  bool _duzenle = false;
  bool _kaydediliyor = false;
  List<UrunModel> _yedekSira = [];
  double _yedekG = _varsayilanG, _yedekY = _varsayilanY;

  @override
  void initState() {
    super.initState();
    _boyutYukle();
    _yukle();
  }

  @override
  void dispose() {
    _yatayController.dispose();
    super.dispose();
  }

  Future<void> _boyutYukle() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _kartG = p.getDouble(_prefGenislik) ?? _varsayilanG;
        _kartY = p.getDouble(_prefYukseklik) ?? _varsayilanY;
      });
    } catch (_) {}
  }

  Future<void> _yukle() async {
    try {
      // Düz plu_sira sırası: "Tümü"de kullanıcının sürükle-bırakla
      // verdiği sıra aynen görünsün (gruplu sorgu ana_grup'a göre dizip
      // gruplar arası taşımayı geri alırdı).
      var liste = await UrunDeposu().pluUrunleriGetir();
      var favori = false;
      if (liste.isEmpty) {
        liste = await FavoriUrunDeposu().favorileriGetir();
        favori = true;
      }
      if (!mounted) return;
      setState(() {
        _urunler = liste;
        _favoriModu = favori;
        _yukleniyor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  String _grupAdi(UrunModel u) =>
      (u.anaGrup == null || u.anaGrup!.trim().isEmpty) ? 'Genel' : u.anaGrup!;

  List<String> get _gruplar {
    final set = <String>{};
    for (final u in _urunler) {
      set.add(_grupAdi(u));
    }
    return [_tumu, ...set];
  }

  void _sec(UrunModel u) {
    if (_isleniyor) return;
    _isleniyor = true;
    widget.onUrunSec(u);
    Future.delayed(const Duration(milliseconds: 300), () => _isleniyor = false);
  }

  // ── Düzenleme modu ──────────────────────────────────────────────────

  void _duzenlemeyiAc() {
    setState(() {
      _yedekSira = List.of(_urunler);
      _yedekG = _kartG;
      _yedekY = _kartY;
      _duzenle = true;
    });
  }

  void _iptal() {
    setState(() {
      _urunler = _yedekSira;
      _kartG = _yedekG;
      _kartY = _yedekY;
      _duzenle = false;
    });
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    setState(() => _kaydediliyor = true);
    try {
      if (!_ayniSira(_urunler, _yedekSira)) {
        final idler = _urunler.map((u) => u.id!).toList();
        if (_favoriModu) {
          await FavoriUrunDeposu().sirayiKaydet(idler);
        } else {
          // plu_sira — PLU Yönetimi ekranındaki sıralamayla aynı alan.
          await UrunDeposu().pluSiralamaKaydet(idler);
        }
      }
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_prefGenislik, _kartG);
      await p.setDouble(_prefYukseklik, _kartY);
      if (!mounted) return;
      setState(() => _duzenle = false);
      basariMesaji(context, 'Ürün tuşları kaydedildi');
    } catch (e) {
      if (mounted) hataMesaji(context, 'Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  bool _ayniSira(List<UrunModel> a, List<UrunModel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// [suruklenen] ürünü [hedef] ürünün yerine taşır (aradakiler kayar).
  void _tasi(UrunModel suruklenen, UrunModel hedef) {
    final kaynak = _urunler.indexWhere((u) => u.id == suruklenen.id);
    final hedefIdx = _urunler.indexWhere((u) => u.id == hedef.id);
    if (kaynak < 0 || hedefIdx < 0 || kaynak == hedefIdx) return;
    setState(() {
      final u = _urunler.removeAt(kaynak);
      _urunler.insert(hedefIdx, u);
    });
  }

  bool _tasinabilir(UrunModel suruklenen, UrunModel hedef) =>
      suruklenen.id != hedef.id;

  void _boyutla(double dx, double dy) {
    setState(() {
      _kartG = (_kartG + dx).clamp(80.0, 280.0);
      _kartY = (_kartY + dy).clamp(80.0, 320.0);
    });
  }

  PopupMenuItem<String> _menuOge(String deger, IconData ikon, String yazi) =>
      PopupMenuItem(
        value: deger,
        child: Row(
          children: [
            Icon(ikon, size: 18, color: context.textSecondary),
            const SizedBox(width: 10),
            Text(yazi, style: TextStyle(color: context.textPrimary)),
          ],
        ),
      );

  Future<void> _sagTikMenusu(Offset konum) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final secim = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        konum & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: _duzenle
          ? [
              _menuOge('kaydet', Icons.save_rounded, 'Kaydet'),
              _menuOge(
                'varsayilan',
                Icons.aspect_ratio_rounded,
                'Varsayılan boyut',
              ),
              _menuOge('iptal', Icons.close_rounded, 'İptal'),
            ]
          : [_menuOge('duzenle', Icons.edit_rounded, 'Düzenle')],
    );
    if (!mounted) return;
    switch (secim) {
      case 'duzenle':
        _duzenlemeyiAc();
      case 'kaydet':
        await _kaydet();
      case 'varsayilan':
        setState(() {
          _kartG = _varsayilanG;
          _kartY = _varsayilanY;
        });
      case 'iptal':
        _iptal();
    }
  }

  /// Fare tekerleği (dikey) → yatay kaydırma. Trackpad'in yatay (dx)
  /// kaydırmasını Scrollable kendisi işler; resolver ile aynı olayın iki
  /// kez uygulanması önlenir.
  void _tekerlek(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      if (!_yatayController.hasClients) return;
      final pos = _yatayController.position;
      final yeni = (pos.pixels + (e as PointerScrollEvent).scrollDelta.dy)
          .clamp(0.0, pos.maxScrollExtent);
      _yatayController.jumpTo(yeni);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    if (_urunler.isEmpty) {
      return Center(
        child: Text(
          "Hızlı satış ürünü yok.\nÜrün Listesi → PLU Yönetimi'nden ürün ekleyin.",
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textSecondary, height: 1.5),
        ),
      );
    }
    final gorunen = _grup == _tumu
        ? _urunler
        : _urunler.where((u) => _grupAdi(u) == _grup).toList();
    return Column(
      children: [
        _sekmeler(),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (d) => _sagTikMenusu(d.globalPosition),
            child: Listener(
              onPointerSignal: _tekerlek,
              child: LayoutBuilder(
                builder: (context, c) {
                  // Satır sayısı yüksekliğe göre; kartlar tam _kartY boyunda
                  // kalsın diye artan alan alt boşluğa verilir.
                  final kullanilabilir = (c.maxHeight - 2 * _bosluk).clamp(
                    40.0,
                    double.infinity,
                  );
                  final kartY = _kartY.clamp(40.0, kullanilabilir);
                  final satir = ((kullanilabilir + _bosluk) / (kartY + _bosluk))
                      .floor()
                      .clamp(1, 50);
                  final artan =
                      (kullanilabilir - satir * kartY - (satir - 1) * _bosluk)
                          .clamp(0.0, double.infinity);
                  return Scrollbar(
                    controller: _yatayController,
                    thumbVisibility: true,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: GridView.builder(
                      controller: _yatayController,
                      padding: EdgeInsets.fromLTRB(
                        _bosluk,
                        _bosluk,
                        _bosluk,
                        _bosluk + artan,
                      ),
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: satir,
                        mainAxisExtent: _kartG,
                        mainAxisSpacing: _bosluk,
                        crossAxisSpacing: _bosluk,
                      ),
                      itemCount: gorunen.length,
                      itemBuilder: (_, i) => _duzenle
                          ? _duzenlenebilirTus(gorunen[i], kartY)
                          : _tus(gorunen[i]),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Sekme çubuğunun sağında durur; ayrı şerit olsaydı ızgaranın
  /// yüksekliğini yer, kart satır sayısı düşerdi.
  Widget _duzenlemeDugmeleri() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    color: TsRenk.primary.withValues(alpha: 0.10),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Tooltip(
          message:
              'Kartı sürükleyip başka kartın üstüne bırakın; '
              'kenarından/köşesinden çekerek boyutlandırın.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_rounded, size: 16, color: TsRenk.primary),
              SizedBox(width: 6),
              Text(
                'Düzenleniyor',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: TsRenk.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _kaydediliyor ? null : _iptal,
          child: const Text('İptal'),
        ),
        const SizedBox(width: 4),
        SizedBox(
          height: 30,
          child: FilledButton.icon(
            onPressed: _kaydediliyor ? null : _kaydet,
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Kaydet'),
          ),
        ),
      ],
    ),
  );

  Widget _duzenlenebilirTus(UrunModel u, double kartY) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DragTarget<UrunModel>(
            onWillAcceptWithDetails: (d) => _tasinabilir(d.data, u),
            onAcceptWithDetails: (d) => _tasi(d.data, u),
            builder: (context, aday, _) => Draggable<UrunModel>(
              data: u,
              feedback: Material(
                color: Colors.transparent,
                child: Opacity(
                  opacity: 0.85,
                  child: SizedBox(
                    width: _kartG,
                    height: kartY,
                    child: _tus(u, pasif: true),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _tus(u, pasif: true),
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: aday.isNotEmpty
                          ? TsRenk.primary
                          : TsRenk.primary.withValues(alpha: 0.45),
                      width: aday.isNotEmpty ? 3 : 1.5,
                    ),
                  ),
                  child: _tus(u, pasif: true),
                ),
              ),
            ),
          ),
        ),
        // Sağ kenar → genişlik, alt kenar → yükseklik, köşe → ikisi birden.
        Positioned(
          right: -3,
          top: 0,
          bottom: 14,
          width: 8,
          child: _tutamac(
            SystemMouseCursors.resizeLeftRight,
            (d) => _boyutla(d.dx, 0),
          ),
        ),
        Positioned(
          left: 0,
          right: 14,
          bottom: -3,
          height: 8,
          child: _tutamac(
            SystemMouseCursors.resizeUpDown,
            (d) => _boyutla(0, d.dy),
          ),
        ),
        Positioned(
          right: -3,
          bottom: -3,
          width: 18,
          height: 18,
          child: _tutamac(
            SystemMouseCursors.resizeDownRight,
            (d) => _boyutla(d.dx, d.dy),
            child: const Icon(
              Icons.open_in_full_rounded,
              size: 14,
              color: TsRenk.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tutamac(
    MouseCursor imlec,
    void Function(Offset delta) degis, {
    Widget? child,
  }) => MouseRegion(
    cursor: imlec,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => degis(d.delta),
      child: child ?? const SizedBox.expand(),
    ),
  );

  Widget _sekmeler() {
    final gruplar = _gruplar;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: [
                if (_favoriModu)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Center(
                      child: Text(
                        'Hızlı Tuşlar',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                for (final g in gruplar)
                  InkWell(
                    onTap: () => setState(() => _grup = g),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: g == _grup
                                ? TsRenk.primary
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: Text(
                        g,
                        style: TextStyle(
                          fontWeight: g == _grup
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: g == _grup
                              ? TsRenk.primary
                              : context.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_duzenle) _duzenlemeDugmeleri(),
        ],
      ),
    );
  }

  Widget _resim(UrunModel u, Color renk) {
    final yol = u.resimYolu;
    if (yol != null && yol.isNotEmpty && File(yol).existsSync()) {
      return Image.file(
        File(yol),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _bas(u, renk),
      );
    }
    final url = u.resimUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _bas(u, renk),
      );
    }
    return _bas(u, renk);
  }

  Widget _bas(UrunModel u, Color renk) => Container(
    color: renk.withValues(alpha: 0.16),
    alignment: Alignment.center,
    child: Text(
      u.urunAdi.isEmpty ? '?' : u.urunAdi[0].toUpperCase(),
      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: renk),
    ),
  );

  Widget _tus(UrunModel u, {bool pasif = false}) {
    final renk = tusRengi(u.urunAdi);
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Düzenleme modunda tıklama sepete ürün eklemesin.
        onTap: pasif ? null : () => _sec(u),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            children: [
              Expanded(child: SizedBox.expand(child: _resim(u, renk))),
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
                child: Column(
                  children: [
                    Text(
                      u.urunAdi,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      ParaUtils.formatla(u.satisFiyati),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: TsRenk.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
