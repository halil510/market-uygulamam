// test/veri/sync_cakisma_tespit_test.dart
//
// Sync Çakışmaları özelliğinin (protokol §12) çekirdek fark-tespit
// mantığını test eder — Veritabani.supaKayitlariGuncelle() içinde, bir
// kaydın gelen (buluttan) sürümüyle üzerine yazılmadan ÖNCE çağrılır.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/veri/database/sync_cakisma_tespit.dart';

void main() {
  group('SyncCakismaTespit.farklariBul', () {
    test('aynı veri, sadece last_updated farklıysa çakışma YOK', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'ad': 'Ürün', 'fiyat': 100,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'ad': 'Ürün', 'fiyat': 100,
        'last_updated': '2026-01-01T10:00:05'};

      expect(SyncCakismaTespit.farklariBul(yerel, gelen), isEmpty);
    });

    test('gerçek fiyat farkı varsa çakışma tespit edilir', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'ad': 'Ürün', 'fiyat': 125,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'ad': 'Ürün', 'fiyat': 129,
        'last_updated': '2026-01-01T10:00:03'};

      final farklar = SyncCakismaTespit.farklariBul(yerel, gelen);
      expect(farklar, contains('fiyat'));
      expect(farklar['fiyat'], equals({'yerel': 125, 'gelen': 129}));
      expect(farklar.containsKey('ad'), isFalse,
          reason: 'ad aynı olduğu için farklar listesinde OLMAMALI');
    });

    test('int/double aynı değer yanlış pozitif üretmez', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'fiyat': 100,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'fiyat': 100.0,
        'last_updated': '2026-01-01T10:00:03'};

      expect(SyncCakismaTespit.farklariBul(yerel, gelen), isEmpty);
    });

    test('birden fazla alan farklıysa hepsi raporlanır', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'ad': 'A', 'fiyat': 100, 'stok': 10,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'ad': 'B', 'fiyat': 200, 'stok': 10,
        'last_updated': '2026-01-01T10:00:03'};

      final farklar = SyncCakismaTespit.farklariBul(yerel, gelen);
      expect(farklar.keys.toSet(), equals({'ad', 'fiyat'}));
    });

    test('null vs değer farkı yakalanır', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'aciklama': null,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'aciklama': 'not eklendi',
        'last_updated': '2026-01-01T10:00:03'};

      final farklar = SyncCakismaTespit.farklariBul(yerel, gelen);
      expect(farklar, contains('aciklama'));
    });
  });

  // 🔴 Regresyon testleri (kullanıcı bulgusu — "sync çakışma var
  // diyor"): ÖNCEDEN her fark, bu cihaz o kaydı hiç düzenlememiş olsa
  // bile "çakışma" sayılıyordu — başka bir cihazın normal, tek yönlü
  // güncellemesinin bu cihaza ilk kez ulaşması da aynı şekilde
  // raporlanıyordu. gercekCakismaMi() artık bunu ayırt ediyor.
  group('SyncCakismaTespit.gercekCakismaMi', () {
    test('yerel kayıt en son başarılı gönderimden SONRA değişmişse '
        'GERÇEK çakışma sayılır', () {
      final sonrasi = SyncCakismaTespit.gercekCakismaMi(
        yerelSonGuncelleme: DateTime.parse('2026-01-01T10:05:00'),
        sonBasariliGonderim: DateTime.parse('2026-01-01T10:00:00'),
      );
      expect(sonrasi, isTrue);
    });

    test('yerel kayıt en son başarılı gönderimden ÖNCE/EŞİT değişmişse '
        '— bu cihazda kaybolacak bir şey yok, çakışma SAYILMAZ', () {
      final oncesi = SyncCakismaTespit.gercekCakismaMi(
        yerelSonGuncelleme: DateTime.parse('2026-01-01T09:55:00'),
        sonBasariliGonderim: DateTime.parse('2026-01-01T10:00:00'),
      );
      expect(oncesi, isFalse);

      final esiti = SyncCakismaTespit.gercekCakismaMi(
        yerelSonGuncelleme: DateTime.parse('2026-01-01T10:00:00'),
        sonBasariliGonderim: DateTime.parse('2026-01-01T10:00:00'),
      );
      expect(esiti, isFalse);
    });

    test('bu tablo bu cihazdan hiç gönderilmediyse (filigran yok) '
        'emin olunamaz — güvenli tarafta kalınır, GERÇEK çakışma sayılır', () {
      final sonuc = SyncCakismaTespit.gercekCakismaMi(
        yerelSonGuncelleme: DateTime.parse('2026-01-01T10:05:00'),
        sonBasariliGonderim: null,
      );
      expect(sonuc, isTrue);
    });

    test('yerel last_updated ayrıştırılamıyorsa (null) emin olunamaz — '
        'güvenli tarafta kalınır', () {
      final sonuc = SyncCakismaTespit.gercekCakismaMi(
        yerelSonGuncelleme: null,
        sonBasariliGonderim: DateTime.parse('2026-01-01T10:00:00'),
      );
      expect(sonuc, isTrue);
    });
  });

  // FAZ 3 (DEEP_AUDIT_REPORT madde 4, 2026-09-21, kullanıcı onaylı
  // mimari karar): işlem/hareket verisi tablolarının sınıflandırması.
  group('SyncCakismaTespit.islemVerisiMi', () {
    test('finansal/hareket ledger tabloları işlem verisi sayılır', () {
      for (final t in [
        'satislar', 'satis_kalem', 'stok_hareket', 'cari_hareket',
        'kasa_hareketleri', 'banka_hareketler', 'kredi_karti_hareket',
        'iade', 'iade_kalem', 'puan_hareket', 'borc_odemeler',
        'audit_log', 'onay_talepleri', 'adisyon_log', 'garson_cagri_log',
        'masa_hareket_log', 'vardiyalar',
      ]) {
        expect(SyncCakismaTespit.islemVerisiMi(t), isTrue, reason: t);
      }
    });

    test('güncel-durum (master) tabloları işlem verisi SAYILMAZ', () {
      for (final t in [
        'urunler', 'cari', 'kullanicilar', 'subeler', 'kategoriler',
        'ayarlar', 'masalar', 'masa_siparisleri', 'borclar',
        'banka_hesaplar', 'promosyonlar', 'donem_kilit',
      ]) {
        expect(SyncCakismaTespit.islemVerisiMi(t), isFalse, reason: t);
      }
    });
  });
}
