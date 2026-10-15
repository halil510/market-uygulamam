// lib/servisler/iade_fis_yazdirma.dart
//
// 🆕 İADE FİŞİ YAZDIRMA (kullanıcı bulgusu — "cari'de iade fişi
// yazdırılmıyor, satışlarda yazdırılıyor"):
//
// Cari ekstresinde Satış → fisYazdir, Tahsilat/Ödeme → makbuzYazdir ile
// basılıyordu; İade hareketlerinin basılacak belgesi yoktu. Bu sınıf bir
// cari hareketinden (veya fiş id + fiş tipinden) iade belgesini okuyup
// YazdirmaServisi.iadeFisiYazdir ile basar. Üç tür desteklenir:
//   • müşteri iadesi        → MUSTERI IADE FISI
//   • bayiden iade alındı   → BAYI IADE FISI
//   • tedarikçiye iade      → TEDARIKCIYE IADE FISI
//
// Kalem/başlık okuma mantığı FisDetayDeposu'ndadır (fiş detay ekranıyla
// AYNI kaynak) — böylece ekranda görünen iade ile basılan iade aynıdır.
import '../depolar/cari_deposu.dart';
import '../depolar/fis_detay_deposu.dart';
import '../depolar/iade_deposu.dart';
import '../modeller/cari_hareket_model.dart';
import '../modeller/cari_model.dart';
import 'yazdirma_servisi.dart';

class IadeFisiYazdirici {
  /// Cari hareket satırı yazdırılabilir bir İADE belgesi mi?
  /// ('Tedarikçi İadesi İptali' gibi salt-audit satırlarının belgesi yok.)
  static const yazdirilabilirFisTipleri = {
    'İade', 'Alım İadesi', 'Tedarikçi İadesi', 'Satış İade', 'Iade',
  };

  static bool iadeMi(String fisTipi) =>
      yazdirilabilirFisTipleri.contains(fisTipi);

  /// Cari hareketinden iade fişini basar. [cariUnvan] verilmezse belgenin
  /// cari adı kullanılır. Hata durumunda exception fırlatır (çağıran
  /// ekran kullanıcıya gösterir).
  static Future<void> hareketten(
    CariHareketModel h, {
    String? cariUnvan,
  }) async {
    if (h.fisId == null) {
      throw Exception('Bu iadenin fiş bilgisi bulunamadı');
    }
    // Hareketin bakiye etkisi — müşteri iadesi 'Nakit/Kart' ödenmişse
    // borç=alacak (bakiyeyi etkilemez); o durumda hesap özeti basılmaz.
    double? onceki, son;
    if ((h.borc - h.alacak).abs() > 0.005) {
      final b = await CariDeposu().bakiyeHareketAninda(h);
      onceki = b.oncekiBakiye;
      son = b.sonBakiye;
    }
    await _bas(
      fisId: h.fisId!,
      fisTipi: h.fisTipi,
      cariUnvan: cariUnvan,
      odemeYontemi: h.odemeTuru,
      kullanici: h.kullanici,
      oncekiBakiye: onceki,
      sonBakiye: son,
    );
  }

  /// Fiş detay ekranından (fis_id + fis_tipi) iade fişini basar.
  static Future<void> fisten({
    required int fisId,
    required String fisTipi,
    String? cariUnvan,
  }) =>
      _bas(fisId: fisId, fisTipi: fisTipi, cariUnvan: cariUnvan);

  static Future<void> _bas({
    required int fisId,
    required String fisTipi,
    String? cariUnvan,
    String? odemeYontemi,
    String? kullanici,
    double? oncekiBakiye,
    double? sonBakiye,
  }) async {
    final sonuc = await FisDetayDeposu().getir(fisId: fisId, fisTipi: fisTipi);
    final fis = sonuc.fis;
    if (fis == null) {
      throw Exception('İade bulunamadı (silinmiş olabilir)');
    }
    if (sonuc.kalemler.isEmpty) {
      throw Exception('İadenin kalem bilgisi bulunamadı');
    }

    // ── Tür tespiti ───────────────────────────────────────────────────
    final cariId = (fis['cari_id'] as num?)?.toInt();
    CariModel? cari;
    if (cariId != null) cari = await CariDeposu().idileGetir(cariId);

    final String tur;
    if (fisTipi == 'Tedarikçi İadesi') {
      tur = 'tedarikci';
    } else if (cari != null && cariSafTedarikciMi(cari.cariTipi)) {
      tur = 'tedarikci';
    } else if (cari != null && cariBayiMi(cari)) {
      tur = 'bayi';
    } else {
      tur = 'musteri';
    }

    // Ödeme şekli: hareketten gelmediyse (fiş detay / iade geçmişi)
    // iadenin cari hareketinden okunur; tedarikçi iadesi hep 'Cari'
    // (borçtan düşülür).
    var odeme = odemeYontemi;
    if (odeme == null || odeme.isEmpty) {
      if (tur == 'tedarikci') {
        odeme = 'Cari';
      } else if (cariId != null) {
        odeme = await IadeDeposu().iadeOdemeYontemiGetir(fisId, cariId);
      }
    }

    final toplam = _d(fis['toplam_tutar'] ?? fis['genel_toplam']) > 0
        ? _d(fis['toplam_tutar'] ?? fis['genel_toplam'])
        : sonuc.kalemler.fold<double>(0, (s, k) => s + _d(k['toplam_tutar']));

    final tarih = DateTime.tryParse('${fis['tarih'] ?? ''}') ?? DateTime.now();
    final neden = '${fis['iade_nedeni'] ?? fis['aciklama'] ?? ''}'.trim();

    await YazdirmaServisi().iadeFisiYazdir(
      iadeTuru: tur,
      fisNo: '${fis['fis_no'] ?? fis['iade_no'] ?? ''}',
      tarih: tarih,
      cariUnvan: (cariUnvan != null && cariUnvan.isNotEmpty)
          ? cariUnvan
          : (cari?.unvan ?? '${fis['cari_adi'] ?? ''}'),
      kalemler: sonuc.kalemler,
      toplam: toplam,
      odemeYontemi: odeme,
      aciklama: neden.isEmpty ? null : neden,
      kullanici: kullanici,
      oncekiBakiye: oncekiBakiye,
      sonBakiye: sonBakiye,
    );
  }

  static double _d(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
}
