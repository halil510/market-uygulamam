// lib/ekranlar/satis/widgets/sepet_kalem_karti.dart
import 'package:flutter/material.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../modeller/sepet_model.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../tasarim_sistemi/ts_token.dart';

class SepetKalemKarti extends StatelessWidget {
  final SepetKalem kalem;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSil;
  final VoidCallback onAzalt;
  final VoidCallback onArttir;
  final bool Function(String) kgMiMi;

  const SepetKalemKarti({
    super.key,
    required this.kalem,
    required this.index,
    required this.onTap,
    required this.onLongPress,
    required this.onSil,
    required this.onAzalt,
    required this.onArttir,
    required this.kgMiMi,
  });

  static const _primary   = Color(0xFF4361EE);
  static const _danger    = Color(0xFFE53935);
  static const _success   = Color(0xFF2E7D32);
  static const _orange    = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) {
    final k          = kalem;
    final normalFiyat = k.urun.satisFiyati;
    final indirimVar  = k.birimFiyat < normalFiyat - 0.001;
    final isKg        = kgMiMi(k.urun.birimAdi);
    final textPrimary = context.textPrimary;
    final textSec     = context.textSecondary;

    return RepaintBoundary(
      key: ValueKey('sepet_kalem_${k.urun.id}_$index'),
      child: Dismissible(
        key: ValueKey('dismiss_${k.urun.id}_$index'),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: _danger,
            borderRadius: BorderRadius.circular(TsRadius.lg),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
              SizedBox(height: 2),
              Text('Sil', style: TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        onDismissed: (_) => onSil(),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: context.cardBg,
            // Kullanıcı isteği: "Logo gibi profesyonel yazılımlar gibi
            // olsun." Aşırı yuvarlak/"balonlu" köşeler yerine daha
            // net, gridli/tablo hissi veren daha keskin köşeler.
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: indirimVar
                  ? const Color(0x33E65100)
                  : context.borderColor,
              width: indirimVar ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            onDoubleTap: onLongPress,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(children: [
                // ── Sol: harf kutusu kaldırıldı ──────────────────────────

                // ── Orta: isim + fiyat ─────────────────────────────────
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k.urun.urunAdi,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(children: [
                      if (isKg) ...[
                        Icon(Icons.scale_rounded,
                            size: 11, color: textSec),
                        const SizedBox(width: 3),
                      ],
                      if (indirimVar) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0x1AE65100),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '-%${((1 - k.birimFiyat / normalFiyat) * 100).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: _orange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        isKg
                            ? '${k.miktar.toStringAsFixed(3)} ${k.urun.birimAdi} × ${ParaUtils.formatla(k.birimFiyat)}'
                            : ParaUtils.formatla(k.birimFiyat),
                        style: TextStyle(
                          fontSize: 11,
                          color: indirimVar ? _orange : textSec,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (indirimVar) ...[
                        const SizedBox(width: 4),
                        Text(
                          ParaUtils.formatla(normalFiyat),
                          style: TextStyle(
                            fontSize: 10,
                            color: textSec,
                            decoration: TextDecoration.lineThrough,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ]),
                  ],
                )),

                // ── Sağ: miktar kontrol ────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? const Color(0xFF1C1F35)
                        : const Color(0xFFF0F3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    // Azalt
                    _MiktarButon(
                      icon: Icons.remove_rounded,
                      onTap: onAzalt,
                      renk: _danger,
                    ),
                    // Miktar
                    SizedBox(
                      width: 32,
                      child: Text(
                        isKg
                            ? k.miktar.toStringAsFixed(3)
                            : k.miktar == k.miktar.roundToDouble()
                                ? k.miktar.toInt().toString()
                                : k.miktar.toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    // Arttır
                    _MiktarButon(
                      icon: Icons.add_rounded,
                      onTap: onArttir,
                      renk: _success,
                    ),
                  ]),
                ),
                const SizedBox(width: 8),

                // ── Toplam tutar ───────────────────────────────────────
                SizedBox(
                  width: 64,
                  child: Text(
                    ParaUtils.formatla(k.toplamTutar),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: indirimVar ? _orange : _primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiktarButon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color renk;
  const _MiktarButon({
    required this.icon,
    required this.onTap,
    required this.renk,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: renk.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 15, color: renk),
      ),
    );
  }
}
