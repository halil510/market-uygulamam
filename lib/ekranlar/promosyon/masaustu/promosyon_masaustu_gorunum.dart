// lib/ekranlar/promosyon/masaustu/promosyon_masaustu_gorunum.dart
//
// Promosyon listesi — masaüstü tablo görünümü: tablo + alt şerit + sağ tık
// menüsü + F1/F2/F3/F4 kısayolları. Sadece görünüm; ekleme/düzenleme/silme
// ve yenileme çağıran ekrandan gelir. Yetki kuralı mobildekiyle AYNI:
// ekle/düzenle/aktif-pasif/sil yalnız Admin/Müdür'e görünür.
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../modeller/promosyon_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class PromosyonMasaustuGorunum extends StatefulWidget {
  final List<PromosyonModel> promosyonlar;
  final bool yetkili;
  final VoidCallback onEkle;
  final void Function(PromosyonModel p) onDuzenle;
  final void Function(PromosyonModel p) onToggle;
  final void Function(PromosyonModel p) onSil;

  /// Liste boşken tablonun yerinde gösterilir; alt şerit (F1 Ekle) YİNE de
  /// görünür — boş listede ekleme yolu kaybolmasın.
  final String bosMesaj;

  const PromosyonMasaustuGorunum({
    super.key,
    required this.promosyonlar,
    required this.yetkili,
    required this.onEkle,
    required this.onDuzenle,
    required this.onToggle,
    required this.onSil,
    this.bosMesaj = 'Promosyon yok — F1 ile ekleyin',
  });

  /// Durum etiketi mobil karttakiyle aynı mantık, ama bitiş günü TAM gün
  /// geçerli sayılır (PromosyonModel.gecerli ile tutarlı).
  static String durumEtiketi(PromosyonModel p) {
    if (!p.aktif) return 'Pasif';
    final simdi = DateTime.now();
    final b = p.bitisTarihi;
    if (b != null && simdi.isAfter(DateTime(b.year, b.month, b.day, 23, 59, 59, 999))) {
      return 'Süresi Doldu';
    }
    final s = p.baslangicTarihi;
    if (s != null && simdi.isBefore(s)) return 'Başlamadı';
    return 'Aktif';
  }

  @override
  State<PromosyonMasaustuGorunum> createState() => _PromosyonMasaustuGorunumState();
}

class _PromosyonMasaustuGorunumState extends State<PromosyonMasaustuGorunum> {
  PromosyonModel? _secili;

  static final _tarih = DateFormat('dd.MM.yyyy');

  static String _oran(double o) {
    var t = o.toStringAsFixed(3);
    if (t.contains('.')) {
      t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return '%${t.replaceAll('.', ',')}';
  }

  late final List<TabloKolon<PromosyonModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Ürün',
        genislik: 240,
        esnek: true,
        deger: (p) => p.urunAdi,
        sirala: (p) => p.urunAdi.toLowerCase()),
    TabloKolon(
        baslik: 'Promosyon Adı',
        genislik: 200,
        deger: (p) => p.promosyonAdi,
        sirala: (p) => p.promosyonAdi.toLowerCase()),
    TabloKolon(
        baslik: 'İskonto',
        genislik: 90,
        sagaYasli: true,
        deger: (p) => _oran(p.iskontoOran),
        sirala: (p) => p.iskontoOran),
    TabloKolon(
        baslik: 'Min. Miktar',
        genislik: 95,
        sagaYasli: true,
        deger: (p) => p.minMiktar.toStringAsFixed(0),
        sirala: (p) => p.minMiktar),
    TabloKolon(
        baslik: 'Başlangıç',
        genislik: 100,
        deger: (p) => p.baslangicTarihi == null ? '' : _tarih.format(p.baslangicTarihi!),
        sirala: (p) => p.baslangicTarihi ?? DateTime(1970)),
    TabloKolon(
        baslik: 'Bitiş',
        genislik: 100,
        deger: (p) => p.bitisTarihi == null ? '' : _tarih.format(p.bitisTarihi!),
        sirala: (p) => p.bitisTarihi ?? DateTime(9999)),
    TabloKolon(
        baslik: 'Durum',
        genislik: 110,
        deger: PromosyonMasaustuGorunum.durumEtiketi,
        sirala: PromosyonMasaustuGorunum.durumEtiketi,
        renk: (p) {
          switch (PromosyonMasaustuGorunum.durumEtiketi(p)) {
            case 'Aktif':
              return TsRenk.basarili;
            case 'Pasif':
              return TsRenk.uyari;
            default:
              return TsRenk.hata;
          }
        }),
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

  /// Liste yenilenince (filtre/silme/düzenleme) seçili satırı güncel kopyayla
  /// eşle; artık listede yoksa seçimi bırak.
  PromosyonModel? get _gecerliSecili {
    final s = _secili;
    if (s == null) return null;
    for (final p in widget.promosyonlar) {
      if (p.id == s.id) return p;
    }
    return null;
  }

  void _menu(PromosyonModel p, Offset konum) {
    if (!widget.yetkili) return;
    masaustuMenuAc(context, konum, [
      MenuOge('Düzenle', () => widget.onDuzenle(p), ikon: Icons.edit_outlined),
      MenuOge(p.aktif ? 'Pasife Al' : 'Aktife Al', () => widget.onToggle(p),
          ikon: p.aktif ? Icons.pause_circle_outline : Icons.play_circle_outline),
      MenuOge('Sil', () => widget.onSil(p), ikon: Icons.delete_outline, ayiracOnce: true),
    ]);
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!ekranUstte(context)) return false;
    // Metin kutusunda yazarken kısayol tetiklenmesin (F tuşları zaten yazı değil,
    // ama odak arama kutusundayken de çalışması istenir) — yalnız F tuşları ele alınır.
    final k = e.logicalKey;
    final s = _gecerliSecili;
    if (!widget.yetkili) return false;
    if (k == LogicalKeyboardKey.f1) {
      widget.onEkle();
    } else if (k == LogicalKeyboardKey.f2) {
      if (s != null) widget.onDuzenle(s);
    } else if (k == LogicalKeyboardKey.f3) {
      if (s != null) widget.onToggle(s);
    } else if (k == LogicalKeyboardKey.f4) {
      if (s != null) widget.onSil(s);
    } else if (k == LogicalKeyboardKey.f6) {
      if (s != null) _menu(s, const Offset(400, 250));
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.promosyonlar;
    final s = _gecerliSecili;
    final aktif = l.where((p) => PromosyonMasaustuGorunum.durumEtiketi(p) == 'Aktif').length;
    return Column(children: [
      Expanded(
        child: l.isEmpty
            ? Center(child: Text(widget.bosMesaj, style: TextStyle(fontSize: 15, color: context.textSecondary)))
            : MasaustuTablo<PromosyonModel>(
          satirlar: l,
          kolonlar: _kolonlar,
          secili: s,
          onSec: (p) => setState(() => _secili = p),
          onCift: widget.yetkili ? widget.onDuzenle : null,
          onSagTik: widget.yetkili ? _menu : null,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Promosyon', '${l.length}'),
          AltOzet('Aktif', '$aktif', renk: TsRenk.basarili),
        ],
        tuslar: [
          if (widget.yetkili) ...[
            AltTus('F1', 'Ekle', Icons.local_offer_outlined, const Color(0xFF2E7D32), widget.onEkle),
            AltTus('F2', 'Düzenle', Icons.edit_outlined, const Color(0xFF1565C0),
                s == null ? null : () => widget.onDuzenle(s)),
            AltTus('F3', s != null && !s.aktif ? 'Aktife Al' : 'Pasife Al',
                Icons.toggle_on_outlined, const Color(0xFFEF6C00),
                s == null ? null : () => widget.onToggle(s)),
            AltTus('F4', 'Sil', Icons.delete_outline, const Color(0xFFC62828),
                s == null ? null : () => widget.onSil(s)),
          ],
        ],
      ),
    ]);
  }
}
