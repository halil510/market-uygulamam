// lib/ekranlar/borc/borc_dashboard_yardimcilar.dart
// borc_dashboard_ekrani.dart'ın parçası — küçük ortak yardımcı widget'lar
// (god-class sertleştirmesi, 2026-09-22). Davranış birebir korundu.
part of 'borc_dashboard_ekrani.dart';

class _BolumBaslik extends StatelessWidget {
  final String baslik;
  final IconData? ikon;
  final int? sayi;
  final bool renkli;

  const _BolumBaslik({required this.baslik, this.ikon, this.sayi, this.renkli = false});

  @override
  Widget build(BuildContext context) {
    final renk = renkli ? TsRenk.hata : TsRenk.metinIkincil(context);
    return Row(children: [
      if (ikon != null) ...[
        Icon(ikon, size: 16, color: renk),
        const SizedBox(width: 6),
      ],
      Text(baslik, style: TsMetin.baslikM.copyWith(
          color: renkli ? TsRenk.hata : TsRenk.metinBirincil(context))),
      if (sayi != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: renkli ? TsRenk.zemin(TsRenk.hata) : TsRenk.zemin(TsRenk.notr),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$sayi',
              style: TsMetin.kucukVurgu.copyWith(
                  color: renkli ? TsRenk.hata : TsRenk.metinIkincil(context))),
        ),
      ],
    ]);
  }
}

class _HataKart extends StatelessWidget {
  final String mesaj;
  const _HataKart({required this.mesaj});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TsBosluk.lg),
      child: TsBosDurum(
        ikon: Icons.error_outline,
        baslik: 'Bir hata oluştu',
        altyazi: mesaj,
        renk: TsRenk.hata,
      ),
    );
  }
}

class _BosKart extends StatelessWidget {
  final String mesaj;
  final IconData ikon;
  final String butonYazisi;
  final VoidCallback onTap;

  const _BosKart({
    required this.mesaj,
    required this.ikon,
    required this.butonYazisi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TsBosDurum(
      ikon: ikon,
      baslik: mesaj,
      aksiyonMetni: butonYazisi,
      aksiyon: onTap,
    );
  }
}
