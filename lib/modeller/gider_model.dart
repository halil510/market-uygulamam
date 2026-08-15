// lib/modeller/gider_model.dart
class GiderModel {
  final int? id;
  final String? globalId;
  final int kategoriId;
  final String kategoriAdi;
  final double tutar;
  final String? aciklama;
  final DateTime tarih;
  final String? belgeNo;
  final String odemeYontemi;
  final int? cariId;
  final int? kullaniciId;

  const GiderModel({
    this.id, this.globalId, required this.kategoriId, this.kategoriAdi = '',
    required this.tutar, this.aciklama, required this.tarih,
    this.belgeNo, this.odemeYontemi = 'Nakit',
    this.cariId, this.kullaniciId,
  });

  factory GiderModel.fromMap(Map<String, dynamic> m) => GiderModel(
    id: m['id'] as int?,
    globalId: m['global_id'] as String?,
    kategoriId: (m['kategori_id'] as int?) ?? 0,
    kategoriAdi: m['kategori_adi'] as String? ?? '',
    tutar: (m['tutar'] is int) ? (m['tutar'] as int).toDouble() : (m['tutar'] as double?) ?? 0.0,
    aciklama: m['aciklama'] as String?,
    tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
    belgeNo: m['belge_no'] as String?,
    odemeYontemi: m['odeme_yontemi'] as String? ?? 'Nakit',
    cariId: m['cari_id'] as int?,
    kullaniciId: m['kullanici_id'] as int?,
  );


  GiderModel copyWith({
    int? id,
    String? globalId,
    int? kategoriId,
    String? kategoriAdi,
    double? tutar,
    String? aciklama,
    DateTime? tarih,
    String? belgeNo,
    String? odemeYontemi,
    int? cariId,
    int? kullaniciId,
  }) => GiderModel(
      id: id ?? this.id,
      globalId: globalId ?? this.globalId,
      kategoriId: kategoriId ?? this.kategoriId,
      kategoriAdi: kategoriAdi ?? this.kategoriAdi,
      tutar: tutar ?? this.tutar,
      aciklama: aciklama ?? this.aciklama,
      tarih: tarih ?? this.tarih,
      belgeNo: belgeNo ?? this.belgeNo,
      odemeYontemi: odemeYontemi ?? this.odemeYontemi,
      cariId: cariId ?? this.cariId,
      kullaniciId: kullaniciId ?? this.kullaniciId,
    );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'kategori_id': kategoriId, 'tutar': tutar,
    if (aciklama != null) 'aciklama': aciklama,
    'tarih': tarih.toIso8601String(),
    if (belgeNo != null) 'belge_no': belgeNo,
    'odeme_yontemi': odemeYontemi,
    if (cariId != null) 'cari_id': cariId,
    if (kullaniciId != null) 'kullanici_id': kullaniciId,
  };
}
