// lib/ekranlar/barkod/raf_etiket_penceresi.dart
//
// Etiket önizleme penceresi: listedeki ürünlerin etiketleri SEÇİLİ tasarımla, basılacağı gibi (PDF) görünür.
// Tasarım burada değiştirilirse seçim kalıcı olur (liste ve ürün ekranlarındaki yazdır düğmeleri de onu kullanır).
// Basma, ürün ekranlarındaki "Etiket yazdır" düğmesiyle AYNI yoldan (etiketleriBas → EtiketBaskiServisi) yapılır;
// yazıcı ayarları da ortak panelden (EtiketYaziciPaneli) değiştirilir.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../cekirdek/etiket/raf_etiket_sablonlari.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/etiket_ayarlari.dart';
import '../../servisler/etiket_baski_servisi.dart';
import '../../servisler/raf_etiket_pdf_servisi.dart';
import '../../servisler/yazdirma_servisi.dart';
import 'etiket_ortak.dart';

/// Ürünler (adetleriyle) için önizleme penceresini açar.
Future<void> rafEtiketPenceresiAc(BuildContext context, List<(UrunModel, int)> kalemler) async {
  if (kalemler.isEmpty) return;
  final tasarimlar = await EtiketAyarlari.tumTasarimlar();
  final secili = await EtiketAyarlari.seciliTasarim();
  final ayar = await EtiketAyarlari.yaziciYukle();
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => RafEtiketPenceresi(kalemler: kalemler, tasarimlar: tasarimlar, sablon: secili, ayar: ayar),
  ));
}

class RafEtiketPenceresi extends StatefulWidget {
  final List<(UrunModel, int)> kalemler;
  final List<EtiketSablonu> tasarimlar;
  final EtiketSablonu sablon;
  final EtiketYaziciAyari ayar;
  const RafEtiketPenceresi({super.key, required this.kalemler, required this.tasarimlar, required this.sablon, required this.ayar});

  @override
  State<RafEtiketPenceresi> createState() => _RafEtiketPenceresiState();
}

class _RafEtiketPenceresiState extends State<RafEtiketPenceresi> {
  final _yazdirma = YazdirmaServisi();
  late EtiketSablonu _sablon = widget.sablon;
  late EtiketYaziciAyari _ayar = widget.ayar;
  bool _basiliyor = false;

  @override
  void initState() {
    super.initState();
    EtiketAyarlari.degisti.addListener(_ayarDegisti);
    _yazdirma.ayarlariYukle().then((_) {
      if (mounted) setState(() {}); // firma adı, bağlı yazıcı
    });
  }

  @override
  void dispose() {
    EtiketAyarlari.degisti.removeListener(_ayarDegisti);
    super.dispose();
  }

  Future<void> _ayarDegisti() async {
    final a = await EtiketAyarlari.yaziciYukle();
    if (mounted) setState(() => _ayar = a);
  }

  bool get _windows => !kIsWeb && Platform.isWindows;

  Future<Uint8List> _pdf() {
    final (:basilacak, denetim: _) = EtiketBaskiServisi.hazirla(widget.kalemler, _sablon);
    return RafEtiketPdfServisi.pdf(basilacak, _sablon,
        kagit: _ayar.etkinKagit, mensei: _ayar.mensei, firma: _yazdirma.firmaAdiOnizleme);
  }

  Future<void> _bas() async {
    if (_basiliyor) return;
    setState(() => _basiliyor = true);
    try {
      await etiketleriBas(context, widget.kalemler, sablon: _sablon);
    } finally {
      if (mounted) setState(() => _basiliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final genis = MediaQuery.sizeOf(context).width >= 900;
    final onizleme = PdfPreview(
      key: ValueKey('${tasarimImzasi(_sablon)}|${_ayar.etkinKagit}|${_ayar.mensei}|${_yazdirma.firmaAdiOnizleme}'),
      build: (_) => _pdf(),
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      // Windows'ta eklentinin yazdır düğmesi etiket yazıcısı sürücüsünün ayarlarını bozuyor (boş etiket): kendi düğmemizle basılır.
      allowPrinting: !_windows,
      pdfFileName: 'etiketler.pdf',
      maxPageWidth: _ayar.etkinKagit == RafEtiketKagidi.rulo ? 520 : 800,
    );
    return Scaffold(
      appBar: AppBar(title: Text('Etiket önizleme (${widget.kalemler.length} ürün)')),
      body: genis
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 380, child: _secenekler(context)),
              const VerticalDivider(width: 1),
              Expanded(child: onizleme),
            ])
          : Column(children: [
              SizedBox(height: MediaQuery.sizeOf(context).height * .42, child: _secenekler(context)),
              const Divider(height: 1),
              Expanded(child: onizleme),
            ]),
    );
  }

  Widget _secenekler(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (:basilacak, :denetim) = EtiketBaskiServisi.hazirla(widget.kalemler, _sablon);
    final toplam = basilacak.length;
    final bagli = _yazdirma.bagliMi ? _yazdirma.baglantiDurumu : null;
    return ListView(padding: const EdgeInsets.all(14), children: [
      DropdownButtonFormField<String>(
        initialValue: _sablon.id,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Etiket tasarımı', border: OutlineInputBorder(), isDense: true),
        items: [
          for (final s in widget.tasarimlar)
            DropdownMenuItem(
              value: s.id,
              child: Text('${s.kendi ? '★ ' : ''}${s.ad}  ·  ${s.olcu}', overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() => _sablon = EtiketAyarlari.tasarimBul(widget.tasarimlar, v));
          EtiketAyarlari.tasarimSec(v); // seçim kalıcı: liste ve ürün ekranları da bunu basar
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Text(_sablon.kendi ? 'Kendi tasarımınız' : 'Hazır şablon (BarTender: ${_sablon.dosya})',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ),
      const SizedBox(height: 14),
      Text('${denetim.basilacak.length} ürün · $toplam etiket', style: const TextStyle(fontWeight: FontWeight.w700)),
      if (denetim.atlanan.isNotEmpty) _uyari(Icons.block, cs.error, '${denetim.atlanan.length} ürün BASILMAYACAK', denetim.atlanan),
      if (denetim.birimFiyatsiz.isNotEmpty)
        _uyari(
          Icons.warning_amber,
          Colors.orange.shade800,
          '${denetim.birimFiyatsiz.length} üründe birim fiyat boş kalacak',
          denetim.birimFiyatsiz,
          aciklama: 'Ürün adında gramaj (ör. 500 GR, 1,5 LT) bulunamadı ya da adda paket / adet bilgisi var. '
              'Ürün kartına Ağırlık (gr) girin; birimi KG / LT olan üründe satış fiyatı birim fiyattır.',
        ),
      const SizedBox(height: 16),
      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.print_outlined),
          title: const Text('Yazıcı', style: TextStyle(fontSize: 12)),
          subtitle: Text(_ayar.ozet(bagliYazici: bagli), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          trailing: TextButton(onPressed: () => etiketYaziciAyarDialogu(context), child: const Text('Değiştir')),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: toplam > 0 && !_basiliyor ? _bas : null,
        icon: _basiliyor
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.print),
        label: Text('$toplam etiket bas', overflow: TextOverflow.ellipsis),
      ),
    ]);
  }

  Widget _uyari(IconData ikon, Color renk, String baslik, List<String> satirlar, {String? aciklama}) {
    const ilk = 8;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        leading: Icon(ikon, color: renk),
        title: Text(baslik, style: TextStyle(color: renk, fontWeight: FontWeight.w600, fontSize: 14)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (aciklama != null)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(aciklama, style: const TextStyle(fontSize: 12))),
          for (final s in satirlar.take(ilk)) Text('• $s', style: const TextStyle(fontSize: 12)),
          if (satirlar.length > ilk) Text('… ve ${satirlar.length - ilk} ürün daha', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
