// lib/ekranlar/tedarik/alim_ekrani.dart
// Performans düzeltmeleri:
//  - tumunuGetir() kaldırıldı, _tumUrunler yok
//  - _ara(): 300ms debounce + _depo.ara() DB sorgusu
//  - Timer dispose eklendi
//  - setState batching iyileştirildi
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/services.dart';
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

class _AlimKalem {
  UrunModel urun;
  double miktar;
  double alisFiyat;
  late final TextEditingController miktarCtrl;
  late final TextEditingController fiyatCtrl;

  _AlimKalem({required this.urun, required this.miktar, required this.alisFiyat}) {
    miktarCtrl = TextEditingController(
        text: miktar % 1 == 0 ? miktar.toStringAsFixed(0) : miktar.toStringAsFixed(3));
    fiyatCtrl  = TextEditingController(text: alisFiyat.toStringAsFixed(2));
  }
  void dispose() { miktarCtrl.dispose(); fiyatCtrl.dispose(); }
  double get toplamTutar => miktar * alisFiyat;
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

  List<_AlimKalem> _kalemler       = [];
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
    for (final k in _kalemler) k.dispose();
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
      if (mounted) setState(() {
        _kalemler.add(_AlimKalem(
          urun: urun,
          miktar: (k['miktar'] as num?)?.toDouble() ?? 1,
          alisFiyat: alisF,
        ));
      });
    }
  }

  Future<void> _tedarikciListesiYukle() async {
    try {  
      final list = await CariDeposu().tumunuGetir();
      if (mounted) setState(() {
        _tedarikciListesi = list.where((c) =>
          c.cariTipi.contains('edarik') ||
          c.cariTipi.contains('upplier')
        ).toList();
      });
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _bankaHesaplariYukle() async {
    try {
      final hesaplar = await BankaHesapDeposu().tumunuGetir();
      if (mounted) setState(() {
        _bankaHesaplari = hesaplar;
        if (hesaplar.isNotEmpty) _secilenHesap = hesaplar.first;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Banka hesapları yüklenemedi: $e');
    }
  }

  Future<void> _tedarikciSec() async {
    final sec = await showDialog<CariModel>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Text('Tedarikçi Seç'),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        content: SizedBox(
          width: double.maxFinite, height: 400,
          child: _tedarikciListesi.isEmpty
            ? const Center(child: Text('Tedarikçi bulunamadı\nCari menüsünden ekleyebilirsiniz.', textAlign: TextAlign.center))
            : ListView.builder(
                itemCount: _tedarikciListesi.length,
                itemBuilder: (_, i) {
                  final t = _tedarikciListesi[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.teal.shade50,
                      child: Text(t.unvan.isNotEmpty ? t.unvan[0].toUpperCase() : '?',
                          style: TsMetin.kucukVurgu.copyWith(color: Colors.teal.shade700)),
                    ),
                    title: Text(t.unvan, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: t.telefon != null ? Text(t.telefon!, style: const TextStyle(fontSize: 11)) : null,
                    onTap: () => Navigator.pop(ctx, t),
                  );
                },
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        ],
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

  double get _genelToplam =>
      _kalemler.fold(0.0, (s, k) => s + k.toplamTutar);

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
                urunId: k.urun.id!, miktar: k.miktar, alisFiyat: k.alisFiyat))
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
        for (final k in _kalemler) k.dispose();
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
        // Kamera paneli (inline)
        if (_kameraAcik) SizedBox(
          height: 160,
          child: Stack(children: [
            MobileScanner(
              controller: _scanCtrl,
              onDetect: (capture) {
                final barcode = capture.barcodes.firstOrNull;
                if (barcode?.rawValue != null) _barkodOkutInline(barcode!.rawValue!);
              },
            ),
            Positioned(top: 8, right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _kameraToggle)),
            Positioned(bottom: 12, left: 0, right: 0,
              child: Center(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: const Text('Barkodu kameraya gösterin', style: TextStyle(color: Colors.white, fontSize: 12)),
              ))),
          ]),
        ),
        // Arama kutusu
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _araCtrl,
              decoration: InputDecoration(
                hintText: 'Ürün ara veya barkod yaz...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _araCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _araCtrl.clear();
                          _aramaSonuclari = [];
                          if (mounted) setState(() {});
                        })
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) { if (v.trim().isNotEmpty) _barkodIsleme(v.trim()); },
            )),
            const SizedBox(width: 8),
            // Kamera toggle butonu
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _kameraAcik ? Theme.of(context).colorScheme.primary : TsRenk.arkaplan(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _kameraAcik ? Theme.of(context).colorScheme.primary : TsRenk.ayirac(context)),
              ),
              child: IconButton(
                icon: Icon(_kameraAcik ? Icons.qr_code_scanner : Icons.qr_code_2,
                    color: _kameraAcik ? Colors.white : TsRenk.metinIkincil(context), size: 24),
                tooltip: _kameraAcik ? 'Kamerayı Kapat' : 'Barkod Okut',
                onPressed: _kameraToggle,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ]),
        ),
        // Arama sonuçları
        if (_aramaSonuclari.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: TsRenk.kart(context),
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _aramaSonuclari.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final u = _aramaSonuclari[i];
                  return ListTile(
                    dense: true,
                    title: Text(u.urunAdi,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(u.barkod ?? u.kod ?? ''),
                    trailing: Text(
                      'Alış: ${ParaUtils.formatla(u.alisFiyat)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _urunEkle(u),
                  );
                },
              ),
            ),
          ),
        // Kalem listesi
        Expanded(
          child: _kalemler.isEmpty
              ? Center(
                  child: Text('Ürün ekleyin',
                      style: TextStyle(color: context.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _kalemler.length,
                  itemBuilder: (_, i) {
                    final k = _kalemler[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6, top: 2),
                      decoration: BoxDecoration(
                        color: TsRenk.kart(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: TsRenk.ayirac(context)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                              child: Text(k.urun.urunAdi,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.red, size: 18),
                              onPressed: () => setState(
                                  () => _kalemler.removeAt(i)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 32),
                            ),
                          ]),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: k.miktarCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                  labelText:
                                      'Miktar (${k.urun.birimAdi})',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  final m = double.tryParse(v) ?? 0;
                                  if (m > 0) {
                                    setState(() => k.miktar = m);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: k.fiyatCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Alış Fiyatı',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  final f = double.tryParse(v) ?? 0;
                                  if (f > 0) {
                                    setState(() => k.alisFiyat = f);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              ParaUtils.formatla(k.toplamTutar),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        // Alt panel
        if (_kalemler.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: const [
                BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 8,
                    offset: Offset(0, -2))
              ],
            ),
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  const Text('Genel Toplam',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(ParaUtils.formatla(_genelToplam),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                // Tedarikçi seç
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _tedarikciSec,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: _tedarikci != null ? Colors.teal : TsRenk.ayirac(context)),
                      borderRadius: BorderRadius.circular(12),
                      color: _tedarikci != null ? Colors.teal.shade50 : null,
                    ),
                    child: Row(children: [
                      Icon(Icons.business, size: 18,
                          color: _tedarikci != null ? Colors.teal : context.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        _tedarikci != null ? _tedarikci!.unvan : 'Tedarikçi Seç (opsiyonel)',
                        style: TextStyle(
                          fontSize: 13,
                          color: _tedarikci != null ? Colors.teal.shade700 : TsRenk.metinIkincil(context),
                          fontWeight: _tedarikci != null ? FontWeight.w600 : FontWeight.normal,
                        ),
                      )),
                      if (_tedarikci != null)
                        GestureDetector(
                          onTap: () => setState(() => _tedarikci = null),
                          child: Icon(Icons.close, size: 16, color: context.textSecondary),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _odemeYontemi,
                  decoration: const InputDecoration(
                      labelText: 'Ödeme', isDense: true,
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Nakit', child: Text('Nakit')),
                    DropdownMenuItem(
                        value: 'Cari', child: Text('Cariye Yaz')),
                    DropdownMenuItem(
                        value: 'Havale', child: Text('Havale')),
                  ],
                  onChanged: (v) =>
                      setState(() => _odemeYontemi = v!),
                ),
                if (_odemeYontemi == 'Havale') ...[
                  const SizedBox(height: 8),
                  if (_bankaHesaplari.isNotEmpty)
                    DropdownButtonFormField<BankaHesapModel>(
                      value: _secilenHesap,
                      decoration: const InputDecoration(
                          labelText: 'Hangi Hesaptan?', isDense: true,
                          border: OutlineInputBorder()),
                      items: _bankaHesaplari
                          .map((h) => DropdownMenuItem(value: h, child: Text(h.hesapAdi, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _secilenHesap = v),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Text('Banka hesabı bulunamadı. Önce bir hesap ekleyin veya "Nakit" seçin.',
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
                    ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isleniyor ? null : _alimKaydet,
                    icon: _isleniyor
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check),
                    label: const Text('Alımı Kaydet'),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
