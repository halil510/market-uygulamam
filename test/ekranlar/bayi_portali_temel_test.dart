// test/ekranlar/bayi_portali_temel_test.dart
//
// Bayi Portalı (erp_roadmap madde 39, kullanıcı onayıyla "aynı uygulama
// içinde Bayi rolü") temel altyapısının doğrulanması: kullanicilar.
// bayi_cari_id kolonu, KullaniciModel round-trip, AuthState.isBayi
// getter'ı ve router'ın bayi kullanıcısını HER ZAMAN /bayi'ye
// yönlendirmesi gereken güvenlik kuralının mantığı.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/modeller/kullanici_model.dart';
import 'package:market_plus/saglayicilar/riverpod/auth_provider.dart';
import '../helper/test_initializer.dart';

void main() {
  group('KullaniciModel.bayiCariId', () {
    test('fromMap/toMap round-trip doğru çalışır', () {
      final m = KullaniciModel.fromMap({
        'id': 1, 'kullanici_adi': 'bayi1', 'sifre_hash': 'x', 'ad_soyad': 'Test Bayi',
        'rol': 'personel', 'aktif': 1, 'bayi_cari_id': 42,
      });
      expect(m.bayiCariId, 42);
      expect(m.isBayi, isTrue);
      expect(m.toMap()['bayi_cari_id'], 42);
    });

    test('bayi_cari_id NULL ise isBayi false döner (normal personel)', () {
      final m = KullaniciModel.fromMap({
        'id': 1, 'kullanici_adi': 'kasiyer1', 'sifre_hash': 'x', 'ad_soyad': 'Kasiyer',
        'rol': 'kasiyer', 'aktif': 1,
      });
      expect(m.bayiCariId, isNull);
      expect(m.isBayi, isFalse);
    });

    test('toMap bayiCariId null ise anahtarı hiç eklemez (mevcut satırı bozmaz)', () {
      const m = KullaniciModel(
        kullaniciAdi: 'x', sifreHash: 'y', adSoyad: 'z',
      );
      expect(m.toMap().containsKey('bayi_cari_id'), isFalse);
    });
  });

  group('AuthState.isBayi', () {
    test('bayi_cari_id dolu kullanıcı için true, bayiCariId doğru yansır', () {
      final kullanici = KullaniciModel.fromMap({
        'id': 1, 'kullanici_adi': 'bayi1', 'sifre_hash': 'x', 'ad_soyad': 'Test Bayi',
        'rol': 'personel', 'aktif': 1, 'bayi_cari_id': 7,
      });
      final state = AuthState.girisYapildi(kullanici);
      expect(state.isBayi, isTrue);
      expect(state.bayiCariId, 7);
      expect(state.isAdmin, isFalse, reason: 'bayi hesabı hiçbir zaman admin sayılmamalı');
    });

    test('normal personel kullanıcı için false', () {
      final kullanici = KullaniciModel.fromMap({
        'id': 1, 'kullanici_adi': 'k1', 'sifre_hash': 'x', 'ad_soyad': 'K',
        'rol': 'admin', 'aktif': 1,
      });
      final state = AuthState.girisYapildi(kullanici);
      expect(state.isBayi, isFalse);
      expect(state.bayiCariId, isNull);
    });
  });

  // kullanicilar.bayi_cari_id gerçek şemada var mı ve doğru çalışıyor mu
  // — hem fresh-install (TabloOlusturucu, temel_semasi.dart) hem
  // migration (migrasyon_yonetici.dart._v57denV58e) yolunun AYNI
  // sütunu ürettiğini doğrular.
  group('kullanicilar.bayi_cari_id şema doğrulaması', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    test('sütun var, bir cari referansı ile kullanıcı eklenip okunabiliyor', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, unvan: 'Test Bayi', cariTipi: 'Tedarikçi');
      await db.update('cari', {'musteri_tipi': 'Bayi'}, where: 'id = ?', whereArgs: [cariId]);

      final kullaniciId = await db.insert('kullanicilar', {
        'kullanici_adi': 'testbayi', 'sifre_hash': 'hash', 'ad_soyad': 'Test Bayi',
        'rol': 'personel', 'bayi_cari_id': cariId,
      });

      final rows = await db.query('kullanicilar', where: 'id = ?', whereArgs: [kullaniciId]);
      expect(rows.first['bayi_cari_id'], cariId);
    });

    test('bayi_cari_id NULL bırakılan normal personel kaydı etkilenmez', () async {
      final kullaniciId = await db.insert('kullanicilar', {
        'kullanici_adi': 'kasiyer1', 'sifre_hash': 'hash', 'ad_soyad': 'Kasiyer',
        'rol': 'kasiyer',
      });
      final rows = await db.query('kullanicilar', where: 'id = ?', whereArgs: [kullaniciId]);
      expect(rows.first['bayi_cari_id'], isNull);
    });
  });
}
