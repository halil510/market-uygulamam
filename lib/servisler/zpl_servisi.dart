// lib/servisler/zpl_servisi.dart
// SRP: Ürün etiketlerini ZPL II (Zebra Programlama Dili) formatında üretir.
//
// Neden ZPL?
//   BarTender'a doğrudan API/driver entegrasyonu Flutter'dan mümkün değil
//   (Windows COM/SDK gerektirir). Ancak BarTender ve hemen hemen tüm Zebra
//   uyumlu etiket yazıcılar/yazılımlar ZPL dosyalarını "şablon" veya
//   "doğrudan yazdır" olarak kabul eder. Bu servis, MarketPlus'taki ürün
//   verisinden hazır ZPL komutları üretir; kullanıcı bu .zpl dosyasını
//   BarTender'a (Yazdır > Dosyadan Yazdır / Native Printer Command) verebilir
//   veya ZPL destekleyen bir yazıcıya (USB/ağ) doğrudan gönderebilir.
//
// Koordinat sistemi: ZPL "dot" birimi kullanır. Standart Zebra yazıcılarda
// 203 dpi (8 dot/mm) yaygındır — bu servis 203 dpi varsayar.

import '../modeller/urun_model.dart';

class ZplServisi {
  static const int _dpmm = 8; // 203 dpi ≈ 8 dot/mm

  /// Tek bir ürün için ZPL etiket komutu üretir.
  /// [genislikMm]/[yukseklikMm]: etiket boyutu (mm).
  static String etiketZpl(
    UrunModel urun, {
    required double genislikMm,
    required double yukseklikMm,
    bool barkodGoster = true,
    bool fiyatGoster = true,
    bool adGoster = true,
    int adet = 1,
    bool firmaGoster = false,
    String? firmaAdi,
    bool anaGrupGoster = false,
    bool lotNoGoster = false,
    bool sktGoster = false,
    bool aciklamaGoster = false,
    bool kdvDahilFiyat = true,
    // 🔴 DÜZELTME (kullanıcı bulgusu — Ayarlar sekmesindeki "Birim Fiyatlı
    // Mod" anahtarı ZPL çıktısına hiç yansımıyordu; sadece termal (ESC/POS)
    // yolunda çalışıyordu). Açıkken fiyat satırı yerine "birim adı | fiyat"
    // yan yana basılır (ör. "Kg   45.00 TL").
    bool birimFiyatliMod = false,
    String? ozelMetin,
    double fontOlcek = 1.0,
  }) {
    final w = (genislikMm * _dpmm).round();
    final h = (yukseklikMm * _dpmm).round();
    final buf = StringBuffer();
    int fs(int base) => (base * fontOlcek).round();

    buf.writeln('^XA'); // Etiket başlangıcı
    buf.writeln('^PW$w'); // Yazdırma genişliği (dot)
    buf.writeln('^LL$h'); // Etiket uzunluğu (dot)
    buf.writeln('^CI28'); // UTF-8 — Türkçe karakter desteği

    var y = 20;

    if (adGoster) {
      final ad = _zplKacis(_kisalt(urun.urunAdi, 32));
      final s = fs(28);
      buf.writeln('^FO10,$y^A0N,$s,$s^FD$ad^FS');
      y += (36 * fontOlcek).round();
    }

    if (anaGrupGoster && (urun.anaGrup?.isNotEmpty ?? false)) {
      final s = fs(18);
      buf.writeln('^FO10,$y^A0N,$s,$s^FD${_zplKacis(_kisalt(urun.anaGrup!, 32))}^FS');
      y += (24 * fontOlcek).round();
    }

    if (barkodGoster && urun.barkod != null && urun.barkod!.isNotEmpty) {
      // Code128 barkod, altında insan-okunabilir metin
      buf.writeln('^FO10,$y^BY2');
      buf.writeln('^BCN,60,Y,N,N');
      buf.writeln('^FD${urun.barkod}^FS');
      y += 80;
    }

    if (lotNoGoster && (urun.lotNo?.isNotEmpty ?? false)) {
      final s = fs(18);
      buf.writeln('^FO10,$y^A0N,$s,$s^FDLot: ${_zplKacis(_kisalt(urun.lotNo!, 26))}^FS');
      y += (24 * fontOlcek).round();
    }

    if (sktGoster && (urun.sonKullanmaTarihi?.isNotEmpty ?? false)) {
      final s = fs(18);
      buf.writeln('^FO10,$y^A0N,$s,$s^FDSKT: ${_zplKacis(_kisalt(urun.sonKullanmaTarihi!, 26))}^FS');
      y += (24 * fontOlcek).round();
    }

    if (aciklamaGoster && (urun.lotAciklama?.isNotEmpty ?? false)) {
      final s = fs(16);
      buf.writeln('^FO10,$y^A0N,$s,$s^FD${_zplKacis(_kisalt(urun.lotAciklama!, 34))}^FS');
      y += (22 * fontOlcek).round();
    }

    if (fiyatGoster) {
      final taban = urun.satisFiyati;
      final kdv = double.tryParse(urun.kdvOran) ?? 0;
      final gosterilecek = kdvDahilFiyat ? taban : taban / (1 + kdv / 100);
      final fiyat = '${gosterilecek.toStringAsFixed(2)} TL';
      if (birimFiyatliMod) {
        // Birim adı solda, fiyat sağda — aynı termal (ESC/POS) yoldaki
        // "Adet/KG + fiyat yan yana" davranışı.
        final birim = urun.birimAdi.isEmpty ? 'Adet' : urun.birimAdi;
        final s = fs(32);
        buf.writeln('^FO10,$y^A0N,$s,$s^FD${_zplKacis(_kisalt(birim, 12))}^FS');
        buf.writeln('^FO${(w * 0.45).round()},$y^A0N,$s,$s^FD$fiyat^FS');
        y += (40 * fontOlcek).round();
      } else {
        final s = fs(40);
        buf.writeln('^FO10,$y^A0N,$s,$s^FD$fiyat^FS');
        y += (48 * fontOlcek).round();
      }
    }

    // 🔴 DÜZELTME (kullanıcı referans tasarımı — raf üstü fiyat etiketi):
    // firma/mağaza adı en altta basılmalı (ör. "DEMAR HİPERMARKET"),
    // ürün adının ÜSTÜNDE değil — önceden en üstteydi.
    if (firmaGoster && (firmaAdi?.isNotEmpty ?? false)) {
      final s = fs(16);
      buf.writeln('^FO10,$y^A0N,$s,$s^FD${_zplKacis(_kisalt(firmaAdi!, 32))}^FS');
      y += (22 * fontOlcek).round();
    }

    if (ozelMetin != null && ozelMetin.trim().isNotEmpty) {
      final s = fs(16);
      buf.writeln('^FO10,$y^A0N,$s,$s^FD${_zplKacis(_kisalt(ozelMetin.trim(), 34))}^FS');
    }

    buf.writeln('^PQ$adet'); // Yazdırma adedi (yazıcı kuyruğunda çoğaltma)
    buf.writeln('^XZ'); // Etiket sonu

    return buf.toString();
  }

  /// Birden fazla ürün/adet için tek bir ZPL dosyası (her etiket art arda).
  static String topluZpl(
    List<({UrunModel urun, int adet})> kalemler, {
    required double genislikMm,
    required double yukseklikMm,
    bool barkodGoster = true,
    bool fiyatGoster = true,
    bool adGoster = true,
    bool firmaGoster = false,
    String? firmaAdi,
    bool anaGrupGoster = false,
    bool lotNoGoster = false,
    bool sktGoster = false,
    bool aciklamaGoster = false,
    bool kdvDahilFiyat = true,
    bool birimFiyatliMod = false,
    String? ozelMetin,
    double fontOlcek = 1.0,
  }) {
    final buf = StringBuffer();
    for (final k in kalemler) {
      buf.write(etiketZpl(
        k.urun,
        genislikMm: genislikMm,
        yukseklikMm: yukseklikMm,
        barkodGoster: barkodGoster,
        fiyatGoster: fiyatGoster,
        adGoster: adGoster,
        adet: k.adet,
        firmaGoster: firmaGoster,
        firmaAdi: firmaAdi,
        anaGrupGoster: anaGrupGoster,
        lotNoGoster: lotNoGoster,
        sktGoster: sktGoster,
        aciklamaGoster: aciklamaGoster,
        kdvDahilFiyat: kdvDahilFiyat,
        birimFiyatliMod: birimFiyatliMod,
        ozelMetin: ozelMetin,
        fontOlcek: fontOlcek,
      ));
    }
    return buf.toString();
  }

  /// ZPL'de özel karakterler (^ ve ~ ve çift tırnak) komut olarak
  /// algılanmasın diye kaçışlanır; Türkçe karakterler ^CI28 ile desteklenir.
  static String _zplKacis(String s) =>
      s.replaceAll('^', ' ').replaceAll('~', ' ').replaceAll('"', "'");

  static String _kisalt(String s, int n) => s.length > n ? s.substring(0, n) : s;
}
