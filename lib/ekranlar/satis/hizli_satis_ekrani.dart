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
import '../../cekirdek/utils/hata_utils.dart';
import 'bekleyen_fisler_ekrani.dart';
import 'widgets/satis_alt_panel.dart';
import 'widgets/kamera_paneli.dart';
import 'coklu_odeme_ekrani.dart';
import 'plu_ekrani.dart';
import '../../servisler/aktif_sube_servisi.dart';

part 'hizli_satis_ekrani_barkod.dart';
part 'hizli_satis_ekrani_odeme.dart';
part 'hizli_satis_ekrani_widgets.dart';

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
                child: TsDokunmaIkon(
                  ikon: Icons.pause_circle_outline,
                  tooltip: 'Askıdaki Satışlar',
                  onTap: () async {
                    _islemBasladi();
                    // 🔴 Derin analizde bulundu: bu blokta birden fazla
                    // erken 'return' vardı ve hiçbiri try/finally ile
                    // korunmuyordu — akış sırasında (ör. idileGetir,
                    // SharedPreferences, jsonDecode) bir istisna oluşursa
                    // _islemBitti() hiç çağrılmadan fonksiyon sonlanır,
                    // _islemAktif kalıcı olarak true kalır ve TÜM satış
                    // ekranı (barkod okuma dahil) uygulama yeniden
                    // başlatılana kadar kilitlenirdi.
                    try {
                      final secilen = await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20))),
                        builder: (_) => const BekleyenFislerEkrani(),
                      );
                      if (!mounted || secilen == null) return;
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
                        if (onay != true) return;
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
                    } finally {
                      _islemBitti();
                    }
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
                        style: TsMetin.kucukVurgu),
                  ),
                ]),
              ),
            ),
          ),
        Expanded(
          child: sepet.satisIsleniyor
          ? const TsYukleniyor()
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
}
