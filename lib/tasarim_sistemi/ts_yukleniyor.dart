// lib/tasarim_sistemi/ts_yukleniyor.dart
import 'package:flutter/material.dart';
import 'ts_token.dart';
import '../uygulama/tema/uygulama_temasi.dart';

/// Tek yükleniyor göstergesi. `iskelet: true` ile liste kartı şeklinde
/// shimmer iskelet, aksi halde ortalanmış dönen gösterge çizer.
class TsYukleniyor extends StatelessWidget {
  final bool iskelet;
  final int iskeletSayisi;

  const TsYukleniyor({super.key, this.iskelet = false, this.iskeletSayisi = 6});

  @override
  Widget build(BuildContext context) {
    if (!iskelet) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      );
    }
    // Tema uzantısındaki hazır token — elle brightness kontrolü yerine
    // (uygulama_temasi.dart'ta shimmerBase/shimmerHighlight tanımlı).
    final baz = context.shimmerBase;
    Widget kart() => Container(
          height: 68,
          decoration: BoxDecoration(
            color: baz,
            borderRadius: BorderRadius.circular(TsRadius.lg),
          ),
        );
    const dolgu = EdgeInsets.symmetric(horizontal: TsBosluk.lg, vertical: TsBosluk.sm);
    // 🔴 DÜZELTME (2026-09-28, uygulama robotu buldu): iskelet her zaman bir
    // ListView'dı. Kaydırılabilir bir alanın İÇİNDE (ör. Rapor > Cari,
    // Rapor > Stok — ListView çocuğu olarak) kullanılınca yükseklik
    // sınırsız kaldığından "Vertical viewport was given unbounded height"
    // ile ekran düzeni çöküyordu (veri yüklenirken her açılışta). Yükseklik
    // sınırsızsa artık sabit bir sütun çiziliyor.
    return LayoutBuilder(builder: (context, c) {
      if (!c.hasBoundedHeight) {
        return Padding(
          padding: dolgu,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < iskeletSayisi; i++) ...[
              if (i > 0) const SizedBox(height: TsBosluk.sm),
              kart(),
            ],
          ]),
        );
      }
      return ListView.separated(
        padding: dolgu,
        itemCount: iskeletSayisi,
        separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
        itemBuilder: (_, __) => kart(),
      );
    });
  }
}
