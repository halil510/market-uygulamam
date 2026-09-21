// lib/depolar/vardiya_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi:
// vardiya_ekrani.dart için hiç repository sınıfı yoktu, ekranın kendisi
// doğrudan Veritabani().db üzerinden SQL çalıştırıyordu. Bu dosya o
// erişimi kapsar — davranış BİREBİR korunmuştur, sadece sorumluluk UI
// katmanından buraya taşınmıştır.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class VardiyaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Kapanmamış (kapanis_tarihi IS NULL) en son vardiyayı döner —
  /// [subeId] verilirse SADECE o şubenin vardiyası (bkz. çok şubeli
  /// kurulumda "aktif vardiya" karışma hatasının düzeltmesi).
  Future<Map<String, dynamic>?> aktifVardiyaGetir({int? subeId}) async {
    final db = await _d;
    final subeSarti = subeId != null ? ' AND v.sube_id = ?' : '';
    final subeArgs = subeId != null ? [subeId] : <Object?>[];
    final rows = await db.rawQuery(
        'SELECT v.*, k.ad_soyad FROM vardiyalar v '
        'LEFT JOIN kullanicilar k ON v.kullanici_id = k.id '
        'WHERE v.kapanis_tarihi IS NULL$subeSarti ORDER BY v.id DESC LIMIT 1',
        subeArgs);
    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : null;
  }

  /// Kapanmış vardiyaların geçmişi (en yeniden eskiye). [onaylayan_adi]:
  /// Madde 12 denetimi — kapanışı onaylayan yöneticinin adı (varsa).
  /// [offset]: DEEP_AUDIT_REPORT FAZ 6 (2026-09-21) — ekran önceden HER
  /// ZAMAN sadece en son [limit] kaydı gösterip daha eskilere ulaşmanın
  /// hiçbir yolunu sunmuyordu (sorgu limitliydi ama sayfalama yoktu).
  /// Artık vardiya_ekrani.dart "Daha Fazla Yükle" ile bu parametreyi
  /// kullanarak bir sonraki sayfayı çekebiliyor.
  Future<List<Map<String, dynamic>>> gecmisVardiyalarGetir({
    int? subeId,
    int limit = 30,
    int offset = 0,
  }) async {
    final db = await _d;
    final subeSarti = subeId != null ? ' AND v.sube_id = ?' : '';
    final args = <Object?>[if (subeId != null) subeId, limit, offset];
    final rows = await db.rawQuery(
        'SELECT v.*, k.ad_soyad, o.ad_soyad AS onaylayan_adi FROM vardiyalar v '
        'LEFT JOIN kullanicilar k ON v.kullanici_id = k.id '
        'LEFT JOIN kullanicilar o ON v.onaylayan_kullanici_id = o.id '
        'WHERE v.kapanis_tarihi IS NOT NULL$subeSarti ORDER BY v.id DESC LIMIT ? OFFSET ?',
        args);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Aktif vardiya özeti — satış sayısı/ciro/ödeme yöntemi kırılımı,
  /// [baslangicTarihi]'nden (vardiyanın açılış anı) bu yana.
  // 🔴 DÜZELTME (Karma/çoklu ödeme denetimi, 2026-09-20 — kullanıcı
  // bulgusu: "gün sonu çoklu ödeme doğru olmamış"): nakit/kart/cari
  // ÖNCEDEN satislar.odeme_yontemi TEK ALAN string'iyle eşleştiriliyordu
  // — Karma ödemeli bir satışın odeme_yontemi'si 'Karma' olduğu için bu
  // üç CASE'in HİÇBİRİNE eşleşmiyordu, yani o satışın gerçek nakit/kart/
  // cari payları kırılımdan TAMAMEN KAYBOLUYORDU (toplam_ciro'da vardı,
  // Nakit/Kredi K. KPI kartlarında yoktu). Aynı ekranda "Beklenen Kasa"
  // (KasaDeposu.nakitDegisimi, kasa_hareketleri tabanlı — Karma satışların
  // nakit payını ZATEN doğru içeriyordu) ile bu ekrandaki "Nakit Satışlar"
  // KPI'ı arasında sessiz bir tutarsızlık vardı. Artık nakit/kart, her
  // satış için ödeme yöntemi bazında ZATEN itemize edilmiş olan
  // kasa_hareketleri'nden (bkz. SatisTamamlamaServisi — Karma ödemede her
  // yöntem için ayrı satır), cari ise cari_hareket'ten (SADECE gerçek borç
  // satırı — self-cancelling bilgi satırı HARİÇ) hesaplanıyor. Bu,
  // SatisDeposu.odemeDagilimiGetir() ile AYNI, zaten doğrulanmış kaynak/
  // mantık — tek fark burada TEK bir satış değil, bir zaman aralığı
  // toplanıyor.
  Future<Map<String, dynamic>> satisOzetiGetir(String baslangicTarihi) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) as satis_sayisi,
        COALESCE(SUM(genel_toplam),0) as toplam_ciro,
        COALESCE(SUM(iskonto_tutar),0) as iskonto,
        COALESCE(SUM(CASE WHEN iptal=1 THEN 1 ELSE 0 END),0) as iptal_sayisi
      FROM satislar
      WHERE datetime(tarih) >= datetime(?) AND iptal=0 AND is_deleted=0
    ''', [baslangicTarihi]);
    final ozet = Map<String, dynamic>.from(rows.first);

    final kasaRows = await db.rawQuery('''
      SELECT kh.odeme_yontemi, COALESCE(SUM(kh.tutar),0) as tutar
      FROM kasa_hareketleri kh
      JOIN satislar s ON s.id = kh.referans_id AND kh.referans_turu = 'satis'
      WHERE datetime(s.tarih) >= datetime(?) AND s.iptal=0 AND s.is_deleted=0
        AND kh.deleted_at IS NULL
      GROUP BY kh.odeme_yontemi
    ''', [baslangicTarihi]);
    double nakit = 0, kart = 0, digerKasa = 0;
    for (final r in kasaRows) {
      final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
      switch (r['odeme_yontemi'] as String?) {
        case 'Nakit':       nakit += tutar; break;
        case 'Kredi Kartı': kart  += tutar; break;
        default:            digerKasa += tutar; break;
      }
    }

    final cariRows = await db.rawQuery('''
      SELECT COALESCE(SUM(ch.borc),0) as tutar
      FROM cari_hareket ch
      JOIN satislar s ON s.id = ch.fis_id
      WHERE ch.fis_tipi = 'Satış' AND ch.alacak = 0 AND ch.borc > 0 AND ch.is_deleted = 0
        AND datetime(s.tarih) >= datetime(?) AND s.iptal=0 AND s.is_deleted=0
    ''', [baslangicTarihi]);
    final cari = (cariRows.first['tutar'] as num?)?.toDouble() ?? 0;

    ozet['nakit'] = nakit;
    ozet['kart']  = kart;
    ozet['cari']  = cari;
    ozet['diger'] = digerKasa;
    return ozet;
  }

  /// PDF vardiya raporu için özet — [satisOzetiGetir] ile AYNI zaman
  /// penceresini sorgular ama farklı kolon adları/alan seti döner (PDF
  /// şablonunun beklediği anahtarlarla birebir); davranış değişmesin
  /// diye bilerek AYRI bir metod olarak tutuldu.
  // 🔴 DÜZELTME (Karma/çoklu ödeme denetimi, 2026-09-20): [satisOzetiGetir]
  // üzerindeki AYNI gerekçe/düzeltme burada da geçerli — bu metod PDF
  // vardiya raporunda kullanıldığından, Karma satışların basılı raporda
  // da nakit/kart/cari kırılımından kaybolmaması için aynı kasa_hareketleri/
  // cari_hareket tabanlı hesaplamaya geçirildi. Anahtar adları (PDF
  // şablonunun beklediği 'sayi'/'ciro'/'cari_toplam') DEĞİŞMEDİ.
  Future<Map<String, dynamic>> pdfSatisOzetiGetir(String baslangicTarihi) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) as sayi, COALESCE(SUM(genel_toplam),0) as ciro,
        COALESCE(SUM(iskonto_tutar),0) as iskonto
      FROM satislar WHERE datetime(tarih) >= datetime(?) AND iptal=0 AND is_deleted=0
    ''', [baslangicTarihi]);
    final ozet = Map<String, dynamic>.from(rows.first);

    final kasaRows = await db.rawQuery('''
      SELECT kh.odeme_yontemi, COALESCE(SUM(kh.tutar),0) as tutar
      FROM kasa_hareketleri kh
      JOIN satislar s ON s.id = kh.referans_id AND kh.referans_turu = 'satis'
      WHERE datetime(s.tarih) >= datetime(?) AND s.iptal=0 AND s.is_deleted=0
        AND kh.deleted_at IS NULL
      GROUP BY kh.odeme_yontemi
    ''', [baslangicTarihi]);
    double nakit = 0, kart = 0;
    for (final r in kasaRows) {
      final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
      switch (r['odeme_yontemi'] as String?) {
        case 'Nakit':       nakit += tutar; break;
        case 'Kredi Kartı': kart  += tutar; break;
      }
    }

    final cariRows = await db.rawQuery('''
      SELECT COALESCE(SUM(ch.borc),0) as tutar
      FROM cari_hareket ch
      JOIN satislar s ON s.id = ch.fis_id
      WHERE ch.fis_tipi = 'Satış' AND ch.alacak = 0 AND ch.borc > 0 AND ch.is_deleted = 0
        AND datetime(s.tarih) >= datetime(?) AND s.iptal=0 AND s.is_deleted=0
    ''', [baslangicTarihi]);
    final cariToplam = (cariRows.first['tutar'] as num?)?.toDouble() ?? 0;

    ozet['nakit'] = nakit;
    ozet['kart']  = kart;
    ozet['cari_toplam'] = cariToplam;
    return ozet;
  }

  /// Yeni vardiya açar.
  Future<Map<String, dynamic>> ac({
    required int kullaniciId,
    required int? subeId,
    required double baslangicKasa,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('vardiyalar', {
      'global_id': const Uuid().v4(),
      'kullanici_id': kullaniciId,
      'sube_id': subeId,
      'acilis_tarihi': now,
      'acilis_kasasi': baslangicKasa,
      'baslangic_bakiye': baslangicKasa,
      'durum': 'acik',
      'last_updated': now,
    });
    final satir = await db.query('vardiyalar',
        where: 'id = ?', whereArgs: [id], limit: 1);
    final row = Map<String, dynamic>.from(satir.first);
    BulutManager().upsert('vardiyalar', row);
    return row;
  }

  /// Açık vardiyayı kapatır (nakit sayım + fark ile).
  ///
  /// [onaylayanKullaniciId]: Madde 12 denetimi (2026-09-16) — vardiyayı
  /// FİİLEN kapatan kişi Müdür/Admin DEĞİLSE, kapanış anında kimlik
  /// bilgileriyle onaylayan yöneticinin id'si (bkz. vardiya_ekrani.dart
  /// _yoneticiOnayIste). Kapatan zaten Müdür/Admin'se null kalır — kendi
  /// yetkisi zaten yeterli, ayrıca onay istenmez.
  Future<Map<String, dynamic>> kapat({
    required int vardiyaId,
    required double sayim,
    required double fark,
    int? onaylayanKullaniciId,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.update(
        'vardiyalar',
        {
          'kapanis_tarihi': now,
          'kapanis_kasasi': sayim,
          'bitis_bakiye': sayim,
          'nakit_sayim': sayim,
          'fark': fark,
          'durum': 'kapali',
          'last_updated': now,
          if (onaylayanKullaniciId != null) ...{
            'onaylayan_kullanici_id': onaylayanKullaniciId,
            'onaylanma_tarihi': now,
          },
        },
        where: 'id = ?',
        whereArgs: [vardiyaId]);
    final satir = await db.query('vardiyalar',
        where: 'id = ?', whereArgs: [vardiyaId], limit: 1);
    final row = Map<String, dynamic>.from(satir.first);
    BulutManager().upsert('vardiyalar', row);
    return row;
  }
}
