// lib/servisler/rapor_servisi.dart
import '../depolar/rapor_deposu.dart';
import '../depolar/satis_deposu.dart';
import '../depolar/gider_deposu.dart';
import '../depolar/kasa_deposu.dart';

class RaporServisi {
  static final RaporServisi _instance = RaporServisi._();
  factory RaporServisi() => _instance;
  RaporServisi._();

  final RaporDeposu  _raporDepo  = RaporDeposu();
  final SatisDeposu  _satisDepo  = SatisDeposu();
  final GiderDeposu  _giderDepo  = GiderDeposu();
  final KasaDeposu   _kasaDepo   = KasaDeposu();

  Future<Map<String, dynamic>> gunSonuRaporu() async {
    final satisIst    = await _satisDepo.gunlukIstatistik();
    final gider       = await _giderDepo.gunlukToplamGider();
    final kasaBakiye  = await _kasaDepo.guncelBakiye();
    final kasaOzet    = await _kasaDepo.gunlukOzet();

    return {
      'ciro':       satisIst['ciro']       ?? 0,
      'satis_say':  satisIst['satis_sayisi'] ?? 0,
      'iskonto':    satisIst['iskonto']    ?? 0,
      'nakit':      satisIst['nakit']      ?? 0,
      'kart':       satisIst['kart']       ?? 0,
      'gider':      gider,
      'net_kar':    (satisIst['ciro'] ?? 0) - gider,
      'kasa':       kasaBakiye,
      'kasa_giris': kasaOzet['giris'] ?? 0,
      'kasa_cikis': kasaOzet['cikis'] ?? 0,
      'tarih':      DateTime.now().toIso8601String(),
    };
  }

  Future<List<Map<String, dynamic>>> enCokSatilan() =>
      _raporDepo.enCokSatilanUrunler();

  Future<Map<String, double>> stokDegerlendirme() =>
      _raporDepo.stokDegerlendirme();
}


