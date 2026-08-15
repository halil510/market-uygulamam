// lib/widgetlar/ortak/hata_widget.dart
// Geriye dönük uyumluluk sarmalayıcısı — gerçek görünüm artık
// lib/tasarim_sistemi/ts_bos_durum.dart (TsBosDurum) içinde tanımlı.
import 'package:flutter/material.dart';
import '../../tasarim_sistemi/ts_bos_durum.dart';
import '../../tasarim_sistemi/ts_token.dart';

class HataWidget extends StatelessWidget {
  final String mesaj;
  final VoidCallback? onYenidenDene;
  final IconData ikon;

  const HataWidget({
    super.key,
    this.mesaj = 'Bir hata oluştu',
    this.onYenidenDene,
    this.ikon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) => TsBosDurum(
        ikon: ikon,
        baslik: mesaj,
        renk: TsRenk.hata,
        aksiyonMetni: onYenidenDene != null ? 'Yeniden Dene' : null,
        aksiyon: onYenidenDene,
      );
}
