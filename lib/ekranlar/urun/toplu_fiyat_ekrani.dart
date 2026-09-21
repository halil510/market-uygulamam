// lib/ekranlar/urun/toplu_fiyat_ekrani.dart
// Toplu fiyat güncelleme - % zam/indirim, kategori bazlı, manuel liste

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';

class TopluFiyatEkrani extends ConsumerStatefulWidget {
  const TopluFiyatEkrani({super.key});
  @override
  ConsumerState<TopluFiyatEkrani> createState() => _TopluFiyatEkraniState();
}

class _TopluFiyatEkraniState extends ConsumerState<TopluFiyatEkrani> with SingleTickerProviderStateMixin {
  final _urunDepo = UrunDeposu();
  late final TabController _tab;

  List<UrunModel> _urunler    = [];
  List<UrunModel> _secili     = [];
  Set<int>        _seciliIds  = {};
  bool _tumunuSec = false;
  bool _yukleniyor = false;
  bool _isleniyor  = false;

  // Filtreler
  String? _filtrGrup, _filtrMarka;
  // Cache - sadece _urunler değişince yeniden hesapla
  List<String> _gruplarCache  = [];
  List<String> _markalarCache = [];
  List<String> get _gruplar  => _gruplarCache;
  List<String> get _markalar => _markalarCache;
  void _cacheGuncelle() {
    _gruplarCache  = _urunler.map((u) => u.anaGrup ?? '').where((g) => g.isNotEmpty).toSet().toList()..sort();
    _markalarCache = _urunler.map((u) => u.marka ?? '').where((m) => m.isNotEmpty).toSet().toList()..sort();
  }

  // Güncelleme parametreleri
  String _islem     = 'zam';       // zam | indirim | sabitFiyat | alisUstune
  String _tipi      = 'yuzde';     // yuzde | tutar
  final _degerCtrl  = TextEditingController();
  final _yeniCtrl   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void dispose() { _tab.dispose(); _degerCtrl.dispose(); _yeniCtrl.dispose(); super.dispose(); }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final list = await _urunDepo.tumunuGetir();
      if (!mounted) return;
      _urunler = list;
      _uygula();
      _cacheGuncelle();
      setState(() => _yukleniyor = false);
    } catch (e) {
      if (kDebugMode) debugPrint('Ürün yükleme hatası: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _uygula() {
    var list = List<UrunModel>.from(_urunler);
    if (_filtrGrup  != null) list = list.where((u) => u.anaGrup == _filtrGrup).toList();
    if (_filtrMarka != null) list = list.where((u) => u.marka   == _filtrMarka).toList();
    _secili    = list;
    _seciliIds = _tumunuSec ? list.map((u) => u.id!).toSet() : _seciliIds.intersection(list.map((u) => u.id!).toSet());
  }

  double _yeniFiyatHesapla(UrunModel u) {
    final deger = double.tryParse(_degerCtrl.text.replaceAll(',', '.')) ?? 0;
    switch (_islem) {
      case 'zam':
        return _tipi == 'yuzde'
            ? u.satisFiyati * (1 + deger / 100)
            : u.satisFiyati + deger;
      case 'indirim':
        return _tipi == 'yuzde'
            ? u.satisFiyati * (1 - deger / 100)
            : u.satisFiyati - deger;
      case 'sabitFiyat':
        return double.tryParse(_yeniCtrl.text.replaceAll(',', '.')) ?? u.satisFiyati;
      case 'alisUstune':
        return u.alisFiyat * (1 + deger / 100);
      default: return u.satisFiyati;
    }
  }

  Future<void> _guncelle() async {
    final hedefIds = _tumunuSec ? _secili.map((u) => u.id!).toSet() : _seciliIds;
    if (hedefIds.isEmpty) { BildirimServisi.uyari(context, 'Ürün seçin'); return; }

    final deger = double.tryParse(_degerCtrl.text.replaceAll(',', '.')) ?? 0;
    if (deger <= 0 && _islem != 'sabitFiyat') {
      BildirimServisi.uyari(context, 'Geçerli değer girin'); return;
    }

    final ok = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Toplu Fiyat Güncelleme'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${hedefIds.length} ürün güncellenecek.'),
          const SizedBox(height: 8),
          Text('İşlem: ${_islemAdi()}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Değer: ${_tipi == 'yuzde' ? '%$deger' : '${deger.toStringAsFixed(2)} ₺'}'),
          const SizedBox(height: 8),
          const Text('Bu işlem geri alınamaz!', style: TextStyle(color: Colors.red, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.orange),
              child: const Text('Güncelle')),
        ],
      ));
    if (ok != true) return;

    setState(() => _isleniyor = true);
    try {
      final hedefUrunler = _secili.where((u) => hedefIds.contains(u.id)).toList();
      var atlanan = 0;
      final yeniFiyatlar = <int, double>{};
      for (final u in hedefUrunler) {
        final yeni = _yeniFiyatHesapla(u);
        if (yeni <= 0) {
          // 🔴 DÜZELTME (derin analizde bulundu): bu satır ÖNCEDEN
          // kullanıcıya HİÇ bildirilmeden sessizce atlanıyordu —
          // "$guncellenen ürün güncellendi" mesajı kaç ürünün
          // atlandığını söylemiyordu, kullanıcı TÜM seçilenlerin
          // güncellendiğini sanıyordu.
          atlanan++;
          continue;
        }
        yeniFiyatlar[u.id!] = yeni;
      }

      // 🔴 DÜZELTME (derin analizde bulundu): bu güncelleme ÖNCEDEN tek
      // transaction'da DEĞİLDİ — her ürün ayrı db.update() ile
      // güncelleniyordu. Kullanıcıya "Bu işlem geri alınamaz!" denip
      // atomik bir işlem izlenimi veriliyordu, ama ortasında bir kesinti
      // (uygulama çökmesi/güç kesintisi) olsaydı KISMİ güncelleme kalır,
      // geri alınamazdı. Artık UrunDeposu.topluFiyatUygula() TEK
      // transaction'da yazıyor (ya hepsi, ya hiçbiri) VE her ürünü
      // buluta bildiriyor (ÖNCEDEN hiç bildirmiyordu, sadece manuel
      // senkronla gidiyordu).
      final guncellenenIds = await UrunDeposu().topluFiyatUygula(yeniFiyatlar);

      await _yukle();
      if (mounted) {
        if (atlanan > 0) {
          BildirimServisi.uyari(context,
              '${guncellenenIds.length} ürün güncellendi, $atlanan ürün geçersiz '
              'hesaplanan fiyat nedeniyle ATLANDI (0 veya altı çıktı)');
        } else {
          BildirimServisi.basari(context, '${guncellenenIds.length} ürün fiyatı güncellendi');
        }
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  String _islemAdi() {
    switch (_islem) {
      case 'zam':       return 'Zam (Artış)';
      case 'indirim':   return 'İndirim (Düşüş)';
      case 'sabitFiyat':return 'Sabit Fiyat';
      case 'alisUstune':return 'Alış Üstüne Kâr';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Toplu Fiyat Güncelleme',
        alt: TabBar(controller: _tab, tabs: const [Tab(text: 'Ayarlar'), Tab(text: 'Ürün Seç')]),
      ),
      body: TabBarView(controller: _tab, children: [
        // ── TAB 1: Güncelleme Ayarları ──────────────────────────────
        ListView(padding: const EdgeInsets.all(16), children: [
          // İşlem tipi
          Container(decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('İşlem Türü', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              _islemChip('zam',        'Zam',         Icons.trending_up,   Colors.red),
              _islemChip('indirim',    'İndirim',     Icons.trending_down,  Colors.green),
              _islemChip('sabitFiyat', 'Sabit Fiyat', Icons.price_change,   Colors.blue),
              _islemChip('alisUstune', 'Alış+Kâr',    Icons.calculate,      Colors.purple),
            ]),
          ]))),
          const SizedBox(height: 10),
          // Değer girişi
          if (_islem != 'sabitFiyat')
            Container(decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))), child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
              Row(children: [
                Expanded(child: RadioListTile<String>(dense: true, title: const Text('Yüzde (%)'),
                    value: 'yuzde', groupValue: _tipi,
                    onChanged: (v) => setState(() => _tipi = v!))),
                Expanded(child: RadioListTile<String>(dense: true, title: const Text('Tutar (₺)'),
                    value: 'tutar', groupValue: _tipi,
                    onChanged: (v) => setState(() => _tipi = v!))),
              ]),
              TextField(controller: _degerCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _tipi == 'yuzde' ? 'Oran (%)' : 'Tutar (₺)',
                  prefixIcon: const Icon(Icons.edit), border: const OutlineInputBorder()),
                onChanged: (_) => setState(() {})),
            ]))),
          if (_islem == 'sabitFiyat')
            Container(decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))), child: Padding(padding: const EdgeInsets.all(14), child:
              TextField(controller: _yeniCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Yeni Fiyat (₺)',
                    prefixIcon: Icon(Icons.price_change), border: OutlineInputBorder()),
                onChanged: (_) => setState(() {})))),
          // Filtre
          const SizedBox(height: 10),
          Container(decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Kategori Filtresi', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                value: _filtrGrup, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ana Grup', border: OutlineInputBorder(), isDense: true),
                items: [const DropdownMenuItem(value: null, child: Text('Tümü')),
                  ..._gruplar.map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)))],
                onChanged: (v) => setState(() { _filtrGrup = v; _uygula(); }))),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                value: _filtrMarka, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Marka', border: OutlineInputBorder(), isDense: true),
                items: [const DropdownMenuItem(value: null, child: Text('Tümü')),
                  ..._markalar.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))],
                onChanged: (v) => setState(() { _filtrMarka = v; _uygula(); }))),
            ]),
          ]))),
          // Önizleme
          const SizedBox(height: 10),
          Container(decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))), child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Etkilenecek Ürünler', style: TextStyle(fontWeight: FontWeight.w700)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: TsRenk.zemin(TsRenk.uyari), borderRadius: BorderRadius.circular(12)),
                child: Text(_tumunuSec ? '${_secili.length} ürün (Tümü)' : '${_seciliIds.length} ürün seçili',
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700))),
            ]),
            if (_secili.isNotEmpty && _degerCtrl.text.isNotEmpty) ...[
              const Divider(height: 16),
              ...(_secili.take(3).map((u) {
                final yeni = _yeniFiyatHesapla(u);
                return Padding(padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(u.urunAdi, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                    Text(ParaUtils.formatla(u.satisFiyati), style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                    const Icon(Icons.arrow_forward, size: 14, color: Colors.orange),
                    Text(ParaUtils.formatla(yeni), style: TsMetin.kucukVurgu.copyWith(color: Colors.orange)),
                  ]));
              })),
              if (_secili.length > 3) Text('... ve ${_secili.length - 3} ürün daha',
                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
            ],
          ]))),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isleniyor ? null : _guncelle,
            icon: _isleniyor
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.update),
            label: Text(_tumunuSec ? 'Tüm Filtrelileri Güncelle (${_secili.length})' : 'Seçilileri Güncelle (${_seciliIds.length})'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50)),
          ),
        ]),

        // ── TAB 2: Ürün Seçimi ────────────────────────────────────────
        Column(children: [
          Padding(padding: const EdgeInsets.all(12),
            child: Row(children: [
              Checkbox(value: _tumunuSec,
                onChanged: (v) => setState(() { _tumunuSec = v!; if (v) _seciliIds = _secili.map((u) => u.id!).toSet(); else _seciliIds.clear(); })),
              Text(_tumunuSec ? 'Tüm Filtreliler (${_secili.length})' : '${_seciliIds.length} Seçildi',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ])),
          Expanded(child: _yukleniyor
              ? const TsYukleniyor()
              : ListView.builder(
                  itemCount: _secili.length,
                  itemBuilder: (_, i) {
                    final u = _secili[i];
                    final secili = _seciliIds.contains(u.id);
                    final yeni = _degerCtrl.text.isNotEmpty ? _yeniFiyatHesapla(u) : null;
                    return CheckboxListTile(
                      dense: true,
                      value: secili || _tumunuSec,
                      onChanged: (v) {
                        if (_tumunuSec) return;
                        setState(() { if (v!) _seciliIds.add(u.id!); else _seciliIds.remove(u.id); });
                      },
                      title: Text(u.urunAdi, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Row(children: [
                        Text(ParaUtils.formatla(u.satisFiyati), style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                        if (yeni != null) ...[
                          const Icon(Icons.arrow_forward, size: 12, color: Colors.orange),
                          Text(ParaUtils.formatla(yeni),
                              style: TextStyle(fontSize: 12, color: yeni > u.satisFiyati ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ]),
                    );
                  })),
        ]),
      ]),
    );
  }

  Widget _islemChip(String value, String label, IconData icon, Color renk) => GestureDetector(
    onTap: () => setState(() => _islem = value),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _islem == value ? renk.withAlpha(31) : TsRenk.arkaplan(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _islem == value ? renk : TsRenk.ayirac(context), width: _islem == value ? 1.5 : 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: _islem == value ? renk : context.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: _islem == value ? renk : context.textSecondary,
            fontWeight: _islem == value ? FontWeight.w700 : FontWeight.normal)),
      ])));
}
