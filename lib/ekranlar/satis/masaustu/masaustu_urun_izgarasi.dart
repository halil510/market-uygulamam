// lib/ekranlar/satis/masaustu/masaustu_urun_izgarasi.dart
//
// Masaüstü Hızlı Satış — alt bölüm: grup sekmeleri + resimli ürün tuşları.
// Kaynak: PLU panelindeki ürünler (ana_grup'a göre sekmeler). PLU'da ürün
// yoksa "Hızlı Tuşlar" (favoriler) gösterilir.
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../depolar/favori_urun_deposu.dart';
import '../../../depolar/urun_deposu.dart';
import '../../../modeller/urun_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../widgets/hizli_tus_paneli.dart' show tusRengi;

class MasaustuUrunIzgarasi extends StatefulWidget {
  final void Function(UrunModel urun) onUrunSec;
  const MasaustuUrunIzgarasi({super.key, required this.onUrunSec});

  @override
  State<MasaustuUrunIzgarasi> createState() => _MasaustuUrunIzgarasiState();
}

class _MasaustuUrunIzgarasiState extends State<MasaustuUrunIzgarasi> {
  static const _tumu = 'Tümü';
  List<UrunModel> _urunler = [];
  bool _yukleniyor = true;
  bool _favoriModu = false;
  String _grup = _tumu;
  bool _isleniyor = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      var liste = await UrunDeposu().pluUrunleriGrupluGetir();
      var favori = false;
      if (liste.isEmpty) {
        liste = await FavoriUrunDeposu().favorileriGetir();
        favori = true;
      }
      if (!mounted) return;
      setState(() {
        _urunler = liste;
        _favoriModu = favori;
        _yukleniyor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  String _grupAdi(UrunModel u) =>
      (u.anaGrup == null || u.anaGrup!.trim().isEmpty) ? 'Genel' : u.anaGrup!;

  List<String> get _gruplar {
    final set = <String>{};
    for (final u in _urunler) {
      set.add(_grupAdi(u));
    }
    return [_tumu, ...set];
  }

  void _sec(UrunModel u) {
    if (_isleniyor) return;
    _isleniyor = true;
    widget.onUrunSec(u);
    Future.delayed(const Duration(milliseconds: 300), () => _isleniyor = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    if (_urunler.isEmpty) {
      return Center(
        child: Text(
          "Hızlı satış ürünü yok.\nÜrün Listesi → PLU Yönetimi'nden ürün ekleyin.",
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textSecondary, height: 1.5),
        ),
      );
    }
    final gorunen = _grup == _tumu
        ? _urunler
        : _urunler.where((u) => _grupAdi(u) == _grup).toList();
    return Column(children: [
      _sekmeler(),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 124,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.92,
          ),
          itemCount: gorunen.length,
          itemBuilder: (_, i) => _tus(gorunen[i]),
        ),
      ),
    ]);
  }

  Widget _sekmeler() {
    final gruplar = _gruplar;
    return Container(
      height: 38,
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.borderColor))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          if (_favoriModu)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                  child: Text('Hızlı Tuşlar',
                      style: TextStyle(
                          color: context.textSecondary,
                          fontWeight: FontWeight.w600))),
            ),
          for (final g in gruplar)
            InkWell(
              onTap: () => setState(() => _grup = g),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: g == _grup ? TsRenk.primary : Colors.transparent,
                          width: 2.5)),
                ),
                child: Text(g,
                    style: TextStyle(
                        fontWeight: g == _grup ? FontWeight.w800 : FontWeight.w500,
                        color: g == _grup ? TsRenk.primary : context.textSecondary)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resim(UrunModel u, Color renk) {
    final yol = u.resimYolu;
    if (yol != null && yol.isNotEmpty && File(yol).existsSync()) {
      return Image.file(File(yol),
          fit: BoxFit.cover, errorBuilder: (_, _, _) => _bas(u, renk));
    }
    final url = u.resimUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(url,
          fit: BoxFit.cover, errorBuilder: (_, _, _) => _bas(u, renk));
    }
    return _bas(u, renk);
  }

  Widget _bas(UrunModel u, Color renk) => Container(
        color: renk.withValues(alpha: 0.16),
        alignment: Alignment.center,
        child: Text(u.urunAdi.isEmpty ? '?' : u.urunAdi[0].toUpperCase(),
            style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.w900, color: renk)),
      );

  Widget _tus(UrunModel u) {
    final renk = tusRengi(u.urunAdi);
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _sec(u),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(children: [
            Expanded(child: SizedBox.expand(child: _resim(u, renk))),
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
              child: Column(children: [
                Text(u.urunAdi,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary)),
                Text(ParaUtils.formatla(u.satisFiyati),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: TsRenk.primary)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
