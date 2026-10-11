// test/servisler/bulut_bolme_butcesi_test.dart
//
// Dış değerlendirme (DeepSeek, 2026-10-11) bulut bulguları:
// - Kalıcı (4xx) hatada grup ikiye bölünerek zehirli satır ayıklanır; grubun
//   TAMAMI bozuksa istek sayısı satır sayısının ~2 katına çıkıyordu → bir
//   turdaki istekler bütçeyle sınırlı, kalanlar BOZUK sayılmadan sonraki
//   tura bırakılır.
// - "Son başarılı gönderim" boş turlarda da "şimdi"ye çekiliyordu.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/servisler/bulut/bulut_saglayici.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// [bozuk] içindeki global_id'lerden biri bulunan her toplu istek 400 döner.
class _ZehirliSaglayici implements IBulutSaglayici {
  final Set<String> bozuk;
  int istekSayisi = 0;
  final giden = <String>{};
  _ZehirliSaglayici(this.bozuk);

  @override String get ad => 'Sahte';
  @override String get ikon => '🧪';
  @override Future<BaglantiSonuc> baglantiTest() async =>
      const BaglantiSonuc(basarili: true, mesaj: 'ok');
  @override
  Future<void> upsert({required String tablo, required Map<String, dynamic> veri,
      required String uniqueAlan}) async {}
  @override
  Future<BulutSonuc> topluUpsert({required String tablo,
      required List<Map<String, dynamic>> veriler, required String uniqueAlan}) async {
    istekSayisi++;
    final gidler = veriler.map((v) => v['global_id'].toString()).toList();
    if (gidler.any(bozuk.contains)) {
      return BulutSonuc(hata: veriler.length, sonStatusKodu: 400,
          hataMesajlari: const ['400']);
    }
    giden.addAll(gidler);
    return BulutSonuc(basarili: veriler.length);
  }
  @override
  Future<List<Map<String, dynamic>>> cek({required String tablo,
      DateTime? sonGuncelleme, int limit = 1000}) async => [];
  @override
  Future<void> sil({required String tablo, required String uniqueAlan,
      required String deger}) async {}
  @override
  Future<void> kaliciSil({required String tablo, required String uniqueAlan,
      required String deger}) async {}
  @override Future<void> ayarlariKaydet(Map<String, String> ayarlar) async {}
  @override Future<Map<String, String>> ayarlariYukle() async => {};
}

void main() {
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    BulutManager().testIcinSifirla();
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<void> kuyrugaYaz(int adet) async {
    final b = db.batch();
    for (var i = 0; i < adet; i++) {
      b.insert('sync_queue', {
        'tablo_adi': 'kategoriler',
        'kayit_global_id': 'K-$i',
        'islem_tipi': 'UPSERT',
        'veri_json': jsonEncode({'global_id': 'K-$i', 'ad': 'Kategori $i'}),
        'deneme_sayisi': 0,
        'durum': 'beklemede',
      });
    }
    await b.commit(noResult: true);
  }

  Future<void> birTur(_ZehirliSaglayici s, bool Function() bitti) async {
    await BulutManager().saglayiciAyarla(s);
    for (var i = 0; i < 60 && !bitti(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await BulutManager().zorlaGonder();
    }
  }

  test('tek bozuk satır ayıklanır, sağlam satırlar gider', () async {
    await kuyrugaYaz(200);
    final s = _ZehirliSaglayici({'K-77'});
    await birTur(s, () => s.giden.length >= 199);

    expect(s.giden.length, 199);
    expect(s.giden.contains('K-77'), isFalse);
    final kalan = await db.query('sync_queue');
    expect(kalan.map((r) => r['kayit_global_id']), ['K-77']);
    expect(kalan.single['durum'], 'kalici_hata');
    expect(s.istekSayisi, lessThan(40), reason: 'bölme ~2·log2(n) istek');
  });

  test('grubun tamamı bozuksa bir turdaki istek sayısı bütçeyle sınırlı', () async {
    await kuyrugaYaz(200);
    final s = _ZehirliSaglayici({for (var i = 0; i < 200; i++) 'K-$i'});
    await BulutManager().saglayiciAyarla(s);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(s.istekSayisi, lessThanOrEqualTo(40),
        reason: 'önceden 200 satırda ~399 istek atılıyordu');
    final kalici = await db.query('sync_queue', where: "durum = 'kalici_hata'");
    final bekleyen = await db.query('sync_queue', where: "durum = 'beklemede'");
    expect(kalici.length + bekleyen.length, 200, reason: 'hiçbir satır kaybolmaz');
    expect(bekleyen, isNotEmpty,
        reason: 'denenemeyenler bozuk sayılmaz, sonraki turda denenir');
  });

  test('boş tur "son başarılı gönderim" zamanını değiştirmez', () async {
    final s = _ZehirliSaglayici({});
    await BulutManager().saglayiciAyarla(s);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // İstatistik tekil nesnede yaşar (önceki testlerden değer kalabilir):
    // boş turdan önce ve sonra AYNI olmalı.
    final once = BulutManager().istatistik.value.sonGonderim;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await BulutManager().zorlaGonder();
    expect(BulutManager().istatistik.value.sonGonderim, once,
        reason: 'hiçbir şey gönderilmedi');
  });
}
