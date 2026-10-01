// lib/ekranlar/satis/masaustu/masaustu_f_tuslari.dart
//
// Masaüstü Hızlı Satış — renkli fonksiyon tuşları (F2, F3, F4 …).
// Hem fareyle tıklanır hem klavyedeki F tuşuyla tetiklenir (bkz. düzen dosyası).
import 'package:flutter/material.dart';

class FTus {
  final String tus; // 'F12'
  final String etiket; // 'Ödeme'
  final Color renk;
  final VoidCallback? onTap;
  const FTus(this.tus, this.etiket, this.renk, this.onTap);
}

class MasaustuFTuslari extends StatelessWidget {
  /// İlk tuş tam genişlikte, büyük gösterilir (Ödeme).
  final FTus ana;
  final List<FTus> tuslar;
  const MasaustuFTuslari({super.key, required this.ana, required this.tuslar});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buton(ana, yukseklik: 50, yazi: 16),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.9,
          children: [for (final t in tuslar) _buton(t)],
        ),
      ]),
    );
  }

  Widget _buton(FTus t, {double? yukseklik, double yazi = 12}) {
    final aktif = t.onTap != null;
    return SizedBox(
      height: yukseklik,
      width: double.infinity,
      child: Material(
        color: aktif ? t.renk : Color.lerp(t.renk, const Color(0xFF7B8794), 0.65),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: t.onTap,
          child: Center(
            child: Text(
              '${t.tus} : ${t.etiket}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: yazi,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}
