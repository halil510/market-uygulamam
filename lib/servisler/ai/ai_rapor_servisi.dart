// lib/servisler/ai/ai_rapor_servisi.dart
// Gerçek DB şeması:
// satislar: fis_no, tarih, genel_toplam, iskonto_tutar, kdv_tutar, odeme_yontemi, iptal, is_deleted
// satis_kalem: satis_id, urun_id, urun_adi, miktar, birim_fiyat, toplam_tutar, alis_fiyat
// urunler: urun_adi, stok, satis_fiyati, alis_fiyat, ana_grup, marka, alan1, minimum_stok, is_deleted
// cari_hareket: cari_id, tarih, fis_tipi, borc, alacak, bakiye, odeme_turu
// kasa_hareketleri: hareket_tipi, tutar, bakiye_sonrasi, tarih

import 'package:intl/intl.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/log_servisi.dart';
import '../aktif_sube_servisi.dart';

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
}
