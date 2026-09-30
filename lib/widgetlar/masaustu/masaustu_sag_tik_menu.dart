// lib/widgetlar/masaustu/masaustu_sag_tik_menu.dart
//
// Sağ tık / F6 bağlam menüsü: fare konumunda açılır.
import 'package:flutter/material.dart';

class MenuOge {
  final String etiket;
  final IconData? ikon;
  final VoidCallback? onTap;
  final bool ayiracOnce;
  const MenuOge(this.etiket, this.onTap, {this.ikon, this.ayiracOnce = false});
}

Future<void> masaustuMenuAc(
    BuildContext context, Offset konum, List<MenuOge> ogeler) async {
  final ekran = MediaQuery.sizeOf(context);
  final secilen = await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(
        konum.dx, konum.dy, ekran.width - konum.dx, ekran.height - konum.dy),
    items: [
      for (var i = 0; i < ogeler.length; i++) ...[
        if (ogeler[i].ayiracOnce) const PopupMenuDivider(height: 1),
        PopupMenuItem<int>(
          value: i,
          enabled: ogeler[i].onTap != null,
          height: 38,
          child: Row(children: [
            if (ogeler[i].ikon != null) ...[
              Icon(ogeler[i].ikon, size: 17),
              const SizedBox(width: 10),
            ],
            Text(ogeler[i].etiket, style: const TextStyle(fontSize: 13.5)),
          ]),
        ),
      ],
    ],
  );
  if (secilen != null) ogeler[secilen].onTap?.call();
}
