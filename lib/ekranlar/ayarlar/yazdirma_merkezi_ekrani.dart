// lib/ekranlar/ayarlar/yazdirma_merkezi_ekrani.dart
//
// YAZDIRMA MERKEZİ — Tek Sayfa Yapısı
// ------------------------------------------------------------------
// Önceden 3 ayrı route'ta (yazici_ayar, fis_tasarim, fatura_ayar) dağınık
// duran yazıcı/fiş/fatura ayarları artık TEK ekranda, üst seviye 3 sekme
// (Yazıcılar / Fiş Tasarımı / Fatura Ayarları) altında toplanıyor.
//
// Her sekme, kendi iş mantığını koruyan mevcut ekran widget'ını `gomulu:
// true` parametresiyle BAŞLIKSIZ (kendi Scaffold/AppBar'ı olmadan) render
// eder — mevcut Bluetooth/WiFi tarama, PDF önizleme, e-Fatura kaydetme
// mantığı aynen çalışmaya devam eder, sadece görsel çatı birleşti.
// ------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'yazici_ayar_ekrani.dart';
import 'fis_tasarim_ekrani.dart';
import 'fatura_ayar_ekrani.dart';

class YazdirmaMerkeziEkrani extends StatefulWidget {
  /// Belirli bir sekmeyle açmak için: 0=Yazıcılar, 1=Fiş Tasarımı, 2=Fatura
  final int baslangicSekmesi;

  const YazdirmaMerkeziEkrani({super.key, this.baslangicSekmesi = 0});

  @override
  State<YazdirmaMerkeziEkrani> createState() => _YazdirmaMerkeziEkraniState();
}

class _YazdirmaMerkeziEkraniState extends State<YazdirmaMerkeziEkrani>
    with SingleTickerProviderStateMixin {
  late final TabController _ustTab;

  static const _sekmeler = [
    (ikon: Icons.print_outlined, baslik: 'Yazıcılar'),
    (ikon: Icons.receipt_long_outlined, baslik: 'Fiş Tasarımı'),
    (ikon: Icons.description_outlined, baslik: 'Fatura Ayarları'),
  ];

  @override
  void initState() {
    super.initState();
    _ustTab = TabController(
      length: _sekmeler.length,
      vsync: this,
      initialIndex: widget.baslangicSekmesi.clamp(0, _sekmeler.length - 1),
    );
  }

  @override
  void dispose() {
    _ustTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Yazdırma Merkezi',
        altBaslik: 'Yazıcı · Fiş · Fatura — tek sayfa',
        gradyanli: true,
      ),
      body: Column(
        children: [
          _ustSekmeBari(context),
          Expanded(
            child: TabBarView(
              controller: _ustTab,
              // Her sekme kendi state'ini korusun diye tembel değil,
              // AutomaticKeepAlive her alt ekranda zaten aktif
              // (ConsumerStatefulWidget varsayılanı).
              children: const [
                YaziciAyarEkrani(gomulu: true),
                FisTasarimEkrani(gomulu: true),
                FaturaAyarEkrani(gomulu: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ustSekmeBari(BuildContext context) => Container(
        color: TsRenk.primary,
        padding: const EdgeInsets.only(bottom: 2),
        child: TabBar(
          controller: _ustTab,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: TsMetin.govdeVurgu,
          tabs: [
            for (final s in _sekmeler)
              Tab(icon: Icon(s.ikon, size: 20), text: s.baslik),
          ],
        ),
      );
}
