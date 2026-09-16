// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: bu dosya extension ile _UrunEkleEkraniState'e metod ekliyor —
// setState() gerçekten kendi State sınıfının üzerinde çağrılıyor, ama
// analizci extension içinden çağrıyı "korumalı üyeye dışarıdan erişim"
// sayıyor (bkz. iade_ekrani_hizli.dart'taki aynı, doğrulanmış not).
// lib/ekranlar/urun/urun_ekle_ekrani_form.dart
//
// urun_ekle_ekrani.dart'ın parçası (part/part of) — dosya çok büyümüştü
// (2075 satır), _UrunEkleEkraniState'in özel (lifecycle olmayan) metodları
// sorumluluk alanına göre 3 dosyaya bölündü. Davranış BİREBİR AYNI —
// extension mekanizması Dart'ta bir sınıfa DIŞARIDAN instance metodu
// eklemenin standart yolu (aynı iade_ekrani.dart'taki desen); private
// alanlara erişim aynı kütüphane (part/part of) içinde sorunsuz çalışır.
// Bu dosya: form doldurma, fiyat/KDV/indirim hesaplama, Gemini API
// anahtarı, dropdown yükleme, resim seçme/kamera OCR, barkod tarama,
// fatura fotoğrafından ürün çıkarma.
part of 'urun_ekle_ekrani.dart';

extension _UrunEkleFormExt on _UrunEkleEkraniState {
  void _listenerlariEkle() {
    _c['alisFiyat']?.addListener(_alisFiyatHesapla);
    _c['alisKdvOran']?.addListener(_alisKdvOranHesapla);
    _c['alisFiyatKdvDahil']?.addListener(_alisKdvliFiyatHesapla);
    _c['satisFiyati']?.addListener(_karHesapla);
    _c['satisFiyati']?.addListener(_satisFiyatiDegistiIndirimSifirla);
    _c['indirimOrani']?.addListener(_indirimHesapla);
    _c['indirimliFiyat']?.addListener(_indirimTersHesapla);
  }

  void _initControllers() {
    final keys = [
      'kod', 'barkod', 'barkodlar', 'urunAdi', 'altUrunAdi',
      'alisFiyat', 'alisFiyatKdvDahil', 'alisKdvOran', 'satisFiyati',
      'indirimOrani', 'indirimliFiyat', 'karOrani',
      'stok', 'minimumStok', 'maksimumStok',
      'marka', 'uretici', 'model', 'rafNo', 'pluNo',
      'alan1', 'alan2', 'alan3', 'alan4',
      'renk', 'beden', 'en', 'boy', 'yukseklik', 'agirlik',
      'muhasebeKodu',
      // Kullanıcı isteği: "toptan satış — Ülker gibi firmaların
      // kullandığı profesyonel sistem."
      'toptanFiyat', 'koliIciMiktar',
    ];
    for (final key in keys) {
      _c[key] = TextEditingController();
    }
    _c['stok']?.text = '0';
    _c['alisKdvOran']?.text = '18';
  }

  Future<void> _geminiApiAnahtariniKontrolEt() async {
    // 🔴 DÜZELTME: Anahtar burada doğrudan SharedPreferences'tan
    // okunuyordu — ama AiVisionServisi.setApiKey() (bu ekranın kayıt
    // yolu) artık güvenli depoya yazıyor. Bu okuma yolu güncellenmeden
    // bırakılsaydı, kaydedilen anahtar HİÇ BULUNAMAZDI (her zaman
    // "eksik" sanılıp dialog tekrar tekrar gösterilirdi).
    final mevcutAnahtar = await AiVisionServisi().apiKeyGetir();
    if (mevcutAnahtar == null || mevcutAnahtar.isEmpty) {
      await _geminiApiAnahtarDialogu();
    }
  }

  Future<void> _geminiApiAnahtarDialogu() async {
    final TextEditingController controller = TextEditingController();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.key, color: Colors.amber),
            SizedBox(width: 8),
            Text('Gemini API Anahtarı'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ücretsiz anahtar almak için Google AI Studio\'ya gidin:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://aistudio.google.com/apikey'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text(
                'https://aistudio.google.com/apikey',
                style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'API Anahtarını Yapıştır',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Anahtar gizli kalacak ve cihazda saklanacaktır.',
              style: TextStyle(fontSize: 10, color: context.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              BildirimServisi.uyari(context, 'Gemini anahtarı olmadan OCR daha az başarılı olabilir.');
            },
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isEmpty) {
                BildirimServisi.uyari(context, 'Lütfen geçerli bir anahtar girin.');
                return;
              }
              await AiVisionServisi().setApiKey(key);
              if (!mounted) return;
              Navigator.pop(ctx);
              BildirimServisi.basari(context, 'API anahtarı başarıyla kaydedildi!');
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _yukleDropdownlar() async {
    if (_dropdownlarYuklendi || _ilkYuklemeYapildi) return;
    _ilkYuklemeYapildi = true;
    try {
      final birimler = await BirimEkrani.birimListesiGetir();
      if (!mounted) return;
      final urunler  = await _depo.tumunuGetir();
      if (!mounted) return;
      final anaGruplar = urunler.map((u) => u.anaGrup).where((g) => g != null && g!.isNotEmpty).cast<String>().toSet().toList()..sort();
      final alan1lar = urunler.map((u) => u.alan1).where((a) => a != null && a!.isNotEmpty).cast<String>().toSet().toList()..sort();
      final altGruplar = urunler.map((u) => u.altGrup).where((g) => g != null && g!.isNotEmpty).cast<String>().toSet().toList()..sort();
      if (mounted) {
        setState(() {
          _birimler   = birimler;
          _anaGruplar = anaGruplar;
          _alan1lar   = alan1lar;
          _altGruplar = altGruplar;
          if (!birimler.contains(_birim) && birimler.isNotEmpty) _birim = birimler.first;
          _dropdownlarYuklendi = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _dropdownlarYuklendi = true);
    }
  }

  void _doldur(UrunModel u) {
    _dolduruluyor = true;
    _c['kod']?.text           = u.kod ?? '';
    _c['barkod']?.text        = u.barkod ?? '';
    _c['barkodlar']?.text     = u.barkodlar ?? '';
    _c['urunAdi']?.text       = u.urunAdi;
    _c['altUrunAdi']?.text    = u.alternatifUrunAdi ?? '';
    _c['alisFiyat']?.text     = u.alisFiyat > 0 ? u.alisFiyat.toStringAsFixed(3) : '';
    _c['alisFiyatKdvDahil']?.text = u.alisFiyatKdvDahil > 0 ? u.alisFiyatKdvDahil.toStringAsFixed(3) : '';
    _c['alisKdvOran']?.text   = u.alisKdvOran.toStringAsFixed(0);
    _c['satisFiyati']?.text   = u.satisFiyati.toStringAsFixed(3);
    _c['indirimOrani']?.text  = u.indirimOrani > 0 ? u.indirimOrani.toStringAsFixed(2) : '';
    _c['indirimliFiyat']?.text = u.indirimliFiyat > 0 ? u.indirimliFiyat.toStringAsFixed(3) : '';
    _c['karOrani']?.text      = u.karOrani > 0 ? u.karOrani.toStringAsFixed(2) : '';
    _c['stok']?.text          = u.stok.toStringAsFixed(u.birimAdi == 'KG' ? 3 : 0);
    _c['minimumStok']?.text   = u.minimumStok > 0 ? u.minimumStok.toStringAsFixed(0) : '';
    _c['maksimumStok']?.text  = u.maksimumStok > 0 ? u.maksimumStok.toStringAsFixed(0) : '';
    _c['marka']?.text         = u.marka ?? '';
    _c['uretici']?.text       = u.uretici ?? '';
    _c['model']?.text         = u.model ?? '';
    _c['rafNo']?.text         = u.rafNumarasi ?? '';
    _c['alan1']?.text         = u.alan1 ?? '';
    _c['alan2']?.text         = u.alan2 ?? '';
    _c['renk']?.text          = u.renk ?? '';
    _c['beden']?.text         = u.beden ?? '';
    _c['en']?.text            = u.en > 0 ? u.en.toString() : '';
    _c['boy']?.text           = u.boy > 0 ? u.boy.toString() : '';
    _c['agirlik']?.text       = u.agirlik > 0 ? u.agirlik.toString() : '';
    _c['muhasebeKodu']?.text  = u.muhasebeKodu ?? '';
    _birim      = u.birimAdi.isNotEmpty ? u.birimAdi : 'ADET';
    _paraBirimi = u.paraBirimi;
    _kdvOran    = u.kdvOran;
    _alisKdvOran = u.alisKdvOran.toStringAsFixed(0);
    _anaGrup    = u.anaGrup?.isNotEmpty == true ? u.anaGrup : null;
    _altGrup    = u.altGrup?.isNotEmpty == true ? u.altGrup : null;
    _c['toptanFiyat']?.text = u.toptanFiyat > 0 ? u.toptanFiyat.toStringAsFixed(2) : '';
    _c['koliIciMiktar']?.text = u.koliIciMiktar > 0 ? u.koliIciMiktar.toStringAsFixed(0) : '';
    _koliBirimAdi = u.koliBirimAdi;
    _satisBirimiTipi = u.satisBirimiTipi;
    _lotTakibi  = u.lotTakibi;
    _seriTakibi = u.seriNoTakibi;
    _otomatikInd = u.otomatikIndirim;
    _aktif      = u.aktif;
    _kgModu     = u.birimAdi == 'KG' || u.birimAdi == 'GR' || u.birimAdi == 'LİTRE';
    if (u.resimYolu != null && u.resimYolu!.isNotEmpty && File(u.resimYolu!).existsSync()) {
      _mevcutResimYolu = u.resimYolu;
      _secilenResim = File(u.resimYolu!);
    }
    _dolduruluyor = false;
  }

  // ---- KDV HESAPLAMALARI ----
  void _alisFiyatHesapla() {
    if (_hesaplamaCalisiyor) return;
    _hesaplamaCalisiyor = true;
    final alisHam = double.tryParse(_c['alisFiyat']?.text.replaceAll(',', '.') ?? '') ?? 0;
    final alisKdvOranDeger = ParaUtils.sayiCoz(_c['alisKdvOran']?.text ?? '') ?? 0;
    if (alisHam > 0) {
      final alisKdvli = alisHam * (1 + alisKdvOranDeger / 100);
      _c['alisFiyatKdvDahil']?.text = alisKdvli.toStringAsFixed(3);
    } else {
      _c['alisFiyatKdvDahil']?.text = '0';
    }
    _karHesapla();
    _hesaplamaCalisiyor = false;
  }

  void _alisKdvOranHesapla() {
    if (_hesaplamaCalisiyor) return;
    _hesaplamaCalisiyor = true;
    final alisHam = double.tryParse(_c['alisFiyat']?.text.replaceAll(',', '.') ?? '') ?? 0;
    final alisKdvOranDeger = ParaUtils.sayiCoz(_c['alisKdvOran']?.text ?? '') ?? 0;
    final alisKdvli = double.tryParse(_c['alisFiyatKdvDahil']?.text.replaceAll(',', '.') ?? '') ?? 0;
    if (alisHam > 0) {
      final yeniKdvli = alisHam * (1 + alisKdvOranDeger / 100);
      _c['alisFiyatKdvDahil']?.text = yeniKdvli.toStringAsFixed(3);
    } else if (alisKdvli > 0) {
      final yeniAlis = alisKdvli / (1 + alisKdvOranDeger / 100);
      _c['alisFiyat']?.text = yeniAlis.toStringAsFixed(3);
    }
    _karHesapla();
    _hesaplamaCalisiyor = false;
  }

  void _alisKdvliFiyatHesapla() {
    if (_hesaplamaCalisiyor) return;
    _hesaplamaCalisiyor = true;
    final alisKdvli = double.tryParse(_c['alisFiyatKdvDahil']?.text.replaceAll(',', '.') ?? '') ?? 0;
    final alisKdvOranDeger = ParaUtils.sayiCoz(_c['alisKdvOran']?.text ?? '') ?? 0;
    if (alisKdvli > 0 && alisKdvOranDeger > 0) {
      final alisHam = alisKdvli / (1 + alisKdvOranDeger / 100);
      _c['alisFiyat']?.text = alisHam.toStringAsFixed(3);
    } else if (alisKdvli > 0) {
      _c['alisFiyat']?.text = alisKdvli.toStringAsFixed(3);
    } else {
      _c['alisFiyat']?.text = '0';
    }
    _karHesapla();
    _hesaplamaCalisiyor = false;
  }

  void _karHesapla() {
    if (_hesaplamaCalisiyor) return;
    _hesaplamaCalisiyor = true;
    final alisKdvli = double.tryParse(_c['alisFiyatKdvDahil']?.text.replaceAll(',', '.') ?? '') ?? 0;
    final satis = double.tryParse(_c['satisFiyati']?.text.replaceAll(',', '.') ?? '') ?? 0;
    if (satis > 0 && alisKdvli > 0) {
      final kar = ((satis - alisKdvli) / alisKdvli) * 100;
      _c['karOrani']?.text = kar.toStringAsFixed(2);
    } else if (satis > 0 && alisKdvli == 0) {
      _c['karOrani']?.text = '100';
    } else {
      _c['karOrani']?.text = '0';
    }
    _hesaplamaCalisiyor = false;
  }

  // 🔴 DÜZELTME (kullanıcı bulgusu — "satış fiyat değiştiğinde indirimli
  // fiyat eski kalıyor, hızlı satışta o eski indirimi yansıtıyor"): satış
  // fiyatı bu üründe daha önce girilmiş bir indirimli fiyat/oranla
  // BİRLİKTE kaydedilmişti. Satış fiyatı düzenlenirken indirim alanları
  // hiç sıfırlanmıyordu — indirimliFiyat (mutlak, kayıtlı) satır DB'ye
  // AYNEN kaydediliyor ve sepet_provider._fiyatHesapla() bunu satış
  // fiyatından bağımsız, koşulsuz uyguluyordu (satış fiyatı 100→150
  // olsa bile ürün hâlâ eski 85'ten satılabiliyordu).
  //
  // Artık satış fiyatı değiştiğinde indirim alanları BOŞALTILIYOR —
  // kullanıcı yeni fiyat için indirim istiyorsa BİLİNÇLİ OLARAK yeniden
  // girmeli. Bu, profesyonel ERP'lerin çoğunun izlediği güvenli
  // yaklaşımdır (fiyat değişince eski indirim sessizce miras kalmaz).
  void _satisFiyatiDegistiIndirimSifirla() {
    if (_hesaplamaCalisiyor || _dolduruluyor) return;
    final oranDolu = (_c['indirimOrani']?.text.trim().isNotEmpty ?? false);
    final fiyatDolu = (_c['indirimliFiyat']?.text.trim().isNotEmpty ?? false);
    if (!oranDolu && !fiyatDolu) return;
    _hesaplamaCalisiyor = true;
    _c['indirimOrani']?.text = '';
    _c['indirimliFiyat']?.text = '';
    _hesaplamaCalisiyor = false;
  }

  void _indirimHesapla() {
    if (_hesaplamaCalisiyor) return;
    _hesaplamaCalisiyor = true;
    final satis = double.tryParse(_c['satisFiyati']?.text.replaceAll(',', '.') ?? '') ?? 0;
    final oran  = ParaUtils.sayiCoz(_c['indirimOrani']?.text ?? '') ?? 0;
    if (satis > 0 && oran > 0) {
      final indirimli = satis * (1 - oran / 100);
      _c['indirimliFiyat']?.text = indirimli.toStringAsFixed(3);
    } else if (satis > 0) {
      _c['indirimliFiyat']?.text = satis.toStringAsFixed(3);
    }
    _hesaplamaCalisiyor = false;
  }

  void _indirimTersHesapla() {
    if (_hesaplamaCalisiyor) return;
    _hesaplamaCalisiyor = true;
    final satis = double.tryParse(_c['satisFiyati']?.text.replaceAll(',', '.') ?? '') ?? 0;
    final indirimli = double.tryParse(_c['indirimliFiyat']?.text.replaceAll(',', '.') ?? '') ?? 0;
    if (satis > 0 && indirimli > 0 && indirimli < satis) {
      final oran = ((satis - indirimli) / satis) * 100;
      _c['indirimOrani']?.text = oran.toStringAsFixed(2);
    } else if (satis > 0 && indirimli == satis) {
      _c['indirimOrani']?.text = '0';
    }
    _hesaplamaCalisiyor = false;
  }

  // ---- RESİM YÖNETİMİ ----
  Future<Directory> _resimDizini() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/urun_resimleri');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _resimSec() async {
    final kaynak = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: AppRenkler.primary),
            title: const Text('Kameradan Çek'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppRenkler.primary),
            title: const Text('Galeriden Seç'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          if (_secilenResim != null || _mevcutResimYolu != null)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Resmi Kaldır', style: TextStyle(color: Colors.red)),
              onTap: () {
                setState(() { _secilenResim = null; _mevcutResimYolu = null; });
                Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
    if (kaynak == null) return;
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: kaynak,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (xFile != null) {
      final dir = await _resimDizini();
      final dosyaAdi = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final hedef = File('${dir.path}/$dosyaAdi');
      await File(xFile.path).copy(hedef.path);
      if (!mounted) return;
      setState(() {
        _secilenResim = hedef;
        _mevcutResimYolu = hedef.path;
      });

      // Ürün adı henüz boşsa, seçilen ürün fotoğrafından bilgi çıkarmayı dene
      if ((_c['urunAdi']?.text ?? '').trim().isEmpty) {
        await _urunFotografindanDoldur(hedef);
      }
    }
  }

  Future<void> _urunFotografindanDoldur(File resim) async {
    if (!mounted) return;
    final scaffold = ScaffoldMessenger.of(context);
    final snack = SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        const Expanded(child: Text('Ürün fotoğrafı analiz ediliyor...')),
      ]),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 15),
    );
    scaffold.showSnackBar(snack);

    final bilgi = await _ai.urunFotografindanBilgiCikar(resim);
    scaffold.removeCurrentSnackBar();
    if (!mounted || bilgi.isEmpty) return;

    _aiDoldurulanAlanlar.clear();
    if (bilgi['urun_adi'] != null && (bilgi['urun_adi'] as String).isNotEmpty) {
      _urunAdiGuncelle(bilgi['urun_adi'] as String);
    }
    if (bilgi.containsKey('ana_grup') && (bilgi['ana_grup']?.toString().isNotEmpty ?? false)) {
      _anaGrup = bilgi['ana_grup'] as String?;
    }
    if (bilgi.containsKey('alt_grup')) _altGrup = bilgi['alt_grup'] as String?;
    if (bilgi.containsKey('alan1') && (bilgi['alan1']?.toString().isNotEmpty ?? false)) {
      _c['alan1']?.text = bilgi['alan1'] as String? ?? '';
    }
    // KDV oranı — önceden hiç doldurulmuyordu, AI doğru çıkarsa bile
    // sessizce atılıyordu. Artık diğer AI-doldurma akışlarıyla (toplu
    // fatura tarama) tutarlı şekilde form alanına yazılıyor.
    if (bilgi.containsKey('kdv_orani')) {
      final kdvDeger = (bilgi['kdv_orani'] as num?)?.toDouble();
      if (kdvDeger != null && kdvDeger > 0) _kdvOran = kdvDeger.toStringAsFixed(0);
    }
    if (bilgi.containsKey('birim_adi') && (bilgi['birim_adi']?.toString().isNotEmpty ?? false)) {
      _birim = bilgi['birim_adi'] as String? ?? _birim;
    }
    if (bilgi.containsKey('alis_fiyat')) {
      final v = (bilgi['alis_fiyat'] as num?)?.toString();
      if (v != null && v != '0' && v != '0.0') _c['alisFiyat']?.text = v;
    }
    if (bilgi.containsKey('satis_fiyati')) {
      _c['satisFiyati']?.text = (bilgi['satis_fiyati'] as num?)?.toString() ?? '';
    }
    if (bilgi.containsKey('kod') && (bilgi['kod']?.toString().isNotEmpty ?? false)) {
      if (_c['barkod']!.text.isEmpty) _c['barkod']!.text = bilgi['kod'] as String;
      if (_c['kod']!.text.isEmpty) _c['kod']!.text = bilgi['kod'] as String;
    }

    setState(() {});
    if (mounted && (bilgi['urun_adi'] != null || bilgi['alan1'] != null)) {
      BildirimServisi.basari(context, 'Fotoğraftan ürün bilgisi dolduruldu (KDV dahil), kontrol edin.');
    }
  }

  // ---- KAMERA İLE RESİM ÇEK (AI İLE DOLDUR) ----
  Future<void> _kameraIleOku() async {
    final picker = ImagePicker();
    final XFile? resim = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 80,
    );
    if (resim == null || !mounted) return;

    final scaffold = ScaffoldMessenger.of(context);
    final snack = SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        const Expanded(child: Text('Resim işleniyor (OCR/AI)...')),
      ]),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 20),
    );
    scaffold.showSnackBar(snack);

    final urunler = await _ai.faturaUrunleriCikar(resim);
    scaffold.removeCurrentSnackBar();

    if (!mounted) return;
    if (urunler.isEmpty) {
      BildirimServisi.uyari(context, 'Resimden ürün bilgisi çıkarılamadı. Lütfen barkod okumayı deneyin veya manuel girin.');
      return;
    }

    List<Map<String, dynamic>> secilenler;
    if (urunler.length > 1) {
      secilenler = await _faturaUrunSecDialog(urunler);
      if (secilenler.isEmpty) return;
    } else {
      secilenler = urunler;
    }

    final ilk = secilenler.first;
    final urunAdi = ilk['urun_adi']?.toString() ?? '';

    // AI ile kategori ve marka önerisi al
    Map<String, String> kategoriOnerisi = {};
    if (urunAdi.isNotEmpty) {
      kategoriOnerisi = await _ai.urunKategoriOner(urunAdi);
    }

    _aiDoldurulanAlanlar.clear();
    _urunAdiGuncelle(urunAdi);

    // OCR'den gelen değerleri öncelikli kullan, yoksa AI önerisini kullan
    if (ilk.containsKey('ana_grup') && ilk['ana_grup'].toString().isNotEmpty) {
      _anaGrup = ilk['ana_grup'] as String?;
    } else if (kategoriOnerisi.containsKey('ana_grup')) {
      _anaGrup = kategoriOnerisi['ana_grup'];
    }

    if (ilk.containsKey('alt_grup')) _altGrup = ilk['alt_grup'] as String?;
    if (ilk.containsKey('kdv_orani')) _kdvOran = (ilk['kdv_orani'] as num?)?.toString() ?? '18';
    if (ilk.containsKey('birim_adi')) _birim = ilk['birim_adi'] as String? ?? 'Adet';

    if (ilk.containsKey('alan1') && ilk['alan1'].toString().isNotEmpty) {
      _c['alan1']?.text = ilk['alan1'] as String? ?? '';
    } else if (kategoriOnerisi.containsKey('alan1')) {
      _c['alan1']?.text = kategoriOnerisi['alan1'] ?? '';
    }

    if (ilk.containsKey('alan2')) _c['alan2']?.text = ilk['alan2'] as String? ?? '';
    if (ilk.containsKey('alis_fiyat')) {
      _c['alisFiyat']?.text = (ilk['alis_fiyat'] as num?)?.toString() ?? '';
    }
    if (ilk.containsKey('satis_fiyati')) {
      _c['satisFiyati']?.text = (ilk['satis_fiyati'] as num?)?.toString() ?? '';
    }
    if (ilk.containsKey('kod')) {
      _c['barkod']!.text = ilk['kod'] as String? ?? '';
    }
    if (_c['kod']!.text.isEmpty) _c['kod']!.text = _c['barkod']?.text ?? '';

    // 🔴 DÜZELTME (Madde 21 — Para Hesaplamaları denetimi, 2026-09-16):
    // BURADA ÖNCEDEN, AI 'kdv_dahil_satis: true' dediğinde (yani okuduğu
    // fiyatın zaten KDV dahil olduğunu bildirdiğinde) o fiyattan KDV
    // ÇIKARILIP satisFiyati'na öyle yazılıyordu. Ama satisFiyati alanı
    // GERÇEKTE KDV DAHİL saklanıyor (kullanıcı onayıyla doğrulandı, bkz.
    // sepet_model.dart baş yorumu) — yani AI zaten doğru (KDV dahil)
    // fiyatı okumuşken, kod bunu KDV oranı kadar (~%18-20) DÜŞÜRÜP
    // yanlış kaydediyordu. AI'nin okuduğu KDV dahil fiyat zaten doğru
    // formatta olduğundan artık hiçbir dönüşüm yapılmıyor.

    if (!mounted) return;   // AI/resim await'leri sonrası
    setState(() {});
    BildirimServisi.basari(context, 'Ürün bilgileri resimden dolduruldu, kontrol edin.');
  }

  // ---- BARKOD TARA ----
  Future<void> _barkodTara() async {
    final b = await _barkodSrv.barkodTara(context);
    if (b == null || !mounted) return;

    // 1. Önce DB'de ara — pasif (deaktif edilmiş) ürünler dahil: aksi
    // halde geçici olarak pasifleştirilmiş bir ürünün barkodu okutulunca
    // "bulunamadı" sanılıp AI'ya soruluyor, kullanıcı formu doldurup
    // kaydetmeye çalışınca da barkod UNIQUE kısıtına takılıp kafa
    // karıştırıcı bir hata alıyordu.
    final mevcutUrun = await _depo.barkodlaGetirPasifDahil(b);
    if (mevcutUrun != null) {
      _doldur(mevcutUrun);
      if (!mounted) return;
      setState(() {});
      BildirimServisi.basari(context, 'Ürün bulundu, form dolduruldu.');
      return;
    }

    // 2. Bulunamadı, AI'ya sor
    if (!mounted) return;   // barkod/DB await'leri sonrası
    final scaffold = ScaffoldMessenger.of(context);
    final snack = SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        const Expanded(child: Text('AI ile ürün bilgisi çıkarılıyor...')),
      ]),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 10),
    );
    scaffold.showSnackBar(snack);

    final bilgi = await _ai.urunBilgisiCikar(b);
    scaffold.removeCurrentSnackBar();

    if (!mounted) return;
    if (bilgi.isNotEmpty && bilgi.containsKey('urun_adi')) {
      // Formu AI verileriyle doldur
      _aiDoldurulanAlanlar.clear();
      _urunAdiGuncelle(bilgi['urun_adi'] ?? '');
      if (bilgi.containsKey('ana_grup')) _anaGrup = bilgi['ana_grup'] as String?;
      if (bilgi.containsKey('alt_grup')) _altGrup = bilgi['alt_grup'] as String?;
      if (bilgi.containsKey('kdv_orani')) _kdvOran = (bilgi['kdv_orani'] as num?)?.toString() ?? '18';
      if (bilgi.containsKey('birim_adi')) _birim = bilgi['birim_adi'] as String? ?? 'Adet';
      if (bilgi.containsKey('alan1')) _c['alan1']?.text = bilgi['alan1'] as String? ?? '';
      if (bilgi.containsKey('alan2')) _c['alan2']?.text = bilgi['alan2'] as String? ?? '';
      if (bilgi.containsKey('alis_fiyat')) _c['alisFiyat']?.text = (bilgi['alis_fiyat'] as num?)?.toString() ?? '';
      if (bilgi.containsKey('satis_fiyati')) _c['satisFiyati']?.text = (bilgi['satis_fiyati'] as num?)?.toString() ?? '';
      // 🔴 DÜZELTME (Madde 21, 2026-09-16): satisFiyati zaten KDV dahil
      // saklanıyor — AI'nin 'kdv_dahil_satis: true' dediği, zaten doğru
      // formattaki fiyattan KDV çıkarıp yanlışlıkla düşüren blok
      // kaldırıldı (bkz. yukarıdaki _faturadanUrunOku'daki aynı düzeltme).
      _c['barkod']!.text = b;
      if (_c['kod']!.text.isEmpty) _c['kod']!.text = b;
      setState(() {});
      BildirimServisi.basari(context, 'AI ürün bilgilerini doldurdu, kontrol edin.');
    } else {
      // AI cevap vermezse sadece barkodu doldur
      _c['barkod']!.text = b;
      if (_c['kod']!.text.isEmpty) _c['kod']!.text = b;
      setState(() {});
      BildirimServisi.uyari(context, 'Ürün bulunamadı, barkod manuel girildi.');
    }
  }

  // ---- FATURADAN ÜRÜN EKLE (AI DESTEKLİ) ----
  Future<void> _faturadanUrunEkle() async {
    // 🔴 DÜZELTME (kullanıcı bulgusu — "fatura fotoğrafından textlere
    // düzgün işlemiyor"): 'xlsx'/'xls' ÖNCEDEN burada seçilebilir
    // sunuluyordu ama AiVisionServisi bunları hiçbir zaman
    // İŞLEYEMİYORDU (OCR/Gemini görsel hattı sadece raster görsel VEYA
    // artık PDF anlıyor — bir Excel dosyasının ham byte'ları görsel
    // olarak yorumlanamaz). Kullanıcı bir Excel seçip sessizce "ürün
    // çıkarılamadı" hatası alıyordu — desteklenmeyen bir format
    // seçtirilebiliyor olması yanıltıcıydı. PDF artık gerçekten
    // destekleniyor (bkz. AiVisionServisi._pdfIlkSayfayiResmeCevir).
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final dosya = result.files.first;
    final scaffold = ScaffoldMessenger.of(context);
    final snack = SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        const Expanded(child: Text('Fatura işleniyor (OCR/AI)...')),
      ]),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 15),
    );
    scaffold.showSnackBar(snack);

    final urunler = await _ai.faturaUrunleriCikar(dosya);
    scaffold.removeCurrentSnackBar();

    if (!mounted) return;
    if (urunler.isEmpty) {
      BildirimServisi.uyari(context, 'Ürün bulunamadı veya fatura okunamadı.');
      return;
    }

    final secilenler = await _faturaUrunSecDialog(urunler);
    if (secilenler.isEmpty) return;

    final ilk = secilenler.first;
    final urunAdi = ilk['urun_adi']?.toString() ?? '';

    // AI ile kategori ve marka önerisi al
    Map<String, String> kategoriOnerisi = {};
    if (urunAdi.isNotEmpty) {
      kategoriOnerisi = await _ai.urunKategoriOner(urunAdi);
    }

    _aiDoldurulanAlanlar.clear();
    _urunAdiGuncelle(urunAdi);

    if (ilk.containsKey('ana_grup') && ilk['ana_grup'].toString().isNotEmpty) {
      _anaGrup = ilk['ana_grup'] as String?;
    } else if (kategoriOnerisi.containsKey('ana_grup')) {
      _anaGrup = kategoriOnerisi['ana_grup'];
    }

    if (ilk.containsKey('alt_grup')) _altGrup = ilk['alt_grup'] as String?;
    if (ilk.containsKey('kdv_orani')) _kdvOran = (ilk['kdv_orani'] as num?)?.toString() ?? '18';
    if (ilk.containsKey('birim_adi')) _birim = ilk['birim_adi'] as String? ?? 'Adet';

    if (ilk.containsKey('alan1') && ilk['alan1'].toString().isNotEmpty) {
      _c['alan1']?.text = ilk['alan1'] as String? ?? '';
    } else if (kategoriOnerisi.containsKey('alan1')) {
      _c['alan1']?.text = kategoriOnerisi['alan1'] ?? '';
    }

    if (ilk.containsKey('alan2')) _c['alan2']?.text = ilk['alan2'] as String? ?? '';
    if (ilk.containsKey('alis_fiyat')) {
      _c['alisFiyat']?.text = (ilk['alis_fiyat'] as num?)?.toString() ?? '';
    }
    if (ilk.containsKey('satis_fiyati')) {
      _c['satisFiyati']?.text = (ilk['satis_fiyati'] as num?)?.toString() ?? '';
    }
    if (ilk.containsKey('kod')) {
      _c['barkod']!.text = ilk['kod'] as String? ?? '';
    }
    if (_c['kod']!.text.isEmpty) _c['kod']!.text = _c['barkod']?.text ?? '';

    // 🔴 DÜZELTME (Madde 21, 2026-09-16): satisFiyati zaten KDV dahil
    // saklanıyor — AI'nin 'kdv_dahil_satis: true' dediği, zaten doğru
    // formattaki fiyattan KDV çıkarıp yanlışlıkla düşüren blok kaldırıldı.

    if (!mounted) return;   // AI await'leri sonrası
    setState(() {});
    BildirimServisi.basari(context, 'İlk ürün forma yüklendi. Diğer ürünler için "Yeni Ürün" ile devam edin.');
  }

}
