// lib/cekirdek/utils/etiket_yardimci.dart
//
// Raf/ürün etiketi için ortak hesaplar — önizleme, termal (ESC/POS) ve ZPL
// çıktısı AYNI sonucu üretsin diye tek yerde.
import '../../modeller/urun_model.dart';
import 'para_utils.dart';

class EtiketYardimci {
  EtiketYardimci._();

  /// Fiyat Etiketi Yönetmeliği'nin istediği BİRİM FİYAT satırı
  /// (ör. "1 KG: 72,22 TL"). Hesaplanamıyorsa null.
  ///
  /// 🔴 DÜZELTME (2026-09-28): "Birim Fiyatlı Mod" ÖNCEDEN yalnızca birim
  /// adını ("Adet") ve AYNI fiyatı yan yana basıyordu — gerçek bir birim
  /// fiyat değildi. Artık:
  ///  - birimi KG/LT olan (tartılı/açık) üründe fiyat zaten birim fiyattır,
  ///  - ürün kartında Ağırlık (gr) girilmişse fiyat 1 kg'a oranlanır.
  static String? birimFiyatMetni(UrunModel u, double fiyat) {
    final birim = u.birimAdi.trim().toUpperCase();
    if (birim == 'KG' || birim == 'KİLOGRAM' || birim == 'KILOGRAM') {
      return '1 KG: ${ParaUtils.formatla(fiyat, simge: '')} TL';
    }
    if (birim == 'LT' || birim == 'LİTRE' || birim == 'LITRE' || birim == 'L') {
      return '1 LT: ${ParaUtils.formatla(fiyat, simge: '')} TL';
    }
    if (u.agirlik > 0 && fiyat > 0) {
      final kgFiyat = fiyat / (u.agirlik / 1000);
      return '1 KG: ${ParaUtils.formatla(kgFiyat, simge: '')} TL';
    }
    return null;
  }

  /// Metni kelime sınırından en fazla [satirSayisi] satıra böler (her satır
  /// en fazla [genislik] karakter). Sığmayan son kelime kısaltılır.
  /// ÖNCEDEN ad 24. karakterde KELİME ORTASINDAN kesiliyordu.
  static List<String> satirlaraBol(String metin, int genislik, {int satirSayisi = 2}) {
    final kelimeler = metin.trim().split(RegExp(r'\s+'));
    final satirlar = <String>[];
    var mevcut = '';
    for (final k in kelimeler) {
      final aday = mevcut.isEmpty ? k : '$mevcut $k';
      if (aday.length <= genislik) {
        mevcut = aday;
        continue;
      }
      if (mevcut.isNotEmpty) satirlar.add(mevcut);
      mevcut = k.length > genislik ? k.substring(0, genislik) : k;
      if (satirlar.length == satirSayisi) break;
    }
    if (mevcut.isNotEmpty && satirlar.length < satirSayisi) satirlar.add(mevcut);
    return satirlar.take(satirSayisi).toList();
  }
}
