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
  /// [context] hâlâ mounted olmalı. Bu satış için (GİB'e gönderilmiş olsun
  /// olmasın) bir fatura varsa silme ENGELLENIR — döner false, satış
  /// SİLİNMEZ. Kullanıcı, bunun yerine ilgili ekrandan "İade Et" ile ters
  /// kayıt (iade faturası) düzenlemeye yönlendirilmelidir.
  //
  // 🔴 DÜZELTME (kritik — derin denetimde bulundu): Bu fonksiyon ÖNCEDEN
  // sadece GİB'e ZATEN gönderilmiş/onaylanmış faturalarda "Yine de İptal
  // Et" seçenekli bir UYARI gösteriyordu — kullanıcı devam ederse yine de
  // SİLİNİYORDU. Henüz gönderilmemiş (taslak/hata durumunda) bir fatura
  // varsa ise HİÇBİR uyarı bile göstermeden SESSİZCE siliyordu. Bu,
  // codebase'in kendi belgelenmiş kuralıyla ("Zaten fatura kesilmiş bir
  // satış doğrudan silinemez — İade Et'e yönlendirilir", bkz.
  // cari_detay_paneli.dart) ÇELİŞİYORDU — burası da AYNI kurala uydurulup
  // gerçek bir engele (override YOK) çevrildi.
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
      await OnayDialog.goster(
        context,
        baslik: 'Bu Satış Faturalandırılmış',
        icerik:
            'Bu satış için zaten bir fatura kesilmiş${fatura?.faturaNo != null ? ' (${fatura!.faturaNo})' : ''} '
            '— muhasebe ve e-Fatura mevzuatına aykırı olduğu için doğrudan '
            'silinemez. Düzeltme yapmak için "İade Et" ile ters kayıt '
            '(iade faturası) oluşturun.',
        onayYazi: 'Tamam',
        ikon: Icons.info_outline,
        iptalGoster: false,
      );
      return false;
    }
    await SatisDeposu().sil(satisId, neden: neden);
    return true;
  }
}
