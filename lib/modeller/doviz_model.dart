// lib/modeller/doviz_model.dart
class DovizModel {
  final int? id;
  final String kod;      // 'USD', 'EUR', 'GBP'
  final String ad;
  final String sembol;
  final double alisKuru;
  final double satisKuru;
  final DateTime? guncellemeTarihi;
  final bool aktif;

  const DovizModel({
    this.id,
    required this.kod,
    required this.ad,
    required this.sembol,
    this.alisKuru = 0,
    this.satisKuru = 0,
    this.guncellemeTarihi,
    this.aktif = true,
  });

  /// Kur hiç girilmemişse (0) — ekranlarda uyarı göstermek için.
  bool get kurGirilmemis => satisKuru <= 0;

  factory DovizModel.fromMap(Map<String, dynamic> m) => DovizModel(
    id: m['id'] as int?,
    kod: m['kod'] as String? ?? '',
    ad: m['ad'] as String? ?? '',
    sembol: m['sembol'] as String? ?? '',
    alisKuru: (m['alis_kuru'] as num?)?.toDouble() ?? 0,
    satisKuru: (m['satis_kuru'] as num?)?.toDouble() ?? 0,
    guncellemeTarihi: m['guncelleme_tarihi'] != null
        ? DateTime.tryParse(m['guncelleme_tarihi'].toString())
        : null,
    aktif: (m['aktif'] as int?) == 1,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'kod': kod,
    'ad': ad,
    'sembol': sembol,
    'alis_kuru': alisKuru,
    'satis_kuru': satisKuru,
    if (guncellemeTarihi != null)
      'guncelleme_tarihi': guncellemeTarihi!.toIso8601String(),
    'aktif': aktif ? 1 : 0,
  };

  DovizModel copyWith({double? alisKuru, double? satisKuru, DateTime? guncellemeTarihi}) =>
      DovizModel(
        id: id, kod: kod, ad: ad, sembol: sembol,
        alisKuru: alisKuru ?? this.alisKuru,
        satisKuru: satisKuru ?? this.satisKuru,
        guncellemeTarihi: guncellemeTarihi ?? this.guncellemeTarihi,
        aktif: aktif,
      );
}
