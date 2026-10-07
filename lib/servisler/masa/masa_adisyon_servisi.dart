// lib/servisler/masa/masa_adisyon_servisi.dart
//
// Masa adisyonunun (ön hesap fişi) oluşturulması ve yazdırma kaydı —
// masa_detay_ekrani.dart'tan ayrıldı (2026-10-07 refactor): ekran yalnız
// yazdırmayı tetikler, fiş/log üretimi burada.
import '../../cekirdek/utils/para_utils.dart';
import '../../depolar/adisyon_log_deposu.dart';
import '../../modeller/masa_siparis_model.dart';
import '../../modeller/satis_kalem_model.dart';
import '../../modeller/satis_model.dart';
import '../auth_servisi.dart';
import '../belge_no_servisi.dart';

class MasaAdisyonServisi {
  MasaAdisyonServisi._();

  /// Sipariş kalemlerinden yazdırılacak adisyon fişi. Fiş no, satış
  /// fişleriyle AYNI kalıcı sayaçtan gelir — çok terminalli restoranda zaman
  /// damgalı numaranın çakışma riski yok.
  static Future<SatisModel> fisOlustur(MasaSiparisModel siparis,
      {required String masaAdi}) async {
    final kalemler = [
      for (final k in siparis.kalemler)
        SatisKalemModel(
          satisId: 0,
          urunId: k.urunId,
          urunAdi: k.urunAdi,
          barkod: null,
          miktar: k.miktar,
          birimFiyat: k.birimFiyat,
          toplamTutar: k.toplam,
          iskontoOran: 0,
          iskontoTutar: 0,
          kdvOran: k.kdvOran,
          kdvTutar: ParaUtils.yuvarla(ParaUtils.kdvPayiCikar(k.toplam, k.kdvOran)),
          netFiyat: k.birimFiyat,
          alisFiyat: 0,
          alisFiyatKdv: 0,
        ),
    ];
    return SatisModel(
      fisNo: await BelgeNoServisi().uret('masa'),
      tarih: DateTime.now(),
      genelToplam: siparis.hesaplananToplam,
      odemeYontemi: 'Adisyon',
      kalemler: kalemler,
      aciklama: 'Masa: $masaAdi - Adisyon',
    );
  }

  /// Yazdırılan adisyonun kaydı. Best-effort: log hatası yazdırmayı bozmaz.
  static Future<void> logKaydet(int siparisId) async {
    try {
      await AdisyonLogDeposu().kaydet(
        siparisId: siparisId,
        adisyonNo: adisyonNo(DateTime.now()),
        yazdiranKullaniciId: AuthServisi().aktifId,
      );
    } catch (_) {/* asıl işlem devam etsin */}
  }

  /// Yalnız harf, rakam ve tire içeren adisyon numarası.
  static String adisyonNo(DateTime an) =>
      'ADY-${an.millisecondsSinceEpoch}'.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
}
