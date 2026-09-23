// lib/widgetlar/ortak/donanim_barkod_dinleyici.dart
//
// El terminali (Zebra/Honeywell/Urovo vb. — tarama tuşu) ve PC'deki USB/
// Bluetooth barkod okuyucular varsayılan olarak KLAVYE gibi davranır:
// barkodun karakterlerini çok hızlı (tipik 5–30 ms arayla) "yazar" ve
// sonuna Enter basar. Bu widget, ekranda hiçbir metin kutusu odakta
// DEĞİLKEN bu hızlı karakter akışını yakalayıp [onBarkod]'a iletir —
// böylece kasiyer sepete dokunduktan sonra bile okutma çalışır. Bir metin
// kutusu odaktaysa dokunmaz (girdi o kutuya gider; o kutunun kendi
// onSubmitted'ı barkodu işler).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tuş vuruşlarından okuyucu kaynaklı barkodu ayırt eden saf mantık
/// (widget'tan bağımsız, birim testi yazılabilir).
class BarkodTusTamponu {
  /// İki karakter arası bundan uzunsa akış insan yazması sayılır ve
  /// tampon sıfırlanır.
  final Duration maxAralik;
  final int minUzunluk;

  BarkodTusTamponu({
    this.maxAralik = const Duration(milliseconds: 80),
    this.minUzunluk = 3,
  });

  final StringBuffer _tampon = StringBuffer();
  DateTime? _sonTus;

  /// Bir karakter geldiğinde çağrılır.
  void karakter(String c, DateTime zaman) {
    if (_sonTus != null && zaman.difference(_sonTus!) > maxAralik) {
      _tampon.clear();
    }
    _tampon.write(c);
    _sonTus = zaman;
  }

  /// Enter geldiğinde çağrılır; tampon geçerli bir okuyucu barkodu ise
  /// onu döndürür (ve tamponu temizler), değilse null.
  String? enter(DateTime zaman) {
    final metin = _tampon.toString().trim();
    final tazeMi = _sonTus != null && zaman.difference(_sonTus!) <= maxAralik;
    _tampon.clear();
    _sonTus = null;
    if (!tazeMi || metin.length < minUzunluk) return null;
    return metin;
  }

  void sifirla() {
    _tampon.clear();
    _sonTus = null;
  }
}

class DonanimBarkodDinleyici extends StatefulWidget {
  final ValueChanged<String> onBarkod;
  final Widget child;

  /// false ise dinleme geçici olarak kapalı (ör. ödeme/dialog sürerken).
  final bool aktif;

  const DonanimBarkodDinleyici({
    super.key,
    required this.onBarkod,
    required this.child,
    this.aktif = true,
  });

  @override
  State<DonanimBarkodDinleyici> createState() => _DonanimBarkodDinleyiciState();
}

class _DonanimBarkodDinleyiciState extends State<DonanimBarkodDinleyici> {
  final _tampon = BarkodTusTamponu();

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

  bool _metinKutusuOdakta() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _tusGeldi(KeyEvent event) {
    if (!mounted || !widget.aktif) return false;
    // Bu ekranın üstünde başka bir sayfa/dialog varsa karışma.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (_metinKutusuOdakta()) {
      _tampon.sifirla();
      return false;
    }
    if (event is! KeyDownEvent) return false;

    final simdi = DateTime.now();
    final tus = event.logicalKey;
    if (tus == LogicalKeyboardKey.enter || tus == LogicalKeyboardKey.numpadEnter) {
      final barkod = _tampon.enter(simdi);
      if (barkod == null) return false;
      widget.onBarkod(barkod);
      return true;
    }
    final c = event.character;
    if (c != null && c.length == 1 && c.codeUnitAt(0) >= 0x20) {
      _tampon.karakter(c, simdi);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Metin kutusuna yazılan bir girdinin barkod gibi görünüp görünmediği
/// (yalnızca rakam, en az 4 hane). Harf içeren girdiler ürün adı araması
/// sayılır.
bool barkodaBenziyor(String s) => RegExp(r'^\d{4,}$').hasMatch(s.trim());
