// lib/ekranlar/stok/stok_sayim_ekrani.dart  (Riverpod versiyonu)
//
// DEĞIŞIKLIKLER:
//   - StatefulWidget → ConsumerStatefulWidget
//   - StokSayimNotifier → stokSayimProvider

import 'dart:async';
import '../../cekirdek/utils/para_utils.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../servisler/barkod_servisi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/stok_sayim_provider.dart';
import '../../depolar/urun_deposu.dart';
import '../../servisler/excel_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class StokSayimEkrani extends ConsumerStatefulWidget {
  const StokSayimEkrani({super.key});

  @override
  ConsumerState<StokSayimEkrani> createState() => _StokSayimEkraniState();
}

class _StokSayimEkraniState extends ConsumerState<StokSayimEkrani> {
  final _araCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _araDebounce;

  @override
  void initState() {
    super.initState();
    _araCtrl.addListener(_aramaChanged);
    _scrollCtrl.addListener(_scrollChanged);
  }

  @override
  void dispose() {
    _araDebounce?.cancel();
    _araCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Excel İçe Al ──────────────────────────────────────────────────────────
  Future<void> _excelIceAl() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx']);
    if (result == null || result.files.first.bytes == null) return;
    if (!mounted) return;
    // 🔴 Derin analizde bulundu: dosya seçilir seçilmez, hiçbir önizleme
    // veya onay olmadan doğrudan uygulanıyordu — manuel sayım akışının
    // aksine ("Sayımı Uygula" açık onay istiyor). Yanlış/eski bir
    // dosyanın seçilmesi, canlı stoğu anında ve geri dönüşsüz şekilde
    // (manuel düzeltme dışında) değiştirebiliyordu.
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Excel İçe Al'),
        content: Text(
          '"${result.files.first.name}" dosyasındaki miktarlara göre stok '
          'güncellenecek.\nBu işlem geri alınamaz. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppRenkler.primary),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(children: [
          const CircularProgressIndicator(color: TsRenk.primary, strokeWidth: 3),
          const SizedBox(width: 16),
          Text('Excel içe alınıyor...'),
        ]),
      ));
    try {
      final sonuc = await ExcelServisi().stokSayimExcelIceAl(result.files.first.bytes!);
      if (!mounted) return;
      Navigator.pop(context);
      ref.read(stokSayimProvider.notifier).yukle(sifirla: true);
      BildirimServisi.basari(context, '✓ ${sonuc['basarili']} güncellendi, ${sonuc['hata']} hata');
    } catch (e) {
      if (mounted) { Navigator.pop(context); BildirimServisi.hata(context, 'Hata: $e'); }
    }
  }

  // ── Excel Dışa Al ──────────────────────────────────────────────────────────
  Future<void> _excelDisaAl() async {
    final durum = ref.read(stokSayimProvider);
    if (durum.urunler.isEmpty) { BildirimServisi.uyari(context, 'Listede ürün yok'); return; }
    try {
      // 🔴 DÜZELTME: 'Stok' ve 'Fark' sütunları her zaman TOPLAM stoğa
      // göre hesaplanıyordu, 'DepoAdi' de sabit "Merkez Depo" yazıyordu
      // — çok şubeli bir işletmede bu, yanlış karşılaştırma tabanı
      // demekti. Artık aktif şube seçiliyse o şubenin gerçek payı ve
      // adı kullanılıyor.
      final subeAdi = AktifSubeServisi().subeAdi;
      final stoklar = durum.urunler.map((u) {
        final mevcut = durum.mevcutStok(u);
        final sayilan = durum.sayimMiktarlari[u.id] ?? mevcut;
        return {
          'Kod': u.barkod ?? '', 'UrunAdi': u.urunAdi,
          'Ana Miktar': sayilan, 'Stok': mevcut,
          'Fark': sayilan - mevcut, 'DepoAdi': subeAdi,
        };
      }).toList();
      final yol = await ExcelServisi().stokSayimExcelDisaAl(stoklar);
      await Share.shareXFiles([XFile(yol)], text: 'Stok Sayım Listesi');
    } catch (e) { if (mounted) BildirimServisi.hata(context, 'Hata: $e'); }
  }

  // Barkod tara → ürünü bul → miktar dialog aç → listede birikimli tut
  Future<void> _barkodTaraVeMiktarGir() async {
    final barkod = await BarkodServisi().barkodTara(context);
    if (barkod == null || !mounted) return;

    // Ürünü barkod ile bul
    final urun = await UrunDeposu().barkodlaGetir(barkod);
    if (!mounted) return;

    if (urun == null) {
      BildirimServisi.uyari(context, 'Barkod bulunamadı: $barkod');
      return;
    }

    // Miktar dialog
    final mevcut = ref.read(stokSayimProvider).sayimMiktarlari[urun.id] ?? 0;
    final ctrl = TextEditingController(text: mevcut > 0 ? mevcut.toStringAsFixed(0) : '');
    final miktar = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        
        title: Text(urun.urunAdi, style: const TextStyle(fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Barkod: $barkod', style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Sayım Miktarı (${urun.birimAdi})',
              border: const OutlineInputBorder(),
              suffixText: urun.birimAdi,
            ),
            onSubmitted: (v) {
              final d = double.tryParse(v.replaceAll(',', '.'));
              Navigator.pop(ctx, d);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              final d = double.tryParse(ctrl.text.replaceAll(',', '.'));
              Navigator.pop(ctx, d);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );

    if (miktar != null && mounted) {
      ref.read(stokSayimProvider.notifier).miktarGuncelle(urun.id!, miktar);
      // Ürün listede yoksa ekle
      final listede = ref.read(stokSayimProvider).urunler.any((u) => u.id == urun.id);
      if (!listede) {
        ref.read(stokSayimProvider.notifier).urunEkle(urun);
      }
      // Sayılanlar moduna geç (göz ikonu)
      if (!ref.read(stokSayimProvider).sadeceSayilan) {
        ref.read(stokSayimProvider.notifier).sadeceSayilanToggle();
      }
      BildirimServisi.basari(context, '${urun.urunAdi}: $miktar ${urun.birimAdi} kaydedildi');
    }
  }

  // Excel dışa aktar → sayılan ürünleri Excel'e yaz
  Future<void> _excelDisaAktar() async {
    final durum = ref.read(stokSayimProvider);
    if (durum.sayimMiktarlari.isEmpty) {
      BildirimServisi.uyari(context, 'Henüz sayım yapılmadı');
      return;
    }
    try {
      final stoklar = durum.urunler
        .where((u) => durum.sayimMiktarlari.containsKey(u.id))
        .map((u) {
          final mevcut = durum.mevcutStok(u);
          return {
            'UrunAdi': u.urunAdi,
            'Kod': u.kod ?? '',
            'Barkod': u.barkod ?? '',
            'Ana Miktar': durum.sayimMiktarlari[u.id] ?? 0,
            'Stok': mevcut,
            'Fark': (durum.sayimMiktarlari[u.id] ?? 0) - mevcut,
            'Birim': u.birimAdi,
          };
        }).toList();
      final yol = await ExcelServisi().stokSayimExcelDisaAl(stoklar);
      if (mounted) await Share.shareXFiles([XFile(yol)], text: 'Stok Sayım Listesi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Dışa aktarma hatası: $e');
    }
  }

  // Excel içe aktar → sayım listesine yükle
  Future<void> _excelIceAktar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true);
      if (result == null || result.files.single.bytes == null || !mounted) return;

      final bytes = result.files.single.bytes!;
      final liste = await ExcelServisi().stokSayimListesiIceAl(bytes);
      if (!mounted) return;

      if (liste.isEmpty) {
        BildirimServisi.uyari(context, 'Excel dosyasında ürün bulunamadı');
        return;
      }

      // Her ürünü sayım listesine ekle
      for (final satir in liste) {
        final urunId = satir['urun_id'] as int?;
        final miktar = satir['miktar'] as double? ?? 0;
        if (urunId != null) {
          ref.read(stokSayimProvider.notifier).miktarGuncelle(urunId, miktar);
        }
      }

      BildirimServisi.basari(context, '${liste.length} ürün sayım listesine yüklendi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel okunamadı: $e');
    }
  }

  void _aramaChanged() {
    _araDebounce?.cancel();
    _araDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(stokSayimProvider.notifier).aramaGuncelle(_araCtrl.text);
    });
  }

  void _scrollChanged() {
    final durum = ref.read(stokSayimProvider);
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      if (durum.dahaFazla && !durum.yukleniyor) {
        ref.read(stokSayimProvider.notifier).yukle(sifirla: false);
      }
    }
  }

  Future<void> _sayimiUygula() async {
    final durum = ref.read(stokSayimProvider);
    if (durum.sayimMiktarlari.isEmpty) {
      BildirimServisi.uyari(context, 'Miktar girilmedi');
      return;
    }

    // 🔴 DÜZELTME (Madde 13 denetimi, 2026-09-16): Müdür/Admin DEĞİLSE
    // bu işlem artık stoğu DEĞİL — sadece bekleyen bir onay talebini
    // değiştirir. Diyalog metni buna göre dürüst olmalı ("geri alınamaz"
    // demek YANLIŞ, çünkü Müdür reddedebilir).
    final yetkili = AuthServisi().isMudur;
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

        title: Text(yetkili ? 'Sayımı Uygula' : 'Sayımı Onaya Gönder'),
        content: Text(yetkili
            ? '${durum.sayimMiktarlari.length} ürün için stok güncelleme yapılacak.\n'
              'Bu işlem geri alınamaz. Devam etmek istiyor musunuz?'
            : '${durum.sayimMiktarlari.length} ürün için sayım Müdür onayına '
              'gönderilecek. Onaylanana kadar stok DEĞİŞMEYECEK. Devam etmek '
              'istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white,
          backgroundColor: AppRenkler.primary),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );

    if (onay != true) return;

    final sonuc = await ref.read(stokSayimProvider.notifier).uygula();

    if (mounted) {
      if (sonuc.basarili) {
        BildirimServisi.basari(context, sonuc.mesaj);
      } else {
        BildirimServisi.hata(context, sonuc.mesaj);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final durum = ref.watch(stokSayimProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Stok Sayımı',
        aksiyonlar: [
          // Madde 13 denetimi (2026-09-16): kasiyer/personelin gönderdiği
          // bekleyen sayımları onaylama ekranına giriş — sadece Müdür/
          // Admin görür (TsYetkili), ekranın kendisi de ayrıca
          // MudurYetkiKorumasi ile route seviyesinde korunuyor.
          TsYetkili(
            child: IconButton(
              icon: const Icon(Icons.fact_check_outlined),
              tooltip: 'Bekleyen Sayımları Onayla',
              onPressed: () => context.push('/stok/sayim-onay'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: _excelIceAl,
            tooltip: 'Excel İçe Al',
          ),
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            onPressed: _excelDisaAl,
            tooltip: 'Excel Dışa Al',
          ),
          if (durum.sayimMiktarlari.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: _excelIceAktar,
              tooltip: "Excel'den İçe Al",
            ),
            IconButton(
              icon: const Icon(Icons.download_outlined),
              onPressed: _excelDisaAktar,
              tooltip: 'Excel Dışa Al',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref
                  .read(stokSayimProvider.notifier)
                  .sayimiSifirla(),
              tooltip: 'Sayımı Sıfırla',
            ),
          IconButton(
            icon: Icon(durum.sadeceSayilan
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            onPressed: () => ref
                .read(stokSayimProvider.notifier)
                .sadeceSayilanToggle(),
            tooltip: durum.sadeceSayilan ? 'Tümünü Göster' : 'Sadece Sayılanlar',
          ),
        ],
      ),
      body: Column(children: [
        // Arama
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: TextField(
            controller: _araCtrl,
            decoration: InputDecoration(
              hintText: 'Ürün ara...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_araCtrl.text.isNotEmpty)
                    IconButton(icon: const Icon(Icons.clear, size: 16),
                      onPressed: () { _araCtrl.clear(); ref.read(stokSayimProvider.notifier).aramaGuncelle(''); }),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                    tooltip: 'Barkod Tara',
                    onPressed: _barkodTaraVeMiktarGir),
                ]),
              filled:    true,
              fillColor: context.inputFill,
              border:    OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),

        // Sayım özeti
        if (durum.sayilanUrunSayisi > 0)
          Container(
            color: Color.fromARGB(15, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(Icons.inventory_2_outlined,
                  color: AppRenkler.primary, size: 18),
              const SizedBox(width: 8),
              Text('${durum.sayilanUrunSayisi} ürün sayıldı',
                  style: const TextStyle(
                      color: AppRenkler.primary,
                      fontWeight: FontWeight.w600, fontSize: 13)),
              if (durum.kritikler.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 16),
                const SizedBox(width: 4),
                Text('${durum.kritikler.length} kritik stok',
                    style: TextStyle(
                        color: Colors.orange.shade700, fontSize: 12)),
              ],
            ]),
          ),

        // Ürün listesi
        Expanded(
          child: durum.yukleniyor && durum.urunler.isEmpty
              ? const Center(child: const AppYukleniyor())
              : durum.gosterilenler.isEmpty
                  ? _BosEkran(sadeceSayilan: durum.sadeceSayilan)
                  : ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                      itemCount: durum.gosterilenler.length +
                          (durum.yukleniyor ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        if (i == durum.gosterilenler.length) {
                          return const Center(
                              child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(strokeWidth: 2, color: TsRenk.primary),
                          ));
                        }
                        final urun = durum.gosterilenler[i];
                        return _UrunSayimKarti(
                          urun:   urun,
                          miktar: durum.sayimMiktarlari[urun.id],
                          onMiktarDegisti: (m) => ref
                              .read(stokSayimProvider.notifier)
                              .miktarGuncelle(urun.id!, m),
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButton: durum.sayilanUrunSayisi > 0
          ? FloatingActionButton.extended(
              onPressed: durum.uygulamaIsleniyor ? null : _sayimiUygula,
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              icon: durum.uygulamaIsleniyor
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_alt),
              label: Text(durum.uygulamaIsleniyor
                  ? 'Uygulanıyor...'
                  : 'Sayımı Uygula (${durum.sayilanUrunSayisi})'),
            )
          : null,
    );
  }
}

// ── Ürün Sayım Kartı ──────────────────────────────────────────────────────────

class _UrunSayimKarti extends ConsumerStatefulWidget {
  final UrunModel urun;
  final double?   miktar;
  final void Function(double) onMiktarDegisti;

  const _UrunSayimKarti({
    required this.urun,
    required this.miktar,
    required this.onMiktarDegisti,
  });

  @override
  ConsumerState<_UrunSayimKarti> createState() => _UrunSayimKartiState();
}

class _UrunSayimKartiState extends ConsumerState<_UrunSayimKarti> {
  late TextEditingController _ctrl;
  bool _duzenlemeModu = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.miktar?.toString() ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_UrunSayimKarti old) {
    super.didUpdateWidget(old);
    if (!_duzenlemeModu &&
        widget.miktar != old.miktar) {
      _ctrl.text = widget.miktar?.toString() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sayildi   = widget.miktar != null;
    final kritik    = widget.urun.kritikStok;

    return Container(
      decoration: BoxDecoration(
        color: sayildi
            ? TsRenk.zemin(TsRenk.basarili, opaklik: 0.5)
            : Colors.white,
        border: sayildi
            ? Border.all(color: Colors.green.shade200)
            : Border.all(color: Colors.transparent),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          // Durum ikon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: sayildi
                  ? TsRenk.zemin(TsRenk.basarili, opaklik: 0.18)
                  : kritik
                      ? TsRenk.zemin(TsRenk.uyari)
                      : TsRenk.arkaplan(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              sayildi ? Icons.check_circle : (kritik ? Icons.warning_amber : Icons.inventory_2_outlined),
              color: sayildi
                  ? Colors.green.shade600
                  : kritik ? Colors.orange.shade700 : TsRenk.metinIkincil(context),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),

          // Ürün bilgi
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.urun.urunAdi,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Row(children: [
                Text('Mevcut: ${ref.watch(stokSayimProvider).mevcutStok(widget.urun)} ${widget.urun.birim ?? ''}',
                    style: TextStyle(
                        fontSize: 11,
                        color: kritik
                            ? Colors.orange.shade700
                            : TsRenk.metinIkincil(context),
                        fontWeight: kritik ? FontWeight.w600 : FontWeight.normal)),
                if (widget.urun.barkod != null) ...[
                  const SizedBox(width: 8),
                  Text(widget.urun.barkod!,
                      style: TextStyle(
                          fontSize: 10, color: TsRenk.metinIkincil(context))),
                ],
              ]),
            ],
          )),

          // Miktar giriş
          SizedBox(
            width: 80,
            child: _duzenlemeModu
                ? TextField(
                    controller: _ctrl,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppRenkler.primary)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppRenkler.primary, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      setState(() => _duzenlemeModu = false);
                      final parsed = double.tryParse(v) ?? -1;
                      widget.onMiktarDegisti(parsed);
                    },
                    onTapOutside: (_) {
                      setState(() => _duzenlemeModu = false);
                      final parsed = ParaUtils.sayiCoz(_ctrl.text) ?? -1;
                      widget.onMiktarDegisti(parsed);
                    },
                  )
                : GestureDetector(
                    onTap: () => setState(() => _duzenlemeModu = true),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: sayildi
                            ? TsRenk.zemin(TsRenk.basarili, opaklik: 0.18)
                            : TsRenk.arkaplan(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sayildi
                              ? Colors.green.shade300
                              : TsRenk.ayirac(context),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        sayildi
                            ? '${widget.miktar}'
                            : '—',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: sayildi
                              ? Colors.green.shade700
                              : TsRenk.metinIkincil(context),
                        ),
                      ),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _BosEkran extends StatelessWidget {
  final bool sadeceSayilan;
  const _BosEkran({required this.sadeceSayilan});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.inventory_2_outlined, size: 64, color: TsRenk.ayirac(context)),
      const SizedBox(height: 16),
      Text(
        sadeceSayilan ? 'Henüz sayım yapılmadı' : 'Ürün bulunamadı',
        style: TextStyle(color: TsRenk.metinIkincil(context)),
      ),
    ]),
  );
}
