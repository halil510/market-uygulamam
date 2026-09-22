// lib/ekranlar/borc/borc_dashboard_tabs.dart
// borc_dashboard_ekrani.dart'ın parçası — 4 sekme (Genel Bakış, Aktif
// Borçlar, Ödenenler, Banka Hesapları) (god-class sertleştirmesi,
// 2026-09-22). Davranış birebir korundu.
part of 'borc_dashboard_ekrani.dart';

// ─── TAB 0: Genel Bakış ───────────────────────────────────────────────────────

class _GenelBakisTab extends StatelessWidget {
  final AsyncValue<BorcDashboardVeri> dashAsync;
  final AsyncValue<List<BankaHesapModel>> bankaHesaplariAsync;
  final void Function(BorcModel) onOde;

  const _GenelBakisTab({
    required this.dashAsync,
    required this.bankaHesaplariAsync,
    required this.onOde,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dashAsync.when(
            loading: () => const TsYukleniyor(),
            error: (e, _) => _HataKart(mesaj: e.toString()),
            data: (v) => _OzetKartlari(ozet: v.ozet),
          ),
          const SizedBox(height: 20),

          // ─── Gecikmiş Borçlar ──────────────────────────────────────
          dashAsync.when(
            loading: () => const SizedBox(),
            error: (e, __) => _HataKart(mesaj: 'Yüklenemedi: $e'),
            data: (v) {
              if (v.gecmis.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BolumBaslik(baslik: 'Gecikmiş Borçlar', ikon: Icons.error_outline_rounded, renkli: true),
                  const SizedBox(height: 8),
                  ...v.gecmis.take(5).map((b) => _BorcKartModern(
                    borc: b,
                    onOde: onOde,
                    onDetay: () => context.push('/borc-detay/${b.id}'),
                  )),
                  const SizedBox(height: 12),
                ],
              );
            },
          ),

          // ─── Yaklaşan Borçlar ──────────────────────────────────────
          dashAsync.when(
            loading: () => const SizedBox(),
            error: (e, __) => _HataKart(mesaj: 'Yüklenemedi: $e'),
            data: (v) {
              if (v.yaklasan.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BolumBaslik(baslik: 'Bu Hafta Yaklaşanlar', ikon: Icons.schedule_rounded, sayi: v.yaklasan.length),
                  const SizedBox(height: 8),
                  ...v.yaklasan.map((b) => _BorcKartModern(
                    borc: b,
                    onOde: onOde,
                    onDetay: () => context.push('/borc-detay/${b.id}'),
                  )),
                ],
              );
            },
          ),

          const SizedBox(height: 8),

          // ─── Diğer Aktif Borçlar ─────────────────────────────────────
          // Gecikmiş VEYA bu hafta içinde vadesi gelen değil ama hâlâ
          // ödenmemiş borçlar — önceden bu ekranda HİÇBİR YERDE
          // gösterilmiyordu (sadece "Aktif Borçlar" sekmesinde vardı),
          // bu yüzden kullanıcı "Genel Bakış"ta eklediği bir borcu
          // göremiyordu. Artık burada da listeleniyor.
          dashAsync.when(
            loading: () => const SizedBox(),
            error: (e, __) => const SizedBox(),
            data: (v) {
              final gecmisIdler = v.gecmis.map((b) => b.id).toSet();
              final yaklasanIdler = v.yaklasan.map((b) => b.id).toSet();
              final diger = v.tumBorclar.where((b) =>
                  !b.odendi &&
                  !gecmisIdler.contains(b.id) &&
                  !yaklasanIdler.contains(b.id)).toList();
              if (diger.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BolumBaslik(baslik: 'Diğer Aktif Borçlar', ikon: Icons.list_alt_rounded, sayi: diger.length),
                  const SizedBox(height: 8),
                  ...diger.map((b) {
                    // TANI AMAÇLI: "rozet 2 diyor ama 1 kart görünüyor"
                    // şikayetini kesin teşhis etmek için — her borç burada
                    // Sistem Logları'na kaydediliyor. Log'da 2 kayıt
                    // görünüyorsa ama ekranda 1 kart varsa sorun GÖRÜNTÜLEME
                    // katmanında; log'da da sadece 1 kayıt varsa sorun VERİ
                    // katmanındadır (borç hiç kaydedilmemiş/yanlış
                    // filtrelenmiş demektir).
                    LogServisi().bilgi(
                        'BorcDashboard.digerListesi: id=${b.id} baslik="${b.baslik}" '
                        'tur=${b.tur} kalan=${b.kalanTutar} odendi=${b.odendi}');
                    return _BorcKartModern(
                      borc: b,
                      onOde: onOde,
                      onDetay: () => context.push('/borc-detay/${b.id}'),
                    );
                  }),
                  const SizedBox(height: 12),
                ],
              );
            },
          ),

          // ─── Kredi Kartları (gerçek kart limiti kullanımı) ──────────
          dashAsync.when(
            loading: () => const SizedBox(),
            error: (e, __) => _HataKart(mesaj: 'Yüklenemedi: $e'),
            data: (v) {
              if (v.krediKartlari.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BolumBaslik(
                    baslik: 'Kredi Kartları',
                    ikon: Icons.credit_card_rounded,
                    sayi: v.krediKartlari.length,
                  ),
                  const SizedBox(height: 8),
                  ...v.krediKartlari.map((k) => _KrediKartiKart(kart: k)),
                  const SizedBox(height: 12),
                ],
              );
            },
          ),

          // ─── Banka Hesapları Özeti ─────────────────────────────────
          const _BolumBaslik(baslik: 'Banka Hesapları', ikon: Icons.account_balance_rounded),
          const SizedBox(height: 8),
          bankaHesaplariAsync.when(
            loading: () => const TsYukleniyor(),
            error: (_, __) => const _HataKart(mesaj: 'Banka hesapları yüklenemedi'),
            data: (hesaplar) {
              if (hesaplar.isEmpty) {
                return _BosKart(
                  mesaj: 'Henüz banka hesabı eklenmedi',
                  ikon: Icons.account_balance_outlined,
                  butonYazisi: 'Hesap Ekle',
                  onTap: () => context.push('/banka'),
                );
              }
              return Column(
                children: hesaplar.take(4).map((h) => _BankaHesapKartOzet(hesap: h)).toList(),
              );
            },
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─── TAB 1: Aktif Borçlar ─────────────────────────────────────────────────────

class _AktifBorcListeTab extends ConsumerWidget {
  final void Function(BorcModel) onOde;
  const _AktifBorcListeTab({required this.onOde});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final borclarAsync = ref.watch(aktifBorclarProvider);

    return borclarAsync.when(
      loading: () => const TsYukleniyor(),
      error: (e, _) => _HataKart(mesaj: e.toString()),
      data: (borclar) {
        if (borclar.isEmpty) {
          return _BosKart(
            mesaj: 'Aktif borç bulunmuyor',
            ikon: Icons.check_circle_outline_rounded,
            butonYazisi: 'Borç Ekle',
            onTap: () async {
              final eklendi = await context.push<bool>('/borc-ekle');
              if (eklendi == true) {
                ref.invalidate(aktifBorclarProvider);
                ref.invalidate(borcDashboardProvider);
              }
            },
          );
        }

        final Map<String, List<BorcModel>> gruplar = {};
        for (final b in borclar) {
          final tur = _turEtiketi(b.tur);
          gruplar.putIfAbsent(tur, () => []).add(b);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final entry in gruplar.entries) ...[
              _BolumBaslik(
                baslik: entry.key,
                ikon: _turIkonu(entry.value.first.tur),
                sayi: entry.value.length,
              ),
              const SizedBox(height: 6),
              ...entry.value.map((b) => _BorcKartModern(
                borc: b,
                onOde: onOde,
                onDetay: () => context.push('/borc-detay/${b.id}'),
              )),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 60),
          ],
        );
      },
    );
  }

  String _turEtiketi(String tur) {
    const map = {
      'kredi_karti': 'Kredi Kartı (Manuel Kayıt)',
      'vergi': 'Vergi',
      'sgk': 'SGK',
      'stopaj': 'Stopaj',
      'kira': 'Kira',
      'fatura': 'Fatura',
    };
    return map[tur] ?? 'Diğer';
  }

  IconData _turIkonu(String tur) {
    const map = {
      'kredi_karti': Icons.credit_card_rounded,
      'vergi': Icons.receipt_long_rounded,
      'sgk': Icons.local_hospital_outlined,
      'stopaj': Icons.bar_chart_rounded,
      'kira': Icons.home_outlined,
      'fatura': Icons.description_outlined,
    };
    return map[tur] ?? Icons.label_outline_rounded;
  }
}

// ─── TAB 2: Ödenenler ─────────────────────────────────────────────────────────

class _OdenenBorcListeTab extends ConsumerWidget {
  const _OdenenBorcListeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final odenenAsync = ref.watch(odenenBorclarProvider);

    return odenenAsync.when(
      loading: () => const TsYukleniyor(),
      error: (e, _) => _HataKart(mesaj: e.toString()),
      data: (borclar) {
        if (borclar.isEmpty) {
          return const TsBosDurum(
            ikon: Icons.hourglass_empty_rounded,
            baslik: 'Henüz ödenmiş borç yok',
          );
        }

        // Ödeme tarihine göre en yeni en üstte
        final siraliBorclar = [...borclar]
          ..sort((a, b) => (b.odemeTarihi ?? b.sonOdemeTarihi)
              .compareTo(a.odemeTarihi ?? a.sonOdemeTarihi));

        final toplamOdenen = borclar.fold<double>(0, (s, b) => s + b.tutar);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TsKart(
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: TsRenk.basarili),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${borclar.length} borç ödendi',
                          style: TsMetin.govdeVurgu.copyWith(color: TsRenk.basarili)),
                      Text('Toplam: ${ParaUtils.formatla(toplamOdenen)}',
                          style: TsMetin.kucuk.copyWith(color: TsRenk.basarili)),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            ...siraliBorclar.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OdenenBorcKart(
                borc: b,
                onDetay: () => context.push('/borc-detay/${b.id}'),
              ),
            )),
            const SizedBox(height: 60),
          ],
        );
      },
    );
  }
}

// ─── TAB 3: Banka Hesapları ───────────────────────────────────────────────────

class _BankaHesaplariTab extends ConsumerWidget {
  final AsyncValue<List<BankaHesapModel>> bankaHesaplariAsync;
  const _BankaHesaplariTab({required this.bankaHesaplariAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return bankaHesaplariAsync.when(
      loading: () => const TsYukleniyor(),
      error: (e, _) => _HataKart(mesaj: e.toString()),
      data: (hesaplar) {
        if (hesaplar.isEmpty) {
          return _BosKart(
            mesaj: 'Henüz banka hesabı eklenmedi',
            ikon: Icons.account_balance_outlined,
            butonYazisi: 'Hesap Ekle',
            onTap: () => context.push('/banka'),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TotalBakiyeBanner(hesaplar: hesaplar),
            const SizedBox(height: 16),
            ...hesaplar.map((h) => _BankaHesapKartDetayli(
              hesap: h,
              onTap: () => context.push('/banka-hareket', extra: {'hesapId': h.id}),
              onHareketEkle: () => context.push('/banka-hareket', extra: {'hesapId': h.id}),
            )),
            const SizedBox(height: 80),
          ],
        );
      },
    );
  }
}
