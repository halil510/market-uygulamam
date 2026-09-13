// lib/uygulama/router/uygulama_router.dart
// ✅ TAMAMEN DÜZELTİLDİ - Eksik import'lar eklendi

import 'package:flutter/material.dart';
import '../tema/uygulama_temasi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tasarim_sistemi/ts_responsive.dart';
import 'package:go_router/go_router.dart';

import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../ekranlar/splash/splash_ekrani.dart';
import '../../ekranlar/auth/giris_ekrani.dart';
import '../../ekranlar/auth/sifre_ekrani.dart';
import '../../ekranlar/dashboard/dashboard_ekrani.dart';
import '../../ekranlar/satis/hizli_satis_ekrani.dart';
import 'rotalar/satis_rotalari.dart';
import 'rotalar/masa_rotalari.dart';
import '../../ekranlar/masa/rezervasyon_ekrani.dart';
import '../../ekranlar/masa/masa_rapor_ekrani.dart';
import '../../ekranlar/satis/satis_liste_ekrani.dart';
import '../../ekranlar/satis/iade_ekrani.dart';
import '../../ekranlar/urun/urun_liste_ekrani.dart';
import 'rotalar/urun_rotalari.dart';
import '../../ekranlar/stok/stok_liste_ekrani.dart';
import '../../ekranlar/stok/depo_transfer_ekrani.dart';
import '../../ekranlar/stok/stok_sayim_ekrani.dart';
import '../../ekranlar/stok/stok_hareket_ekrani.dart';
import '../../ekranlar/cari/cari_liste_ekrani.dart';
import 'rotalar/cari_rotalari.dart';
import '../../ekranlar/rapor/gunluk_rapor_ekrani.dart';
import '../../ekranlar/rapor/satis_rapor_ekrani.dart';
import '../../ekranlar/rapor/kar_zarar_ekrani.dart';
import '../../ekranlar/rapor/stok_rapor_ekrani.dart';
import '../../ekranlar/rapor/cari_rapor_ekrani.dart';
import '../../ekranlar/rapor/abc_stok_analizi_ekrani.dart';
import '../../ekranlar/rapor/stok_devir_analizi_ekrani.dart';
import '../../ekranlar/rapor/tedarikci_performans_ekrani.dart';
import '../../ekranlar/onay/onay_merkezi_ekrani.dart';
import '../../ekranlar/rapor/risk_merkezi_ekrani.dart';
import '../../ekranlar/gider/gider_liste_ekrani.dart';
import '../../ekranlar/gider/gider_ekle_ekrani.dart';
import '../../modeller/gider_model.dart';
import '../../ekranlar/kasa/kasa_ekrani.dart';
import '../../ekranlar/kasa/virman_ekrani.dart';
import '../../ekranlar/kasa/kasa_hareket_ekrani.dart';
import '../../ekranlar/kasa/kasa_rapor_ekrani.dart';
import '../../ekranlar/vardiya/vardiya_ekrani.dart';
import '../../ekranlar/promosyon/promosyon_ekrani.dart';
import '../../ekranlar/tedarik/tedarik_siparis_ekrani.dart';
import '../../ekranlar/tedarik/alim_ekrani.dart';
import '../../ekranlar/tedarik/siparis_olustur_ekrani.dart';
import '../../ekranlar/tedarik/satin_alma_onerileri_ekrani.dart';
import '../../ekranlar/barkod/etiket_tasarim_ekrani.dart';
import '../../ekranlar/barkod/barkod_ureteci_ekrani.dart';
import '../../ekranlar/sube/sube_ekrani.dart';
import '../../ekranlar/irsaliye/irsaliye_ekrani.dart';
import '../../ekranlar/lot/lot_seri_ekrani.dart';
import '../../ekranlar/ai/ai_panel_ekrani.dart';
import '../../ekranlar/finans/finans_merkezi_ekrani.dart';
import '../../ekranlar/ayarlar/yazdirma_merkezi_ekrani.dart';
import '../../ekranlar/urun/fiyat_gor_ekrani.dart';
import 'rotalar/ayarlar_rotalari.dart';
import '../../ekranlar/kullanici/kullanici_liste_ekrani.dart';
import '../../ekranlar/kullanici/kullanici_ekle_ekrani.dart';
import '../../ekranlar/fatura/fatura_liste_ekrani.dart';
import '../../ekranlar/fatura/gib_gelen_kutusu_ekrani.dart';
import '../../ekranlar/urun/toplu_doviz_guncelleme_ekrani.dart';
import '../../ekranlar/urun/fiyat_simulasyon_ekrani.dart';
import 'rotalar/fatura_rotalari.dart';

import '../../ekranlar/personel/personel_liste_ekrani.dart';
import '../../ekranlar/bildirim/bildirim_merkezi_ekrani.dart';
import '../../ekranlar/auth/kullanici_degistir_ekrani.dart';
import '../../widgetlar/ortak/yetki_koruma.dart';
import '../../modeller/kullanici_model.dart';

import '../../modeller/cari_model.dart';

// ✅ EKSİK IMPORT'LAR EKLENDİ

// Modüler rota grupları (bkz. rotalar/ klasörü)
import 'rotalar/banka_rotalari.dart';
import 'rotalar/borc_rotalari.dart';

// Shell route içinde hâlâ doğrudan kullanılan borç ekranları
import '../../ekranlar/borc/borc_takip_ekrani.dart';
import '../../ekranlar/borc/borc_ekle_ekrani.dart';



final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class UygulamaRouter {
  static GoRouter? _router;

  static GoRouter router(WidgetRef ref) {
    _router ??= _olustur(ref);
    return _router!;
  }

  static GoRouter _olustur(WidgetRef ref) {
    final listenable = _AuthListenable(ref);

    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/splash',
      refreshListenable: listenable,
      redirect: (context, state) => _redirect(ref, state),
      // Tanımsız/kırık bir rotaya gidilirse (ör. eskiden /finans'ta olduğu
      // gibi) artık GoRouter'ın çıplak varsayılan hata ekranı yerine,
      // kullanıcıyı ana ekrana döndüren zarif bir ekran gösterilir.
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.explore_off_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Bu sayfa bulunamadı',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('"${state.uri}" adresine ulaşılamadı.',
                  style: TextStyle(fontSize: 13, color: context.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Ana Ekrana Dön'),
              ),
            ]),
          ),
        ),
      ),
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashEkrani()),
        GoRoute(path: '/giris', builder: (_, __) => const GirisEkrani()),
        GoRoute(path: '/sifre', builder: (_, __) => const SifreEkrani()),

        // ---------- FULL-SCREEN ROUTES ----------
        GoRoute(path: '/kasa/virman', name: 'virman', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const VirmanEkrani()),
        GoRoute(path: '/stok/transfer', name: 'depo_transfer', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const DepoTransferEkrani()),
        // ---------- SATIŞ ROUTES (bkz. rotalar/satis_rotalari.dart) ----------
        ...satisRotalari(rootNavigatorKey),
        // ---------- CARİ ROUTES (bkz. rotalar/cari_rotalari.dart) ----------
        ...cariRotalari(rootNavigatorKey),
        // ---------- FATURA ROUTES (bkz. rotalar/fatura_rotalari.dart) ----------
        ...faturaRotalari(rootNavigatorKey),
        GoRoute(path: '/ayarlar/fatura', name: 'fatura_ayar', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const YazdirmaMerkeziEkrani(baslangicSekmesi: 2)),
        GoRoute(path: '/ayarlar/fis', name: 'fis_tasarim', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const YazdirmaMerkeziEkrani(baslangicSekmesi: 1)),
        // ---------- MASA ROUTES (bkz. rotalar/masa_rotalari.dart) ----------
        ...masaRotalari(rootNavigatorKey),
        // ---------- ÜRÜN ROUTES (bkz. rotalar/urun_rotalari.dart) ----------
        ...urunRotalari(rootNavigatorKey),
        GoRoute(path: '/lot', name: 'lot', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => LotSeriEkrani(urunId: s.extra as int?)),
        GoRoute(path: '/tedarik/alim', name: 'tedarik_alim', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) {
            final extra = s.extra;
            if (extra is Map<String, dynamic>) {
              return AlimEkrani(
                tedarikci: extra['tedarikci'] as CariModel?,
                baslangicKalemler: extra['kalemler'] as List<Map<String, dynamic>>?,
                mevcutSiparisId: extra['siparisId'] as int?,
              );
            }
            return AlimEkrani(tedarikci: extra as CariModel?);
          }),
        GoRoute(path: '/tedarik/siparis-olustur', name: 'tedarik_siparis_olustur', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) {
            final extra = s.extra;
            if (extra is Map<String, dynamic>) {
              return SiparisOlusturEkrani(
                tedarikci: extra['tedarikci'] as CariModel,
                onerilenKalemler: extra['onerilenKalemler'] as List<OnerilenSiparisKalemi>?,
              );
            }
            return SiparisOlusturEkrani(tedarikci: extra as CariModel);
          }),
        GoRoute(path: '/tedarik/oneriler', name: 'tedarik_oneriler', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => const SatinAlmaOnerileriEkrani()),
        // 🔴 Derin analizde bulundu: bu rotanın hiç YetkiKoruma sarmalayıcısı
        // yoktu — kardeş rota '/kullanici' (liste) sarmalıyken bu (yeni
        // kullanıcı ekleme/rol atama) sarmalanmamıştı. '/kullanici' önekiyle
        // rota-seviyesi yönlendirme koruması zaten kapsıyordu, ama
        // tutarlılık ve savunma derinliği için widget seviyesi de eklendi.
        GoRoute(path: '/kullanici/ekle', name: 'kullanici_ekle', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => YetkiKoruma(yetkiKodu: 'kullanici', ekranAdi: 'Kullanıcı Ekle',
              child: KullaniciEkleEkrani(duzenlenecek: s.extra as KullaniciModel?))),
        GoRoute(path: '/kullanici-degistir', name: 'kullanici_degistir', parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const KullaniciDegistirEkrani()),
        GoRoute(path: '/gider/ekle', name: 'gider_ekle', parentNavigatorKey: rootNavigatorKey,
          builder: (_, state) => GiderEkleEkrani(duzenlenecek: state.extra as GiderModel?)),

        // ---------- BORÇ ROUTES (bkz. rotalar/borc_rotalari.dart) ----------
        ...borcRotalari(rootNavigatorKey),

        // ---------- BANKA / KREDİ KARTI / MAİL ROUTES (bkz. rotalar/banka_rotalari.dart) ----------
        ...bankaRotalari(rootNavigatorKey),


        // ---------- DASHBOARD'DAN AÇILAN EKRANLAR (root navigator, düzgün geri tuşu) ----------
        GoRoute(path: '/fiyat-gor', name: 'fiyat_gor', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const FiyatGorEkrani()),
        // Not: Bu rotalar önceden ShellRoute içindeydi ve parentNavigatorKey
        // eklenmişti ama Shell'in KENDİ routes listesinde kalmışlardı — bu
        // tutarsız yapı navigasyon sorunlarına yol açtı. Artık diğer modüllerle
        // (Satış, Cari, Ürün vb.) AYNI şekilde, Shell'in DIŞINDA tanımlanıyorlar.
            GoRoute(path: '/satis/liste', name: 'satis_liste', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const YetkiKoruma(yetkiKodu: 'satis_liste', ekranAdi: 'Satış Listesi', child: SatisListeEkrani())),
            GoRoute(path: '/satis/iade', name: 'satis_iade', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const YetkiKoruma(yetkiKodu: 'satis_iade', ekranAdi: 'İade', child: IadeEkrani())),
            GoRoute(path: '/stok', name: 'stok', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const YetkiKoruma(yetkiKodu: 'stok', ekranAdi: 'Stok', child: StokListeEkrani())),
            GoRoute(path: '/stok/sayim', name: 'stok_sayim', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const StokSayimEkrani()),
            GoRoute(path: '/stok/hareket', name: 'stok_hareket', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const StokHareketEkrani()),
            GoRoute(path: '/rapor/gunluk', name: 'rapor_gunluk', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const GunlukRaporEkrani()),
            GoRoute(path: '/rapor/satis', name: 'rapor_satis', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const SatisRaporEkrani()),
            GoRoute(path: '/rapor/kar', name: 'rapor_kar', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const KarZararEkrani()),
            GoRoute(path: '/rapor/stok', name: 'rapor_stok', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const StokRaporEkrani()),
            GoRoute(path: '/rapor/cari', name: 'rapor_cari', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const CariRaporEkrani()),
            GoRoute(path: '/rapor/abc-analiz', name: 'rapor_abc_analiz', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const AbcStokAnaliziEkrani()),
            GoRoute(path: '/rapor/stok-devir', name: 'rapor_stok_devir', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const StokDevirAnaliziEkrani()),
            GoRoute(path: '/rapor/tedarikci-performans', name: 'rapor_tedarikci_performans', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const TedarikciPerformansEkrani()),
            GoRoute(path: '/onay-merkezi', name: 'onay_merkezi', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const OnayMerkeziEkrani()),
            GoRoute(path: '/risk-merkezi', name: 'risk_merkezi', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const RiskMerkeziEkrani()),
            GoRoute(path: '/gider', name: 'gider_liste', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const GiderListeEkrani()),
            GoRoute(path: '/kasa', name: 'kasa', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const KasaEkrani()),
            GoRoute(path: '/kasa/hareket', name: 'kasa_hareket', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const KasaHareketEkrani()),
            GoRoute(path: '/kasa/rapor', name: 'kasa_rapor', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const KasaRaporEkrani()),
            GoRoute(path: '/vardiya', name: 'vardiya', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const VardiyaEkrani()),
            GoRoute(path: '/promosyon', name: 'promosyon', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const YetkiKoruma(yetkiKodu: 'promosyon', ekranAdi: 'Promosyonlar', child: PromosyonEkrani())),
            GoRoute(path: '/fatura', name: 'fatura_liste', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const FaturaListeEkrani()),
            GoRoute(path: '/fatura/gelen-kutusu', name: 'gib_gelen_kutusu', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const GibGelenKutusuEkrani()),
            GoRoute(path: '/urun/doviz-guncelle', name: 'toplu_doviz_guncelle', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const TopluDovizGuncellemeEkrani()),
            GoRoute(path: '/urun/fiyat-simulasyon', name: 'fiyat_simulasyon', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const FiyatSimulasyonuEkrani()),
            GoRoute(path: '/tedarik', name: 'tedarik', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const TedarikSiparisEkrani()),
            GoRoute(path: '/barkod/etiket', name: 'barkod_etiket', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const EtiketTasarimEkrani()),
            GoRoute(path: '/barkod/uret', name: 'barkod_uret', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const BarkodUreteciEkrani()),
            GoRoute(path: '/sube', name: 'sube', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const SubeEkrani()),
            GoRoute(path: '/irsaliye', name: 'irsaliye', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const IrsaliyeEkrani()),
            GoRoute(path: '/ai', name: 'ai', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const AiPanelEkrani()),
            GoRoute(path: '/finans', name: 'finans', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const FinansMerkeziEkrani()),
            GoRoute(path: '/personel', name: 'personel', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const PersonelListeEkrani()),
            GoRoute(path: '/bildirimler', name: 'bildirimler', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const BildirimMerkeziEkrani()),
            // ---------- AYARLAR ROUTES (bkz. rotalar/ayarlar_rotalari.dart) ----------
            ...ayarlarRotalari(rootNavigatorKey),
            GoRoute(path: '/kullanici', name: 'kullanici_liste', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const YetkiKoruma(yetkiKodu: 'kullanici', ekranAdi: 'Kullanıcılar', child: KullaniciListeEkrani())),
            GoRoute(path: '/rezervasyon', name: 'rezervasyon', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const RezervasyonEkrani()),
            GoRoute(path: '/masa-rapor', name: 'masa_rapor', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const MasaRaporEkrani()),
            GoRoute(path: '/borc-takip', name: 'borc_takip', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const BorcTakipEkrani()),
            GoRoute(path: '/borc-ekle', name: 'borc_ekle', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const BorcEkleEkrani()),

        // ---------- SHELL ROUTE ----------
        ShellRoute(
          builder: (context, state, child) => AnaKabuk(child: child, mevcutRota: state.matchedLocation),
          routes: [
            GoRoute(path: '/', name: 'dashboard', builder: (_, __) => const DashboardEkrani()),
            GoRoute(path: '/satis', name: 'satis', builder: (_, __) => const HizliSatisEkrani()),
            GoRoute(path: '/urun', name: 'urun_liste', builder: (_, state) => YetkiKoruma(yetkiKodu: 'urun', ekranAdi: 'Ürünler', child: UrunListeEkrani(baslangicArama: state.extra as String?))),
            GoRoute(path: '/cari', name: 'cari_liste', builder: (_, state) => YetkiKoruma(yetkiKodu: 'cari', ekranAdi: 'Cariler', child: CariListeEkrani(baslangicArama: state.extra as String?))),
          ],
        ),
      ],
    );
  }

  // ✅ YETKİ HARİTASI (Güncellendi)
  // 🔴🔴 KRİTİK GÜVENLİK AÇIĞI (derin analizde bulundu): 'kasa', 'gider',
  // 'fatura' ve 'tedarik' — kullanıcı ekleme ekranındaki YetkiTanimlari
  // içinde TANIMLI ve atanabilir yetki kodlarıydı (ör. bir kasiyerden bu
  // kutucuklar kaldırılabiliyordu) ama bu haritada karşılık gelen rota
  // önekleri HİÇ YOKTU. Sonuç: 'Kasa' yetkisi verilmemiş bir personel bile
  // '/kasa' rotasına (deep-link, geri/ileri gezinme, adres çubuğu vb. ile)
  // doğrudan gidip kasayı, gider yönetimini, faturaları ve tedarik/alım
  // ekranını tamamen kullanabiliyordu — yetki kutucuğunun hiçbir pratik
  // etkisi yoktu. Artık bu dört rota da haritada.
  static const _routeYetkiler = <String, String>{
    '/satis': 'satis',
    '/satis/liste': 'satis_liste',
    '/satis/iade': 'satis_iade',
    '/urun': 'urun',
    '/stok': 'stok',
    '/stok/sayim': 'stok',
    '/cari': 'cari',
    '/cari/hareket': 'cari_hareket',
    '/irsaliye': 'stok',
    '/promosyon': 'promosyon',
    '/rapor': 'rapor',
    '/kullanici': 'ayarlar',
    '/ayarlar': 'ayarlar',
    '/personel': 'ayarlar',
    '/banka': 'cari',
    '/kredi-karti': 'cari',
    '/mail-baglanti': 'cari',
    '/banka-hareket': 'cari',
    '/kasa': 'kasa',
    '/gider': 'gider',
    '/fatura': 'fatura',
    '/tedarik': 'tedarik',
  };

  static String? _redirect(WidgetRef ref, GoRouterState state) {
    final auth = ref.read(authProvider);
    final gidilen = state.matchedLocation;

    if (gidilen == '/splash') return null;
    if (auth.yukleniyor) return null;

    if (!auth.girisYapildi && gidilen != '/giris') return '/giris';
    if (auth.girisYapildi && gidilen == '/giris') return '/';

    // 🔴🔴 GÜVENLİK DÜZELTMESİ (derin analizde bulundu): bu blok müdür
    // rolünü de admin gibi TÜM rota yetki kontrollerinden koşulsuz
    // muaf tutuyordu — yetkiVarSync()'teki aynı köke sahip açık (bkz. o
    // dosyadaki not). Bir adminin bir müdürden 'kullanici'/'ayarlar' vb.
    // yetkisini kaldırması bu yüzden hiçbir pratik etkisi olmuyordu.
    // Artık sadece admin muaf; müdür de diğer roller gibi
    // _routeYetkiler haritasına göre kontrol ediliyor.
    if (auth.girisYapildi && !auth.isAdmin) {
      for (final e in _routeYetkiler.entries) {
        if (gidilen.startsWith(e.key) && !ref.read(authProvider.notifier).yetkiVarSync(e.value)) {
          return '/';
        }
      }
    }
    return null;
  }
}

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(WidgetRef ref) {
    ref.listenManual(authProvider, (_, __) => notifyListeners());
  }
}

// ---------- ANA KABUK ----------

class AnaKabuk extends ConsumerStatefulWidget {
  final Widget child;
  final String mevcutRota;
  const AnaKabuk({super.key, required this.child, required this.mevcutRota});

  @override
  ConsumerState<AnaKabuk> createState() => _AnaKabukState();
}

class _AnaKabukState extends ConsumerState<AnaKabuk> {
  int get _seciliIndex {
    if (widget.mevcutRota == '/') return 0;
    if (widget.mevcutRota.startsWith('/satis')) return 1;
    if (widget.mevcutRota.startsWith('/urun') ||
        widget.mevcutRota.startsWith('/stok') ||
        widget.mevcutRota.startsWith('/barkod') ||
        widget.mevcutRota.startsWith('/promosyon') ||
        widget.mevcutRota.startsWith('/tedarik') ||
        widget.mevcutRota.startsWith('/lot') ||
        widget.mevcutRota.startsWith('/birim') ||
        widget.mevcutRota.startsWith('/personel')) return 2;
    if (widget.mevcutRota.startsWith('/cari') ||
        widget.mevcutRota.startsWith('/fatura') ||
        widget.mevcutRota.startsWith('/irsaliye') ||
        widget.mevcutRota.startsWith('/banka') ||
        widget.mevcutRota.startsWith('/kredi-karti') ||
        widget.mevcutRota.startsWith('/mail-baglanti') ||
        widget.mevcutRota.startsWith('/banka-hareket') ||
        widget.mevcutRota.startsWith('/finans') ||
        widget.mevcutRota.startsWith('/borc')) return 3;
    return 4;
  }

  static const _navItems = [
    (icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Ana Ekran', route: '/'),
    (icon: Icons.point_of_sale, activeIcon: Icons.point_of_sale, label: 'Satış', route: '/satis'),
    (icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: 'Ürünler', route: '/urun'),
    (icon: Icons.people_outline, activeIcon: Icons.people, label: 'Cariler', route: '/cari'),
    (icon: Icons.more_horiz, activeIcon: Icons.more_horiz, label: 'Daha Fazla', route: '/ayarlar'),
  ];

  @override
  Widget build(BuildContext context) {
    final tablet = TsResponsive.tabletMi(context);

    void navSecildi(int i) {
      final r = _navItems[i].route;
      if (i == _seciliIndex && r != '/') { context.go('/'); return; }
      context.go(r);
    }

    // ── TABLET / YATAY MOD / GENİŞ EKRAN — kalıcı yan menü ─────────────────
    // Telefon davranışı bu bloğa hiç girmez, aşağıdaki orijinal
    // bottomNavigationBar yapısı birebir korunuyor.
    if (tablet) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, __) {},
        child: Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: _seciliIndex,
              onDestinationSelected: navSecildi,
              backgroundColor: Colors.white,
              labelType: NavigationRailLabelType.all,
              useIndicator: true,
              indicatorColor: const Color(0xFFE8EAFF),
              selectedIconTheme: const IconThemeData(color: Color(0xFF4361EE)),
              unselectedIconTheme: const IconThemeData(color: Color(0xFF6B7280)),
              selectedLabelTextStyle: const TextStyle(color: Color(0xFF4361EE), fontWeight: FontWeight.w700, fontSize: 12),
              unselectedLabelTextStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              destinations: _navItems.map((item) => NavigationRailDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon),
                label: Text(item.label),
              )).toList(),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: widget.child),
          ]),
        ),
      );
    }

    // ── TELEFON — orijinal alt navigasyon (değişmedi) ──────────────────────
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: const Offset(0, -3))],
          ),
          child: NavigationBar(
            selectedIndex: _seciliIndex,
            elevation: 0,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: navSecildi,
            destinations: _navItems.map((item) => NavigationDestination(
              icon: Icon(item.icon, color: const Color(0xFF6B7280)),
              selectedIcon: Icon(item.activeIcon, color: const Color(0xFF4361EE)),
              label: item.label,
            )).toList(),
          ),
        ),
      ),
    );
  }
}
