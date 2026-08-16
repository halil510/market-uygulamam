// lib/modeller/fiyat_grubu_model.dart
class FiyatGrubuModel {
  final int? id;
  final String? globalId;
  final String ad;
  final String? aciklama;
  final double varsayilanIskontoOrani; // % — ürün bazlı fiyat yoksa perakende fiyata uygulanır
  final bool aktif;

  const FiyatGrubuModel({
    this.id,
    this.globalId,
    required this.ad,
    this.aciklama,
    this.varsayilanIskontoOrani = 0,
    this.aktif = true,
  });

  factory FiyatGrubuModel.fromMap(Map<String, dynamic> m) => FiyatGrubuModel(
        id: m['id'] as int?,
        globalId: m['global_id'] as String?,
        ad: m['ad'] as String? ?? '',
        aciklama: m['aciklama'] as String?,
        varsayilanIskontoOrani: (m['varsayilan_iskonto_orani'] as num?)?.toDouble() ?? 0,
        aktif: (m['aktif'] as int?) == 1,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (globalId != null) 'global_id': globalId,
        'ad': ad,
        if (aciklama != null) 'aciklama': aciklama,
        'varsayilan_iskonto_orani': varsayilanIskontoOrani,
        'aktif': aktif ? 1 : 0,
      };

  FiyatGrubuModel copyWith({
    String? ad, String? aciklama, double? varsayilanIskontoOrani, bool? aktif,
  }) => FiyatGrubuModel(
        id: id, globalId: globalId,
        ad: ad ?? this.ad,
        aciklama: aciklama ?? this.aciklama,
        varsayilanIskontoOrani: varsayilanIskontoOrani ?? this.varsayilanIskontoOrani,
        aktif: aktif ?? this.aktif,
      );
}
