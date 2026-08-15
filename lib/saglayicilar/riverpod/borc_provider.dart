// lib/saglayicilar/riverpod/borc_provider.dart
// v2.0 – DÜZELTME:
//  1) tumBorclarProvider artık ÖDENMİŞ borçları da getiriyor
//     (eskiden BorcDeposu.tumunuGetir() varsayılan sadeceAktif:true
//      kullanıyordu, ödenenler hiç dönmüyordu)
//  2) Kredi kartları (kredi_kartlari tablosu - gerçek kullanılan limit)
//     artık dashboard'a "borç" olarak dahil ediliyor. Bu, borclar
//     tablosundaki manuel 'kredi_karti' türündeki kayıtlardan AYRI
//     bir veri kaynağıdır; ikisi de gösteriliyor ve kaynağı net
//     etiketlendiriliyor (manuel vs kart-limiti).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../depolar/borc_deposu.dart';
import '../../depolar/kredi_karti_deposu.dart';
import '../../modeller/borc_model.dart';
import '../../modeller/kredi_karti_model.dart';

final borcDeposuProvider = Provider<BorcDeposu>((ref) => BorcDeposu());
final krediKartiDeposuProvider = Provider<KrediKartiDeposu>((ref) => KrediKartiDeposu());

final borcOzetProvider = FutureProvider<Map<String, double>>((ref) async {
  final depo = ref.watch(borcDeposuProvider);
  final ozet = await depo.ozetGetir();

  // Kredi kartı kullanılan limitlerini de "kalan borç" ve "toplam borç"a ekle
  final kartlar = await ref.watch(krediKartlariToplamProvider.future);

  return {
    'toplam_borc': (ozet['toplam_borc'] ?? 0) + kartlar['toplam_limit_kullanimi']!,
    'toplam_odenen': ozet['toplam_odenen'] ?? 0,
    'kalan_borc': (ozet['kalan_borc'] ?? 0) + kartlar['toplam_limit_kullanimi']!,
    'gecmis_borc': ozet['gecmis_borc'] ?? 0,
    // Sadece borclar tablosundaki (manuel) tutarlar, kart hariç -
    // bazı ekranlarda saf "borclar" tablosu özetini görmek isteyebiliriz
    'manuel_toplam_borc': ozet['toplam_borc'] ?? 0,
    'manuel_kalan_borc': ozet['kalan_borc'] ?? 0,
    'kredi_karti_borcu': kartlar['toplam_limit_kullanimi']!,
  };
});

/// Tüm aktif kredi kartlarının kullanılan limit toplamı (= güncel kart borcu)
final krediKartlariToplamProvider = FutureProvider<Map<String, double>>((ref) async {
  final depo = ref.watch(krediKartiDeposuProvider);
  try {
    final kartlar = await depo.tumunuGetir();
    final toplamKullanim = kartlar.fold<double>(0, (s, k) => s + k.kullanilanLimit);
    final toplamLimit = kartlar.fold<double>(0, (s, k) => s + k.kartLimit);
    return {
      'toplam_limit_kullanimi': toplamKullanim,
      'toplam_limit': toplamLimit,
      'kart_sayisi': kartlar.length.toDouble(),
    };
  } catch (_) {
    return {'toplam_limit_kullanimi': 0, 'toplam_limit': 0, 'kart_sayisi': 0};
  }
});

/// Tüm aktif kredi kartları (borç dashboard'unda listelemek için)
final tumKrediKartlariProvider = FutureProvider<List<KrediKartiModel>>((ref) async {
  final depo = ref.watch(krediKartiDeposuProvider);
  try {
    return await depo.tumunuGetir();
  } catch (_) {
    return [];
  }
});

final yaklasanBorclarProvider = FutureProvider<List<BorcModel>>((ref) async {
  final depo = ref.watch(borcDeposuProvider);
  return await depo.yaklasanlariGetir(gun: 7);
});

final gecmisBorclarProvider = FutureProvider<List<BorcModel>>((ref) async {
  final depo = ref.watch(borcDeposuProvider);
  return await depo.vadesiGecenleriGetir();
});

/// DÜZELTME: artık hem ödenmemiş hem ödenmiş borçları getiriyor.
/// (sadeceAktif: false → borclar tablosundaki TÜM kayıtlar gelir)
final tumBorclarProvider = FutureProvider<List<BorcModel>>((ref) async {
  final depo = ref.watch(borcDeposuProvider);
  return await depo.tumunuGetir(sadeceAktif: false);
});

/// Sadece ödenmemiş (aktif) borçlar — eski davranışı koruyan ayrı provider
final aktifBorclarProvider = FutureProvider<List<BorcModel>>((ref) async {
  final depo = ref.watch(borcDeposuProvider);
  return await depo.tumunuGetir(sadeceAktif: true);
});

/// Sadece ödenmiş borçlar
final odenenBorclarProvider = FutureProvider<List<BorcModel>>((ref) async {
  final tum = await ref.watch(tumBorclarProvider.future);
  return tum.where((b) => b.odendi).toList();
});

// ---- DASHBOARD: Mail'i BEKLEME, sadece temel verileri paralel getir ----
class BorcDashboardVeri {
  final Map<String, double> ozet;
  final List<BorcModel> gecmis;
  final List<BorcModel> yaklasan;
  final List<BorcModel> tumBorclar;
  final List<KrediKartiModel> krediKartlari;

  const BorcDashboardVeri({
    required this.ozet,
    required this.gecmis,
    required this.yaklasan,
    required this.tumBorclar,
    required this.krediKartlari,
  });
}

final borcDashboardProvider = FutureProvider<BorcDashboardVeri>((ref) async {
  final ozetF = ref.watch(borcOzetProvider.future);
  final gecmisF = ref.watch(gecmisBorclarProvider.future);
  final yaklasanF = ref.watch(yaklasanBorclarProvider.future);
  final tumF = ref.watch(tumBorclarProvider.future);
  final kartlarF = ref.watch(tumKrediKartlariProvider.future);

  final results = await Future.wait([ozetF, gecmisF, yaklasanF, tumF, kartlarF]);

  return BorcDashboardVeri(
    ozet: results[0] as Map<String, double>,
    gecmis: results[1] as List<BorcModel>,
    yaklasan: results[2] as List<BorcModel>,
    tumBorclar: results[3] as List<BorcModel>,
    krediKartlari: results[4] as List<KrediKartiModel>,
  );
});