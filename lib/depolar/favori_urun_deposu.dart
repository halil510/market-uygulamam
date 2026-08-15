// lib/depolar/favori_urun_deposu.dart
//
// 🆕 YENİ MODÜL — HIZLI TUŞ (FAVORİ ÜRÜN)
//
// DERİN ANALİZ BULGUSU: `favori_urunler` tablosu şemada (urun_semasi.dart)
// ve migrasyon zincirinde ZATEN vardı, hatta global_id kolonu bile
// eklenmişti — ama projede bu tabloya dokunan TEK BİR SATIR KOD YOKTU.
// Tablo boş duruyordu.
//
// Bir markette barkodsuz satılan ürünler (ekmek, poşet, çay, gazete,
// sigara, su) kasiyerin en sık dokunduğu kalemlerdir. Şu ana kadar
// bunları satmak için PLU ekranını açıp aramak gerekiyordu. Profesyonel
// POS sistemlerinde (Barkomatik, BarkoPOS, Nebim) bunun için "hızlı tuş"
// paneli bulunur.
//
// Bu depo o paneli besler.
import 'package:sqflite/sqflite.dart';
import '../veri/database/veritabani.dart';
import '../modeller/urun_model.dart';
import '../servisler/auth_servisi.dart';

class FavoriUrunDeposu {
  static final FavoriUrunDeposu _instance = FavoriUrunDeposu._internal();
  factory FavoriUrunDeposu() => _instance;
  FavoriUrunDeposu._internal();

  Future<Database> get _d async => Veritabani().db;

  /// Aktif kullanıcının id'si. Oturum yoksa 0 döner — bu durumda
  /// favoriler "ortak/varsayılan" kullanıcı altında tutulur, böylece
  /// kilitli ekrandan gelen durumlarda da panel boş kalmaz.
  int get _kullaniciId => AuthServisi().aktifKullanici?.id ?? 0;

  // ── OKUMA ──────────────────────────────────────────────────────────────

  /// Hızlı tuş panelinde gösterilecek ürünler, kullanıcının belirlediği
  /// sırayla. Silinmiş/pasif ürünler otomatik elenir (favori kaydı
  /// dururken ürün silinmişse panelde hayalet tuş görünmesin).
  Future<List<UrunModel>> favorileriGetir({int? kullaniciId}) async {
    final db  = await _d;
    final kid = kullaniciId ?? _kullaniciId;
    final rows = await db.rawQuery('''
      SELECT u.* FROM favori_urunler f
      INNER JOIN urunler u ON u.id = f.urun_id
      WHERE f.kullanici_id = ?
        AND u.is_deleted = 0
        AND u.aktif = 1
      ORDER BY f.sira ASC, u.urun_adi ASC
    ''', [kid]);
    return rows.map(UrunModel.fromMap).toList();
  }

  /// Bir ürünün favoride olup olmadığı — ürün detay ekranındaki
  /// yıldız ikonunun durumu için.
  Future<bool> favoriMi(int urunId, {int? kullaniciId}) async {
    final db  = await _d;
    final kid = kullaniciId ?? _kullaniciId;
    final r = await db.query('favori_urunler',
        columns: ['id'],
        where: 'kullanici_id = ? AND urun_id = ?',
        whereArgs: [kid, urunId],
        limit: 1);
    return r.isNotEmpty;
  }

  Future<Set<int>> favoriIdleri({int? kullaniciId}) async {
    final db  = await _d;
    final kid = kullaniciId ?? _kullaniciId;
    final r = await db.query('favori_urunler',
        columns: ['urun_id'], where: 'kullanici_id = ?', whereArgs: [kid]);
    return r.map((e) => e['urun_id'] as int).toSet();
  }

  Future<int> favoriSayisi({int? kullaniciId}) async {
    final db  = await _d;
    final kid = kullaniciId ?? _kullaniciId;
    final r = await db.rawQuery(
        'SELECT COUNT(*) c FROM favori_urunler WHERE kullanici_id = ?', [kid]);
    return (r.first['c'] as int?) ?? 0;
  }

  // ── YAZMA ──────────────────────────────────────────────────────────────

  /// Favoriye ekler. Zaten varsa hiçbir şey yapmaz (UNIQUE kısıtı
  /// nedeniyle ConflictAlgorithm.ignore kullanılıyor — hata fırlatmaz).
  Future<void> ekle(int urunId, {int? kullaniciId}) async {
    final db  = await _d;
    final kid = kullaniciId ?? _kullaniciId;
    // Yeni ürün listenin SONUNA eklenir
    final r = await db.rawQuery(
        'SELECT COALESCE(MAX(sira), -1) + 1 AS s '
        'FROM favori_urunler WHERE kullanici_id = ?', [kid]);
    final sira = (r.first['s'] as int?) ?? 0;
    await db.insert(
      'favori_urunler',
      {'kullanici_id': kid, 'urun_id': urunId, 'sira': sira},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> cikar(int urunId, {int? kullaniciId}) async {
    final db  = await _d;
    final kid = kullaniciId ?? _kullaniciId;
    await db.delete('favori_urunler',
        where: 'kullanici_id = ? AND urun_id = ?', whereArgs: [kid, urunId]);
  }

  /// Yıldız ikonu için — favorideyse çıkarır, değilse ekler.
  /// Dönüş: işlem sonrası favoride mi?
  Future<bool> degistir(int urunId, {int? kullaniciId}) async {
    final varMi = await favoriMi(urunId, kullaniciId: kullaniciId);
    if (varMi) {
      await cikar(urunId, kullaniciId: kullaniciId);
      return false;
    }
    await ekle(urunId, kullaniciId: kullaniciId);
    return true;
  }

  /// Sürükle-bırak ile yeniden sıralama sonrası çağrılır.
  /// [sirali] listesi, ürün id'lerini yeni sırasıyla içerir.
  /// Tek transaction'da yazılır — yarım kalmış sıralama oluşmaz.
  Future<void> sirayiKaydet(List<int> sirali, {int? kullaniciId}) async {
    final db  = await _d;
    final kid = kullaniciId ?? _kullaniciId;
    await db.transaction((txn) async {
      for (var i = 0; i < sirali.length; i++) {
        await txn.update('favori_urunler', {'sira': i},
            where: 'kullanici_id = ? AND urun_id = ?',
            whereArgs: [kid, sirali[i]]);
      }
    });
  }

  /// Yönetim ekranındaki "kaydet" için — seçilen id kümesini tek
  /// seferde uygular (eksikleri ekler, çıkarılanları siler).
  Future<void> secimleriKaydet(Set<int> secilen, {int? kullaniciId}) async {
    final db  = await _d;
    final kid = kullaniciId ?? _kullaniciId;
    final mevcut = await favoriIdleri(kullaniciId: kid);

    final eklenecek = secilen.difference(mevcut);
    final silinecek = mevcut.difference(secilen);
    if (eklenecek.isEmpty && silinecek.isEmpty) return;

    final r = await db.rawQuery(
        'SELECT COALESCE(MAX(sira), -1) + 1 AS s '
        'FROM favori_urunler WHERE kullanici_id = ?', [kid]);
    var sira = (r.first['s'] as int?) ?? 0;

    await db.transaction((txn) async {
      for (final id in silinecek) {
        await txn.delete('favori_urunler',
            where: 'kullanici_id = ? AND urun_id = ?', whereArgs: [kid, id]);
      }
      for (final id in eklenecek) {
        await txn.insert(
          'favori_urunler',
          {'kullanici_id': kid, 'urun_id': id, 'sira': sira++},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// İlk kurulumda / panel boşken öneri: en çok satılan ürünlerden
  /// otomatik favori listesi kurar. Kullanıcıya "başlangıç için
  /// doldurayım mı?" diye sorulduğunda kullanılır.
  Future<List<UrunModel>> encokSatilanOneri({int limit = 12}) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT u.*, SUM(sk.miktar) AS toplam
      FROM satis_kalem sk
      INNER JOIN urunler u ON u.id = sk.urun_id
      WHERE u.is_deleted = 0 AND u.aktif = 1
      GROUP BY sk.urun_id
      ORDER BY toplam DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(UrunModel.fromMap).toList();
  }
}
