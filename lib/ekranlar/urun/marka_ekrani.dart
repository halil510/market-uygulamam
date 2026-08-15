// lib/ekranlar/urun/marka_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../servisler/bildirim_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../veri/database/veritabani.dart';

class MarkaEkrani extends ConsumerStatefulWidget {
  const MarkaEkrani({super.key});
  @override
  ConsumerState<MarkaEkrani> createState() => _MarkaEkraniState();
}

class _MarkaEkraniState extends ConsumerState<MarkaEkrani> {
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
      final db = await Veritabani().db;
      final rows = await db.rawQuery(
        'SELECT m.id, m.ad, m.aktif, COUNT(u.id) as urun_sayisi '
        'FROM markalar m LEFT JOIN urunler u ON u.marka = m.ad AND u.is_deleted = 0 '
        'WHERE m.aktif = 1 '
        'GROUP BY m.id ORDER BY m.ad ASC',
      );
      _markalar = rows;
      _yukleniyor = false;
      if (mounted) setState(() {});
    } catch (_) {
      // markalar tablosu yoksa urunler'den distinct al
      try {
        final db = await Veritabani().db;
        final rows = await db.rawQuery(
          "SELECT marka as ad, COUNT(*) as urun_sayisi FROM urunler "
          "WHERE marka IS NOT NULL AND marka != '' AND is_deleted = 0 "
          "GROUP BY marka ORDER BY marka ASC",
        );
        _markalar = rows;
        _yukleniyor = false;
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) setState(() => _yukleniyor = false);
      }
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
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('markalar', {'ad': ctrl.text.trim(), 'aktif': 1, 'last_updated': now});
      // 🔴 Derin analizde bulundu: last_updated hiç ayarlanmıyordu
      // (sütun az önce eklendi), BulutManager hiç çağrılmıyordu.
      final satir = await db.query('markalar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('markalar', Map<String, dynamic>.from(satir.first));
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
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      if (marka['id'] != null) {
        await db.update('markalar', {'ad': ctrl.text.trim(), 'last_updated': now},
            where: 'id = ?', whereArgs: [marka['id']]);
        await db.update('urunler', {'marka': ctrl.text.trim()},
            where: 'marka = ? AND is_deleted = 0', whereArgs: [marka['ad']]);
        final satir = await db.query('markalar', where: 'id = ?', whereArgs: [marka['id']], limit: 1);
        if (satir.isNotEmpty) BulutManager().upsert('markalar', Map<String, dynamic>.from(satir.first));
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
      final db = await Veritabani().db;
      if (marka['id'] != null) {
        // 🔴 DÜZELTME: Gerçek hard-delete yapılıyordu — markalar
        // tablosunda zaten 'aktif' bayrağı vardı ama hiç kullanılmıyordu.
        // Hard delete, silmenin buluta bildirilememesine yol açıyordu.
        final now = DateTime.now().toIso8601String();
        await db.update('markalar', {'aktif': 0, 'last_updated': now},
            where: 'id = ?', whereArgs: [marka['id']]);
        final satir = await db.query('markalar', where: 'id = ?', whereArgs: [marka['id']], limit: 1);
        if (satir.isNotEmpty) BulutManager().upsert('markalar', Map<String, dynamic>.from(satir.first));
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
