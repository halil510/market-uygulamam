// lib/ekranlar/stok/stok_liste_ekrani.dart
// Performans düzeltmeleri:
//  - Arama: tumunuGetir() + client-side filter → _depo.ara() DB sorgusu
//  - Sayfalı yükleme (sayfaliGetir) korundu, arama artık DB'ye gidiyor
//  - Timer dispose zaten vardı (korundu)
import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/barkod_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/excel_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class StokListeEkrani extends ConsumerStatefulWidget {
  const StokListeEkrani({super.key});
  @override
  ConsumerState<StokListeEkrani> createState() => _StokListeEkraniState();
}

class _StokListeEkraniState extends ConsumerState<StokListeEkrani>
    with SingleTickerProviderStateMixin {
  final _depo      = UrunDeposu();
  final _barkodSrv = BarkodServisi();
  final _excelSrv  = ExcelServisi();

  late TabController _tab;

  List<UrunModel> _gosterilenler = [];
  List<UrunModel> _kritikler     = [];
  Set<int>        _seciliUrunler = {};
  bool            _secimModu     = false;

  final _aramaCtrl  = TextEditingController();
  final _aramaFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  Timer? _aramaDebounce;

  bool   _yukleniyor      = true;
  bool   _sayfaYukleniyor = false;
  bool   _dahaFazla       = true;
  int    _sayfa           = 0;
  static const int _sayfaBoyutu = 50;
  bool   _aramaYapiliyor  = false;
  String _aramaMetni      = '';
  String? _seciliGrup;
  int    _aramaId         = 0; // Yarış durumu önleyici

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _aramaCtrl.addListener(_onAramaChanged);
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle(reset: true));
  }

  @override
  void dispose() {
    _aramaDebounce?.cancel();
    _aramaCtrl.dispose();
    _aramaFocus.dispose();
    _scrollCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _yukle({bool reset = false}) async {
    if (_sayfaYukleniyor && !reset) return;
    if (!reset && !_dahaFazla) return;

    if (reset) {
      // Tek setState — çoklu setState önlendi
      _sayfa = 0;
      _dahaFazla = true;
      _gosterilenler = [];
    }

    if (!mounted) return;
    setState(() { _yukleniyor = reset; _sayfaYukleniyor = true; });

    try {
      final aramaId = ++_aramaId;
      List<UrunModel> yeni;

      if (_aramaYapiliyor && _aramaMetni.isNotEmpty) {
        // DB sorgusu — bellekte tüm liste yok
        yeni = await _depo.ara(_aramaMetni);
        _dahaFazla = false;
      } else {
        yeni = await _depo.sayfaliGetir(
          _sayfa * _sayfaBoyutu,
          _sayfaBoyutu,
          grup: _seciliGrup,
        );
        _dahaFazla = yeni.length >= _sayfaBoyutu;
        _sayfa++;
      }

      final kritikler = await _depo.kritikStoklar();

      if (!mounted || aramaId != _aramaId) return;
      setState(() {
        if (reset || _aramaYapiliyor) {
          _gosterilenler = yeni;
        } else {
          _gosterilenler = [..._gosterilenler, ...yeni];
        }
        _kritikler       = kritikler;
        _yukleniyor      = false;
        _sayfaYukleniyor = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _yukleniyor = false; _sayfaYukleniyor = false; });
      BildirimServisi.hata(context, 'Yükleme hatası: $e');
    }
  }

  void _onAramaChanged() {
    _aramaDebounce?.cancel();
    final q = _aramaCtrl.text.trim();
    if (q.isEmpty) {
      if (_aramaYapiliyor) {
        _aramaYapiliyor = false;
        _aramaMetni     = '';
        _yukle(reset: true);
      }
      return;
    }
    _aramaDebounce = Timer(const Duration(milliseconds: 300), () {
      _aramaYapiliyor = true;
      _aramaMetni     = q;
      _yukle(reset: true);
    });
  }

  void _onScroll() {
    if (_sayfaYukleniyor || !_dahaFazla || _aramaYapiliyor) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _yukle();
    }
  }

  void _secimDegistir(int id) => setState(() {
    if (_seciliUrunler.contains(id)) {
      _seciliUrunler.remove(id);
      if (_seciliUrunler.isEmpty) _secimModu = false;
    } else {
      _seciliUrunler.add(id);
    }
  });

  Future<void> _topluExcel() async {
    final urunler = _seciliUrunler.isEmpty
        ? _gosterilenler
        : _gosterilenler.where((u) => _seciliUrunler.contains(u.id)).toList();
    if (urunler.isEmpty) return;
    try {
      final yol = await _excelSrv.urunleriExcelEAktar(urunler);
      await _excelSrv.paylasExcel(yol);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: _secimModu
            ? Text('${_seciliUrunler.length} seçili')
            : const Text('Stok Listesi'),
        aksiyonlar: [
          if (_secimModu) ...[
            IconButton(
                icon: Image.asset("assets/images/excel_icon.png", width: 22, height: 22, errorBuilder: (_, __, ___) => const Icon(Icons.table_chart)),
                tooltip: 'Excel',
                onPressed: _topluExcel),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                if (!mounted) return;
                setState(() { _seciliUrunler.clear(); _secimModu = false; });
              },
            ),
          ] else ...[
            IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _yukle(reset: true)),
          ],
        ],
        alt: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Tümü'),
            Tab(text: 'Kritik'),
            Tab(text: 'Tükenen'),
          ],
        ),
        geriTusu: false,
      ),
      body: Column(children: [
        // Arama
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller:  _aramaCtrl,
            focusNode:   _aramaFocus,
            decoration: InputDecoration(
              hintText:    'Ürün adı, barkod veya grup ara...',
              prefixIcon:  const Icon(Icons.search),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_aramaCtrl.text.isNotEmpty)
                    IconButton(icon: const Icon(Icons.clear, size: 16),
                      onPressed: () { _aramaCtrl.clear(); _aramaYapiliyor = false; _aramaMetni = ''; _yukle(reset: true); }),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                    tooltip: 'Barkod Tara',
                    onPressed: () async {
                      final b = await BarkodServisi().barkodTara(context);
                      if (b == null || !mounted) return;

                      // Direkt DB'den ara
                      final urun = await UrunDeposu().barkodlaGetir(b);
                      if (!mounted) return;

                      if (urun != null) {
                        // Bulundu — listede göster
                        _aramaCtrl.text = b;
                        setState(() { _aramaYapiliyor = true; _aramaMetni = b; });
                        _yukle(reset: true);
                      } else {
                        // Bulunamadı — direkt ürün ekle
                        final ok = await context.push<bool>(
                          '/urun/ekle',
                          extra: {'barkod': b, 'kaynak': 'stok_liste'},
                        );
                        if (ok == true && mounted) {
                          _aramaCtrl.clear();
                          setState(() => _aramaMetni = '');
                          _yukle(reset: true);
                        }
                      }
                    }),
                ]),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        // Grup filtresi chip'i
        if (_seciliGrup != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Wrap(children: [
              FilterChip(
                label: Text(_seciliGrup!),
                selected: true,
                onSelected: (_) {},
                onDeleted: () {
                  _seciliGrup = null;
                  if (mounted) setState(() {});
                  _yukle(reset: true);
                },
              ),
            ]),
          ),
        // Liste
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _stokListesi(_gosterilenler),
              _stokListesi(_kritikler),
              _stokListesi(
                  _gosterilenler.where((u) => u.stok <= 0).toList()),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _stokListesi(List<UrunModel> liste) {
    if (_yukleniyor) {
      return const TsYukleniyor();
    }
    if (liste.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off_rounded, size: 56, color: context.textHint),
        const SizedBox(height: 12),
        Text('Ürün bulunamadı', style: TextStyle(color: context.textSecondary, fontSize: 15)),
        const SizedBox(height: 16),
        if (_aramaMetni.isNotEmpty)
          FilledButton.icon(
            onPressed: () async {
              final ok = await context.push<bool>('/urun/ekle',
                extra: {'barkod': _aramaMetni, 'kaynak': 'stok_liste'});
              if (ok == true && mounted) _yukle();
            },
            icon: const Icon(Icons.add),
            label: const Text('Yeni Ürün Ekle'),
          ),
      ]));
    }
    return ListView.builder(
      controller: _scrollCtrl,
      itemCount: liste.length + (_sayfaYukleniyor ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == liste.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: const AppYukleniyor()),
          );
        }
        final u = liste[i];
        final stokRenk = u.stok <= 0
            ? Colors.red
            : u.minimumStok > 0 && u.stok <= u.minimumStok
                ? Colors.orange
                : Colors.green;

        return RepaintBoundary(
          child: TsKart.liste(
            secili: _seciliUrunler.contains(u.id),
            onTap: _secimModu
                ? () => _secimDegistir(u.id!)
                : () => context.push('/urun/detay/${u.id}'),
            onLongPress: () {
              if (!_secimModu) setState(() => _secimModu = true);
              _secimDegistir(u.id!);
            },
            ikon: _secimModu
                ? Checkbox(
                    value: _seciliUrunler.contains(u.id),
                    onChanged: (_) => _secimDegistir(u.id!),
                  )
                : Text(
                    u.urunAdi.isNotEmpty ? u.urunAdi[0] : '?',
                    style: TextStyle(color: stokRenk, fontWeight: FontWeight.bold),
                  ),
            baslik: u.urunAdi,
            altBaslik: '${u.barkod ?? u.kod ?? ''} · ${u.anaGrup ?? ''}',
            sagAksiyon: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${u.stok.toStringAsFixed(u.stok % 1 == 0 ? 0 : 2)} ${u.birimAdi}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: stokRenk,
                        fontSize: 13),
                  ),
                  Text(ParaUtils.formatla(u.satisFiyati),
                      style: const TextStyle(fontSize: 11)),
                ]),
          ),
        );
      },
    );
  }
}
