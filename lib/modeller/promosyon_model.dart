// lib/modeller/promosyon_model.dart
class PromosyonModel {
  final int? id;
  final int urunId;
  final String urunAdi;
  final String promosyonAdi;
  final double iskontoOran;
  final double iskontoTutar;
  final double minMiktar;
  final DateTime? baslangicTarihi;
  final DateTime? bitisTarihi;
  final bool aktif;

  bool get gecerli {
    if (!aktif) return false;
    final now = DateTime.now();
    if (baslangicTarihi != null && now.isBefore(baslangicTarihi!)) return false;
    if (bitisTarihi != null && now.isAfter(bitisTarihi!)) return false;
    return true;
  }

  const PromosyonModel({
    this.id, required this.urunId, this.urunAdi = '',
    required this.promosyonAdi,
    this.iskontoOran = 0, this.iskontoTutar = 0, this.minMiktar = 1,
    this.baslangicTarihi, this.bitisTarihi, this.aktif = true,
  });

  PromosyonModel copyWith({
    int? id, int? urunId, String? urunAdi, String? promosyonAdi,
    double? iskontoOran, double? iskontoTutar, double? minMiktar,
    DateTime? baslangicTarihi, DateTime? bitisTarihi, bool? aktif,
  }) => PromosyonModel(
    id:              id              ?? this.id,
    urunId:          urunId          ?? this.urunId,
    urunAdi:         urunAdi         ?? this.urunAdi,
    promosyonAdi:    promosyonAdi    ?? this.promosyonAdi,
    iskontoOran:     iskontoOran     ?? this.iskontoOran,
    iskontoTutar:    iskontoTutar    ?? this.iskontoTutar,
    minMiktar:       minMiktar       ?? this.minMiktar,
    baslangicTarihi: baslangicTarihi ?? this.baslangicTarihi,
    bitisTarihi:     bitisTarihi     ?? this.bitisTarihi,
    aktif:           aktif           ?? this.aktif,
  );

  factory PromosyonModel.fromMap(Map<String, dynamic> m) {
    double toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    return PromosyonModel(
      id:              m['id'] as int?,
      urunId:          (m['urun_id'] as int?) ?? 0,
      urunAdi:         m['urun_adi'] as String? ?? '',
      promosyonAdi:    m['promosyon_adi'] as String? ?? '',
      iskontoOran:     toD(m['iskonto_oran']),
      iskontoTutar:    toD(m['iskonto_tutar']),
      minMiktar:       toD(m['min_miktar']),
      baslangicTarihi: m['baslangic_tarihi'] != null
          ? DateTime.tryParse(m['baslangic_tarihi'].toString()) : null,
      bitisTarihi:     m['bitis_tarihi'] != null
          ? DateTime.tryParse(m['bitis_tarihi'].toString()) : null,
      aktif:           (m['aktif'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'urun_id':      urunId,
    'promosyon_adi': promosyonAdi,
    'iskonto_oran':  iskontoOran,
    'iskonto_tutar': iskontoTutar,
    'min_miktar':    minMiktar,
    if (baslangicTarihi != null)
      'baslangic_tarihi': baslangicTarihi!.toIso8601String(),
    if (bitisTarihi != null)
      'bitis_tarihi': bitisTarihi!.toIso8601String(),
    'aktif': aktif ? 1 : 0,
  };
}
