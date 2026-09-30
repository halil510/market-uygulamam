// lib/ekranlar/satis/masaustu/masaustu_hizli_satis_duzeni.dart
//
// Masaüstü Hızlı Satış — tüm parçaları birleştiren düzen (BarkoPOS benzeri):
//
//   ┌───────────────────────────────┬──────────────────┐
//   │ arama                         │  TOPLAM  0,00    │
//   │ sepet tablosu                 │  F12 Ödeme       │
//   │───────────────────────────────│  F tuşları       │
//   │ grup sekmeleri + ürün tuşları │  sayı tuşları    │
//   └───────────────────────────────┴──────────────────┘
//
// Sadece GÖRÜNÜM + klavye kısayolları: iş mantığı (ödeme, sepete ekleme,
// müşteri seçimi…) çağıran ekrandan geri-çağrı (callback) ile gelir.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../modeller/sepet_model.dart';
import '../../../modeller/urun_model.dart';
import '../../../saglayicilar/riverpod/sepet_provider.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import 'masaustu_f_tuslari.dart';
import 'masaustu_sayi_tuslari.dart';
import 'masaustu_sepet_tablosu.dart';
import 'masaustu_toplam_karti.dart';
import 'masaustu_urun_izgarasi.dart';

class MasaustuHizliSatisDuzeni extends ConsumerStatefulWidget {
  final Widget aramaPaneli;

  /// Arama sonucu varsa (liste) tablo+ızgara yerine gösterilir.
  final Widget? aramaSonuclari;
  final ScrollController sepetScroll;
  final void Function(UrunModel urun) onUrunSec;
  final void Function(SepetKalem kalem, int index) onKalemDuzenle;
  final VoidCallback onOdeme;
  final VoidCallback onAramaOdak;
  final VoidCallback onStok;
  final VoidCallback onAskiyaAl;
  final VoidCallback? onSonFis; // null = henüz satış yok
  final VoidCallback onCari;
  final VoidCallback onFiyatGor;

  const MasaustuHizliSatisDuzeni({
    super.key,
    required this.aramaPaneli,
    required this.aramaSonuclari,
    required this.sepetScroll,
    required this.onUrunSec,
    required this.onKalemDuzenle,
    required this.onOdeme,
    required this.onAramaOdak,
    required this.onStok,
    required this.onAskiyaAl,
    required this.onSonFis,
    required this.onCari,
    required this.onFiyatGor,
  });

  @override
  ConsumerState<MasaustuHizliSatisDuzeni> createState() =>
      _MasaustuHizliSatisDuzeniState();
}

class _MasaustuHizliSatisDuzeniState
    extends ConsumerState<MasaustuHizliSatisDuzeni> {
  int? _secili;
  String _tampon = '';
  double _alinan = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tusGeldi);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tusGeldi);
    super.dispose();
  }

  // ── Klavye kısayolları ────────────────────────────────────────────────
  bool _metinKutusuOdakta() {
    final odak = FocusManager.instance.primaryFocus;
    return odak?.context?.widget is EditableText;
  }

  bool _tusGeldi(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    // Üstte diyalog/başka ekran varsa dokunma.
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final k = e.logicalKey;
    final sepet = ref.read(sepetProvider);
    final odemeAktif = !sepet.bos && !sepet.satisIsleniyor;

    if (k == LogicalKeyboardKey.f2) {
      widget.onAramaOdak();
    } else if (k == LogicalKeyboardKey.f3) {
      widget.onStok();
    } else if (k == LogicalKeyboardKey.f4) {
      if (!sepet.bos) widget.onAskiyaAl();
    } else if (k == LogicalKeyboardKey.f5) {
      widget.onSonFis?.call();
    } else if (k == LogicalKeyboardKey.f7) {
      widget.onCari();
    } else if (k == LogicalKeyboardKey.f8) {
      widget.onFiyatGor();
    } else if (k == LogicalKeyboardKey.f9) {
      _sepetiTemizle();
    } else if (k == LogicalKeyboardKey.f12) {
      if (odemeAktif) widget.onOdeme();
    } else if (k == LogicalKeyboardKey.delete && !_metinKutusuOdakta()) {
      _seciliyiSil();
    } else if (k == LogicalKeyboardKey.escape && !_metinKutusuOdakta()) {
      setState(() {
        _tampon = '';
        _alinan = 0;
        _secili = null;
      });
    } else if (!_metinKutusuOdakta() &&
        (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp)) {
      _seciliyiKaydir(k == LogicalKeyboardKey.arrowDown ? 1 : -1, sepet);
    } else {
      return false;
    }
    return true;
  }

  void _seciliyiKaydir(int yon, SepetDurum sepet) {
    if (sepet.bos) return;
    final son = sepet.kalemler.length - 1;
    setState(() => _secili = ((_secili ?? (yon > 0 ? -1 : son + 1)) + yon).clamp(0, son));
  }

  // ── Sepet işlemleri ───────────────────────────────────────────────────
  void _seciliyiSil() {
    final s = _secili;
    if (s == null) return;
    ref.read(sepetProvider.notifier).sil(s);
    setState(() => _secili = null);
  }

  Future<void> _sepetiTemizle() async {
    if (ref.read(sepetProvider).bos) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sepeti temizle'),
        content: const Text('Sepetteki tüm ürünler silinecek. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Temizle')),
        ],
      ),
    );
    if (onay == true && mounted) ref.read(sepetProvider.notifier).temizle();
  }

  // ── Sayı tuş takımı ───────────────────────────────────────────────────
  double? get _tamponSayi => double.tryParse(_tampon.replaceAll(',', '.'));

  void _karakter(String c) {
    if (c == ',' && (_tampon.contains(',') || _tampon.isEmpty)) {
      if (_tampon.isEmpty) setState(() => _tampon = '0,');
      return;
    }
    if (_tampon.length >= 9) return;
    setState(() => _tampon += c);
  }

  void _miktarUygula() {
    final sepet = ref.read(sepetProvider);
    final n = _tamponSayi;
    if (sepet.bos || n == null || n <= 0) return;
    final i = _secili ?? sepet.kalemler.length - 1;
    ref.read(sepetProvider.notifier).miktarGuncelle(i, n);
    setState(() => _tampon = '');
  }

  void _alinanUygula() {
    final n = _tamponSayi;
    if (n == null) return;
    setState(() {
      _alinan = n;
      _tampon = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final sepet = ref.watch(sepetProvider);
    // Satış bitip sepet boşalınca yerel durumu sıfırla.
    ref.listen<SepetDurum>(sepetProvider, (onceki, yeni) {
      if (yeni.bos && (onceki?.bos == false)) {
        setState(() {
          _secili = null;
          _tampon = '';
          _alinan = 0;
        });
      } else if (_secili != null && _secili! >= yeni.kalemler.length) {
        setState(() => _secili = null);
      }
    });

    final odemeAktif = !sepet.bos && !sepet.satisIsleniyor;
    return Row(children: [
      Expanded(child: _sol(sepet)),
      VerticalDivider(width: 1, thickness: 1, color: context.borderColor),
      SizedBox(width: 350, child: _sag(sepet, odemeAktif)),
    ]);
  }

  Widget _sol(SepetDurum sepet) {
    return Column(children: [
      widget.aramaPaneli,
      if (widget.aramaSonuclari != null)
        Expanded(child: SingleChildScrollView(child: widget.aramaSonuclari!))
      else ...[
        Expanded(
          flex: 11,
          child: MasaustuSepetTablosu(
            kalemler: sepet.kalemler,
            seciliIndex: _secili,
            scrollController: widget.sepetScroll,
            onSec: (i) => setState(() => _secili = i),
            onDuzenle: widget.onKalemDuzenle,
            onSil: (i) {
              ref.read(sepetProvider.notifier).sil(i);
              setState(() => _secili = null);
            },
          ),
        ),
        Divider(height: 1, color: context.borderColor),
        Expanded(
          flex: 10,
          child: MasaustuUrunIzgarasi(onUrunSec: widget.onUrunSec),
        ),
      ],
    ]);
  }

  Widget _sag(SepetDurum sepet, bool odemeAktif) {
    return Column(children: [
      MasaustuToplamKarti(sepet: sepet, alinanPara: _alinan),
      MasaustuFTuslari(
        ana: FTus('F12', 'ÖDEME', const Color(0xFFD32F2F),
            odemeAktif ? widget.onOdeme : null),
        tuslar: [
          FTus('F2', 'Ara', const Color(0xFFF9A825), widget.onAramaOdak),
          FTus('F3', 'Stok', const Color(0xFFC62828), widget.onStok),
          FTus('F4', 'Askıya Al', const Color(0xFF2E7D32),
              sepet.bos ? null : widget.onAskiyaAl),
          FTus('F5', 'Son Fiş', const Color(0xFF6A1B9A), widget.onSonFis),
          FTus('F7', 'Cari', const Color(0xFF1565C0), widget.onCari),
          FTus('F8', 'Fiyat Gör', const Color(0xFF00838F), widget.onFiyatGor),
          FTus('F9', 'Temizle', const Color(0xFF546E7A),
              sepet.bos ? null : _sepetiTemizle),
          FTus('Del', 'Satır Sil', const Color(0xFF8D6E63),
              _secili == null ? null : _seciliyiSil),
        ],
      ),
      Expanded(
        child: MasaustuSayiTuslari(
          tampon: _tampon,
          onKarakter: _karakter,
          onGeri: () => setState(() {
            if (_tampon.isNotEmpty) _tampon = _tampon.substring(0, _tampon.length - 1);
          }),
          onTemizle: () => setState(() {
            _tampon = '';
            _alinan = 0;
          }),
          onMiktar: _miktarUygula,
          onAlinan: _alinanUygula,
          onHizliPara: (p) => setState(() => _alinan += p),
          onFiyatGor: widget.onFiyatGor,
        ),
      ),
    ]);
  }
}
