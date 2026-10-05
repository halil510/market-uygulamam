// lib/ekranlar/satis/masaustu/masaustu_sayi_tuslari.dart
//
// Masaüstü Hızlı Satış — sayı tuş takımı (dokunmatik/fare).
//   0-9 , ⌫ C  : tampon girişi
//   ×          : tamponu, seçili sepet satırının MİKTARI yap
//   =          : tamponu "alınan para" yap (para üstü hesabı)
//   5…200      : hızlı para (alınan paraya EKLENİR — banknot banknot)
import 'package:flutter/material.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';

class MasaustuSayiTuslari extends StatelessWidget {
  final String tampon;
  final ValueChanged<String> onKarakter; // '0'-'9' veya ','
  final VoidCallback onGeri;
  final VoidCallback onTemizle;
  final VoidCallback onMiktar; // ×
  final VoidCallback onAlinan; // =
  final ValueChanged<int> onHizliPara;
  final VoidCallback onFiyatGor;

  const MasaustuSayiTuslari({
    super.key,
    required this.tampon,
    required this.onKarakter,
    required this.onGeri,
    required this.onTemizle,
    required this.onMiktar,
    required this.onAlinan,
    required this.onHizliPara,
    required this.onFiyatGor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(children: [
        // Tampon ekranı
        Container(
          width: double.infinity,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerRight,
          decoration: BoxDecoration(
            color: context.cardBg,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(tampon.isEmpty ? '0' : tampon,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: tampon.isEmpty ? context.textHint : context.textPrimary)),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(children: [
            // Hızlı para sütunu
            SizedBox(
              width: 58,
              child: Column(children: [
                for (final p in const [5, 10, 20, 50, 100, 200])
                  Expanded(
                      child: _tus('$p', () => onHizliPara(p),
                          renk: TsRenk.basarili,
                          yaziRenk: Colors.white)),
              ]),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(children: [
                _sira([
                  _tus('×', onMiktar, renk: TsRenk.uyari, yaziRenk: Colors.white),
                  _tus('=', onAlinan, renk: TsRenk.uyari, yaziRenk: Colors.white),
                  _tus('⌫', onGeri),
                ]),
                _sira([for (final r in const ['7', '8', '9']) _tus(r, () => onKarakter(r))]),
                _sira([for (final r in const ['4', '5', '6']) _tus(r, () => onKarakter(r))]),
                _sira([for (final r in const ['1', '2', '3']) _tus(r, () => onKarakter(r))]),
                _sira([
                  _tus('0', () => onKarakter('0')),
                  _tus(',', () => onKarakter(',')),
                  _tus('C', onTemizle, renk: TsRenk.hata, yaziRenk: Colors.white),
                ]),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _tus('FİYAT GÖR', onFiyatGor,
                        renk: TsRenk.primary, yaziRenk: Colors.white, yazi: 13),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _sira(List<Widget> cocuklar) => Expanded(
        child: Row(children: [
          for (final c in cocuklar) Expanded(child: c),
        ]),
      );

  Widget _tus(String etiket, VoidCallback onTap,
      {Color? renk, Color yaziRenk = const Color(0xFF263238), double yazi = 18}) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Builder(builder: (context) {
        return Material(
          color: renk ?? context.cardBg,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Container(
              alignment: Alignment.center,
              decoration: renk == null
                  ? BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(6))
                  : null,
              child: Text(etiket,
                  style: TextStyle(
                      fontSize: yazi,
                      fontWeight: FontWeight.w800,
                      color: renk == null ? context.textPrimary : yaziRenk)),
            ),
          ),
        );
      }),
    );
  }
}
