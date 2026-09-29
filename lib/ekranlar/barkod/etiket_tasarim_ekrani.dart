// lib/ekranlar/barkod/etiket_tasarim_ekrani.dart
// v3.0 — Barkod/metin arama + barkod okuyucu ile ürün ekleme, çoklu etiket yazdırma
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../../cekirdek/utils/etiket_yardimci.dart';
import '../../widgetlar/ortak/yukleniyor_widget.dart';
part 'etiket_tasarim_ekrani_islemler.dart';
part 'etiket_tasarim_ekrani_gorunum.dart';

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
  _EtiketKalem({required this.urun}) : adet = 1;
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

  // Özel boyut — 4 hazır ölçünün yanında, mm cinsinden serbest boyut girişi.
  // "Raf etiketi" kullanımında işletmeler genelde kendi raf/ürün ölçüsüne
  // göre özel etiket kağıdı kullanır; sabit 4 preset yetersiz kalıyordu.
  bool _ozelBoyutAktif       = false;
  final _ozelGenislikCtrl    = TextEditingController(text: '58');
  final _ozelYukseklikCtrl   = TextEditingController(text: '30');

  // Yazı boyutu ölçeği — önizlemede ve ZPL çıktısında tüm metinleri
  // orantılı büyütüp küçültür. Termal (ESC/POS) tarafı donanım sınırlı
  // olduğundan (sabit iki boy) bu ölçekten etkilenmez.
  double _fontOlcek         = 1.0;

  // Kullanıcının kaydettiği adlandırılmış özel şablonlar (5 hazır şablonun
  // ötesinde) — SharedPreferences'ta JSON liste olarak saklanır.
  List<Map<String, dynamic>> _ozelSablonlar = [];

  double get _efGenislik => _ozelBoyutAktif
      ? (ParaUtils.sayiCoz(_ozelGenislikCtrl.text) ?? _boyut.w).clamp(20.0, 200.0)
      : _boyut.w;
  double get _efYukseklik => _ozelBoyutAktif
      ? (ParaUtils.sayiCoz(_ozelYukseklikCtrl.text) ?? _boyut.h).clamp(15.0, 200.0)
      : _boyut.h;
  PaperSize get _efKagit => _efGenislik > 65 ? PaperSize.mm80 : PaperSize.mm58;
  String get _boyutEtiketMetni => _ozelBoyutAktif
      ? '${_efGenislik.toStringAsFixed(0)}×${_efYukseklik.toStringAsFixed(0)} mm (özel)'
      : _boyut.etiket;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _btDurumKontrol();
    // Firma adı önizlemede doğru görünsün diye erken yükleniyor
    _yazdirma.ayarlariYukle().then((_) { if (mounted) setState(() {}); });
    _ozelSablonlariYukle();
  }

  @override
  void dispose() {
    _araDebounce?.cancel();
    _araCtrl.dispose();
    _araFocus.dispose();
    _ozelMetinCtrl.dispose();
    _ozelGenislikCtrl.dispose();
    _ozelYukseklikCtrl.dispose();
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
                backgroundColor: _btBagliMi ? TsRenk.zemin(TsRenk.basarili) : TsRenk.zemin(TsRenk.hata),
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

  /// KDV Dahil anahtarı kapalıysa önizlemede de net (KDV hariç) fiyat gösterilir
  /// — böylece önizleme gerçek çıktıyla birebir tutarlı olur.
  double _onizlemeFiyat(UrunModel u) {
    if (_kdvDahilGoster) return u.satisFiyati;
    final kdv = double.tryParse(u.kdvOran) ?? 0;
    return u.satisFiyati / (1 + kdv / 100);
  }

}