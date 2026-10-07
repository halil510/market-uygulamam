// lib/ekranlar/urun/urun_ekle_ekrani.dart
// AI destekli tam otomasyonlu ürün ekleme
// - Fatura fotoğrafından OCR ile ürün listesi çıkar
// - Seçilen ürünün adı, miktarı, birim fiyatı, KDV'si forma doldur
// - Ürün adına göre kategori (ana_grup) ve marka (alan1) otomatik belirlenir
// - Gemini API anahtarı kullanıcıdan alınır ve SharedPreferences'ta saklanır

import '../../widgetlar/masaustu/ekran_ustte.dart';
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
import '../../servisler/ai/urun_ses_ayristirici.dart';
import '../../servisler/ai/tr_sayi_ayristirici.dart';
import '../../servisler/ai/ai_vision_servisi.dart'; // API anahtarını set etmek için
// urun_ekle_ekrani_ai_ses.dart (part) kullanıyor
import '../birim/birim_ekrani.dart';
import 'widgets/urun_form_alanlari.dart';
import '../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/ses_tanima_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../depolar/doviz_deposu.dart';
import '../../modeller/doviz_model.dart';
import '../../servisler/log_servisi.dart';
import '../../servisler/onay_merkezi_servisi.dart';

part 'urun_ekle_ekrani_form.dart';
part 'urun_ekle_ekrani_ai_ses.dart';
part 'urun_ekle_ekrani_widgets.dart';

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
  // Kullanıcı bulgusu: "satış fiyat değiştiğinde indirimli fiyat eski
  // kalıyor, hızlı satışta o eski indirimi yansıtıyor". _doldur()'ün
  // programatik alan doldurması sırasında satisFiyati alanı da
  // set edildiği için (bkz. _doldur), bu bayrak o sırada indirim
  // sıfırlama listener'ının yanlışlıkla tetiklenmesini engeller.
  bool _dolduruluyor = false;
  bool _ilkYuklemeYapildi = false;

  // AI ile doldurulan alanları işaretlemek için
  final Set<String> _aiDoldurulanAlanlar = {};

  // Sesli komut özelliği için — extension'lar alan (field) tanımlayamaz,
  // bu yüzden burada, sınıfın kendi alanlarıyla birlikte kalmalı (bkz.
  // urun_ekle_ekrani_ai_ses.dart._sesliKomut).
  final _ses = SesTanimaServisi();

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
    if (Platform.isWindows) HardwareKeyboard.instance.addHandler(_masaustuTus);
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
        _listenerlariEkle();
        _yukleDropdownlar();
      }
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows) HardwareKeyboard.instance.removeHandler(_masaustuTus);
    for (final ctrl in _c.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // ---- MASAÜSTÜ DÜZENİ (geniş pencere) ----
  bool _masaustuMu(BuildContext context) =>
      Platform.isWindows && MediaQuery.sizeOf(context).width > 1100;

  /// Geniş pencerede iki sütun (sol: temel/fiyat, sağ: stok/detay), dar
  /// pencerede/mobilde eskisi gibi tek sütun.
  Widget _formDuzeni(List<Widget> sol, List<Widget> sag) {
    if (!_masaustuMu(context)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...sol, ...sag]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: sol)),
      const SizedBox(width: 24),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: sag)),
    ]);
  }

  bool _masaustuTus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted || _yukleniyor) return false;
    if (!ekranUstte(context)) return false;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (k == LogicalKeyboardKey.f2 || (ctrl && k == LogicalKeyboardKey.keyS)) {
      _kaydet();
    } else if (k == LogicalKeyboardKey.f3 && widget.duzenlenecekUrun != null) {
      _sil();
    } else if (k == LogicalKeyboardKey.f4) {
      _otomatikBarkodUret();
    } else {
      return false;
    }
    return true;
  }

  // ---- GEMINI API ANAHTARI KONTROLÜ ----
  @override
  Widget build(BuildContext context) {
    final duzenleme = widget.duzenlenecekUrun != null;
    final masaustu = _masaustuMu(context);
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: Text(duzenleme ? 'Ürünü Düzenle' : 'Yeni Ürün'),
        aksiyonlar: [
          // 5 yardımcı işlev tek menüde: 6 ikon başlığı "Y…" diye kesiyordu.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'Yardımcı işlemler',
            enabled: !_yukleniyor,
            onSelected: (v) {
              switch (v) {
                case 'api':
                  _geminiApiAnahtarDialogu();
                  break;
                case 'kamera':
                  _kameraIleOku();
                  break;
                case 'ses':
                  _sesliKomut();
                  break;
                case 'fatura':
                  _faturadanUrunEkle();
                  break;
                case 'barkod':
                  _otomatikBarkodUret();
                  break;
              }
            },
            itemBuilder: (_) => [
              // Windows'ta kamera ve mikrofon yok.
              if (!Platform.isWindows)
              const PopupMenuItem(
                  value: 'kamera',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.camera_alt),
                      title: Text('Kamera ile Fatura/Ürün Oku (AI)'))),
              if (!Platform.isWindows)
              const PopupMenuItem(
                  value: 'ses',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.mic_none_outlined),
                      title: Text('Sesle Doldur'))),
              const PopupMenuItem(
                  value: 'fatura',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.receipt_long_outlined),
                      title: Text('Faturadan Ürün Ekle (AI)'))),
              const PopupMenuItem(
                  value: 'barkod',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.qr_code),
                      title: Text('Otomatik Barkod Üret'))),
              const PopupMenuItem(
                  value: 'api',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.key),
                      title: Text('API Anahtarını Değiştir'))),
            ],
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
          ? const TsYukleniyor()
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: TsResponsive.formSarmalayici(
                  context: context,
                  maxGenislik: masaustu ? 1200 : null,
                  child: _formDuzeni([
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
                                    Text(Platform.isWindows ? 'Resim Ekle (Dosyadan seç)' : 'Resim Ekle (Kamera / Galeri)',
                                        style: TextStyle(color: context.textSecondary, fontSize: 13)),
                                  ],
                                ),
                    ),
                  ),

                  _bolum('TEMEL BİLGİLER', Icons.info_outline),
                  Row(children: [
                    Expanded(child: _alan('kod', 'Ürün Kodu *')),
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
                        if (b == null || !context.mounted) return;
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
                        // Pasif ürünler dahil aranıyor — aksi halde pasif
                        // bir ürüne ait barkod, bu üründe "boşta" sanılıp
                        // ikinci bir ürüne de eklenebiliyordu (aynı barkod
                        // iki üründe birden görünüp POS'ta karışıklık
                        // yaratıyordu).
                        final dbUrun = await UrunDeposu().barkodlaGetirPasifDahil(b);
                        if (!context.mounted) return;
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
                        color: TsRenk.zemin(TsRenk.uyari),
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
                        initialValue: _satisBirimiTipi,
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
                          initialValue: _koliBirimAdi,
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

                  ], [
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
                      initialValue: _paraBirimi,
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
      // Masaüstü: alt şerit (F2 Kaydet / F3 Sil / F4 Barkod Üret); mobil: FAB.
      bottomNavigationBar: masaustu
          ? MasaustuAltSerit(
              ozetler: const [
                AltOzet('Ctrl+S', 'veya F2 ile kaydet'),
              ],
              tuslar: [
                AltTus('F2', 'Kaydet', Icons.save, const Color(0xFF2E7D32),
                    _yukleniyor ? null : _kaydet),
                if (duzenleme)
                  AltTus('F3', 'Sil', Icons.delete_outline, const Color(0xFFC62828),
                      _yukleniyor ? null : _sil),
                AltTus('F4', 'Barkod Üret', Icons.qr_code, const Color(0xFF6A1B9A),
                    _yukleniyor ? null : _otomatikBarkodUret),
              ],
            )
          : null,
      floatingActionButton: masaustu ? null : FloatingActionButton.extended(
        backgroundColor: const Color(0xFF4361EE),
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: _yukleniyor ? null : _kaydet,
        icon: const Icon(Icons.save),
        label: const Text('Kaydet'),
      ),
    );
  }
}
