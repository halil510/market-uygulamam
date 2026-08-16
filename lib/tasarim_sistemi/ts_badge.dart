// lib/tasarim_sistemi/ts_badge.dart
import 'package:flutter/material.dart';
import 'ts_token.dart';

enum TsBadgeTuru { basarili, uyari, hata, bilgi, notr }

/// Tek durum rozeti — "Aktif", "Beklemede", "İptal", "Stokta yok" gibi
/// tüm durum etiketleri bu bileşenden üretilir.
class TsBadge extends StatelessWidget {
  final String metin;
  final TsBadgeTuru tur;
  final IconData? ikon;

  const TsBadge({super.key, required this.metin, this.tur = TsBadgeTuru.notr, this.ikon});

  const TsBadge.basarili(this.metin, {super.key, this.ikon}) : tur = TsBadgeTuru.basarili;
  const TsBadge.uyari(this.metin, {super.key, this.ikon}) : tur = TsBadgeTuru.uyari;
  const TsBadge.hata(this.metin, {super.key, this.ikon}) : tur = TsBadgeTuru.hata;

  Color get _renk {
    switch (tur) {
      case TsBadgeTuru.basarili:
        return TsRenk.basarili;
      case TsBadgeTuru.uyari:
        return TsRenk.uyari;
      case TsBadgeTuru.hata:
        return TsRenk.hata;
      case TsBadgeTuru.bilgi:
        return TsRenk.bilgi;
      case TsBadgeTuru.notr:
        return TsRenk.notr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final renk = _renk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: TsBosluk.sm, vertical: 3),
      decoration: BoxDecoration(
        color: TsRenk.zemin(renk),
        borderRadius: BorderRadius.circular(TsRadius.sm),
        border: Border.all(color: TsRenk.zemin(renk, opaklik: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ikon != null) ...[
            Icon(ikon, size: 11, color: renk),
            const SizedBox(width: 3),
          ],
          Text(metin, style: TsMetin.etiket.copyWith(color: renk)),
        ],
      ),
    );
  }
}
