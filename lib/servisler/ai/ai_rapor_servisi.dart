// lib/servisler/ai/ai_rapor_servisi.dart
// Gerçek DB şeması:
// satislar: fis_no, tarih, genel_toplam, iskonto_tutar, kdv_tutar, odeme_yontemi, iptal, is_deleted
// satis_kalem: satis_id, urun_id, urun_adi, miktar, birim_fiyat, toplam_tutar, alis_fiyat
// urunler: urun_adi, stok, satis_fiyati, alis_fiyat, ana_grup, marka, alan1, minimum_stok, is_deleted
// cari_hareket: cari_id, tarih, fis_tipi, borc, alacak, bakiye, odeme_turu
// kasa_hareketleri: hareket_tipi, tutar, bakiye_sonrasi, tarih

import 'dart:math' show sqrt;
import 'package:intl/intl.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/log_servisi.dart';
import '../aktif_sube_servisi.dart';
import '../stok_devir_analizi_servisi.dart';

double _ortalama(List<double> degerler) =>
    degerler.isEmpty ? 0 : degerler.reduce((a, b) => a + b) / degerler.length;

/// Saf fonksiyon (DB'den bağımsız, test edilebilir): verilen değerler
/// kümesinde z-skoru [esikZSkoru] veya üzeri olan (istatistiksel olarak
/// sıra dışı) değerleri döner. En az 5 değer + sıfırdan farklı standart
/// sapma gerekir — aksi halde boş liste (güvenilir tespit için yetersiz
/// veri/varyans).
List<double> zSkoruAnormalDegerleriBul(List<double> degerler, {double esikZSkoru = 2.5}) {
  if (degerler.length < 5) return const [];
  final ort = _ortalama(degerler);
  final varyans =
      degerler.map((d) => (d - ort) * (d - ort)).reduce((a, b) => a + b) / degerler.length;
  final stdSapma = varyans <= 0 ? 0.0 : sqrt(varyans);
  if (stdSapma <= 0) return const [];
  return degerler.where((d) => (d - ort) / stdSapma >= esikZSkoru).toList();
}

class AiRaporServisi {
  static final _p = NumberFormat('#,##0.00', 'tr_TR');
  static final _t = DateFormat('dd.MM.yyyy');

  static String _bas(DateTime d) => d.toIso8601String();
  static String _bit(DateTime d) => d.toIso8601String();

  // ── Z RAPORU ─────────────────────────────────────────────────────────────
  static Future<String> zRaporu(DateTime tarih) async {
    try {
      final db  = await Veritabani().db;
      final bas = DateTime(tarih.year, tarih.month, tarih.day);
      final bit = DateTime(tarih.year, tarih.month, tarih.day, 23, 59, 59);
      // ÖNCEDEN Günlük Rapor'da (Z Raporu) hiç şube filtresi yoktu.
      final subeId = AktifSubeServisi().subeId;
      final subeKosulu = subeId != null ? 'AND sube_id = ?' : '';
      final subeKosuluJoin = subeId != null ? 'AND s.sube_id = ?' : '';
      final subeArgs = subeId != null ? [subeId] : <Object?>[];

      final s = (await db.rawQuery('''
        SELECT COUNT(*) as adet,
               COALESCE(SUM(genel_toplam),0) as ciro,
               COALESCE(SUM(iskonto_tutar),0) as iskonto,
               COALESCE(SUM(kdv_tutar),0) as kdv
        FROM satislar
        WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0 $subeKosulu
      ''', [_bas(bas), _bit(bit), ...subeArgs])).first;

      final odemeler = await db.rawQuery('''
        SELECT odeme_yontemi,
               COUNT(*) as adet,
               COALESCE(SUM(genel_toplam),0) as tutar
        FROM satislar
        WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0 $subeKosulu
        GROUP BY odeme_yontemi ORDER BY tutar DESC
      ''', [_bas(bas), _bit(bit), ...subeArgs]);

      final iadeler = (await db.rawQuery('''
        SELECT COUNT(*) as adet, COALESCE(SUM(toplam_tutar),0) as tutar
        FROM iade WHERE tarih BETWEEN ? AND ? AND deleted_at IS NULL
      ''', [_bas(bas), _bit(bit)])).first;

      final maliyet = (await db.rawQuery('''
        SELECT COALESCE(SUM(sk.miktar * COALESCE(sk.alis_fiyat,0)),0) as mal
        FROM satis_kalem sk
        JOIN satislar s ON sk.satis_id = s.id
        WHERE s.tarih BETWEEN ? AND ? AND s.iptal=0 AND s.is_deleted=0 $subeKosuluJoin
      ''', [_bas(bas), _bit(bit), ...subeArgs])).first;

      final kasa = (await db.rawQuery('''
        SELECT COALESCE(SUM(tutar),0) as toplam
        FROM kasa_hareketleri WHERE tarih BETWEEN ? AND ? AND deleted_at IS NULL $subeKosulu
      ''', [_bas(bas), _bit(bit), ...subeArgs])).first;

      // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu Z Raporu
      // (Türkiye'de perakende için yasal/muhasebe önemi taşıyan bir
      // gün sonu belgesi) "Net kâr" etiketliyordu ama GİDERLER hiç
      // düşülmüyordu — aynı hata ai_sohbet_servisi.dart'ta da vardı.
      final gider = (await db.rawQuery('''
        SELECT COALESCE(SUM(tutar),0) as toplam
        FROM giderler WHERE tarih BETWEEN ? AND ? AND deleted_at IS NULL
      ''', [_bas(bas), _bit(bit)])).first;

      final ciro  = (s['ciro'] as num?)?.toDouble() ?? 0;
      final isk   = (s['iskonto'] as num?)?.toDouble() ?? 0;
      final kdv   = (s['kdv'] as num?)?.toDouble() ?? 0;
      final mal   = (maliyet['mal'] as num?)?.toDouble() ?? 0;
      final iade  = (iadeler['tutar'] as num?)?.toDouble() ?? 0;
      final giderTutar = (gider['toplam'] as num?)?.toDouble() ?? 0;
      final kar   = ciro - mal - iade - giderTutar;

      final sb = StringBuffer();
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('📋 Z RAPORU — ${_t.format(tarih)}');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('🛒 SATIŞ');
      sb.writeln('  İşlem      : ${s['adet']} adet');
      sb.writeln('  Brüt ciro  : ${_p.format(ciro)} TL');
      sb.writeln('  İskonto    : ${_p.format(isk)} TL');
      sb.writeln('  KDV        : ${_p.format(kdv)} TL');
      sb.writeln('  Net ciro   : ${_p.format(ciro - isk)} TL');
      sb.writeln('');
      sb.writeln('💳 ÖDEME YÖNTEMLERİ');
      for (final o in odemeler) {
        final yontem = (o['odeme_yontemi']?.toString() ?? 'Diğer').padRight(10);
        sb.writeln('  $yontem : ${_p.format((o['tutar'] as num?)?.toDouble() ?? 0)} TL  (${o['adet']} işlem)');
      }
      if (odemeler.isEmpty) sb.writeln('  Satış bulunamadı');
      sb.writeln('');
      sb.writeln('↩️  İADE');
      sb.writeln('  İade sayısı : ${iadeler['adet']}');
      sb.writeln('  İade tutarı : ${_p.format(iade)} TL');
      sb.writeln('');
      sb.writeln('💰 KAR');
      sb.writeln('  Maliyet    : ${_p.format(mal)} TL');
      sb.writeln('  Giderler   : ${_p.format(giderTutar)} TL');
      sb.writeln('  Net kâr    : ${_p.format(kar)} TL');
      if (ciro > 0) sb.writeln('  Kâr marjı : %${((kar / ciro) * 100).toStringAsFixed(1)}');
      sb.writeln('');
      sb.writeln('🏦 KASA');
      sb.writeln('  Kasa hareketi: ${_p.format((kasa['toplam'] as num?)?.toDouble() ?? 0)} TL');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return sb.toString();
    } catch (e, st) {
      LogServisi().hata('AiRaporServisi.zRaporu', hata: e, yigin: st);
      return 'Z raporu hatası: $e';
    }
  }

  // ── ÜRÜN Z RAPORU ─────────────────────────────────────────────────────────
  static Future<String> urunZRaporu(DateTime tarih, {int limit = 25}) async {
    try {
      final db  = await Veritabani().db;
      final bas = DateTime(tarih.year, tarih.month, tarih.day);
      final bit = DateTime(tarih.year, tarih.month, tarih.day, 23, 59, 59);

      final rows = await db.rawQuery('''
        SELECT sk.urun_adi,
               SUM(sk.miktar) as miktar,
               SUM(sk.toplam_tutar) as tutar,
               SUM(sk.miktar * COALESCE(sk.alis_fiyat, 0)) as maliyet
        FROM satis_kalem sk
        JOIN satislar s ON sk.satis_id = s.id
        WHERE s.tarih BETWEEN ? AND ? AND s.iptal=0 AND s.is_deleted=0
        GROUP BY sk.urun_adi
        ORDER BY tutar DESC
        LIMIT ?
      ''', [_bas(bas), _bit(bit), limit]);

      if (rows.isEmpty) return '${_t.format(tarih)} tarihinde satış kaydı yok.';

      final sb = StringBuffer();
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('📦 ÜRÜN Z RAPORU — ${_t.format(tarih)}');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('${'Ürün'.padRight(24)} ${'Miktar'.padLeft(7)} ${'Tutar(TL)'.padLeft(11)} ${'Kâr(TL)'.padLeft(10)}');
      sb.writeln('─' * 55);

      double topCiro = 0, topKar = 0;
      for (final r in rows) {
        final ad = (r['urun_adi']?.toString() ?? '?');
        final adK = ad.length > 23 ? ad.substring(0, 23) : ad.padRight(23);
        final mik = (r['miktar'] as num?)?.toDouble() ?? 0;
        final tut = (r['tutar'] as num?)?.toDouble() ?? 0;
        final mal = (r['maliyet'] as num?)?.toDouble() ?? 0;
        final kar = tut - mal;
        topCiro += tut; topKar += kar;
        sb.writeln('$adK ${mik.toStringAsFixed(0).padLeft(7)} ${_p.format(tut).padLeft(11)} ${_p.format(kar).padLeft(10)}');
      }
      sb.writeln('─' * 55);
      sb.writeln('${'TOPLAM'.padRight(24)} ${''.padLeft(7)} ${_p.format(topCiro).padLeft(11)} ${_p.format(topKar).padLeft(10)}');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return sb.toString();
    } catch (e, st) {
      LogServisi().hata('AiRaporServisi.urunZRaporu', hata: e, yigin: st);
      return 'Ürün Z raporu hatası: $e';
    }
  }

  // ── AYLIK RAPOR ──────────────────────────────────────────────────────────
  static Future<String> aylikRapor(DateTime tarih) async {
    try {
      final db  = await Veritabani().db;
      final bas = DateTime(tarih.year, tarih.month, 1);
      final bit = DateTime(tarih.year, tarih.month + 1, 0, 23, 59, 59);
      final ayAdi = DateFormat('MMMM yyyy', 'tr_TR').format(bas);

      final ozet = (await db.rawQuery('''
        SELECT COUNT(*) as islem,
               COALESCE(SUM(genel_toplam),0) as ciro,
               COALESCE(SUM(iskonto_tutar),0) as iskonto,
               COALESCE(SUM(kdv_tutar),0) as kdv
        FROM satislar WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
      ''', [_bas(bas), _bit(bit)])).first;

      final maliyet = (await db.rawQuery('''
        SELECT COALESCE(SUM(sk.miktar * COALESCE(sk.alis_fiyat,0)),0) as mal
        FROM satis_kalem sk JOIN satislar s ON sk.satis_id=s.id
        WHERE s.tarih BETWEEN ? AND ? AND s.iptal=0 AND s.is_deleted=0
      ''', [_bas(bas), _bit(bit)])).first;

      final odemeler = await db.rawQuery('''
        SELECT odeme_yontemi, COALESCE(SUM(genel_toplam),0) as tutar
        FROM satislar WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
        GROUP BY odeme_yontemi ORDER BY tutar DESC
      ''', [_bas(bas), _bit(bit)]);

      final enCok = await db.rawQuery('''
        SELECT sk.urun_adi, SUM(sk.miktar) as miktar, SUM(sk.toplam_tutar) as tutar
        FROM satis_kalem sk JOIN satislar s ON sk.satis_id=s.id
        WHERE s.tarih BETWEEN ? AND ? AND s.iptal=0 AND s.is_deleted=0
        GROUP BY sk.urun_adi ORDER BY tutar DESC LIMIT 10
      ''', [_bas(bas), _bit(bit)]);

      final gunluk = await db.rawQuery('''
        SELECT DATE(tarih) as gun,
               COUNT(*) as islem,
               COALESCE(SUM(genel_toplam),0) as ciro
        FROM satislar WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
        GROUP BY DATE(tarih) ORDER BY gun
      ''', [_bas(bas), _bit(bit)]);

      // 🔴🔴 Derin analizde bulundu: Z Raporu'nda bulduğum AYNI hata —
      // "Net kâr" giderleri hiç düşmüyordu.
      final giderR = (await db.rawQuery('''
        SELECT COALESCE(SUM(tutar),0) as toplam
        FROM giderler WHERE tarih BETWEEN ? AND ? AND deleted_at IS NULL
      ''', [_bas(bas), _bit(bit)])).first;

      final ciro = (ozet['ciro'] as num?)?.toDouble() ?? 0;
      final isk  = (ozet['iskonto'] as num?)?.toDouble() ?? 0;
      final kdv  = (ozet['kdv'] as num?)?.toDouble() ?? 0;
      final mal  = (maliyet['mal'] as num?)?.toDouble() ?? 0;
      final giderTutar = (giderR['toplam'] as num?)?.toDouble() ?? 0;
      final kar  = ciro - mal - giderTutar;

      final sb = StringBuffer();
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('📅 AYLIK RAPOR — $ayAdi');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('📊 ÖZET');
      sb.writeln('  İşlem sayısı : ${ozet['islem']}');
      sb.writeln('  Brüt ciro    : ${_p.format(ciro)} TL');
      sb.writeln('  İskonto      : ${_p.format(isk)} TL');
      sb.writeln('  KDV          : ${_p.format(kdv)} TL');
      sb.writeln('  Maliyet      : ${_p.format(mal)} TL');
      sb.writeln('  Giderler     : ${_p.format(giderTutar)} TL');
      sb.writeln('  Net kâr      : ${_p.format(kar)} TL');
      if (ciro > 0) sb.writeln('  Kâr marjı   : %${((kar / ciro) * 100).toStringAsFixed(1)}');
      sb.writeln('');
      sb.writeln('💳 ÖDEME');
      for (final o in odemeler) {
        sb.writeln('  ${(o['odeme_yontemi']?.toString() ?? 'Diğer').padRight(12)}: ${_p.format((o['tutar'] as num?)?.toDouble() ?? 0)} TL');
      }
      sb.writeln('');
      sb.writeln('🏆 EN ÇOK SATAN 10 ÜRÜN');
      for (int i = 0; i < enCok.length; i++) {
        final r = enCok[i];
        final ad = r['urun_adi']?.toString() ?? '?';
        sb.writeln('  ${(i+1).toString().padLeft(2)}. ${ad.length > 22 ? ad.substring(0,22) : ad} — ${_p.format((r['tutar'] as num?)?.toDouble() ?? 0)} TL');
      }
      if (gunluk.isNotEmpty) {
        sb.writeln('');
        sb.writeln('📈 GÜNLÜK DAĞILIM');
        final maxCiro = gunluk.map((g) => (g['ciro'] as num?)?.toDouble() ?? 0).reduce((a, b) => a > b ? a : b);
        for (final g in gunluk) {
          final gCiro = (g['ciro'] as num?)?.toDouble() ?? 0;
          final bar = '█' * (maxCiro > 0 ? (gCiro / maxCiro * 15).round() : 0);
          sb.writeln('  ${g['gun']} $bar ${_p.format(gCiro)} TL');
        }
      }
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return sb.toString();
    } catch (e, st) {
      LogServisi().hata('AiRaporServisi.aylikRapor', hata: e, yigin: st);
      return 'Aylık rapor hatası: $e';
    }
  }

  // ── GRUP / MARKA / ALAN1 RAPORU ───────────────────────────────────────────
  static Future<String> grupRaporu(DateTime bas, DateTime bit, {String kolon = 'ana_grup', String baslik = 'KATEGORİ'}) async {
    try {
      final db = await Veritabani().db;

      final rows = await db.rawQuery('''
        SELECT COALESCE(u.$kolon, 'Diğer') as grup,
               SUM(sk.miktar) as miktar,
               SUM(sk.toplam_tutar) as tutar,
               SUM(sk.miktar * COALESCE(sk.alis_fiyat, 0)) as maliyet,
               COUNT(DISTINCT s.id) as satis
        FROM satis_kalem sk
        JOIN satislar s ON sk.satis_id = s.id
        LEFT JOIN urunler u ON sk.urun_id = u.id
        WHERE s.tarih BETWEEN ? AND ? AND s.iptal=0 AND s.is_deleted=0
        GROUP BY u.$kolon
        ORDER BY tutar DESC
      ''', [_bas(bas), _bit(bit)]);

      if (rows.isEmpty) return 'Bu dönemde $baslik bazında satış verisi yok.';

      final donem = '${_t.format(bas)} - ${_t.format(bit)}';
      final topTutar = rows.fold<double>(0.0, (s, r) => s + ((r['tutar'] as num?)?.toDouble() ?? 0));

      final sb = StringBuffer();
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('📂 $baslik RAPORU — $donem');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      for (final r in rows) {
        final grup  = r['grup']?.toString() ?? 'Diğer';
        final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
        final mal   = (r['maliyet'] as num?)?.toDouble() ?? 0;
        final kar   = tutar - mal;
        final oran  = topTutar > 0 ? (tutar / topTutar * 100) : 0;
        final bar   = '█' * ((oran / 5).round().clamp(0, 20));

        sb.writeln('');
        sb.writeln('▸ $grup  (%${oran.toStringAsFixed(1)})');
        sb.writeln('  $bar');
        sb.writeln('  Ciro   : ${_p.format(tutar)} TL');
        sb.writeln('  Kâr    : ${_p.format(kar)} TL');
        sb.writeln('  İşlem  : ${r['satis']}');
      }
      sb.writeln('');
      sb.writeln('──────────────────────────────');
      sb.writeln('TOPLAM: ${_p.format(topTutar)} TL');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return sb.toString();
    } catch (e, st) {
      LogServisi().hata('AiRaporServisi.grupRaporu', hata: e, yigin: st);
      return '$baslik raporu hatası: $e';
    }
  }

  // ── KÂR DEĞİŞİM AÇIKLAMASI (FAZ 10 — erp_roadmap madde 24) ────────────────
  // Son [gunSayisi] gün ile ondan önceki AYNI uzunluktaki dönemi
  // karşılaştırır, kârdaki değişimi ciro/maliyet/gider kırılımına ayırır
  // ve ciroyu en çok düşüren/artıran ürünleri listeler. Salt okuma —
  // hiçbir veriye yazmaz, sadece AÇIKLAR.
  static Future<String> karDegisimAciklama({int gunSayisi = 30}) async {
    try {
      final db = await Veritabani().db;
      final simdi = DateTime.now();
      final bit2 = DateTime(simdi.year, simdi.month, simdi.day, 23, 59, 59);
      final bas2 = bit2.subtract(Duration(days: gunSayisi));
      final bit1 = bas2.subtract(const Duration(seconds: 1));
      final bas1 = bit1.subtract(Duration(days: gunSayisi));

      Future<Map<String, double>> ozet(DateTime b, DateTime e) async {
        final s = (await db.rawQuery('''
          SELECT COALESCE(SUM(genel_toplam),0) as ciro
          FROM satislar WHERE tarih BETWEEN ? AND ? AND iptal=0 AND is_deleted=0
        ''', [_bas(b), _bit(e)])).first;
        final m = (await db.rawQuery('''
          SELECT COALESCE(SUM(sk.miktar * COALESCE(sk.alis_fiyat,0)),0) as mal
          FROM satis_kalem sk JOIN satislar st ON sk.satis_id = st.id
          WHERE st.tarih BETWEEN ? AND ? AND st.iptal=0 AND st.is_deleted=0
        ''', [_bas(b), _bit(e)])).first;
        final g = (await db.rawQuery('''
          SELECT COALESCE(SUM(tutar),0) as gider
          FROM giderler WHERE tarih BETWEEN ? AND ? AND deleted_at IS NULL
        ''', [_bas(b), _bit(e)])).first;
        final ciro = (s['ciro'] as num?)?.toDouble() ?? 0;
        final mal = (m['mal'] as num?)?.toDouble() ?? 0;
        final gider = (g['gider'] as num?)?.toDouble() ?? 0;
        return {'ciro': ciro, 'mal': mal, 'gider': gider, 'kar': ciro - mal - gider};
      }

      final onceki = await ozet(bas1, bit1);
      final guncel = await ozet(bas2, bit2);
      final karFarki = guncel['kar']! - onceki['kar']!;
      final ciroFarki = guncel['ciro']! - onceki['ciro']!;
      final malFarki = guncel['mal']! - onceki['mal']!;
      final giderFarki = guncel['gider']! - onceki['gider']!;

      // Ciroyu en çok düşüren/artıran ürünler (iki dönem kıyası).
      Future<Map<String, double>> urunCirolari(DateTime b, DateTime e) async {
        final rows = await db.rawQuery('''
          SELECT sk.urun_adi, SUM(sk.toplam_tutar) as tutar
          FROM satis_kalem sk JOIN satislar s ON sk.satis_id = s.id
          WHERE s.tarih BETWEEN ? AND ? AND s.iptal=0 AND s.is_deleted=0
          GROUP BY sk.urun_adi
        ''', [_bas(b), _bit(e)]);
        return {
          for (final r in rows)
            (r['urun_adi'] as String? ?? '—'): (r['tutar'] as num?)?.toDouble() ?? 0,
        };
      }

      final urunOnceki = await urunCirolari(bas1, bit1);
      final urunGuncel = await urunCirolari(bas2, bit2);
      final tumUrunler = {...urunOnceki.keys, ...urunGuncel.keys};
      final farklar = tumUrunler
          .map((u) => MapEntry(u, (urunGuncel[u] ?? 0) - (urunOnceki[u] ?? 0)))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final enCokDusenler = farklar.where((f) => f.value < -0.01).take(3).toList();
      final enCokArtanlar =
          farklar.reversed.where((f) => f.value > 0.01).take(3).toList();

      final sb = StringBuffer();
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('🔍 KÂR DEĞİŞİM AÇIKLAMASI');
      sb.writeln('   (Son $gunSayisi gün vs önceki $gunSayisi gün)');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln(karFarki >= 0
          ? '📈 Kâr ${_p.format(karFarki)} TL ARTTI'
          : '📉 Kâr ${_p.format(-karFarki)} TL DÜŞTÜ');
      sb.writeln('');
      sb.writeln('Önceki dönem kâr : ${_p.format(onceki['kar'] ?? 0)} TL');
      sb.writeln('Bu dönem kâr      : ${_p.format(guncel['kar'] ?? 0)} TL');
      sb.writeln('');
      sb.writeln('KIRILIM (bu dönem − önceki dönem):');
      sb.writeln('  Ciro değişimi   : ${ciroFarki >= 0 ? '+' : ''}${_p.format(ciroFarki)} TL');
      sb.writeln('  Maliyet değişimi: ${malFarki >= 0 ? '+' : ''}${_p.format(malFarki)} TL'
          '${malFarki > 0 ? ' (maliyet arttı → kârı düşürür)' : ''}');
      sb.writeln('  Gider değişimi  : ${giderFarki >= 0 ? '+' : ''}${_p.format(giderFarki)} TL'
          '${giderFarki > 0 ? ' (gider arttı → kârı düşürür)' : ''}');
      if (enCokDusenler.isNotEmpty) {
        sb.writeln('');
        sb.writeln('⬇️  Cirosu en çok düşen ürünler:');
        for (final f in enCokDusenler) {
          sb.writeln('  • ${f.key}: ${_p.format(f.value)} TL');
        }
      }
      if (enCokArtanlar.isNotEmpty) {
        sb.writeln('');
        sb.writeln('⬆️  Cirosu en çok artan ürünler:');
        for (final f in enCokArtanlar) {
          sb.writeln('  • ${f.key}: +${_p.format(f.value)} TL');
        }
      }
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return sb.toString();
    } catch (e, st) {
      LogServisi().hata('AiRaporServisi.karDegisimAciklama', hata: e, yigin: st);
      return 'Kâr değişim açıklaması hatası: $e';
    }
  }

  // ── ANORMAL İŞLEM TESPİTİ (FAZ 10 — erp_roadmap madde 24) ──────────────────
  // Son [gunSayisi] gündeki satış ve iade işlemlerinde, dönemin ortalama
  // + standart sapmasına göre istatistiksel olarak SIRA DIŞI (z-skoru
  // yüksek) tekil işlemleri işaretler. Bu bir SUÇLAMA değil, "gözden
  // geçirmeye değer" bir işarettir — fiyat girişi hatası, mükerrer kayıt
  // veya gerçekten büyük bir müşteri siparişi olabilir.
  static Future<String> anormalIslemleriTespitEt({int gunSayisi = 30}) async {
    try {
      final db = await Veritabani().db;
      final bugun = DateTime.now();
      final bas = DateTime(bugun.year, bugun.month, bugun.day)
          .subtract(Duration(days: gunSayisi));

      final satislar = await db.rawQuery('''
        SELECT fis_no, tarih, genel_toplam FROM satislar
        WHERE tarih >= ? AND iptal=0 AND is_deleted=0
      ''', [_bas(bas)]);
      final iadeler = await db.rawQuery('''
        SELECT fis_no, tarih, toplam_tutar FROM iade
        WHERE tarih >= ? AND deleted_at IS NULL
      ''', [_bas(bas)]);

      double alanDegeri(Map<String, Object?> r, String alan) =>
          (r[alan] as num?)?.toDouble() ?? 0;

      List<Map<String, Object?>> anormalBul(
          List<Map<String, Object?>> rows, String alan) {
        final degerler = rows.map((r) => alanDegeri(r, alan)).toList();
        final anormalDegerler = zSkoruAnormalDegerleriBul(degerler);
        if (anormalDegerler.isEmpty) return const [];
        return rows.where((r) => anormalDegerler.contains(alanDegeri(r, alan))).toList()
          ..sort((a, b) => alanDegeri(b, alan).compareTo(alanDegeri(a, alan)));
      }

      final anormalSatis = anormalBul(satislar, 'genel_toplam');
      final anormalIade = anormalBul(iadeler, 'toplam_tutar');
      final satisOrt = _ortalama(satislar.map((r) => alanDegeri(r, 'genel_toplam')).toList());
      final iadeOrt = _ortalama(iadeler.map((r) => alanDegeri(r, 'toplam_tutar')).toList());

      final sb = StringBuffer();
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('🚨 ANORMAL İŞLEM TESPİTİ (Son $gunSayisi Gün)');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      if (anormalSatis.isEmpty && anormalIade.isEmpty) {
        sb.writeln('Bu dönemde istatistiksel olarak sıra dışı bir satış/iade '
            'işlemi bulunamadı.');
        if (satislar.length < 5 && iadeler.length < 5) {
          sb.writeln('(Not: güvenilir bir tespit için en az 5 işlem gerekir.)');
        }
      } else {
        if (anormalSatis.isNotEmpty) {
          sb.writeln('💰 Sıra dışı büyüklükte satışlar '
              '(ortalama: ${_p.format(satisOrt)} TL):');
          for (final r in anormalSatis.take(5)) {
            sb.writeln('  • Fiş ${r['fis_no']}: ${_p.format((r['genel_toplam'] as num?)?.toDouble() ?? 0)} TL');
          }
        }
        if (anormalIade.isNotEmpty) {
          sb.writeln('');
          sb.writeln('↩️  Sıra dışı büyüklükte iadeler '
              '(ortalama: ${_p.format(iadeOrt)} TL):');
          for (final r in anormalIade.take(5)) {
            sb.writeln('  • Fiş ${r['fis_no']}: ${_p.format((r['toplam_tutar'] as num?)?.toDouble() ?? 0)} TL');
          }
        }
        sb.writeln('');
        sb.writeln('ℹ️  Bu bir suçlama değil, gözden geçirmeye değer bir '
            'işarettir — fiyat girişi hatası, mükerrer kayıt veya gerçek '
            'büyük bir sipariş olabilir.');
      }
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return sb.toString();
    } catch (e, st) {
      LogServisi().hata('AiRaporServisi.anormalIslemleriTespitEt', hata: e, yigin: st);
      return 'Anormal işlem tespiti hatası: $e';
    }
  }

  // ── STOK TÜKENME TAHMİNİ (FAZ 10 — erp_roadmap madde 24) ───────────────────
  // StokDevirAnaliziServisi'nin (FAZ 8) hesapladığı satış hızı/mevcut stok
  // verisinden, "kaç güne tükenir" tahminini türetir — ayrı bir sorgu
  // yazmak yerine mevcut analiz mantığı yeniden kullanılıyor.
  static Future<String> stokTukenmeTahmini({int limit = 15}) async {
    try {
      final satirlar = await StokDevirAnaliziServisi().analizGetir(gunSayisi: 30);
      final tahminler = satirlar
          .where((s) => s.sinif != DevirSinifi.hareketsiz && s.satilanMiktar > 0)
          .map((s) {
        final gunlukTuketim = s.satilanMiktar / 30;
        final tukenmeGunu = gunlukTuketim > 0 ? s.mevcutStok / gunlukTuketim : null;
        return (s.urunAdi, s.mevcutStok, tukenmeGunu);
      }).where((t) => t.$3 != null).toList()
        ..sort((a, b) => a.$3!.compareTo(b.$3!));

      if (tahminler.isEmpty) {
        return 'Tükenme tahmini için yeterli satış hareketi bulunamadı '
            '(son 30 günde satılan + stoklu ürün yok).';
      }

      final sb = StringBuffer();
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      sb.writeln('⏳ STOK TÜKENME TAHMİNİ (satış hızına göre)');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      for (final t in tahminler.take(limit)) {
        final gun = t.$3!.round();
        final uyari = gun <= 7 ? ' 🔴' : gun <= 14 ? ' 🟡' : '';
        sb.writeln('  • ${t.$1}: ~$gun günde tükenir '
            '(stok: ${t.$2.toStringAsFixed(0)})$uyari');
      }
      sb.writeln('');
      sb.writeln('ℹ️  Son 30 günün satış hızına göre yaklaşık tahmindir, '
          'garantili teslimat/sipariş süresi dikkate alınmaz.');
      sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return sb.toString();
    } catch (e, st) {
      LogServisi().hata('AiRaporServisi.stokTukenmeTahmini', hata: e, yigin: st);
      return 'Stok tükenme tahmini hatası: $e';
    }
  }
}
