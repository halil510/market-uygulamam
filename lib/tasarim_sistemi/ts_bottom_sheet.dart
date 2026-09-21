// lib/tasarim_sistemi/ts_bottom_sheet.dart
//
// DEEP_AUDIT_REPORT FAZ 6 (UX/UI, P3) — madde 25, kullanıcı onayıyla
// (sadece tasarım bileşenleri): "Design System'de TsDialog/TsBottomSheet/
// TsChart bileşenleri yok — dialog radius/padding elle tekrarlanıyor."
// Uygulamada onlarca yerde `showModalBottomSheet(backgroundColor:
// Colors.transparent, builder: (_) => Container(decoration: BoxDecoration(
// color: ..., borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
// ...))` + elle çizilen bir sürükleme tutamacı elle tekrarlanıyordu (bkz.
// hizli_satis_ekrani_widgets.dart _OdemeSecimSheet). TsDialog'un kapsadığı
// AYNI mantık, bottom sheet'ler için.
//
// BİLİNÇLİ KAPSAM: mevcut onlarca showModalBottomSheet çağrısını buna
// taşımak (geniş, görsel doğrulama gerektiren, riskli bir retrofit) bu
// turun kapsamı DIŞINDA bırakıldı — bu sadece BUNDAN SONRA yazılacak yeni
// bottom sheet'ler için tutarlı bir temel sağlıyor.
import 'package:flutter/material.dart';
import 'ts_token.dart';

class TsBottomSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool surukleTutamaci;

  const TsBottomSheet({
    super.key,
    required this.child,
    this.padding,
    this.surukleTutamaci = true,
  });

  /// `showModalBottomSheet` + `TsBottomSheet`'i tek adımda birleştiren
  /// kısayol — arkaplan şeffaf, üst köşeler yuvarlak.
  static Future<T?> goster<T>(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry? padding,
    bool surukleTutamaci = true,
    bool isScrollControlled = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (_) => TsBottomSheet(
        padding: padding,
        surukleTutamaci: surukleTutamaci,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(TsRadius.xl)),
      ),
      padding: padding ??
          const EdgeInsets.fromLTRB(
              TsBosluk.xl, TsBosluk.lg, TsBosluk.xl, TsBosluk.xxxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (surukleTutamaci) ...[
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: TsRenk.ayirac(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: TsBosluk.lg),
          ],
          child,
        ],
      ),
    );
  }
}
