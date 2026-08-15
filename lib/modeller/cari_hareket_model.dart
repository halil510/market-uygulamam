// lib/modeller/cari_hareket_model.dart
class CariHareketModel {
  final int? id;
  final int cariId;
  final DateTime tarih;
  final String fisTipi;
  final int? fisId;
  final String? fisNo;
  final String aciklama;
  final double borc;
  final double alacak;
  final double? bakiye;
  final String? odemeTuru;
  final String? kullanici;

  const CariHareketModel({
    this.id, required this.cariId,
    required this.tarih, required this.fisTipi,
    this.fisId, this.fisNo, this.aciklama = '',
    this.borc = 0, this.alacak = 0, this.bakiye,
    this.odemeTuru, this.kullanici,
  });

  factory CariHareketModel.fromMap(Map<String, dynamic> m) {
    double toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    return CariHareketModel(
      id: m['id'] as int?,
      cariId: (m['cari_id'] as int?) ?? 0,
      tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
      fisTipi: m['fis_tipi'] as String? ?? '',
      fisId: m['fis_id'] as int?,
      fisNo: m['fis_no'] as String?,
      aciklama: m['aciklama'] as String? ?? '',
      borc: toD(m['borc']),
      alacak: toD(m['alacak']),
      bakiye: m['bakiye'] != null ? toD(m['bakiye']) : null,
      odemeTuru: m['odeme_turu'] as String?,
      kullanici: m['kullanici'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'cari_id': cariId,
    'tarih': tarih.toIso8601String(),
    'fis_tipi': fisTipi,
    if (fisId != null) 'fis_id': fisId,
    if (fisNo != null) 'fis_no': fisNo,
    'aciklama': aciklama,
    'borc': borc, 'alacak': alacak,
    if (bakiye != null) 'bakiye': bakiye,
    if (odemeTuru != null) 'odeme_turu': odemeTuru,
    if (kullanici != null) 'kullanici': kullanici,
  };
}
