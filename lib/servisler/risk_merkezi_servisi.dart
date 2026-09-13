// lib/servisler/risk_merkezi_servisi.dart
//
// FAZ 11 — Risk Merkezi (erp_roadmap madde 21). Kredi limiti tanımlı
// tüm müşterilerin risk kullanım %'sini tek listede gösteren salt-okunur
// rapor — limit aşımında müdür onayı zaten Onay Merkezi'nin (FAZ 9)
// "Risk Aşımı" akışıyla sağlanıyor; bu ekran o riskin TOPLU/ÖNCEDEN
// görünürlüğünü sağlıyor. Hiçbir tabloya yazmaz.
import '../veri/database/veritabani.dart';

enum RiskSeviyesi { iyi, dikkat, kritik }

extension RiskSeviyesiUzanti on RiskSeviyesi {
  String get etiket => switch (this) {
        RiskSeviyesi.iyi => 'İyi',
        RiskSeviyesi.dikkat => 'Dikkat',
        RiskSeviyesi.kritik => 'Kritik',
      };
}

class RiskSatiri {
  final int cariId;
  final String unvan;
  final double bakiye;
  final double limitTutari;
  final double riskOrani;
  final RiskSeviyesi seviye;
  const RiskSatiri({
    required this.cariId,
    required this.unvan,
    required this.bakiye,
    required this.limitTutari,
    required this.riskOrani,
    required this.seviye,
  });
}

/// Saf fonksiyon — cari_detay_ekrani.dart'taki risk rozeti İLE AYNI
/// eşikler (tutarlılık için): >=%90 Kritik, >=%60 Dikkat, altı İyi.
RiskSeviyesi riskSeviyesiHesapla(double riskOrani) {
  if (riskOrani >= 0.9) return RiskSeviyesi.kritik;
  if (riskOrani >= 0.6) return RiskSeviyesi.dikkat;
  return RiskSeviyesi.iyi;
}

class RiskMerkeziServisi {
  /// Sadece kredi limiti TANIMLI (limit_tutari > 0) müşterileri döner,
  /// risk oranına göre büyükten küçüğe sıralı.
  Future<List<RiskSatiri>> analizGetir() async {
    final db = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT id, unvan, bakiye, limit_tutari FROM cari
      WHERE is_deleted = 0 AND aktif = 1
        AND cari_tipi LIKE '%Müşteri%' AND limit_tutari > 0
    ''');
    final satirlar = rows.map((r) {
      final bakiye = (r['bakiye'] as num?)?.toDouble() ?? 0;
      final limit = (r['limit_tutari'] as num?)?.toDouble() ?? 0;
      final oran = limit > 0 ? bakiye / limit : 0.0;
      return RiskSatiri(
        cariId: r['id'] as int,
        unvan: r['unvan'] as String? ?? '—',
        bakiye: bakiye,
        limitTutari: limit,
        riskOrani: oran,
        seviye: riskSeviyesiHesapla(oran),
      );
    }).toList()
      ..sort((a, b) => b.riskOrani.compareTo(a.riskOrani));
    return satirlar;
  }
}
