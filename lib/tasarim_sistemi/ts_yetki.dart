// lib/tasarim_sistemi/ts_yetki.dart
//
// TEK YETKİ KONTROLÜ — silme/düzenleme gibi kritik aksiyonları
// sadece Admin/Müdür görsün, Kasiyer hiç görmesin.
//
// Kural (kullanıcı onayı ile, 2026-07-03): Sadece Admin/Müdür silebilir/
// düzenleyebilir; Kasiyer sadece görüntüler.
//
// Kullanım:
//   TsYetkili(
//     child: IconButton(icon: Icon(Icons.delete), onPressed: _sil),
//   )
//
// Yetkisiz kullanıcıda hiçbir şey render edilmez (SizedBox.shrink) —
// buton tamamen kaybolur, devre dışı/gri gösterilmez. Bu, kasiyerin
// "neden tıklayamıyorum" diye kafasının karışmasını önler; yetkisi
// olmayan bir aksiyonu hiç görmez.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../saglayicilar/riverpod/auth_provider.dart';

class TsYetkili extends ConsumerWidget {
  final Widget child;

  /// true ise Admin/Müdür dışındaki roller de görebilir (varsayılan false —
  /// yani varsayılan olarak sadece Admin/Müdür).
  final bool kasiyerDeGorsun;

  const TsYetkili({super.key, required this.child, this.kasiyerDeGorsun = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kasiyerDeGorsun) return child;
    final yetkili = ref.watch(authProvider.select((s) => s.isMudur));
    return yetkili ? child : const SizedBox.shrink();
  }
}

/// Widget ağacı dışında (ör. bir metod içinde) hızlı senkron kontrol
/// gerektiğinde kullanılır: `if (!TsYetki.silebilirMi(ref)) return;`
class TsYetki {
  TsYetki._();
  static bool silebilirMi(WidgetRef ref) =>
      ref.read(authProvider).isMudur;
  static bool duzenleyebilirMi(WidgetRef ref) =>
      ref.read(authProvider).isMudur;
}
