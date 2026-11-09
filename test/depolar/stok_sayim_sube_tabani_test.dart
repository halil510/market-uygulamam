// test/depolar/stok_sayim_sube_tabani_test.dart
//
// Derin denetim (2026-11-09), yüksek:
//  #12 Şube seçiliyken sayım, şube payı yazılmamış üründe stoğu şişiriyordu
//      (90 sayılan → 190, 50 sayılan → 100).
//  #13 Excel'den sayım, şube sayımını toplam stoğa MUTLAK yazıyor, onay
//      akışını ve transaction'ı atlıyordu.
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/stok_deposu.dart';
import 'package:market_plus/depolar/sube_urun_deposu.dart';
import 'package:market_plus/saglayicilar/riverpod/stok_sayim_provider.dart';
import 'package:market_plus/servisler/excel_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    for (final s in [1, 2]) {
      if ((await db.query('subeler', where: 'id = ?', whereArgs: [s])).isEmpty) {
        await db.insert('subeler', {'id': s, 'sube_kodu': 'S$s', 'sube_adi': 'Şube $s'});
      }
    }
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('#12 tek şubede (başka şube payı yok) sayım tabanı toplam stoktur', () async {
    final urun = await TestVeritabani.ornekUrunEkle(db, stok: 90);
    // Başlangıç stoğu şube payına yazılmamış, yalnız satış düşülmüş: pay −10.
    await db.insert('sube_urun', {'urun_id': urun, 'sube_id': 1, 'stok': -10});
    final taban = await SubeUrunDeposu().sayimTabaniGetir(urun, 1);
    expect(taban, isNull);
    final yeni = StokSayimHesap.yeniToplamHesapla(toplamStok: 90, subeStok: taban, sayilan: 90);
    expect(yeni, 90, reason: 'önceden 190 çıkıyordu');
  });

  test('#12 ürün birden çok şubeye dağılmışsa şube payı korunur', () async {
    final urun = await TestVeritabani.ornekUrunEkle(db, stok: 100);
    await db.insert('sube_urun', {'urun_id': urun, 'sube_id': 1, 'stok': 60});
    await db.insert('sube_urun', {'urun_id': urun, 'sube_id': 2, 'stok': 40});
    final taban = await SubeUrunDeposu().sayimTabaniGetir(urun, 1);
    expect(taban, 60);
    expect(StokSayimHesap.yeniToplamHesapla(toplamStok: 100, subeStok: taban, sayilan: 55), 95);
  });

  test('#13 Excel sayımı stoğu doğrudan yazmaz; yetkisiz kullanıcıda onaya düşer', () async {
    final urun = await TestVeritabani.ornekUrunEkle(db, stok: 100, barkod: '8690000000099');
    final excel = Excel.createExcel();
    final sayfa = excel['Stok Sayım'];
    excel.delete('Sheet1');
    sayfa.appendRow([TextCellValue('Kod'), TextCellValue('Ana Miktar')]);
    sayfa.appendRow([TextCellValue('8690000000099'), const IntCellValue(80)]);
    final bytes = Uint8List.fromList(excel.encode()!);

    final sonuc = await ExcelServisi().stokSayimExcelIceAl(bytes);

    expect(sonuc['basarili'], 1, reason: '${sonuc['hatalar']} $sonuc');
    expect(sonuc['onay_bekliyor'], isTrue);
    final stok = (await db.query('urunler', where: 'id = ?', whereArgs: [urun])).first['stok'];
    expect((stok as num).toDouble(), 100, reason: 'onaydan önce stok değişmemeli');
    final bekleyen = (await db.query('gecici_sayim', where: 'urun_id = ?', whereArgs: [urun])).single;
    expect((bekleyen['yeni_stok'] as num).toDouble(), 80);
  });

  test('#44 sayım ile onay arasındaki satış korunur (fark uygulanır, mutlak değil)', () async {
    final urun = await TestVeritabani.ornekUrunEkle(db, stok: 100);
    // Sayım: sistem 100, sayılan 80 → fark −20.
    await StokDeposu().geciciSayimEkleGuncelle(urun, 100, 80);
    // Onaydan önce 5 adet satıldı.
    await db.update('urunler', {'stok': 95}, where: 'id = ?', whereArgs: [urun]);

    await StokDeposu().geciciSayimUygula(1);

    final stok = (await db.query('urunler', where: 'id = ?', whereArgs: [urun])).first['stok'];
    expect((stok as num).toDouble(), 75, reason: 'önceden 80 yazılıp satış siliniyordu');
  });
}
