// test/servisler/ai_eylem_motoru_test.dart
//
// Asistanın İŞLEM motoru — GERÇEK depo/servislerle uçtan uca:
//   komut cümlesi → önizleme → onay → veritabanında doğrulama.
// Ortam: robot ortamı (bellek içi gerçek şema, tohum veri, admin girişi).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/sifre_hash.dart';
import 'package:market_plus/servisler/ai/eylem/ai_eylem_modeli.dart';
import 'package:market_plus/servisler/ai/eylem/ai_eylem_motoru.dart';
import 'package:market_plus/servisler/auth_servisi.dart';
import '../robot/robot_ortam.dart';

void main() {
  late Database db;
  late RobotVeri v;
  final motor = AiEylemMotoru();

  Future<double> sayi(String sql, [List<Object?>? a]) async {
    final r = await db.rawQuery(sql, a);
    return (r.first.values.first as num?)?.toDouble() ?? 0;
  }

  Future<double> fiyat(String ad) =>
      sayi("SELECT satis_fiyati FROM urunler WHERE urun_adi LIKE ?", ['%$ad%']);
  Future<double> stok(String ad) => sayi("SELECT stok FROM urunler WHERE urun_adi LIKE ?", ['%$ad%']);

  Future<AiEylemSonucu> ver(String s) async {
    final r = await motor.coz(s, aiYedek: false);
    expect(r, isNotNull, reason: 'komut anlaşılmalı: $s');
    return r!;
  }

  setUp(() async {
    await RobotOrtam.hazirla();
    db = await RobotOrtam.veritabaniAc();
    v = await RobotOrtam.tohumla(db);
    expect(await AuthServisi().girisYap('admin', '1234'), isTrue);
  });
  tearDown(() async {
    // Motor, Onay Merkezi gibi bazı kayıtları BEKLEMEDEN (fire-and-forget)
    // yazar; veritabanı kapanmadan önce bitmelerine fırsat ver.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await AuthServisi().cikisYap();
    await db.close();
  });

  group('Fiyat', () {
    test('satış fiyatı ayarla: önizleme veriyi DEĞİŞTİRMEZ, onay değiştirir', () async {
      final r = await ver('çikolatanın satış fiyatını 30 yap');
      expect(r.oneri, isNotNull);
      expect(r.oneri!.satirlar.join(' '), contains('25'));
      expect(r.oneri!.satirlar.join(' '), contains('30'));
      expect(await fiyat('Çikolata'), 25, reason: 'önizleme yazmamalı');

      final sonuc = await r.oneri!.calistir();
      expect(sonuc, startsWith('✅'));
      expect(await fiyat('Çikolata'), 30);

      // çift dokunma ikinci kez UYGULAMAZ
      expect(await r.oneri!.calistir(), contains('zaten'));
      expect(await fiyat('Çikolata'), 30);
    });

    test('yüzde zam', () async {
      final r = await ver('çikolataya yüzde 10 zam yap');
      await r.oneri!.calistir();
      expect(await fiyat('Çikolata'), closeTo(27.5, 0.001));
    });

    test('tutar indirim ve sıfır/eksi sonuç reddi', () async {
      var r = await ver('suyun fiyatını 3 lira düşür');
      await r.oneri!.calistir();
      expect(await fiyat('Su'), 7);
      r = await ver('suyun fiyatını 50 lira düşür');
      expect(r.oneri, isNull);
      expect(r.mesaj, contains('geçersiz'));
    });

    test('alış fiyatı KDV dahil alanı da güncellenir', () async {
      final r = await ver('çikolatanın alış fiyatını 20 yap');
      await r.oneri!.calistir();
      final satir = (await db.query('urunler', where: 'urun_adi LIKE ?', whereArgs: ['%Çikolata%'])).first;
      expect((satir['alis_fiyat'] as num).toDouble(), 20);
    });

    test('satış fiyatı değişince kayıtlı indirim sıfırlanır', () async {
      await db.update('urunler', {'indirim_orani': 20, 'indirimli_fiyat': 20},
          where: 'id = ?', whereArgs: [v.id['urun0']]);
      final r = await ver('çikolatanın fiyatını 40 yap');
      expect(r.oneri!.uyarilar.join(' '), contains('indirim'));
      await r.oneri!.calistir();
      final satir = (await db.query('urunler', where: 'id = ?', whereArgs: [v.id['urun0']])).first;
      expect((satir['indirim_orani'] as num).toDouble(), 0);
    });

    test('önizlemeden sonra fiyat değişirse bayat veriyle EZMEZ', () async {
      final r = await ver('çikolatanın fiyatını 30 yap');
      await db.update('urunler', {'satis_fiyati': 99}, where: 'id = ?', whereArgs: [v.id['urun0']]);
      final sonuc = await r.oneri!.calistir();
      expect(sonuc, contains('bu arada'));
      expect(await fiyat('Çikolata'), 99);
    });

    test('ürün bulunamadı', () async {
      final r = await ver('xyzabc fiyatını 5 yap');
      expect(r.oneri, isNull);
      expect(r.mesaj, contains('bulunamadı'));
    });
  });

  group('Stok', () {
    test('artır / azalt / ayarla — hareket kaydı düşer', () async {
      var r = await ver('deterjana 50 adet stok ekle');
      await r.oneri!.calistir();
      expect(await stok('Deterjan'), 150);

      r = await ver('çikolatadan stoktan 10 düş');
      await r.oneri!.calistir();
      expect(await stok('Çikolata'), 90);

      r = await ver('suyun stoğunu 7 yap');
      await r.oneri!.calistir();
      expect(await stok('Su'), 7);

      final hareket = await sayi('SELECT COUNT(*) FROM stok_hareket');
      expect(hareket, greaterThanOrEqualTo(3));
    });

    test('eksiye düşecek çıkış reddedilir', () async {
      final r = await ver('çikolata stoğunu 500 azalt');
      expect(r.oneri, isNull);
      expect(r.mesaj, contains('EKSİYE'));
      expect(await stok('Çikolata'), 100);
    });

    test('bayat stok: arada satış olduysa uygulamaz', () async {
      final r = await ver('çikolataya 10 adet stok ekle');
      await db.update('urunler', {'stok': 80}, where: 'id = ?', whereArgs: [v.id['urun0']]);
      expect(await r.oneri!.calistir(), contains('bu arada'));
      expect(await stok('Çikolata'), 80);
    });

    test('aynı değere ayarlama: işlem yok', () async {
      final r = await ver('çikolata stoğunu 100 yap');
      expect(r.oneri, isNull);
      expect(r.mesaj, contains('zaten'));
    });
  });

  group('Belirsizlik ve bağlam', () {
    test('birden çok ürün eşleşirse SEÇENEK sunar, hiçbir şey yazmaz', () async {
      final r = await ver('robot stoğunu 5 yap');
      expect(r.oneri, isNull);
      expect(r.secimler.length, 3);
      expect(await stok('Çikolata'), 100);
      // birini onayla → yalnız o değişir
      await r.secimler.first.calistir();
      final degisen = await sayi('SELECT COUNT(*) FROM urunler WHERE stok = 5');
      expect(degisen, 1);
    });

    test('"onu" devam cümlesi son ürünü kullanır', () async {
      await ver('çikolatanın fiyatını 30 yap');
      final r = await ver('stoğunu 60 yap');
      expect(r.oneri, isNotNull);
      expect(r.oneri!.satirlar.join(' '), contains('Çikolata'));
    });

    test('yazıyla "evet" bekleyen öneriyi uygular, "vazgeç" iptal eder', () async {
      await ver('çikolatanın fiyatını 31 yap');
      final onay = await motor.onayKomutu('evet');
      expect(onay?.mesaj, startsWith('✅'));
      expect(await fiyat('Çikolata'), 31);

      await ver('çikolatanın fiyatını 50 yap');
      final iptal = await motor.onayKomutu('vazgeç');
      expect(iptal?.mesaj, contains('iptal'));
      expect(await fiyat('Çikolata'), 31);
      expect(await motor.onayKomutu('evet'), isNull, reason: 'bekleyen kalmadı');
    });
  });

  group('Ürün durumu', () {
    test('pasife al / zaten pasif', () async {
      final r = await ver('çikolatayı pasife al');
      await r.oneri!.calistir();
      expect(await sayi('SELECT aktif FROM urunler WHERE id = ?', [v.id['urun0']]), 0);
      // pasif ürün arama sonucuna gelmez → ikinci kez öneri çıkmaz
      final ikinci = await motor.coz('çikolatayı pasife al', aiYedek: false);
      expect(ikinci?.oneri, isNull);
    });
  });

  group('Ürün ekle', () {
    test('alanlarla ekler, barkod üretir, KDV dahil alışı hesaplar', () async {
      final r = await ver('yeni ürün ekle Test Sakız alış 3 satış 5 stok 20 kdv 10');
      expect(r.oneri, isNotNull);
      await r.oneri!.calistir();
      final u = (await db.query('urunler', where: 'urun_adi = ?', whereArgs: ['Test Sakız'])).first;
      expect((u['satis_fiyati'] as num).toDouble(), 5);
      expect((u['stok'] as num).toDouble(), 20);
      expect((u['alis_fiyat_kdv_dahil'] as num).toDouble(), closeTo(3.3, 0.001));
      expect((u['barkod'] as String).isNotEmpty, isTrue);
      expect(u['kod'], u['barkod']);
    });

    test('aynı adlı ürün mükerrer açılmaz', () async {
      final r = await ver('robot çikolata 80 g ekle alış 18 satış 25');
      expect(r.oneri, isNull);
      expect(r.mesaj, contains('zaten kayıtlı'));
    });

    test('mevcut barkod çakışması reddedilir', () async {
      final r = await ver('Yeni Ürün X ekle satış 5 barkod 8690000000017');
      expect(r.oneri, isNull);
      expect(r.mesaj, contains('zaten'));
    });

    test('zararına satış uyarısı', () async {
      final r = await ver('yeni ürün ekle Zararlı Ürün alış 10 satış 5 kdv 20');
      expect(r.oneri!.uyarilar.join(' '), contains('ALTINDA'));
    });
  });

  group('Gider', () {
    test('kira gideri → Kira kategorisi, kasadan düşer', () async {
      final once = await sayi('SELECT COUNT(*) FROM kasa_hareketleri');
      final r = await ver('kira gideri 15000 ekle');
      expect(r.oneri!.satirlar.join(' '), contains('Kira'));
      expect(r.oneri!.kritik, isTrue);
      await r.oneri!.calistir();
      expect(await sayi('SELECT tutar FROM giderler ORDER BY id DESC LIMIT 1'), 15000);
      expect(await sayi('SELECT COUNT(*) FROM kasa_hareketleri'), greaterThan(once));
    });

    test('eşleşmeyen kategori → Diğer + uyarı', () async {
      final r = await ver('çay ocağı gideri 200 ekle');
      expect(r.oneri!.satirlar.join(' '), contains('Diğer'));
      expect(r.oneri!.uyarilar, isNotEmpty);
    });

    test('banka/kart ile gider asistanda yapılmaz', () async {
      final r = await ver('kira gideri 15000 havale ile ekle');
      expect(r.oneri, isNull);
      expect(r.mesaj, contains('NAKİT'));
    });
  });

  group('Tahsilat / ödeme / cari', () {
    test('tahsilat: cari hareketi + kasa girişi, bakiye düşer', () async {
      final r = await ver("Robot Müşteri'den 500 lira tahsilat al");
      expect(r.oneri!.satirlar.join(' '), contains('Robot Müşteri'));
      expect(r.oneri!.kritik, isTrue);
      await r.oneri!.calistir();
      expect(await sayi('SELECT alacak FROM cari_hareket WHERE cari_id = ? ORDER BY id DESC LIMIT 1', [v.id['cari']]), 500);
      expect(await sayi('SELECT bakiye FROM cari WHERE id = ?', [v.id['cari']]), -500);
    });

    test('ödeme yap: borç hareketi, kasadan çıkış', () async {
      final r = await ver("Robot Tedarikçi'ye 300 lira ödeme yap");
      await r.oneri!.calistir();
      expect(await sayi('SELECT borc FROM cari_hareket WHERE cari_id = ? ORDER BY id DESC LIMIT 1', [v.id['tedarikci']]), 300);
    });

    test('havale ile tahsilat asistanda yapılmaz', () async {
      final r = await ver('Robot Müşteri 500 lira havale tahsilat al');
      expect(r.oneri, isNull);
      expect(r.mesaj, contains('NAKİT'));
    });

    test('yeni cari ekle', () async {
      final r = await ver('yeni müşteri Test Cari 05321112233');
      await r.oneri!.calistir();
      final c = (await db.query('cari', where: 'unvan = ?', whereArgs: ['Test Cari'])).first;
      expect(c['telefon'], '05321112233');
      // tekrar → mükerrer açmaz
      final r2 = await ver('yeni müşteri Test Cari');
      expect(r2.oneri, isNull);
      expect(r2.mesaj, contains('zaten'));
    });
  });

  group('Yetki', () {
    test('kasiyer ürün/fiyat/gider işlemi yapamaz', () async {
      final tuz = SifreHash.tuzUret();
      await db.insert('kullanicilar', {
        'kullanici_adi': 'kasiyer1', 'sifre_hash': SifreHash.hashleTuzlu('1234', tuz), 'tuz': tuz,
        'ad_soyad': 'Kasiyer', 'rol': 'kasiyer', 'aktif': 1, 'global_id': 'g-kasiyer',
      });
      await AuthServisi().cikisYap();
      expect(await AuthServisi().girisYap('kasiyer1', '1234'), isTrue);

      for (final s in ['çikolatanın fiyatını 30 yap', 'kira gideri 15000 ekle', 'çikolata stoğunu 5 yap']) {
        final r = await ver(s);
        expect(r.oneri, isNull, reason: s);
        expect(r.mesaj, contains('yetki'), reason: s);
      }
      expect(await fiyat('Çikolata'), 25);
    });
  });

  group('Okuma soruları işlem sayılmaz', () {
    for (final s in ['kritik stoklar', 'bugünkü ciro ne kadar', 'borçlu müşteriler', 'kolanın fiyatı kaç']) {
      test('"$s"', () async => expect(await motor.coz(s, aiYedek: false), isNull));
    }
  });

  group('AiEylemOnerisi', () {
    test('süresi dolan öneri çalışmaz', () async {
      final o = AiEylemOnerisi(
        id: 'x',
        tur: AiEylemTuru.fiyatGuncelle,
        baslik: 't',
        satirlar: const [],
        olusturma: DateTime.now().subtract(const Duration(minutes: 30)),
        uygula: () async => 'ÇALIŞTI',
      );
      expect(o.suresiDoldu, isTrue);
      expect(await o.calistir(), contains('süresi doldu'));
    });

    test('iptal edilen öneri çalışmaz', () async {
      var calisti = false;
      final o = AiEylemOnerisi(
        id: 'y',
        tur: AiEylemTuru.cariEkle,
        baslik: 't',
        satirlar: const [],
        uygula: () async {
          calisti = true;
          return 'ok';
        },
      );
      o.iptalEt();
      await o.calistir();
      expect(calisti, isFalse);
    });
  });
}
