// lib/ekranlar/rapor/satis_rapor_ortak.dart
//
// Satış Raporu: mobil ve masaüstü görünümün PAYLAŞTIĞI filtre, sorgu ve
// yardımcılar.
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../cekirdek/utils/dosya_paylasim.dart';
import '../../cekirdek/utils/excel_guvenlik_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../depolar/satis_deposu.dart';
import '../../modeller/satis_model.dart';

class SatisRaporFiltre {
  final DateTime bas, bit;
  final String donem;
  SatisRaporFiltre({required this.bas, required this.bit, this.donem = 'Bugün'});
  SatisRaporFiltre.bugun()
      : bas = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
        bit = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
        donem = 'Bugün';
}

const satisRaporDonemler = ['Bugün', 'Bu Hafta', 'Bu Ay', 'Özel'];

/// Hazır dönem adı → filtre. 'Özel' veya bilinmeyen için null.
SatisRaporFiltre? satisRaporDonemFiltresi(String donem) {
  final now = DateTime.now();
  final gunSonu = DateTime(now.year, now.month, now.day, 23, 59, 59);
  switch (donem) {
    case 'Bugün':
      return SatisRaporFiltre(
          bas: DateTime(now.year, now.month, now.day), bit: gunSonu, donem: donem);
    case 'Bu Hafta':
      final pzt = now.subtract(Duration(days: now.weekday - 1));
      return SatisRaporFiltre(
          bas: DateTime(pzt.year, pzt.month, pzt.day), bit: gunSonu, donem: donem);
    case 'Bu Ay':
      return SatisRaporFiltre(bas: DateTime(now.year, now.month, 1), bit: gunSonu, donem: donem);
  }
  return null;
}

final satisRaporFiltreProvider =
    StateProvider<SatisRaporFiltre>((_) => SatisRaporFiltre.bugun());

final satisRaporProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final f = ref.watch(satisRaporFiltreProvider);
  final depo = SatisDeposu();
  final satislar = await depo.tariheGoreGetir(f.bas, f.bit);
  final aktif = satislar.where((s) => !s.iptal).toList();
  // tariheGoreGetir() SQL seviyesinde iptalleri zaten dışlar; iptal sayısı
  // bu yüzden ayrı bir sorguyla alınır.
  final iptalSayisi = await depo.iptalSayisiGetir(f.bas, f.bit);
  // Maliyet ve iade: Gün Sonu raporuyla AYNI kaynaklar (KDV dahil maliyet,
  // iade tutarı/maliyeti) — iki rapor aynı günde farklı net ciro/kâr
  // göstermesin.
  final maliyet = await depo.maliyetToplami(f.bas, f.bit);
  final iade = await depo.iadeTutarVeMaliyet(f.bas, f.bit);

  double ciro = 0, iskonto = 0;
  final odemeMap = <String, double>{};
  final saatMap = <int, double>{};
  for (final s in aktif) {
    ciro += s.genelToplam;
    iskonto += s.iskonto;
    odemeMap[s.odemeYontemi] = (odemeMap[s.odemeYontemi] ?? 0) + s.genelToplam;
    saatMap[s.tarih.hour] = (saatMap[s.tarih.hour] ?? 0) + s.genelToplam;
  }

  final netCiro = ciro - iade.tutar;
  final brutKar = (ciro - maliyet) - (iade.tutar - iade.maliyet);
  return {
    'satislar': satislar,
    'aktif': aktif,
    'ciro': ciro,
    'iskonto': iskonto,
    'sayi': aktif.length,
    'iptal': iptalSayisi,
    'odemeMap': odemeMap,
    'saatMap': saatMap,
    'ortalamaFis': aktif.isEmpty ? 0.0 : ciro / aktif.length,
    'iade': iade.tutar,
    'netCiro': netCiro,
    'maliyet': maliyet - iade.maliyet,
    'brutKar': brutKar,
  };
});

const _odemeRenkleri = <String, Color>{
  'Nakit': Color(0xFF4CAF50),
  'Kredi Kartı': Color(0xFF2196F3),
  'Havale': Color(0xFF9C27B0),
  'Cari': Color(0xFFFF9800),
  'QR': Color(0xFF00BCD4),
  'Karma': Color(0xFF607D8B),
};
const _digerRenk = Color(0xFF9E9E9E);

/// Ödeme yöntemi → renk. Bilinmeyen yöntemler (ör. 'Havale/EFT', 'Veresiye')
/// önceden pasta grafiğinden ve açıklamadan SESSİZCE düşüyordu; artık gri.
Color satisRaporOdemeRengi(String yontem) => _odemeRenkleri[yontem] ?? _digerRenk;

List<SatisModel> satisRaporSatislar(Map<String, dynamic> d) =>
    d['satislar'] as List<SatisModel>;

/// Fiş listesini Excel'e yazıp paylaşır. Hata durumunda istisna fırlatır.
Future<void> satisRaporExcelAktar(List<SatisModel> satislar) async {
  final excel = Excel.createExcel();
  final sheet = excel['Satışlar'];
  excel.delete('Sheet1');
  sheet.appendRow([
    TextCellValue('Fiş No'), TextCellValue('Tarih'), TextCellValue('Müşteri'),
    TextCellValue('Ödeme'), TextCellValue('İskonto'), TextCellValue('Toplam'),
  ]);
  final fmt = DateFormat('dd.MM.yyyy HH:mm');
  for (final s in satislar) {
    sheet.appendRow([
      TextCellValue(excelIcinGuvenliMetin(s.fisNo)),
      TextCellValue(fmt.format(s.tarih)),
      TextCellValue(excelIcinGuvenliMetin(s.cariAdi)),
      TextCellValue(s.odemeYontemi),
      DoubleCellValue(s.iskonto),
      DoubleCellValue(s.genelToplam),
    ]);
  }
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/satis_raporu_${DateTime.now().millisecondsSinceEpoch}.xlsx';
  await File(path).writeAsBytes(excel.encode()!);
  await DosyaPaylasim.paylas(ShareParams(files: [XFile(path)], text: 'Satış Raporu'));
}
