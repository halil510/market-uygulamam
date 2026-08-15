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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
          horizontal: TsBosluk.lg, vertical: TsBosluk.sm),
      itemCount: iskeletSayisi,
      separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
      itemBuilder: (_, __) => Container(
        height: 68,
        decoration: BoxDecoration(
          color: baz,
          borderRadius: BorderRadius.circular(TsRadius.lg),
        ),
      ),
    );
  }
}
