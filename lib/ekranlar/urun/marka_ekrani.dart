// lib/ekranlar/urun/marka_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/marka_deposu.dart';

class MarkaEkrani extends ConsumerStatefulWidget {
  const MarkaEkrani({super.key});
  @override
  ConsumerState<MarkaEkrani> createState() => _MarkaEkraniState();
}

class _MarkaEkraniState extends ConsumerState<MarkaEkrani> {
  final _depo = MarkaDeposu();
  List<Map<String, dynamic>> _markalar = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    _yukleniyor = true;
    if (mounted) setState(() {});
    try {
      _markalar = await _depo.listele();
      _yukleniyor = false;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _markaEkle() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: const Text('Yeni Marka Ekle'),
        content: TsInput(etiket: 'Marka Adı', controller: ctrl, oncilIkon: Icons.branding_watermark),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(ctx, false)),
          TsButon(metin: 'Ekle', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await _depo.ekle(ctrl.text.trim());
      await _yukle();
      if (mounted) BildirimServisi.basari(context, 'Marka eklendi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Marka eklenemedi: $e');
    }
  }

  Future<void> _markaDuzenle(Map<String, dynamic> marka) async {
    final ctrl = TextEditingController(text: marka['ad'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: const Text('Marka Düzenle'),
        content: TsInput(etiket: 'Marka Adı', controller: ctrl, oncilIkon: Icons.branding_watermark),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(ctx, false)),
          TsButon(metin: 'Kaydet', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      if (marka['id'] != null) {
        await _depo.duzenle(
          id: marka['id'] as int,
          eskiAd: marka['ad']?.toString() ?? '',
          yeniAd: ctrl.text.trim(),
        );
      }
      await _yukle();
      if (mounted) BildirimServisi.basari(context, 'Marka güncellendi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Güncelleme hatası: $e');
    }
  }

  Future<void> _markaSil(Map<String, dynamic> marka) async {
    final urunSayisi = (marka['urun_sayisi'] as int?) ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: const Text('Marka Sil'),
        content: Text(urunSayisi > 0
            ? '"${marka['ad']}" markası $urunSayisi üründe kullanılıyor. Yine de silmek istiyor musunuz?'
            : '"${marka['ad']}" markasını silmek istiyor musunuz?'),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(ctx, false)),
          TsButon.tehlike(metin: 'Sil', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (marka['id'] != null) {
        await _depo.sil(marka['id'] as int);
      }
      await _yukle();
      if (mounted) BildirimServisi.basari(context, 'Marka silindi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Silme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Markalar',
        gradyanli: true,
        aksiyonlar: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _yukle)],
      ),
      body: TsListe<Map<String, dynamic>>(
        yukleniyor: _yukleniyor,
        ogeler: _markalar,
        aramaMetniAl: (m) => m['ad'] as String? ?? '',
        bosBaslik: 'Marka bulunamadı',
        bosIkon: Icons.branding_watermark_outlined,
        bosAltyazi: 'Sağ alttaki "Marka Ekle" ile başlayın',
        yenile: _yukle,
        kartOlustur: (context, m, i) {
          final urunSayisi = (m['urun_sayisi'] as int?) ?? 0;
          final ad = m['ad'] as String? ?? '';
          return TsKart.liste(
            baslik: ad,
            altBaslik: '$urunSayisi ürün',
            ikon: Text(ad.isNotEmpty ? ad[0].toUpperCase() : '?',
                style: const TextStyle(color: TsRenk.primary, fontWeight: FontWeight.bold)),
            sagAksiyon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _markaDuzenle(m), tooltip: 'Düzenle'),
              IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: TsRenk.hata), onPressed: () => _markaSil(m), tooltip: 'Sil'),
            ]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: _markaEkle,
        icon: const Icon(Icons.add),
        label: const Text('Marka Ekle'),
      ),
    );
  }
}
