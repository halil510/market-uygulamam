// lib/modeller/banka_model.dart
class BankaModel {
  final int? id;
  final String? globalId;
  final String ad;
  final String? kod;
  final String? tel;
  final String? email;
  final String? web;
  final String? adres;
  final String? logo;
  final String? yetkili;
  final bool aktif;

  const BankaModel({
    this.id,
    this.globalId,
    required this.ad,
    this.kod,
    this.tel,
    this.email,
    this.web,
    this.adres,
    this.logo,
    this.yetkili,
    this.aktif = true,
  });

  factory BankaModel.fromMap(Map<String, dynamic> m) => BankaModel(
    id: m['id'] as int?,
    globalId: m['global_id'] as String?,
    ad: m['ad'] as String? ?? '',
    kod: m['kod'] as String?,
    tel: m['tel'] as String?,
    email: m['email'] as String?,
    web: m['web'] as String?,
    adres: m['adres'] as String?,
    logo: m['logo'] as String?,
    yetkili: m['yetkili'] as String?,
    aktif: ((m['aktif'] as int?) ?? 1) == 1,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'ad': ad,
    if (kod != null) 'kod': kod,
    if (tel != null) 'tel': tel,
    if (email != null) 'email': email,
    if (web != null) 'web': web,
    if (adres != null) 'adres': adres,
    if (logo != null) 'logo': logo,
    if (yetkili != null) 'yetkili': yetkili,
    'aktif': aktif ? 1 : 0,
    'last_updated': DateTime.now().toIso8601String(),
  };

  BankaModel copyWith({String? ad, bool? aktif}) => BankaModel(
    id: id,
    globalId: globalId,
    ad: ad ?? this.ad,
    kod: kod,
    tel: tel,
    email: email,
    web: web,
    adres: adres,
    logo: logo,
    yetkili: yetkili,
    aktif: aktif ?? this.aktif,
  );
}
