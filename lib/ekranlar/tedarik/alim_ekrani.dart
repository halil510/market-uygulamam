// lib/ekranlar/tedarik/alim_ekrani.dart
// Performans düzeltmeleri:
//  - tumunuGetir() kaldırıldı, _tumUrunler yok
//  - _ara(): 300ms debounce + _depo.ara() DB sorgusu
//  - Timer dispose eklendi
//  - setState batching iyileştirildi
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/banka_hesap_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/banka_hesap_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/barkod_servisi.dart';
import '../../servisler/alim_islem_servisi.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/auth_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';

part 'alim_ekrani_gorunum.dart';

class _AlimKalem {
  UrunModel urun;
  double miktar;
  double alisFiyat;
  late final TextEditingController miktarCtrl;
  late final TextEditingController fiyatCtrl;
  // 🔴 Derin denetimde bulundu (P2, kullanıcı onayıyla): lot_takibi
  // açık ürünlerde alım anında lot_seri hiç oluşturulmuyordu — ikisi de
  // OPSİYONEL, boş bırakılırsa davranış eskisi gibi kalır.
  late final TextEditingController lotNoCtrl;
  late final TextEditingController sktCtrl;

  _AlimKalem({required this.urun, required this.miktar, required this.alisFiyat}) {
    miktarCtrl = TextEditingController(
        text: miktar % 1 == 0 ? miktar.toStringAsFixed(0) : miktar.toStringAsFixed(3));
    fiyatCtrl  = TextEditingController(text: alisFiyat.toStringAsFixed(2).replaceAll('.', ','));
    lotNoCtrl  = TextEditingController();
    sktCtrl    = TextEditingController();
  }
  void dispose() {
    miktarCtrl.dispose();
    fiyatCtrl.dispose();
    lotNoCtrl.dispose();
    sktCtrl.dispose();
  }
  /// KDV hariç tutar (miktar × birim alış fiyatı).
  double get toplamTutar => ParaUtils.yuvarla(miktar * alisFiyat);
  double get kdvOran => urun.alisKdvOran;
  double get kdvTutar =>
      ParaUtils.yuvarla(miktar * alisFiyat * kdvOran / 100);

  /// KDV dahil tutar — tedarikçiye ödenecek/borçlanılacak miktar.
  double get kdvDahilTutar => ParaUtils.yuvarla(toplamTutar + kdvTutar);
}

class AlimEkrani extends ConsumerStatefulWidget {
  final CariModel? tedarikci;
  final List<Map<String, dynamic>>? baslangicKalemler; // sepetten/siparişten gelen kalemler
  final int? mevcutSiparisId; // dolu ise: yeni fiş açmak yerine bu bekleyen siparişi teslim alıyoruz
  const AlimEkrani({super.key, this.tedarikci, this.baslangicKalemler, this.mevcutSiparisId});
  @override
  ConsumerState<AlimEkrani> createState() => _AlimEkraniState();
}

class _AlimEkraniState extends ConsumerState<AlimEkrani> {
  final _urunDepo  = UrunDeposu();
  final _barkodSrv = BarkodServisi();

  final List<_AlimKalem> _kalemler       = [];
  List<UrunModel>  _aramaSonuclari = [];
  CariModel?       _tedarikci;
  List<CariModel>  _tedarikciListesi = [];
  bool   _isleniyor    = false;
  String _odemeYontemi = 'Nakit';
  int    _aramaId      = 0;

  // Havale seçilince gerçek para çıkışının hangi hesaptan yapılacağı.
  List<BankaHesapModel> _bankaHesaplari = [];
  BankaHesapModel?      _secilenHesap;

  final _araCtrl    = TextEditingController();
  Timer? _aramaDebounce;
  bool _kameraAcik = false;
  late MobileScannerController _scanCtrl;
  String _sonBarkod = '';
  DateTime _sonBarkodZaman = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _tedarikci = widget.tedarikci;
    _tedarikciListesiYukle();
    _bankaHesaplariYukle();
    // Hızlı satıştan gelen kalemler
    if (widget.baslangicKalemler != null) {
      _baslangicKalemYukle();
    }
    _araCtrl.addListener(_aramaChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // AlimNotifier hazır
    });
    _scanCtrl = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  }

  @override
  void dispose() {
    for (final k in _kalemler) {
      k.dispose();
    }
    _aramaDebounce?.cancel();
    if (_kameraAcik) _scanCtrl.stop();
    _scanCtrl.dispose();
    _araCtrl.dispose();
    super.dispose();
  }

  void _aramaChanged() {
    _aramaDebounce?.cancel();
    final q = _araCtrl.text.trim();
    if (q.isEmpty) {
      if (mounted) { _aramaSonuclari = []; setState(() {}); }
      return;
    }
    if (q.length < 2) return;
    _aramaDebounce = Timer(const Duration(milliseconds: 300), () => _ara(q));
  }

  Future<void> _ara(String q) async {
    final aramaId = ++_aramaId;
    try {
      final sonuclar = await _urunDepo.ara(q, limit: 12);
      if (!mounted || aramaId != _aramaId) return;
      _aramaSonuclari = sonuclar;
      if (mounted) setState(() {});
    } catch (e) { /* ignore */ }
  }

  void _kameraToggle() {
    final yeni = !_kameraAcik;
    if (yeni) { _scanCtrl.start(); } else { _scanCtrl.stop(); }
    if (mounted) { _kameraAcik = yeni; setState(() {}); }
  }

  Future<void> _barkodOkutInline(String barkod) async {
    try {  
      final now = DateTime.now();
      if (_sonBarkod == barkod && now.difference(_sonBarkodZaman).inMilliseconds < 1500) return;
      _sonBarkod = barkod;
      _sonBarkodZaman = now;
      await _barkodIsleme(barkod);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _baslangicKalemYukle() async {
    final urunDepo = UrunDeposu();
    for (final k in widget.baslangicKalemler!) {
      final urunId = k['urunId'] as int?;
      if (urunId == null) continue;
      final urun = await urunDepo.idileGetir(urunId);
      if (urun == null) continue;
      // 🔴 Derin analizde bulundu: bu ekrana 'alisFiyat' anahtarıyla kalem
      // gönderen çağıranlar (hızlı satış sepeti, sipariş teslim alma) vardı
      // ama burada HİÇ okunmuyordu — her zaman ürünün GÜNCEL alış fiyatı
      // kullanılıyordu, sipariş/sepetteki anlaşılan fiyat sessizce yok
      // sayılıyordu.
      final alisF = (k['alisFiyat'] as num?)?.toDouble() ??
          (urun.alisFiyat > 0 ? urun.alisFiyat : urun.satisFiyati);
      if (mounted) {
        setState(() {
        _kalemler.add(_AlimKalem(
          urun: urun,
          miktar: (k['miktar'] as num?)?.toDouble() ?? 1,
          alisFiyat: alisF,
        ));
      });
      }
    }
  }

  Future<void> _tedarikciListesiYukle() async {
    try {  
      final list = await CariDeposu().tumunuGetir();
      if (mounted) {
        setState(() {
        _tedarikciListesi = list.where((c) =>
          c.cariTipi.contains('edarik') ||
          c.cariTipi.contains('upplier')
        ).toList();
      });
      }
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _bankaHesaplariYukle() async {
    try {
      final hesaplar = await BankaHesapDeposu().tumunuGetir();
      if (mounted) {
        setState(() {
        _bankaHesaplari = hesaplar;
        if (hesaplar.isNotEmpty) _secilenHesap = hesaplar.first;
      });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Banka hesapları yüklenemedi: $e');
    }
  }

  /// Arama için Türkçe karakter/büyük-küçük harf duyarsız normalizasyon.
  static String _normalize(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .toLowerCase()
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  Future<void> _tedarikciSec() async {
    // 49+ tedarikçi düz listede kaydırarak seçiliyordu (yanlış kişi seçme
    // riski): artık arama kutusu var.
    String filtre = '';
    final sec = await showDialog<CariModel>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final liste = _tedarikciListesi
              .where((t) =>
                  filtre.isEmpty ||
                  _normalize(t.unvan).contains(_normalize(filtre)) ||
                  (t.telefon ?? '').contains(filtre))
              .toList();
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Tedarikçi Seç'),
            contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: _tedarikciListesi.isEmpty
                  ? const Center(
                      child: Text(
                          'Tedarikçi bulunamadı\nCari menüsünden ekleyebilirsiniz.',
                          textAlign: TextAlign.center))
                  : Column(children: [
                      TextField(
                        autofocus: false,
                        decoration: const InputDecoration(
                          hintText: 'Tedarikçi ara...',
                          prefixIcon: Icon(Icons.search, size: 20),
                          isDense: true,
                        ),
                        onChanged: (v) => setD(() => filtre = v.trim()),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: liste.isEmpty
                            ? const Center(child: Text('Eşleşen tedarikçi yok'))
                            : ListView.builder(
                                itemCount: liste.length,
                                itemBuilder: (_, i) {
                                  final t = liste[i];
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: TsRenk.zemin(Colors.teal),
                                      child: Text(
                                          t.unvan.isNotEmpty ? t.unvan[0].toUpperCase() : '?',
                                          style: TsMetin.kucukVurgu
                                              .copyWith(color: Colors.teal.shade700)),
                                    ),
                                    title: Text(t.unvan,
                                        style: const TextStyle(
                                            fontSize: 13, fontWeight: FontWeight.w600)),
                                    subtitle: t.telefon != null
                                        ? Text(t.telefon!, style: const TextStyle(fontSize: 11))
                                        : null,
                                    onTap: () => Navigator.pop(ctx, t),
                                  );
                                },
                              ),
                      ),
                    ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
            ],
          );
        },
      ),
    );
    if (sec != null && mounted) setState(() => _tedarikci = sec);
  }

  Future<void> _barkodOku() async {
    try {  
      final barkod = await _barkodSrv.barkodTara(context);
      if (barkod == null || !mounted) return;
      await _barkodIsleme(barkod);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _barkodIsleme(String barkod) async {
    if (!mounted) return;

    // GS1-TR tartım kontrolü
    final tartim = BarkodServisi.tartimBarkodCoz(barkod);
    if (tartim != null) {
      var urun = await _urunDepo.barkodlaGetir(tartim.urunKodu);
      if (!mounted) return;
      urun ??= await _urunDepo.barkodlaGetir(
          tartim.urunKodu.replaceAll(RegExp(r'^0+'), ''));
      if (urun != null && mounted) {
        _urunEkle(urun, miktar: tartim.miktarKg);
        return;
      }
    }

    final urun = await _urunDepo.barkodlaGetir(barkod);
    if (!mounted) return;
    if (urun != null && mounted) {
      // Zaten listede varsa artır ve bilgi ver
      final mevcutIdx = _kalemler.indexWhere((k) => k.urun.id == urun.id);
      _urunEkle(urun);
      if (mevcutIdx >= 0 && mounted) {
        BildirimServisi.bilgi(context, '${urun.urunAdi} → ${_kalemler[mevcutIdx].miktar.toStringAsFixed(1)} adet');
      }
    } else {
      await _ara(barkod);
      if (mounted) { _araCtrl.text = barkod; setState(() {}); }
    }
  }

  void _urunEkle(UrunModel urun, {double miktar = 1}) {
    if (!mounted) return;
    setState(() {
      final idx = _kalemler.indexWhere((k) => k.urun.id == urun.id);
      if (idx != -1) {
        _kalemler[idx].miktar += miktar;
      } else {
        _kalemler.add(_AlimKalem(
            urun: urun,
            miktar: miktar,
            alisFiyat: urun.alisFiyat));
      }
      _araCtrl.clear();
      _aramaSonuclari = [];
    });
  }

  double get _araToplam =>
      ParaUtils.yuvarla(_kalemler.fold(0.0, (s, k) => s + k.toplamTutar));
  double get _kdvToplam =>
      ParaUtils.yuvarla(_kalemler.fold(0.0, (s, k) => s + k.kdvTutar));

  /// KDV DAHİL genel toplam (cari borç / kasa çıkışı bu tutardır).
  double get _genelToplam => ParaUtils.yuvarla(_araToplam + _kdvToplam);

  Future<void> _alimKaydet() async {
    if (_kalemler.isEmpty) {
      BildirimServisi.uyari(context, 'Kalem eklenmemiş');
      return;
    }
    if (_odemeYontemi == 'Havale' && _secilenHesap == null) {
      BildirimServisi.uyari(context, 'Havale için önce bir banka hesabı seçin');
      return;
    }
    if (_tedarikci == null) {
      // 🔴 Derin analizde bulundu: 'tedarikci_siparisler.cari_id' şemada
      // NOT NULL — ama bu ekran tedarikçi seçilmeden de kayıt yapmaya
      // İZİN VERİYORDU (aciklama'daki "Manuel" varsayılanı bunu ima
      // ediyordu). Sonuç: tedarikçisiz bir alım kaydetmeye çalışıldığında
      // ham bir SQL "NOT NULL constraint failed" hatasıyla çöküyordu.
      BildirimServisi.uyari(context, 'Alım için önce bir tedarikçi seçin');
      return;
    }
    if (!mounted) return;
    _isleniyor = true;
    if (mounted) setState(() {});
    try {
      final kullanici = AuthServisi().aktifKullanici;

      // Tüm transaction + bulut senkron mantığı artık
      // AlimIslemServisi.alimKaydet'te — bkz. o metodun doc yorumu,
      // davranış birebir korundu (fiş + kalemler + stok + kasa/banka +
      // cari TEK transaction içinde).
      await AlimIslemServisi().alimKaydet(
        mevcutSiparisId: widget.mevcutSiparisId,
        kalemler: _kalemler
            .map((k) => AlimKalemGirdi(
                urunId: k.urun.id!,
                miktar: k.miktar,
                alisFiyat: k.alisFiyat,
                kdvOran: k.kdvOran,
                lotNo: k.urun.lotTakibi && k.lotNoCtrl.text.trim().isNotEmpty
                    ? k.lotNoCtrl.text.trim()
                    : null,
                skt: k.urun.lotTakibi
                    ? DateTime.tryParse(k.sktCtrl.text.trim())
                    : null))
            .toList(),
        tedarikciId: _tedarikci?.id,
        tedarikciAdi: _tedarikci?.unvan,
        genelToplam: _genelToplam,
        odemeYontemi: _odemeYontemi,
        bankaHesapId: _secilenHesap?.id,
        kullaniciId: kullanici?.id,
        kullaniciAdi: kullanici?.adSoyad,
      );

      if (mounted) {
        BildirimServisi.basari(context,
            '${_kalemler.length} kalem stoka eklendi');
        for (final k in _kalemler) {
          k.dispose();
        }
        _kalemler.clear();
        _aramaSonuclari = [];
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Alım hatası: $e');
    } finally {
      _isleniyor = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Text(_tedarikci != null
            ? (widget.mevcutSiparisId != null ? 'Teslim Al: ${_tedarikci!.unvan}' : 'Alım: ${_tedarikci!.unvan}')
            : 'Mal Alımı'),
        aksiyonlar: [
          IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              tooltip: 'Barkod',
              onPressed: _barkodOku),
        ],
      ),
      body: Column(children: [
        if (_kameraAcik) _kameraPaneli(),
        _aramaKutusu(),
        if (_aramaSonuclari.isNotEmpty) _aramaSonuclariListesi(),
        Expanded(
          child: _kalemler.isEmpty
              ? Center(
                  child: Text('Ürün ekleyin',
                      style: TextStyle(color: context.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _kalemler.length,
                  itemBuilder: (_, i) => _kalemKarti(_kalemler[i], i),
                ),
        ),
        if (_kalemler.isNotEmpty) _altPanel(),
      ]),
    );
  }
}
