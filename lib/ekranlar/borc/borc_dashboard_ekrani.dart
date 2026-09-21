// lib/ekranlar/borc/borc_dashboard_ekrani.dart
// v4.0 – DÜZELTİLDİ:
//  1) Kredi kartları artık görünüyor (kredi_kartlari tablosundan
//     gerçek kullanılan limit borç olarak çekiliyor)
//  2) Ödenmiş borçlar artık listeleniyor (tumBorclarProvider düzeltildi,
//     "Ödenenler" sekmesi eklendi)
//  3) Banka hesapları aynı dashboard'da entegre, modern görünüm
//
// NOT: Bu ekran iki ayrı "kredi kartı borcu" kaynağını birleştirir:
//   a) borclar tablosu, tur='kredi_karti' → kullanıcının elle girdiği
//      kart ekstresi/son ödeme kaydı (taksit takibi, vade tarihi vb.)
//   b) kredi_kartlari tablosu → KrediKartiModel.kullanilanLimit,
//      bankalar ekranından eklenen GERÇEK kart limit kullanımı
//   İkisi farklı amaçlara hizmet ettiği için ayrı bölümlerde, açıkça
//   etiketlenerek gösterilir; aynı borç iki kez sayılmaz.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:market_plus/tasarim_sistemi/tasarim_sistemi.dart';
import '../../saglayicilar/riverpod/borc_provider.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../modeller/borc_model.dart';
import '../../modeller/banka_hesap_model.dart';
import '../../modeller/kredi_karti_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/log_servisi.dart';
import 'widgets/borc_odeme_bottom_sheet.dart';

// ─── ANA EKRAN ───────────────────────────────────────────────────────────────

class BorcDashboardEkrani extends ConsumerStatefulWidget {
  const BorcDashboardEkrani({super.key});

  @override
  ConsumerState<BorcDashboardEkrani> createState() => _BorcDashboardEkraniState();
}

class _BorcDashboardEkraniState extends ConsumerState<BorcDashboardEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _yenile() {
    ref.invalidate(borcDashboardProvider);
    ref.invalidate(borcOzetProvider);
    ref.invalidate(gecmisBorclarProvider);
    ref.invalidate(yaklasanBorclarProvider);
    ref.invalidate(tumBorclarProvider);
    ref.invalidate(aktifBorclarProvider);
    ref.invalidate(odenenBorclarProvider);
    ref.invalidate(tumKrediKartlariProvider);
    ref.invalidate(krediKartlariToplamProvider);
    ref.invalidate(bankaHesaplarProvider(null));
  }

  @override
  Widget build(BuildContext context) {
    final dashAsync = ref.watch(borcDashboardProvider);
    final bankaHesaplariAsync = ref.watch(bankaHesaplarProvider(null));

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerBoxScrolled) => [
          SliverAppBar(
            expandedHeight: 168,
            pinned: true,
            backgroundColor: TsModulRenk.koyu(TsModul.ana),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _yenile,
                tooltip: 'Yenile',
              ),
              TsYetkili(child: IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () async {
                  final eklendi = await context.push<bool>('/borc-ekle');
                  if (eklendi == true) _yenile();
                },
                tooltip: 'Borç Ekle',
              )),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeroHeader(dashAsync, bankaHesaplariAsync),
            ),
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [
                Tab(text: 'Genel Bakış', icon: Icon(Icons.dashboard_rounded, size: 16)),
                Tab(text: 'Aktif Borçlar', icon: Icon(Icons.pending_actions_rounded, size: 16)),
                Tab(text: 'Ödenenler', icon: Icon(Icons.check_circle_outline_rounded, size: 16)),
                Tab(text: 'Banka', icon: Icon(Icons.account_balance_rounded, size: 16)),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tab,
          children: [
            _GenelBakisTab(
              dashAsync: dashAsync,
              bankaHesaplariAsync: bankaHesaplariAsync,
              onOde: (borc) => _odemeDialogGoster(context, borc),
            ),
            _AktifBorcListeTab(
              onOde: (borc) => _odemeDialogGoster(context, borc),
            ),
            const _OdenenBorcListeTab(),
            _BankaHesaplariTab(bankaHesaplariAsync: bankaHesaplariAsync),
          ],
        ),
      ),
      floatingActionButton: TsYetkili(child: FloatingActionButton.extended(
        onPressed: () async {
          final eklendi = await context.push<bool>('/borc-ekle');
          if (eklendi == true) _yenile();
        },
        backgroundColor: TsRenk.primaryKoyu,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Borç Ekle'),
      )),
    );
  }

  Widget _buildHeroHeader(
    AsyncValue<BorcDashboardVeri> dashAsync,
    AsyncValue<List<BankaHesapModel>> bankaHesaplariAsync,
  ) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [TsRenk.primaryKoyu, TsRenk.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 56),
          child: Row(
            children: [
              Expanded(
                child: dashAsync.when(
                  loading: () => _heroSkeleton(),
                  error: (e, __) => _HataKart(mesaj: 'Yüklenemedi: $e'),
                  data: (v) => _heroKart(
                    'Toplam Borç (Kart Dahil)',
                    ParaUtils.formatla(v.ozet['kalan_borc'] ?? 0),
                    Icons.money_off_rounded,
                    Colors.orangeAccent,
                    alt: '${v.gecmis.length} gecikmiş • ${v.krediKartlari.length} kart',
                    altRenk: v.gecmis.isNotEmpty ? Colors.redAccent : Colors.white60,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: bankaHesaplariAsync.when(
                  loading: () => _heroSkeleton(),
                  error: (e, __) => _HataKart(mesaj: 'Yüklenemedi: $e'),
                  data: (hesaplar) {
                    final toplam = hesaplar.fold<double>(0, (s, h) => s + h.bakiye);
                    final kullanilabilir =
                        hesaplar.fold<double>(0, (s, h) => s + h.kullanilabilirBakiye);
                    return _heroKart(
                      'Banka Bakiyesi',
                      ParaUtils.formatla(toplam),
                      Icons.account_balance_rounded,
                      Colors.greenAccent,
                      alt: 'Kullanılabilir: ${ParaUtils.formatla(kullanilabilir)}',
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroKart(
    String baslik,
    String deger,
    IconData ikon,
    Color renk, {
    String? alt,
    Color? altRenk,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(ikon, color: renk, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(baslik,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 6),
          Text(deger,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
          if (alt != null) ...[
            const SizedBox(height: 2),
            Text(alt,
                style: TextStyle(color: altRenk ?? Colors.white60, fontSize: 10),
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  Widget _heroSkeleton() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Future<void> _odemeDialogGoster(BuildContext context, BorcModel borc) async {
    final bankaHesaplari = await ref.read(bankaHesaplarProvider(null).future);
    final krediKartlari = await ref.read(krediKartlariProvider(null).future);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BorcOdemeBottomSheet(
        borc: borc,
        bankaHesaplari: bankaHesaplari,
        krediKartlari: krediKartlari,
        onOdemeYapildi: () {
          _yenile();
          BildirimServisi.basari(context, '${borc.baslik} için ödeme kaydedildi ✓');
        },
      ),
    );
  }
}

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


// ─── Yardımcı Widgetlar ───────────────────────────────────────────────────────

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