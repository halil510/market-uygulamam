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
import 'sync_cakisma_tespit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Veritabani {
  static final Veritabani _instance = Veritabani._internal();
  factory Veritabani() => _instance;
  Veritabani._internal();

  static Database? _db;

  // Tek kaynak: UygSabitler.dbVersiyon ile eşleşmeli
  static const int _versiyon = UygSabitler.dbVersiyon;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _baslatDb();
    return _db!;
  }

  Future<Database> _baslatDb() async {
    final dbPath = await getDatabasesPath();
    // DbSabitler.dbAdi = 'market.db' — tek kaynak
    final yol = join(dbPath, DbSabitler.dbAdi);

    return await openDatabase(
      yol,
      version: _versiyon,
      onCreate: _olustur,
      onUpgrade: _guncelle,
      onConfigure: _onConfigure,
    );
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
      'firma_adi': 'MarketPlus',
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

  // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu fonksiyon
  // ÖNCEDEN 'WHERE sube_id = 1' olarak SABİT KODLANMIŞTI — uygulama
  // çoklu şube desteklediği (AktifSubeServisi, şube filtreleri her
  // yerde) halde, hangi şube aktif olursa olsun fiş numaralandırma
  // HER ZAMAN 1 numaralı şubenin sayacını kullanıyordu. Bir yönetici
  // aynı cihazdan farklı şubeler arasında geçiş yaptığında, fiş
  // numaraları o şubeye göre doğru sıralanmıyordu — Türkiye'de
  // e-fatura/e-irsaliye için şube bazlı sıralı numaralandırma yasal
  // bir gereklilik olabilir. Artık [subeId] parametre olarak alınıyor;
  // çağıran taraf vermezse (geriye dönük uyumluluk) varsayılan 1'dir.
  // 🔴 Derin analizde bulundu (P1 #11): fis_seri TAMAMEN yerel bir
  // sayaçtı — aynı şubede birden fazla POS terminali kullanılıyorsa her
  // biri kendi sayacını tutuyordu, biri diğerinin ürettiği numaradan
  // habersizdi. Aşağıdaki iki adım riski azaltır ama TAM bulletproof
  // DEĞİLDİR — iki terminal TAMAMEN AYNI ANDA, ikisi de offlineyken sayaç
  // üretirse çakışma yine mümkündür (çevrimdışı-öncelikli bir mimaride
  // kaçınılmaz bir ödünleşim; kesin çözüm online zorunluluğu getirir ki
  // bu, uygulamanın temel "internet olmadan da satış yapılabilir"
  // ilkesini bozar — bkz. kullanıcıyla yapılan görüşme):
  //   1) fisNoUret'in KENDİSİ ağdan ASLA etkilenmez/beklemez —
  //      _fisSeriBulutlaUyumla() burada unawaited'tir, sadece BİR
  //      SONRAKİ çağrıya fayda sağlar, mevcut satışı yavaşlatmaz/offline'ı
  //      bozmaz.
  //   2) Yeni sayaç DEĞERİ üretildikten (transaction commit olduktan)
  //      SONRA buluta best-effort itilir; Supabase tarafındaki BEFORE
  //      UPDATE tetikleyicisi (bkz. Supabase şema dosyası) son_fis_no'nun
  //      ASLA küçülmemesini (GREATEST) garanti eder — iki terminal farklı
  //      sırayla/farklı zamanlarda senkron olsa bile büyük olan değer
  //      kazanır, küçük bir yerel değer büyük olanın üzerine yazamaz.
  // Bilerek projenin genel "son_updated kazanır" senkron mekanizmasından
  // (SupabaseSyncServisi._tabloSirasi) AYRI, özel bir yol kullanıldı —
  // bir SAYAÇ için "son güncelleyen kazanır" semantiği YANLIŞTIR (geç
  // senkron olan küçük bir yerel değer, zaten kullanılmış büyük bir
  // numarayı sessizce geri alıp numara çakışmasına yeniden yol açabilir).
  Future<String> fisNoUret(String tip, {int subeId = 1}) async {
    unawaited(_fisSeriBulutlaUyumla());
    final database = await db;
    late final int yeniNo;
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — ekran görüntüsü:
    // "DatabaseException(FOREIGN KEY constraint failed (code 787 ...))
    // sql 'INSERT INTO fis_seri(sube_id, fis_tipi, son_fis_no)
    // VALUES(?, ?, ?)' args [1, satis, 1]"): fis_seri.sube_id,
    // subeler(id)'ye FK ile bağlı — bu fonksiyon HER ZAMAN subeId (ya da
    // varsayılan 1) ile INSERT/UPDATE deniyordu. O id'de GERÇEKTEN bir
    // şube yoksa (ör. "Veritabanını Temizle" sonrası oluşan bir
    // ara/yarış durumu, ya da subeler tablosu her nasılsa boşaldıysa)
    // INSERT anında FK ihlaliyle patlıyor ve kullanıcı HİÇ SATIŞ
    // YAPAMAZ hale geliyordu — satış ekranı sürekli "Satış hatası"
    // veriyordu. Artık kullanılan sube_id'nin GERÇEKTEN var olduğu
    // doğrulanıyor; yoksa mevcut ilk şubeye, o da yoksa yeni oluşturulan
    // bir "Merkez Şube"ye düşülüyor — kendi kendini onaran, satışı asla
    // engellemeyen bir yol.
    final gecerliSubeId = await _gecerliSubeIdGetir(database, subeId);
    final sonuc = await database.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT son_fis_no FROM ${DbSabitler.fisSeri} WHERE sube_id = ? AND fis_tipi = ?',
        [gecerliSubeId, tip],
      );
      final sonNo =
          result.isNotEmpty ? (result.first['son_fis_no'] as int) : 0;
      yeniNo = sonNo + 1;
      if (result.isEmpty) {
        // Satır yoksa ekle
        await txn.rawInsert(
          'INSERT INTO ${DbSabitler.fisSeri}(sube_id, fis_tipi, son_fis_no) VALUES(?, ?, ?)',
          [gecerliSubeId, tip, yeniNo],
        );
      } else {
        await txn.rawUpdate(
          'UPDATE ${DbSabitler.fisSeri} SET son_fis_no = ? WHERE sube_id = ? AND fis_tipi = ?',
          [yeniNo, gecerliSubeId, tip],
        );
      }
      final now = DateTime.now();
      // GIB Türkiye e-Fatura/e-Arşiv standartı:
      // Fatura: [A-Z]{3}[0-9]{4}[0-9]{9} = 3 harf + 4 yıl rakamı + 9 sıra no
      // Örnek: MKP2024000000001
      final prefix = switch (tip) {
        'satis'     => 'MKP',
        'masa'      => 'MSA',
        'cari_satis'=> 'CRI',
        'fatura'    => 'FAT',
        'irsaliye'  => 'IRS',
        'alim'      => 'ALM',
        'iade'      => 'IAD',
        'siparis'   => 'SIP',
        _ => tip.toUpperCase().substring(0, min(3, tip.length)).padRight(3, 'X'),
      };
      final yil = now.year.toString();
      final siraNo = yeniNo.toString().padLeft(9, '0');
      return '$prefix$yil$siraNo'; // GIB standartı: 16 karakter
    });
    unawaited(_fisSeriBulutaPushla(gecerliSubeId, tip, yeniNo));
    return sonuc;
  }

  /// [istenenSubeId] gerçekten subeler tablosunda varsa aynen döner;
  /// yoksa mevcut ilk şubeye, hiç şube yoksa yeni oluşturulan bir
  /// "Merkez Şube"ye düşer. bkz. fisNoUret üzerindeki kritik düzeltme
  /// notu — bu, fis_seri.sube_id FK ihlalini kalıcı olarak önler.
  Future<int> _gecerliSubeIdGetir(Database database, int istenenSubeId) async {
    final istenen = await database.query(DbSabitler.subeler,
        columns: ['id'], where: 'id = ?', whereArgs: [istenenSubeId], limit: 1);
    if (istenen.isNotEmpty) return istenenSubeId;

    final ilkSube =
        await database.query(DbSabitler.subeler, columns: ['id'], orderBy: 'id', limit: 1);
    if (ilkSube.isNotEmpty) return ilkSube.first['id'] as int;

    final yeniId = await database.insert(
        DbSabitler.subeler, {'sube_kodu': 'MERKEZ', 'sube_adi': 'Merkez Şube'},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (yeniId > 0) return yeniId;

    // ignore nedeniyle 0 döndüyse (aynı sube_kodu'yla BAŞKA bir satır
    // araya girmiş) — o satırı bul.
    final tekrar =
        await database.query(DbSabitler.subeler, columns: ['id'], orderBy: 'id', limit: 1);
    return tekrar.isNotEmpty ? tekrar.first['id'] as int : istenenSubeId;
  }

  static DateTime? _sonFisSeriUyum;

  /// Bulut'taki fis_seri satırlarını çekip yerel sayaçla MAX-birleştirir
  /// (bkz. fisNoUret üzerindeki not) — başka bir terminalin bu şubede/bu
  /// tipte ÜRETTİĞİ daha yüksek bir numarayı öğrenirse yerel sayaç ona
  /// göre YUKARI çekilir, ASLA aşağı çekilmez (MAX(), tersini yapamaz).
  /// Tamamen best-effort: bulut yapılandırılmamışsa, offline'sa ya da
  /// herhangi bir hata olursa sessizce hiçbir şey yapmaz — fisNoUret'i
  /// asla ağa bağımlı hale getirmez. 30 saniyede bir kendini kısıtlar
  /// (her satışta ağ isteği atmasın diye).
  Future<void> _fisSeriBulutlaUyumla() async {
    final simdi = DateTime.now();
    if (_sonFisSeriUyum != null &&
        simdi.difference(_sonFisSeriUyum!) < const Duration(seconds: 30)) {
      return;
    }
    _sonFisSeriUyum = simdi;
    try {
      final saglayici = BulutManager().mevcutSaglayici;
      if (saglayici == null) return;
      final uzakSatirlar =
          await saglayici.cek(tablo: DbSabitler.fisSeri, limit: 500);
      if (uzakSatirlar.isEmpty) return;
      final database = await db;
      await database.transaction((txn) async {
        for (final satir in uzakSatirlar) {
          final uzakSubeId = (satir['sube_id'] as num?)?.toInt();
          final uzakTip = satir['fis_tipi']?.toString();
          final uzakSon = (satir['son_fis_no'] as num?)?.toInt();
          if (uzakSubeId == null || uzakTip == null || uzakSon == null) {
            continue;
          }
          // Satır yerelde yoksa önce oluştur (yoksayılabilir çakışma),
          // sonra HER KOŞULDA MAX() ile kelepçele — asla küçültme.
          await txn.rawInsert(
            'INSERT OR IGNORE INTO ${DbSabitler.fisSeri}'
            '(sube_id, fis_tipi, son_fis_no) VALUES(?, ?, ?)',
            [uzakSubeId, uzakTip, uzakSon],
          );
          await txn.rawUpdate(
            'UPDATE ${DbSabitler.fisSeri} SET son_fis_no = MAX(son_fis_no, ?) '
            'WHERE sube_id = ? AND fis_tipi = ?',
            [uzakSon, uzakSubeId, uzakTip],
          );
        }
      });
    } catch (_) {
      // best-effort — offline/hata sessizce yutulur
    }
  }

  /// Yeni üretilen yerel sayaç değerini buluta best-effort iter.
  /// BulutManager()'ın genel kuyruk/dedup mekanizması KASITLI OLARAK
  /// kullanılmıyor — o mekanizma kayıtları 'global_id' ile eşleştirip
  /// gruplandırıyor, fis_seri'nin ise hiç global_id'si yok (doğal
  /// anahtarı sube_id+fis_tipi). Bu, aynı tablo için kuyrukta bekleyen
  /// FARKLI (sube_id,fis_tipi) kayıtlarının birbirinin üzerine
  /// yazılmasına (kuyruktan sessizce düşmesine) yol açabilirdi — bu
  /// yüzden burada sağlayıcının tekli upsert'i DOĞRUDAN, kuyruğa
  /// girmeden çağrılıyor.
  Future<void> _fisSeriBulutaPushla(int subeId, String tip, int yeniNo) async {
    try {
      final saglayici = BulutManager().mevcutSaglayici;
      if (saglayici == null) return;
      await saglayici.upsert(
        tablo: DbSabitler.fisSeri,
        veri: {
          'sube_id': subeId,
          'fis_tipi': tip,
          'son_fis_no': yeniNo,
          'last_updated': DateTime.now().toUtc().toIso8601String(),
        },
        uniqueAlan: 'sube_id,fis_tipi',
      );
    } catch (_) {
      // best-effort — offline/hata sessizce yutulur, yerel numara zaten üretildi
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SUPABASE SYNC METODLARI
  // ═══════════════════════════════════════════════════════════════

  /// Supabase'e gönderilecek kayıtları getir
  Future<List<Map<String, dynamic>>> supaTumKayitlariGetir(
    String tablo,
    bool filtrele,
  ) async {
    final database = await db;
    try {
      // 🔴🔴🔴 KRİTİK KÖK NEDEN DÜZELTMESİ: Bu fonksiyon SADECE bulut
      // senkronuna GÖNDERİLECEK kayıtları toplamak için kullanılıyor.
      // Önceden 'urunler','cari','satislar','faturalar' için
      // is_deleted=1 (silinmiş) kayıtlar SORGUDAN TAMAMEN ÇIKARILIYORDU
      // — bu 4 tablodaki HİÇBİR SİLME İŞLEMİNİN buluta gitmemesi
      // demekti. Artık silinmiş kayıtlar da dahil TÜM kayıtlar
      // döndürülüyor — silme durumu doğru şekilde buluta yansıyor.
      return await database.query(tablo);
    } catch (e) {
      debugPrint('❌ supaTumKayitlariGetir hatası ($tablo): $e');
      return [];
    }
  }

  // 🔴🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — kredi_kartlari NOT
  // NULL hatası, Supabase TAMAMEN temizlenip tekrar gönderilmesine
  // rağmen AYNI hata devam ediyordu): BulutManager.upsert()'e
  // eklediğim kart_no_maskeli sanitizasyonu SADECE otomatik arka plan
  // senkronunda çalışıyordu. "Buluta Gönder" (manuel tam senkron) BU
  // FONKSİYONU (supaTumKayitlariGetir) kullanıyor — BulutManager'ı HİÇ
  // görmüyor, bu yüzden düzeltme hiç devreye girmiyordu. Artık bu
  // merkezi noktada da uygulanıyor.
  Future<List<Map<String, dynamic>>> supaTumKayitlariGetirTemiz(
    String tablo, bool filtrele,
  ) async {
    final satirlar = await supaTumKayitlariGetir(tablo, filtrele);
    if (tablo == 'kredi_kartlari') {
      final database = await db;
      for (final satir in satirlar) {
        final knm = satir['kart_no_maskeli'];
        if (knm == null || (knm is String && knm.isEmpty)) {
          satir['kart_no_maskeli'] = '**** **** **** ????';
          if (satir['id'] != null) {
            database.update('kredi_kartlari', {'kart_no_maskeli': '**** **** **** ????'},
                where: 'id = ?', whereArgs: [satir['id']]).catchError((_) => 0);
          }
        }
      }
    }
    return satirlar;
  }

  /// Yeni kayıtları ekle (Supabase'den gelen)
  /// 🔴🔴🔴 KULLANICI TARAFINDAN BULUNAN, GERÇEK VERİ KAYBI HATASI:
  /// 'cari' tablosunda cari_kodu, 'satislar'/'faturalar'da fiş/fatura
  /// no UNIQUE — 2 cihaz FARKLI global_id'li ama AYNI kod/numaralı
  /// kayıt oluşturduğunda, bu kayıt senkronize edilirken UNIQUE
  /// ihlaliyle patlıyordu (INSERT'te ConflictAlgorithm.replace bunu
  /// "çakışma" sayıp var olan kaydı SİLİP üzerine yazma riski
  /// taşıyordu; UPDATE'te ise SQL doğrudan hata fırlatıp o kaydı hiç
  /// güncellemiyordu — kullanıcının bildirdiği hata TAM OLARAK bu).
  ///
  /// 🔴 BU FONKSİYON ÖNCEDEN SADECE supaKayitlariEkle (INSERT) İÇİNDE
  /// VARDI — supaKayitlariGuncelle (UPDATE) hiç çağırmıyordu. Aynı
  /// çakışma sınıfı, kaydın zaten yerelde var olduğu (dolayısıyla
  /// UPDATE yoluna düştüğü) durumda korumasız kalıyordu. Artık HER
  /// İKİ yoldan da (ekleme VE güncelleme) önce bu uygulanıyor.
  Future<void> _cakismaKorumasiUygula(
      Database database, String tablo, List<Map<String, dynamic>> kayitlar) async {
    if (tablo == 'cari') {
      for (final kayit in kayitlar) {
        final gelenKod = kayit['cari_kodu'];
        final gelenGlobalId = kayit['global_id'];
        if (gelenKod == null || gelenGlobalId == null) continue;
        final cakisan = await database.query('cari',
            columns: ['global_id'],
            where: 'cari_kodu = ? AND global_id != ?',
            whereArgs: [gelenKod, gelenGlobalId]);
        if (cakisan.isNotEmpty) {
          final maxRows = await database.rawQuery(
              "SELECT cari_kodu FROM cari WHERE cari_kodu LIKE 'CARIO-%' "
              "ORDER BY CAST(SUBSTR(cari_kodu, 7) AS INTEGER) DESC LIMIT 1");
          var sonNo = 0;
          if (maxRows.isNotEmpty) {
            final kod = maxRows.first['cari_kodu'] as String?;
            sonNo = int.tryParse(kod?.replaceFirst('CARIO-', '') ?? '') ?? 0;
          }
          kayit['cari_kodu'] = 'CARIO-${sonNo + 1}';
          LogServisi().bilgi(
              'Senkronizasyon çakışması önlendi: gelen cari ($gelenGlobalId) '
              'yeni kod aldı (${kayit["cari_kodu"]}), yerel kayıt korundu.');
        }
      }
    }

    if (tablo == 'satislar' || tablo == 'faturalar') {
      final alanAdi = tablo == 'satislar' ? 'fis_no' : 'fatura_no';
      for (final kayit in kayitlar) {
        final gelenNo = kayit[alanAdi];
        final gelenGlobalId = kayit['global_id'];
        if (gelenNo == null || gelenGlobalId == null) continue;
        final cakisan = await database.query(tablo,
            columns: ['global_id'],
            where: '$alanAdi = ? AND global_id != ?',
            whereArgs: [gelenNo, gelenGlobalId]);
        if (cakisan.isNotEmpty) {
          final kisaId = gelenGlobalId.toString().substring(0, 6);
          kayit[alanAdi] = '$gelenNo-SYNC$kisaId';
          // 🔴 DÜZELTME (kullanıcı bulgusu, 2026-09-21): bu satır ÖNCEDEN
          // sadece ⚠ ile işaretlenip Satış Listesi/Gün Sonu'nda sıradan
          // bir satış gibi TAM DEĞERLİ sayılıyordu — kullanıcı ekran
          // görüntüsünde tek bir ₺90'lık satışın Gün Sonu'nda ₺180 Cari
          // Satış olarak göründüğünü bildirdi ("kafa karıştırıyor").
          // Artık 'satislar' için ayrıca sync_cakisma_kopyasi=1
          // damgalanıyor (v73 migrasyonu) — SatisDeposu.tariheGoreGetir/
          // maliyetToplami/gunSonuDetayGetir bunu varsayılan olarak
          // dışlıyor, Sync Çakışmaları ekranı ayrı bir bölümde gösterip
          // kullanıcıya "gerçek satış" / "kopya, sil" seçimi sunuyor.
          // 'faturalar' tablosunda bu sütun yok (kapsam dışı bırakıldı,
          // GİB tarafında farklı bir inceleme akışı gerektirir).
          if (tablo == 'satislar') {
            kayit['sync_cakisma_kopyasi'] = 1;
          }
          // 🔴 DÜZELTME (kritik — derin denetimde bulundu, sadece
          // 'faturalar' için): Bu yeniden adlandırma ÖNCEDEN SADECE yerel
          // veritabanına yazılıyordu — Supabase'e (veya diğer cihazlara)
          // HİÇ geri gönderilmiyordu. Sonuç: bulutta AYNI fatura_no'ya
          // sahip İKİ satır kalıcı olarak duruyordu, ve iki cihaz bu
          // çakışmayı GÖRDÜKLERİ SIRAYA göre BAĞIMSIZ/FARKLI şekillerde
          // çözüyordu (A cihazı X satırını, B cihazı Y satırını "-SYNC"
          // yapabiliyordu) — resmi fatura numaralarında çoklu-cihaz
          // tutarsızlığı. Artık çözülmüş (yeni numaralı) hâli BULUTA DA
          // geri gönderiliyor ki diğer cihazlar bir sonraki senkronda
          // AYNI (çözülmüş) sonucu görsün.
          //
          // NOT: Bu, İKİ cihazın TAM OLARAK AYNI ANDA aynı fatura_no'yu
          // üretme riskinin KENDİSİNİ ortadan kaldırmaz (bu, çevrimdışı-
          // öncelikli mimariyi bozmadan ayrı, daha büyük bir tasarım
          // kararı gerektirir — bkz. proje notları) — sadece çakışma
          // TESPİT EDİLDİKTEN SONRA bulutun ve tüm cihazların AYNI
          // (çözülmüş) sonuca YAKINSAMASINI sağlar.
          if (tablo == 'faturalar') {
            try {
              BulutManager().upsert(tablo, Map<String, dynamic>.from(kayit));
            } catch (e) {
              LogServisi().bilgi('Fatura çakışma düzeltmesi buluta '
                  'gönderilemedi (bir sonraki senkronda tekrar denenecek): $e');
            }
          }
          LogServisi().bilgi(
              'Senkronizasyon çakışması önlendi: $tablo ($gelenGlobalId) '
              'yeni numara aldı, yerel kayıt korundu.');
        }
      }
    }

    if (tablo == 'urunler') {
      for (final kayit in kayitlar) {
        final gelenGlobalId = kayit['global_id'];
        if (gelenGlobalId == null) continue;
        for (final alan in ['kod', 'barkod']) {
          final gelenDeger = kayit[alan];
          if (gelenDeger == null) continue;
          final cakisan = await database.query('urunler',
              columns: ['global_id'],
              where: '$alan = ? AND global_id != ?',
              whereArgs: [gelenDeger, gelenGlobalId]);
          if (cakisan.isNotEmpty) {
            kayit[alan] = null; // çakışan alanı temizle, ürünü kaybetme
            LogServisi().bilgi(
                'Senkronizasyon çakışması önlendi: urunler.$alan '
                '($gelenGlobalId) temizlendi, yerel kayıt korundu.');
          }
        }
      }
    }

    // 🔴 Aynı çakışma sınıfının şemadaki DİĞER örnekleri — cari/satislar
    // hatası bildirilince şemadaki TÜM UNIQUE sütunlar tek tek tarandı.
    // Numara/kod alanları: çakışırsa yeniden numaralanır (veri kaybı yok).
    const numaraAlanlari = {
      'irsaliyeler': 'irsaliye_no',
      'tedarikci_siparisler': 'siparis_no',
      'subeler': 'sube_kodu',
    };
    if (numaraAlanlari.containsKey(tablo)) {
      final alanAdi = numaraAlanlari[tablo]!;
      for (final kayit in kayitlar) {
        final gelenNo = kayit[alanAdi];
        final gelenGlobalId = kayit['global_id'];
        if (gelenNo == null || gelenGlobalId == null) continue;
        final cakisan = await database.query(tablo,
            columns: ['global_id'],
            where: '$alanAdi = ? AND global_id != ?',
            whereArgs: [gelenNo, gelenGlobalId]);
        if (cakisan.isNotEmpty) {
          final kisaId = gelenGlobalId.toString().substring(0, 6);
          kayit[alanAdi] = '$gelenNo-SYNC$kisaId';
          LogServisi().bilgi(
              'Senkronizasyon çakışması önlendi: $tablo ($gelenGlobalId) '
              'yeni numara aldı, yerel kayıt korundu.');
        }
      }
    }

    // İsim alanları: rastgele numara yerine okunabilir bir ek uygun —
    // ör. "İçecek" çakışırsa "İçecek (SYNC)".
    // 🔴 KULLANICI TARAFINDAN BULUNAN HATA: 'masalar' bu listede hiç
    // yoktu — masa isimleri (ad) hiçbir çakışma koruması olmadan
    // senkronlanıyordu. Sonuç: "Masa 1" adında, farklı global_id'li
    // ikinci bir kayıt (başka bir cihazda oluşmuş / bir önceki kurulum
    // artığı vb.) buluttan gelince, aynı isimle SESSİZCE ikinci bir
    // satır olarak ekleniyordu — kullanıcı "Masa 1'den iki tane oluyor"
    // diye bildirdi. Artık masalar da bu korumaya dahil; çakışan gelen
    // kayıt "Masa 1 (SYNC)" gibi görünür bir adla eklenir, üzerine
    // yazma/veri kaybı olmaz ve kullanıcı ekranda ikisini görüp elle
    // birleştirip silebilir.
    const isimTablolari = {'kategoriler', 'birimler', 'markalar', 'masalar'};
    if (isimTablolari.contains(tablo)) {
      for (final kayit in kayitlar) {
        final gelenAd = kayit['ad'];
        final gelenGlobalId = kayit['global_id'];
        if (gelenAd == null || gelenGlobalId == null) continue;
        final cakisan = await database.query(tablo,
            columns: ['global_id'],
            where: 'ad = ? COLLATE NOCASE AND global_id != ?',
            whereArgs: [gelenAd, gelenGlobalId]);
        if (cakisan.isNotEmpty) {
          kayit['ad'] = '$gelenAd (SYNC)';
          LogServisi().bilgi(
              'Senkronizasyon çakışması önlendi: $tablo ($gelenGlobalId) '
              'yeni ad aldı, yerel kayıt korundu.');
        }
      }
    }
  }

  /// SupabaseSyncServisi._filigranAnahtari(tablo, 'gonder') İLE AYNI
  /// anahtar biçimi — bu cihazın o tabloyu buluta EN SON BAŞARIYLA
  /// gönderdiği (hatasız tamamlanan) zaman. Kasıtlı olarak o dosyayı
  /// import ETMİYORUZ (döngüsel bağımlılık: o dosya zaten bu dosyayı
  /// import ediyor) — sadece aynı anahtar sözleşmesini paylaşıyoruz.
  Future<DateTime?> _sonGonderFiligrani(String tablo) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('mp_sync_gonder_$tablo') ??
        prefs.getString('mp_sync_$tablo'); // eski tek-anahtar sürümü
    return s != null ? DateTime.tryParse(s) : null;
  }

  /// Bir kaydın gelen (buluttan) sürümüyle üzerine yazılmadan HEMEN önce
  /// çağrılır. Yerel ve gelen satır arasında metadata dışı gerçek bir alan
  /// farkı varsa 'sync_cakismalar' tablosuna kalıcı bir kayıt düşer —
  /// kaybedecek olan yerel değer(ler) böylece kaybolmadan önce arşivlenmiş
  /// olur. Fark tespiti saf/test edilebilir SyncCakismaTespit'te (bkz. o
  /// dosya).
  ///
  /// 🔴 FAZ 3 (madde 4, 2026-09-21): ÖNCEDEN bu fonksiyon LWW SONUCUNU
  /// HİÇ DEĞİŞTİRMİYORDU, sadece görünürlük ekliyordu — artık dönüş
  /// değeri (gerçek bir çakışma kaydedildi mi) çağırana taşınıyor ki
  /// "işlem verisi" tablolarında (bkz. SyncCakismaTespit.islemVerisiMi)
  /// otomatik üzerine yazmayı DURDURABİLSİN.
  Future<bool> _cakismaKaydetGerekirse(
    Database database,
    String tablo,
    Map<String, dynamic> yerelSatir,
    Map<String, dynamic> gelenSatir,
  ) async {
    try {
      final farklar = SyncCakismaTespit.farklariBul(yerelSatir, gelenSatir);
      if (farklar.isEmpty) return false; // gerçek bir fark yok, çakışma sayılmaz

      // 🔴🔴 KÖK NEDEN DÜZELTMESİ (kullanıcı bulgusu — "sync çakışma var
      // diyor"): ÖNCEDEN buraya, yerel satır ile gelen satır sadece
      // FARKLI diye düşülüyordu. Ama bu fark, BU cihazın yaptığı bir
      // değişiklikle hiç ilgisiz olabilir — sadece BAŞKA bir cihazın
      // DAHA ÖNCE yaptığı, tamamen normal bir güncellemenin bu cihaza
      // İLK KEZ ulaşması da (yerelde eski sürüm durduğu için) birebir
      // aynı şekilde "fark" üretiyordu. Sonuç: gerçekte kimse çakışmadı
      // — sadece normal, tek yönlü senkron yayılması oldu — ama bu her
      // seferinde "Sync Çakışmaları" ekranına gerçek bir çakışmaymış
      // gibi düşüp kullanıcıyı gereksiz yere karar vermeye zorluyordu.
      // Artık: bu cihazın o tabloyu EN SON BAŞARIYLA gönderdiği andan
      // BERİ yerel kayıt hiç değişmediyse (yani yerelde "kaybolacak",
      // henüz buluta gitmemiş bir değişiklik YOKSA) bu bir çakışma
      // sayılmıyor — sadece sessizce uygulanıyor. Emin olunamayan
      // durumlarda (bu tablo bu cihazdan hiç gönderilmediyse)
      // ESKİ (güvenli/muhafazakâr) davranışa dönülüyor: yine kaydedilir.
      final gonderFiligrani = await _sonGonderFiligrani(tablo);
      final yerelZaman =
          DateTime.tryParse(yerelSatir['last_updated']?.toString() ?? '');
      if (!SyncCakismaTespit.gercekCakismaMi(
          yerelSonGuncelleme: yerelZaman,
          sonBasariliGonderim: gonderFiligrani)) {
        return false; // yerel sürüm zaten buluta gönderilmişti — kayıp riski yok
      }

      final now = DateTime.now().toIso8601String();
      final globalId = gelenSatir['global_id']?.toString();
      // 🔴 DEEP_AUDIT (kendi-keşif turu, 2026-09-21): ÖNCEDEN her turda
      // koşulsuz INSERT yapılıyordu — kullanıcı bir çakışmayı hemen
      // çözmezse, her periyodik sync turunda AYNI (tablo, global_id)
      // için mükerrer "sync_cakismalar" satırı birikiyordu (FAZ 3'ün
      // "işlem verisi otomatik uygulanmaz" davranışıyla artık daha da
      // görünür — satır bir daha asla kendiliğinden "çözülmüş" olmuyor).
      // Artık aynı kayıt için ÇÖZÜLMEMİŞ bir çakışma zaten varsa, yeni
      // satır eklemek yerine o satır GÜNCELLENİYOR (en güncel alan
      // farkları/kayıtlarla) — kullanıcı "Sync Çakışmaları" ekranında
      // tek, güncel bir kayıt görür.
      final mevcutCakisma = globalId != null
          ? await database.query(DbSabitler.syncCakismalar,
              columns: ['id'],
              where: 'tablo = ? AND kayit_global_id = ? AND cozuldu = 0',
              whereArgs: [tablo, globalId],
              limit: 1)
          : const <Map<String, dynamic>>[];
      final satirVerisi = {
        'tablo': tablo,
        'kayit_global_id': globalId,
        'alan_farklari': jsonEncode(farklar),
        'yerel_kayit': jsonEncode(yerelSatir),
        'gelen_kayit': jsonEncode(gelenSatir),
        'tarih': now,
        'cozuldu': 0,
      };
      if (mevcutCakisma.isNotEmpty) {
        await database.update(DbSabitler.syncCakismalar, satirVerisi,
            where: 'id = ?', whereArgs: [mevcutCakisma.first['id']]);
      } else {
        await database.insert(DbSabitler.syncCakismalar, satirVerisi);
      }
      return true;
    } catch (e, st) {
      // Çakışma kaydı BEST-EFFORT'tur — burada bir hata olsa bile asıl
      // senkron akışını (gelen değerin uygulanmasını) DURDURMAMALI.
      LogServisi().hata('Veritabani._cakismaKaydetGerekirse', hata: e, yigin: st);
      return false;
    }
  }

  Future<void> supaKayitlariEkle(
    String tablo,
    List<Map<String, dynamic>> kayitlar,
  ) async {
    if (kayitlar.isEmpty) return;
    final database = await db;
    // 🔴🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "buluttan veri al'ı
    // kontrol et, uyuşmayan yer olur"): Bu liste ÖNCEDEN sadece 18
    // tablo içeriyordu — proje 58 tabloyu senkronize ediyor. Listede
    // OLMAYAN bir tabloda, gelen kayıt global_id çakışmasına
    // uğrarsa (nadir ama interrupted/retry senaryolarında mümkün)
    // ConflictAlgorithm.ignore SESSİZCE atlıyordu — replace yerine.
    // Artık TÜM senkronize edilen tablolar burada.
    const globalIdTablosu = {
      'urunler', 'cari', 'satislar', 'iade', 'faturalar',
      'fatura_detaylari', 'promosyonlar', 'promosyon_tanim',
      'tedarikci_siparisler', 'giderler', 'kasa_hareketleri',
      'vardiyalar', 'personel', 'musteri_puan', 'lot_seri',
      'masalar', 'masa_siparisleri', 'masa_siparis_kalem',
      'subeler', 'kullanicilar', 'kategoriler', 'birimler',
      'markalar', 'gider_kategoriler', 'rol_yetkileri',
      'roller_yetki', 'ayarlar', 'zaman_fiyat', 'fiyat_gecmis',
      'fiyat_gruplari', 'cari_adres', 'satis_kalem', 'iade_kalem',
      'irsaliyeler', 'irsaliye_kalem', 'promosyon_kosul',
      'promosyon_aksiyon', 'tedarikci_siparis_kalem', 'stok_hareket',
      'cari_hareket', 'puan_hareket', 'masa_rezervasyon',
      'adisyon_log', 'garson_cagri_log', 'masa_hareket_log',
      'banka_hesaplar', 'bankalar', 'kredi_kartlari',
      'banka_hareketler', 'kredi_karti_hareket', 'borclar',
      'borc_odemeler', 'audit_log', 'urun_fiyat_gruplari',
      'fiyat_kademeleri', 'sube_urun',
      // 🔴 DÜZELTME: bu 3 tablo senkron sistemine (supabase_sync_servisi.dart
      // _tabloSirasi/_globalIdVar/_uniqueAlan) sonradan eklendiğinde bu
      // liste güncellenmemişti — global_id çakışması olursa (retry/kesinti
      // senaryosu) sessizce IGNORE ediliyordu, REPLACE yerine.
      'bekleyen_siparisler', 'bekleyen_siparis_kalem', 'onay_talepleri',
      // Yıl Sonu Devir / Dönem Kapatma / Arşivleme (2026-09-16):
      'donemler', 'donem_sube_durumlari', 'devir_checkpoint',
      'stok_kapanis_snapshot', 'cari_kapanis_snapshot',
      'kasa_kapanis_snapshot', 'banka_kapanis_snapshot',
      'donem_kilit', // çoklu cihaz kilidi (2026-09-21, FAZ 4)
    };
    final conflict = globalIdTablosu.contains(tablo)
        ? ConflictAlgorithm.replace
        : ConflictAlgorithm.ignore;

    await _cakismaKorumasiUygula(database, tablo, kayitlar);

    await database.execute('PRAGMA foreign_keys = OFF');
    // 🔴🔴 KRİTİK DÜZELTME (derin denetimde bulundu): `batch.commit(...,
    // continueOnError: true)` bir satır eklerken hata verirse SESSİZCE
    // atlıyordu — bu fonksiyon hiçbir istisna fırlatmadan normal dönüyordu.
    // Çağıran taraf (supabase_sync_servisi.dart._buluttanAlCalistir),
    // "her şey başarıyla yazıldı" sanıp senkron filigranını (watermark)
    // çekilen TÜM kayıtların en büyük last_updated'ine ilerletiyordu.
    // Sonuç: atlanan satır bu cihazda KALICI OLARAK kayboluyordu — bir
    // daha hiçbir zaman "last_updated > filigran" sorgusuna dahil
    // olmuyordu, senkron ekranı ise "başarılı" diyordu. Push tarafında
    // (aynı dosya, ~satır 1133) kısmi hatada filigranın İLERLETİLMEDİĞİ
    // zaten doğru yapılmış — pull tarafında bu koruma hiç yoktu.
    // Artık her satır TEK TEK denenip başarısız olanlar sayılıyor; en az
    // bir satır başarısız olursa fonksiyon istisna fırlatıyor (iyi
    // giden satırlar yine de yazılmış olarak kalır — eski dayanıklılık
    // korunuyor) — bu istisna _buluttanAlCalistir'in try/catch'ine düşer,
    // filigran o tablo için İLERLEMEZ, başarısız satır BİR SONRAKİ
    // senkronda tekrar çekilip denenir.
    var basarisizSayisi = 0;
    try {
      for (final kayit in kayitlar) {
        final temiz = Map<String, dynamic>.from(kayit);
        temiz.remove('id');
        temiz.removeWhere((_, v) => v == null);
        try {
          await database.insert(tablo, temiz, conflictAlgorithm: conflict);
        } catch (e) {
          basarisizSayisi++;
          if (kDebugMode) {
            debugPrint('supaKayitlariEkle ($tablo) satır hatası: $e');
          }
        }
      }
    } finally {
      await database.execute('PRAGMA foreign_keys = ON');
    }
    if (basarisizSayisi > 0) {
      throw Exception(
          '$tablo: $basarisizSayisi/${kayitlar.length} kayıt yazılamadı');
    }
  }

  /// Mevcut kayıtları güncelle (Supabase'den gelen)
  Future<void> supaKayitlariGuncelle(
    String tablo,
    List<Map<String, dynamic>> kayitlar,
  ) async {
    if (kayitlar.isEmpty) return;
    final database = await db;
    await _cakismaKorumasiUygula(database, tablo, kayitlar);
    await database.execute('PRAGMA foreign_keys = OFF');
    int atlanan = 0;
    try {
      for (final kayit in kayitlar) {
        final temiz = Map<String, dynamic>.from(kayit);
        temiz.remove('id');
        temiz.removeWhere((_, v) => v == null);
        if (temiz.containsKey('global_id') && temiz['global_id'] != null) {
          // 🔴🔴 GENELLEŞTİRİLMİŞ ÇAKIŞMA KORUMASI (kullanıcı isteği:
          // "tam ERP sistemi — internetsiz gelip bulutsuz çalışıp sonra
          // senkron olsun, hiçbir tabloda veri kaybı olmasın"):
          // ÖNCEDEN bu koruma SADECE 'urunler' fiyat alanları içindi —
          // diğer TÜM tablolarda gelen bulut kaydı yerel kaydın
          // TAMAMININ üzerine körü körüne yazılıyordu. Artık HER
          // TABLODA, HER KAYIT için: yerel last_updated, gelen bulut
          // kaydından DAHA YENİYSE, o kayıt TAMAMEN ATLANIYOR (yerel,
          // henüz gönderilmemiş değişiklik korunuyor).
          final mevcut = await database.query(tablo,
              where: 'global_id = ?', whereArgs: [temiz['global_id']], limit: 1);
          if (mevcut.isNotEmpty) {
            final yerelSatir = mevcut.first;
            final yerelStr = yerelSatir['last_updated']?.toString();
            final gelenStr = temiz['last_updated']?.toString();
            final yerelZaman = yerelStr != null ? DateTime.tryParse(yerelStr) : null;
            final gelenZaman = gelenStr != null ? DateTime.tryParse(gelenStr) : null;
            if (yerelZaman != null && gelenZaman != null &&
                yerelZaman.isAfter(gelenZaman)) {
              atlanan++;
              continue;
            }
            // 🆕 SYNC ÇAKIŞMASI KAYDI (protokol §12): Üzerine yazmadan ÖNCE,
            // yerel ve gelen satır arasında (metadata dışı) gerçek bir alan
            // farkı varsa çakışma tablosuna düşülüyor.
            // 🔴 FAZ 3 (madde 4, 2026-09-21, kullanıcı onaylı mimari
            // karar): "master veri" (urunler, cari vb.) için davranış
            // DEĞİŞMEDİ — LWW ile gelen kazanır. Ama "işlem verisi"
            // (satış/stok/kasa/banka hareketi vb. — bkz. SyncCakismaTespit.
            // islemTablolari dosya başı gerekçesi) için GERÇEK bir
            // çakışma tespit edilirse artık otomatik üzerine YAZILMAZ —
            // yerel kayıt korunur, kullanıcı "Sync Çakışmaları"
            // ekranından bilinçli olarak karar verir.
            final gercekCakisma = await _cakismaKaydetGerekirse(
                database, tablo, yerelSatir, temiz);
            if (gercekCakisma && SyncCakismaTespit.islemVerisiMi(tablo)) {
              atlanan++;
              continue;
            }
          }
          await database.update(
            tablo,
            temiz,
            where: 'global_id = ?',
            whereArgs: [temiz['global_id']],
          );
        }
      }
      if (atlanan > 0 && kDebugMode) {
        debugPrint('supaKayitlariGuncelle ($tablo): $atlanan kayıt atlandı '
            '(yerel değişiklik daha yeniydi, korundu)');
      }
    } finally {
      await database.execute('PRAGMA foreign_keys = ON');
    }
  }

  /// Toplu UPSERT (ekle veya güncelle) - Tek metodla her şey
  // ⚠️ NOT: Bu fonksiyon projede HİÇBİR YERDEN ÇAĞRILMIYOR (ölü kod).
  // Aktif senkron yolu BulutManager.upsert() + buluttanAl()'dır.
  Future<void> supaKayitlariUpsert(
    String tablo,
    List<Map<String, dynamic>> kayitlar,
  ) async {
    if (kayitlar.isEmpty) return;
    final database = await db;
    
    const globalIdTablosu = {
      'urunler', 'lot_seri', 'cari', 'satislar', 'iade',
      'promosyonlar', 'promosyon_tanim', 'tedarikci_siparisler',
      'giderler', 'kasa_hareketleri', 'vardiyalar',
      'faturalar', 'fatura_detaylari', 'personel', 'musteri_puan',
      'masalar', 'masa_siparisleri', 'masa_siparis_kalem',
    };
    
    final conflict = globalIdTablosu.contains(tablo)
        ? ConflictAlgorithm.replace
        : ConflictAlgorithm.ignore;

    final batch = database.batch();
    for (final kayit in kayitlar) {
      final temiz = Map<String, dynamic>.from(kayit);
      temiz.remove('id');
      temiz.removeWhere((_, v) => v == null);
      batch.insert(tablo, temiz, conflictAlgorithm: conflict);
    }
    await batch.commit(noResult: true, continueOnError: true);
  }

  /// Soft delete: is_deleted=1 olan kayıtları işaretler
  Future<void> supaKayitlariSoftDelete(String tablo, List<int> ids) async {
    if (ids.isEmpty) return;
    final database = await db;
    final placeholders = ids.map((_) => '?').join(',');
    await database.rawUpdate(
      'UPDATE $tablo SET is_deleted = 1, last_updated = ? WHERE id IN ($placeholders)',
      [DateTime.now().toIso8601String(), ...ids],
    );
  }

  /// Global ID ile soft delete
  Future<void> supaKayitlariSoftDeleteByGlobalId(String tablo, List<String> globalIds) async {
    if (globalIds.isEmpty) return;
    final database = await db;
    final placeholders = globalIds.map((_) => '?').join(',');
    await database.rawUpdate(
      'UPDATE $tablo SET is_deleted = 1, last_updated = ? WHERE global_id IN ($placeholders)',
      [DateTime.now().toIso8601String(), ...globalIds],
    );
  }

  /// Tablodaki tüm kayıtları getir (senkronizasyon için)
  Future<List<Map<String, dynamic>>> supaLokalVerileriGetir(
    String tablo, {
    bool sadeceSilmemis = true,
  }) async {
    final database = await db;
    try {
      return await database.query(tablo);
    } catch (e) {
      return [];
    }
  }

  /// Lokal kayıt ekle (tek kayıt)
  Future<int> supaLokalKayitEkle(String tablo, Map<String, dynamic> kayit) async {
    final database = await db;
    final temiz = Map<String, dynamic>.from(kayit);
    temiz.remove('id');
    temiz.removeWhere((_, v) => v == null);
    return await database.insert(tablo, temiz);
  }

  /// Lokal kayıt güncelle (tek kayıt)
  Future<int> supaLokalKayitGuncelle(String tablo, Map<String, dynamic> kayit) async {
    final database = await db;
    final temiz = Map<String, dynamic>.from(kayit);
    temiz.remove('id');
    temiz.removeWhere((_, v) => v == null);
    
    if (temiz.containsKey('global_id') && temiz['global_id'] != null) {
      return await database.update(
        tablo,
        temiz,
        where: 'global_id = ?',
        whereArgs: [temiz['global_id']],
      );
    } else if (temiz.containsKey('id') && temiz['id'] != null) {
      return await database.update(
        tablo,
        temiz,
        where: 'id = ?',
        whereArgs: [temiz['id']],
      );
    }
    return 0;
  }

  /// Tablodaki tüm kayıtları sil (test için)
  Future<void> supaTabloyuTemizle(String tablo) async {
    final database = await db;
    await database.delete(tablo);
  }

  /// Son senkronizasyon zamanını al
  Future<DateTime?> supaSonSenkronZamani(String tablo) async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString('supabase_sync_$tablo');
    if (timeStr != null) {
      return DateTime.tryParse(timeStr);
    }
    return null;
  }

  /// Son senkronizasyon zamanını kaydet
  Future<void> supaSonSenkronZamaniKaydet(String tablo, DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('supabase_sync_$tablo', time.toIso8601String());
  }

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