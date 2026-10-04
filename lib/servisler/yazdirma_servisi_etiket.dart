// lib/servisler/yazdirma_servisi_etiket.dart
//
// yazdirma_servisi.dart'ın parçası (part/part of) — etiket (ESC/POS, RawBT, ZPL) ve kasa çekmecesi.
// Davranış BİREBİR aynı: YazdirmaServisi üzerine extension; private
// üyelere aynı kütüphane olduğu için erişir.
part of 'yazdirma_servisi.dart';

extension YazdirmaServisiEtiket on YazdirmaServisi {
  // ══════════════════════════════════════════════════════════════════════════
  // ETİKET YAZDIRMA
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> etiketYazdir(
    UrunModel urun, {
    bool barkodGoster    = true,
    bool fiyatGoster     = true,
    bool adGoster        = true,
    bool birimFiyatliMod = false,
    bool indirimliMod    = false,
    double? indirimFiyat,
    PaperSize etiketBoy  = PaperSize.mm58,
    int adet             = 1,
    // Aşağıdaki ayarlar önceden ekranda tanımlı ama hiçbir yere
    // bağlanmamıştı (arayüzde değiştirilse bile etikete yansımıyordu).
    // Artık gerçekten etikete basılıyor.
    bool firmaGoster     = false,
    bool lotNoGoster     = false,
    bool sktGoster       = false,
    bool anaGrupGoster   = false,
    bool kdvDahilFiyat   = true,
    bool aciklamaGoster  = false,
    String? ozelMetin,
    /// Etiketin GERÇEK genişliği (mm) — barkod ve satır uzunluğu buna göre.
    double? etiketGenislikMm,
  }) async {
    await ayarlariYukle();
    final profile   = await _profil();
    final generator = Generator(etiketBoy, profile);

    // 🔴 DÜZELTME (2026-09-28): barkod resmi ÖNCEDEN FİŞ yazıcısının kâğıt
    // ayarına (_kagit) göre boyutlanıyordu — fiş 80 mm, etiket 58 mm (ya da
    // 40x30 gibi küçük sticker) iken barkod kâğıttan taşıp kesiliyor,
    // okunmuyordu. Artık etiketin kendi genişliği kullanılıyor (8 nokta/mm).
    final kagitPx = etiketBoy == PaperSize.mm58 ? 384 : 576;
    final etiketPx = etiketGenislikMm != null && etiketGenislikMm > 0
        ? (etiketGenislikMm * 8).round().clamp(160, kagitPx)
        : kagitPx;
    final barkodPx = (etiketPx * 0.85).round();
    final satirKarakter = (etiketPx / 12).floor().clamp(12, 48); // font A: 12 nokta

    // Tüm adetler TEK pakette gönderilir (önceden her etiket ayrı yazma +
    // 300 ms bekleme idi: 50 etiket ≈ 15 sn ek gecikme).
    final tumBytes = <int>[];
    for (int i = 0; i < adet.clamp(1, 500); i++) {
      final bytes = <int>[];
      if (adGoster) {
        // Kelime sınırından en fazla 2 satır (önceden 24. harfte kesiliyordu).
        for (final satir in EtiketYardimci.satirlaraBol(urun.urunAdi, satirKarakter)) {
          bytes.addAll(generator.text(YazdirmaServisi._t(satir),
              styles: const PosStyles(bold: true, align: PosAlign.center)));
        }
      }
      if (anaGrupGoster && (urun.anaGrup?.isNotEmpty ?? false)) {
        bytes.addAll(generator.text(YazdirmaServisi._t(urun.anaGrup!),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (barkodGoster && urun.barkod != null && urun.barkod!.isNotEmpty) {
        // 🔴 ÜRÜN ETİKETİ BARKODU — fiş barkoduyla AYNI sorunu taşıyordu.
        // `generator.barcode()` (GS k komutu) ucuz termal yazıcıların
        // çoğunda çalışmıyor; etiketlerde de sadece barkod NUMARASI
        // basılıyor, çizgi çıkmıyordu. Artık resim olarak basılıyor.
        bytes.addAll(_barkodBas(generator, urun.barkod!, genislikPx: barkodPx));
      }
      if (lotNoGoster && (urun.lotNo?.isNotEmpty ?? false)) {
        bytes.addAll(generator.text(YazdirmaServisi._t('Lot: ${urun.lotNo}'),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (sktGoster && (urun.sonKullanmaTarihi?.isNotEmpty ?? false)) {
        bytes.addAll(generator.text(YazdirmaServisi._t('SKT: ${urun.sonKullanmaTarihi}'),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (aciklamaGoster && (urun.lotAciklama?.isNotEmpty ?? false)) {
        bytes.addAll(generator.text(YazdirmaServisi._t(urun.lotAciklama!),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (fiyatGoster) {
        final tabanFiyat = indirimliMod && indirimFiyat != null ? indirimFiyat : urun.satisFiyati;
        // KDV Dahil anahtarı: kapalıysa KDV hariç (net) fiyat basılır.
        final kdv = double.tryParse(urun.kdvOran) ?? 0;
        final fiyat = kdvDahilFiyat ? tabanFiyat : tabanFiyat / (1 + kdv / 100);
        bytes.addAll(generator.text(YazdirmaServisi._t('${_fmt.format(fiyat)} TL'),
            styles: const PosStyles(bold: true, align: PosAlign.center,
                height: PosTextSize.size2, width: PosTextSize.size1)));
        // Birim fiyat satırı (1 KG / 1 LT) — bkz. EtiketYardimci.
        if (birimFiyatliMod) {
          final bf = EtiketYardimci.birimFiyatMetni(urun, fiyat);
          bytes.addAll(generator.text(
              YazdirmaServisi._t(bf ?? (urun.birimAdi.isEmpty ? 'Adet' : urun.birimAdi)),
              styles: const PosStyles(align: PosAlign.center)));
        }
      }
      // 🔴 DÜZELTME (kullanıcı referans tasarımı — raf üstü fiyat etiketi):
      // firma/mağaza adı en altta basılmalı (ör. "DEMAR HİPERMARKET"),
      // ürün adının ÜSTÜNDE değil — önceden en üstteydi.
      if (firmaGoster && _firmaAdi.isNotEmpty) {
        bytes.addAll(generator.text(YazdirmaServisi._t(_firmaAdi),
            styles: const PosStyles(bold: false, align: PosAlign.center)));
      }
      if (ozelMetin != null && ozelMetin.trim().isNotEmpty) {
        bytes.addAll(generator.text(YazdirmaServisi._t(ozelMetin.trim()),
            styles: const PosStyles(align: PosAlign.center)));
      }
      bytes.addAll(generator.feed(1));
      bytes.addAll(generator.cut(mode: PosCutMode.partial));
      tumBytes.addAll(bytes);
    }
    await _yazdir(tumBytes);
  }

  // Legacy compat
  Future<void> _rawbtYaz(Uint8List bytes) async {
    final b64 = base64Encode(bytes);
    final encoded = Uri.encodeComponent(b64);
    final uri = Uri.parse('rawbt://print?base64=$encoded');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('RawBT uygulaması bulunamadı');
      }
    } catch (e) {
      throw Exception('RawBT hatası: $e');
    }
  }


  // ══════════════════════════════════════════════════════════════════════════
  // ZEBRA / ZPL — Doğrudan Ağ veya Bluetooth Etiket Yazıcısına Gönderim
  // BarTender'a gerek kalmadan, ZPL komutlarını mevcut bağlı yazıcıya
  // (WiFi:9100 veya BT) ham metin/byte olarak yollar. Yazıcı Zebra/ZPL
  // uyumlu olmalıdır (ZD/GK/GC/TLP serisi vb.).
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> zplGonder(String zpl) async {
    if (_aktif == null || !_aktif!.bagliMi) {
      throw Exception('Etiket yazıcısı bağlı değil. Ayarlar > Yazıcılar bölümünden '
          'Zebra yazıcınızı (WiFi veya Bluetooth) bağlayın.');
    }
    final bytes = utf8.encode(zpl);
    await _yazdir(bytes);
  }

  /// Fiş yazıcısına bağlı para çekmecesini açar (ESC p 0 25 250 — pin 2,
  /// ~50 ms / 500 ms). Çekmece yoksa yazıcı komutu yok sayar.
  Future<void> kasaCekmecesiAc() async {
    if (_aktif == null || !_aktif!.bagliMi) {
      throw Exception('Yazıcı bağlı değil. Ayarlar > Yazdırma bölümünden '
          'fiş yazıcısını bağlayın.');
    }
    await _yazdir(const [0x1B, 0x70, 0x00, 0x19, 0xFA]);
  }

  Future<bool> get yaziciBagliMi async => bagliMi;


  Future<bool> get btBagliMi async => bagliMi && _aktif?.tur == YaziciTur.bluetooth;
}
