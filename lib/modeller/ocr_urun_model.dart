// lib/modeller/ocr_urun_model.dart
// OCR'den çıkan her bir ürün için güven skorlu model

class OcrUrunModel {
  final String? urunAdi;
  final double? miktar;
  final String? birimAdi;
  final double? birimFiyat;
  final double? toplamTutar;
  final double? kdvOrani;
  final double? iskontoOrani;
  final String? kod;
  double guven; // final değil, sonradan değiştirilebilir

  OcrUrunModel({
    this.urunAdi,
    this.miktar,
    this.birimAdi,
    this.birimFiyat,
    this.toplamTutar,
    this.kdvOrani,
    this.iskontoOrani,
    this.kod,
    this.guven = 0.0,
  });

  /// JSON'dan dönüştürme
  factory OcrUrunModel.fromJson(Map<String, dynamic> json) {
    return OcrUrunModel(
      urunAdi: json['urun_adi']?.toString(),
      miktar: _toDouble(json['miktar']),
      birimAdi: json['birim_adi']?.toString(),
      birimFiyat: _toDouble(json['birim_fiyat']),
      toplamTutar: _toDouble(json['toplam_tutar']),
      kdvOrani: _toDouble(json['kdv_orani']),
      iskontoOrani: _toDouble(json['iskonto_orani']),
      kod: json['kod']?.toString(),
      guven: _toDouble(json['guven']) ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'urun_adi': urunAdi,
    'miktar': miktar,
    'birim_adi': birimAdi,
    'birim_fiyat': birimFiyat,
    'toplam_tutar': toplamTutar,
    'kdv_orani': kdvOrani,
    'iskonto_orani': iskontoOrani,
    'kod': kod,
    'guven': guven,
  };

  /// Kopyalama metodu (guven güncellemek için)
  OcrUrunModel copyWith({double? guven}) {
    return OcrUrunModel(
      urunAdi: urunAdi,
      miktar: miktar,
      birimAdi: birimAdi,
      birimFiyat: birimFiyat,
      toplamTutar: toplamTutar,
      kdvOrani: kdvOrani,
      iskontoOrani: iskontoOrani,
      kod: kod,
      guven: guven ?? this.guven,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.');
      return double.tryParse(cleaned);
    }
    return null;
  }
}