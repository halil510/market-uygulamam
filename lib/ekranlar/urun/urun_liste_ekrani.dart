// lib/ekranlar/urun/urun_liste_ekrani.dart  (Riverpod v2.2)
//
// DEĞIŞIKLIKLER:
//   - Consumer<UrunListeNotifier> → ref.watch(urunlerProvider)
//   - context.read<UrunListeNotifier>() → ref.read(urunlerProvider.notifier)
//   - UrunFiltreDurum provider ile filtre yönetimi

import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../widgetlar/ortak/bulut_durum_widget.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:go_router/go_router.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgetlar/urun/excel_ice_aktar_yardimcisi.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/barkod_servisi.dart';
import '../../saglayicilar/riverpod/urun_provider.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../cekirdek/utils/excel_guvenlik_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

// God-class sertleştirmesi (2026-09-22, kullanıcı onayıyla): bu dosya
// 1225 satırdı. İçerik davranış DEĞİŞTİRİLMEDEN 2 parçaya ayrıldı:
//   - urun_liste_dialoglar_ext.dart → görünüm tercihi, hızlı bilgi,
//     toplu silme, barkod arama/gösterme, Excel aktarım, filtre sheet
//   - urun_liste_kartlar_ext.dart   → liste/ızgara kartı görünümleri
part 'urun_liste_dialoglar_ext.dart';
part 'urun_liste_kartlar_ext.dart';

class UrunListeEkrani extends ConsumerStatefulWidget {
  /// AI Chat'ten "ürün listesi X'e git" gibi bir komutla gelindiğinde,
  /// ekran açılır açılmaz bu terimle otomatik arama yapılması için.
  final String? baslangicArama;
  const UrunListeEkrani({super.key, this.baslangicArama});

  @override
  ConsumerState<UrunListeEkrani> createState() => _UrunListeEkraniState();
}

class _UrunListeEkraniState extends ConsumerState<UrunListeEkrani> {
  final _araCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _barkodSrv = BarkodServisi();

  bool _izgara = false;
  Timer? _araDebounce;

  // ── Görünüm/kolon yönetimi ──────────────────────────────────────────────
  // Roadmap madde 17 ("Enterprise DataTable — sıralanabilir kolon, kolon
  // yönetimi"): bu ekran spreadsheet tarzı bir tablo değil, kart tabanlı bir
  // liste — telefon/tablet POS hedefli bu uygulamada gerçek bir DataTable
  // widget'ı (yatay kaydırma, küçük dokunma alanları) UX'i kötüleştirirdi,
  // bu yüzden BİLİNÇLİ OLARAK yapılmadı (daha önce de 2 kez bu nedenle
  // ertelenmişti). Bunun yerine aynı ihtiyacı bu ortama uygun şekilde
  // karşılıyor: "sıralama" zaten filtre sayfasında var (_filtreSheet),
  // "kolon yönetimi" ise kart üzerinde HANGİ EK ALANLARIN görüneceğini
  // seçebilme olarak karşılanıyor. Varsayılan: hiçbiri (mevcut görünüm
  // BİREBİR korunuyor, sadece isteyen kullanıcı ek bilgi ekleyebiliyor).
  // Kullanıcı isteği (2026-09-21): "kartda gösterilecek alanları
  // çoğalt" — mevcut 3 alana (barkod/marka/kdv) 6 yeni seçenek eklendi.
  static const _ekAlanEtiketleri = {
    'barkod': 'Barkod',
    'marka': 'Marka',
    'kdv': 'KDV Oranı',
    'kod': 'Ürün Kodu',
    'minStok': 'Min. Stok',
    'karTutari': 'Kâr Tutarı',
    'stokDegeri': 'Stok Değeri',
    'rafNo': 'Raf No',
    'uretici': 'Üretici',
  };
  Set<String> _ekAlanlar = {};

  @override
  void initState() {
    super.initState();
    _araCtrl.addListener(_aramaChanged);
    _scrollCtrl.addListener(_scrollChanged);
    _gorunumTercihiYukle();
    if (widget.baslangicArama != null &&
        widget.baslangicArama!.trim().isNotEmpty) {
      // addListener sonrası .text ataması _aramaChanged'i otomatik tetikler.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _araCtrl.text = widget.baslangicArama!.trim();
      });
    }
  }

  @override
  void dispose() {
    _araDebounce?.cancel();
    _araCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _aramaChanged() {
    _araDebounce?.cancel();
    _araDebounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(urunFiltresiProvider.notifier).aramaGuncelle(_araCtrl.text);
    });
  }

  void _scrollChanged() {
    final durum = ref.read(urunlerProvider);
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      if (durum.dahaSonraVar && !durum.yukleniyor) {
        ref.read(urunlerProvider.notifier).yukle(sifirla: false);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final durum = ref.watch(urunlerProvider);
    final filtre = ref.watch(urunFiltresiProvider);
    final filtreAktif = filtre.sadecKritikler == true ||
        filtre.grupFiltre != null ||
        filtre.siralama != 'isim';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        backgroundColor: context.scaffoldBg,
        appBar: durum.secimModu
            ? TsAppBar(
                lider: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      ref.read(urunlerProvider.notifier).secimTemizle(),
                ),
                baslik: '${durum.seciliIds.length} seçili',
                aksiyonlar: [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    tooltip: 'Tümünü Seç',
                    onPressed: () =>
                        ref.read(urunlerProvider.notifier).tumunuSec(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.build_outlined),
                    tooltip: 'Toplu İşlem',
                    onPressed: () {
                      final ids = durum.seciliIds.toList();
                      ref.read(urunlerProvider.notifier).secimTemizle();
                      context.push('/urun/toplu-islem', extra: ids);
                    },
                  ),
                  TsYetkili(
                      child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Seçilileri Sil',
                    onPressed: () => _seciliUrunleriSil(durum.seciliIds),
                  )),
                ],
              )
            : TsAppBar(
                baslik: 'Ürünler',
                aksiyonlar: [
                  IconButton(
                    icon: const Icon(Icons.currency_exchange, size: 22),
                    tooltip: 'Toplu Döviz Güncelleme',
                    onPressed: () => context.push('/urun/doviz-guncelle'),
                  ),
                  IconButton(
                    icon:
                        Icon(_izgara ? Icons.list : Icons.grid_view, size: 22),
                    onPressed: () => setState(() => _izgara = !_izgara),
                  ),
                  if (!_izgara)
                    IconButton(
                      icon: Badge(
                          isLabelVisible: _ekAlanlar.isNotEmpty,
                          child: const Icon(Icons.view_column_outlined, size: 22)),
                      tooltip: 'Kartta Gösterilecek Alanlar',
                      onPressed: _gorunumSecimiAc,
                    ),
                  IconButton(
                    icon: Badge(
                        isLabelVisible: filtreAktif,
                        child: const Icon(Icons.filter_list, size: 22)),
                    onPressed: _filtreSheet,
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 22),
                    onSelected: (v) {
                      if (v == 'excel') _excelAktar();
                      if (v == 'excel_ice')
                        ExcelIceAktarYardimcisi.iceAktar(context,
                            onTamamlandi: () => ref
                                .read(urunlerProvider.notifier)
                                .yukle(sifirla: true));
                      if (v == 'toplu_fiyat') context.push('/urun/toplu-fiyat');
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'excel_ice',
                          child: ListTile(
                              dense: true,
                              leading: Icon(Icons.upload_file,
                                  size: 18, color: Colors.green),
                              title: Text('Excel\'den İçe Aktar',
                                  style: TextStyle(fontSize: 13)))),
                      PopupMenuItem(
                          value: 'excel',
                          child: ListTile(
                              dense: true,
                              leading: Icon(Icons.download,
                                  size: 18, color: AppRenkler.primary),
                              title: Text('Excel Aktar',
                                  style: TextStyle(fontSize: 13)))),
                      PopupMenuItem(
                          value: 'toplu_fiyat',
                          child: ListTile(
                              dense: true,
                              leading: Icon(Icons.price_change,
                                  size: 18, color: AppRenkler.primary),
                              title: Text('Toplu Fiyat',
                                  style: TextStyle(fontSize: 13)))),
                    ],
                  ),
                ],
              ),
        body: Column(children: [
          // Arama
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _araCtrl,
                  decoration: InputDecoration(
                    hintText: 'Ad, barkod, kod, marka ara…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_araCtrl.text.isNotEmpty)
                        IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _araCtrl.clear();
                              ref
                                  .read(urunFiltresiProvider.notifier)
                                  .aramaGuncelle('');
                            }),
                      IconButton(
                          icon: Icon(Icons.qr_code_scanner_outlined,
                              size: 20, color: context.textSecondary),
                          tooltip: 'Barkod Tara',
                          onPressed: () async {
                            final b = await BarkodServisi().barkodTara(context);
                            if (b != null && mounted) {
                              _araCtrl.text = b;
                              ref
                                  .read(urunFiltresiProvider.notifier)
                                  .aramaGuncelle(b);
                            }
                          }),
                    ]),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, size: 28),
                onPressed: _barkodIleAra,
                tooltip: 'Barkod ile ara',
                style: IconButton.styleFrom(
                  backgroundColor: TsRenk.zemin(TsRenk.bilgi),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ]),
          ),

          // Filtre chips
          if (filtreAktif)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(children: [
                if (filtre.sadecKritikler == true)
                  _FilterChip(
                      'Kritik Stok',
                      () => ref
                          .read(urunFiltresiProvider.notifier)
                          .kritikToggle()),
              ]),
            ),

          // Liste / Izgara
          Expanded(
            child: durum.yukleniyor && durum.urunler.isEmpty
                ? const TsYukleniyor(iskelet: true)
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.read(urunlerProvider.notifier).yukle(sifirla: true),
                    child: durum.urunler.isEmpty
                        ? TsBosDurum(
                            ikon: Icons.inventory_2_outlined,
                            baslik: 'Ürün bulunamadı',
                            aksiyonMetni: 'Yeni Ürün Ekle',
                            aksiyon: () async {
                              final ok = await context.push<bool>('/urun/ekle');
                              if (ok == true) {
                                ref
                                    .read(urunlerProvider.notifier)
                                    .yukle(sifirla: true);
                              }
                            })
                        : _izgara
                            ? _izgaraView(durum.urunler, durum)
                            : _listeView(durum.urunler, durum),
                  ),
          ),
        ]),
        floatingActionButton: TsYetkili(
            child: FloatingActionButton(
          backgroundColor: AppRenkler.primary,
          foregroundColor: Colors.white,
          tooltip: 'Ürün Ekle',
          onPressed: () async {
            final result = await context.push<bool>('/urun/ekle',
                extra: {'barkod': _araCtrl.text, 'kaynak': 'urun_liste'});
            if (result == true) {
              ref.read(urunlerProvider.notifier).yukle(sifirla: true);
            }
          },
          child: const Icon(Icons.add),
        )),
      ),
    );
  }
}
