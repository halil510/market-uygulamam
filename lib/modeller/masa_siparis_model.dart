// lib/modeller/masa_siparis_model.dart
import 'masa_siparis_kalem_model.dart';

class MasaSiparisModel {
  final int? id;
  final String? globalId;
  final int masaId;
  final int? cariId;
  final String? cariAdi;
  final String durum; // acik | odendi | iptal
  final DateTime acilisZamani;
  final DateTime? kapanisZamani;
  final double toplamTutar;
  final String? not_;
  final int? kullaniciId;
  final int? satisId;
  final List<MasaSiparisKalemModel> kalemler;

  const MasaSiparisModel({
    this.id, this.globalId,
    required this.masaId,
    this.cariId, this.cariAdi,
    this.durum = 'acik',
    required this.acilisZamani,
    this.kapanisZamani,
    this.toplamTutar = 0,
    this.not_,
    this.kullaniciId,
    this.satisId,
    this.kalemler = const [],
  });

  double get hesaplananToplam =>
      kalemler.fold(0.0, (s, k) => s + k.toplam);

  factory MasaSiparisModel.fromMap(Map<String, dynamic> m, {List<MasaSiparisKalemModel> kalemler = const []}) => MasaSiparisModel(
    id:        m['id'] as int?,
    globalId:  m['global_id'] as String?,
    masaId:    m['masa_id'] as int,
    cariId:    m['cari_id'] as int?,
    cariAdi:   m['cari_adi'] as String?,
    durum:     m['durum'] as String? ?? 'acik',
    acilisZamani: DateTime.tryParse(m['acilis_zamani']?.toString() ?? '') ?? DateTime.now(),
    kapanisZamani: m['kapanis_zamani'] != null ? DateTime.tryParse(m['kapanis_zamani'].toString()) : null,
    toplamTutar: (m['toplam_tutar'] as num?)?.toDouble() ?? 0,
    not_:      m['not_'] as String?,
    kullaniciId: m['kullanici_id'] as int?,
    satisId:   m['satis_id'] as int?,
    kalemler:  kalemler,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'masa_id': masaId,
    'cari_id': cariId,
    'cari_adi': cariAdi,
    'durum': durum,
    'acilis_zamani': acilisZamani.toIso8601String(),
    'kapanis_zamani': kapanisZamani?.toIso8601String(),
    'toplam_tutar': toplamTutar,
    'not_': not_,
    'kullanici_id': kullaniciId,
    'satis_id': satisId,
    'last_updated': DateTime.now().toIso8601String(),
  };
}
