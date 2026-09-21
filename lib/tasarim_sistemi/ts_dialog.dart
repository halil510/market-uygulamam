// lib/tasarim_sistemi/ts_dialog.dart
//
// DEEP_AUDIT_REPORT FAZ 6 (UX/UI, P3): "Design System'de TsDialog/
// TsBottomSheet/TsChart bileşenleri yok — dialog radius/padding elle
// tekrarlanıyor." Ekranlarda onlarca yerde `AlertDialog(shape:
// RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), ...)`
// elle tekrarlanıyordu. Basit onay/iptal diyalogları için zaten
// `OnayDialog` (lib/widgetlar/ortak/onay_dialog.dart) var — bu sınıf
// onun KAPSAMADIĞI, ÖZEL içerikli (form/liste/TextField vb.) diyaloglar
// için aynı standart görünümü (radius, başlık stili, ikon) sağlıyor.
//
// BİLİNÇLİ KAPSAM: mevcut onlarca AlertDialog çağrısını buna taşımak
// (geniş, görsel doğrulama gerektiren, riskli bir retrofit) bu turun
// kapsamı DIŞINDA bırakıldı — bu sadece BUNDAN SONRA yazılacak yeni
// diyaloglar için tutarlı bir temel sağlıyor.
import 'package:flutter/material.dart';
import 'ts_token.dart';

class TsDialog extends StatelessWidget {
  final String baslik;
  final IconData? ikon;
  final Color? ikonRengi;
  final Widget content;
  final List<Widget> actions;
  final EdgeInsetsGeometry? contentPadding;

  const TsDialog({
    super.key,
    required this.baslik,
    required this.content,
    required this.actions,
    this.ikon,
    this.ikonRengi,
    this.contentPadding,
  });

  /// `showDialog` + `TsDialog`'u tek adımda birleştiren kısayol.
  static Future<T?> goster<T>(
    BuildContext context, {
    required String baslik,
    required Widget content,
    required List<Widget> actions,
    IconData? ikon,
    Color? ikonRengi,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => TsDialog(
        baslik: baslik,
        content: content,
        actions: actions,
        ikon: ikon,
        ikonRengi: ikonRengi,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TsRadius.xl)),
      title: Row(children: [
        if (ikon != null) ...[
          Icon(ikon, color: ikonRengi ?? TsRenk.primary),
          const SizedBox(width: TsBosluk.sm),
        ],
        Expanded(child: Text(baslik)),
      ]),
      contentPadding: contentPadding ??
          const EdgeInsets.fromLTRB(
              TsBosluk.xl, TsBosluk.md, TsBosluk.xl, TsBosluk.lg),
      content: content,
      actions: actions,
    );
  }
}
