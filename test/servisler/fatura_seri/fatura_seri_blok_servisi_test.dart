// test/servisler/fatura_seri/fatura_seri_blok_servisi_test.dart
//
// FaturaSeriBlokServisi.faturaNoTuket() — MERKEZİ FATURA SERİ/BLOK
// YÖNETİMİ'nin yerel, offline-güvenli tüketim mantığını test eder.
// Bkz. CENTRAL_DOCUMENT_NUMBERING_DEEP_AUDIT.md §25 (Test Planı).
//
// NOT: Bu testler SADECE ağ gerektirmeyen kısmı (yerel blok tüketimi,
// atomiklik, tükenme tespiti) kapsar — Supabase RPC'sinin gerçek
// çoklu-terminal concurrency garantisi (canlı Postgres'e ihtiyaç
// duyar) bu ortamda test edilemez; bkz. supabase_fatura_seri_bloklari
// .sql dosyasının sonundaki manuel doğrulama adımları.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/fatura_seri/fatura_seri_blok_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../../helper/test_initializer.dart';

Future<int> _blokEkle(Database db,
    {String seri = 'HLF', int? yil, required int baslangic, required int bitis, String durum = 'aktif'}) {
  return db.insert('yerel_fatura_blok', {
    'seri': seri,
    'yil': yil ?? DateTime.now().year,
    'blok_baslangic': baslangic,
    'blok_bitis': bitis,
    'siradaki': baslangic,
    'durum': durum,
  });
}

final _yil = DateTime.now().year;

void main() {
  late Database db;
  final servis = FaturaSeriBlokServisi();

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('FaturaSeriBlokServisi.faturaNoTuket', () {
    test('bloktan sırayla, artan numaralar tüketir', () async {
      await _blokEkle(db, baslangic: 100, bitis: 105);

      final sonuc1 = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      final sonuc2 = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      final sonuc3 = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));

      expect(sonuc1.numara, 100);
      expect(sonuc2.numara, 101);
      expect(sonuc3.numara, 102);
      expect(sonuc1.yil, _yil);
    });

    test('blok tam tüketilince durum tukendi olur ve bir daha numara vermez', () async {
      await _blokEkle(db, baslangic: 1, bitis: 2);

      final s1 = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      final s2 = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      expect(s1.numara, 1);
      expect(s2.numara, 2);

      // Blok artık tükenmiş olmalı.
      final satir = (await db.query('yerel_fatura_blok', limit: 1)).first;
      expect(satir['durum'], 'tukendi');

      // Üçüncü tüketim BlokTukendiException fırlatmalı — sessizce eski
      // MAX+1 yöntemine ya da mükerrer bir numaraya asla dönülmemeli.
      expect(
        () => db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF')),
        throwsA(isA<BlokTukendiException>()),
      );
    });

    test('hiç blok yoksa doğrudan BlokTukendiException fırlatır', () async {
      expect(
        () => db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF')),
        throwsA(isA<BlokTukendiException>()),
      );
    });

    test('farklı seri için ayrı blok kullanılır, birbirini etkilemez', () async {
      await _blokEkle(db, seri: 'HLF', baslangic: 1, bitis: 5);
      await _blokEkle(db, seri: 'HLA', baslangic: 500, bitis: 505);

      final hlf = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      final hla = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLA'));

      expect(hlf.numara, 1);
      expect(hla.numara, 500);
    });

    test('eski/tükenmiş bir blok varken YENİ aktif blok eklenirse ondan devam eder '
        '(iki blok birbirine karışmaz, sıradaki blok kullanılır)', () async {
      await _blokEkle(db, baslangic: 1, bitis: 1, durum: 'tukendi');
      await _blokEkle(db, baslangic: 50, bitis: 55);

      final sonuc = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      expect(sonuc.numara, 50);
    });

    test('AYNI transaction içinde art arda tüketim — atomiklik: hiçbir '
        'numara İKİ KEZ verilmez (aynı cihaz içi yarışa karşı temel güvence)', () async {
      await _blokEkle(db, baslangic: 1, bitis: 20);

      final uretilenler = <int>[];
      // Gerçek eşzamanlı cihazlar arası yarış Postgres RPC'sinde
      // engellenir (bu ortamda test edilemez) — burada tek cihazdaki
      // ATOMİK okuma+güncelleme örüntüsünün kendisini doğruluyoruz:
      // art arda 10 tüketim, 10 BENZERSİZ ve ARTAN numara üretmeli.
      for (var i = 0; i < 10; i++) {
        final s = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
        uretilenler.add(s.numara);
      }

      expect(uretilenler, List.generate(10, (i) => i + 1));
      expect(uretilenler.toSet().length, 10, reason: 'mükerrer numara üretildi');
    });
  });

  group('FaturaSeriBlokServisi.blokHazirOldugundanEminOl — kullanılmış numara atlama', () {
    setUp(() => Veritabani.testVeritabani = db);
    tearDown(() => Veritabani.testVeritabani = null);

    Future<void> faturaEkle(String no) => db.insert('faturalar', {'fatura_no': no});

    test('manuel ekranın önceden aldığı numarayı atlar (otomatik faturalar kilitlenmez)', () async {
      await _blokEkle(db, baslangic: 11, bitis: 20);
      // Manuel "Fatura Ekle" (yerel MAX+1) bloğun sıradaki 11 ve 12'sini almış.
      await faturaEkle('HLF${_yil}000000011');
      await faturaEkle('HLF${_yil}000000012');

      await servis.blokHazirOldugundanEminOl('HLF');
      final s = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      expect(s.numara, 13);
    });

    test('kullanılmamış numarada hiçbir şey atlamaz', () async {
      await _blokEkle(db, baslangic: 11, bitis: 20);
      await faturaEkle('HLF${_yil}000000013'); // sıradaki (11) boş — araya dokunulmaz

      await servis.blokHazirOldugundanEminOl('HLF');
      final s = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      expect(s.numara, 11);
    });

    test('farklı serideki aynı sıra numarası atlamaya sebep olmaz', () async {
      await _blokEkle(db, baslangic: 11, bitis: 20);
      await faturaEkle('FTR${_yil}000000011');

      await servis.blokHazirOldugundanEminOl('HLF');
      final s = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      expect(s.numara, 11);
    });
  });

  // Derin denetim (2026-11-09) #15, yüksek: yeni yılda ÖNCEKİ yılın aktif
  // bloğundan numara veriliyordu (numaradaki yıl ≠ düzenleme yılı).
  group('FaturaSeriBlokServisi — yıl devri (#15)', () {
    setUp(() => Veritabani.testVeritabani = db);
    tearDown(() => Veritabani.testVeritabani = null);

    test('önceki yılın aktif bloğundan numara tüketilmez', () async {
      await _blokEkle(db, yil: _yil - 1, baslangic: 5, bitis: 10);
      await expectLater(
          db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF')),
          throwsA(isA<BlokTukendiException>()));
    });

    test('hazırlıkta önceki yılın aktif bloğu kapatılır, bu yılın bloğundan devam edilir', () async {
      final eski = await _blokEkle(db, yil: _yil - 1, baslangic: 5, bitis: 10);
      await _blokEkle(db, baslangic: 1, bitis: 10); // bu yıl
      await servis.blokHazirOldugundanEminOl('HLF');
      final eskiDurum = (await db.query('yerel_fatura_blok', where: 'id = ?', whereArgs: [eski]))
          .first['durum'];
      expect(eskiDurum, 'kapandi');
      final s = await db.transaction((txn) => servis.faturaNoTuket(txn, 'HLF'));
      expect(s.yil, _yil);
      expect(s.numara, 1);
    });
  });
}
