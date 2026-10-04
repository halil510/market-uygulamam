import '../../servisler/kolon_haritalama.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../servisler/log_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../cekirdek/sabitler/db_sabitleri.dart';
import '../../cekirdek/utils/sifre_hash.dart';
import '../../cekirdek/sabitler/uygulama_sabitleri.dart';
import 'migrasyon_yonetici.dart';
import 'tablolar/tablo_olusturucu.dart';
import 'sema_onarici.dart';
import 'sync_cakisma_tespit.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'veritabani_fis_seri.dart';
part 'veritabani_supabase.dart';

class Veritabani {
  static final Veritabani _instance = Veritabani._internal();
  factory Veritabani() => _instance;
  Veritabani._internal();

  static Database? _db;
  static Future<Database>? _acilis;

  /// Testlerde bellek-içi veritabanını singleton'a bağlamak için.
  @visibleForTesting
  static set testVeritabani(Database? db) {
    _db = db;
    _acilis = null;
  }

  // Tek kaynak: UygSabitler.dbVersiyon ile eşleşmeli
  static const int _versiyon = UygSabitler.dbVersiyon;

  /// 🔴 Açılış TEK SEFERLİK (2026-09-28): önceden `_db` null iken gelen her
  /// eşzamanlı çağrı ayrı bir `_baslatDb()` başlatıyordu. Açılış sırasında
  /// (migrasyon / şema onarımı) yazılan loglar da veritabanını istediği için
  /// ikinci bir açılış tetikleniyor, şema onarımı iki kez paralel çalışıyor
  /// ve geç biten açılış `_db`'nin üzerine yazabiliyordu. Artık açılış
  /// sürerken gelen çağrılar AYNI açılışı bekler.
  Future<Database> get db {
    final mevcut = _db;
    if (mevcut != null) return Future.value(mevcut);
    return _acilis ??= _baslatDb().then((d) {
      _db ??= d; // bu arada testVeritabani atandıysa ona dokunma
      return _db!;
    }).whenComplete(() => _acilis = null);
  }

  Future<Database> _baslatDb() async {
    final dbPath = await getDatabasesPath();
    // DbSabitler.dbAdi = 'market.db' — tek kaynak
    final yol = join(dbPath, DbSabitler.dbAdi);

    final database = await openDatabase(
      yol,
      version: _versiyon,
      onCreate: _olustur,
      onUpgrade: _guncelle,
      onConfigure: _onConfigure,
    );
    await _semaOnarGerekirse(database);
    return database;
  }

  /// Eski sürümden yükseltilmiş cihazlarda migrasyonun atladığı sütun/tablo/
  /// indeksleri güncel şemaya tamamlar — her DB sürümünde BİR KEZ (bkz.
  /// SemaOnarici; kullanıcı bulgusu 2026-09-28 "cari_hareket 119/119
  /// yazılamadı"). Hata olursa açılışı engellemez.
  static Future<void> _semaOnarGerekirse(Database database) async {
    final anahtar = 'mp_sema_onarim_v$_versiyon';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(anahtar) == true) return;
      await SemaOnarici.onar(database);
      await prefs.setBool(anahtar, true);
    } catch (e, st) {
      LogServisi().hata('Veritabani._semaOnarGerekirse', hata: e, yigin: st);
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    // WAL mode: concurrent read/write → büyük performans artışı
    try { await db.execute('PRAGMA journal_mode = WAL'); } catch (e) { /* ignore */ }
    // Cache: 10MB bellek - büyük liste sorguları
    try { await db.execute('PRAGMA cache_size = -10000'); } catch (e) { /* ignore */ }
    // Temp: RAM → join ve sort işlemleri için
    try { await db.execute('PRAGMA temp_store = MEMORY'); } catch (e) { /* ignore */ }
    // Sync: NORMAL → flush her transaction'da değil, periyodik
    try { await db.execute('PRAGMA synchronous = NORMAL'); } catch (e) { /* ignore */ }
    // Mmap: 128MB → büyük okumalar için bellek eşleme
    try { await db.execute('PRAGMA mmap_size = 134217728'); } catch (e) { /* ignore */ }
  }

  Future<void> _olustur(Database db, int version) async {
    await _tumTablolariOlustur(db);
    await _varsayilanVerileriEkle(db);
  }

  /// Migration tamamen MigrasyonYonetici'ye delege ediliyor — çift kod yok
  Future<void> _guncelle(Database db, int eski, int yeni) async {
    await MigrasyonYonetici.guncelle(db, eski, yeni);
  }

  Future<void> _tumTablolariOlustur(Database db) async {
    // Tüm tablo SQL'leri TabloOlusturucu'da — temiz ayrım
    await TabloOlusturucu.olustur(db);
  }

  Future<void> _varsayilanVerileriEkle(Database db) async {
    // Admin kullanıcı — şifre '1234' güvenli (tuzlu) hash ile, ilk
    // girişte değiştirilmeli. Yeni kurulumlar en baştan güvenli şemayla
    // başlasın diye SifreHash kullanılıyor (eski, tuzsuz _hashle DEĞİL).
    final _adminTuz = SifreHash.tuzUret();
    await db.insert(DbSabitler.kullanicilar, {
      'kullanici_adi': 'admin',
      'sifre_hash': SifreHash.hashleTuzlu('1234', _adminTuz),
      'tuz': _adminTuz,
      'ad_soyad': 'Sistem Yöneticisi',
      'rol': 'admin',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    // Merkez şube
    await db.insert(DbSabitler.subeler, {
      'sube_kodu': 'MERKEZ',
      'sube_adi': 'Merkez Şube',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    // Kategoriler
    for (final kat in [
      'Gıda', 'İçecek', 'Temizlik', 'Kişisel Bakım',
      'Elektronik', 'Kırtasiye', 'Ev & Yaşam', 'Diğer'
    ]) {
      await db.insert(DbSabitler.kategoriler, {'ad': kat},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Birimler
    for (final birim in [
      {'ad': 'Adet', 'kisaltma': 'Adet'},
      {'ad': 'Kilogram', 'kisaltma': 'KG'},
      {'ad': 'Gram', 'kisaltma': 'GR'},
      {'ad': 'Litre', 'kisaltma': 'LT'},
      {'ad': 'Mililitre', 'kisaltma': 'ML'},
      {'ad': 'Metre', 'kisaltma': 'MT'},
      {'ad': 'Kutu', 'kisaltma': 'Kutu'},
      {'ad': 'Paket', 'kisaltma': 'PKT'},
      {'ad': 'Koli', 'kisaltma': 'Koli'},
      {'ad': 'Çift', 'kisaltma': 'Çift'},
    ]) {
      await db.insert(DbSabitler.birimler, birim,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Gider kategorileri
    for (final kat in [
      'Kira', 'Elektrik', 'Su', 'Doğalgaz', 'İnternet',
      'Personel', 'Sigorta', 'Vergi', 'Bakım', 'Diğer'
    ]) {
      await db.insert(DbSabitler.giderKategoriler, {'ad': kat},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Uygulama ayarları
    final ayarlar = {
      'firma_adi': 'BarkoPro',
      'firma_adres': '',
      'firma_telefon': '',
      'firma_vergi_no': '',
      'firma_vergi_dairesi': '',
      'kdv_oran': '18',
      'para_birimi': 'TRY',
      'tema': 'light',
      'fis_alt_yazi': 'Bizi tercih ettiğiniz için teşekkürler',
      'min_stok_uyari': '1',
      'otomatik_fatura': '0',
      'puan_orani': '1',
      'puan_aktif': '0',
    };
    for (final e in ayarlar.entries) {
      await db.insert(DbSabitler.ayarlar,
          {'anahtar': e.key, 'deger': e.value},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Fiş serisi
    for (final tip in ['satis', 'iade', 'alim', 'transfer', 'fatura']) {
      await db.insert(DbSabitler.fisSeri,
          {'sube_id': 1, 'fis_tipi': tip, 'son_fis_no': 0},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // 🔴🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "veritabanı
    // temizlemede borç kalıyor, temizliyorum açtığımda borç var diye
    // bildirim geliyor"): Burada ÖNCEDEN sabit kodlanmış SAHTE DEMO
    // BORÇ VERİSİ ekleniyordu — "Vergi Dairesi Borcu" (₺12.500,50) ve
    // "Kredi Kartı" (₺8.750,00), toplamı TAM OLARAK kullanıcının
    // gördüğü ₺21.250,50! Bu fonksiyon veritabanı İLK KEZ
    // oluşturulduğunda (sqflite'ın onCreate'i) çalışıyor — yani hem
    // ilk kurulumda hem her "Veritabanını Temizle" sonrasında yeniden
    // tetikleniyordu. Gerçek bir işletme kullanıcısının hiç girmediği
    // sahte borçlarla karşılaşması KABUL EDİLEMEZ — muhtemelen
    // geliştirme/test amacıyla eklenip production'a kazara kalmış.
    // Tamamen kaldırıldı; yeni kurulum artık borç listesi TAMAMEN
    // BOŞ başlıyor (doğru davranış).
  }

  static String _hashle(String deger) {
    final bytes = utf8.encode(deger);
    return sha256.convert(bytes).toString();
  }

  static String sifrehashle(String sifre) => _hashle(sifre);


  /// Madde 2 sertleştirmesi (ayarlar_ekrani.dart — "Veritabanını Dışa
  /// Aktar"): veritabanı dosyasının diskteki tam yolu — ekranın
  /// doğrudan `(await Veritabani().db).path` okuması yerine.
  Future<String> dbYolu() async {
    final database = await db;
    return database.path;
  }

  Future<void> kapat() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
