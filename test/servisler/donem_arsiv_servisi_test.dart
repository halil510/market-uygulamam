// test/servisler/donem_arsiv_servisi_test.dart
//
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — GERÇEK ARŞİVLEME,
// SADECE KOPYALAMA AŞAMASI (2026-09-16). DonemArsivServisi'nin gerçek
// üretim şemasına (TestVeritabani — TabloOlusturucu) karşı UÇTAN UCA
// çalıştığını doğrular: [aktifDbTest]/[arsivDosyaYoluTest] test seamleri
// sayesinde Veritabani() singleton'ına ve path_provider'a ihtiyaç
// duymadan, gerçek geçici bir arşiv dosyasına karşı test edilebiliyor.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/donem_arsiv_servisi.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database aktif;
  late Directory geciciDizin;
  late String arsivYolu;

  setUp(() async {
    aktif = await TestVeritabani.olustur();
    geciciDizin = Directory.systemTemp.createTempSync('donem_arsiv_test_');
    arsivYolu = '${geciciDizin.path}/barkopro_2026.db';
  });

  tearDown(() async {
    await aktif.close();
    try {
      if (geciciDizin.existsSync()) geciciDizin.deleteSync(recursive: true);
    } catch (_) {
      // Bir test başarısız olup arşiv bağlantısını kapatamadan çıkarsa
      // dosya silinemeyebilir — bu tearDown'ı ASLA çökertmemeli, asıl
      // test hatası zaten ayrıca raporlanıyor.
    }
  });

  /// Şube 1'e 2026 içine düşen, Şube 2'ye ve 2025'e düşen örnek satırlar
  /// ekler — filtreleme (tarih aralığı + şube) doğru çalışıyor mu
  /// görebilmek için.
  Future<void> ornekVeriEkle() async {
    // satislar — sube_id'li
    await aktif.insert('satislar', {
      'tarih': DateTime(2026, 6, 15).toIso8601String(), 'sube_id': 1, 'genel_toplam': 100.0,
    });
    await aktif.insert('satislar', {
      'tarih': DateTime(2026, 3, 1).toIso8601String(), 'sube_id': 1, 'genel_toplam': 50.0,
    });
    await aktif.insert('satislar', { // farklı şube — dahil edilmemeli
      'tarih': DateTime(2026, 6, 15).toIso8601String(), 'sube_id': 2, 'genel_toplam': 999.0,
    });
    await aktif.insert('satislar', { // önceki yıl — dahil edilmemeli
      'tarih': DateTime(2025, 12, 31).toIso8601String(), 'sube_id': 1, 'genel_toplam': 777.0,
    });

    // stok_hareket — sube_id'li
    await aktif.insert('stok_hareket', {
      'urun_id': 1, 'hareket_turu': 'Satış', 'miktar': 5.0, 'sube_id': 1,
      'tarih': DateTime(2026, 6, 15).toIso8601String(),
    });
    await aktif.insert('stok_hareket', { // farklı şube
      'urun_id': 1, 'hareket_turu': 'Satış', 'miktar': 999.0, 'sube_id': 2,
      'tarih': DateTime(2026, 6, 15).toIso8601String(),
    });

    // cari_hareket — ŞİRKET GENELİ (sube_id yok, şube filtresi UYGULANMAMALI)
    await aktif.insert('cari_hareket', {
      'cari_id': 1, 'fis_tipi': 'Satış', 'borc': 100.0, 'alacak': 0.0,
      'tarih': DateTime(2026, 6, 15).toIso8601String(),
    });
    await aktif.insert('cari_hareket', { // önceki yıl — dahil edilmemeli
      'cari_id': 1, 'fis_tipi': 'Satış', 'borc': 50.0, 'alacak': 0.0,
      'tarih': DateTime(2025, 6, 15).toIso8601String(),
    });

    // kasa_hareketleri — sube_id'li
    await aktif.insert('kasa_hareketleri', {
      'hareket_tipi': 'Satış', 'tutar': 100.0, 'sube_id': 1,
      'tarih': DateTime(2026, 6, 15).toIso8601String(),
    });

    // banka_hareketler — ŞİRKET GENELİ
    await aktif.insert('banka_hareketler', {
      'banka_hesap_id': 1, 'islem_tipi': 'Havale', 'tutar': 250.0,
      'tarih': DateTime(2026, 6, 15).toIso8601String(),
    });
  }

  final baslangic = DateTime(2026, 1, 1);
  final bitis = DateTime(2026, 12, 31, 23, 59, 59);

  group('arsivleVeDogrula', () {
    test('5 tablo da doğrulanır, sadece dönem+şube filtresine uyan satırlar kopyalanır', () async {
      await ornekVeriEkle();
      final servis = DonemArsivServisi();

      final sonuclar = await servis.arsivleVeDogrula(
        donemYili: 2026, subeId: 1, baslangic: baslangic, bitis: bitis,
        aktifDbTest: aktif, arsivDosyaYoluTest: arsivYolu,
      );

      expect(sonuclar, hasLength(5));
      for (final s in sonuclar) {
        expect(s.dogrulandiMi, isTrue, reason: '${s.tablo} doğrulanamadı');
      }

      final satislarSonuc = sonuclar.firstWhere((s) => s.tablo == 'satislar');
      expect(satislarSonuc.kopyalanan, 2); // sadece Şube 1 + 2026
      expect(satislarSonuc.aktifToplam, 150.0);

      final stokSonuc = sonuclar.firstWhere((s) => s.tablo == 'stok_hareket');
      expect(stokSonuc.kopyalanan, 1);

      final cariSonuc = sonuclar.firstWhere((s) => s.tablo == 'cari_hareket');
      expect(cariSonuc.kopyalanan, 1); // şube filtresi YOK, ama tarih filtresi var
    });

    test('şirket geneli tablolar (cari/banka) şube filtresi UYGULANMADAN kopyalanır', () async {
      await ornekVeriEkle();
      final servis = DonemArsivServisi();
      await servis.arsivleVeDogrula(
        donemYili: 2026, subeId: 2, baslangic: baslangic, bitis: bitis, // FARKLI şube
        aktifDbTest: aktif, arsivDosyaYoluTest: arsivYolu,
      );

      final arsivDb = await openDatabase(arsivYolu);
      try {
        final cariSatirlar = await arsivDb.query('cari_hareket');
        final bankaSatirlar = await arsivDb.query('banka_hareketler');
        // sube_id=2 ile çağrılsa bile cari/banka şirket geneli olduğundan
        // aynı 2026 satırları kopyalanmalı (şube filtresi yok).
        expect(cariSatirlar, hasLength(1));
        expect(bankaSatirlar, hasLength(1));
      } finally {
        await arsivDb.close();
      }
    });

    test('master tablolar (urunler vb.) arşive HİÇ kopyalanmaz', () async {
      await ornekVeriEkle();
      final servis = DonemArsivServisi();
      await servis.arsivleVeDogrula(
        donemYili: 2026, subeId: 1, baslangic: baslangic, bitis: bitis,
        aktifDbTest: aktif, arsivDosyaYoluTest: arsivYolu,
      );

      final arsivDb = await openDatabase(arsivYolu);
      try {
        final tablolar = await arsivDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'");
        final tabloAdlari = tablolar.map((r) => r['name']).toSet();
        // sqlite_sequence, AUTOINCREMENT sütunları için SQLite'ın kendi
        // ürettiği dahili bir tablo — beklenen bir yan etki.
        expect(tabloAdlari, {
          'satislar', 'stok_hareket', 'cari_hareket', 'kasa_hareketleri',
          'banka_hareketler', 'sqlite_sequence',
        });
        expect(tabloAdlari.contains('urunler'), isFalse);
        expect(tabloAdlari.contains('cari'), isFalse);
      } finally {
        await arsivDb.close();
      }
    });

    test('aktif veriden HİÇBİR SATIR silinmez — sadece kopyalanır', () async {
      await ornekVeriEkle();
      final oncekiSayim = Sqflite.firstIntValue(
          await aktif.rawQuery('SELECT COUNT(*) FROM satislar'));

      final servis = DonemArsivServisi();
      await servis.arsivleVeDogrula(
        donemYili: 2026, subeId: 1, baslangic: baslangic, bitis: bitis,
        aktifDbTest: aktif, arsivDosyaYoluTest: arsivYolu,
      );

      final sonrakiSayim = Sqflite.firstIntValue(
          await aktif.rawQuery('SELECT COUNT(*) FROM satislar'));
      expect(sonrakiSayim, oncekiSayim);
    });

    test('idempotent — aynı devir ikinci kez çalışsa arşivde satır çoğalmaz', () async {
      await ornekVeriEkle();
      final servis = DonemArsivServisi();

      await servis.arsivleVeDogrula(
        donemYili: 2026, subeId: 1, baslangic: baslangic, bitis: bitis,
        aktifDbTest: aktif, arsivDosyaYoluTest: arsivYolu,
      );
      final sonuclar2 = await servis.arsivleVeDogrula(
        donemYili: 2026, subeId: 1, baslangic: baslangic, bitis: bitis,
        aktifDbTest: aktif, arsivDosyaYoluTest: arsivYolu,
      );

      for (final s in sonuclar2) {
        expect(s.dogrulandiMi, isTrue);
      }
      final satislarSonuc = sonuclar2.firstWhere((s) => s.tablo == 'satislar');
      expect(satislarSonuc.arsivSayim, 2); // hâlâ 2 — çoğalmadı
    });

    test('hiç satır yoksa (boş dönem) yine de doğrulanır (0=0)', () async {
      final servis = DonemArsivServisi();
      final sonuclar = await servis.arsivleVeDogrula(
        donemYili: 2026, subeId: 1, baslangic: baslangic, bitis: bitis,
        aktifDbTest: aktif, arsivDosyaYoluTest: arsivYolu,
      );
      for (final s in sonuclar) {
        expect(s.dogrulandiMi, isTrue);
        expect(s.kopyalanan, 0);
      }
    });
  });

  group('DonemArsivTabloSonucu.dogrulandiMi (saf mantık)', () {
    test('sayı ve toplam eşleşirse true', () {
      const s = DonemArsivTabloSonucu(
        tablo: 'x', kopyalanan: 10, aktifSayim: 10, arsivSayim: 10,
        aktifToplam: 1000.0, arsivToplam: 1000.0,
      );
      expect(s.dogrulandiMi, isTrue);
    });

    test('satır sayısı uyuşmazsa false', () {
      const s = DonemArsivTabloSonucu(
        tablo: 'x', kopyalanan: 9, aktifSayim: 10, arsivSayim: 9,
        aktifToplam: 1000.0, arsivToplam: 900.0,
      );
      expect(s.dogrulandiMi, isFalse);
    });

    test('toplam tutar uyuşmazsa false (sayı aynı olsa bile)', () {
      const s = DonemArsivTabloSonucu(
        tablo: 'x', kopyalanan: 10, aktifSayim: 10, arsivSayim: 10,
        aktifToplam: 1000.0, arsivToplam: 950.0,
      );
      expect(s.dogrulandiMi, isFalse);
    });

    test('0.01 altı ondalık fark tolere edilir', () {
      const s = DonemArsivTabloSonucu(
        tablo: 'x', kopyalanan: 10, aktifSayim: 10, arsivSayim: 10,
        aktifToplam: 1000.001, arsivToplam: 1000.0,
      );
      expect(s.dogrulandiMi, isTrue);
    });
  });
}
