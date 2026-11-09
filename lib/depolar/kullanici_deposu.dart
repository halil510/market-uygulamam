// lib/depolar/kullanici_deposu.dart
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';
import '../modeller/kullanici_model.dart';
import '../cekirdek/utils/sifre_hash.dart';
import '../servisler/auth_servisi.dart';

/// Kaldırılmış yetki satırının ön eki ('-kasa') — bkz. yetkileriKaydet.
const String _pasifOnEk = '-';

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

  // ── Admin hesabı koruması (derin denetim 2026-11-09, #21) ─────────────
  // 'kullanici' yetkisi verilmiş admin OLMAYAN biri admin hesabının
  // şifresini sıfırlayıp onunla girebiliyor, admini düşürebiliyor ya da
  // kendine tüm yetkileri verebiliyordu (ekrandaki tek koruma yalnız admin
  // rolü atamayı engelliyordu). Kural depoda: her yoldan geçerli. Oturum
  // yokken (kurulum/sistem akışı) eski davranış sürer.

  static bool get _yoneticiDegilOturumVar =>
      AuthServisi().aktifKullanici != null && !AuthServisi().isAdmin;

  Future<void> _adminHesabiniKoru(DatabaseExecutor db, int hedefId) async {
    if (!_yoneticiDegilOturumVar) return;
    final r = await db.query('kullanicilar',
        columns: ['rol'], where: 'id = ?', whereArgs: [hedefId], limit: 1);
    if (r.isNotEmpty && r.first['rol'] == 'admin') {
      throw Exception('Admin hesabı yalnız bir admin tarafından değiştirilebilir');
    }
  }

  void _adminAtamasiniKoru(String? rol) {
    if (rol == 'admin' && _yoneticiDegilOturumVar) {
      throw Exception('Sadece admin, başka bir hesaba admin rolü atayabilir');
    }
  }

  Future<int> ekle(KullaniciModel k) async {
    try {
      _adminAtamasiniKoru(k.rol);
      final db = await _d;
      final m = k.toMap();
      m.remove('id');
      m['last_updated'] ??= DateTime.now().toIso8601String();
      final yeniId = await db.insert('kullanicilar', m);
      // 🔴 DÜZELTME: yeni kullanıcı önceden hiç buluta bildirilmiyordu.
      await BulutManager().satiriBildir(db, 'kullanicilar', yeniId);
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
      await _adminHesabiniKoru(db, k.id!);
      _adminAtamasiniKoru(k.rol);
      final m = k.toMap();
      m.remove('id'); // id where clause'da zaten var — map'ten çıkar
      // 🔴 DÜZELTME: last_updated bümlenmiyordu — kullanıcı bilgisi
      // değişikliği (ad, yetki, aktiflik vb.) diğer cihazlara hiç
      // gitmiyordu.
      m['last_updated'] = DateTime.now().toIso8601String();
      await db.update('kullanicilar', m,
          where: 'id = ?', whereArgs: [k.id]);
      await BulutManager().satiriBildir(db, 'kullanicilar', k.id);
    } catch (e, st) {
      LogServisi().hata('Kullanici.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sil(int id) async {
    try {
      final db = await _d;
      await _adminHesabiniKoru(db, id);
      final now = DateTime.now().toIso8601String();
      // 🔴🔴 ÖNEMLİ DÜZELTME: silinen (deaktif edilen) bir kullanıcı,
      // last_updated bümlenmediği için diğer cihazlara hiç
      // bildirilmiyordu — o cihazlarda bu kullanıcı SİLİNMEMİŞ gibi
      // giriş yapabilir durumda kalmaya devam ederdi (güvenlik riski).
      await db.update('kullanicilar', {'is_deleted': 1, 'last_updated': now},
          where: 'id = ?', whereArgs: [id]);
      await BulutManager().satiriBildir(db, 'kullanicilar', id);
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
      await _adminHesabiniKoru(db, id);
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
      await BulutManager().satiriBildir(db, 'kullanicilar', id);
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
      // '-kod' = kaldırılmış yetki (bkz. yetkileriKaydet) — sayılmaz.
      return rows
          .map((r) => r['yetki_kodu'] as String)
          .where((k) => !k.startsWith(_pasifOnEk))
          .toSet();
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
  ///
  /// 🔴 DERİN DENETİM (2026-11-09, #22): ÖNCEDEN tüm satırlar SİLİNİP yeni
  /// global_id'lerle yeniden yazılıyordu — kaldırılan yetkinin buluttaki
  /// satırı hiç silinmiyor, diğer kasalarda yetki kalıyor, "Tam Al"da aynı
  /// cihazda bile geri geliyordu (silme izi taşıyacak sütun yok). Artık
  /// fark yazılır, satırların kimliği korunur: kaldırılan yetki '-kod'
  /// yapılır (normal güncelleme olarak her cihaza gider; yetki kontrolü bu
  /// kodu eşlemez), tekrar verilen '-kod' satırı geri 'kod' olur.
  /// #21: admin olmayan biri admin hesabının yetkilerine dokunamaz ve
  /// başkasına KENDİNDE olmayan yetkiyi veremez.
  Future<void> yetkileriKaydet(
      int kullaniciId, Set<String> yetkiler) async {
    final db = await _d;
    await _adminHesabiniKoru(db, kullaniciId);
    final now = DateTime.now().toIso8601String();
    final gidler = <String>[];
    await db.transaction((txn) async {
      final mevcut = await txn.query('roller_yetki',
          where: 'kullanici_id = ?', whereArgs: [kullaniciId]);
      final aktif = <String, Map<String, Object?>>{};
      final pasif = <String, Map<String, Object?>>{};
      for (final r in mevcut) {
        final kod = r['yetki_kodu'] as String;
        if (kod.startsWith(_pasifOnEk)) {
          pasif[kod.substring(_pasifOnEk.length)] = r;
        } else {
          aktif[kod] = r;
        }
      }
      if (_yoneticiDegilOturumVar) {
        final yeniVerilen = yetkiler.difference(aktif.keys.toSet());
        final yetkisiz = yeniVerilen.where((k) => !AuthServisi().yetkiVarSync(k)).toList();
        if (yetkisiz.isNotEmpty) {
          throw Exception('Kendinizde olmayan yetkiyi veremezsiniz: ${yetkisiz.join(', ')}');
        }
      }

      Future<void> guncelle(Map<String, Object?> satir, String yeniKod) async {
        var gid = satir['global_id'] as String?;
        if (gid == null || gid.isEmpty) gid = const Uuid().v4();
        await txn.update('roller_yetki',
            {'yetki_kodu': yeniKod, 'global_id': gid, 'last_updated': now},
            where: 'id = ?', whereArgs: [satir['id']]);
        gidler.add(gid);
      }

      // Kaldırılan yetkiler → pasif ('-kod').
      for (final e in aktif.entries) {
        if (yetkiler.contains(e.key)) continue;
        final eskiPasif = pasif.remove(e.key);
        if (eskiPasif != null) {
          // Aynı kodun eski pasif kopyası varsa (UNIQUE) yerelden kaldırılır;
          // buluttaki karşılığı zaten pasif, zararsız.
          await txn.delete('roller_yetki', where: 'id = ?', whereArgs: [eskiPasif['id']]);
        }
        await guncelle(e.value, '$_pasifOnEk${e.key}');
      }
      // Verilen yetkiler: aktif varsa dokunma; pasif varsa geri aç; yoksa ekle.
      for (final yetki in yetkiler) {
        if (aktif.containsKey(yetki)) continue;
        final p = pasif[yetki];
        if (p != null) {
          await guncelle(p, yetki);
          continue;
        }
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
