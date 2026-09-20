// lib/ekranlar/satis/plu_ekrani.dart  v4.0
// Üstte kaydırmalı grup butonları + ürün ızgarası (tek tıkla sepete)
// Çift tetikleme YOK — onUrunSec direkt çağrılır, bottom sheet dışarıdan kapatılır
import 'dart:io';
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../cekirdek/utils/para_utils.dart';

const _renkPaleti = [
  Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFC62828),
  Color(0xFF6A1B9A), Color(0xFF00695C), Color(0xFFE65100),
  Color(0xFF37474F), Color(0xFF558B2F), Color(0xFF4527A0),
  Color(0xFF00838F), Color(0xFF283593), Color(0xFF880E4F),
];

Color _renk(String s) =>
    _renkPaleti[s.codeUnits.fold(0, (a, b) => a + b) % _renkPaleti.length];

class PluEkrani extends ConsumerStatefulWidget {
  /// Ürün seçilince çağrılır — bottom sheet kapatma BURAYA bırakılır
  final void Function(UrunModel urun) onUrunSec;
  const PluEkrani({super.key, required this.onUrunSec});

  @override
  ConsumerState<PluEkrani> createState() => _PluEkraniState();
}

class _PluEkraniState extends ConsumerState<PluEkrani> {
  List<UrunModel> _urunler    = [];
  bool            _yukleniyor = true;
  String?         _secilenGrup; // null = Tümü
  bool            _isleniyor   = false; // çift tıklamayı engelle

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      // NOT: Önceden burada her ekran açılışında "ALTER TABLE urunler ADD
      // COLUMN plu..." çalıştırılıyordu — ama bu kolonlar zaten hem taze
      // kurulum şemasında (urun_semasi.dart) hem de doğru migration
      // adımında (v9→v10, migrasyon_yonetici.dart) ekleniyor. UI
      // ekranının kendi başına şema değişikliği yapması gereksiz ve
      // yanlış katmanda bir sorumluluktu — kaldırıldı.
      final urunler = await UrunDeposu().pluUrunleriGrupluGetir();
      if (!mounted) return;
      setState(() {
        _urunler    = urunler;
        _yukleniyor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // Tüm gruplar (Tümü dahil)
  List<String> get _gruplar {
    final set = <String>{};
    for (final u in _urunler) {
      set.add(u.anaGrup?.isNotEmpty == true ? u.anaGrup! : 'Diğer');
    }
    return set.toList()..sort();
  }

  // Gösterilecek ürünler
  List<UrunModel> get _gosterilen {
    if (_secilenGrup == null) return _urunler;
    return _urunler.where((u) {
      final g = u.anaGrup?.isNotEmpty == true ? u.anaGrup! : 'Diğer';
      return g == _secilenGrup;
    }).toList();
  }

  // TEK TETİKLEME — _isleniyor bayrağı ile koruma
  void _urunSec(UrunModel urun) {
    if (_isleniyor) return;
    _isleniyor = true;
    HapticFeedback.lightImpact();
    widget.onUrunSec(urun); // sadece bu — dışarıdan kapatılır
  }

  @override
  Widget build(BuildContext context) {
    final gruplar = _gruplar;
    final gosterilen = _gosterilen;

    // Izgara sütun sayısı — seçili gruptaki max boyuta göre
    int crossCount = 3;
    double ratio   = 0.82;
    if (gosterilen.isNotEmpty) {
      final max = gosterilen.map((u) => u.pluKartBoyut).reduce((a, b) => a > b ? a : b);
      if (max == 3) { crossCount = 2; ratio = 0.88; }
      else if (max == 1) { crossCount = 4; ratio = 1.1; }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        // 🔴 DÜZELTME: sabit #F5F5F5 idi — koyu temada bu yarım-ekran
        // panel parlak/beyaz bir dikdörtgen olarak kalıyordu.
        color: context.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [

        // ── Tutma çubuğu ────────────────────────────────────────────────────
        Center(child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: TsRenk.ayirac(context),
            borderRadius: BorderRadius.circular(2),
          ),
        )),

        // ── Başlık + kapat ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            const Expanded(
              child: Text('Hızlı Ürün Seç',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('${gosterilen.length} ürün',
                  style: TextStyle(fontSize: 12, color: context.textSecondary)),
            ),
          ]),
        ),

        // ── Grup butonları (yatay scroll) ───────────────────────────────────
        if (gruplar.length > 1)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // Tümü butonu
                _grupBtn(null, 'Tümü', _urunler.length),
                ...gruplar.map((g) {
                  final adet = _urunler.where((u) {
                    return (u.anaGrup?.isNotEmpty == true ? u.anaGrup! : 'Diğer') == g;
                  }).length;
                  return _grupBtn(g, g, adet);
                }),
              ],
            ),
          ),

        if (gruplar.length > 1) const SizedBox(height: 10),

        // ── Ürün ızgarası ───────────────────────────────────────────────────
        Expanded(
          child: _yukleniyor
              ? const TsYukleniyor()
              : _urunler.isEmpty
                  ? _bosEkran()
                  : gosterilen.isEmpty
                      ? Center(child: Text('Bu grupta ürün yok',
                          style: TextStyle(color: context.textSecondary)))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossCount,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: ratio,
                          ),
                          itemCount: gosterilen.length,
                          itemBuilder: (_, i) => _urunKarti(gosterilen[i]),
                        ),
        ),
      ]),
    );
  }

  // ── Grup butonu ───────────────────────────────────────────────────────────
  Widget _grupBtn(String? deger, String etiket, int adet) {
    final secili = _secilenGrup == deger;
    return GestureDetector(
      onTap: () => setState(() => _secilenGrup = deger),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        decoration: BoxDecoration(
          color: secili ? TsRenk.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: secili ? TsRenk.primary : context.borderColor,
            width: secili ? 0 : 1,
          ),
          boxShadow: secili
              ? [BoxShadow(color: TsRenk.primary.withAlpha(0x4D),
                  blurRadius: 8, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            etiket,
            style: TsMetin.kucukVurgu.copyWith(color: secili ? Colors.white : context.textSecondary),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: secili
                  ? Color(0x40FFFFFF)
                  : context.borderColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$adet',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: secili ? Colors.white : context.textSecondary,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Ürün kartı ────────────────────────────────────────────────────────────
  Widget _urunKarti(UrunModel urun) {
    final renk = _renk(urun.anaGrup ?? 'Diğer');
    return GestureDetector(
      onTap: () => _urunSec(urun),
      child: Container(
        decoration: BoxDecoration(
          color: TsRenk.kart(context),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [const BoxShadow(
            color: Color(0x12000000),
            blurRadius: 6, offset: Offset(0, 2),
          )],
        ),
        child: Column(children: [
          // Resim
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: SizedBox.expand(child: _arkaplan(urun, renk)),
            ),
          ),
          // İsim + fiyat
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(urun.urunAdi,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Text(ParaUtils.formatla(urun.satisFiyati),
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: renk),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _arkaplan(UrunModel urun, Color renk) {
    final yol = urun.resimYolu;
    if (yol != null && yol.isNotEmpty) {
      final f = File(yol);
      if (f.existsSync()) {
        return Image.file(f, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _gradient(urun, renk));
      }
    }
    return _gradient(urun, renk);
  }

  Widget _gradient(UrunModel urun, Color renk) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [renk.withAlpha(204), renk],
      ),
    ),
    child: Center(child: Text(
      urun.urunAdi.isNotEmpty ? urun.urunAdi[0].toUpperCase() : '?',
      style: const TextStyle(
          color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900),
    )),
  );

  Widget _bosEkran() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.grid_off, size: 56, color: context.textHint),
      const SizedBox(height: 12),
      Text("PLU panelinde ürün yok\nDashboard → PLU Yönetimi'nden ürün ekleyin",
        textAlign: TextAlign.center,
        style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.6),
      ),
    ]),
  );
}
