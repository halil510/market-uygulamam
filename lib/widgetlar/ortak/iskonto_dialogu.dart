// lib/widgetlar/ortak/iskonto_dialogu.dart
//
// Hızlı Satış İskonto (masaüstü F6 + mobil uzun basış). Üç alan birbirini hesaplar:
//   İndirim oranı (%)  ↔  İndirim tutarı (TL)  ↔  Yeni toplam
// Örn. 60 TL × 2 = 120: toplamı 100 yaz → oran %16,67 / tutar 20 görünür;
// %10 yaz → tutar 12, yeni toplam 108 görünür.
// Hesap, ürünün LİSTE fiyatı (brüt) üzerinden yapılır; sonuç sepete ürün
// birim fiyatı düşürülerek yansıtılır (fişte kalem indirimi olarak kaydolur).
import 'package:flutter/material.dart';
import '../../../cekirdek/utils/para_utils.dart';

/// [brutToplam] indirim öncesi (liste fiyatı × miktar) toplam. Onaylanırsa
/// hedeflenen YENİ TOPLAM döner (brüte eşitse indirim kaldırılır), iptalde null.
Future<double?> iskontoDialoguGoster(
  BuildContext context, {
  required String baslik,
  required double brutToplam,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _IskontoDialogu(baslik: baslik, brutToplam: brutToplam),
  );
}

class _IskontoDialogu extends StatefulWidget {
  final String baslik;
  final double brutToplam;
  const _IskontoDialogu({required this.baslik, required this.brutToplam});

  @override
  State<_IskontoDialogu> createState() => _IskontoDialoguState();
}

class _IskontoDialoguState extends State<_IskontoDialogu> {
  final _oranCtrl = TextEditingController();
  final _tutarCtrl = TextEditingController();
  final _yeniCtrl = TextEditingController();
  String? _hata;

  double get _brut => widget.brutToplam;

  @override
  void dispose() {
    _oranCtrl.dispose();
    _tutarCtrl.dispose();
    _yeniCtrl.dispose();
    super.dispose();
  }

  String _bicim(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  void _doldur(
      {String? oran, String? tutar, String? yeni}) {
    if (oran != null) _oranCtrl.text = oran;
    if (tutar != null) _tutarCtrl.text = tutar;
    if (yeni != null) _yeniCtrl.text = yeni;
  }

  void _oranDegisti(String s) {
    final o = ParaUtils.sayiCoz(s);
    setState(() => _hata = null);
    if (o == null || _brut <= 0) {
      _doldur(tutar: '', yeni: '');
      return;
    }
    final tutar = _brut * o / 100;
    _doldur(tutar: _bicim(tutar), yeni: _bicim(_brut - tutar));
  }

  void _tutarDegisti(String s) {
    final t = ParaUtils.sayiCoz(s);
    setState(() => _hata = null);
    if (t == null || _brut <= 0) {
      _doldur(oran: '', yeni: '');
      return;
    }
    _doldur(oran: _bicim(t / _brut * 100), yeni: _bicim(_brut - t));
  }

  void _yeniDegisti(String s) {
    final y = ParaUtils.sayiCoz(s);
    setState(() => _hata = null);
    if (y == null || _brut <= 0) {
      _doldur(oran: '', tutar: '');
      return;
    }
    final tutar = _brut - y;
    _doldur(oran: _bicim(tutar / _brut * 100), tutar: _bicim(tutar));
  }

  void _tamam() {
    final yeni = ParaUtils.sayiCoz(_yeniCtrl.text);
    if (yeni == null || yeni <= 0) {
      setState(() => _hata = 'Geçerli bir değer girin');
      return;
    }
    if (yeni > _brut + 0.005) {
      setState(() => _hata = 'Yeni toplam, ${ParaUtils.formatla(_brut)} tutarını aşamaz');
      return;
    }
    // Brüte eşit = indirimi kaldır.
    Navigator.pop(context, yeni > _brut ? _brut : yeni);
  }

  InputDecoration _dekor(String etiket, String ek) => InputDecoration(
        labelText: etiket,
        suffixText: ek,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    const buyuk = TextStyle(fontSize: 22, fontWeight: FontWeight.w800);
    return AlertDialog(
      title: Text(widget.baslik,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('İndirim öncesi toplam: ${ParaUtils.formatla(_brut)}',
                style: const TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _oranCtrl,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: buyuk,
            decoration: _dekor('İndirim oranı', '%'),
            onChanged: _oranDegisti,
            onSubmitted: (_) => _tamam(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tutarCtrl,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: buyuk,
            decoration: _dekor('İndirim tutarı', '₺'),
            onChanged: _tutarDegisti,
            onSubmitted: (_) => _tamam(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _yeniCtrl,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: buyuk.copyWith(color: Theme.of(context).colorScheme.primary),
            decoration: _dekor('Yeni toplam', '₺').copyWith(errorText: _hata),
            onChanged: _yeniDegisti,
            onSubmitted: (_) => _tamam(),
          ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(onPressed: _tamam, child: const Text('Uygula')),
      ],
    );
  }
}
