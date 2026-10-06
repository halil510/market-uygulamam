// test/servisler/irsaliye_sevk_senkron_test.dart
//
// Bekleyen siparişten oluşan "sevk kaydı" irsaliyesi ÖNCEDEN buluta hiç
// bildirilmiyordu — diğer cihazda irsaliye listesinde görünmüyordu. Artık
// başlık ve kalemleri AYNI transaction'da senkron kuyruğuna yazılır.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/irsaliye_deposu.dart';
import '../robot/robot_ortam.dart';

void main() {
  late Database db;
  late RobotVeri v;

  setUp(() async {
    await RobotOrtam.hazirla();
    db = await RobotOrtam.veritabaniAc();
    v = await RobotOrtam.tohumla(db);
    await db.delete('sync_queue');
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await db.close();
  });

  test('sevk kaydı irsaliye + kalemleriyle senkron kuyruğuna girer; stok değişmez', () async {
    final stokOnce = ((await db.query('urunler', where: 'id = ?', whereArgs: [v.id['urun0']])).first['stok'] as num).toDouble();
    final id = await IrsaliyeDeposu().olusturSevkKaydi(
      kalemler: [
        IrsaliyeKalemGirdi(urunId: v.id['urun0']!, urunAdi: 'Robot Çikolata 80 G', miktar: 3, birimFiyat: 25),
        IrsaliyeKalemGirdi(urunId: v.id['urun1']!, urunAdi: 'Robot Deterjan 900 G', miktar: 1, birimFiyat: 90),
      ],
      cariId: v.id['cari'],
      kullaniciId: 1,
      irsaliyeNo: 'IRS-SEVK-1',
    );
    final q = await db.query('sync_queue');
    final tablolar = q.map((r) => r['tablo_adi']).toList();
    expect(tablolar.where((t) => t == 'irsaliyeler').length, 1);
    expect(tablolar.where((t) => t == 'irsaliye_kalem').length, 2);
    final baslik = jsonDecode(q.firstWhere((r) => r['tablo_adi'] == 'irsaliyeler')['veri_json'].toString())
        as Map<String, dynamic>;
    expect(baslik['id'], id);
    expect(baslik['irsaliye_no'], 'IRS-SEVK-1');
    expect(baslik['last_updated'], isNotNull);
    final stokSonra = ((await db.query('urunler', where: 'id = ?', whereArgs: [v.id['urun0']])).first['stok'] as num).toDouble();
    expect(stokSonra, stokOnce, reason: 'sevk kaydı stoğa dokunmaz');
  });
}
