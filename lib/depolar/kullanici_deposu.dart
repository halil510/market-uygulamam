// lib/depolar/kullanici_deposu.dart
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';
import '../modeller/kullanici_model.dart';
import '../cekirdek/utils/sifre_hash.dart';

class KullaniciDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Kullanıcı adı + DÜZ şifre ile giriş kontrolü yapar.
  /// - Kullanıcının tuzu (salt) varsa: yeni, güvenli (tuzlu+çok turlu)
  ///   şema ile doğrulanır.
  /// - Tuzu YOKSA (eski hesap): eski tuzsuz şemayla doğrulanır, EŞLEŞİRSE
  ///   kullanıcı fark etmeden otomatik olarak yeni, güvenli şemaya
  ///   yükseltilir (yeni tuz üretilip yeniden hashlenir ve kaydedilir).
  Future<KullaniciModel?> girisKontrol(
      String kullaniciAdi, String duzSifre) async {
    final db = await _d;
    final rows = await db.query(
      'kullanicilar',
      where: 'kullanici_adi = ? AND aktif = 1 AND is_deleted = 0',
      whereArgs: [kullaniciAdi],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final kayitliHash = row['sifre_hash'] as String?;
    final tuz = row['tuz'] as String?;
    if (kayitliHash == null) return null;

    if (tuz != null && tuz.isNotEmpty) {
      // Yeni, güvenli (tuzlu) şema
      final hesaplanan = SifreHash.hashleTuzlu(duzSifre, tuz);
      if (hesaplanan != kayitliHash) return null;
      return KullaniciModel.fromMap(row);
    }

    // Eski (tuzsuz) şema — doğrula, eşleşirse SESSİZCE yeni şemaya yükselt
    final eskiHesaplanan = SifreHash.eskiHashle(duzSifre);
    if (eskiHesaplanan != kayitliHash) return null;

    try {
      final yeniTuz = SifreHash.tuzUret();
      final yeniHash = SifreHash.hashleTuzlu(duzSifre, yeniTuz);
      // 🔴 DÜZELTME: last_updated bümlenmiyordu — sessiz şifre şeması
      // yükseltmesi diğer cihazlara hiç senkron olmuyordu.
      await db.update('kullanicilar',
          {'sifre_hash': yeniHash, 'tuz': yeniTuz, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [row['id']]);
      LogServisi().bilgi('Kullanıcı ${row['id']} şifresi güvenli tuzlu şemaya yükseltildi');
    } catch (e) {
      // Yükseltme başarısız olsa bile giriş engellenmemeli — bir sonraki
      // girişte tekrar denenir.
      LogServisi().hata('Kullanici.girisKontrol (tuz yükseltme)', hata: e);
    }
    return KullaniciModel.fromMap(row);
  }

  /// Şifresiz, sadece kullanıcı adına göre aktif kullanıcıyı getirir —
  /// biyometrik girişte kullanıcının şifresi hiç bilinmediği için
  /// girisKontrol() yerine bu kullanılır (biyometrik token doğrulaması
  /// ayrıca yapılır, bkz. BiyometrikDeposu).
  Future<KullaniciModel?> kullaniciAdiIleGetir(String kullaniciAdi) async {
    final db = await _d;
    final rows = await db.query(
      'kullanicilar',
      where: 'kullanici_adi = ? AND aktif = 1 AND is_deleted = 0',
      whereArgs: [kullaniciAdi],
    );
    if (rows.isEmpty) return null;
    return KullaniciModel.fromMap(rows.first);
  }

  /// Bir cari'ye (bayiye) bağlı, silinmemiş portal girişini getirir —
  /// Madde 2 mimari denetimi: cari_detay_ekrani.dart önceden bu sorguyu
  /// doğrudan kendisi çalıştırıyordu (bkz. _bayiGirisiYonet).
  Future<KullaniciModel?> bayiCariIleGetir(int cariId) async {
    final db = await _d;
    final rows = await db.query('kullanicilar',
        where: 'bayi_cari_id = ? AND is_deleted = 0', whereArgs: [cariId], limit: 1);
    if (rows.isEmpty) return null;
    return KullaniciModel.fromMap(rows.first);
  }

  Future<KullaniciModel?> idileGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.query('kullanicilar',
          where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
      if (rows.isEmpty) return null;
      return KullaniciModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('Kullanici.idileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<KullaniciModel>> tumunuGetir() async {
    try {
      final db = await _d;
      final rows = await db.query('kullanicilar',
          where: 'is_deleted = 0', orderBy: 'ad_soyad');
      return rows.map(KullaniciModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Kullanici.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<int> ekle(KullaniciModel k) async {
    try {
      final db = await _d;
      final m = k.toMap();
      m.remove('id');
      m['last_updated'] ??= DateTime.now().toIso8601String();
      final yeniId = await db.insert('kullanicilar', m);
      // 🔴 DÜZELTME: yeni kullanıcı önceden hiç buluta bildirilmiyordu.
      final guncelSatir = await db.query('kullanicilar', where: 'id = ?', whereArgs: [yeniId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('kullanicilar', Map<String, dynamic>.from(guncelSatir.first));
      }
      return yeniId;
    } catch (e, st) {
      LogServisi().hata('Kullanici.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> guncelle(KullaniciModel k) async {
    try {
      if (k.id == null) return;
      final db = await _d;
      final m = k.toMap();
      m.remove('id'); // id where clause'da zaten var — map'ten çıkar
      // 🔴 DÜZELTME: last_updated bümlenmiyordu — kullanıcı bilgisi
      // değişikliği (ad, yetki, aktiflik vb.) diğer cihazlara hiç
      // gitmiyordu.
      m['last_updated'] = DateTime.now().toIso8601String();
      await db.update('kullanicilar', m,
          where: 'id = ?', whereArgs: [k.id]);
      final guncelSatir = await db.query('kullanicilar', where: 'id = ?', whereArgs: [k.id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('kullanicilar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Kullanici.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sil(int id) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      // 🔴🔴 ÖNEMLİ DÜZELTME: silinen (deaktif edilen) bir kullanıcı,
      // last_updated bümlenmediği için diğer cihazlara hiç
      // bildirilmiyordu — o cihazlarda bu kullanıcı SİLİNMEMİŞ gibi
      // giriş yapabilir durumda kalmaya devam ederdi (güvenlik riski).
      await db.update('kullanicilar', {'is_deleted': 1, 'last_updated': now},
          where: 'id = ?', whereArgs: [id]);
      final guncelSatir = await db.query('kullanicilar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('kullanicilar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Kullanici.sil', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Kullanıcının şifresini DÜZ yeni şifre ile değiştirir — her şifre
  /// değişikliğinde YENİ bir tuz üretilip yeniden hashlenir.
  Future<void> sifreDegistir(int id, String yeniDuzSifre) async {
    try {
      final db = await _d;
      final yeniTuz = SifreHash.tuzUret();
      final yeniHash = SifreHash.hashleTuzlu(yeniDuzSifre, yeniTuz);
      final now = DateTime.now().toIso8601String();
      // 🔴 DÜZELTME: last_updated bümlenmiyordu — şifre değişikliği
      // diğer cihazlara hiç senkron olmuyordu; o cihazlarda kullanıcı
      // ESKİ şifreyle giriş yapmaya devam edebilirdi.
      await db.update(
        'kullanicilar',
        {'sifre_hash': yeniHash, 'tuz': yeniTuz, 'last_updated': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      final guncelSatir = await db.query('kullanicilar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('kullanicilar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Kullanici.sifreDegistir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sonGirisGuncelle(int id) async {
    try {
      final db = await _d;
      // NOT: Kasıtlı olarak BulutManager().upsert() ÇAĞRILMIYOR — her
      // girişte hassas alanları (şifre_hash, tuz dahil) tüm satırı
      // buluta göndermek hem gereksiz trafik hem de güvenlik açısından
      // dikkatli olunması gereken bir durum. last_updated yine de
      // bümleniyor ki bu kayıt bir sonraki TAM senkronda (manuel
      // "Buluta Gönder") normal şekilde yakalansın.
      final now = DateTime.now().toIso8601String();
      await db.update(
        'kullanicilar',
        {'son_giris': now, 'last_updated': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      LogServisi().hata('Kullanici.sonGirisGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Kullanıcıya ait yetki kodlarını döndürür
  Future<Set<String>> yetkileriniGetir(int kullaniciId) async {
    try {
      final db = await _d;
      final rows = await db.query(
        'roller_yetki',
        columns: ['yetki_kodu'],
        where: 'kullanici_id = ?',
        whereArgs: [kullaniciId],
      );
      return rows.map((r) => r['yetki_kodu'] as String).toSet();
    } catch (e, st) {
      LogServisi().hata('Kullanici.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Yetkileri transaction ile kaydet — önce temizle, sonra ekle.
  ///
  /// 🔴🔴 KOMPLE DERİN ANALİZ — mimari borç pilot düzeltmesi: bu metod
  /// ÖNCEDEN gerçekten var ama HİÇBİR YERDEN ÇAĞRILMIYORDU (dead code) —
  /// `kullanici_ekle_ekrani.dart` bunun yerine KENDİ private kopyasını
  /// (`_yetkileriKaydet`) kullanıyordu; UI katmanında `Veritabani().db`'ye
  /// doğrudan erişen 44 dosyadan biriydi. O kopya, bu depo metodunun
  /// EKSİK bıraktığı iki şeyi ZATEN doğru yapıyordu: `global_id`/
  /// `created_at`/`last_updated` sütunlarını dolduruyordu VE her satırı
  /// `BulutManager().upsert()` ile senkronluyordu (roller_yetki daha önce
  /// senkron sisteminde HİÇ yoktu — bir yöneticinin verdiği özel yetki
  /// başka bir terminalde hiç görünmüyordu). Bu depo metodu, ekrandaki
  /// doğru mantıkla değiştirildi ve ekran artık BUNU çağırıyor —
  /// SCREEN→REPOSITORY hedef mimarisine uygun, davranış AYNEN korundu.
  Future<void> yetkileriKaydet(
      int kullaniciId, Set<String> yetkiler) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final gidler = <String>[];
    await db.transaction((txn) async {
      await txn.delete('roller_yetki',
          where: 'kullanici_id = ?', whereArgs: [kullaniciId]);
      for (final yetki in yetkiler) {
        final gid = const Uuid().v4();
        gidler.add(gid);
        await txn.insert(
          'roller_yetki',
          {
            'kullanici_id': kullaniciId,
            'yetki_kodu': yetki,
            'created_at': now,
            'global_id': gid,
            'last_updated': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    try {
      for (final gid in gidler) {
        final satir = await db.query('roller_yetki',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (satir.isNotEmpty) {
          BulutManager().upsert('roller_yetki', Map<String, dynamic>.from(satir.first));
        }
      }
    } catch (e) {
      LogServisi().hata('Kullanici.yetkileriKaydet (bulut bildirimi)', hata: e);
    }
  }
}
