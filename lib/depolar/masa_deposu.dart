// lib/depolar/masa_deposu.dart
// Masa / Restoran modülü repository.
// Tek sorumluluk: masalar, masa_siparisleri, masa_siparis_kalem tablolarına erişim.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../modeller/masa_model.dart';
import '../modeller/masa_siparis_model.dart';
import '../modeller/masa_siparis_kalem_model.dart';

class MasaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Tüm açık siparişleri (tüm masalardan), kalemleriyle birlikte getirir.
  /// Mutfak/Bar ekranı bu metodu kullanır.
  Future<List<MasaSiparisModel>> tumAcikSiparisler() async {
    final db = await _d;
    final siparisler = await db.query(DbSabitler.masaSiparisleri,
        where: 'durum = ? AND is_deleted = 0', whereArgs: ['acik'],
        orderBy: 'acilis_zamani ASC');

    final sonuc = <MasaSiparisModel>[];
    for (final s in siparisler) {
      final kalemRows = await db.query(DbSabitler.masaSiparisKalem,
          where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [s['id']], orderBy: 'id ASC');
      final kalemler = kalemRows.map(MasaSiparisKalemModel.fromMap).toList();
      sonuc.add(MasaSiparisModel.fromMap(s, kalemler: kalemler));
    }
    return sonuc;
  }

  /// Masa adını id ile getirir (mutfak ekranında gösterim için).
  Future<Map<int, String>> masaAdlariHaritasi() async {
    final db = await _d;
    final rows = await db.query(DbSabitler.masalar, columns: ['id', 'ad']);
    return {for (final r in rows) r['id'] as int: r['ad'] as String};
  }

  // ── Masalar ──────────────────────────────────────────────────────────────

  /// Tüm masaları, varsa açık siparişlerinin toplamı/zamanı ile birlikte getirir.
  Future<List<MasaModel>> masalariGetir() async {
    final db = await _d;
    final masalar = await db.query(DbSabitler.masalar,
        where: 'is_deleted = 0', orderBy: 'sira ASC, ad ASC');

    final acikSiparisler = await db.query(DbSabitler.masaSiparisleri,
        where: 'durum = ? AND is_deleted = 0', whereArgs: ['acik']);

    final sonuc = <MasaModel>[];
    for (final m in masalar) {
      final masa = MasaModel.fromMap(m);
      final siparis = acikSiparisler.where((s) => s['masa_id'] == m['id']).toList();
      if (siparis.isEmpty) { sonuc.add(masa); continue; }

      final s = siparis.first;
      final kalemler = await db.query(DbSabitler.masaSiparisKalem,
          where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [s['id']],
          orderBy: 'id ASC');
      final toplam = kalemler.fold<double>(0.0, (acc, k) =>
          acc + (k['miktar'] as num).toDouble() * (k['birim_fiyat'] as num).toDouble());

      String? ozet;
      if (kalemler.isNotEmpty) {
        final adlar = kalemler.map((k) => k['urun_adi'] as String).toList();
        ozet = adlar.length <= 2
            ? adlar.join(', ')
            : '${adlar.take(2).join(', ')} +${adlar.length - 2}';
      }

      sonuc.add(masa.copyWith(
        aktifSiparisId: s['id'] as int,
        aktifToplam: toplam,
        aktifOzet: ozet,
        acilisZamani: DateTime.tryParse(s['acilis_zamani']?.toString() ?? ''),
      ));
    }
    return sonuc;
  }

  Future<int> masaEkle(MasaModel masa) async {
    final db = await _d;
    final m = masa.toMap();
    m['global_id'] = const Uuid().v4();
    m['last_updated'] = DateTime.now().toIso8601String();
    final id = await db.insert(DbSabitler.masalar, m);
    // 🔴 Derin analizde bulundu: MasaDeposu'ndaki 12 fonksiyondan
    // SADECE BİRİ (masaGuncelle) BulutManager çağırıyordu — masa
    // açma/sipariş/kapatma gibi restoran modülünün EN SIK kullanılan
    // işlemleri hiç otomatik senkron olmuyordu.
    final satir = await db.query(DbSabitler.masalar, where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masalar', Map<String, dynamic>.from(satir.first));
    return id;
  }

  /// "10 masa ekle" gibi toplu masa oluşturma — her biri kalıcı, ayrı bir
  /// satır olarak `masalar` tablosuna yazılır (sabit kalırlar).
  /// Örn: onek='Salon', adet=10, baslangic=1 → "Salon 1".."Salon 10"
  Future<void> topluMasaEkle({
    required String onek,
    required int adet,
    required String kategori,
    int kapasite = 4,
    int baslangic = 1,
  }) async {
    final db = await _d;
    // Mevcut en yüksek sira değerinden devam et — sıralama bozulmasın
    final maxSira = await db.rawQuery('SELECT MAX(sira) as m FROM ${DbSabitler.masalar}');
    int sira = (maxSira.first['m'] as int?) ?? 0;

    final gidler = <String>[];
    final batch = db.batch();
    for (var i = 0; i < adet; i++) {
      sira++;
      final gid = const Uuid().v4();
      gidler.add(gid);
      batch.insert(DbSabitler.masalar, {
        'global_id': gid,
        'ad': '$onek ${baslangic + i}',
        'kategori': kategori,
        'kapasite': kapasite,
        'durum': 'bos',
        'sira': sira,
        'last_updated': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
    for (final gid in gidler) {
      final satir = await db.query(DbSabitler.masalar, where: 'global_id = ?', whereArgs: [gid], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('masalar', Map<String, dynamic>.from(satir.first));
    }
  }

  Future<void> masaGuncelle(MasaModel masa) async {
    final db = await _d;
    await db.update(DbSabitler.masalar, masa.toMap(),
        where: 'id = ?', whereArgs: [masa.id]);
    final guncelSatir = await db.query(DbSabitler.masalar, where: 'id = ?', whereArgs: [masa.id], limit: 1);
    if (guncelSatir.isNotEmpty) {
      BulutManager().upsert('masalar', Map<String, dynamic>.from(guncelSatir.first));
    }
  }

  Future<void> masaSil(int id) async {
    final db = await _d;
    // Açık siparişi varsa silmeye izin verme
    final acik = await db.query(DbSabitler.masaSiparisleri,
        where: 'masa_id = ? AND durum = ? AND is_deleted = 0', whereArgs: [id, 'acik']);
    if (acik.isNotEmpty) {
      throw Exception('Bu masada açık bir hesap var, önce kapatın.');
    }
    await db.update(DbSabitler.masalar,
        {'is_deleted': 1, 'last_updated': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
    final satir = await db.query(DbSabitler.masalar, where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masalar', Map<String, dynamic>.from(satir.first));
  }

  Future<void> masaDurumGuncelle(int id, String durum) async {
    final db = await _d;
    await db.update(DbSabitler.masalar,
        {'durum': durum, 'last_updated': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
    // 🔴 Bu fonksiyon EN SIK çağrılanlardan biri (masa boş/dolu/rezerve
    // her değiştiğinde) — BulutManager hiç çağrılmıyordu.
    final satir = await db.query(DbSabitler.masalar, where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masalar', Map<String, dynamic>.from(satir.first));
  }

  // ── Siparişler ───────────────────────────────────────────────────────────

  /// Masanın açık siparişini (varsa kalemleriyle) getirir.
  Future<MasaSiparisModel?> acikSiparisGetir(int masaId) async {
    final db = await _d;
    final rows = await db.query(DbSabitler.masaSiparisleri,
        where: 'masa_id = ? AND durum = ? AND is_deleted = 0',
        whereArgs: [masaId, 'acik'], limit: 1);
    if (rows.isEmpty) return null;

    final kalemRows = await db.query(DbSabitler.masaSiparisKalem,
        where: 'siparis_id = ? AND is_deleted = 0',
        whereArgs: [rows.first['id']], orderBy: 'id ASC');
    final kalemler = kalemRows.map(MasaSiparisKalemModel.fromMap).toList();
    return MasaSiparisModel.fromMap(rows.first, kalemler: kalemler);
  }

  /// Masada açık sipariş yoksa yeni bir sipariş açar, varsa onu döner.
  Future<MasaSiparisModel> siparisAcVeyaGetir(int masaId) async {
    final mevcut = await acikSiparisGetir(masaId);
    if (mevcut != null) return mevcut;

    final db = await _d;
    final simdi = DateTime.now();
    final gid = const Uuid().v4();
    final id = await db.insert(DbSabitler.masaSiparisleri, {
      'global_id': gid,
      'masa_id': masaId,
      'durum': 'acik',
      'acilis_zamani': simdi.toIso8601String(),
      'toplam_tutar': 0,
      'last_updated': simdi.toIso8601String(),
    });
    await masaDurumGuncelle(masaId, 'dolu');
    final satir = await db.query(DbSabitler.masaSiparisleri, where: 'global_id = ?', whereArgs: [gid], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masa_siparisleri', Map<String, dynamic>.from(satir.first));
    return MasaSiparisModel(id: id, masaId: masaId, acilisZamani: simdi);
  }

  /// Açık siparişe ürün ekler. Aynı ürün+not zaten varsa miktarı artırır.
  Future<void> kalemEkle(int siparisId, {
    required int urunId, required String urunAdi,
    required double birimFiyat, required double kdvOran,
    double miktar = 1, String? not_,
  }) async {
    final db = await _d;
    final mevcut = await db.query(DbSabitler.masaSiparisKalem,
        where: 'siparis_id = ? AND urun_id = ? AND is_deleted = 0 AND durum = ?'
            '${not_ == null ? ' AND (not_ IS NULL)' : ' AND not_ = ?'}',
        whereArgs: not_ == null ? [siparisId, urunId, 'beklemede'] : [siparisId, urunId, 'beklemede', not_]);

    if (mevcut.isNotEmpty) {
      final mevcutMiktar = (mevcut.first['miktar'] as num).toDouble();
      final kalemId = mevcut.first['id'];
      await db.update(DbSabitler.masaSiparisKalem,
          {'miktar': mevcutMiktar + miktar, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [kalemId]);
      final satir = await db.query(DbSabitler.masaSiparisKalem, where: 'id = ?', whereArgs: [kalemId], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('masa_siparis_kalem', Map<String, dynamic>.from(satir.first));
    } else {
      final gid = const Uuid().v4();
      await db.insert(DbSabitler.masaSiparisKalem, {
        'global_id': gid,
        'siparis_id': siparisId,
        'urun_id': urunId,
        'urun_adi': urunAdi,
        'miktar': miktar,
        'birim_fiyat': birimFiyat,
        'kdv_oran': kdvOran,
        'not_': not_,
        'durum': 'beklemede',
        'eklenme_zamani': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      });
      // 🔴 Derin analizde bulundu: masa_siparis_kalem eklemesi
      // BulutManager'ı hiç çağırmıyordu — restoranda masaya ürün
      // eklemek (en sık yapılan işlem) hiç senkronize olmuyordu.
      final satir = await db.query(DbSabitler.masaSiparisKalem, where: 'global_id = ?', whereArgs: [gid], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('masa_siparis_kalem', Map<String, dynamic>.from(satir.first));
    }
    await _toplamGuncelle(siparisId);
  }

  Future<void> kalemMiktarGuncelle(int kalemId, double miktar) async {
    final db = await _d;
    final rows = await db.query(DbSabitler.masaSiparisKalem,
        where: 'id = ?', whereArgs: [kalemId], limit: 1);
    if (rows.isEmpty) return;
    final siparisId = rows.first['siparis_id'] as int;

    if (miktar <= 0) {
      await db.update(DbSabitler.masaSiparisKalem,
          {'is_deleted': 1, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [kalemId]);
    } else {
      await db.update(DbSabitler.masaSiparisKalem,
          {'miktar': miktar, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [kalemId]);
    }
    final satir = await db.query(DbSabitler.masaSiparisKalem, where: 'id = ?', whereArgs: [kalemId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masa_siparis_kalem', Map<String, dynamic>.from(satir.first));
    await _toplamGuncelle(siparisId);
    // 🔴 Aynı düzeltme: miktar 0'a düşürülerek kalem silindiğinde de
    // (yukarıdaki 'if (miktar <= 0)' dalı) masa 'dolu' kalabiliyordu.
    if (miktar <= 0) {
      final kalanKalemler = await db.query(DbSabitler.masaSiparisKalem,
          where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [siparisId]);
      if (kalanKalemler.isEmpty) {
        final siparis = await db.query(DbSabitler.masaSiparisleri,
            columns: ['masa_id'], where: 'id = ?', whereArgs: [siparisId], limit: 1);
        if (siparis.isNotEmpty) {
          final masaId = siparis.first['masa_id'] as int;
          await masaDurumGuncelle(masaId, 'bos');
        }
      }
    }
  }

  Future<void> kalemDurumGuncelle(int kalemId, String durum) async {
    final db = await _d;
    await db.update(DbSabitler.masaSiparisKalem,
        {'durum': durum, 'last_updated': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [kalemId]);
    // 🔴 Mutfak/bar ekranı bu fonksiyonu sürekli çağırıyor (hazırlanıyor
    // → hazır gibi) — senkron hiç yoktu.
    final satir = await db.query(DbSabitler.masaSiparisKalem, where: 'id = ?', whereArgs: [kalemId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masa_siparis_kalem', Map<String, dynamic>.from(satir.first));
  }

  Future<void> kalemNotGuncelle(int kalemId, String? not_) async {
    final db = await _d;
    await db.update(DbSabitler.masaSiparisKalem,
        {'not_': not_, 'last_updated': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [kalemId]);
    final satir = await db.query(DbSabitler.masaSiparisKalem, where: 'id = ?', whereArgs: [kalemId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masa_siparis_kalem', Map<String, dynamic>.from(satir.first));
  }

  Future<void> kalemSil(int kalemId) async {
    final db = await _d;
    final rows = await db.query(DbSabitler.masaSiparisKalem,
        where: 'id = ?', whereArgs: [kalemId], limit: 1);
    if (rows.isEmpty) return;
    final siparisId = rows.first['siparis_id'] as int;
    await db.update(DbSabitler.masaSiparisKalem,
        {'is_deleted': 1, 'last_updated': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [kalemId]);
    final satir = await db.query(DbSabitler.masaSiparisKalem, where: 'id = ?', whereArgs: [kalemId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masa_siparis_kalem', Map<String, dynamic>.from(satir.first));
    await _toplamGuncelle(siparisId);
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "masada ürün ekledim
    // masa dolu oldu, siliyorum çıkıyorum masa boş ama dolu
    // gösteriyor"): _toplamGuncelle() siparişin toplamını doğru
    // sıfırlıyordu ama MASANIN 'durum' alanına HİÇ dokunmuyordu — son
    // kalem silinse bile masa 'dolu' olarak KALICI kalıyordu. Artık
    // siparişte hiç (silinmemiş) kalem kalmadıysa, masa otomatik
    // olarak 'bos' durumuna çekiliyor.
    final kalanKalemler = await db.query(DbSabitler.masaSiparisKalem,
        where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [siparisId]);
    if (kalanKalemler.isEmpty) {
      final siparis = await db.query(DbSabitler.masaSiparisleri,
          columns: ['masa_id'], where: 'id = ?', whereArgs: [siparisId], limit: 1);
      if (siparis.isNotEmpty) {
        final masaId = siparis.first['masa_id'] as int;
        await masaDurumGuncelle(masaId, 'bos');
      }
    }
  }

  /// Kullanıcı isteği: "3+ terminal, hepsi çakışabilir, hatasız olsun" —
  /// birden fazla personel AYNI masaya farklı cihazlardan sipariş
  /// eklerse, her yeni ürün kendi global_id'siyle ayrı bir satır olduğu
  /// için düzgün birleşiyor. AMA sipariş toplamı (`toplam_tutar`)
  /// SADECE yerel bir değişiklik olduğunda yeniden hesaplanıyordu —
  /// senkronizasyon sonrası, başka bir cihazdan gelen kalemler eklenince
  /// toplam OTOMATİK güncellenmiyordu. Bu fonksiyon, tıpkı stok
  /// mutabakatı gibi, TÜM aktif siparişlerin toplamını kalemlerinin
  /// gerçek toplamından yeniden hesaplar — senkronizasyon sonrası
  /// çağrılması önerilir.
  Future<int> siparisToplamlariMutabakatYap() async {
    try {
      final db = await _d;
      // 🔴 DÜZELTME: WHERE koşulu 'kapatildi' durumunu hariç tutmaya
      // çalışıyordu ama bu değer HİÇBİR YERDE kullanılmıyor — gerçek
      // kapanış durumu 'odendi'. Bu yüzden koşul aslında hiçbir şeyi
      // filtrelemiyordu; zaten ÖDENMİŞ siparişler bile gereksiz yere
      // taranıp güncelleniyordu.
      final siparisler = await db.query(DbSabitler.masaSiparisleri,
          where: "durum != 'odendi' AND durum != 'iptal'",
          columns: ['id', 'toplam_tutar']);
      var duzeltilen = 0;
      for (final s in siparisler) {
        final siparisId = s['id'] as int;
        final eskiToplam = (s['toplam_tutar'] as num?)?.toDouble() ?? 0;
        final kalemler = await db.query(DbSabitler.masaSiparisKalem,
            where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [siparisId]);
        final dogruToplam = kalemler.fold<double>(0.0, (acc, k) =>
            acc + (k['miktar'] as num).toDouble() * (k['birim_fiyat'] as num).toDouble());
        if ((eskiToplam - dogruToplam).abs() > 0.01) {
          await db.update(DbSabitler.masaSiparisleri,
              {'toplam_tutar': dogruToplam, 'last_updated': DateTime.now().toIso8601String()},
              where: 'id = ?', whereArgs: [siparisId]);
          // 🔴 Derin analizde bulundu: BulutManager hiç çağrılmıyordu.
          final satir = await db.query(DbSabitler.masaSiparisleri, where: 'id = ?', whereArgs: [siparisId], limit: 1);
          if (satir.isNotEmpty) BulutManager().upsert('masa_siparisleri', Map<String, dynamic>.from(satir.first));
          duzeltilen++;
        }
      }
      if (duzeltilen > 0) {
        LogServisi().bilgi('Masa siparişi mutabakatı: $duzeltilen sipariş düzeltildi');
      }
      return duzeltilen;
    } catch (e, st) {
      LogServisi().hata('Masa.siparisToplamlariMutabakatYap', hata: e, yigin: st);
      return 0;
    }
  }

  Future<void> _toplamGuncelle(int siparisId) async {
    final db = await _d;
    final kalemler = await db.query(DbSabitler.masaSiparisKalem,
        where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [siparisId]);
    final toplam = kalemler.fold<double>(0.0, (acc, k) =>
        acc + (k['miktar'] as num).toDouble() * (k['birim_fiyat'] as num).toDouble());
    await db.update(DbSabitler.masaSiparisleri,
        {'toplam_tutar': toplam, 'last_updated': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [siparisId]);
    // 🔴 Derin analizde bulundu: bu yardımcı fonksiyon (kalemEkle,
    // kalemMiktarGuncelle, kalemSil tarafından çağrılıyor — yani
    // masa siparişindeki HER değişiklik) BulutManager'ı hiç
    // çağırmıyordu.
    final satir = await db.query(DbSabitler.masaSiparisleri, where: 'id = ?', whereArgs: [siparisId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masa_siparisleri', Map<String, dynamic>.from(satir.first));
  }

  /// Müşteri (cari) bağla — fatura/cari ödeme için.
  Future<void> musteriBagla(int siparisId, int? cariId, String? cariAdi) async {
    final db = await _d;
    await db.update(DbSabitler.masaSiparisleri,
        {'cari_id': cariId, 'cari_adi': cariAdi, 'last_updated': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [siparisId]);
    final satir = await db.query(DbSabitler.masaSiparisleri, where: 'id = ?', whereArgs: [siparisId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masa_siparisleri', Map<String, dynamic>.from(satir.first));
  }

  /// "Hesap istensin" — garson çağırma / ödeme bekleniyor durumu.
  Future<void> hesapIstendi(int masaId) async {
    await masaDurumGuncelle(masaId, 'hesap_istendi');
  }

  /// Siparişi ödenmiş olarak kapatır, masayı boşa çevirir.
  Future<void> siparisKapat(int siparisId, int masaId, {int? satisId}) async {
    final db = await _d;
    await db.update(DbSabitler.masaSiparisleri, {
      'durum': 'odendi',
      'kapanis_zamani': DateTime.now().toIso8601String(),
      'satis_id': satisId,
      'last_updated': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [siparisId]);
    // 🔴 Hesap kapatma — restoran akışının en kritik anı — hiç
    // senkronize olmuyordu.
    final satir = await db.query(DbSabitler.masaSiparisleri, where: 'id = ?', whereArgs: [siparisId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masa_siparisleri', Map<String, dynamic>.from(satir.first));
    await masaDurumGuncelle(masaId, 'bos');
  }

  /// Açık siparişi tamamen iptal eder (yanlış açılan masa için).
  Future<void> siparisIptal(int siparisId, int masaId) async {
    final db = await _d;
    await db.update(DbSabitler.masaSiparisleri, {
      'durum': 'iptal',
      'kapanis_zamani': DateTime.now().toIso8601String(),
      'last_updated': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [siparisId]);
    final satir = await db.query(DbSabitler.masaSiparisleri, where: 'id = ?', whereArgs: [siparisId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('masa_siparisleri', Map<String, dynamic>.from(satir.first));
    await masaDurumGuncelle(masaId, 'bos');
  }

  /// Bir masadaki kalemleri başka bir (boş) masaya taşır — "Masa Birleştir/Taşı".
  Future<void> masaTasi(int kaynakSiparisId, int hedefMasaId) async {
    final hedef = await siparisAcVeyaGetir(hedefMasaId);
    final db = await _d;
    await db.update(DbSabitler.masaSiparisKalem,
        {'siparis_id': hedef.id, 'last_updated': DateTime.now().toIso8601String()},
        where: 'siparis_id = ?', whereArgs: [kaynakSiparisId]);
    // 🔴 Taşınan TÜM kalemler senkronize edilmiyordu.
    final tasinanlar = await db.query(DbSabitler.masaSiparisKalem, where: 'siparis_id = ?', whereArgs: [hedef.id]);
    for (final k in tasinanlar) {
      BulutManager().upsert('masa_siparis_kalem', Map<String, dynamic>.from(k));
    }
    await _toplamGuncelle(hedef.id!);

    final kaynak = await db.query(DbSabitler.masaSiparisleri,
        where: 'id = ?', whereArgs: [kaynakSiparisId], limit: 1);
    if (kaynak.isNotEmpty) {
      await siparisIptal(kaynakSiparisId, kaynak.first['masa_id'] as int);
    }
  }
}
