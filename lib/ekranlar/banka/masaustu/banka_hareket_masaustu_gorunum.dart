// lib/ekranlar/banka/masaustu/banka_hareket_masaustu_gorunum.dart
//
// Banka hesabı / kredi kartı hareketleri — masaüstü tablo görünümü. Yön, renk
// ve işaret mobil karttakiyle AYNI kurala uyar: tutar hep pozitif saklanır,
// giriş/çıkış `islemTipi == 'Gelen'` ile belirlenir.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/banka_hareket_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class BankaHareketMasaustuGorunum extends StatefulWidget {
  final List<BankaHareketModel> hareketler;

  /// null ise (kredi kartı) "Hareket Ekle" tuşu/kısayolu gösterilmez.
  final VoidCallback? onEkle;
  final Future<void> Function() onYenile;

  const BankaHareketMasaustuGorunum({
    super.key,
    required this.hareketler,
    required this.onYenile,
    this.onEkle,
  });

  /// Para girişi mi? (Mobil kart ve tablo aynı kuralı kullanır.)
  static bool giris(BankaHareketModel h) => h.islemTipi == 'Gelen';

  @override
  State<BankaHareketMasaustuGorunum> createState() =>
      _BankaHareketMasaustuGorunumState();
}

class _BankaHareketMasaustuGorunumState
    extends State<BankaHareketMasaustuGorunum> {
  BankaHareketModel? _secili;

  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');

  late final List<TabloKolon<BankaHareketModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Tarih',
        genislik: 135,
        deger: (h) => _tarih.format(h.tarih),
        sirala: (h) => h.tarih),
    TabloKolon(
        baslik: 'İşlem',
        genislik: 90,
        deger: (h) => h.islemTipi,
        sirala: (h) => h.islemTipi,
        renk: (h) => BankaHareketMasaustuGorunum.giris(h) ? TsRenk.basarili : TsRenk.hata),
    TabloKolon(
        baslik: 'Açıklama',
        genislik: 240,
        esnek: true,
        deger: (h) => h.aciklama ?? '',
        sirala: (h) => (h.aciklama ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Kategori',
        genislik: 120,
        deger: (h) => h.kategori ?? '',
        sirala: (h) => (h.kategori ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Referans',
        genislik: 110,
        deger: (h) => h.referansNo ?? '',
        sirala: (h) => h.referansNo ?? ''),
    TabloKolon(
        baslik: 'Tutar',
        genislik: 130,
        sagaYasli: true,
        deger: (h) =>
            '${BankaHareketMasaustuGorunum.giris(h) ? '+' : '-'}${ParaUtils.formatla(h.tutar)}',
        sirala: (h) => BankaHareketMasaustuGorunum.giris(h) ? h.tutar : -h.tutar,
        renk: (h) => BankaHareketMasaustuGorunum.giris(h) ? TsRenk.basarili : TsRenk.hata),
    TabloKolon(
        baslik: 'Sonraki Bakiye',
        genislik: 130,
        sagaYasli: true,
        deger: (h) => h.sonrakiBakiye == null ? '' : ParaUtils.formatla(h.sonrakiBakiye!),
        sirala: (h) => h.sonrakiBakiye ?? 0),
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

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!ekranUstte(context)) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.f1 && widget.onEkle != null) {
      widget.onEkle!();
    } else if (k == LogicalKeyboardKey.f5) {
      widget.onYenile();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.hareketler;
    final giren = l
        .where(BankaHareketMasaustuGorunum.giris)
        .fold(0.0, (t, h) => t + h.tutar);
    final cikan = l
        .where((h) => !BankaHareketMasaustuGorunum.giris(h))
        .fold(0.0, (t, h) => t + h.tutar);
    return Column(children: [
      Expanded(
        child: l.isEmpty
            ? const Center(child: Text('Henüz hareket yok'))
            : MasaustuTablo<BankaHareketModel>(
                satirlar: l,
                kolonlar: _kolonlar,
                secili: _secili,
                onSec: (h) => setState(() => _secili = h),
              ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Kayıt', '${l.length}'),
          AltOzet('Giriş', ParaUtils.formatla(giren), renk: TsRenk.basarili),
          AltOzet('Çıkış', ParaUtils.formatla(cikan), renk: TsRenk.hata),
        ],
        tuslar: [
          if (widget.onEkle != null)
            AltTus('F1', 'Hareket Ekle', Icons.add_circle_outline,
                const Color(0xFF2E7D32), widget.onEkle),
          AltTus('F5', 'Yenile', Icons.refresh, const Color(0xFF455A64),
              () => widget.onYenile()),
        ],
      ),
    ]);
  }
}
