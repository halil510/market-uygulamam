// lib/ekranlar/stok/stok_sayim_ekrani.dart  (Riverpod versiyonu)
//
// DEĞIŞIKLIKLER:
//   - StatefulWidget → ConsumerStatefulWidget
//   - StokSayimNotifier → stokSayimProvider

import '../../cekirdek/utils/denetleyici_birak.dart';
import '../../cekirdek/utils/dosya_paylasim.dart';
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
import '../../widgetlar/masaustu/ekran_ustte.dart';
import '../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../widgetlar/masaustu/masaustu_tablo.dart';

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
    final secilen = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['xlsx']);
    if (secilen == null) return;
    final secilenBytes = await secilen.readAsBytes();
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
          '"${secilen.name}" dosyasındaki miktarlara göre stok '
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
        content: const Row(children: [
          CircularProgressIndicator(color: TsRenk.primary, strokeWidth: 3),
          SizedBox(width: 16),
          Text('Excel içe alınıyor...'),
        ]),
      ));
    try {
      final sonuc = await ExcelServisi().stokSayimExcelIceAl(secilenBytes);
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
      await DosyaPaylasim.paylas(ShareParams(files: [XFile(yol)], text: 'Stok Sayım Listesi'));
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
              final d = ParaUtils.sayiCoz(v);
              Navigator.pop(ctx, d);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              final d = ParaUtils.sayiCoz(ctrl.text);
              Navigator.pop(ctx, d);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ).whenComplete(() => dialogSonrasiBirak([ctrl]));

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

  /// Masaüstü: seçili ürünün sayım miktarını diyalogla gir.
  Future<void> _miktarSor(UrunModel urun) async {
    final mevcut = ref.read(stokSayimProvider).sayimMiktarlari[urun.id];
    final ctrl = TextEditingController(text: mevcut == null ? '' : _miktarYazi(mevcut));
    final miktar = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(urun.urunAdi, style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Sayılan miktar (${urun.birimAdi})',
            helperText:
                'Sistemdeki stok: ${_miktarYazi(ref.read(stokSayimProvider).mevcutStok(urun))}',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, ParaUtils.sayiCoz(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ParaUtils.sayiCoz(ctrl.text)),
              child: const Text('Kaydet')),
        ],
      ),
    ).whenComplete(() => dialogSonrasiBirak([ctrl]));
    if (miktar != null && mounted) {
      ref.read(stokSayimProvider.notifier).miktarGuncelle(urun.id!, miktar);
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
            'Kod': (u.barkod ?? '').isNotEmpty ? u.barkod : (u.kod ?? ''),
            'Barkod': u.barkod ?? '',
            'Ana Miktar': durum.sayimMiktarlari[u.id] ?? 0,
            'Stok': mevcut,
            'Fark': (durum.sayimMiktarlari[u.id] ?? 0) - mevcut,
            'Birim': u.birimAdi,
          };
        }).toList();
      final yol = await ExcelServisi().stokSayimExcelDisaAl(stoklar);
      if (mounted) await DosyaPaylasim.paylas(ShareParams(files: [XFile(yol)], text: 'Stok Sayım Listesi'));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Dışa aktarma hatası: $e');
    }
  }

  // Excel içe aktar → sayım listesine yükle
  Future<void> _excelIceAktar() async {
    try {
      final secilen = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
      if (secilen == null || !mounted) return;

      final bytes = await secilen.readAsBytes();
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
          color: context.cardBg,
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
            color: AppRenkler.primary.withAlpha(15),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Icon(Icons.inventory_2_outlined,
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
              ? const Center(child: AppYukleniyor())
              : durum.gosterilenler.isEmpty
                  ? _BosEkran(sadeceSayilan: durum.sadeceSayilan)
                  // Masaüstü: tablo + çift tık/F2 miktar, F4 çıkar, F9 uygula
                  // (canlı tarama 2026-10-08: telefon kart listesi görünüyordu).
                  : MediaQuery.sizeOf(context).width > 1100
                      ? _SayimTablosu(
                          durum: durum,
                          scrollController: _scrollCtrl,
                          onMiktarGir: _miktarSor,
                          onCikar: (u) => ref
                              .read(stokSayimProvider.notifier)
                              .miktarGuncelle(u.id!, -1),
                          onUygula: _sayimiUygula,
                        )
                  : ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                      itemCount: durum.gosterilenler.length +
                          (durum.yukleniyor ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
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
      floatingActionButton: durum.sayilanUrunSayisi > 0 &&
              MediaQuery.sizeOf(context).width <= 1100
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

class _SayimTablosu extends StatefulWidget {
  final StokSayimDurum durum;
  final ScrollController scrollController;
  final void Function(UrunModel u) onMiktarGir;
  final void Function(UrunModel u) onCikar;
  final VoidCallback onUygula;
  const _SayimTablosu({
    required this.durum,
    required this.scrollController,
    required this.onMiktarGir,
    required this.onCikar,
    required this.onUygula,
  });

  @override
  State<_SayimTablosu> createState() => _SayimTablosuState();
}

class _SayimTablosuState extends State<_SayimTablosu> {
  int? _seciliId;

  double? _sayilan(UrunModel u) => widget.durum.sayimMiktarlari[u.id];
  double _mevcut(UrunModel u) => widget.durum.mevcutStok(u);

  String _fark(UrunModel u) {
    final s = _sayilan(u);
    if (s == null) return '';
    final f = s - _mevcut(u);
    if (f == 0) return '0';
    return f > 0 ? '+${_miktarYazi(f)}' : _miktarYazi(f);
  }

  late final List<TabloKolon<UrunModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Ürün',
        genislik: 320,
        esnek: true,
        deger: (u) => u.urunAdi,
        sirala: (u) => u.urunAdi.toLowerCase()),
    TabloKolon(
        baslik: 'Barkod',
        genislik: 150,
        deger: (u) => u.barkod ?? '',
        sirala: (u) => u.barkod ?? ''),
    TabloKolon(baslik: 'Birim', genislik: 80, deger: (u) => u.birimAdi),
    TabloKolon(
        baslik: 'Sistem Stoğu',
        genislik: 120,
        sagaYasli: true,
        deger: (u) => _miktarYazi(_mevcut(u)),
        sirala: _mevcut,
        renk: (u) => _mevcut(u) < 0 ? TsRenk.hata : null),
    TabloKolon(
        baslik: 'Sayılan',
        genislik: 110,
        sagaYasli: true,
        deger: (u) => _sayilan(u) == null ? '' : _miktarYazi(_sayilan(u)!),
        sirala: (u) => _sayilan(u) ?? -1e12,
        renk: (u) => _sayilan(u) == null ? null : TsRenk.primary),
    TabloKolon(
        baslik: 'Fark',
        genislik: 100,
        sagaYasli: true,
        deger: _fark,
        sirala: (u) => _sayilan(u) == null ? 0 : _sayilan(u)! - _mevcut(u),
        renk: (u) {
          final s = _sayilan(u);
          if (s == null) return null;
          final f = s - _mevcut(u);
          return f == 0 ? null : (f > 0 ? TsRenk.basarili : TsRenk.hata);
        }),
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tus);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tus);
    super.dispose();
  }

  UrunModel? get _secili {
    for (final u in widget.durum.gosterilenler) {
      if (u.id == _seciliId) return u;
    }
    return null;
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted || !ekranUstte(context)) return false;
    final k = e.logicalKey;
    final u = _secili;
    if (k == LogicalKeyboardKey.f2 && u != null) {
      widget.onMiktarGir(u);
    } else if (k == LogicalKeyboardKey.f4 && u != null && _sayilan(u) != null) {
      widget.onCikar(u);
    } else if (k == LogicalKeyboardKey.f9 &&
        widget.durum.sayilanUrunSayisi > 0 &&
        !widget.durum.uygulamaIsleniyor) {
      widget.onUygula();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.durum;
    final u = _secili;
    return Column(children: [
      Expanded(
        child: MasaustuTablo<UrunModel>(
          satirlar: d.gosterilenler,
          kolonlar: _kolonlar,
          secili: u,
          scrollController: widget.scrollController,
          onSec: (x) => setState(() => _seciliId = x.id),
          onCift: widget.onMiktarGir,
          onSagTik: (x, konum) => masaustuMenuAc(context, konum, [
            MenuOge('Miktar Gir', () => widget.onMiktarGir(x), ikon: Icons.edit_outlined),
            if (_sayilan(x) != null)
              MenuOge('Sayımdan Çıkar', () => widget.onCikar(x),
                  ikon: Icons.remove_circle_outline, ayiracOnce: true),
          ]),
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Sayılan Ürün', '${d.sayilanUrunSayisi}'),
          if (d.kritikler.isNotEmpty)
            AltOzet('Kritik Stok', '${d.kritikler.length}', renk: Colors.orange.shade700),
        ],
        tuslar: [
          AltTus('F2', 'Miktar Gir', Icons.edit_outlined, const Color(0xFF1565C0),
              u == null ? null : () => widget.onMiktarGir(u)),
          AltTus('F4', 'Çıkar', Icons.remove_circle_outline, const Color(0xFFC62828),
              u == null || _sayilan(u) == null ? null : () => widget.onCikar(u)),
          AltTus('F9', AuthServisi().isMudur ? 'Sayımı Uygula' : 'Onaya Gönder',
              Icons.save_alt, const Color(0xFF2E7D32),
              d.sayilanUrunSayisi == 0 || d.uygulamaIsleniyor ? null : widget.onUygula),
        ],
      ),
    ]);
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: sayildi
            ? TsRenk.zemin(TsRenk.basarili, opaklik: 0.5)
            : context.cardBg,
        border: sayildi
            ? Border.all(color: Colors.green.shade200)
            : Border.all(color: Colors.transparent),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6, offset: Offset(0, 2))],
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
                // "498.0" yerine "498" (kesirli miktarda en fazla 3 hane).
                Text('Mevcut: ${_miktarYazi(ref.watch(stokSayimProvider).mevcutStok(widget.urun))} ${widget.urun.birim}',
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

String _miktarYazi(double m) => m == m.roundToDouble()
    ? m.toStringAsFixed(0)
    : m.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
