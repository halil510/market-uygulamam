// lib/ekranlar/toptan/toptan_satis_ekrani.dart
//
// Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
// profesyonel sistem, Logo gibi yazılımlar gibi görsel olsun, e-Fatura/
// e-Arşiv ile entegre olsun." Bu ekran mevcut satış altyapısını
// (SatisDeposu, StokDeposu, CariDeposu) ve mevcut faturalandırma
// zincirini (FaturalandirmaServisi — satış detay ekranıyla AYNI,
// kanıtlanmış akış) kullanıyor; üstüne fiyat grubu/kademe/koli-adet-kg
// hesaplama katmanı ve "Logo tarzı" fatura-önizleme görünümlü sepet
// ekliyor.
import 'package:flutter/material.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/satis_model.dart';
import '../../modeller/satis_kalem_model.dart';
import '../../modeller/fatura_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/satis_deposu.dart';
import '../../servisler/belge_no_servisi.dart';
import '../../servisler/fiyat_hesaplama_servisi.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/onay_merkezi_servisi.dart';
import '../../servisler/toptan_satis_islem_servisi.dart';
import '../../widgetlar/ortak/donanim_barkod_dinleyici.dart';
part 'toptan_satis_ekrani_islemler.dart';
part 'toptan_satis_ekrani_widgetlar.dart';

class _SepetKalemi {
  final UrunModel urun;
  double miktar;
  String birim; // 'adet' | 'koli' | 'kg'
  FiyatSonucu fiyatSonucu;
  _SepetKalemi(
      {required this.urun,
      required this.miktar,
      required this.birim,
      required this.fiyatSonucu});

  double get kdvOran => double.tryParse(urun.kdvOran) ?? 18;
  // 🔴 DÜZELTME (Madde 21 — Para Hesaplamaları denetimi, 2026-09-16):
  // birim fiyat GERÇEKTEN KDV DAHİL (kullanıcı onayıyla doğrulandı,
  // bkz. sepet_model.dart baş yorumu) — önceki yorumdaki "ters çıkarma
  // yanlıştı" iddiası hatalıydı, aslen doğru olan bölme tabanlı çıkarma
  // yanlışlıkla çarpma tabanlı (KDV'yi üzerine ekleyen) bir formülle
  // değiştirilmişti. toplamTutar = müşteriden tahsil edilen tutarın ta
  // kendisi (bu her zaman doğruydu, değişmedi); kdvTutari artık bu
  // tutarın İÇİNDEN doğru şekilde ayıklanıyor.
  double get toplamTutar => miktar * fiyatSonucu.birimFiyat;
  double get kdvTutari => ParaUtils.kdvPayiCikar(toplamTutar, kdvOran);
  // Stoktan gerçekte düşülecek miktar (koli ise adede çevrilir).
  double get stokMiktari => (birim == 'koli' && urun.koliIciMiktar > 0)
      ? miktar * urun.koliIciMiktar
      : miktar;
}

class ToptanSatisEkrani extends StatefulWidget {
  // Kullanıcı isteği: "cariye girip satış dedik mi o bayi seçili
  // gelsin" + "çoğalt dedik mi eski siparişin kalemleri gelsin."
  final CariModel? baslangicBayi;
  final int?
      tekrarSatisId; // "Çoğalt" — bu satışın kalemleri fiyatlar TAZE hesaplanarak yeniden eklenir
  const ToptanSatisEkrani({super.key, this.baslangicBayi, this.tekrarSatisId});

  @override
  State<ToptanSatisEkrani> createState() => _ToptanSatisEkraniState();
}

class _ToptanSatisEkraniState extends State<ToptanSatisEkrani> {
  final _cariDepo = CariDeposu();
  final _urunDepo = UrunDeposu();
  final _fiyatServisi = FiyatHesaplamaServisi();

  CariModel? _secilenBayi;
  final List<_SepetKalemi> _sepet = [];
  final _aramaCtrl = TextEditingController();
  List<UrunModel> _aramaSonuclari = [];
  bool _kaydediliyor = false;

  double get _kdvToplam => _sepet.fold(0.0, (s, k) => s + k.kdvTutari);
  double get _genelToplam => _sepet.fold(0.0, (s, k) => s + k.toplamTutar);

  @override
  void initState() {
    super.initState();
    _secilenBayi = widget.baslangicBayi;
    if (widget.tekrarSatisId != null) {
      // "Çoğalt" — eski build tamamlanana kadar bekleyip sepeti doldur.
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _eskiSiparisiCogalt(widget.tekrarSatisId!));
    }
  }

  @override
  void dispose() {
    _aramaCtrl.dispose();
    super.dispose();
  }

  void _kalemSil(int index) => setState(() => _sepet.removeAt(index));

  @override
  Widget build(BuildContext context) {
    // El terminali / USB okuyucu: arama kutusu odakta değilken de okutma
    // ürün ekler (bkz. DonanimBarkodDinleyici).
    return DonanimBarkodDinleyici(
      onBarkod: _aramaGonderildi,
      aktif: _secilenBayi != null,
      child: Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Toptan Satış',
        altBaslik: _secilenBayi?.unvan,
        gradyanli: true,
      ),
      body: Column(children: [
        // ── Bayi Bilgi Kartı (Logo-tarzı: bakiye + limit görsel özet) ──
        Container(
          margin: const EdgeInsets.all(TsBosluk.md),
          child: InkWell(
            onTap: _bayiSec,
            borderRadius: BorderRadius.circular(TsRadius.lg),
            child: Container(
              padding: const EdgeInsets.all(TsBosluk.lg),
              decoration: BoxDecoration(
                gradient: _secilenBayi == null
                    ? null
                    : LinearGradient(
                        colors: [
                          TsRenk.zemin(TsRenk.primary, opaklik: 0.10),
                          TsRenk.zemin(TsRenk.primary, opaklik: 0.03)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: _secilenBayi == null ? TsRenk.kart(context) : null,
                borderRadius: BorderRadius.circular(TsRadius.lg),
                border: Border.all(
                    color: _secilenBayi == null
                        ? TsRenk.zemin(TsRenk.uyari, opaklik: 0.4)
                        : TsRenk.primary,
                    width: 1.5),
                boxShadow: TsGolge.yumusak,
              ),
              child: _secilenBayi == null
                  ? Row(children: [
                      Icon(Icons.storefront, color: TsRenk.uyari),
                      const SizedBox(width: TsBosluk.sm),
                      Expanded(
                          child: Text('Bayi/Toptan Müşteri Seçin',
                              style: TsMetin.govdeVurgu.copyWith(
                                  color: TsRenk.metinBirincil(context)))),
                      const Icon(Icons.chevron_right),
                    ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Row(children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: TsRenk.primary,
                              child: Text(
                                  _secilenBayi!.unvan.isNotEmpty
                                      ? _secilenBayi!.unvan[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: TsBosluk.md),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_secilenBayi!.unvan,
                                        style: TsMetin.baslikM.copyWith(
                                            color:
                                                TsRenk.metinBirincil(context))),
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: TsRenk.zemin(TsRenk.primary),
                                          borderRadius: BorderRadius.circular(
                                              TsRadius.sm)),
                                      child: Text(_secilenBayi!.musteriTipi,
                                          style: TsMetin.kucuk.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: TsRenk.primary)),
                                    ),
                                  ]),
                            ),
                            IconButton(
                                icon: const Icon(Icons.swap_horiz),
                                tooltip: 'Bayi Değiştir',
                                onPressed: _bayiSec),
                          ]),
                          const SizedBox(height: TsBosluk.sm),
                          Row(children: [
                            Expanded(
                                child: _MiniIstatistik(
                                    baslik: 'Bakiye',
                                    deger: ParaUtils.formatla(
                                        _secilenBayi!.bakiye),
                                    renk: _secilenBayi!.bakiye > 0
                                        ? TsRenk.uyari
                                        : TsRenk.basarili)),
                            if (_secilenBayi!.limitTutari > 0)
                              Expanded(
                                  child: _MiniIstatistik(
                                      baslik: 'Kredi Limiti',
                                      deger: ParaUtils.formatla(
                                          _secilenBayi!.limitTutari),
                                      renk: TsRenk.primary)),
                          ]),
                        ]),
            ),
          ),
        ),

        if (_secilenBayi != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TsBosluk.md),
            child: TextField(
              controller: _aramaCtrl,
              decoration: InputDecoration(
                hintText: 'Ürün ara (ad, barkod, kod)...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: TsRenk.zemin(TsRenk.notr, opaklik: 0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(TsRadius.md),
                    borderSide: BorderSide.none),
              ),
              onChanged: _urunAra,
              onSubmitted: _aramaGonderildi,
              textInputAction: TextInputAction.search,
            ),
          ),
          if (_aramaSonuclari.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(TsBosluk.md, 4, TsBosluk.md, 0),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                  color: TsRenk.kart(context),
                  borderRadius: BorderRadius.circular(TsRadius.lg),
                  border: Border.all(color: TsRenk.ayirac(context)),
                  boxShadow: TsGolge.yumusak),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(TsBosluk.sm),
                itemCount: _aramaSonuclari.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: TsBosluk.xs),
                itemBuilder: (c, i) {
                  final u = _aramaSonuclari[i];
                  return TsKart.liste(
                    baslik: u.urunAdi,
                    altBaslik:
                        'Stok: ${u.stok.toStringAsFixed(0)} ${u.birimAdi}'
                        '${u.koliIciMiktar > 0 ? " · 1 ${u.koliBirimAdi} = ${u.koliIciMiktar.toStringAsFixed(0)} ${u.birimAdi}" : ""}',
                    ikon: const Icon(Icons.inventory_2_outlined),
                    sagAksiyon: Icon(Icons.add_circle_rounded,
                        color: TsRenk.basarili, size: 24),
                    onTap: () => _urunEkle(u),
                  );
                },
              ),
            ),
          const SizedBox(height: TsBosluk.sm),

          // ── Sepet: GERÇEK fatura kalemi ızgarası (Logo/Netsis tarzı) ──
          // Kart listesi DEĞİL — ince kenarlıklı, zebra çizgili, sıra
          // numaralı, hizalı rakamlı klasik muhasebe tablosu. Bu, tam
          // olarak istenen "profesyonel ERP" görünümü — sadece renk/
          // boşluk tokenleri modernize edildi, düzeni korundu.
          if (_sepet.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: TsBosluk.md),
              decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.primary, opaklik: 0.05),
                border: Border.all(color: TsRenk.ayirac(context)),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(TsRadius.sm)),
              ),
              child: Row(children: [
                _gridBaslikHucre('#', flex: 1, ortala: true),
                _gridBaslikHucre('ÜRÜN', flex: 6),
                _gridBaslikHucre('MİKTAR', flex: 3, ortala: true),
                _gridBaslikHucre('B.FİYAT', flex: 3, sagaYasla: true),
                _gridBaslikHucre('KDV%', flex: 2, ortala: true),
                _gridBaslikHucre('TUTAR', flex: 3, sagaYasla: true),
                const SizedBox(width: 32),
              ]),
            ),
          Expanded(
            child: _sepet.isEmpty
                ? TsBosDurum(
                    ikon: Icons.shopping_cart_outlined,
                    baslik: 'Sepet boş',
                    altyazi: 'Ürün arayıp ekleyin',
                  )
                : Container(
                    margin: const EdgeInsets.fromLTRB(
                        TsBosluk.md, 0, TsBosluk.md, 0),
                    decoration: BoxDecoration(
                      color: TsRenk.kart(context),
                      border: Border(
                        left: BorderSide(color: TsRenk.ayirac(context)),
                        right: BorderSide(color: TsRenk.ayirac(context)),
                        bottom: BorderSide(color: TsRenk.ayirac(context)),
                      ),
                      boxShadow: TsGolge.yumusak,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _sepet.length,
                      itemBuilder: (c, i) {
                        final k = _sepet[i];
                        final kdvOran = double.tryParse(k.urun.kdvOran) ?? 18;
                        final ciftMi = i.isEven;
                        return Column(children: [
                          Container(
                            color: ciftMi
                                ? TsRenk.zemin(TsRenk.notr, opaklik: 0.04)
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _gridHucre('${i + 1}',
                                      flex: 1, ortala: true, sonuk: true),
                                  Expanded(
                                    flex: 6,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(k.urun.urunAdi,
                                                style: TsMetin.govdeVurgu
                                                    .copyWith(
                                                        fontSize: 12.5,
                                                        color: TsRenk
                                                            .metinBirincil(
                                                                context)),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                            Text(k.fiyatSonucu.aciklama,
                                                style: TsMetin.kucuk.copyWith(
                                                    color: TsRenk.basarili,
                                                    fontStyle:
                                                        FontStyle.italic),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ]),
                                    ),
                                  ),
                                  _gridHucre(
                                      '${k.miktar.toStringAsFixed(k.miktar == k.miktar.roundToDouble() ? 0 : 1)}\n${_birimEtiket(k.birim)}',
                                      flex: 3,
                                      ortala: true),
                                  _gridHucre(
                                      ParaUtils.formatla(
                                          k.fiyatSonucu.birimFiyat),
                                      flex: 3,
                                      sagaYasla: true),
                                  _gridHucre('%${kdvOran.toStringAsFixed(0)}',
                                      flex: 2, ortala: true, sonuk: true),
                                  _gridHucre(ParaUtils.formatla(k.toplamTutar),
                                      flex: 3, sagaYasla: true, kalin: true),
                                  SizedBox(
                                    width: 32,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: Icon(Icons.close,
                                          size: 15, color: TsRenk.hata),
                                      onPressed: () => _kalemSil(i),
                                    ),
                                  ),
                                ]),
                          ),
                          if (i < _sepet.length - 1)
                            Divider(height: 1, color: TsRenk.ayirac(context)),
                        ]);
                      },
                    ),
                  ),
          ),

          // ── Fatura-tarzı özet paneli: Ara Toplam / KDV / Genel Toplam ──
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              boxShadow: TsGolge.yumusak,
            ),
            child: SafeArea(
              top: false,
              child: Column(children: [
                _OzetSatiri(baslik: 'Ürün Toplamı', deger: _genelToplam),
                _OzetSatiri(
                    baslik: 'Fiyata Dahil KDV (bilgi amaçlı)',
                    deger: _kdvToplam,
                    vurgusuz: true),
                const Divider(height: 16),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GENEL TOPLAM',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      Text(ParaUtils.formatla(_genelToplam),
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: TsRenk.primary)),
                    ]),
                const SizedBox(height: TsBosluk.md),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: TsRenk.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(TsRadius.md))),
                    onPressed: (_sepet.isEmpty || _kaydediliyor)
                        ? null
                        : _satisiTamamla,
                    icon: _kaydediliyor
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_kaydediliyor
                        ? 'Kaydediliyor...'
                        : 'Satışı Tamamla (Veresiye)'),
                  ),
                ),
              ]),
            ),
          ),
        ] else
          Expanded(
              child: TsBosDurum(
            ikon: Icons.storefront_outlined,
            baslik: 'Bayi seçilmedi',
            altyazi: 'Devam etmek için bir bayi/toptan müşteri seçin',
          )),
      ]),
    ));
  }
}
