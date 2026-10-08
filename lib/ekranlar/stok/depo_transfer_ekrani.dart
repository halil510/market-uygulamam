// lib/ekranlar/stok/depo_transfer_ekrani.dart
//
// 🔴 GÜNCELLEME: Bu ekran ÖNCEDEN gerçek şube bazlı stok takibi
// YAPMIYORDU — sahte, sabit kodlanmış bir "depo" listesi kullanıyordu
// ve bir üründe stokDus()+stokGir() işlemini art arda yaparak (net etki
// sıfır) sadece "X depodan Y depoya" açıklamalı bir hareket geçmişi
// kaydı bırakıyordu. Artık gerçek 'sube_urun' tablosu ve gerçek
// 'subeler' listesi kullanılıyor — transfer GERÇEKTEN kaynak şubenin
// payını düşürüp hedef şubenin payını artırıyor.
import 'package:flutter/material.dart';
import 'package:market_plus/cekirdek/utils/metin_arama.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/sube_urun_deposu.dart';
import '../../depolar/sube_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/masaustu/ekran_ustte.dart';
import '../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../widgetlar/masaustu/masaustu_tablo.dart';

class DepoTransferEkrani extends ConsumerStatefulWidget {
  const DepoTransferEkrani({super.key});
  @override
  ConsumerState<DepoTransferEkrani> createState() => _DepoTransferEkraniState();
}

class _DepoTransferEkraniState extends ConsumerState<DepoTransferEkrani> {
  List<UrunModel> _urunler = [];
  List<Map<String, dynamic>> _subeler = [];
  final Map<int, double> _miktarlar = {};
  final Map<int, TextEditingController> _ctrls = {};
  int? _kaynakSubeId;
  int? _hedefSubeId;
  bool _yukleniyor   = true;
  bool _islem        = false;
  final _araCtrl     = TextEditingController();

  @override
  void initState() {
    super.initState();
    _yukle();
    _araCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _araCtrl.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final u = await UrunDeposu().tumunuGetir();
      final subeler = await SubeDeposu().aktifOlanlariGetir();
      if (mounted) {
        setState(() {
          _urunler = u;
          _subeler = subeler;
          if (subeler.isNotEmpty) _kaynakSubeId = subeler.first['id'] as int;
          if (subeler.length > 1) _hedefSubeId = subeler[1]['id'] as int;
          _yukleniyor = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  List<UrunModel> get _filtrelenmis {
    final q = aramaNormalize(_araCtrl.text);
    final seciliIdsOlanlar = _miktarlar.entries
        .where((e) => e.value > 0).map((e) => e.key).toSet();
    final liste = q.isEmpty ? _urunler
        : _urunler.where((u) => aramaNormalize(u.urunAdi).contains(q)).toList();
    return [
      ...liste.where((u) => seciliIdsOlanlar.contains(u.id)),
      ...liste.where((u) => !seciliIdsOlanlar.contains(u.id)),
    ];
  }

  int get _seciliSayisi => _miktarlar.values.where((v) => v > 0).length;

  String _subeAdi(int? id) {
    if (id == null) return '?';
    final s = _subeler.firstWhere((s) => s['id'] == id, orElse: () => {});
    return s['sube_adi'] as String? ?? '?';
  }

  Future<void> _transferYap() async {
    if (_seciliSayisi == 0) {
      BildirimServisi.uyari(context, 'En az bir ürün seçin');
      return;
    }
    if (_kaynakSubeId == null || _hedefSubeId == null) {
      BildirimServisi.uyari(context, 'Kaynak ve hedef şube seçin');
      return;
    }
    if (_kaynakSubeId == _hedefSubeId) {
      BildirimServisi.uyari(context, 'Kaynak ve hedef şube farklı olmalı');
      return;
    }

    final kaynakAdi = _subeAdi(_kaynakSubeId);
    final hedefAdi = _subeAdi(_hedefSubeId);

    final onay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Transfer Onayı'),
        content: Text(
          '$kaynakAdi → $hedefAdi\n'
          '$_seciliSayisi ürün, '
          '${_miktarlar.values.where((v) => v > 0).fold(0.0, (s, v) => s + v)} adet\n\n'
          'Bu, kaynak şubenin stoğunu düşürüp hedef şubenin stoğunu '
          'artıracak gerçek bir transferdir.\n\n'
          'Devam edilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Onayla')),
        ],
      ));
    if (onay != true || !mounted) return;

    setState(() => _islem = true);
    try {
      final subeUrunDepo = SubeUrunDeposu();
      final basarisizlar = <String>[];
      final basariliAnahtarlar = <int>[];
      for (final entry in _miktarlar.entries.toList()) {
        if (entry.value <= 0) continue;
        try {
          await subeUrunDepo.transferEt(
            urunId: entry.key,
            kaynakSubeId: _kaynakSubeId!,
            hedefSubeId: _hedefSubeId!,
            miktar: entry.value,
          );
          basariliAnahtarlar.add(entry.key);
        } catch (e) {
          final urun = _urunler.firstWhere((u) => u.id == entry.key, orElse: () => _urunler.first);
          basarisizlar.add('${urun.urunAdi}: $e');
        }
      }
      // Sadece başarılı transferler listeden düşer; hatalı satırlar tekrar
      // denenebilsin diye kalır. Sayı temizlemeden ÖNCE alınır.
      final basariliSayisi = basariliAnahtarlar.length;
      if (mounted) {
        setState(() => basariliAnahtarlar.forEach(_miktarlar.remove));
      }
      if (mounted) {
        if (basarisizlar.isEmpty) {
          BildirimServisi.basari(context, '$basariliSayisi ürün $kaynakAdi → $hedefAdi transfer edildi ✓');
        } else {
          BildirimServisi.uyari(context,
              '${basarisizlar.length} üründe hata: ${basarisizlar.join(", ")}');
        }
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'İşlem yapılamadı: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  /// Masaüstü: seçili ürünün transfer miktarını diyalogla gir (0 = kaldır).
  Future<void> _miktarGir(UrunModel u) async {
    final ctrl = TextEditingController(
        text: (_miktarlar[u.id!] ?? 0) > 0 ? _miktarlar[u.id!]!.toStringAsFixed(0) : '');
    final sonuc = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(u.urunAdi, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
              labelText: 'Transfer miktarı (${u.birimAdi})',
              helperText: 'Stok: ${u.stok.toStringAsFixed(0)} — 0 girerseniz listeden çıkar'),
          onSubmitted: (v) => Navigator.pop(ctx, double.tryParse(v) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0),
              child: const Text('Tamam')),
        ],
      ),
    );
    ctrl.dispose();
    if (sonuc == null || !mounted) return;
    setState(() {
      _miktarlar[u.id!] = sonuc;
      _ctrls[u.id!]?.text = sonuc > 0 ? sonuc.toStringAsFixed(0) : '';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TsRenk.arkaplan(context),
    appBar: TsAppBar(
        baslik: 'Depo Transferi',
        aksiyonlar: [
        if (_seciliSayisi > 0) TextButton.icon(
          onPressed: _islem ? null : _transferYap,
          icon: _islem
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.swap_horiz, color: Colors.white),
          label: Text('Transfer ($_seciliSayisi)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
      ],
      ),
    body: Column(children: [
      Container(
        color: TsRenk.kart(context),
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: TsRenk.uyari.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: TsRenk.uyari),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Şubeler arası gerçek stok transferi — kaynak şubenin '
                  'stoğu düşer, hedef şubenin stoğu artar.',
                  style: TextStyle(fontSize: 11, color: TsRenk.uyari),
                ),
              ),
            ]),
          ),
          Row(children: [
            Expanded(child: _DepoSec('Kaynak', _kaynakSubeId, _subeler,
                (v) => setState(() => _kaynakSubeId = v), Colors.orange.shade700)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, color: TsRenk.metinIkincil(context))),
            Expanded(child: _DepoSec('Hedef', _hedefSubeId, _subeler,
                (v) => setState(() => _hedefSubeId = v), Colors.green.shade700)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _araCtrl,
            decoration: InputDecoration(
              hintText: 'Ürün ara...',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true, fillColor: TsRenk.arkaplan(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 8)),
          ),
        ]),
      ),
      Expanded(child: _yukleniyor
        ? const TsYukleniyor(iskelet: true)
        // Masaüstü: tablo + çift tık/F2 miktar, F9 transfer (canlı tarama
        // 2026-10-08: telefon kart listesi görünüyordu).
        : MediaQuery.sizeOf(context).width > 1100
            ? _TransferTablosu(
                urunler: _filtrelenmis,
                miktarlar: _miktarlar,
                islemde: _islem,
                onMiktarGir: _miktarGir,
                onKaldir: (u) => setState(() {
                  _miktarlar.remove(u.id);
                  _ctrls[u.id]?.clear();
                }),
                onTransfer: _transferYap,
              )
        : ListView.builder(
            padding: const EdgeInsets.all(TsBosluk.md),
            itemCount: _filtrelenmis.length,
            itemBuilder: (_, i) {
              final u = _filtrelenmis[i];
              final miktar = _miktarlar[u.id!] ?? 0.0;
              final ctrl = _ctrls.putIfAbsent(u.id!, () => TextEditingController());
              if (ctrl.text.isEmpty && miktar > 0) ctrl.text = miktar.toStringAsFixed(0);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: miktar > 0 ? TsRenk.zemin(TsRenk.primary) : TsRenk.kart(context),
                    borderRadius: BorderRadius.circular(12),
                    border: miktar > 0 ? Border.all(color: TsRenk.primary.withAlpha(100)) : null,
                    boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u.urunAdi, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('Stok: ${u.stok.toStringAsFixed(0)} ${u.birimAdi}',
                        style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                  ])),
                  SizedBox(width: 80, child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '0',
                      isDense: true,
                      filled: true, fillColor: TsRenk.kart(context),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8)),
                    onChanged: (v) {
                      final val = double.tryParse(v) ?? 0;
                      setState(() => _miktarlar[u.id!] = val);
                    },
                  )),
                ]),
              );
            },
          )),
    ]),
  );
}

class _DepoSec extends StatelessWidget {
  final String etiket;
  final int? deger;
  final List<Map<String, dynamic>> subeler;
  final ValueChanged<int?> onChanged;
  final Color renk;
  const _DepoSec(this.etiket, this.deger, this.subeler, this.onChanged, this.renk);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(etiket, style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context), fontWeight: FontWeight.w600)),
    const SizedBox(height: 4),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: renk.withAlpha(20),
          borderRadius: BorderRadius.circular(12), border: Border.all(color: renk.withAlpha(76))),
      child: DropdownButton<int>(
        value: deger, isDense: true, underline: const SizedBox.shrink(),
        hint: const Text('Şube seçin', style: TextStyle(fontSize: 12)),
        items: subeler.map((s) => DropdownMenuItem(value: s['id'] as int,
            child: Text(s['sube_adi'] as String? ?? '?', style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: onChanged,
        style: TextStyle(color: renk, fontWeight: FontWeight.w600, fontSize: 13)),
    ),
  ]);
}

class _TransferTablosu extends StatefulWidget {
  final List<UrunModel> urunler;
  final Map<int, double> miktarlar;
  final bool islemde;
  final void Function(UrunModel u) onMiktarGir;
  final void Function(UrunModel u) onKaldir;
  final VoidCallback onTransfer;
  const _TransferTablosu({
    required this.urunler,
    required this.miktarlar,
    required this.islemde,
    required this.onMiktarGir,
    required this.onKaldir,
    required this.onTransfer,
  });

  @override
  State<_TransferTablosu> createState() => _TransferTablosuState();
}

class _TransferTablosuState extends State<_TransferTablosu> {
  int? _seciliId;

  double _m(UrunModel u) => widget.miktarlar[u.id] ?? 0;

  late final List<TabloKolon<UrunModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Ürün',
        genislik: 320,
        esnek: true,
        deger: (u) => u.urunAdi,
        sirala: (u) => u.urunAdi.toLowerCase()),
    TabloKolon(
        baslik: 'Barkod',
        genislik: 150,
        deger: (u) => u.barkod ?? '',
        sirala: (u) => u.barkod ?? ''),
    TabloKolon(
        baslik: 'Stok',
        genislik: 110,
        sagaYasli: true,
        deger: (u) => '${u.stok.toStringAsFixed(0)} ${u.birimAdi}',
        sirala: (u) => u.stok,
        renk: (u) => u.stok < 0 ? TsRenk.hata : null),
    TabloKolon(
        baslik: 'Transfer',
        genislik: 120,
        sagaYasli: true,
        deger: (u) => _m(u) > 0 ? _m(u).toStringAsFixed(0) : '',
        sirala: _m,
        renk: (u) => _m(u) > 0 ? TsRenk.primary : null),
  ];

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

  UrunModel? get _secili {
    for (final u in widget.urunler) {
      if (u.id == _seciliId) return u;
    }
    return null;
  }

  int get _seciliSayisi => widget.miktarlar.values.where((v) => v > 0).length;

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted || !ekranUstte(context)) return false;
    final k = e.logicalKey;
    final u = _secili;
    if ((k == LogicalKeyboardKey.f2 || k == LogicalKeyboardKey.enter) && u != null) {
      // Enter yalnız arama kutusu dışında (odak tablodayken) işlenir.
      if (k == LogicalKeyboardKey.enter &&
          FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
        return false;
      }
      widget.onMiktarGir(u);
    } else if (k == LogicalKeyboardKey.f4 && u != null && _m(u) > 0) {
      widget.onKaldir(u);
    } else if (k == LogicalKeyboardKey.f9 && _seciliSayisi > 0 && !widget.islemde) {
      widget.onTransfer();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final u = _secili;
    final toplamAdet = widget.miktarlar.values.where((v) => v > 0).fold(0.0, (t, v) => t + v);
    return Column(children: [
      Expanded(
        child: widget.urunler.isEmpty
            ? Center(child: Text('Ürün bulunamadı',
                style: TextStyle(color: TsRenk.metinIkincil(context))))
            : MasaustuTablo<UrunModel>(
                satirlar: widget.urunler,
                kolonlar: _kolonlar,
                secili: u,
                onSec: (x) => setState(() => _seciliId = x.id),
                onCift: widget.onMiktarGir,
                onSagTik: (x, konum) => masaustuMenuAc(context, konum, [
                  MenuOge('Miktar Gir', () => widget.onMiktarGir(x), ikon: Icons.edit_outlined),
                  if (_m(x) > 0)
                    MenuOge('Listeden Çıkar', () => widget.onKaldir(x),
                        ikon: Icons.remove_circle_outline, ayiracOnce: true),
                ]),
              ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Seçili Ürün', '$_seciliSayisi'),
          AltOzet('Toplam Adet', toplamAdet.toStringAsFixed(0)),
        ],
        tuslar: [
          AltTus('F2', 'Miktar Gir', Icons.edit_outlined, const Color(0xFF1565C0),
              u == null ? null : () => widget.onMiktarGir(u)),
          AltTus('F4', 'Çıkar', Icons.remove_circle_outline, const Color(0xFFC62828),
              u == null || _m(u) <= 0 ? null : () => widget.onKaldir(u)),
          AltTus('F9', 'Transfer Et', Icons.swap_horiz, const Color(0xFF2E7D32),
              _seciliSayisi == 0 || widget.islemde ? null : widget.onTransfer),
        ],
      ),
    ]);
  }
}
