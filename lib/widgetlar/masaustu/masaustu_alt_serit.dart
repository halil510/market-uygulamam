// lib/widgetlar/masaustu/masaustu_alt_serit.dart
//
// Masaüstü liste ekranlarının alt şeridi (BarkoPOS düzeni):
//   sol: özet değerler (Çeşit Sayısı, Stok Miktarı, Toplam Borç …)
//   sağ: büyük renkli işlem butonları (F1 Ekle, F2 Düzenle, F3 Sil …)
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

class AltOzet {
  final String etiket;
  final String deger;
  final Color? renk;
  const AltOzet(this.etiket, this.deger, {this.renk});
}

class AltTus {
  final String tus; // 'F1'
  final String etiket; // 'Ekle'
  final IconData ikon;
  final Color renk;
  final VoidCallback? onTap;
  const AltTus(this.tus, this.etiket, this.ikon, this.renk, this.onTap);
}

class MasaustuAltSerit extends StatelessWidget {
  final List<AltOzet> ozetler;
  final List<AltTus> tuslar;
  const MasaustuAltSerit({super.key, required this.ozetler, required this.tuslar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: context.cardBg,
        border: Border(top: BorderSide(color: context.borderColor)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, -2)),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Wrap(spacing: 28, runSpacing: 4, children: [
            for (final o in ozetler)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.etiket,
                    style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
                Text(o.deger,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: o.renk ?? context.textPrimary)),
              ]),
          ]),
        ),
        for (final t in tuslar) _buton(t),
      ]),
    );
  }

  Widget _buton(AltTus t) {
    final aktif = t.onTap != null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        // Pasif: renk gri tona çekilir (yarı saydam yapmak beyaz yazıyı açık
        // zeminde okunmaz hale getiriyordu).
        color: aktif ? t.renk : Color.lerp(t.renk, const Color(0xFF7B8794), 0.65),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: t.onTap,
          child: SizedBox(
            width: 104,
            height: 52,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(t.ikon, color: Colors.white, size: 18),
              const SizedBox(height: 2),
              Text('${t.tus} : ${t.etiket}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    );
  }
}
