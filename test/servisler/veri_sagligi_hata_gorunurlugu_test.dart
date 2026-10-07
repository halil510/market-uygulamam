// test/servisler/veri_sagligi_hata_gorunurlugu_test.dart
//
// Derin analiz 2026-10-07 (A3) düzeltmelerinin gerçek servis üzerinden
// doğrulanması:
//  • Çalıştırılamayan bir kontrol artık YEŞİL "uyumlu" görünmez; finansal
//    mutabakatlarda KIRMIZI döner ve diğer kontroller yine raporlanır.
//  • Akış (kontrolleriAkisla) her kontrol için tam bir sonuç verir.
//  • Stok mutabakatı (tek SQL) sayım ile düzeltmede aynı tanımı kullanır.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/depolar/stok_deposu.dart';
import 'package:market_plus/servisler/veri_sagligi_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<void> _stokHareketiEkle(Database db, int urunId,
    {required double onceki, required double sonraki}) {
  return db.insert('stok_hareket', {
    'urun_id': urunId,
    'hareket_turu': 'Giriş',
    'miktar': sonraki - onceki,
    'onceki_stok': onceki,
    'sonraki_stok': sonraki,
    'tarih': DateTime.now().toIso8601String(),
  });
}

void main() {
  late Database db;

  setUp(() async {
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() => db.close());

  test('akış her kontrol için tekil bir sonuç verir', () async {
    final servis = VeriSagligiServisi();
    final sonuclar = await servis.kontrolleriAkisla().toList();
    expect(sonuclar, hasLength(servis.kontrolSayisi));
    expect(sonuclar.map((s) => s.id).toSet(), hasLength(servis.kontrolSayisi));
  });

  test('sorgusu hata veren mutabakat YEŞİL değil KIRMIZI "Kontrol edilemedi" döner, '
      'diğer kontroller yine raporlanır', () async {
    await db.execute('DROP TABLE kredi_karti_hareket');

    final servis = VeriSagligiServisi();
    final sonuclar = await servis.tumKontrolleriCalistir();

    expect(sonuclar, hasLength(servis.kontrolSayisi),
        reason: 'tek kontrolün hatası tüm listeyi düşürmemeli');
    final kart = sonuclar.firstWhere((s) => s.id == 'kredi_karti_mutabakat');
    expect(kart.durum, SaglikDurum.kirmizi);
    expect(kart.calistirilamadi, isTrue);
    expect(kart.mesaj, startsWith('Kontrol edilemedi'));
    expect(sonuclar.firstWhere((s) => s.id == 'negatif_stok').calistirilamadi, isFalse);
  });

  test('stok mutabakatı: tek sorguluk sayım ve transaction içi düzeltme aynı sonucu verir',
      () async {
    final depo = StokDeposu();
    // Hareketlere göre 7 olması gereken ürün, 10 olarak kayıtlı.
    final kayan = await TestVeritabani.ornekUrunEkle(db, barkod: 'KAYAN', stok: 10);
    await _stokHareketiEkle(db, kayan, onceki: 0, sonraki: 7);
    // Hareketleriyle uyumlu ürün.
    final uyumlu = await TestVeritabani.ornekUrunEkle(db, barkod: 'UYUMLU', stok: 4);
    await _stokHareketiEkle(db, uyumlu, onceki: 0, sonraki: 4);
    // Hareket toplamı negatif → doğru stok NEGATİF (B2 kararı: 0'a kırpılmaz).
    final eksi = await TestVeritabani.ornekUrunEkle(db, barkod: 'EKSI', stok: 0);
    await _stokHareketiEkle(db, eksi, onceki: 2, sonraki: 0);
    await _stokHareketiEkle(db, eksi, onceki: 0, sonraki: -1);

    expect(await depo.mutabakatUyumsuzlukSayisi(), 2);
    expect(await depo.stokMutabakatYap(), 2);

    final rows = await db.query('urunler', columns: ['id', 'stok']);
    final stoklar = {for (final r in rows) r['id']: (r['stok'] as num).toDouble()};
    expect(stoklar[kayan], 7);
    expect(stoklar[uyumlu], 4);
    expect(stoklar[eksi], -3);
    expect(await depo.mutabakatUyumsuzlukSayisi(), 0);
  });

  test('stok sayacı hata verince 0 değil hata iletir', () async {
    await db.execute('DROP TABLE stok_hareket');
    expect(StokDeposu().mutabakatUyumsuzlukSayisi(), throwsA(isA<DatabaseException>()));
  });
}
