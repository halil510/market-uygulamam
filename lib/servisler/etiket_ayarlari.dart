// lib/servisler/etiket_ayarlari.dart
//
// Etiket basımının TEK ayar kaynağı (cihazda, SharedPreferences):
//   • Seçili etiket tasarımı — hazır BarTender şablonu ya da kullanıcının kendi tasarımı,
//   • Kullanıcının kendi tasarımları (JSON listesi),
//   • Etiket yazıcısı: basma yolu (etiket yazıcısı TSPL / fiş yazıcısı / Windows yazıcısı), Windows yazıcısının adı,
//     TSPL ağ adresi ve ayarları, kâğıt (rulo / A4), varsayılan menşei.
// Etiket Yazdırma ekranı, önizleme penceresi ve ürün ekranlarındaki "Etiket yazdır" düğmeleri hep buradan okur:
// bir yerde seçilen tasarım / yazıcı her yerde aynen kullanılır.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cekirdek/etiket/etiket_tasarimi.dart';
import '../cekirdek/etiket/raf_etiket_sablonlari.dart';
import '../cekirdek/etiket/tspl.dart';
import 'etiket_ag_gonderici.dart';
import 'raf_etiket_pdf_servisi.dart' show RafEtiketKagidi;

/// Ayarlarda saklanan anahtarlar (eski sürümlerle AYNI — kullanıcının seçimleri korunur).
class RafEtiketAyar {
  RafEtiketAyar._();
  static const sablon = 'raf_etiket_sablon'; // seçili tasarımın kimliği
  static const mensei = 'raf_etiket_mensei';
  static const kagit = 'raf_etiket_kagit';
  static const yontem = 'raf_etiket_yontem'; // RafBasmaYontemi.name
  static const windowsYazici = 'raf_etiket_windows_yazici';
  static const tsplBosluk = 'raf_etiket_tspl_bosluk';
  static const tsplTers = 'raf_etiket_tspl_ters';
  static const tsplKoyuluk = 'raf_etiket_tspl_koyuluk';
  static const tsplAdres = 'raf_etiket_tspl_adres'; // IP[:port]; boşsa bağlı yazıcıya
  static const kendiTasarimlar = 'etiket_kendi_tasarimlar'; // JSON liste
  static const eskiSablonlar = 'etiket_ozel_sablonlar'; // eski serbest etiket kayıtları (göç edilir)
  static const gocYapildi = 'etiket_tasarim_goc_v1';
}

enum RafBasmaYontemi { tspl, escpos, windows }

bool get _windows => !kIsWeb && Platform.isWindows;

// ───────────────────────── Yazıcı ayarı ─────────────────────────

class EtiketYaziciAyari {
  final RafBasmaYontemi yontem;
  final String windowsYazici;
  final String tsplAdres;
  final TsplAyar tspl;
  final RafEtiketKagidi kagit;
  final String mensei;
  const EtiketYaziciAyari({
    required this.yontem,
    this.windowsYazici = '',
    this.tsplAdres = '',
    this.tspl = const TsplAyar(),
    this.kagit = RafEtiketKagidi.rulo,
    this.mensei = 'Türkiye',
  });

  /// TSPL ayrı bir ağ adresine mi gidiyor (fiş yazıcısı bağlantısından bağımsız)?
  bool get tsplAgda => etiketAdresCoz(tsplAdres) != null;

  /// A4 yalnız Windows yazıcısıyla basılır (etiket / fiş yazıcısı rulodur).
  RafEtiketKagidi get etkinKagit => yontem == RafBasmaYontemi.windows ? kagit : RafEtiketKagidi.rulo;

  /// Kısa açıklama: "Windows: Xprinter XP-490B", "Etiket yazıcısı 192.168.1.35", …
  String ozet({String? bagliYazici}) => switch (yontem) {
        RafBasmaYontemi.windows => windowsYazici.isEmpty
            ? 'Windows yazıcısı (seçilmedi)'
            : 'Windows: $windowsYazici${kagit == RafEtiketKagidi.a4 ? ' · A4' : ''}',
        RafBasmaYontemi.tspl => tsplAgda
            ? 'Etiket yazıcısı (TSPL) · $tsplAdres'
            : 'Etiket yazıcısı (TSPL) · ${bagliYazici ?? 'bağlı yazıcı yok'}',
        RafBasmaYontemi.escpos => 'Fiş yazıcısı · ${bagliYazici ?? 'bağlı yazıcı yok'}',
      };

  EtiketYaziciAyari kopya({
    RafBasmaYontemi? yontem,
    String? windowsYazici,
    String? tsplAdres,
    TsplAyar? tspl,
    RafEtiketKagidi? kagit,
    String? mensei,
  }) =>
      EtiketYaziciAyari(
        yontem: yontem ?? this.yontem,
        windowsYazici: windowsYazici ?? this.windowsYazici,
        tsplAdres: tsplAdres ?? this.tsplAdres,
        tspl: tspl ?? this.tspl,
        kagit: kagit ?? this.kagit,
        mensei: mensei ?? this.mensei,
      );
}

// ───────────────────────── Servis ─────────────────────────

class EtiketAyarlari {
  EtiketAyarlari._();

  /// Tasarım / yazıcı ayarı her değiştiğinde artar — açık ekranlar dinleyip tazelenir.
  static final ValueNotifier<int> degisti = ValueNotifier<int>(0);

  static void _bildir() => degisti.value++;

  // ── Yazıcı ──

  static Future<EtiketYaziciAyari> yaziciYukle() async {
    final p = await SharedPreferences.getInstance();
    final ad = p.getString(RafEtiketAyar.yontem);
    // Hiç seçilmemişse: Windows'ta Windows yazıcısı (USB'ye takılı etiket yazıcısı), telefonda etiket yazıcısı (TSPL).
    var yontem = RafBasmaYontemi.values.where((e) => e.name == ad).firstOrNull ??
        (_windows ? RafBasmaYontemi.windows : RafBasmaYontemi.tspl);
    if (yontem == RafBasmaYontemi.windows && !_windows) yontem = RafBasmaYontemi.tspl;
    return EtiketYaziciAyari(
      yontem: yontem,
      windowsYazici: p.getString(RafEtiketAyar.windowsYazici) ?? '',
      tsplAdres: p.getString(RafEtiketAyar.tsplAdres) ?? '',
      tspl: TsplAyar(
        bosluk: p.getDouble(RafEtiketAyar.tsplBosluk) ?? 2,
        ters: p.getBool(RafEtiketAyar.tsplTers) ?? false,
        koyuluk: p.getInt(RafEtiketAyar.tsplKoyuluk),
      ),
      kagit: p.getString(RafEtiketAyar.kagit) == RafEtiketKagidi.a4.name ? RafEtiketKagidi.a4 : RafEtiketKagidi.rulo,
      mensei: p.getString(RafEtiketAyar.mensei) ?? 'Türkiye',
    );
  }

  static Future<void> yaziciKaydet(EtiketYaziciAyari a) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(RafEtiketAyar.yontem, a.yontem.name);
    await p.setString(RafEtiketAyar.windowsYazici, a.windowsYazici);
    await p.setString(RafEtiketAyar.tsplAdres, a.tsplAdres.trim());
    await p.setDouble(RafEtiketAyar.tsplBosluk, a.tspl.bosluk);
    await p.setBool(RafEtiketAyar.tsplTers, a.tspl.ters);
    if (a.tspl.koyuluk == null) {
      await p.remove(RafEtiketAyar.tsplKoyuluk);
    } else {
      await p.setInt(RafEtiketAyar.tsplKoyuluk, a.tspl.koyuluk!);
    }
    await p.setString(RafEtiketAyar.kagit, a.kagit.name);
    await p.setString(RafEtiketAyar.mensei, a.mensei.trim());
    _bildir();
  }

  // ── Tasarımlar ──

  /// Kullanıcının kendi tasarımları (eski serbest etiket kayıtları ilk açılışta buraya çevrilir).
  static Future<List<EtiketSablonu>> kendiTasarimlar() async {
    final p = await SharedPreferences.getInstance();
    await _gocEt(p);
    return _kendiOku(p);
  }

  static List<EtiketSablonu> _kendiOku(SharedPreferences p) {
    final ham = p.getString(RafEtiketAyar.kendiTasarimlar);
    if (ham == null || ham.isEmpty) return [];
    try {
      return tasarimlarJsondan(jsonDecode(ham));
    } catch (e) {
      debugPrint('Etiket tasarımları okunamadı: $e');
      return [];
    }
  }

  static Future<void> _kendiYaz(SharedPreferences p, List<EtiketSablonu> l) =>
      p.setString(RafEtiketAyar.kendiTasarimlar, jsonEncode([for (final t in l) tasarimJson(t)]));

  /// Önce kendi tasarımlar, sonra hazır şablonlar.
  static Future<List<EtiketSablonu>> tumTasarimlar() async => [...await kendiTasarimlar(), ...sablonlar];

  /// Seçili tasarım; seçim yoksa / silinmişse ilk hazır şablon.
  static Future<EtiketSablonu> seciliTasarim() async {
    final p = await SharedPreferences.getInstance();
    await _gocEt(p);
    final id = p.getString(RafEtiketAyar.sablon) ?? '';
    return tasarimBul([..._kendiOku(p), ...sablonlar], id);
  }

  static EtiketSablonu tasarimBul(List<EtiketSablonu> hepsi, String? id) =>
      hepsi.where((s) => s.id == id).firstOrNull ?? sablonlar.first;

  static Future<void> tasarimSec(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(RafEtiketAyar.sablon, id);
    _bildir();
  }

  /// Kendi tasarımı ekler ya da (aynı kimlikliyi) günceller. Hazır şablon kimliği verilirse hata.
  static Future<void> tasarimKaydet(EtiketSablonu t) async {
    if (!t.kendi) throw ArgumentError('Hazır şablon değiştirilemez; kopyası kaydedilir');
    final p = await SharedPreferences.getInstance();
    await _gocEt(p);
    final l = _kendiOku(p);
    final i = l.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      l[i] = t;
    } else {
      l.add(t);
    }
    await _kendiYaz(p, l);
    _bildir();
  }

  /// Kendi tasarımı siler; seçili olan silinirse seçim ilk hazır şablona döner.
  static Future<void> tasarimSil(String id) async {
    final p = await SharedPreferences.getInstance();
    final l = _kendiOku(p)..removeWhere((e) => e.id == id);
    await _kendiYaz(p, l);
    if (p.getString(RafEtiketAyar.sablon) == id) await p.setString(RafEtiketAyar.sablon, sablonlar.first.id);
    _bildir();
  }

  static String yeniKimlik() => '${EtiketSablonu.kendiOnEki}${DateTime.now().microsecondsSinceEpoch}';

  /// Eski "Kayıtlı Şablonlarım" (serbest etiket anahtarları) bir kez kendi tasarıma çevrilir.
  static Future<void> _gocEt(SharedPreferences p) async {
    if (p.getBool(RafEtiketAyar.gocYapildi) == true) return;
    try {
      final ham = p.getString(RafEtiketAyar.eskiSablonlar);
      if (ham != null && ham.isNotEmpty) {
        final eski = jsonDecode(ham);
        if (eski is List) {
          final l = _kendiOku(p);
          var n = 0;
          for (final e in eski) {
            if (e is! Map) continue;
            final t = eskiSablondanTasarim(e.cast<String, dynamic>(), '${EtiketSablonu.kendiOnEki}goc_${n++}');
            if (t != null && !l.any((x) => x.ad == t.ad)) l.add(t);
          }
          await _kendiYaz(p, l);
        }
      }
    } catch (e) {
      debugPrint('Eski etiket şablonları çevrilemedi: $e'); // eski kayıt bozuksa yeni düzen yine çalışır
    }
    await p.setBool(RafEtiketAyar.gocYapildi, true);
  }
}
