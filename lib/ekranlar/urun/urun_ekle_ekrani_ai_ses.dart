// ignore_for_file: invalid_use_of_protected_member
// lib/ekranlar/urun/urun_ekle_ekrani_ai_ses.dart
// urun_ekle_ekrani.dart'ın parçası — bkz. urun_ekle_ekrani_form.dart
// başındaki not. Bu dosya: fatura ürün seçim dialogu, AI grup/marka
// önerisi, sesli komut, döviz bazlı hesaplama, benzer ürün kontrolü,
// kaydet/sil/barkod üretme.
part of 'urun_ekle_ekrani.dart';

extension _UrunEkleAiSesExt on _UrunEkleEkraniState {
  // ---- FATURA ÜRÜN SEÇİM DİALOGU ----
  Future<List<Map<String, dynamic>>> _faturaUrunSecDialog(
      List<Map<String, dynamic>> urunler) async {
    Set<int> seciliIndeksler = {};
    return await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Faturadaki Ürünler'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: urunler.length,
              itemBuilder: (_, i) {
                final u = urunler[i];
                final secili = seciliIndeksler.contains(i);
                return CheckboxListTile(
                  value: secili,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) seciliIndeksler.add(i);
                      else seciliIndeksler.remove(i);
                    });
                  },
                  title: Text(u['urun_adi'] ?? ''),
                  subtitle: Text('Fiyat: ${u['birim_fiyat'] ?? '-'}  KDV: %${u['kdv_orani'] ?? 18}'),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, []),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final secilenUrunler = seciliIndeksler.map((i) => urunler[i]).toList();
                Navigator.pop(ctx, secilenUrunler);
              },
              child: Text('${seciliIndeksler.length} Ürün Ekle'),
            ),
          ],
        ),
      ),
    ) ?? [];
  }

  // ---- AI ÖNERİ BUTONLARI ----
  Future<void> _aiGrupOner() async {
    final ad = _c['urunAdi']?.text.trim();
    if (ad == null || ad.isEmpty) {
      BildirimServisi.uyari(context, 'Önce ürün adını girin.');
      return;
    }
    final cevap = await _ai.urunKategoriOner(ad);
    if (cevap.containsKey('ana_grup')) {
      if (!mounted) return;
      setState(() {
        _anaGrup = cevap['ana_grup'] as String?;
        _aiDoldurulanAlanlar.add('ana_grup');
      });
      if (mounted) BildirimServisi.basari(context, 'Grup önerisi: $_anaGrup');
    } else {
      if (mounted) BildirimServisi.uyari(context, 'Grup önerisi alınamadı.');
    }
  }

  Future<void> _aiAlan1Oner() async {
    final ad = _c['urunAdi']?.text.trim();
    if (ad == null || ad.isEmpty) {
      BildirimServisi.uyari(context, 'Önce ürün adını girin.');
      return;
    }
    final cevap = await _ai.urunKategoriOner(ad);
    if (cevap.containsKey('alan1')) {
      if (!mounted) return;
      setState(() {
        _c['alan1']?.text = cevap['alan1'] as String? ?? '';
        _aiDoldurulanAlanlar.add('alan1');
      });
      if (mounted) BildirimServisi.basari(context, 'Alan1 önerisi: ${_c['alan1']?.text}');
    } else {
      if (mounted) BildirimServisi.uyari(context, 'Alan1 önerisi alınamadı.');
    }
  }

  /// Tek mikrofon, doğal cümle: "ürün adı çikolata", "alış fiyat 25,50",
  /// "satış fiyat 35", "stok 100", "kdv oranı 18", "barkod 869...",
  /// "grup öner" gibi komutları dinler, doğru alanı bulup otomatik yazar.
  Future<void> _sesliKomut() async {
    final hazir = await _ses.hazirla();
    if (!hazir) {
      if (mounted) BildirimServisi.uyari(context,
          'Mikrofon kullanılamıyor. Cihaz ayarlarından mikrofon iznini kontrol edin.');
      return;
    }
    if (!mounted) return;

    // Dinlerken kullanıcıya durum göstermek için basit bir alt sayfa
    final tamamlandi = Completer<String?>();
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => _SesliKomutSheet(
        ses: _ses,
        onSonuc: (metin) { if (!tamamlandi.isCompleted) tamamlandi.complete(metin); },
        onIptal: () { if (!tamamlandi.isCompleted) tamamlandi.complete(null); },
      ),
    );

    final metin = await tamamlandi.future;
    if (!mounted) return;
    if (metin == null || metin.trim().isEmpty) return;
    await _sesliKomutuUygula(metin.trim());
  }

  /// Kullanıcı isteği: "2 dolara ürün geldi, kur 45,90 lira, ürün fiyatı
  /// otomatik hesaplansın" — kayıtlı döviz kurlarından birini seçtirip,
  /// yabancı para tutarını TL'ye çevirip Alış Fiyatı alanına otomatik
  /// yazar. Profesyonel muhasebe programlarındaki "dövizle alış" akışının
  /// basitleştirilmiş karşılığı.
  Future<void> _dovizleHesapla() async {
    final dovizler = await DovizDeposu().tumunuGetir();
    if (!mounted) return;
    if (dovizler.isEmpty || dovizler.every((d) => d.kurGirilmemis)) {
      BildirimServisi.uyari(context,
          'Önce Ayarlar > Döviz Kurları\'ndan bir para birimi ekleyip '
          'güncel kuru çekin.');
      return;
    }

    final sonuc = await showDialog<_DovizSonuc>(
      context: context,
      builder: (ctx) => _DovizleHesaplaDialog(dovizler: dovizler.where((d) => !d.kurGirilmemis).toList()),
    );
    if (sonuc == null || !mounted) return;
    setState(() {
      _c['alisFiyat']?.text = sonuc.tlTutari.toStringAsFixed(2);
      _dovizKoduTakip = sonuc.dovizKodu;
      _dovizTutariTakip = sonuc.dovizTutari;
    });
    BildirimServisi.basari(context,
        sonuc.dovizKodu != null
            ? 'Alış fiyatı: ${sonuc.tlTutari.toStringAsFixed(2)} ₺ (${sonuc.dovizKodu} bazında takip ediliyor)'
            : 'Alış fiyatı: ${sonuc.tlTutari.toStringAsFixed(2)} ₺ olarak hesaplandı');
  }

  /// Alan adlarını gerçek form alanlarına yazan ortak yardımcı — hem
  /// kural tabanlı hem Gemini yolundan gelen sonuçlar buradan geçer.
  void _alaniDoldur(String alan, String deger) {
    double? sayi() {
      final t = deger.replaceAll('lira', '').replaceAll('tl', '').replaceAll('₺', '').trim();
      final m = RegExp(r'[\d]+([.,]\d+)?').firstMatch(t);
      return m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', '.'));
    }

    switch (alan) {
      case 'satisFiyati':
        final v = sayi();
        if (v != null) {
          setState(() => _c['satisFiyati']?.text = v.toStringAsFixed(2));
          BildirimServisi.basari(context, 'Satış fiyatı: ${v.toStringAsFixed(2)} ₺');
        }
      case 'alisFiyat':
        final v = sayi();
        if (v != null) {
          setState(() => _c['alisFiyat']?.text = v.toStringAsFixed(2));
          BildirimServisi.basari(context, 'Alış fiyatı: ${v.toStringAsFixed(2)} ₺');
        }
      case 'kdvOrani':
        final v = sayi();
        if (v != null) {
          setState(() => _c['alisKdvOran']?.text = v.toStringAsFixed(0));
          BildirimServisi.basari(context, 'KDV oranı: %${v.toStringAsFixed(0)}');
        }
      case 'stok':
        final v = sayi();
        if (v != null) {
          setState(() => _c['stok']?.text = v.toStringAsFixed(0));
          BildirimServisi.basari(context, 'Stok: ${v.toStringAsFixed(0)}');
        }
      case 'barkod':
        final rakam = deger.replaceAll(RegExp(r'[^\d]'), '');
        if (rakam.isNotEmpty) {
          setState(() => _c['barkod']?.text = rakam);
          BildirimServisi.basari(context, 'Barkod: $rakam');
        }
      case 'anaGrup':
        if (deger.trim().isNotEmpty) {
          setState(() => _anaGrup = deger.trim());
          BildirimServisi.basari(context, 'Grup: ${deger.trim()}');
        }
      case 'marka':
        if (deger.trim().isNotEmpty) {
          setState(() => _c['alan1']?.text = deger.trim());
          BildirimServisi.basari(context, 'Marka: ${deger.trim()}');
        }
      case 'urunAdi':
      default:
        if (deger.trim().isNotEmpty) {
          setState(() {
            _c['urunAdi']?.text = deger.trim();
            _urunAdiGuncelle(deger.trim());
          });
          BildirimServisi.basari(context, 'Ürün adı: ${deger.trim()}');
          _benzerUrunKontrolEt(deger.trim());
        }
    }
  }

  /// Sesle söylenen ürün adı zaten kayıtlıysa kullanıcıyı bilgilendirir
  /// (mükerrer kayıt açmadan önce fark etsin diye) — "ülker çubuk dedim,
  /// asistan ürün listesinden bulsun" isteğinin karşılığı budur.
  Future<void> _benzerUrunKontrolEt(String urunAdi) async {
    final benzerler = await _ai.benzerUrunleriAra(urunAdi, limit: 3);
    if (!mounted || benzerler.isEmpty) return;
    final ilk = benzerler.first;
    BildirimServisi.uyari(
      context,
      '📦 Benzer ürün zaten kayıtlı: "${ilk.urunAdi}" '
      '(Stok: ${ilk.stok.toStringAsFixed(0)}, Fiyat: ${ParaUtils.formatla(ilk.satisFiyati)}). '
      'Yine de yeni ürün olarak devam edebilirsiniz.',
    );
  }

  /// Tüm bilinen tetik kelimelerinin UZUNDAN KISAYA sıralı düz listesi —
  /// hem tek komut eşleştirmede hem çoklu komut bölmede kullanılıyor.
  static const List<String> _tumTetikKelimeler = [
    'satış fiyatı', 'satış fiyat', 'satis fiyat',
    'alış fiyatı', 'alış fiyat', 'alis fiyat', 'maliyet',
    'kdv oranı', 'kdv oran',
    'ana grup', 'grup öner', 'kategori öner', 'kategori',
    'marka öner', 'alan öner', 'alan1', 'alan 1', 'marka',
    'ürün adı', 'urun adi', 'ürün ismi', 'ismi',
    'miktar', 'stok', 'adet', 'barkod', 'grup',
  ];

  /// Tek bir komut parçasını ("alış fiyat 25" gibi) dener; eşleşen bir
  /// tetik ifadesi bulunup uygulandıysa true döner. "alan1 ülker" gibi
  /// kullanıcı örneği de "marka" tetikleyicileri arasında destekleniyor.
  bool _tekKomutUygula(String parca) {
    double? sayiBul(String s) {
      final t = s.replaceAll('lira', '').replaceAll('tl', '').replaceAll('₺', '');
      final m = RegExp(r'[\d]+([.,]\d+)?').firstMatch(t);
      if (m == null) return null;
      return double.tryParse(m.group(0)!.replaceAll(',', '.'));
    }

    // Tetik ifadeleri UZUNDAN KISAYA doğru kontrol edilmeli (ör. "satış
    // fiyat" önce, düz "fiyat" sonra) — aksi halde yanlış alana yazabilir.
    final kurallar = <(List<String>, void Function(String))>[
      (['satış fiyat', 'satis fiyat', 'satış fiyatı'], (kalan) {
        final v = sayiBul(kalan);
        if (v != null) _alaniDoldur('satisFiyati', v.toStringAsFixed(2));
      }),
      (['alış fiyat', 'alis fiyat', 'alış fiyatı', 'maliyet'], (kalan) {
        final v = sayiBul(kalan);
        if (v != null) _alaniDoldur('alisFiyat', v.toStringAsFixed(2));
      }),
      (['kdv oranı', 'kdv oran'], (kalan) {
        final v = sayiBul(kalan);
        if (v != null) _alaniDoldur('kdvOrani', v.toStringAsFixed(0));
      }),
      (['stok', 'miktar', 'adet'], (kalan) {
        final v = sayiBul(kalan);
        if (v != null) _alaniDoldur('stok', v.toStringAsFixed(0));
      }),
      (['barkod'], (kalan) => _alaniDoldur('barkod', kalan)),
      (['grup öner', 'kategori öner'], (_) => _aiGrupOner()),
      (['marka öner', 'alan öner'], (_) => _aiAlan1Oner()),
      (['grup', 'kategori', 'ana grup'], (kalan) => _alaniDoldur('anaGrup', kalan)),
      // "alan1"/"alan 1" kullanıcının kendi örneğiydi — marka
      // tetikleyicilerine eklendi.
      (['alan1', 'alan 1', 'marka'], (kalan) => _alaniDoldur('marka', kalan)),
      (['ürün adı', 'urun adi', 'ürün ismi', 'ismi'], (kalan) => _alaniDoldur('urunAdi', kalan)),
    ];

    for (final (tetikler, uygula) in kurallar) {
      for (final tetik in tetikler) {
        final idx = parca.indexOf(tetik);
        if (idx != -1) {
          final kalan = parca.substring(idx + tetik.length).trim();
          uygula(kalan);
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _sesliKomutuUygula(String metinHam) async {
    final metin = metinHam.toLowerCase().trim();

    // ÖNCEDEN: sadece TEK bir komut işlenip fonksiyondan çıkılıyordu, VE
    // virgülle bölme denendiğinde bile "satış fiyat 30 alan1 ülker" gibi
    // konuşma-tanımanın virgül KOYMADIĞI durumlarda ikinci komut
    // kayboluyordu (sayı ayıklayıcı ilk sayıyı bulup gerisini atıyordu).
    // Artık metin, noktalama işaretine değil BİLİNEN TETİK KELİMELERİNİN
    // KONUMUNA göre bölünüyor — "alış fiyat 25 satış fiyat 30 alan1
    // ülker" gibi virgülsüz, art arda söylenmiş komutlar da doğru
    // ayrıştırılıyor.
    final tetikKonumlari = <int>[];
    for (final tetik in _tumTetikKelimeler) {
      var ara = 0;
      while (true) {
        final idx = metin.indexOf(tetik, ara);
        if (idx == -1) break;
        tetikKonumlari.add(idx);
        ara = idx + tetik.length;
      }
    }
    tetikKonumlari.sort();
    // Çakışan/iç içe konumları (ör. "satış fiyat" içindeki "fiyat") temizle
    final benzersizKonumlar = <int>[];
    for (final k in tetikKonumlari) {
      if (benzersizKonumlar.isEmpty || k - benzersizKonumlar.last > 2) {
        benzersizKonumlar.add(k);
      }
    }

    final parcalar = <String>[];
    if (benzersizKonumlar.length > 1) {
      for (var i = 0; i < benzersizKonumlar.length; i++) {
        final bas = benzersizKonumlar[i];
        final son = (i + 1 < benzersizKonumlar.length) ? benzersizKonumlar[i + 1] : metin.length;
        final parca = metin.substring(bas, son).replaceAll(',', ' ').trim();
        if (parca.isNotEmpty) parcalar.add(parca);
      }
    }

    if (parcalar.length > 1) {
      var enAzBirTaneUygulandi = false;
      for (final parca in parcalar) {
        if (_tekKomutUygula(parca)) enAzBirTaneUygulandi = true;
      }
      if (enAzBirTaneUygulandi) return;
      // Hiçbiri eşleşmediyse tek parça gibi devam et (aşağıdaki akıllı
      // yola düşsün).
    } else if (_tekKomutUygula(metin)) {
      return;
    }

    // 2) AKILLI YOL — hiçbir sabit tetik ifadesi geçmiyorsa, doğrudan
    // "ürün adı" varsaymak yerine Gemini'ye sorup DAHA İSABETLİ bir alan
    // tahmini alınıyor (ör. "bunun kilosu on iki lira elli" gibi tetik
    // kelimesi içermeyen ama fiyat belirten cümleleri de anlayabilir).
    // API anahtarı yoksa/hata olursa sessizce eski davranışa (ürün adı)
    // düşülür — kullanıcı hiçbir zaman "hiçbir şey olmadı" durumunda
    // kalmaz.
    final aiSonuc = await _ai.sesliKomutYorumla(metinHam);
    if (aiSonuc != null && aiSonuc['alan'] != null && aiSonuc['deger'] != null) {
      _alaniDoldur(aiSonuc['alan']!, aiSonuc['deger']!);
      return;
    }

    // 3) SON ÇARE — tek başına söylenmiş bir isim/kelime muhtemelen
    // ürün adıdır (en yaygın kullanım).
    if (metinHam.trim().isNotEmpty) {
      _alaniDoldur('urunAdi', metinHam.trim());
    }
  }

  // ---- YARDIMCI ----
  void _urunAdiGuncelle(String ad) {
    _c['urunAdi']?.text = ad;
    _aiDoldurulanAlanlar.add('urunAdi');
  }

  // ---- KAYDET / SİL ----
  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) {
      BildirimServisi.uyari(context, 'Zorunlu alanları doldurun');
      return;
    }
    final barkodVal = _c['barkod']?.text.trim() ?? '';
    if (barkodVal.isEmpty) {
      BildirimServisi.uyari(context, 'Barkod zorunludur.');
      return;
    }
    final kodVal = _c['kod']?.text.trim() ?? '';
    if (kodVal.isEmpty) {
      BildirimServisi.uyari(context, 'Ürün kodu zorunludur.');
      return;
    }

    // 🔴 Derin denetimde bulundu (P1): fiyat/stok alanları hep
    // `double.tryParse(...) ?? 0` ile okunuyordu — negatif bir değer
    // ("-50" gibi) geçerli bir double olarak parse edilip hiçbir yerde
    // kontrol edilmeden kaydediliyordu. Kaydetmeden önce tek bir yerden
    // negatif değer kontrolü ekleniyor.
    const negatifKontrolAlanlari = {
      'alisFiyat': 'Alış Fiyatı',
      'alisFiyatKdvDahil': 'Alış Fiyatı (KDV Dahil)',
      'satisFiyati': 'Satış Fiyatı',
      'indirimliFiyat': 'İndirimli Fiyat',
      'stok': 'Stok',
      'toptanFiyat': 'Toptan Fiyat',
      'koliIciMiktar': 'Koli İçi Miktar',
    };
    for (final girdi in negatifKontrolAlanlari.entries) {
      final metin = _c[girdi.key]?.text.trim().replaceAll(',', '.') ?? '';
      final deger = double.tryParse(metin);
      if (deger != null && deger < 0) {
        BildirimServisi.uyari(context, '${girdi.value} negatif olamaz.');
        return;
      }
    }

    setState(() => _yukleniyor = true);
    try {
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — QR menü ürününün
      // resim eklendiğinde QR menüden kaybolması): Bu ekran DÜZENLEME
      // modunda bile HER ZAMAN sıfırdan yeni bir UrunModel(...)
      // oluşturuyordu. Modeldeki 93 alandan SADECE 46'sı bu formda
      // bulunuyor — geri kalan 47 alan (qrMenude, promosyonAktif,
      // toptanSatista, evrakKontrolAktif, toplamMaliyet, toplamStok,
      // resmiBakiye, hacim, receteKatsayi, netAlisFiyat, eskiFiyat,
      // puanOrani, kartTipi gibi KOŞULSUZ/varsayılanlı alanlar dahil)
      // her düzenlemede SESSİZCE varsayılan değerine (çoğunlukla false/0)
      // SIFIRLANIYORDU. Kullanıcı sadece bir ÜRÜN RESMİ ekleyip
      // kaydettiğinde bile, o ürünün "QR Menüde Göster" ayarı arka
      // planda false'a düşüyordu — QR menüden "kayboluyordu".
      // Artık DÜZENLEME modunda mevcut modelin copyWith()'i kullanılıyor
      // — formda olmayan HER alan olduğu gibi korunuyor.
      final urun = widget.duzenlenecekUrun != null
          ? widget.duzenlenecekUrun!.copyWith(
        kod: _c['kod']?.text.trim().isEmpty == true ? null : _c['kod']?.text.trim(),
        barkod: barkodVal.isEmpty ? null : barkodVal,
        barkodlar: _c['barkodlar']?.text.trim().isEmpty == true ? null : _c['barkodlar']?.text.trim(),
        urunAdi: _c['urunAdi']?.text.trim() ?? '',
        alternatifUrunAdi: _c['altUrunAdi']?.text.trim().isEmpty == true ? null : _c['altUrunAdi']?.text.trim(),
        birimAdi: _birim,
        alisFiyat: double.tryParse(_c['alisFiyat']?.text.replaceAll(',', '.') ?? '') ?? 0,
        dovizKodu: _dovizKoduTakip,
        dovizTutari: _dovizTutariTakip,
        alisFiyatKdvDahil: double.tryParse(_c['alisFiyatKdvDahil']?.text.replaceAll(',', '.') ?? '') ?? 0,
        alisKdvOran: ParaUtils.sayiCoz(_c['alisKdvOran']?.text ?? '') ?? 18,
        kdvOran: _kdvOran,
        satisFiyati: double.tryParse(_c['satisFiyati']?.text.replaceAll(',', '.') ?? '') ?? 0,
        indirimOrani: ParaUtils.sayiCoz(_c['indirimOrani']?.text ?? '') ?? 0,
        indirimliFiyatKayitli: double.tryParse(_c['indirimliFiyat']?.text.replaceAll(',', '.') ?? '') ?? 0,
        stok: double.tryParse(_c['stok']?.text.replaceAll(',', '.') ?? '') ?? 0,
        minimumStok: ParaUtils.sayiCoz(_c['minimumStok']?.text ?? '') ?? 0,
        maksimumStok: ParaUtils.sayiCoz(_c['maksimumStok']?.text ?? '') ?? 0,
        marka: _c['marka']?.text.trim().isEmpty == true ? null : _c['marka']?.text.trim(),
        uretici: _c['uretici']?.text.trim().isEmpty == true ? null : _c['uretici']?.text.trim(),
        model: _c['model']?.text.trim().isEmpty == true ? null : _c['model']?.text.trim(),
        rafNumarasi: _c['rafNo']?.text.trim().isEmpty == true ? null : _c['rafNo']?.text.trim(),
        alan1: _c['alan1']?.text.trim().isEmpty == true ? null : _c['alan1']?.text.trim(),
        alan2: _c['alan2']?.text.trim().isEmpty == true ? null : _c['alan2']?.text.trim(),
        alan3: _c['alan3']?.text.trim().isEmpty == true ? null : _c['alan3']?.text.trim(),
        alan4: _c['alan4']?.text.trim().isEmpty == true ? null : _c['alan4']?.text.trim(),
        renk: _c['renk']?.text.trim().isEmpty == true ? null : _c['renk']?.text.trim(),
        beden: _c['beden']?.text.trim().isEmpty == true ? null : _c['beden']?.text.trim(),
        en: ParaUtils.sayiCoz(_c['en']?.text ?? '') ?? 0,
        boy: ParaUtils.sayiCoz(_c['boy']?.text ?? '') ?? 0,
        yukseklik: ParaUtils.sayiCoz(_c['yukseklik']?.text ?? '') ?? 0,
        agirlik: ParaUtils.sayiCoz(_c['agirlik']?.text ?? '') ?? 0,
        muhasebeKodu: _c['muhasebeKodu']?.text.trim().isEmpty == true ? null : _c['muhasebeKodu']?.text.trim(),
        anaGrup: _anaGrup,
        altGrup: _altGrup,
        toptanFiyat: double.tryParse(_c['toptanFiyat']?.text.replaceAll(',', '.') ?? '') ?? 0,
        koliIciMiktar: double.tryParse(_c['koliIciMiktar']?.text.replaceAll(',', '.') ?? '') ?? 0,
        koliBirimAdi: _koliBirimAdi,
        satisBirimiTipi: _satisBirimiTipi,
        paraBirimi: _paraBirimi,
        lotTakibi: _lotTakibi,
        seriNoTakibi: _seriTakibi,
        otomatikIndirim: _otomatikInd || (ParaUtils.sayiCoz(_c["indirimOrani"]?.text ?? '') ?? 0) > 0,
        aktif: _aktif,
        resimYolu: _mevcutResimYolu,
      )
          : UrunModel(
        id: widget.duzenlenecekUrun?.id,
        kod: _c['kod']?.text.trim().isEmpty == true ? null : _c['kod']?.text.trim(),
        barkod: barkodVal.isEmpty ? null : barkodVal,
        barkodlar: _c['barkodlar']?.text.trim().isEmpty == true ? null : _c['barkodlar']?.text.trim(),
        urunAdi: _c['urunAdi']?.text.trim() ?? '',
        alternatifUrunAdi: _c['altUrunAdi']?.text.trim().isEmpty == true ? null : _c['altUrunAdi']?.text.trim(),
        birimAdi: _birim,
        alisFiyat: double.tryParse(_c['alisFiyat']?.text.replaceAll(',', '.') ?? '') ?? 0,
        dovizKodu: _dovizKoduTakip,
        dovizTutari: _dovizTutariTakip,
        alisFiyatKdvDahil: double.tryParse(_c['alisFiyatKdvDahil']?.text.replaceAll(',', '.') ?? '') ?? 0,
        alisKdvOran: ParaUtils.sayiCoz(_c['alisKdvOran']?.text ?? '') ?? 18,
        kdvOran: _kdvOran,
        satisFiyati: double.tryParse(_c['satisFiyati']?.text.replaceAll(',', '.') ?? '') ?? 0,
        indirimOrani: ParaUtils.sayiCoz(_c['indirimOrani']?.text ?? '') ?? 0,
        indirimliFiyatKayitli: double.tryParse(_c['indirimliFiyat']?.text.replaceAll(',', '.') ?? '') ?? 0,
        stok: double.tryParse(_c['stok']?.text.replaceAll(',', '.') ?? '') ?? 0,
        minimumStok: ParaUtils.sayiCoz(_c['minimumStok']?.text ?? '') ?? 0,
        maksimumStok: ParaUtils.sayiCoz(_c['maksimumStok']?.text ?? '') ?? 0,
        marka: _c['marka']?.text.trim().isEmpty == true ? null : _c['marka']?.text.trim(),
        uretici: _c['uretici']?.text.trim().isEmpty == true ? null : _c['uretici']?.text.trim(),
        model: _c['model']?.text.trim().isEmpty == true ? null : _c['model']?.text.trim(),
        rafNumarasi: _c['rafNo']?.text.trim().isEmpty == true ? null : _c['rafNo']?.text.trim(),
        alan1: _c['alan1']?.text.trim().isEmpty == true ? null : _c['alan1']?.text.trim(),
        alan2: _c['alan2']?.text.trim().isEmpty == true ? null : _c['alan2']?.text.trim(),
        alan3: _c['alan3']?.text.trim().isEmpty == true ? null : _c['alan3']?.text.trim(),
        alan4: _c['alan4']?.text.trim().isEmpty == true ? null : _c['alan4']?.text.trim(),
        renk: _c['renk']?.text.trim().isEmpty == true ? null : _c['renk']?.text.trim(),
        beden: _c['beden']?.text.trim().isEmpty == true ? null : _c['beden']?.text.trim(),
        en: ParaUtils.sayiCoz(_c['en']?.text ?? '') ?? 0,
        boy: ParaUtils.sayiCoz(_c['boy']?.text ?? '') ?? 0,
        yukseklik: ParaUtils.sayiCoz(_c['yukseklik']?.text ?? '') ?? 0,
        agirlik: ParaUtils.sayiCoz(_c['agirlik']?.text ?? '') ?? 0,
        muhasebeKodu: _c['muhasebeKodu']?.text.trim().isEmpty == true ? null : _c['muhasebeKodu']?.text.trim(),
        anaGrup: _anaGrup,
        altGrup: _altGrup,
        toptanFiyat: double.tryParse(_c['toptanFiyat']?.text.replaceAll(',', '.') ?? '') ?? 0,
        koliIciMiktar: double.tryParse(_c['koliIciMiktar']?.text.replaceAll(',', '.') ?? '') ?? 0,
        koliBirimAdi: _koliBirimAdi,
        satisBirimiTipi: _satisBirimiTipi,
        paraBirimi: _paraBirimi,
        lotTakibi: _lotTakibi,
        seriNoTakibi: _seriTakibi,
        otomatikIndirim: _otomatikInd || (ParaUtils.sayiCoz(_c["indirimOrani"]?.text ?? '') ?? 0) > 0,
        aktif: _aktif,
        resimYolu: _mevcutResimYolu,
      );

      if (widget.duzenlenecekUrun == null) {
        final yeniId = await _depo.ekle(urun);
        if (mounted) BildirimServisi.basari(context, 'Ürün eklendi');
        // Kullanıcı isteği: görsel otomatik olarak buluta yüklensin —
        // ARKA PLANDA yapılıyor (await EDİLMİYOR), kullanıcı yükleme
        // bitmesini beklemeden ekrandan çıkabilir. Görsel yoksa veya
        // internet yoksa sessizce atlanır, ürün kaydı ASLA engellenmez.
        if (_mevcutResimYolu != null && _mevcutResimYolu!.isNotEmpty) {
  await _resimBulutaYukle(yeniId, _mevcutResimYolu!);
}
      } else {
        // FAZ 9 — Onay Merkezi (bildirim tipi): fiyat değişimi
        // ENGELLENMEDİ — güncelleme her zaman kaydedilir, sadece eşik
        // aşan fiyat değişimleri sonradan incelenebilsin diye kayda
        // düşülüyor.
        final eskiFiyat = widget.duzenlenecekUrun!.satisFiyati;
        final oran = fiyatDegisimOraniHesapla(eskiFiyat, urun.satisFiyati);
        await _depo.guncelle(urun);
        if (mounted) BildirimServisi.basari(context, 'Ürün güncellendi');
        if (oran != null) {
          OnayMerkeziServisi().kaydet(
            tur: OnayTuru.fiyatDegisimi,
            tutar: oran,
            esikTutar: OnayEsikleri.fiyatDegisimiOrani,
            referansTuru: 'urunler',
            referansId: widget.duzenlenecekUrun!.id,
            aciklama: '${urun.urunAdi}: ${ParaUtils.formatla(eskiFiyat)} → '
                '${ParaUtils.formatla(urun.satisFiyati)} (%${oran.toStringAsFixed(0)})',
          );
        }
        if (_mevcutResimYolu != null && _mevcutResimYolu!.isNotEmpty) {
  await _resimBulutaYukle(widget.duzenlenecekUrun!.id!, _mevcutResimYolu!);
}
      }
      if (mounted) context.pop(true);
    } catch (e) {
      // ÖNCEDEN BURADA HAM, TEKNİK HATA MESAJI GÖSTERİLİYORDU (örn.
      // "DatabaseException(UNIQUE constraint failed: urunler.barkod)")
      // — bir kasiyer/mağaza sahibi için tamamen anlamsız. En sık
      // karşılaşılan durum (barkod veya ürün kodu çakışması) artık
      // açık, anlaşılır bir mesajla gösteriliyor.
      final hataMetni = e.toString();
      String mesaj;
      if (hataMetni.contains('barkod')) {
        mesaj = 'Bu barkod zaten başka bir üründe kullanılıyor. '
            'Lütfen farklı bir barkod girin.';
      } else if (hataMetni.contains('UNIQUE constraint failed: urunler.kod')) {
        mesaj = 'Bu ürün kodu zaten kullanılıyor. Lütfen farklı bir kod girin.';
      } else {
        mesaj = 'Kaydedilemedi: $e';
      }
      if (mounted) BildirimServisi.hata(context, mesaj);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  /// Kullanıcı isteği: ürün görseli otomatik olarak Supabase Storage'a
  /// yüklensin — QR bulut menüde görünebilsin diye. Bu fonksiyon
  /// KASITLI OLARAK "await" edilmeden (fire-and-forget) çağrılıyor,
  /// böylece kullanıcı yükleme bitmesini beklemek zorunda kalmaz.
 Future<void> _resimBulutaYukle(int urunId, String yerelYol) async {
  try {
    LogServisi().bilgi('Resim yükleniyor: $yerelYol -> ürün ID: $urunId');
    final url = await UrunResimYuklemeServisi().yukle(yerelYol, urunId);
    if (url != null) {
      LogServisi().bilgi('Resim URL geldi: $url');
      await _depo.resimUrlGuncelle(urunId, url);
      if (mounted) {
        BildirimServisi.basari(context, 'Resim buluta yüklendi!');
      }
    } else {
      LogServisi().hata('Resim yüklendi ama URL boş döndü.');
      if (mounted) {
        BildirimServisi.hata(context, 'Resim yüklendi ama URL alınamadı.');
      }
    }
  } catch (e) {
    LogServisi().hata('Resim yükleme hatası', hata: e);
    if (mounted) {
      BildirimServisi.hata(context, 'Resim yüklenemedi: $e');
    }
  }
}
  Future<void> _sil() async {
    if (widget.duzenlenecekUrun?.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Ürünü Sil'),
        content: const Text('Bu ürünü silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _yukleniyor = true);
    try {
      await _depo.sil(widget.duzenlenecekUrun!.id!);
      if (mounted) {
        BildirimServisi.basari(context, 'Ürün silindi');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Silme hatası: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // ---- OTOMATİK BARKOD ÜRET ----
  // 🔴 Derin denetimde bulundu (P2): iki ayrı sorun vardı —
  //   1) `ORDER BY id DESC` en YÜKSEK M-numaralı barkodu değil en SON
  //      EKLENEN satırı buluyordu (Excel'den yüksek numaralı bir barkod
  //      düşük id ile önce eklenmişse ikisi aynı olmayabilirdi) —
  //      SQLite'ın sayısal CAST'i ile gerçek MAX numaraya göre sıralanıyor.
  //   2) `int.parse` try/catch'siz çağrılıyordu — biri elle "M-ABC" gibi
  //      rakam olmayan bir barkod girip kaydederse bir sonraki "Otomatik
  //      Barkod Üret" denemesi yakalanmamış bir FormatException ile
  //      çöküyordu. `int.tryParse` + `?? 0` ile artık böyle bir satır
  //      sessizce yok sayılıyor (0 kabul edilir), çökme riski yok.
  Future<String> _benzersizBarkodUret() async {
    final db = await Veritabani().db;
    final sonuc = await db.rawQuery('''
      SELECT barkod FROM urunler
      WHERE barkod LIKE 'M%'
        AND barkod IS NOT NULL
        AND barkod != ''
        AND is_deleted = 0
      ORDER BY CAST(SUBSTR(barkod, 2) AS INTEGER) DESC LIMIT 1
    ''');
    int yeniNumara = 1;
    if (sonuc.isNotEmpty) {
      final sonBarkod = sonuc.first['barkod'] as String;
      final numaraStr = sonBarkod.substring(1);
      yeniNumara = (int.tryParse(numaraStr) ?? 0) + 1;
    }
    return "M${yeniNumara.toString().padLeft(6, '0')}";
  }

  Future<void> _otomatikBarkodUret() async {
    final yeni = await _benzersizBarkodUret();
    if (!mounted) return;
    setState(() {
      _c['barkod']!.text = yeni;
      if (_c['kod']!.text.trim().isEmpty) _c['kod']!.text = yeni;
    });
    BildirimServisi.basari(context, 'Barkod üretildi: $yeni');
  }

  // ---- BUILD ----
}
