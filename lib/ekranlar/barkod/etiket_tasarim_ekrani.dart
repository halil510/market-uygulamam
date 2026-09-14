// lib/ekranlar/barkod/etiket_tasarim_ekrani.dart
// v3.0 — Barkod/metin arama + barkod okuyucu ile ürün ekleme, çoklu etiket yazdırma
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' show PaperSize;
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/zpl_servisi.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../widgetlar/ortak/yukleniyor_widget.dart';

enum EtiketBoyut {
  kucuk('40×25 mm',  40.0, 25.0, PaperSize.mm58),
  orta( '58×30 mm',  58.0, 30.0, PaperSize.mm58),
  buyuk('80×40 mm',  80.0, 40.0, PaperSize.mm80),
  genis('100×50 mm', 100.0, 50.0, PaperSize.mm80);

  final String etiket;
  final double w, h;
  final PaperSize kagit;
  const EtiketBoyut(this.etiket, this.w, this.h, this.kagit);
}

// Sepet kalem modeli
class _EtiketKalem {
  final UrunModel urun;
  int adet;
  _EtiketKalem({required this.urun, this.adet = 1});
}

class EtiketTasarimEkrani extends ConsumerStatefulWidget {
  const EtiketTasarimEkrani({super.key});
  @override
  ConsumerState<EtiketTasarimEkrani> createState() => _EtiketTasarimEkraniState();
}

class _EtiketTasarimEkraniState extends ConsumerState<EtiketTasarimEkrani>
    with SingleTickerProviderStateMixin {
  final _depo       = UrunDeposu();
  final _yazdirma   = YazdirmaServisi();
  final _araCtrl    = TextEditingController();
  final _araFocus   = FocusNode();
  late TabController _tab;
  MobileScannerController? _scanCtrl;

  // Ürün listesi ve sepet
  List<UrunModel>   _aramaSonuclari = [];
  List<_EtiketKalem> _sepet        = [];
  Timer?            _araDebounce;
  bool              _kameraAcik    = false;
  // 🔴 Derin analizde bulundu: kamera barkod tarayıcısında hiç debounce
  // yoktu — MobileScanner.onDetect, bir barkod kamerada göründüğü
  // sürece SANİYEDE BİRÇOK KEZ tetiklenir. Kullanıcı bir ürünü kararsız
  // tutarken (bir sonrakine geçmeden önce), her tetiklenme adedi 1
  // artırıyordu — kullanıcı fark etmeden yazdırma kuyruğuna istenenden
  // çok daha fazla etiket ekleniyordu.
  String? _sonTaranan;
  DateTime? _sonTaramaZamani;
  static const _ayniBarkodMinAralik = Duration(milliseconds: 1200);
  bool              _btBagliMi     = false;

  // Etiket ayarları
  EtiketBoyut _boyut        = EtiketBoyut.orta;
  bool _barkodGoster         = true;
  bool _fiyatGoster          = true;
  bool _adGoster             = true;
  bool _firmaBilgi           = false;
  bool _birimFiyatliMod      = false;
  bool _lotNoGoster          = false;
  bool _sktGoster            = false;
  bool _anaGrupGoster        = false;
  bool _kdvDahilGoster       = true;
  bool _aciklamaGoster       = false;
  String _ozelMetin          = '';  // Her etikette sabit yazı
  final _ozelMetinCtrl       = TextEditingController();
  String _secilenSablon      = 'Varsayılan';
  final List<String> _sablonlar = ['Varsayılan', 'Gıda', 'Tekstil', 'Elektronik', 'Kargo'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _btDurumKontrol();
    // Firma adı önizlemede doğru görünsün diye erken yükleniyor
    _yazdirma.ayarlariYukle().then((_) { if (mounted) setState(() {}); });
  }

  Future<void> _btDurumKontrol() async {
    try {  
      final b = await _yazdirma.btBagliMi;
      if (mounted) setState(() => _btBagliMi = b);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  /// Şablon seçimi, o ürün türü için genelde anlamlı olan alanları otomatik
  /// açar/kapatır. Kullanıcı seçtikten sonra dilediği anahtarı yine elle
  /// değiştirebilir — şablon sadece bir başlangıç noktası sunar.
  void _sablonUygula(String sablon) {
    setState(() {
      _secilenSablon = sablon;
      switch (sablon) {
        case 'Gıda':
          _sktGoster = true;
          _lotNoGoster = true;
          _anaGrupGoster = false;
          _aciklamaGoster = false;
        case 'Tekstil':
          _sktGoster = false;
          _lotNoGoster = false;
          _anaGrupGoster = true;
          _aciklamaGoster = true;
        case 'Elektronik':
          _sktGoster = false;
          _lotNoGoster = true; // seri no amaçlı
          _anaGrupGoster = true;
          _aciklamaGoster = false;
        case 'Kargo':
          _sktGoster = false;
          _lotNoGoster = false;
          _anaGrupGoster = false;
          _aciklamaGoster = true;
        default: // Varsayılan
          _sktGoster = false;
          _lotNoGoster = false;
          _anaGrupGoster = false;
          _aciklamaGoster = false;
      }
    });
  }

  @override
  void dispose() {
    _araDebounce?.cancel();
    _araCtrl.dispose();
    _araFocus.dispose();
    _ozelMetinCtrl.dispose();
    _tab.dispose();
    _scanCtrl?.dispose();
    super.dispose();
  }

  // ── Arama ─────────────────────────────────────────────────────────────────
  void _aramaDegisti(String q) {
    _araDebounce?.cancel();
    if (q.trim().isEmpty) {
      if (mounted) setState(() => _aramaSonuclari = []);
      return;
    }
    _araDebounce = Timer(const Duration(milliseconds: 280), () async {
      final s = await _depo.ara(q.trim(), limit: 30);
      if (!mounted) return;
      setState(() => _aramaSonuclari = s);
    });
  }

  // ── Barkod okuyucu ────────────────────────────────────────────────────────
  void _kameraToggle() {
    setState(() {
      _kameraAcik = !_kameraAcik;
      if (_kameraAcik) {
        _scanCtrl = MobileScannerController(facing: CameraFacing.back);
      } else {
        _scanCtrl?.dispose();
        _scanCtrl = null;
      }
    });
  }

  Future<void> _barkodIleEkle(String barkod) async {
    final b = barkod.trim();
    if (b.isEmpty) return;
    final simdi = DateTime.now();
    if (b == _sonTaranan && _sonTaramaZamani != null &&
        simdi.difference(_sonTaramaZamani!) < _ayniBarkodMinAralik) {
      return;
    }
    _sonTaranan = b;
    _sonTaramaZamani = simdi;
    final urun = await _depo.barkodlaGetir(b);
    if (!mounted) return;
    if (urun == null) {
      BildirimServisi.uyari(context, 'Barkod bulunamadı: $b');
      return;
    }
    _sepeteEkle(urun);
    // Kamera modunda hafif titreşim
    if (_kameraAcik) {
      try { HapticFeedback.lightImpact(); } catch (e) { /* ignore */ }
    }
  }

  // ── Sepet işlemleri ───────────────────────────────────────────────────────
  void _sepeteEkle(UrunModel urun) {
    setState(() {
      final idx = _sepet.indexWhere((k) => k.urun.id == urun.id);
      if (idx >= 0) {
        _sepet[idx].adet = (_sepet[idx].adet + 1).clamp(1, 999);
      } else {
        _sepet.add(_EtiketKalem(urun: urun));
      }
    });
    // Arama kutusunu temizle ve sekmeye git
    _araCtrl.clear();
    _aramaSonuclari = [];
    if (_tab.index != 0) _tab.animateTo(0);
  }

  void _adetDegistir(int idx, int yeni) {
    setState(() {
      if (yeni <= 0) _sepet.removeAt(idx);
      else _sepet[idx].adet = yeni.clamp(1, 999);
    });
  }

  // ── Yazdır ────────────────────────────────────────────────────────────────
  Future<void> _yazdir() async {
    if (_sepet.isEmpty) { BildirimServisi.uyari(context, 'Ürün ekleyin'); return; }
    if (!_btBagliMi) {
      _showBtUyari();
      return;
    }

    showDialog(
      context: context, barrierDismissible: false,
      builder: (bCtx) => const ProgressDialog(mesaj: 'Etiketler yazdırılıyor...'),
    );

    try {
      int toplam = 0;
      for (final kalem in _sepet) {
        await _yazdirma.etiketYazdir(
          kalem.urun,
          barkodGoster:    _barkodGoster,
          fiyatGoster:     _fiyatGoster,
          adGoster:        _adGoster,
          birimFiyatliMod: _birimFiyatliMod,
          etiketBoy:       _boyut.kagit,
          adet:            kalem.adet,
          firmaGoster:     _firmaBilgi,
          lotNoGoster:     _lotNoGoster,
          sktGoster:       _sktGoster,
          anaGrupGoster:   _anaGrupGoster,
          kdvDahilFiyat:   _kdvDahilGoster,
          aciklamaGoster:  _aciklamaGoster,
          ozelMetin:       _ozelMetin,
        );
        toplam += kalem.adet;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      BildirimServisi.basari(context,
          '$toplam etiket gönderildi (${_sepet.length} çeşit)');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      BildirimServisi.hata(context, 'Yazıcı hatası: $e');
    }
  }

  /// Sepetteki etiketleri ZPL'e çevirip seçenek sunar:
  /// - Bağlı bir yazıcı (WiFi/BT) varsa: doğrudan gönder (BarTender'a gerek yok)
  /// - Yoksa veya kullanıcı isterse: .zpl dosyası olarak dışa aktar (BarTender vb.)
  Future<void> _zplDisaAktar() async {
    if (_sepet.isEmpty) { BildirimServisi.uyari(context, 'Ürün ekleyin'); return; }
    final zpl = ZplServisi.topluZpl(
      _sepet.map((k) => (urun: k.urun, adet: k.adet)).toList(),
      genislikMm: _boyut.w,
      yukseklikMm: _boyut.h,
      barkodGoster: _barkodGoster,
      fiyatGoster: _fiyatGoster,
      adGoster: _adGoster,
      firmaGoster: _firmaBilgi,
      firmaAdi: _yazdirma.firmaAdiOnizleme,
      anaGrupGoster: _anaGrupGoster,
      lotNoGoster: _lotNoGoster,
      sktGoster: _sktGoster,
      aciklamaGoster: _aciklamaGoster,
      kdvDahilFiyat: _kdvDahilGoster,
      ozelMetin: _ozelMetin,
    );

    if (_yazdirma.bagliMi) {
      final secim = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16),
              child: Text('Etiketler nasıl gönderilsin?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          // ZPL önizleme — gönderilmeden önce küçük bir özet ve kod örneği
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TsRenk.arkaplan(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TsRenk.ayirac(context)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.label_outline, size: 16, color: TsRenk.metinIkincil(context)),
                  const SizedBox(width: 6),
                  Text('${_boyut.etiket} • ${_sepet.length} çeşit • '
                      '${_sepet.fold<int>(0, (t, k) => t + k.adet)} adet',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TsRenk.metinBirincil(context))),
                ]),
                const SizedBox(height: 6),
                Text(
                  zpl.length > 160 ? '${zpl.substring(0, 160)}...' : zpl,
                  maxLines: 4, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: TsRenk.metinIkincil(context)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.print, color: Colors.blue),
            title: const Text('Bağlı Yazıcıya Doğrudan Gönder (ZPL)'),
            subtitle: Text('Zebra/ZPL uyumlu — ${_yazdirma.baglantiDurumu}'),
            onTap: () => Navigator.pop(ctx, 'direkt'),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share, color: Colors.orange),
            title: const Text('.zpl Dosyası Olarak Paylaş'),
            subtitle: const Text('BarTender veya başka bir uygulamaya aktarın'),
            onTap: () => Navigator.pop(ctx, 'dosya'),
          ),
          const SizedBox(height: 8),
        ])),
      );
      if (secim == null) return;
      if (secim == 'direkt') {
        try {
          await _yazdirma.zplGonder(zpl);
          if (mounted) BildirimServisi.basari(context, 'Etiketler yazıcıya gönderildi (ZPL)');
        } catch (e) {
          if (mounted) BildirimServisi.hata(context, 'ZPL gönderim hatası: $e');
        }
        return;
      }
    }

    await _zplDosyaPaylas(zpl);
  }

  Future<void> _zplDosyaPaylas(String zpl) async {
    try {
      final dir = await getTemporaryDirectory();
      final dosya = File('${dir.path}/etiketler_${DateTime.now().millisecondsSinceEpoch}.zpl');
      await dosya.writeAsString(zpl);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(dosya.path, mimeType: 'text/plain')],
        subject: 'MarketPlus Etiketler (ZPL)',
        text: 'Bu .zpl dosyasını BarTender veya Zebra/ZPL uyumlu '
              'bir etiket yazıcısına "Dosyadan Yazdır" ile gönderebilirsiniz.\n'
              'Etiket boyutu: ${_boyut.etiket}, Toplam: '
              '${_sepet.fold<int>(0, (t, k) => t + k.adet)} adet.',
      );
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'ZPL dışa aktarma hatası: $e');
    }
  }

  void _showBtUyari() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Row(children: [
          Icon(Icons.print_disabled, color: Colors.red), const SizedBox(width: 8),
          Text('Yazıcı Bağlı Değil'),
        ]),
        content: const Text('Etiket yazdırmak için önce Yazıcı Ayarları ekranından '
            'Bluetooth yazıcıya bağlanın.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }

  int get _toplamEtiket => _sepet.fold(0, (s, k) => s + k.adet);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Etiket Yazdırma',
        aksiyonlar: [
          // BT durum chip
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: GestureDetector(
              onTap: () => context.push('/ayarlar/yazici'),
              child: Chip(
                avatar: Icon(
                  _btBagliMi ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  size: 14,
                  color: _btBagliMi ? Colors.green : Colors.red,
                ),
                label: Text(_btBagliMi ? 'Bağlı' : 'Yok',
                    style: TextStyle(fontSize: 11,
                        color: _btBagliMi ? Colors.green.shade700 : Colors.red.shade700)),
                backgroundColor: _btBagliMi ? Colors.green.shade50 : Colors.red.shade50,
              ),
            ),
          ),
          // Yazdır butonu
          if (_sepet.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.sd_card_outlined),
              onPressed: _zplDisaAktar,
              tooltip: 'ZPL Dışa Aktar (BarTender/Zebra)',
            ),
            Badge(
              label: Text('$_toplamEtiket'),
              child: IconButton(
                icon: const Icon(Icons.print),
                onPressed: _yazdir,
                tooltip: 'Yazdır',
              ),
            ),
          ],
        ],
        alt: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'Etiket Listesi'),
            Tab(icon: Icon(Icons.tune), text: 'Ayarlar'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_listesiTab(), _ayarTab()],
      ),
      floatingActionButton: _sepet.isEmpty ? null : GestureDetector(
        onLongPress: _zplDisaAktar,
        child: FloatingActionButton.extended(
          elevation: 6,
          backgroundColor: const Color(0xFF4361EE),
          foregroundColor: Colors.white,
          onPressed: _yazdir,
          icon: const Icon(Icons.print),
          label: Text('$_toplamEtiket Etiket Yazdır'),
        ),
      ),
    );
  }

  // ── Etiket Listesi Tab ────────────────────────────────────────────────────
  Widget _listesiTab() {
    return Column(children: [
      // Arama + barkod okuyucu satırı
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _araCtrl,
              focusNode: _araFocus,
              onChanged: _aramaDegisti,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _barkodIleEkle(v.trim());
              },
              decoration: InputDecoration(
                hintText: 'Ürün adı veya barkod ara…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _araCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _araCtrl.clear();
                          setState(() => _aramaSonuclari = []);
                        })
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Barkod okuyucu butonu
          GestureDetector(
            onTap: _kameraToggle,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _kameraAcik
                    ? Theme.of(context).colorScheme.primary
                    : Color.fromARGB(26, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _kameraAcik ? Icons.qr_code_scanner : Icons.qr_code_scanner,
                color: _kameraAcik ? Colors.white : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ]),
      ),

      // Kamera önizleme
      if (_kameraAcik && _scanCtrl != null)
        _kameraPaneli(),

      // Arama sonuçları overlay
      if (_aramaSonuclari.isNotEmpty && !_kameraAcik)
        _aramaSonucListesi(),

      // Sepet başlığı
      if (_sepet.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(children: [
            Text('${_sepet.length} çeşit • $_toplamEtiket etiket',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: const Text('Temizle', style: TextStyle(fontSize: 12)),
              onPressed: () => setState(() => _sepet.clear()),
            ),
          ]),
        ),

      // Sepet listesi
      Expanded(
        child: _sepet.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.qr_code_2, size: 64, color: TsRenk.metinIkincil(context)),
                const SizedBox(height: 14),
                Text('Ürün arayın veya barkod okutun',
                    style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 14)),
                const SizedBox(height: 6),
                Text('Birden fazla ürün ve adet seçebilirsiniz',
                    style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 12)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                itemCount: _sepet.length,
                itemBuilder: (_, i) => _sepetKalemKarti(i),
              ),
      ),
    ]);
  }

  // ── Kamera paneli ─────────────────────────────────────────────────────────
  Widget _kameraPaneli() {
    return Container(
      height: 180,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          MobileScanner(
            controller: _scanCtrl!,
            onDetect: (capture) {
              final barkod = capture.barcodes.firstOrNull?.rawValue;
              if (barkod != null && barkod.isNotEmpty) {
                _barkodIleEkle(barkod);
              }
            },
          ),
          // Çerçeve
          Center(
            child: Container(
              width: 200, height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 8, left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Barkodu çerçeve içine getirin',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            )),
          ),
        ]),
      ),
    );
  }

  // ── Arama sonuç listesi ───────────────────────────────────────────────────
  Widget _aramaSonucListesi() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        decoration: BoxDecoration(
          color: TsRenk.kart(context),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _aramaSonuclari.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final u = _aramaSonuclari[i];
            final barkodGecerli = u.barkod != null &&
                u.barkod!.isNotEmpty && u.barkod!.length >= 8;
            return ListTile(
              dense: true,
              leading: barkodGecerli
                  ? SizedBox(
                      width: 52, height: 36,
                      child: bw.BarcodeWidget(
                        barcode: u.barkod!.length == 13
                            ? bw.Barcode.ean13(drawEndChar: false)
                            : bw.Barcode.code128(),
                        data: u.barkod!,
                        style: const TextStyle(fontSize: 6),
                        errorBuilder: (_, __) =>
                            Icon(Icons.qr_code, size: 32, color: context.textSecondary),
                      ),
                    )
                  : Icon(Icons.qr_code, size: 36, color: context.textSecondary),
              title: Text(u.urunAdi,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(u.barkod ?? '-',
                  style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(ParaUtils.formatla(u.satisFiyati),
                    style: TsMetin.kucukVurgu.copyWith(color: Theme.of(context).colorScheme.primary)),
                const SizedBox(width: 8),
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(26, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.add, size: 18,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ]),
              onTap: () => _sepeteEkle(u),
            );
          },
        ),
      ),
    );
  }

  // ── Sepet kalem kartı ─────────────────────────────────────────────────────
  Widget _sepetKalemKarti(int i) {
    final k = _sepet[i];
    final u = k.urun;
    final barkodGecerli = u.barkod != null &&
        u.barkod!.isNotEmpty && u.barkod!.length >= 8;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TsRenk.ayirac(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          // Etiket önizleme (küçük)
          _miniEtiketOnizleme(u, barkodGecerli),
          const SizedBox(width: 12),
          // Ürün bilgileri
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.urunAdi,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(u.barkod ?? '-',
                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context),
                      fontFamily: 'monospace')),
              const SizedBox(height: 2),
              Text(ParaUtils.formatla(u.satisFiyati),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary)),
            ]),
          ),
          // Adet kontrol
          Column(children: [
            // Adet direkt düzenleme
            GestureDetector(
              onTap: () => _adetDialogu(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Color.fromARGB(20, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Color.fromARGB(76, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue)),
                ),
                child: Text('${k.adet} adet',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary)),
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _adetBtn(Icons.remove, () => _adetDegistir(i, k.adet - 1)),
              const SizedBox(width: 4),
              _adetBtn(Icons.add, () => _adetDegistir(i, k.adet + 1)),
              const SizedBox(width: 4),
              _adetBtn(Icons.delete_outline, () => _adetDegistir(i, 0),
                  renk: Colors.red),
            ]),
          ]),
        ]),
      ),
    );
  }

  Widget _miniEtiketOnizleme(UrunModel u, bool barkodGecerli) {
    final w = _boyut.w * 1.8;
    final h = _boyut.h * 1.8;
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        // Gerçek etiket her zaman beyaz sticker kağıdıdır — bu önizleme
        // bilinçli olarak temadan bağımsız, sabit beyaz tutuluyor (içindeki
        // koyu metinlerle tutarlı kalması için).
        color: Colors.white,
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(3),
        boxShadow: [BoxShadow(color: Color(0x0F000000),
            blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // NOT: Bu önizleme kutusunun arkaplanı bilinçli olarak sabit
          // beyaz (gerçek etiket kağıdı gibi) — bu yüzden İÇİNDEKİ TÜM
          // metinler de sabit koyu renkte olmalı. Önceden bazı metinler
          // hiç renk belirtmiyordu (karanlık modda tema varsayılanından
          // açık renk miras alıp beyaz zeminde kaybolurdu) ya da yanlışlıkla
          // tema-uyarlamalı renklere geçirilmişti (karanlık modda açık
          // griye dönüp yine kaybolurdu). Hepsi sabitlendi.
          if (_firmaBilgi)
            Text(_yazdirma.firmaAdiOnizleme,
                style: TextStyle(fontSize: w * 0.03, color: Colors.black87),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          if (_adGoster)
            Text(u.urunAdi,
                style: TextStyle(fontSize: w * 0.04, fontWeight: FontWeight.bold, color: Colors.black),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          if (_anaGrupGoster && (u.anaGrup?.isNotEmpty ?? false))
            Text(u.anaGrup!,
                style: TextStyle(fontSize: w * 0.03, color: context.textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          if (barkodGecerli && _barkodGoster)
            Flexible(child: bw.BarcodeWidget(
              barcode: u.barkod!.length == 13
                  ? bw.Barcode.ean13(drawEndChar: false)
                  : bw.Barcode.code128(),
              data: u.barkod!,
              style: TextStyle(fontSize: w * 0.025),
              errorBuilder: (_, __) => const SizedBox.shrink(),
            )),
          if (_lotNoGoster && (u.lotNo?.isNotEmpty ?? false))
            Text('Lot: ${u.lotNo}',
                style: TextStyle(fontSize: w * 0.025, color: context.textSecondary)),
          if (_sktGoster && (u.sonKullanmaTarihi?.isNotEmpty ?? false))
            Text('SKT: ${u.sonKullanmaTarihi}',
                style: TextStyle(fontSize: w * 0.025, color: context.textSecondary)),
          if (_aciklamaGoster && (u.lotAciklama?.isNotEmpty ?? false))
            Text(u.lotAciklama!,
                style: TextStyle(fontSize: w * 0.022, color: context.textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          if (_fiyatGoster)
            Text('${ParaUtils.formatla(_onizlemeFiyat(u))} ₺',
                style: TextStyle(fontSize: w * 0.045, fontWeight: FontWeight.w900,
                    color: Colors.red.shade700)),
          if (_ozelMetin.trim().isNotEmpty)
            Text(_ozelMetin.trim(),
                style: TextStyle(fontSize: w * 0.025, fontStyle: FontStyle.italic),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  /// KDV Dahil anahtarı kapalıysa önizlemede de net (KDV hariç) fiyat gösterilir
  /// — böylece önizleme gerçek çıktıyla birebir tutarlı olur.
  double _onizlemeFiyat(UrunModel u) {
    if (_kdvDahilGoster) return u.satisFiyati;
    final kdv = double.tryParse(u.kdvOran) ?? 0;
    return u.satisFiyati / (1 + kdv / 100);
  }

  Widget _adetBtn(IconData icon, VoidCallback onTap, {Color? renk}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: Color.fromARGB(20, (renk ?? Theme.of(context).colorScheme.primary).red, (renk ?? Theme.of(context).colorScheme.primary).green, (renk ?? Theme.of(context).colorScheme.primary).blue),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16,
              color: renk ?? Theme.of(context).colorScheme.primary),
        ),
      );

  // Adet dialog - klavye ile hızlı giriş
  Future<void> _adetDialogu(int i) async {
    final ctrl = TextEditingController(text: '${_sepet[i].adet}');
    final yeni = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: Text(_sepet[i].urun.urunAdi,
            style: const TextStyle(fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(
            labelText: 'Kaç adet etiket?',
            border: OutlineInputBorder(), isDense: true),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ParaUtils.tamSayiCoz(ctrl.text)),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    if (yeni != null) _adetDegistir(i, yeni);
  }

  // ── Ayarlar Tab ───────────────────────────────────────────────────────────
  Widget _ayarTab() => ListView(padding: const EdgeInsets.all(16), children: [
    _baslik('Şablon'),
    DropdownButtonFormField<String>(
      value: _secilenSablon,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        helperText: 'Şablon, ürün türüne uygun alanları otomatik açar/kapatır',
        helperMaxLines: 2,
      ),
      items: _sablonlar.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: (v) { if (v != null) _sablonUygula(v); },
    ),
    const Divider(height: 24),
    _baslik('Etiket Boyutu'),
    ...EtiketBoyut.values.map((b) => RadioListTile<EtiketBoyut>(
      title: Text(b.etiket),
      subtitle: Text('${b.w.toInt()}×${b.h.toInt()} mm · '
          '${b.kagit == PaperSize.mm58 ? "58mm kağıt" : "80mm kağıt"}'),
      value: b, groupValue: _boyut,
      onChanged: (v) { if (v != null) setState(() => _boyut = v); },
    )),
    const Divider(height: 24),
    _baslik('İçerik'),
    SwitchListTile(
        title: const Text('Ürün Adı'), value: _adGoster,
        onChanged: (v) => setState(() => _adGoster = v)),
    SwitchListTile(
        title: const Text('Barkod'), value: _barkodGoster,
        onChanged: (v) => setState(() => _barkodGoster = v)),
    SwitchListTile(
        title: const Text('Fiyat'), value: _fiyatGoster,
        onChanged: (v) => setState(() => _fiyatGoster = v)),
    SwitchListTile(
        title: const Text('KDV Dahil Fiyat'),
        subtitle: const Text('Kapalıysa KDV hariç (net) fiyat basılır'),
        value: _kdvDahilGoster,
        onChanged: (v) => setState(() => _kdvDahilGoster = v)),
    SwitchListTile(
        title: const Text('Firma Adı'), value: _firmaBilgi,
        onChanged: (v) => setState(() => _firmaBilgi = v)),
    SwitchListTile(
        title: const Text('Ana Grup / Kategori'), value: _anaGrupGoster,
        onChanged: (v) => setState(() => _anaGrupGoster = v)),
    SwitchListTile(
        title: const Text('Lot No'),
        subtitle: const Text('Ürünün Lot/Seri numarası varsa gösterilir'),
        value: _lotNoGoster,
        onChanged: (v) => setState(() => _lotNoGoster = v)),
    SwitchListTile(
        title: const Text('Son Kullanma Tarihi (SKT)'), value: _sktGoster,
        onChanged: (v) => setState(() => _sktGoster = v)),
    SwitchListTile(
        title: const Text('Açıklama'),
        subtitle: const Text('Üründeki lot açıklaması varsa gösterilir'),
        value: _aciklamaGoster,
        onChanged: (v) => setState(() => _aciklamaGoster = v)),
    SwitchListTile(
        title: const Text('Birim Fiyatlı Mod'),
        subtitle: const Text('Adet/KG + fiyat yan yana'),
        value: _birimFiyatliMod,
        onChanged: (v) => setState(() => _birimFiyatliMod = v)),
    const SizedBox(height: 8),
    TextField(
      controller: _ozelMetinCtrl,
      maxLength: 40,
      decoration: InputDecoration(
        labelText: 'Özel Metin (opsiyonel)',
        hintText: 'Örn: "Kampanya Ürünü", "Yeni"',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      onChanged: (v) => setState(() => _ozelMetin = v),
    ),
    const SizedBox(height: 16),
    _baslik('Sepet Özeti'),
    if (_sepet.isEmpty)
      Text('Henüz ürün eklenmedi.',
          style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 13))
    else
      ..._sepet.map((k) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k.urun.urunAdi,
              style: const TextStyle(fontSize: 13), maxLines: 1,
              overflow: TextOverflow.ellipsis)),
          Text('${k.adet} adet',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      )),
    if (_sepet.isNotEmpty) ...[
      const Divider(height: 20),
      Text('Toplam: $_toplamEtiket etiket',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  ]);

  Widget _baslik(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary)),
  );
}