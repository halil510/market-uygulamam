// lib/uygulama/masaustu/masaustu_yan_menu.dart
//
// Windows masaüstü kabuğu: tüm ekranların solunda kalıcı, kategorili menü
// (telefondaki alt çubuk + "Daha Fazla" yerine) ve üstünde Geri düğmesi.
// Menü uygulama genelinde (root navigator'ın üstünde) olduğundan, ayrı
// pencere olarak açılan ekranlarda da görünür ve geri dönüş her yerde var.
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

const _masaRotalari = {'/masa', '/mutfak', '/rezervasyon', '/masa-rapor'};
const _menusuzRotalar = ['/splash', '/giris', '/sifre'];

/// MaterialApp.router builder'ında [icerik] (Navigator) etrafına sarılır.
/// İçerik alanının genişliği menü düşülerek MediaQuery'ye yansıtılır.
class MasaustuKabuk extends ConsumerWidget {
  final Widget icerik;
  const MasaustuKabuk({super.key, required this.icerik});

  static const double menuGenislik = 240;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = UygulamaRouter.router(ref);
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) {
        final rota = router.routerDelegate.currentConfiguration.uri.path;
        if (_menusuzRotalar.any(rota.startsWith)) return icerik;
        final mq = MediaQuery.of(context);
        return Row(children: [
          _YanMenu(rota: rota, router: router),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: MediaQuery(
              data: mq.copyWith(
                  size: Size(mq.size.width - menuGenislik - 1, mq.size.height)),
              child: icerik,
            ),
          ),
        ]);
      },
    );
  }
}

class _YanMenu extends ConsumerWidget {
  final String rota;
  final GoRouter router;
  const _YanMenu({required this.rota, required this.router});

  void _geri() {
    final nav = rootNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else {
      router.go('/');
    }
  }

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

    return Material(
      color: cs.surface,
      child: SizedBox(
        width: MasaustuKabuk.menuGenislik,
        child: Column(children: [
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_back),
            title: const Text('Geri'),
            onTap: _geri,
          ),
          ListTile(
            dense: true,
            selected: rota == '/',
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text('Ana Ekran'),
            onTap: () => router.go('/'),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(children: [
              for (final g in grupler)
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: PageStorageKey('mk_${g.ad}'),
                    dense: true,
                    initiallyExpanded: g.ogeler.any((o) => o.rota == rota),
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
                          contentPadding:
                              const EdgeInsets.only(left: 28, right: 8),
                          selected: o.rota == rota,
                          selectedTileColor: cs.primaryContainer,
                          leading: Icon(o.ikon, size: 18),
                          title:
                              Text(o.ad, style: const TextStyle(fontSize: 13)),
                          onTap: () => router.go(o.rota),
                        ),
                    ],
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
