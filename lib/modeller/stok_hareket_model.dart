// lib/modeller/stok_hareket_model.dart
class StokHareketModel {
  final int? id;
  final int urunId;
  final String urunAdi;
  final String hareketTuru;
  final double miktar;
  final double oncekiStok;
  final double sonrakiStok;
  final double birimMaliyet;
  final DateTime tarih;
  final int? referansId;
  final String? referansTuru;
  final String? aciklama;
  final int? kullaniciId;

  const StokHareketModel({
    this.id, required this.urunId, this.urunAdi = '',
    required this.hareketTuru, required this.miktar,
    this.oncekiStok = 0, this.sonrakiStok = 0, this.birimMaliyet = 0,
    required this.tarih, this.referansId, this.referansTuru,
    this.aciklama, this.kullaniciId,
  });

  factory StokHareketModel.fromMap(Map<String, dynamic> m) {
    double toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    return StokHareketModel(
      id: m['id'] as int?,
      urunId: (m['urun_id'] as int?) ?? 0,
      urunAdi: m['urun_adi'] as String? ?? '',
      hareketTuru: m['hareket_turu'] as String? ?? '',
      miktar: toD(m['miktar']),
      oncekiStok: toD(m['onceki_stok']),
      sonrakiStok: toD(m['sonraki_stok']),
      birimMaliyet: toD(m['birim_maliyet']),
      tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
      referansId: m['referans_id'] as int?,
      referansTuru: m['referans_turu'] as String?,
      aciklama: m['aciklama'] as String?,
      kullaniciId: m['kullanici_id'] as int?,
    );
  }


  StokHareketModel copyWith({
    int? id,
    int? urunId,
    String? urunAdi,
    String? hareketTuru,
    double? miktar,
    double? oncekiStok,
    double? sonrakiStok,
    double? birimMaliyet,
    DateTime? tarih,
    int? referansId,
    String? referansTuru,
    String? aciklama,
    int? kullaniciId,
  }) => StokHareketModel(
      id: id ?? this.id,
      urunId: urunId ?? this.urunId,
      urunAdi: urunAdi ?? this.urunAdi,
      hareketTuru: hareketTuru ?? this.hareketTuru,
      miktar: miktar ?? this.miktar,
      oncekiStok: oncekiStok ?? this.oncekiStok,
      sonrakiStok: sonrakiStok ?? this.sonrakiStok,
      birimMaliyet: birimMaliyet ?? this.birimMaliyet,
      tarih: tarih ?? this.tarih,
      referansId: referansId ?? this.referansId,
      referansTuru: referansTuru ?? this.referansTuru,
      aciklama: aciklama ?? this.aciklama,
      kullaniciId: kullaniciId ?? this.kullaniciId,
    );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'urun_id': urunId, 'hareket_turu': hareketTuru, 'miktar': miktar,
    'onceki_stok': oncekiStok, 'sonraki_stok': sonrakiStok,
    'birim_maliyet': birimMaliyet,
    'tarih': tarih.toIso8601String(),
    if (referansId != null) 'referans_id': referansId,
    if (referansTuru != null) 'referans_turu': referansTuru,
    if (aciklama != null) 'aciklama': aciklama,
    if (kullaniciId != null) 'kullanici_id': kullaniciId,
  };
}
