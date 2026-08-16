// lib/servisler/ai_servisi.dart
// Ana AI wrapper — eski metodlar + yeni sohbet sistemi
import 'package:flutter/foundation.dart';
import 'ai/ai_sohbet_servisi.dart';
import '../veri/database/veritabani.dart';
export 'ai/ai_modeller.dart';
export 'ai/ai_sohbet_servisi.dart';

class AiServisi {
  static final AiServisi _i = AiServisi._();
  factory AiServisi() => _i;
  AiServisi._();

  final _sohbet = AiSohbetServisi();

  /// Yeni sohbet arayüzü — artık gezinme (navigasyon) komutlarını da
  /// destekler, bkz. AiSohbetSonuc.
  Future<AiSohbetSonuc> sor(String soru) => _sohbet.sor(soru);

  /// Günlük özet — AI panel Özet sekmesi
  Future<Map<String, dynamic>> gunlukOzet() async {
    try {
      final db  = await Veritabani().db;
      final now = DateTime.now();
      final bas = DateTime(now.year, now.month, now.day).toIso8601String();
      final bit = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

      final s = (await db.rawQuery('''
        SELECT COUNT(*) as islem,
               COALESCE(SUM(genel_toplam),0) as ciro,
               COALESCE(SUM(iskonto_tutar),0) as iskonto
        FROM satislar WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
      ''', [bas, bit])).first;

      final m = (await db.rawQuery('''
        SELECT COALESCE(SUM(sk.miktar * COALESCE(sk.alis_fiyat,0)),0) as mal
        FROM satis_kalem sk JOIN satislar st ON sk.satis_id=st.id
        WHERE st.tarih BETWEEN ? AND ? AND st.iptal=0 AND st.is_deleted=0
      ''', [bas, bit])).first;

      final kasa = (await db.rawQuery(
        'SELECT bakiye_sonrasi FROM kasa_hareketleri ORDER BY tarih DESC, id DESC LIMIT 1'
      ));

      // 🔴🔴 Derin analizde bulundu: ai_sohbet_servisi.dart ve
      // ai_rapor_servisi.dart'ta bulduğum AYNI hata — "kar" (AI
      // Panel'in Özet sekmesinde gösterilen günlük kâr rakamı)
      // giderleri hiç düşmüyordu.
      final g = (await db.rawQuery('''
        SELECT COALESCE(SUM(tutar),0) as toplam
        FROM giderler WHERE tarih BETWEEN ? AND ? AND deleted_at IS NULL
      ''', [bas, bit])).first;

      final ciro   = (s['ciro'] as num?)?.toDouble() ?? 0;
      final islem  = (s['islem'] as num?)?.toInt() ?? 0;
      final mal    = (m['mal'] as num?)?.toDouble() ?? 0;
      final gider  = (g['toplam'] as num?)?.toDouble() ?? 0;

      // Kritik stok sayısı
      final kritikRows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM urunler WHERE stok <= CASE WHEN minimum_stok > 0 THEN minimum_stok ELSE 5 END AND aktif=1 AND is_deleted=0');
      final kritikSayi = (kritikRows.first['c'] as num?)?.toInt() ?? 0;

      return {
        'ciro':          ciro,
        'kar':           ciro - mal - gider,
        'gider':         gider,
        'iskonto':       (s['iskonto'] as num?)?.toDouble() ?? 0,
        'islem':         islem,
        'satis_sayisi':  islem,
        'ortalama_sepet': islem > 0 ? ciro / islem : 0.0,
        'kritik_stok':   kritikSayi,
        'kasa':          kasa.isEmpty ? 0.0 : (kasa.first['bakiye_sonrasi'] as num?)?.toDouble() ?? 0,
      };
    } catch (e) { if (kDebugMode) debugPrint('[AiServisi.gunlukOzet] $e'); return {}; }
  }

  /// Satış tahmini
  Future<Map<String, double>> satisTahmini() async {
    try {
      final db  = await Veritabani().db;
      final bas = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      final bit = DateTime.now().toIso8601String();
      final r   = (await db.rawQuery('''
        SELECT COALESCE(SUM(genel_toplam),0)/30.0 as ort
        FROM satislar WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
      ''', [bas, bit])).first;
      final ort = (r['ort'] as num?)?.toDouble() ?? 0;
      return {
        '7gun':    ort * 7,
        '30gun':   ort * 30,
        'yarin':   ort,
        'bu_hafta': ort * 7,
        'bu_ay':   ort * 30,
      };
    } catch (e) { if (kDebugMode) debugPrint('[AiServisi.satisTahmini] $e'); return {}; }
  }




  /// Stok önerileri — _StokTab: urun_adi, stok, minimum_stok, acil, oneri_miktar, son30gun_satis
  Future<List<Map<String, dynamic>>> stokOnerisi() async {
    try {
      final db  = await Veritabani().db;
      final bas = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      final bit = DateTime.now().toIso8601String();
      final rows = await db.rawQuery('''
        SELECT u.id, u.urun_adi, u.stok,
          CASE WHEN u.minimum_stok > 0 THEN u.minimum_stok ELSE 5 END as min_stok,
          COALESCE(s.satis_adet, 0) as son30gun_satis
        FROM urunler u
        LEFT JOIN (
          SELECT sk.urun_id, SUM(sk.miktar) as satis_adet
          FROM satis_kalem sk
          JOIN satislar st ON sk.satis_id = st.id
          WHERE st.tarih BETWEEN ? AND ? AND st.iptal=0 AND st.is_deleted=0
          GROUP BY sk.urun_id
        ) s ON s.urun_id = u.id
        WHERE u.aktif=1 AND u.is_deleted=0
          AND u.stok <= CASE WHEN u.minimum_stok > 0 THEN u.minimum_stok ELSE 5 END
        ORDER BY u.stok ASC LIMIT 20
      ''', [bas, bit]);
      return rows.map((r) {
        final stok    = (r['stok'] as num?)?.toDouble() ?? 0;
        final minStok = (r['min_stok'] as num?)?.toDouble() ?? 5;
        final satis30 = (r['son30gun_satis'] as num?)?.toDouble() ?? 0;
        final oneri   = satis30 > 0 ? (satis30 * 1.5).ceil().toDouble() : (minStok * 3);
        return {
          'urun_adi':       r['urun_adi'],
          'stok':           stok,
          'minimum_stok':   minStok,
          'son30gun_satis': satis30,
          'oneri_miktar':   oneri,
          'acil':           stok == 0,
          'neden':          stok == 0 ? 'Stok tukendi!' : 'Kritik stok',
        };
      }).toList();
    } catch (e) { if (kDebugMode) debugPrint('[AiServisi.stokOnerisi] $e'); return []; }
  }

  /// Promosyon önerileri — _PromosyonTab: urun_adi, stok, satis_fiyati, indirimli_fiyat, satis_adet
  Future<List<Map<String, dynamic>>> promosyonOnerisi() async {
    try {
      final db  = await Veritabani().db;
      final bas = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      final bit = DateTime.now().toIso8601String();
      final rows = await db.rawQuery('''
        SELECT u.id, u.urun_adi, u.stok, u.satis_fiyati,
               COALESCE(u.alis_fiyat, 0) as alis_fiyat,
               COALESCE(s.satis_adet, 0) as satis_adet,
               CASE WHEN u.alis_fiyat > 0
                 THEN ((u.satis_fiyati - u.alis_fiyat) / u.alis_fiyat * 100)
                 ELSE 0 END as kar_marji
        FROM urunler u
        LEFT JOIN (
          SELECT sk.urun_id, SUM(sk.miktar) as satis_adet
          FROM satis_kalem sk
          JOIN satislar st ON sk.satis_id = st.id
          WHERE st.tarih BETWEEN ? AND ? AND st.iptal=0 AND st.is_deleted=0
          GROUP BY sk.urun_id
        ) s ON s.urun_id = u.id
        WHERE u.aktif=1 AND u.is_deleted=0 AND u.stok > 0
        ORDER BY (u.stok * COALESCE(u.satis_fiyati, 0)) DESC
        LIMIT 10
      ''', [bas, bit]);
      return rows.map((r) {
        final fiyat  = (r['satis_fiyati'] as num?)?.toDouble() ?? 0;
        final satis  = (r['satis_adet'] as num?)?.toDouble() ?? 0;
        final marji  = (r['kar_marji'] as num?)?.toDouble() ?? 0;
        final stok   = (r['stok'] as num?)?.toDouble() ?? 0;
        final ind    = satis == 0 ? 15 : (marji > 40 ? 10 : 5);
        return {
          'urun_adi':        r['urun_adi'],
          'stok':            stok,
          'satis_fiyati':    fiyat,
          'indirimli_fiyat': fiyat * (1 - ind / 100),
          'satis_adet':      satis,
          'kar_marji':       marji,
          'onerilenIndirim': ind,
          'neden':           satis == 0 ? 'Son 30 gunde satilmadi' :
                             marji > 40 ? 'Yuksek kar marji' : 'Yuksek stok degeri',
        };
      }).toList();
    } catch (e) { if (kDebugMode) debugPrint('[AiServisi.promosyonOnerisi] $e'); return []; }
  }

  /// En çok satanlar — AI panel Özet sekmesi
  Future<List<Map<String, dynamic>>> enCokSatanlar({int limit = 5}) async {
    try {
      final db  = await Veritabani().db;
      final bas = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      final bit = DateTime.now().toIso8601String();
      final rows = await db.rawQuery('''
        SELECT sk.urun_adi, sk.urun_adi as ad,
               SUM(sk.miktar) as miktar, SUM(sk.miktar) as toplam_adet,
               SUM(sk.toplam_tutar) as tutar, SUM(sk.toplam_tutar) as toplam_tutar
        FROM satis_kalem sk JOIN satislar s ON sk.satis_id=s.id
        WHERE s.tarih BETWEEN ? AND ? AND s.iptal=0 AND s.is_deleted=0
        GROUP BY sk.urun_adi ORDER BY tutar DESC LIMIT ?
      ''', [bas, bit, limit]);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) { if (kDebugMode) debugPrint('[AiServisi.enCokSatanlar] $e'); return []; }
  }

  /// Cari risk — AI panel Cari Risk sekmesi
  Future<List<Map<String, dynamic>>> cariRisk() async {
    try {
      final db   = await Veritabani().db;
      // cari_hareket'ten güncel bakiyeyi hesapla
      final rows = await db.rawQuery('''
        SELECT c.id, c.unvan, c.cari_tipi,
               COALESCE(SUM(ch.borc) - SUM(ch.alacak), c.bakiye, 0) as gercek_bakiye,
               COUNT(ch.id) as hareket_sayisi,
               MAX(ch.tarih) as son_hareket
        FROM cari c
        LEFT JOIN cari_hareket ch ON ch.cari_id = c.id AND ch.is_deleted = 0
        WHERE c.is_deleted=0 AND c.aktif=1
        GROUP BY c.id
        HAVING gercek_bakiye > 0
        ORDER BY gercek_bakiye DESC
        LIMIT 15
      ''');
      if (rows.isEmpty) {
        // Bakiye yoksa en az hareketi olan carileri göster
        final alt = await db.rawQuery('''
          SELECT c.id, c.unvan, c.cari_tipi, c.bakiye,
                 COUNT(ch.id) as hareket_sayisi
          FROM cari c
          LEFT JOIN cari_hareket ch ON ch.cari_id = c.id AND ch.is_deleted = 0
          WHERE c.is_deleted=0 AND c.aktif=1
          GROUP BY c.id
          ORDER BY c.bakiye DESC, hareket_sayisi ASC
          LIMIT 10
        ''');
        return alt.map((r) {
          final bak = (r['bakiye'] as num?)?.toDouble() ?? 0;
          return {
            'unvan': r['unvan'],
            'bakiye': bak,
            'risk': 'Bilgi',
            'hareketSayisi': r['hareket_sayisi'],
          };
        }).toList();
      }
      return rows.map((r) {
        final bak = (r['gercek_bakiye'] as num?)?.toDouble() ?? 0;
        return {
          'id':             r['id'],
          'unvan':          r['unvan'],
          'cari_tipi':      r['cari_tipi'],
          'bakiye':         bak,
          'limit_tutari':   0.0,
          'limit_doluluk':  0.0,
          'risk':           bak > 5000 ? 'Yuksek' : bak > 1000 ? 'Orta' : 'Dusuk',
          'hareketSayisi':  r['hareket_sayisi'],
          'sonHareket':     r['son_hareket'],
        };
      }).toList();
    } catch (e) { if (kDebugMode) debugPrint('[AiServisi.cariRisk] $e'); return []; }
  }
}
