// lib/veri/database/semalar/sync_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _sync() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Bulut senkronizasyon kuyruğu ve meta tabloları
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class SyncSemasi {
  static Future<void> olustur(Database db) async {

    // 🔴🔴🔴 MADDE 5 SERTLEŞTİRMESİ (ERP_DENETIM_KURALLARI.md): bu tablo
    // ÖNCEDEN kuruluyordu ama HİÇBİR KOD ONA YAZMIYORDU — gerçek kuyruk
    // BulutManager._kuyruk adlı RAM-only bir listeydi, uygulama çökerse
    // henüz gönderilmemiş kayıtlar kalıcı olarak kayboluyordu. Artık
    // BulutManager tamamen bu tabloyu kullanıyor (bkz. o dosya) —
    // 'hata_mesaji' kolonu son başarısız deneme mesajını görünür kılmak
    // için eklendi (mevcut cihazlar için ALTER TABLE migrasyonu: bkz.
    // migrasyon_yonetici_v36_v63.dart._v64denV65e).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.syncQueue} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tablo_adi TEXT NOT NULL, kayit_global_id TEXT, kayit_id INTEGER,
        islem_tipi TEXT NOT NULL, veri_json TEXT NOT NULL,
        deneme_sayisi INTEGER DEFAULT 0, son_deneme DATETIME,
        hata_mesaji TEXT,
        durum TEXT DEFAULT 'beklemede',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.syncMeta} (
        tablo_adi TEXT PRIMARY KEY, son_senkron DATETIME,
        son_id INTEGER, deleted_records TEXT
      )
    ''');

    // Sync Çakışmaları — iki cihaz aynı kaydı bağımsız değiştirdiğinde
    // (protokol §12), sessiz "son-yazan-kazanır" overwrite'tan ÖNCE burada
    // bir kayıt tutulur; kaybeden taraf denetlenebilir/manuel çözülebilir
    // olsun diye. Bkz. SupabaseSyncServisi._cakismaKaydet.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.syncCakismalar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tablo TEXT NOT NULL,
        kayit_global_id TEXT,
        alan_farklari TEXT,
        yerel_kayit TEXT,
        gelen_kayit TEXT,
        tarih DATETIME NOT NULL,
        cozuldu INTEGER NOT NULL DEFAULT 0,
        cozum_tipi TEXT,
        cozen_kullanici TEXT,
        cozum_tarihi DATETIME
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_cakisma_cozuldu ON ${DbSabitler.syncCakismalar}(cozuldu)');
  }
}
