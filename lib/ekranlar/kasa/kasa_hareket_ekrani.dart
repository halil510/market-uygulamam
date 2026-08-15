// lib/ekranlar/kasa/kasa_hareket_ekrani.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../depolar/kasa_deposu.dart';
import '../../saglayicilar/riverpod/kasa_rapor_provider.dart';
import '../../modeller/kasa_hareket_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class KasaHareketEkrani extends ConsumerStatefulWidget {
  const KasaHareketEkrani({super.key});
  @override
  ConsumerState<KasaHareketEkrani> createState() => _KasaHareketEkraniState();
}

class _KasaHareketEkraniState extends ConsumerState<KasaHareketEkrani> {
  final _depo = KasaDeposu();
  List<KasaHareketModel> _hareketler = [];
  bool _yukleniyor = true;
  double _bakiye = 0;
  Map<String, double> _gunlukOzet = {'giris': 0, 'cikis': 0};

  
@override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _yukle()); }

  Future<void> _yukle() async {
    _yukleniyor = true;

    if (mounted) setState(() {});
    try {
      final results = await Future.wait([
        _depo.guncelBakiye(),
        _depo.hareketleriniGetir(limit: 100),
        _depo.gunlukOzet(),
      ]);
      if (!mounted) return;
        _bakiye        = results[0] as double;
        _hareketler    = results[1] as List<KasaHareketModel>;
        _gunlukOzet    = results[2] as Map<String, double>;
        _yukleniyor    = false;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _hareketEkle() async {
    String tip = 'Tahsilat';
    final ctrl  = TextEditingController();
    final acCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Kasa Hareketi'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: tip,
            decoration: const InputDecoration(labelText: 'Hareket Tipi', border: OutlineInputBorder()),
            items: ['Tahsilat', 'Ödeme', 'Gider', 'Banka Ödemesi', 'Kasa Sayım', 'AçılışKasa', 'KapanışKasa']
                .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => ss(() => tip = v!),
          ),
          const SizedBox(height: 10),
          TextField(controller: ctrl, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Tutar (₺)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: acCtrl, decoration: const InputDecoration(labelText: 'Açıklama', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      )),
    );
    if (ok != true) return;
    final tutar = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
    if (tutar <= 0) return;
    await _depo.hareketEkle(KasaHareketModel(
      hareketTipi: tip, tutar: tutar,
      tarih: DateTime.now(),
      aciklama: acCtrl.text.trim().isEmpty ? tip : acCtrl.text.trim(),
    ));
    await _yukle();
    // Aynı sınıf sorun: bu ekranın kendi listesi yenileniyordu ama
    // başka bir ekranda açık olabilecek Kasa Raporu yenilenmiyordu.
    ref.invalidate(kasaRaporProvider);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    final girisToplam  = _gunlukOzet['giris'] ?? 0;
    final cikisToplam  = _gunlukOzet['cikis'] ?? 0;

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Kasa Hareketleri',
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'Hareket Ekle', onPressed: _hareketEkle),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _yukle),
        ],
        geriTusu: false,
        gradyanli: false,
      ),
      body: Column(children: [
        // Bakiye + özet
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [TsRenk.primaryKoyu, TsRenk.primary],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            const Text('Güncel Bakiye', style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 4),
            Text(ParaUtils.formatla(_bakiye),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _ozetKart('Bugün Giriş', girisToplam, Colors.greenAccent)),
              const SizedBox(width: 12),
              Expanded(child: _ozetKart('Bugün Çıkış', cikisToplam, Colors.redAccent)),
              const SizedBox(width: 12),
              Expanded(child: _ozetKart('Net', girisToplam - cikisToplam,
                  girisToplam >= cikisToplam ? Colors.lightGreenAccent : Colors.orangeAccent)),
            ]),
          ]),
        ),
        Expanded(child: _yukleniyor
          ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: TsRenk.primary))
          : _hareketler.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 56, color: context.textHint),
                  const SizedBox(height: 12),
                  Text('Henüz hareket yok', style: TextStyle(color: context.textSecondary)),
                ]))
              : RefreshIndicator(onRefresh: _yukle,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _hareketler.length,
                    itemBuilder: (_, i) {
                      final h = _hareketler[i];
                      final giris = KasaHareketModel.girisMi(h.hareketTipi);
                      final renk = giris ? Colors.green : Colors.red;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: TsKart.liste(
                          ikon: Icon(giris ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: renk),
                          baslik: h.aciklama ?? h.hareketTipi,
                          altBaslik: fmt.format(h.tarih),
                          etiketler: [TsBadge(metin: h.hareketTipi, tur: giris ? TsBadgeTuru.basarili : TsBadgeTuru.hata)],
                          sagAksiyon: Column(mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('${giris ? '+' : '-'}${ParaUtils.formatla(h.tutar)}',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: renk)),
                            if (h.bakiyeSonrasi != null)
                              Text(ParaUtils.formatla(h.bakiyeSonrasi!),
                                  style: TextStyle(fontSize: 10, color: context.textSecondary)),
                          ]),
                        ),
                      );
                    },
                  )),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: _hareketEkle,
        icon: const Icon(Icons.add),
        label: const Text('Hareket Ekle'),
      ),
    );
  }

  Widget _ozetKart(String label, double val, Color renk) => Column(children: [
    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    const SizedBox(height: 2),
    Text(ParaUtils.formatla(val),
        style: TextStyle(color: renk, fontSize: 13, fontWeight: FontWeight.w700)),
  ]);
}
