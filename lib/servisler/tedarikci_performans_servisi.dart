// lib/servisler/tedarikci_performans_servisi.dart
//
// FAZ 8 — Tedarikçi Performansı (erp_roadmap madde 18). FAZ 6'da eklenen
// tedarikçi sipariş yaşam döngüsünden (beklemede→teslim_alindi/iptal,
// bkz. lib/ekranlar/tedarik/siparis_olustur_ekrani.dart) türetilen
// salt-okunur performans özeti: her tedarikçi için tamamlanma oranı,
// ortalama teslim süresi, ortalama sipariş tutarı.
import '../veri/database/veritabani.dart';

enum TedarikciPerformansSinifi { veriYok, zayif, normal, iyi }

extension TedarikciPerformansSinifiUzanti on TedarikciPerformansSinifi {
  String get etiket => switch (this) {
        TedarikciPerformansSinifi.veriYok => 'Veri Yok',
        TedarikciPerformansSinifi.zayif => 'Zayıf',
        TedarikciPerformansSinifi.normal => 'Normal',
        TedarikciPerformansSinifi.iyi => 'İyi',
      };
}

class TedarikciPerformansGirdi {
  final int tedarikciId;
  final String tedarikciAdi;
  final int toplamSiparis;
  final int teslimAlinan;
  final int iptalEdilen;
  final int bekleyen;
  final double? ortalamaTeslimSuresiGun;
  final double ortalamaSiparisTutari;

  const TedarikciPerformansGirdi({
    required this.tedarikciId,
    required this.tedarikciAdi,
    required this.toplamSiparis,
    required this.teslimAlinan,
    required this.iptalEdilen,
    required this.bekleyen,
    required this.ortalamaTeslimSuresiGun,
    required this.ortalamaSiparisTutari,
  });
}

class TedarikciPerformansSatiri {
  final int tedarikciId;
  final String tedarikciAdi;
  final int toplamSiparis;
  final int teslimAlinan;
  final int iptalEdilen;
  final int bekleyen;
  final double? ortalamaTeslimSuresiGun;
  final double ortalamaSiparisTutari;
  /// teslimAlinan / (teslimAlinan + iptalEdilen). Sonuçlanmış (bekleyen
  /// olmayan) sipariş yoksa null.
  final double? tamamlanmaOrani;
  final TedarikciPerformansSinifi sinif;

  const TedarikciPerformansSatiri({
    required this.tedarikciId,
    required this.tedarikciAdi,
    required this.toplamSiparis,
    required this.teslimAlinan,
    required this.iptalEdilen,
    required this.bekleyen,
    required this.ortalamaTeslimSuresiGun,
    required this.ortalamaSiparisTutari,
    required this.tamamlanmaOrani,
    required this.sinif,
  });
}

/// Saf fonksiyon: SADECE sonuçlanmış siparişler (teslim_alindi + iptal —
/// hâlâ 'beklemede' olanlar henüz bir sonuç üretmediği için hariç)
/// üzerinden tamamlanma oranı hesaplanır. Eşikler: >=%90 → İyi, >=%60 →
/// Normal, altı → Zayıf. Hiç sonuçlanmış sipariş yoksa → Veri Yok.
TedarikciPerformansSatiri tedarikciPerformansiHesapla(TedarikciPerformansGirdi g) {
  final sonuclanan = g.teslimAlinan + g.iptalEdilen;
  if (sonuclanan == 0) {
    return TedarikciPerformansSatiri(
      tedarikciId: g.tedarikciId,
      tedarikciAdi: g.tedarikciAdi,
      toplamSiparis: g.toplamSiparis,
      teslimAlinan: g.teslimAlinan,
      iptalEdilen: g.iptalEdilen,
      bekleyen: g.bekleyen,
      ortalamaTeslimSuresiGun: g.ortalamaTeslimSuresiGun,
      ortalamaSiparisTutari: g.ortalamaSiparisTutari,
      tamamlanmaOrani: null,
      sinif: TedarikciPerformansSinifi.veriYok,
    );
  }
  final oran = g.teslimAlinan / sonuclanan;
  final sinif = oran >= 0.9
      ? TedarikciPerformansSinifi.iyi
      : oran >= 0.6
          ? TedarikciPerformansSinifi.normal
          : TedarikciPerformansSinifi.zayif;
  return TedarikciPerformansSatiri(
    tedarikciId: g.tedarikciId,
    tedarikciAdi: g.tedarikciAdi,
    toplamSiparis: g.toplamSiparis,
    teslimAlinan: g.teslimAlinan,
    iptalEdilen: g.iptalEdilen,
    bekleyen: g.bekleyen,
    ortalamaTeslimSuresiGun: g.ortalamaTeslimSuresiGun,
    ortalamaSiparisTutari: g.ortalamaSiparisTutari,
    tamamlanmaOrani: oran,
    sinif: sinif,
  );
}

/// En kötüden en iyiye sıralar (Zayıf → en üstte, en actionable bulgu),
/// Veri Yok'lar en sona.
List<TedarikciPerformansSatiri> tedarikciPerformansListesiHesapla(
    List<TedarikciPerformansGirdi> girdiler) {
  final satirlar = girdiler.map(tedarikciPerformansiHesapla).toList();
  int siralamaDegeri(TedarikciPerformansSinifi s) => switch (s) {
        TedarikciPerformansSinifi.zayif => 0,
        TedarikciPerformansSinifi.normal => 1,
        TedarikciPerformansSinifi.iyi => 2,
        TedarikciPerformansSinifi.veriYok => 3,
      };
  satirlar.sort((a, b) {
    final s = siralamaDegeri(a.sinif).compareTo(siralamaDegeri(b.sinif));
    if (s != 0) return s;
    return (a.tamamlanmaOrani ?? 1).compareTo(b.tamamlanmaOrani ?? 1);
  });
  return satirlar;
}

class TedarikciPerformansServisi {
  Future<List<TedarikciPerformansSatiri>> analizGetir() async {
    final db = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT c.id AS tedarikci_id, c.unvan AS tedarikci_adi,
        COUNT(*) AS toplam,
        SUM(CASE WHEN t.durum = 'teslim_alindi' THEN 1 ELSE 0 END) AS teslim_alinan,
        SUM(CASE WHEN t.durum = 'iptal' THEN 1 ELSE 0 END) AS iptal_edilen,
        SUM(CASE WHEN t.durum = 'beklemede' THEN 1 ELSE 0 END) AS bekleyen,
        AVG(CASE WHEN t.durum = 'teslim_alindi' AND t.teslim_tarihi IS NOT NULL
              THEN julianday(t.teslim_tarihi) - julianday(t.siparis_tarihi) END) AS ort_sure,
        AVG(t.toplam_tutar) AS ort_tutar
      FROM tedarikci_siparisler t
      JOIN cari c ON c.id = t.cari_id
      WHERE t.is_deleted = 0
      GROUP BY t.cari_id
    ''');

    final girdiler = rows
        .map((r) => TedarikciPerformansGirdi(
              tedarikciId: r['tedarikci_id'] as int,
              tedarikciAdi: r['tedarikci_adi'] as String? ?? '—',
              toplamSiparis: (r['toplam'] as num?)?.toInt() ?? 0,
              teslimAlinan: (r['teslim_alinan'] as num?)?.toInt() ?? 0,
              iptalEdilen: (r['iptal_edilen'] as num?)?.toInt() ?? 0,
              bekleyen: (r['bekleyen'] as num?)?.toInt() ?? 0,
              ortalamaTeslimSuresiGun: (r['ort_sure'] as num?)?.toDouble(),
              ortalamaSiparisTutari: (r['ort_tutar'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
    return tedarikciPerformansListesiHesapla(girdiler);
  }
}
