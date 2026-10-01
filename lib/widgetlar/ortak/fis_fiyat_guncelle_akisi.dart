// lib/widgetlar/ortak/fis_fiyat_guncelle_akisi.dart
//
// "Son fiyata göre güncelle" akışı: önizleme diyaloğu + onay + uygulama.
// Cari Detay (Hareketler sekmesi) ve Cari Hareketler ekranı AYNI akışı
// paylaşır. Asıl mantık FisFiyatGuncellemeServisi'nde.
import 'package:flutter/material.dart';
import '../../cekirdek/utils/hata_utils.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/fis_fiyat_guncelleme_servisi.dart';

/// [satisIdleri] seçili satış fişlerinin id'leri. Fiyat güncellendiyse
/// true döner (çağıran ekran verisini yenilemeli), aksi halde false.
Future<bool> fisFiyatGuncelleAkisi(
  BuildContext context,
  List<int> satisIdleri, {
  String? kullanici,
}) async {
  if (satisIdleri.isEmpty) {
    BildirimServisi.hata(context, 'Seçili hareketler arasında satış fişi yok');
    return false;
  }
  final servis = FisFiyatGuncellemeServisi();
  try {
    final planlar = await servis.onizle(satisIdleri.toSet().toList());
    if (!context.mounted) return false;
    final degisecek = planlar.where((p) => p.degisecekMi).toList();
    final atlanan = planlar.where((p) => p.atlamaNedeni != null).toList();
    final toplamFark = degisecek.fold<double>(0, (a, p) => a + p.fark);

    if (degisecek.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Güncellenecek fiş yok'),
          content: Text(atlanan.isEmpty
              ? 'Seçili fişlerdeki tüm fiyatlar zaten güncel.'
              : 'Atlananlar:\n${atlanan.map((p) => '• ${p.fisNo}: ${p.atlamaNedeni}').join('\n')}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
          ],
        ),
      );
      return false;
    }

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Son Fiyata Göre Güncelle'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in degisecek) ...[
                  Text(
                    '${p.fisNo}:  ${ParaUtils.formatla(p.eskiToplam)} → ${ParaUtils.formatla(p.yeniToplam)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final u in p.degisenUrunler)
                    Text('   $u', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                if (atlanan.isNotEmpty) ...[
                  const Divider(),
                  Text('Atlanacak ${atlanan.length} fiş:',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final p in atlanan)
                    Text('• ${p.fisNo}: ${p.atlamaNedeni}',
                        style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                const Divider(),
                Text(
                  'Cari bakiyesi ${toplamFark >= 0 ? "+" : "−"}${ParaUtils.formatla(toplamFark.abs())} değişecek.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('${degisecek.length} Fişi Güncelle')),
        ],
      ),
    );
    if (onay != true || !context.mounted) return false;

    final sonuc = await servis.uygula(
      degisecek.map((p) => p.satisId).toList(),
      kullanici: kullanici,
    );
    if (context.mounted) {
      BildirimServisi.basari(context,
          '${sonuc.guncellenen} fiş güncellendi (${sonuc.toplamFark >= 0 ? "+" : "−"}${ParaUtils.formatla(sonuc.toplamFark.abs())})');
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      BildirimServisi.hata(
          context, 'Fiyat güncelleme hatası: ${kullaniciyaHataMetni(e)}');
    }
    return false;
  }
}
