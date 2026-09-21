// test/veri/sync_cakisma_islem_verisi_test.dart
//
// FAZ 3 (DEEP_AUDIT_REPORT madde 4, 2026-09-21, kullanıcı onaylı mimari
// karar): Veritabani.supaKayitlariGuncelle()'ın YENİ davranışını
// doğrular — "işlem verisi" (satış/stok/kasa/banka hareketi vb.)
// tablolarında GERÇEK bir çakışma tespit edilirse artık otomatik LWW
// üzerine yazma UYGULANMAZ (yerel korunur, çakışma yine loglanır);
// "master veri" (urunler, cari vb.) tablolarında davranış DEĞİŞMEDİ.
//
// Veritabani() singleton'ı (SharedPreferences filigranı + PRAGMA
// foreign_keys) üzerinden çalıştığı için (diğer depo testlerinde olduğu
// gibi) burada AYNI (düzeltilmiş) karar algoritması gerçek şema
// üzerinde bir in-memory veritabanında doğrudan doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/veri/database/sync_cakisma_tespit.dart';
import '../helper/test_initializer.dart';

/// Veritabani.supaKayitlariGuncelle()'ın TEK KAYIT için karar mantığıyla
/// BİREBİR AYNI: gerçek çakışma + işlem verisi ise atla, aksi halde
/// (mevcut davranış) üzerine yaz.
Future<bool> _kayitUygulaVeyaAtla(
  Database db,
  String tablo,
  Map<String, dynamic> yerelSatir,
  Map<String, dynamic> gelenSatirHam,
  DateTime? sonGonderFiligrani,
) async {
  final temiz = Map<String, dynamic>.from(gelenSatirHam)..remove('id');

  final farklar = SyncCakismaTespit.farklariBul(yerelSatir, temiz);
  var gercekCakisma = false;
  if (farklar.isNotEmpty) {
    final yerelZaman =
        DateTime.tryParse(yerelSatir['last_updated']?.toString() ?? '');
    gercekCakisma = SyncCakismaTespit.gercekCakismaMi(
        yerelSonGuncelleme: yerelZaman,
        sonBasariliGonderim: sonGonderFiligrani);
    if (gercekCakisma) {
      // Veritabani._cakismaKaydetGerekirse ile AYNI dedup mantığı
      // (DEEP_AUDIT kendi-keşif turu, 2026-09-21): aynı (tablo,
      // global_id) için çözülmemiş bir çakışma varsa GÜNCELLE, yoksa EKLE.
      final globalId = temiz['global_id']?.toString();
      final mevcut = globalId != null
          ? await db.query('sync_cakismalar',
              columns: ['id'],
              where: 'tablo = ? AND kayit_global_id = ? AND cozuldu = 0',
              whereArgs: [tablo, globalId],
              limit: 1)
          : const <Map<String, dynamic>>[];
      final satirVerisi = {
        'tablo': tablo,
        'kayit_global_id': globalId,
        'alan_farklari': '{}',
        'tarih': DateTime.now().toIso8601String(),
        'cozuldu': 0,
      };
      if (mevcut.isNotEmpty) {
        await db.update('sync_cakismalar', satirVerisi,
            where: 'id = ?', whereArgs: [mevcut.first['id']]);
      } else {
        await db.insert('sync_cakismalar', satirVerisi);
      }
    }
  }

  if (gercekCakisma && SyncCakismaTespit.islemVerisiMi(tablo)) {
    return false; // atlandı — yerel korunuyor
  }
  await db.update(tablo, temiz,
      where: 'global_id = ?', whereArgs: [temiz['global_id']]);
  return true; // uygulandı
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('İşlem verisi tablolarında gerçek çakışmada otomatik üzerine yazma YOK', () {
    test(
        'kasa_hareketleri (işlem verisi): gerçek çakışmada yerel KORUNUR, '
        'çakışma yine loglanır', () async {
      final yerelSonGuncelleme = DateTime(2026, 9, 21, 10, 5);
      final sonGonderFiligrani = DateTime(2026, 9, 21, 10, 0); // filigrandan SONRA yerel değişmiş

      final id = await db.insert('kasa_hareketleri', {
        'global_id': 'kasa-1', 'hareket_tipi': 'Satış', 'tutar': 100,
        'bakiye_sonrasi': 500, // BU cihazın kendi zinciri
        'last_updated': yerelSonGuncelleme.toIso8601String(),
      });
      final yerelSatir =
          (await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [id])).first;

      final gelen = {
        'global_id': 'kasa-1', 'hareket_tipi': 'Satış', 'tutar': 100,
        'bakiye_sonrasi': 999, // BAŞKA cihazın FARKLI zinciri — çakışma
        'last_updated': DateTime(2026, 9, 21, 10, 6).toIso8601String(),
      };

      final uygulandi = await _kayitUygulaVeyaAtla(
          db, 'kasa_hareketleri', yerelSatir, gelen, sonGonderFiligrani);
      expect(uygulandi, isFalse);

      final sonuc = (await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [id])).first;
      expect(sonuc['bakiye_sonrasi'], 500,
          reason: 'yerel zincir KORUNMALI, buluttaki farklı zincirle EZİLMEMELİ');

      final cakismalar = await db.query('sync_cakismalar');
      expect(cakismalar, hasLength(1),
          reason: 'çakışma yine de görünür/denetlenebilir olmalı');
    });

    test(
        'ÇÖZÜLMEMİŞ bir çakışma sonraki sync turlarında MÜKERRER kayıt '
        'oluşturmaz (dedup)', () async {
      final yerelSonGuncelleme = DateTime(2026, 9, 21, 10, 5);
      final sonGonderFiligrani = DateTime(2026, 9, 21, 10, 0);

      final id = await db.insert('kasa_hareketleri', {
        'global_id': 'kasa-dedup', 'hareket_tipi': 'Satış', 'tutar': 100,
        'bakiye_sonrasi': 500,
        'last_updated': yerelSonGuncelleme.toIso8601String(),
      });
      final yerelSatir =
          (await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [id])).first;
      final gelen = {
        'global_id': 'kasa-dedup', 'hareket_tipi': 'Satış', 'tutar': 100,
        'bakiye_sonrasi': 999,
        'last_updated': DateTime(2026, 9, 21, 10, 6).toIso8601String(),
      };

      // Kullanıcı çözmeden AYNI çakışma 3 kez daha (periyodik sync) tetiklenir.
      for (var i = 0; i < 3; i++) {
        await _kayitUygulaVeyaAtla(
            db, 'kasa_hareketleri', yerelSatir, gelen, sonGonderFiligrani);
      }

      final cakismalar = await db.query('sync_cakismalar');
      expect(cakismalar, hasLength(1),
          reason: 'aynı çözülmemiş çakışma tekrar tekrar birikmemeli');
    });

    test('stok_hareket (işlem verisi): aynı senaryo, aynı sonuç', () async {
      final yerelSonGuncelleme = DateTime(2026, 9, 21, 10, 5);
      final sonGonderFiligrani = DateTime(2026, 9, 21, 10, 0);

      final id = await db.insert('stok_hareket', {
        'global_id': 'stok-1', 'urun_id': 1, 'hareket_turu': 'Satış',
        'miktar': 5, 'onceki_stok': 20, 'sonraki_stok': 15,
        'last_updated': yerelSonGuncelleme.toIso8601String(),
      });
      final yerelSatir =
          (await db.query('stok_hareket', where: 'id = ?', whereArgs: [id])).first;

      final gelen = {
        'global_id': 'stok-1', 'urun_id': 1, 'hareket_turu': 'Satış',
        'miktar': 5, 'onceki_stok': 999, 'sonraki_stok': 994,
        'last_updated': DateTime(2026, 9, 21, 10, 6).toIso8601String(),
      };

      final uygulandi = await _kayitUygulaVeyaAtla(
          db, 'stok_hareket', yerelSatir, gelen, sonGonderFiligrani);
      expect(uygulandi, isFalse);

      final sonuc = (await db.query('stok_hareket', where: 'id = ?', whereArgs: [id])).first;
      expect(sonuc['sonraki_stok'], 15);
    });
  });

  group('Master veri tablolarında davranış DEĞİŞMEDİ (LWW aynen uygulanır)', () {
    test('urunler: gerçek çakışmada bile gelen (daha yeni) UYGULANIR',
        () async {
      final yerelSonGuncelleme = DateTime(2026, 9, 21, 10, 5);
      final sonGonderFiligrani = DateTime(2026, 9, 21, 10, 0);

      final urunId = await TestVeritabani.ornekUrunEkle(db, satisFiyati: 100);
      await db.update(
          'urunler',
          {
            'global_id': 'urun-1',
            'last_updated': yerelSonGuncelleme.toIso8601String(),
          },
          where: 'id = ?', whereArgs: [urunId]);
      final yerelSatir =
          (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;

      final gelen = Map<String, dynamic>.from(yerelSatir)
        ..['satis_fiyati'] = 150.0
        ..['last_updated'] = DateTime(2026, 9, 21, 10, 6).toIso8601String();

      final uygulandi =
          await _kayitUygulaVeyaAtla(db, 'urunler', yerelSatir, gelen, sonGonderFiligrani);
      expect(uygulandi, isTrue);

      final sonuc = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect(sonuc['satis_fiyati'], 150.0,
          reason: 'master veride LWW aynen devam etmeli — davranış korunmalı');
    });
  });

  group('Çakışma yoksa (sadece tek yönlü normal yayılma) her iki sınıfta da uygulanır', () {
    test('işlem verisi tablosunda GERÇEK olmayan farkta yine uygulanır',
        () async {
      // Yerel, filigrandan BERİ hiç değişmemiş (gercekCakismaMi=false) —
      // bu sadece normal, tek yönlü senkron yayılması.
      final yerelSonGuncelleme = DateTime(2026, 9, 21, 9, 55);
      final sonGonderFiligrani = DateTime(2026, 9, 21, 10, 0);

      final id = await db.insert('kasa_hareketleri', {
        'global_id': 'kasa-2', 'hareket_tipi': 'Satış', 'tutar': 100,
        'bakiye_sonrasi': 500,
        'last_updated': yerelSonGuncelleme.toIso8601String(),
      });
      final yerelSatir =
          (await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [id])).first;

      final gelen = {
        'global_id': 'kasa-2', 'hareket_tipi': 'Satış', 'tutar': 100,
        'bakiye_sonrasi': 700, // başka bir cihazın DAHA ÖNCEKİ, normal güncellemesi
        'last_updated': DateTime(2026, 9, 21, 10, 10).toIso8601String(),
      };

      final uygulandi = await _kayitUygulaVeyaAtla(
          db, 'kasa_hareketleri', yerelSatir, gelen, sonGonderFiligrani);
      expect(uygulandi, isTrue);

      final sonuc = (await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [id])).first;
      expect(sonuc['bakiye_sonrasi'], 700);
    });
  });
}
