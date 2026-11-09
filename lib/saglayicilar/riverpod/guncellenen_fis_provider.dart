// lib/saglayicilar/riverpod/guncellenen_fis_provider.dart
//
// Hızlı Satış'ta geri çağrılıp GÜNCELLENEN fiş (fiş güncelleme modu).
//
// 🔴 DERİN DENETİM (2026-11-09, #23 #24): bu bilgi ÖNCEDEN yalnız ekran
// State'inde (_guncellenenSatis) tutuluyordu, sepet ise keepAlive.
//  • Ekrandan çıkıp dönünce sepet dolu, mod kayıp → aynı ürünler YENİ satış
//    olarak tekrar satılıyordu (stok/kasa/cari ikinci kez).
//  • Askıya Al / Askıdan Yükle / Tedarikçiye Aktar sepeti değiştiriyor ama
//    modu kapatmıyordu → sıradaki müşterinin sepeti eski fişin üzerine
//    yazılıyordu.
// Artık mod sepetle AYNI ömürde (keepAlive) ve sepet her boşaltıldığında
// (Sepet.temizle) kapanır.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../modeller/satis_model.dart';

class GuncellenenFis extends Notifier<SatisModel?> {
  @override
  SatisModel? build() => null;

  void ayarla(SatisModel? satis) => state = satis;
}

final guncellenenFisProvider =
    NotifierProvider<GuncellenenFis, SatisModel?>(GuncellenenFis.new);
