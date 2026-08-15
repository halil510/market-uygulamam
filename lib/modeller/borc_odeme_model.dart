// lib/modeller/borc_odeme_model.dart
class BorcOdemeModel {
  final int? id;
  final String? globalId;
  final int borcId;
  final double tutar;
  final DateTime tarih;
  final String odemeYontemi; // Nakit, Banka, Kredi KartÄ±, Havale
  final String? aciklama;
  final String? referansNo;
  final int? bankaHesapId;
  final int? krediKartiId;

  const BorcOdemeModel({
    this.id,
    this.globalId,
    required this.borcId,
    required this.tutar,
    required this.tarih,
    required this.odemeYontemi,
    this.aciklama,
    this.referansNo,
    this.bankaHesapId,
    this.krediKartiId,
  });

  factory BorcOdemeModel.fromMap(Map<String, dynamic> m) => BorcOdemeModel(
    id: m['id'] as int?,
    globalId: m['global_id'] as String?,
    borcId: m['borc_id'] as int? ?? 0,
    tutar: (m['tutar'] as num?)?.toDouble() ?? 0,
    tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
    odemeYontemi: m['odeme_yontemi'] as String? ?? 'Nakit',
    aciklama: m['aciklama'] as String?,
    referansNo: m['referans_no'] as String?,
    bankaHesapId: m['banka_hesap_id'] as int?,
    krediKartiId: m['kredi_karti_id'] as int?,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'borc_id': borcId,
    'tutar': tutar,
    'tarih': tarih.toIso8601String(),
    'odeme_yontemi': odemeYontemi,
    if (aciklama != null) 'aciklama': aciklama,
    if (referansNo != null) 'referans_no': referansNo,
    if (bankaHesapId != null) 'banka_hesap_id': bankaHesapId,
    if (krediKartiId != null) 'kredi_karti_id': krediKartiId,
  };
}
