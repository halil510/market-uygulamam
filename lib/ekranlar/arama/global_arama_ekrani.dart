// lib/ekranlar/arama/global_arama_ekrani.dart
//
// erp_roadmap_yeni_ekranlar.md madde 23 — Global Arama. Ürün/cari/
// satış/fatura/masa'yı tek kutudan arayıp doğrudan detay ekranına
// gitmek için. Salt-okunur, hiçbir veriye yazmıyor.
//
// Kullanıcı isteği: "ai asistanı dashboard'da arama ve konuşmayla o
// sayfayı gidip veya değerlendirme gibi daha iyi olmazmı" — bu ekran
// artık SADECE literal (birebir metin) eşleşme aramıyor; aynı kutudan
// 🎤 sesle de yazılabiliyor, ve altta her zaman "Yapay Zekaya Sor"
// seçeneği duruyor. AiServisi().sor() zaten (ai_sohbet_servisi.dart)
// hem gezinme komutlarını ("ürün ekle git" gibi) hem rapor/değerlendirme
// sorularını ("bu ayın net karı", "kritik stoklar" gibi) destekliyor —
// burada TEKRAR yazılmadı, olduğu gibi yeniden kullanıldı.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../servisler/global_arama_servisi.dart';
import '../../servisler/ai_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/ortak/mikrofon_butonu.dart';

class GlobalAramaEkrani extends StatefulWidget {
  const GlobalAramaEkrani({super.key});
  @override
  State<GlobalAramaEkrani> createState() => _GlobalAramaEkraniState();
}

class _GlobalAramaEkraniState extends State<GlobalAramaEkrani> {
  final _servis = GlobalAramaServisi();
  final _ai = AiServisi();
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _sorguSira = 0;
  List<GlobalAramaSonucu> _sonuclar = [];
  bool _araniyor = false;

  AiSohbetSonuc? _aiSonuc;
  bool _aiSoruluyor = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _metinDegisti(String metin) {
    _debounce?.cancel();
    // Yeni bir arama başlıyor — önceki AI cevabı artık bu metne ait değil.
    if (_aiSonuc != null || _aiSoruluyor) {
      setState(() { _aiSonuc = null; _aiSoruluyor = false; });
    }
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

  /// Sesle söylenen metni arama kutusuna yazar ve aramayı/gezinmeyi
  /// tetikler — "konuşmayla o sayfaya gidip" isteğinin karşılığı.
  void _sesleGeldi(String metin) {
    _ctrl.text = metin;
    _ctrl.selection = TextSelection.collapsed(offset: metin.length);
    _metinDegisti(metin);
  }

  Future<void> _aiyaSor() async {
    final soru = _ctrl.text.trim();
    if (soru.isEmpty || _aiSoruluyor) return;
    setState(() { _aiSoruluyor = true; _aiSonuc = null; });
    try {
      final sonuc = await _ai.sor(soru);
      if (!mounted) return;
      setState(() { _aiSonuc = sonuc; _aiSoruluyor = false; });
      // ai_panel_ekrani.dart'taki AYNI desen: AI bir gezinme komutu
      // algıladıysa (sonuc.rota doluysa), kullanıcı cevabı bir an
      // okuyabilsin diye kısa bir gecikmeyle GERÇEKTEN o ekrana gidiliyor.
      if (sonuc.rota != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        const sekmeKokleri = {'/', '/satis', '/urun', '/cari'};
        if (sekmeKokleri.contains(sonuc.rota)) {
          context.go(sonuc.rota!, extra: sonuc.aramaTerimi);
        } else {
          context.push(sonuc.rota!, extra: sonuc.aramaTerimi);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiSonuc = AiSohbetSonuc(cevap: 'Bir hata oluştu: $e');
        _aiSoruluyor = false;
      });
    }
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
            hintText: 'Ara, ya da konuşarak sor...',
            hintStyle: const TextStyle(color: Colors.white70, fontSize: 14),
            // 🔴🔴 KRİTİK DÜZELTME (cari_liste_ekrani.dart'taki AYNI
            // kullanıcı bulgusunun, 2026-09-22, yan etkisi): global
            // inputDecorationTheme TÜM TextField'lara varsayılan olarak
            // `filled: true, fillColor: AppRenkler.background` (açık
            // temada neredeyse beyaz) uyguluyor — bu alan bunu hiç
            // ezmediği için beyaz yazı, gradyanlı AppBar'ın ÜSTÜNE binen
            // neredeyse-beyaz bir dolgu üstünde görünmez oluyordu.
            filled: false,
            border: InputBorder.none,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_ctrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                    onPressed: () {
                      _ctrl.clear();
                      _metinDegisti('');
                    },
                  ),
                Theme(
                  // MikrofonButonu varsayılan (koyu) ikon rengiyle geliyor —
                  // bu AppBar beyaz üzerine gradyanlı olduğu için ikonun
                  // beyaz görünmesi gerekiyor.
                  data: Theme.of(context).copyWith(
                    iconTheme: const IconThemeData(color: Colors.white70)),
                  child: MikrofonButonu(
                    ipucu: 'Konuşarak arayın',
                    onMetin: _sesleGeldi,
                  ),
                ),
              ],
            ),
          ),
          onChanged: _metinDegisti,
          onSubmitted: (_) => _aiyaSor(),
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
        altyazi: 'En az 2 karakter girin — ürün adı/barkod, cari adı/telefon,\n'
            'fiş/fatura no veya masa adı arayabilirsiniz.\n\n'
            'Ya da 🎤 ile konuşarak "ürün ekle git" veya "bu ayın net karı"\n'
            'gibi bir komut/soru sorabilirsiniz.',
      );
    }
    if (_araniyor) return const TsYukleniyor();

    return ListView(
      padding: const EdgeInsets.all(TsBosluk.lg),
      children: [
        _aiSorKarti(),
        if (_aiSonuc != null) ...[
          const SizedBox(height: TsBosluk.md),
          _aiCevapKarti(_aiSonuc!),
        ],
        const SizedBox(height: TsBosluk.lg),
        if (_sonuclar.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TsBosDurum(
              ikon: Icons.search_off,
              baslik: '"${_ctrl.text.trim()}" için kayıt bulunamadı',
              altyazi: 'Yukarıdan yapay zekaya da sorabilirsiniz.',
            ),
          )
        else
          ..._sonucListesi(),
      ],
    );
  }

  /// "Yapay Zekaya Sor" — hem gezinme komutları ("cari ekle git") hem
  /// değerlendirme/rapor soruları ("bu ayın net karı", "kritik stoklar")
  /// için tek giriş noktası. Literal sonuç olsun olmasın HER ZAMAN
  /// görünür — kullanıcı ürün ararken de aklına gelen bir rapor
  /// sorusunu sorabilsin diye.
  Widget _aiSorKarti() {
    final soru = _ctrl.text.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(TsRadius.lg),
        onTap: _aiSoruluyor ? null : _aiyaSor,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [TsRenk.primary, TsRenk.primaryKoyu],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(TsRadius.lg),
            boxShadow: TsGolge.renkli(TsRenk.primary),
          ),
          child: Row(children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Yapay Zekaya Sor: "$soru"',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_aiSoruluyor)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
            else
              const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _aiCevapKarti(AiSohbetSonuc sonuc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(TsRadius.lg),
        border: Border.all(color: TsRenk.ayirac(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.smart_toy_outlined, size: 16, color: TsRenk.primary),
          const SizedBox(width: 6),
          Text('Yapay Zeka Asistanı',
              style: TsMetin.kucukVurgu.copyWith(color: TsRenk.primary)),
        ]),
        const SizedBox(height: 8),
        SelectableText(
          sonuc.cevap,
          style: TextStyle(
              fontSize: 13, height: 1.5, color: TsRenk.metinBirincil(context)),
        ),
      ]),
    );
  }

  List<Widget> _sonucListesi() {
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

    return [
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
    ];
  }
}
