// lib/uygulama/masaustu/masaustu_yan_menu.dart
//
// Windows masaüstü kabuğu: Hızlı Satış "Menü" paneli + geri şeridi.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/masa_modu_provider.dart';
import '../router/uygulama_router.dart';

class _Oge {
  final String ad, rota;
  final IconData ikon;
  const _Oge(this.ad, this.ikon, this.rota);
}

class _Grup {
  final String ad;
  final IconData ikon;
  final List<_Oge> ogeler;
  const _Grup(this.ad, this.ikon, this.ogeler);
}

const _gruplar = <_Grup>[
  _Grup('Satış', Icons.point_of_sale, [
    _Oge('Hızlı Satış', Icons.point_of_sale, '/satis'),
    _Oge('Satış Listesi', Icons.receipt_long, '/satis/liste'),
    _Oge('İadeler', Icons.undo, '/satis/iade'),
    _Oge('Toptan Satış', Icons.local_shipping_outlined, '/toptan/dashboard'),
    _Oge('Fiyat Grupları', Icons.storefront_outlined, '/toptan/fiyat-gruplari'),
  ]),
  _Grup('Ürün & Stok', Icons.inventory_2, [
    _Oge('Ürün Listesi', Icons.inventory_2, '/urun'),
    _Oge('Ürün Ekle', Icons.add_box, '/urun/ekle'),
    _Oge('Fiyat Gör', Icons.price_check_rounded, '/fiyat-gor'),
    _Oge('Stok Listesi', Icons.warehouse, '/stok'),
    _Oge('Stok Sayım', Icons.calculate, '/stok/sayim'),
    _Oge('Stok Hareket', Icons.swap_vert, '/stok/hareket'),
    _Oge('Depo Transfer', Icons.local_shipping, '/stok/transfer'),
    _Oge('Toplu İşlem', Icons.bolt_outlined, '/urun/toplu-islem'),
    _Oge('Toplu Fiyat', Icons.price_change_outlined, '/urun/toplu-fiyat'),
    _Oge('Kategoriler', Icons.category, '/urun/kategori'),
    _Oge('Markalar', Icons.branding_watermark, '/urun/marka'),
    _Oge('Birimler', Icons.straighten, '/birim'),
    _Oge('Lot/Seri Takibi', Icons.qr_code_2, '/lot'),
    _Oge('PLU Yönetimi', Icons.grid_view_rounded, '/urun/plu'),
    _Oge('Promosyonlar', Icons.local_offer, '/promosyon'),
  ]),
  _Grup('Masa & Restoran', Icons.table_restaurant, [
    _Oge('Masalar', Icons.table_restaurant, '/masa'),
    _Oge('Mutfak/Bar', Icons.soup_kitchen_outlined, '/mutfak'),
    _Oge('Rezervasyon', Icons.event_available, '/rezervasyon'),
    _Oge('Masa Raporu', Icons.assessment, '/masa-rapor'),
  ]),
  _Grup('Cari & Fatura', Icons.people, [
    _Oge('Cariler', Icons.people, '/cari'),
    _Oge('Cari Ekle', Icons.person_add, '/cari/ekle'),
    _Oge('Cari Hareket', Icons.history, '/cari/hareket'),
    _Oge('Tahsilat/Ödeme', Icons.payments, '/cari/tahsilat'),
    _Oge('Faturalar', Icons.receipt, '/fatura'),
    _Oge('Fatura Oluştur', Icons.add, '/fatura/yeni'),
    _Oge('İrsaliye', Icons.local_shipping, '/irsaliye'),
  ]),
  _Grup('Finans', Icons.account_balance, [
    _Oge('Kasa', Icons.account_balance, '/kasa'),
    _Oge('Kasa Hareket', Icons.history, '/kasa/hareket'),
    _Oge('Virman', Icons.swap_horiz, '/kasa/virman'),
    _Oge('Giderler', Icons.money_off, '/gider'),
    _Oge('Banka Yönetimi', Icons.business, '/banka'),
    _Oge('Banka Hareketleri', Icons.history, '/banka-hareket'),
    _Oge('Kredi Kartları', Icons.credit_card, '/kredi-karti'),
    _Oge('Borç Takip', Icons.payment, '/borc-dashboard'),
    _Oge('Finans Merkezi', Icons.analytics_outlined, '/finans'),
  ]),
  _Grup('Raporlar', Icons.bar_chart, [
    _Oge('Günlük Rapor', Icons.assessment, '/rapor/gunluk'),
    _Oge('Satış Raporu', Icons.timeline, '/rapor/satis'),
    _Oge('Kâr / Zarar', Icons.trending_up, '/rapor/kar'),
    _Oge('Kasa Raporu', Icons.account_balance_wallet, '/kasa/rapor'),
    _Oge('Stok Raporu', Icons.inventory_2, '/rapor/stok'),
    _Oge('Cari Raporu', Icons.people, '/rapor/cari'),
    _Oge('ABC Stok Analizi', Icons.pie_chart_outline, '/rapor/abc-analiz'),
    _Oge('Stok Devir Analizi', Icons.autorenew, '/rapor/stok-devir'),
    _Oge('Fiyat Simülasyonu', Icons.calculate_outlined, '/urun/fiyat-simulasyon'),
    _Oge('AI Analiz', Icons.auto_graph, '/ai'),
    _Oge('Onay Merkezi', Icons.verified_user_outlined, '/onay-merkezi'),
    _Oge('Risk Merkezi', Icons.shield_outlined, '/risk-merkezi'),
  ]),
  _Grup('Tedarik & Alım', Icons.shopping_cart, [
    _Oge('Tedarikçi Sipariş', Icons.shopping_cart_outlined, '/tedarik'),
    _Oge('Mal Alımı', Icons.shopping_cart, '/tedarik/alim'),
    _Oge('Satın Alma Önerileri', Icons.lightbulb_outline, '/tedarik/oneriler'),
    _Oge('Tedarikçi Performansı', Icons.local_shipping_outlined, '/rapor/tedarikci-performans'),
  ]),
  _Grup('Barkod & Etiket', Icons.qr_code_2, [
    _Oge('Etiket Yazdır', Icons.qr_code_2, '/barkod/etiket'),
    _Oge('Barkod Üreteci', Icons.qr_code, '/barkod/uret'),
  ]),
  _Grup('Sistem', Icons.settings, [
    _Oge('Ayarlar', Icons.settings, '/ayarlar'),
    _Oge('Yazıcı Ayarları', Icons.print, '/ayarlar/yazici'),
    _Oge('Yedekleme', Icons.backup, '/ayarlar/yedek'),
    _Oge('Kullanıcılar', Icons.people, '/kullanici'),
    _Oge('Personel', Icons.badge_outlined, '/personel'),
    _Oge('Şubeler', Icons.store, '/sube'),
    _Oge('Vardiya', Icons.access_time, '/vardiya'),
    _Oge('Bildirimler', Icons.notifications, '/bildirimler'),
    _Oge('Sistem Logları', Icons.history, '/ayarlar/log'),
    _Oge('GİB e-Fatura', Icons.receipt, '/ayarlar/gib'),
    _Oge('Fatura Ayarları', Icons.description, '/ayarlar/fatura'),
    _Oge('Fiş Tasarımı', Icons.receipt_outlined, '/ayarlar/fis'),
    _Oge('Bulut Senkronizasyon', Icons.cloud_sync, '/ayarlar/bulut-sync'),
    _Oge('Kullanıcı Değiştir', Icons.swap_horiz, '/kullanici-degistir'),
  ]),
];

/// Geçerli adres. push ile açılan ekranlarda uri.path değişmediğinden son
/// eşleşmeye bakılır; liste boşsa (açılış anı) uri'ye düşülür.
String mevcutRota(GoRouter router) {
  final c = router.routerDelegate.currentConfiguration;
  return c.isEmpty ? c.uri.path : c.last.matchedLocation;
}

const _masaRotalari = {'/masa', '/mutfak', '/rezervasyon', '/masa-rapor'};
const _menusuzRotalar = ['/splash', '/giris', '/sifre'];

/// Windows kabuğu: kalıcı menü YOK. Sadece ana ekran ('/') ve Hızlı Satış
/// ('/satis') dışındaki, geri dönüşü olmayan ekranlarda ince bir "Geri"
/// şeridi gösterir (Windows'ta donanım geri tuşu yok).
class MasaustuKabuk extends ConsumerStatefulWidget {
  final Widget icerik;
  const MasaustuKabuk({super.key, required this.icerik});

  @override
  ConsumerState<MasaustuKabuk> createState() => _MasaustuKabukState();
}

class _MasaustuKabukState extends ConsumerState<MasaustuKabuk> {
  // Router bildirimi build sırasında gelebilir (ilk açılış); setState'i
  // kare sonrasına erteleyen ara bildirici.
  final _rotaTik = ValueNotifier<int>(0);
  late final GoRouter _router;

  Widget get icerik => widget.icerik;

  @override
  void initState() {
    super.initState();
    _router = UygulamaRouter.router(ref);
    _router.routerDelegate.addListener(_rotaDegisti);
  }

  void _rotaDegisti() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rotaTik.value++;
    });
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_rotaDegisti);
    _rotaTik.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    return ListenableBuilder(
      listenable: _rotaTik,
      builder: (context, _) {
        final rota = mevcutRota(router);
        final kok = rota == '/panel' || rota == '/satis';
        if (kok || _menusuzRotalar.any(rota.startsWith)) return icerik;
        final cs = Theme.of(context).colorScheme;
        void geri() {
          if (router.canPop()) {
            router.pop();
          } else {
            router.go('/satis');
          }
        }
        return Column(children: [
          Material(
            color: cs.surfaceContainerHighest,
            child: SizedBox(
              height: 40,
              child: Theme(
                data: Theme.of(context).copyWith(
                    textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(foregroundColor: cs.onSurface))),
                child: Row(children: [
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: geri,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Geri'),
                ),
                TextButton.icon(
                  onPressed: () {
                    final c = rootNavigatorKey.currentContext;
                    if (c != null) masaustuMenuAc(c);
                  },
                  icon: const Icon(Icons.menu, size: 18),
                  label: const Text('Menü'),
                ),
                TextButton.icon(
                  onPressed: () => router.go('/panel'),
                  icon: const Icon(Icons.dashboard_outlined, size: 18),
                  label: const Text('Ana Ekran'),
                ),
              ]),
              ),
            ),
          ),
          Expanded(child: icerik),
        ]);
      },
    );
  }
}
/// Hızlı Satış'taki "Menü" butonu: kategorili tüm modül listesini soldan
/// açılan bir panelde gösterir. Seçilen ekran ÜSTE açılır (push), böylece
/// kendi geri okuyla Hızlı Satış'a dönülür.
Future<void> masaustuMenuAc(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Menü',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (ctx, _, __) => Align(
      alignment: Alignment.centerLeft,
      child: Material(
        elevation: 8,
        child: SizedBox(width: 280, height: double.infinity, child: _MenuPaneli()),
      ),
    ),
  );
}

class _MenuPaneli extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final masaModu = ref.watch(masaModuProvider);
    final grupler = _gruplar
        .map((g) => _Grup(
            g.ad,
            g.ikon,
            g.ogeler
                .where((o) => masaModu || !_masaRotalari.contains(o.rota))
                .toList()))
        .where((g) => g.ogeler.isNotEmpty)
        .toList();

    void git(String rota) {
      Navigator.of(context).pop();
      GoRouter.of(rootNavigatorKey.currentContext ?? context).push(rota);
    }

    return Column(children: [
      const SizedBox(height: 8),
      ListTile(
        leading: const Icon(Icons.close),
        title: const Text('Menü', style: TextStyle(fontWeight: FontWeight.w700)),
        onTap: () => Navigator.of(context).pop(),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView(children: [
          for (final g in grupler)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                leading: Icon(g.ikon, size: 20),
                title: Text(g.ad,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                childrenPadding: EdgeInsets.zero,
                children: [
                  for (final o in g.ogeler)
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.only(left: 28, right: 8),
                      leading: Icon(o.ikon, size: 18, color: cs.primary),
                      title: Text(o.ad, style: const TextStyle(fontSize: 13)),
                      onTap: () => git(o.rota),
                    ),
                ],
              ),
            ),
        ]),
      ),
    ]);
  }
}
