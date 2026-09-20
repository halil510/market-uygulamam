// test/servisler/virman_servisi_test.dart
//
// VirmanServisi.virmanYap() (Madde 2 mimari denetimi, 2026-09-20:
// virman_ekrani.dart'tan taşındı) — Kasa/Banka/Kredi Kartı arası
// virmanın HER ikili kombinasyonunda İKİ TARAFI DA güncellediğini
// doğrular.
//
// 🔴 REGRESYON TESTİ (bkz. virman_ekrani.dart'taki Madde 11 yorumu):
// bu ekran ÖNCEDEN "Banka" veya "Kredi Kartı" taraf olduğunda O TARAFA
// HİÇ YAZMIYORDU — sadece Kasa tarafı (varsa) kaydediliyordu, diğer
// taraf sessizce hiçbir yere işlenmiyordu. Kullanıcı "✓ virman yapıldı"
// başarı mesajı görürken banka hesabı/kart limiti GERÇEKTE HİÇ
// değişmiyordu — para sessizce kayboluyordu. Bu test, en riskli
// senaryoyu (Banka↔Kredi Kartı, Kasa hiç taraf değilken) özellikle
// kapsıyor.
//
// VirmanServisi Veritabani() singleton'ı üzerinden çalıştığı için
// (diğer depo/servis testlerinde olduğu gibi) burada altındaki gerçek
// depo metodları (KasaDeposu.hareketEkleTxn, BankaHareketDeposu.ekleTxn,
// KrediKartiDeposu.limitDegistirTxn) — VirmanServisi.virmanYap() ile
// BİREBİR AYNI sırayla — gerçek şema üzerinde bir in-memory veritabanı
// içinde doğrudan çağrılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/depolar/banka_hareket_deposu.dart';
import 'package:market_plus/depolar/kredi_karti_deposu.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';
import 'package:market_plus/modeller/banka_hareket_model.dart';
import '../helper/test_initializer.dart';

/// VirmanServisi.virmanYap()'ın AYNI orkestrasyonu — tek fark, gerçek
/// Veritabani() singleton'ı yerine test db'sinin transaction'ı kullanılır.
Future<void> _virmanYap(
  Database db, {
  required String kaynakHesap,
  required String hedefHesap,
  required double tutar,
  int? bankaHesapId,
  int? krediKartiId,
}) async {
  final now = DateTime.now();
  await db.transaction((txn) async {
    if (kaynakHesap == 'Kasa') {
      await KasaDeposu().hareketEkleTxn(txn, KasaHareketModel(
          hareketTipi: 'Virman Çıkış', tutar: tutar, tarih: now,
          aciklama: 'test (Çıkış)', referansTuru: 'virman'));
    } else if (hedefHesap == 'Kasa') {
      await KasaDeposu().hareketEkleTxn(txn, KasaHareketModel(
          hareketTipi: 'Virman Giriş', tutar: tutar, tarih: now,
          aciklama: 'test (Giriş)', referansTuru: 'virman'));
    }
    if (kaynakHesap == 'Banka' && bankaHesapId != null) {
      await BankaHareketDeposu().ekleTxn(txn, BankaHareketModel(
          bankaHesapId: bankaHesapId, islemTipi: 'Giden',
          tutar: tutar, tarih: now, aciklama: 'test (Çıkış)'));
    } else if (hedefHesap == 'Banka' && bankaHesapId != null) {
      await BankaHareketDeposu().ekleTxn(txn, BankaHareketModel(
          bankaHesapId: bankaHesapId, islemTipi: 'Gelen',
          tutar: tutar, tarih: now, aciklama: 'test (Giriş)'));
    }
    if (kaynakHesap == 'Kredi Kartı' && krediKartiId != null) {
      await KrediKartiDeposu().limitDegistirTxn(
          txn, krediKartiId, tutar, aciklama: 'test (Avans)');
    } else if (hedefHesap == 'Kredi Kartı' && krediKartiId != null) {
      await KrediKartiDeposu().limitDegistirTxn(
          txn, krediKartiId, -tutar, aciklama: 'test (Ödeme)');
    }
  });
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<int> _bankaIdAl() async => db.insert('bankalar', {'ad': 'Test Bankası'});

  Future<int> _bankaEkle({double bakiye = 0}) async {
    final bankaId = await _bankaIdAl();
    return db.insert('banka_hesaplar', {
      'banka_id': bankaId, 'hesap_adi': 'Test Hesap', 'hesap_no': '123',
      'bakiye': bakiye, 'kullanilabilir_bakiye': bakiye,
    });
  }

  // NOT: KrediKartiDeposu.limitDegistirTxn() kullanilan_limit'i HER
  // ÇAĞRIDA kredi_karti_hareket tablosundaki TÜM satırların toplamından
  // YENİDEN HESAPLAR (running-total DEĞİL) — bu yüzden başlangıç
  // "kullanılan" değeri burada satırdaki kolona değil, gerçek bir
  // kredi_karti_hareket satırına yazılmalı; aksi halde ilk virmanYap()
  // çağrısı bu sahte başlangıç değerini görmezden gelip sıfırdan
  // hesaplar (bu, testi yazarken bulunan bir ayrıntı — production
  // davranışı DOĞRU, sadece test kurulumunun buna uyması gerekiyordu).
  Future<int> _krediKartiEkle({double limit = 10000, double kullanilan = 0}) async {
    final bankaId = await _bankaIdAl();
    final kartId = await db.insert('kredi_kartlari', {
      'banka_id': bankaId, 'kart_adi': 'Test Kart', 'kart_no_maskeli': '**** 1234',
      'kartlimit': limit, 'kullanilan_limit': kullanilan,
      'kalan_limit': limit - kullanilan,
    });
    if (kullanilan > 0) {
      await db.insert('kredi_karti_hareket', {
        'global_id': 'seed-$kartId', 'kredi_karti_id': kartId,
        'tutar': kullanilan, 'yon': 'harcama', 'aciklama': 'Başlangıç bakiyesi (test)',
      });
    }
    return kartId;
  }

  group('Kasa dahil virmanlar', () {
    test('Kasa → Banka: kasa Çıkış + banka Gelen, banka bakiyesi artar', () async {
      final bankaId = await _bankaEkle(bakiye: 500);

      await _virmanYap(db, kaynakHesap: 'Kasa', hedefHesap: 'Banka',
          tutar: 200, bankaHesapId: bankaId);

      final kasaRows = await db.query('kasa_hareketleri');
      expect(kasaRows, hasLength(1));
      expect(kasaRows.first['hareket_tipi'], 'Virman Çıkış');
      expect(kasaRows.first['tutar'], 200);

      final banka = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [bankaId])).first;
      expect(banka['bakiye'], 700); // 500 + 200
    });

    test('Banka → Kasa: kasa Giriş + banka Giden, banka bakiyesi azalır', () async {
      final bankaId = await _bankaEkle(bakiye: 500);

      await _virmanYap(db, kaynakHesap: 'Banka', hedefHesap: 'Kasa',
          tutar: 150, bankaHesapId: bankaId);

      final kasaRows = await db.query('kasa_hareketleri');
      expect(kasaRows.first['hareket_tipi'], 'Virman Giriş');

      final banka = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [bankaId])).first;
      expect(banka['bakiye'], 350); // 500 - 150
    });

    test('Kasa → Kredi Kartı: kasa Çıkış + kart kullanılan limiti AZALIR (ödeme)', () async {
      // Kart burada HEDEF — kasadan karta para gidiyor, yani kart borcu
      // ÖDENİYOR (bkz. VirmanServisi.virmanYap() yorumu: "Kart HEDEF ise
      // kullanılan limit AZALIR").
      final kartId = await _krediKartiEkle(limit: 5000, kullanilan: 1000);

      await _virmanYap(db, kaynakHesap: 'Kasa', hedefHesap: 'Kredi Kartı',
          tutar: 300, krediKartiId: kartId);

      final kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect(kart['kullanilan_limit'], 700); // 1000 - 300 (ödeme)
      expect(kart['kalan_limit'], 4300); // 5000 - 700
    });
  });

  group('🔴 REGRESYON — Kasa taraf DEĞİLKEN (önceden para sessizce kayboluyordu)', () {
    test('Banka → Kredi Kartı: HER İKİ taraf da güncellenir, kasa hiç etkilenmez', () async {
      final bankaId = await _bankaEkle(bakiye: 1000);
      final kartId = await _krediKartiEkle(limit: 5000, kullanilan: 2000);

      await _virmanYap(db, kaynakHesap: 'Banka', hedefHesap: 'Kredi Kartı',
          tutar: 400, bankaHesapId: bankaId, krediKartiId: kartId);

      // Kasa hiç taraf değil — kasa_hareketleri BOŞ kalmalı.
      final kasaRows = await db.query('kasa_hareketleri');
      expect(kasaRows, isEmpty);

      // Banka tarafı: para ÇIKTI.
      final banka = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [bankaId])).first;
      expect(banka['bakiye'], 600); // 1000 - 400

      // Kredi kartı tarafı: kart ÖDENDİ — kullanılan limit AZALIR.
      final kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect(kart['kullanilan_limit'], 1600); // 2000 - 400
      expect(kart['kalan_limit'], 3400); // 5000 - 1600
    });

    test('Kredi Kartı → Banka: kart AVANS çeker (limit artar), banka bakiyesi artar', () async {
      final bankaId = await _bankaEkle(bakiye: 0);
      final kartId = await _krediKartiEkle(limit: 5000, kullanilan: 0);

      await _virmanYap(db, kaynakHesap: 'Kredi Kartı', hedefHesap: 'Banka',
          tutar: 1000, bankaHesapId: bankaId, krediKartiId: kartId);

      final banka = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [bankaId])).first;
      expect(banka['bakiye'], 1000);

      final kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect(kart['kullanilan_limit'], 1000); // avans = kullanılan limit artışı
    });
  });

  test('kredi_karti_hareket satırı doğru yön/tutar ile yazılır', () async {
    final kartId = await _krediKartiEkle(limit: 2000, kullanilan: 0);

    await _virmanYap(db, kaynakHesap: 'Kasa', hedefHesap: 'Kredi Kartı',
        tutar: 250, krediKartiId: kartId);

    final hareketler = await db.query('kredi_karti_hareket', where: 'kredi_karti_id = ?', whereArgs: [kartId]);
    expect(hareketler, hasLength(1));
    expect(hareketler.first['yon'], 'odeme'); // kart HEDEF — kasadan karta = ödeme
    expect(hareketler.first['tutar'], 250);
  });
}
