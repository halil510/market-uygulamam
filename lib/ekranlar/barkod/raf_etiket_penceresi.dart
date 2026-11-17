// lib/ekranlar/barkod/raf_etiket_penceresi.dart
//
// Raf etiketi şablonlarıyla (BarTender tasarımları) yazdırma penceresi: şablon / kâğıt / menşei seçilir,
// önizleme anında güncellenir. Basma yolları:
//   • Etiket yazıcısı (TSPL — Xprinter XP-490B vb.): kendi ağ adresine (fiş yazıcısından bağımsız; USB'deki yazıcı için
//     takılı olduğu bilgisayarda "Yazıcıyı ağa aç") ya da adres boşsa bağlı yazıcıya (WiFi / Bluetooth / USB / Windows RAW) etiket
//     komutu olarak gönderilir; sürücü ayarı gerekmez.
//   • Fiş yazıcısı (ESC/POS): bağlı termal fiş yazıcısına resim olarak.
//   • Windows sürücüsü: seçilen Windows yazıcısına, sürücünün kendi etiket ayarlarıyla (printing eklentisinin yazdır
//     düğmesi sürücü ayarlarını sıfırladığı için Windows'ta kapalı: XP-490B'de boş etiketler + ortaya baskı).
// Her yolda barkod çubukları yazıcının noktalarına oturtulur (silik / düzensiz çubuk olmaz).

import 'dart:async';
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' show PaperSize;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cekirdek/etiket/raf_etiket_sablonlari.dart';
import '../../cekirdek/etiket/tspl.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/etiket_ag_gonderici.dart';
import '../../servisler/raf_etiket_pdf_servisi.dart';
import '../../servisler/windows_etiket_yazici.dart';
import '../../servisler/yazdirma_servisi.dart';

/// Ayarlarda saklanan anahtarlar.
class RafEtiketAyar {
  RafEtiketAyar._();
  static const sablon = 'raf_etiket_sablon'; // '' = serbest etiket (eski tasarım)
  static const mensei = 'raf_etiket_mensei';
  static const kagit = 'raf_etiket_kagit';
  static const yontem = 'raf_etiket_yontem'; // RafBasmaYontemi.name
  static const windowsYazici = 'raf_etiket_windows_yazici';
  static const tsplBosluk = 'raf_etiket_tspl_bosluk';
  static const tsplTers = 'raf_etiket_tspl_ters';
  static const tsplKoyuluk = 'raf_etiket_tspl_koyuluk';
  static const tsplAdres = 'raf_etiket_tspl_adres'; // IP[:port]; boşsa bağlı yazıcıya
}

enum RafBasmaYontemi { tspl, escpos, windows }

bool get _windows => !kIsWeb && Platform.isWindows;

/// Fiş yazıcısının basım alanı (nokta, 203 dpi).
int _fisNokta(PaperSize k) => k == PaperSize.mm58 ? 384 : 576;

/// ESC/POS yolunda etiketin kâğıda sığacağı çözünürlük: resim ölçeklenmeden basılır (ölçekleme barkodu bozar).
double fisDpi(double etiketGenislikMm, PaperSize kagit) {
  final sigan = _fisNokta(kagit) * 25.4 / etiketGenislikMm;
  return sigan < varsayilanDpi ? sigan.floorToDouble() : varsayilanDpi;
}

/// Sepetteki ürünler (adetleriyle) için raf etiketi penceresini açar.
Future<void> rafEtiketPenceresiAc(BuildContext context, List<(UrunModel, int)> kalemler, {required String sablonId}) async {
  if (kalemler.isEmpty) return;
  final p = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  final yontemAdi = p.getString(RafEtiketAyar.yontem);
  var yontem = RafBasmaYontemi.values.where((e) => e.name == yontemAdi).firstOrNull ?? RafBasmaYontemi.tspl;
  if (yontem == RafBasmaYontemi.windows && !_windows) yontem = RafBasmaYontemi.tspl;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => RafEtiketPenceresi(
      kalemler: kalemler,
      sablonId: sablonId,
      mensei: p.getString(RafEtiketAyar.mensei) ?? 'Türkiye',
      kagit: p.getString(RafEtiketAyar.kagit) == RafEtiketKagidi.a4.name ? RafEtiketKagidi.a4 : RafEtiketKagidi.rulo,
      yontem: yontem,
      windowsYazici: p.getString(RafEtiketAyar.windowsYazici) ?? '',
      tsplAdres: p.getString(RafEtiketAyar.tsplAdres) ?? '',
      tspl: TsplAyar(
        bosluk: p.getDouble(RafEtiketAyar.tsplBosluk) ?? 2,
        ters: p.getBool(RafEtiketAyar.tsplTers) ?? false,
        koyuluk: p.getInt(RafEtiketAyar.tsplKoyuluk),
      ),
    ),
  ));
}

class RafEtiketPenceresi extends StatefulWidget {
  final List<(UrunModel, int)> kalemler;
  final String sablonId;
  final String mensei;
  final RafEtiketKagidi kagit;
  final RafBasmaYontemi yontem;
  final String windowsYazici;
  final String tsplAdres;
  final TsplAyar tspl;
  const RafEtiketPenceresi({
    super.key,
    required this.kalemler,
    required this.sablonId,
    required this.mensei,
    required this.kagit,
    this.yontem = RafBasmaYontemi.tspl,
    this.windowsYazici = '',
    this.tsplAdres = '',
    this.tspl = const TsplAyar(),
  });
  @override
  State<RafEtiketPenceresi> createState() => _RafEtiketPenceresiState();
}

class _RafEtiketPenceresiState extends State<RafEtiketPenceresi> {
  final _yazdirma = YazdirmaServisi();
  late String _sablonId = sablonBul(widget.sablonId).id;
  late String _mensei = widget.mensei;
  late RafEtiketKagidi _kagit = widget.kagit;
  late RafBasmaYontemi _yontem = widget.yontem;
  late String _windowsYazici = widget.windowsYazici;
  late String _tsplAdres = widget.tsplAdres;
  late final _adresCtrl = TextEditingController(text: widget.tsplAdres);
  late double _bosluk = widget.tspl.bosluk;
  late bool _ters = widget.tspl.ters;
  late int? _koyuluk = widget.tspl.koyuluk;
  late final _menseiCtrl = TextEditingController(text: widget.mensei);
  late final _boslukCtrl = TextEditingController(text: _mmYaz(widget.tspl.bosluk));
  late final List<(EtiketVeri, int)> _veriler = [for (final (u, adet) in widget.kalemler) (etiketVerisi(u), adet)];
  Timer? _bekle;
  bool _basiliyor = false;

  EtiketSablonu get _sablon => sablonBul(_sablonId);

  /// TSPL ayrı bir ağ adresine mi gidiyor (fiş yazıcısı bağlantısından bağımsız)?
  bool get _tsplAgda => etiketAdresCoz(_tsplAdres) != null;

  EtiketDenetimi get _denetim => etiketDenetle(_sablon, [for (final (v, _) in _veriler) v]);

  /// Denetimden geçenler, adet kadar çoğaltılmış.
  List<EtiketVeri> get _basilacak {
    final gecen = _denetim.basilacak.toSet();
    return [
      for (final (v, adet) in _veriler)
        if (gecen.contains(v))
          for (var i = 0; i < adet; i++) v,
    ];
  }

  /// [dpi]: barkod çubuklarının oturacağı yazıcı çözünürlüğü.
  Future<Uint8List> _pdf({RafEtiketKagidi? kagit, double dpi = varsayilanDpi}) => RafEtiketPdfServisi.pdf(
      _basilacak, _sablon,
      kagit: kagit ?? _kagit, mensei: _mensei, firma: _yazdirma.firmaAdiOnizleme, dpi: dpi);

  @override
  void initState() {
    super.initState();
    _yazdirma.ayarlariYukle().then((_) {
      if (mounted) setState(() {}); // firma adı, bağlı yazıcı
    });
  }

  @override
  void dispose() {
    _bekle?.cancel();
    _menseiCtrl.dispose();
    _boslukCtrl.dispose();
    _adresCtrl.dispose();
    super.dispose();
  }

  static String _mmYaz(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.', ',');

  Future<void> _kaydet() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(RafEtiketAyar.sablon, _sablonId);
    await p.setString(RafEtiketAyar.mensei, _mensei);
    await p.setString(RafEtiketAyar.kagit, _kagit.name);
    await p.setString(RafEtiketAyar.yontem, _yontem.name);
    await p.setString(RafEtiketAyar.windowsYazici, _windowsYazici);
    await p.setString(RafEtiketAyar.tsplAdres, _tsplAdres);
    await p.setDouble(RafEtiketAyar.tsplBosluk, _bosluk);
    await p.setBool(RafEtiketAyar.tsplTers, _ters);
    if (_koyuluk == null) {
      await p.remove(RafEtiketAyar.tsplKoyuluk);
    } else {
      await p.setInt(RafEtiketAyar.tsplKoyuluk, _koyuluk!);
    }
  }

  void _degisti(void Function() f) {
    setState(f);
    unawaited(_kaydet());
  }

  Future<void> _bas({bool yaziciSec = false}) async {
    if (_basiliyor) return;
    final adet = _basilacak.length;
    if (adet == 0) return;
    setState(() => _basiliyor = true);
    try {
      final gonderildi = switch (_yontem) {
        RafBasmaYontemi.tspl => await _tsplBas(),
        RafBasmaYontemi.escpos => await _fisBas(),
        RafBasmaYontemi.windows => await _windowsBas(yaziciSec: yaziciSec),
      };
      if (gonderildi && mounted) BildirimServisi.basari(context, '$adet etiket yazıcıya gönderildi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yazıcı hatası: $e');
    } finally {
      if (mounted) setState(() => _basiliyor = false);
    }
  }

  /// Etiket yazıcısı (TSPL): her etiket 203 dpi resim olarak bağlı yazıcıya.
  Future<bool> _tsplBas() async {
    const dpi = varsayilanDpi;
    final pdf = await _pdf(kagit: RafEtiketKagidi.rulo, dpi: dpi);
    final etiketler = <TsplResim>[];
    await for (final r in Printing.raster(pdf, dpi: dpi)) {
      etiketler.add(tsplResim(r.pixels, r.width, r.height));
    }
    final is_ = tsplIs(etiketler,
        genislik: _sablon.genislik,
        uzunluk: _sablon.yukseklik,
        ayar: TsplAyar(bosluk: _bosluk, ters: _ters, koyuluk: _koyuluk));
    if (_tsplAgda) {
      await etiketAgaGonder(_tsplAdres, is_);
    } else {
      await _yazdirma.tsplGonder(is_);
    }
    return true;
  }

  /// Fiş yazıcısı (ESC/POS): etiket kâğıda sığacak çözünürlükte çizilir, ölçeklenmeden basılır.
  Future<bool> _fisBas() async {
    final kagit = _sablon.genislik > 58 ? PaperSize.mm80 : PaperSize.mm58;
    final dpi = fisDpi(_sablon.genislik, kagit);
    final pdf = await _pdf(kagit: RafEtiketKagidi.rulo, dpi: dpi);
    final resimler = await RafEtiketPdfServisi.resimler(pdf, dpi: dpi);
    await _yazdirma.resimEtiketleriYazdir(resimler, kagit: kagit);
    return true;
  }

  /// Windows sürücüsüyle (GDI): sürücünün kendi etiket ayarları korunur.
  Future<bool> _windowsBas({bool yaziciSec = false}) async {
    var ad = _windowsYazici;
    if (!yaziciSec && ad.isNotEmpty) {
      final hepsi = await Printing.listPrinters();
      if (!hepsi.any((e) => e.name == ad)) ad = '';
    }
    if (ad.isEmpty || yaziciSec) {
      if (!mounted) return false;
      final p = await Printing.pickPrinter(context: context, title: 'Etiket yazıcısını seçin');
      if (p == null) return false;
      ad = p.name;
      _degisti(() => _windowsYazici = p.name);
    }
    final (g, u) = _kagit == RafEtiketKagidi.a4 ? (210.0, 297.0) : (_sablon.genislik, _sablon.yukseklik);
    final sayfa = windowsSayfaSorgula(ad, g, u);
    if (!sayfa.uyar(g, u)) {
      if (!mounted) return false;
      if (await _sayfaUyarisi(ad, sayfa, g, u) != true) return false;
    }
    final pdf = await _pdf(dpi: sayfa.dpi);
    return await windowsYazdir(ad, pdf, genislik: g, uzunluk: u) > 0;
  }

  Future<bool?> _sayfaUyarisi(String yazici, YaziciSayfasi s, double g, double u) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Yazıcı kâğıt boyu uymuyor'),
          content: Text(
            'Etiket: ${_mmYaz(g)} × ${_mmYaz(u)} mm\n'
            '"$yazici" sürücüsünün sayfası: ${s.olcu} (${s.aciklama})\n\n'
            'Böyle basılırsa boş etiket çıkabilir ya da yazı kayabilir.\n'
            'Düzeltmek için: Denetim Masası → Aygıtlar ve Yazıcılar → "$yazici" → sağ tık → '
            'Yazdırma Tercihleri → Sayfa / Stok ayarında kâğıt boyunu ${_mmYaz(g)} × ${_mmYaz(u)} mm yapın.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yine de bas')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final genis = MediaQuery.sizeOf(context).width >= 900;
    final onizleme = PdfPreview(
      key: ValueKey('$_sablonId|$_kagit|$_mensei|${_yazdirma.firmaAdiOnizleme}'),
      build: (_) => _pdf(),
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      // Windows'ta eklentinin yazdır düğmesi etiket yazıcısı sürücüsünün ayarlarını bozuyor: "Windows sürücüsü" yolunu kullanın.
      allowPrinting: !_windows,
      pdfFileName: 'raf_etiketleri.pdf',
      maxPageWidth: _kagit == RafEtiketKagidi.rulo ? 520 : 800,
    );
    return Scaffold(
      appBar: AppBar(title: Text('Raf Etiketi (${_veriler.length} ürün)')),
      body: genis
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 380, child: _secenekler(context)),
              const VerticalDivider(width: 1),
              Expanded(child: onizleme),
            ])
          : Column(children: [
              SizedBox(height: MediaQuery.sizeOf(context).height * .45, child: _secenekler(context)),
              const Divider(height: 1),
              Expanded(child: onizleme),
            ]),
    );
  }

  Widget _secenekler(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kucuk = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final d = _denetim;
    final toplam = _basilacak.length;
    final (sutun, satir) = RafEtiketPdfServisi.a4Dizilim(_sablon);
    final bagliYazici = _yazdirma.bagliMi ? _yazdirma.baglantiDurumu : null;
    // A4 yalnız Windows sürücüsüyle (ya da önizlemedeki yazdır / paylaş ile) basılır.
    final a4Engel = _kagit == RafEtiketKagidi.a4 && _yontem != RafBasmaYontemi.windows;
    final basilabilir = toplam > 0 && !_basiliyor && !a4Engel && (_yontem == RafBasmaYontemi.windows || (_yontem == RafBasmaYontemi.tspl && _tsplAgda) || _yazdirma.bagliMi);
    return ListView(padding: const EdgeInsets.all(14), children: [
      DropdownButtonFormField<String>(
        initialValue: _sablonId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Şablon', border: OutlineInputBorder(), isDense: true),
        items: [
          for (final s in sablonlar)
            DropdownMenuItem(value: s.id, child: Text('${s.ad}  ·  ${s.olcu}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          if (v != null) _degisti(() => _sablonId = v);
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Text('BarTender şablonu: ${_sablon.dosya}', style: kucuk),
      ),
      const SizedBox(height: 12),
      SegmentedButton<RafEtiketKagidi>(
        segments: [
          const ButtonSegment(value: RafEtiketKagidi.rulo, label: Text('Etiket rulosu'), icon: Icon(Icons.receipt_long)),
          ButtonSegment(value: RafEtiketKagidi.a4, label: Text('A4 ($sutun×$satir)'), icon: const Icon(Icons.grid_on)),
        ],
        selected: {_kagit},
        onSelectionChanged: (v) => _degisti(() => _kagit = v.first),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _menseiCtrl,
        decoration: const InputDecoration(
          labelText: 'Menşei',
          helperText: 'Ürün kartında menşei yazılıysa o kullanılır',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) {
          _bekle?.cancel();
          _bekle = Timer(const Duration(milliseconds: 600), () {
            if (mounted) _degisti(() => _mensei = v.trim());
          });
        },
      ),
      const SizedBox(height: 14),
      Text('${d.basilacak.length} ürün · $toplam etiket', style: const TextStyle(fontWeight: FontWeight.w700)),
      if (d.atlanan.isNotEmpty) _uyari(Icons.block, cs.error, '${d.atlanan.length} ürün BASILMAYACAK', d.atlanan),
      if (d.birimFiyatsiz.isNotEmpty)
        _uyari(
          Icons.warning_amber,
          Colors.orange.shade800,
          '${d.birimFiyatsiz.length} üründe birim fiyat boş kalacak',
          d.birimFiyatsiz,
          aciklama: 'Ürün adında gramaj (ör. 500 GR, 1,5 LT) bulunamadı ya da adda paket / adet bilgisi var. '
              'Ürün kartına Ağırlık (gr) girin; birimi KG / LT olan üründe satış fiyatı birim fiyattır.',
        ),
      const SizedBox(height: 16),
      DropdownButtonFormField<RafBasmaYontemi>(
        initialValue: _yontem,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Nasıl basılsın?', border: OutlineInputBorder(), isDense: true),
        items: [
          const DropdownMenuItem(value: RafBasmaYontemi.tspl, child: Text('Etiket yazıcısı (TSPL · XP-490B vb.)')),
          const DropdownMenuItem(value: RafBasmaYontemi.escpos, child: Text('Fiş yazıcısı (ESC/POS)')),
          if (_windows) const DropdownMenuItem(value: RafBasmaYontemi.windows, child: Text('Windows sürücüsü')),
        ],
        onChanged: (v) {
          if (v != null) _degisti(() => _yontem = v);
        },
      ),
      const SizedBox(height: 6),
      if (_yontem == RafBasmaYontemi.windows)
        Text(
          _windowsYazici.isEmpty
              ? 'Bas\'a basınca Windows yazıcısı seçilir; sürücünün kendi etiket ayarlarıyla basılır.'
              : 'Yazıcı: $_windowsYazici (sürücünün kendi etiket ayarlarıyla)',
          style: kucuk,
        )
      else if (_yontem == RafBasmaYontemi.tspl) ...[
        const SizedBox(height: 6),
        TextField(
          controller: _adresCtrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Etiket yazıcısının adresi (IP)',
            hintText: '192.168.1.35  (port: 9100)',
            helperText: 'Yazıcı bilgisayara USB ile takılıysa o bilgisayarın IP adresi ("Yazıcıyı ağa aç"). '
                'Boş bırakılırsa Ayarlar > Yazıcılar\'daki bağlı yazıcıya gider.',
            helperMaxLines: 3,
            errorText: _adresCtrl.text.trim().isEmpty || _tsplAgda ? null : 'Geçersiz adres',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => _degisti(() => _tsplAdres = v.trim()),
        ),
        const SizedBox(height: 4),
        Text(
          _tsplAgda
              ? 'Etiketler $_tsplAdres adresine gider; fiş yazıcısı bağlantısı değişmez.'
              : bagliYazici != null
                  ? 'Bağlı yazıcı: $bagliYazici — bu bir fiş yazıcısıysa yukarıya etiket yazıcısının adresini yazın.'
                  : 'Etiket yazıcısının adresini yazın.',
          style: _tsplAgda || bagliYazici != null ? kucuk : TextStyle(fontSize: 12, color: cs.error),
        ),
      ] else
        Text(
          bagliYazici != null
              ? 'Bağlı yazıcı: $bagliYazici'
              : 'Bağlı yazıcı yok. Ayarlar > Yazıcılar bölümünden etiket yazıcısını (WiFi, Bluetooth, USB'
                  '${_windows ? ' ya da Windows' : ''}) bağlayın.',
          style: bagliYazici != null ? kucuk : TextStyle(fontSize: 12, color: cs.error),
        ),
      if (_yontem == RafBasmaYontemi.tspl) _tsplAyarlari(context),
      if (a4Engel)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('A4 seçili: A4 için önizlemedeki yazdır / paylaş düğmelerini'
              '${_windows ? ' ya da "Windows sürücüsü"nü' : ''} kullanın.', style: TextStyle(fontSize: 12, color: cs.error)),
        ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: basilabilir ? _bas : null,
        icon: _basiliyor
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.print),
        label: Text('$toplam etiket bas', overflow: TextOverflow.ellipsis),
      ),
      if (_yontem == RafBasmaYontemi.windows && _windowsYazici.isNotEmpty)
        TextButton(
          onPressed: _basiliyor || toplam == 0 ? null : () => _bas(yaziciSec: true),
          child: const Text('Başka yazıcı seçip bas'),
        ),
    ]);
  }

  Widget _tsplAyarlari(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Etiket yazıcısı ayarları', style: TextStyle(fontSize: 14)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          TextField(
            controller: _boslukCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Etiketler arası boşluk (mm)',
              helperText: 'Genelde 2 mm. Sürekli (boşluksuz) kâğıtta 0.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              final d = double.tryParse(v.trim().replaceAll(',', '.'));
              if (d != null && d >= 0 && d <= 20) _degisti(() => _bosluk = d);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ters basıyorsa çevir (180°)'),
            value: _ters,
            onChanged: (v) => _degisti(() => _ters = v),
          ),
          DropdownButtonFormField<int?>(
            initialValue: _koyuluk,
            decoration: const InputDecoration(
              labelText: 'Baskı koyuluğu',
              helperText: 'Barkod silik çıkıyorsa artırın',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Yazıcının kendi ayarı')),
              for (var k = 4; k <= 15; k++) DropdownMenuItem(value: k, child: Text('$k${k == 8 ? ' (normal)' : ''}')),
            ],
            onChanged: (v) => _degisti(() => _koyuluk = v),
          ),
        ],
      );

  Widget _uyari(IconData ikon, Color renk, String baslik, List<String> satirlar, {String? aciklama}) {
    const ilk = 8;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        leading: Icon(ikon, color: renk),
        title: Text(baslik, style: TextStyle(color: renk, fontWeight: FontWeight.w600, fontSize: 14)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (aciklama != null)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(aciklama, style: const TextStyle(fontSize: 12))),
          for (final s in satirlar.take(ilk)) Text('• $s', style: const TextStyle(fontSize: 12)),
          if (satirlar.length > ilk) Text('… ve ${satirlar.length - ilk} ürün daha', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
