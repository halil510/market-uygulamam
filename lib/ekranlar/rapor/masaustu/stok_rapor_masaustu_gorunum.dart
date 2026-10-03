// lib/ekranlar/rapor/masaustu/stok_rapor_masaustu_gorunum.dart
//
// Stok Raporu — masaüstü (geniş pencere) görünümü: filtreler (ana grup,
// marka, durum, arama), KPI şeridi, tüm aktif ürünlerin tablosu
// (çift tık = ürün detayı) ve alt şerit (F5 Yenile / F9 Excel).
import 'dart:async';
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../cekirdek/utils/dosya_paylasim.dart';
import '../../../cekirdek/utils/excel_guvenlik_utils.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../depolar/urun_rapor_deposu.dart';
import '../../../servisler/bildirim_servisi.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';
import '../urun_rapor_ortak.dart';

class StokRaporMasaustuGorunum extends ConsumerStatefulWidget {
  const StokRaporMasaustuGorunum({super.key});

  @override
  ConsumerState<StokRaporMasaustuGorunum> createState() =>
      _StokRaporMasaustuGorunumState();
}

class _StokRaporMasaustuGorunumState
    extends ConsumerState<StokRaporMasaustuGorunum> {
  final _depo = UrunRaporDeposu();
  final _aramaC = TextEditingController();
  Timer? _debounce;

  String? _anaGrup;
  String? _marka;
  StokDurum? _durum;
  String _arama = '';

  late Future<List<StokRaporSatir>> _veri = _yukle();
  StokRaporSatir? _secili;
  List<StokRaporSatir> _son = const [];

  Future<List<StokRaporSatir>> _yukle() async {
    final l = await _depo.stokListesi(
        anaGrup: _anaGrup, marka: _marka, durum: _durum, arama: _arama);
    _son = l;
    return l;
  }

  void _yenile() => setState(() => _veri = _yukle());

  static String _durumAd(StokDurum d) => switch (d) {
        StokDurum.saglikli => 'Sağlıklı',
        StokDurum.kritik => 'Kritik',
        StokDurum.stoksuz => 'Stoksuz',
      };

  static Color _durumRenk(StokDurum d) => switch (d) {
        StokDurum.saglikli => const Color(0xFF2E7D32),
        StokDurum.kritik => const Color(0xFFEF6C00),
        StokDurum.stoksuz => TsRenk.hata,
      };

  late final List<TabloKolon<StokRaporSatir>> _kolonlar = [
    TabloKolon(
        baslik: 'Barkod / Kod',
        genislik: 130,
        deger: (s) => s.kod,
        sirala: (s) => s.kod),
    TabloKolon(
        baslik: 'Ürün',
        genislik: 240,
        esnek: true,
        deger: (s) => s.ad,
        sirala: (s) => s.ad.toLowerCase()),
    TabloKolon(
        baslik: 'Ana Grup',
        genislik: 120,
        deger: (s) => s.anaGrup,
        sirala: (s) => s.anaGrup.toLowerCase()),
    TabloKolon(
        baslik: 'Marka',
        genislik: 110,
        deger: (s) => s.marka,
        sirala: (s) => s.marka.toLowerCase()),
    TabloKolon(
        baslik: 'Stok',
        genislik: 90,
        sagaYasli: true,
        deger: (s) => urunRaporMiktarYaz(s.stok),
        sirala: (s) => s.stok,
        renk: (s) => s.stok <= 0 ? TsRenk.hata : null),
    TabloKolon(
        baslik: 'Birim',
        genislik: 60,
        deger: (s) => s.birim,
        sirala: (s) => s.birim),
    TabloKolon(
        baslik: 'Min.',
        genislik: 70,
        sagaYasli: true,
        deger: (s) => s.minimumStok > 0 ? urunRaporMiktarYaz(s.minimumStok) : '',
        sirala: (s) => s.minimumStok),
    TabloKolon(
        baslik: 'Alış (KDV hariç)',
        genislik: 120,
        sagaYasli: true,
        deger: (s) => ParaUtils.formatla(s.alisFiyat, simge: ''),
        sirala: (s) => s.alisFiyat),
    TabloKolon(
        baslik: 'Stok Değeri',
        genislik: 115,
        sagaYasli: true,
        deger: (s) => ParaUtils.formatla(s.stokDegeri, simge: ''),
        sirala: (s) => s.stokDegeri),
    TabloKolon(
        baslik: 'Satış (KDV dahil)',
        genislik: 120,
        sagaYasli: true,
        deger: (s) => ParaUtils.formatla(s.satisFiyat, simge: ''),
        sirala: (s) => s.satisFiyat),
    TabloKolon(
        baslik: 'Durum',
        genislik: 90,
        deger: (s) => _durumAd(s.durum),
        sirala: (s) => s.durum.index,
        renk: (s) => _durumRenk(s.durum)),
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tus);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tus);
    _debounce?.cancel();
    _aramaC.dispose();
    super.dispose();
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (e.logicalKey == LogicalKeyboardKey.f5) {
      _yenile();
    } else if (e.logicalKey == LogicalKeyboardKey.f9) {
      _excel(_son);
    } else {
      return false;
    }
    return true;
  }

  Future<void> _excel(List<StokRaporSatir> l) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Stok'];
      excel.delete('Sheet1');
      sheet.appendRow([
        for (final b in [
          'Barkod/Kod', 'Ürün', 'Ana Grup', 'Marka', 'Stok', 'Birim', 'Min. Stok',
          'Alış (KDV hariç)', 'Stok Değeri', 'Satış (KDV dahil)', 'Durum'
        ])
          TextCellValue(b)
      ]);
      for (final s in l) {
        sheet.appendRow([
          TextCellValue(excelIcinGuvenliMetin(s.kod)),
          TextCellValue(excelIcinGuvenliMetin(s.ad)),
          TextCellValue(excelIcinGuvenliMetin(s.anaGrup)),
          TextCellValue(excelIcinGuvenliMetin(s.marka)),
          DoubleCellValue(s.stok),
          TextCellValue(s.birim),
          DoubleCellValue(s.minimumStok),
          DoubleCellValue(s.alisFiyat),
          DoubleCellValue(s.stokDegeri),
          DoubleCellValue(s.satisFiyat),
          TextCellValue(_durumAd(s.durum)),
        ]);
      }
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/stok_raporu_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await File(path).writeAsBytes(excel.encode()!);
      await DosyaPaylasim.paylas(
          ShareParams(files: [XFile(path)], text: 'Stok Raporu'));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  Future<void> _anaGrupSec() async {
    final liste = await ref.read(urunRaporAnaGruplarProvider.future);
    if (!mounted) return;
    final s = await urunRaporSecimPenceresi<String>(context,
        baslik: 'Ana Grup', ogeler: liste, etiket: (e) => e);
    if (s == null) return;
    _anaGrup = s.temizle ? null : s.secim;
    _yenile();
  }

  Future<void> _markaSec() async {
    final liste = await ref.read(urunRaporMarkalarProvider.future);
    if (!mounted) return;
    final s = await urunRaporSecimPenceresi<String>(context,
        baslik: 'Marka', ogeler: liste, etiket: (e) => e);
    if (s == null) return;
    _marka = s.temizle ? null : s.secim;
    _yenile();
  }

  Widget _kpi(String baslik, String deger, Color renk) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(baslik,
                style: TextStyle(fontSize: 11.5, color: TsRenk.metinIkincil(context))),
            const SizedBox(height: 2),
            Text(deger,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: renk)),
          ]),
        ),
      );

  Widget _cip(IconData ikon, String metin,
          {required VoidCallback onTap, bool aktif = false, VoidCallback? temizle}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InputChip(
          avatar: Icon(ikon, size: 16),
          label: Text(metin),
          selected: aktif,
          showCheckmark: false,
          onPressed: onTap,
          onDeleted: temizle,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Row(children: [
          _cip(Icons.category_outlined, _anaGrup ?? 'Ana Grup',
              onTap: _anaGrupSec,
              aktif: _anaGrup != null,
              temizle: _anaGrup == null
                  ? null
                  : () {
                      _anaGrup = null;
                      _yenile();
                    }),
          _cip(Icons.sell_outlined, _marka ?? 'Marka',
              onTap: _markaSec,
              aktif: _marka != null,
              temizle: _marka == null
                  ? null
                  : () {
                      _marka = null;
                      _yenile();
                    }),
          const SizedBox(width: 6),
          for (final d in [null, ...StokDurum.values])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(d == null ? 'Tümü' : _durumAd(d)),
                selected: _durum == d,
                onSelected: (_) {
                  _durum = d;
                  _yenile();
                },
              ),
            ),
          const Spacer(),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _aramaC,
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Ürün adı / barkod / kod ara…',
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  _arama = v;
                  _yenile();
                });
              },
            ),
          ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<StokRaporSatir>>(
          future: _veri,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const TsYukleniyor(iskelet: true);
            }
            if (snap.hasError) {
              return TsBosDurum(
                  ikon: Icons.error_outline,
                  baslik: 'Yüklenemedi: ${snap.error}',
                  renk: TsRenk.hata,
                  aksiyonMetni: 'Tekrar dene',
                  aksiyon: _yenile);
            }
            final l = snap.data!;
            final stokDeger = l.fold<double>(0, (a, s) => a + s.stokDegeri);
            final satisDeger = l.fold<double>(0, (a, s) => a + s.satisDegeri);
            final kritik = l.where((s) => s.durum == StokDurum.kritik).length;
            final stoksuz = l.where((s) => s.durum == StokDurum.stoksuz).length;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 4, 8),
                child: Row(children: [
                  _kpi('Ürün (listelenen)', '${l.length}', Colors.blue.shade700),
                  _kpi('Stok Değeri (Alış)', ParaUtils.formatla(stokDeger),
                      Colors.indigo.shade700),
                  _kpi('Satış Değeri (KDV dahil)', ParaUtils.formatla(satisDeger),
                      Colors.green.shade700),
                  _kpi('Kritik', '$kritik', const Color(0xFFEF6C00)),
                  _kpi('Stoksuz', '$stoksuz', TsRenk.hata),
                ]),
              ),
              Expanded(
                child: l.isEmpty
                    ? const TsBosDurum(
                        ikon: Icons.inventory_2_outlined,
                        baslik: 'Bu filtrelerle ürün bulunamadı')
                    : MasaustuTablo<StokRaporSatir>(
                        satirlar: l,
                        kolonlar: _kolonlar,
                        secili: _secili,
                        onSec: (s) => setState(() => _secili = s),
                        onCift: (s) => context.push('/urun/detay/${s.id}'),
                      ),
              ),
              MasaustuAltSerit(
                ozetler: [
                  AltOzet('Ürün', '${l.length}'),
                  AltOzet('Stok Değeri', ParaUtils.formatla(stokDeger)),
                  AltOzet('Satış Değeri', ParaUtils.formatla(satisDeger)),
                ],
                tuslar: [
                  AltTus('F5', 'Yenile', Icons.refresh, const Color(0xFF1565C0),
                      _yenile),
                  AltTus('F9', 'Excel', Icons.table_view, const Color(0xFF2E7D32),
                      l.isEmpty ? null : () => _excel(l)),
                ],
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}
