// lib/ekranlar/satis/sicak_soguk_satis_ekrani.dart
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../servisler/barkod_servisi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/sepet_provider.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/urun_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

enum SatisTipi { sicak, soguk }

class SicakSogukSatisEkrani extends ConsumerStatefulWidget {
  final SatisTipi tip;
  const SicakSogukSatisEkrani({super.key, this.tip = SatisTipi.sicak});
  @override
  ConsumerState<SicakSogukSatisEkrani> createState() => _SicakSogukSatisEkraniState();
}

class _SicakSogukSatisEkraniState extends ConsumerState<SicakSogukSatisEkrani> {
  CariModel? _seciliCari;
  List<UrunModel> _urunler = [];
  final _araCtrl = TextEditingController();
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _urunYukle();
    _araCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _araCtrl.dispose(); super.dispose(); }

  Future<void> _urunYukle() async {
    try {
      final u = await UrunDeposu().tumunuGetir();
      if (mounted) setState(() { _urunler = u; _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  List<UrunModel> get _filtrelenmis {
    final q = _araCtrl.text.toLowerCase();
    if (q.isEmpty) return _urunler;
    return _urunler.where((u) =>
        u.urunAdi.toLowerCase().contains(q) ||
        (u.barkod?.contains(q) ?? false)).toList();
  }

  bool get _sicak => widget.tip == SatisTipi.sicak;

  @override
  Widget build(BuildContext context) {
    final sepet = ref.watch(sepetProvider);
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Row(children: [
          Icon(_sicak ? Icons.local_fire_department : Icons.ac_unit, size: 20),
          const SizedBox(width: 8),
          Text(_sicak ? 'Sıcak Satış' : 'Soğuk Satış'),
        ]),
        aksiyonlar: [
          if (!sepet.bos) Stack(alignment: Alignment.topRight, children: [
            IconButton(icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () => context.go('/satis')),
            Container(
              margin: const EdgeInsets.only(right: 6, top: 6),
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
              child: Text('${sepet.kalemSayisi}',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black))),
          ]),
        ],
      ),
      body: Column(children: [
        // Cari + arama
        Container(color: TsRenk.kart(context), padding: const EdgeInsets.all(12),
          child: Column(children: [
            // Cari seçim
            GestureDetector(
              onTap: () async {
                final cariler = ref.read(carilerProvider).musteriler;
                if (!mounted) return;
                final secilen = await showDialog<CariModel>(context: context,
                  builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Müşteri Seç'),
                    content: SizedBox(height: 300, width: double.maxFinite,
                      child: ListView.builder(
                        itemCount: cariler.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          title: Text(cariler[i].unvan),
                          subtitle: Text(cariler[i].telefon ?? ''),
                          onTap: () => Navigator.pop(ctx, cariler[i])))),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal'))],
                  ));
                if (secilen != null) {
                  setState(() => _seciliCari = secilen);
                  ref.read(sepetProvider.notifier).musteriSec(secilen);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: _seciliCari != null ? TsRenk.zemin(TsRenk.basarili) : TsRenk.arkaplan(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _seciliCari != null
                        ? Colors.green.shade300 : TsRenk.ayirac(context))),
                child: Row(children: [
                  Icon(_seciliCari != null ? Icons.person : Icons.person_add_outlined,
                      color: _seciliCari != null ? Colors.green : context.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    _seciliCari?.unvan ?? 'Müşteri Seç',
                    style: TextStyle(fontWeight: FontWeight.w500,
                        color: _seciliCari != null ? Colors.green.shade700 : TsRenk.metinIkincil(context)))),
                  Icon(Icons.chevron_right, color: context.textSecondary, size: 18),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            // Arama
            TextField(
              controller: _araCtrl,
              decoration: InputDecoration(
                hintText: 'Ürün ara...',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true, fillColor: TsRenk.arkaplan(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_araCtrl.text.isNotEmpty)
                    IconButton(icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() => _araCtrl.clear())),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                    tooltip: 'Barkod Tara',
                    onPressed: () async {
                      final b = await BarkodServisi().barkodTara(context);
                      if (b != null && mounted) setState(() => _araCtrl.text = b);
                    }),
                ]),
              ),
            ),
          ]),
        ),

        // Ürün listesi
        Expanded(child: _yukleniyor
          ? const Center(child: const AppYukleniyor())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              itemCount: _filtrelenmis.length,
              itemBuilder: (_, i) {
                final u = _filtrelenmis[i];
                final kalemIdx = sepet.kalemler.indexWhere((k) => k.urun.id == u.id);
                final miktar   = kalemIdx >= 0 ? sepet.kalemler[kalemIdx].miktar : 0.0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: miktar > 0 ? TsRenk.zemin(TsRenk.basarili) : TsRenk.kart(context),
                    borderRadius: BorderRadius.circular(12),
                    border: miktar > 0 ? Border.all(color: Colors.green.shade300) : null,
                    boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.urunAdi, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('${ParaUtils.formatla(u.satisFiyati)} · Stok: ${u.stok.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                    ])),
                    if (miktar > 0) Row(children: [
                      GestureDetector(
                        onTap: () => ref.read(sepetProvider.notifier).miktarGuncelle(kalemIdx, miktar - 1),
                        child: Container(width: 30, height: 30,
                            decoration: BoxDecoration(color: TsRenk.zemin(TsRenk.hata), shape: BoxShape.circle),
                            child: const Icon(Icons.remove, size: 16, color: Colors.red))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(miktar.toStringAsFixed(0),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                      GestureDetector(
                        onTap: () => ref.read(sepetProvider.notifier).miktarGuncelle(kalemIdx, miktar + 1),
                        child: Container(width: 30, height: 30,
                            decoration: BoxDecoration(color: TsRenk.zemin(TsRenk.basarili), shape: BoxShape.circle),
                            child: const Icon(Icons.add, size: 16, color: Colors.green))),
                    ])
                    else GestureDetector(
                      onTap: () => ref.read(sepetProvider.notifier).ekle(u),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                            color: _sicak ? Colors.red.shade600 : AppRenkler.primary,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Text('Ekle',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                    ),
                  ]),
                );
              },
            )),
      ]),
      // Sepet bottom bar
      bottomNavigationBar: sepet.bos ? null : Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
            color: TsRenk.kart(context),
            boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 8)]),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${sepet.kalemSayisi} ürün',
                style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
            Text(ParaUtils.formatla(sepet.genelToplam),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
          const SizedBox(width: 16),
          Expanded(child: FilledButton.icon(
            onPressed: () => context.go('/satis'),
            icon: const Icon(Icons.shopping_cart_checkout),
            label: const Text('Sepete Git'),
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white,
          backgroundColor: _sicak ? Colors.red.shade700 : AppRenkler.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
        ]),
      ),
    );
  }
}
