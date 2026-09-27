// lib/servisler/senkron_sonrasi_mutabakat.dart
//
// "Buluttan Al" SONRASI türetilmiş değerlerin hareketlerden yeniden
// hesaplanması — tek merkez.
//
// 🔴 ÇOKLU TERMİNAL DÜZELTMESİ (2026-09-27): bu adımlar ÖNCEDEN yalnızca
// Ayarlar > Bulut Senkronizasyon ekranındaki "Buluttan Al" butonunda
// çalışıyordu. Ana ekrandaki hızlı senkron butonu ve masa ekranının
// otomatik çekmesi hiçbirini çalıştırmıyordu; CARİ BAKİYE mutabakatı ise
// hiçbir yolda yoktu. Oysa cari bakiyesini güncelleyen tetikleyici yalnızca
// INSERT'te çalışıyor: başka kasada iptal edilen bir tahsilat (is_deleted=1
// güncellemesi) ya da buluttan gelen cari satırı bu kasadaki bakiyeyi
// bayat/yanlış bırakıyordu. Artık SupabaseSyncServisi.buluttanAl her
// çağrıldığında (hangi ekrandan olursa olsun), bir şey indiyse bunlar
// çalışır.
import 'package:flutter/foundation.dart';
import '../depolar/borc_deposu.dart';
import '../depolar/cari_deposu.dart';
import '../depolar/kredi_karti_deposu.dart';
import '../depolar/masa_deposu.dart';
import '../depolar/stok_deposu.dart';
import 'log_servisi.dart';
import 'puan_servisi.dart';

class SenkronSonrasiMutabakat {
  SenkronSonrasiMutabakat._();

  static Future<void> calistir({void Function(String)? log}) async {
    Future<void> adim(String etiket, Future<int> Function() islem) async {
      try {
        final n = await islem();
        if (n > 0) log?.call('🔧 $etiket: $n kayıt düzeltildi');
      } catch (e, st) {
        LogServisi().hata('SenkronSonrasiMutabakat($etiket)', hata: e, yigin: st);
        if (kDebugMode) debugPrint('Mutabakat hatası ($etiket): $e');
      }
    }

    // Aynı cari kodunu farklı kasalarda alan cariler.
    await adim('Mükerrer cari kodu', () => CariDeposu().mukerrerKodlariDuzelt());
    // Cari bakiye = SUM(borç − alacak), hareketlerden.
    await adim('Cari bakiye', () => CariDeposu().bakiyeMutabakatYap());
    // Stok = stok hareketlerinin toplamı.
    await adim('Stok', () => StokDeposu().stokMutabakatYap());
    await adim('Masa sipariş toplamı', () => MasaDeposu().siparisToplamlariMutabakatYap());
    await adim('Borç ödenen tutar', () => BorcDeposu().odemeMutabakatYap());
    await adim('Kredi kartı limiti', () => KrediKartiDeposu().limitMutabakatYap());
    await adim('Müşteri puanı', () => PuanServisi().puanMutabakatYap());
  }
}
