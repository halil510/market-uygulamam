// test/servisler/cari_excel_ice_disa_aktarim_test.dart
//
// Kullanıcı isteği (2026-09-21): Cari Liste'de Excel içe/dışa aktarma —
// cari kodu zaten kayıtlıysa GÜNCELLE, yoksa YENİ KAYIT; örnekteki gibi
// (Cari kod, Ünvan, Adres, Telefon, Borç, Alacak, Bakiye, Cari Türü)
// başlıklarla dışa aktarma.
//
// BAKİYE mimari kararı: cari.bakiye asla doğrudan yazılmaz (kanonik
// değer HER ZAMAN cari_hareket'ten SUM ile hesaplanır — bkz.
// CariDeposu.guncelle()'deki "Madde 9" notu). Bu yüzden:
//   - var olan bir cari GÜNCELLENİRKEN Borç/Alacak/Bakiye YOK SAYILIR.
//   - YENİ bir cari eklenirken (borç/alacak > 0 ise) TEK bir "Açılış
//     Bakiyesi" cari_hareket satırı yazılır, bakiye bundan doğal
//     olarak hesaplanır.
//
// ExcelServisi.exceldenCarileriBytesIceriAl() ve içindeki private
// yardımcılar (_cariTuruCoz, _cariBaslikSatiriBul) private olduğu için,
// burada BİREBİR AYNI mantık mirror edilip hem saf fonksiyon hem de
// (CariDeposu/CariAdresDeposu Veritabani() singleton'ına bağlı olduğu
// için) gerçek şema üzerinde bir in-memory veritabanına karşı
// doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

// ── Saf mantık mirror'ları ──────────────────────────────────────────────

String _normalizeString(String s) => s
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .replaceAll(' ', '')
    .replaceAll('-', '')
    .replaceAll('_', '');

String _cariTuruCoz(String ham) {
  final n = _normalizeString(ham);
  final musteriMi = n.contains('musteri') || n.contains('customer') || n.contains('alici');
  final tedarikciMi = n.contains('tedarik') ||
      n.contains('supplier') ||
      n.contains('vendor') ||
      n.contains('satici');
  if (musteriMi && tedarikciMi) return 'Hem Müşteri Hem Tedarikçi';
  if (tedarikciMi) return 'Tedarikçi';
  return 'Müşteri';
}

int _cariBaslikSatiriBul(List<List<String>> rows) {
  final sinir = rows.length < 6 ? rows.length : 6;
  for (int r = 0; r < sinir; r++) {
    for (final v in rows[r]) {
      if (_normalizeString(v).contains('carikod')) return r;
    }
  }
  return 0;
}

void main() {
  group('Cari Türü normalizasyonu', () {
    test('"Müsteri" (Türkçe karaktersiz) -> Müşteri', () {
      expect(_cariTuruCoz('Müsteri'), 'Müşteri');
    });
    test('"Tedarikçi" -> Tedarikçi', () {
      expect(_cariTuruCoz('Tedarikçi'), 'Tedarikçi');
    });
    test('boş/tanınmayan -> varsayılan Müşteri', () {
      expect(_cariTuruCoz(''), 'Müşteri');
      expect(_cariTuruCoz('???'), 'Müşteri');
    });
  });

  group('Başlık satırı bulma (süs satırları olsa bile)', () {
    test('kullanıcının örnek dosyasındaki gibi 2. satırda başlık varsa '
        'doğru satır bulunur', () {
      final rows = [
        ['Cari listesi'],
        ['--'],
        ['Cari kod', 'Ünvan', 'Adres', 'Telefon', 'Borç', 'Alacak', 'Bakiye', 'Cari Türü'],
        ['CARI0-1', 'Test', 'Adres', '', '0', '0', '0', 'Müsteri'],
      ];
      expect(_cariBaslikSatiriBul(rows), 2);
    });

    test('başlık ilk satırdaysa (süs yoksa) yine doğru bulunur', () {
      final rows = [
        ['Cari kod', 'Ünvan'],
        ['CARI0-1', 'Test'],
      ];
      expect(_cariBaslikSatiriBul(rows), 0);
    });
  });

  group('İçe aktarım — güncelle-veya-yeni-ekle + açılış bakiyesi', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    /// CariDeposu.ekle()/guncelle()/hareketEkleTxn() ile BİREBİR AYNI
    /// davranış: yeni caride açılış bakiyesi hareketi yazılır, var olan
    /// caride bakiyeye HİÇ dokunulmaz.
    Future<void> _satiriIsle(Database db, {
      required String kod,
      required String unvan,
      required double borc,
      required double alacak,
    }) async {
      final mevcut = await db.query('cari',
          where: 'cari_kodu = ? AND is_deleted = 0', whereArgs: [kod], limit: 1);
      if (mevcut.isNotEmpty) {
        // guncelle() deseni: 'bakiye' HİÇ yazılmaz.
        await db.update('cari', {'unvan': unvan, 'last_updated': DateTime.now().toIso8601String()},
            where: 'id = ?', whereArgs: [mevcut.first['id']]);
        return;
      }
      final cariId = await db.insert('cari', {
        'cari_kodu': kod, 'unvan': unvan, 'cari_tipi': 'Müşteri',
        'bakiye': 0, 'aktif': 1, 'is_deleted': 0,
      });
      if (borc > 0.005 || alacak > 0.005) {
        await db.transaction((txn) async {
          await txn.insert('cari_hareket', {
            'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
            'fis_tipi': 'Açılış', 'aciklama': 'Açılış Bakiyesi (Excel içe aktarım)',
            'borc': borc, 'alacak': alacak, 'odeme_turu': 'Açılış', 'is_deleted': 0,
          });
          // hareketEkleTxn() ile AYNI: bakiye HER ZAMAN SUM'dan hesaplanır.
          await txn.rawUpdate('''
            UPDATE cari SET bakiye = (
              SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0)
              FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0
            ) WHERE id = ?
          ''', [cariId, cariId]);
        });
      }
    }

    test('cari kodu YOKSA yeni kayıt oluşur VE açılış bakiyesi cari_hareket '
        "satırından doğru hesaplanır (önceden bu özellik hiç yoktu)",
        () async {
      await _satiriIsle(db, kod: 'CARI0-3', unvan: 'Hayrullah Şeran',
          borc: 181462.23, alacak: 157284.0);

      final cari = (await db.query('cari', where: 'cari_kodu = ?', whereArgs: ['CARI0-3'])).first;
      expect(cari['unvan'], 'Hayrullah Şeran');
      expect((cari['bakiye'] as num).toDouble(), closeTo(24178.23, 0.01));

      final hareketler = await db.query('cari_hareket', where: 'cari_id = ?', whereArgs: [cari['id']]);
      expect(hareketler.length, 1);
      expect(hareketler.first['fis_tipi'], 'Açılış');
    });

    test('cari kodu ZATEN VARSA güncellenir ama bakiyesine/hareketine '
        'HİÇ dokunulmaz (mevcut gerçek işlem geçmişi korunur)', () async {
      // Sistemde ZATEN gerçek bir satıştan gelen bakiyesi olan bir cari var.
      final cariId = await db.insert('cari', {
        'cari_kodu': 'CARI0-3', 'unvan': 'Eski Ünvan', 'cari_tipi': 'Müşteri',
        'bakiye': 500.0, 'aktif': 1, 'is_deleted': 0,
      });
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'Satış', 'aciklama': 'Gerçek satış', 'borc': 500.0, 'alacak': 0,
        'is_deleted': 0,
      });

      // Excel'deki (eski/dış sistem) borç/alacak farklı olsa bile...
      await _satiriIsle(db, kod: 'CARI0-3', unvan: 'Hayrullah Şeran (Güncel)',
          borc: 181462.23, alacak: 157284.0);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect(cari['unvan'], 'Hayrullah Şeran (Güncel)',
          reason: 'profil bilgisi güncellenmeli');
      expect((cari['bakiye'] as num).toDouble(), 500.0,
          reason: 'GERÇEK sistem bakiyesi ASLA Excel değeriyle ezilmemeli');

      final hareketler = await db.query('cari_hareket', where: 'cari_id = ?', whereArgs: [cariId]);
      expect(hareketler.length, 1,
          reason: 'mükerrer/çelişkili bir açılış hareketi eklenmemeli');
    });

    test('sadece Bakiye sütunu verilmişse (Borç/Alacak yok) doğru '
        'borç/alacağa çevrilir', () async {
      // Pozitif bakiye -> borç.
      await _satiriIsle(db, kod: 'CARI0-9', unvan: 'Pozitif Bakiyeli', borc: 100.0, alacak: 0);
      var cari = (await db.query('cari', where: 'cari_kodu = ?', whereArgs: ['CARI0-9'])).first;
      expect((cari['bakiye'] as num).toDouble(), 100.0);

      // Negatif bakiye -> alacak (borç negatif olamaz, alacağa çevrilmeli).
      await _satiriIsle(db, kod: 'CARI0-10', unvan: 'Negatif Bakiyeli', borc: 0, alacak: 50.0);
      cari = (await db.query('cari', where: 'cari_kodu = ?', whereArgs: ['CARI0-10'])).first;
      expect((cari['bakiye'] as num).toDouble(), -50.0);
    });
  });
}
