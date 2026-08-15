// lib/tasarim_sistemi/ts_liste.dart
//
// TEK LİSTE SİSTEMİ
// ------------------------------------------------------------------
// Daha önce 41 ekranda kendi ListView.builder'ı elle yazılıyordu; her
// birinin arama/boş-durum/yükleniyor/hata mantığı ayrı ayrı tekrarlanmıştı.
// Bundan sonra tüm liste ekranları (ürün, cari, personel, banka, borç,
// masa, satış geçmişi…) TsListe<T> üzerinden kurulur.
//
// Kullanım örneği:
//   TsListe<Urun>(
//     ogeler: urunler,
//     aramaMetniAl: (u) => u.ad,
//     kartOlustur: (context, u) => TsKart.liste(baslik: u.ad, ...),
//     yukleniyor: durum.yukleniyor,
//     hata: durum.hata,
//     yenile: () => ref.refresh(urunlerProvider),
//   )
// ------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'ts_token.dart';
import 'ts_bos_durum.dart';
import 'ts_yukleniyor.dart';

class TsListe<T> extends StatefulWidget {
  final List<T> ogeler;
  final Widget Function(BuildContext context, T oge, int index) kartOlustur;

  /// Arama kutusu için: bir öğeden aranabilir metni döndürür.
  /// null verilirse arama kutusu gösterilmez.
  final String Function(T oge)? aramaMetniAl;

  final bool yukleniyor;
  final String? hata;
  final Future<void> Function()? yenile;

  final String bosBaslik;
  final String? bosAltyazi;
  final IconData bosIkon;

  final EdgeInsetsGeometry padding;
  final Widget? ustWidget; // filtre çubuğu, toplam özet vb.
  final double aralarindaBosluk;
  final ScrollController? kaydirmaKontrolcusu;

  const TsListe({
    super.key,
    required this.ogeler,
    required this.kartOlustur,
    this.aramaMetniAl,
    this.yukleniyor = false,
    this.hata,
    this.yenile,
    this.bosBaslik = 'Kayıt bulunamadı',
    this.bosAltyazi,
    this.bosIkon = Icons.inbox_outlined,
    this.padding =
        const EdgeInsets.symmetric(horizontal: TsBosluk.lg, vertical: TsBosluk.sm),
    this.ustWidget,
    this.aralarindaBosluk = TsBosluk.sm,
    this.kaydirmaKontrolcusu,
  });

  @override
  State<TsListe<T>> createState() => _TsListeState<T>();
}

class _TsListeState<T> extends State<TsListe<T>> {
  final TextEditingController _aramaController = TextEditingController();
  String _aramaMetni = '';

  @override
  void dispose() {
    _aramaController.dispose();
    super.dispose();
  }

  List<T> get _filtrelenmis {
    if (widget.aramaMetniAl == null || _aramaMetni.trim().isEmpty) {
      return widget.ogeler;
    }
    final q = _aramaMetni.trim().toLowerCase();
    return widget.ogeler
        .where((o) => widget.aramaMetniAl!(o).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.yukleniyor) return const TsYukleniyor();

    if (widget.hata != null) {
      return TsBosDurum(
        ikon: Icons.error_outline,
        baslik: 'Bir hata oluştu',
        altyazi: widget.hata,
        renk: TsRenk.hata,
        aksiyonMetni: widget.yenile != null ? 'Tekrar dene' : null,
        aksiyon: widget.yenile,
      );
    }

    final liste = _filtrelenmis;

    Widget govde = liste.isEmpty
        ? TsBosDurum(
            ikon: widget.bosIkon,
            baslik: _aramaMetni.isNotEmpty ? 'Sonuç bulunamadı' : widget.bosBaslik,
            altyazi: _aramaMetni.isNotEmpty
                ? '"$_aramaMetni" için sonuç yok'
                : widget.bosAltyazi,
          )
        : ListView.separated(
            controller: widget.kaydirmaKontrolcusu,
            padding: widget.padding,
            itemCount: liste.length,
            separatorBuilder: (_, __) =>
                SizedBox(height: widget.aralarindaBosluk),
            itemBuilder: (context, i) =>
                widget.kartOlustur(context, liste[i], i),
          );

    if (widget.yenile != null) {
      govde = RefreshIndicator(onRefresh: widget.yenile!, child: govde);
    }

    return Column(
      children: [
        if (widget.aramaMetniAl != null) _aramaCubugu(context),
        if (widget.ustWidget != null) widget.ustWidget!,
        Expanded(child: govde),
      ],
    );
  }

  Widget _aramaCubugu(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            TsBosluk.lg, TsBosluk.sm, TsBosluk.lg, TsBosluk.sm),
        child: TextField(
          controller: _aramaController,
          onChanged: (v) => setState(() => _aramaMetni = v),
          decoration: InputDecoration(
            hintText: 'Ara...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _aramaMetni.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _aramaController.clear();
                      setState(() => _aramaMetni = '');
                    },
                  )
                : null,
            isDense: true,
            filled: true,
            fillColor: TsRenk.arkaplan(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TsRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );
}
