// lib/ekranlar/tedarik/siparis_olustur_ekrani.dart
//
// FAZ 6 (Satın Alma) — daha önce hiç implement edilmemiş "sipariş ver"
// akışının gerçek karşılığı. Bu ekran SADECE bir SİPARİŞ NİYETİ kaydeder:
// stok/kasa/cari hiçbir şekilde ETKİLENMEZ (schema zaten siparis_mik/
// teslim_mik ayrımıyla buna hazırlanmıştı, ama hiç kullanılmıyordu).
// Teslim alma işlemi ayrı bir adımdır — bkz. AlimEkrani(mevcutSiparisId:).
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../depolar/urun_deposu.dart';
import '../../depolar/tedarikci_siparis_deposu.dart';
import '../../veri/database/veritabani.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/barkod_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

class _SiparisKalem {
  UrunModel urun;
  double miktar;
  double birimFiyat;
  late final TextEditingController miktarCtrl;
  late final TextEditingController fiyatCtrl;

  _SiparisKalem({required this.urun, required this.miktar, required this.birimFiyat}) {
    miktarCtrl = TextEditingController(
        text: miktar % 1 == 0 ? miktar.toStringAsFixed(0) : miktar.toStringAsFixed(3));
    fiyatCtrl = TextEditingController(text: birimFiyat.toStringAsFixed(2));
  }
  void dispose() { miktarCtrl.dispose(); fiyatCtrl.dispose(); }
  double get toplamTutar => miktar * birimFiyat;
}

class OnerilenSiparisKalemi {
  final UrunModel urun;
  final double miktar;
  const OnerilenSiparisKalemi({required this.urun, required this.miktar});
}

class SiparisOlusturEkrani extends ConsumerStatefulWidget {
  final CariModel tedarikci;
  final List<OnerilenSiparisKalemi>? onerilenKalemler;
  const SiparisOlusturEkrani({super.key, required this.tedarikci, this.onerilenKalemler});
  @override
  ConsumerState<SiparisOlusturEkrani> createState() => _SiparisOlusturEkraniState();
}

class _SiparisOlusturEkraniState extends ConsumerState<SiparisOlusturEkrani> {
  final _urunDepo = UrunDeposu();
  final _barkodSrv = BarkodServisi();
  final _araCtrl = TextEditingController();
  Timer? _aramaDebounce;
  int _aramaId = 0;

  List<_SiparisKalem> _kalemler = [];
  List<UrunModel> _aramaSonuclari = [];
  bool _isleniyor = false;

  @override
  void initState() {
    super.initState();
    _araCtrl.addListener(_aramaChanged);
    final onerilen = widget.onerilenKalemler;
    if (onerilen != null && onerilen.isNotEmpty) {
      _kalemler = onerilen
          .map((o) => _SiparisKalem(
              urun: o.urun,
              miktar: o.miktar,
              birimFiyat: o.urun.alisFiyat > 0 ? o.urun.alisFiyat : o.urun.satisFiyati))
          .toList();
    }
  }

  @override
  void dispose() {
    for (final k in _kalemler) k.dispose();
    _aramaDebounce?.cancel();
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

  Future<void> _barkodOku() async {
    try {
      final barkod = await _barkodSrv.barkodTara(context);
      if (barkod == null || !mounted) return;
      final urun = await _urunDepo.barkodlaGetir(barkod);
      if (!mounted) return;
      if (urun != null) {
        _urunEkle(urun);
      } else {
        await _ara(barkod);
        if (mounted) { _araCtrl.text = barkod; setState(() {}); }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
    }
  }

  void _urunEkle(UrunModel urun) {
    if (!mounted) return;
    setState(() {
      final idx = _kalemler.indexWhere((k) => k.urun.id == urun.id);
      if (idx != -1) {
        _kalemler[idx].miktar += 1;
        _kalemler[idx].miktarCtrl.text = _kalemler[idx].miktar % 1 == 0
            ? _kalemler[idx].miktar.toStringAsFixed(0)
            : _kalemler[idx].miktar.toStringAsFixed(3);
      } else {
        _kalemler.add(_SiparisKalem(
            urun: urun,
            miktar: 1,
            birimFiyat: urun.alisFiyat > 0 ? urun.alisFiyat : urun.satisFiyati));
      }
      _araCtrl.clear();
      _aramaSonuclari = [];
    });
  }

  double get _genelToplam => _kalemler.fold(0.0, (s, k) => s + k.toplamTutar);

  Future<void> _siparisKaydet() async {
    if (_kalemler.isEmpty) {
      BildirimServisi.uyari(context, 'Kalem eklenmemiş');
      return;
    }
    _isleniyor = true;
    if (mounted) setState(() {});
    try {
      final kullanici = AuthServisi().aktifKullanici;
      final siparisNo = await Veritabani().fisNoUret('siparis', subeId: AktifSubeServisi().subeId ?? 1);

      // Tüm transaction + bulut senkron mantığı artık
      // TedarikciSiparisDeposu.olustur'da — bkz. o metodun doc yorumu,
      // davranış birebir korundu (stok/kasa/cari HİÇ ETKİLENMEZ, sadece
      // 'beklemede' sipariş kaydı).
      await TedarikciSiparisDeposu().olustur(
        tedarikciId: widget.tedarikci.id!,
        tedarikciUnvan: widget.tedarikci.unvan,
        kalemler: _kalemler
            .map((k) => TedarikciSiparisKalemGirdi(
                urunId: k.urun.id!,
                miktar: k.miktar,
                birimFiyat: k.birimFiyat))
            .toList(),
        genelToplam: _genelToplam,
        siparisNo: siparisNo,
        olusturanId: kullanici?.id,
      );

      if (mounted) {
        BildirimServisi.basari(context, 'Sipariş oluşturuldu: $siparisNo');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Sipariş kaydedilemedi: $e');
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
        baslikWidget: Text('Sipariş: ${widget.tedarikci.unvan}'),
        aksiyonlar: [
          IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              tooltip: 'Barkod',
              onPressed: _barkodOku),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
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
          ),
        ),
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
                    title: Text(u.urunAdi, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(u.barkod ?? u.kod ?? ''),
                    trailing: Text('Alış: ${ParaUtils.formatla(u.alisFiyat)}', style: const TextStyle(fontSize: 12)),
                    onTap: () => _urunEkle(u),
                  );
                },
              ),
            ),
          ),
        Expanded(
          child: _kalemler.isEmpty
              ? Center(child: Text('Sipariş edilecek ürünleri ekleyin', style: TextStyle(color: context.textSecondary)))
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                              child: Text(k.urun.urunAdi,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red, size: 18),
                              onPressed: () => setState(() => _kalemler.removeAt(i)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          ]),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: k.miktarCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Miktar (${k.urun.birimAdi})',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  final m = double.tryParse(v) ?? 0;
                                  if (m > 0) setState(() => k.miktar = m);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: k.fiyatCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Birim Fiyat',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  final f = double.tryParse(v) ?? 0;
                                  if (f > 0) setState(() => k.birimFiyat = f);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(ParaUtils.formatla(k.toplamTutar),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        if (_kalemler.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 8, offset: Offset(0, -2))],
            ),
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Genel Toplam', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(ParaUtils.formatla(_genelToplam),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isleniyor ? null : _siparisKaydet,
                    icon: _isleniyor
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check),
                    label: const Text('Siparişi Kaydet'),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
