// test/depolar/canli_bulgu_20261008_test.dart
//
// Canlı bulgular (2026-10-08):
//  1) "Caride telefonu sildim, silinmedi" — form copyWith + toMap null'u
//     atıyordu; boş bırakılan alan veritabanında kalıyordu.
//  2) "Mobilde masada satış yaptım, ekran sıfırlandı, ürünler geri geldi" —
//     senkron sonrası masa toplam mutabakatı başka kasanın siparişini YENİ
//     damgayla buluta geri yazıp ödenen siparişi yeniden açıyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/masa_deposu.dart';
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    BulutManager().testIcinSifirla();
    Veritabani.testVeritabani = null;
    await db.close();
  });

  group('cari: boş bırakılan alan temizlenir', () {
    test('formdan null alanları uygular, copyWith bilinçli olarak korur', () {
      const c = CariModel(id: 1, unvan: 'A', cariTipi: 'Müşteri',
          telefon: '555', email: 'a@b.c', notlar: 'not', fiyatGrubuId: 3);
      final f = c.formdan(cariKodu: null, unvan: 'A', cariTipi: 'Müşteri',
          telefon: null, email: null, vergiDairesi: null, vergiNo: null,
          tcKimlik: null, limitTutari: 0, vadeGun: 0, notlar: null, aktif: true,
          fiyatGrubuId: null, musteriTipi: 'Perakende');
      expect(f.telefon, isNull);
      expect(f.email, isNull);
      expect(f.notlar, isNull);
      expect(f.fiyatGrubuId, isNull);
      expect(f.toMap().containsKey('telefon'), isTrue);
      expect(c.copyWith(telefon: null).telefon, '555',
          reason: 'Excel aktarımı boş hücrede mevcut numarayı korur');
    });

    test('guncelle telefonu veritabanında da siler', () async {
      final id = await db.insert('cari', {'unvan': 'B', 'cari_tipi': 'Müşteri',
          'telefon': '5550020005', 'cari_kodu': 'C-1', 'global_id': 'CARI-G'});
      final mevcut = CariModel.fromMap((await db.query('cari', where: 'id = ?', whereArgs: [id])).first);
      await CariDeposu().guncelle(mevcut.formdan(cariKodu: 'C-1', unvan: 'B',
          cariTipi: 'Müşteri', telefon: null, email: null, vergiDairesi: null,
          vergiNo: null, tcKimlik: null, limitTutari: 0, vadeGun: 0, notlar: null,
          aktif: true, fiyatGrubuId: null, musteriTipi: 'Perakende'));
      final r = (await db.query('cari', where: 'id = ?', whereArgs: [id])).first;
      expect(r['telefon'], isNull);
    });
  });

  test('masa toplam mutabakatı damgayı ilerletmez (ödenen sipariş yeniden açılmaz)', () async {
    final masaId = await db.insert('masalar', {'ad': 'Salon 1', 'durum': 'dolu'});
    const damga = '2026-10-07T23:26:55.000+00:00';
    final sid = await db.insert('masa_siparisleri', {
      'global_id': 'MS-1', 'masa_id': masaId, 'durum': 'acik',
      'toplam_tutar': 0, 'last_updated': damga,
    });
    await db.insert('masa_siparis_kalem', {
      'global_id': 'MSK-1', 'siparis_id': sid, 'urun_id': await TestVeritabani.ornekUrunEkle(db), 'urun_adi': 'Kakao',
      'miktar': 1, 'birim_fiyat': 37.5, 'is_deleted': 0,
    });
    expect(await MasaDeposu().siparisToplamlariMutabakatYap(), 1);
    final r = (await db.query('masa_siparisleri', where: 'id = ?', whereArgs: [sid])).first;
    expect(r['toplam_tutar'], 37.5);
    expect(r['last_updated'], damga,
        reason: 'yeni damga başka kasada ödenen siparişi geri açardı');
  });
}
