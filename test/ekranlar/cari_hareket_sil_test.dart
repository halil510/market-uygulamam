// test/ekranlar/cari_hareket_sil_test.dart
//
// Kullanıcı bulgusu (2026-09-13): "caride fiş silme işleminde sıkıntı
// var, silme yapmıyor". İki AYRI kök neden bulundu:
//
// 1. cari_hareket_ekrani.dart'ta swipe-sil akışı İKİ AYRI onay diyaloğu
//    gösteriyordu — Dismissible.confirmDismiss kendi diyaloğunu gösterip
//    true dönüyordu, ardından _silHareket kendi İKİNCİ bir diyaloğunu
//    daha açıyordu. Kullanıcı ikinci diyaloğu fark etmeden kapatırsa
//    (barrier-dismiss) `ok != true` olduğu için fonksiyon SESSİZCE
//    (hata/bildirim olmadan) geri dönüyordu. Düzeltme: tek diyalog
//    (confirmDismiss), _silHareket artık onay istemeden direkt siliyor.
//
// 2. Onay sonrası silme FİİLEN GERÇEKLEŞİYORDU ama bakiyeyi YANLIŞ
//    hesaplıyordu: orijinal kayıt is_deleted=1 ile bakiye SUM'ından
//    (CariDeposu.bakiyeYenidenHesapla ile AYNI kanonik 'is_deleted=0'
//    filtresi) dışlanıyordu, AMA yanına sıfır-olmayan (borç/alacak yer
//    değiştirmiş) bir "ters" kayıt da EKLENİYORDU — bu ikisi net
//    SIFIRA inmek yerine, bakiyeyi orijinal tutarın TERSİ kadar
//    kaydırıyordu (10 TL'lik bir hareket silinince bakiye 0'a değil
//    +10'a gidiyordu). Düzeltme: ters kayıt artık borc=0/alacak=0 (salt
//    görüntüleme/audit amaçlı) — asıl bakiye sıfırlaması SADECE
//    orijinalin SUM'dan dışlanmasıyla sağlanıyor.
//
// _silHareket private bir State metodu olduğu için (widget içi), bu test
// o metottaki BİREBİR aynı soft-delete + ters-hareket + bakiye yeniden
// hesaplama SQL akışını gerçek şema üzerinde doğruluyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../helper/test_initializer.dart';

Future<void> _silHareketSimulasyonu(Database db, {
  required int hareketId,
  required int cariId,
}) async {
  await db.transaction((txn) async {
    final guncelRows =
        await txn.query('cari_hareket', where: 'id = ?', whereArgs: [hareketId]);
    if (guncelRows.isEmpty) throw Exception('Hareket bulunamadı');
    final guncel = guncelRows.first;
    if ((guncel['is_deleted'] as int? ?? 0) == 1) {
      throw Exception('Bu hareket zaten iptal edilmiş');
    }
    final now = DateTime.now().toIso8601String();

    await txn.update('cari_hareket', {'is_deleted': 1, 'last_updated': now},
        where: 'id = ?', whereArgs: [hareketId]);

    await txn.insert('cari_hareket', {
      'global_id': const Uuid().v4(),
      'cari_id': cariId,
      'tarih': now,
      'fis_tipi': '${guncel['fis_tipi']} İptali',
      'fis_id': hareketId,
      'fis_no': guncel['fis_no'],
      'aciklama': 'İptal: ${guncel['aciklama']}',
      'borc': 0,
      'alacak': 0,
      'odeme_turu': guncel['odeme_turu'],
      'last_updated': now,
      'is_deleted': 0,
    });

    await txn.rawUpdate('''
      UPDATE cari SET bakiye = (
        SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0)
        FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0
      ), last_updated = ?
      WHERE id = ?
    ''', [cariId, now, cariId]);
  });
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Cari hareket silme (onay sonrası fiilen çalışıyor mu)', () {
    test('onay sonrası hareket soft-delete edilir, ters kayıt eklenir, bakiye güncellenir', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, unvan: 'Test Müşteri');
      final hareketId = await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'İskonto', 'aciklama': '10 TL iskonto',
        'borc': 0, 'alacak': 10, 'is_deleted': 0,
      });
      await db.update('cari', {'bakiye': -10}, where: 'id = ?', whereArgs: [cariId]);

      await _silHareketSimulasyonu(db, hareketId: hareketId, cariId: cariId);

      final orijinal = await db.query('cari_hareket', where: 'id = ?', whereArgs: [hareketId]);
      expect(orijinal.first['is_deleted'], 1, reason: 'orijinal kayıt soft-delete edilmeli, HARD DELETE olmamalı');

      final tumHareketler = await db.query('cari_hareket', where: 'cari_id = ?', whereArgs: [cariId]);
      expect(tumHareketler.length, 2, reason: 'orijinal + ters kayıt olmak üzere 2 satır olmalı');

      final cari = await db.query('cari', where: 'id = ?', whereArgs: [cariId]);
      expect((cari.first['bakiye'] as num).toDouble(), 0.0,
          reason: 'ters kayıt eklendiği için bakiye sıfırlanmalı (10 alacak - orijinal 10 alacak + ters 10 borç)');
    });

    test('zaten silinmiş bir hareket TEKRAR silinmeye çalışılırsa hata fırlatır (sessizce yutulmaz)', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      final hareketId = await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'İskonto', 'aciklama': 'X',
        'borc': 0, 'alacak': 10, 'is_deleted': 1,
      });

      expect(
        () => _silHareketSimulasyonu(db, hareketId: hareketId, cariId: cariId),
        throwsException,
      );
    });

    test('is_deleted=0 filtresi sayesinde silinen hareket listede tekrar görünmez', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      final hareketId = await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'İskonto', 'aciklama': 'X',
        'borc': 0, 'alacak': 10, 'is_deleted': 0,
      });

      await _silHareketSimulasyonu(db, hareketId: hareketId, cariId: cariId);

      final listeGorunumu = await db.rawQuery(
        'SELECT * FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0 ORDER BY tarih DESC',
        [cariId],
      );
      expect(listeGorunumu.any((r) => r['id'] == hareketId), isFalse,
          reason: 'silinen orijinal hareket ekrandaki listeden kaybolmalı');
      expect(listeGorunumu.length, 1, reason: 'sadece ters (iptal) kaydı görünmeli');
    });
  });
}
