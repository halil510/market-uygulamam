// lib/ekranlar/dashboard/dashboard_ekrani.dart
//
// God-class sertleştirmesi (2026-09-22, kullanıcı onayıyla): bu dosya
// 1252 satırdı. İçerik davranış DEĞİŞTİRİLMEDEN 4 parçaya ayrıldı:
//   - dashboard_menu_verileri.dart  → sabit buton/kategori verisi
//   - dashboard_appbar_ext.dart     → üst bar (SliverAppBar) inşası
//   - dashboard_ana_butonlar_ext.dart → 12 büyük buton ızgarası
//   - dashboard_tum_uygulamalar_ext.dart → kategori bazlı arama sayfası
// _SyncMiniButon ise bağımsız, genel (public) bir widget'a çevrilip
// widgets/sync_mini_buton.dart'a taşındı (normal import ile kullanılıyor
// — diğerleri gibi part-of yapılmadı çünkü zaten kendi kendine yeten,
// _DashboardEkraniState'in private üyelerine hiç ihtiyaç duymuyordu).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../depolar/sube_deposu.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../widgetlar/ortak/tap_scale.dart';
import 'widgets/dashboard_istatistik_sayfasi.dart';
import 'widgets/sync_mini_buton.dart';
import '../../saglayicilar/riverpod/dashboard_provider.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../saglayicilar/riverpod/masa_provider.dart';
import '../../saglayicilar/riverpod/masa_modu_provider.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../auth/kullanici_degistir_ekrani.dart';
import '../urun/fiyat_gor_ekrani.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../bildirim/bildirim_merkezi_ekrani.dart' show okunmamisSayiProvider;

part 'dashboard_menu_verileri.dart';
part 'dashboard_appbar_ext.dart';
part 'dashboard_ana_butonlar_ext.dart';
part 'dashboard_tum_uygulamalar_ext.dart';

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
          color: TsRenk.zemin(TsRenk.hata),
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

  /// Admin/Müdür kullanıcıların şubeler arasında geçiş yapmasını veya
  /// "Tüm Şubeler" görünümünü seçmesini sağlayan dialog.
  Future<void> _subeSecDialogGoster() async {
    final subeler = await SubeDeposu().aktifOlanlariGetir();
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
            DashboardIstatistikSayfasi(data: data),
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
}
