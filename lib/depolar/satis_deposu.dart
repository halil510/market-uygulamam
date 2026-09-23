import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import 'package:flutter/foundation.dart';
// lib/depolar/satis_deposu.dart
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../servisler/aktif_sube_servisi.dart';
import '../veri/database/veritabani.dart';
import '../modeller/satis_model.dart';
import '../modeller/satis_kalem_model.dart';
import '../modeller/kasa_hareket_model.dart';
import '../servisler/puan_servisi.dart';
import 'kasa_deposu.dart';

class SatisDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> satisEkle(SatisModel satis, List<SatisKalemModel> kalemler) async {
    final db = await _d;
    final satisId = await db.transaction((txn) => satisEkleTxn(txn, satis, kalemler));
    // 🔴 DÜZELTME: 'satis.globalId' çağıranın verdiği ORİJİNAL (çoğu
    // zaman null) değerdi — asıl DB'ye yazılan global_id, satisEkleTxn
    // içinde (satis.globalId boşsa) YENİDEN ÜRETİLİYORDU. Önceki hâl
    // buluta gerçek kayıttan FARKLI (null) bir global_id gönderiyordu.
    // Artık transaction kapandıktan sonra satırı GERÇEKTEN geri okuyup
    // onu gönderiyor — projenin geri kalanındaki standart desenle aynı.
    final satisSatir = await db.query('satislar', where: 'id = ?', whereArgs: [satisId], limit: 1);
    if (satisSatir.isNotEmpty) {
      BulutManager().upsert('satislar', Map<String, dynamic>.from(satisSatir.first));
    }
    for (final k in kalemler) {
      BulutManager().upsert('satis_kalem', k.toMap());
    }
    return satisId;
  }

  /// [satisEkle] ile AYNI mantık, VERİLEN transaction içinde çalışır —
  /// kendi transaction'ını açmaz. BulutManager bildirimini YAPMAZ (dış
  /// transaction commit olmadan buluta göndermek riskli — bkz.
  /// KasaDeposu.hareketEkleTxn'deki aynı not). Çağıran, dış transaction
  /// kapandıktan sonra kendi bildirimini yapmalıdır.
  Future<int> satisEkleTxn(dynamic txn, SatisModel satis, List<SatisKalemModel> kalemler) async {
    final satisMap = satis.toMap();
    satisMap.remove('id');
    // global_id yoksa üret - çok cihaz sync için şart
    satisMap['global_id'] ??= const Uuid().v4();
    // ÖNCEDEN sube_id sadece VERİLMİŞSE doğrulanıyordu, hiç
    // damgalanmıyordu — çağıran taraf unutursa satış hangi şubede
    // yapıldığı bilinmeden kaydediliyordu. Artık boşsa aktif şubeden
    // otomatik dolduruluyor.
    satisMap['sube_id'] ??= AktifSubeServisi().subeId;
    // FK constraint ihlali riskini azalt: geçersiz ID'leri null yap
    // 🔴 GERÇEK ÜRETİM HATASI (SQLite 787 = FOREIGN KEY constraint
    // failed): 'cari_id' bu kontrolün DIŞINDA kalmıştı — sube_id,
    // kasiyer_id, kullanici_id doğrulanıyordu ama cari_id hiç
    // doğrulanmıyordu. Bir satış, henüz bu cihaza senkronlanmamış
    // (başka cihazda oluşturulmuş) bir cariye referans verirse, ya da
    // cari silinmiş/birleştirilmişse, INSERT foreign key hatasıyla
    // patlıyordu — masa ödemesi tam bu noktada kesiliyordu.
    if (satisMap['cari_id'] != null) {
      final car = await txn.query('cari',
          where: 'id = ?', whereArgs: [satisMap['cari_id']], limit: 1);
      if (car.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ satisEkleTxn: cari_id=${satisMap['cari_id']} yerelde yok, '
              'satış cariye BAĞLANMADAN kaydedildi (veresiye/borç izlenemeyecek). '
              'Muhtemel sebep: bu cari başka bir cihazda oluşturulmuş, henüz senkron olmamış.');
        }
        satisMap.remove('cari_id');
      }
    }
    if (satisMap['sube_id'] != null) {
      final sube = await txn.query('subeler',
          where: 'id = ?', whereArgs: [satisMap['sube_id']], limit: 1);
      if (sube.isEmpty) satisMap.remove('sube_id');
    }
    if (satisMap['kasiyer_id'] != null) {
      final kas = await txn.query('kullanicilar',
          where: 'id = ?', whereArgs: [satisMap['kasiyer_id']], limit: 1);
      if (kas.isEmpty) satisMap.remove('kasiyer_id');
    }
    if (satisMap['kullanici_id'] != null) {
      final kul = await txn.query('kullanicilar',
          where: 'id = ?', whereArgs: [satisMap['kullanici_id']], limit: 1);
      if (kul.isEmpty) satisMap.remove('kullanici_id');
    }
    final satisId = await txn.insert('satislar', satisMap,
        conflictAlgorithm: ConflictAlgorithm.replace);
    // Madde 5 sertleştirmesi: satış başlığı + her kalem, business data
    // ile AYNI transaction'da senkron kuyruğuna yazılıyor (bkz.
    // SyncKuyrukYazici yorumu — rollback olursa hiçbiri kuyrukta kalmaz).
    await SyncKuyrukYazici.ekleTxn(txn,
        tablo: 'satislar', veri: {...satisMap, 'id': satisId});
    for (final k in kalemler) {
      final km = k.copyWith(satisId: satisId).toMap();
      km.remove('id');
      km['global_id'] ??= const Uuid().v4();
      final kalemId = await txn.insert('satis_kalem', km);
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'satis_kalem', veri: {...km, 'id': kalemId});
    }
    return satisId;
  }

  /// Tek satış + kalemleri — detay ekranı için
  Future<SatisModel?> idileGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        'SELECT s.*, c.unvan as cari_adi '
        'FROM satislar s LEFT JOIN cari c ON s.cari_id = c.id WHERE s.id = ?',
        [id],
      );
      if (rows.isEmpty) return null;
      final kalemRows = await db.query('satis_kalem',
          where: 'satis_id = ?', whereArgs: [id]);
      final kalemler = kalemRows.map(SatisKalemModel.fromMap).toList();
      return SatisModel.fromMap(rows.first, kalemler: kalemler);
    } catch (e, st) {
      LogServisi().hata('SatisDeposu.idileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Kullanıcı bulgusu (2026-09-20): Karma ödemeli bir satışın detay
  /// ekranında "Ödeme Yöntemi" alanı sadece düz "Karma" yazıyordu — hangi
  /// yöntemden ne kadar ödendiği (ör. 50 Nakit + 50 Cari) görünmüyordu.
  /// Bu, satış için kayıtlı gerçek ödeme dağılımını döner:
  ///   - Nakit/Kart/Havale vb. paylar: kasa_hareketleri'nden (her yöntem
  ///     SatisTamamlamaServisi.tamamla() tarafından zaten AYRI bir
  ///     satırda tutuluyor — bkz. o dosyanın FAZ 1 madde 2 yorumu).
  ///   - Cari (veresiye) payı: cari_hareket'teki GERÇEK borç satırından
  ///     (borc>0 VE alacak=0) — Karma+Cari satışlarda ayrıca yazılan,
  ///     bakiyeyi etkilemeyen self-cancelling "bilgi" satırı (borc=alacak)
  ///     BİLEREK HARİÇ tutulur, o satır bir ödeme yöntemi değildir.
  /// Karma olmayan (tek yöntemli) satışlarda da çalışır — tek elemanlı
  /// bir liste döner.
  Future<List<Map<String, dynamic>>> odemeDagilimiGetir(int satisId) async {
    try {
      final db = await _d;
      final sonuc = <Map<String, dynamic>>[];

      final kasaRows = await db.rawQuery('''
        SELECT odeme_yontemi, COALESCE(SUM(tutar), 0) AS tutar
        FROM kasa_hareketleri
        WHERE referans_id = ? AND referans_turu = 'satis' AND deleted_at IS NULL
        GROUP BY odeme_yontemi
      ''', [satisId]);
      for (final r in kasaRows) {
        final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
        if (tutar <= 0.005) continue;
        sonuc.add({'yontem': r['odeme_yontemi'] as String? ?? '—', 'tutar': tutar});
      }

      final cariRows = await db.rawQuery('''
        SELECT COALESCE(SUM(borc), 0) AS tutar
        FROM cari_hareket
        WHERE fis_id = ? AND fis_tipi = 'Satış' AND alacak = 0 AND borc > 0 AND is_deleted = 0
      ''', [satisId]);
      final cariTutar = (cariRows.first['tutar'] as num?)?.toDouble() ?? 0;
      if (cariTutar > 0.005) {
        sonuc.add({'yontem': 'Cari', 'tutar': cariTutar});
      }

      return sonuc;
    } catch (e, st) {
      LogServisi().hata('SatisDeposu.odemeDagilimiGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 FİŞ GERİ ÇAĞIRMA — fiş numarasıyla satış bul
  //
  // Kasiyer, fişin altındaki barkodu okuttuğunda bu fonksiyon çağrılır.
  // İPTAL EDİLMİŞ ve SİLİNMİŞ fişler bilerek DIŞARIDA bırakılır —
  // iptal edilmiş bir fişe ekleme yapılamamalı.
  // ══════════════════════════════════════════════════════════════════════
  Future<SatisModel?> fisNoIleGetir(String fisNo) async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        'SELECT s.*, c.unvan as cari_adi '
        'FROM satislar s LEFT JOIN cari c ON s.cari_id = c.id '
        'WHERE s.fis_no = ? AND s.iptal = 0 AND s.is_deleted = 0 LIMIT 1',
        [fisNo],
      );
      if (rows.isEmpty) return null;
      final satisId = rows.first['id'] as int;
      final kalemRows = await db.query('satis_kalem',
          where: 'satis_id = ?', whereArgs: [satisId]);
      final kalemler = kalemRows.map(SatisKalemModel.fromMap).toList();
      return SatisModel.fromMap(rows.first, kalemler: kalemler);
    } catch (e, st) {
      LogServisi().hata('SatisDeposu.fisNoIleGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 KAPATILMIŞ FİŞİ GÜNCELLE (kalem düzeltme + ekleme)
  //
  // Kullanıcı isteği: fiş barkodu okutulunca ÜRÜNLER SEPETE GELİR,
  // kasiyer düzeltme yapar (miktar değiştirir, kalem siler) veya yeni
  // ürün ekler, "Tamamla" der. Fişin yeni içeriği = sepetin son hali.
  //
  // ─────────────────────────────────────────────────────────────────────
  // MUHASEBE: NEDEN "ÜRÜN BAZINDA FARK"
  //
  // Kalemleri komple silip yeniden yazmak KOLAY olurdu ama stok yanlış
  // olurdu: eski kalemler için stok zaten düşülmüştü. Doğru hesap,
  // her ürün için NET FARKI bulup sadece onu uygulamaktır:
  //
  //     fark = yeniMiktar - eskiMiktar
  //     fark > 0  →  stoktan DÜŞ    (miktar artmış / yeni ürün)
  //     fark < 0  →  stoğa GERİ VER (miktar azalmış / kalem silinmiş)
  //     fark = 0  →  dokunma
  //
  // Örnek: fişte [Ekmek×2, Süt×1] varken kasiyer [Ekmek×3, Peynir×1]
  // yaptıysa:
  //     Ekmek : 3-2 = +1  → 1 adet daha düş
  //     Süt   : 0-1 = -1  → 1 adet stoğa geri ver
  //     Peynir: 1-0 = +1  → 1 adet düş
  //
  // Bu yüzden `stokFarklari` hesabı ÇAĞIRAN tarafta değil, burada
  // döndürülüyor — ekran katmanı muhasebe kuralı bilmek zorunda kalmasın.
  //
  // ─────────────────────────────────────────────────────────────────────
  // DENETİM İZİ
  //
  // Fiş no DEĞİŞMEZ. `aciklama` alanına güncelleme notu düşer.
  // Stok hareketleri "fis_guncelleme" referans türüyle yazılır, böylece
  // raporda orijinal satıştan ayırt edilir.
  // ══════════════════════════════════════════════════════════════════════

  /// Fişi yeni kalem listesiyle günceller.
  ///
  /// Döner: her ürün için uygulanması gereken stok farkı
  ///        (`urunId -> fark`; pozitif = düşülecek, negatif = geri verilecek)
  /// Çağıran bu farkları StokDeposu üzerinden uygular.
  Future<Map<int, double>> fisiGuncelle({
    required int satisId,
    required List<SatisKalemModel> yeniKalemler,
    required double yeniGenelToplam,
    required double yeniOdenenTutar,
    String? guncelleyenKullanici,
  }) async {
    try {
      final db  = await _d;
      final Map<int, double> stokFarklari = await db.transaction((txn) => fisiGuncelleTxn(
        txn, satisId: satisId, yeniKalemler: yeniKalemler,
        yeniGenelToplam: yeniGenelToplam, yeniOdenenTutar: yeniOdenenTutar,
        guncelleyenKullanici: guncelleyenKullanici,
      ));

      // Buluta gönder (transaction DIŞINDA — ağ kilidi tutmasın)
      final basSatir = await db.query('satislar',
          where: 'id = ?', whereArgs: [satisId], limit: 1);
      if (basSatir.isNotEmpty) {
        BulutManager().upsert('satislar',
            Map<String, dynamic>.from(basSatir.first));
      }
      final kalemSatirlar = await db.query('satis_kalem',
          where: 'satis_id = ?', whereArgs: [satisId]);
      for (final ks in kalemSatirlar) {
        BulutManager().upsert('satis_kalem', Map<String, dynamic>.from(ks));
      }

      return stokFarklari;
    } catch (e, st) {
      LogServisi().hata('SatisDeposu.fisiGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// [fisiGuncelle] ile AYNI mantık, VERİLEN transaction içinde çalışır —
  /// kendi transaction'ını açmaz, BulutManager bildirmez (bkz.
  /// KasaDeposu.hareketEkleTxn'deki aynı gerekçe). Çağıran, dönen
  /// stok farklarını AYNI dış transaction'da stokDusTxn/stokGirTxn ile
  /// uygulayarak tüm fiş güncellemesini (kalemler + stok + cari/kasa)
  /// tek atomik işlemde tamamlayabilir (bkz. SatisTamamlamaServisi
  /// .fisiGuncelle).
  Future<Map<int, double>> fisiGuncelleTxn(
    dynamic txn, {
    required int satisId,
    required List<SatisKalemModel> yeniKalemler,
    required double yeniGenelToplam,
    required double yeniOdenenTutar,
    String? guncelleyenKullanici,
  }) async {
    final now = DateTime.now().toIso8601String();

    // ── 1) ESKİ kalemleri oku (stok farkı için şart)
    final eskiRows = await txn.query('satis_kalem',
        where: 'satis_id = ?', whereArgs: [satisId]);
    final eskiMiktarlar = <int, double>{};
    for (final r in eskiRows) {
      final uid = r['urun_id'] as int?;
      if (uid == null) continue;
      eskiMiktarlar[uid] =
          (eskiMiktarlar[uid] ?? 0) + ((r['miktar'] as num?)?.toDouble() ?? 0);
    }

    // ── 2) YENİ miktarlar
    final yeniMiktarlar = <int, double>{};
    for (final k in yeniKalemler) {
      yeniMiktarlar[k.urunId] = (yeniMiktarlar[k.urunId] ?? 0) + k.miktar;
    }

    // ── 3) NET fark (her iki tarafta geçen tüm ürünler)
    final stokFarklari = <int, double>{};
    for (final uid in {...eskiMiktarlar.keys, ...yeniMiktarlar.keys}) {
      final fark = (yeniMiktarlar[uid] ?? 0) - (eskiMiktarlar[uid] ?? 0);
      if (fark.abs() > 0.0001) stokFarklari[uid] = fark;
    }

    // ── 4) Kalemleri değiştir + başlığı güncelle
    await txn.delete('satis_kalem',
        where: 'satis_id = ?', whereArgs: [satisId]);

    for (final k in yeniKalemler) {
      final km = k.copyWith(satisId: satisId).toMap();
      km.remove('id');
      km['global_id'] ??= const Uuid().v4();
      final kalemId = await txn.insert('satis_kalem', km);
      // Madde 5 sertleştirmesi (bkz. satisEkleTxn'deki aynı gerekçe).
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'satis_kalem', veri: {...km, 'id': kalemId});
    }

    final mevcut = await txn.query('satislar',
        where: 'id = ?', whereArgs: [satisId], limit: 1);
    final eskiAciklama = mevcut.isNotEmpty
        ? (mevcut.first['aciklama'] as String? ?? '')
        : '';
    final not = '[Guncellendi ${now.substring(0, 16)}'
        '${guncelleyenKullanici != null ? " / $guncelleyenKullanici" : ""}]';

    await txn.update('satislar', {
      'genel_toplam': yeniGenelToplam,
      'toplam_tutar': yeniGenelToplam,
      'odenen_tutar': yeniOdenenTutar,
      'aciklama': eskiAciklama.isEmpty ? not : '$eskiAciklama $not',
      'last_updated': now,
    }, where: 'id = ?', whereArgs: [satisId]);
    final guncelSatisSatiri = await txn.query('satislar',
        where: 'id = ?', whereArgs: [satisId], limit: 1);
    if (guncelSatisSatiri.isNotEmpty) {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'satislar',
          veri: Map<String, dynamic>.from(guncelSatisSatiri.first));
    }

    return stokFarklari;
  }

  /// Birden fazla satışın kalemlerini tek sorguda yükle (Excel export için)
  Future<Map<int, List<SatisKalemModel>>> satisKalemleriGetir(List<int> satisIds) async {
    if (satisIds.isEmpty) return {};
    final db = await _d;
    final placeholders = satisIds.map((_) => '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM satis_kalem WHERE satis_id IN ($placeholders) ORDER BY satis_id, id',
      satisIds,
    );
    final Map<int, List<SatisKalemModel>> result = {};
    for (final r in rows) {
      final satisId = r['satis_id'] as int;
      result.putIfAbsent(satisId, () => []).add(SatisKalemModel.fromMap(r));
    }
    return result;
  }

  /// Satış listesi — kalemler YÜKLENMİYOR (sadece header, hız için)
  Future<List<SatisModel>> tariheGoreGetir(DateTime bas, DateTime bit) async {
    final db = await _d;
    // ÖNCEDEN şube filtresi yoktu — Satış Raporu her zaman TÜM
    // şubelerin satışlarını gösteriyordu.
    final subeId = AktifSubeServisi().subeId;
    final subeKosulu = subeId != null ? 'AND s.sube_id = ?' : '';
    // 🔴 DÜZELTME (kullanıcı bulgusu, 2026-09-21): sync_cakisma_kopyasi=1
    // satırlar (bkz. Veritabani._cakismaKorumasiUygula) artık Satış
    // Listesi'nden VE (bu fonksiyonu paylaşan) Gün Sonu Raporu'ndan
    // varsayılan olarak dışlanıyor — incelemesi Sync Çakışmaları
    // ekranındaki ayrı bölümde yapılır (bkz. syncKopyalariGetir).
    final rows = await db.rawQuery(
      'SELECT s.*, c.unvan as cari_adi '
      'FROM satislar s LEFT JOIN cari c ON s.cari_id = c.id '
      'WHERE datetime(s.tarih) BETWEEN datetime(?) AND datetime(?) '
      '  AND s.iptal = 0 AND s.is_deleted = 0 '
      '  AND s.sync_cakisma_kopyasi = 0 $subeKosulu '
      'ORDER BY s.tarih DESC',
      [bas.toIso8601String(), bit.toIso8601String(), if (subeId != null) subeId],
    );
    return rows.map((r) => SatisModel.fromMap(r)).toList();
  }

  /// sync_cakisma_kopyasi=1 damgalı (bkz. tariheGoreGetir'deki not) tüm
  /// satışları döner — Sync Çakışmaları ekranındaki inceleme bölümü için.
  /// Tarih aralığı YOK (bu tür kayıtlar nadir olur, hepsi görülebilmeli).
  Future<List<SatisModel>> syncKopyalariGetir() async {
    final db = await _d;
    final rows = await db.rawQuery(
      'SELECT s.*, c.unvan as cari_adi '
      'FROM satislar s LEFT JOIN cari c ON s.cari_id = c.id '
      'WHERE s.sync_cakisma_kopyasi = 1 AND s.is_deleted = 0 '
      'ORDER BY s.tarih DESC',
    );
    return rows.map((r) => SatisModel.fromMap(r)).toList();
  }

  /// Kullanıcı bir sync-kopyası şüpheli satışı inceleyip "bu gerçek bir
  /// satış" derse, damgayı kaldırıp satışı normal listelere/toplamlara
  /// geri döndürür. Kopyaysa zaten mevcut [sil] kullanılmalı.
  Future<void> syncKopyasiGercekOlarakIsaretle(int id) async {
    final db = await _d;
    await db.update('satislar', {'sync_cakisma_kopyasi': 0}, where: 'id = ?', whereArgs: [id]);
    final satisSatir = await db.query('satislar', where: 'id = ?', whereArgs: [id], limit: 1);
    if (satisSatir.isNotEmpty) {
      BulutManager().upsert('satislar', Map<String, dynamic>.from(satisSatir.first));
    }
  }

  // 🔴 Derin analizde bulundu: Satış Raporu'nun "$X iptal satış"
  // banner'ı ASLA görünmüyordu — tariheGoreGetir() zaten SQL
  // seviyesinde iptal=0 filtrelediği için raporun kendi hesabı
  // (satislar.length - aktif.length) her zaman 0 çıkıyordu. Bu
  // paylaşılan fonksiyonun davranışını (dashboard/satış listesi de
  // kullanıyor) değiştirmemek için ayrı, hedefli bir sayım fonksiyonu.
  Future<int> iptalSayisiGetir(DateTime bas, DateTime bit) async {
    final db = await _d;
    final subeId = AktifSubeServisi().subeId;
    final subeKosulu = subeId != null ? 'AND sube_id = ?' : '';
    final res = await db.rawQuery(
      'SELECT COUNT(*) as adet FROM satislar '
      'WHERE datetime(tarih) BETWEEN datetime(?) AND datetime(?) '
      '  AND iptal = 1 AND is_deleted = 0 $subeKosulu',
      [bas.toIso8601String(), bit.toIso8601String(), if (subeId != null) subeId],
    );
    return (res.first['adet'] as int?) ?? 0;
  }

  /// Tarih aralığındaki satılan malın maliyetini (COGS) hesaplar — satır
  /// bazında TARİHSEL maliyet (satis_kalem.alis_fiyat_kdv, satış anında
  /// kalıcı olarak damgalanan KDV DAHİL alış maliyeti) kullanılır;
  /// eski/migrasyon-öncesi VEYA masa satışı satırları için (0 ise) güncel
  /// urunler.alis_fiyat_kdv_dahil'e düşülür. Aktif şubeye göre filtrelenir
  /// (bkz. tariheGoreGetir'deki AYNI desen). Madde 2 mimari denetimi:
  /// gunluk_rapor_ekrani.dart önceden bu sorguyu doğrudan kendisi
  /// çalıştırıyordu.
  ///
  /// 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22): bu sorgu
  /// ÖNCEDEN satir bazlı maliyeti KDV HARİÇ (sk.alis_fiyat / u.alis_fiyat)
  /// hesaplıyordu, ama ciro tarafı (satislar.genel_toplam, bu değerin
  /// çıkarıldığı yer) HER ZAMAN KDV DAHİL'dir (satis_fiyati KDV DAHİL
  /// saklanır — doğrulanmış proje kuralı). KDV dahil ciro'dan KDV hariç
  /// maliyet çıkarmak, Net Kâr'ı maliyetin KDV payı kadar OLDUĞUNDAN
  /// FAZLA gösteriyordu. Artık ikisi de KDV DAHİL — elma elmayla
  /// kıyaslanıyor.
  Future<double> maliyetToplami(DateTime bas, DateTime bit) async {
    final db = await _d;
    final subeId = AktifSubeServisi().subeId;
    final subeKosulu = subeId != null ? 'AND s.sube_id = ?' : '';
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE WHEN sk.alis_fiyat_kdv > 0 THEN sk.miktar * sk.alis_fiyat_kdv
             ELSE sk.miktar * COALESCE(u.alis_fiyat_kdv_dahil, 0) END
      ), 0) as maliyet
      FROM satis_kalem sk
      JOIN satislar s ON sk.satis_id = s.id
      LEFT JOIN urunler u ON sk.urun_id = u.id
      WHERE s.tarih BETWEEN ? AND ?
        AND s.iptal = 0 AND s.is_deleted = 0
        AND s.sync_cakisma_kopyasi = 0 $subeKosulu
    ''', [bas.toIso8601String(), bit.toIso8601String(), if (subeId != null) subeId]);
    return (rows.first['maliyet'] as num?)?.toDouble() ?? 0;
  }

  /// Gün Sonu Excel dışa aktarımı için detaylı satış kalemleri (fiş no,
  /// cari unvanı, ürün, miktar, fiyat...) — tarihe göre, aktif şubeye
  /// göre filtrelenir. Madde 2 mimari denetimi: gunluk_rapor_ekrani.dart
  /// önceden bu sorguyu doğrudan kendisi çalıştırıyordu.
  Future<List<Map<String, dynamic>>> gunSonuDetayGetir(DateTime bas, DateTime bit) async {
    final db = await _d;
    final subeId = AktifSubeServisi().subeId;
    final subeKosulu = subeId != null ? 'AND s.sube_id = ?' : '';
    return db.rawQuery('''
      SELECT
        s.fis_no,
        s.tarih,
        c.unvan as cari_unvan,
        s.odeme_yontemi,
        sk.barkod,
        sk.urun_adi,
        sk.miktar,
        sk.birim_fiyat,
        sk.iskonto_tutar,
        sk.kdv_oran,
        sk.kdv_tutar,
        sk.net_fiyat,
        sk.toplam_tutar,
        sk.urun_id
      FROM satislar s
      INNER JOIN satis_kalem sk ON s.id = sk.satis_id
      LEFT JOIN cari c ON s.cari_id = c.id
      WHERE s.tarih BETWEEN ? AND ?
        AND s.iptal = 0
        AND s.is_deleted = 0
        AND s.sync_cakisma_kopyasi = 0 $subeKosulu
      ORDER BY s.tarih, s.id
    ''', [bas.toIso8601String(), bit.toIso8601String(), if (subeId != null) subeId]);
  }

  /// Bir carinin son 6 ayının aylık satış toplamlarını (ay bazında
  /// gruplanmış) döner — cari 360 panelindeki analiz grafiği için (bkz.
  /// cari_detay_paneli.dart). Madde 2 mimari denetimi.
  Future<List<Map<String, dynamic>>> cariAylikSatisGetir(int cariId) async {
    final db = await _d;
    return db.rawQuery('''
      SELECT strftime('%Y-%m', tarih) AS ay, SUM(genel_toplam) AS toplam
      FROM satislar
      WHERE cari_id = ? AND iptal = 0 AND is_deleted = 0
        AND tarih >= date('now', 'localtime', '-6 months')
      GROUP BY ay ORDER BY ay ASC
    ''', [cariId]);
  }

  /// Bir carinin en çok satın aldığı ürünleri (miktar bazlı, ilk [limit])
  /// döner — cari 360 panelindeki "En Çok Alınanlar" bloğu için. Madde 2
  /// mimari denetimi.
  Future<List<Map<String, dynamic>>> cariEnCokAlinanlarGetir(int cariId, {int limit = 6}) async {
    final db = await _d;
    return db.rawQuery('''
      SELECT sk.urun_adi, SUM(sk.miktar) AS toplam_miktar, SUM(sk.toplam_tutar) AS toplam_tutar
      FROM satis_kalem sk
      JOIN satislar s ON sk.satis_id = s.id
      WHERE s.cari_id = ? AND s.iptal = 0 AND s.is_deleted = 0
      GROUP BY sk.urun_adi ORDER BY toplam_tutar DESC LIMIT ?
    ''', [cariId, limit]);
  }

  /// Bugünkü toplam toptan satış cirosu (iptal hariç) — toptan
  /// dashboard'unun ciro kartı için. Madde 2 mimari denetimi:
  /// toptan_dashboard_ekrani.dart önceden bu sorguyu doğrudan kendisi
  /// çalıştırıyordu.
  Future<double> bugunkuToptanCiro() async {
    final db = await _d;
    final bugun = DateTime.now();
    final baslangic = DateTime(bugun.year, bugun.month, bugun.day).toIso8601String();
    final res = await db.rawQuery(
      "SELECT COALESCE(SUM(genel_toplam),0) AS toplam FROM satislar "
      "WHERE fis_tipi = 'Toptan Satış' AND iptal = 0 AND tarih >= ?",
      [baslangic],
    );
    return (res.first['toplam'] as num?)?.toDouble() ?? 0;
  }

  Future<List<SatisModel>> bugunkunSatislar() async {
    final now = DateTime.now();
    return tariheGoreGetir(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  // 🔴 DÜZELTME (Cari/Fiş denetimi, 2026-09-20): is_deleted=1 (silinmiş)
  // satışlar iptal=0 filtresinden kaçıp burada listeleniyordu — sil()
  // ikisini birlikte set ettiği için pratikte nadiren tetiklenen bir
  // tutarsızlıktı, ama Fiş Detay/cari_hareket_ekrani.dart'taki diğer
  // sorgularla aynı filtre disiplinine getirildi. `limit` parametresi de
  // ölüydü (hiç SQL'e uygulanmıyordu) — artık gerçekten uygulanıyor.
  Future<List<SatisModel>> cariSatislari(int cariId, {int limit = 100}) async {
    final db = await _d;
    final rows = await db.rawQuery(
      'SELECT s.*, c.unvan as cari_adi '
      'FROM satislar s LEFT JOIN cari c ON s.cari_id = c.id '
      'WHERE s.cari_id = ? AND s.iptal = 0 AND s.is_deleted = 0 '
      'ORDER BY s.tarih DESC LIMIT ?',
      [cariId, limit],
    );
    return rows.map((r) => SatisModel.fromMap(r)).toList();
  }

  Future<void> satisIptal(int id, String neden) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      // 🔴 DÜZELTME: last_updated bümlenmiyordu — satış iptali diğer
      // cihazlara hiç senkron olmuyordu.
      await db.update('satislar', {
        'iptal': 1,
        'iptal_tarihi': now,
        'iptal_nedeni': neden,
        'last_updated': now,
      }, where: 'id = ?', whereArgs: [id]);
      final guncelSatir = await db.query('satislar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('satislar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('SatisDeposu.satisIptal', hata: e, yigin: st);
      rethrow;
    }
  }


  Future<Map<String, double>> gunlukIstatistik() async {
    final db = await _d;
    final res = await db.rawQuery(
      "SELECT COUNT(*) as satis_sayisi, SUM(genel_toplam) as ciro, "
      "SUM(iskonto_tutar) as iskonto, "
      "SUM(CASE WHEN odeme_yontemi = 'Nakit' THEN odenen_tutar ELSE 0 END) as nakit, "
      "SUM(CASE WHEN odeme_yontemi = 'Kredi Kartı' THEN odenen_tutar ELSE 0 END) as kart, "
      // Madde 31 (Dashboard) denetimi, 2026-09-20: Cari için odenen_tutar
      // DEĞİL genel_toplam kullanılır — gunluk_rapor_ekrani.dart'taki
      // AYNI kırılım desenine hizalı (Cari satışta odenen_tutar tipik
      // olarak 0'dır, ödenmemiş tam tutar veresiye yazılır).
      "SUM(CASE WHEN odeme_yontemi = 'Cari' THEN genel_toplam ELSE 0 END) as cari "
      "FROM satislar "
      // 🔴 KRİTİK DÜZELTME (derin analiz — gün sonu raporu / kasa özeti):
      // SQLite'ın DATE('now') fonksiyonu VARSAYILAN OLARAK UTC kullanır.
      // Ama `tarih` sütunu DateTime.now().toIso8601String() ile YEREL
      // saatle yazılıyor (satis_model.dart, gider_model.dart, kasa
      // hareketleri — hepsi aynı desen).
      //
      // Türkiye UTC+3 olduğu için, YEREL saatle 00:00–03:00 arasında
      // (yani UTC henüz bir önceki güne ait sayılırken) yapılan HER
      // satış/gider/kasa hareketi bu sorgudan DÜŞÜYORDU:
      //
      //   Yerel 01:00 (27 Tem) → tarih sütunu: '2026-07-27T01:00:00'
      //   O ANDA UTC saati     : 26 Tem 22:00 → DATE('now') = '2026-07-26'
      //   DATE(tarih)='2026-07-27' ≠ DATE('now')='2026-07-26' → KAYIP
      //
      // 24 saat açık ya da gece geç saatlere çalışan bir markette, gece
      // yarısından sonraki 3 saatlik satışlar "Gün Sonu Raporu"na hiç
      // girmiyordu. 'localtime' değiştiricisi SQLite'a cihazın kendi
      // saat dilimini kullanmasını söyler — POS cihazı zaten işletmenin
      // kendi lokasyonunda olduğu için bu doğru varsayımdır.
      "WHERE DATE(tarih) = DATE('now','localtime') AND iptal = 0 AND is_deleted = 0",
    );
    if (res.isEmpty) return {};
    final r = res.first;
    return {
      'satis_sayisi': (r['satis_sayisi'] as num?)?.toDouble() ?? 0,
      'ciro':         (r['ciro']         as num?)?.toDouble() ?? 0,
      'iskonto':      (r['iskonto']      as num?)?.toDouble() ?? 0,
      'nakit':        (r['nakit']        as num?)?.toDouble() ?? 0,
      'kart':         (r['kart']         as num?)?.toDouble() ?? 0,
      'cari':         (r['cari']         as num?)?.toDouble() ?? 0,
    };
  }

  /// Madde 31 (Dashboard) + Madde 24 (Raporlar) denetimi, 2026-09-20:
  /// bugünün maliyeti (COGS) — Kâr/Zarar raporu ve (düzeltilmiş) Gün
  /// Sonu raporuyla BİREBİR AYNI formül. Dashboard'daki "Bugünkü Kâr"ın
  /// bu değeri KULLANMASI gerekiyordu — önceden hiç kullanmıyordu (sadece
  /// ciro-gider'di).
  ///
  /// 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22): maliyetToplami()
  /// ile AYNI hata — KDV HARİÇ maliyet (alis_fiyat), KDV DAHİL ciroya
  /// (genel_toplam) karşı çıkarılıyordu. Artık ikisi de KDV DAHİL
  /// (alis_fiyat_kdv / urunler.alis_fiyat_kdv_dahil) — bkz. o metodun
  /// yorumu.
  Future<double> gunlukMaliyet() async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE WHEN sk.alis_fiyat_kdv > 0 THEN sk.miktar * sk.alis_fiyat_kdv
             ELSE sk.miktar * COALESCE(u.alis_fiyat_kdv_dahil, 0) END
      ), 0) as maliyet
      FROM satis_kalem sk
      JOIN satislar s ON sk.satis_id = s.id
      LEFT JOIN urunler u ON sk.urun_id = u.id
      WHERE DATE(s.tarih) = DATE('now','localtime')
        AND s.iptal = 0 AND s.is_deleted = 0
    ''');
    return (rows.first['maliyet'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> haftaGrafikVerisi() async {
    final db = await _d;
    // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu):
    // 1) SQL 'toplam' adında bir sütun döndürüyordu ama Dashboard
    //    ekranı 'ciro' anahtarını okuyordu — anahtar hiç eşleşmediği
    //    için grafik HER ZAMAN sıfır gösteriyordu.
    // 2) is_deleted = 0 filtresi eksikti (sadece iptal = 0 vardı).
    // 3) "Son 6 gün" (GROUP BY ile satışsız günler atlanarak) sorgusu,
    //    ekranın varsaydığı SABİT "Pzt,Sal,Çar,Per,Cum,Cmt,Paz" (bu
    //    haftanın Pazartesi'den başlayan) etiketleriyle örtüşmüyordu —
    //    hem gün kayması hem de eksik günlerde grafik çarpıklığı riski
    //    vardı. Artık bu haftanın Pazartesi'sinden bugüne kadar TAM 7
    //    gün (satışsız günler için 0 dahil), doğru sırada üretiliyor.
    final now = DateTime.now();
    final pazartesi = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    final rows = await db.rawQuery(
      "SELECT DATE(tarih) as gun, SUM(genel_toplam) as ciro "
      "FROM satislar "
      "WHERE tarih >= ? AND iptal = 0 AND is_deleted = 0 "
      "GROUP BY DATE(tarih)",
      [pazartesi.toIso8601String()],
    );
    final gunHaritasi = <String, double>{
      for (final r in rows)
        (r['gun'] as String): (r['ciro'] as num?)?.toDouble() ?? 0,
    };

    return List.generate(7, (i) {
      final gun = pazartesi.add(Duration(days: i));
      final anahtar = '${gun.year.toString().padLeft(4, '0')}-'
          '${gun.month.toString().padLeft(2, '0')}-'
          '${gun.day.toString().padLeft(2, '0')}';
      return {'gun': anahtar, 'ciro': gunHaritasi[anahtar] ?? 0.0};
    });
  }

  /// Satışı siler ve stokları geri yükler
  /// [stokGeriYukle] = false ise stok hareketi yapılmaz (iade durumu gibi)
  /// Satışı iptal et / sil — atomik transaction
  /// Stok geri yüklenir, kasa düzeltilir, cari hareketi tersine çevrilir
  Future<void> sil(int id, {bool stokGeriYukle = true, String? neden}) async {
    final db = await _d;
    // 🔴 DERLEME HATASI DÜZELTMESİ: cariId önceden transaction
    // closure'ının İÇİNDE 'final' olarak tanımlanıyordu — bu yüzden
    // transaction bittikten SONRA (BulutManager bildirimleri için)
    // kullanılmaya çalışıldığında derleyici "tanımsız getter" hatası
    // veriyordu. Artık üst kapsamda tanımlanıp transaction içinde
    // sadece atanıyor, böylece her iki yerden de erişilebiliyor.
    int? cariId;
    final kasaHareketIdleri = <int>[];
    await db.transaction((txn) async {

      // 1. Satış başlığını al
      final satisRows = await txn.query('satislar',
          where: 'id = ?', whereArgs: [id]);
      if (satisRows.isEmpty) return;
      final satis = satisRows.first;

      final odemeYontemi = satis['odeme_yontemi'] as String? ?? '';
      cariId       = satis['cari_id'] as int?;
      final fisNo        = satis['fis_no'] as String? ?? '#$id';

      // 2. Kalemleri al
      final kalemler = await txn.query('satis_kalem',
          where: 'satis_id = ?', whereArgs: [id]);

      // 3. Satışı soft-delete
      final simdi = DateTime.now().toIso8601String();
      await txn.update('satislar', {
        'is_deleted':    1,
        'iptal':         1,
        'iptal_tarihi':  simdi,
        'iptal_nedeni':  neden ?? 'Kullanıcı tarafından silindi',
        'last_updated':  simdi,
      }, where: 'id = ?', whereArgs: [id]);

      // 4. Stok geri yükle
      if (stokGeriYukle) {
        for (final k in kalemler) {
          final urunId = k['urun_id'] as int?;
          final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
          if (urunId == null || miktar <= 0) continue;
          // ÖNCEDEN BURADA onceki_stok/sonraki_stok SABİT 0 OLARAK
          // BIRAKILIYORDU — gerçek değerler hiç hesaplanmıyordu. Bu,
          // stok mutabakat sisteminin bu hareketi "değişiklik yok"
          // olarak yorumlamasına yol açardı (0-0=0 fark). Artık gerçek
          // önceki/sonraki değerler okunup kaydediliyor.
          final urunRows = await txn.query('urunler',
              columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
          final onceki = urunRows.isNotEmpty
              ? (urunRows.first['stok'] as num).toDouble() : 0.0;
          final sonraki = onceki + miktar;
          await txn.update('urunler', {'stok': sonraki, 'last_updated': simdi}, where: 'id = ?', whereArgs: [urunId]);
          await txn.insert('stok_hareket', {
            'urun_id':       urunId,
            'hareket_turu':  'İptal İadesi',
            'miktar':        miktar,
            'onceki_stok':   onceki,
            'sonraki_stok':  sonraki,
            'referans_id':   id,
            'referans_turu': 'satis_iptal',
            'tarih':         simdi,
            'last_updated':  simdi,
            'aciklama':      'Satış iptali — Fiş $fisNo',
          });
        }
      }

      // 5. Kasa hareketini tersine çevir (nakit/kart satışlar)
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu 2026-09-21): önceden bu
      // blok satislar.odenen_tutar/odeme_yontemi alanlarına bakıp TEK bir
      // ters kayıt tahmin ediyordu. Ama Karma (Nakit+Cari gibi) satışlarda
      // odenen_tutar TÜM tutarları (Cari payı dahil) topluyor — bu da
      // kasadan olduğundan FAZLA düşülmesine yol açardı. Artık bu satışa
      // ait GERÇEKTEN yazılmış kasa_hareketleri satırları (referans_turu
      // = 'satis') sorgulanıp HER biri kendi tutarı/ödeme yöntemiyle tek
      // tek tersine çevriliyor — saf Cari (veresiye) satışta hiç kasa
      // satırı yoktur, dolayısıyla hiçbir şey ters çevrilmez (doğru).
      final orijinalKasaSatirlari = await txn.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ? AND deleted_at IS NULL',
          whereArgs: [id, 'satis']);
      for (final k in orijinalKasaSatirlari) {
        final tutar = (k['tutar'] as num?)?.toDouble() ?? 0;
        if (tutar <= 0) continue;
        final kid = await KasaDeposu().hareketEkleTxn(txn, KasaHareketModel(
          hareketTipi:  'Satış İptali',
          tutar:        tutar,
          referansId:   id,
          referansTuru: 'satis_iptal',
          tarih:        DateTime.parse(simdi),
          aciklama:     'Satış iptali: $fisNo',
          odemeYontemi: k['odeme_yontemi'] as String?,
        ));
        kasaHareketIdleri.add(kid);
      }

      // 6. Cari hareketi tersine çevir
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu 2026-09-21): önceden bu
      // blok "Satış İptali" ters kaydını satis.genel_toplam'a göre
      // yazıyor, AYRICA odenen_tutar > 0 ise HER ZAMAN ekstra bir
      // "Tahsilat İptali" borcu ekliyordu. Saf Veresiye (Cari) satışlarda
      // odenen_tutar HİÇBİR ZAMAN gerçek bir tahsilatı temsil etmiyor —
      // sadece bookkeeping alanı satis.genel_toplam ile aynı değere sahip.
      // Sonuç: satış silinince "Satış İptali" borcu sıfırlıyor ama hemen
      // ardından "Tahsilat İptali" AYNI TUTARI TEKRAR borç yazıyordu —
      // müşteri borcu satış silinmeden ÖNCEKİ HALİYLE AYNEN kalıyordu ve
      // Cari Hareketler ekranında açıklanamaz "Tahsilat İptali" satırı
      // görünüyordu. Artık tahmin yok: bu satışın GERÇEKTEN yazdığı
      // cari_hareket satırları (fis_id + fis_tipi='Satış') sorgulanıp
      // toplam borç/alacağın TAM TERSİ TEK bir "Satış İptali" kaydıyla
      // sıfırlanıyor — hem saf Cari hem Karma+Cari satışlarda doğru.
      if (cariId != null) {
        final now = simdi;
        // 'Satış' perakende akışının, 'Toptan Satış' ise
        // ToptanSatisIslemServisi'nin bu fis_id için yazdığı fis_tipi —
        // bu ekran (cari_detay_paneli.dart) her iki tür satışı da AYNI
        // SatisDeposu.sil() ile siler, ikisi de eşleşmeli.
        final orijinalCariSatirlari = await txn.query('cari_hareket',
            where:
                'fis_id = ? AND cari_id = ? AND fis_tipi IN (?, ?) AND is_deleted = 0',
            whereArgs: [id, cariId, 'Satış', 'Toptan Satış']);
        final toplamBorc = orijinalCariSatirlari.fold(
            0.0, (s, r) => s + ((r['borc'] as num?)?.toDouble() ?? 0));
        final toplamAlacak = orijinalCariSatirlari.fold(
            0.0, (s, r) => s + ((r['alacak'] as num?)?.toDouble() ?? 0));
        if (toplamBorc > 0.005 || toplamAlacak > 0.005) {
          await txn.insert('cari_hareket', {
            'global_id':  const Uuid().v4(),
            'cari_id':    cariId,
            'tarih':      now,
            'last_updated': now,
            'fis_tipi':   'Satış İptali',
            'fis_id':     id,
            'fis_no':     fisNo,
            'aciklama':   'Satış iptali: $fisNo',
            'borc':       toplamAlacak,
            'alacak':     toplamBorc,
            'odeme_turu': odemeYontemi,
          });
        }
        // Cari bakiyeyi yeniden hesapla
        final bRes = await txn.rawQuery(
          'SELECT SUM(borc) - SUM(alacak) AS b FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0',
          [cariId]);
        final yeniBakiye = (bRes.first['b'] as num?)?.toDouble() ?? 0;
        await txn.update('cari', {'bakiye': yeniBakiye, 'last_updated': simdi},
            where: 'id = ?', whereArgs: [cariId]);
      }
    });
    // BulutManager'a satış bildirimi — transaction dışında.
    final db2 = await _d;
    final satisSon = await db2.query('satislar', where: 'id = ?', whereArgs: [id], limit: 1);
    if (satisSon.isNotEmpty) BulutManager().upsert('satislar', Map<String, dynamic>.from(satisSon.first));
    for (final kasaHareketId in kasaHareketIdleri) {
      final kasaSon = await db2.query('kasa_hareketleri', where: 'id = ?', whereArgs: [kasaHareketId], limit: 1);
      if (kasaSon.isNotEmpty) BulutManager().upsert('kasa_hareketleri', Map<String, dynamic>.from(kasaSon.first));
    }
    // 🔴 Derin analizde bulundu: cari_hareket eklemeleri (yukarıdaki
    // Satış İptali kaydı) global_id ATAMIYORDU ve BulutManager'a HİÇ
    // bildirilmiyordu — ne bu kayıtlar ne de cari bakiye güncellemesi
    // buluta gidiyordu.
    if (cariId != null) {
      final cariHareketSon = await db2.query('cari_hareket',
          where: 'fis_id = ? AND cari_id = ? AND fis_tipi = ?',
          whereArgs: [id, cariId, 'Satış İptali'], orderBy: 'id DESC', limit: 1);
      for (final satir in cariHareketSon) {
        BulutManager().upsert('cari_hareket', Map<String, dynamic>.from(satir));
      }
      final cariSon = await db2.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
      if (cariSon.isNotEmpty) BulutManager().upsert('cari', Map<String, dynamic>.from(cariSon.first));

      // 🔴🔴 KRİTİK DÜZELTME (paralel fork denetimi, 2026-09-22): satış
      // silinince kazanılan/kullanılan sadakat puanı hiç geri alınmıyordu
      // — bkz. PuanServisi.puanIptalEt() dosya başı yorumu. Ana silme
      // işlemini geri almamalı diye ayrı, best-effort bir adım.
      try {
        await PuanServisi().puanIptalEt(cariId: cariId!, satisId: id);
      } catch (e) {
        if (kDebugMode) debugPrint('Satış silme — puan iptali hatası: $e');
      }
    }
  }
}
