// lib/ekranlar/dashboard/dashboard_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../servisler/supabase_sync_servisi.dart';
import '../../veri/database/veritabani.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../saglayicilar/riverpod/dashboard_provider.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../saglayicilar/riverpod/masa_provider.dart';
import '../../saglayicilar/riverpod/masa_modu_provider.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../auth/kullanici_degistir_ekrani.dart';
import '../urun/fiyat_gor_ekrani.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../bildirim/bildirim_merkezi_ekrani.dart' show okunmamisSayiProvider;

// ──────────────────────────────────────────────────────────────────────────────
// ANA EKRANDA GÖSTERİLECEK BÜYÜK BUTONLAR
// ──────────────────────────────────────────────────────────────────────────────
class _AnaButon {
  final String ad;
  final IconData ikon;
  final Color renk;
  final String rota;
  const _AnaButon(this.ad, this.ikon, this.renk, this.rota);
}

const List<_AnaButon> _anaButonlar = [
  _AnaButon('Hızlı Satış', Icons.point_of_sale, Color(0xFF4361EE), '/satis'),
  _AnaButon('Ürün Listesi', Icons.inventory_2, Color(0xFF3F51B5), '/urun'),
  _AnaButon('Cariler', Icons.people, Color(0xFF0097A7), '/cari'),
  _AnaButon(
      'Satış Listesi', Icons.receipt_long, Color(0xFF00BCD4), '/satis/liste'),
  _AnaButon('Masalar', Icons.table_restaurant, Color(0xFF6D4C41), '/masa'),
  _AnaButon(
      'Mutfak/Bar', Icons.soup_kitchen_outlined, Color(0xFFE64A19), '/mutfak'),
  _AnaButon('İadeler', Icons.undo, Color(0xFFF57F17), '/satis/iade'),
  _AnaButon('Promosyon', Icons.local_offer, Color(0xFFE65100), '/promosyon'),
  _AnaButon('Raporlar', Icons.bar_chart, Color(0xFF1565C0), '/rapor/satis'),
  _AnaButon('Borç Takip', Icons.payment, Color(0xFFD32F2F), '/borc-dashboard'),
  _AnaButon('Finans', Icons.account_balance, Color(0xFF2E7D32), '/finans'),
  _AnaButon('Ayarlar', Icons.settings, Color(0xFF546E7A), '/ayarlar'),
];

// ──────────────────────────────────────────────────────────────────────────────
// TÜM UYGULAMALAR (Kategori Bazlı)
// ──────────────────────────────────────────────────────────────────────────────
class _UygulamaItem {
  final String ad, rota;
  final IconData ikon;
  final Color renk;
  const _UygulamaItem(this.ad, this.ikon, this.renk, this.rota);
}

class _Kategori {
  final String ad;
  final IconData ikon;
  final List<_UygulamaItem> uygulamalar;
  const _Kategori(this.ad, this.ikon, this.uygulamalar);
}

const List<_Kategori> _tumKategoriler = [
  _Kategori('Satış', Icons.point_of_sale, [
    _UygulamaItem(
        'Hızlı Satış', Icons.point_of_sale, Color(0xFF2196F3), '/satis'),
    _UygulamaItem(
        'Satış Listesi', Icons.receipt_long, Color(0xFF00BCD4), '/satis/liste'),
    _UygulamaItem('İadeler', Icons.undo, Color(0xFFF57F17), '/satis/iade'),
    _UygulamaItem('Sıcak Satış', Icons.local_fire_department, Color(0xFFB71C1C),
        '/satis/sicak'),
    _UygulamaItem(
        'Soğuk Satış', Icons.ac_unit, Color(0xFF1A237E), '/satis/soguk'),
    _UygulamaItem('Fiş Önizleme', Icons.receipt_outlined, Color(0xFF4CAF50),
        '/satis/fis-onizleme'),
    _UygulamaItem('Toptan Satış', Icons.local_shipping_outlined,
        Color(0xFF6D4C41), '/toptan/dashboard'),
    _UygulamaItem('Fiyat Grupları', Icons.storefront_outlined,
        Color(0xFF8D6E63), '/toptan/fiyat-gruplari'),
  ]),
  _Kategori('Ürün & Stok', Icons.inventory_2, [
    _UygulamaItem(
        'Ürün Listesi', Icons.inventory_2, Color(0xFF3F51B5), '/urun'),
    _UygulamaItem('Ürün Ekle', Icons.add_box, Color(0xFF4CAF50), '/urun/ekle'),
    _UygulamaItem('Fiyat Gör', Icons.price_check_rounded, Color(0xFF00ACC1),
        '/fiyat-gor'),
    _UygulamaItem('Stok Listesi', Icons.warehouse, Color(0xFF673AB7), '/stok'),
    _UygulamaItem(
        'Stok Sayım', Icons.calculate, Color(0xFF1976D2), '/stok/sayim'),
    _UygulamaItem(
        'Stok Hareket', Icons.swap_vert, Color(0xFF283593), '/stok/hareket'),
    _UygulamaItem('Depo Transfer', Icons.local_shipping, Color(0xFFE65100),
        '/stok/transfer'),
    _UygulamaItem(
        'Kritik Stok', Icons.warning_amber, Color(0xFFE65100), '/stok'),
    _UygulamaItem('Toplu İşlem', Icons.bolt_outlined, Color(0xFF1B5E20),
        '/urun/toplu-islem'),
    _UygulamaItem('Toplu Fiyat', Icons.price_change_outlined, Color(0xFF4E342E),
        '/urun/toplu-fiyat'),
    _UygulamaItem(
        'Kategoriler', Icons.category, Color(0xFF9C27B0), '/urun/kategori'),
    _UygulamaItem(
        'Markalar', Icons.branding_watermark, Color(0xFF3F51B5), '/urun/marka'),
    _UygulamaItem('Birimler', Icons.straighten, Color(0xFF795548), '/birim'),
    _UygulamaItem(
        'Lot/Seri Takibi', Icons.qr_code_2, Color(0xFF607D8B), '/lot'),
    _UygulamaItem('PLU Yönetimi', Icons.grid_view_rounded, Color(0xFF2E7D32),
        '/urun/plu'),
  ]),
  _Kategori('Masa & Restoran', Icons.table_restaurant, [
    _UygulamaItem(
        'Masalar', Icons.table_restaurant, Color(0xFF6D4C41), '/masa'),
    _UygulamaItem('Mutfak/Bar', Icons.soup_kitchen_outlined, Color(0xFFE64A19),
        '/mutfak'),
    _UygulamaItem('Rezervasyon', Icons.event_available, Color(0xFF6D4C41),
        '/rezervasyon'),
    _UygulamaItem(
        'Masa Raporu', Icons.assessment, Color(0xFF1565C0), '/masa-rapor'),
    _UygulamaItem('QR Menü', Icons.qr_code_2, Color(0xFF6D4C41), '/masa'),
  ]),
  _Kategori('Cari & Fatura', Icons.people, [
    _UygulamaItem('Cariler', Icons.people, Color(0xFF0097A7), '/cari'),
    _UygulamaItem(
        'Cari Ekle', Icons.person_add, Color(0xFF4CAF50), '/cari/ekle'),
    _UygulamaItem(
        'Cari Hareket', Icons.history, Color(0xFF607D8B), '/cari/hareket'),
    _UygulamaItem('Faturalar', Icons.receipt, Color(0xFF4E342E), '/fatura'),
    _UygulamaItem(
        'Fatura Oluştur', Icons.add, Color(0xFF4CAF50), '/fatura/yeni'),
    _UygulamaItem(
        'İrsaliye', Icons.local_shipping, Color(0xFF00695C), '/irsaliye'),
  ]),
  _Kategori('Promosyon', Icons.local_offer, [
    _UygulamaItem(
        'Promosyonlar', Icons.local_offer, Color(0xFFE65100), '/promosyon'),
    _UygulamaItem('Promosyon Ekle', Icons.add, Color(0xFF4CAF50), '/promosyon'),
  ]),
  _Kategori('Finans', Icons.account_balance, [
    _UygulamaItem(
        'Banka Yönetimi', Icons.business, Color(0xFF1565C0), '/banka'),
    _UygulamaItem(
        'Kredi Kartları', Icons.credit_card, Color(0xFFE65100), '/kredi-karti'),
    _UygulamaItem(
        'Borç Dashboard', Icons.payment, Color(0xFFD32F2F), '/borc-dashboard'),
    _UygulamaItem('Mail Bağlantısı', Icons.email_outlined, Color(0xFF1976D2),
        '/mail-baglanti'),
    _UygulamaItem('Banka Hareketleri', Icons.history, Color(0xFF6A1B9A),
        '/banka-hareket'),
    _UygulamaItem('Kasa', Icons.account_balance, Color(0xFF2E7D32), '/kasa'),
    _UygulamaItem('Kasa Raporu', Icons.account_balance_wallet,
        Color(0xFF1B5E20), '/kasa/rapor'),
    _UygulamaItem(
        'Kasa Hareket', Icons.history, Color(0xFF607D8B), '/kasa/hareket'),
    _UygulamaItem(
        'Virman', Icons.swap_horiz, Color(0xFF4527A0), '/kasa/virman'),
    _UygulamaItem('Giderler', Icons.money_off, Color(0xFFC62828), '/gider'),
    _UygulamaItem('Gider Ekle', Icons.add, Color(0xFF4CAF50), '/gider/ekle'),
    _UygulamaItem(
        'Tahsilat/Ödeme', Icons.payments, Color(0xFF2E7D32), '/cari/tahsilat'),
    _UygulamaItem('Borç Ekle', Icons.add_card, Color(0xFF4CAF50), '/borc-ekle'),
  ]),
  _Kategori('Raporlar', Icons.bar_chart, [
    _UygulamaItem(
        'Günlük Rapor', Icons.assessment, Color(0xFF6A1B9A), '/rapor/gunluk'),
    _UygulamaItem(
        'Satış Raporu', Icons.timeline, Color(0xFF1565C0), '/rapor/satis'),
    _UygulamaItem(
        'Kar / Zarar', Icons.trending_up, Color(0xFF006064), '/rapor/kar'),
    _UygulamaItem('Kasa Raporu', Icons.account_balance_wallet,
        Color(0xFF1B5E20), '/kasa/rapor'),
    _UygulamaItem(
        'Stok Raporu', Icons.inventory_2, Color(0xFF3F51B5), '/rapor/stok'),
    _UygulamaItem(
        'Cari Raporu', Icons.people, Color(0xFF0097A7), '/rapor/cari'),
    _UygulamaItem('ABC Stok Analizi', Icons.pie_chart_outline,
        Color(0xFF00838F), '/rapor/abc-analiz'),
    _UygulamaItem('Fiyat Simülasyonu', Icons.calculate_outlined,
        Color(0xFF6A1B9A), '/urun/fiyat-simulasyon'),
    _UygulamaItem('Stok Devir Analizi', Icons.autorenew,
        Color(0xFF5D4037), '/rapor/stok-devir'),
    _UygulamaItem('AI Analiz', Icons.auto_graph, Color(0xFF4527A0), '/ai'),
    _UygulamaItem('Onay Merkezi', Icons.verified_user_outlined,
        Color(0xFFB71C1C), '/onay-merkezi'),
    _UygulamaItem('Risk Merkezi', Icons.shield_outlined,
        Color(0xFFD84315), '/risk-merkezi'),
  ]),
  _Kategori('Tedarik & Alım', Icons.shopping_cart, [
    _UygulamaItem('Tedarikçi Sipariş', Icons.shopping_cart_outlined,
        Color(0xFF558B2F), '/tedarik'),
    _UygulamaItem(
        'Mal Alımı', Icons.shopping_cart, Color(0xFF558B2F), '/tedarik/alim'),
    _UygulamaItem('Satın Alma Önerileri', Icons.lightbulb_outline,
        Color(0xFFEF6C00), '/tedarik/oneriler'),
    _UygulamaItem('Tedarikçi Performansı', Icons.local_shipping_outlined,
        Color(0xFF37474F), '/rapor/tedarikci-performans'),
  ]),
  _Kategori('Barkod & Etiket', Icons.qr_code_2, [
    _UygulamaItem(
        'Etiket Yazdır', Icons.qr_code_2, Color(0xFF4E342E), '/barkod/etiket'),
    _UygulamaItem(
        'Barkod Üreteci', Icons.qr_code, Color(0xFF2196F3), '/barkod/uret'),
  ]),
  _Kategori('Sistem', Icons.settings, [
    _UygulamaItem('Ayarlar', Icons.settings, Color(0xFF546E7A), '/ayarlar'),
    _UygulamaItem(
        'Yazıcı Ayarları', Icons.print, Color(0xFF546E7A), '/ayarlar/yazici'),
    _UygulamaItem(
        'Yedekleme', Icons.backup, Color(0xFF2E7D32), '/ayarlar/yedek'),
    _UygulamaItem(
        'Kullanıcılar', Icons.people, Color(0xFFAD1457), '/kullanici'),
    _UygulamaItem(
        'Personel', Icons.badge_outlined, Color(0xFF7B1FA2), '/personel'),
    _UygulamaItem('Şubeler', Icons.store, Color(0xFF1A237E), '/sube'),
    _UygulamaItem('Vardiya', Icons.access_time, Color(0xFF37474F), '/vardiya'),
    _UygulamaItem(
        'Bildirimler', Icons.notifications, Color(0xFFE91E63), '/bildirimler'),
    _UygulamaItem(
        'Sistem Logları', Icons.history, Color(0xFF607D8B), '/ayarlar/log'),
    _UygulamaItem(
        'GIB e-Fatura', Icons.receipt, Color(0xFFC62828), '/ayarlar/gib'),
    _UygulamaItem('Fatura Ayarları', Icons.description, Color(0xFF3E2723),
        '/ayarlar/fatura'),
    _UygulamaItem('Fiş Tasarımı', Icons.receipt_outlined, Color(0xFF263238),
        '/ayarlar/fis'),
    _UygulamaItem('Bulut Senkronizasyon', Icons.cloud_sync, Color(0xFF4361EE),
        '/ayarlar/bulut-sync'),
    _UygulamaItem('Veri Aktarımı WiFi', Icons.sync_alt, Color(0xFF1565C0),
        '/ayarlar/sync'),
    _UygulamaItem('Kullanıcı Değiştir', Icons.swap_horiz, Color(0xFF4361EE),
        '/kullanici-degistir'),
  ]),
];

/// Masa/Restoran modülüne ait bir rota mı? — Masa Modu kapalıyken
/// bu rotalar dashboard'dan gizlenir.
bool _masaModulOgesi(String rota) =>
    rota == '/masa' ||
    rota == '/mutfak' ||
    rota == '/rezervasyon' ||
    rota == '/masa-rapor' ||
    rota == '/qr-menu';

/// Saate göre selamlama metni.
String _selamlama() {
  final h = DateTime.now().hour;
  if (h < 6) return 'İyi geceler';
  if (h < 12) return 'Günaydın';
  if (h < 18) return 'İyi günler';
  return 'İyi akşamlar';
}

// ──────────────────────────────────────────────────────────────────────────────
// DASHBOARD EKRANI
// ──────────────────────────────────────────────────────────────────────────────

class DashboardEkrani extends ConsumerStatefulWidget {
  const DashboardEkrani({super.key});

  @override
  ConsumerState<DashboardEkrani> createState() => _DashboardEkraniState();
}

class _DashboardEkraniState extends ConsumerState<DashboardEkrani>
    with SingleTickerProviderStateMixin {
  final _yazdirma = YazdirmaServisi();
  bool _btBagliMi = false;
  bool _varsayilanSifreUyarisi = false;
  late AnimationController _animCtrl;
  final _pageCtrl = PageController();
  int _aktifSayfa = 0;
  bool _tumUygulamalarGoster = false;

  final _aramaCtrl = TextEditingController();
  String _aramaMetni = '';

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _btDurumKontrol();
    // Yedek başlatma: splash'te zamanlama sorunu olursa (auth durumu
    // henüz hazır değilse) Dashboard açıldığında kesin olarak başlatılır.
    if (!AktifSubeServisi().hazir) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => AktifSubeServisi().baslat());
    }
    _aramaCtrl.addListener(() {
      setState(() => _aramaMetni = _aramaCtrl.text.toLowerCase());
    });
    // Play Store öncesi güvenlik denetiminde bulundu: admin varsayılan
    // "1234" şifresini hâlâ kullanıyorsa fark edilir bir uyarı göster.
    AuthServisi().varsayilanSifreKullaniliyorMu().then((varsayilan) {
      if (mounted && varsayilan) setState(() => _varsayilanSifreUyarisi = true);
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _pageCtrl.dispose();
    _aramaCtrl.dispose();
    super.dispose();
  }

  /// Play Store öncesi güvenlik denetiminde bulundu: admin şifresi hâlâ
  /// varsayılan "1234" ise, fiziksel erişimi olan HERKES tam yönetici
  /// erişimi kazanabilir. Bu banner, fark edilir ama kapatılabilir bir
  /// uyarı gösteriyor.
  Widget _varsayilanSifreBandi() => Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.red.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Güvenlik Uyarısı',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Colors.red.shade800)),
              Text(
                  'Admin şifreniz hâlâ varsayılan ("1234") — lütfen değiştirin.',
                  style: TextStyle(fontSize: 11.5, color: Colors.red.shade700)),
            ]),
          ),
          TextButton(
            onPressed: () => context.push('/sifre'),
            child: const Text('Değiştir',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: Colors.red.shade400),
            onPressed: () => setState(() => _varsayilanSifreUyarisi = false),
          ),
        ]),
      );

  Future<void> _btDurumKontrol() async {
    try {
      final bagli = await _yazdirma.btBagliMi;
      if (mounted) setState(() => _btBagliMi = bagli);
    } catch (e) {
      if (mounted) debugPrint('BT kontrol hatası: $e');
    }
  }

  /// Admin/Müdür kullanıcıların şubeler arasında geçiş yapmasını veya
  /// "Tüm Şubeler" görünümünü seçmesini sağlayan dialog.
  Future<void> _subeSecDialogGoster() async {
    final db = await Veritabani().db;
    final subeler =
        await db.query('subeler', where: 'aktif = 1', orderBy: 'sube_adi ASC');
    if (!mounted) return;

    final secilen = await showDialog<({int? id, String ad})>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Şube Seç'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              leading: const Icon(Icons.apps),
              title: const Text('Tüm Şubeler'),
              selected: AktifSubeServisi().tumSubelerModu,
              onTap: () => Navigator.pop(ctx, (id: null, ad: 'Tüm Şubeler')),
            ),
            const Divider(),
            ...subeler.map((s) => ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: Text(s['sube_adi'] as String),
                  selected: AktifSubeServisi().subeId == s['id'],
                  onTap: () => Navigator.pop(
                      ctx, (id: s['id'] as int, ad: s['sube_adi'] as String)),
                )),
          ]),
        ),
      ),
    );
    if (secilen == null || !mounted) return;
    await AktifSubeServisi().subeDegistir(secilen.id, yeniSubeAdi: secilen.ad);
    if (mounted)
      setState(() {}); // dashboard verilerini yeni şubeye göre yenile
  }

  Future<void> _cikisYap() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(children: [
          Icon(Icons.logout, color: Colors.red),
          SizedBox(width: 8),
          Text('Çıkış Yap'),
        ]),
        content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hayır')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    await ref.read(authProvider.notifier).cikisYap();
    if (mounted) context.go('/giris');
  }

  void _kullaniciDegistirAc() {
    Navigator.push(
        context,
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (_, __, ___) => const KullaniciDegistirEkrani(),
          transitionsBuilder: (_, a, __, c) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                    CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: c,
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final dashAsync = ref.watch(dashboardProvider);
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).yenile(),
        child: CustomScrollView(
          slivers: [
            _modernAppBar(),
            if (_varsayilanSifreUyarisi)
              SliverToBoxAdapter(child: _varsayilanSifreBandi()),
            if (!_tumUygulamalarGoster)
              dashAsync.when(
                loading: () => const SliverFillRemaining(
                    child: Center(child: AppYukleniyor(mesaj: 'Yükleniyor…'))),
                error: (e, _) => SliverFillRemaining(
                  child: TsBosDurum(
                    ikon: Icons.error_outline,
                    baslik: 'Veri yüklenemedi',
                    altyazi: '$e',
                    renk: TsRenk.hata,
                    aksiyonMetni: 'Tekrar Dene',
                    aksiyon: () =>
                        ref.read(dashboardProvider.notifier).yenile(),
                  ),
                ),
                data: (data) {
                  _animCtrl.forward(from: 0);
                  return SliverList(
                    delegate: SliverChildListDelegate([
                      _anaIcerik(data),
                      const SizedBox(height: 24),
                    ]),
                  );
                },
              )
            else
              SliverFillRemaining(
                child: _tumUygulamalarSayfasi(),
              ),
          ],
        ),
      ),
    );
  }

  // ── Modern AppBar ──────────────────────────────────────────────────────────
  Widget _modernAppBar() {
    final saatTarih =
        DateFormat('HH:mm • dd MMMM yyyy', 'tr_TR').format(DateTime.now());
    final ad = ref.watch(authProvider).aktifAd;
    final selamlama = _selamlama();
    final masaModu = ref.watch(masaModuProvider);
    final masaDoluSayisi = masaModu
        ? ref.watch(masaListesiProvider).maybeWhen(
            data: (m) => m.where((x) => x.durum != 'bos').length,
            orElse: () => 0)
        : 0;

    return SliverAppBar(
      expandedHeight: 150,
      pinned: true,
      elevation: 0,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white, size: 22),
      actionsIconTheme: const IconThemeData(color: Colors.white, size: 22),
      backgroundColor: TsRenk.primary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [TsRenk.primary, TsRenk.primaryKoyu],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Image.asset('assets/images/logo.png',
                        width: 22,
                        height: 22,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.storefront,
                            color: Colors.white70,
                            size: 22)),
                    const SizedBox(width: 6),
                    Image.asset('assets/images/logoYazı.png',
                        height: 18,
                        errorBuilder: (_, __, ___) => const Text('MarketPlus',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 8),
                    // 🔴 DÜZELTME: Bu 3 rozet (Tümü/Şube/Yazıcı) Expanded/Flexible
                    // olmadan diziliyordu — uzun şube adında dar ekranlarda
                    // RenderFlex taşma hatası riski vardı. Artık gerekirse
                    // yatay kaydırılabilir.
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          // Tüm Uygulamalar butonu
                          GestureDetector(
                            onTap: () => setState(() =>
                                _tumUygulamalarGoster = !_tumUygulamalarGoster),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(20),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: Colors.white.withAlpha(40),
                                    width: 1),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        _tumUygulamalarGoster
                                            ? Icons.grid_view
                                            : Icons.apps,
                                        size: 16,
                                        color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                        _tumUygulamalarGoster
                                            ? 'Ana Sayfa'
                                            : 'Tümü',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                  ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Aktif Şube göstergesi — kilitli değilse tıklanınca
                          // şube değiştirme seçeneği sunuyor.
                          AnimatedBuilder(
                            animation: AktifSubeServisi(),
                            builder: (context, _) => GestureDetector(
                              onTap: AktifSubeServisi().kilitliMi
                                  ? null
                                  : () => _subeSecDialogGoster(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(20),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                      color: Colors.white.withAlpha(40),
                                      width: 1),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.store_outlined,
                                          size: 14, color: Colors.white),
                                      const SizedBox(width: 4),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 90),
                                        child: Text(AktifSubeServisi().subeAdi,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                      if (!AktifSubeServisi().kilitliMi) ...[
                                        const SizedBox(width: 2),
                                        const Icon(Icons.expand_more,
                                            size: 14, color: Colors.white70),
                                      ],
                                    ]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Yazıcı durumu
                          GestureDetector(
                            onTap: () => context.push('/ayarlar/yazici'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Color.fromARGB(
                                    51,
                                    (_btBagliMi ? Colors.green : Colors.red)
                                        .red,
                                    (_btBagliMi ? Colors.green : Colors.red)
                                        .green,
                                    (_btBagliMi ? Colors.green : Colors.red)
                                        .blue),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _btBagliMi
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        _btBagliMi
                                            ? Icons.print
                                            : Icons.print_disabled,
                                        size: 14,
                                        color: _btBagliMi
                                            ? Colors.greenAccent
                                            : Colors.redAccent),
                                    const SizedBox(width: 4),
                                    Text(
                                        _btBagliMi
                                            ? 'Yazıcı Bağlı'
                                            : 'Yazıcı Yok',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: _btBagliMi
                                                ? Colors.greenAccent
                                                : Colors.redAccent)),
                                  ]),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _kullaniciDegistirAc,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(
                          ad.isNotEmpty ? '$selamlama, $ad 👋' : selamlama,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.swap_horiz_rounded,
                          size: 18, color: Colors.white70),
                    ]),
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(
                      saatTarih,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Kullanıcı isteği: "buluta gönderme ve alma ana
                    // menüde ikon olsa, tarih/saatin yan tarafına"
                    // (araya boşluk: kullanıcı "çok yakın, basılmıyor"
                    // dediği için 10→16)
                    _SyncMiniButon(ref: ref),
                  ]),
                  if (masaModu && masaDoluSayisi > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GestureDetector(
                        onTap: () => context.push('/masa'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(30),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withAlpha(60), width: 0.5),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.table_restaurant,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('$masaDoluSayisi masa dolu',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        Builder(builder: (context) {
          final sayi = ref.watch(okunmamisSayiProvider);
          return Stack(clipBehavior: Clip.none, children: [
            IconButton(
              icon:
                  const Icon(Icons.notifications_outlined, color: Colors.white),
              onPressed: () => context.push('/bildirimler'),
              tooltip: 'Bildirimler',
            ),
            if (sayi > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10)),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(sayi > 99 ? '99+' : '$sayi',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ),
          ]);
        }),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: () => ref.read(dashboardProvider.notifier).yenile(),
          tooltip: 'Yenile',
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: _cikisYap,
          tooltip: 'Çıkış',
        ),
      ],
    );
  }

  // ── Ana İçerik ────────────────────────────────────────────────────────────
  Widget _anaIcerik(DashboardVeri data) {
    return Column(children: [
      SizedBox(
        height: MediaQuery.of(context).size.height * 0.66,
        child: PageView(
          controller: _pageCtrl,
          onPageChanged: (i) => setState(() => _aktifSayfa = i),
          children: [
            _anaButonlarSayfasi(),
            _istatistikSayfasi(data),
            const FiyatGorIcerik(),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _sayfaGostergesi(),
      ),
    ]);
  }

  // ── Sayfa Göstergesi (segmented switcher) ────────────────────────────────
  Widget _sayfaGostergesi() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _gostergeSegmenti(0, 'Ana Menu', Icons.grid_view_rounded),
        _gostergeSegmenti(1, 'İstatistikler', Icons.bar_chart_rounded),
        _gostergeSegmenti(2, 'Fiyat Gör', Icons.price_check_rounded),
      ]),
    );
  }

  Widget _gostergeSegmenti(int index, String etiket, IconData ikon) {
    final aktif = _aktifSayfa == index;
    return GestureDetector(
      onTap: () => _pageCtrl.animateToPage(index,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: aktif ? AppRenkler.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          boxShadow: aktif
              ? [
                  BoxShadow(
                    color: AppRenkler.primary.withAlpha(60),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon,
              size: 15, color: aktif ? Colors.white : context.textSecondary),
          const SizedBox(width: 6),
          Text(etiket,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: aktif ? Colors.white : context.textSecondary)),
        ]),
      ),
    );
  }

  // ── Ana Butonlar Sayfası (12 Büyük Buton) ─────────────────────────────────
  Widget _anaButonlarSayfasi() {
    final masaModu = ref.watch(masaModuProvider);
    final liste = _anaButonlar
        .where((b) => masaModu || !_masaModulOgesi(b.rota))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: TsResponsive.izgaraKolonSayisi(context,
              telefon: 2, tablet: 3, genis: 4),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.2,
        ),
        itemCount: liste.length,
        itemBuilder: (_, i) => _buyukMenuKarti(liste[i]),
      ),
    );
  }

  // ── Büyük Menü Kartı ──────────────────────────────────────────────────────
  Widget _buyukMenuKarti(_AnaButon item) {
    final masaSayisi = item.rota == '/masa'
        ? ref.watch(masaListesiProvider).maybeWhen(
            data: (m) => m.where((x) => x.durum != 'bos').length,
            orElse: () => 0)
        : 0;
    final mutfakSayisi = item.rota == '/mutfak'
        ? ref.watch(mutfakProvider).maybeWhen(
            data: (d) => d.siparisler
                .expand((s) => s.kalemler)
                .where(
                    (k) => k.durum == 'beklemede' || k.durum == 'hazirlaniyor')
                .length,
            orElse: () => 0)
        : 0;
    final rozetSayisi = item.rota == '/masa' ? masaSayisi : mutfakSayisi;

    return _TapScale(
      onTap: () {
        try {
          context.push(item.rota);
        } catch (_) {
          context.go(item.rota);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              item.renk,
              Color.fromARGB(
                  204, item.renk.red, item.renk.green, item.renk.blue),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Color.fromARGB(
                  76, item.renk.red, item.renk.green, item.renk.blue),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Arka plan deseni
            Positioned(
              bottom: 0,
              right: 0,
              child: Opacity(
                opacity: 0.08,
                child: Icon(item.ikon, size: 80, color: Colors.white),
              ),
            ),
            // İçerik
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(item.ikon, size: 24, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.ad,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Masa/Mutfak badge
            if (rozetSayisi > 0)
              Positioned(
                  top: 8, right: 8, child: _rozet(rozetSayisi, Colors.white)),
          ],
        ),
      ),
    );
  }

  // ── Tüm Uygulamalar Sayfası (Kategori Bazlı) ───────────────────────────────
  Widget _tumUygulamalarSayfasi() {
    final masaModu = ref.watch(masaModuProvider);

    final kategoriler = masaModu
        ? _tumKategoriler
        : _tumKategoriler.where((k) => k.ad != 'Masa & Restoran').toList();

    final toplamEslesme = _aramaMetni.isEmpty
        ? -1
        : kategoriler
            .expand((k) => k.uygulamalar)
            .where((u) => u.ad.toLowerCase().contains(_aramaMetni))
            .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Arama kutusu
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _aramaCtrl,
              decoration: InputDecoration(
                hintText: 'Uygulama ara...',
                prefixIcon:
                    Icon(Icons.search, color: context.textSecondary, size: 20),
                suffixIcon: _aramaMetni.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: context.textSecondary, size: 18),
                        onPressed: () => _aramaCtrl.clear(),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          // Sonuç bulunamadı durumu
          if (toplamEslesme == 0)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: TsBosDurum(
                ikon: Icons.search_off,
                baslik: '"$_aramaMetni" için sonuç bulunamadı',
              ),
            ),

          // Kategori listesi
          ...kategoriler.map((kategori) {
            final filtrelenmis = kategori.uygulamalar
                .where((u) =>
                    _aramaMetni.isEmpty ||
                    u.ad.toLowerCase().contains(_aramaMetni))
                .toList();
            if (filtrelenmis.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Row(children: [
                    Icon(kategori.ikon, size: 20, color: AppRenkler.primary),
                    const SizedBox(width: 8),
                    Text(kategori.ad,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2)),
                  ]),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: filtrelenmis.length,
                  itemBuilder: (_, i) => _kucukUygulamaKarti(filtrelenmis[i]),
                ),
              ],
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Küçük Uygulama Kartı ──────────────────────────────────────────────────
  Widget _kucukUygulamaKarti(_UygulamaItem item) {
    return _TapScale(
      onTap: () {
        try {
          context.push(item.rota);
        } catch (_) {
          context.go(item.rota);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color.fromARGB(
                    26, item.renk.red, item.renk.green, item.renk.blue),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.ikon, size: 24, color: item.renk),
            ),
            const SizedBox(height: 8),
            Text(
              item.ad,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── İstatistik Sayfası ────────────────────────────────────────────────────
  Widget _istatistikSayfasi(DashboardVeri data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [TsRenk.primaryKoyu, TsRenk.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade900.withAlpha(30),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Genel Bakış',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(ParaUtils.formatla(data.gunlukCiro),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
              const Text('Bugünkü Ciro',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _statKart('Günlük Ciro', ParaUtils.formatla(data.gunlukCiro),
                  Icons.today, const Color(0xFF1565C0)),
              _statKart('Haftalık Ciro', ParaUtils.formatla(data.haftalikCiro),
                  Icons.date_range, const Color(0xFF2E7D32)),
              _statKart('Aylık Ciro', ParaUtils.formatla(data.aylikCiro),
                  Icons.calendar_month, const Color(0xFF6A1B9A)),
              _statKart('Günlük Gider', ParaUtils.formatla(data.gunlukGider),
                  Icons.money_off, const Color(0xFFC62828)),
            ],
          ),
          const SizedBox(height: 12),
          if (data.haftaData.isNotEmpty) _grafikBolumu(data),
          const SizedBox(height: 12),
          if (data.kritikUrunler.isNotEmpty) _kritikStokBolumu(data),
          _istatistikKartlar(data),
        ],
      ),
    );
  }

  // ── Yardımcı Widget'lar ────────────────────────────────────────────────────
  // FAZ 1 UI/UX: bu yerel widget kaldırıldı, ortak TsKpiKart component'ine
  // taşındı (bkz. lib/tasarim_sistemi/ts_kpi_kart.dart) — aynı görünüm,
  // artık dashboard dışındaki ekranlarda da tekrar kullanılabilir.
  Widget _statKart(String baslik, String deger, IconData ikon, Color renk) =>
      TsKpiKart(baslik: baslik, deger: deger, ikon: ikon, renk: renk);

  Widget _grafikBolumu(DashboardVeri d) {
    if (d.haftaData.isEmpty) return const SizedBox.shrink();
    const gunler = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final maxY = d.haftaData.fold(0.0, (mx, x) {
          final v = (x['ciro'] as num?)?.toDouble() ?? 0;
          return v > mx ? v : mx;
        }) *
        1.2;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Haftalık Satış',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2)),
          const SizedBox(height: 4),
          Text(
              'Grafikteki sütunlara dokunarak günlük ciro detayını görebilirsiniz',
              style: TextStyle(
                  fontSize: 10.5, color: TsRenk.metinIkincil(context))),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY <= 0 ? 1 : maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final idx = group.x.toInt();
                      final gun =
                          idx >= 0 && idx < gunler.length ? gunler[idx] : '';
                      return BarTooltipItem(
                        '$gun\n${ParaUtils.formatla(rod.toY)}',
                        const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        if (idx < 0 || idx >= gunler.length)
                          return const SizedBox.shrink();
                        return Text(gunler[idx],
                            style: TextStyle(
                                fontSize: 9,
                                color: context.textSecondary,
                                fontWeight: FontWeight.w500));
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: context.borderColor, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                barGroups: d.haftaData.asMap().entries.map((e) {
                  final ciro = (e.value['ciro'] as num?)?.toDouble() ?? 0;
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: ciro,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppRenkler.primary,
                            AppRenkler.primary.withAlpha(102),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kritikStokBolumu(DashboardVeri d) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Kritik Stok',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        const SizedBox(height: 12),
        ...d.kritikUrunler.take(3).map((u) {
          final stok = u['stok'] as double;
          final min = u['min'] as double;
          final oran = min > 0 ? (stok / min).clamp(0.0, 1.0) : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(
                    child: Text(u['ad'] as String,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                Text('$stok / $min',
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                        fontWeight: FontWeight.w500)),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: oran,
                minHeight: 5,
                backgroundColor: context.borderColor,
                valueColor: AlwaysStoppedAnimation(
                  oran < 0.3 ? Colors.red.shade600 : Colors.orange.shade700,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ]),
          );
        }),
        if (d.kritikUrunler.length > 3)
          TextButton(
            onPressed: () => context.push('/stok'),
            child: const Text('Tümünü Gör →',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  Widget _istatistikKartlar(DashboardVeri d) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Expanded(
            child: _sayacKart('Ürün', d.toplamUrun, Icons.inventory_2,
                const Color(0xFF3F51B5),
                onTap: () => context.push('/urun'))),
        const SizedBox(width: 10),
        Expanded(
            child: _sayacKart('Kritik', d.kritikStok, Icons.warning_amber,
                const Color(0xFFE65100),
                onTap: () => context.push('/stok'))),
        const SizedBox(width: 10),
        Expanded(
            child: _sayacKart(
                'Cari', d.toplamMusteri, Icons.people, const Color(0xFF00695C),
                onTap: () => context.push('/cari'))),
      ]),
    );
  }

  Widget _sayacKart(String baslik, int deger, IconData ikon, Color renk,
      {VoidCallback? onTap}) {
    return _TapScale(
      onTap: onTap,
      child: TsKart(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(children: [
          Icon(ikon, color: renk, size: 22),
          const SizedBox(height: 6),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: deger),
            duration: const Duration(milliseconds: 800),
            builder: (_, v, __) => Text('$v',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: renk)),
          ),
          Text(baslik,
              style: TextStyle(
                  fontSize: 9,
                  color: context.textSecondary,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Ortak yardımcılar
// ──────────────────────────────────────────────────────────────────────────────

Widget _rozet(int sayi, Color renk) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
      ),
      child: Text(sayi > 99 ? '99+' : '$sayi',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
    );

/// Dokununca hafifçe küçülen, bırakınca geri büyüyen kart sarmalayıcısı.
/// Tüm dashboard kartlarına "dokunma hissi" kazandırır.
class _TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _TapScale({required this.child, this.onTap});

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _scale = 0.94),
      onTapUp:
          widget.onTap == null ? null : (_) => setState(() => _scale = 1.0),
      onTapCancel:
          widget.onTap == null ? null : () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ── Hızlı Sync Mini Butonu (tarih/saat yanında) ──────────────────────────
// Kullanıcı isteği: "buluta gönderme ve alma ana menüde ikon olsa,
// tarih/saatin yan tarafına." Tek dokunuşla delta sync (sadece
// değişenler) yapar — uzun sürmez. Long-press ile tam sync seçeneği.
class _SyncMiniButon extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _SyncMiniButon({required this.ref});

  @override
  ConsumerState<_SyncMiniButon> createState() => _SyncMiniButonState();
}

class _SyncMiniButonState extends ConsumerState<_SyncMiniButon>
    with SingleTickerProviderStateMixin {
  bool _calisiyor = false;
  bool _basarili = false;
  bool _hata = false;
  late AnimationController _dondurmeCtrl;

  @override
  void initState() {
    super.initState();
    _dondurmeCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat();
    _dondurmeCtrl.stop();
  }

  @override
  void dispose() {
    _dondurmeCtrl.dispose();
    super.dispose();
  }

  Future<void> _hizliSync() async {
    if (_calisiyor) return;
    setState(() {
      _calisiyor = true;
      _basarili = false;
      _hata = false;
    });
    _dondurmeCtrl.repeat();
    try {
      final db = Veritabani();
      // Gönder (sadece değişenler)
      final gonderSonuc = await SupabaseSyncServisi.bulutaGonder(
        veriGetir: (t, f) => db.supaTumKayitlariGetirTemiz(t, f),
        sadeceDegisenler: true,
      );
      // Al (sadece değişenler)
      final alSonuc = await SupabaseSyncServisi.buluttanAl(
        kayitEkle: (t, k) => db.supaKayitlariEkle(t, k),
        kayitGuncelle: (t, k) => db.supaKayitlariGuncelle(t, k),
        sadeceDegisenler: true,
      );
      final hatalar = [...gonderSonuc.hatalar, ...alSonuc.hatalar];
      if (mounted) {
        setState(() {
          _calisiyor = false;
          _basarili = hatalar.isEmpty;
          _hata = hatalar.isNotEmpty;
        });
        _dondurmeCtrl.stop();
        // 3 saniye sonra normal ikona dön
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted)
            setState(() {
              _basarili = false;
              _hata = false;
            });
        });
        if (hatalar.isNotEmpty && mounted) {
          hataMesaji(context,
              'Sync: ${hatalar.length} hata — Ayarlar\'dan detay alın');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _calisiyor = false;
          _hata = true;
        });
        _dondurmeCtrl.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ikon = _basarili
        ? Icons.check_circle_outline
        : _hata
            ? Icons.error_outline
            : Icons.sync;
    final renk = _basarili
        ? Colors.greenAccent
        : _hata
            ? Colors.redAccent
            : Colors.white70;

    return GestureDetector(
      onTap: _hizliSync,
      onLongPress: () => context.push('/ayarlar/bulut-sync'),
      // Kullanıcı geri bildirimi: "ikon tarih/saate çok yakın,
      // basılmıyor." behavior: opaque + padding ile DOKUNMA ALANI
      // ikonun kendisinden çok daha geniş; ikon 16→22'ye büyütüldü
      // ve hafif bir arka planla ayrı bir buton gibi görünüyor.
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: 'Hızlı Sync (sadece değişenler)\nUzun bas → Tam Sync ekranı',
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(28),
            borderRadius: BorderRadius.circular(12),
          ),
          child: RotationTransition(
            turns: _calisiyor ? _dondurmeCtrl : const AlwaysStoppedAnimation(0),
            child: Icon(ikon, size: 22, color: renk),
          ),
        ),
      ),
    );
  }
}
