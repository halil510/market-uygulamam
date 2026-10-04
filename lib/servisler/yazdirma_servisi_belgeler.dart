// lib/servisler/yazdirma_servisi_belgeler.dart
//
// yazdirma_servisi.dart'ın parçası (part/part of) — fiş, makbuz, fatura ve test fişi basımı.
// Davranış BİREBİR aynı: YazdirmaServisi üzerine extension; private
// üyelere aynı kütüphane olduğu için erişir.
part of 'yazdirma_servisi.dart';

extension YazdirmaServisiBelgeler on YazdirmaServisi {
  // ══════════════════════════════════════════════════════════════════════════
  // FİŞ YAZDIRMA
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> fisYazdir(SatisModel satis, {
    String? firmaAdi, String? firmaAdres, String? firmaTel, String? altYazi,
    String? cariUnvan, String? kasiyerAdi,
    // 🔴 YENİ (kullanıcı bulgusu): Satış bir cariye (veresiye/hesaba)
    // yapıldıysa, müşterinin fişte önceki ve yeni bakiyesini görmesi
    // gerekiyor — bu iki parametre opsiyonel, sadece cari satışlarda
    // doldurulur.
    double? cariOncekiBakiye, double? cariSonBakiye,
  }) async {
    await ayarlariYukle();
    final profile   = await _profil();
    final generator = Generator(_kagit, profile);

    final fa  = firmaAdi   ?? _firmaAdi;
    final fadr = firmaAdres ?? _firmaAdres;
    final ft  = firmaTel   ?? _firmaTel;
    final ay  = altYazi    ?? (_fisTesekkurGoster ? _fisTesekkurMetni : '');
    final tarih = DateFormat('dd.MM.yyyy HH:mm').format(satis.tarih);

    // Kopya sayısı kadar aynı fişi yazdır (Fiş Tasarım > Kopya Sayısı ayarı)
    for (int kopya = 0; kopya < _fisKopyaSayisi.clamp(1, 5); kopya++) {
      final List<int> bytes = [];

      bytes.addAll(await _logoBas(generator));
      bytes.addAll(generator.text(YazdirmaServisi._t(fa),
          styles: const PosStyles(bold: true, align: PosAlign.center,
              height: PosTextSize.size2, width: PosTextSize.size1)));
      if (fadr.isNotEmpty)
        bytes.addAll(generator.text(YazdirmaServisi._t(fadr), styles: const PosStyles(align: PosAlign.center)));
      if (ft.isNotEmpty)
        bytes.addAll(generator.text(YazdirmaServisi._t('Tel: $ft'), styles: const PosStyles(align: PosAlign.center)));
      if (_fisVergiNoGoster && _firmaVergiNo.isNotEmpty)
        bytes.addAll(generator.text(YazdirmaServisi._t('VKN: $_firmaVergiNo'), styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.hr(ch: '='));

      bytes.addAll(generator.row([
        PosColumn(text:YazdirmaServisi._t('Tarih:'), width: 4, styles: const PosStyles(bold: true)),
        PosColumn(text:YazdirmaServisi._t(tarih), width: 8),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text:YazdirmaServisi._t('Fiş No:'), width: 4, styles: const PosStyles(bold: true)),
        PosColumn(text:YazdirmaServisi._t(satis.fisNo ?? '-'), width: 8),
      ]));
      if (_fisKasiyerGoster && kasiyerAdi != null && kasiyerAdi.isNotEmpty)
        bytes.addAll(generator.row([
          PosColumn(text:YazdirmaServisi._t('Kasiyer:'), width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text:YazdirmaServisi._t(kasiyerAdi), width: 8),
        ]));
      // ══════════════════════════════════════════════════════════════════
      // 🆕 CARİ (MÜŞTERİ) ADI
      //
      // ÖNCEDEN: sadece `cariUnvan` parametresi doluysa basılıyordu —
      // ama fisYazdir()'ı çağıran 5 ekranın HİÇBİRİ bu parametreyi
      // geçmiyordu, dolayısıyla cari adı fişte HİÇ görünmüyordu.
      //
      // ARTIK: parametre boşsa satışın kendi `cariAdi` alanına geri
      // düşülüyor. SatisModel zaten cari_id ile JOIN'den geliyor, yani
      // veri elimizde — sadece kullanılmıyordu.
      //
      // Ayrıca `fis_cari_goster` ayarına bağlandı; perakende satış
      // yapan işletmeler kapatabilsin.
      // ══════════════════════════════════════════════════════════════════
      final gosterilecekCari =
          (cariUnvan != null && cariUnvan.isNotEmpty)
              ? cariUnvan
              : (satis.cariAdi ?? '');
      if (_fisCariGoster && gosterilecekCari.isNotEmpty)
        bytes.addAll(generator.row([
          PosColumn(text:YazdirmaServisi._t('Cari:'), width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text:YazdirmaServisi._t(gosterilecekCari), width: 8),
        ]));
      bytes.addAll(generator.hr());

      bytes.addAll(generator.row([
        PosColumn(text:YazdirmaServisi._t('Urun'), width: 6, styles: const PosStyles(bold: true)),
        PosColumn(text:YazdirmaServisi._t('Mkt'), width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
        PosColumn(text:YazdirmaServisi._t('Fiy'), width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
        PosColumn(text:YazdirmaServisi._t('Top'), width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]));
      bytes.addAll(generator.hr());

      double topIsk = 0, topKdv = 0;
      for (final k in satis.kalemler) {
        final mkt = k.miktar % 1 == 0
            ? '${k.miktar.toInt()}' : k.miktar.toStringAsFixed(2);
        // 🔴 DÜZELTME (kullanıcı bulgusu): Ürün adı 20 karakterden uzunsa
        // ikinci bir satıra KAYDIRILIYORDU (taşma) — 80mm kağıtta bu,
        // fişin okunmasını zorlaştırıyor ve dağınık görünüyordu. Artık
        // "…" ile KESİLİYOR, tek satırda kalıyor.
        // 58 mm'de 6/12 sütun 16 karakter — 20'lik ad orada da taşıyordu.
        final adMax = _kagit == PaperSize.mm58 ? 16 : 20;
        final ad = k.urunAdi.length > adMax ? '${k.urunAdi.substring(0, adMax - 3)}...' : k.urunAdi;
        // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu): "Fiyat" sütunu
        // ÖNCEDEN her zaman k.birimFiyat (İNDİRİMSİZ, orijinal fiyat)
        // gösteriyordu — ama "Toplam" sütunu k.toplamTutar (netFiyat ×
        // miktar, yani İNDİRİMLİ) gösteriyordu. Bir üründe indirim
        // varsa, fişte "Fiyat × Miktar ≠ Toplam" gibi kafa karıştırıcı
        // bir tutarsızlık oluşuyordu. Artık indirim varsa NET (indirimli)
        // birim fiyat gösteriliyor — matematik tutarlı.
        final gosterilecekFiyat = k.iskontoTutar > 0 ? k.netFiyat : k.birimFiyat;
        bytes.addAll(generator.row([
          PosColumn(text:YazdirmaServisi._t(ad),  width: 6),
          PosColumn(text:YazdirmaServisi._t(mkt), width: 2, styles: const PosStyles(align: PosAlign.center)),
          PosColumn(text:YazdirmaServisi._t(_fmt.format(gosterilecekFiyat)), width: 2, styles: const PosStyles(align: PosAlign.right)),
          PosColumn(text:YazdirmaServisi._t(_fmt.format(k.toplamTutar)), width: 2, styles: const PosStyles(align: PosAlign.right)),
        ]));
        if (_fisUrunKoduGoster && (k.barkod?.isNotEmpty ?? false))
          bytes.addAll(generator.text(YazdirmaServisi._t('  Kod: ${k.barkod}'),
              styles: const PosStyles(align: PosAlign.left)));
        if (k.iskontoTutar > 0)
          bytes.addAll(generator.text(YazdirmaServisi._t('  İnd: -${_fmt.format(k.iskontoTutar)}')));
        if (_fisKdvGosterAna && _fisKdvDetayGoster && k.kdvTutar > 0)
          bytes.addAll(generator.text(YazdirmaServisi._t('  KDV(%${k.kdvOran.toStringAsFixed(0)}): ${_fmt.format(k.kdvTutar)}')));
        topIsk += k.iskontoTutar;
        topKdv += k.kdvTutar;
      }
      bytes.addAll(generator.hr());

      if (topIsk > 0.001)
        bytes.addAll(generator.row([
          PosColumn(text:YazdirmaServisi._t('ISKONTO'), width: 8),
          PosColumn(text:YazdirmaServisi._t('-${_fmt.format(topIsk)}'), width: 4,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
      // KDV detay kapalıysa toplu KDV özeti gösterilir; açıksa yukarıda
      // satır satır zaten gösterildiği için burada tekrar edilmez.
      if (_fisKdvGosterAna && !_fisKdvDetayGoster && topKdv > 0.001)
        bytes.addAll(generator.row([
          PosColumn(text:YazdirmaServisi._t('KDV'), width: 8),
          PosColumn(text:YazdirmaServisi._t(_fmt.format(topKdv)), width: 4,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
      bytes.addAll(generator.row([
        PosColumn(text:YazdirmaServisi._t('TOPLAM'), width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text:YazdirmaServisi._t(_fmt.format(satis.genelToplam)), width: 4,
            styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]));
      if (_fisOdemeYontemiGoster)
        bytes.addAll(generator.row([
          PosColumn(text:YazdirmaServisi._t('ODENEN (${satis.odemeYontemi})'), width: 8),
          PosColumn(text:YazdirmaServisi._t(_fmt.format(satis.odenenTutar)), width: 4,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
      final paraUstu = satis.odenenTutar - satis.genelToplam;
      if (_fisParaUstuGoster && paraUstu > 0.01)
        bytes.addAll(generator.row([
          PosColumn(text:YazdirmaServisi._t('PARA ÜSTÜ'), width: 8, styles: const PosStyles(bold: true)),
          PosColumn(text:YazdirmaServisi._t(_fmt.format(paraUstu)), width: 4,
              styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]));

      bytes.addAll(generator.hr());

      // ══════════════════════════════════════════════════════════════════
      // 🆕 CARİ HESAP ÖZETİ — "Eski Bakiye / İşlem / Son Bakiye" üçlüsü
      //
      // Cariye (veresiye/hesaba) yapılan satışlarda müşteri fişte kendi
      // hesap durumunu görür. Profesyonel ön muhasebe programlarındaki
      // (Paraşüt, Uyumsoft vb.) cari ekstre satırının fiş karşılığıdır.
      //
      // İŞARET KURALI — bakiye = SUM(borc) - SUM(alacak) (cari_deposu):
      //   • Bakiye POZİTİF  → müşteri BİZE borçlu   → "Borç"
      //   • Bakiye NEGATİF  → biz müşteriye borçlu  → "Alacak"
      // Kullanıcı "-1.500,00" gibi çıplak bir eksi görüp kafası
      // karışmasın diye tutar mutlak değerle, yanına etiketle basılır.
      // ══════════════════════════════════════════════════════════════════
      if (_fisCariBakiyeGoster &&
          cariOncekiBakiye != null && cariSonBakiye != null) {
        bytes.addAll(generator.text(YazdirmaServisi._t('CARI HESAP OZETI'),
            styles: const PosStyles(bold: true, align: PosAlign.center)));
        bytes.addAll(generator.row([
          PosColumn(text: YazdirmaServisi._t('Eski Bakiye'), width: 7),
          PosColumn(text: YazdirmaServisi._t(_bakiyeYaz(cariOncekiBakiye)), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
        // Bu satışın cariye yansıyan tutarı (bakiye farkı) — genel
        // toplamdan değil, iki bakiyenin farkından hesaplanır ki kısmi
        // ödeme yapılmış satışlarda da doğru olsun.
        final fark = cariSonBakiye - cariOncekiBakiye;
        bytes.addAll(generator.row([
          PosColumn(text: YazdirmaServisi._t(fark >= 0 ? '(+) Bu Fis' : '(-) Bu Fis'), width: 7),
          PosColumn(text: YazdirmaServisi._t(_fmt.format(fark.abs())), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
        bytes.addAll(generator.hr());
        bytes.addAll(generator.row([
          PosColumn(text: YazdirmaServisi._t('SON BAKIYE'), width: 7,
              styles: const PosStyles(bold: true)),
          PosColumn(text: YazdirmaServisi._t(_bakiyeYaz(cariSonBakiye)), width: 5,
              styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]));
        bytes.addAll(generator.hr(ch: '='));
      }

      if (ay.isNotEmpty)
        bytes.addAll(generator.text(YazdirmaServisi._t(ay), styles: const PosStyles(align: PosAlign.center, bold: true)));

      // ══════════════════════════════════════════════════════════════════
      // 🆕 FİŞ BARKODU — fiş numarasını Code128 olarak basar
      //
      // Kasiyer bu barkodu Hızlı Satış ekranında okuttuğunda o satış
      // geri çağrılır (bkz. hizli_satis_ekrani._barkodIleEkle).
      //
      // Neden Code128: fiş no GİB standardında 16 KARAKTER ve harf
      // içeriyor (MKP2026000000001). EAN-13 sadece 13 rakam alır,
      // yetmez. Code128 alfanümerik ve değişken uzunlukludur.
      // ══════════════════════════════════════════════════════════════════
      if (_fisBarkodGoster && (satis.fisNo ?? '').isNotEmpty) {
        bytes.addAll(generator.feed(1));
        // Barkod RESİM olarak basılıyor — ESC/POS'un yerel barkod
        // komutunu (GS k) ucuz yazıcıların çoğu desteklemiyordu.
        bytes.addAll(_barkodBas(generator, satis.fisNo!));
      }

      bytes.addAll(generator.feed(_fisBeslemeKagit.clamp(0, 10)));
      bytes.addAll(generator.cut());

      await _yazdir(bytes);
      if (kopya < _fisKopyaSayisi.clamp(1, 5) - 1) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 TAHSİLAT / TEDİYE MAKBUZU
  //
  // Türkiye'de bu İKİ AYRI belgedir ve araştırma sonucu şu ayrım standart:
  //   • TAHSİLAT MAKBUZU — parayı ALAN taraf keser.
  //       Müşteriden tahsilat yaptığımızda biz keseriz.
  //   • TEDİYE MAKBUZU   — parayı VEREN taraf keser.
  //       Tedarikçiye ödeme yaptığımızda biz keseriz.
  // Başlık buna göre değişir; kalan alanlar aynıdır.
  //
  // ZORUNLU/STANDART ALANLAR (Paraşüt, Uyumsoft, Evobulut kaynaklarında
  // ortak olarak geçenler):
  //   makbuz no · tarih · cari unvan · tutar (RAKAM + YAZIYLA) ·
  //   ödeme türü · açıklama · eski/yeni bakiye · kesen kişi · imza yeri
  //
  // "Tutar yazıyla" isteğe bağlı bir süs değil: rakamın sonradan
  // değiştirilmesine (tahrifat) karşı standart güvenlik önlemidir.
  // Bu yüzden varsayılan olarak AÇIK gelir.
  //
  // NOT: Makbuz FATURA YERİNE GEÇMEZ — sadece para hareketini belgeler.
  // Bu uyarı makbuzun altına basılır ki kullanıcı yanlış kullanmasın.
  // ══════════════════════════════════════════════════════════════════════
  Future<void> makbuzYazdir({
    required String makbuzNo,
    required DateTime tarih,
    required String cariUnvan,
    required double tutar,
    required String odemeTuru,
    /// 'Tahsilat' → parayı biz aldık   → TAHSİLAT MAKBUZU
    /// 'Odeme'    → parayı biz verdik  → TEDİYE MAKBUZU
    required String islemTipi,
    String? aciklama,
    String? kesenKisi,
    double? oncekiBakiye,
    double? sonBakiye,
    String? firmaAdi,
    String? firmaAdres,
    String? firmaTel,
  }) async {
    await ayarlariYukle();
    final profile   = await _profil();
    final generator = Generator(_kagit, profile);

    final tahsilatMi = islemTipi == 'Tahsilat';
    final baslik = tahsilatMi ? 'TAHSILAT MAKBUZU' : 'TEDIYE MAKBUZU';
    final tutarEtiketi = tahsilatMi ? 'Tahsil Edilen' : 'Odenen Tutar';
    final tarihStr = DateFormat('dd.MM.yyyy HH:mm').format(tarih);

    final fa   = firmaAdi   ?? _firmaAdi;
    final fadr = firmaAdres ?? _firmaAdres;
    final ft   = firmaTel   ?? _firmaTel;

    for (int kopya = 0; kopya < _fisKopyaSayisi.clamp(1, 5); kopya++) {
      final List<int> bytes = [];

      // ── Firma başlığı ────────────────────────────────────────────────
      bytes.addAll(generator.text(YazdirmaServisi._t(fa),
          styles: const PosStyles(bold: true, align: PosAlign.center,
              height: PosTextSize.size2, width: PosTextSize.size1)));
      if (fadr.isNotEmpty) {
        bytes.addAll(generator.text(YazdirmaServisi._t(fadr),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (ft.isNotEmpty) {
        bytes.addAll(generator.text(YazdirmaServisi._t('Tel: $ft'),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (_fisVergiNoGoster && _firmaVergiNo.isNotEmpty) {
        bytes.addAll(generator.text(YazdirmaServisi._t('VKN: $_firmaVergiNo'),
            styles: const PosStyles(align: PosAlign.center)));
      }
      bytes.addAll(generator.hr(ch: '='));

      // ── Belge başlığı ────────────────────────────────────────────────
      bytes.addAll(generator.text(YazdirmaServisi._t(baslik),
          styles: const PosStyles(bold: true, align: PosAlign.center,
              height: PosTextSize.size2, width: PosTextSize.size1)));
      bytes.addAll(generator.hr(ch: '='));

      // ── Belge künyesi ────────────────────────────────────────────────
      bytes.addAll(generator.row([
        PosColumn(text: YazdirmaServisi._t('Makbuz No:'), width: 4,
            styles: const PosStyles(bold: true)),
        PosColumn(text: YazdirmaServisi._t(makbuzNo), width: 8),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text: YazdirmaServisi._t('Tarih:'), width: 4,
            styles: const PosStyles(bold: true)),
        PosColumn(text: YazdirmaServisi._t(tarihStr), width: 8),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text: YazdirmaServisi._t(tahsilatMi ? 'Odeyen:' : 'Alan:'), width: 4,
            styles: const PosStyles(bold: true)),
        PosColumn(text: YazdirmaServisi._t(cariUnvan), width: 8),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text: YazdirmaServisi._t('Odeme:'), width: 4,
            styles: const PosStyles(bold: true)),
        PosColumn(text: YazdirmaServisi._t(odemeTuru), width: 8),
      ]));
      if (aciklama != null && aciklama.trim().isNotEmpty) {
        bytes.addAll(generator.row([
          PosColumn(text: YazdirmaServisi._t('Aciklama:'), width: 4,
              styles: const PosStyles(bold: true)),
          PosColumn(text: YazdirmaServisi._t(aciklama.trim()), width: 8),
        ]));
      }
      bytes.addAll(generator.hr());

      // ── Tutar (rakam) ────────────────────────────────────────────────
      bytes.addAll(generator.row([
        PosColumn(text: YazdirmaServisi._t(tutarEtiketi), width: 6,
            styles: const PosStyles(bold: true, height: PosTextSize.size2)),
        PosColumn(text: YazdirmaServisi._t(_fmt.format(tutar)), width: 6,
            styles: const PosStyles(bold: true, align: PosAlign.right,
                height: PosTextSize.size2)),
      ]));

      // ── Tutar (yazıyla) — tahrifat önlemi ───────────────────────────
      if (_fisYaziylaTutar) {
        bytes.addAll(generator.text(YazdirmaServisi._t('Yalniz: ${tutariYaziyaCevir(tutar)}'),
            styles: const PosStyles(bold: true)));
      }
      bytes.addAll(generator.hr());

      // ── Cari hesap özeti ────────────────────────────────────────────
      if (_fisCariBakiyeGoster &&
          oncekiBakiye != null && sonBakiye != null) {
        bytes.addAll(generator.text(YazdirmaServisi._t('CARI HESAP OZETI'),
            styles: const PosStyles(bold: true, align: PosAlign.center)));
        bytes.addAll(generator.row([
          PosColumn(text: YazdirmaServisi._t('Eski Bakiye'), width: 7),
          PosColumn(text: YazdirmaServisi._t(_bakiyeYaz(oncekiBakiye)), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
        final fark = sonBakiye - oncekiBakiye;
        bytes.addAll(generator.row([
          PosColumn(text: YazdirmaServisi._t(fark >= 0 ? '(+) Bu Makbuz' : '(-) Bu Makbuz'),
              width: 7),
          PosColumn(text: YazdirmaServisi._t(_fmt.format(fark.abs())), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
        bytes.addAll(generator.hr());
        bytes.addAll(generator.row([
          PosColumn(text: YazdirmaServisi._t('SON BAKIYE'), width: 7,
              styles: const PosStyles(bold: true)),
          PosColumn(text: YazdirmaServisi._t(_bakiyeYaz(sonBakiye)), width: 5,
              styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]));
        bytes.addAll(generator.hr(ch: '='));
      }

      // ── Kesen + imza ────────────────────────────────────────────────
      if (kesenKisi != null && kesenKisi.isNotEmpty) {
        bytes.addAll(generator.row([
          PosColumn(text: YazdirmaServisi._t(tahsilatMi ? 'Tahsil Eden:' : 'Odeyen:'),
              width: 5, styles: const PosStyles(bold: true)),
          PosColumn(text: YazdirmaServisi._t(kesenKisi), width: 7),
        ]));
      }
      bytes.addAll(generator.feed(1));
      bytes.addAll(generator.text(YazdirmaServisi._t('Imza / Kase'),
          styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text(YazdirmaServisi._t('........................'),
          styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.hr());

      // ── Yasal uyarı ─────────────────────────────────────────────────
      // Araştırmadaki tüm kaynaklar (Paraşüt, Uyumsoft, Evobulut) bunu
      // vurguluyor: makbuz fatura yerine geçmez. Kullanıcı yanlış
      // kullanıp usulsüzlüğe düşmesin diye belgenin üstüne basılıyor.
      bytes.addAll(generator.text(
          YazdirmaServisi._t('Bu belge fatura yerine gecmez.'),
          styles: const PosStyles(align: PosAlign.center)));

      // ── Makbuz barkodu ──────────────────────────────────────────────
      if (_fisBarkodGoster && makbuzNo.isNotEmpty) {
        bytes.addAll(generator.feed(1));
        bytes.addAll(_barkodBas(generator, makbuzNo));
      }

      bytes.addAll(generator.feed(_fisBeslemeKagit.clamp(0, 10)));
      bytes.addAll(generator.cut());

      await _yazdir(bytes);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FATURA — 80mm/58mm termal yazıcıya RAW ESC/POS
  // PDF tabanlı 80mm çıktı bazı termal yazıcılarda küçük/yanlış ölçekte
  // basıldığı için, yazıcı bağlıysa fatura da fiş gibi RAW gönderilir.
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> faturaYazdir(FaturaModel f) async {
    await ayarlariYukle();
    final profile   = await _profil();
    final generator = Generator(_kagit, profile);
    final List<int> bytes = [];
    final tarih = DateFormat('dd.MM.yyyy HH:mm').format(f.duzenlenmeTarihi ?? f.tarih);

    bytes.addAll(generator.text(YazdirmaServisi._t(_firmaAdi),
        styles: const PosStyles(bold: true, align: PosAlign.center,
            height: PosTextSize.size2, width: PosTextSize.size1)));
    if (_firmaAdres.isNotEmpty)
      bytes.addAll(generator.text(YazdirmaServisi._t(_firmaAdres), styles: const PosStyles(align: PosAlign.center)));
    if (_firmaTel.isNotEmpty)
      bytes.addAll(generator.text(YazdirmaServisi._t('Tel: $_firmaTel'), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.hr(ch: '='));

    bytes.addAll(generator.text(YazdirmaServisi._t((f.faturaTipi ?? 'FATURA').toUpperCase()),
        styles: const PosStyles(bold: true, align: PosAlign.center)));
    bytes.addAll(generator.row([
      PosColumn(text:YazdirmaServisi._t('No:'), width: 4, styles: const PosStyles(bold: true)),
      PosColumn(text:YazdirmaServisi._t(f.faturaNo ?? '-'), width: 8),
    ]));
    bytes.addAll(generator.row([
      PosColumn(text:YazdirmaServisi._t('Tarih:'), width: 4, styles: const PosStyles(bold: true)),
      PosColumn(text:YazdirmaServisi._t(tarih), width: 8),
    ]));
    if (f.eFaturaUuid != null)
      bytes.addAll(generator.text(YazdirmaServisi._t('ETTN: ${f.eFaturaUuid}'), styles: const PosStyles(align: PosAlign.left)));
    bytes.addAll(generator.hr());

    bytes.addAll(generator.text(YazdirmaServisi._t('SAYIN'), styles: const PosStyles(bold: true)));
    bytes.addAll(generator.text(YazdirmaServisi._t(f.cariUnvan ?? '-'), styles: const PosStyles(bold: true)));
    if (f.cariAdres != null && f.cariAdres!.isNotEmpty)
      bytes.addAll(generator.text(YazdirmaServisi._t(f.cariAdres!)));
    bytes.addAll(generator.text(YazdirmaServisi._t('VD: ${f.cariVergiDairesi ?? "-"}  VKN/TC: ${f.cariVergiNo ?? "-"}')));
    bytes.addAll(generator.hr());

    bytes.addAll(generator.row([
      PosColumn(text:YazdirmaServisi._t('Ürün'), width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text:YazdirmaServisi._t('Mik'), width: 2, styles: const PosStyles(align: PosAlign.center, bold: true)),
      PosColumn(text:YazdirmaServisi._t('Fiyat'), width: 2, styles: const PosStyles(align: PosAlign.right, bold: true)),
      PosColumn(text:YazdirmaServisi._t('Tutar'), width: 2, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]));
    for (final d in f.detaylar) {
      final mkt = d.miktar == d.miktar.roundToDouble()
          ? '${d.miktar.toInt()}' : d.miktar.toStringAsFixed(2);
      // 🔴 DÜZELTME (kullanıcı bulgusu — satış fişindeki AYNI hata
      // sınıfı): ürün adı kesiliyor (kaydırma yerine), ve indirim
      // varsa "Fiyat" sütunu indirimli net birim fiyatı gösteriyor
      // (toplamTutar zaten indirimli olduğu için miktar'a bölerek
      // güvenle türetiliyor — modeldeki alan adı farklılıklarına
      // bağımlı olmadan).
      final ad = d.urunAdi.length > 20 ? '${d.urunAdi.substring(0, 17)}...' : d.urunAdi;
      final netBirimFiyat = d.miktar > 0 ? d.toplamTutar / d.miktar : d.birimFiyat;
      final indirimliMi = d.iskontoTutari > 0.005;
      bytes.addAll(generator.row([
        PosColumn(text:YazdirmaServisi._t(ad), width: 6),
        PosColumn(text:YazdirmaServisi._t(mkt), width: 2, styles: const PosStyles(align: PosAlign.center)),
        PosColumn(text:YazdirmaServisi._t(_fmt.format(indirimliMi ? netBirimFiyat : d.birimFiyat)), width: 2, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(text:YazdirmaServisi._t(_fmt.format(d.toplamTutar)), width: 2, styles: const PosStyles(align: PosAlign.right)),
      ]));
      if (indirimliMi)
        bytes.addAll(generator.text(YazdirmaServisi._t('  İnd: -${_fmt.format(d.iskontoTutari)}')));
    }
    bytes.addAll(generator.hr());

    // Not: "Ara Toplam" BİLEREK indirim UYGULANMADAN ÖNCEKİ brüt tutar
    // olarak gösteriliyor (toplamAraToplam zaten net saklanıyor,
    // +toplamIskonto ile brüte geri çevriliyor) — aksi halde alttaki
    // "İndirim" satırı ikinci kez düşülmüş gibi görünüp toplam tutmazdı
    // (bkz. fatura_detay_pdf_ext.dart'taki aynı düzeltme).
    bytes.addAll(generator.row([
      PosColumn(text:YazdirmaServisi._t('Ara Toplam'), width: 8),
      PosColumn(text:YazdirmaServisi._t(_fmt.format(f.toplamAraToplam + f.toplamIskonto)), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]));
    if (f.toplamIskonto > 0)
      bytes.addAll(generator.row([
        PosColumn(text:YazdirmaServisi._t('İndirim'), width: 8),
        PosColumn(text:YazdirmaServisi._t('-${_fmt.format(f.toplamIskonto)}'), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]));
    bytes.addAll(generator.row([
      PosColumn(text:YazdirmaServisi._t('KDV'), width: 8),
      PosColumn(text:YazdirmaServisi._t(_fmt.format(f.toplamKdv)), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(generator.row([
      PosColumn(text:YazdirmaServisi._t('GENEL TOPLAM'), width: 8, styles: const PosStyles(bold: true)),
      PosColumn(text:YazdirmaServisi._t(_fmt.format(f.genelToplam)), width: 4,
          styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(YazdirmaServisi._t(tutariYaziyaCevir(f.genelToplam)),
        styles: const PosStyles(align: PosAlign.center)));

    try {
      final qrVeri = f.eFaturaUuid ?? f.faturaNo ?? 'BarkoPro';
      bytes.addAll(generator.qrcode(qrVeri));
    } catch (_) {/* QR desteklenmiyorsa atla */}

    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.text(YazdirmaServisi._t(_altYazi), styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    await _yazdir(bytes);
  }

  Future<void> testFisYazdir() async {
    await ayarlariYukle();
    final profile   = await _profil();
    final generator = Generator(_kagit, profile);
    final bytes     = <int>[];

    bytes.addAll(generator.text(YazdirmaServisi._t(_firmaAdi),
        styles: const PosStyles(bold: true, align: PosAlign.center,
            height: PosTextSize.size2)));
    if (_firmaAdres.isNotEmpty)
      bytes.addAll(generator.text(YazdirmaServisi._t(_firmaAdres), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(YazdirmaServisi._t('*** TEST FİŞİ ***'),
        styles: const PosStyles(bold: true, align: PosAlign.center)));
    bytes.addAll(generator.text(YazdirmaServisi._t(
        DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())),
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.row([
      PosColumn(text:YazdirmaServisi._t('Test Ürün 1'), width: 8),
      PosColumn(text:YazdirmaServisi._t('50,00'), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(generator.row([
      PosColumn(text:YazdirmaServisi._t('Test Ürün 2'), width: 8),
      PosColumn(text:YazdirmaServisi._t('35,00'), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.row([
      PosColumn(text:YazdirmaServisi._t('TOPLAM'), width: 8, styles: const PosStyles(bold: true)),
      PosColumn(text:YazdirmaServisi._t('85,00'), width: 4,
          styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(YazdirmaServisi._t(_altYazi),
        styles: const PosStyles(align: PosAlign.center)));

    final tur = _aktif?.tur == YaziciTur.wifi ? 'WiFi/LAN'
        : _aktif?.tur == YaziciTur.bluetooth ? 'Bluetooth'
        : 'USB';
    bytes.addAll(generator.text(YazdirmaServisi._t('Bağlantı: $tur'),
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    await _yazdir(bytes);
  }
}
