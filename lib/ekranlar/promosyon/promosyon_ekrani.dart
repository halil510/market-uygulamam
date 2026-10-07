// lib/ekranlar/promosyon/promosyon_ekrani.dart
import '../../cekirdek/utils/hata_utils.dart';
import 'package:flutter/foundation.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/promosyon_provider.dart';
import '../../modeller/promosyon_model.dart';
import '../../depolar/promosyon_deposu.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../cekirdek/utils/dosya_paylasim.dart';
import '../../servisler/excel_servisi.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import 'masaustu/promosyon_masaustu_gorunum.dart';
import 'promosyon_form_sheet.dart';
import 'widgets/promosyon_kart_widgetlari.dart';

export 'promosyon_form_sheet.dart' show PromosyonFormSheet;

class PromosyonEkrani extends ConsumerStatefulWidget {
  const PromosyonEkrani({super.key});
  @override
  ConsumerState<PromosyonEkrani> createState() => _PromosyonEkraniState();
}

class _PromosyonEkraniState extends ConsumerState<PromosyonEkrani> {
  final _araCtrl = TextEditingController();
  static const _durumlar = ['Tümü', 'Aktif', 'Pasif', 'Süresi Dolmuş'];

  @override
  void initState() {
    super.initState();
    _araCtrl.addListener(() {
      ref.read(promosyonFiltresiProvider.notifier).aramaGuncelle(_araCtrl.text);
    });
  }

  @override
  void dispose() { _araCtrl.dispose(); super.dispose(); }

  // ── Excel (PROMOSYON.xlsx başlıklarıyla birebir) ───────────────────────────
  Future<void> _excelDisaVer() async {
    try {
      final liste = await PromosyonDeposu().detayliGetir();
      if (liste.isEmpty) {
        BildirimServisi.uyari(context, 'Dışarı verilecek promosyon yok');
        return;
      }
      final yol = await ExcelServisi().promosyonExcelDisaAl(liste);
      await DosyaPaylasim.paylas(ShareParams(files: [XFile(yol)], text: 'Promosyon Listesi'));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  Future<void> _excelIceAl() async {
    final secilen = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['xlsx']);
    if (secilen == null || !mounted) return;
    final bytes = await secilen.readAsBytes();
    if (!mounted) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excel içeri al'),
        content: Text('"${secilen.name}" dosyasındaki promosyonlar eklenecek. '
            'Aynı ürün için kayıtlı promosyon varsa yenisiyle değiştirilir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İçeri Al')),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    try {
      final sonuc = await ExcelServisi().promosyonExcelIceAl(bytes);
      ref.invalidate(promosyonlarProvider);
      if (!mounted) return;
      final hata = sonuc['hata'] as int;
      final msg = '${sonuc['basarili']} promosyon alındı${hata > 0 ? ', $hata satır atlandı' : ''}';
      if (hata > 0 && sonuc['basarili'] == 0) {
        BildirimServisi.hata(context, msg);
      } else {
        BildirimServisi.basari(context, msg);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  Future<void> _aktiflikToggle(PromosyonModel p) async {
    try {  
      await PromosyonDeposu().aktiflikToggle(p.id!, !p.aktif);
      ref.invalidate(promosyonlarProvider);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _sil(PromosyonModel p) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Text('Promosyonu Sil'),
        content: Text('${p.promosyonAdi} silinecek. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay == true && mounted) {
      await PromosyonDeposu().sil(p.id!);
      ref.invalidate(promosyonlarProvider);
    }
  }

  /// Düzenleme, "Yeni Promosyon" formuyla AYNI formu kullanır (ürün, iskonto %
  /// ↔ toplam fiyat, min. miktar, başlangıç/bitiş tarihi + tarih yenileme,
  /// aktif) — önceden ayrı, tarihsiz ve toplam fiyatsız bir form vardı.
  Future<void> _promosyonDuzenle(PromosyonModel promo) async {
    try {
      final sonuc = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: _sheetKisiti(context),
        builder: (_) => PromosyonFormSheet(duzenlenecek: promo),
      );
      if (sonuc == true) {
        ref.invalidate(promosyonlarProvider);
        if (mounted) BildirimServisi.basari(context, 'Promosyon güncellendi ✓');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<void> _promosyonEkleDialog() async {
    try {  
      final sonuc = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: _sheetKisiti(context),
        builder: (_) => const PromosyonFormSheet(),
      );
      if (sonuc == true) ref.invalidate(promosyonlarProvider);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  /// Geniş pencerede alttan açılan form tüm genişliğe yayılmasın.
  BoxConstraints? _sheetKisiti(BuildContext c) =>
      MediaQuery.sizeOf(c).width > 1100 ? const BoxConstraints(maxWidth: 560) : null;

  @override
  Widget build(BuildContext context) {
    final masaustu = MediaQuery.sizeOf(context).width > 1100;
    final yetkili = ref.watch(authProvider.select((s) => s.isMudur));
    final filtre = ref.watch(promosyonFiltresiProvider);
    final liste = ref.watch(filtreliPromosyonlarProvider);
    final async = ref.watch(promosyonlarProvider);
    final aktifSayisi = ref.watch(aktifPromosyonSayisiProvider);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Promosyonlar',
        aksiyonlar: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Excel',
            onSelected: (v) => v == 'ice' ? _excelIceAl() : _excelDisaVer(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'ice',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.file_download_outlined),
                      title: Text('Excel içeri al'))),
              PopupMenuItem(
                  value: 'disa',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.file_upload_outlined),
                      title: Text('Excel dışarı ver'))),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(promosyonlarProvider),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: context.cardBg,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(children: [
            TextField(
              controller: _araCtrl,
              decoration: InputDecoration(
                hintText: 'Promosyon ara...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _araCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear),
                        onPressed: () { _araCtrl.clear(); ref.read(promosyonFiltresiProvider.notifier).aramaGuncelle(''); })
                    : null,
                filled: true, fillColor: context.borderColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _durumlar.map((d) {
                final secili = filtre.durum == d;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(d), selected: secili,
                    onSelected: (_) => ref.read(promosyonFiltresiProvider.notifier).durumAyarla(d),
                    selectedColor: AppRenkler.primary,
                    labelStyle: TextStyle(color: secili ? Colors.white : context.textSecondary, fontSize: 11),
                    backgroundColor: context.scaffoldBg, checkmarkColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList()),
            ),
          ]),
        ),
        if (async.hasValue)
          Container(
            color: context.cardBg,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              PromosyonChip('$aktifSayisi Aktif', Colors.green.shade700),
              const SizedBox(width: 8),
              PromosyonChip('${async.value!.length} Toplam', AppRenkler.primary),
            ]),
          ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: AppYukleniyor()),
            error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Hata: ${kullaniciyaHataMetni(e)}', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => ref.invalidate(promosyonlarProvider), child: const Text('Tekrar Dene')),
            ])),
            data: (_) => liste.isEmpty && !masaustu
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.local_offer_outlined, size: 64, color: context.textHint),
                    const SizedBox(height: 12),
                    Text(_araCtrl.text.isNotEmpty ? 'Sonuç bulunamadı' : 'Promosyon yok',
                        style: TextStyle(color: context.textSecondary)),
                  ]))
                : masaustu
                ? PromosyonMasaustuGorunum(
                    promosyonlar: liste,
                    yetkili: yetkili,
                    onEkle: _promosyonEkleDialog,
                    onDuzenle: _promosyonDuzenle,
                    onToggle: _aktiflikToggle,
                    onSil: _sil,
                    bosMesaj: _araCtrl.text.isNotEmpty
                        ? 'Sonuç bulunamadı'
                        : 'Promosyon yok — F1 ile ekleyin',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: liste.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => PromosyonKarti(
                      promosyon: liste[i],
                      onToggle:   () => _aktiflikToggle(liste[i]),
                      onSil:      () => _sil(liste[i]),
                      onDuzenle:  () => _promosyonDuzenle(liste[i]),
                    ),
                  ),
          ),
        ),
      ]),
      floatingActionButton: masaustu ? null : TsYetkili(child: FloatingActionButton.extended(
        elevation: 6,
        onPressed: _promosyonEkleDialog,
        backgroundColor: AppRenkler.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.local_offer),
        label: const Text('Promosyon Ekle'),
      )),
    );
  }
}
