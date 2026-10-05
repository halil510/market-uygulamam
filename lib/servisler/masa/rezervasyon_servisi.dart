// lib/servisler/masa/rezervasyon_servisi.dart
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../modeller/rezervasyon_model.dart';
import '../../cekirdek/sabitler/db_sabitleri.dart';
import '../../depolar/masa_deposu.dart';

class RezervasyonServisi {
  static final RezervasyonServisi _instance = RezervasyonServisi._();
  factory RezervasyonServisi() => _instance;
  RezervasyonServisi._();

  Future<Database> get _db async => Veritabani().db;

  /// Rezervasyon ekle
  // 🔴 Derin analizde bulundu: çakışma kontrolü (SELECT COUNT) ile
  // ekleme (INSERT) iki ayrı, transaction'sız çağrıydı — iki farklı
  // terminalden aynı masa/saat için neredeyse eş zamanlı rezervasyon
  // yapılırsa, ikisi de birbirinin henüz eklemediği kaydı görmeden
  // kontrolü geçip iki çift rezervasyon oluşturabilirdi. Artık kontrol
  // ve ekleme TEK transaction içinde (sqflite yazarları serileştirir,
  // yarış penceresini kapatır).
  Future<int> ekle(RezervasyonModel rezervasyon) async {
    final db = await _db;
    late final int id;
    await db.transaction((txn) async {
      if (await _cakisiyorMu(txn, rezervasyon.masaId, rezervasyon.saat)) {
        throw Exception('Bu saat için masa dolu');
      }

      // 🔴🔴 Derin analizde bulundu: 'masa_rezervasyon' senkron
      // sisteminde kayıtlı olduğu halde global_id atanmıyordu ve
      // BulutManager hiç çağrılmıyordu — restoran rezervasyonları
      // birden fazla terminal arasında hiç senkronize olmuyordu.
      final veri = rezervasyon.toMap();
      veri['global_id'] ??= const Uuid().v4();
      veri['last_updated'] = DateTime.now().toIso8601String();
      id = await txn.insert(DbSabitler.masaRezervasyon, veri);
    });
    final satir = await db.query(DbSabitler.masaRezervasyon, where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert(DbSabitler.masaRezervasyon, Map<String, dynamic>.from(satir.first));
    return id;
  }

  /// Rezervasyon güncelle
  Future<void> guncelle(RezervasyonModel rezervasyon) async {
    final db = await _db;
    // Saat/masa değiştirilerek başka bir rezervasyonla çakışılmasın
    // (önceden güncellemede hiç kontrol yoktu). Kendisi sayılmaz; iptal/
    // tamamlanmış bir rezervasyonun yeniden düzenlenmesi engellenmez.
    final aktifMi = rezervasyon.durum != RezervasyonDurum.iptal &&
        rezervasyon.durum != RezervasyonDurum.tamamlandi;
    if (aktifMi &&
        await _cakisiyorMu(db, rezervasyon.masaId, rezervasyon.saat,
            haricId: rezervasyon.id)) {
      throw Exception('Bu saat için masa dolu');
    }
    final veri = rezervasyon.toMap();
    veri['last_updated'] = DateTime.now().toIso8601String();
    await db.update(
      DbSabitler.masaRezervasyon,
      veri,
      where: 'id = ?',
      whereArgs: [rezervasyon.id],
    );
    final satir = await db.query(DbSabitler.masaRezervasyon, where: 'id = ?', whereArgs: [rezervasyon.id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert(DbSabitler.masaRezervasyon, Map<String, dynamic>.from(satir.first));
  }

  /// Rezervasyon sil
  Future<void> sil(int id) async {
    // 🔴 DÜZELTME: Gerçek HARD DELETE yapılıyordu — senkron
    // sisteminde olan bir kayıt için bu, silmenin buluta hiç
    // bildirilememesine ve bulut→yerel çekişte "dirilmesine" yol
    // açardı. Artık soft-delete (is_deleted=1) yapılıyor.
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.update(DbSabitler.masaRezervasyon,
        {'is_deleted': 1, 'last_updated': now},
        where: 'id = ?', whereArgs: [id]);
    final satir = await db.query(DbSabitler.masaRezervasyon, where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert(DbSabitler.masaRezervasyon, Map<String, dynamic>.from(satir.first));
  }

  /// Durum güncelle
  Future<void> durumGuncelle(int id, RezervasyonDurum durum) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.update(
      DbSabitler.masaRezervasyon,
      {'durum': durum.name, 'last_updated': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    final satir = await db.query(DbSabitler.masaRezervasyon, where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert(DbSabitler.masaRezervasyon, Map<String, dynamic>.from(satir.first));
    
    if (durum == RezervasyonDurum.geldi) {
      final rez = await idileGetir(id);
      if (rez != null) {
        await db.update(
          DbSabitler.masalar,
          {'durum': 'dolu', 'last_updated': now},
          where: 'id = ?',
          whereArgs: [rez.masaId],
        );
        final masaSatir = await db.query(DbSabitler.masalar, where: 'id = ?', whereArgs: [rez.masaId], limit: 1);
        if (masaSatir.isNotEmpty) BulutManager().upsert(DbSabitler.masalar, Map<String, dynamic>.from(masaSatir.first));
      }
    }
  }

  /// Masanın "rezerve" görünmesine yol açan (yaklaşan / yeni başlamış,
  /// beklemede-onaylı) rezervasyonlarını iptal eder; iptal edilen sayıyı döner.
  Future<int> masaYaklasanRezervasyonlariIptalEt(int masaId) async {
    final db = await _db;
    final simdi = DateTime.now();
    final rows = await db.query(DbSabitler.masaRezervasyon,
        columns: ['id', 'saat'],
        where: "masa_id = ? AND is_deleted = 0 AND durum IN ('beklemede', 'onaylandi')",
        whereArgs: [masaId]);
    var adet = 0;
    for (final r in rows) {
      final saat = DateTime.tryParse(r['saat']?.toString() ?? '');
      if (saat == null) continue;
      if (saat.isAfter(simdi.add(MasaDeposu.rezervasyonOncesi)) ||
          saat.isBefore(simdi.subtract(MasaDeposu.rezervasyonGecikme))) {
        continue;
      }
      await durumGuncelle(r['id'] as int, RezervasyonDurum.iptal);
      adet++;
    }
    return adet;
  }

  /// ID ile getir
  Future<RezervasyonModel?> idileGetir(int id) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT r.*, m.ad as masa_adi 
      FROM ${DbSabitler.masaRezervasyon} r
      LEFT JOIN ${DbSabitler.masalar} m ON r.masa_id = m.id
      WHERE r.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return RezervasyonModel.fromMap(rows.first);
  }

  /// Tarihe göre rezervasyonlar
  Future<List<RezervasyonModel>> tariheGoreGetir(DateTime tarih) async {
    final db = await _db;
    final bas = DateTime(tarih.year, tarih.month, tarih.day);
    final bit = DateTime(tarih.year, tarih.month, tarih.day, 23, 59, 59);
    final rows = await db.rawQuery('''
      SELECT r.*, m.ad as masa_adi 
      FROM ${DbSabitler.masaRezervasyon} r
      LEFT JOIN ${DbSabitler.masalar} m ON r.masa_id = m.id
      WHERE r.tarih BETWEEN ? AND ? AND r.is_deleted = 0
      ORDER BY r.saat ASC
    ''', [bas.toIso8601String(), bit.toIso8601String()]);
    return rows.map(RezervasyonModel.fromMap).toList();
  }

  /// Bugünkü rezervasyonlar
  Future<List<RezervasyonModel>> bugunkuRezervasyonlar() async {
    return tariheGoreGetir(DateTime.now());
  }

  /// Bekleyen rezervasyonlar
  Future<List<RezervasyonModel>> bekleyenler() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT r.*, m.ad as masa_adi 
      FROM ${DbSabitler.masaRezervasyon} r
      LEFT JOIN ${DbSabitler.masalar} m ON r.masa_id = m.id
      WHERE r.durum IN ('beklemede', 'onaylandi') AND r.is_deleted = 0
        AND date(r.tarih) >= date('now', 'localtime')
      ORDER BY r.tarih ASC, r.saat ASC
    ''');
    return rows.map(RezervasyonModel.fromMap).toList();
  }

  /// 20 dakika içinde başlayacak rezervasyonları kontrol et
  Future<List<RezervasyonModel>> yaklasanRezervasyonlar() async {
    final db = await _db;
    final now = DateTime.now();
    final hedef = now.add(const Duration(minutes: 20));
    final rows = await db.rawQuery('''
      SELECT r.*, m.ad as masa_adi 
      FROM ${DbSabitler.masaRezervasyon} r
      LEFT JOIN ${DbSabitler.masalar} m ON r.masa_id = m.id
      WHERE r.durum IN ('beklemede', 'onaylandi') AND r.is_deleted = 0
        AND r.saat BETWEEN ? AND ?
      ORDER BY r.saat ASC
    ''', [now.toIso8601String(), hedef.toIso8601String()]);
    return rows.map(RezervasyonModel.fromMap).toList();
  }

  /// Masa müsaitlik kontrolü
  Future<bool> masaMusaitMi(int masaId, DateTime tarih, DateTime saat) async {
    final db = await _db;
    return !await _cakisiyorMu(db, masaId, saat);
  }

  /// Her rezervasyon [rezervasyonSuresi] boyunca masayı tutar; iki
  /// rezervasyonun başlangıçları bu süreden yakınsa çakışır (ör. 19:00
  /// varken 20:00 ya da 18:30 çakışır, 21:00 ya da 17:00 çakışmaz).
  ///
  /// 🔴 Önceki SQL kontrolü `datetime(saat,'+2 hours')` ('2026-10-04 21:00:00',
  /// boşluklu) ile ISO 'T' biçimli saat metnini karşılaştırıyordu; 'T' > ' '
  /// olduğundan "yeni saat mevcut rezervasyonun 2 saatlik penceresinde" hiç
  /// yakalanmıyor, `tarih = ?` eşitliği de farklı saat bileşenli kayıtları
  /// kaçırıyordu → aynı masa aynı akşam iki kez rezerve edilebiliyordu.
  static const rezervasyonSuresi = Duration(hours: 2);

  Future<bool> _cakisiyorMu(DatabaseExecutor ex, int masaId, DateTime saat,
      {int? haricId}) async {
    String g(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    // Gece yarısını aşan rezervasyonlar için komşu günler de taranır.
    final rows = await ex.rawQuery('''
      SELECT id, saat FROM ${DbSabitler.masaRezervasyon}
      WHERE masa_id = ? AND is_deleted = 0
        AND durum NOT IN ('iptal', 'tamamlandi')
        AND substr(saat, 1, 10) IN (?, ?, ?)
    ''', [
      masaId,
      g(saat.subtract(const Duration(days: 1))),
      g(saat),
      g(saat.add(const Duration(days: 1))),
    ]);
    for (final r in rows) {
      if (haricId != null && r['id'] == haricId) continue;
      final diger = DateTime.tryParse(r['saat']?.toString() ?? '');
      if (diger == null) continue;
      if (diger.difference(saat).abs() < rezervasyonSuresi) return true;
    }
    return false;
  }
}
