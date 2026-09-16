// lib/modeller/satis_kalem_model.dart
import '../cekirdek/utils/para_utils.dart';

class SatisKalemModel {
  final int? id;
  final int satisId;
  final int urunId;
  final String urunAdi;
  final String? barkod;
  final double miktar;
  final double birimFiyat;
  final double iskontoOran;
  final double iskontoTutar;
  final double kdvOran;
  final double kdvTutar;
  final double netFiyat;
  final double toplamTutar;
  final int? lotId;
  final String? seriNo;
  // KAR/ZARAR için kritik — satış anındaki alış fiyatı
  final double alisFiyat;
  final double alisFiyatKdv;

  const SatisKalemModel({
    this.id, required this.satisId, required this.urunId,
    required this.urunAdi, this.barkod,
    required this.miktar, required this.birimFiyat,
    this.iskontoOran = 0, this.iskontoTutar = 0,
    this.kdvOran = 18, this.kdvTutar = 0,
    this.netFiyat = 0, this.toplamTutar = 0,
    this.lotId, this.seriNo,
    this.alisFiyat = 0,
    this.alisFiyatKdv = 0,
  });

  double get brutKar => (birimFiyat - alisFiyat) * miktar;
  double get brutKarOrani => alisFiyat > 0
      ? ((birimFiyat - alisFiyat) / alisFiyat * 100)
      : 0;

  factory SatisKalemModel.fromMap(Map<String, dynamic> m) {
    double toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    return SatisKalemModel(
      id: m['id'] as int?,
      satisId: (m['satis_id'] as int?) ?? 0,
      urunId: (m['urun_id'] as int?) ?? 0,
      urunAdi: m['urun_adi'] as String? ?? '',
      barkod: m['barkod'] as String?,
      miktar: toD(m['miktar']),
      birimFiyat: toD(m['birim_fiyat']),
      iskontoOran: toD(m['iskonto_oran']),
      iskontoTutar: toD(m['iskonto_tutar']),
      kdvOran: toD(m['kdv_oran']),
      kdvTutar: toD(m['kdv_tutar']),
      netFiyat: toD(m['net_fiyat']),
      toplamTutar: toD(m['toplam_tutar']),
      lotId: m['lot_id'] as int?,
      seriNo: m['seri_no'] as String?,
      alisFiyat: toD(m['alis_fiyat']),
      alisFiyatKdv: toD(m['alis_fiyat_kdv']),
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'satis_id': satisId, 'urun_id': urunId, 'urun_adi': urunAdi,
    if (barkod != null) 'barkod': barkod,
    'miktar': miktar, 'birim_fiyat': birimFiyat,
    'iskonto_oran': iskontoOran, 'iskonto_tutar': iskontoTutar,
    'kdv_oran': kdvOran, 'kdv_tutar': kdvTutar,
    'net_fiyat': netFiyat, 'toplam_tutar': toplamTutar,
    if (lotId != null) 'lot_id': lotId,
    if (seriNo != null) 'seri_no': seriNo,
    'alis_fiyat': alisFiyat,
    'alis_fiyat_kdv': alisFiyatKdv,
  };

  SatisKalemModel copyWith({int? satisId, double? miktar, double? birimFiyat, double? iskontoOran}) {
    final isk = iskontoOran ?? this.iskontoOran;
    final fiy = birimFiyat ?? this.birimFiyat;
    final mik = miktar ?? this.miktar;
    final indTutar = fiy * mik * (isk / 100);
    final netF = fiy * (1 - isk / 100);
    // 🔴 DÜZELTME (Madde 21, 2026-09-16): birimFiyat KDV DAHİL — kdvTutar
    // toplam tutarın İÇİNDEN ayıklanır, üzerine eklenmez.
    final kdvT = ParaUtils.kdvPayiCikar(netF * mik, kdvOran);
    return SatisKalemModel(
      id: id, satisId: satisId ?? this.satisId, urunId: urunId,
      urunAdi: urunAdi, barkod: barkod,
      miktar: mik, birimFiyat: fiy,
      iskontoOran: isk, iskontoTutar: indTutar,
      kdvOran: kdvOran, kdvTutar: kdvT,
      netFiyat: netF, toplamTutar: netF * mik,
      lotId: lotId, seriNo: seriNo,
      alisFiyat: alisFiyat, alisFiyatKdv: alisFiyatKdv,
    );
  }
}
