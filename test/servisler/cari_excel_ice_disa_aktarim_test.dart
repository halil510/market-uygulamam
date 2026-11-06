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
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN
// _cariTuruCoz / _cariBaslikSatiriBul / satır işleme mantığının
// KOPYALARINI çağırıyordu — üretim kodu bozulsa bile yeşil kalırdı.
// Yardımcılar private ve gerçek Excel hücresi beklediği için sarmalayıcı
// yerine (üretim koduna HİÇ dokunmadan) testte gerçek bir .xlsx üretilip
// GERÇEK ExcelServisi().exceldenCarileriBytesIceriAl() çağrılıyor; tür
// çözme ve başlık satırı bulma bu gerçek yoldan doğrulanıyor.
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/excel_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

const _baslik = ['Cari kod', 'Ünvan', 'Adres', 'Telefon', 'Borç', 'Alacak', 'Bakiye', 'Cari Türü'];

/// Verilen satırlardan gerçek bir .xlsx (tek sayfa) üretir. Sayı olarak
/// verilen hücreler DoubleCellValue, diğerleri TextCellValue yazılır.
Uint8List _xlsx(List<List<Object>> satirlar) {
  final ex = Excel.createExcel();
  final sh = ex[ex.getDefaultSheet()!];
  for (final s in satirlar) {
    sh.appendRow(s
        .map<CellValue?>((v) => v is num ? DoubleCellValue(v.toDouble()) : TextCellValue(v.toString()))
        .toList());
  }
  return Uint8List.fromList(ex.encode()!);
}

/// GERÇEK içe aktarım — tek veri satırı (başlık + satır).
Future<CariIceAktarSonuc> _satiriIsle({
  required String kod,
  required String unvan,
  required double borc,
  required double alacak,
  String turu = 'Müsteri',
}) =>
    ExcelServisi().exceldenCarileriBytesIceriAl(_xlsx([
      _baslik,
      [kod, unvan, '', '', borc, alacak, borc - alacak, turu],
    ]));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<String?> tip(String kod) async => (await db.query('cari',
          columns: ['cari_tipi'], where: 'cari_kodu = ?', whereArgs: [kod]))
      .first['cari_tipi'] as String?;

  group('Cari Türü normalizasyonu', () {
    test('"Müsteri" (Türkçe karaktersiz) -> Müşteri', () async {
      await _satiriIsle(kod: 'T-1', unvan: 'A', borc: 0, alacak: 0, turu: 'Müsteri');
      expect(await tip('T-1'), 'Müşteri');
    });
    test('"Tedarikçi" -> Tedarikçi', () async {
      await _satiriIsle(kod: 'T-2', unvan: 'B', borc: 0, alacak: 0, turu: 'Tedarikçi');
      expect(await tip('T-2'), 'Tedarikçi');
    });
    test('boş/tanınmayan -> varsayılan Müşteri', () async {
      await _satiriIsle(kod: 'T-3', unvan: 'C', borc: 0, alacak: 0, turu: '');
      await _satiriIsle(kod: 'T-4', unvan: 'D', borc: 0, alacak: 0, turu: '???');
      expect(await tip('T-3'), 'Müşteri');
      expect(await tip('T-4'), 'Müşteri');
    });
  });

  group('Başlık satırı bulma (süs satırları olsa bile)', () {
    test('kullanıcının örnek dosyasındaki gibi 2. satırda başlık varsa '
        'doğru satır bulunur', () async {
      final sonuc = await ExcelServisi().exceldenCarileriBytesIceriAl(_xlsx([
        ['Cari listesi'],
        ['--'],
        _baslik,
        ['CARI0-1', 'Test', 'Adres', '', 0, 0, 0, 'Müsteri'],
      ]));
      // Başlık 2. (0 tabanlı) satırda bulunduysa yalnız altındaki satır
      // veri sayılır: tek ekleme, hata yok.
      expect(sonuc.eklenen, 1);
      expect(sonuc.hatali, 0);
      expect(await tip('CARI0-1'), 'Müşteri');
    });

    test('başlık ilk satırdaysa (süs yoksa) yine doğru bulunur', () async {
      final sonuc = await ExcelServisi().exceldenCarileriBytesIceriAl(_xlsx([
        ['Cari kod', 'Ünvan'],
        ['CARI0-1', 'Test'],
      ]));
      expect(sonuc.eklenen, 1);
      expect(sonuc.hatali, 0);
    });
  });

  group('İçe aktarım — güncelle-veya-yeni-ekle + açılış bakiyesi', () {
    test('cari kodu YOKSA yeni kayıt oluşur VE açılış bakiyesi cari_hareket '
        "satırından doğru hesaplanır (önceden bu özellik hiç yoktu)",
        () async {
      await _satiriIsle(kod: 'CARI0-3', unvan: 'Hayrullah Şeran',
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
      await _satiriIsle(kod: 'CARI0-3', unvan: 'Hayrullah Şeran (Güncel)',
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
      // Pozitif bakiye -> borç (Borç/Alacak sütunları 0, yalnız Bakiye dolu).
      await ExcelServisi().exceldenCarileriBytesIceriAl(_xlsx([
        _baslik,
        ['CARI0-9', 'Pozitif Bakiyeli', '', '', 0, 0, 100, 'Müsteri'],
      ]));
      var cari = (await db.query('cari', where: 'cari_kodu = ?', whereArgs: ['CARI0-9'])).first;
      expect((cari['bakiye'] as num).toDouble(), 100.0);

      // Negatif bakiye -> alacak (borç negatif olamaz, alacağa çevrilmeli).
      await ExcelServisi().exceldenCarileriBytesIceriAl(_xlsx([
        _baslik,
        ['CARI0-10', 'Negatif Bakiyeli', '', '', 0, 0, -50, 'Müsteri'],
      ]));
      cari = (await db.query('cari', where: 'cari_kodu = ?', whereArgs: ['CARI0-10'])).first;
      expect((cari['bakiye'] as num).toDouble(), -50.0);
    });
  });
}
