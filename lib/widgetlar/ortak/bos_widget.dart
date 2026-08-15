// lib/widgetlar/ortak/bos_widget.dart
// Geriye dönük uyumluluk sarmalayıcısı — gerçek görünüm artık
// lib/tasarim_sistemi/ts_bos_durum.dart (TsBosDurum) içinde tanımlı.
import 'package:flutter/material.dart';
import '../../tasarim_sistemi/ts_bos_durum.dart';

class BosWidget extends StatelessWidget {
  final String mesaj;
  final IconData ikon;
  final String? butonYazi;
  final VoidCallback? butonAksiyon;

  const BosWidget({
    super.key,
    this.mesaj = 'Henüz kayıt yok',
    this.ikon = Icons.inbox_outlined,
    this.butonYazi,
    this.butonAksiyon,
  });

  @override
  Widget build(BuildContext context) => TsBosDurum(
        ikon: ikon,
        baslik: mesaj,
        aksiyonMetni: butonYazi,
        aksiyon: butonAksiyon,
      );
}
