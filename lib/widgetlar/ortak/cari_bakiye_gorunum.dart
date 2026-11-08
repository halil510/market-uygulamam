// lib/widgetlar/ortak/cari_bakiye_gorunum.dart
//
// Cari bakiyesinin ekranda hangi renk ve etiketle gösterileceği — TEK kaynak.
// Önceden Cari Liste ve Cari Detay aynı kuralı ayrı ayrı yazıyordu; Tahsilat/
// Ödeme ekranı ise kendi kuralıyla müşterinin bize borcunu (bakiye > 0)
// KIRMIZI, listede aynı tutar YEŞİL görünüyordu (canlı test 2026-11-08).
//
// Kural (cari.bakiye = borç - alacak, hareketlerden türetilir):
//   Müşteri:    > 0 → bize borçlu ("Alacak"),        yeşil
//               < 0 → fazla ödemiş ("Fazla Ödedi"),  mavi
//   Diğerleri:  < 0 → biz borçluyuz ("Borç"),         kırmızı
//               > 0 → fazla ödemişiz ("Fazla Ödedik"), mavi
//   0          → "Dengede", ikincil metin rengi
import 'package:flutter/material.dart';
import '../../modeller/cari_model.dart';
import '../../tasarim_sistemi/ts_token.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

bool _musteriMi(CariModel c) => c.cariTipi.contains('Müşteri');

Color cariBakiyeRengi(BuildContext context, CariModel c) {
  if (c.bakiye == 0) return context.textSecondary;
  if (_musteriMi(c)) return c.bakiye > 0 ? TsRenk.basarili : TsRenk.bilgi;
  return c.bakiye < 0 ? TsRenk.hata : TsRenk.bilgi;
}

/// [kisa]: liste rozetleri için ("Alacak"/"Borç"); varsayılan uzun biçim
/// detay/işlem ekranları için ("Alacağımız"/"Borcumuz").
String cariBakiyeEtiketi(CariModel c, {bool kisa = false}) {
  if (c.bakiye == 0) return 'Dengede';
  if (_musteriMi(c)) {
    return c.bakiye > 0 ? (kisa ? 'Alacak' : 'Alacağımız') : 'Fazla Ödedi';
  }
  return c.bakiye < 0 ? (kisa ? 'Borç' : 'Borcumuz') : 'Fazla Ödedik';
}
