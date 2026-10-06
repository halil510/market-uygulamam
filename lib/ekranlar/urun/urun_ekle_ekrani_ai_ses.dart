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
    final Set<int> seciliIndeksler = {};
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
                      if (v == true) {
                        seciliIndeksler.add(i);
                      } else {
                        seciliIndeksler.remove(i);
                      }
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
        _anaGrup = cevap['ana_grup'];
        _aiDoldurulanAlanlar.add('ana_grup');
      });
      if (mounted) BildirimServisi.basari(context, 'Grup önerisi: $_anaGrup');
    } else {
      if (mounted) BildirimServisi.uyari(context, 'Grup önerisi alınamadı.');
    }
  }

  /// Tek mikrofon, doğal cümle: "ürün adı çikolata", "alış fiyat 25,50",
  /// "satış fiyat 35", "stok 100", "kdv oranı 18", "barkod 869...",
  /// "grup öner" gibi komutları dinler, doğru alanı bulup otomatik yazar.
  Future<void> _sesliKomut() async {
    final hazir = await _ses.hazirla();
    if (!hazir) {
      if (mounted) {
        BildirimServisi.uyari(context,
          'Mikrofon kullanılamıyor. Cihaz ayarlarından mikrofon iznini kontrol edin.');
      }
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

  // ---- SESLİ / YAZILI KOMUT MOTORU ------------------------------------
  // Tek cümlede istenen kadar alan: "ülker gofret alış yirmi beş buçuk
  // satış otuz beş kdv on stok yüz raf a üç". Ayrıştırma saf bir sınıfta
  // (UrunSesAyristirici — test edilebilir); burası yalnız forma yazar.
  // Sıra: kural tabanlı → (hiçbir şey bulunamazsa) Gemini çoklu alan →
  // (hâlâ yoksa) tek başına söylenen kelime ürün adıdır.
  Future<void> _sesliKomutuUygula(String metinHam) async {
    var sonuc = UrunSesAyristirici.ayristir(metinHam);

    if (sonuc.bos) {
      final ai = await _ai.sesliKomutCokluYorumla(metinHam);
      if (!mounted) return;
      if (ai != null && ai.isNotEmpty) {
        sonuc = UrunSesJson.jsondan(ai);
      }
    }

    if (sonuc.bos) {
      final t = metinHam.trim();
      // Sayı içermeyen tek başına bir ifade büyük olasılıkla ürün adıdır.
      if (t.isNotEmpty && !RegExp(r'\d').hasMatch(t) && sonuc.anlasilmayan.isEmpty) {
        await _urunSesSonucunuUygula(UrunSesSonuc(
            {'urunAdi': UrunSesAyristirici.basHarfBuyut(TrSayi.normalize(t))},
            const <String>{},
            const <String>[]));
        return;
      }
      if (mounted) {
        BildirimServisi.uyari(
            context,
            sonuc.anlasilmayan.isNotEmpty
                ? sonuc.anlasilmayan.join(' • ')
                : 'Anlayamadım: "$t". Örn: "satış fiyatı 35, stok 100, kdv 10".');
      }
      return;
    }
    await _urunSesSonucunuUygula(sonuc);
  }

  static String _sesSayi(double v, {int hane = 2}) {
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(hane).replaceFirst(RegExp(r'0+$'), '');
  }

  /// Ayrıştırılan alanları forma yazar. Yazma SIRASI önemlidir: formun
  /// dinleyicileri (KDV/fiyat/indirim) birbirini tetikler — önce KDV, sonra
  /// alış, sonra satış, en son indirim yazılır ki satış fiyatı yazımı
  /// indirimi sıfırlamasın.
  Future<void> _urunSesSonucunuUygula(UrunSesSonuc r) async {
    final a = r.alanlar;
    final uyarilar = <String>[...r.anlasilmayan];

    double? d(String k) => a[k] is double ? a[k] as double : null;
    String? s(String k) => a[k] is String ? a[k] as String : null;

    setState(() {
      // 1) KDV oranları
      final alisKdv = d('alisKdvOran');
      if (alisKdv != null) {
        final v = alisKdv.toStringAsFixed(0);
        _c['alisKdvOran']?.text = v;
        _alisKdvOran = v;
      }
      final satisKdv = d('kdvOran');
      if (satisKdv != null) _kdvOran = satisKdv.toStringAsFixed(0);

      // 2) Alış → KDV dahil alış
      if (d('alisFiyat') != null) _c['alisFiyat']?.text = _sesSayi(d('alisFiyat')!);
      if (d('alisFiyatKdvDahil') != null) {
        _c['alisFiyatKdvDahil']?.text = _sesSayi(d('alisFiyatKdvDahil')!, hane: 3);
      }
      // 3) Satış, ardından indirim
      if (d('satisFiyati') != null) _c['satisFiyati']?.text = _sesSayi(d('satisFiyati')!);
      if (d('indirimOrani') != null) _c['indirimOrani']?.text = _sesSayi(d('indirimOrani')!);
      if (d('toptanFiyat') != null) _c['toptanFiyat']?.text = _sesSayi(d('toptanFiyat')!);

      // 4) Miktarlar
      if (d('stok') != null) _c['stok']?.text = _sesSayi(d('stok')!, hane: 3);
      if (d('minimumStok') != null) _c['minimumStok']?.text = _sesSayi(d('minimumStok')!, hane: 3);
      if (d('maksimumStok') != null) _c['maksimumStok']?.text = _sesSayi(d('maksimumStok')!, hane: 3);
      if (d('koliIciMiktar') != null) _c['koliIciMiktar']?.text = _sesSayi(d('koliIciMiktar')!, hane: 3);
      if (d('agirlik') != null) _c['agirlik']?.text = _sesSayi(d('agirlik')!, hane: 3);

      // 5) Birim ve satış tipi
      final birim = s('birim');
      if (birim != null) {
        if (_birimler.isEmpty || _birimler.contains(birim)) {
          _birim = birim;
          _kgModu = birim == 'KG' || birim == 'GR' || birim == 'LİTRE' || birim == 'ML';
        } else {
          uyarilar.add('"$birim" birimi tanımlı değil (Ayarlar > Birimler)');
        }
      }
      if (s('satisBirimiTipi') != null) _satisBirimiTipi = s('satisBirimiTipi')!;
      if (s('koliBirimAdi') != null) _koliBirimAdi = s('koliBirimAdi')!;

      // 6) Metin alanları
      if (s('urunAdi') != null) _urunAdiGuncelle(s('urunAdi')!);
      if (s('barkod') != null) {
        _c['barkod']?.text = s('barkod')!;
        _aiDoldurulanAlanlar.add('barkod');
        // Form ürün kodunu zorunlu tutar; boşsa barkodla aynı yap (otomatik
        // barkod üretiminde de böyle).
        if ((_c['kod']?.text.trim().isEmpty ?? true) && s('kod') == null) {
          _c['kod']?.text = s('barkod')!;
        }
      }
      for (final k in const [
        'kod', 'marka', 'uretici', 'model', 'rafNo', 'renk', 'beden',
        'muhasebeKodu', 'alan1', 'alan2', 'alan3', 'alan4',
      ]) {
        if (s(k) != null) _c[k]?.text = s(k)!;
      }
      if (s('anaGrup') != null) {
        _anaGrup = s('anaGrup');
        _aiDoldurulanAlanlar.add('ana_grup');
      }
      if (s('altGrup') != null) _altGrup = s('altGrup');

      // 7) Anahtarlar
      if (a['aktif'] is bool) _aktif = a['aktif'] as bool;
      if (a['lotTakibi'] is bool) _lotTakibi = a['lotTakibi'] as bool;
      if (a['seriTakibi'] is bool) _seriTakibi = a['seriTakibi'] as bool;
    });

    // Kullanıcıya NE yazıldığını göster — sessizce değişmesin.
    if (r.alanlar.isNotEmpty && mounted) {
      final satirlar = r.ozetSatirlari();
      final gosterilen = satirlar.take(6).join(' • ');
      final fazla = satirlar.length > 6 ? ' (+${satirlar.length - 6})' : '';
      BildirimServisi.basari(context, '✓ $gosterilen$fazla');
    }
    if (uyarilar.isNotEmpty && mounted) {
      BildirimServisi.uyari(context, uyarilar.join(' • '));
    }

    // Eylemler
    if (r.eylemler.contains('barkodUret')) await _otomatikBarkodUret();
    if (r.eylemler.contains('grupOner')) await _aiGrupOner();
    if (r.eylemler.contains('markaOner')) await _aiMarkaOner();
    if (s('urunAdi') != null && widget.duzenlenecekUrun == null) {
      _benzerUrunKontrolEt(s('urunAdi')!);
    }
    if (r.eylemler.contains('kaydet') && mounted) await _sesleKaydetOnayi();
  }

  /// Sesle söylenen "kaydet" yanlış tanımaya karşı onay ister.
  Future<void> _sesleKaydetOnayi() async {
    final ad = _c['urunAdi']?.text.trim() ?? '';
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Ürün kaydedilsin mi?'),
        content: Text(
          ad.isEmpty
              ? 'Ürün adı boş.'
              : '$ad\nAlış: ${_c['alisFiyat']?.text ?? ''}  '
                  'Satış: ${_c['satisFiyati']?.text ?? ''}  '
                  'Stok: ${_c['stok']?.text ?? ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (onay == true && mounted) await _kaydet();
  }

  Future<void> _aiMarkaOner() async {
    final ad = _c['urunAdi']?.text.trim();
    if (ad == null || ad.isEmpty) {
      BildirimServisi.uyari(context, 'Önce ürün adını söyleyin/girin.');
      return;
    }
    final cevap = await _ai.urunKategoriOner(ad);
    if (!mounted) return;
    if (cevap['alan1'] != null && cevap['alan1']!.isNotEmpty) {
      setState(() {
        _c['marka']?.text = cevap['alan1']!;
        _aiDoldurulanAlanlar.add('alan1');
      });
      BildirimServisi.basari(context, 'Marka önerisi: ${cevap['alan1']}');
    } else {
      BildirimServisi.uyari(context, 'Marka önerilemedi.');
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
    final indirimOrani = ParaUtils.sayiCoz(_c['indirimOrani']?.text ?? '');
    if (indirimOrani != null && (indirimOrani < 0 || indirimOrani >= 100)) {
      BildirimServisi.uyari(context, 'İndirim % 0 ile 100 arasında olmalı.');
      return;
    }
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
        alisFiyat: ParaUtils.sayiCoz(_c['alisFiyat']?.text) ?? 0,
        dovizKodu: _dovizKoduTakip,
        dovizTutari: _dovizTutariTakip,
        alisFiyatKdvDahil: ParaUtils.sayiCoz(_c['alisFiyatKdvDahil']?.text) ?? 0,
        alisKdvOran: ParaUtils.sayiCoz(_c['alisKdvOran']?.text ?? '') ?? 18,
        kdvOran: _kdvOran,
        satisFiyati: ParaUtils.sayiCoz(_c['satisFiyati']?.text) ?? 0,
        indirimOrani: ParaUtils.sayiCoz(_c['indirimOrani']?.text ?? '') ?? 0,
        indirimliFiyatKayitli: ParaUtils.sayiCoz(_c['indirimliFiyat']?.text) ?? 0,
        stok: ParaUtils.sayiCoz(_c['stok']?.text) ?? 0,
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
        toptanFiyat: ParaUtils.sayiCoz(_c['toptanFiyat']?.text) ?? 0,
        koliIciMiktar: ParaUtils.sayiCoz(_c['koliIciMiktar']?.text) ?? 0,
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
        alisFiyat: ParaUtils.sayiCoz(_c['alisFiyat']?.text) ?? 0,
        dovizKodu: _dovizKoduTakip,
        dovizTutari: _dovizTutariTakip,
        alisFiyatKdvDahil: ParaUtils.sayiCoz(_c['alisFiyatKdvDahil']?.text) ?? 0,
        alisKdvOran: ParaUtils.sayiCoz(_c['alisKdvOran']?.text ?? '') ?? 18,
        kdvOran: _kdvOran,
        satisFiyati: ParaUtils.sayiCoz(_c['satisFiyati']?.text) ?? 0,
        indirimOrani: ParaUtils.sayiCoz(_c['indirimOrani']?.text ?? '') ?? 0,
        indirimliFiyatKayitli: ParaUtils.sayiCoz(_c['indirimliFiyat']?.text) ?? 0,
        stok: ParaUtils.sayiCoz(_c['stok']?.text) ?? 0,
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
        toptanFiyat: ParaUtils.sayiCoz(_c['toptanFiyat']?.text) ?? 0,
        koliIciMiktar: ParaUtils.sayiCoz(_c['koliIciMiktar']?.text) ?? 0,
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
  // Madde 2 sertleştirmesi (2026-09-22): doğrudan Veritabani().db erişimi
  // kaldırıldı — UrunDeposu.benzersizBarkodUret() üzerinden, davranış
  // birebir korunarak (bkz. o metodun doc yorumu).
  Future<String> _benzersizBarkodUret() => _depo.benzersizBarkodUret();

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
