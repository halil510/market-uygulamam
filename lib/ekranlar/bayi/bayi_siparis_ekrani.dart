// lib/ekranlar/bayi/bayi_siparis_ekrani.dart
//
// Bayi Portalı MVP — ürün ara, kendi fiyatını gör (FiyatHesaplamaServisi
// ile, tıpkı toptan_satis_ekrani/bayi_siparis_al_ekrani'nin kullandığı
// AYNI motor), sepete ekle, "Bekleyen Sipariş" olarak gönder. Staff'ın
// bayi adına sipariş girdiği ekrandan (BayiSiparisAlEkrani) BİLİNÇLİ
// OLARAK farklı: alış fiyatı/kâr/iskonto override GÖSTERİLMEZ — bayi
// sadece KENDİ ödeyeceği fiyatı görür. Sipariş doğrudan satışa dönüşmez;
// staff "Bekleyen Siparişler" ekranından onaylar (mevcut akış, değişmedi).
import 'package:flutter/material.dart';

import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/bekleyen_siparis_deposu.dart';
import '../../servisler/fiyat_hesaplama_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class _SepetKalemi {
  final UrunModel urun;
  double miktar;
  double birimFiyat;
  _SepetKalemi({required this.urun, required this.miktar, required this.birimFiyat});
  double get toplam => miktar * birimFiyat;
}

class BayiSiparisEkrani extends StatefulWidget {
  final CariModel bayi;
  const BayiSiparisEkrani({super.key, required this.bayi});
  @override
  State<BayiSiparisEkrani> createState() => _BayiSiparisEkraniState();
}

class _BayiSiparisEkraniState extends State<BayiSiparisEkrani> {
  final _urunDepo = UrunDeposu();
  final _fiyatServisi = FiyatHesaplamaServisi();
  final _siparisDepo = BekleyenSiparisDeposu();
  final _aramaCtrl = TextEditingController();
  final _notCtrl = TextEditingController();

  List<UrunModel> _sonuclar = [];
  final List<_SepetKalemi> _sepet = [];
  bool _araniyor = false;
  bool _gonderiliyor = false;
  int _aramaSira = 0;

  double get _genelToplam => _sepet.fold(0.0, (s, k) => s + k.toplam);

  @override
  void dispose() {
    _aramaCtrl.dispose();
    _notCtrl.dispose();
    super.dispose();
  }

  Future<void> _ara(String sorgu) async {
    if (sorgu.trim().length < 2) {
      setState(() => _sonuclar = []);
      return;
    }
    final sira = ++_aramaSira;
    setState(() => _araniyor = true);
    final r = await _urunDepo.ara(sorgu.trim(), limit: 20);
    if (mounted && sira == _aramaSira) setState(() { _sonuclar = r; _araniyor = false; });
  }

  Future<void> _urunEkle(UrunModel urun) async {
    _aramaCtrl.clear();
    setState(() => _sonuclar = []);
    final fiyat = await _fiyatServisi.hesapla(urun: urun, cari: widget.bayi, miktar: 1, birim: 'adet');
    if (!mounted) return;
    setState(() {
      final idx = _sepet.indexWhere((k) => k.urun.id == urun.id);
      if (idx >= 0) {
        _sepet[idx].miktar += 1;
      } else {
        _sepet.add(_SepetKalemi(urun: urun, miktar: 1, birimFiyat: fiyat.birimFiyat));
      }
    });
  }

  Future<void> _miktarGuncelle(_SepetKalemi kalem, double yeniMiktar) async {
    if (yeniMiktar <= 0) {
      setState(() => _sepet.remove(kalem));
      return;
    }
    // Miktar kademesine göre fiyat değişebilir (ör. 10+ adette indirim) —
    // her miktar değişiminde fiyat yeniden hesaplanır.
    final fiyat = await _fiyatServisi.hesapla(
        urun: kalem.urun, cari: widget.bayi, miktar: yeniMiktar, birim: 'adet');
    if (!mounted) return;
    setState(() {
      kalem.miktar = yeniMiktar;
      kalem.birimFiyat = fiyat.birimFiyat;
    });
  }

  Future<void> _siparisiGonder() async {
    if (_sepet.isEmpty || _gonderiliyor || widget.bayi.id == null) return;
    setState(() => _gonderiliyor = true);
    try {
      final kalemler = _sepet.map((k) => BekleyenSiparisKalemGirdi(
            urunId: k.urun.id!,
            urunAdi: k.urun.urunAdi,
            birimAdi: k.urun.birimAdi,
            birimCarpani: 1,
            miktar: k.miktar,
            birimFiyat: k.birimFiyat,
            alisFiyat: k.urun.alisFiyat,
            kdvOran: double.tryParse(k.urun.kdvOran) ?? 18,
          )).toList();
      await _siparisDepo.siparisOlustur(
        cari: widget.bayi,
        kalemler: kalemler,
        not: _notCtrl.text.trim().isEmpty ? null : _notCtrl.text.trim(),
      );
      if (!mounted) return;
      BildirimServisi.basari(context, 'Siparişiniz alındı — onay bekliyor.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Sipariş gönderilemedi: $e');
    } finally {
      if (mounted) setState(() => _gonderiliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(baslik: 'Sipariş Ver', gradyanli: true),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(TsBosluk.lg),
          child: TextField(
            controller: _aramaCtrl,
            onChanged: _ara,
            decoration: InputDecoration(
              hintText: 'Ürün adı veya barkod ile ara...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _araniyor
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(TsRadius.md)),
              isDense: true,
            ),
          ),
        ),
        if (_sonuclar.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: TsBosluk.lg),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              borderRadius: BorderRadius.circular(TsRadius.md),
              border: Border.all(color: TsRenk.ayirac(context)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _sonuclar.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final u = _sonuclar[i];
                return ListTile(
                  dense: true,
                  title: Text(u.urunAdi),
                  subtitle: Text('Stok: ${u.stok.toStringAsFixed(0)} ${u.birimAdi}'),
                  onTap: () => _urunEkle(u),
                );
              },
            ),
          ),
        const SizedBox(height: TsBosluk.sm),
        Expanded(
          child: _sepet.isEmpty
              ? TsBosDurum(
                  ikon: Icons.shopping_cart_outlined,
                  baslik: 'Sepetiniz boş',
                  altyazi: 'Yukarıdan ürün arayarak sepete ekleyin.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: TsBosluk.lg),
                  itemCount: _sepet.length,
                  separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
                  itemBuilder: (_, i) {
                    final k = _sepet[i];
                    return TsKart(
                      child: Padding(
                        padding: const EdgeInsets.all(TsBosluk.md),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(k.urun.urunAdi, style: TsMetin.govdeVurgu),
                                const SizedBox(height: 2),
                                Text('${ParaUtils.formatla(k.birimFiyat)} / ${k.urun.birimAdi}',
                                    style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _miktarGuncelle(k, k.miktar - 1),
                          ),
                          Text(k.miktar.toStringAsFixed(0), style: TsMetin.govdeVurgu),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _miktarGuncelle(k, k.miktar + 1),
                          ),
                          SizedBox(
                            width: 70,
                            child: Text(ParaUtils.formatla(k.toplam),
                                textAlign: TextAlign.right, style: TsMetin.govdeVurgu),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        if (_sepet.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(TsBosluk.lg),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              boxShadow: TsGolge.yumusak,
            ),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: _notCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Sipariş Notu (opsiyonel)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: TsBosluk.md),
                Row(children: [
                  Expanded(
                    child: Text('Toplam: ${ParaUtils.formatla(_genelToplam)}',
                        style: TsMetin.baslikM),
                  ),
                  FilledButton.icon(
                    onPressed: _gonderiliyor ? null : _siparisiGonder,
                    icon: _gonderiliyor
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_outlined),
                    label: const Text('Siparişi Gönder'),
                  ),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}
