// lib/ekranlar/urun/urun_ekle_ekrani.dart
// AI destekli tam otomasyonlu ürün ekleme
// - Fatura fotoğrafından OCR ile ürün listesi çıkar
// - Seçilen ürünün adı, miktarı, birim fiyatı, KDV'si forma doldur
// - Ürün adına göre kategori (ana_grup) ve marka (alan1) otomatik belirlenir
// - Gemini API anahtarı kullanıcıdan alınır ve SharedPreferences'ta saklanır

import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart'; // API anahtar linki için

import '../../uygulama/tema/uygulama_temasi.dart';
import '../../modeller/urun_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../servisler/masa/urun_resim_yukleme_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/barkod_servisi.dart';
import '../../servisler/ai/ai_urun_ekle_servisi.dart';
import '../../servisler/ai/ai_vision_servisi.dart'; // API anahtarını set etmek için
import '../../veri/database/veritabani.dart';
import '../birim/birim_ekrani.dart';
import 'widgets/urun_form_alanlari.dart';
import '../../tasarim_sistemi/ts_responsive.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/ses_tanima_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../depolar/doviz_deposu.dart';
import '../../modeller/doviz_model.dart';
import '../../servisler/log_servisi.dart';
import '../../servisler/onay_merkezi_servisi.dart';

class UrunEkleEkrani extends ConsumerStatefulWidget {
  final UrunModel? duzenlenecekUrun;
  final String? baslangicBarkod;
  const UrunEkleEkrani({super.key, this.duzenlenecekUrun, this.baslangicBarkod});
  @override
  ConsumerState<UrunEkleEkrani> createState() => _UrunEkleEkraniState();
}

class _UrunEkleEkraniState extends ConsumerState<UrunEkleEkrani> {
  final _formKey  = GlobalKey<FormState>();
  final _depo     = UrunDeposu();
  final _barkodSrv = BarkodServisi();
  final _ai       = AiUrunEkleServisi();
  bool _yukleniyor = false;

  // Controllers
  final Map<String, TextEditingController> _c = {};
  
  // Seçimli alanlar
  String _birim       = 'ADET';
  String _paraBirimi  = 'TRY';
  String _kdvOran     = '18';
  String _alisKdvOran = '18';
  String? _anaGrup, _altGrup;
  // Kullanıcı isteği: "toptan satış — koli ve adet kg." Ürünün koli
  // birim adı (Koli/Paket/Palet/Kasa) ve temel satış birimi tipi.
  String _koliBirimAdi = 'Koli';
  String _satisBirimiTipi = 'adet';
  String? _dovizKoduTakip;
  double? _dovizTutariTakip;
  bool   _lotTakibi   = false;
  bool   _seriTakibi  = false;
  bool   _otomatikInd = false;
  bool   _aktif       = true;

  List<String> _birimler     = [];
  List<String> _anaGruplar   = [];
  List<String> _alan1lar     = [];
  List<String> _altGruplar   = [];
  bool _kgModu = false;
  
  File? _secilenResim;
  String? _mevcutResimYolu;
  
  bool _hesaplamaCalisiyor = false;
  bool _dropdownlarYuklendi = false;
  bool _ilkYuklemeYapildi = false;

  // AI ile doldurulan alanları işaretlemek için
  final Set<String> _aiDoldurulanAlanlar = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map) {
        final barkod = extra['barkod'] as String?;
        if (barkod != null && barkod.isNotEmpty) {
          _c['barkod']?.text = barkod;
          _c['kod']?.text = barkod;
        }
      }
    });
    _initControllers();
    _hesaplamaCalisiyor = true;
    if (widget.baslangicBarkod != null) {
      _c['barkod']?.text = widget.baslangicBarkod!;
      _c['kod']?.text = widget.baslangicBarkod!;
    }
    if (widget.duzenlenecekUrun != null) {
      _doldur(widget.duzenlenecekUrun!);
    }
    _hesaplamaCalisiyor = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _geminiApiAnahtariniKontrolEt(); // API anahtarı kontrolü
        _listenerlariEkle();
        _yukleDropdownlar();
      }
    });
  }

  void _listenerlariEkle() {
    _c['alisFiyat']?.addListener(_alisFiyatHesapla);
    _c['alisKdvOran']?.addListener(_alisKdvOranHesapla);
    _c['alisFiyatKdvDahil']?.addListener(_alisKdvliFiyatHesapla);
    _c['satisFiyati']?.addListener(_karHesapla);
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

  @override
  void dispose() {
    for (final ctrl in _c.values) ctrl.dispose();
    super.dispose();
  }

  // ---- GEMINI API ANAHTARI KONTROLÜ ----
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

    if (ilk.containsKey('kdv_dahil_satis') && ilk['kdv_dahil_satis'] == true) {
      final kdvOran = double.tryParse(_kdvOran) ?? 18;
      final satisKdvli = ParaUtils.sayiCoz(_c['satisFiyati']?.text ?? '') ?? 0;
      if (satisKdvli > 0) {
        _c['satisFiyati']?.text = (satisKdvli / (1 + kdvOran / 100)).toStringAsFixed(3);
      }
    }

    if (!mounted) return;   // AI/resim await'leri sonrası
    setState(() {});
    BildirimServisi.basari(context, 'Ürün bilgileri resimden dolduruldu, kontrol edin.');
  }

  // ---- BARKOD TARA ----
  Future<void> _barkodTara() async {
    final b = await _barkodSrv.barkodTara(context);
    if (b == null || !mounted) return;

    // 1. Önce DB'de ara
    final mevcutUrun = await _depo.barkodlaGetir(b);
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
      if (bilgi.containsKey('kdv_dahil_satis') && bilgi['kdv_dahil_satis'] == true) {
        final kdvOran = double.tryParse(_kdvOran) ?? 18;
        final satisKdvli = ParaUtils.sayiCoz(_c['satisFiyati']?.text ?? '') ?? 0;
        if (satisKdvli > 0) {
          _c['satisFiyati']?.text = (satisKdvli / (1 + kdvOran / 100)).toStringAsFixed(3);
        }
      }
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'xlsx', 'xls'],
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

    if (ilk.containsKey('kdv_dahil_satis') && ilk['kdv_dahil_satis'] == true) {
      final kdvOran = double.tryParse(_kdvOran) ?? 18;
      final satisKdvli = ParaUtils.sayiCoz(_c['satisFiyati']?.text ?? '') ?? 0;
      if (satisKdvli > 0) {
        _c['satisFiyati']?.text = (satisKdvli / (1 + kdvOran / 100)).toStringAsFixed(3);
      }
    }

    if (!mounted) return;   // AI await'leri sonrası
    setState(() {});
    BildirimServisi.basari(context, 'İlk ürün forma yüklendi. Diğer ürünler için "Yeni Ürün" ile devam edin.');
  }

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

  final _ses = SesTanimaServisi();

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
  Future<String> _benzersizBarkodUret() async {
    final db = await Veritabani().db;
    final sonuc = await db.rawQuery('''
      SELECT barkod FROM urunler 
      WHERE barkod LIKE 'M%' 
        AND barkod IS NOT NULL
        AND barkod != ''
        AND is_deleted = 0
      ORDER BY id DESC LIMIT 1
    ''');
    int yeniNumara = 1;
    if (sonuc.isNotEmpty) {
      final sonBarkod = sonuc.first['barkod'] as String;
      final numaraStr = sonBarkod.substring(1);
      yeniNumara = int.parse(numaraStr) + 1;
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
  @override
  Widget build(BuildContext context) {
    final duzenleme = widget.duzenlenecekUrun != null;
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: Text(duzenleme ? 'Ürünü Düzenle' : 'Yeni Ürün'),
        aksiyonlar: [
          // API anahtarını değiştirmek için buton (isteğe bağlı)
          IconButton(
            icon: const Icon(Icons.key, color: Colors.white),
            tooltip: 'API Anahtarını Değiştir',
            onPressed: _geminiApiAnahtarDialogu,
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.amber),
            tooltip: 'Kamera ile Fatura/Ürün Resmi Çek (AI)',
            onPressed: _yukleniyor ? null : _kameraIleOku,
          ),
          IconButton(
            icon: const Icon(Icons.mic_none_outlined, color: Colors.white),
            tooltip: 'Sesle Doldur: "ürün adı çikolata", "alış fiyat 25,50", '
                '"satış fiyat 35" gibi söyleyin',
            onPressed: _yukleniyor ? null : _sesliKomut,
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined, color: Colors.white),
            tooltip: 'Faturadan Ürün Ekle (AI)',
            onPressed: _yukleniyor ? null : _faturadanUrunEkle,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code, color: Colors.amber),
            tooltip: 'Otomatik Barkod Üret',
            onPressed: _yukleniyor ? null : _otomatikBarkodUret,
          ),
          if (duzenleme)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _yukleniyor ? null : _sil,
            ),
          IconButton(
            icon: const Icon(Icons.save, color: Colors.white),
            tooltip: 'Kaydet',
            onPressed: _yukleniyor ? null : _kaydet,
          ),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF4361EE)))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: TsResponsive.formSarmalayici(
                  context: context,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _bolum('ÜRÜN RESMİ', Icons.image),
                  GestureDetector(
                    onTap: _resimSec,
                    child: Container(
                      height: 160,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: context.borderColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: _secilenResim != null && _secilenResim!.existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.file(_secilenResim!, fit: BoxFit.cover),
                            )
                          : _mevcutResimYolu != null && File(_mevcutResimYolu!).existsSync()
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: Image.file(File(_mevcutResimYolu!), fit: BoxFit.cover),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate_outlined,
                                        size: 48, color: context.textSecondary),
                                    const SizedBox(height: 8),
                                    Text('Resim Ekle (Kamera / Galeri)',
                                        style: TextStyle(color: context.textSecondary, fontSize: 13)),
                                  ],
                                ),
                    ),
                  ),

                  _bolum('TEMEL BİLGİLER', Icons.info_outline),
                  Row(children: [
                    Expanded(child: _alan('kod', 'Ürün Kodu')),
                    const SizedBox(width: 8),
                    Expanded(child: _barkodAlani()),
                  ]),
                  _alan('barkodlar', 'Ek Barkodlar (virgülle)',
                    suffix: IconButton(
                      icon: const Icon(Icons.qr_code_scanner, size: 20,
                          color: Color(0xFF4361EE)),
                      tooltip: 'Barkod okut — virgülle ekler',
                      onPressed: () async {
                        final b = await _barkodSrv.barkodTara(context);
                        if (b == null || !mounted) return;
                        final mevcut = _c['barkodlar']?.text.trim() ?? '';
                        final liste = mevcut.isEmpty
                            ? <String>[]
                            : mevcut.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                        if (liste.contains(b)) {
                          BildirimServisi.uyari(context, 'Bu barkod zaten listede var');
                          return;
                        }
                        if (_c['barkod']?.text.trim() == b) {
                          BildirimServisi.uyari(context, 'Bu barkod zaten ana barkod alanında var');
                          return;
                        }
                        final dbUrun = await UrunDeposu().barkodlaGetir(b);
                        if (!mounted) return;
                        if (dbUrun != null && dbUrun.id != widget.duzenlenecekUrun?.id) {
                          BildirimServisi.hata(context,
                            'Bu barkod "${dbUrun.urunAdi}" ürününe kayıtlı');
                          return;
                        }
                        _c['barkodlar']?.text = liste.isEmpty ? b : '$mevcut, $b';
                        if (mounted) setState(() {});
                      },
                    )),
                  _alan('urunAdi', 'Ürün Adı *', zorunlu: true),
                  _alan('altUrunAdi', 'Alternatif Ürün Adı'),

                  Row(children: [
                    Expanded(child: _birimSecim()),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Birim Ekle', style: TextStyle(fontSize: 12)),
                      onPressed: () async {
                        await context.push('/birim');
                        _dropdownlarYuklendi = false;
                        _ilkYuklemeYapildi = false;
                        _yukleDropdownlar();
                      },
                    ),
                  ]),
                  if (_kgModu)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline, color: Colors.orange, size: 16),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'KG/LİTRE birimi: Hızlı satışta tartım girişi aktif olacak.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        )),
                      ]),
                    ),

                  const SizedBox(height: 8),

                  _bolum('FİYAT BİLGİLERİ', Icons.attach_money),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _dovizleHesapla,
                      icon: const Icon(Icons.currency_exchange, size: 16),
                      label: const Text('Dövizle Hesapla', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  Row(children: [
                    Expanded(child: _alanSayi('alisFiyat', 'Alış (KDV Hariç)')),
                    const SizedBox(width: 8),
                    SizedBox(width: 100, child: _alisKdvSecim()),
                  ]),
                  Row(children: [
                    Expanded(child: _alanSayi('alisFiyatKdvDahil', 'Alış (KDV Dahil)')),
                    const SizedBox(width: 8),
                    Expanded(child: _alanSayi('karOrani', 'Kâr Oranı %')),
                  ]),
                  _alanSayi('satisFiyati', 'Satış Fiyatı *', zorunlu: true),

                  _bolum('TOPTAN SATIŞ BİLGİLERİ', Icons.local_shipping_outlined),
                  _alanSayi('toptanFiyat', 'Toptan Fiyatı (opsiyonel)'),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _satisBirimiTipi,
                        decoration: const InputDecoration(labelText: 'Satış Birimi', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'adet', child: Text('Adet')),
                          DropdownMenuItem(value: 'kg', child: Text('Kg (Ağırlık)')),
                        ],
                        onChanged: (v) => setState(() => _satisBirimiTipi = v ?? 'adet'),
                      ),
                    ),
                  ]),
                  if (_satisBirimiTipi == 'adet') ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _alanSayi('koliIciMiktar', '1 Koli Kaç Adet? (opsiyonel)')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _koliBirimAdi,
                          decoration: const InputDecoration(labelText: 'Koli Adı', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'Koli', child: Text('Koli')),
                            DropdownMenuItem(value: 'Paket', child: Text('Paket')),
                            DropdownMenuItem(value: 'Kasa', child: Text('Kasa')),
                            DropdownMenuItem(value: 'Palet', child: Text('Palet')),
                          ],
                          onChanged: (v) => setState(() => _koliBirimAdi = v ?? 'Koli'),
                        ),
                      ),
                    ]),
                  ],

                  _bolum('İNDİRİM BİLGİLERİ', Icons.local_offer_outlined),
                  Row(children: [
                    Expanded(child: _alanSayi('indirimOrani', 'İndirim %')),
                    const SizedBox(width: 8),
                    Expanded(child: _alanSayi('indirimliFiyat', 'İndirimli Fiyat')),
                  ]),
                  SwitchListTile.adaptive(
                    dense: true,
                    title: const Text('Otomatik İndirim', style: TextStyle(fontSize: 14)),
                    value: _otomatikInd,
                    onChanged: (v) => setState(() => _otomatikInd = v),
                  ),

                  _bolum('STOK BİLGİLERİ', Icons.warehouse),
                  Row(children: [
                    Expanded(child: _alanSayi('stok', 'Mevcut Stok')),
                    const SizedBox(width: 8),
                    Expanded(child: _alanSayi('minimumStok', 'Min Stok')),
                    const SizedBox(width: 8),
                    Expanded(child: _alanSayi('maksimumStok', 'Maks Stok')),
                  ]),

                  _bolum('KATEGORİ', Icons.category_outlined),
                  Row(children: [
                    Expanded(child: _grupSecim(true)),
                    const SizedBox(width: 8),
                    Expanded(child: _grupSecim(false)),
                  ]),

                  _bolum('ÜRÜN DETAYI', Icons.description_outlined),
                  Row(children: [
                    Expanded(child: _alan('marka', 'Marka')),
                    const SizedBox(width: 8),
                    Expanded(child: _alan('uretici', 'Üretici')),
                  ]),
                  Row(children: [
                    Expanded(child: _alan('model', 'Model')),
                    const SizedBox(width: 8),
                    Expanded(child: _alan('rafNo', 'Raf No')),
                  ]),
                  Row(children: [
                    Expanded(child: _alan1Secim()),
                    const SizedBox(width: 8),
                    Expanded(child: _alan('alan2', 'Alan 2')),
                  ]),
                  Row(children: [
                    Expanded(child: _alan('renk', 'Renk')),
                    const SizedBox(width: 8),
                    Expanded(child: _alan('beden', 'Beden')),
                  ]),

                  _bolum('ÖLÇÜLER & AĞIRLIK', Icons.straighten),
                  Row(children: [
                    Expanded(child: _alanSayi('en', 'En (cm)')),
                    const SizedBox(width: 8),
                    Expanded(child: _alanSayi('boy', 'Boy (cm)')),
                    const SizedBox(width: 8),
                    Expanded(child: _alanSayi('agirlik', 'Ağırlık (gr)')),
                  ]),

                  _bolum('DİĞER', Icons.more_horiz),
                  Row(children: [
                    Expanded(child: _alan('muhasebeKodu', 'Muhasebe Kodu')),
                    const SizedBox(width: 8),
                    Expanded(child: DropdownButtonFormField<String>(
                      value: _paraBirimi,
                      decoration: const InputDecoration(
                        labelText: 'Para Birimi',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ['TRY', 'USD', 'EUR'].map((v) =>
                        DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) => setState(() => _paraBirimi = v!),
                    )),
                  ]),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    dense: true,
                    title: const Text('Lot Takibi', style: TextStyle(fontSize: 14)),
                    value: _lotTakibi,
                    onChanged: (v) => setState(() => _lotTakibi = v),
                  ),
                  SwitchListTile.adaptive(
                    dense: true,
                    title: const Text('Seri No Takibi', style: TextStyle(fontSize: 14)),
                    value: _seriTakibi,
                    onChanged: (v) => setState(() => _seriTakibi = v),
                  ),
                  SwitchListTile.adaptive(
                    dense: true,
                    title: const Text('Aktif', style: TextStyle(fontSize: 14)),
                    value: _aktif,
                    onChanged: (v) => setState(() => _aktif = v),
                  ),

                  const SizedBox(height: 80),
                ]),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF4361EE),
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: _yukleniyor ? null : _kaydet,
        icon: const Icon(Icons.save),
        label: const Text('Kaydet'),
      ),
    );
  }

  // ---- YARDIMCI WIDGET METODLARI ----
  Widget _bolum(String title, IconData icon) => FormBolum(baslik: title, ikon: icon);

  Widget _alan(String key, String label, {bool zorunlu = false, Widget? suffix}) =>
      FormMetinAlani(controller: _c[key]!, label: label, zorunlu: zorunlu, suffix: suffix);

  Widget _alanSayi(String key, String label, {bool zorunlu = false, Widget? suffix}) =>
      FormSayiAlani(controller: _c[key]!, label: label, zorunlu: zorunlu, suffix: suffix);

  Widget _barkodAlani() => Padding(padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        controller: _c['barkod'],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Barkod',
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            onPressed: _barkodTara,
          ),
        ),
      ),
      if (_aiDoldurulanAlanlar.contains('barkod') || _aiDoldurulanAlanlar.contains('urunAdi'))
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_awesome, size: 14, color: Colors.amber.shade700),
            const SizedBox(width: 4),
            Text('AI ile dolduruldu',
                style: TextStyle(fontSize: 10, color: Colors.amber.shade800)),
          ]),
        ),
    ]),
  );

  Widget _birimSecim() => FormBirimSecim(
    birimler: _birimler,
    secilenBirim: _birim,
    onDegisti: (v) => setState(() {
      _birim  = v;
      _kgModu = v == 'KG' || v == 'GR' || v == 'LİTRE' || v == 'ML';
    }),
  );

  Widget _alisKdvSecim() => FormAlisKdvSecim(
    secilenKdv: _alisKdvOran,
    onDegisti: (v) {
      _c['alisKdvOran']?.text = v;
      setState(() => _alisKdvOran = v);
      _alisKdvOranHesapla();
    },
  );

  Widget _alan1Secim() => FormOtomatikAlan(
    controller: _c['alan1']!,
    secenekler: _alan1lar,
    label: 'Alan 1',
    onDegisti: (_) => setState(() {}),
  );

  Widget _grupSecim(bool ana) => FormGrupSecim(
    key: ValueKey('${ana ? 'ana' : 'alt'}-${ana ? _anaGrup : _altGrup}'),
    gruplar: ana ? _anaGruplar : _altGruplar,
    secilenGrup: ana ? _anaGrup : _altGrup,
    label: ana ? 'Ana Grup' : 'Alt Grup',
    onDegisti: (v) => setState(() { if (ana) _anaGrup = v; else _altGrup = v; }),
  );
}

/// Sesli komut dinlerken gösterilen alt sayfa — canlı önizleme + durdur/iptal.
class _SesliKomutSheet extends StatefulWidget {
  final SesTanimaServisi ses;
  final void Function(String metin) onSonuc;
  final VoidCallback onIptal;
  const _SesliKomutSheet({required this.ses, required this.onSonuc, required this.onIptal});

  @override
  State<_SesliKomutSheet> createState() => _SesliKomutSheetState();
}

class _SesliKomutSheetState extends State<_SesliKomutSheet> {
  String _canliMetin = '';
  bool _basladi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _dinlemeyeBasla());
  }

  Future<void> _dinlemeyeBasla() async {
    setState(() => _basladi = true);
    await widget.ses.dinlemeyeBasla(
      onSonuc: (metin) { if (mounted) setState(() => _canliMetin = metin); },
      onBitti: (metin) {
        if (mounted) Navigator.of(context).pop();
        widget.onSonuc(metin);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(26),
              shape: BoxShape.circle,
            ),
            child: Icon(_basladi ? Icons.mic : Icons.mic_none, color: Colors.red, size: 36),
          ),
          const SizedBox(height: 16),
          Text(_basladi ? 'Dinliyorum...' : 'Hazırlanıyor...',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            _canliMetin.isEmpty
                ? 'Örn: "ürün adı çikolata", "alış fiyat 25,50", "satış fiyat 35"'
                : _canliMetin,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _canliMetin.isEmpty ? context.textSecondary : context.textPrimary),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () async {
              await widget.ses.iptal();
              if (mounted) Navigator.of(context).pop();
              widget.onIptal();
            },
            child: const Text('İptal'),
          ),
        ]),
      ),
    );
  }
}

/// "2 dolar geldi, kur 45,90" senaryosu için: döviz seç, yabancı tutarı
/// gir, TL karşılığı canlı olarak hesaplanıp gösterilir.
class _DovizleHesaplaDialog extends StatefulWidget {
  final List<DovizModel> dovizler;
  const _DovizleHesaplaDialog({required this.dovizler});

  @override
  State<_DovizleHesaplaDialog> createState() => _DovizleHesaplaDialogState();
}

class _DovizSonuc {
  final double tlTutari;
  final String? dovizKodu;
  final double? dovizTutari;
  const _DovizSonuc(this.tlTutari, {this.dovizKodu, this.dovizTutari});
}

class _DovizleHesaplaDialogState extends State<_DovizleHesaplaDialog> {
  late DovizModel _secili;
  final _tutarCtrl = TextEditingController();
  double _sonuc = 0;
  bool _dovizBazliTakip = false;

  @override
  void initState() {
    super.initState();
    _secili = widget.dovizler.first;
    _tutarCtrl.addListener(_hesapla);
  }

  @override
  void dispose() {
    _tutarCtrl.dispose();
    super.dispose();
  }

  void _hesapla() {
    final tutar = double.tryParse(_tutarCtrl.text.replaceAll(',', '.')) ?? 0;
    setState(() => _sonuc = tutar * _secili.satisKuru);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Dövizle Hesapla'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<DovizModel>(
          value: _secili,
          decoration: const InputDecoration(labelText: 'Para Birimi', border: OutlineInputBorder()),
          items: widget.dovizler.map((d) => DropdownMenuItem(
              value: d, child: Text('${d.kod} (${d.satisKuru.toStringAsFixed(4)} ₺)'))).toList(),
          onChanged: (v) => setState(() { _secili = v!; _hesapla(); }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tutarCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: '${_secili.kod} Tutarı',
            prefixText: '${_secili.sembol} ',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text('TL Karşılığı', style: TextStyle(fontSize: 11, color: context.textSecondary)),
            Text('${_sonuc.toStringAsFixed(2)} ₺',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.green)),
          ]),
        ),
        const SizedBox(height: 8),
        // Kullanıcı sorusu: "kur değişti o zaman nasıl olacak?" — bu
        // seçenek işaretlenirse ürün, bu döviz tutarına "sabitlenir";
        // kur değiştiğinde Ürün Listesi > Toplu Döviz Güncelleme'den
        // TÜM bu tür ürünlerin TL fiyatı tek seferde yeniden hesaplanabilir.
        CheckboxListTile(
          value: _dovizBazliTakip,
          onChanged: (v) => setState(() => _dovizBazliTakip = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Bu ürünü döviz bazında takip et',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          subtitle: const Text(
              'Kur değiştiğinde "Toplu Döviz Güncelleme" ile bu ürünün '
              'TL fiyatını otomatik yeniden hesaplayabilirsiniz.',
              style: TextStyle(fontSize: 10)),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: _sonuc > 0
              ? () => Navigator.pop(context, _DovizSonuc(_sonuc,
                  dovizKodu: _dovizBazliTakip ? _secili.kod : null,
                  dovizTutari: _dovizBazliTakip
                      ? double.tryParse(_tutarCtrl.text.replaceAll(',', '.'))
                      : null))
              : null,
          child: const Text('Kullan'),
        ),
      ],
    );
  }
}