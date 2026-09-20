// test/veri/vardiya_karma_odeme_kirilimi_test.dart
//
// Karma/çoklu ödeme denetimi, 2026-09-20 — kullanıcı bulgusu: "gün sonu
// çoklu ödeme doğru olmamış, satış raporu gibi çoklu ödeme düzgün olsun".
//
// VardiyaDeposu.satisOzetiGetir()/pdfSatisOzetiGetir() (Vardiya/Gün Sonu
// ekranının Nakit/Kredi K./Cari KPI'larının kaynağı) ÖNCEDEN nakit/kart/
// cari toplamlarını satislar.odeme_yontemi TEK ALAN string'iyle
// eşleştiriyordu — Karma ödemeli bir satışın odeme_yontemi'si 'Karma'
// olduğundan bu üç CASE'in hiçbirine eşleşmiyor, o satışın gerçek nakit/
// kart/cari payları kırılımdan TAMAMEN KAYBOLUYORDU. Düzeltme: nakit/kart
// artık kasa_hareketleri'nden (her ödeme yöntemi için ZATEN ayrı satır —
// bkz. SatisTamamlamaServisi), cari ise cari_hareket'ten (self-cancelling
// bilgi satırı HARİÇ, SADECE gerçek borç satırı) hesaplanıyor.
//
// VardiyaDeposu, Veritabani() singleton'ı üzerinden çalıştığı için (diğer
// depo testlerinde olduğu gibi — bkz. vardiya_nakit_mutabakat_test.dart)
// burada AYNI SQL gerçek şema üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

/// VardiyaDeposu.satisOzetiGetir() ile BİREBİR aynı SQL.
Future<Map<String, double>> _satisOzetiKirilimi(
    Database db, String baslangicTarihi) async {
  final kasaRows = await db.rawQuery('''
    SELECT kh.odeme_yontemi, COALESCE(SUM(kh.tutar),0) as tutar
    FROM kasa_hareketleri kh
    JOIN satislar s ON s.id = kh.referans_id AND kh.referans_turu = 'satis'
    WHERE datetime(s.tarih) >= datetime(?) AND s.iptal=0 AND s.is_deleted=0
      AND kh.deleted_at IS NULL
    GROUP BY kh.odeme_yontemi
  ''', [baslangicTarihi]);
  double nakit = 0, kart = 0, digerKasa = 0;
  for (final r in kasaRows) {
    final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
    switch (r['odeme_yontemi'] as String?) {
      case 'Nakit':       nakit += tutar; break;
      case 'Kredi Kartı': kart  += tutar; break;
      default:            digerKasa += tutar; break;
    }
  }

  final cariRows = await db.rawQuery('''
    SELECT COALESCE(SUM(ch.borc),0) as tutar
    FROM cari_hareket ch
    JOIN satislar s ON s.id = ch.fis_id
    WHERE ch.fis_tipi = 'Satış' AND ch.alacak = 0 AND ch.borc > 0 AND ch.is_deleted = 0
      AND datetime(s.tarih) >= datetime(?) AND s.iptal=0 AND s.is_deleted=0
  ''', [baslangicTarihi]);
  final cari = (cariRows.first['tutar'] as num?)?.toDouble() ?? 0;

  return {'nakit': nakit, 'kart': kart, 'cari': cari, 'diger': digerKasa};
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('VardiyaDeposu.satisOzetiGetir — Karma ödeme kırılımı', () {
    test('Karma satış (60 Nakit + 40 Cari) nakit ve cari paylarına DOĞRU dağıtılır — önceden ikisi de 0 dönüyordu', () async {
      final acilis = DateTime(2026, 9, 20, 9, 0);
      final satisId = await db.insert('satislar', {
        'fis_no': 'F-KARMA-1', 'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
        'genel_toplam': 100, 'odenen_tutar': 100, 'odeme_yontemi': 'Karma',
        'iptal': 0, 'is_deleted': 0, 'cari_id': 1,
      });
      // SatisTamamlamaServisi'nin karma ödemede yaptığı gibi: Nakit payı
      // için ayrı bir kasa_hareketleri satırı...
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 60, 'odeme_yontemi': 'Nakit',
        'referans_id': satisId, 'referans_turu': 'satis',
        'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
      });
      // ...ve Cari payı için hem gerçek borç satırı (alacak=0)...
      await db.insert('cari_hareket', {
        'cari_id': 1, 'fis_id': satisId, 'fis_tipi': 'Satış',
        'borc': 40, 'alacak': 0, 'is_deleted': 0,
        'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
      });

      final k = await _satisOzetiKirilimi(db, acilis.toIso8601String());

      expect(k['nakit'], 60.0, reason: 'ÖNCEDEN 0 dönüyordu (odeme_yontemi==Karma, Nakit CASE\'ine eşleşmiyordu)');
      expect(k['cari'], 40.0, reason: 'ÖNCEDEN 0 dönüyordu (odeme_yontemi==Karma, Cari CASE\'ine eşleşmiyordu)');
      expect(k['kart'], 0.0);
    });

    test('Karma satış (self-cancelling cari bilgi satırı) çift sayılmaz', () async {
      final acilis = DateTime(2026, 9, 20, 9, 0);
      final satisId = await db.insert('satislar', {
        'fis_no': 'F-KARMA-2', 'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
        'genel_toplam': 100, 'odenen_tutar': 100, 'odeme_yontemi': 'Karma',
        'iptal': 0, 'is_deleted': 0, 'cari_id': 1,
      });
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'odeme_yontemi': 'Nakit',
        'referans_id': satisId, 'referans_turu': 'satis',
        'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
      });
      // SatisTamamlamaServisi'nin Nakit/Kart payı için AYRICA yazdığı,
      // bakiyeyi etkilemeyen (borc==alacak) bilgi amaçlı cari_hareket
      // satırı — bu, cari kırılımına DAHİL EDİLMEMELİ (borc>0 AND
      // alacak=0 filtresi bunu dışarıda bırakıyor).
      await db.insert('cari_hareket', {
        'cari_id': 1, 'fis_id': satisId, 'fis_tipi': 'Satış',
        'borc': 100, 'alacak': 100, 'is_deleted': 0,
        'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
      });

      final k = await _satisOzetiKirilimi(db, acilis.toIso8601String());

      expect(k['nakit'], 100.0);
      expect(k['cari'], 0.0, reason: 'self-cancelling bilgi satırı (borc==alacak) cari kırılımına dahil edilmemeli');
    });

    test('saf Nakit ve saf Kredi Kartı satışlar öncekiyle AYNI şekilde doğru çalışmaya devam eder', () async {
      final acilis = DateTime(2026, 9, 20, 9, 0);
      final s1 = await db.insert('satislar', {
        'fis_no': 'F-N', 'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
        'genel_toplam': 50, 'odenen_tutar': 50, 'odeme_yontemi': 'Nakit',
        'iptal': 0, 'is_deleted': 0,
      });
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 50, 'odeme_yontemi': 'Nakit',
        'referans_id': s1, 'referans_turu': 'satis',
        'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
      });
      final s2 = await db.insert('satislar', {
        'fis_no': 'F-K', 'tarih': acilis.add(const Duration(hours: 2)).toIso8601String(),
        'genel_toplam': 75, 'odenen_tutar': 75, 'odeme_yontemi': 'Kredi Kartı',
        'iptal': 0, 'is_deleted': 0,
      });
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 75, 'odeme_yontemi': 'Kredi Kartı',
        'referans_id': s2, 'referans_turu': 'satis',
        'tarih': acilis.add(const Duration(hours: 2)).toIso8601String(),
      });

      final k = await _satisOzetiKirilimi(db, acilis.toIso8601String());

      expect(k['nakit'], 50.0);
      expect(k['kart'], 75.0);
      expect(k['cari'], 0.0);
    });

    test('iptal edilmiş satışın kasa/cari hareketi kırılıma dahil edilmez', () async {
      final acilis = DateTime(2026, 9, 20, 9, 0);
      final satisId = await db.insert('satislar', {
        'fis_no': 'F-IPTAL', 'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
        'genel_toplam': 100, 'odenen_tutar': 100, 'odeme_yontemi': 'Nakit',
        'iptal': 1, 'is_deleted': 0,
      });
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'odeme_yontemi': 'Nakit',
        'referans_id': satisId, 'referans_turu': 'satis',
        'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
      });

      final k = await _satisOzetiKirilimi(db, acilis.toIso8601String());

      expect(k['nakit'], 0.0);
    });

    test('vardiya açılışından ÖNCEKİ satışlar kırılıma dahil edilmez', () async {
      final acilis = DateTime(2026, 9, 20, 9, 0);
      final satisId = await db.insert('satislar', {
        'fis_no': 'F-ONCE', 'tarih': acilis.subtract(const Duration(hours: 1)).toIso8601String(),
        'genel_toplam': 100, 'odenen_tutar': 100, 'odeme_yontemi': 'Nakit',
        'iptal': 0, 'is_deleted': 0,
      });
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'odeme_yontemi': 'Nakit',
        'referans_id': satisId, 'referans_turu': 'satis',
        'tarih': acilis.subtract(const Duration(hours: 1)).toIso8601String(),
      });

      final k = await _satisOzetiKirilimi(db, acilis.toIso8601String());

      expect(k['nakit'], 0.0);
    });
  });
}
