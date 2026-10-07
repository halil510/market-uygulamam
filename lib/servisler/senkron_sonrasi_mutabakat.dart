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

  /// Her adımın kaynak tabloları — kısmi/anlık çekimde yalnız etkilenen
  /// adımlar çalışsın diye.
  @visibleForTesting
  static const Map<String, Set<String>> adimTablolari = {
    'Mükerrer cari kodu': {'cari'},
    'Cari bakiye': {'cari', 'cari_hareket'},
    'Stok': {'urunler', 'stok_hareket'},
    'Masa sipariş toplamı': {'masalar', 'masa_siparisleri', 'masa_siparis_kalem'},
    'Borç ödenen tutar': {'borclar', 'borc_odemeler'},
    'Kredi kartı limiti': {'kredi_kartlari', 'kredi_karti_hareket'},
    'Müşteri puanı': {'musteri_puan', 'puan_hareket'},
  };

  /// [degisenTablolar] verilirse (kısmi/anlık çekim) yalnız o tablolardan
  /// beslenen adımlar çalışır; null ise hepsi.
  ///
  /// 🔴 DÜZELTME (Bulut Veri Güvenliği Raporu 2026-10-07, Bulgu 11): anlık
  /// dinleyicinin kısmi çekimlerinde (başka kasadan gelen tahsilat, stok
  /// hareketi …) mutabakat HİÇ çalışmıyordu — bakiye/stok bir sonraki tam
  /// çekime kadar yanlış kalıyordu.
  static Future<void> calistir(
      {void Function(String)? log, Set<String>? degisenTablolar}) async {
    Future<void> adim(String etiket, Future<int> Function() islem) async {
      final kaynak = adimTablolari[etiket];
      if (degisenTablolar != null && kaynak != null &&
          kaynak.intersection(degisenTablolar).isEmpty) {
        return;
      }
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
