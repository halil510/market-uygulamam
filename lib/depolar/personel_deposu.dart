// lib/depolar/personel_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi:
// personel_liste_ekrani.dart için hiç repository sınıfı yoktu — hem
// üstteki Riverpod provider hem "kaydet" akışı doğrudan Veritabani().db
// üzerinden SQL çalıştırıyordu. Bu dosya o erişimi kapsar — davranış
// BİREBİR korunmuştur, sadece sorumluluk UI katmanından buraya
// taşınmıştır.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../modeller/personel_model.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class PersonelDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<List<PersonelModel>> hepsiGetir() async {
    final db = await _d;
    final rows = await db.query(
      DbSabitler.personel,
      where: 'is_deleted = 0',
      orderBy: 'ad_soyad ASC',
    );
    return rows.map(PersonelModel.fromMap).toList();
  }

  /// [id] null ise yeni personel ekler, doluysa mevcut kaydı günceller.
  Future<PersonelModel> kaydet({
    int? id,
    required String adSoyad,
    String? pozisyon,
    String? telefon,
    String? email,
    required double maas,
    required bool aktif,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final veri = <String, dynamic>{
      'ad_soyad': adSoyad,
      'pozisyon': pozisyon,
      'telefon': telefon,
      'email': email,
      'maas': maas,
      'aktif': aktif ? 1 : 0,
      // Düzenleme modunda 'notlar' alanına DOKUNULMAZ — form bu alanı
      // hiç göstermiyor, sadece yeni kayıtta null ile başlatılır.
      if (id == null) 'notlar': null,
      'last_updated': now,
    };
    int personelId;
    if (id == null) {
      veri['global_id'] = const Uuid().v4();
      personelId = await db.insert(DbSabitler.personel, veri);
    } else {
      personelId = id;
      await db.update(DbSabitler.personel, veri,
          where: 'id = ?', whereArgs: [personelId]);
    }
    final satir = await db.query(DbSabitler.personel,
        where: 'id = ?', whereArgs: [personelId], limit: 1);
    final row = Map<String, dynamic>.from(satir.first);
    BulutManager().upsert(DbSabitler.personel, row);
    return PersonelModel.fromMap(row);
  }
}
