// lib/saglayicilar/riverpod/kar_zarar_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/aktif_sube_servisi.dart';

part 'kar_zarar_provider.g.dart';

class KarZararFiltre {
  final DateTime basTarih, bitTarih;
  final String donem;
  KarZararFiltre({required this.basTarih, required this.bitTarih, this.donem = 'Bugun'});
  KarZararFiltre copyWith({DateTime? basTarih, DateTime? bitTarih, String? donem}) =>
      KarZararFiltre(basTarih: basTarih ?? this.basTarih,
          bitTarih: bitTarih ?? this.bitTarih, donem: donem ?? this.donem);
  static KarZararFiltre bugun() {
    final now = DateTime.now();
    return KarZararFiltre(
      basTarih: DateTime(now.year, now.month, now.day),
      bitTarih: DateTime(now.year, now.month, now.day, 23, 59, 59));
  }
}

@riverpod
class KarZararFiltresi extends _$KarZararFiltresi {
  @override
  KarZararFiltre build() => KarZararFiltre.bugun();

  void donemAyarla(String donem) {
    final now = DateTime.now();
    late DateTime bas, bit;
    switch (donem) {
      case 'Bugun':
        bas = DateTime(now.year, now.month, now.day);
        bit = DateTime(now.year, now.month, now.day, 23, 59, 59);
      case 'Bu Hafta':
        final pzt = now.subtract(Duration(days: now.weekday - 1));
        bas = DateTime(pzt.year, pzt.month, pzt.day);
        bit = DateTime(now.year, now.month, now.day, 23, 59, 59);
      case 'Bu Ay':
        bas = DateTime(now.year, now.month, 1);
        bit = DateTime(now.year, now.month, now.day, 23, 59, 59);
      case 'Bu Yil':
        bas = DateTime(now.year, 1, 1);
        bit = DateTime(now.year, 12, 31, 23, 59, 59);
      default: return;
    }
    state = state.copyWith(basTarih: bas, bitTarih: bit, donem: donem);
  }

  void tarihAyarla(DateTime bas, DateTime bit) =>
      state = state.copyWith(basTarih: bas, bitTarih: bit, donem: 'Ozel');
}

class KarZararVeri {
  final double ciro, alisMaliyeti, brutKar, netKar, kdvToplam, giderToplam, iskonto;
  final int satisSayisi;
  final List<Map<String, dynamic>> odemeByTur, kategorGider, aylikVeri;
  const KarZararVeri({
    required this.ciro, required this.alisMaliyeti, required this.brutKar,
    required this.netKar, required this.kdvToplam, required this.giderToplam,
    required this.iskonto, required this.satisSayisi,
    required this.odemeByTur, required this.kategorGider, required this.aylikVeri,
  });
  double get brutKarOrani => ciro > 0 ? (brutKar / ciro * 100) : 0;
  double get netKarOrani  => ciro > 0 ? (netKar  / ciro * 100) : 0;
}

@riverpod
Future<KarZararVeri> karZarar(KarZararRef ref) async {
  final f   = ref.watch(karZararFiltresiProvider);
  final db  = await Veritabani().db;
  final bas = f.basTarih.toIso8601String();
  final bit = f.bitTarih.toIso8601String();

  // ÖNCEDEN Kâr-Zarar raporunda hiç şube filtresi yoktu — birden fazla
  // şubeniz varsa rapor her zaman TÜM şubelerin toplamını gösteriyordu.
  final subeId = AktifSubeServisi().subeId;
  final satisSubeKosulu = subeId != null ? 'AND s.sube_id = ?' : '';
  final satisSubeKosuluDuzSatislar = subeId != null ? 'AND sube_id = ?' : '';
  final giderSubeKosulu = subeId != null ? 'AND g.sube_id = ?' : '';
  final subeArgs = subeId != null ? [subeId] : <Object?>[];

  final results = await Future.wait([
    db.rawQuery('''SELECT COUNT(*) as sayi, COALESCE(SUM(genel_toplam),0) as ciro,
      COALESCE(SUM(iskonto_tutar),0) as iskonto, COALESCE(SUM(kdv_tutar),0) as kdv
      FROM satislar WHERE datetime(tarih) BETWEEN datetime(?) AND datetime(?)
      AND iptal=0 AND is_deleted=0 $satisSubeKosuluDuzSatislar''', [bas, bit, ...subeArgs]),
    db.rawQuery('''SELECT COALESCE(SUM(CASE WHEN sk.alis_fiyat>0 THEN sk.miktar*sk.alis_fiyat
      ELSE sk.miktar*COALESCE(u.alis_fiyat,0) END),0) as maliyet
      FROM satis_kalem sk JOIN satislar s ON sk.satis_id=s.id LEFT JOIN urunler u ON sk.urun_id=u.id
      WHERE datetime(s.tarih) BETWEEN datetime(?) AND datetime(?) AND s.iptal=0 AND s.is_deleted=0
      $satisSubeKosulu''', [bas, bit, ...subeArgs]),
    // 🔴 Derin analizde bulundu: 'giderler' tablosu soft-delete'e
    // (deleted_at) geçirildi ama bu rapor kendi ham SQL'ini kullandığı
    // için filtrelemiyordu — silinen bir gider bile Net Kâr hesabını
    // etkilemeye devam ediyordu.
    db.rawQuery('''SELECT COALESCE(SUM(tutar),0) as toplam FROM giderler g
      WHERE datetime(tarih) BETWEEN datetime(?) AND datetime(?) AND g.deleted_at IS NULL $giderSubeKosulu''',
      [bas, bit, ...subeArgs]),
    db.rawQuery('''SELECT odeme_yontemi, COALESCE(SUM(genel_toplam),0) as toplam FROM satislar
      WHERE datetime(tarih) BETWEEN datetime(?) AND datetime(?) AND iptal=0 AND is_deleted=0
      $satisSubeKosuluDuzSatislar GROUP BY odeme_yontemi''', [bas, bit, ...subeArgs]),
    db.rawQuery('''SELECT gk.ad as kategori, COALESCE(SUM(g.tutar),0) as toplam FROM giderler g
      LEFT JOIN gider_kategoriler gk ON g.kategori_id=gk.id
      WHERE datetime(g.tarih) BETWEEN datetime(?) AND datetime(?) AND g.deleted_at IS NULL $giderSubeKosulu
      GROUP BY g.kategori_id ORDER BY toplam DESC''', [bas, bit, ...subeArgs]),
    // 🔴 Derin analizde bulundu: DATE('now') SQLite'ta VARSAYILAN OLARAK
    // UTC kullanır, ama 'tarih' sütunu yerel saatle yazılıyor (bkz.
    // kasa_deposu.dart'taki aynı hata sınıfının notu) — Türkiye UTC+3
    // olduğu için yerel 00:00-03:00 arası pencere sınırı bir gün/ay
    // kayabiliyordu. 'localtime' değiştiricisi eklendi.
    db.rawQuery('''SELECT strftime('%Y-%m',tarih) as ay, COALESCE(SUM(genel_toplam),0) as ciro, COUNT(*) as sayi
      FROM satislar WHERE tarih>=date('now','localtime','-5 months','start of month')
      AND iptal=0 AND is_deleted=0 $satisSubeKosuluDuzSatislar GROUP BY ay ORDER BY ay''', subeArgs),
  ]);

  final s    = (results[0] as List<Map<String, dynamic>>).first;
  final m    = (results[1] as List<Map<String, dynamic>>).first;
  final g    = (results[2] as List<Map<String, dynamic>>).first;
  final ciro = (s['ciro'] as num?)?.toDouble() ?? 0;
  final ali  = (m['maliyet'] as num?)?.toDouble() ?? 0;
  final gid  = (g['toplam'] as num?)?.toDouble() ?? 0;

  return KarZararVeri(
    ciro: ciro, alisMaliyeti: ali, brutKar: ciro - ali,
    netKar: ciro - ali - gid, kdvToplam: (s['kdv'] as num?)?.toDouble() ?? 0,
    giderToplam: gid, iskonto: (s['iskonto'] as num?)?.toDouble() ?? 0,
    satisSayisi: (s['sayi'] as int?) ?? 0,
    odemeByTur:  results[3] as List<Map<String, dynamic>>,
    kategorGider:results[4] as List<Map<String, dynamic>>,
    aylikVeri:   results[5] as List<Map<String, dynamic>>,
  );
}
