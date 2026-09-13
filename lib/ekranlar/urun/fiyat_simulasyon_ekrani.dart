// lib/ekranlar/urun/fiyat_simulasyon_ekrani.dart
//
// FAZ 11 — Fiyat Simülasyonu (erp_roadmap madde 25). Ürün seçilip yeni
// bir fiyat/yüzde denendiğinde kâr etkisini gösterir. KESİNLİKLE
// önizlemedir — "Kaydet" butonu YOKTUR, gerçek satış fiyatına hiçbir
// şekilde yazmaz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/fiyat_simulasyon_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class FiyatSimulasyonuEkrani extends ConsumerStatefulWidget {
  const FiyatSimulasyonuEkrani({super.key});
  @override
  ConsumerState<FiyatSimulasyonuEkrani> createState() => _FiyatSimulasyonuEkraniState();
}

class _FiyatSimulasyonuEkraniState extends ConsumerState<FiyatSimulasyonuEkrani> {
  final _aramaCtrl = TextEditingController();
  final _yeniFiyatCtrl = TextEditingController();
  final _yuzdeCtrl = TextEditingController();
  List<UrunModel> _sonuclar = [];
  UrunModel? _secili;
  FiyatSimulasyonuSonuc? _sonuc;
  bool _araniyor = false;
  bool _hesaplaniyor = false;

  @override
  void dispose() {
    _aramaCtrl.dispose();
    _yeniFiyatCtrl.dispose();
    _yuzdeCtrl.dispose();
    super.dispose();
  }

  // 🔴 DÜZELTME (derin analizde bulundu): her tuş vuruşunda tetiklenen
  // bu async fonksiyonların sıralama/iptal koruması yoktu — kullanıcı
  // hızlı yazınca ("1"→"12"→"120"), yavaş tamamlanan ERKEN bir istek
  // geç tamamlanan sonucun üzerine yazabiliyordu (ekranda o an yazılan
  // değerle uyuşmayan bir sonuç görünebiliyordu). Basit bir sıra
  // numarası ile bayat cevaplar yok sayılıyor.
  int _aramaSira = 0;
  int _simulasyonSira = 0;

  Future<void> _ara(String sorgu) async {
    if (sorgu.trim().length < 2) {
      setState(() => _sonuclar = []);
      return;
    }
    final sira = ++_aramaSira;
    setState(() => _araniyor = true);
    final r = await UrunDeposu().ara(sorgu.trim(), limit: 15);
    if (mounted && sira == _aramaSira) setState(() { _sonuclar = r; _araniyor = false; });
  }

  void _urunSec(UrunModel u) {
    setState(() {
      _secili = u;
      _sonuclar = [];
      _aramaCtrl.text = u.urunAdi;
      _yeniFiyatCtrl.text = u.satisFiyati.toStringAsFixed(2);
      _yuzdeCtrl.clear();
      _sonuc = null;
    });
  }

  void _yuzdedenFiyatHesapla(String yuzdeStr) {
    final u = _secili;
    if (u == null) return;
    final yuzde = double.tryParse(yuzdeStr.replaceAll(',', '.'));
    if (yuzde == null) return;
    final yeni = u.satisFiyati * (1 + yuzde / 100);
    _yeniFiyatCtrl.text = yeni.toStringAsFixed(2);
    _simuleEt();
  }

  Future<void> _simuleEt() async {
    final u = _secili;
    final yeniFiyat = double.tryParse(_yeniFiyatCtrl.text.replaceAll(',', '.'));
    if (u == null || yeniFiyat == null || u.id == null) return;
    final sira = ++_simulasyonSira;
    setState(() => _hesaplaniyor = true);
    final sonuc = await FiyatSimulasyonuServisi().hesapla(
      urunId: u.id!,
      alisFiyat: u.alisFiyat,
      alisFiyatKdvDahil: u.alisFiyatKdvDahil,
      eskiFiyat: u.satisFiyati,
      yeniFiyat: yeniFiyat,
    );
    if (mounted && sira == _simulasyonSira) {
      setState(() { _sonuc = sonuc; _hesaplaniyor = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(baslik: 'Fiyat Simülasyonu', gradyanli: true),
      body: ListView(
        padding: const EdgeInsets.all(TsBosluk.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(TsBosluk.md),
            decoration: BoxDecoration(
              color: TsRenk.zemin(TsRenk.bilgi),
              borderRadius: BorderRadius.circular(TsRadius.md),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: TsRenk.bilgi, size: 18),
              const SizedBox(width: TsBosluk.sm),
              Expanded(
                child: Text(
                  'Bu bir ÖNİZLEMEDİR — hiçbir fiyat kaydedilmez/değişmez.',
                  style: TsMetin.kucuk.copyWith(color: TsRenk.bilgi),
                ),
              ),
            ]),
          ),
          const SizedBox(height: TsBosluk.lg),
          TextField(
            controller: _aramaCtrl,
            decoration: InputDecoration(
              labelText: 'Ürün Ara (ad/barkod)',
              border: const OutlineInputBorder(),
              suffixIcon: _araniyor
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : const Icon(Icons.search),
            ),
            onChanged: _ara,
          ),
          if (_sonuclar.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: TsBosluk.xs),
              decoration: BoxDecoration(
                color: TsRenk.kart(context),
                borderRadius: BorderRadius.circular(TsRadius.md),
                border: Border.all(color: TsRenk.ayirac(context)),
              ),
              child: Column(
                children: _sonuclar
                    .map((u) => ListTile(
                          dense: true,
                          title: Text(u.urunAdi),
                          subtitle: Text(ParaUtils.formatla(u.satisFiyati)),
                          onTap: () => _urunSec(u),
                        ))
                    .toList(),
              ),
            ),
          if (_secili != null) ...[
            const SizedBox(height: TsBosluk.lg),
            TsKart(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_secili!.urunAdi, style: TsMetin.baslikM),
                  const SizedBox(height: TsBosluk.xs),
                  Text('Mevcut fiyat: ${ParaUtils.formatla(_secili!.satisFiyati)}  ·  '
                      'Alış: ${ParaUtils.formatla(_secili!.alisFiyat)}  ·  '
                      'Mevcut kâr oranı: %${_secili!.karOrani.toStringAsFixed(1)}',
                      style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                  const SizedBox(height: TsBosluk.md),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _yuzdeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(
                            labelText: '% Değişim (ör. 10 veya -5)', border: OutlineInputBorder(), isDense: true),
                        onChanged: _yuzdedenFiyatHesapla,
                      ),
                    ),
                    const SizedBox(width: TsBosluk.sm),
                    Expanded(
                      child: TextField(
                        controller: _yeniFiyatCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Yeni Fiyat (₺)', border: OutlineInputBorder(), isDense: true),
                        onChanged: (_) => _simuleEt(),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
          if (_hesaplaniyor) const Padding(
            padding: EdgeInsets.symmetric(vertical: TsBosluk.xl),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: TsRenk.primary)),
          ),
          if (_sonuc != null && !_hesaplaniyor) ...[
            const SizedBox(height: TsBosluk.lg),
            _sonucKarti(_sonuc!),
          ],
        ],
      ),
    );
  }

  Widget _sonucKarti(FiyatSimulasyonuSonuc s) {
    final karArtti = s.yeniBirimKar >= s.eskiBirimKar;
    final renk = karArtti ? TsRenk.basarili : TsRenk.hata;
    return TsKart(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(karArtti ? Icons.trending_up : Icons.trending_down, color: renk),
            const SizedBox(width: TsBosluk.sm),
            Text('Simülasyon Sonucu', style: TsMetin.baslikM),
          ]),
          const SizedBox(height: TsBosluk.md),
          Row(children: [
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'Birim Kâr',
                    deger: ParaUtils.formatla(s.yeniBirimKar),
                    altDeger: '${karArtti ? '+' : ''}${ParaUtils.formatla(s.yeniBirimKar - s.eskiBirimKar)}',
                    ikon: const Icon(Icons.payments_outlined),
                    vurguRenk: renk)),
            const SizedBox(width: TsBosluk.sm),
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'Kâr Oranı',
                    deger: '%${s.yeniKarOrani.toStringAsFixed(1)}',
                    altDeger: '${karArtti ? '+' : ''}${(s.yeniKarOrani - s.eskiKarOrani).toStringAsFixed(1)} puan',
                    ikon: const Icon(Icons.percent),
                    vurguRenk: renk)),
          ]),
          if (s.aylikTahminiKarFarki != null) ...[
            const SizedBox(height: TsBosluk.sm),
            TsKart.istatistik(
              baslik: 'Aylık Tahmini Kâr Farkı (son 30 gün satış hızıyla)',
              deger:
                  '${s.aylikTahminiKarFarki! >= 0 ? '+' : ''}${ParaUtils.formatla(s.aylikTahminiKarFarki!)}',
              ikon: const Icon(Icons.calendar_month_outlined),
              vurguRenk: renk,
            ),
          ] else ...[
            const SizedBox(height: TsBosluk.sm),
            Text(
              'Son 30 günde satış geçmişi olmadığı için aylık etki tahmini hesaplanamadı.',
              style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context)),
            ),
          ],
          const SizedBox(height: TsBosluk.sm),
          Text(
            'Not: Fiyat değişikliğinin talebi nasıl etkileyeceği (esneklik) hesaba '
            'katılmaz — mevcut satış hızının AYNI kalacağı varsayılır.',
            style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context)),
          ),
        ],
      ),
    );
  }
}
