// lib/ekranlar/borc/borc_dashboard_kartlar.dart
// borc_dashboard_ekrani.dart'ın parçası — özet kartları + borç kartı
// widget'ları (god-class sertleştirmesi, 2026-09-22). Davranış birebir
// korundu.
part of 'borc_dashboard_ekrani.dart';

// ─── Özet Kartları ────────────────────────────────────────────────────────────

class _OzetKartlari extends StatelessWidget {
  final Map<String, double> ozet;
  const _OzetKartlari({required this.ozet});

  @override
  Widget build(BuildContext context) {
    final items = [
      _OzetItem('Toplam Borç', ozet['toplam_borc'] ?? 0, Colors.indigo, Icons.summarize_rounded),
      _OzetItem('Ödenen (Manuel)', ozet['toplam_odenen'] ?? 0, Colors.green, Icons.check_circle_rounded),
      _OzetItem('Kalan', ozet['kalan_borc'] ?? 0, Colors.orange, Icons.pending_rounded),
      _OzetItem('Gecikmiş', ozet['gecmis_borc'] ?? 0, Colors.red, Icons.warning_rounded),
    ];

    return Column(children: [
      GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: items.map((item) => _OzetKartWidget(item: item)).toList(),
      ),
      const SizedBox(height: 10),
      // Kredi kartı borcu ayrı bir vurgu şeridi olarak — asimetrik 2'li
      // grid yerine tam genişlikte, kendi kimliğiyle gösteriliyor (kart
      // borcu, manuel borç takibinden farklı bir kaynaktan geliyor —
      // bkz. dosya başındaki açıklama).
      _OzetKartWidget(
        item: _OzetItem('Kredi Kartı Borcu', ozet['kredi_karti_borcu'] ?? 0,
            Colors.purple, Icons.credit_card_rounded),
        tamGenislik: true,
      ),
    ]);
  }
}

class _OzetItem {
  final String etiket;
  final double deger;
  final Color renk;
  final IconData ikon;
  const _OzetItem(this.etiket, this.deger, this.renk, this.ikon);
}

class _OzetKartWidget extends StatelessWidget {
  final _OzetItem item;
  final bool tamGenislik;
  const _OzetKartWidget({super.key, required this.item, this.tamGenislik = false});

  @override
  Widget build(BuildContext context) {
    if (tamGenislik) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: item.renk.withAlpha(20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.renk.withAlpha(51)),
        ),
        child: Row(children: [
          Icon(item.ikon, color: item.renk, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(item.etiket,
                style: TextStyle(fontSize: 13, color: item.renk, fontWeight: FontWeight.w600)),
          ),
          Text(
            ParaUtils.formatla(item.deger),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: item.renk),
          ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item.renk.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.renk.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(item.ikon, color: item.renk, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(item.etiket,
                  style: TextStyle(
                      fontSize: 11, color: item.renk, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          Text(
            ParaUtils.formatla(item.deger),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: item.renk),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Borç Kart (Modern) ───────────────────────────────────────────────────────

class _BorcKartModern extends StatelessWidget {
  final BorcModel borc;
  final void Function(BorcModel) onOde;
  final VoidCallback onDetay;

  const _BorcKartModern({
    required this.borc,
    required this.onOde,
    required this.onDetay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color accentRenk;
    if (borc.vadesiGecti) {
      accentRenk = Colors.red;
    } else if (borc.kritik) {
      accentRenk = Colors.orange;
    } else {
      accentRenk = Colors.blue;
    }

    // ÖNCEDEN BURADA CİDDİ, ARALIKLI (INTERMITTENT) BİR LAYOUT HATASI
    // VARDI: Dıştaki Row `crossAxisAlignment: stretch` kullanıyordu VE
    // içeride birden fazla `Spacer()` (=Expanded) belirsiz/iç içe
    // kısıtlar altında kullanılıyordu. `Spacer`, ana eksende SINIRLI bir
    // genişlik/yükseklik gerektirir — iç içe stretch+Expanded+Spacer
    // kombinasyonu bazı durumlarda Flutter'ın layout algoritmasını
    // kararsız bırakıp bir kartın sıfır yükseklikte "görünmez" render
    // olmasına yol açabiliyordu (kullanıcının "birini ödeyince diğeri
    // görünüyor" gözlemiyle birebir örtüşen bir belirti — liste bir
    // eksilince kalan kartın laycount'u değişip aniden görünür oluyordu).
    // Düzeltme: `IntrinsicHeight` ile net yükseklik + `Spacer()` yerine
    // `MainAxisAlignment.spaceBetween` (Expanded/Spacer'a hiç gerek
    // kalmadan) kullanılıyor.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TsKart(
        onTap: onDetay,
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accentRenk,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(TsRadius.lg),
                    bottomLeft: Radius.circular(TsRadius.lg),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(borc.baslik,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          _OncelikBadge(oncelik: borc.oncelik),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Kalan',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: TsRenk.metinIkincil(context))),
                                  Text(
                                    ParaUtils.formatla(borc.kalanTutar),
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: accentRenk),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Toplam',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: TsRenk.metinIkincil(context))),
                                  Text(ParaUtils.formatla(borc.tutar),
                                      style: const TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                          if (!borc.odendi)
                            FilledButton.icon(
                              onPressed: () => onOde(borc),
                              icon: const Icon(Icons.payment_rounded, size: 16),
                              label: const Text('Öde', style: TextStyle(fontSize: 12)),
                              style: FilledButton.styleFrom(
                                backgroundColor: accentRenk,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: TsRenk.zemin(TsRenk.basarili),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('✓ Ödendi',
                                  style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (borc.odemeOrani / 100).clamp(0, 1),
                          backgroundColor: accentRenk.withAlpha(38),
                          valueColor: AlwaysStoppedAnimation(accentRenk),
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 12, color: TsRenk.metinIkincil(context)),
                              const SizedBox(width: 4),
                              Text(
                                _tarihMetni(borc),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: borc.vadesiGecti ? Colors.red : TsRenk.metinIkincil(context)),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentRenk.withAlpha(26),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _turKisaEtiket(borc.tur),
                              style: TextStyle(fontSize: 10, color: accentRenk, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tarihMetni(BorcModel b) {
    final fmt = DateFormat('dd MMM yyyy', 'tr_TR');
    if (b.vadesiGecti) {
      final gun = DateTime.now().difference(b.sonOdemeTarihi).inDays;
      return '${gun}g gecikmiş (${fmt.format(b.sonOdemeTarihi)})';
    }
    final gun = b.kalanGun;
    return 'Son: ${fmt.format(b.sonOdemeTarihi)} ($gun gün)';
  }

  String _turKisaEtiket(String tur) {
    const map = {
      'kredi_karti': 'K.Kartı',
      'vergi': 'Vergi',
      'sgk': 'SGK',
      'stopaj': 'Stopaj',
      'kira': 'Kira',
      'fatura': 'Fatura',
    };
    return map[tur] ?? 'Diğer';
  }
}

// ─── Ödenen Borç Kart (sadeleştirilmiş, salt-okunur) ──────────────────────────

class _OdenenBorcKart extends StatelessWidget {
  final BorcModel borc;
  final VoidCallback onDetay;
  const _OdenenBorcKart({required this.borc, required this.onDetay});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy', 'tr_TR');
    return TsKart.liste(
      onTap: onDetay,
      ikon: Icon(Icons.check_circle_rounded, color: Colors.green.shade600),
      baslik: borc.baslik,
      altBaslik: borc.odemeTarihi != null
          ? 'Ödendi: ${fmt.format(borc.odemeTarihi!)}'
          : 'Son ödeme: ${fmt.format(borc.sonOdemeTarihi)}',
      deger: ParaUtils.formatla(borc.tutar),
    );
  }
}

class _OncelikBadge extends StatelessWidget {
  final int oncelik;
  const _OncelikBadge({required this.oncelik});

  @override
  Widget build(BuildContext context) {
    final (renk, etiket) = switch (oncelik) {
      1 => (Colors.red, 'Kritik'),
      2 => (Colors.orange, 'Orta'),
      _ => (context.textSecondary, 'Düşük'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: renk.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(etiket, style: TextStyle(fontSize: 9, color: renk, fontWeight: FontWeight.w700)),
    );
  }
}

// ─── Kredi Kartı Kart (kredi_kartlari tablosundan) ────────────────────────────

class _KrediKartiKart extends StatelessWidget {
  final KrediKartiModel kart;
  const _KrediKartiKart({required this.kart});

  @override
  Widget build(BuildContext context) {
    final doluluk = kart.kartLimit > 0
        ? (kart.kullanilanLimit / kart.kartLimit).clamp(0.0, 1.0)
        : 0.0;
    final renk = doluluk > 0.8
        ? Colors.red
        : doluluk > 0.5
            ? Colors.orange
            : Colors.indigo;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TsKart(
        onTap: () => context.push('/kredi-karti/detay/${kart.id}'),
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: renk,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(TsRadius.lg),
                    bottomLeft: Radius.circular(TsRadius.lg),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.credit_card_rounded, color: renk, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(kart.kartAdi,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (kart.sonOdemeTarihi != null)
                          Text(
                            DateFormat('dd MMM', 'tr_TR').format(kart.sonOdemeTarihi!),
                            style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
                          ),
                      ]),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Kullanılan', style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
                                  Text(ParaUtils.formatla(kart.kullanilanLimit),
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: renk)),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Limit', style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
                                  Text(ParaUtils.formatla(kart.kartLimit),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                          Text('%${(doluluk * 100).toStringAsFixed(0)}',
                              style: TextStyle(fontWeight: FontWeight.w700, color: renk, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: doluluk,
                          backgroundColor: renk.withAlpha(38),
                          valueColor: AlwaysStoppedAnimation(renk),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
