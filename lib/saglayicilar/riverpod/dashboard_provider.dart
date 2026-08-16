// lib/saglayicilar/riverpod/dashboard_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/satis_deposu.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/gider_deposu.dart';
import '../../depolar/kasa_deposu.dart';

part 'dashboard_provider.g.dart';

class DashboardVeri {
  final int toplamUrun, kritikStok, toplamMusteri;
  final double gunlukCiro, haftalikCiro, aylikCiro, gunlukGider, netKar, mustBakiye, kasaBakiye;
  final List<Map<String, dynamic>> haftaData, kritikUrunler;
  final DateTime yuklenmeTarihi;

  const DashboardVeri({
    required this.toplamUrun,    required this.kritikStok,
    required this.toplamMusteri, required this.gunlukCiro,
    required this.haftalikCiro,  required this.aylikCiro,
    required this.gunlukGider,   required this.netKar,
    required this.mustBakiye,    required this.kasaBakiye,
    required this.haftaData,     required this.kritikUrunler,
    required this.yuklenmeTarihi,
  });

  bool get gecerli => DateTime.now().difference(yuklenmeTarihi).inMinutes < 5;
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
      CariDeposu().tumunuGetir(limit: 200),
      SatisDeposu().gunlukIstatistik(),
      SatisDeposu().haftaGrafikVerisi(),
      SatisDeposu().tariheGoreGetir(
          DateTime(haftaBas.year, haftaBas.month, haftaBas.day), bugunBit),
      SatisDeposu().tariheGoreGetir(ayBas, bugunBit),
      GiderDeposu().aralikToplamGider(bugunBas, bugunBit),
      KasaDeposu().guncelBakiye(),
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

    final gunCiro   = (gunIst['ciro'] as num?)?.toDouble() ?? 0;
    final haftaCiro = haftaS.fold(0.0, (s, x) => s + ((x.genelToplam as double?) ?? 0));
    final aylikCiro = aylikS.fold(0.0, (s, x) => s + ((x.genelToplam as double?) ?? 0));
    final mustBak   = cariler.fold(0.0, (s, c) => s + ((c.bakiye as double?) ?? 0));

    return DashboardVeri(
      toplamUrun:     ist['toplam'] as int? ?? 0,
      kritikStok:     kritik.length,
      toplamMusteri:  cariler.length,
      gunlukCiro:     gunCiro,
      haftalikCiro:   haftaCiro,
      aylikCiro:      aylikCiro,
      gunlukGider:    gunG,
      netKar:         gunCiro - gunG,
      mustBakiye:     mustBak,
      kasaBakiye:     kasaB,
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
