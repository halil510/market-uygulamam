// lib/modeller/fiyat_kademesi_model.dart
class FiyatKademesiModel {
  final int? id;
  final String? globalId;
  final int urunId;
  final int? fiyatGrubuId; // null = tüm bayi/toptan müşterileri için geçerli
  final double minMiktar;  // bu miktar VE ÜZERİ için geçerli
  final String birim;      // 'adet' | 'koli' | 'kg'
  final double fiyat;

  const FiyatKademesiModel({
    this.id,
    this.globalId,
    required this.urunId,
    this.fiyatGrubuId,
    required this.minMiktar,
    this.birim = 'adet',
    required this.fiyat,
  });

  factory FiyatKademesiModel.fromMap(Map<String, dynamic> m) => FiyatKademesiModel(
        id: m['id'] as int?,
        globalId: m['global_id'] as String?,
        urunId: m['urun_id'] as int,
        fiyatGrubuId: m['fiyat_grubu_id'] as int?,
        minMiktar: (m['min_miktar'] as num?)?.toDouble() ?? 0,
        birim: m['birim'] as String? ?? 'adet',
        fiyat: (m['fiyat'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (globalId != null) 'global_id': globalId,
        'urun_id': urunId,
        if (fiyatGrubuId != null) 'fiyat_grubu_id': fiyatGrubuId,
        'min_miktar': minMiktar,
        'birim': birim,
        'fiyat': fiyat,
      };
}
