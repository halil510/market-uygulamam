// lib/ekranlar/rapor/masaustu/urun_rapor_masaustu_gorunum.dart
//
// Ürün Raporu — masaüstü (geniş pencere) görünümü: filtre çubuğu, özet
// şeridi, sıralanabilir tablo, alt şerit (Excel / Yenile). Çift tık ürün
// detayını açar (sadece "Ürün bazlı" gruplamada).
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../cekirdek/utils/para_utils.dart';
import '../../../depolar/urun_rapor_deposu.dart';
import '../../../servisler/bildirim_servisi.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';
import '../urun_rapor_filtre_cubugu.dart';
import '../urun_rapor_ortak.dart';

class UrunRaporMasaustuGorunum extends ConsumerStatefulWidget {
  final UrunRaporTuru tur;
  const UrunRaporMasaustuGorunum({super.key, required this.tur});

  @override
  ConsumerState<UrunRaporMasaustuGorunum> createState() =>
      _UrunRaporMasaustuGorunumState();
}

class _UrunRaporMasaustuGorunumState
    extends ConsumerState<UrunRaporMasaustuGorunum> {
  UrunRaporSatir? _secili;

  bool get _satis => widget.tur == UrunRaporTuru.satis;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tus);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tus);
    super.dispose();
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!ekranUstte(context)) return false;
    // İki sekme de ağaçta yaşar; sadece görünür (aktif) olan tepki versin.
    if (!TickerMode.valuesOf(context).enabled) return false;
    if (e.logicalKey == LogicalKeyboardKey.f5) {
      ref.invalidate(urunRaporSonucProvider(widget.tur));
    } else if (e.logicalKey == LogicalKeyboardKey.f9) {
      final s = ref.read(urunRaporSonucProvider(widget.tur)).value;
      if (s != null) _excel(s);
    } else {
      return false;
    }
    return true;
  }

  List<TabloKolon<UrunRaporSatir>> _kolonlar(UrunRaporGruplama g) => [
        TabloKolon(
            baslik: g.etiket,
            genislik: 260,
            esnek: true,
            deger: (r) => r.ad,
            sirala: (r) => r.ad.toLowerCase()),
        TabloKolon(
            baslik: g == UrunRaporGruplama.urun ? 'Barkod / Kod' : 'Çeşit',
            genislik: 130,
            deger: (r) => r.alt,
            sirala: (r) => r.alt),
        if (g == UrunRaporGruplama.urun) ...[
          TabloKolon(
              baslik: 'Ana Grup',
              genislik: 120,
              deger: (r) => r.anaGrup,
              sirala: (r) => r.anaGrup.toLowerCase()),
          TabloKolon(
              baslik: 'Marka',
              genislik: 120,
              deger: (r) => r.marka,
              sirala: (r) => r.marka.toLowerCase()),
        ],
        TabloKolon(
            baslik: 'Miktar',
            genislik: 90,
            sagaYasli: true,
            deger: (r) => urunRaporMiktarYaz(r.miktar),
            sirala: (r) => r.miktar),
        TabloKolon(
            baslik: _satis ? 'Ciro (KDV dahil)' : 'Alım Tutarı',
            genislik: 130,
            sagaYasli: true,
            deger: (r) => ParaUtils.formatla(r.tutar, simge: ''),
            sirala: (r) => r.tutar),
        TabloKolon(
            baslik: 'Ort. Birim Fiyat',
            genislik: 115,
            sagaYasli: true,
            deger: (r) => ParaUtils.formatla(r.ortBirimFiyat, simge: ''),
            sirala: (r) => r.ortBirimFiyat),
        if (_satis) ...[
          TabloKolon(
              baslik: 'Maliyet',
              genislik: 110,
              sagaYasli: true,
              deger: (r) => ParaUtils.formatla(r.maliyet, simge: ''),
              sirala: (r) => r.maliyet),
          TabloKolon(
              baslik: 'Kâr',
              genislik: 110,
              sagaYasli: true,
              deger: (r) => ParaUtils.formatla(r.kar, simge: ''),
              sirala: (r) => r.kar,
              renk: (r) => r.kar < 0 ? TsRenk.hata : const Color(0xFF2E7D32)),
          TabloKolon(
              baslik: 'Marj %',
              genislik: 80,
              sagaYasli: true,
              deger: (r) => r.karMarji.toStringAsFixed(1),
              sirala: (r) => r.karMarji),
        ],
        TabloKolon(
            baslik: 'Fiş',
            genislik: 70,
            sagaYasli: true,
            deger: (r) => '${r.fisSayisi}',
            sirala: (r) => r.fisSayisi),
      ];

  Future<void> _excel(UrunRaporSonuc s) async {
    try {
      await urunRaporExcelAktar(
          tur: widget.tur, filtre: ref.read(urunRaporFiltreProvider), sonuc: s);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtre = ref.watch(urunRaporFiltreProvider);
    final async = ref.watch(urunRaporSonucProvider(widget.tur));
    final sonuc = async.value;

    return Column(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: UrunRaporFiltreCubugu(masaustu: true),
      ),
      Expanded(
        child: async.when(
          loading: () => const TsYukleniyor(iskelet: true),
          error: (e, _) => TsBosDurum(
              ikon: Icons.error_outline,
              baslik: 'Yüklenemedi: $e',
              renk: TsRenk.hata),
          data: (s) => s.satirlar.isEmpty
              ? TsBosDurum(
                  ikon: Icons.inbox_outlined,
                  baslik: _satis
                      ? 'Bu filtrelerle satış bulunamadı'
                      : 'Bu filtrelerle alım bulunamadı')
              : MasaustuTablo<UrunRaporSatir>(
                  satirlar: s.satirlar,
                  kolonlar: _kolonlar(filtre.gruplama),
                  secili: _secili,
                  onSec: (r) => setState(() => _secili = r),
                  onCift: filtre.gruplama == UrunRaporGruplama.urun
                      ? (r) => context.push('/urun/detay/${r.anahtar}')
                      : null,
                ),
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Kayıt', '${sonuc?.satirlar.length ?? 0}'),
          AltOzet('Fiş', '${sonuc?.fisSayisi ?? 0}'),
          AltOzet('Miktar', urunRaporMiktarYaz(sonuc?.toplamMiktar ?? 0)),
          AltOzet(_satis ? 'Ciro' : 'Alım Tutarı',
              ParaUtils.formatla(sonuc?.toplamTutar ?? 0)),
          if (_satis) ...[
            AltOzet('Maliyet', ParaUtils.formatla(sonuc?.toplamMaliyet ?? 0)),
            AltOzet('Brüt Kâr', ParaUtils.formatla(sonuc?.toplamKar ?? 0),
                renk: (sonuc?.toplamKar ?? 0) < 0
                    ? TsRenk.hata
                    : const Color(0xFF2E7D32)),
          ],
        ],
        tuslar: [
          AltTus('F5', 'Yenile', Icons.refresh, const Color(0xFF1565C0),
              () => ref.invalidate(urunRaporSonucProvider(widget.tur))),
          AltTus('F9', 'Excel', Icons.table_view, const Color(0xFF2E7D32),
              sonuc == null ? null : () => _excel(sonuc)),
        ],
      ),
    ]);
  }
}
