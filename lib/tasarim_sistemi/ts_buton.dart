// lib/tasarim_sistemi/ts_buton.dart
import 'package:flutter/material.dart';
import 'ts_token.dart';

enum TsButonTuru { birincil, ikincil, tehlike, metin }

/// Tek buton bileşeni — birincil (dolu), ikincil (dış çizgili), tehlike
/// (kırmızı, silme/iptal işlemleri) ve metin (düz yazı) varyantları.
class TsButon extends StatelessWidget {
  final String metin;
  final VoidCallback? onPressed;
  final TsButonTuru tur;
  final IconData? ikon;
  final bool yukleniyor;
  final bool tamGenislik;

  const TsButon({
    super.key,
    required this.metin,
    required this.onPressed,
    this.tur = TsButonTuru.birincil,
    this.ikon,
    this.yukleniyor = false,
    this.tamGenislik = false,
  });

  const TsButon.tehlike({
    super.key,
    required this.metin,
    required this.onPressed,
    this.ikon,
    this.yukleniyor = false,
    this.tamGenislik = false,
  }) : tur = TsButonTuru.tehlike;

  @override
  Widget build(BuildContext context) {
    // 🔴 DÜZELTME: Spinner rengi TÜM buton türleri için sabit beyazdı —
    // 'ikincil' (çizgili, şeffaf zemin) ve 'metin' (düz yazı, şeffaf
    // zemin) türlerinde beyaz spinner neredeyse görünmezdi. Artık
    // dolu-zeminli türlerde (birincil/tehlike) beyaz, şeffaf-zeminli
    // türlerde (ikincil/metin) markanın rengiyle eşleşiyor.
    final spinnerRengi = (tur == TsButonTuru.ikincil || tur == TsButonTuru.metin)
        ? TsRenk.primary
        : Colors.white;
    final icerik = yukleniyor
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: spinnerRengi),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ikon != null) ...[
                Icon(ikon, size: 18),
                const SizedBox(width: TsBosluk.sm),
              ],
              Text(metin),
            ],
          );

    Widget child;
    switch (tur) {
      case TsButonTuru.birincil:
        child = FilledButton(onPressed: yukleniyor ? null : onPressed, child: icerik);
        break;
      case TsButonTuru.ikincil:
        child = OutlinedButton(onPressed: yukleniyor ? null : onPressed, child: icerik);
        break;
      case TsButonTuru.tehlike:
        child = FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
          onPressed: yukleniyor ? null : onPressed,
          child: icerik,
        );
        break;
      case TsButonTuru.metin:
        child = TextButton(onPressed: yukleniyor ? null : onPressed, child: icerik);
        break;
    }

    return tamGenislik ? SizedBox(width: double.infinity, child: child) : child;
  }
}
