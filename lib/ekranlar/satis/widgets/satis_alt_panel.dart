// lib/ekranlar/satis/widgets/satis_alt_panel.dart
import 'package:flutter/material.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../saglayicilar/riverpod/sepet_provider.dart';
import '../../../cekirdek/utils/para_utils.dart';

class SatisAltPanel extends StatelessWidget {
  final SepetDurum sepet;
  final VoidCallback onOdeme;

  const SatisAltPanel({
    super.key,
    required this.sepet,
    required this.onOdeme,
  });

  @override
  Widget build(BuildContext context) {
    final bool bos = sepet.bos;

    return Container(
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            // ── Sol: tutar özeti ───────────────────────────────────────
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: bos
                          ? const Color(0x1A9E9E9E)
                          : const Color(0x1A4361EE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      bos
                          ? 'Sepet boş'
                          : '${sepet.toplamAdet} ürün • ${sepet.kalemler.length} çeşit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: bos
                            ? TsRenk.metinIkincil(context)
                            : const Color(0xFF4361EE),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                    ParaUtils.formatla(sepet.genelToplam),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: bos
                          ? TsRenk.metinIkincil(context)
                          : const Color(0xFF4361EE),
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (!bos && sepet.genelIskontoYuzde > 0) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.discount_outlined,
                        size: 11, color: Color(0xFFE65100)),
                    const SizedBox(width: 3),
                    Text(
                      '${sepet.genelIskontoYuzde.toStringAsFixed(0)}% genel indirim uygulandı',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ]),
                ],
              ],
            )),

            const SizedBox(width: 16),

            // ── Sağ: ödeme butonu ──────────────────────────────────────
            GestureDetector(
              onTap: bos ? null : onOdeme,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 58,
                width: 150,
                decoration: BoxDecoration(
                  gradient: bos
                      ? const LinearGradient(
                          colors: [Color(0xFFBDBDBD), Color(0xFF9E9E9E)])
                      : const LinearGradient(
                          colors: [TsRenk.primaryKoyu, TsRenk.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: bos
                      ? []
                      : [
                          const BoxShadow(
                            color: Color(0x664361EE),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                ),
                child: Center(
                  child: sepet.satisIsleniyor
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.payment_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Ödeme Al',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
