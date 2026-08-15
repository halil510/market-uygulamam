// lib/modeller/masa_siparis_kalem_model.dart
class MasaSiparisKalemModel {
  final int? id;
  final String? globalId;
  final int siparisId;
  final int urunId;
  final String urunAdi;
  final double miktar;
  final double birimFiyat;
  final double kdvOran;
  final String? not_;
  final String durum; // beklemede | hazirlaniyor | hazir | servis_edildi

  const MasaSiparisKalemModel({
    this.id, this.globalId,
    required this.siparisId,
    required this.urunId,
    required this.urunAdi,
    this.miktar = 1,
    this.birimFiyat = 0,
    this.kdvOran = 18,
    this.not_,
    this.durum = 'beklemede',
  });

  double get toplam => miktar * birimFiyat;

  factory MasaSiparisKalemModel.fromMap(Map<String, dynamic> m) => MasaSiparisKalemModel(
    id:         m['id'] as int?,
    globalId:   m['global_id'] as String?,
    siparisId:  m['siparis_id'] as int,
    urunId:     m['urun_id'] as int,
    urunAdi:    m['urun_adi'] as String? ?? '',
    miktar:     (m['miktar'] as num?)?.toDouble() ?? 1,
    birimFiyat: (m['birim_fiyat'] as num?)?.toDouble() ?? 0,
    kdvOran:    (m['kdv_oran'] as num?)?.toDouble() ?? 18,
    not_:       m['not_'] as String?,
    durum:      m['durum'] as String? ?? 'beklemede',
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'siparis_id': siparisId,
    'urun_id': urunId,
    'urun_adi': urunAdi,
    'miktar': miktar,
    'birim_fiyat': birimFiyat,
    'kdv_oran': kdvOran,
    'not_': not_,
    'durum': durum,
    'last_updated': DateTime.now().toIso8601String(),
  };

  MasaSiparisKalemModel copyWith({double? miktar, String? durum, String? not_}) =>
    MasaSiparisKalemModel(
      id: id, globalId: globalId, siparisId: siparisId,
      urunId: urunId, urunAdi: urunAdi,
      miktar: miktar ?? this.miktar,
      birimFiyat: birimFiyat, kdvOran: kdvOran,
      not_: not_ ?? this.not_,
      durum: durum ?? this.durum,
    );
}
