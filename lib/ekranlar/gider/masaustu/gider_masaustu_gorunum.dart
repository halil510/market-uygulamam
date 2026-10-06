// lib/ekranlar/gider/masaustu/gider_masaustu_gorunum.dart
//
// Gider listesi — masaüstü tablo görünümü: tablo + alt şerit + sağ tık menüsü
// + F1/F2/F4 kısayolları. Sadece görünüm; ekleme/düzenleme/silme çağıran
// ekrandan gelir. Yetki kuralı mobildekiyle AYNI: ekle/sil yalnız
// Admin/Müdür'e görünür, düzenleme (satıra dokunma) herkese açıktır.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/gider_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class GiderMasaustuGorunum extends StatefulWidget {
  final List<GiderModel> giderler;
  final bool yetkili;
  final VoidCallback onEkle;
  final void Function(GiderModel g) onDuzenle;
  final void Function(GiderModel g) onSil;

  const GiderMasaustuGorunum({
    super.key,
    required this.giderler,
    required this.yetkili,
    required this.onEkle,
    required this.onDuzenle,
    required this.onSil,
  });

  @override
  State<GiderMasaustuGorunum> createState() => _GiderMasaustuGorunumState();
}

class _GiderMasaustuGorunumState extends State<GiderMasaustuGorunum> {
  GiderModel? _secili;

  static final _tarih = DateFormat('dd.MM.yyyy');

  late final List<TabloKolon<GiderModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Tarih',
        genislik: 100,
        deger: (g) => _tarih.format(g.tarih),
        sirala: (g) => g.tarih),
    TabloKolon(
        baslik: 'Açıklama',
        genislik: 240,
        esnek: true,
        deger: (g) => g.aciklama ?? '—',
        sirala: (g) => (g.aciklama ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Kategori',
        genislik: 150,
        deger: (g) => g.kategoriAdi.isEmpty ? 'Genel' : g.kategoriAdi,
        sirala: (g) => g.kategoriAdi.toLowerCase()),
    TabloKolon(
        baslik: 'Ödeme',
        genislik: 100,
        deger: (g) => g.odemeYontemi,
        sirala: (g) => g.odemeYontemi),
    TabloKolon(
        baslik: 'Belge No',
        genislik: 110,
        deger: (g) => g.belgeNo ?? '',
        sirala: (g) => (g.belgeNo ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Tutar',
        genislik: 120,
        sagaYasli: true,
        deger: (g) => ParaUtils.formatla(g.tutar),
        sirala: (g) => g.tutar,
        renk: (g) => TsRenk.hata),
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

  /// Liste yenilenince seçili satırı güncel kopyayla eşle; artık yoksa bırak.
  GiderModel? get _gecerliSecili {
    final s = _secili;
    if (s == null) return null;
    for (final g in widget.giderler) {
      if (g.id == s.id) return g;
    }
    return null;
  }

  void _menu(GiderModel g, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Düzenle', () => widget.onDuzenle(g), ikon: Icons.edit_outlined),
      if (widget.yetkili)
        MenuOge('Sil', () => widget.onSil(g),
            ikon: Icons.delete_outline, ayiracOnce: true),
    ]);
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!ekranUstte(context)) return false;
    final k = e.logicalKey;
    final s = _gecerliSecili;
    if (k == LogicalKeyboardKey.f1 && widget.yetkili) {
      widget.onEkle();
    } else if (k == LogicalKeyboardKey.f2) {
      if (s != null) widget.onDuzenle(s);
    } else if (k == LogicalKeyboardKey.f4 && widget.yetkili) {
      if (s != null) widget.onSil(s);
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.giderler;
    final s = _gecerliSecili;
    final toplam = l.fold(0.0, (t, g) => t + g.tutar);
    return Column(children: [
      Expanded(
        child: l.isEmpty
            ? Center(
                child: Text(
                    widget.yetkili ? 'Gider kaydı yok — F1 ile ekleyin' : 'Gider kaydı yok',
                    style: TextStyle(fontSize: 15, color: context.textSecondary)))
            : MasaustuTablo<GiderModel>(
                satirlar: l,
                kolonlar: _kolonlar,
                secili: s,
                onSec: (g) => setState(() => _secili = g),
                onCift: widget.onDuzenle,
                onSagTik: _menu,
              ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Kayıt', '${l.length}'),
          AltOzet('Toplam', ParaUtils.formatla(toplam), renk: TsRenk.hata),
        ],
        tuslar: [
          if (widget.yetkili)
            AltTus('F1', 'Ekle', Icons.add_circle_outline,
                const Color(0xFF2E7D32), widget.onEkle),
          AltTus('F2', 'Düzenle', Icons.edit_outlined, const Color(0xFF1565C0),
              s == null ? null : () => widget.onDuzenle(s)),
          if (widget.yetkili)
            AltTus('F4', 'Sil', Icons.delete_outline, const Color(0xFFC62828),
                s == null ? null : () => widget.onSil(s)),
        ],
      ),
    ]);
  }
}
