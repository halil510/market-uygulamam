import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
// lib/ekranlar/satis/iade_ekrani.dart
// Eski uygulamanın BarkodluIadeEkrani mantığı yeni altyapıya tam entegre edildi

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../saglayicilar/riverpod/kasa_rapor_provider.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'iade/iade_arama_widget.dart';
import 'iade/iade_urun_formu.dart';
import 'iade/iade_gecmis_widget.dart';
import 'iade/iade_cari_dialog.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/fatura_model.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../depolar/fatura_deposu.dart';
import '../../widgetlar/ortak/onay_dialog.dart';
import '../../modeller/satis_model.dart';
import '../../modeller/satis_kalem_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/satis_deposu.dart';
import '../../depolar/iade_deposu.dart';
import '../../servisler/auth_servisi.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/barkod_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/excel_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../servisler/onay_merkezi_servisi.dart';
import '../../servisler/iade_islem_servisi.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';

// Geçmiş İadeler sekmesinin kodu, dosya boyutunu azaltmak için ayrı bir
// dosyaya taşındı (bkz. dosyanın sonundaki not). part/part of ile bu
// dosyayla AYNI kütüphane kapsamını paylaşıyor — davranış değişmedi.
part 'iade_ekrani_gecmis.dart';
part 'iade_ekrani_fis.dart';
part 'iade_ekrani_hizli.dart';

// ─── Renk paleti ─────────────────────────────────────────────────────────────
// 🔴 DÜZELTME (görsel tutarlılık denetimi — "sırayla" listenin 2.
// maddesi): bu ekran ÖNCEDEN kendi izole/sabit renk paletini
// kullanıyordu — primary rengi (koyu lacivert) uygulamanın geri
// kalanından FARKLIYDI ve dark mode'a hiç uymuyordu (1266+ satırlık bu
// finansal-kritik ekran diğer TÜM ekranlardan görsel olarak
// kopuyordu). Durum/aksan renkleri (orange/green/red/blue/primary)
// TsRenk'in AYNI semantik sabitleriyle hizalandı (hâlâ const, context
// gerektirmiyor). Yüzey/metin renkleri (bg/card/textD/textL/border)
// artık context alan metotlar — TsRenk üzerinden dark mode'a uyuyor.
class _R {
  static const primary = TsRenk.primary;
  static const orange = TsRenk.uyari;
  static const blue = TsRenk.bilgi;

  static Color bg(BuildContext c) => TsRenk.arkaplan(c);
  static Color textL(BuildContext c) => TsRenk.metinIkincil(c);
}

// ─── Hızlı mod öğesi ─────────────────────────────────────────────────────────
class _HizliItem {
  final UrunModel urun;
  int adet;
  _HizliItem({required this.urun, this.adet = 1});
}

// ─────────────────────────────────────────────────────────────────────────────
class IadeEkrani extends ConsumerStatefulWidget {
  final List<UrunModel>? baslangicUrunleri;
  // Kullanıcı isteği: "iade alımı yaptığımızda o ekran kapanacak" —
  // toptan cari panelinden tek-ürünlük hızlı iade akışı için. Normal
  // (çok kalemli, sekmeli) perakende iade akışını BOZMAMAK için
  // varsayılan false — sadece açıkça istenirse otomatik kapanır.
  final bool otomatikKapat;
  const IadeEkrani(
      {super.key, this.baslangicUrunleri, this.otomatikKapat = false});

  @override
  ConsumerState<IadeEkrani> createState() => _IadeEkraniState();
}

class _IadeEkraniState extends ConsumerState<IadeEkrani>
    with TickerProviderStateMixin {
  final _aciklamaCtrl = TextEditingController();
  final _urunDepo = UrunDeposu();
  final _cariDepo = CariDeposu();
  final _satisDepo = SatisDeposu();
  final _barkodSrv = BarkodServisi();
  final _excelSrv = ExcelServisi();

  // Veriler
  List<UrunModel> _tumUrunler = [];
  List<CariModel> _cariler = [];
  CariModel? _secilenCari;

  // İade geçmişi
  List<Map<String, dynamic>> _gecmisIadeler = [];
  bool _gecmisYukleniyor = false;
  DateTime? _gecmisTarihBaslangic;
  DateTime? _gecmisTarihBitis;
  CariModel? _gecmisCariFiltre;
  final _gecmisFisCtrl = TextEditingController();

  // Form state
  UrunModel? _secilenUrun;
  double _miktar = 1;
  double _orijinalFiyat = 0;
  bool _yukleniyor = false;
  // 🔴🔴 FAZ 1 madde 1 (kullanıcı onayıyla): bu manuel iade akışının
  // belirli bir orijinal satışa bağlantısı yok, bu yüzden "orijinal
  // ödeme yöntemi" bilinmiyor — kullanıcı burada seçiyor (varsayılan:
  // Nakit). Kart/Banka seçilirse kasa_hareketleri'ne hiç yazılmaz.
  String _iadeOdemeYontemi = 'Nakit';

  // Hızlı mod
  final Map<int, _HizliItem> _hizliMap = {};

  // İade listesi (bu oturumda yapılanlar)
  final List<Map<String, dynamic>> _iadeListesi = [];

  // Oturum iade - tüm kalemler tek fiş altında
  int? _oturumIadeId;
  String _oturumFisNo = '';

  // Düzenleme modu — geçmişten açılan iade
  int?
      _duzenlemeModu_iadeId; // null = yeni iade, int = mevcut iade üzerinde çalışıyoruz
  String? _duzenlemeModu_fisNo;

  // Arama
  List<UrunModel> _aramaListesi = [];
  Timer? _debounce;

  // Fiş arama
  SatisModel? _bulunanSatis;
  // urun_id -> bu satıştan bugüne kadar bu üründen kaç adet iade edilmiş.
  // Fiş sekmesinde aynı kalemin birden fazla kez iade edilmesini
  // (dolayısıyla kasadan mükerrer para çıkışını ve stok şişmesini)
  // önlemek için kullanılır.
  Map<int, double> _fisIadeEdilenMiktar = {};

  // Controllers
  final _aramaCtrl = TextEditingController();
  final _miktarCtrl = TextEditingController(text: '1');
  final _fiyatCtrl = TextEditingController();
  final _iskontoCtrl = TextEditingController(text: '0');
  final _fisNoCtrl = TextEditingController();
  final _aramaFocus = FocusNode();

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _yeniFisNoOlustur(); // Oturum başında fiş no oluştur
    _tab.addListener(() {
      if (_tab.index == 3) _gecmisYukle();
    });
    _aramaCtrl.addListener(_aramaDebounce);
    _miktarCtrl.addListener(() {
      final v = ParaUtils.sayiCoz(_miktarCtrl.text) ?? 1;
      if (v != _miktar) setState(() => _miktar = v);
    });
    _verileriYukle();

    if (widget.baslangicUrunleri?.isNotEmpty == true) {
      for (final u in widget.baslangicUrunleri!) {
        if (u.id == null) continue;
        _hizliMap.containsKey(u.id)
            ? _hizliMap[u.id]!.adet++
            : _hizliMap[u.id!] = _HizliItem(urun: u);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _aramaCtrl.dispose();
    _miktarCtrl.dispose();
    _fiyatCtrl.dispose();
    _iskontoCtrl.dispose();
    _fisNoCtrl.dispose();
    _aramaFocus.dispose();
    _tab.dispose();
    _gecmisFisCtrl.dispose();
    _aciklamaCtrl.dispose();
    super.dispose();
  }

  Future<void> _verileriYukle() async {
    try {
      _gecmisYukle(); // Paralel yükle
      final results =
          await Future.wait([_urunDepo.tumunuGetir(), _cariDepo.tumunuGetir()]);
      if (!mounted) return;
      _tumUrunler = results[0] as List<UrunModel>;
      _cariler = results[1] as List<CariModel>;
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
      // ÖNCEDEN kullanıcıya hiçbir şey gösterilmiyordu — ürün/cari
      // listesi yüklenemezse ekran sessizce BOŞ kalır, kullanıcı
      // nedenini asla bilemezdi.
      if (mounted)
        BildirimServisi.hata(
            context, 'Veriler yüklenemedi, lütfen tekrar deneyin');
    }
  }

  // ── Arama ─────────────────────────────────────────────────────────────────
  void _aramaDebounce() {
    _debounce?.cancel();
    final q = _aramaCtrl.text.trim();
    if (q.isEmpty) {
      _aramaListesi = [];
      if (mounted) setState(() {});
      return;
    }
    if (q.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 280), () => _ara(q));
  }

  void _ara(String q) {
    final ql = q.toLowerCase();
    final res = _tumUrunler
        .where((u) =>
            u.ad.toLowerCase().contains(ql) ||
            (u.barkod?.toLowerCase().contains(ql) ?? false))
        .toList();
    if (!mounted) return;
    _aramaListesi = res;
    if (mounted) setState(() {});
    if (res.length == 1) _secilenUrunAyarla(res.first);
  }

  void _secilenUrunAyarla(UrunModel u) {
    // Aynı ürün bu oturumda iade edilmişse öne çek
    final mevcutIdx = _iadeListesi.indexWhere((i) => i['urun_id'] == u.id);
    if (mevcutIdx > 0) {
      final mevcut = _iadeListesi.removeAt(mevcutIdx);
      _iadeListesi.insert(0, mevcut);
      _msg('${u.urunAdi} daha önce iade edildi — öne çekildi', err: false);
    }
    setState(() {
      _secilenUrun = u;
      _aramaListesi = [];
      // ÖNCEDEN BURADA HER ZAMAN alış fiyatı gösteriliyordu, cari
      // tipine (Müşteri/Tedarikçi) hiç bakılmıyordu. Kullanıcı isteği:
      // cari bir MÜŞTERİ ise satış fiyatı, bir TEDARİKÇİ ise alış
      // fiyatı üzerinden iade edilsin — bu artık cari tipine göre
      // koşullu olarak doğru fiyatı gösteriyor.
      final cariTipi = _secilenCari?.cariTipi ?? '';
      final isTedarikci =
          cariTipi.contains('edarik') || cariTipi.contains('upplier');
      _orijinalFiyat = isTedarikci ? u.alisFiyat : u.satisFiyat;
      _fiyatCtrl.text = _orijinalFiyat.toStringAsFixed(2);
      _miktar = 1;
      _miktarCtrl.text = '1';
    });
    _aramaCtrl.clear();
    _tab.animateTo(0);
  }

  // Oturum için yeni fiş no oluştur
  Future<void> _yeniFisNoOlustur() async {
    try {
      final no = await Veritabani()
          .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);
      if (mounted)
        setState(() {
          _oturumFisNo = no;
        });
    } catch (_) {
      _oturumFisNo =
          'IAD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    }
  }

  void _formSifirla() {
    _secilenUrun = null;
    _miktar = 1;
    _orijinalFiyat = 0;
    _aramaListesi = [];
    _aramaCtrl.clear();
    _miktarCtrl.text = '1';
    _fiyatCtrl.clear();
    _iskontoCtrl.text = '0';
    _aciklamaCtrl.clear();
    if (mounted) setState(() {});
  }

  /// Yeni iade başlat — düzenleme modunu kapat, listeyi temizle
  void _yeniIadeBaslat() {
    setState(() {
      _duzenlemeModu_iadeId = null;
      _duzenlemeModu_fisNo = null;
      _oturumIadeId = null;
      _oturumFisNo = '';
      _iadeListesi.clear();
      _secilenCari = null;
    });
    _yeniFisNoOlustur(); // Yeni oturum için yeni fiş no
    _formSifirla();
    _msg('Yeni iade başlatıldı', err: false);
  }

  // ── Barkod ─────────────────────────────────────────────────────────────────
  Future<void> _barkodOku() async {
    try {
      final barkod = await _barkodSrv.barkodTara(context);
      if (barkod == null || barkod.isEmpty) return;

      // 🔴 DÜZELTME (Madde 34 — Barkod/POS denetimi, 2026-09-20): tartılan
      // (değişken ağırlıklı) bir ürün satışta terazi barkoduyla (13 hane,
      // prefix 20-29, gömülü ürün kodu+ağırlık) sorunsuz ekleniyordu, ama
      // AYNI barkod İade ekranında hiç çözülmüyordu — tam barkod dizesi
      // urunler.barkod'a karşı LİTERAL aranıyordu, hiçbir zaman eşleşmezdi
      // ("Ürün bulunamadı"). Aynı fiziksel ürün/etiket, satışta çalışıp
      // iadede çalışmayan tutarsız bir davranış sergiliyordu.
      final tartim = BarkodServisi.tartimBarkodCoz(barkod);
      final aranacakKod = tartim?.urunKodu ?? barkod;
      final urun = await _urunDepo.barkodlaGetir(aranacakKod);
      if (!mounted) return;
      if (urun != null) {
        _secilenUrunAyarla(urun);
        // Terazi barkodundaki gömülü ağırlığı ön-doldur (satış akışındaki
        // AYNI davranış) — kasiyer yine de elle düzeltebilir.
        if (tartim != null && mounted) {
          setState(() {
            _miktar = tartim.miktarKg;
            _miktarCtrl.text = tartim.miktarKg.toStringAsFixed(3);
          });
        }
      } else {
        _msg('Ürün bulunamadı: $barkod', err: true);
      }
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  // 🔥 "Hızlı" sekmesinin _hizliBarkod() kodu
  // 'iade_ekrani_hizli.dart' dosyasına taşındı (extension olarak).

  // ── Cari seçim - kayıtsız müşteri dahil ─────────────────────────────────
  Future<CariModel?> _cariSecimDialog() async {
    return showDialog<CariModel>(
      context: context,
      builder: (ctx) => CariSecDialog(cariler: _cariler),
    );
  }

  // ── İade kaydet (TEMİZ) ────────────────────────────────────────────────────
  Future<void> _kaydet() async {
    if (_secilenUrun == null) {
      _msg('Ürün seçin', err: true);
      return;
    }
    if (_miktar <= 0) {
      _msg('Geçerli miktar girin', err: true);
      return;
    }

    // Müşteri seçimi - kayıtsız müşteri veya kayıtlı cari seçimi
    if (_secilenCari == null) {
      final sec = await _cariSecimDialog();
      if (sec == null) return; // Kullanıcı iptal etti
      if (!mounted) return;
      setState(() => _secilenCari = sec);
    }

    // Düzenleme modunda mevcut fişe kalem ekle
    if (_duzenlemeModu_iadeId != null) {
      final fiyat = ParaUtils.sayiCoz(_fiyatCtrl.text) ?? _orijinalFiyat;
      final isk = ParaUtils.sayiCoz(_iskontoCtrl.text) ?? 0;
      final toplam = _miktar * fiyat * (1 - isk / 100);
      await _duzenlemeModu_kalemEkle(fiyat, isk, _miktar * fiyat * (isk / 100),
          fiyat * (1 - isk / 100), toplam);
      return;
    }

    if (!mounted) return;
    setState(() => _yukleniyor = true);

    try {
      final fiyat = ParaUtils.sayiCoz(_fiyatCtrl.text) ?? _orijinalFiyat;
      final isk = ParaUtils.sayiCoz(_iskontoCtrl.text) ?? 0;
      final toplam = _miktar * fiyat * (1 - isk / 100);
      final neden = _aciklamaCtrl.text.trim().isEmpty
          ? 'Iade'
          : _aciklamaCtrl.text.trim();

      // Fiş no transaction dışında (sequence güncelleme ayrı transaction gerektirir)
      if (_oturumFisNo.isEmpty)
        _oturumFisNo = await Veritabani()
            .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);

      // Tüm transaction + bulut senkron mantığı artık
      // IadeIslemServisi.manuelKalemEkle'de — bkz. o metodun doc yorumu,
      // davranış birebir korundu.
      final iadeId = await IadeIslemServisi().manuelKalemEkle(
        oturumIadeId: _oturumIadeId,
        cariId: _secilenCari?.id,
        cariTipi: _secilenCari?.cariTipi,
        fisNo: _oturumFisNo,
        urunId: _secilenUrun!.id!,
        urunAdi: _secilenUrun!.urunAdi,
        miktar: _miktar,
        fiyat: fiyat,
        toplam: toplam,
        neden: neden,
        odemeYontemi: _iadeOdemeYontemi,
        kullaniciId: AuthServisi().aktifId,
        kullaniciAdi: AuthServisi().aktifAd,
      );

      // Transaction başarılı - state güncelle
      if (_oturumIadeId == null) _oturumIadeId = iadeId;

      // ── Lokal liste güncelle ─────────────────────────────────────────────
      final mevcutIdx =
          _iadeListesi.indexWhere((x) => x['urun_id'] == _secilenUrun!.id);
      if (mevcutIdx != -1) {
        final m = _iadeListesi[mevcutIdx];
        final yM = (m['miktar'] as double) + _miktar;
        final yT = (m['toplam_tutar'] as double) + toplam;
        final updated = {...m, 'miktar': yM, 'toplam_tutar': yT};
        _iadeListesi.removeAt(mevcutIdx);
        _iadeListesi.insert(0, updated); // Öne taşı
      } else {
        _iadeListesi.insert(0, {
          'iade_id': iadeId,
          'urun_id': _secilenUrun!.id,
          'tarih': DateTime.now(),
          'urun_adi': _secilenUrun!.urunAdi,
          'barkod': _secilenUrun!.barkod ?? '',
          'miktar': _miktar,
          'birim_fiyat': fiyat,
          'iskonto_oran': isk,
          'iskonto_tutar': _miktar * fiyat * (isk / 100),
          'toplam_tutar': toplam,
          'musteri_adi': _secilenCari?.unvan ?? 'Kayıtsız Müşteri',
          'cari_id': _secilenCari?.id,
          'fis_no': _oturumFisNo,
        });
      }

      // Lokal stok
      final si = _tumUrunler.indexWhere((u) => u.id == _secilenUrun!.id);
      if (si != -1)
        _tumUrunler[si] =
            _tumUrunler[si].copyWith(stok: _tumUrunler[si].stok + _miktar);

      _msg('${_secilenUrun!.urunAdi} iade edildi ✓', err: false);
      // Kullanıcı isteği: "iade alımı yaptığımızda o ekran kapanacak"
      // — bu, sadece toptan cari panelinden tek-ürünlük hızlı iade
      // akışında istenir; normal çok-kalemli akışta ekran açık kalıp
      // form sıfırlanmaya devam eder (mevcut davranış korunuyor).
      if (widget.otomatikKapat) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      _formSifirla();
      _gecmisYukle(); // Geçmişi güncelle
    } catch (e) {
      _msg('Hata: $e', err: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // ── Toplu iade (hızlı mod) ───────────────────────────────────────────────
  // 🔥 "Hızlı" sekmesinin _hizliKaydet() kodu taşındı.

  // ── Fiş arama ─────────────────────────────────────────────────────────────
  // 🔥 "Fiş" sekmesinin _fisBul()/_fisKalemIade() kodu
  // 'iade_ekrani_fis.dart' dosyasına taşındı (extension olarak).

  // ── Excel ─────────────────────────────────────────────────────────────────
  Future<void> _excel() async {
    if (_iadeListesi.isEmpty) {
      _msg('İade kaydı yok', err: true);
      return;
    }
    try {
      final path = await _excelSrv.iadelerExcelEAktar(_iadeListesi);
      await _excelSrv.paylasExcel(path);
    } catch (e) {
      _msg('Excel hatası: $e', err: true);
    }
  }

  void _msg(String s, {bool err = false}) {
    if (!mounted) return;
    // 🔴 UX TUTARLILIK DÜZELTMESİ: bkz. aynı düzeltme diğer ekranlarda —
    // artık paylaşılan BildirimServisi kullanılıyor.
    if (err) {
      BildirimServisi.hata(context, s);
    } else {
      BildirimServisi.basari(context, s);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: _duzenlemeModu_iadeId != null
            ? Text('İade: ${_duzenlemeModu_fisNo ?? ''}',
                style: const TextStyle(fontSize: 15))
            : const Text('İade İşlemleri'),
        aksiyonlar: [
          if (_duzenlemeModu_iadeId != null)
            TextButton.icon(
              icon: const Icon(Icons.add_circle_outline,
                  color: Colors.white, size: 16),
              label: const Text('Yeni',
                  style: TextStyle(color: Colors.white, fontSize: 11)),
              onPressed: _yeniIadeBaslat,
            ),
          IconButton(
              icon: Image.asset("assets/images/excel_icon.png",
                  width: 22,
                  height: 22,
                  errorBuilder: (_, __, ___) => const Icon(Icons.table_chart)),
              tooltip: 'Excel',
              onPressed: _excel),
          if (_secilenCari != null)
            Chip(
                label: Text(_secilenCari!.unvan,
                    style: const TextStyle(fontSize: 11)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () {
                  _secilenCari = null;
                  if (mounted) setState(() {});
                }),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              if (v == 'musteri') {
                final secilen = await showDialog<CariModel?>(
                    context: context,
                    builder: (ctx) => CariSecDialog(cariler: _cariler));
                if (secilen != null) {
                  _secilenCari = secilen;
                  if (mounted) setState(() {});
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'musteri',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.person, color: AppRenkler.primary),
                      title: Text('Müşteri Seç'))),
            ],
          ),
        ],
        alt: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: _R.orange,
          tabs: const [
            Tab(icon: Icon(Icons.assignment_return, size: 18), text: 'İade'),
            Tab(icon: Icon(Icons.list_alt, size: 18), text: 'Hızlı'),
            Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Fiş'),
            Tab(icon: Icon(Icons.history, size: 18), text: 'Geçmiş'),
          ],
        ),
        lider: BackButton(onPressed: () => context.go('/')),
        modul: TsModul.uyari,
      ),
      body: TabBarView(controller: _tab, children: [
        _iadeTab(),
        _hizliTab(),
        _fisTab(),
        _gecmisTab(),
      ]),
    );
  }

  // ── İade Sekmesi ──────────────────────────────────────────────────────────
  Widget _iadeTab() => Column(children: [
        _aramaKutusu(),
        if (_aramaListesi.isNotEmpty) _aramaPanel(),
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  if (_secilenUrun != null) ...[
                    _urunFormu(),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: _yukleniyor
                            ? null
                            : LinearGradient(
                                colors: [_R.orange, _R.orange.withAlpha(200)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        color: _yukleniyor ? _R.orange.withAlpha(150) : null,
                        boxShadow: _yukleniyor
                            ? []
                            : [
                                BoxShadow(
                                    color: _R.orange.withAlpha(90),
                                    blurRadius: 14,
                                    offset: const Offset(0, 5)),
                              ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _yukleniyor ? null : _kaydet,
                          child: Center(
                            child: _yukleniyor
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: Colors.white))
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.assignment_return,
                                          color: Colors.white, size: 20),
                                      SizedBox(width: 8),
                                      Text('İade Et',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.2)),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ] else
                    _bosEkran(),
                  if (_iadeListesi.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _iadeGecmisi(),
                  ],
                ]))),
      ]);

  Widget _aramaKutusu() => IadeAramaKutusu(
        controller: _aramaCtrl,
        focusNode: _aramaFocus,
        onTemizle: () {
          _aramaCtrl.clear();
          _aramaListesi = [];
          if (mounted) setState(() {});
        },
        onBarkod: _barkodOku,
      );

  Widget _aramaPanel() => IadeAramaPanel(
        aramaListesi: _aramaListesi,
        onSec: (u) => _secilenUrunAyarla(u as dynamic),
      );
  Widget _urunFormu() => IadeUrunFormu(
        urun: _secilenUrun!,
        miktarCtrl: _miktarCtrl,
        fiyatCtrl: _fiyatCtrl,
        iskontoCtrl: _iskontoCtrl,
        miktar: _miktar,
        orijinalFiyat: _orijinalFiyat,
        onSifirla: _formSifirla,
        onDegisti: () {
          if (mounted) setState(() {});
        },
        odemeYontemi: _iadeOdemeYontemi,
        onOdemeYontemiChanged: (v) {
          if (mounted) setState(() => _iadeOdemeYontemi = v);
        },
      );

  Widget _bosEkran() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: BosEkran(
          ikon: Icons.assignment_return_outlined,
          baslik: 'Ürün seçilmedi',
          aciklama:
              'İade almak için yukarıdaki kutudan ürün adı yazın,\nbarkod okutun veya "Hızlı" ve "Fiş" sekmelerini kullanın.',
          renk: _R.orange,
        ),
      );

  Widget _iadeGecmisi() => IadeGecmisWidget(
        iadeListesi: _iadeListesi,
        duzenlemeModu_iadeId: _duzenlemeModu_iadeId,
        duzenlemeModu_fisNo: _duzenlemeModu_fisNo,
        onSilOnay: _oturumIadeSilOnay,
        onSil: _oturumIadeSil,
        onDuzenle: _oturumIadeDuzenle,
        onExcel: _excel,
      );

  // ── Hızlı İade Sekmesi ────────────────────────────────────────────────────
  // 🔥 "Hızlı" sekmesinin _hizliTab() kodu 'iade_ekrani_hizli.dart' dosyasına taşındı.

  // ── Fiş Arama Sekmesi ─────────────────────────────────────────────────────
  // 🔥 "Fiş" sekmesinin _fisTab() kodu 'iade_ekrani_fis.dart' dosyasına taşındı.

// ── Geçmiş İadeler Tab ───────────────────────────────────────────────────────
  // 🔥 "Geçmiş İadeler" sekmesinin TÜM kodu (_gecmisTab, _oturumIadeSilOnay,
  // _oturumIadeSil, _oturumIadeDuzenle, _gecmisIadeyiDevamEt, _gecmisIadeSil,
  // _gecmisYukle, _iadeyiFaturalandir, _gecmisIadeDetay, _gecmisIadeDuzelt vb.)
  // dosya boyutunu azaltmak için 'iade_ekrani_gecmis.dart' dosyasına taşındı
  // (part/part of ile — mantık/davranış AYNEN korunuyor, sadece organizasyon
  // değişti). Bu metodlar hâlâ bu sınıfın (_IadeEkraniState) birer üyesi gibi
  // çağrılabiliyor, çünkü extension olarak tanımlandılar.

// ── Cari Seç Dialog ─────────────────────────────────────────────────────────
}
