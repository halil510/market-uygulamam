// lib/servisler/abc_stok_analizi_servisi.dart
//
// FAZ 8 — Rapor/Analiz (erp_roadmap madde 15): ABC stok analizi. Klasik
// Pareto/ABC sınıflandırması — ürünler seçilen dönemdeki ciroya göre
// büyükten küçüğe sıralanır, kümülatif ciro yüzdesi hesaplanır:
//   A sınıfı: kümülatif %0-80  (genelde cironun büyük kısmını üreten az sayıda ürün)
//   B sınıfı: kümülatif %80-95
//   C sınıfı: kümülatif %95-100 (çok sayıda düşük cirolu ürün)
// Salt okunur — hiçbir tabloya yazmaz, fiyat/stok kararını OTOMATİK
// uygulamaz, sadece görüntüler.
import '../veri/database/veritabani.dart';

enum AbcSinifi { a, b, c }

extension AbcSinifiUzanti on AbcSinifi {
  String get etiket => switch (this) {
        AbcSinifi.a => 'A',
        AbcSinifi.b => 'B',
        AbcSinifi.c => 'C',
      };
}

class AbcUrunSatiri {
  final int urunId;
  final String urunAdi;
  final double toplamTutar;
  final double toplamMiktar;
  final double kumulatifYuzde;
  final AbcSinifi sinif;

  const AbcUrunSatiri({
    required this.urunId,
    required this.urunAdi,
    required this.toplamTutar,
    required this.toplamMiktar,
    required this.kumulatifYuzde,
    required this.sinif,
  });
}

class AbcUrunGirdi {
  final int urunId;
  final String urunAdi;
  final double tutar;
  final double miktar;
  const AbcUrunGirdi(
      {required this.urunId,
      required this.urunAdi,
      required this.tutar,
      required this.miktar});
}

/// Saf fonksiyon: verilen ürün cirolarını büyükten küçüğe sıralayıp
/// kümülatif yüzdeye göre A/B/C sınıfı atar. Toplam ciro 0 ise (hiç
/// satış yoksa) boş liste döner.
List<AbcUrunSatiri> abcSinifiHesapla(List<AbcUrunGirdi> girdiler) {
  final toplamCiro = girdiler.fold<double>(0, (t, g) => t + g.tutar);
  if (toplamCiro <= 0) return [];

  final sirali = [...girdiler]..sort((a, b) => b.tutar.compareTo(a.tutar));
  var kumulatif = 0.0;
  return sirali.map((g) {
    kumulatif += g.tutar;
    final yuzde = (kumulatif / toplamCiro) * 100;
    final sinif = yuzde <= 80
        ? AbcSinifi.a
        : yuzde <= 95
            ? AbcSinifi.b
            : AbcSinifi.c;
    return AbcUrunSatiri(
      urunId: g.urunId,
      urunAdi: g.urunAdi,
      toplamTutar: g.tutar,
      toplamMiktar: g.miktar,
      kumulatifYuzde: yuzde,
      sinif: sinif,
    );
  }).toList();
}

class AbcStokAnaliziServisi {
  /// [gunSayisi]: analiz penceresi (varsayılan son 90 gün).
  Future<List<AbcUrunSatiri>> analizGetir({int gunSayisi = 90}) async {
    final db = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT sk.urun_id AS urun_id, sk.urun_adi AS urun_adi,
             SUM(sk.toplam_tutar) AS tutar, SUM(sk.miktar) AS miktar
      FROM satis_kalem sk
      JOIN satislar s ON s.id = sk.satis_id
      WHERE s.iptal = 0 AND s.is_deleted = 0
        AND DATE(s.tarih) >= DATE('now', 'localtime', ?)
      GROUP BY sk.urun_id
    ''', ['-$gunSayisi days']);

    final girdiler = rows
        .map((r) => AbcUrunGirdi(
              urunId: r['urun_id'] as int,
              urunAdi: r['urun_adi'] as String? ?? '—',
              tutar: (r['tutar'] as num?)?.toDouble() ?? 0,
              miktar: (r['miktar'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
    return abcSinifiHesapla(girdiler);
  }
}
