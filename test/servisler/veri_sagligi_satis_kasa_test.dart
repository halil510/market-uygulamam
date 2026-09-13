// test/servisler/veri_sagligi_satis_kasa_test.dart
//
// FAZ 2/3/4 küçük boşluk: veri_sagligi_servisi.dart'taki "Satış-Kasa
// Tutarlılığı" kontrolü ÖNCEDEN sadece odeme_yontemi='Nakit' satışları
// kontrol ediyordu — Kredi Kartı ve Karma ödemeli satışlar (her ikisi de
// gerçek kasa hareketi ÜRETMESİ gereken satışlar, bkz. FAZ 1 madde 2)
// bu kontrolün tamamen dışındaydı. Bu test, düzeltilen SQL'i (Cari hariç
// TÜM ödeme yöntemleri) gerçek şema üzerinde doğrular.
// VeriSagligiServisi Veritabani() singleton'ı üzerinden çalıştığı için
// (diğer depo testlerinde olduğu gibi) burada servis sınıfı değil, aynı
// SQL doğrudan test db'sine karşı çalıştırılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<int> _satisEksikSayisi(Database db) async {
  final rows = await db.rawQuery('''
    SELECT COUNT(*) as n FROM satislar s
    WHERE s.is_deleted = 0 AND s.odeme_yontemi != 'Cari' AND s.odenen_tutar > 0.005
      AND NOT EXISTS (
        SELECT 1 FROM kasa_hareketleri k
        WHERE k.referans_id = s.id AND k.referans_turu = 'satis' AND k.deleted_at IS NULL
      )
  ''');
  return (rows.first['n'] as int?) ?? 0;
}

int _fisSayaci = 0;

Future<int> _satisEkle(Database db, {required String odemeYontemi, required double tutar}) {
  return db.insert('satislar', {
    'fis_no': 'F-${_fisSayaci++}',
    'genel_toplam': tutar,
    'odenen_tutar': tutar,
    'odeme_yontemi': odemeYontemi,
    'is_deleted': 0,
  });
}

Future<void> _kasaHareketiEkle(Database db, {required int satisId}) {
  return db.insert('kasa_hareketleri', {
    'hareket_tipi': 'Satış',
    'tutar': 10,
    'referans_id': satisId,
    'referans_turu': 'satis',
  });
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Satış-Kasa Tutarlılığı (FAZ 2-4 boşluk kapatma)', () {
    test('Kredi Kartı satışının kasa hareketi eksikse artık YAKALANIR', () async {
      await _satisEkle(db, odemeYontemi: 'Kredi Kartı', tutar: 100);
      expect(await _satisEksikSayisi(db), equals(1),
          reason: 'Önceki sorgu sadece Nakit\'i kontrol ediyordu, Kredi Kartı hiç görülmüyordu');
    });

    test('Karma satışının kasa hareketi eksikse artık YAKALANIR', () async {
      await _satisEkle(db, odemeYontemi: 'Karma', tutar: 150);
      expect(await _satisEksikSayisi(db), equals(1));
    });

    test('Cari satışın kasa hareketi hiç beklenmez, eksik sayılmaz', () async {
      await _satisEkle(db, odemeYontemi: 'Cari', tutar: 200);
      expect(await _satisEksikSayisi(db), equals(0));
    });

    test('Kasa hareketi mevcutsa (Nakit/Kredi Kartı/Karma) eksik sayılmaz', () async {
      final nakitId = await _satisEkle(db, odemeYontemi: 'Nakit', tutar: 50);
      await _kasaHareketiEkle(db, satisId: nakitId);
      final kartId = await _satisEkle(db, odemeYontemi: 'Kredi Kartı', tutar: 75);
      await _kasaHareketiEkle(db, satisId: kartId);
      final karmaId = await _satisEkle(db, odemeYontemi: 'Karma', tutar: 90);
      await _kasaHareketiEkle(db, satisId: karmaId);

      expect(await _satisEksikSayisi(db), equals(0));
    });
  });
}
