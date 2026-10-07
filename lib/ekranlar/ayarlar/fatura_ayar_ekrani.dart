// lib/ekranlar/ayarlar/fatura_ayar_ekrani.dart — Türkiye e-Fatura/e-Arşiv
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'dart:io';
import '../../servisler/fatura/fatura_gorsel_servisi.dart';
import '../../widgetlar/ortak/il_ilce_alani.dart';

part 'fatura_ayar_sekmeleri.dart';
part 'fatura_ayar_tasarim.dart';

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

  // e-Fatura / GIB — SADECE aktiflik anahtarları burada. Bağlantı bilgileri
  // (API URL/kullanıcı/şifre/VKN/test-canlı modu) TEK bir yerde, GİB e-Fatura
  // Entegrasyonu ekranında (/ayarlar/gib) yönetilir — bkz. 2026-09-14 derin
  // analiz: bu ekranda ÖNCEDEN bu bilgiler için AYRI, SharedPreferences'a
  // yazan alanlar vardı ama gerçek gönderim servisi (GibServisi) onları HİÇ
  // OKUMUYORDU — kullanıcı burayı doldurup "kaydedildi" görüp aslında hiçbir
  // şey göndermemiş oluyordu. O alanlar kaldırıldı, tek gerçek ekrana link
  // eklendi.
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
  // Yazı boyutu ölçeği — PDF'teki tüm metinleri orantılı büyütür/küçültür
  // (resmi "T.C. Değerli Kağıt" damga kutusu hariç — o sabit kalmalı).
  double _fontOlcek      = 1.0;

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
        _ticaretSicilCtrl, _mersisCtrl, _faturaNotCtrl, _dipnotCtrl,
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
      _fontOlcek             = prefs.getDouble('fatura_font_olcek') ?? 1.0;
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
      await prefs.setBool('efatura_aktif',         _eFaturaAktif);
      await prefs.setBool('earsiv_aktif',          _eArsivAktif);
      await prefs.setBool('eirsaliye_aktif',       _eIrsaliyeAktif);
      await prefs.setString('varsayilan_kdv',      _varsayilanKdv);
      await prefs.setBool('kdv_musaf',             _kdvMusaf);
      await prefs.setBool('tevkifat',              _tevkifat);
      await prefs.setString('tevkifat_orani',      _tevkifatOrani);
      await prefs.setBool('fatura_logo',           _logoGoster);
      await prefs.setBool('fatura_imza',           _imzaGoster);
      if (_logoYolu != null) {
        await prefs.setString('fatura_logo_yolu', _logoYolu!);
      } else {
        await prefs.remove('fatura_logo_yolu');
      }
      if (_imzaYolu != null) {
        await prefs.setString('fatura_imza_yolu', _imzaYolu!);
      } else {
        await prefs.remove('fatura_imza_yolu');
      }
      await prefs.setString('fatura_no_onek', _faturaOnEkCtrl.text.trim().toUpperCase());
      await prefs.setString('fatura_varsayilan_iskonto', _iskontoCtrl.text.trim());
      await prefs.setString('fatura_baslangic_no', _baslangicNoCtrl.text.trim().isEmpty ? '1' : _baslangicNoCtrl.text.trim());
      await prefs.setString('fatura_yazdirma_format', _yazdirmaFormat);
      await prefs.setBool('fatura_kdv_ayri',       _kdvAyri);
      await prefs.setBool('fatura_barkod',         _barkodGoster);
      await prefs.setString('fatura_notlari',      _faturaNotCtrl.text.trim());
      await prefs.setString('fatura_dipnot',       _dipnotCtrl.text.trim());
      await prefs.setDouble('fatura_font_olcek',   _fontOlcek);
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

  // ── Logo / İmza-Kaşe görseli seç ────────────────────────────────────────
  Future<void> _gorselSec(bool logoMu) async {
    final kaynak = await FaturaGorselServisi.galeridenSec(logoMu: logoMu);
    if (kaynak == null) return;
    try {
      final yol = await FaturaGorselServisi.kaydet(kaynak, logoMu: logoMu);
      if (!mounted) return;
      setState(() {
        if (logoMu) { _logoYolu = yol; _logoGoster = true; }
        else        { _imzaYolu = yol; }
      });
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Görsel kaydedilemedi: $e');
    }
  }

  void _gorselKaldir(bool logoMu) {
    setState(() {
      if (logoMu) { _logoYolu = null; _logoGoster = false; }
      else {
        _imzaYolu = null;
      }
    });
  }
}
