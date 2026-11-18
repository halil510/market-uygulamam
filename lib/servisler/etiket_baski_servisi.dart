// lib/servisler/etiket_baski_servisi.dart
//
// Etiketleri SEÇİLİ tasarım ve SEÇİLİ yazıcıyla basar. Etiket Yazdırma listesi, önizleme penceresi ve ürün
// ekranlarındaki "Etiket yazdır" düğmeleri hep bunu çağırır (aynı ürün her yerden aynı etiketle çıkar).
// BuildContext almaz: yazıcı seçtirmek / kâğıt boyu uyarısı gibi sorular [EtiketBaskiSorulari] ile ekrana sorulur.
//
// Basma yolları (her yolda etiket önce PDF'e çizilir, yazıcı çözünürlüğünde resme çevrilir → önizlemeyle birebir):
//   • Etiket yazıcısı (TSPL — Xprinter XP-490B vb.): kendi ağ adresine ya da bağlı yazıcıya BITMAP komutu.
//   • Fiş yazıcısı (ESC/POS): bağlı termal yazıcıya resim.
//   • Windows yazıcısı: sürücünün kendi etiket ayarlarıyla GDI (printing eklentisi XP-490B'de boş etiket döküyordu).

import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' show PaperSize;
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../cekirdek/etiket/raf_etiket_sablonlari.dart';
import '../cekirdek/etiket/tspl.dart';
import '../cekirdek/etiket/zpl_resim.dart';
import '../modeller/urun_model.dart';
import 'etiket_ag_gonderici.dart';
import 'etiket_ayarlari.dart';
import 'raf_etiket_pdf_servisi.dart';
import 'windows_etiket_yazici.dart';
import 'yazdirma_servisi.dart';

/// Fiş yazıcısının basım alanı (nokta, 203 dpi).
int _fisNokta(PaperSize k) => k == PaperSize.mm58 ? 384 : 576;

/// ESC/POS yolunda etiketin kâğıda sığacağı çözünürlük: resim ölçeklenmeden basılır (ölçekleme barkodu bozar).
double fisDpi(double etiketGenislikMm, PaperSize kagit) {
  final sigan = _fisNokta(kagit) * 25.4 / etiketGenislikMm;
  return sigan < varsayilanDpi ? sigan.floorToDouble() : varsayilanDpi;
}

/// Basım sırasında kullanıcıya sorulacaklar (ekran doldurur).
abstract class EtiketBaskiSorulari {
  /// Windows yazıcısı seçilmemiş ya da artık yok: kullanıcı seçsin. Vazgeçerse null.
  Future<String?> windowsYaziciSec();

  /// Sürücünün kâğıt boyu etikete uymuyor: yine de basılsın mı?
  Future<bool> sayfaUyumsuz(String yazici, YaziciSayfasi sayfa, double genislik, double uzunluk);
}

class EtiketBaskiHatasi implements Exception {
  final String mesaj;

  /// Yazıcı ayarlanmamış (ekran "Yazıcı ayarları"nı açmayı önerir).
  final bool ayarEksik;
  EtiketBaskiHatasi(this.mesaj, {this.ayarEksik = false});
  @override
  String toString() => mesaj;
}

class EtiketBaskiSonucu {
  final int basilan; // gönderilen etiket sayısı
  final EtiketDenetimi denetim;
  final String yazici; // nereye gönderildi
  final bool iptal; // kullanıcı vazgeçti
  const EtiketBaskiSonucu(this.basilan, this.denetim, this.yazici, {this.iptal = false});
}

class EtiketBaskiServisi {
  EtiketBaskiServisi._();

  static final _yazdirma = YazdirmaServisi();
  static bool get _windows => !kIsWeb && Platform.isWindows;

  /// Ürünlerden etiket verisi (adet kadar) ve denetim.
  static ({List<EtiketVeri> basilacak, EtiketDenetimi denetim}) hazirla(List<(UrunModel, int)> kalemler, EtiketSablonu s) {
    final veriler = [for (final (u, adet) in kalemler) (etiketVerisi(u), adet)];
    final denetim = etiketDenetle(s, [for (final (v, _) in veriler) v]);
    final gecen = denetim.basilacak.toSet();
    return (
      basilacak: [
        for (final (v, adet) in veriler)
          if (gecen.contains(v))
            for (var i = 0; i < adet.clamp(0, 999); i++) v,
      ],
      denetim: denetim,
    );
  }

  /// Firma adı (etiketteki {firma}).
  static Future<String> firmaAdi() async {
    await _yazdirma.ayarlariYukle();
    return _yazdirma.firmaAdiOnizleme;
  }

  /// [kalemler] (ürün, adet) seçili ya da verilen tasarım / yazıcı ayarıyla basılır.
  static Future<EtiketBaskiSonucu> bas(
    List<(UrunModel, int)> kalemler, {
    required EtiketBaskiSorulari sorular,
    EtiketSablonu? sablon,
    EtiketYaziciAyari? ayar,
  }) async {
    final s = sablon ?? await EtiketAyarlari.seciliTasarim();
    var a = ayar ?? await EtiketAyarlari.yaziciYukle();
    final (:basilacak, :denetim) = hazirla(kalemler, s);
    if (basilacak.isEmpty) return EtiketBaskiSonucu(0, denetim, '');
    final firma = await firmaAdi();

    switch (a.yontem) {
      case RafBasmaYontemi.windows:
        if (!_windows) throw EtiketBaskiHatasi('Windows yazıcısı yalnız bilgisayarda kullanılabilir', ayarEksik: true);
        var ad = a.windowsYazici;
        if (ad.isNotEmpty) {
          final hepsi = await Printing.listPrinters();
          if (!hepsi.any((e) => e.name == ad)) ad = ''; // yazıcı kaldırılmış / adı değişmiş
        }
        if (ad.isEmpty) {
          final secilen = await sorular.windowsYaziciSec();
          if (secilen == null || secilen.isEmpty) return EtiketBaskiSonucu(0, denetim, '', iptal: true);
          ad = secilen;
          a = a.kopya(windowsYazici: ad);
          await EtiketAyarlari.yaziciKaydet(a); // bir kez seçilen yazıcıyla devam edilir
        }
        final kagit = a.kagit;
        final (g, u) = kagit == RafEtiketKagidi.a4 ? (210.0, 297.0) : (s.genislik, s.yukseklik);
        final sayfa = windowsSayfaSorgula(ad, g, u);
        if (!sayfa.uyar(g, u) && !await sorular.sayfaUyumsuz(ad, sayfa, g, u)) {
          return EtiketBaskiSonucu(0, denetim, ad, iptal: true);
        }
        final pdf = await RafEtiketPdfServisi.pdf(basilacak, s, kagit: kagit, mensei: a.mensei, firma: firma, dpi: sayfa.dpi);
        final n = await windowsYazdir(ad, pdf, genislik: g, uzunluk: u);
        if (n <= 0) throw EtiketBaskiHatasi('"$ad" yazıcısına gönderilemedi');
        return EtiketBaskiSonucu(basilacak.length, denetim, ad);

      case RafBasmaYontemi.tspl:
        if (!a.tsplAgda && !_yazdirma.bagliMi) {
          throw EtiketBaskiHatasi(
            'Etiket yazıcısı ayarlanmamış: etiket yazıcısının adresini (IP) yazın '
            'ya da Ayarlar > Yazıcılar bölümünden yazıcıyı bağlayın.',
            ayarEksik: true,
          );
        }
        final is_ = await tsplHazirla(basilacak, s, a, firma: firma);
        if (a.tsplAgda) {
          await etiketAgaGonder(a.tsplAdres, is_);
          return EtiketBaskiSonucu(basilacak.length, denetim, a.tsplAdres);
        }
        await _yazdirma.tsplGonder(is_);
        return EtiketBaskiSonucu(basilacak.length, denetim, _yazdirma.baglantiDurumu);

      case RafBasmaYontemi.escpos:
        if (!_yazdirma.bagliMi) {
          throw EtiketBaskiHatasi('Fiş yazıcısı bağlı değil. Ayarlar > Yazıcılar bölümünden bağlayın.', ayarEksik: true);
        }
        final kagit = s.genislik > 58 ? PaperSize.mm80 : PaperSize.mm58;
        final dpi = fisDpi(s.genislik, kagit);
        final pdf = await RafEtiketPdfServisi.pdf(basilacak, s, mensei: a.mensei, firma: firma, dpi: dpi);
        final resimler = await RafEtiketPdfServisi.resimler(pdf, dpi: dpi);
        await _yazdirma.resimEtiketleriYazdir(resimler, kagit: kagit);
        return EtiketBaskiSonucu(basilacak.length, denetim, _yazdirma.baglantiDurumu);
    }
  }

  /// Etiketlerin 203 dpi tek renkli resimleri (TSPL / ZPL için).
  static Future<List<TsplResim>> _tekRenk(List<EtiketVeri> liste, EtiketSablonu s, {required String mensei, required String firma}) async {
    const dpi = varsayilanDpi;
    final pdf = await RafEtiketPdfServisi.pdf(liste, s, mensei: mensei, firma: firma, dpi: dpi);
    final sonuc = <TsplResim>[];
    await for (final r in Printing.raster(pdf, dpi: dpi)) {
      sonuc.add(tsplResim(r.pixels, r.width, r.height));
    }
    return sonuc;
  }

  static Future<Uint8List> tsplHazirla(List<EtiketVeri> liste, EtiketSablonu s, EtiketYaziciAyari a, {required String firma}) async {
    final etiketler = await _tekRenk(liste, s, mensei: a.mensei, firma: firma);
    return tsplIs(etiketler, genislik: s.genislik, uzunluk: s.yukseklik, ayar: a.tspl);
  }

  /// Seçili tasarımla ZPL (Zebra) işi: her etiket grafik olarak (tasarımla birebir).
  static Future<String> zpl(List<(UrunModel, int)> kalemler, EtiketSablonu s, EtiketYaziciAyari a) async {
    final (:basilacak, denetim: _) = hazirla(kalemler, s);
    if (basilacak.isEmpty) return '';
    return zplResimIs(await _tekRenk(basilacak, s, mensei: a.mensei, firma: await firmaAdi()));
  }

  // ── Küçük önizleme resimleri (liste, ayarlar) ──

  static final _onbellek = <String, Uint8List>{};
  static const _onbellekSiniri = 80;

  /// Tek etiketin PNG önizlemesi ([dpi] düşük tutulur: listede hızlı). Aynı istek önbellekten gelir.
  static Future<Uint8List> onizlemePng(EtiketSablonu s, EtiketVeri v,
      {required String mensei, required String firma, double dpi = 140, String? anahtar}) async {
    final k = anahtar;
    if (k != null) {
      final var_ = _onbellek.remove(k);
      if (var_ != null) return _onbellek[k] = var_; // en sona taşı (en son kullanılan)
    }
    final pdf = await RafEtiketPdfServisi.pdf([v], s, mensei: mensei, firma: firma, dpi: dpi);
    Uint8List? png;
    await for (final r in Printing.raster(pdf, dpi: dpi)) {
      png ??= await r.toPng();
    }
    if (png == null) throw Exception('Etiket önizlemesi oluşturulamadı');
    if (k != null) {
      _onbellek[k] = png;
      while (_onbellek.length > _onbellekSiniri) {
        _onbellek.remove(_onbellek.keys.first);
      }
    }
    return png;
  }
}
