// lib/ekranlar/banka/masaustu/kredi_karti_masaustu_gorunum.dart
//
// Kredi kartı listesi — masaüstü tablo görünümü. Limit doluluğu >%80 olan
// kart mobildeki "LİMİT DOLUYOR" rozetiyle aynı eşikle kırmızı vurgulanır.
// Ekleme yalnız Admin/Müdür'e görünür (mobildeki TsYetkili ile aynı).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/kredi_karti_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class KrediKartiMasaustuGorunum extends StatefulWidget {
  final List<KrediKartiModel> kartlar;
  final bool yetkili;
  final VoidCallback onEkle;
  final void Function(KrediKartiModel k) onDetay;

  const KrediKartiMasaustuGorunum({
    super.key,
    required this.kartlar,
    required this.yetkili,
    required this.onEkle,
    required this.onDetay,
  });

  /// Limit doluluk yüzdesi (limit tanımsızsa 0).
  static double doluluk(KrediKartiModel k) =>
      k.kartLimit > 0 ? k.kullanilanLimit / k.kartLimit * 100 : 0.0;

  @override
  State<KrediKartiMasaustuGorunum> createState() =>
      _KrediKartiMasaustuGorunumState();
}

class _KrediKartiMasaustuGorunumState extends State<KrediKartiMasaustuGorunum> {
  KrediKartiModel? _secili;

  static final _tarih = DateFormat('dd.MM.yyyy');

  late final List<TabloKolon<KrediKartiModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Kart',
        genislik: 200,
        esnek: true,
        deger: (k) => k.kartAdi,
        sirala: (k) => k.kartAdi.toLowerCase()),
    TabloKolon(
        baslik: 'Kart No',
        genislik: 150,
        deger: (k) => k.kartNoMaskeli,
        sirala: (k) => k.kartNoMaskeli),
    TabloKolon(
        baslik: 'Limit',
        genislik: 110,
        sagaYasli: true,
        deger: (k) => ParaUtils.formatla(k.kartLimit),
        sirala: (k) => k.kartLimit),
    TabloKolon(
        baslik: 'Kullanılan',
        genislik: 110,
        sagaYasli: true,
        deger: (k) => ParaUtils.formatla(k.kullanilanLimit),
        sirala: (k) => k.kullanilanLimit),
    TabloKolon(
        baslik: 'Kullanım',
        genislik: 80,
        sagaYasli: true,
        deger: (k) => '%${KrediKartiMasaustuGorunum.doluluk(k).toStringAsFixed(0)}',
        sirala: KrediKartiMasaustuGorunum.doluluk,
        renk: (k) => KrediKartiMasaustuGorunum.doluluk(k) > 80 ? TsRenk.hata : null),
    TabloKolon(
        baslik: 'Kesim',
        genislik: 100,
        deger: (k) => k.kesimTarihi == null ? '' : _tarih.format(k.kesimTarihi!),
        sirala: (k) => k.kesimTarihi ?? DateTime(9999)),
    TabloKolon(
        baslik: 'Son Ödeme',
        genislik: 100,
        deger: (k) => k.sonOdemeTarihi == null ? '' : _tarih.format(k.sonOdemeTarihi!),
        sirala: (k) => k.sonOdemeTarihi ?? DateTime(9999)),
    TabloKolon(
        baslik: 'Durum',
        genislik: 80,
        deger: (k) => k.aktif ? 'Aktif' : 'Pasif',
        renk: (k) => k.aktif ? TsRenk.basarili : TsRenk.uyari),
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

  KrediKartiModel? get _gecerliSecili {
    final s = _secili;
    if (s == null) return null;
    for (final k in widget.kartlar) {
      if (k.id == s.id) return k;
    }
    return null;
  }

  void _menu(KrediKartiModel k, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Kart Detayı', () => widget.onDetay(k), ikon: Icons.credit_card),
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
      if (s != null) widget.onDetay(s);
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.kartlar;
    final s = _gecerliSecili;
    final limit = l.fold(0.0, (t, k) => t + k.kartLimit);
    final kullanilan = l.fold(0.0, (t, k) => t + k.kullanilanLimit);
    return Column(children: [
      Expanded(
        child: l.isEmpty
            ? Center(
                child: Text(
                    widget.yetkili
                        ? 'Kredi kartı yok — F1 ile ekleyin'
                        : 'Kredi kartı bulunamadı',
                    style: TextStyle(fontSize: 15, color: context.textSecondary)))
            : MasaustuTablo<KrediKartiModel>(
                satirlar: l,
                kolonlar: _kolonlar,
                secili: s,
                onSec: (k) => setState(() => _secili = k),
                onCift: widget.onDetay,
                onSagTik: _menu,
              ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Kart', '${l.length}'),
          AltOzet('Toplam Limit', ParaUtils.formatla(limit)),
          AltOzet('Kullanılan', ParaUtils.formatla(kullanilan), renk: TsRenk.hata),
        ],
        tuslar: [
          if (widget.yetkili)
            AltTus('F1', 'Kart Ekle', Icons.add_card_outlined,
                const Color(0xFF2E7D32), widget.onEkle),
          AltTus('F2', 'Detay', Icons.credit_card, const Color(0xFF1565C0),
              s == null ? null : () => widget.onDetay(s)),
        ],
      ),
    ]);
  }
}
