// lib/widgetlar/urun/excel_ice_aktar_yardimcisi.dart
// Tek sorumluluk: Excel'den ürün içe aktarma akışını (dosya seç → işle →
// sonuç/hata dialog'u göster) tek bir yerden sunmak. Ayarlar ekranındaki
// orijinal akışla aynı mantık — kod tekrarını önlemek için buraya taşındı.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../servisler/excel_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../ortak/yukleniyor_widget.dart';

class ExcelIceAktarYardimcisi {
  /// Excel/CSV dosyası seçtirir, ürünleri içe aktarır ve sonucu dialog ile
  /// gösterir. Başarılı olursa [onTamamlandi] çağrılır (liste yenilensin diye).
  static Future<void> iceAktar(BuildContext context, {required VoidCallback onTamamlandi}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final dosya = result.files.single;
      final Uint8List? fileBytes = dosya.bytes ??
          (dosya.path != null ? await File(dosya.path!).readAsBytes() : null);
      if (fileBytes == null) {
        if (context.mounted) BildirimServisi.hata(context, 'Dosya okunamadı');
        return;
      }

      if (!context.mounted) return;
      final progressCtx = context;
      showDialog(
        context: progressCtx,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) => const ProgressDialog(mesaj: 'Excel dosyası işleniyor...'),
      );

      IceriAktarSonuc? sonuc;
      try {
        sonuc = await ExcelServisi().exceldenurunleriBytesIceriAl(fileBytes);
      } catch (e) {
        if (progressCtx.mounted) Navigator.of(progressCtx, rootNavigator: true).pop();
        if (context.mounted) BildirimServisi.hata(context, 'Excel işleme hatası: $e');
        return;
      }

      if (progressCtx.mounted) Navigator.of(progressCtx, rootNavigator: true).pop();
      if (!context.mounted) return;

      if (sonuc != null && (sonuc.eklenen + sonuc.guncellenen) > 0) {
        onTamamlandi();
        if (context.mounted) _sonucDialog(context, sonuc);
      } else {
        if (context.mounted) _hataDialog(context, sonuc);
      }
    } catch (e) {
      try {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      } catch (_) { /* ignore */ }
      if (context.mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  static void _sonucDialog(BuildContext context, IceriAktarSonuc sonuc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8),
          Text('İçe Aktarma Tamamlandı'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _sonucSatiri('Eklenen Ürün', sonuc.eklenen, Colors.green),
          _sonucSatiri('Güncellenen Ürün', sonuc.guncellenen, Colors.blue),
          if (sonuc.indirimliKaydedilen > 0)
            _sonucSatiri('Otomatik İndirimli', sonuc.indirimliKaydedilen, Colors.orange),
          if (sonuc.hatali > 0) _sonucSatiri('Hatalı Satır', sonuc.hatali, Colors.red),
          const SizedBox(height: 8),
          Text('Toplam ${sonuc.toplam} satır işlendi'),
          if (sonuc.indirimliKaydedilen > 0)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.local_offer, color: Colors.orange, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${sonuc.indirimliKaydedilen} üründe otomatik indirim aktif edildi. '
                  'Hızlı satışta barkod okutunca indirimli fiyat uygulanır.',
                  style: const TextStyle(fontSize: 11),
                )),
              ]),
            ),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
      ),
    );
  }

  static void _hataDialog(BuildContext context, IceriAktarSonuc? sonuc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.error_outline, color: Colors.red), SizedBox(width: 8),
          Text('İçe Aktarma Başarısız'),
        ]),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hiç ürün eklenemedi.'),
            if (sonuc != null && sonuc.hatalar.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Hatalar:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...sonuc.hatalar.take(5).map((h) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• ${h.length > 200 ? '${h.substring(0, 200)}…' : h}',
                    style: const TextStyle(fontSize: 12)),
              )),
            ],
          ])),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
      ),
    );
  }

  static Widget _sonucSatiri(String etiket, int sayi, Color renk) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(etiket, style: const TextStyle(fontSize: 14)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
                color: Color.fromARGB(26, renk.red, renk.green, renk.blue),
                borderRadius: BorderRadius.circular(12)),
            child: Text('$sayi', style: TextStyle(fontWeight: FontWeight.w700, color: renk)),
          ),
        ]),
      );
}
