// lib/servisler/satis_iptal_servisi.dart
import 'package:flutter/material.dart';
import '../depolar/satis_deposu.dart';
import '../depolar/fatura_deposu.dart';
import 'faturalandirma_servisi.dart';
import '../widgetlar/ortak/onay_dialog.dart';

/// Bir satışı GÜVENLİ şekilde silen tek nokta — Satış Detayı ekranından
/// VE Cari Detay'dan (satış-kökenli bir cari hareketi silinirken) AYNI
/// koda çıkması için buraya çıkarıldı. Önceden bu mantık sadece
/// satis_detay_ekrani.dart içindeydi; Cari tarafında satış-kökenli bir
/// hareket silinince asıl satışa hiç dokunulmuyordu (bkz. CariDeposu.
/// hareketIptalEt çağrı yorumu) — bu, "cariden sil, satış listede aktif
/// kalır" tutarsızlığına yol açıyordu. Artık her iki ekran da aynı
/// SatisDeposu().sil() akışını (stok geri yükleme + kasa/banka tersine
/// çevirme + cari ters kaydı) ve aynı e-Fatura/GİB güvenlik kontrolünü
/// paylaşıyor.
class SatisIptalServisi {
  /// [context] hâlâ mounted olmalı. Kullanıcı e-Fatura uyarısından
  /// vazgeçerse false döner ve satış SİLİNMEZ.
  static Future<bool> guvenliSil(
    BuildContext context,
    int satisId, {
    required String neden,
  }) async {
    final faturaId =
        await FaturalandirmaServisi.mevcutFaturaId(satisId: satisId);
    if (faturaId != null) {
      if (!context.mounted) return false;
      final fatura = await FaturaDeposu().idileGetir(faturaId);
      final gibeGonderildi = fatura != null &&
          (fatura.eFaturaDurum == 'gonderildi' ||
              fatura.eFaturaDurum == 'onaylandi');
      if (gibeGonderildi) {
        if (!context.mounted) return false;
        final devamEt = await OnayDialog.goster(
          context,
          baslik: 'Bu Satışın Onaylı Bir e-Faturası Var',
          icerik:
              'Bu satış için GİB\'e gönderilmiş ve onaylanmış bir e-Fatura '
              '(${fatura.faturaNo ?? ''}) mevcut. Satışı iptal etmek bu '
              'faturayı OTOMATİK OLARAK iptal ETMEZ — resmi GİB iptali '
              'ayrıca fatura ekranından yapılmalıdır. Satışı yine de iptal '
              'etmek istiyor musunuz?',
          onayYazi: 'Yine de İptal Et',
          onayRengi: Colors.red,
          ikon: Icons.warning_amber_rounded,
        );
        if (!devamEt) return false;
      }
    }
    await SatisDeposu().sil(satisId, neden: neden);
    return true;
  }
}
