// lib/modeller/masa_model.dart
class MasaModel {
  final int? id;
  final String? globalId;
  final String ad;
  final String kategori;   // Salon, Bahçe, Teras vb.
  final int kapasite;
  final String durum;      // bos | dolu | hesap_istendi
  final int sira;
  final int? subeId;

  // UI'da gösterilecek özet (siparişten hesaplanır, tabloda tutulmaz)
  final double aktifToplam;
  final String? aktifOzet;
  final int? aktifSiparisId;
  final DateTime? acilisZamani;

  const MasaModel({
    this.id, this.globalId,
    required this.ad,
    this.kategori = 'Salon',
    this.kapasite = 4,
    this.durum = 'bos',
    this.sira = 0,
    this.subeId,
    this.aktifToplam = 0,
    this.aktifOzet,
    this.aktifSiparisId,
    this.acilisZamani,
  });

  bool get bos => durum == 'bos';
  bool get hesapIstendi => durum == 'hesap_istendi';

  factory MasaModel.fromMap(Map<String, dynamic> m) => MasaModel(
    id:       m['id'] as int?,
    globalId: m['global_id'] as String?,
    ad:       m['ad'] as String? ?? '',
    kategori: m['kategori'] as String? ?? 'Salon',
    kapasite: (m['kapasite'] as int?) ?? 4,
    durum:    m['durum'] as String? ?? 'bos',
    sira:     (m['sira'] as int?) ?? 0,
    subeId:   m['sube_id'] as int?,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'ad': ad,
    'kategori': kategori,
    'kapasite': kapasite,
    'durum': durum,
    'sira': sira,
    'sube_id': subeId,
    'last_updated': DateTime.now().toIso8601String(),
  };

  MasaModel copyWith({
    String? ad, String? kategori, int? kapasite, String? durum, int? sira,
    double? aktifToplam, String? aktifOzet, int? aktifSiparisId, DateTime? acilisZamani,
    bool aktifSiparisYok = false,
  }) => MasaModel(
    id: id, globalId: globalId,
    ad: ad ?? this.ad,
    kategori: kategori ?? this.kategori,
    kapasite: kapasite ?? this.kapasite,
    durum: durum ?? this.durum,
    sira: sira ?? this.sira,
    subeId: subeId,
    aktifToplam: aktifToplam ?? this.aktifToplam,
    aktifOzet: aktifSiparisYok ? null : (aktifOzet ?? this.aktifOzet),
    aktifSiparisId: aktifSiparisYok ? null : (aktifSiparisId ?? this.aktifSiparisId),
    acilisZamani: aktifSiparisYok ? null : (acilisZamani ?? this.acilisZamani),
  );
}
