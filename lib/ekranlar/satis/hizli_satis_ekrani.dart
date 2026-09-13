// lib/ekranlar/satis/hizli_satis_ekrani.dart  (Riverpod v2.2)
//
// DEĞIŞIKLIKLER:
//   - StatefulWidget → ConsumerStatefulWidget
//   - Consumer<HizliSatisNotifier> → ref.watch(sepetProvider)
//   - context.read<HizliSatisNotifier>() → ref.read(sepetProvider.notifier)
//   - Tüm "final n = context.read<HizliSatisNotifier>()" → ref.read(sepetProvider.notifier)
//   - Otomatik yazdırma kaldırıldı, manuel yazdırma ikonu appBar'a eklendi.

import 'package:flutter/foundation.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import 'package:intl/intl.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/ts_token.dart';
import 'widgets/hizli_satis_arama_paneli.dart';
import 'widgets/hizli_tus_paneli.dart';
import 'hizli_tus_yonetim_ekrani.dart';
import 'para_ustu_ekrani.dart';
import 'widgets/hizli_satis_sepet_listesi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/satis_model.dart';
import '../../modeller/sepet_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/satis_deposu.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/onay_merkezi_servisi.dart';
import '../../servisler/satis_tamamlama_servisi.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../saglayicilar/riverpod/sepet_provider.dart';
import '../../saglayicilar/riverpod/dashboard_provider.dart';
import '../../cekirdek/utils/para_utils.dart';
import 'bekleyen_fisler_ekrani.dart';
import 'widgets/satis_alt_panel.dart';
import 'widgets/kamera_paneli.dart';
import 'coklu_odeme_ekrani.dart';
import 'fis_onizleme_ekrani.dart';
import 'plu_ekrani.dart';
import '../../servisler/aktif_sube_servisi.dart';

class HizliSatisEkrani extends ConsumerStatefulWidget {
  const HizliSatisEkrani({super.key});

  @override
  ConsumerState<HizliSatisEkrani> createState() => _HizliSatisEkraniState();
}

class _HizliSatisEkraniState extends ConsumerState<HizliSatisEkrani>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  final _urunDepo  = UrunDeposu();
  final _cariDepo  = CariDeposu();
  final _satisDepo = SatisDeposu();
  final _satisTamamlamaServisi = SatisTamamlamaServisi();

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 FİŞ GÜNCELLEME MODU
  //
  // null  → normal satış (yeni fiş kesilecek)
  // dolu  → fiş barkodu okutuldu, bu fişe EKLEME yapılıyor.
  //         "Tamamla"ya basılınca yeni fiş kesilmez; sadece sepetteki
  //         fişin kalemleri sepete YÜKLENİR; kasiyer düzeltme yapar
  //         veya ürün ekler. "Tamamla"da sepetin son hali fişin yeni
  //         içeriği olur (SatisDeposu.fisiGuncelle).
  // ══════════════════════════════════════════════════════════════════════
  SatisModel? _guncellenenSatis;

  final _araCtrl  = TextEditingController();
  final _araFocus = FocusNode();
  late MobileScannerController _scanCtrl;
  late AnimationController _laserAnim;
  final AudioPlayer _player = AudioPlayer();
  Future<int>? _bekleyenSayiFuture;

  // ── Son satış bilgisi (manuel yazdırma için) ──
  SatisModel? _sonSatis;

  // Barkod kontrol
  final Queue<String> _barkodKuyrugu = Queue<String>();
  Timer? _barkodIslemeTimer;
  bool _barkodIsleniyor = false;
  bool _islemAktif  = false;
  bool _dialogAcik  = false;
  final _sepetScroll = ScrollController();
  String?  _sonIslenenBarkod;
  DateTime? _sonIslenenZaman;
  static const _ayniBarkodMinAralik = Duration(milliseconds: 800);
  bool  _scannerKilitli = false;
  Timer? _scannerKilitAcmaTimer;

  Timer? _araDebounce;
  int   _aramaId = 0;
  // Arama sonuçları artık local state — sepetProvider'a gerek yok
  List<UrunModel> _aramaSonuclari = [];
  bool _kameraAcik = false;
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanCtrl = MobileScannerController(
      torchEnabled: false,
      facing: CameraFacing.back,
    );
    _player.setPlayerMode(PlayerMode.lowLatency);
    _laserAnim = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _bekleyenSayiFuture = BekleyenFislerEkrani.bekleyenSayi();
    // Promosyonları yükle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(aktifPromosyonlarProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _araDebounce?.cancel();
    _barkodIslemeTimer?.cancel();
    _scannerKilitAcmaTimer?.cancel();
    if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }
    _scanCtrl.dispose();
    _player.dispose();
    _laserAnim.dispose();
    _araCtrl.dispose();
    _araFocus.dispose();
    _sepetScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }
    } else if (state == AppLifecycleState.resumed) {
      if (_kameraAcik && !_islemAktif && !_dialogAcik) {
        try { _scanCtrl.start(); } catch (e) { /* ignore */ }
      }
    }
  }

  // ── İşlem Kontrol ───────────────────────────────────────────────────────────
  void _islemBasladi() {
    _islemAktif = true;
    if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }
  }

  void _islemBitti() {
    _islemAktif = false;
    _dialogAcik = false;
    if (_kameraAcik && mounted) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    _kuyruktakiBarkodlariIsle();
  }

  // ── Barkod Kontrol ───────────────────────────────────────────────────────────
  Future<void> _barkodOkutIsle(String barkod) async {
    if (_islemAktif || _dialogAcik) {
      _barkodKuyrugu.add(barkod);
      _kuyruktakiBarkodlariIsle();
      return;
    }
    if (_sonIslenenBarkod == barkod && _sonIslenenZaman != null &&
        DateTime.now().difference(_sonIslenenZaman!) < _ayniBarkodMinAralik) return;
    if (_scannerKilitli || _barkodIsleniyor) {
      _barkodKuyrugu.add(barkod);
      _kuyruktakiBarkodlariIsle();
      return;
    }
    await _barkodIsle(barkod);
  }

  Future<void> _barkodIsle(String barkod) async {
    _barkodIsleniyor = true;
    _sonIslenenBarkod = barkod;
    _sonIslenenZaman = DateTime.now();
    _scannerKilitli = true;
    _scannerKilitAcmaTimer = Timer(const Duration(milliseconds: 300), () {
      _scannerKilitli = false;
      _kuyruktakiBarkodlariIsle();
    });
    _bipSes();
    try {
      await _barkodIleEkle(barkod);
    } catch (e) {
      if (kDebugMode) debugPrint('Barkod işleme hatası: $e');
      if (mounted) {
        BildirimServisi.hata(context, 'Ürün eklenemedi: $barkod bulunamadı veya bir hata oluştu');
      }
    } finally {
      _barkodIsleniyor = false;
    }
  }

  void _kuyruktakiBarkodlariIsle() {
    _barkodIslemeTimer?.cancel();
    if (_barkodKuyrugu.isEmpty || _islemAktif || _dialogAcik) return;
    _barkodIslemeTimer = Timer(const Duration(milliseconds: 150), () async {
      if (_barkodKuyrugu.isNotEmpty && !_islemAktif && !_dialogAcik && !_barkodIsleniyor) {
        final barkod = _barkodKuyrugu.removeFirst();
        await _barkodIsle(barkod);
        if (_barkodKuyrugu.isNotEmpty) _kuyruktakiBarkodlariIsle();
      }
    });
  }

  void _bipSes() {
    if (_islemAktif || _dialogAcik) return;
    _player.stop().then((_) {
      _player.play(AssetSource('sounds/bip.mp3'), volume: 0.5);
    }).catchError((_) {});
    Vibration.hasVibrator().then((has) {
      if (has ?? false) Vibration.vibrate(duration: 50);
    }).catchError((_) {});
  }

  // ── PLU / Barkod İşleme ──────────────────────────────────────────────────────
  Future<void> _pluAc() async {
    try {  
      _araFocus.unfocus();
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useRootNavigator: true,
        builder: (sheetCtx) => PluEkrani(
          onUrunSec: (urun) {
            ref.read(sepetProvider.notifier).ekleAsync(urun);
            Navigator.pop(sheetCtx);
          },
        ),
      );
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  // ── 🆕 HIZLI TUŞ (FAVORİ ÜRÜN) PANELİ ────────────────────────────────────────
  Future<void> _hizliTusAc() async {
    var tekrarAc = true;
    while (tekrarAc && mounted) {
      tekrarAc = false;
      try {
        if (!mounted) return;
        _araFocus.unfocus();
        final sonuc = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          useRootNavigator: true,
          builder: (sheetCtx) => HizliTusPaneli(
            onUrunSec: (urun) async {
              Navigator.pop(sheetCtx, 'secildi');
              if (!mounted) return;
              if (_kgBirimMi(urun.birimAdi)) {
                await _kgIleEkle(urun);
              } else {
                await ref.read(sepetProvider.notifier).ekleAsync(urun);
              }
              if (!mounted) return;
              _bipSes();
              if (_sepetScroll.hasClients) _sepetScroll.jumpTo(0);
            },
            onDuzenle: () => Navigator.pop(sheetCtx, 'duzenle'),
          ),
        );

        if (sonuc == 'duzenle' && mounted) {
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const HizliTusYonetimEkrani()),
          );
          tekrarAc = true;
        }
      } catch (e) {
        if (kDebugMode) if (mounted) debugPrint('Hızlı tuş hatası: $e');
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 FİŞ BARKODU TANIMA
  static final _fisNoDeseni = RegExp(r'^(MKP|CRI|MSA)\d{13}$');
  bool _fisBarkoduMu(String b) => _fisNoDeseni.hasMatch(b.toUpperCase());

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 FİŞ GERİ ÇAĞIRMA
  Future<void> _fisGeriCagir(String fisNo) async {
    try {
      final satis = await _satisDepo.fisNoIleGetir(fisNo);
      if (!mounted) return;

      if (satis == null) {
        BildirimServisi.uyari(context,
            'Fiş bulunamadı veya iptal edilmiş: $fisNo');
        return;
      }

      final mevcutSepet = ref.read(sepetProvider).kalemler;
      if (mevcutSepet.isNotEmpty) {
        final devam = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)),
              SizedBox(width: 8),
              Expanded(child: Text('Sepet Dolu', style: TextStyle(fontSize: 15))),
            ]),
            content: Text(
              'Sepetinizde ${mevcutSepet.length} ürün var.\n\n'
              'Fiş geri çağrılırsa bu ürünler SİLİNECEK.',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade800),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sepeti Boşalt, Devam Et'),
              ),
            ],
          ),
        );
        if (devam != true || !mounted) return;
      }

      final onay = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.receipt_long_rounded, color: Color(0xFF4361EE)),
            SizedBox(width: 8),
            Expanded(child: Text('Fiş Bulundu', style: TextStyle(fontSize: 15))),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fisOzetSatiri('Fiş No', satis.fisNo ?? '-'),
              _fisOzetSatiri('Tarih',
                  DateFormat('dd.MM.yyyy HH:mm').format(satis.tarih)),
              if ((satis.cariAdi ?? '').isNotEmpty)
                _fisOzetSatiri('Cari', satis.cariAdi!),
              _fisOzetSatiri('Ürün', '${satis.kalemler.length} kalem'),
              _fisOzetSatiri('Tutar', ParaUtils.formatla(satis.genelToplam)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: Colors.orange.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fişin ürünleri sepete yüklenecek. Miktar '
                      'değiştirebilir, kalem silebilir, yeni ürün '
                      'ekleyebilirsiniz.\n\n'
                      'Tamamladığınızda FİŞ GÜNCELLENECEK — müşterideki '
                      'basılı fiş ile sistemdeki kayıt farklı olacaktır.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton.icon(
              icon: const Icon(Icons.edit_rounded, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('Fişi Düzenle'),
            ),
          ],
        ),
      );
      if (onay != true || !mounted) return;

      ref.read(sepetProvider.notifier).temizle();

      final bulunamayan = <String>[];
      for (final k in satis.kalemler) {
        final urun = await _urunDepo.idileGetir(k.urunId);
        if (urun == null) {
          bulunamayan.add(k.urunAdi);
          continue;
        }
        ref.read(sepetProvider.notifier).ekle(
          urun,
          miktar: k.miktar,
          fiyatOverride: k.birimFiyat,
        );
      }
      if (!mounted) return;

      setState(() {
        _guncellenenSatis = satis;
      });

      if (bulunamayan.isNotEmpty) {
        BildirimServisi.uyari(context,
            '${bulunamayan.length} ürün artık kayıtlı değil ve sepete '
            'yüklenemedi: ${bulunamayan.take(3).join(", ")}'
            '${bulunamayan.length > 3 ? "…" : ""}');
      } else {
        BildirimServisi.basari(context,
            'Fiş ${satis.fisNo} sepete yüklendi — düzeltme yapıp '
            'veya ürün ekleyip tamamlayın');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Fiş çağrılamadı: $e');
    }
  }

  Widget _fisOzetSatiri(String etiket, String deger) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
            width: 62,
            child: Text('$etiket:',
                style: TextStyle(
                    fontSize: 12, color: context.textSecondary)),
          ),
          Expanded(
            child: Text(deger,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Future<void> _barkodIleEkle(String barkod) async {
    if (!mounted) return;
    final b = barkod.trim();

    if (_fisBarkoduMu(b)) {
      await _fisGeriCagir(b.toUpperCase());
      return;
    }

    if (b.length == 13) {
      final prefix = int.tryParse(b.substring(0, 2)) ?? 0;
      if (prefix >= 20 && prefix <= 29) {
        final urunKodu  = b.substring(2, 7);
        final agirlikStr = b.substring(7, 12);
        final agirlik   = (int.tryParse(agirlikStr) ?? 0) / 1000.0;
        final urun      = await _urunDepo.barkodlaGetir(urunKodu);
        if (!mounted) return;
        if (urun != null && agirlik > 0) {
          ref.read(sepetProvider.notifier).ekleAsync(urun, miktar: agirlik);
          return;
        }
      }
    }

    final urun = await _urunDepo.barkodlaGetir(b);
    if (!mounted) return;
    if (urun != null) {
      if (_kgBirimMi(urun.birimAdi)) {
        await _kgIleEkle(urun);
      } else {
        await ref.read(sepetProvider.notifier).ekleAsync(urun);
      }
      Future.microtask(() {
        if (_sepetScroll.hasClients) _sepetScroll.jumpTo(0);
      });
      return;
    }
    if (!mounted) return;
    final kayitYap = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.search_off_rounded, color: Color(0xFFE65100)),
          SizedBox(width: 8),
          Text('Ürün Bulunamadı', style: TextStyle(fontSize: 15)),
        ]),
        content: Text('$b\n\nBu barkodla ürün kaydı yok.\nŞimdi eklemek ister misiniz?',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hayır'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ürün Ekle'),
          ),
        ],
      ),
    );
    if (kayitYap != true || !mounted) return;
    final eklendi = await context.push<bool>(
      '/urun/ekle',
      extra: {'barkod': b, 'kaynak': 'hizli_satis'},
    );
    if (!mounted) return;
    if (eklendi == true) {
      final yeniUrun = await _urunDepo.barkodlaGetir(b);
      if (!mounted) return;
      if (yeniUrun != null) {
        ref.read(sepetProvider.notifier).ekle(yeniUrun);
        BildirimServisi.basari(context, '${yeniUrun.urunAdi} sepete eklendi');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sepetScroll.hasClients) {
            _sepetScroll.animateTo(0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
          }
        });
      }
    }
  }

  bool _kgBirimMi(String birimAdi) {
    final b = birimAdi.toLowerCase()
        .replaceAll('ı', 'i').replaceAll('İ'.toLowerCase(), 'i');
    return b == 'kg' || b == 'kilogram' || b == 'gr' || b == 'gram' ||
        b == 'lt' || b == 'litre' || b == 'ml' || b == 'mt' || b == 'metre';
  }

  Future<void> _kgIleEkle(UrunModel urun) async {
    if (!mounted) return;
    _dialogAcik = true;
    _islemAktif = true;
    if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }

    final ctrl = TextEditingController();
    double m = 0;

    final miktar = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            const Icon(Icons.scale_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(urun.urunAdi,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Miktar (${urun.birimAdi})',
                prefixIcon: const Icon(Icons.scale_rounded, color: Colors.orange),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                m = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                ss(() {});
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: m > 0 ? Colors.green.shade50 : TsRenk.arkaplan(ctx),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: m > 0 ? Colors.green.shade300 : TsRenk.ayirac(ctx)),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('\${m.toStringAsFixed(3)} \${urun.birimAdi}',
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(ctx))),
                  Text('@\${ParaUtils.formatla(urun.indirimliFiyat)}/\${urun.birimAdi}',
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(ctx))),
                ]),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Tutar:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(m > 0 ? ParaUtils.formatla(m * urun.indirimliFiyat) : '—',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                        color: m > 0 ? Colors.green.shade700 : context.textSecondary)),
                ]),
              ]),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx); },
              child: const Text('İptal'),
            ),
            FilledButton.icon(
              onPressed: () {
                final mv = double.tryParse(ctrl.text.replaceAll(',', '.'));
                if (mv == null || mv <= 0) return;
                _dialogAcik = false;
                _islemAktif = false;
                Navigator.pop(ctx, mv);
              },
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Ekle'),
              style: FilledButton.styleFrom(foregroundColor: Colors.white,
                  backgroundColor: Colors.orange),
            ),
          ],
        ),
      ),
    );

    if (_kameraAcik && mounted) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    if (!mounted || miktar == null || miktar <= 0) return;
    ref.read(sepetProvider.notifier).ekle(urun, miktar: miktar);
    Future.microtask(() {
      if (_sepetScroll.hasClients) _sepetScroll.jumpTo(0);
    });
    _kuyruktakiBarkodlariIsle();
  }

  // ── Arama ────────────────────────────────────────────────────────────────────
  void _aramaDegisti(String q) {
    _araDebounce?.cancel();
    final temiz = q.trim();
    if (temiz.isEmpty) {
      setState(() => _aramaSonuclari = []);
      return;
    }
    if (temiz.length < 2) return;
    final aramaId = ++_aramaId;
    _araDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final sonuclar = await _urunDepo.ara(temiz, limit: 20);
        if (!mounted || aramaId != _aramaId) return;
        setState(() => _aramaSonuclari = sonuclar);
      } catch (e) { /* ignore */ }
    });
  }

  Future<void> _urunSepeteEkleAkilli(UrunModel urun) async {
    try {
      if (_kgBirimMi(urun.birimAdi)) {
        _kgIleEkle(urun);
      } else {
        await ref.read(sepetProvider.notifier).ekleAsync(urun);
      }
      _araCtrl.clear();
      setState(() => _aramaSonuclari = []);
      Future.microtask(() {
        if (_sepetScroll.hasClients && _sepetScroll.position.pixels > 0) {
          _sepetScroll.jumpTo(0);
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Ürün ekleme hatası: $e');
      if (mounted) {
        BildirimServisi.hata(context, '${urun.urunAdi} sepete eklenemedi: $e');
      }
    }
  }

  // ── Kamera Toggle ────────────────────────────────────────────────────────────
  void _kameraToggle() {
    final yeni = !_kameraAcik;
    if (yeni) {
      if (!_islemAktif && !_dialogAcik) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    } else {
      try { _scanCtrl.stop(); } catch (e) { /* ignore */ }
    }
    setState(() => _kameraAcik = yeni);
  }

  // ── İndirim Dialog ───────────────────────────────────────────────────────────
  Future<void> _indirimDuzenle(SepetKalem k, int index) async {
    if (!mounted) return;
    _dialogAcik = true;
    _islemAktif = true;
    if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }

    final normalFiyat = k.urun.satisFiyati;
    final mevcutOran  = k.birimFiyat < normalFiyat - 0.01
        ? ((1 - k.birimFiyat / normalFiyat) * 100) : 0.0;
    final oranCtrl  = TextEditingController(
        text: mevcutOran > 0 ? mevcutOran.toStringAsFixed(1) : '');
    final fiyatCtrl = TextEditingController(
        text: k.birimFiyat.toStringAsFixed(2));

    final uygula = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        void oranDegisti(String v) {
          final oran = double.tryParse(v.replaceAll(',', '.'));
          if (oran != null && oran > 0 && oran < 100) {
            fiyatCtrl.text = (normalFiyat * (1 - oran / 100)).toStringAsFixed(2);
          } else if (oran == 0) {
            fiyatCtrl.text = normalFiyat.toStringAsFixed(2);
          }
          ss(() {});
        }
        void fiyatDegisti(String v) {
          final fiyat = double.tryParse(v.replaceAll(',', '.'));
          if (fiyat != null && fiyat > 0 && fiyat < normalFiyat) {
            oranCtrl.text = ((1 - fiyat / normalFiyat) * 100).toStringAsFixed(1);
          } else if (fiyat != null && fiyat >= normalFiyat) {
            oranCtrl.text = '';
          }
          ss(() {});
        }
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(k.urun.urunAdi,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: TextField(
                controller: oranCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'İndirim %', border: OutlineInputBorder()),
                onChanged: oranDegisti,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: fiyatCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Fiyat ₺', border: OutlineInputBorder()),
                onChanged: fiyatDegisti,
              )),
            ]),
          ]),
          actions: [
            TextButton(
              onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx, false); },
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx, true); },
              child: const Text('Uygula'),
            ),
          ],
        );
      }),
    );

    if (_kameraAcik && mounted) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    if (uygula != true || !mounted) return;
    final yeniFiyat = double.tryParse(fiyatCtrl.text.replaceAll(',', '.'));
    if (yeniFiyat != null && yeniFiyat > 0) {
      ref.read(sepetProvider.notifier).fiyatGuncelle(index, yeniFiyat);
    }
  }

  // ── Müşteri Seç ──────────────────────────────────────────────────────────────
  Future<void> _musteriSec() async {
    _islemBasladi();
    try {
      final cariler = await _cariDepo.tumunuGetir();
      if (!mounted) return;
      final secilen = await showModalBottomSheet<CariModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _MusteriSecimPaneli(cariler: cariler),
      );
      if (secilen == null || !mounted) return;

      final tedarikciMi = secilen.cariTipi.contains('edarik');
      if (tedarikciMi) {
        if (ref.read(sepetProvider).bos) {
          BildirimServisi.bilgi(context,
              '${secilen.unvan} bir Tedarikçi. Sepet boş olduğu için doğrudan Alım ekranına yönlendiriliyorsunuz.');
          if (mounted) context.push('/tedarik/alim', extra: secilen);
          return;
        }
        await _sepetiAlimaAktar(secilen);
        return;
      }

      ref.read(sepetProvider.notifier).musteriSec(secilen);
    } catch (e) {
      if (kDebugMode) debugPrint('Müşteri seçme hatası: $e');
      if (mounted) BildirimServisi.hata(context, 'Müşteri listesi yüklenemedi: $e');
    } finally {
      _islemBitti();
    }
  }

  // ── Ödeme Akışı ──────────────────────────────────────────────────────────────
  Future<void> _odemeYontemiSec() async {
    final sepet  = ref.read(sepetProvider);
    if (sepet.bos) return;
    _islemBasladi();

    try {
      final yontem = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _OdemeSecimSheet(toplam: sepet.genelToplam, musteriSecili: sepet.musteri != null),
      );
      if (!mounted || yontem == null) return;

      if (yontem == 'Karma') {
        final sonuc = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => SizedBox(
            height: MediaQuery.of(context).size.height * 0.94,
            child: CokluOdemeEkrani(
              toplamTutar: sepet.genelToplam,
              cariMevcut: sepet.musteri != null,
            ),
          ),
        );
        if (!mounted || sonuc == null) return;
        final kalemler = (sonuc['kalemler'] as List).cast<Map<String, dynamic>>();
        final toplamOdenen = (sonuc['toplam_odenen'] as num?)?.toDouble() ?? sepet.genelToplam;
        final paraUstu = (sonuc['para_ustu'] as num?)?.toDouble() ?? 0.0;
        final odemeYontemiEtiketi = kalemler.length == 1
            ? (kalemler.first['yontem'] as String) : 'Karma';
        await _satisiTamamla(odemeYontemiEtiketi, toplamOdenen, paraUstu,
            karmaKalemler: kalemler);
      } else if (yontem == 'Nakit') {
        final alinan = await _nakitAlintiSor(sepet.genelToplam);
        if (!mounted || alinan == null) return;
        final paraUstu = alinan - sepet.genelToplam;
        await _satisiTamamla('Nakit', alinan, paraUstu > 0 ? paraUstu : 0.0);
      } else {
        await _satisiTamamla(yontem, sepet.genelToplam, 0.0);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Ödeme akışı hatası: $e');
      if (mounted) BildirimServisi.hata(context, 'Ödeme işlemi başarısız: $e');
    } finally {
      _islemBitti();
    }
  }

  Future<double?> _nakitAlintiSor(double toplam) async {
    _dialogAcik = true;
    final ctrl = TextEditingController();
    final sonuc = await showDialog<double?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) { _dialogAcik = false; _islemAktif = false; },
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Nakit Ödeme'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Toplam: ${ParaUtils.formatla(toplam)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(
                hintText: 'Boş → tam tutar',
                labelText: 'Alınan Tutar (₺)',
                prefixIcon: Icon(Icons.payments),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: const Text('Para Üstü Hesapla'),
                onPressed: () async {
                  final alinan = await Navigator.push<double>(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) =>
                          ParaUstuEkrani(odenmesiGereken: toplam),
                    ),
                  );
                  if (alinan != null) {
                    ctrl.text = alinan.toStringAsFixed(2);
                  }
                },
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx); },
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final txt = ctrl.text.trim().replaceAll(',', '.');
                final val = txt.isEmpty ? toplam : double.tryParse(txt);
                _dialogAcik = false; _islemAktif = false;
                Navigator.pop(ctx, val);
              },
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
    return sonuc;
  }

  // ── Satış Tamamla ────────────────────────────────────────────────────────────
  Future<void> _fisiGuncelle() async {
    final satis = _guncellenenSatis;
    if (satis == null || satis.id == null) return;

    final sepet    = ref.read(sepetProvider);
    final kalemler = List<SepetKalem>.from(sepet.kalemler);
    if (kalemler.isEmpty) {
      BildirimServisi.uyari(context,
          'Sepet boş. Fişi tamamen iptal etmek için Satışlar ekranını kullanın.');
      return;
    }

    _islemBasladi();
    try {
      final kullanici = await AuthServisi().mevcutKullanici();
      if (!mounted) return;

      // Kalemler + stok farkı + cari/kasa hareketi — hepsi
      // SatisTamamlamaServisi.fisiGuncelle()'de TEK transaction'da atomik
      // (protokol §6/§35 — önceden bu ekranda 4 ayrı, transaction'sız
      // çağrıydı; davranış birebir korunarak servise taşındı).
      final sonuc = await _satisTamamlamaServisi.fisiGuncelle(
        satis: satis,
        yeniKalemler: kalemler,
        yeniGenelToplam: sepet.genelToplam,
        kullanici: kullanici,
      );
      final tutarFarki = sonuc.tutarFarki;

      if (satis.cariId != null && mounted) {
        ProviderScope.containerOf(context, listen: false)
            .invalidate(cariDetayProvider(satis.cariId!));
      }

      if (!mounted) return;
      ref.read(sepetProvider.notifier).temizle();
      ref.read(dashboardProvider.notifier).yenile();

      // Güncellenmiş fiş bilgisini _sonSatis'e ata (manuel yazdırma için)
      setState(() {
        _sonSatis = sonuc.guncelSatis;
      });

      setState(() => _guncellenenSatis = null);

      final ozet = tutarFarki > 0
          ? '+${ParaUtils.formatla(tutarFarki)}'
          : tutarFarki < 0
              ? '-${ParaUtils.formatla(-tutarFarki)}'
              : 'tutar değişmedi';
      BildirimServisi.basari(context, 'Fiş ${satis.fisNo} güncellendi ($ozet)');

      // YAZDIRMA DİALOGU KALDIRILDI — manuel yazdırma butonu ile yapılacak.

    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Fiş güncellenemedi: $e');
    } finally {
      _islemBitti();
    }
  }

  Future<void> _satisiTamamla(
      String odemeYontemi, double odenenTutar, double paraUstu,
      {List<Map<String, dynamic>>? karmaKalemler}) async {
    if (!mounted) return;

    if (_guncellenenSatis != null) {
      await _fisiGuncelle();
      return;
    }

    _islemBasladi();
    ref.read(sepetProvider.notifier).satisBasladi();

    final sepet     = ref.read(sepetProvider);
    final musteri   = sepet.musteri;
    final kalemler  = List<SepetKalem>.from(sepet.kalemler);
    final genelTop  = sepet.genelToplam;

    try {
      final kullanici = await AuthServisi().mevcutKullanici();
      if (!mounted) return;

      // Satış kaydı + stok düşümü + kasa/cari hareketi + bulut senkronu +
      // puan — hepsi SatisTamamlamaServisi'nde (tek transaction, atomik).
      // Önceden bu mantık doğrudan bu ekranda yaşıyordu (protokol §6/§35
      // — mimari borç); davranış BİREBİR korunarak servise taşındı.
      final sonuc = await _satisTamamlamaServisi.tamamla(
        kalemler:      kalemler,
        musteri:       musteri,
        genelToplam:   genelTop,
        odemeYontemi:  odemeYontemi,
        odenenTutar:   odenenTutar,
        karmaKalemler: karmaKalemler,
        kullanici:     kullanici,
        subeId:        AktifSubeServisi().subeId,
      );
      final satisId = sonuc.satisId;
      final fisNo = sonuc.fisNo;
      final tarih = sonuc.tarih;
      final satisKalemler = sonuc.kalemler;

      // FAZ 9 — Onay Merkezi (bildirim tipi): satış ENGELLENMEDİ, zaten
      // tamamlandı — sadece genel iskonto oranı eşiği aşıyorsa sonradan
      // incelenebilsin diye kayda düşülüyor.
      OnayMerkeziServisi().kaydet(
        tur: OnayTuru.yuksekIskonto,
        tutar: sepet.genelIskontoYuzde,
        esikTutar: OnayEsikleri.yuksekIskontoOrani,
        referansTuru: 'satis',
        referansId: satisId,
        aciklama: 'Fiş $fisNo: %${sepet.genelIskontoYuzde.toStringAsFixed(0)} iskonto',
      );

      if (!mounted) return;

      // ── Son satış bilgisini sakla (manuel yazdırma için) ──
      setState(() {
        _sonSatis = SatisModel(
          id: satisId,
          fisNo: fisNo,
          tarih: tarih,
          odemeYontemi: odemeYontemi,
          genelToplam: genelTop,
          odenenTutar: odenenTutar,
          kalemler: satisKalemler,
          cariId: musteri?.id,
          cariAdi: musteri?.unvan,
        );
      });

      ref.read(sepetProvider.notifier).temizle();
      ref.read(dashboardProvider.notifier).yenile();
      setState(() {
        _bekleyenSayiFuture = BekleyenFislerEkrani.bekleyenSayi();
      });

      final mesaj = (odemeYontemi == 'Nakit' && paraUstu > 0.005)
          ? 'Satış tamamlandı ✓  Para üstü: ${ParaUtils.formatla(paraUstu)}'
          : 'Satış başarıyla tamamlandı ✓';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mesaj),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Fişi Gör',
            textColor: Colors.white,
            onPressed: () {
              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => FisOnizlemeEkrani(satis: SatisModel(
                  id:          satisId,
                  fisNo:       fisNo,
                  tarih:       tarih,
                  odemeYontemi: odemeYontemi,
                  genelToplam: genelTop,
                  odenenTutar: odenenTutar,
                  kalemler:    satisKalemler,
                  cariId:      musteri?.id,
                  cariAdi:     musteri?.unvan,
                )),
              ));
            },
          ),
        ));
      }

      // Yazdırma işlemi tamamen kaldırıldı. Kullanıcı appBar'daki yazıcı ikonu ile manuel olarak yazdıracak.

    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Satış hatası: $e');
    } finally {
      if (mounted) ref.read(sepetProvider.notifier).satisGitti();
      _islemBitti();
    }
  }

  // ── Sepet Kalem Düzenleme ────────────────────────────────────────────────────
  Future<void> _sepetKalemMiktarDuzenle(SepetKalem k, int index) async {
    if (_kgBirimMi(k.urun.birimAdi)) { await _kgIleEkle(k.urun); return; }
    _dialogAcik = true;
    _islemAktif = true;
    if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }

    final ctrl = TextEditingController(text: k.miktar.toInt().toString());
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(k.urun.urunAdi,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: 'Miktar',
            border: const OutlineInputBorder(),
            suffixText: k.urun.birimAdi,
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx, false); },
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx, true); },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );

    if (_kameraAcik && mounted) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    if (ok != true || !mounted) return;
    final yeniMiktar = double.tryParse(ctrl.text.replaceAll(',', '.'));
    if (yeniMiktar == null || yeniMiktar <= 0) {
      ref.read(sepetProvider.notifier).sil(index);
    } else {
      ref.read(sepetProvider.notifier).miktarGuncelle(index, yeniMiktar);
    }
    _kuyruktakiBarkodlariIsle();
  }

  // ── Askıya Al ────────────────────────────────────────────────────────────────
  Future<void> _sepetiAlimaAktar(CariModel tedarikci) async {
    final sepet = ref.read(sepetProvider);
    if (sepet.bos || !mounted) return;

    final sepetKalemler = sepet.kalemler.map((k) => {
      'urunId':    k.urun.id,
      'urunAdi':   k.urun.urunAdi,
      'miktar':    k.miktar,
      'alisFiyat': k.urun.alisFiyat > 0 ? k.urun.alisFiyat : k.urun.satisFiyati,
    }).toList();

    ref.read(sepetProvider.notifier).temizle();
    if (!mounted) return;

    await context.push('/tedarik/alim',
        extra: {'tedarikci': tedarikci, 'kalemler': sepetKalemler});
    if (mounted) setState(() {});
  }

  Future<void> _tedarikciyeAktar() async {
    final sepet = ref.read(sepetProvider);
    if (sepet.bos) return;
    _islemBasladi();
    try {
      final list = await CariDeposu().tumunuGetir().then((l) => l.where((x) =>
          x.cariTipi.contains('edarik') || x.cariTipi.contains('Hem ')).toList());
      if (!mounted) { _islemBitti(); return; }
      final tedarikci = await showDialog<CariModel>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.shopping_basket_outlined, color: Colors.teal),
            const SizedBox(width: 8),
            Text('Tedarikçi Seç'),
          ]),
          contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          content: SizedBox(
            width: double.maxFinite, height: 360,
            child: list.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.person_off_outlined, size: 48, color: context.textSecondary),
                  const SizedBox(height: 8),
                  Text('Tedarikçi bulunamadı', style: TextStyle(color: context.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Cari menüsünden Tedarikçi ekleyin',
                      style: TextStyle(fontSize: 12, color: context.textSecondary), textAlign: TextAlign.center),
                ]))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final t = list[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(radius: 18,
                        backgroundColor: Colors.teal.shade50,
                        child: Text(t.unvan.isNotEmpty ? t.unvan[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.teal.shade700))),
                      title: Text(t.unvan, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: t.telefon != null ? Text(t.telefon!) : null,
                      onTap: () => Navigator.pop(ctx, t),
                    );
                  }),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal'))],
        ),
      );
      _islemBitti();
      if (tedarikci == null || !mounted) return;
      await _sepetiAlimaAktar(tedarikci);
    } catch (e) {
      _islemBitti();
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<void> _askiyaAl() async {
    final sepet = ref.read(sepetProvider);
    if (sepet.bos) return;
    _islemBasladi();

    try {
      await BekleyenFislerEkrani.askiyaAl(
        sepet:   sepet.kalemler,
        musteri: sepet.musteri,
      );

      ref.read(sepetProvider.notifier).temizle();
      if (mounted) setState(() => _bekleyenSayiFuture = BekleyenFislerEkrani.bekleyenSayi());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Satış askıya alındı'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Askıya alma hatası: $e');
      if (mounted) BildirimServisi.hata(context, 'Askıya alınamadı: $e');
    } finally {
      _islemBitti();
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final sepet = ref.watch(sepetProvider);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: Text(_kameraAcik ? 'Barkod Okut' : 'Hızlı Satış'),
        aksiyonlar: [
          if (!sepet.bos) ...[
            _AppBarButon(
              icon: Icons.shopping_basket_outlined,
              renk: Colors.teal,
              tooltip: 'Tedarikçi Alımı',
              onTap: _tedarikciyeAktar,
            ),
            _AppBarButon(
              icon: Icons.pause_circle_outlined,
              renk: Colors.orange,
              tooltip: 'Askıya Al',
              onTap: _askiyaAl,
            ),
          ],
          FutureBuilder<int>(
            future: _bekleyenSayiFuture,
            builder: (_, snap) {
              final sayi = snap.data ?? 0;
              return Badge(
                label:          sayi > 0 ? Text(sayi.toString()) : null,
                isLabelVisible: sayi > 0,
                child: IconButton(
                  icon: const Icon(Icons.pause_circle_outline),
                  tooltip: 'Askıdaki Satışlar',
                  onPressed: () async {
                    _islemBasladi();
                    final secilen = await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20))),
                      builder: (_) => const BekleyenFislerEkrani(),
                    );
                    if (!mounted) { _islemBitti(); return; }
                    if (secilen != null) {
                      if (sepet.kalemler.isNotEmpty) {
                        final onay = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('Dikkat'),
                            content: const Text(
                                'Mevcut sepette ürün var. Yüklemek için temizlenmeli. Devam edilsin mi?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('İptal')),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.orange),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Evet, Yükle'),
                              ),
                            ],
                          ),
                        );
                        if (onay != true) { _islemBitti(); return; }
                      }
                      final prefs2 = await SharedPreferences.getInstance();
                      final json2  = prefs2.getString('askidaki_satislar');
                      if (json2 != null) {
                        final list2 = List<Map<String, dynamic>>.from(
                            jsonDecode(json2));
                        list2.removeWhere((x) => x['id'] == secilen.id);
                        await prefs2.setString(
                            'askidaki_satislar', jsonEncode(list2));
                      }
                      ref.read(sepetProvider.notifier).temizle();
                      for (final k in (secilen.kalemler as List)) {
                        final urun = await _urunDepo.idileGetir(k['urunId'] as int);
                        if (urun != null) {
                          final fiyat = (k['birimFiyat'] ?? k['fiyat'] ?? urun.satisFiyati) as num;
                          ref.read(sepetProvider.notifier).ekle(
                              urun,
                              miktar: (k['miktar'] as num).toDouble(),
                              fiyatOverride: fiyat.toDouble());
                        }
                      }
                      if (!mounted) return;
                      setState(() {
                        _bekleyenSayiFuture = BekleyenFislerEkrani.bekleyenSayi();
                      });
                    }
                    _islemBitti();
                  },
                ),
              );
            },
          ),
          if (sepet.musteri != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Chip(
                avatar: const Icon(Icons.person, size: 14, color: AppRenkler.primary),
                label: Text(
                  sepet.musteri!.unvan,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: TsRenk.metinBirincil(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                deleteIcon: Icon(Icons.close, size: 14, color: TsRenk.metinIkincil(context)),
                backgroundColor: TsRenk.kart(context),
                side: BorderSide(color: AppRenkler.primary.withAlpha(76)),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onDeleted: () => ref.read(sepetProvider.notifier).musteriSec(null),
              ),
            ),
          // ── YAZICI BUTONU (manuel yazdırma) ──
          _AppBarButon(
            icon: Icons.print_rounded,
            renk: _sonSatis != null ? Colors.white : Colors.grey,
            tooltip: _sonSatis != null ? 'Fişi Yazdır' : 'Henüz satış yok',
            onTap: _sonSatis != null
                ? () async {
                    try {
                      await YazdirmaServisi().fisYazdir(_sonSatis!);
                      if (!mounted) return;
                      BildirimServisi.basari(context, 'Fiş yazdırılıyor…');
                    } catch (e) {
                      if (!mounted) return;
                      BildirimServisi.hata(context, 'Yazdırılamadı: $e');
                    }
                  }
                : null,
          ),
          _AppBarButon(
            icon: _kameraAcik ? Icons.search_rounded : Icons.qr_code_scanner_rounded,
            renk: _kameraAcik ? Colors.green : Colors.white,
            tooltip: _kameraAcik ? 'Arama Modu' : 'Barkod Tara',
            onTap: _kameraToggle,
          ),
          _AppBarButon(
            icon: Icons.person_add_outlined,
            renk: Colors.white,
            tooltip: 'Müşteri Seç',
            onTap: _musteriSec,
          ),
        ],
      ),
      body: Column(children: [
        if (_guncellenenSatis != null)
          Material(
            color: Colors.orange.shade800,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  const Icon(Icons.edit_note_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('FİŞ GÜNCELLEME MODU',
                            style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w800, fontSize: 12,
                                letterSpacing: 0.5)),
                        Text(
                          '${_guncellenenSatis!.fisNo} • '
                          'eski tutar ${ParaUtils.formatla(_guncellenenSatis!.genelToplam)} '
                          '• sepetin son hali fişin yeni içeriği olacak',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(sepetProvider.notifier).temizle();
                      setState(() => _guncellenenSatis = null);
                      BildirimServisi.uyari(context, 'Fiş güncelleme iptal edildi');
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('İPTAL',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ]),
              ),
            ),
          ),
        Expanded(
          child: sepet.satisIsleniyor
          ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF4361EE)))
          : LayoutBuilder(builder: (ctx, constraints) {
              if (constraints.maxWidth > 700) {
                return Row(children: [
                  Expanded(flex: 5, child: Column(children: [
                    _aramaPaneli(),
                    if (_kameraAcik) _kameraPaneli(),
                    if (_aramaSonuclari.isNotEmpty && !_kameraAcik)
                      _aramaSonucListesi(),
                    const Spacer(),
                  ])),
                  const VerticalDivider(width: 1, thickness: 1),
                  SizedBox(width: 360, child: Column(children: [
                    Expanded(child: _sepetListesi()),
                    _altPanel(sepet),
                  ])),
                ]);
              }
              return Column(children: [
                if (_kameraAcik) _kameraPaneli() else _aramaPaneli(),
                if (_aramaSonuclari.isNotEmpty && !_kameraAcik)
                  _aramaSonucListesi(),
                Expanded(child: _sepetListesi()),
                _altPanel(sepet),
              ]);
            }),
        ),
      ]),
    );
  }

  Widget _aramaPaneli() => HizliSatisAramaPaneli(
    araCtrl:  _araCtrl,
    araFocus: _araFocus,
    onDegisti: (v) {
      _aramaDegisti(v);
      setState(() {});
    },
    onPluAc: _pluAc,
    onHizliTusAc: _hizliTusAc,
  );

  Widget _kameraPaneli() => SatisKameraPaneli(
    controller: _scanCtrl,
    flash: _flash,
    onBarkod: _barkodOkutIsle,
    onKapat: () => setState(() => _kameraAcik = false),
    onFlashToggle: () {
      setState(() => _flash = !_flash);
      _scanCtrl.toggleTorch();
    },
  );

  Widget _koseAksesuari(Alignment konum) {
    final isTop  = konum == Alignment.topLeft  || konum == Alignment.topRight;
    final isLeft = konum == Alignment.topLeft  || konum == Alignment.bottomLeft;
    const c = BorderSide(color: Colors.greenAccent, width: 3);
    const n = BorderSide.none;
    return Positioned(
      top: isTop ? -1 : null, bottom: !isTop ? -1 : null,
      left: isLeft ? -1 : null, right: !isLeft ? -1 : null,
      child: Container(width: 20, height: 20,
        decoration: BoxDecoration(border: Border(
          top: isTop ? c : n, bottom: !isTop ? c : n,
          left: isLeft ? c : n, right: !isLeft ? c : n,
        ))),
    );
  }

  Widget _aramaSonucListesi() => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 220),
    child: Container(
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(TsRadius.lg),
        border: Border.all(color: TsRenk.ayirac(context)),
        boxShadow: TsGolge.yumusak,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _aramaSonuclari.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final u = _aramaSonuclari[i];
          final indirimVar = u.indirimliFiyatKayitli > 0 &&
              u.indirimliFiyatKayitli < u.satisFiyati;
          return ListTile(
            dense: true,
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4361EE), Color(0xFF3A0CA3)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(
                u.urunAdi.isNotEmpty ? u.urunAdi[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: Colors.white),
              )),
            ),
            title: Text(u.urunAdi,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(u.barkod ?? '',
                style: const TextStyle(fontSize: 11)),
            trailing: Text(
              indirimVar
                  ? ParaUtils.formatla(u.indirimliFiyatKayitli)
                  : ParaUtils.formatla(u.satisFiyati),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: indirimVar ? Colors.orange : null,
              ),
            ),
            onTap: () { _urunSepeteEkleAkilli(u); },
          );
        },
      ),
    ),
  );

  Widget _sepetListesi() => HizliSatisSepetListesi(
    scrollController: _sepetScroll,
    kgMiMi: _kgBirimMi,
    onKalemTap: _sepetKalemMiktarDuzenle,
    onIndirimDuzenle: _indirimDuzenle,
    onKgEkle: _kgIleEkle,
  );

  Widget _altPanel(SepetDurum sepet) => SatisAltPanel(
    sepet: sepet,
    onOdeme: _odemeYontemiSec,
  );
}

// ── Ödeme Seçim Sheet ────────────────────────────────────────────────────────
class _OdemeSecimSheet extends StatelessWidget {
  final double toplam;
  final bool musteriSecili;
  const _OdemeSecimSheet({required this.toplam, this.musteriSecili = false});

  @override
  Widget build(BuildContext context) {
    const yontemler = [
      (ikon: Icons.payments,        label: 'Nakit',        renk: Color(0xFF4CAF50), deger: 'Nakit'),
      (ikon: Icons.credit_card,     label: 'Kredi Kartı',  renk: Color(0xFF2196F3), deger: 'Kredi Kartı'),
      (ikon: Icons.account_balance, label: 'Banka/Havale', renk: Color(0xFF9C27B0), deger: 'Havale'),
      (ikon: Icons.people_outline,  label: 'Cari Hesap',   renk: Color(0xFFFF9800), deger: 'Cari'),
      (ikon: Icons.qr_code,         label: 'QR Kod',       renk: Color(0xFF00BCD4), deger: 'QR'),
      (ikon: Icons.tune,            label: 'Karma Ödeme',  renk: Color(0xFF607D8B), deger: 'Karma'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('Toplam: ${ParaUtils.formatla(toplam)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Ödeme yöntemi seçin',
            style: TextStyle(color: context.textSecondary, fontSize: 13)),
        const SizedBox(height: 20),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: List.generate(yontemler.length, (i) {
            final y = yontemler[i];
            final kilitli = y.deger == 'Cari' && !musteriSecili;
            return GestureDetector(
              onTap: kilitli
                  ? null
                  : () => Navigator.pop(context, y.deger),
              child: Opacity(
                opacity: kilitli ? 0.35 : 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Color.fromARGB(36, y.renk.red, y.renk.green, y.renk.blue),
                    border: Border.all(color: Color.fromARGB(120, y.renk.red, y.renk.green, y.renk.blue), width: 1.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(y.ikon, color: y.renk, size: 28),
                      const SizedBox(height: 6),
                      Text(y.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: y.renk)),
                      if (kilitli)
                        Text('Müşteri seç',
                            style: TextStyle(
                                fontSize: 9, color: context.textSecondary)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }
}

class _MusteriSecimPaneli extends ConsumerStatefulWidget {
  final List<CariModel> cariler;
  const _MusteriSecimPaneli({required this.cariler});

  @override
  ConsumerState<_MusteriSecimPaneli> createState() => _MusteriSecimPaneliState();
}

class _MusteriSecimPaneliState extends ConsumerState<_MusteriSecimPaneli> {
  final _araCtrl = TextEditingController();
  List<CariModel> _filtreli = [];

  @override
  void initState() {
    super.initState();
    _filtreli = widget.cariler;
    _araCtrl.addListener(_filtrele);
  }

  @override
  void dispose() { _araCtrl.dispose(); super.dispose(); }

  void _filtrele() {
    final q = _araCtrl.text.toLowerCase();
    setState(() {
      _filtreli = q.isEmpty
          ? widget.cariler
          : widget.cariler.where((c) =>
              c.unvan.toLowerCase().contains(q) ||
              (c.telefon?.contains(q) ?? false)).toList();
    });
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.7,
    minChildSize: 0.4,
    maxChildSize: 0.95,
    expand: false,
    builder: (_, ctrl) => Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(color: context.borderColor,
                borderRadius: BorderRadius.circular(2))),
        const Text('Müşteri / Tedarikçi Seç',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _araCtrl,
            decoration: const InputDecoration(
              hintText: 'Müşteri ara…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(child: ListView.builder(
          controller: ctrl,
          itemCount: _filtreli.length,
          itemBuilder: (_, i) {
            final c = _filtreli[i];
            return ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF43A047)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(
                  c.unvan.isNotEmpty ? c.unvan[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: Colors.white),
                )),
              ),
              title: Row(children: [
                Flexible(child: Text(c.unvan, overflow: TextOverflow.ellipsis)),
                if (c.cariTipi.contains('edarik')) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x1A009688),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Tedarikçi',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: Color(0xFF00796B))),
                  ),
                ],
              ]),
              subtitle: Text(c.telefon ?? ''),
              onTap: () => Navigator.pop(context, c),
            );
          },
        )),
      ]),
    ),
  );
}

// ── Modern AppBar İkon Butonu (nullable onTap desteği) ──────────────────────
class _AppBarButon extends StatelessWidget {
  final IconData icon;
  final Color renk;
  final String tooltip;
  final VoidCallback? onTap;

  const _AppBarButon({
    required this.icon,
    required this.renk,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1.0,
      child: GestureDetector(
        onTap: onTap, // null ise tıklama olmaz
        child: Container(
          width: 38, height: 38,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: renk == Colors.white
                ? Colors.white.withAlpha(25)
                : Colors.white.withAlpha(40),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withAlpha(50)),
          ),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.grey : Colors.white),
        ),
      ),
    ),
  );
}