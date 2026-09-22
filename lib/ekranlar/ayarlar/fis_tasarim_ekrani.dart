// lib/ekranlar/ayarlar/fis_tasarim_ekrani.dart
// v2.1 - Tamamen düzeltilmiş, çalışan versiyon
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:barcode/barcode.dart' as bc;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/ayarlar_deposu.dart';

class FisTasarimEkrani extends ConsumerStatefulWidget {
  /// true ise kendi Scaffold/AppBar'ını çizmez — Yazdırma Merkezi içine
  /// sekme olarak gömülür.
  final bool gomulu;
  const FisTasarimEkrani({super.key, this.gomulu = false});
  @override
  ConsumerState<FisTasarimEkrani> createState() => _FisTasarimEkraniState();
}

class _FisTasarimEkraniState extends ConsumerState<FisTasarimEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _ayarlarDepo = AyarlarDeposu();
  // 🔴 DÜZELTME (derin analizde bulundu): Bu ekranda hiçbir çift
  // tıklama koruması YOKTU — ne bir durum değişkeni ne buton devre
  // dışı bırakma. Hızlı çift tıklamada 22 ayarın hepsi iki kez (yarışan
  // sırayla) yazılabiliyordu.
  bool _kayit = false;

  int    _fisGenislik     = 80;
  double _baslikFontBoyut = 12.0;
  double _satirFontBoyut  = 8.0;
  double _toplamFontBoyut = 10.0;

  bool _firmaAdi      = true;
  bool _firmaAdres    = true;
  bool _firmaTelefon  = true;
  bool _firmaVergiNo  = true;
  bool _fisNo         = true;
  bool _tarihSaat     = true;
  bool _kasiyerAdi    = true;
  bool _urunKodu      = false;
  bool _barkod        = false;

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 CARİ HESAP ÖZETİ + MAKBUZ + FİŞ BARKODU AYARLARI
  //
  // ⚠ NOT: Yukarıdaki `_barkod` (anahtar: fis_barkod_goster) ÜRÜN
  // SATIRLARINDAKİ barkodu kastediyor. Aşağıdaki `_altBarkod` ise
  // fişin ALTINA basılan FİŞ NUMARASI barkodudur — ayrı anahtar
  // (fis_alt_barkod_goster) kullanır ki ikisi karışmasın.
  // ══════════════════════════════════════════════════════════════════════
  bool _cariAdi       = true;   // Fişte cari (müşteri) adı
  bool _cariBakiye    = true;   // Eski Bakiye / Bu Fiş / Son Bakiye üçlüsü
  bool _yaziylaTutar  = true;   // Makbuzlarda tutarı yazıyla da bas
  bool _altBarkod     = true;   // Fişin altına fiş no barkodu
  bool _kdvDetay      = true;
  bool _altToplamlar  = true;
  bool _odemeYontemi  = true;
  bool _paraUstu      = true;
  bool _tesekkur      = true;
  bool _qrKod         = false;
  bool _otomatikYazdir = false;

  final _baslikCtrl   = TextEditingController();
  final _altYaziCtrl  = TextEditingController();
  final _tesekkurCtrl = TextEditingController(text: 'Bizi tercih ettiginiz icin tesekkurler!');

  int    _kopySayisi      = 1;
  int    _beslemeKagit    = 3;

  // Firma logosu — fişin en üstüne, firma adının üzerine basılır.
  bool   _logoGoster      = false;
  String? _logoYolu;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _yukle();
  }

  @override
  void dispose() {
    _tab.dispose();
    _baslikCtrl.dispose();
    _altYaziCtrl.dispose();
    _tesekkurCtrl.dispose();
    super.dispose();
  }

  static const _ayarAnahtarlari = [
    'fis_kagit', 'fis_font_baslik', 'fis_font_satir', 'fis_font_toplam',
    'firma_adi', 'firma_adres', 'firma_telefon', 'fis_vergi_no_goster', 'fis_fis_no_goster',
    'fis_tarih_goster', 'fis_kasiyer_goster', 'fis_urun_kodu_goster', 'fis_barkod_goster',
    'fis_kdv_detay_goster', 'fis_alt_toplamlar_goster', 'fis_odeme_yontemi_goster',
    'fis_para_ustu_goster', 'fis_tesekkur_goster', 'fis_qr_kod_goster', 'fis_otomatik_yazdir',
    'fis_baslik_metin', 'fis_alt_yazi', 'fis_tesekkur_metni', 'fis_kopya_sayisi',
    'fis_besleme_kagit',
    'fis_cari_bakiye_goster', 'fis_yaziyla_tutar', 'fis_alt_barkod_goster',
    'fis_cari_goster', 'fis_logo_goster', 'fis_logo_yolu',
  ];

  Future<void> _yukle() async {
    try {
      final m = await _ayarlarDepo.coguGetir(_ayarAnahtarlari);
      if (!mounted) return;
      setState(() {
        _fisGenislik      = (m['fis_kagit'] ?? '80mm') == '58mm' ? 58 : 80;
        _baslikFontBoyut  = double.tryParse(m['fis_font_baslik'] ?? '') ?? 12.0;
        _satirFontBoyut   = double.tryParse(m['fis_font_satir'] ?? '') ?? 8.0;
        _toplamFontBoyut  = double.tryParse(m['fis_font_toplam'] ?? '') ?? 10.0;
        _firmaAdi         = true;
        _firmaAdres       = (m['firma_adres'] ?? '').isNotEmpty;
        _firmaTelefon     = (m['firma_telefon'] ?? '').isNotEmpty;
        _firmaVergiNo     = (m['fis_vergi_no_goster'] ?? '1') == '1';
        _fisNo            = (m['fis_fis_no_goster'] ?? '1') == '1';
        _tarihSaat        = (m['fis_tarih_goster'] ?? '1') == '1';
        _kasiyerAdi       = (m['fis_kasiyer_goster'] ?? '1') == '1';
        _urunKodu         = (m['fis_urun_kodu_goster'] ?? '0') == '1';
        _barkod           = (m['fis_barkod_goster'] ?? '0') == '1';
        _cariAdi          = (m['fis_cari_goster'] ?? '1') == '1';
        _cariBakiye       = (m['fis_cari_bakiye_goster'] ?? '1') == '1';
        _yaziylaTutar     = (m['fis_yaziyla_tutar'] ?? '1') == '1';
        _altBarkod        = (m['fis_alt_barkod_goster'] ?? '1') == '1';
        _kdvDetay         = (m['fis_kdv_detay_goster'] ?? '1') == '1';
        _altToplamlar     = (m['fis_alt_toplamlar_goster'] ?? '1') == '1';
        _odemeYontemi     = (m['fis_odeme_yontemi_goster'] ?? '1') == '1';
        _paraUstu         = (m['fis_para_ustu_goster'] ?? '1') == '1';
        _tesekkur         = (m['fis_tesekkur_goster'] ?? '1') == '1';
        _qrKod            = (m['fis_qr_kod_goster'] ?? '0') == '1';
        _otomatikYazdir   = (m['fis_otomatik_yazdir'] ?? '0') == '1';
        _kopySayisi       = int.tryParse(m['fis_kopya_sayisi'] ?? '') ?? 1;
        _beslemeKagit     = int.tryParse(m['fis_besleme_kagit'] ?? '') ?? 3;
        _baslikCtrl.text  = m['fis_baslik_metin'] ?? '';
        _altYaziCtrl.text = m['fis_alt_yazi'] ?? '';
        _tesekkurCtrl.text = m['fis_tesekkur_metni'] ??
            'Bizi tercih ettiğiniz için teşekkürler!';
        _logoGoster       = (m['fis_logo_goster'] ?? '0') == '1';
        _logoYolu         = (m['fis_logo_yolu'] ?? '').isEmpty ? null : m['fis_logo_yolu'];
      });
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Ayarlar yüklenemedi: $e');
    }
  }

  Future<void> _ayarKaydet(String anahtar, String deger) =>
      _ayarlarDepo.kaydet(anahtar, deger);

  Future<void> _kaydet() async {
    if (_kayit) return;
    setState(() => _kayit = true);
    try {
      // NOT: Bu ekran artik gercek yazdirma servisiyle (yazdirma_servisi.dart)
      // AYNI SQLite `ayarlar` tablosunu kullaniyor -- onceden SharedPreferences'a
      // kaydediliyordu ve gercek fis yazdirma bu ayarlari HIC okumuyordu; yani
      // burada yapilan her degisiklik sessizce hicbir ise yaramiyordu. Artik
      // her ayar gercekten uygulaniyor.
      await Future.wait([
        _ayarKaydet('fis_kagit', _fisGenislik == 58 ? '58mm' : '80mm'),
        _ayarKaydet('fis_font_baslik', _baslikFontBoyut.toString()),
        _ayarKaydet('fis_font_satir', _satirFontBoyut.toString()),
        _ayarKaydet('fis_font_toplam', _toplamFontBoyut.toString()),
        _ayarKaydet('fis_vergi_no_goster', _firmaVergiNo ? '1' : '0'),
        _ayarKaydet('fis_fis_no_goster', _fisNo ? '1' : '0'),
        _ayarKaydet('fis_tarih_goster', _tarihSaat ? '1' : '0'),
        _ayarKaydet('fis_kasiyer_goster', _kasiyerAdi ? '1' : '0'),
        _ayarKaydet('fis_urun_kodu_goster', _urunKodu ? '1' : '0'),
        _ayarKaydet('fis_barkod_goster', _barkod ? '1' : '0'),
        _ayarKaydet('fis_cari_goster', _cariAdi ? '1' : '0'),
        _ayarKaydet('fis_cari_bakiye_goster', _cariBakiye ? '1' : '0'),
        _ayarKaydet('fis_yaziyla_tutar', _yaziylaTutar ? '1' : '0'),
        _ayarKaydet('fis_alt_barkod_goster', _altBarkod ? '1' : '0'),
        _ayarKaydet('fis_kdv_detay_goster', _kdvDetay ? '1' : '0'),
        _ayarKaydet('fis_alt_toplamlar_goster', _altToplamlar ? '1' : '0'),
        _ayarKaydet('fis_odeme_yontemi_goster', _odemeYontemi ? '1' : '0'),
        _ayarKaydet('fis_para_ustu_goster', _paraUstu ? '1' : '0'),
        _ayarKaydet('fis_tesekkur_goster', _tesekkur ? '1' : '0'),
        _ayarKaydet('fis_qr_kod_goster', _qrKod ? '1' : '0'),
        _ayarKaydet('fis_otomatik_yazdir', _otomatikYazdir ? '1' : '0'),
        _ayarKaydet('fis_kopya_sayisi', _kopySayisi.toString()),
        _ayarKaydet('fis_besleme_kagit', _beslemeKagit.toString()),
        _ayarKaydet('fis_baslik_metin', _baslikCtrl.text),
        _ayarKaydet('fis_alt_yazi', _altYaziCtrl.text),
        _ayarKaydet('fis_tesekkur_metni', _tesekkurCtrl.text),
        _ayarKaydet('fis_logo_goster', _logoGoster ? '1' : '0'),
        _ayarKaydet('fis_logo_yolu', _logoYolu ?? ''),
      ]);
      if (mounted) BildirimServisi.basari(context, 'Fiş tasarımı kaydedildi ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }


  // ── Logo seç/kaldır ──────────────────────────────────────────────────────
  Future<void> _logoSec() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 90);
    if (xFile == null) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/fis_gorseller');
      if (!await dir.exists()) await dir.create(recursive: true);
      final hedef = File('${dir.path}/logo.png');
      await File(xFile.path).copy(hedef.path);
      if (!mounted) return;
      setState(() { _logoYolu = hedef.path; _logoGoster = true; });
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Logo kaydedilemedi: $e');
    }
  }

  void _logoKaldir() => setState(() { _logoYolu = null; _logoGoster = false; });

  // PDF Olusturucu
  Future<pw.Document> _fisPdfOlustur() async {
    final pdf = pw.Document();
    final genislik = _fisGenislik == 58
        ? PdfPageFormat(58 * PdfPageFormat.mm, 297 * PdfPageFormat.mm)
        : PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm);
    pw.MemoryImage? logoResim;
    if (_logoGoster && _logoYolu != null && await File(_logoYolu!).exists()) {
      try { logoResim = pw.MemoryImage(await File(_logoYolu!).readAsBytes()); } catch (_) {}
    }

    pdf.addPage(pw.Page(
      pageFormat: genislik,
      margin: const pw.EdgeInsets.all(4),
      build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (logoResim != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Image(logoResim, height: 40, fit: pw.BoxFit.contain),
          ),
        if (_baslikCtrl.text.isNotEmpty)
          pw.Text(_baslikCtrl.text, style: pw.TextStyle(fontSize: _baslikFontBoyut, fontWeight: pw.FontWeight.bold)),
        if (_firmaAdi) pw.Text('ORNEK MARKET', style: pw.TextStyle(fontSize: _baslikFontBoyut, fontWeight: pw.FontWeight.bold)),
        if (_firmaAdres) pw.Text('Ataturk Cad. No:1', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        if (_firmaTelefon) pw.Text('Tel: 0212 555 44 33', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        if (_firmaVergiNo) pw.Text('VKN: 1234567890', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        pw.Divider(),
        if (_fisNo) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Fis No:', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          pw.Text('MKP-000001', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        ]),
        if (_tarihSaat) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Tarih:', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          pw.Text('02.06.2026 18:30', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        ]),
        if (_kasiyerAdi) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Kasiyer:', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          pw.Text('Admin', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        ]),
        pw.Divider(),
        pw.Row(children: [
          pw.Expanded(flex: 4, child: pw.Text('Urun', style: pw.TextStyle(fontSize: _satirFontBoyut, fontWeight: pw.FontWeight.bold))),
          pw.Text('Adet', style: pw.TextStyle(fontSize: _satirFontBoyut, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 4),
          pw.Text('Tutar', style: pw.TextStyle(fontSize: _satirFontBoyut, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.Row(children: [pw.Expanded(flex: 4, child: pw.Text('Ekmek', style: pw.TextStyle(fontSize: _satirFontBoyut))), pw.Text('2', style: pw.TextStyle(fontSize: _satirFontBoyut)), pw.SizedBox(width: 4), pw.Text('10,00 TL', style: pw.TextStyle(fontSize: _satirFontBoyut))]),
        pw.Row(children: [pw.Expanded(flex: 4, child: pw.Text('Sut 1L', style: pw.TextStyle(fontSize: _satirFontBoyut))), pw.Text('1', style: pw.TextStyle(fontSize: _satirFontBoyut)), pw.SizedBox(width: 4), pw.Text('28,50 TL', style: pw.TextStyle(fontSize: _satirFontBoyut))]),
        pw.Row(children: [pw.Expanded(flex: 4, child: pw.Text('Yogurt', style: pw.TextStyle(fontSize: _satirFontBoyut))), pw.Text('3', style: pw.TextStyle(fontSize: _satirFontBoyut)), pw.SizedBox(width: 4), pw.Text('54,00 TL', style: pw.TextStyle(fontSize: _satirFontBoyut))]),
        pw.Divider(),
        if (_altToplamlar) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Ara Toplam:', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          pw.Text('92,50 TL', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        ]),
        if (_kdvDetay) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('KDV (%20):', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          pw.Text('15,42 TL', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        ]),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('TOPLAM:', style: pw.TextStyle(fontSize: _toplamFontBoyut, fontWeight: pw.FontWeight.bold)),
          pw.Text('92,50 TL', style: pw.TextStyle(fontSize: _toplamFontBoyut, fontWeight: pw.FontWeight.bold)),
        ]),
        if (_odemeYontemi) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Nakit:', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          pw.Text('100,00 TL', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        ]),
        if (_paraUstu) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Para Ustu:', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          pw.Text('7,50 TL', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        ]),
        pw.Divider(),

        // ══════════════════════════════════════════════════════════════
        // 🆕 CARİ ADI + HESAP ÖZETİ + FİŞ BARKODU (ÖNİZLEME)
        //
        // Bu ekranın önizlemesi fişin DÖRDÜNCÜ çizim yolu — gerçek
        // fişten tamamen ayrı, örnek verilerle çizilen bir PDF.
        // Eklenen üç özellik burada YOKTU, kullanıcı ayarı açsa bile
        // önizlemede etkisini göremiyordu.
        // ══════════════════════════════════════════════════════════════
        if (_cariAdi) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Cari:', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          pw.Text('ORNEK MUSTERI', style: pw.TextStyle(fontSize: _satirFontBoyut)),
        ]),

        if (_cariBakiye) ...[
          pw.SizedBox(height: 2),
          pw.Text('CARI HESAP OZETI',
              style: pw.TextStyle(fontSize: _satirFontBoyut, fontWeight: pw.FontWeight.bold)),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Eski Bakiye', style: pw.TextStyle(fontSize: _satirFontBoyut)),
            pw.Text('1.250,00 B', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          ]),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('(+) Bu Fis', style: pw.TextStyle(fontSize: _satirFontBoyut)),
            pw.Text('92,50', style: pw.TextStyle(fontSize: _satirFontBoyut)),
          ]),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('SON BAKIYE',
                style: pw.TextStyle(fontSize: _satirFontBoyut, fontWeight: pw.FontWeight.bold)),
            pw.Text('1.342,50 B',
                style: pw.TextStyle(fontSize: _satirFontBoyut, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.Divider(),
        ],

        if (_tesekkur) pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(_tesekkurCtrl.text, style: pw.TextStyle(fontSize: _satirFontBoyut), textAlign: pw.TextAlign.center)),
        if (_altYaziCtrl.text.isNotEmpty)
          pw.Text(_altYaziCtrl.text, style: pw.TextStyle(fontSize: _satirFontBoyut), textAlign: pw.TextAlign.center),

        if (_altBarkod) ...[
          pw.SizedBox(height: 6),
          pw.BarcodeWidget(
            barcode: bc.Barcode.code128(),
            data: 'MKP2026000000001',
            width: _fisGenislik == 58 ? 110 : 150,
            height: 34,
            drawText: false,
          ),
          pw.SizedBox(height: 2),
          pw.Text('MKP2026000000001',
              style: pw.TextStyle(fontSize: _satirFontBoyut - 1),
              textAlign: pw.TextAlign.center),
        ],
      ]),
    ));
    return pdf;
  }

  Widget _govde() => TabBarView(controller: _tab, children: [
        _icerikTab(),
        _tasarimTab(),
        _onizlemeTab(),
      ]);

  PreferredSizeWidget _icSekmeBari({required bool beyaz}) => TabBar(
        controller: _tab,
        labelColor: beyaz ? Colors.white : const Color(0xFF4361EE),
        unselectedLabelColor: beyaz ? Colors.white60 : context.textSecondary,
        indicatorColor: beyaz ? Colors.white : const Color(0xFF4361EE),
        tabs: const [
          Tab(text: 'İçerik'),
          Tab(text: 'Tasarım'),
          Tab(text: 'Önizleme'),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (widget.gomulu) {
      return Column(
        children: [
          Material(
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                Expanded(child: _icSekmeBari(beyaz: false)),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'PDF Önizle',
                  onPressed: () => _tab.animateTo(2),
                ),
                IconButton(
                  icon: const Icon(Icons.save_outlined),
                  tooltip: 'Kaydet',
                  onPressed: _kayit ? null : _kaydet,
                ),
              ],
            ),
          ),
          Expanded(child: _govde()),
        ],
      );
    }

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Fiş Tasarımı',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
            tooltip: 'PDF Önizle',
            onPressed: () => _tab.animateTo(2),
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Colors.white),
            tooltip: 'Kaydet',
            onPressed: _kayit ? null : _kaydet,
          ),
        ],
        alt: _icSekmeBari(beyaz: true),
      ),
      body: _govde(),
    );
  }

  // TAB 1: Icerik
  Widget _icerikTab() => ListView(padding: const EdgeInsets.all(16), children: [
    _bolumBaslik('Firma Bilgileri'),
    _switchKart([
      _SwitchItem('Firma Adi', _firmaAdi, (v) => setState(() => _firmaAdi = v), Icons.store_outlined),
      _SwitchItem('Firma Adresi', _firmaAdres, (v) => setState(() => _firmaAdres = v), Icons.location_on_outlined),
      _SwitchItem('Telefon', _firmaTelefon, (v) => setState(() => _firmaTelefon = v), Icons.phone_outlined),
      _SwitchItem('Vergi No/Daire', _firmaVergiNo, (v) => setState(() => _firmaVergiNo = v), Icons.numbers_outlined),
    ]),
    _bolumBaslik('Fis Bilgileri'),
    _switchKart([
      _SwitchItem('Fis No', _fisNo, (v) => setState(() => _fisNo = v), Icons.tag),
      _SwitchItem('Tarih/Saat', _tarihSaat, (v) => setState(() => _tarihSaat = v), Icons.access_time),
      _SwitchItem('Kasiyer Adi', _kasiyerAdi, (v) => setState(() => _kasiyerAdi = v), Icons.person_outline),
      _SwitchItem('Urun Kodu', _urunKodu, (v) => setState(() => _urunKodu = v), Icons.qr_code_outlined),
      _SwitchItem('Barkod', _barkod, (v) => setState(() => _barkod = v), Icons.linear_scale),
    ]),
    _bolumBaslik('Toplam Bolumu'),
    _switchKart([
      _SwitchItem('KDV Detayi', _kdvDetay, (v) => setState(() => _kdvDetay = v), Icons.percent),
      _SwitchItem('Ara Toplamlar', _altToplamlar, (v) => setState(() => _altToplamlar = v), Icons.calculate_outlined),
      _SwitchItem('Odeme Yontemi', _odemeYontemi, (v) => setState(() => _odemeYontemi = v), Icons.payment_outlined),
      _SwitchItem('Para Ustu', _paraUstu, (v) => setState(() => _paraUstu = v), Icons.money_outlined),
      _SwitchItem('QR Kod', _qrKod, (v) => setState(() => _qrKod = v), Icons.qr_code_2),
    ]),
    _bolumBaslik('Cari Hesap ve Makbuz'),
    _switchKart([
      _SwitchItem('Cari (Musteri) Adi', _cariAdi,
          (v) => setState(() => _cariAdi = v), Icons.person_outline_rounded),
      _SwitchItem('Cari Bakiye Ozeti', _cariBakiye,
          (v) => setState(() => _cariBakiye = v), Icons.account_balance_wallet_outlined),
      _SwitchItem('Tutari Yaziyla Yaz', _yaziylaTutar,
          (v) => setState(() => _yaziylaTutar = v), Icons.text_fields_rounded),
    ]),
    _bilgiNotu(
      'Cari (Musteri) Adi: Cari secilerek yapilan satislarda musterinin '
      'unvani fise basilir. Perakende satislarda zaten bos oldugu icin '
      'gorunmez.\n\n'
      'Cari Bakiye Ozeti: Cariye yapilan satis, tahsilat ve tedarikci '
      'odemelerinde fise "Eski Bakiye / Bu Islem / Son Bakiye" ucluau '
      'basilir. Bakiye yaninda B (Borc) veya A (Alacak) etiketi cikar.\n\n'
      'Tutari Yaziyla: Tahsilat ve tediye makbuzlarinda tutar rakamin '
      'yaninda yaziyla da basilir. Turkiye\'de makbuzlarda tahrifata '
      'karsi standart uygulamadir.'),

    _bolumBaslik('Fis Barkodu'),
    _switchKart([
      _SwitchItem('Fis Altina Barkod Bas', _altBarkod,
          (v) => setState(() => _altBarkod = v), Icons.qr_code_scanner_rounded),
    ]),
    _bilgiNotu(
      'Fisin altina fis numarasi Code128 barkod olarak basilir. '
      'Bu barkodu Hizli Satis ekraninda okuttugunuzda o satis geri '
      'cagrilir ve uzerine urun ekleyebilirsiniz.\n\n'
      'DIKKAT: Fise ekleme yapildiginda musterideki basili fis ile '
      'sistemdeki kayit farklilasir. Islem oncesi uyari gosterilir.'),

    _bolumBaslik('Ozel Metinler'),
    _textField('Fis Basligi', _baslikCtrl, hint: 'HOS GELDINIZ'),
    _textField('Alt Yazi', _altYaziCtrl, hint: 'Afiyet olsun!', maxLines: 2),
    _switchKart([
      _SwitchItem('Tesekkur Mesaji', _tesekkur, (v) => setState(() => _tesekkur = v), Icons.favorite_outline),
    ]),
    if (_tesekkur) _textField('Tesekkur Metni', _tesekkurCtrl, maxLines: 2),
    const SizedBox(height: 80),
  ]);

  // TAB 2: Tasarim
  Widget _tasarimTab() => ListView(padding: const EdgeInsets.all(16), children: [
    _bolumBaslik('Firma Logosu'),
    _logoAlani(),
    const SizedBox(height: 16),
    _bolumBaslik('Kagit Genisligi'),
    Row(children: [58, 80].map((g) => Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => setState(() => _fisGenislik = g),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
              color: _fisGenislik == g ? AppRenkler.primary : TsRenk.kart(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _fisGenislik == g ? AppRenkler.primary : TsRenk.ayirac(context))),
          child: Column(children: [
            Icon(Icons.receipt_long_outlined,
                color: _fisGenislik == g ? Colors.white : TsRenk.metinIkincil(context),
                size: 24),
            const SizedBox(height: 4),
            Text('$g mm', style: TextStyle(fontWeight: FontWeight.w700,
                color: _fisGenislik == g ? Colors.white : TsRenk.metinIkincil(context))),
          ]),
        ),
      ),
    )).toList()),
    const SizedBox(height: 16),
    _bolumBaslik('Font Boyutlari'),
    _fontSlider('Baslik', _baslikFontBoyut, 8, 18, (v) => setState(() => _baslikFontBoyut = v)),
    _fontSlider('Satir',  _satirFontBoyut,  6, 12, (v) => setState(() => _satirFontBoyut = v)),
    _fontSlider('Toplam', _toplamFontBoyut, 8, 14, (v) => setState(() => _toplamFontBoyut = v)),
    const SizedBox(height: 16),
    _bolumBaslik('Yazici Ayarlari'),
    _switchKart([
      _SwitchItem('Otomatik Yazdir', _otomatikYazdir, (v) => setState(() => _otomatikYazdir = v), Icons.print_outlined),
    ]),
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TsRenk.ayirac(context)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 6)],
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.info_outline, size: 16, color: context.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Yazıcı bağlantısı (WiFi/Bluetooth/USB) Ayarlar > Yazdırma '
              'Merkezi\'nden yönetilir. Burada sadece fiş içeriği ve görünümü '
              'ayarlanır.',
              style: TextStyle(fontSize: 11.5, color: TsRenk.metinIkincil(context)),
            ),
          ),
        ]),
        const Divider(height: 16),
        Row(children: [
          Text('Kopya Sayisi', style: TextStyle(fontWeight: FontWeight.w600, color: TsRenk.metinBirincil(context))),
          const Spacer(),
          IconButton(icon: const Icon(Icons.remove, size: 18),
              onPressed: () => setState(() => _kopySayisi = (_kopySayisi - 1).clamp(1, 5))),
          Text('$_kopySayisi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TsRenk.metinBirincil(context))),
          IconButton(icon: const Icon(Icons.add, size: 18),
              onPressed: () => setState(() => _kopySayisi = (_kopySayisi + 1).clamp(1, 5))),
        ]),
        const Divider(height: 16),
        Row(children: [
          Expanded(child: Text('Kagit Besleme', style: TextStyle(fontWeight: FontWeight.w600, color: TsRenk.metinBirincil(context)))),
          Expanded(flex: 2, child: Slider(
              value: _beslemeKagit.toDouble(), min: 0, max: 10, divisions: 10,
              label: '$_beslemeKagit satir',
              onChanged: (v) => setState(() => _beslemeKagit = v.round()))),
          Text('$_beslemeKagit', style: TextStyle(fontSize: 13, color: TsRenk.metinBirincil(context))),
        ]),
      ]),
    ),
    const SizedBox(height: 80),
  ]);

  // TAB 3: Onizleme
  Widget _onizlemeTab() => PdfPreview(
    maxPageWidth: _fisGenislik == 58 ? 220 : 320,
    allowPrinting: true,
    allowSharing: true,
    canChangePageFormat: false,
    canChangeOrientation: false,
    pdfFileName: 'fis_onizleme.pdf',
    build: (_) async => (await _fisPdfOlustur()).save(),
  );

  // YARDIMCI WIDGET'LAR

  Widget _logoAlani() {
    final var_ = _logoYolu != null && File(_logoYolu!).existsSync();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TsRenk.ayirac(context))),
      child: Row(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: TsRenk.arkaplan(context),
            borderRadius: BorderRadius.circular(8),
            image: var_ ? DecorationImage(image: FileImage(File(_logoYolu!)), fit: BoxFit.contain) : null,
          ),
          child: !var_ ? Icon(Icons.image_outlined, color: TsRenk.metinIkincil(context), size: 26) : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Fişin üstüne basılır', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: TsRenk.metinBirincil(context))),
          const SizedBox(height: 2),
          Text(var_ ? 'Yüklendi' : 'PNG/JPG — şeffaf arkaplan önerilir',
              style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
        ])),
        TextButton(onPressed: _logoSec, child: Text(var_ ? 'Değiştir' : 'Yükle')),
        if (var_)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: _logoKaldir,
          ),
      ]),
    );
  }

  Widget _fontSlider(String label, double val, double min, double max, ValueChanged<double> onChange) =>
    Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TsRenk.ayirac(context)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 4)],
      ),
      child: Row(children: [
        SizedBox(width: 60, child: Text(label,
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: TsRenk.metinBirincil(context)))),
        Expanded(child: Slider(
            value: val, min: min, max: max, divisions: (max - min).round(),
            label: '${val.toInt()}px', onChanged: onChange)),
        Text('${val.toInt()}px',
            style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
      ]),
    );

  Widget _textField(String label, TextEditingController ctrl, {String? hint, int maxLines = 1}) =>
    Padding(padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: TextStyle(color: TsRenk.metinBirincil(context)),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: TsRenk.metinIkincil(context)),
          hintStyle: TextStyle(color: TsRenk.metinIkincil(context).withAlpha(153)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: TsRenk.ayirac(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4361EE), width: 1.5),
          ),
          filled: true,
          fillColor: TsRenk.kart(context),
        ),
      ),
    );

  Widget _bolumBaslik(String metin) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(metin,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: AppRenkler.primary,
          letterSpacing: 0.5,
        )),
  );

  /// Ayar grubunun altına açıklama notu — kullanıcı bu ayarın ne
  /// yaptığını tahmin etmek zorunda kalmasın.
  Widget _bilgiNotu(String metin) => Container(
    margin: const EdgeInsets.only(bottom: 14, left: 2, right: 2),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: TsRenk.zemin(AppRenkler.primary, opaklik: 0.06),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
          color: TsRenk.zemin(AppRenkler.primary, opaklik: 0.20)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline_rounded,
          size: 15, color: TsRenk.metinIkincil(context)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(metin,
            style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: TsRenk.metinIkincil(context))),
      ),
    ]),
  );

  Widget _switchKart(List<_SwitchItem> items) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: TsRenk.ayirac(context)),
      boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 6)],
    ),
    child: Column(
      children: items.map((sw) => SwitchListTile(
        secondary: Icon(sw.ikon, size: 18, color: TsRenk.metinIkincil(context)),
        title: Text(sw.baslik,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TsRenk.metinBirincil(context))),
        value: sw.deger,
        onChanged: sw.onChange,
        dense: true,
        activeColor: AppRenkler.primary,
      )).toList(),
    ),
  );
}

/// Switch item sinifi
class _SwitchItem {
  final String baslik;
  final bool deger;
  final ValueChanged<bool> onChange;
  final IconData ikon;
  
  const _SwitchItem(this.baslik, this.deger, this.onChange, this.ikon);
}