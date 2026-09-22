// lib/ekranlar/borc/borc_dashboard_banka_widgets.dart
// borc_dashboard_ekrani.dart'ın parçası — banka hesabı kartları (god-class
// sertleştirmesi, 2026-09-22). Davranış birebir korundu.
part of 'borc_dashboard_ekrani.dart';

// ─── Banka Hesap Kartları ─────────────────────────────────────────────────────

class _BankaHesapKartOzet extends StatelessWidget {
  final BankaHesapModel hesap;
  const _BankaHesapKartOzet({required this.hesap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TsKart.liste(
        ikon: const Icon(Icons.account_balance_rounded, color: Colors.blue),
        baslik: hesap.hesapAdi,
        altBaslik: hesap.hesapNo,
        sagAksiyon: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(ParaUtils.formatla(hesap.bakiye),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: hesap.bakiye >= 0 ? Colors.green : Colors.red)),
            Text(hesap.paraBirimi, style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
          ],
        ),
      ),
    );
  }
}

class _BankaHesapKartDetayli extends StatelessWidget {
  final BankaHesapModel hesap;
  final VoidCallback onTap;
  final VoidCallback onHareketEkle;

  const _BankaHesapKartDetayli({
    required this.hesap,
    required this.onTap,
    required this.onHareketEkle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TsKart(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [TsRenk.primaryKoyu, TsRenk.primary]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hesap.hesapAdi,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      if (hesap.hesapTuru != null)
                        Text(hesap.hesapTuru!,
                            style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                    ],
                  ),
                ),
                TsYetkili(child: IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: TsRenk.primaryKoyu),
                  onPressed: onHareketEkle,
                  tooltip: 'Hareket Ekle',
                )),
              ]),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BakiyeKolonu('Bakiye', hesap.bakiye),
                  _BakiyeKolonu('Kullanılabilir', hesap.kullanilabilirBakiye),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('IBAN', style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
                      Text(
                        hesap.iban != null && hesap.iban!.length >= 4
                            ? '...${hesap.iban!.substring(hesap.iban!.length - 4)}'
                            : hesap.hesapNo,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
      ),
    );
  }
}

class _BakiyeKolonu extends StatelessWidget {
  final String etiket;
  final double deger;
  const _BakiyeKolonu(this.etiket, this.deger);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiket, style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
        Text(
          ParaUtils.formatla(deger),
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: deger >= 0 ? Colors.green.shade700 : Colors.red),
        ),
      ],
    );
  }
}

// ─── Toplam Bakiye Banner ─────────────────────────────────────────────────────

class _TotalBakiyeBanner extends StatelessWidget {
  final List<BankaHesapModel> hesaplar;
  const _TotalBakiyeBanner({required this.hesaplar});

  @override
  Widget build(BuildContext context) {
    final toplam = hesaplar.fold<double>(0, (s, h) => s + h.bakiye);
    final kullanilabilir = hesaplar.fold<double>(0, (s, h) => s + h.kullanilabilirBakiye);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0D1B6E), Color(0xFF283593)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 28),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Toplam Banka Bakiyesi',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
            Text(ParaUtils.formatla(toplam),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('Kullanılabilir', style: TextStyle(color: Colors.white60, fontSize: 10)),
            Text(ParaUtils.formatla(kullanilabilir),
                style: const TextStyle(
                    color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ]),
    );
  }
}
