// lib/ekranlar/personel/masaustu/personel_masaustu_gorunum.dart
//
// Personel listesi — masaüstü tablo görünümü: tablo + alt şerit + sağ tık
// menüsü + F1/F2 kısayolları. Sadece görünüm; ekleme ve detay/düzenleme
// çağıran ekrandan gelir (mobildeki aynı alt pencereler). Ekle yalnız
// Admin/Müdür'e görünür; detay herkese açıktır (mobille aynı).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/personel_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class PersonelMasaustuGorunum extends StatefulWidget {
  final List<PersonelModel> personeller;
  final bool yetkili;
  final VoidCallback onEkle;
  final void Function(PersonelModel p) onDetay;

  const PersonelMasaustuGorunum({
    super.key,
    required this.personeller,
    required this.yetkili,
    required this.onEkle,
    required this.onDetay,
  });

  @override
  State<PersonelMasaustuGorunum> createState() => _PersonelMasaustuGorunumState();
}

class _PersonelMasaustuGorunumState extends State<PersonelMasaustuGorunum> {
  PersonelModel? _secili;

  static final _tarih = DateFormat('dd.MM.yyyy');

  late final List<TabloKolon<PersonelModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Ad Soyad',
        genislik: 220,
        esnek: true,
        deger: (p) => p.adSoyad,
        sirala: (p) => p.adSoyad.toLowerCase()),
    TabloKolon(
        baslik: 'Pozisyon',
        genislik: 150,
        deger: (p) => p.pozisyon ?? '',
        sirala: (p) => (p.pozisyon ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Telefon',
        genislik: 130,
        deger: (p) => p.telefon ?? '',
        sirala: (p) => p.telefon ?? ''),
    TabloKolon(
        baslik: 'Maaş',
        genislik: 120,
        sagaYasli: true,
        deger: (p) => p.maas > 0 ? ParaUtils.formatla(p.maas) : '',
        sirala: (p) => p.maas),
    TabloKolon(
        baslik: 'İşe Başlama',
        genislik: 105,
        deger: (p) => p.iseBaslama == null ? '' : _tarih.format(p.iseBaslama!),
        sirala: (p) => p.iseBaslama ?? DateTime(1970)),
    TabloKolon(
        baslik: 'Durum',
        genislik: 90,
        deger: (p) => p.aktif ? 'Aktif' : 'Pasif',
        sirala: (p) => p.aktif ? 0 : 1,
        renk: (p) => p.aktif ? TsRenk.basarili : TsRenk.hata),
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

  /// Liste yenilenince/filtrelenince seçili satırı güncel kopyayla eşle.
  PersonelModel? get _gecerliSecili {
    final s = _secili;
    if (s == null) return null;
    for (final p in widget.personeller) {
      if (p.id == s.id) return p;
    }
    return null;
  }

  void _menu(PersonelModel p, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Detay / Düzenle', () => widget.onDetay(p), ikon: Icons.edit_outlined),
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
    final l = widget.personeller;
    final s = _gecerliSecili;
    final aktif = l.where((p) => p.aktif).length;
    final maas = l.where((p) => p.aktif).fold(0.0, (t, p) => t + p.maas);
    return Column(children: [
      Expanded(
        child: l.isEmpty
            ? Center(
                child: Text(
                    widget.yetkili ? 'Personel yok — F1 ile ekleyin' : 'Personel bulunamadı',
                    style: TextStyle(fontSize: 15, color: context.textSecondary)))
            : MasaustuTablo<PersonelModel>(
                satirlar: l,
                kolonlar: _kolonlar,
                secili: s,
                onSec: (p) => setState(() => _secili = p),
                onCift: widget.onDetay,
                onSagTik: _menu,
              ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Personel', '${l.length}'),
          AltOzet('Aktif', '$aktif', renk: TsRenk.basarili),
          AltOzet('Aylık Maaş (aktif)', ParaUtils.formatla(maas)),
        ],
        tuslar: [
          if (widget.yetkili)
            AltTus('F1', 'Ekle', Icons.person_add_alt_1_outlined,
                const Color(0xFF2E7D32), widget.onEkle),
          AltTus('F2', 'Detay / Düzenle', Icons.edit_outlined,
              const Color(0xFF1565C0), s == null ? null : () => widget.onDetay(s)),
        ],
      ),
    ]);
  }
}
