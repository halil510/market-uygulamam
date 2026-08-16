// lib/ekranlar/toptan/bayi_siparis_al_ekrani.dart
//
// Kullanıcı isteği: "Bayilerden sipariş alma ekranı — bayiye fiyat
// alış fiyat olacak, ürün arama yapılarak ve barkod okutularak da
// sipariş alma, toptan satış carinin içinden ulaşılsın. Sipariş
// almada alış fiyat gelecek (referans/kâr için), ürün bazında tekrar
// fiyat belirleme/iskonto yapılabilsin. Adet/Koli/Paket miktarları
// Ölçü Birimleri'ndeki çarpana göre hesaplansın (ör. Paket=24 girmişim,
// Paket seçince 24 toplam olarak hesaplasın). Sonradan faturalandırma/
// sevk (irsaliye) — yani bu ekran önce 'Bekleyen Sipariş' oluşturur,
// onay ayrı bir ekrandan yapılır."
//
// Mevcut ToptanSatisEkrani'nin bayi-fiyat/arama/barkod altyapısı
// (FiyatHesaplamaServisi, UrunDeposu.ara/barkodlaGetir) AYNEN
// kullanılıyor; üstüne alış fiyatı görünürlüğü, kalem bazlı iskonto ve
// birim-çarpanı (Ölçü Birimleri) katmanı ekleniyor. Sonuç doğrudan
// satışa değil, BekleyenSiparisDeposu üzerinden "Bekleyen Sipariş"e
// kaydedilir.
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/bekleyen_siparis_deposu.dart';
import '../../servisler/fiyat_hesaplama_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../birim/birim_ekrani.dart';
import '../satis/widgets/kamera_paneli.dart';

class BayiSiparisAlEkrani extends StatefulWidget {
  final CariModel bayi;
  const BayiSiparisAlEkrani({super.key, required this.bayi});

  @override
  State<BayiSiparisAlEkrani> createState() => _BayiSiparisAlEkraniState();
}

class _BayiSiparisAlEkraniState extends State<BayiSiparisAlEkrani> {
  final _urunDepo = UrunDeposu();
  final _fiyatServisi = FiyatHesaplamaServisi();
  final _siparisDepo = BekleyenSiparisDeposu();

  final List<BekleyenSiparisKalemGirdi> _sepet = [];
  final _aramaCtrl = TextEditingController();
  final _notCtrl = TextEditingController();
  List<UrunModel> _aramaSonuclari = [];
  bool _araniyor = false;
  bool _kaydediliyor = false;

  MobileScannerController? _kameraCtrl;
  bool _kameraAcik = false;
  bool _flashAcik = false;

  double get _genelToplam => _sepet.fold(0.0, (s, k) => s + k.toplamTutar);
  double get _alisToplam => _sepet.fold(0.0, (s, k) => s + k.alisToplam);
  double get _tahminiKar => _genelToplam - _alisToplam;

  @override
  void dispose() {
    _aramaCtrl.dispose();
    _notCtrl.dispose();
    _kameraCtrl?.dispose();
    super.dispose();
  }

  Future<void> _urunAra(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _aramaSonuclari = []);
      return;
    }
    setState(() => _araniyor = true);
    final sonuc = await _urunDepo.ara(q.trim());
    if (!mounted) return;
    setState(() { _aramaSonuclari = sonuc; _araniyor = false; });
  }

  void _kamerayiAc() {
    _kameraCtrl = MobileScannerController();
    setState(() => _kameraAcik = true);
  }

  Future<void> _barkodOkundu(String barkod) async {
    setState(() => _kameraAcik = false);
    _kameraCtrl?.dispose();
    _kameraCtrl = null;
    final urun = await _urunDepo.barkodlaGetir(barkod);
    if (!mounted) return;
    if (urun == null) {
      BildirimServisi.hata(context, 'Bu barkodla eşleşen ürün bulunamadı');
      return;
    }
    await _urunEkle(urun);
  }

  Future<void> _urunEkle(UrunModel urun) async {
    _aramaCtrl.clear();
    setState(() => _aramaSonuclari = []);

    final birimler = await BirimEkrani.birimListesiCarpanliGetir();
    if (!mounted) return;

    final baslangicFiyat = await _fiyatServisi.hesapla(urun: urun, cari: widget.bayi, miktar: 1, birim: 'adet');
    if (!mounted) return;

    final sonuc = await showDialog<BekleyenSiparisKalemGirdi>(
      context: context,
      builder: (c) => _KalemDialog(
        urun: urun,
        birimler: birimler,
        baslangicFiyat: baslangicFiyat.birimFiyat,
      ),
    );
    if (sonuc == null) return;

    setState(() {
      final mevcutIdx = _sepet.indexWhere((k) => k.urunId == sonuc.urunId && k.birimAdi == sonuc.birimAdi);
      if (mevcutIdx >= 0) {
        _sepet[mevcutIdx] = BekleyenSiparisKalemGirdi(
          urunId: sonuc.urunId, urunAdi: sonuc.urunAdi, birimAdi: sonuc.birimAdi,
          birimCarpani: sonuc.birimCarpani,
          miktar: _sepet[mevcutIdx].miktar + sonuc.miktar,
          birimFiyat: sonuc.birimFiyat, alisFiyat: sonuc.alisFiyat,
          iskontoOran: sonuc.iskontoOran, kdvOran: sonuc.kdvOran,
        );
      } else {
        _sepet.add(sonuc);
      }
    });
  }

  void _kalemSil(int i) => setState(() => _sepet.removeAt(i));

  Future<void> _siparisiKaydet() async {
    if (_sepet.isEmpty || _kaydediliyor) return;
    setState(() => _kaydediliyor = true);
    try {
      final kullanici = AuthServisi().aktifKullanici;
      await _siparisDepo.siparisOlustur(
        cari: widget.bayi,
        kalemler: _sepet,
        not: _notCtrl.text.trim().isEmpty ? null : _notCtrl.text.trim(),
        kullaniciId: kullanici?.id,
        subeId: AktifSubeServisi().subeId,
      );
      if (!mounted) return;
      BildirimServisi.basari(context,
          '${widget.bayi.unvan} için sipariş kaydedildi — Bekleyen Siparişler\'den onaylayabilirsiniz.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Sipariş kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_kameraAcik && _kameraCtrl != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SatisKameraPaneli(
          controller: _kameraCtrl!,
          flash: _flashAcik,
          onBarkod: _barkodOkundu,
          onKapat: () {
            setState(() => _kameraAcik = false);
            _kameraCtrl?.dispose();
            _kameraCtrl = null;
          },
          onFlashToggle: () {
            setState(() => _flashAcik = !_flashAcik);
            _kameraCtrl?.toggleTorch();
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Sipariş Al',
        altBaslik: widget.bayi.unvan,
        gradyanli: true,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(TsBosluk.lg),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _aramaCtrl,
                  onChanged: _urunAra,
                  decoration: InputDecoration(
                    hintText: 'Ürün adı veya barkod ile ara...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: TsRenk.zemin(TsRenk.notr, opaklik: 0.06),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(TsRadius.md), borderSide: BorderSide.none),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: TsBosluk.sm),
              Container(
                decoration: BoxDecoration(
                    color: TsRenk.kart(context),
                    borderRadius: BorderRadius.circular(TsRadius.md),
                    border: Border.all(color: TsRenk.ayirac(context)),
                    boxShadow: TsGolge.yumusak),
                child: IconButton(
                  icon: Icon(Icons.qr_code_scanner, color: TsRenk.primary),
                  tooltip: 'Barkod Okut',
                  onPressed: _kamerayiAc,
                ),
              ),
            ]),
            if (_araniyor)
              const Padding(
                padding: EdgeInsets.only(top: TsBosluk.md),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_aramaSonuclari.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: TsBosluk.sm),
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                    color: TsRenk.kart(context),
                    borderRadius: BorderRadius.circular(TsRadius.lg),
                    border: Border.all(color: TsRenk.ayirac(context)),
                    boxShadow: TsGolge.yumusak),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(TsBosluk.sm),
                  itemCount: _aramaSonuclari.length,
                  separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.xs),
                  itemBuilder: (ctx, i) {
                    final u = _aramaSonuclari[i];
                    return TsKart.liste(
                      baslik: u.urunAdi,
                      altBaslik: 'Satış: ${ParaUtils.formatla(u.satisFiyati)} · Alış: ${ParaUtils.formatla(u.alisFiyat)} · Stok: ${u.stok.toStringAsFixed(0)}',
                      ikon: const Icon(Icons.inventory_2_outlined),
                      sagAksiyon: Icon(Icons.add_circle_rounded, color: TsRenk.basarili, size: 26),
                      onTap: () => _urunEkle(u),
                    );
                  },
                ),
              ),
          ]),
        ),
        Divider(height: 1, color: TsRenk.ayirac(context)),
        Expanded(
          child: _sepet.isEmpty
              ? TsBosDurum(
                  ikon: Icons.shopping_cart_outlined,
                  baslik: 'Sepet boş',
                  altyazi: 'Yukarıdan ürün arayın veya barkod okutun',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(TsBosluk.lg),
                  itemCount: _sepet.length,
                  separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
                  itemBuilder: (ctx, i) {
                    final k = _sepet[i];
                    final karOran = k.alisFiyat > 0 ? ((k.birimFiyatIskontolu - k.alisFiyat) / k.alisFiyat * 100) : 0;
                    return TsKart(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(k.urunAdi, style: TsMetin.govdeVurgu.copyWith(color: TsRenk.metinBirincil(context)),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.close, size: 18, color: TsRenk.hata),
                            onPressed: () => _kalemSil(i),
                          ),
                        ]),
                        const SizedBox(height: TsBosluk.xs),
                        Text('${k.miktar.toStringAsFixed(k.miktar == k.miktar.roundToDouble() ? 0 : 1)} ${k.birimAdi}'
                            '${k.birimCarpani != 1 ? " (=${k.toplamMiktar.toStringAsFixed(0)} Adet)" : ""}'
                            '${k.iskontoOran > 0 ? " · %${k.iskontoOran.toStringAsFixed(0)} iskonto" : ""}',
                            style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                        const SizedBox(height: TsBosluk.sm),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Alış: ${ParaUtils.formatla(k.alisFiyat)}/birim',
                                style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                            Text('Kâr marjı: %${karOran.toStringAsFixed(0)}',
                                style: TsMetin.kucuk.copyWith(
                                    color: karOran >= 0 ? TsRenk.basarili : TsRenk.hata, fontWeight: FontWeight.w700)),
                          ]),
                          Text(ParaUtils.formatla(k.toplamTutar),
                              style: TsMetin.baslikM.copyWith(color: TsRenk.primary)),
                        ]),
                      ]),
                    );
                  },
                ),
        ),
        if (_sepet.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              boxShadow: TsGolge.yumusak,
            ),
            child: SafeArea(
              top: false,
              child: Column(children: [
                TextField(
                  controller: _notCtrl,
                  decoration: InputDecoration(
                    hintText: 'Sipariş notu (opsiyonel)',
                    isDense: true,
                    filled: true, fillColor: TsRenk.zemin(TsRenk.notr, opaklik: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(TsRadius.md), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: TsBosluk.sm),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Toplam Maliyet (referans)', style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                  Text(ParaUtils.formatla(_alisToplam), style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                ]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Tahmini Kâr', style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                  Text(ParaUtils.formatla(_tahminiKar),
                      style: TsMetin.kucuk.copyWith(color: _tahminiKar >= 0 ? TsRenk.basarili : TsRenk.hata, fontWeight: FontWeight.w700)),
                ]),
                const Divider(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('GENEL TOPLAM', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  Text(ParaUtils.formatla(_genelToplam),
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: TsRenk.primary)),
                ]),
                const SizedBox(height: TsBosluk.md),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: TsRenk.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.md))),
                    onPressed: _kaydediliyor ? null : _siparisiKaydet,
                    icon: _kaydediliyor
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_kaydediliyor ? 'Kaydediliyor...' : 'Siparişi Kaydet (Bekleyen)'),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Ürün eklenirken: miktar, birim (Ölçü Birimleri çarpanı otomatik
/// dolar, gerekirse elle düzeltilebilir), satış fiyatı (bayi fiyatından
/// başlar, elle değiştirilebilir), iskonto — hepsi TEK dialogda.
/// Alış fiyatı salt-okunur referans olarak gösterilir.
class _KalemDialog extends StatefulWidget {
  final UrunModel urun;
  final List<(String ad, double carpan)> birimler;
  final double baslangicFiyat;
  const _KalemDialog({required this.urun, required this.birimler, required this.baslangicFiyat});

  @override
  State<_KalemDialog> createState() => _KalemDialogState();
}

class _KalemDialogState extends State<_KalemDialog> {
  late String _birimAdi;
  late double _carpan;
  final _miktarCtrl = TextEditingController(text: '1');
  late final TextEditingController _fiyatCtrl;
  final _iskontoCtrl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _birimAdi = widget.urun.birimAdi.isNotEmpty ? widget.urun.birimAdi.toUpperCase() : 'ADET';
    final eslesen = widget.birimler.where((b) => b.$1 == _birimAdi);
    _carpan = eslesen.isNotEmpty ? eslesen.first.$2 : 1;
    _fiyatCtrl = TextEditingController(text: widget.baslangicFiyat.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _miktarCtrl.dispose();
    _fiyatCtrl.dispose();
    _iskontoCtrl.dispose();
    super.dispose();
  }

  double get _toplamAdet {
    final miktar = double.tryParse(_miktarCtrl.text.replaceAll(',', '.')) ?? 0;
    return miktar * _carpan;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
      title: Text(widget.urun.urunAdi, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _miktarCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Miktar', border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                value: widget.birimler.any((b) => b.$1 == _birimAdi) ? _birimAdi : null,
                decoration: const InputDecoration(labelText: 'Birim', border: OutlineInputBorder(), isDense: true),
                items: widget.birimler
                    .map((b) => DropdownMenuItem(value: b.$1, child: Text(b.$1, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final secilen = widget.birimler.firstWhere((b) => b.$1 == v);
                  setState(() { _birimAdi = v; _carpan = secilen.$2; });
                },
              ),
            ),
          ]),
          if (_carpan != 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('1 $_birimAdi = ${_carpan.toStringAsFixed(0)} Adet  →  Toplam: ${_toplamAdet.toStringAsFixed(0)} Adet',
                  style: TextStyle(fontSize: 11, color: context.textSecondary)),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _fiyatCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Birim Satış Fiyatı', border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _iskontoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'İskonto %', border: OutlineInputBorder(), isDense: true),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: context.textSecondary.withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Alış Fiyatı (referans)', style: TextStyle(fontSize: 12, color: context.textSecondary)),
              Text(ParaUtils.formatla(widget.urun.alisFiyat), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final miktar = double.tryParse(_miktarCtrl.text.replaceAll(',', '.')) ?? 0;
            final fiyat = double.tryParse(_fiyatCtrl.text.replaceAll(',', '.')) ?? 0;
            final iskonto = double.tryParse(_iskontoCtrl.text.replaceAll(',', '.')) ?? 0;
            if (miktar <= 0 || fiyat <= 0) return;
            Navigator.pop(context, BekleyenSiparisKalemGirdi(
              urunId: widget.urun.id!,
              urunAdi: widget.urun.urunAdi,
              birimAdi: _birimAdi,
              birimCarpani: _carpan,
              miktar: miktar,
              birimFiyat: fiyat,
              alisFiyat: widget.urun.alisFiyat,
              iskontoOran: iskonto.clamp(0, 100),
              kdvOran: double.tryParse(widget.urun.kdvOran) ?? 18,
            ));
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
