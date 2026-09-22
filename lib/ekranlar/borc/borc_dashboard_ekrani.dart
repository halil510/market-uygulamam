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

// God-class sertleştirmesi (2026-09-22, kullanıcı onayıyla): bu dosya
// 1370 satırdı. İçerik davranış DEĞİŞTİRİLMEDEN 4 parçaya ayrıldı —
// hepsi zaten bağımsız (State'e ihtiyaç duymayan) top-level widget
// sınıflarıydı, bu yüzden `part of` ile taşınıp doğrudan aynı sınıf
// tanımları olarak kalabildiler (extension sarmalamaya gerek yoktu):
//   - borc_dashboard_tabs.dart          → 4 sekme
//   - borc_dashboard_kartlar.dart       → özet/borç kartı widget'ları
//   - borc_dashboard_banka_widgets.dart → banka hesap kartları
//   - borc_dashboard_yardimcilar.dart   → küçük ortak yardımcılar
part 'borc_dashboard_tabs.dart';
part 'borc_dashboard_kartlar.dart';
part 'borc_dashboard_banka_widgets.dart';
part 'borc_dashboard_yardimcilar.dart';

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
