// test/veri/satis_sync_kopyasi_filtre_test.dart
//
// Kullanıcı bulgusu (ekran görüntüleri, 2026-09-21): Supabase+yerel veri
// sıfırlandıktan sonra yapılan tek bir ₺90'lık veresiye satış, bulutta
// tam temizlenmemiş eski bir kayıtla fis_no çakışınca Veritabani.
// _cakismaKorumasiUygula() onu '<fis_no>-SYNC<hash>' diye AYRI bir satır
// olarak ekliyordu (veri kaybını önlemek için BİLİNÇLİ bir davranış) —
// ama bu "hayalet" satır Satış Listesi'nde VE Gün Sonu Raporu'nda
// sıradan, TAM DEĞERLİ bir satış gibi görünüp toplamları şişiriyordu
// (Cari Satış ₺90 yerine ₺180 gösterdi). Kullanıcı: "sync'ce fişi satış
// ve gün sonunda gözükmesin, kafa karışıklığı yapıyor" dedi.
//
// Düzeltme: satislar.sync_cakisma_kopyasi sütunu eklendi (v73 migrasyon),
// _cakismaKorumasiUygula bunu 1 olarak damgalıyor, SatisDeposu.
// tariheGoreGetir/maliyetToplami/gunSonuDetayGetir varsayılan olarak
// dışlıyor. SatisDeposu Veritabani() singleton'ı üzerinden çalıştığı
// için (bkz. diğer depo testlerindeki AYNI gerekçe), burada
// tariheGoreGetir'in SQL'i BİREBİR AYNI şekilde gerçek şema üzerinde
// bir in-memory veritabanı içinde doğrudan çalıştırılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

/// SatisDeposu.tariheGoreGetir() ile BİREBİR AYNI SQL (sube filtresi hariç
/// — testte tek şube var).
Future<List<Map<String, dynamic>>> _tariheGoreGetir(
    Database db, DateTime bas, DateTime bit) async {
  return db.rawQuery(
    'SELECT s.*, c.unvan as cari_adi '
    'FROM satislar s LEFT JOIN cari c ON s.cari_id = c.id '
    'WHERE datetime(s.tarih) BETWEEN datetime(?) AND datetime(?) '
    '  AND s.iptal = 0 AND s.is_deleted = 0 '
    '  AND s.sync_cakisma_kopyasi = 0 '
    'ORDER BY s.tarih DESC',
    [bas.toIso8601String(), bit.toIso8601String()],
  );
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('satislar.sync_cakisma_kopyasi filtresi', () {
    test('yeni sütun varsayılan olarak 0 — normal INSERT etkilenmez', () async {
      final id = await db.insert('satislar', {
        'fis_no': 'CRI2026000000001', 'tarih': DateTime.now().toIso8601String(),
        'genel_toplam': 90.0, 'odeme_yontemi': 'Cari',
      });
      final satir = await db.query('satislar', where: 'id = ?', whereArgs: [id]);
      expect(satir.first['sync_cakisma_kopyasi'], 0);
    });

    test('sync_cakisma_kopyasi=1 satır tariheGoreGetir\'de GÖRÜNMEZ '
        '(gerçek satışın toplamı şişmez)', () async {
      final bugun = DateTime.now();
      await db.insert('satislar', {
        'fis_no': 'CRI2026000000001', 'tarih': bugun.toIso8601String(),
        'genel_toplam': 90.0, 'odeme_yontemi': 'Cari',
      });
      // Sync çakışması kopyası — Veritabani._cakismaKorumasiUygula'nın
      // ürettiğiyle BİREBİR AYNI şekil: yeniden adlandırılmış fis_no +
      // sync_cakisma_kopyasi=1.
      await db.insert('satislar', {
        'fis_no': 'CRI2026000000001-SYNC959a8f', 'tarih': bugun.toIso8601String(),
        'genel_toplam': 90.0, 'odeme_yontemi': 'Cari',
        'sync_cakisma_kopyasi': 1,
      });

      final sonuc = await _tariheGoreGetir(
          db, bugun.subtract(const Duration(days: 1)), bugun.add(const Duration(days: 1)));

      expect(sonuc.length, 1, reason: 'sadece gerçek satış görünmeli, kopya gizlenmeli');
      expect(sonuc.first['fis_no'], 'CRI2026000000001');
      final toplam = sonuc.fold<double>(0, (s, r) => s + (r['genel_toplam'] as num).toDouble());
      expect(toplam, 90.0, reason: 'Cari Satış toplamı ₺180 değil ₺90 olmalı');
    });

    test('kopya "gerçek satış" olarak işaretlenince (sync_cakisma_kopyasi=0) '
        'tekrar listede görünür', () async {
      final bugun = DateTime.now();
      final id = await db.insert('satislar', {
        'fis_no': 'CRI2026000000002-SYNCabc123', 'tarih': bugun.toIso8601String(),
        'genel_toplam': 50.0, 'odeme_yontemi': 'Nakit',
        'sync_cakisma_kopyasi': 1,
      });

      var sonuc = await _tariheGoreGetir(
          db, bugun.subtract(const Duration(days: 1)), bugun.add(const Duration(days: 1)));
      expect(sonuc, isEmpty);

      // SatisDeposu.syncKopyasiGercekOlarakIsaretle() ile BİREBİR AYNI.
      await db.update('satislar', {'sync_cakisma_kopyasi': 0}, where: 'id = ?', whereArgs: [id]);

      sonuc = await _tariheGoreGetir(
          db, bugun.subtract(const Duration(days: 1)), bugun.add(const Duration(days: 1)));
      expect(sonuc.length, 1);
    });
  });
}
