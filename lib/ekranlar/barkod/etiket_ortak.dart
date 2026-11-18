// lib/ekranlar/barkod/etiket_ortak.dart
//
// Etiket ekranlarının ortak parçaları:
//   • etiketleriBas / urunEtiketiBas — SEÇİLİ tasarım + SEÇİLİ yazıcıyla basar (ürün listesi / detay / düzenle
//     ekranlarındaki "Etiket yazdır" düğmesi ve Etiket Yazdırma listesi bunu kullanır),
//   • EtiketYazdirDugmesi — ürün ekranlarındaki yazdır ikonu (dokun: 1 etiket, uzun bas: adet sor),
//   • EtiketOnizleme — etiketin gerçek çıktısıyla aynı küçük resmi,
//   • EtiketYaziciPaneli / etiketYaziciAyarDialogu — etiket yazıcısı ayarları (her değişiklik hemen kaydedilir).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../cekirdek/etiket/etiket_tasarimi.dart';
import '../../cekirdek/etiket/raf_etiket_sablonlari.dart';
import '../../cekirdek/etiket/tspl.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/etiket_ayarlari.dart';
import '../../servisler/etiket_baski_servisi.dart';
import '../../servisler/raf_etiket_pdf_servisi.dart' show RafEtiketKagidi;
import '../../servisler/windows_etiket_yazici.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../ayarlar/yazici_paylasim_karti.dart';

bool get _windows => !kIsWeb && Platform.isWindows;

String _mmYaz(double v) => mmYaz(v);

// ───────────────────────── Basma ─────────────────────────

/// Ekrandan sorulan sorular: Windows yazıcısı seçimi, kâğıt boyu uyarısı.
class _EkranSorulari implements EtiketBaskiSorulari {
  final BuildContext context;
  _EkranSorulari(this.context);

  @override
  Future<String?> windowsYaziciSec() async {
    if (!context.mounted) return null;
    final p = await Printing.pickPrinter(context: context, title: 'Etiket yazıcısını seçin');
    return p?.name;
  }

  @override
  Future<bool> sayfaUyumsuz(String yazici, YaziciSayfasi s, double g, double u) async {
    if (!context.mounted) return false;
    final r = await showDialog<bool>(
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
    return r == true;
  }
}

bool _basiliyor = false;

/// Seçili tasarım + seçili yazıcıyla basar; sonucu / hatayı ekranda bildirir. Basıldıysa true.
/// Aynı anda ikinci basım isteği yok sayılır (çift tıklamayla iki kez basılmaz).
Future<bool> etiketleriBas(BuildContext context, List<(UrunModel, int)> kalemler, {EtiketSablonu? sablon}) async {
  if (kalemler.isEmpty) return false;
  if (_basiliyor) {
    BildirimServisi.bilgi(context, 'Önceki etiketler basılıyor, bekleyin…');
    return false;
  }
  _basiliyor = true;
  final mesajci = ScaffoldMessenger.maybeOf(context);
  mesajci?.showSnackBar(const SnackBar(
    content: Row(children: [
      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
      SizedBox(width: 12),
      Text('Etiket yazıcıya gönderiliyor…'),
    ]),
    duration: Duration(minutes: 2),
    behavior: SnackBarBehavior.floating,
  ));
  try {
    final s = sablon ?? await EtiketAyarlari.seciliTasarim();
    if (!context.mounted) return false;
    final sonuc = await EtiketBaskiServisi.bas(kalemler, sorular: _EkranSorulari(context), sablon: s);
    mesajci?.hideCurrentSnackBar();
    if (!context.mounted) return sonuc.basilan > 0;
    final atlanan = sonuc.denetim.atlanan;
    if (sonuc.iptal) {
      BildirimServisi.bilgi(context, 'Yazdırma iptal edildi');
    } else if (sonuc.basilan == 0) {
      BildirimServisi.uyari(context, atlanan.isEmpty ? 'Basılacak etiket yok' : 'Etiket basılmadı: ${atlanan.join(' · ')}');
    } else if (atlanan.isNotEmpty) {
      BildirimServisi.uyari(context, '${sonuc.basilan} etiket basıldı (${s.ad}). Basılmayan: ${atlanan.join(' · ')}');
    } else {
      BildirimServisi.basari(context, '${sonuc.basilan} etiket basıldı · ${s.ad} → ${sonuc.yazici}');
    }
    return sonuc.basilan > 0;
  } on EtiketBaskiHatasi catch (e) {
    mesajci?.hideCurrentSnackBar();
    if (context.mounted) {
      if (e.ayarEksik) {
        await _ayarEksikDialogu(context, e.mesaj);
      } else {
        BildirimServisi.hata(context, e.mesaj);
      }
    }
    return false;
  } catch (e) {
    mesajci?.hideCurrentSnackBar();
    if (context.mounted) BildirimServisi.hata(context, 'Yazıcı hatası: $e');
    return false;
  } finally {
    _basiliyor = false;
  }
}

Future<void> _ayarEksikDialogu(BuildContext context, String mesaj) async {
  final ac = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.print_disabled),
      title: const Text('Etiket yazıcısı ayarlanmamış'),
      content: Text(mesaj),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Kapat')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yazıcı ayarları')),
      ],
    ),
  );
  if (ac == true && context.mounted) await etiketYaziciAyarDialogu(context);
}

/// Tek ürünün etiketi ([adet] tane).
Future<bool> urunEtiketiBas(BuildContext context, UrunModel u, {int adet = 1}) => etiketleriBas(context, [(u, adet)]);

/// "Kaç etiket?" sorusu. Vazgeçilirse null.
Future<int?> etiketAdediSor(BuildContext context, String urunAdi, {int baslangic = 1}) async {
  final ctrl = TextEditingController(text: '$baslangic');
  try {
    return await showDialog<int>(
      context: context,
      builder: (c) {
        void tamam() {
          final n = ParaUtils.tamSayiCoz(ctrl.text);
          if (n != null && n > 0) Navigator.pop(c, n.clamp(1, 999));
        }

        return AlertDialog(
          title: Text(urunAdi, style: const TextStyle(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(labelText: 'Kaç etiket?', border: OutlineInputBorder(), isDense: true),
            onSubmitted: (_) => tamam(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
            FilledButton.icon(onPressed: tamam, icon: const Icon(Icons.print, size: 18), label: const Text('Yazdır')),
          ],
        );
      },
    );
  } finally {
    ctrl.dispose();
  }
}

/// Ürün ekranlarındaki "Etiket yazdır" ikonu: dokununca 1 etiket, uzun basınca (ya da sağ tık) adet sorar.
/// [urun] null dönerse basılmaz. [bas] verilirse basma işini o yapar (ör. düzenleme ekranı: önce kaydet, sonra bas).
class EtiketYazdirDugmesi extends StatelessWidget {
  final FutureOr<UrunModel?> Function()? urun;
  final Future<void> Function(int adet)? bas;
  final String adetBasligi;
  final Color? renk;
  final double? boyut;
  final bool kompakt; // liste kartı: küçük, kenar boşluksuz
  const EtiketYazdirDugmesi({
    super.key,
    this.urun,
    this.bas,
    this.adetBasligi = 'Etiket',
    this.renk,
    this.boyut,
    this.kompakt = false,
  }) : assert(urun != null || bas != null);

  Future<void> _bas(BuildContext context, {bool adetSor = false}) async {
    if (bas != null) {
      var adet = 1;
      if (adetSor) {
        final n = await etiketAdediSor(context, adetBasligi);
        if (n == null || !context.mounted) return;
        adet = n;
      }
      await bas!(adet);
      return;
    }
    final u = await urun!();
    if (u == null || !context.mounted) return;
    var adet = 1;
    if (adetSor) {
      final n = await etiketAdediSor(context, u.urunAdi);
      if (n == null || !context.mounted) return;
      adet = n;
    }
    await urunEtiketiBas(context, u, adet: adet);
  }

  @override
  Widget build(BuildContext context) {
    final ikon = Icon(Icons.print_outlined, color: renk, size: boyut);
    return GestureDetector(
      onLongPress: () => _bas(context, adetSor: true),
      onSecondaryTap: () => _bas(context, adetSor: true),
      child: kompakt
          ? IconButton(
              icon: ikon,
              tooltip: 'Etiket yazdır (uzun bas: adet)',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _bas(context),
            )
          : IconButton(icon: ikon, tooltip: 'Etiket yazdır (uzun bas: adet)', onPressed: () => _bas(context)),
    );
  }
}

// ───────────────────────── Önizleme resmi ─────────────────────────

final _imzalar = Expando<String>();

/// Tasarımın içeriğine göre anahtar (aynı kimlikli tasarım düzenlenince önizleme tazelenir).
String tasarimImzasi(EtiketSablonu s) => _imzalar[s] ??= jsonEncode(tasarimJson(s));

String _veriImzasi(EtiketVeri v) => [
      v.ad, v.fiyat, v.barkod, v.indirimliFiyat, v.birimFiyat, v.tarih?.toIso8601String(), v.mensei, v.kod, v.grup, v.birim, v.skt //
    ].join('|');

/// Etiketin gerçek çıktısıyla aynı küçük resmi (beyaz kâğıt üstünde, en-boy oranı korunur).
class EtiketOnizleme extends StatefulWidget {
  final EtiketSablonu sablon;
  final EtiketVeri veri;
  final String mensei, firma;
  final double genislik; // ekranda (piksel)
  final double dpi;
  const EtiketOnizleme({
    super.key,
    required this.sablon,
    required this.veri,
    required this.mensei,
    required this.firma,
    this.genislik = 120,
    this.dpi = 140,
  });

  @override
  State<EtiketOnizleme> createState() => _EtiketOnizlemeState();
}

class _EtiketOnizlemeState extends State<EtiketOnizleme> {
  Uint8List? _png;
  bool _hata = false;
  String _anahtar = '';

  String get _yeniAnahtar =>
      '${tasarimImzasi(widget.sablon)}#${_veriImzasi(widget.veri)}#${widget.mensei}#${widget.firma}#${widget.dpi}';

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void didUpdateWidget(EtiketOnizleme eski) {
    super.didUpdateWidget(eski);
    if (_yeniAnahtar != _anahtar) _yukle();
  }

  Future<void> _yukle() async {
    final k = _anahtar = _yeniAnahtar;
    try {
      final png = await EtiketBaskiServisi.onizlemePng(widget.sablon, widget.veri,
          mensei: widget.mensei, firma: widget.firma, dpi: widget.dpi, anahtar: k);
      if (mounted && k == _anahtar) {
        setState(() {
          _png = png;
          _hata = false;
        });
      }
    } catch (e) {
      if (mounted && k == _anahtar) setState(() => _hata = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sablon;
    final w = widget.genislik, h = w * s.yukseklik / s.genislik;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white, // gerçek etiket beyaz kâğıt — temadan bağımsız
        border: Border.all(color: Colors.black26, width: 0.6),
        borderRadius: BorderRadius.circular(2),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: _png != null
          ? Image.memory(_png!, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium)
          : Center(
              child: _hata
                  ? const Icon(Icons.broken_image_outlined, size: 18, color: Colors.black38)
                  : const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6)),
            ),
    );
  }
}

// ───────────────────────── Yazıcı ayarları ─────────────────────────

Future<void> etiketYaziciAyarDialogu(BuildContext context) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Etiket yazıcısı'),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        content: const SizedBox(width: 460, child: SingleChildScrollView(child: EtiketYaziciPaneli())),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
      ),
    );

/// Etiket yazıcısı ayarları. Her değişiklik hemen kaydedilir; seçilen yazıcı bir sonraki basımda da kullanılır.
class EtiketYaziciPaneli extends StatefulWidget {
  /// Deneme etiketi düğmesi (seçili tasarımla örnek ürün basar).
  final bool denemeDugmesi;
  const EtiketYaziciPaneli({super.key, this.denemeDugmesi = true});

  @override
  State<EtiketYaziciPaneli> createState() => _EtiketYaziciPaneliState();
}

class _EtiketYaziciPaneliState extends State<EtiketYaziciPaneli> {
  final _yazdirma = YazdirmaServisi();
  EtiketYaziciAyari? _a;
  List<String>? _windowsYazicilari;
  final _adresCtrl = TextEditingController();
  final _boslukCtrl = TextEditingController();
  final _menseiCtrl = TextEditingController();
  Timer? _bekle;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final a = await EtiketAyarlari.yaziciYukle();
    await _yazdirma.ayarlariYukle();
    if (!mounted) return;
    _adresCtrl.text = a.tsplAdres;
    _boslukCtrl.text = _mmYaz(a.tspl.bosluk);
    _menseiCtrl.text = a.mensei;
    setState(() => _a = a);
    if (_windows) unawaited(_yazicilariYukle());
  }

  Future<void> _yazicilariYukle() async {
    try {
      final l = await Printing.listPrinters();
      if (mounted) setState(() => _windowsYazicilari = [for (final p in l) p.name]);
    } catch (e) {
      if (mounted) setState(() => _windowsYazicilari = const []);
    }
  }

  @override
  void dispose() {
    // Bekleyen yazı değişikliği kaybolmasın.
    if (_bekle?.isActive == true && _a != null) unawaited(EtiketAyarlari.yaziciKaydet(_a!));
    _bekle?.cancel();
    _adresCtrl.dispose();
    _boslukCtrl.dispose();
    _menseiCtrl.dispose();
    super.dispose();
  }

  void _degistir(EtiketYaziciAyari yeni, {bool gecikmeli = false}) {
    setState(() => _a = yeni);
    _bekle?.cancel();
    if (gecikmeli) {
      _bekle = Timer(const Duration(milliseconds: 500), () => EtiketAyarlari.yaziciKaydet(yeni));
    } else {
      unawaited(EtiketAyarlari.yaziciKaydet(yeni));
    }
  }

  Future<void> _denemeBas() async {
    final o = ornekEtiketVerisi();
    final u = UrunModel(
      urunAdi: 'DENEME ETİKETİ ${o.ad.replaceFirst('ÖRNEK ÜRÜN ADI ', '')}',
      birimAdi: 'Adet',
      satisFiyati: o.fiyat!,
      barkod: o.barkod,
      kod: o.kod,
      anaGrup: o.grup,
      indirimliFiyatKayitli: o.indirimliFiyat!,
      agirlik: 500,
    );
    // Bekleyen değişiklik önce kaydedilsin (adres yazılır yazılmaz denenebilir).
    if (_bekle?.isActive == true && _a != null) {
      _bekle!.cancel();
      await EtiketAyarlari.yaziciKaydet(_a!);
    }
    if (mounted) await etiketleriBas(context, [(u, 1)]);
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final cs = Theme.of(context).colorScheme;
    final kucuk = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final hataStil = TextStyle(fontSize: 12, color: cs.error);
    final bagli = _yazdirma.bagliMi ? _yazdirma.baglantiDurumu : null;
    final yazicilar = _windowsYazicilari;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<RafBasmaYontemi>(
        initialValue: a.yontem,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Nereye basılsın?', border: OutlineInputBorder(), isDense: true),
        items: [
          if (_windows)
            const DropdownMenuItem(value: RafBasmaYontemi.windows, child: Text('Windows yazıcısı (USB · XP-490B vb.)')),
          const DropdownMenuItem(value: RafBasmaYontemi.tspl, child: Text('Etiket yazıcısı — ağdan / bağlı (TSPL)')),
          const DropdownMenuItem(value: RafBasmaYontemi.escpos, child: Text('Fiş yazıcısı (ESC/POS)')),
        ],
        onChanged: (v) {
          if (v != null) _degistir(a.kopya(yontem: v));
        },
      ),
      const SizedBox(height: 12),
      if (a.yontem == RafBasmaYontemi.windows) ...[
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('wy-${yazicilar?.length}-${a.windowsYazici}'),
              initialValue: a.windowsYazici.isEmpty ? null : a.windowsYazici,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Yazıcı',
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: a.windowsYazici.isEmpty ? 'Etiket yazıcısını seçin' : null,
              ),
              items: [
                if (a.windowsYazici.isNotEmpty && !(yazicilar ?? const []).contains(a.windowsYazici))
                  DropdownMenuItem(
                      value: a.windowsYazici,
                      child: Text('${a.windowsYazici}${yazicilar == null ? '' : ' (bulunamadı)'}', overflow: TextOverflow.ellipsis)),
                for (final y in yazicilar ?? const <String>[])
                  DropdownMenuItem(value: y, child: Text(y, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v != null) _degistir(a.kopya(windowsYazici: v));
              },
            ),
          ),
          IconButton(tooltip: 'Yazıcı listesini yenile', icon: const Icon(Icons.refresh), onPressed: _yazicilariYukle),
        ]),
        const SizedBox(height: 6),
        Text('Sürücünün kendi etiket ayarlarıyla basılır. Seçilen yazıcı kaydedilir; her seferinde sorulmaz.', style: kucuk),
        const SizedBox(height: 12),
        SegmentedButton<RafEtiketKagidi>(
          segments: const [
            ButtonSegment(value: RafEtiketKagidi.rulo, label: Text('Etiket rulosu'), icon: Icon(Icons.receipt_long)),
            ButtonSegment(value: RafEtiketKagidi.a4, label: Text('A4 kâğıt'), icon: Icon(Icons.grid_on)),
          ],
          selected: {a.kagit},
          onSelectionChanged: (v) => _degistir(a.kopya(kagit: v.first)),
        ),
        // Telefondan bu bilgisayardaki (USB) etiket yazıcısına basmak için: 9100 portundan ağa aç.
        // Ayarlar > Yazıcılar'daki kartın aynısı — o ekran "ayarlar" yetkisi istediği için burada da var.
        const SizedBox(height: 12),
        const YaziciPaylasimKarti(),
      ] else if (a.yontem == RafBasmaYontemi.tspl) ...[
        TextField(
          controller: _adresCtrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Etiket yazıcısının adresi (IP)',
            hintText: '192.168.1.35  (port: 9100)',
            helperText: 'Yazıcı bir bilgisayara USB ile takılıysa o bilgisayarın IP adresi (orada Ayarlar > Yazıcılar > '
                '"Yazıcıyı ağa aç"). Boş bırakılırsa Ayarlar > Yazıcılar\'daki bağlı yazıcıya gider.',
            helperMaxLines: 4,
            errorText: _adresCtrl.text.trim().isEmpty || a.tsplAgda ? null : 'Geçersiz adres',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => _degistir(a.kopya(tsplAdres: v.trim()), gecikmeli: true),
        ),
        const SizedBox(height: 6),
        Text(
          a.tsplAgda
              ? 'Etiketler ${a.tsplAdres} adresine gider; fiş yazıcısı bağlantısı değişmez.'
              : bagli != null
                  ? 'Bağlı yazıcı: $bagli — bu bir fiş yazıcısıysa yukarıya etiket yazıcısının adresini yazın.'
                  : 'Etiket yazıcısının adresini yazın.',
          style: a.tsplAgda || bagli != null ? kucuk : hataStil,
        ),
        _tsplAyarlari(a),
      ] else ...[
        Text(
          bagli != null
              ? 'Bağlı yazıcı: $bagli'
              : 'Bağlı yazıcı yok. Ayarlar > Yazıcılar bölümünden fiş yazıcısını bağlayın.',
          style: bagli != null ? kucuk : hataStil,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Ayarlar > Yazıcılar'),
            onPressed: () => context.push('/ayarlar/yazici'),
          ),
        ),
      ],
      const SizedBox(height: 14),
      TextField(
        controller: _menseiCtrl,
        decoration: const InputDecoration(
          labelText: 'Menşei (varsayılan)',
          helperText: 'Ürün kartında menşei yazılıysa o kullanılır',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => _degistir(a.kopya(mensei: v), gecikmeli: true),
      ),
      if (widget.denemeDugmesi) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Deneme etiketi bas'),
            onPressed: _denemeBas,
          ),
        ),
      ],
      const SizedBox(height: 8),
    ]);
  }

  Widget _tsplAyarlari(EtiketYaziciAyari a) => ExpansionTile(
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
              final d = ParaUtils.sayiCoz(v);
              if (d != null && d >= 0 && d <= 20) {
                _degistir(a.kopya(tspl: TsplAyar(bosluk: d, ters: a.tspl.ters, koyuluk: a.tspl.koyuluk)), gecikmeli: true);
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ters basıyorsa çevir (180°)'),
            value: a.tspl.ters,
            onChanged: (v) => _degistir(a.kopya(tspl: TsplAyar(bosluk: a.tspl.bosluk, ters: v, koyuluk: a.tspl.koyuluk))),
          ),
          DropdownButtonFormField<int?>(
            initialValue: a.tspl.koyuluk,
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
            onChanged: (v) => _degistir(a.kopya(tspl: TsplAyar(bosluk: a.tspl.bosluk, ters: a.tspl.ters, koyuluk: v))),
          ),
        ],
      );
}
