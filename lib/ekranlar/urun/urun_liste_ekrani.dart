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
  static const _ekAlanEtiketleri = {
    'barkod': 'Barkod',
    'marka': 'Marka',
    'kdv': 'KDV Oranı',
  };
  Set<String> _ekAlanlar = {};

  Future<void> _gorunumTercihiYukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kayitli = prefs.getStringList('urun_liste_ek_alanlar');
      if (kayitli != null && mounted) {
        setState(() => _ekAlanlar = kayitli.toSet());
      }
    } catch (_) {
      // Tercih okunamazsa varsayılan (boş) görünümle devam edilir.
    }
  }

  Future<void> _gorunumTercihiKaydet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('urun_liste_ek_alanlar', _ekAlanlar.toList());
    } catch (_) {
      // Kaydedilemezse sessizce geçilir — bir sonraki açılışta varsayılana döner.
    }
  }

  Future<void> _gorunumSecimiAc() async {
    var secim = Set<String>.from(_ekAlanlar);
    final sonuc = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Kartta Gösterilecek Alanlar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in _ekAlanEtiketleri.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: secim.contains(e.key),
                  onChanged: (v) => ss(() {
                    if (v == true) {
                      secim.add(e.key);
                    } else {
                      secim.remove(e.key);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, secim),
                child: const Text('Uygula')),
          ],
        );
      }),
    );
    if (sonuc != null && mounted) {
      setState(() => _ekAlanlar = sonuc);
      _gorunumTercihiKaydet();
    }
  }

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

  void _hizliBilgiGoster(UrunModel u) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(u.urunAdi, style: const TextStyle(fontSize: 15)),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (u.barkod != null) _bilgiSatir('Barkod', u.barkod!),
                    _bilgiSatir(
                        'Satış Fiyatı', ParaUtils.formatla(u.satisFiyati)),
                    _bilgiSatir('Alış Fiyatı', ParaUtils.formatla(u.alisFiyat)),
                    _bilgiSatir('KDV', '%${u.kdvOran}'),
                    _bilgiSatir('Stok', '${u.stok} ${u.birimAdi}'),
                    if (u.anaGrup != null) _bilgiSatir('Grup', u.anaGrup!),
                    if (u.marka != null) _bilgiSatir('Marka', u.marka!),
                    _bilgiSatir(
                        'Kar Oranı', '%${u.karOrani.toStringAsFixed(1)}'),
                  ]),
              actions: [
                const BulutDurumIkonu(),
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/urun/detay/${u.id}');
                    },
                    child: const Text('Detay')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Kapat')),
              ],
            ));
  }

  Widget _bilgiSatir(String etiket, String deger) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
            width: 90,
            child: Text(etiket,
                style: TextStyle(
                    fontSize: 12, color: TsRenk.metinIkincil(context)))),
        Expanded(
            child: Text(deger,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600))),
      ]));

  Future<void> _seciliUrunleriSil(Set<int> ids) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Toplu Silme'),
        content: Text('${ids.length} ürün silinecek. Onaylıyor musunuz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    for (final id in ids) {
      await ref.read(urunlerProvider.notifier).sil(id);
    }
    ref.read(urunlerProvider.notifier).secimTemizle();
    if (mounted) basariMesaji(context, '${ids.length} ürün silindi');
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

  // ── Barkod ile arama ──────────────────────────────────────────────────────
  Future<void> _barkodIleAra() async {
    try {
      final barkod = await _barkodSrv.barkodTara(context);
      if (barkod == null || !mounted) return;

      // Direkt DB'den barkodla ara (barkod ve barkodlar alanları)
      final urun = await UrunDeposu().barkodlaGetir(barkod);
      if (!mounted) return;

      if (urun != null) {
        // Bulundu — listede göster
        _araCtrl.text = barkod;
        ref.read(urunFiltresiProvider.notifier).aramaGuncelle(barkod);
      } else {
        // Bulunamadı — direkt ürün ekle ekranına git
        final ok = await context.push<bool>(
          '/urun/ekle',
          extra: {'barkod': barkod, 'kaynak': 'urun_liste'},
        );
        if (ok == true && mounted) {
          _araCtrl.clear();
          ref.read(urunlerProvider.notifier).yukle(sifirla: true);
        }
      }
    } catch (e) {
      if (kDebugMode && mounted) debugPrint('Hata: $e');
    }
  }

  // ── Resim büyüt ───────────────────────────────────────────────────────────
  void _resimBuyut(String? resimYolu) {
    if (resimYolu == null || resimYolu.isEmpty) return;
    final file = File(resimYolu);
    if (!file.existsSync()) return;
    showDialog(
      context: context,
      builder: (bCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(alignment: Alignment.center, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(bCtx),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Barkod göster dialog ─────────────────────────────────────────────────
  void _barkodGoster(String barkod, String urunAdi) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(urunAdi,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            BarcodeWidget(
              barcode: Barcode.code128(),
              data: barkod,
              width: 220,
              height: 80,
              drawText: true,
            ),
            const SizedBox(height: 16),
            Text(barkod,
                style: const TextStyle(fontSize: 13, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: barkod));
                Navigator.pop(ctx);
              },
              child: const Text('Kopyala & Kapat'),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Seçili sil ────────────────────────────────────────────────────────────
  Future<void> _seciliSil() async {
    final durum = ref.read(urunlerProvider);
    // UrunListeNotifier'da secim yoktu — basit bir dialog
    hataMesaji(context, 'Toplu silme için toplu işlem ekranını kullanın');
  }

  // ── Excel aktar ───────────────────────────────────────────────────────────
  Future<void> _excelAktar({bool sutunSec = false}) async {
    final durum = ref.read(urunlerProvider);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Ürünler'];
      sheet.appendRow([
        TextCellValue('Ürün Adı'),
        TextCellValue('Barkod'),
        TextCellValue('Stok'),
        TextCellValue('Alış'),
        TextCellValue('Satış'),
        TextCellValue('Birim'),
        TextCellValue('Grup'),
      ]);
      for (final u in durum.urunler) {
        sheet.appendRow([
          TextCellValue(excelIcinGuvenliMetin(u.urunAdi)),
          TextCellValue(excelIcinGuvenliMetin(u.barkod)),
          DoubleCellValue(u.stok),
          DoubleCellValue(u.alisFiyat),
          DoubleCellValue(u.satisFiyati),
          TextCellValue(u.birimAdi),
          TextCellValue(excelIcinGuvenliMetin(u.anaGrup)),
        ]);
      }
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/urunler_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await File(path).writeAsBytes(excel.encode()!);
      await Share.shareXFiles([XFile(path)], text: 'Ürün Listesi');
    } catch (e) {
      if (mounted) hataMesaji(context, 'Excel hatası: $e');
    }
  }

  // ── Filtre sheet ──────────────────────────────────────────────────────────
  Future<void> _filtreSheet() async {
    final durum = ref.read(urunlerProvider);
    final filtre = ref.read(urunFiltresiProvider);
    final gruplar = durum.urunler
        .map((u) => u.anaGrup ?? '')
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    const siralamaSecenekleri = [
      ('isim', 'İsim (A-Z)'),
      ('stok_azalan', 'Stok (Çoktan Aza)'),
      ('stok_artan', 'Stok (Azdan Çoka)'),
      ('guncelleme_yeni', 'En Son Güncellenen'),
      ('fiyat_yuksek', 'Satış Fiyatı (Yüksekten Düşüğe)'),
      ('fiyat_dusuk', 'Satış Fiyatı (Düşükten Yükseğe)'),
      ('grup', 'Gruba Göre'),
      ('alan1', 'Alan 1\'e Göre'),
    ];

    // 🔥 ÖNCEDEN BURADAKİ HATA: kritikOnly/tmpSiralama/tmpGrup
    // StatefulBuilder'ın builder FONKSİYONUNUN İÇİNDE tanımlıydı — bu,
    // klasik bir Flutter hatası: ss() (setState) her çağrıldığında
    // builder fonksiyonu BAŞTAN çalışıyor, bu üç değişken de HER
    // SEFERİNDE orijinal (filtre.xxx) değerine SIFIRLANIYORDU. Yani
    // bir sıralama seçeneğine dokunduğunuzda görsel olarak an be an
    // değişiyor gibi görünse de, "Uygula"ya bastığınızda değişken
    // ZATEN sıfırlanmış oluyordu — kullanıcının bildirdiği "filtreleme
    // yapmıyor" hatası tam olarak buydu. Artık bu üç değişken
    // StatefulBuilder'ın DIŞINDA tanımlanıyor, rebuild'lerden
    // ETKİLENMİYOR.
    bool kritikOnly = filtre.sadecKritikler ?? false;
    String tmpSiralama = filtre.siralama;
    String? tmpGrup = filtre.grupFiltre;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // 🔥 ÖNCEDEN arkaplan rengi belirtilmiyordu (varsayılan beyaz
      // geliyordu) ve metinler de renk belirtmeden (varsayılan tema
      // rengiyle) yazılmıştı — karanlık modda "beyaz üzerine beyaz"
      // gibi okunmaz bir görüntü oluşabiliyordu. Artık uygulamanın
      // kendi tema-farkında renkleri (context.cardBg, textPrimary vb.)
      // kullanılıyor, hem açık hem karanlık modda net okunuyor.
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        return Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Filtrele ve Sırala',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary)),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text('Sadece Kritik Stok',
                    style: TextStyle(color: context.textPrimary)),
                value: kritikOnly,
                onChanged: (v) => ss(() => kritikOnly = v),
              ),
              Divider(height: 24, color: context.dividerColor),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Sıralama',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.textSecondary))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (deger, etiket) in siralamaSecenekleri)
                  ChoiceChip(
                    label: Text(etiket,
                        style: TextStyle(
                            fontSize: 12,
                            color: tmpSiralama == deger
                                ? Colors.white
                                : context.textPrimary)),
                    selected: tmpSiralama == deger,
                    backgroundColor: context.inputFill,
                    onSelected: (_) => ss(() => tmpSiralama = deger),
                  ),
              ]),
              if (gruplar.isNotEmpty) ...[
                Divider(height: 24, color: context.dividerColor),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Grup',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.textSecondary))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: tmpGrup,
                  dropdownColor: context.cardBg,
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: context.inputFill,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10)),
                  hint: Text('Tüm Gruplar',
                      style: TextStyle(color: context.textHint)),
                  items: [
                    DropdownMenuItem(
                        value: null,
                        child: Text('Tüm Gruplar',
                            style: TextStyle(color: context.textPrimary))),
                    for (final g in gruplar)
                      DropdownMenuItem(
                          value: g,
                          child: Text(g,
                              style: TextStyle(color: context.textPrimary))),
                  ],
                  onChanged: (v) => ss(() => tmpGrup = v),
                ),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                  onPressed: () {
                    ref.read(urunFiltresiProvider.notifier).sifirla();
                    ref.read(urunlerProvider.notifier).yukle(sifirla: true);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Temizle'),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton(
                  onPressed: () {
                    final notifier = ref.read(urunFiltresiProvider.notifier);
                    if (kritikOnly != (filtre.sadecKritikler ?? false)) {
                      notifier.kritikToggle();
                    }
                    notifier.siralamaGuncelle(tmpSiralama);
                    notifier.grupGuncelle(tmpGrup);
                    ref.read(urunlerProvider.notifier).yukle(sifirla: true);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Uygula'),
                )),
              ]),
            ]),
          ),
        );
      }),
    );
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
                  backgroundColor: Colors.blue.shade50,
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

  Widget _FilterChip(String label, VoidCallback onRemove) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.blue)),
          const SizedBox(width: 4),
          GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 14, color: Colors.blue)),
        ]),
      );

  Widget _listeView(List<UrunModel> urunler, UrunListeDurum durum) =>
      ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
        itemCount: urunler.length + (durum.yukleniyor ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == urunler.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: AppYukleniyor()),
            );
          }
          final u = urunler[i];
          final stokRenk = u.stok <= 0
              ? Colors.red
              : u.kritikStok
                  ? Colors.orange
                  : Colors.green;

          final kart = RepaintBoundary(
            child: TsKart(
              padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
              onLongPress: () =>
                  ref.read(urunlerProvider.notifier).secimToggle(u.id!),
              onTap: () {
                if (durum.secimModu) {
                  ref.read(urunlerProvider.notifier).secimToggle(u.id!);
                } else {
                  context.push('/urun/detay/${u.id}');
                }
              },
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // Avatar / resim
                GestureDetector(
                  onTap: () => _resimBuyut(u.resimYolu),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Color.fromARGB(
                            46, stokRenk.red, stokRenk.green, stokRenk.blue),
                        Color.fromARGB(
                            15, stokRenk.red, stokRenk.green, stokRenk.blue)
                      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Color.fromARGB(
                              64, stokRenk.red, stokRenk.green, stokRenk.blue)),
                      image: u.resimYolu != null &&
                              u.resimYolu!.isNotEmpty &&
                              File(u.resimYolu!).existsSync()
                          ? DecorationImage(
                              // 🔴 DÜZELTME (performans denetimi):
                              // FileImage tam çözünürlükte decode ediyordu
                              // (kamera fotoğrafı birkaç MB olabilir) —
                              // 64x64'lük bir kutuda gösterilirken bile.
                              // ResizeImage, decode boyutunu gerçek
                              // gösterim boyutuna indirip bellek/jank
                              // riskini ortadan kaldırıyor.
                              image: ResizeImage(
                                FileImage(File(u.resimYolu!)),
                                width: (64 * MediaQuery.of(context).devicePixelRatio).round(),
                                height: (64 * MediaQuery.of(context).devicePixelRatio).round(),
                              ),
                              fit: BoxFit.cover)
                          : null,
                    ),
                    child: (u.resimYolu == null ||
                            u.resimYolu!.isEmpty ||
                            !File(u.resimYolu!).existsSync())
                        ? Center(
                            child: Text(u.urunAdi[0].toUpperCase(),
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: stokRenk)))
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // ORTA — ürün adı + stok + alış + grup
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // Ürün adı — uzun isimler için tüm genişlik
                      Text(u.urunAdi,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      // Stok rozeti + Alış fiyatı — isim altında, yan yana
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: Color.fromARGB(31, stokRenk.red,
                                  stokRenk.green, stokRenk.blue),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(
                              '${u.stok.toStringAsFixed(u.stok == u.stok.roundToDouble() ? 0 : 1)} ${u.birimAdi}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: stokRenk)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                            child: Text(
                                'Alış: ${ParaUtils.formatla(u.alisFiyatKdvDahil)}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: TsRenk.metinIkincil(context)))),
                      ]),
                      if (u.anaGrup != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(u.anaGrup!,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                      if (_ekAlanlar.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 2, children: [
                          if (_ekAlanlar.contains('barkod') &&
                              u.barkod != null &&
                              u.barkod!.isNotEmpty)
                            Text('Barkod: ${u.barkod}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('marka') &&
                              u.marka != null &&
                              u.marka!.isNotEmpty)
                            Text('Marka: ${u.marka}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                          if (_ekAlanlar.contains('kdv'))
                            Text('KDV: %${u.kdvOran}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: TsRenk.metinIkincil(context))),
                        ]),
                      ],
                    ])),
                const SizedBox(width: 10),
                // SAĞ — satış fiyatı + kar + ikonlar
                Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(ParaUtils.formatla(u.satisFiyati),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: TsRenk.primary)),
                      if (u.karOrani > 0) ...[
                        const SizedBox(height: 3),
                        Text('%${u.karOrani.toStringAsFixed(1)} ▲',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 8),
                      // 2 ikon — aralık genişletildi
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(
                          onTap: () => _hizliBilgiGoster(u),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.info_outline,
                                size: 19, color: Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            if (u.barkod != null && u.barkod!.isNotEmpty) {
                              _barkodGoster(u.barkod!, u.urunAdi);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                                color: context.borderColor,
                                borderRadius: BorderRadius.circular(8)),
                            child: Icon(Icons.linear_scale,
                                size: 19,
                                color: u.barkod != null && u.barkod!.isNotEmpty
                                    ? context.textSecondary
                                    : context.borderColor),
                          ),
                        ),
                      ]),
                    ]),
              ]),
            ),
          );
          // Seçim tik — seçim modunda sol üstte her zaman görünen daire
          return Stack(children: [
            kart,
            if (durum.secimModu)
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: () =>
                      ref.read(urunlerProvider.notifier).secimToggle(u.id!),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: durum.seciliIds.contains(u.id!)
                          ? AppRenkler.primary
                          : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: durum.seciliIds.contains(u.id!)
                              ? AppRenkler.primary
                              : context.textSecondary,
                          width: 1.5),
                      boxShadow: const [
                        BoxShadow(color: Color(0x1F000000), blurRadius: 3)
                      ],
                    ),
                    child: durum.seciliIds.contains(u.id!)
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),
              ),
          ]);
        },
      );

  Widget _izgaraView(List<UrunModel> urunler, UrunListeDurum durum) =>
      GridView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: TsResponsive.izgaraKolonSayisi(context,
                telefon: 2, tablet: 4, genis: 5),
            childAspectRatio: 0.85,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8),
        itemCount: urunler.length + (durum.yukleniyor ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == urunler.length) {
            return const Center(child: AppYukleniyor());
          }
          final u = urunler[i];
          final stokRenk = u.stok <= 0
              ? Colors.red
              : u.kritikStok
                  ? Colors.orange
                  : Colors.green;
          return RepaintBoundary(
            child: TsKart(
              secili: durum.seciliIds.contains(u.id!),
              onLongPress: () =>
                  ref.read(urunlerProvider.notifier).secimToggle(u.id!),
              onTap: () {
                if (durum.secimModu) {
                  ref.read(urunlerProvider.notifier).secimToggle(u.id!);
                } else {
                  context.push('/urun/detay/${u.id}');
                }
              },
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => _resimBuyut(u.resimYolu),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                  color: Color.fromARGB(26, stokRenk.red,
                                      stokRenk.green, stokRenk.blue),
                                  borderRadius: BorderRadius.circular(12),
                                  image: u.resimYolu != null &&
                                          u.resimYolu!.isNotEmpty &&
                                          File(u.resimYolu!).existsSync()
                                      ? DecorationImage(
                                          // bkz. yukarıdaki liste-modu notu — aynı düzeltme
                                          image: ResizeImage(
                                            FileImage(File(u.resimYolu!)),
                                            width: (48 * MediaQuery.of(context).devicePixelRatio).round(),
                                            height: (48 * MediaQuery.of(context).devicePixelRatio).round(),
                                          ),
                                          fit: BoxFit.cover)
                                      : null),
                              child: (u.resimYolu == null ||
                                      u.resimYolu!.isEmpty ||
                                      !File(u.resimYolu!).existsSync())
                                  ? Center(
                                      child: Text(u.urunAdi[0].toUpperCase(),
                                          style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: stokRenk)))
                                  : null,
                            ),
                          ),
                          if (u.barkod != null && u.barkod!.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.qr_code_2,
                                  size: 18, color: Colors.blue),
                              onPressed: () =>
                                  _barkodGoster(u.barkod!, u.urunAdi),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ]),
                    const SizedBox(height: 8),
                    Text(u.urunAdi,
                        style: TsMetin.govdeVurgu,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const Spacer(),
                    Text(ParaUtils.formatla(u.satisFiyati),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 20)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Color.fromARGB(
                              31, stokRenk.red, stokRenk.green, stokRenk.blue),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('${u.stok.toStringAsFixed(0)} ${u.birimAdi}',
                          style: TsMetin.kucukVurgu.copyWith(color: stokRenk)),
                    ),
                  ]),
            ),
          );
        },
      );
}

class _IkonButon extends StatelessWidget {
  final IconData icon;
  final Color renk, bg;
  final VoidCallback onTap;
  const _IkonButon(
      {required this.icon,
      required this.renk,
      required this.bg,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: renk),
        ),
      );
}
