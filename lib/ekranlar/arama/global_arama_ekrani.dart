// lib/ekranlar/arama/global_arama_ekrani.dart
//
// erp_roadmap_yeni_ekranlar.md madde 23 — Global Arama. Ürün/cari/
// satış/fatura/masa'yı tek kutudan arayıp doğrudan detay ekranına
// gitmek için. Salt-okunur, hiçbir veriye yazmıyor.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../servisler/global_arama_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class GlobalAramaEkrani extends StatefulWidget {
  const GlobalAramaEkrani({super.key});
  @override
  State<GlobalAramaEkrani> createState() => _GlobalAramaEkraniState();
}

class _GlobalAramaEkraniState extends State<GlobalAramaEkrani> {
  final _servis = GlobalAramaServisi();
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _sorguSira = 0;
  List<GlobalAramaSonucu> _sonuclar = [];
  bool _araniyor = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _metinDegisti(String metin) {
    _debounce?.cancel();
    if (metin.trim().length < 2) {
      setState(() { _sonuclar = []; _araniyor = false; });
      return;
    }
    setState(() => _araniyor = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _ara(metin));
  }

  Future<void> _ara(String metin) async {
    final sira = ++_sorguSira;
    final sonuc = await _servis.ara(metin);
    // Hızlı yazımda önceki (yavaş dönen) sorgunun sonucu, sonraki
    // sorgunun sonucunun üzerine YAZMASIN diye sıra numarası guard'ı
    // (fiyat_simulasyon_ekrani.dart'ta bu turda kurulan aynı desen).
    if (!mounted || sira != _sorguSira) return;
    setState(() { _sonuclar = sonuc; _araniyor = false; });
  }

  IconData _ikon(GlobalAramaTuru t) => switch (t) {
        GlobalAramaTuru.urun => Icons.inventory_2_outlined,
        GlobalAramaTuru.cari => Icons.people_outline,
        GlobalAramaTuru.satis => Icons.receipt_long_outlined,
        GlobalAramaTuru.fatura => Icons.description_outlined,
        GlobalAramaTuru.masa => Icons.table_restaurant_outlined,
      };

  void _git(GlobalAramaSonucu s) {
    switch (s.tur) {
      case GlobalAramaTuru.urun:
        context.push('/urun/detay/${s.id}');
        break;
      case GlobalAramaTuru.cari:
        context.push('/cari/detay/${s.id}');
        break;
      case GlobalAramaTuru.satis:
        context.push('/satis/detay/${s.id}');
        break;
      case GlobalAramaTuru.fatura:
        context.push('/fatura/detay/${s.id}');
        break;
      case GlobalAramaTuru.masa:
        context.push('/masa/detay/${s.id}');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        gradyanli: true,
        baslikWidget: TextField(
          controller: _ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Ürün, cari, fiş, fatura, masa ara...',
            hintStyle: const TextStyle(color: Colors.white70, fontSize: 14),
            border: InputBorder.none,
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                    onPressed: () {
                      _ctrl.clear();
                      _metinDegisti('');
                    },
                  ),
          ),
          onChanged: _metinDegisti,
        ),
      ),
      body: _govde(),
    );
  }

  Widget _govde() {
    if (_ctrl.text.trim().length < 2) {
      return const TsBosDurum(
        ikon: Icons.search,
        baslik: 'Aramaya başlayın',
        altyazi: 'En az 2 karakter girin — ürün adı/barkod, cari adı/telefon,\nfiş/fatura no veya masa adı arayabilirsiniz.',
      );
    }
    if (_araniyor) return const TsYukleniyor();
    if (_sonuclar.isEmpty) {
      return TsBosDurum(
        ikon: Icons.search_off,
        baslik: '"${_ctrl.text.trim()}" için sonuç bulunamadı',
      );
    }

    final gruplar = <GlobalAramaTuru, List<GlobalAramaSonucu>>{};
    for (final s in _sonuclar) {
      gruplar.putIfAbsent(s.tur, () => []).add(s);
    }
    const baslikSira = [
      GlobalAramaTuru.urun,
      GlobalAramaTuru.cari,
      GlobalAramaTuru.satis,
      GlobalAramaTuru.fatura,
      GlobalAramaTuru.masa,
    ];
    const baslikEtiket = {
      GlobalAramaTuru.urun: 'Ürünler',
      GlobalAramaTuru.cari: 'Cariler',
      GlobalAramaTuru.satis: 'Satışlar',
      GlobalAramaTuru.fatura: 'Faturalar',
      GlobalAramaTuru.masa: 'Masalar',
    };

    return ListView(
      padding: const EdgeInsets.all(TsBosluk.lg),
      children: [
        for (final tur in baslikSira)
          if (gruplar[tur]?.isNotEmpty ?? false) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: TsBosluk.sm, top: TsBosluk.sm),
              child: Text(baslikEtiket[tur]!,
                  style: TsMetin.kucuk.copyWith(
                      color: TsRenk.metinIkincil(context), fontWeight: FontWeight.w700)),
            ),
            ...gruplar[tur]!.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                  child: TsKart.liste(
                    ikon: Icon(_ikon(s.tur)),
                    baslik: s.baslik,
                    altBaslik: s.altBaslik,
                    onTap: () => _git(s),
                  ),
                )),
          ],
      ],
    );
  }
}
