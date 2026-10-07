// lib/ekranlar/borc/widgets/borc_odeme_baslatici.dart
//
// Borç ödeme penceresini açan TEK giriş noktası (Borç Merkezi, Borç Takip,
// Borç Detayı ve /borc-odeme rotası bunu kullanır).
//
// 🔴 DÜZELTME (derin analiz 2026-10-07): bu dört ekran banka/kart listesini
// aynı kodu kopyalayarak, HİÇBİR hata yakalama olmadan yüklüyordu. Liste
// okunamadığında (ör. yükseltilmiş cihazda şema farkı, kilitli veritabanı)
// hata sessizce kayboluyor: ödeme penceresi hiç açılmıyor, /borc-odeme
// rotası ise sonsuza dek "yükleniyor"da kalıyordu. Artık tek bir başlatıcı
// var; hata kullanıcıya anlaşılır metinle bildiriliyor.
import 'package:flutter/material.dart';

import '../../../cekirdek/utils/hata_utils.dart';
import '../../../depolar/banka_hesap_deposu.dart';
import '../../../depolar/kredi_karti_deposu.dart';
import '../../../modeller/banka_hesap_model.dart';
import '../../../modeller/borc_model.dart';
import '../../../modeller/kredi_karti_model.dart';
import '../../../servisler/bildirim_servisi.dart';
import 'borc_odeme_bottom_sheet.dart';

/// Ödeme penceresinin seçenek olarak sunduğu hesaplar.
class BorcOdemeKaynaklari {
  final List<BankaHesapModel> bankaHesaplari;
  final List<KrediKartiModel> krediKartlari;

  const BorcOdemeKaynaklari({
    required this.bankaHesaplari,
    required this.krediKartlari,
  });

  /// Aktif banka hesaplarını ve kredi kartlarını yükler. Hata fırlatabilir.
  static Future<BorcOdemeKaynaklari> yukle() async {
    final bankaHesaplari = await BankaHesapDeposu().tumunuGetir();
    final krediKartlari = await KrediKartiDeposu().tumunuGetir();
    return BorcOdemeKaynaklari(
      bankaHesaplari: bankaHesaplari,
      krediKartlari: krediKartlari,
    );
  }
}

/// [borc] için ödeme penceresini açar. Ödeme kaydedildiyse `true` döner;
/// vazgeçildiyse veya hesaplar yüklenemediyse (kullanıcıya bildirilir)
/// `false` döner.
Future<bool> borcOdemePenceresiAc(BuildContext context, BorcModel borc) async {
  final BorcOdemeKaynaklari kaynaklar;
  try {
    kaynaklar = await BorcOdemeKaynaklari.yukle();
  } catch (e) {
    if (context.mounted) {
      BildirimServisi.hata(context,
          'Banka hesapları / kredi kartları yüklenemedi: ${kullaniciyaHataMetni(e)}');
    }
    return false;
  }
  if (!context.mounted) return false;

  var odemeYapildi = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BorcOdemeBottomSheet(
      borc: borc,
      bankaHesaplari: kaynaklar.bankaHesaplari,
      krediKartlari: kaynaklar.krediKartlari,
      onOdemeYapildi: () => odemeYapildi = true,
    ),
  );
  return odemeYapildi;
}
