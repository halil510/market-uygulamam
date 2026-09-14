// test/depolar/kasa_deposu_sube_test.dart
//
// KOMPLE UYGULAMA DERİN ANALİZİNDE bulunan, kanıtlanmış hata: KasaDeposu
// içindeki '_sonBakiyeTxn' (her yeni kasa hareketinin bakiye_sonrasi
// zincirinin TEMELİ), 'guncelBakiyeNakit' (Vardiya'nın "Anlık Kasa Bak."
// alanı) ve 'nakitDegisimi' (Vardiya kapanış mutabakatının "Beklenen
// Kasa" alanı) ÖNCEDEN hiç sube_id filtresi içermiyordu — aynı dosyadaki
// 'hareketleriniGetir()' ZATEN bu filtreyi uyguluyordu, tutarsızlık
// buradan tespit edildi. Çok şubeli kurulumda Şube B'deki bir kasa
// hareketi, Şube A'nın bakiye zincirinin/nakit toplamının üzerine
// (yanlış tabana göre) hesaplanıyordu.
//
// KasaDeposu, Veritabani() singleton'ı üzerinden çalıştığı için (bkz.
// veri_sagligi_mutabakat_test.dart'taki aynı desen), üretim koduyla
// BİREBİR aynı (düzeltilmiş) SQL burada TestVeritabani'nin gerçek
// şemasına karşı doğrudan çalıştırılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

// KasaDeposu._sonBakiyeTxn ile BİREBİR aynı (düzeltilmiş) SQL.
Future<double> _sonBakiye(Database db, int? subeId) async {
  final rows = subeId != null
      ? await db.rawQuery(
          'SELECT bakiye_sonrasi FROM kasa_hareketleri WHERE deleted_at IS NULL AND sube_id = ? ORDER BY tarih DESC, id DESC LIMIT 1',
          [subeId])
      : await db.rawQuery(
          'SELECT bakiye_sonrasi FROM kasa_hareketleri WHERE deleted_at IS NULL ORDER BY tarih DESC, id DESC LIMIT 1');
  if (rows.isEmpty) return 0;
  return (rows.first['bakiye_sonrasi'] as num?)?.toDouble() ?? 0;
}

Future<void> _kasaHareketEkle(Database db,
    {required int subeId,
    required String tip,
    required double tutar,
    required double bakiyeSonrasi,
    String tarih = '2026-01-01T10:00:00'}) async {
  await db.insert('kasa_hareketleri', {
    'sube_id': subeId,
    'hareket_tipi': tip,
    'tutar': tutar,
    'bakiye_sonrasi': bakiyeSonrasi,
    'tarih': tarih,
    'odeme_yontemi': 'Nakit',
  });
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('KasaDeposu._sonBakiyeTxn — şube izolasyonu', () {
    test('aktif şube seçiliyse SADECE o şubenin son bakiyesi döner', () async {
      // Şube 1: 100 -> 150 (Satış). Şube 2: 500 -> 460 (Ödeme). Şube 1'in
      // hareketi ZAMAN OLARAK sonra eklenir ki "en son satır" yanlışlıkla
      // Şube 2'ninkiymiş gibi seçilirse test bunu yakalasın.
      await _kasaHareketEkle(db,
          subeId: 2, tip: 'Ödeme', tutar: 40, bakiyeSonrasi: 460,
          tarih: '2026-01-01T09:00:00');
      await _kasaHareketEkle(db,
          subeId: 1, tip: 'Satış', tutar: 50, bakiyeSonrasi: 150,
          tarih: '2026-01-01T08:00:00');

      expect(await _sonBakiye(db, 1), equals(150.0));
      expect(await _sonBakiye(db, 2), equals(460.0));
    });

    test('"Tüm Şubeler" (subeId=null) modunda eskisi gibi TÜM şubeler '
        'arasında en son hareket döner', () async {
      await _kasaHareketEkle(db,
          subeId: 1, tip: 'Satış', tutar: 50, bakiyeSonrasi: 150,
          tarih: '2026-01-01T08:00:00');
      await _kasaHareketEkle(db,
          subeId: 2, tip: 'Ödeme', tutar: 40, bakiyeSonrasi: 460,
          tarih: '2026-01-01T09:00:00');

      expect(await _sonBakiye(db, null), equals(460.0));
    });
  });
}
