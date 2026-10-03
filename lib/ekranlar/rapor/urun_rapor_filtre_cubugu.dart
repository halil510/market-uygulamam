// lib/ekranlar/rapor/urun_rapor_filtre_cubugu.dart
//
// Ürün Raporu filtre çubuğu: dönem, ana grup, marka, cari, gruplama, arama.
// Mobil ve masaüstü aynı çubuğu kullanır; [masaustu] true iken tek satırda
// yan yana, false iken yatay kaydırılabilir çip şeridi olarak çizilir.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../depolar/urun_rapor_deposu.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'urun_rapor_ortak.dart';

class UrunRaporFiltreCubugu extends ConsumerStatefulWidget {
  final bool masaustu;
  const UrunRaporFiltreCubugu({super.key, this.masaustu = false});

  @override
  ConsumerState<UrunRaporFiltreCubugu> createState() =>
      _UrunRaporFiltreCubuguState();
}

class _UrunRaporFiltreCubuguState extends ConsumerState<UrunRaporFiltreCubugu> {
  final _aramaC = TextEditingController();
  Timer? _debounce;
  final _fmt = DateFormat('dd.MM.yyyy');

  @override
  void initState() {
    super.initState();
    _aramaC.text = ref.read(urunRaporFiltreProvider).arama;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _aramaC.dispose();
    super.dispose();
  }

  void _guncelle(UrunRaporFiltre Function(UrunRaporFiltre f) fn) {
    final n = ref.read(urunRaporFiltreProvider.notifier);
    n.state = fn(n.state);
  }

  Future<void> _donemSec() async {
    final f = ref.read(urunRaporFiltreProvider);
    final secilen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final d in urunRaporDonemler)
            ListTile(
              title: Text(d),
              trailing: urunRaporAktifDonem(f) == d ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, d),
            ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Özel aralık…'),
            onTap: () => Navigator.pop(ctx, 'ozel'),
          ),
        ]),
      ),
    );
    if (secilen == null || !mounted) return;
    if (secilen == 'ozel') {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        initialDateRange: DateTimeRange(start: f.bas, end: f.bit),
        locale: const Locale('tr', 'TR'),
      );
      if (r != null) _guncelle((x) => x.kopya(bas: r.start, bit: r.end));
    } else {
      final a = urunRaporDonemAraligi(secilen);
      if (a != null) _guncelle((x) => x.kopya(bas: a.$1, bit: a.$2));
    }
  }

  Future<void> _anaGrupSec() async {
    final liste = await ref.read(urunRaporAnaGruplarProvider.future);
    if (!mounted) return;
    final s = await urunRaporSecimPenceresi<String>(context,
        baslik: 'Ana Grup', ogeler: liste, etiket: (e) => e);
    if (s == null) return;
    _guncelle((x) => s.temizle
        ? x.kopya(anaGrupTemizle: true)
        : x.kopya(anaGrup: s.secim));
  }

  Future<void> _markaSec() async {
    final liste = await ref.read(urunRaporMarkalarProvider.future);
    if (!mounted) return;
    final s = await urunRaporSecimPenceresi<String>(context,
        baslik: 'Marka', ogeler: liste, etiket: (e) => e);
    if (s == null) return;
    _guncelle(
        (x) => s.temizle ? x.kopya(markaTemizle: true) : x.kopya(marka: s.secim));
  }

  Future<void> _cariSec() async {
    final liste = await ref.read(urunRaporCarilerProvider.future);
    if (!mounted) return;
    final s = await urunRaporSecimPenceresi<({int id, String unvan})>(context,
        baslik: 'Cari', ogeler: liste, etiket: (e) => e.unvan);
    if (s == null) return;
    _guncelle((x) =>
        s.temizle ? x.kopya(cariTemizle: true) : x.kopya(cariId: s.secim!.id));
  }

  Future<void> _gruplamaSec() async {
    final f = ref.read(urunRaporFiltreProvider);
    final g = await showModalBottomSheet<UrunRaporGruplama>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(
              title: Text('Gruplama', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final g in UrunRaporGruplama.values)
            ListTile(
              title: Text('${g.etiket} bazlı'),
              trailing: f.gruplama == g ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, g),
            ),
        ]),
      ),
    );
    if (g != null) _guncelle((x) => x.kopya(gruplama: g));
  }

  Widget _cip(IconData ikon, String metin,
      {required VoidCallback onTap, bool aktif = false, VoidCallback? temizle}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        avatar: Icon(ikon, size: 16),
        label: Text(metin, overflow: TextOverflow.ellipsis),
        selected: aktif,
        showCheckmark: false,
        onPressed: onTap,
        onDeleted: temizle,
        deleteIcon: temizle == null ? null : const Icon(Icons.close, size: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(urunRaporFiltreProvider);
    final cariler = ref.watch(urunRaporCarilerProvider).value;
    final cariAd = f.cariId == null
        ? null
        : cariler?.where((c) => c.id == f.cariId).firstOrNull?.unvan ?? 'Cari';
    final donem = urunRaporAktifDonem(f) ??
        '${_fmt.format(f.bas)} - ${_fmt.format(f.bit)}';

    final cipler = <Widget>[
      _cip(Icons.calendar_today, donem, onTap: _donemSec, aktif: true),
      _cip(Icons.category_outlined, f.anaGrup ?? 'Ana Grup',
          onTap: _anaGrupSec,
          aktif: f.anaGrup != null,
          temizle: f.anaGrup == null
              ? null
              : () => _guncelle((x) => x.kopya(anaGrupTemizle: true))),
      _cip(Icons.sell_outlined, f.marka ?? 'Marka',
          onTap: _markaSec,
          aktif: f.marka != null,
          temizle: f.marka == null
              ? null
              : () => _guncelle((x) => x.kopya(markaTemizle: true))),
      _cip(Icons.person_outline, cariAd ?? 'Cari',
          onTap: _cariSec,
          aktif: f.cariId != null,
          temizle: f.cariId == null
              ? null
              : () => _guncelle((x) => x.kopya(cariTemizle: true))),
      _cip(Icons.account_tree_outlined, '${f.gruplama.etiket} bazlı',
          onTap: _gruplamaSec),
    ];

    final arama = TextField(
      controller: _aramaC,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Ürün adı / barkod / kod ara…',
        filled: false,
        suffixIcon: _aramaC.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _aramaC.clear();
                  _guncelle((x) => x.kopya(arama: ''));
                  setState(() {});
                }),
      ),
      onChanged: (v) {
        setState(() {});
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350),
            () => _guncelle((x) => x.kopya(arama: v)));
      },
    );

    if (widget.masaustu) {
      return Row(children: [
        Expanded(child: Wrap(runSpacing: 6, children: cipler)),
        const SizedBox(width: 12),
        SizedBox(width: 280, child: arama),
      ]);
    }
    return Column(children: [
      SingleChildScrollView(
          scrollDirection: Axis.horizontal, child: Row(children: cipler)),
      const SizedBox(height: TsBosluk.sm),
      arama,
    ]);
  }
}
