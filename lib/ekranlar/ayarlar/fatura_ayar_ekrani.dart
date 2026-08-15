// lib/ekranlar/ayarlar/fatura_ayar_ekrani.dart — Türkiye e-Fatura/e-Arşiv
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class FaturaAyarEkrani extends ConsumerStatefulWidget {
  /// true ise kendi Scaffold/AppBar'ını çizmez — Yazdırma Merkezi içine
  /// sekme olarak gömülür.
  final bool gomulu;
  const FaturaAyarEkrani({super.key, this.gomulu = false});
  @override
  ConsumerState<FaturaAyarEkrani> createState() => _FaturaAyarEkraniState();
}

class _FaturaAyarEkraniState extends ConsumerState<FaturaAyarEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _kayitYapiliyor = false;

  // Firma Bilgileri
  final _firmaAdiCtrl    = TextEditingController();
  final _vergiNoCtrl     = TextEditingController();
  final _vergiDairesiCtrl= TextEditingController();
  final _adresCtrl       = TextEditingController();
  final _ilCtrl          = TextEditingController();
  final _ilceCtrl        = TextEditingController();
  final _telefonCtrl     = TextEditingController();
  final _faxCtrl         = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _webCtrl         = TextEditingController();
  final _ticaretSicilCtrl= TextEditingController();
  final _mersisCtrl      = TextEditingController();

  // e-Fatura / GIB
  final _gibApiUrlCtrl   = TextEditingController();
  final _gibApiKeyCtrl   = TextEditingController();
  final _gibKullaniciCtrl= TextEditingController();
  final _gibSifreCtrl    = TextEditingController();
  String _gibOrtam       = 'test'; // test | prod
  bool _eFaturaAktif     = false;
  bool _eArsivAktif      = false;
  bool _eIrsaliyeAktif   = false;

  // Fiş / Fatura Tasarımı
  bool _logoGoster       = false;
  bool _imzaGoster       = true;
  bool _kdvAyri          = true;
  bool _barkodGoster      = true;
  String? _logoYolu;
  String? _imzaYolu;
  final _faturaOnEkCtrl  = TextEditingController(); // Örn: HLF, HLA
  final _iskontoCtrl     = TextEditingController(); // Varsayılan iskonto %
  final _baslangicNoCtrl = TextEditingController(); // Fatura başlangıç sıra no
  String _yazdirmaFormat = 'a4'; // a4 | 80mm
  final _faturaNotCtrl   = TextEditingController();
  final _dipnotCtrl      = TextEditingController();

  // KDV ayarları
  String _varsayilanKdv  = '20'; // Türkiye 2024: %20 standart
  bool _kdvMusaf         = false;
  bool _tevkifat         = false;
  String _tevkifatOrani  = '1/2';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _yukle();
  }

  @override
  void dispose() {
    _tab.dispose();
    for (final c in [_firmaAdiCtrl, _vergiNoCtrl, _vergiDairesiCtrl, _adresCtrl,
        _ilCtrl, _ilceCtrl, _telefonCtrl, _faxCtrl, _emailCtrl, _webCtrl,
        _ticaretSicilCtrl, _mersisCtrl, _gibApiUrlCtrl, _gibApiKeyCtrl,
        _gibKullaniciCtrl, _gibSifreCtrl, _faturaNotCtrl, _dipnotCtrl,
        _faturaOnEkCtrl, _iskontoCtrl, _baslangicNoCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _firmaAdiCtrl.text     = prefs.getString('firma_adi') ?? '';
      _vergiNoCtrl.text      = prefs.getString('firma_vergi_no') ?? '';
      _vergiDairesiCtrl.text = prefs.getString('firma_vergi_dairesi') ?? '';
      _adresCtrl.text        = prefs.getString('firma_adres') ?? '';
      _ilCtrl.text           = prefs.getString('firma_il') ?? '';
      _ilceCtrl.text         = prefs.getString('firma_ilce') ?? '';
      _telefonCtrl.text      = prefs.getString('firma_telefon') ?? '';
      _faxCtrl.text          = prefs.getString('firma_fax') ?? '';
      _emailCtrl.text        = prefs.getString('firma_email') ?? '';
      _webCtrl.text          = prefs.getString('firma_web') ?? '';
      _ticaretSicilCtrl.text = prefs.getString('firma_ticaret_sicil') ?? '';
      _mersisCtrl.text       = prefs.getString('firma_mersis') ?? '';
      _gibApiUrlCtrl.text    = prefs.getString('gib_api_url') ?? 'https://earsivportal.efatura.gov.tr';
      _gibApiKeyCtrl.text    = prefs.getString('gib_api_key') ?? '';
      _gibKullaniciCtrl.text = prefs.getString('gib_kullanici') ?? '';
      _gibSifreCtrl.text     = prefs.getString('gib_sifre') ?? '';
      _gibOrtam              = prefs.getString('gib_ortam') ?? 'test';
      _eFaturaAktif          = prefs.getBool('efatura_aktif') ?? false;
      _eArsivAktif           = prefs.getBool('earsiv_aktif') ?? false;
      _eIrsaliyeAktif        = prefs.getBool('eirsaliye_aktif') ?? false;
      _varsayilanKdv         = prefs.getString('varsayilan_kdv') ?? '20';
      _kdvMusaf              = prefs.getBool('kdv_musaf') ?? false;
      _tevkifat              = prefs.getBool('tevkifat') ?? false;
      _tevkifatOrani         = prefs.getString('tevkifat_orani') ?? '1/2';
      _logoGoster            = prefs.getBool('fatura_logo') ?? false;
      _imzaGoster            = prefs.getBool('fatura_imza') ?? true;
      _logoYolu              = prefs.getString('fatura_logo_yolu');
      _imzaYolu              = prefs.getString('fatura_imza_yolu');
      _faturaOnEkCtrl.text   = prefs.getString('fatura_no_onek') ?? '';
      _iskontoCtrl.text      = prefs.getString('fatura_varsayilan_iskonto') ?? '0';
      _baslangicNoCtrl.text  = prefs.getString('fatura_baslangic_no') ?? '1';
      _yazdirmaFormat        = prefs.getString('fatura_yazdirma_format') ?? 'a4';
      _kdvAyri               = prefs.getBool('fatura_kdv_ayri') ?? true;
      _barkodGoster          = prefs.getBool('fatura_barkod') ?? true;
      _faturaNotCtrl.text    = prefs.getString('fatura_notlari') ?? '';
      _dipnotCtrl.text       = prefs.getString('fatura_dipnot') ??
          'Bu fatura elektronik olarak oluşturulmuştur.';
    });
  }

  Future<void> _kaydet() async {
    if (_kayitYapiliyor) return; // 🔴 DÜZELTME: çift tıklama koruması yoktu
    setState(() => _kayitYapiliyor = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('firma_adi',           _firmaAdiCtrl.text.trim());
      await prefs.setString('firma_vergi_no',      _vergiNoCtrl.text.trim());
      await prefs.setString('firma_vergi_dairesi', _vergiDairesiCtrl.text.trim());
      await prefs.setString('firma_adres',         _adresCtrl.text.trim());
      await prefs.setString('firma_il',            _ilCtrl.text.trim());
      await prefs.setString('firma_ilce',          _ilceCtrl.text.trim());
      await prefs.setString('firma_telefon',       _telefonCtrl.text.trim());
      await prefs.setString('firma_fax',           _faxCtrl.text.trim());
      await prefs.setString('firma_email',         _emailCtrl.text.trim());
      await prefs.setString('firma_web',           _webCtrl.text.trim());
      await prefs.setString('firma_ticaret_sicil', _ticaretSicilCtrl.text.trim());
      await prefs.setString('firma_mersis',        _mersisCtrl.text.trim());
      await prefs.setString('gib_api_url',         _gibApiUrlCtrl.text.trim());
      await prefs.setString('gib_api_key',         _gibApiKeyCtrl.text.trim());
      await prefs.setString('gib_kullanici',       _gibKullaniciCtrl.text.trim());
      await prefs.setString('gib_sifre',           _gibSifreCtrl.text.trim());
      await prefs.setString('gib_ortam',           _gibOrtam);
      await prefs.setBool('efatura_aktif',         _eFaturaAktif);
      await prefs.setBool('earsiv_aktif',          _eArsivAktif);
      await prefs.setBool('eirsaliye_aktif',       _eIrsaliyeAktif);
      await prefs.setString('varsayilan_kdv',      _varsayilanKdv);
      await prefs.setBool('kdv_musaf',             _kdvMusaf);
      await prefs.setBool('tevkifat',              _tevkifat);
      await prefs.setString('tevkifat_orani',      _tevkifatOrani);
      await prefs.setBool('fatura_logo',           _logoGoster);
      await prefs.setBool('fatura_imza',           _imzaGoster);
      if (_logoYolu != null) await prefs.setString('fatura_logo_yolu', _logoYolu!);
      else await prefs.remove('fatura_logo_yolu');
      if (_imzaYolu != null) await prefs.setString('fatura_imza_yolu', _imzaYolu!);
      else await prefs.remove('fatura_imza_yolu');
      await prefs.setString('fatura_no_onek', _faturaOnEkCtrl.text.trim().toUpperCase());
      await prefs.setString('fatura_varsayilan_iskonto', _iskontoCtrl.text.trim());
      await prefs.setString('fatura_baslangic_no', _baslangicNoCtrl.text.trim().isEmpty ? '1' : _baslangicNoCtrl.text.trim());
      await prefs.setString('fatura_yazdirma_format', _yazdirmaFormat);
      await prefs.setBool('fatura_kdv_ayri',       _kdvAyri);
      await prefs.setBool('fatura_barkod',         _barkodGoster);
      await prefs.setString('fatura_notlari',      _faturaNotCtrl.text.trim());
      await prefs.setString('fatura_dipnot',       _dipnotCtrl.text.trim());
      if (mounted) BildirimServisi.basari(context, '✓ Fatura ayarları kaydedildi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _kayitYapiliyor = false);
    }
  }

  Widget _govde() => TabBarView(controller: _tab, children: [
        _firmaTab(),
        _eFaturaTab(),
        _kdvTab(),
        _tasarimTab(),
      ]);

  PreferredSizeWidget _icSekmeBari({required bool beyaz}) => TabBar(
        controller: _tab,
        labelColor: beyaz ? Colors.white : AppRenkler.primary,
        unselectedLabelColor: beyaz ? Colors.white60 : context.textSecondary,
        indicatorColor: beyaz ? Colors.white : AppRenkler.primary,
        isScrollable: true,
        tabs: const [
          Tab(text: 'Firma'),
          Tab(text: 'e-Fatura'),
          Tab(text: 'KDV'),
          Tab(text: 'Tasarım'),
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
                _kayitYapiliyor
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        icon: const Icon(Icons.save_outlined),
                        onPressed: _kaydet,
                        tooltip: 'Kaydet'),
              ],
            ),
          ),
          Expanded(child: _govde()),
        ],
      );
    }

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Fatura Ayarları',
        aksiyonlar: [
          _kayitYapiliyor
              ? const Padding(padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : IconButton(icon: const Icon(Icons.save_outlined, color: Colors.white),
                  onPressed: _kaydet, tooltip: 'Kaydet'),
        ],
        alt: _icSekmeBari(beyaz: true),
      ),
      body: _govde(),
    );
  }

  // ── Firma Bilgileri ────────────────────────────────────────────────────────
  Widget _firmaTab() => ListView(padding: const EdgeInsets.all(16), children: [
    _Baslik('Temel Bilgiler'),
    _Alan('Firma Adı *', _firmaAdiCtrl, hint: 'ABC Ticaret A.Ş.'),
    _Alan('Vergi No *', _vergiNoCtrl, hint: '1234567890',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]),
    _Alan('Vergi Dairesi *', _vergiDairesiCtrl, hint: 'Kadıköy Vergi Dairesi'),
    _Alan('MERSİS No', _mersisCtrl, hint: '0123456789012345',
        keyboardType: TextInputType.number),
    _Alan('Ticaret Sicil No', _ticaretSicilCtrl, hint: '12345'),
    const SizedBox(height: 8),
    _Baslik('Adres'),
    _Alan('Adres', _adresCtrl, hint: 'Mevlana Cad. No:1 Daire:5', maxLines: 2),
    Row(children: [
      Expanded(child: _Alan('İl', _ilCtrl, hint: 'İstanbul')),
      const SizedBox(width: 10),
      Expanded(child: _Alan('İlçe', _ilceCtrl, hint: 'Kadıköy')),
    ]),
    const SizedBox(height: 8),
    _Baslik('İletişim'),
    _Alan('Telefon', _telefonCtrl, hint: '0212 555 44 33',
        keyboardType: TextInputType.phone),
    _Alan('Faks', _faxCtrl, hint: '0212 555 44 34',
        keyboardType: TextInputType.phone),
    _Alan('E-Posta', _emailCtrl, hint: 'info@firma.com',
        keyboardType: TextInputType.emailAddress),
    _Alan('Web Sitesi', _webCtrl, hint: 'www.firma.com'),
    const SizedBox(height: 80),
  ]);

  // ── e-Fatura / GIB ────────────────────────────────────────────────────────
  Widget _eFaturaTab() => ListView(padding: const EdgeInsets.all(16), children: [
    // Aktiflik toggle'ları
    _Kart(children: [
      _SwitchSatir('e-Fatura Aktif', 'GIB kayıtlı mükellefler için zorunlu',
          _eFaturaAktif, (v) => setState(() => _eFaturaAktif = v),
          Icons.receipt_long_outlined, Colors.blue),
      _SwitchSatir('e-Arşiv Aktif', 'Diğer alıcılar için fatura',
          _eArsivAktif, (v) => setState(() => _eArsivAktif = v),
          Icons.archive_outlined, Colors.green),
      _SwitchSatir('e-İrsaliye Aktif', 'Taşıma irsaliyesi düzenleme',
          _eIrsaliyeAktif, (v) => setState(() => _eIrsaliyeAktif = v),
          Icons.local_shipping_outlined, Colors.orange),
    ]),
    const SizedBox(height: 16),

    // GIB Ortam Seçimi
    _Baslik('GIB Bağlantı Ayarları'),
    _Kart(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GIB Ortamı', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'test', label: Text('Test'), icon: Icon(Icons.bug_report, size: 16)),
              ButtonSegment(value: 'prod', label: Text('Canlı'), icon: Icon(Icons.verified, size: 16)),
            ],
            selected: {_gibOrtam},
            onSelectionChanged: (s) => setState(() => _gibOrtam = s.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: _gibOrtam == 'prod' ? Colors.red.shade50 : Colors.blue.shade50),
          ),
          if (_gibOrtam == 'prod') Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.red.shade50, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200)),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
              const SizedBox(width: 6),
              const Expanded(child: Text('CANLI ORTAM - Gerçek faturalar kesilecek!',
                  style: TextStyle(fontSize: 11, color: Colors.red))),
            ]),
          ),
        ]),
      ),
    ]),
    const SizedBox(height: 12),
    _Alan('GIB API URL', _gibApiUrlCtrl,
        hint: 'https://earsivportal.efatura.gov.tr'),
    _Alan('API Key / Token', _gibApiKeyCtrl,
        hint: 'Entegratör API anahtarınız', obscure: true),
    _Alan('GIB Kullanıcı Kodu', _gibKullaniciCtrl,
        hint: 'Vergi numaranız veya kullanıcı kodu'),
    _Alan('GIB Şifre', _gibSifreCtrl,
        hint: 'GIB portal şifreniz', obscure: true),
    const SizedBox(height: 8),
    // GIB bilgi kutusu
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.info_outline, color: Colors.blue, size: 16),
          const SizedBox(width: 6),
          const Text('Türkiye e-Fatura (2026)', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.blue)),
        ]),
        const SizedBox(height: 6),
        const Text(
          '• e-Fatura: GIB onaylı Mali Mühür veya e-İmza zorunludur\n'
          '• e-İmza: Kamu SM (kamusm.gov.tr) üzerinden temin edilir\n'
          '• Mali Mühür: TÜBİTAK-BİLGEM CA üzerinden alınır\n'
          '• e-Arşiv: 2026 itibarıyla tüm B2C satışlar zorunlu\n'
          '• Ciro 3M TL üzeri → e-Fatura mükellefi (2024 sınırı)\n'
          '• GIB Portal: efatura.gov.tr\n'
          '• Entegratör API bilgilerini yukarıya giriniz',
          style: TextStyle(fontSize: 11, height: 1.6, color: Colors.blue)),
      ]),
    ),
    const SizedBox(height: 80),
  ]);

  // ── KDV Ayarları ──────────────────────────────────────────────────────────
  Widget _kdvTab() => ListView(padding: const EdgeInsets.all(16), children: [
    _Baslik('Türkiye KDV Oranları (2024)'),
    _Kart(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Varsayılan KDV Oranı',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: ['0', '1', '10', '20'].map((oran) {
            final secili = _varsayilanKdv == oran;
            return GestureDetector(
              onTap: () => setState(() => _varsayilanKdv = oran),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: secili ? AppRenkler.primary : TsRenk.arkaplan(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: secili ? AppRenkler.primary : TsRenk.ayirac(context)),
                ),
                child: Column(children: [
                  Text('%$oran',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16,
                          color: secili ? Colors.white : TsRenk.metinBirincil(context))),
                  Text(_kdvAciklama(oran),
                      style: TextStyle(fontSize: 10,
                          color: secili ? Colors.white70 : context.textSecondary)),
                ]),
              ),
            );
          }).toList()),
        ]),
      ),
    ]),
    const SizedBox(height: 12),
    _Kart(children: [
      _SwitchSatir('KDV Muafiyeti', 'Belirli mal/hizmetler KDV\'den muaf',
          _kdvMusaf, (v) => setState(() => _kdvMusaf = v),
          Icons.no_meals_outlined, Colors.orange),
    ]),
    const SizedBox(height: 12),
    _Kart(children: [
      _SwitchSatir('Tevkifat (KDV Stopajı)', 'Belirli hizmetlerde KDV tevkifatı',
          _tevkifat, (v) => setState(() => _tevkifat = v),
          Icons.calculate_outlined, Colors.purple),
      if (_tevkifat) Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tevkifat Oranı', style: TextStyle(fontSize: 12, color: context.textSecondary)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6,
            children: ['1/2', '2/3', '3/4', '4/5', '5/6', '7/10', '9/10'].map((o) =>
              ChoiceChip(label: Text(o), selected: _tevkifatOrani == o,
                onSelected: (_) => setState(() => _tevkifatOrani = o))).toList()),
        ]),
      ),
    ]),
    const SizedBox(height: 12),
    // KDV bilgi kutusu
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade300)),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.info_outline, color: Colors.amber, size: 16),
          const SizedBox(width: 6),
          Text('Güncel KDV Oranları (2026)', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.amber)),
        ]),
        const SizedBox(height: 6),
        Text(
          '• %20 — Standart oran (2023\'ten itibaren %18→%20)\n'
          '• %10 — İndirimli oran (gıda, bazı hizmetler)\n'
          '• %1  — Özel indirimli (temel gıda, tarım)\n'
          '• %0  — KDV\'den muaf',
          style: TextStyle(fontSize: 11, height: 1.6, color: Colors.amber)),
      ]),
    ),
    const SizedBox(height: 80),
  ]);

  String _kdvAciklama(String oran) {
    switch (oran) {
      case '20': return 'Standart';
      case '10': return 'İndirimli';
      case '1':  return 'Özel';
      case '0':  return 'Muaf';
      default:   return '';
    }
  }

  Widget _formatSecimi(String etiket, String deger, IconData ikon) {
    final secili = _yazdirmaFormat == deger;
    return InkWell(
      onTap: () => setState(() => _yazdirmaFormat = deger),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: secili ? AppRenkler.primary.withAlpha(26) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: secili ? AppRenkler.primary : context.borderColor),
        ),
        child: Column(children: [
          Icon(ikon, color: secili ? AppRenkler.primary : context.textSecondary, size: 22),
          const SizedBox(height: 4),
          Text(etiket, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: secili ? AppRenkler.primary : context.textSecondary)),
          if (secili) ...[
            const SizedBox(height: 2),
            Icon(Icons.check_circle, size: 14, color: AppRenkler.primary),
          ],
        ]),
      ),
    );
  }

  // ── Logo / İmza-Kaşe görseli seç ────────────────────────────────────────
  Future<void> _gorselSec(bool logoMu) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: logoMu ? 600 : 800,
      maxHeight: logoMu ? 600 : 400,
      imageQuality: 90,
    );
    if (xFile == null) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir  = Directory('${base.path}/fatura_gorseller');
      if (!await dir.exists()) await dir.create(recursive: true);
      final dosyaAdi = logoMu ? 'logo.png' : 'imza.png';
      final hedef = File('${dir.path}/$dosyaAdi');
      await File(xFile.path).copy(hedef.path);
      if (!mounted) return;
      setState(() {
        if (logoMu) { _logoYolu = hedef.path; _logoGoster = true; }
        else        { _imzaYolu = hedef.path; }
      });
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Görsel kaydedilemedi: $e');
    }
  }

  void _gorselKaldir(bool logoMu) {
    setState(() {
      if (logoMu) { _logoYolu = null; _logoGoster = false; }
      else        _imzaYolu = null;
    });
  }

  // ── Logo / İmza yükleme alanı (kart) ────────────────────────────────────
  Widget _gorselAlani({required bool logoMu}) {
    final yol = logoMu ? _logoYolu : _imzaYolu;
    final var_ = yol != null && File(yol).existsSync();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: context.cardBg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor)),
      child: Row(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: context.dividerColor,
            borderRadius: BorderRadius.circular(8),
            image: var_ ? DecorationImage(image: FileImage(File(yol)), fit: BoxFit.contain) : null,
          ),
          child: !var_
              ? Icon(logoMu ? Icons.image_outlined : Icons.draw_outlined,
                  color: context.textSecondary, size: 28)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(logoMu ? 'Firma Logosu' : 'İmza / Kaşe Görseli',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            var_
                ? 'Yüklendi — faturalarda görünecek'
                : (logoMu
                    ? 'PNG/JPG — şeffaf arkaplan önerilir'
                    : 'Islak imza/kaşe taraması veya dijital imza'),
            style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ])),
        TextButton(
          onPressed: () => _gorselSec(logoMu),
          child: Text(var_ ? 'Değiştir' : 'Yükle'),
        ),
        if (var_)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: () => _gorselKaldir(logoMu),
          ),
      ]),
    );
  }

  // ── Fatura Tasarımı ───────────────────────────────────────────────────────
  Widget _tasarimTab() => ListView(padding: const EdgeInsets.all(16), children: [
    _Baslik('Logo ve İmza/Kaşe'),
    _gorselAlani(logoMu: true),
    const SizedBox(height: 8),
    _gorselAlani(logoMu: false),
    const SizedBox(height: 12),
    _Baslik('Görünüm'),
    _Kart(children: [
      _SwitchSatir('Logo Göster', 'Fatura başlığında firma logosu',
          _logoGoster, (v) => setState(() => _logoGoster = v),
          Icons.image_outlined, Colors.blue),
      _SwitchSatir('İmza/Kaşe Alanı', 'Fatura altında imza ve kaşe alanı',
          _imzaGoster, (v) => setState(() => _imzaGoster = v),
          Icons.draw_outlined, Colors.indigo),
      _SwitchSatir('KDV Ayrı Göster', 'Her satırda KDV tutarını ayrıca belirt',
          _kdvAyri, (v) => setState(() => _kdvAyri = v),
          Icons.percent_outlined, Colors.teal),
      _SwitchSatir('Barkod/QR Göster', 'Fatura altında barkod veya QR kod',
          _barkodGoster, (v) => setState(() => _barkodGoster = v),
          Icons.qr_code_outlined, Colors.purple),
    ]),
    const SizedBox(height: 12),
    _Baslik('Numaralandırma ve İskonto'),
    Row(children: [
      Expanded(child: _Alan('Fatura No Ön Eki', _faturaOnEkCtrl,
          hint: 'Örn: HLF (e-Fatura), HLA (e-Arşiv)')),
      const SizedBox(width: 12),
      Expanded(child: _Alan('Başlangıç Sıra No', _baslangicNoCtrl,
          hint: '1', keyboardType: TextInputType.number)),
    ]),
    _Alan('Varsayılan İskonto %', _iskontoCtrl,
        hint: '0', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'Örnek: Ön ek "HLF", Başlangıç No "18" ise ilk fatura '
        '"HLF2026000000018" olur. Sayaç bu numaradan devam eder.',
        style: TextStyle(fontSize: 11, color: context.textSecondary)),
    ),
    const SizedBox(height: 4),
    _Baslik('Yazdırma Formatı'),
    _Kart(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Fatura "Yazdır" butonuna basınca varsayılan format',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _formatSecimi('A4 (e-Fatura/e-Arşiv)', 'a4',
                Icons.description_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _formatSecimi('80mm Fiş', '80mm',
                Icons.receipt_long_outlined)),
          ]),
          const SizedBox(height: 6),
          Text(
            'Diğer format ve e-posta gönderimi her zaman fatura ekranındaki '
            '"⋮" menüsünden de seçilebilir.',
            style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ]),
      ),
    ]),
    const SizedBox(height: 4),
    _Baslik('Fatura Notları'),
    _Alan('Fatura Notları', _faturaNotCtrl,
        hint: 'Her faturada görünecek notlar...', maxLines: 3),
    _Alan('Dipnot', _dipnotCtrl,
        hint: 'Fatura alt bilgisi...', maxLines: 2),
    const SizedBox(height: 12),
    // Önizleme kartı
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: context.cardBg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Fatura Önizleme',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              border: Border.all(color: context.borderColor),
              borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_logoGoster) Container(
              width: 60, height: 30,
              decoration: BoxDecoration(color: context.dividerColor, borderRadius: BorderRadius.circular(4)),
              child: Center(child: Text('LOGO', style: TextStyle(fontSize: 10, color: context.textSecondary)))),
            Text(_firmaAdiCtrl.text.isEmpty ? 'Firma Adı' : _firmaAdiCtrl.text,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (_vergiNoCtrl.text.isNotEmpty)
              Text('VKN: ${_vergiNoCtrl.text}', style: TextStyle(fontSize: 10, color: context.textSecondary)),
            const Divider(height: 12),
            Row(children: [
              const Text('FATURA', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
              const Spacer(),
              Text('No: FAT-2024-0001', style: TextStyle(fontSize: 10, color: context.textSecondary)),
            ]),
            const SizedBox(height: 6),
            Container(height: 1, color: context.borderColor),
            const SizedBox(height: 4),
            const Row(children: [
              Expanded(flex: 3, child: Text('Ürün Adı', style: TextStyle(fontSize: 9))),
              Expanded(child: Text('Adet', style: TextStyle(fontSize: 9), textAlign: TextAlign.right)),
              Expanded(child: Text('Fiyat', style: TextStyle(fontSize: 9), textAlign: TextAlign.right)),
              Expanded(child: Text('Tutar', style: TextStyle(fontSize: 9), textAlign: TextAlign.right)),
            ]),
            const SizedBox(height: 4),
            if (_faturaNotCtrl.text.isNotEmpty)
              Text(_faturaNotCtrl.text, style: TextStyle(fontSize: 8, color: context.textSecondary)),
            if (_imzaGoster) const SizedBox(height: 20),
            if (_imzaGoster) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('İmza / Kaşe', style: TextStyle(fontSize: 9, color: context.textSecondary)),
                Text('Alınan / Teslim Alan', style: TextStyle(fontSize: 9, color: context.textSecondary)),
              ]),
            if (_dipnotCtrl.text.isNotEmpty)
              Text(_dipnotCtrl.text,
                  style: TextStyle(fontSize: 8, color: context.textSecondary,
                      fontStyle: FontStyle.italic)),
          ]),
        ),
      ]),
    ),
    const SizedBox(height: 80),
  ]);

  Widget _Alan(String label, TextEditingController ctrl, {
    String? hint, int maxLines = 1, TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters, bool obscure = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: context.textSecondary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
}

class _Baslik extends StatelessWidget {
  final String metin;
  const _Baslik(this.metin);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(metin, style: TextStyle(
        fontWeight: FontWeight.w700, fontSize: 12,
        color: Color.fromARGB(204, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
        letterSpacing: 0.5)),
  );
}

class _Kart extends StatelessWidget {
  final List<Widget> children;
  const _Kart({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
        color: context.cardBg, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 6)]),
    child: Column(children: children),
  );
}

class _SwitchSatir extends StatelessWidget {
  final String baslik, aciklama; final bool deger;
  final ValueChanged<bool> onChanged; final IconData ikon; final Color renk;
  const _SwitchSatir(this.baslik, this.aciklama, this.deger,
      this.onChanged, this.ikon, this.renk);
  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: Container(padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Color.fromARGB(26, renk.red, renk.green, renk.blue), borderRadius: BorderRadius.circular(12)),
        child: Icon(ikon, color: renk, size: 18)),
    title: Text(baslik, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    subtitle: Text(aciklama, style: TextStyle(fontSize: 11, color: context.textSecondary)),
    value: deger, onChanged: onChanged,
    activeColor: renk,
    dense: true,
  );
}
