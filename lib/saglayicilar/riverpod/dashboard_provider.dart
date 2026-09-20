// lib/saglayicilar/riverpod/dashboard_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/satis_deposu.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/gider_deposu.dart';
import '../../depolar/kasa_deposu.dart';
import '../../servisler/onay_merkezi_servisi.dart';
import '../../servisler/risk_merkezi_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';

part 'dashboard_provider.g.dart';

class DashboardVeri {
  final int toplamUrun, kritikStok, toplamMusteri;
  final double gunlukCiro, haftalikCiro, aylikCiro, gunlukGider, netKar, mustBakiye, kasaBakiye;
  // 🔴 EKLENDİ (Madde 31 — Dashboard denetimi, 2026-09-20): dokümanın
  // istediği ama HİÇ gösterilmeyen KPI'lar. Bir kısmı (netKar/mustBakiye/
  // kasaBakiye) zaten hesaplanıyordu ama UI'da HİÇBİR YERDE render
  // edilmiyordu — ölü alanlardı. netKar'ın KENDİSİ de bug'lıydı (aşağı
  // bkz.).
  final double brutKar, brutMarjOrani, toplamAlacak, toplamBorc;
  final double nakitBugun, kartBugun, cariSatisBugun;
  final int onayBekleyen, syncBekleyen, riskliCariSayisi;
  final List<Map<String, dynamic>> haftaData, kritikUrunler;
  final DateTime yuklenmeTarihi;

  const DashboardVeri({
    required this.toplamUrun,    required this.kritikStok,
    required this.toplamMusteri, required this.gunlukCiro,
    required this.haftalikCiro,  required this.aylikCiro,
    required this.gunlukGider,   required this.netKar,
    required this.mustBakiye,    required this.kasaBakiye,
    required this.brutKar,       required this.brutMarjOrani,
    required this.toplamAlacak,  required this.toplamBorc,
    required this.nakitBugun,    required this.kartBugun,
    required this.cariSatisBugun,
    required this.onayBekleyen,  required this.syncBekleyen,
    required this.riskliCariSayisi,
    required this.haftaData,     required this.kritikUrunler,
    required this.yuklenmeTarihi,
  });

  bool get gecerli => DateTime.now().difference(yuklenmeTarihi).inMinutes < 5;
}

/// Madde 31 (Dashboard) denetimi, 2026-09-20 — saf, DB'den bağımsız
/// yardımcılar (para/işaret hassasiyeti olan mantık için test
/// edilebilirlik amacıyla ayrı tutuldu).
class DashboardHesap {
  DashboardHesap._();

  /// cari.bakiye listesini "Toplam Alacak" (pozitif bakiyeler — bize
  /// borçlu olanlar) ve "Toplam Borç" (negatif bakiyeler, mutlak değer —
  /// bizim borçlu olduğumuz) olarak ikiye ayırır. Madde 31 bu ikisini
  /// AYRI KPI olarak istiyor — net toplam (mustBakiye) tek başına
  /// hangisinin ne kadar olduğunu gizler (ör. +500 net, aslında
  /// +2000 alacak - 1500 borç olabilir).
  static ({double alacak, double borc}) alacakBorcAyir(Iterable<double> bakiyeler) {
    var alacak = 0.0, borc = 0.0;
    for (final b in bakiyeler) {
      if (b > 0) {
        alacak += b;
      } else if (b < 0) {
        borc += -b;
      }
    }
    return (alacak: alacak, borc: borc);
  }

  /// Brüt kâr = ciro - maliyet (COGS). Net kâr = brüt kâr - gider.
  /// Madde 24/31 denetimi: netKar ÖNCEDEN maliyeti hiç düşmüyordu (bkz.
  /// dashboard_provider.dart _fetch() yorumu) — Kâr/Zarar raporuyla
  /// (kar_zarar_provider.dart) AYNI formüle hizalandı.
  static ({double brutKar, double netKar, double marjOrani}) karHesapla({
    required double ciro,
    required double maliyet,
    required double gider,
  }) {
    final brut = ciro - maliyet;
    final net = brut - gider;
    final marj = ciro > 0 ? (brut / ciro * 100) : 0.0;
    return (brutKar: brut, netKar: net, marjOrani: marj);
  }
}

@riverpod
class Dashboard extends _$Dashboard {
  @override
  Future<DashboardVeri> build() => _fetch();

  Future<DashboardVeri> _fetch() async {
    final now      = DateTime.now();
    final bugunBas = DateTime(now.year, now.month, now.day);
    final bugunBit = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final haftaBas = now.subtract(Duration(days: now.weekday - 1));
    final ayBas    = DateTime(now.year, now.month, 1);

    final results = await Future.wait([
      UrunDeposu().istatistikler(),
      UrunDeposu().kritikStoklar(),
      // 🔴 Derin analizde bulundu: limit: 200 ile çağrılıyordu — 200'den
      // fazla aktif cariye sahip bir işletmede "Toplam Müşteri" sayısı
      // ve toplam cari bakiyesi (mustBakiye) sessizce eksik (sadece
      // unvana göre alfabetik ilk 200 kayıt) gösteriliyordu, hiçbir
      // hata/uyarı olmadan. Gerçekçi bir üst sınırla (pratikte hiçbir
      // küçük/orta işletmenin aşmayacağı) sınırlama kaldırıldı.
      CariDeposu().tumunuGetir(limit: 100000),
      SatisDeposu().gunlukIstatistik(),
      SatisDeposu().haftaGrafikVerisi(),
      SatisDeposu().tariheGoreGetir(
          DateTime(haftaBas.year, haftaBas.month, haftaBas.day), bugunBit),
      SatisDeposu().tariheGoreGetir(ayBas, bugunBit),
      GiderDeposu().aralikToplamGider(bugunBas, bugunBit),
      KasaDeposu().guncelBakiye(),
      // 🔴 EKLENDİ (Madde 31 — Dashboard denetimi, 2026-09-20): dokümanın
      // istediği ama hiç gösterilmeyen KPI'lar — hepsi zaten var olan,
      // başka ekranlarda da kullanılan kanonik kaynaklara delege ediyor
      // (tek gerçek kaynak ilkesi — Madde 24'te bulunanın AYNISI hataya
      // düşmemek için, ör. Onay Merkezi/Risk Merkezi'nin KENDİ mantığını
      // burada YENİDEN YAZMAK yerine doğrudan çağırıyoruz).
      SatisDeposu().gunlukMaliyet(),
      OnayMerkeziServisi().gorulmemisSayisi(),
      RiskMerkeziServisi().analizGetir(),
    ]);

    final ist     = results[0] as Map<String, dynamic>;
    final kritik  = results[1] as List;
    final cariler = results[2] as List;
    final gunIst  = results[3] as Map<String, dynamic>;
    final haftaD  = results[4] as List<Map<String, dynamic>>;
    final haftaS  = results[5] as List;
    final aylikS  = results[6] as List;
    final gunG    = results[7] as double;
    final kasaB   = results[8] as double;
    final gunM    = results[9] as double;
    final onayB   = results[10] as int;
    final riskler = results[11] as List<RiskSatiri>;

    final gunCiro   = (gunIst['ciro'] as num?)?.toDouble() ?? 0;
    final haftaCiro = haftaS.fold(0.0, (s, x) => s + ((x.genelToplam as double?) ?? 0));
    final aylikCiro = aylikS.fold(0.0, (s, x) => s + ((x.genelToplam as double?) ?? 0));
    final mustBak   = cariler.fold(0.0, (s, c) => s + ((c.bakiye as double?) ?? 0));
    // Madde 31: "Toplam cari alacak" ve "Toplam cari borç" AYRI iki KPI
    // isteniyor — mustBakiye (net toplam) tek başına ikisini de gizler.
    final alacakBorc = DashboardHesap.alacakBorcAyir(
        cariler.map((c) => (c.bakiye as double?) ?? 0));
    // 🔴 DÜZELTME: netKar ÖNCEDEN sadece "ciro - gider"di — maliyeti
    // (COGS) HİÇ düşmüyordu, yani gerçek bir "net kâr" DEĞİLDİ (bir
    // ürünü 60'a alıp 100'e satsanız bile, gider 0 ise "netKar" 100
    // gösterirdi — 40 TL kâr yerine tüm ciro kâr gibi görünürdü). Artık
    // Kâr/Zarar raporuyla (kar_zarar_provider.dart) AYNI formül:
    // ciro - maliyet - gider.
    final kar = DashboardHesap.karHesapla(ciro: gunCiro, maliyet: gunM, gider: gunG);
    final syncB  = BulutManager().bekleyenSayisi;
    final riskliSayi = riskler.where((r) => r.seviye == RiskSeviyesi.kritik).length;

    return DashboardVeri(
      toplamUrun:     ist['toplam'] as int? ?? 0,
      kritikStok:     kritik.length,
      toplamMusteri:  cariler.length,
      gunlukCiro:     gunCiro,
      haftalikCiro:   haftaCiro,
      aylikCiro:      aylikCiro,
      gunlukGider:    gunG,
      netKar:         kar.netKar,
      mustBakiye:     mustBak,
      kasaBakiye:     kasaB,
      brutKar:        kar.brutKar,
      brutMarjOrani:  kar.marjOrani,
      toplamAlacak:   alacakBorc.alacak,
      toplamBorc:     alacakBorc.borc,
      nakitBugun:     (gunIst['nakit'] as num?)?.toDouble() ?? 0,
      kartBugun:      (gunIst['kart'] as num?)?.toDouble() ?? 0,
      cariSatisBugun: (gunIst['cari'] as num?)?.toDouble() ?? 0,
      onayBekleyen:   onayB,
      syncBekleyen:   syncB,
      riskliCariSayisi: riskliSayi,
      haftaData:      haftaD,
      kritikUrunler:  kritik.take(5).map((u) => {
        'ad': u.urunAdi as String,
        'stok': u.stok as double,
        'min': u.minimumStok as double,
      }).toList(),
      yuklenmeTarihi: DateTime.now(),
    );
  }

  Future<void> yenile() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

// Granular
@riverpod
double gunlukCiro(GunlukCiroRef ref) =>
    ref.watch(dashboardProvider).valueOrNull?.gunlukCiro ?? 0;
