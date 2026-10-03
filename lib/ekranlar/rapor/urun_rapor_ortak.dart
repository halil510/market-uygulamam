// lib/ekranlar/rapor/urun_rapor_ortak.dart
//
// Ürün Raporu: mobil ve masaüstü görünümün PAYLAŞTIĞI durum + yardımcılar
// (filtre sağlayıcısı, sorgu sağlayıcıları, dönem seçimi, Excel çıktısı,
// arama yapılabilir seçim penceresi).
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../cekirdek/utils/dosya_paylasim.dart';
import '../../cekirdek/utils/excel_guvenlik_utils.dart';
import '../../depolar/urun_rapor_deposu.dart';

/// Rapor türü: satış veya alım. İki sekme AYNI filtreyi paylaşır —
/// kullanıcı marka/grup seçip sekme değiştirince karşılaştırma yapabilir.
enum UrunRaporTuru { satis, alim }

final urunRaporFiltreProvider =
    StateProvider<UrunRaporFiltre>((_) => UrunRaporFiltre.buAy());

final urunRaporSonucProvider = FutureProvider.autoDispose
    .family<UrunRaporSonuc, UrunRaporTuru>((ref, tur) {
  final f = ref.watch(urunRaporFiltreProvider);
  final depo = UrunRaporDeposu();
  return tur == UrunRaporTuru.satis ? depo.satisRaporu(f) : depo.alimRaporu(f);
});

final urunRaporMarkalarProvider = FutureProvider.autoDispose<List<String>>(
    (_) => UrunRaporDeposu().markalariGetir());
final urunRaporAnaGruplarProvider = FutureProvider.autoDispose<List<String>>(
    (_) => UrunRaporDeposu().anaGruplariGetir());
final urunRaporCarilerProvider =
    FutureProvider.autoDispose<List<({int id, String unvan})>>(
        (_) => UrunRaporDeposu().carileriGetir());

const urunRaporDonemler = ['Bugün', 'Dün', 'Bu Hafta', 'Bu Ay', 'Geçen Ay', 'Bu Yıl'];

/// Hazır dönem → (başlangıç, bitiş). Bilinmeyen ad için null.
(DateTime, DateTime)? urunRaporDonemAraligi(String donem) {
  final n = DateTime.now();
  final bugun = DateTime(n.year, n.month, n.day);
  switch (donem) {
    case 'Bugün':
      return (bugun, bugun);
    case 'Dün':
      final d = bugun.subtract(const Duration(days: 1));
      return (d, d);
    case 'Bu Hafta':
      return (bugun.subtract(Duration(days: n.weekday - 1)), bugun);
    case 'Bu Ay':
      return (DateTime(n.year, n.month, 1), bugun);
    case 'Geçen Ay':
      return (DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 0));
    case 'Bu Yıl':
      return (DateTime(n.year, 1, 1), bugun);
  }
  return null;
}

/// Seçili aralığın hangi hazır döneme denk geldiği (yoksa null = özel).
String? urunRaporAktifDonem(UrunRaporFiltre f) {
  bool ayni(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  for (final d in urunRaporDonemler) {
    final r = urunRaporDonemAraligi(d);
    if (r != null && ayni(r.$1, f.bas) && ayni(r.$2, f.bit)) return d;
  }
  return null;
}

String urunRaporMiktarYaz(double m) =>
    m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(2);

/// Arama yapılabilir tek seçim penceresi (çok sayıda cari/marka için).
/// "Tümü" seçilirse [temizle] true döner.
Future<({bool temizle, T? secim})?> urunRaporSecimPenceresi<T>(
  BuildContext context, {
  required String baslik,
  required List<T> ogeler,
  required String Function(T) etiket,
}) {
  return showDialog<({bool temizle, T? secim})>(
    context: context,
    builder: (ctx) {
      var q = '';
      return StatefulBuilder(builder: (ctx, setS) {
        final liste = ogeler
            .where((o) => etiket(o).toLowerCase().contains(q.toLowerCase()))
            .toList();
        return AlertDialog(
          title: Text(baslik),
          content: SizedBox(
            width: 380,
            height: 420,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Ara…'),
                onChanged: (v) => setS(() => q = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.clear_all),
                    title: const Text('Tümü (filtreyi kaldır)'),
                    onTap: () => Navigator.pop(ctx, (temizle: true, secim: null)),
                  ),
                  for (final o in liste)
                    ListTile(
                      dense: true,
                      title: Text(etiket(o)),
                      onTap: () => Navigator.pop(ctx, (temizle: false, secim: o)),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          ],
        );
      });
    },
  );
}

/// Sonucu Excel dosyasına yazıp paylaşır. Başarısızsa istisna fırlatır.
Future<void> urunRaporExcelAktar({
  required UrunRaporTuru tur,
  required UrunRaporFiltre filtre,
  required UrunRaporSonuc sonuc,
}) async {
  final satis = tur == UrunRaporTuru.satis;
  final excel = Excel.createExcel();
  final adi = satis ? 'Satış' : 'Alım';
  final sheet = excel[adi];
  excel.delete('Sheet1');
  final fmt = DateFormat('dd.MM.yyyy');
  sheet.appendRow([
    TextCellValue('Ürün $adi Raporu: ${fmt.format(filtre.bas)} - ${fmt.format(filtre.bit)}'
        '${filtre.anaGrup != null ? '  Grup: ${filtre.anaGrup}' : ''}'
        '${filtre.marka != null ? '  Marka: ${filtre.marka}' : ''}'),
  ]);
  sheet.appendRow([
    TextCellValue(filtre.gruplama.etiket),
    TextCellValue('Kod / Bilgi'),
    TextCellValue('Ana Grup'),
    TextCellValue('Marka'),
    TextCellValue('Miktar'),
    TextCellValue(satis ? 'Ciro (KDV dahil)' : 'Alım Tutarı'),
    if (satis) TextCellValue('Maliyet'),
    if (satis) TextCellValue('Kâr'),
    if (satis) TextCellValue('Marj %'),
    TextCellValue('Fiş Sayısı'),
  ]);
  for (final s in sonuc.satirlar) {
    sheet.appendRow([
      TextCellValue(excelIcinGuvenliMetin(s.ad)),
      TextCellValue(excelIcinGuvenliMetin(s.alt)),
      TextCellValue(excelIcinGuvenliMetin(s.anaGrup)),
      TextCellValue(excelIcinGuvenliMetin(s.marka)),
      DoubleCellValue(s.miktar),
      DoubleCellValue(s.tutar),
      if (satis) DoubleCellValue(s.maliyet),
      if (satis) DoubleCellValue(s.kar),
      if (satis) DoubleCellValue(double.parse(s.karMarji.toStringAsFixed(1))),
      IntCellValue(s.fisSayisi),
    ]);
  }
  sheet.appendRow([
    TextCellValue('TOPLAM'),
    TextCellValue(''),
    TextCellValue(''),
    TextCellValue(''),
    DoubleCellValue(sonuc.toplamMiktar),
    DoubleCellValue(sonuc.toplamTutar),
    if (satis) DoubleCellValue(sonuc.toplamMaliyet),
    if (satis) DoubleCellValue(sonuc.toplamKar),
    if (satis) TextCellValue(''),
    IntCellValue(sonuc.fisSayisi),
  ]);
  final dir = await getApplicationDocumentsDirectory();
  final path =
      '${dir.path}/urun_${satis ? 'satis' : 'alim'}_raporu_${DateTime.now().millisecondsSinceEpoch}.xlsx';
  await File(path).writeAsBytes(excel.encode()!);
  await DosyaPaylasim.paylas(
      ShareParams(files: [XFile(path)], text: 'Ürün $adi Raporu'));
}
