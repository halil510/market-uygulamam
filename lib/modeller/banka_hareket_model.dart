// lib/modeller/banka_hareket_model.dart
class BankaHareketModel {
  final int? id;
  final String? globalId;
  final int bankaHesapId;
  final int? krediKartiId;
  final String islemTipi; // Gelen, Giden, Havale, EFT, Kredi, Taksit
  final double tutar;
  final String? aciklama;
  final DateTime tarih;
  final String? referansNo;
  final String? karsiHesap;
  final double? oncekiBakiye;
  final double? sonrakiBakiye;
  final String? kategori;
  // DEEP_AUDIT (kendi-keşif turu, 2026-09-21): CariDeposu.hareketIptalEt()
  // bu hareketi bulup tersine çevirebilsin diye — kasa_hareketleri'ndeki
  // referans_id/referans_turu ile AYNI desen.
  final int? referansId;
  final String? referansTuru;

  const BankaHareketModel({
    this.id,
    this.globalId,
    required this.bankaHesapId,
    this.krediKartiId,
    required this.islemTipi,
    required this.tutar,
    this.aciklama,
    required this.tarih,
    this.referansNo,
    this.kategori,
    this.karsiHesap,
    this.oncekiBakiye,
    this.sonrakiBakiye,
    this.referansId,
    this.referansTuru,
  });

  factory BankaHareketModel.fromMap(Map<String, dynamic> m) => BankaHareketModel(
    id: m['id'] as int?,
    globalId: m['global_id'] as String?,
    bankaHesapId: m['banka_hesap_id'] as int? ?? 0,
    krediKartiId: m['kredi_karti_id'] as int?,
    islemTipi: m['islem_tipi'] as String? ?? '',
    tutar: (m['tutar'] as num?)?.toDouble() ?? 0,
    aciklama: m['aciklama'] as String?,
    tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
    referansNo: m['referans_no'] as String?,
    karsiHesap: m['karsi_hesap'] as String?,
    oncekiBakiye: m['onceki_bakiye'] != null ? (m['onceki_bakiye'] as num).toDouble() : null,
    sonrakiBakiye: m['sonraki_bakiye'] != null ? (m['sonraki_bakiye'] as num).toDouble() : null,
    referansId: m['referans_id'] as int?,
    referansTuru: m['referans_turu'] as String?,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'banka_hesap_id': bankaHesapId,
    if (krediKartiId != null) 'kredi_karti_id': krediKartiId,
    'islem_tipi': islemTipi,
    'tutar': tutar,
    if (aciklama != null) 'aciklama': aciklama,
    'tarih': tarih.toIso8601String(),
    if (referansNo != null) 'referans_no': referansNo,
    if (karsiHesap != null) 'karsi_hesap': karsiHesap,
    if (oncekiBakiye != null) 'onceki_bakiye': oncekiBakiye,
    if (sonrakiBakiye != null) 'sonraki_bakiye': sonrakiBakiye,
    if (referansId != null) 'referans_id': referansId,
    if (referansTuru != null) 'referans_turu': referansTuru,
  };
}
