// test/servisler/iade_olustur_cift_iade_fix_test.dart
//
// Kullanıcı kararı (2026-09-22): İade oluştururken cari seçimi (hangi
// müşterinin iade ettiğini kaydetmek için) ile ödeme yöntemi (Nakit/
// Kart) birbirinden TAMAMEN BAĞIMSIZ iki seçimdi. Kasiyer "Nakit" iade
// seçip AYRICA kayıtlı bir müşteri de seçerse, kod HEM kasadan nakit
// veriyor HEM DE müşterinin cari hesabından düşüyordu (borcu varsa
// azalıyor, yoksa "fazla ödedi" durumuna geçiyor) — aynı iade iki kere
// işlenmiş oluyordu. Kullanıcı kararı: cari seçimi SADECE "kim iade
// etti" takibi için — para her zaman nakit/kart yoluyla gerçekten geri
// veriliyor, cari_hareket kaydı artık HER ZAMAN bakiyeyi etkilemeyen
// (borc=alacak) salt-kayıt.
//
// IadeIslemServisi Veritabani() singleton'ına bağımlı olduğundan
// (projenin yerleşik test deseni), bu test topluIadeKaydet()'teki
// BİREBİR aynı cari_hareket yazımını gerçek şema üzerinde doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../helper/test_initializer.dart';

/// IadeIslemServisi.topluIadeKaydet()'teki (düzeltilmiş) cari_hareket
/// yazımının BİREBİR aynısı.
Future<void> _iadeCariYaz(Database db, {
  required int cariId,
  required int iadeId,
  required String fisNo,
  required double toplamIade,
}) async {
  await db.transaction((txn) async {
    await txn.insert('cari_hareket', {
      'global_id': const Uuid().v4(), 'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
      'fis_tipi': 'İade', 'fis_id': iadeId, 'fis_no': fisNo,
      'aciklama': 'Toplu iade: $fisNo — bakiyeyi etkilemez',
      'borc': toplamIade, 'alacak': toplamIade, 'odeme_turu': 'Nakit',
    });
    await txn.rawUpdate(
        'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
        [cariId, cariId]);
  });
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  test('Nakit iade edilip AYRICA bir müşteri seçilirse, müşterinin bakiyesi DEĞİŞMEZ (çift iade önlenir)', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    await db.update('cari', {'bakiye': 0}, where: 'id = ?', whereArgs: [cariId]);

    // Kasadan zaten 60 TL nakit verildi (bu test kasa tarafını kapsamıyor,
    // sadece cari tarafını doğruluyor) — kasiyer AYRICA müşteriyi de seçti.
    await _iadeCariYaz(db, cariId: cariId, iadeId: 1, fisNo: 'IAD1', toplamIade: 60.0);

    final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
    expect((cari['bakiye'] as num).toDouble(), equals(0.0),
        reason: 'Nakit zaten elden verildiği için cari bakiyesi hiç etkilenmemeli');
  });

  test('cari_hareket satırı YİNE de yazılır (takip/audit için), sadece net etkisi sıfırdır', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    await _iadeCariYaz(db, cariId: cariId, iadeId: 2, fisNo: 'IAD2', toplamIade: 45.0);

    final satir = (await db.query('cari_hareket', where: 'fis_id = ?', whereArgs: [2])).first;
    expect((satir['borc'] as num).toDouble(), equals(45.0));
    expect((satir['alacak'] as num).toDouble(), equals(45.0));
  });

  test('mevcut borcu olan bir müşteride bile Nakit+Cari birlikte seçilince borç YANLIŞLIKLA azalmaz', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    // Müşterinin önceden 200 TL veresiye borcu var.
    await db.insert('cari_hareket', {
      'global_id': const Uuid().v4(), 'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
      'fis_tipi': 'Satış', 'borc': 200.0, 'alacak': 0.0, 'odeme_turu': 'Cari',
    });
    await db.update('cari', {'bakiye': 200.0}, where: 'id = ?', whereArgs: [cariId]);

    // Müşteri bir ürünü Nakit olarak iade ediyor (60 TL elden verildi),
    // kasiyer takip için aynı müşteriyi cari olarak da seçiyor.
    await _iadeCariYaz(db, cariId: cariId, iadeId: 3, fisNo: 'IAD3', toplamIade: 60.0);

    final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
    expect((cari['bakiye'] as num).toDouble(), equals(200.0),
        reason: 'Nakit iade ile veresiye borcu birbirinden bağımsız — borç yanlışlıkla 140\'a düşmemeli');
  });
}
