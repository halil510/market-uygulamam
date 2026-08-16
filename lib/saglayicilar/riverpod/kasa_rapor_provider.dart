// lib/saglayicilar/riverpod/kasa_rapor_provider.dart
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/kasa_deposu.dart';
import '../../modeller/kasa_hareket_model.dart';

part 'kasa_rapor_provider.g.dart';

class KasaRaporVeri {
  final double toplamGiris, toplamCikis, netHareket, guncelBakiye;
  final List<KasaHareketModel> hareketler;
  const KasaRaporVeri({
    required this.toplamGiris, required this.toplamCikis,
    required this.netHareket,  required this.guncelBakiye,
    required this.hareketler,
  });
}

@riverpod
Future<KasaRaporVeri> kasaRapor(KasaRaporRef ref, DateTimeRange aralik) async {
  final depo       = KasaDeposu();
  final ozet       = await depo.aralikOzet(aralik.start, aralik.end);
  final hareketler = await depo.hareketleriniGetir(baslangic: aralik.start, bitis: aralik.end);
  final giris      = (ozet['giris'] as num?)?.toDouble() ?? 0;
  final cikis      = (ozet['cikis'] as num?)?.toDouble() ?? 0;
  final bakiye     = await depo.guncelBakiye();
  return KasaRaporVeri(
    toplamGiris:  giris,
    toplamCikis:  cikis.abs(),
    netHareket:   giris - cikis.abs(),
    guncelBakiye: bakiye,
    hareketler:   hareketler,
  );
}
