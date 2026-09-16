// lib/veri/database/semalar/donem_semasi.dart
//
// YIL SONU DEVİR / DÖNEM KAPATMA / ARŞİVLEME SİSTEMİ — FAZ 1 (2026-09-16,
// kullanıcı onayıyla, bkz. ERP_DENETIM_KURALLARI.md.txt "YIL SONU DEVİR"
// bölümü + onaylanan mimari plan raporu).
//
// Bu dosya SADECE şema (tablo tanımı) içerir — devir motoru mantığı
// (DevirYoneticiServisi) İLERİKİ bir fazda eklenecek. 7 yeni tablo:
//   donemler                  — yıllık dönem kaydı (genel/özet durum)
//   donem_sube_durumlari      — şube bazlı kapanış ilerlemesi (Madde 29)
//   devir_checkpoint          — 10 fazlı devir motorunun resumable
//                                state-machine tablosu (Madde 17/27/28)
//   stok_kapanis_snapshot     — ürün+şube bazlı kapanış stok miktarı
//   cari_kapanis_snapshot     — cari bazlı kapanış bakiyesi (ŞUBE
//                                BAZLI DEĞİL — cari_hareket'te sube_id
//                                yok, cari bakiyesi şirket geneli)
//   kasa_kapanis_snapshot     — şube bazlı kapanış kasa bakiyesi
//   banka_kapanis_snapshot    — banka hesabı bazlı kapanış bakiyesi
//                                (ŞUBE BAZLI DEĞİL — banka_hesaplar'da
//                                sube_id yok, şirket geneli)
//
// TASARIM NOTU (sube_id NULL yerine 0 sentinel): SQLite UNIQUE
// kısıtlarında NULL değerler birbirine EŞİT sayılmaz — yani
// UNIQUE(donem_id, sube_id) gibi bir kısıt, sube_id NULL olan iki
// satırın aynı donem_id için tekrar oluşmasını ENGELLEMEZ (klasik bir
// SQLite tuzağı). Bu yüzden "şubeye bağlı olmayan" (genel/şirket
// geneli) kayıtlarda sube_id NULL değil, 0 (sentinel) kullanılır —
// böylece UNIQUE kısıtı güvenilir çalışır. devir_checkpoint_deposu.dart
// ve donem_deposu.dart bu kuralı uygulamalı.
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class DonemSemasi {
  static Future<void> olustur(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.donemler} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        donem_yili INTEGER NOT NULL UNIQUE,
        baslangic_tarihi TEXT NOT NULL,
        bitis_tarihi TEXT NOT NULL,
        durum TEXT NOT NULL DEFAULT 'OPEN',
        kapanis_tarihi TEXT,
        kapanisi_yapan_kullanici_id INTEGER,
        kapanis_cihazi TEXT,
        backup_durumu TEXT NOT NULL DEFAULT 'bekliyor',
        arsiv_durumu TEXT NOT NULL DEFAULT 'bekliyor',
        devir_durumu TEXT NOT NULL DEFAULT 'bekliyor',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_donem_yili ON ${DbSabitler.donemler}(donem_yili)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_donem_durum ON ${DbSabitler.donemler}(durum)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.donemSubeDurumlari} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        donem_id INTEGER NOT NULL,
        sube_id INTEGER NOT NULL,
        durum TEXT NOT NULL DEFAULT 'OPEN',
        kapanis_tarihi TEXT,
        kapanisi_yapan_kullanici_id INTEGER,
        kapanis_cihazi TEXT,
        backup_durumu TEXT NOT NULL DEFAULT 'bekliyor',
        arsiv_durumu TEXT NOT NULL DEFAULT 'bekliyor',
        devir_durumu TEXT NOT NULL DEFAULT 'bekliyor',
        last_updated TEXT,
        UNIQUE(donem_id, sube_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_donemsube_donem ON ${DbSabitler.donemSubeDurumlari}(donem_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.devirCheckpoint} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        devir_id TEXT NOT NULL UNIQUE,
        kaynak_donem_id INTEGER NOT NULL,
        hedef_donem_id INTEGER NOT NULL,
        sube_id INTEGER NOT NULL DEFAULT 0,
        durum TEXT NOT NULL DEFAULT 'INIT',
        mevcut_faz INTEGER NOT NULL DEFAULT 0,
        faz_ilerleme_json TEXT,
        baslangic_zamani TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        son_guncelleme TEXT,
        tamamlanma_zamani TEXT,
        hata_mesaji TEXT,
        last_updated TEXT,
        UNIQUE(kaynak_donem_id, hedef_donem_id, sube_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_devir_durum ON ${DbSabitler.devirCheckpoint}(durum)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.stokKapanisSnapshot} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        devir_id TEXT NOT NULL,
        donem_id INTEGER NOT NULL,
        sube_id INTEGER NOT NULL,
        urun_id INTEGER NOT NULL,
        miktar REAL NOT NULL,
        kaynak_hash TEXT,
        olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated TEXT,
        UNIQUE(donem_id, sube_id, urun_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stoksnap_donem ON ${DbSabitler.stokKapanisSnapshot}(donem_id, sube_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.cariKapanisSnapshot} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        devir_id TEXT NOT NULL,
        donem_id INTEGER NOT NULL,
        cari_id INTEGER NOT NULL,
        bakiye REAL NOT NULL,
        kaynak_hash TEXT,
        olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated TEXT,
        UNIQUE(donem_id, cari_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_carisnap_donem ON ${DbSabitler.cariKapanisSnapshot}(donem_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.kasaKapanisSnapshot} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        devir_id TEXT NOT NULL,
        donem_id INTEGER NOT NULL,
        sube_id INTEGER NOT NULL,
        bakiye REAL NOT NULL,
        kaynak_hash TEXT,
        olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated TEXT,
        UNIQUE(donem_id, sube_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_kasasnap_donem ON ${DbSabitler.kasaKapanisSnapshot}(donem_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.bankaKapanisSnapshot} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        devir_id TEXT NOT NULL,
        donem_id INTEGER NOT NULL,
        banka_hesap_id INTEGER NOT NULL,
        bakiye REAL NOT NULL,
        kaynak_hash TEXT,
        olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated TEXT,
        UNIQUE(donem_id, banka_hesap_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_bankasnap_donem ON ${DbSabitler.bankaKapanisSnapshot}(donem_id)');
  }
}
