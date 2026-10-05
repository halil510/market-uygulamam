// lib/ekranlar/banka/masaustu/banka_masaustu_gorunum.dart
//
// Bankalar ve Banka Hesapları — masaüstü (geniş pencere) tablo görünümleri:
// tablo + alt şerit + sağ tık menüsü + F1/F2/F3/F4/F6 kısayolları.
// Sadece görünüm; silme ve yenileme çağıran ekrandan gelir.
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/banka_hesap_model.dart';
import '../../../modeller/banka_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

/// Ortak: görünür sekme/rota için F-tuşu dinleyicisi kaydı.
mixin _FTusDinleyici<T extends StatefulWidget> on State<T> {
  bool tusIsle(LogicalKeyboardKey k);

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!TickerMode.of(context)) return false;
    if (!ekranUstte(context)) return false;
    return tusIsle(e.logicalKey);
  }

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
}

// ─── BANKALAR ────────────────────────────────────────────────────────────────

class BankaMasaustuGorunum extends StatefulWidget {
  final List<BankaModel> bankalar;
  final Future<void> Function(BankaModel banka) onSil;
  final Future<void> Function() onYenile;

  const BankaMasaustuGorunum({
    super.key,
    required this.bankalar,
    required this.onSil,
    required this.onYenile,
  });

  @override
  State<BankaMasaustuGorunum> createState() => _BankaMasaustuGorunumState();
}

class _BankaMasaustuGorunumState extends State<BankaMasaustuGorunum>
    with _FTusDinleyici<BankaMasaustuGorunum> {
  BankaModel? _secili;

  final List<TabloKolon<BankaModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Kod',
        genislik: 100,
        deger: (b) => b.kod ?? '',
        sirala: (b) => b.kod ?? ''),
    TabloKolon(
        baslik: 'Banka Adı',
        genislik: 240,
        esnek: true,
        deger: (b) => b.ad,
        sirala: (b) => b.ad.toLowerCase()),
    TabloKolon(baslik: 'Telefon', genislik: 130, deger: (b) => b.tel ?? ''),
    TabloKolon(
        baslik: 'Yetkili',
        genislik: 160,
        deger: (b) => b.yetkili ?? '',
        sirala: (b) => b.yetkili ?? ''),
    TabloKolon(baslik: 'E-posta', genislik: 200, deger: (b) => b.email ?? ''),
    TabloKolon(baslik: 'Durum', genislik: 80, deger: (b) => b.aktif ? 'Aktif' : 'Pasif'),
  ];

  Future<void> _ekle() async {
    final eklendi = await context.push<bool>('/banka/ekle');
    if (eklendi == true && mounted) widget.onYenile();
  }

  Future<void> _duzenle(BankaModel b) async {
    final guncellendi = await context.push<bool>('/banka/ekle', extra: b);
    if (guncellendi == true && mounted) widget.onYenile();
  }

  Future<void> _git(String yol) async {
    await context.push(yol);
    if (mounted) widget.onYenile();
  }

  void _menu(BankaModel b, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Banka Detayı', () => _git('/banka/detay/${b.id}'),
          ikon: Icons.business_outlined),
      MenuOge('Hesaplar', () => _git('/banka/hesaplar/${b.id}'),
          ikon: Icons.account_balance_outlined),
      MenuOge('Düzenle', () => _duzenle(b), ikon: Icons.edit_outlined, ayiracOnce: true),
      MenuOge('Sil', () => widget.onSil(b), ikon: Icons.delete_outline, ayiracOnce: true),
    ]);
  }

  @override
  bool tusIsle(LogicalKeyboardKey k) {
    final s = _secili;
    if (k == LogicalKeyboardKey.f1) {
      _ekle();
    } else if (k == LogicalKeyboardKey.f2) {
      if (s != null) _duzenle(s);
    } else if (k == LogicalKeyboardKey.f3) {
      if (s != null) widget.onSil(s);
    } else if (k == LogicalKeyboardKey.f4) {
      if (s != null) _git('/banka/hesaplar/${s.id}');
    } else if (k == LogicalKeyboardKey.f6) {
      if (s != null) _menu(s, const Offset(400, 250));
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.bankalar;
    final s = _secili;
    return Column(children: [
      Expanded(
        child: MasaustuTablo<BankaModel>(
          satirlar: l,
          kolonlar: _kolonlar,
          secili: s,
          onSec: (b) => setState(() => _secili = b),
          onCift: (b) => _git('/banka/detay/${b.id}'),
          onSagTik: _menu,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Banka Sayısı', '${l.length}'),
          AltOzet('Aktif', '${l.where((b) => b.aktif).length}'),
        ],
        tuslar: [
          AltTus('F1', 'Ekle', Icons.add_business_outlined, const Color(0xFF2E7D32), _ekle),
          AltTus('F2', 'Düzenle', Icons.edit_outlined, const Color(0xFF1565C0),
              s == null ? null : () => _duzenle(s)),
          AltTus('F3', 'Sil', Icons.delete_outline, const Color(0xFFC62828),
              s == null ? null : () => widget.onSil(s)),
          AltTus('F4', 'Hesaplar', Icons.account_balance_outlined, const Color(0xFF6A1B9A),
              s == null ? null : () => _git('/banka/hesaplar/${s.id}')),
          AltTus('F6', 'Menü', Icons.menu, const Color(0xFF546E7A),
              s == null ? null : () => _menu(s, const Offset(400, 250))),
        ],
      ),
    ]);
  }
}

// ─── BANKA HESAPLARI ─────────────────────────────────────────────────────────

class BankaHesapMasaustuGorunum extends StatefulWidget {
  final int bankaId;
  final List<BankaHesapModel> hesaplar;
  final Future<void> Function() onYenile;

  const BankaHesapMasaustuGorunum({
    super.key,
    required this.bankaId,
    required this.hesaplar,
    required this.onYenile,
  });

  @override
  State<BankaHesapMasaustuGorunum> createState() => _BankaHesapMasaustuGorunumState();
}

class _BankaHesapMasaustuGorunumState extends State<BankaHesapMasaustuGorunum>
    with _FTusDinleyici<BankaHesapMasaustuGorunum> {
  BankaHesapModel? _secili;

  static String _bakiyeMetni(BankaHesapModel h) => h.paraBirimi == 'TRY'
      ? ParaUtils.formatla(h.bakiye, simge: '')
      : '${ParaUtils.formatla(h.bakiye, simge: '')} ${h.paraBirimi}';

  final List<TabloKolon<BankaHesapModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Hesap Adı',
        genislik: 200,
        esnek: true,
        deger: (h) => h.hesapAdi,
        sirala: (h) => h.hesapAdi.toLowerCase()),
    TabloKolon(baslik: 'Hesap No', genislik: 130, deger: (h) => h.hesapNo),
    TabloKolon(baslik: 'IBAN', genislik: 230, deger: (h) => h.iban ?? ''),
    TabloKolon(baslik: 'Şube', genislik: 140, deger: (h) => h.subeAdi ?? ''),
    TabloKolon(
        baslik: 'Tür',
        genislik: 100,
        deger: (h) => h.hesapTuru ?? '',
        sirala: (h) => h.hesapTuru ?? ''),
    TabloKolon(baslik: 'Para Birimi', genislik: 90, deger: (h) => h.paraBirimi),
    TabloKolon(
        baslik: 'Bakiye',
        genislik: 140,
        sagaYasli: true,
        deger: _bakiyeMetni,
        sirala: (h) => h.bakiye,
        renk: (h) => h.bakiye < 0 ? TsRenk.hata : null),
  ];

  Future<void> _ekle() async {
    final eklendi = await context.push<bool>('/banka/hesap-ekle/${widget.bankaId}');
    if (eklendi == true && mounted) widget.onYenile();
  }

  Future<void> _hareketler(BankaHesapModel h) async {
    await context.push('/banka-hareket', extra: {'hesapId': h.id});
    if (mounted) widget.onYenile();
  }

  void _menu(BankaHesapModel h, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Hesap Hareketleri', () => _hareketler(h), ikon: Icons.receipt_long_outlined),
    ]);
  }

  @override
  bool tusIsle(LogicalKeyboardKey k) {
    final s = _secili;
    if (k == LogicalKeyboardKey.f1) {
      _ekle();
    } else if (k == LogicalKeyboardKey.f2) {
      if (s != null) _hareketler(s);
    } else if (k == LogicalKeyboardKey.f6) {
      if (s != null) _menu(s, const Offset(400, 250));
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.hesaplar;
    final s = _secili;
    final tryToplam = l
        .where((h) => h.paraBirimi == 'TRY')
        .fold<double>(0, (t, h) => t + h.bakiye);
    return Column(children: [
      Expanded(
        child: MasaustuTablo<BankaHesapModel>(
          satirlar: l,
          kolonlar: _kolonlar,
          secili: s,
          onSec: (h) => setState(() => _secili = h),
          onCift: _hareketler,
          onSagTik: _menu,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Hesap Sayısı', '${l.length}'),
          AltOzet('Toplam Bakiye (TL)', ParaUtils.formatla(tryToplam)),
        ],
        tuslar: [
          AltTus('F1', 'Hesap Ekle', Icons.add_card_outlined, const Color(0xFF2E7D32), _ekle),
          AltTus('F2', 'Hareketler', Icons.receipt_long_outlined, const Color(0xFF1565C0),
              s == null ? null : () => _hareketler(s)),
          AltTus('F6', 'Menü', Icons.menu, const Color(0xFF546E7A),
              s == null ? null : () => _menu(s, const Offset(400, 250))),
        ],
      ),
    ]);
  }
}
