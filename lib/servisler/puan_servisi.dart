// lib/servisler/puan_servisi.dart
//
// Müşteri sadakat puan sistemi
//  - Satış sonrası puan kazandır
//  - Puan harca (indirim olarak)
//  - Geçmiş ve bakiye sorgula
//  musteri_puan ve puan_hareket tabloları DB'de hazır
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../veri/database/veritabani.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import 'bulut/bulut_manager.dart';

class PuanServisi {
  static final PuanServisi _i = PuanServisi._();
  factory PuanServisi() => _i;
  PuanServisi._();

  /// Satış sonrası puan ekle (varsayılan: her 1₺ = 1 puan)
  Future<void> puanEkle({
    required int cariId,
    required double tutar,
    required int satisId,
    double puanOrani = 1.0, // 1 puan per TL
    String? aciklama,
  }) async {
    if (tutar <= 0 || puanOrani <= 0) return;
    final kazanilanPuan = (tutar * puanOrani).floorToDouble();
    if (kazanilanPuan <= 0) return;

    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      // musteri_puan upsert
      await txn.rawInsert('''
        INSERT INTO ${DbSabitler.musteriPuan}(cari_id, toplam_puan, kullanilan, son_islem, global_id)
        VALUES(?, ?, 0, ?, ?)
        ON CONFLICT(cari_id) DO UPDATE SET
          toplam_puan = toplam_puan + excluded.toplam_puan,
          son_islem   = excluded.son_islem
      ''', [cariId, kazanilanPuan, now, const Uuid().v4()]);

      // Hareket kaydı
      await txn.insert(DbSabitler.puanHareket, {
        'global_id':  const Uuid().v4(),
        'cari_id':    cariId,
        'islem_tipi': 'Kazanıldı',
        'puan':       kazanilanPuan,
        'referans_id': satisId,
        'aciklama':   aciklama ?? 'Satış puanı (${tutar.toStringAsFixed(2)} ₺)',
        ..._damga(now),
      });
    });
    // 🔴 Derin analizde bulundu: bu servis hiçbir zaman BulutManager
    // çağırmıyordu — müşteri sadakat puanları (kazanma/harcama) sadece
    // manuel senkronla buluta gidiyordu.
    await _bulutBildir(cariId, satisId, kazanilanTip: true);
    if (kDebugMode) debugPrint('Puan eklendi: cari=$cariId, puan=$kazanilanPuan');
  }

  /// Değişen musteri_puan ve son eklenen puan_hareket kaydını buluta bildirir.
  Future<void> _bulutBildir(int cariId, int referansId, {required bool kazanilanTip}) async {
    try {
      final db = await Veritabani().db;
      final puanSatir = await db.query(DbSabitler.musteriPuan,
          where: 'cari_id = ?', whereArgs: [cariId], limit: 1);
      if (puanSatir.isNotEmpty) {
        BulutManager().upsert(DbSabitler.musteriPuan, Map<String, dynamic>.from(puanSatir.first));
      }
      final hareketSatir = await db.query(DbSabitler.puanHareket,
          where: 'cari_id = ? AND referans_id = ?', whereArgs: [cariId, referansId],
          orderBy: 'id DESC', limit: 1);
      if (hareketSatir.isNotEmpty) {
        BulutManager().upsert(DbSabitler.puanHareket, Map<String, dynamic>.from(hareketSatir.first));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PuanServisi._bulutBildir hata: $e');
    }
  }

  /// Puan kullan (ödeme anında)
  /// Döndürür: gerçekte kullanılan puan miktarı
  Future<double> puanKullan({
    required int cariId,
    required double istenenPuan,
    required int satisId,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    var kullanilanPuan = 0.0;
    // Bakiye kontrolü yazma ile AYNI transaction'da — önceden dışarıdaydı,
    // çift dokunuşta iki çağrı da aynı bakiyeyi görüp fazla harcayabiliyordu.
    await db.transaction((txn) async {
      final rows = await txn.query(DbSabitler.musteriPuan,
          where: 'cari_id = ?', whereArgs: [cariId], limit: 1);
      if (rows.isEmpty) return;
      final bakiye = ((rows.first['toplam_puan'] as num?)?.toDouble() ?? 0) -
          ((rows.first['kullanilan'] as num?)?.toDouble() ?? 0);
      kullanilanPuan = istenenPuan.clamp(0.0, bakiye < 0 ? 0.0 : bakiye);
      if (kullanilanPuan <= 0) return;

      await txn.rawUpdate('''
        UPDATE ${DbSabitler.musteriPuan}
        SET kullanilan   = kullanilan + ?,
            son_islem    = ?,
            last_updated = ?
        WHERE cari_id = ?
      ''', [kullanilanPuan, now, now, cariId]);

      await txn.insert(DbSabitler.puanHareket, {
        'global_id':   const Uuid().v4(),
        'cari_id':     cariId,
        'islem_tipi':  'Harcandı',
        'puan':        -kullanilanPuan,
        'referans_id': satisId,
        'aciklama':    'Ödeme puanı kullanıldı',
        ..._damga(now),
      });
    });
    if (kullanilanPuan <= 0) return 0;
    await _bulutBildir(cariId, satisId, kazanilanTip: false);
    return kullanilanPuan;
  }

  // 🔴🔴 KRİTİK DÜZELTME (paralel fork denetimi, 2026-09-22 — "tam ERP"
  // turu): bir satış tamamlanınca müşteri puan kazanıyordu (puanEkle),
  // ama o satış İPTAL EDİLİP SİLİNİRSE (SatisDeposu.sil()) kazanılan
  // puan hiç geri alınmıyordu — kasiyer satışı yanlışlıkla girip hemen
  // silse bile müşterinin puan bakiyesinde kalıcı olarak duruyordu.
  // Bu, dosyadaki AYNI hata sınıfının (stok/kasa/cari reversal eksikliği
  // — bugün İade/Gider'de bulunup düzeltilen) sadakat puanı karşılığı.
  //
  // idempotent: aynı satisId için ikinci kez çağrılırsa (örn. bir hata
  // sonrası tekrar denenirse) zaten yazılmış 'İptal' kaydını görüp
  // hiçbir şey yapmaz — mükerrer geri alma/çifte düzeltme riski yok.
  Future<void> puanIptalEt({required int cariId, required int satisId}) async {
    final db = await Veritabani().db;
    final iptalGlobalIdleri = <String>[];
    await db.transaction((txn) async {
      final zatenIptal = await txn.query(DbSabitler.puanHareket,
          where: 'cari_id = ? AND referans_id = ? AND islem_tipi = ?',
          whereArgs: [cariId, satisId, 'İptal']);
      if (zatenIptal.isNotEmpty) return;

      final hareketler = await txn.query(DbSabitler.puanHareket,
          where: 'cari_id = ? AND referans_id = ? AND islem_tipi != ?',
          whereArgs: [cariId, satisId, 'İptal']);
      if (hareketler.isEmpty) return;

      // 'toplam_puan' (kazanılan) ve 'kullanilan' (harcanan) AYRI
      // sayaçlar — ikisini de kendi yönünde tersine çevirmek gerekir.
      double kazanilanToplam = 0, harcananToplam = 0;
      for (final h in hareketler) {
        final puan = (h['puan'] as num?)?.toDouble() ?? 0;
        if (puan > 0) {
          kazanilanToplam += puan;
        } else {
          harcananToplam += puan.abs();
        }
      }

      final now = DateTime.now().toIso8601String();
      if (kazanilanToplam > 0.005) {
        await txn.rawUpdate('''
          UPDATE ${DbSabitler.musteriPuan}
          SET toplam_puan = MAX(0, toplam_puan - ?), son_islem = ?, last_updated = ?
          WHERE cari_id = ?
        ''', [kazanilanToplam, now, now, cariId]);
        final gid = const Uuid().v4();
        await txn.insert(DbSabitler.puanHareket, {
          'global_id': gid,
          'cari_id': cariId,
          'islem_tipi': 'İptal',
          'puan': -kazanilanToplam,
          'referans_id': satisId,
          'aciklama': 'Satış iptali/silindi — kazanılan puan geri alındı',
          ..._damga(now),
        });
        iptalGlobalIdleri.add(gid);
      }
      if (harcananToplam > 0.005) {
        await txn.rawUpdate('''
          UPDATE ${DbSabitler.musteriPuan}
          SET kullanilan = MAX(0, kullanilan - ?), son_islem = ?, last_updated = ?
          WHERE cari_id = ?
        ''', [harcananToplam, now, now, cariId]);
        final gid = const Uuid().v4();
        await txn.insert(DbSabitler.puanHareket, {
          'global_id': gid,
          'cari_id': cariId,
          'islem_tipi': 'İptal',
          'puan': harcananToplam,
          'referans_id': satisId,
          'aciklama': 'Satış iptali/silindi — kullanılan puan iade edildi',
          ..._damga(now),
        });
        iptalGlobalIdleri.add(gid);
      }
    });
    if (iptalGlobalIdleri.isEmpty) return;
    try {
      final puanSatir = await db.query(DbSabitler.musteriPuan,
          where: 'cari_id = ?', whereArgs: [cariId], limit: 1);
      if (puanSatir.isNotEmpty) {
        BulutManager().upsert(DbSabitler.musteriPuan, Map<String, dynamic>.from(puanSatir.first));
      }
      for (final gid in iptalGlobalIdleri) {
        final hareketSatir = await db.query(DbSabitler.puanHareket,
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (hareketSatir.isNotEmpty) {
          BulutManager().upsert(DbSabitler.puanHareket, Map<String, dynamic>.from(hareketSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PuanServisi.puanIptalEt bulut bildirimi hatası: $e');
    }
  }

  /// Hareketlerden (toplam_puan, kullanilan) sayaçlarını puanIptalEt ile
  /// AYNI kuralla hesaplar: 'İptal' satırı kendi sayacını geri alır (eksi
  /// İptal → kazanılanı düşürür, artı İptal → harcananı düşürür). Önceden
  /// mutabakat yalnız işarete bakıyordu — eksi İptal'i "harcandı" sayıp
  /// her senkronda sayaçları değiştiriyor ve buluta yeniden gönderiyordu.
  @visibleForTesting
  static (double, double) sayaclariHesapla(List<Map<String, Object?>> hareketler) {
    double kazanilan = 0, harcanan = 0;
    for (final h in hareketler) {
      final puan = (h['puan'] as num?)?.toDouble() ?? 0;
      if (h['islem_tipi'] == 'İptal') {
        if (puan < 0) {
          kazanilan += puan;
        } else {
          harcanan -= puan;
        }
      } else if (puan > 0) {
        kazanilan += puan;
      } else {
        harcanan += puan.abs();
      }
    }
    return (kazanilan < 0 ? 0 : kazanilan, harcanan < 0 ? 0 : harcanan);
  }

  /// SQLite CURRENT_TIMESTAMP UTC yazar; ekran yerel saat beklediğinden
  /// geçmiş 3 saat geride görünüyordu — tarih açıkça yerel yazılır.
  static Map<String, Object> _damga(String now) =>
      {'tarih': now, 'last_updated': now};

  /// Mevcut kullanılabilir puan bakiyesi
  Future<double> puanBakiyesi(int cariId) async {
    final db = await Veritabani().db;
    final rows = await db.query(
      DbSabitler.musteriPuan,
      where: 'cari_id = ?',
      whereArgs: [cariId],
    );
    if (rows.isEmpty) return 0;
    final toplam    = (rows.first['toplam_puan'] as num?)?.toDouble() ?? 0;
    final kullanilan = (rows.first['kullanilan']  as num?)?.toDouble() ?? 0;
    return (toplam - kullanilan).clamp(0.0, double.infinity);
  }

  /// Puan geçmişi
  Future<List<Map<String, dynamic>>> puanGecmisi(int cariId,
      {int limit = 30}) async {
    final db = await Veritabani().db;
    return db.query(
      DbSabitler.puanHareket,
      where: 'cari_id = ?',
      whereArgs: [cariId],
      orderBy: 'tarih DESC',
      limit: limit,
    );
  }

  /// Puanı TL'ye çevir (varsayılan: 1 puan = 0.01 TL)
  double puanTL(double puan, {double oran = 0.01}) => puan * oran;

  /// Senkronizasyon sonrası çağrılması önerilir — tıpkı stok/borç/kredi
  /// kartı mutabakatı gibi. Atomik SQL artırımı (`col = col + ?`) tek
  /// cihaz içinde zaten güvenli, ama senkronizasyon sırasında iki
  /// cihazın gönderdiği "toplam_puan"/"kullanilan" ANLIK DEĞERLERİ
  /// (mutlak sayılar olarak) çakışabilir. Bu fonksiyon, her müşterinin
  /// puan durumunu KENDİ hareket kayıtlarının (`puan_hareket`) gerçek
  /// toplamından yeniden hesaplar.
  Future<int> puanMutabakatYap() async {
    final db = await Veritabani().db;
    final musteriler = await db.query(DbSabitler.musteriPuan);
    var duzeltilen = 0;
    for (final m in musteriler) {
      final cariId = m['cari_id'] as int;
      final eskiToplam = (m['toplam_puan'] as num?)?.toDouble() ?? 0;
      final eskiKullanilan = (m['kullanilan'] as num?)?.toDouble() ?? 0;
      final hareketler = await db.query(DbSabitler.puanHareket,
          where: 'cari_id = ?', whereArgs: [cariId]);
      final (dogruKazanilan, dogruHarcanan) = sayaclariHesapla(hareketler);
      if ((eskiToplam - dogruKazanilan).abs() > 0.01 ||
          (eskiKullanilan - dogruHarcanan).abs() > 0.01) {
        await db.update(DbSabitler.musteriPuan, {
          'toplam_puan': dogruKazanilan,
          'kullanilan': dogruHarcanan,
          // Türetilmiş değer: last_updated ilerletilmez (bkz. MasaDeposu.
          // siparisToplamlariMutabakatYap notu).
        }, where: 'cari_id = ?', whereArgs: [cariId]);
        final satir = await db.query(DbSabitler.musteriPuan,
            where: 'cari_id = ?', whereArgs: [cariId], limit: 1);
        if (satir.isNotEmpty) {
          BulutManager().upsert(DbSabitler.musteriPuan, Map<String, dynamic>.from(satir.first));
        }
        duzeltilen++;
      }
    }
    return duzeltilen;
  }
}
