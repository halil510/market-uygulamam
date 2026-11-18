// lib/ekranlar/barkod/etiket_tasarim_ekrani.dart
// v4.0 — Etiket Yazdırma: ürün ara / barkod okut → listeye ekle → SEÇİLİ tasarım + SEÇİLİ yazıcıyla bas.
//
// İki sekme:
//   • Etiket Listesi: her ürünün etiketi, basılacağı tasarımla birebir küçük resim olarak görünür.
//   • Tasarım ve Yazıcı: tasarım seçimi (hazır BarTender şablonları + kendi tasarımlarınız; yeni / kopyala /
//     düzenle / sil) ve etiket yazıcısı ayarları. Seçimler kalıcıdır; ürün listesi / detay / düzenle ekranlarındaki
//     "Etiket yazdır" düğmesi de aynı tasarım ve yazıcıyı kullanır.
// (Eski "serbest etiket" anahtarları kaldırıldı; kayıtlı serbest şablonlar ilk açılışta kendi tasarıma çevrilir.)
import '../../cekirdek/utils/dosya_paylasim.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/etiket_ayarlari.dart';
import '../../servisler/etiket_baski_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../cekirdek/etiket/etiket_tasarimi.dart';
import '../../cekirdek/etiket/raf_etiket_sablonlari.dart';
import 'etiket_ortak.dart';
import 'etiket_tasarimci_ekrani.dart';
import 'raf_etiket_penceresi.dart';
part 'etiket_tasarim_ekrani_islemler.dart';
part 'etiket_tasarim_ekrani_gorunum.dart';

// Liste kalemi
class _EtiketKalem {
  final UrunModel urun;
  int adet;
  _EtiketKalem({required this.urun}) : adet = 1;
}

class EtiketTasarimEkrani extends StatefulWidget {
  const EtiketTasarimEkrani({super.key});
  @override
  State<EtiketTasarimEkrani> createState() => _EtiketTasarimEkraniState();
}

class _EtiketTasarimEkraniState extends State<EtiketTasarimEkrani> with SingleTickerProviderStateMixin {
  final _depo = UrunDeposu();
  final _yazdirma = YazdirmaServisi();
  final _araCtrl = TextEditingController();
  final _araFocus = FocusNode();
  late TabController _tab;
  MobileScannerController? _scanCtrl;

  List<UrunModel> _aramaSonuclari = [];
  final List<_EtiketKalem> _sepet = [];
  Timer? _araDebounce;
  bool _kameraAcik = false;
  // Kamera aynı barkodu saniyede birçok kez okur: kısa aralıkta tekrar eden okuma adet artırmaz.
  String? _sonTaranan;
  DateTime? _sonTaramaZamani;
  static const _ayniBarkodMinAralik = Duration(milliseconds: 1200);

  // Tasarım ve yazıcı (EtiketAyarlari'ndan; başka ekranda değişirse tazelenir)
  List<EtiketSablonu> _tasarimlar = sablonlar;
  EtiketSablonu _secili = sablonlar.first;
  EtiketYaziciAyari? _ayar;
  String _firma = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    EtiketAyarlari.degisti.addListener(_ayarlariYukle);
    _ayarlariYukle();
  }

  @override
  void dispose() {
    EtiketAyarlari.degisti.removeListener(_ayarlariYukle);
    _araDebounce?.cancel();
    _araCtrl.dispose();
    _araFocus.dispose();
    _tab.dispose();
    _scanCtrl?.dispose();
    super.dispose();
  }

  Future<void> _ayarlariYukle() async {
    try {
      final t = await EtiketAyarlari.tumTasarimlar();
      final s = await EtiketAyarlari.seciliTasarim();
      final a = await EtiketAyarlari.yaziciYukle();
      await _yazdirma.ayarlariYukle();
      if (!mounted) return;
      setState(() {
        _tasarimlar = t;
        _secili = s;
        _ayar = a;
        _firma = _yazdirma.firmaAdiOnizleme;
      });
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Etiket ayarları okunamadı: $e');
    }
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
    if (b == _sonTaranan && _sonTaramaZamani != null && simdi.difference(_sonTaramaZamani!) < _ayniBarkodMinAralik) {
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
    if (_kameraAcik) {
      try {
        HapticFeedback.lightImpact();
      } catch (_) {/* titreşim yoksa önemsiz */}
    }
  }

  // ── Liste işlemleri ───────────────────────────────────────────────────────
  void _sepeteEkle(UrunModel urun) {
    setState(() {
      final idx = _sepet.indexWhere((k) => k.urun.id == urun.id);
      if (idx >= 0) {
        _sepet[idx].adet = (_sepet[idx].adet + 1).clamp(1, 999);
      } else {
        _sepet.add(_EtiketKalem(urun: urun));
      }
      _aramaSonuclari = [];
    });
    _araCtrl.clear();
    if (_tab.index != 0) _tab.animateTo(0);
  }

  void _adetDegistir(int idx, int yeni) {
    setState(() {
      if (yeni <= 0) {
        _sepet.removeAt(idx);
      } else {
        _sepet[idx].adet = yeni.clamp(1, 999);
      }
    });
  }

  int get _toplamEtiket => _sepet.fold(0, (s, k) => s + k.adet);

  List<(UrunModel, int)> get _kalemler => [for (final k in _sepet) (k.urun, k.adet)];

  /// Önizlemelerde kullanılan ürün: listedeki ilk ürün, yoksa örnek.
  EtiketVeri get _ornekVeri => _sepet.isEmpty ? ornekEtiketVerisi() : etiketVerisi(_sepet.first.urun);

  @override
  Widget build(BuildContext context) {
    final bagli = _yazdirma.bagliMi ? _yazdirma.baglantiDurumu : null;
    final ozet = _ayar?.ozet(bagliYazici: bagli) ?? '…';
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Etiket Yazdırma',
        aksiyonlar: [
          if (MediaQuery.sizeOf(context).width >= 700)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: ActionChip(
                avatar: const Icon(Icons.print_outlined, size: 16),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(ozet, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                ),
                tooltip: 'Etiket yazıcısı',
                onPressed: () => etiketYaziciAyarDialogu(context),
              ),
            ),
          if (_sepet.isNotEmpty) ...[
            IconButton(icon: const Icon(Icons.preview_outlined), onPressed: _onizle, tooltip: 'Önizle'),
            IconButton(icon: const Icon(Icons.sd_card_outlined), onPressed: _zplDisaAktar, tooltip: 'ZPL (Zebra) olarak gönder / paylaş'),
            Badge(
              label: Text('$_toplamEtiket'),
              child: IconButton(icon: const Icon(Icons.print), onPressed: _yazdir, tooltip: 'Yazdır'),
            ),
          ],
        ],
        alt: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'Etiket Listesi'),
            Tab(icon: Icon(Icons.tune), text: 'Tasarım ve Yazıcı'),
          ],
        ),
      ),
      body: TabBarView(controller: _tab, children: [_listesiTab(), _ayarTab()]),
      floatingActionButton: _sepet.isEmpty
          ? null
          : FloatingActionButton.extended(
              elevation: 6,
              backgroundColor: TsRenk.primary,
              foregroundColor: Colors.white,
              onPressed: _yazdir,
              icon: const Icon(Icons.print),
              label: Text('$_toplamEtiket Etiket Yazdır'),
            ),
    );
  }
}
