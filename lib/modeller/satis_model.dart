// lib/modeller/satis_model.dart
import 'satis_kalem_model.dart';

class SatisModel {
  final int? id;
  final String? globalId;
  final String? fisNo;
  final DateTime tarih;
  final int? cariId;
  final String? cariAdi;
  final double toplamTutar;
  final double iskonto;
  final double iskontoOran;
  final double kdvTutar;
  final double genelToplam;
  final double odenenTutar;
  final String odemeYontemi;
  final String fisTipi;
  final String? aciklama;
  final double kargoUcreti;
  final int? kasiyerId;
  final int? kullaniciId;
  final int? vardiyaId;
  final bool iptal;
  final String? iptalNedeni;
  final List<SatisKalemModel> kalemler;

  double get kalanTutar => genelToplam - odenenTutar;

  const SatisModel({
    this.id, this.globalId, this.fisNo,
    required this.tarih,
    this.cariId, this.cariAdi,
    this.toplamTutar = 0,
    this.iskonto = 0, this.iskontoOran = 0, this.kdvTutar = 0,
    this.genelToplam = 0, this.odenenTutar = 0,
    this.odemeYontemi = 'Nakit',
    this.fisTipi = 'Satış',
    this.aciklama, this.kargoUcreti = 0,
    this.kasiyerId, this.kullaniciId, this.vardiyaId,
    this.iptal = false, this.iptalNedeni,
    this.kalemler = const [],
  });

  factory SatisModel.fromMap(Map<String, dynamic> m, {List<SatisKalemModel>? kalemler}) {
    double toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    return SatisModel(
      id: m['id'] as int?,
      globalId: m['global_id'] as String?,
      fisNo: m['fis_no'] as String?,
      tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
      cariId: m['cari_id'] as int?,
      cariAdi: m['cari_adi'] as String?,
      toplamTutar: toD(m['toplam_tutar']),
      iskonto: toD(m['iskonto_tutar']),
      iskontoOran: toD(m['iskonto_oran']),
      kdvTutar: toD(m['kdv_tutar']),
      genelToplam: toD(m['genel_toplam']),
      odenenTutar: toD(m['odenen_tutar']),
      odemeYontemi: m['odeme_yontemi'] as String? ?? 'Nakit',
      fisTipi: m['fis_tipi'] as String? ?? 'Satış',
      aciklama: m['aciklama'] as String?,
      kargoUcreti: toD(m['kargo_ucreti']),
      kasiyerId: m['kasiyer_id'] as int?,
      kullaniciId: m['kullanici_id'] as int?,
      vardiyaId: m['vardiya_id'] as int?,
      iptal: (m['iptal'] as int?) == 1,
      iptalNedeni: m['iptal_nedeni'] as String?,
      kalemler: kalemler ?? [],
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    if (fisNo != null) 'fis_no': fisNo,
    'tarih': tarih.toIso8601String(),
    if (cariId != null) 'cari_id': cariId,
    'toplam_tutar': toplamTutar,
    'iskonto_tutar': iskonto,
    'iskonto_oran': iskontoOran,
    'kdv_tutar': kdvTutar,
    'genel_toplam': genelToplam,
    'odenen_tutar': odenenTutar,
    'odeme_yontemi': odemeYontemi,
    'fis_tipi': fisTipi,
    if (aciklama != null) 'aciklama': aciklama,
    'kargo_ucreti': kargoUcreti,
    if (kasiyerId != null) 'kasiyer_id': kasiyerId,
    if (kullaniciId != null) 'kullanici_id': kullaniciId,
    if (vardiyaId != null) 'vardiya_id': vardiyaId,
    'iptal': iptal ? 1 : 0,
    if (iptalNedeni != null) 'iptal_nedeni': iptalNedeni,
  };

  // ✅ DÜZELTİLDİ: copyWith eklendi (SatisServisi ve diğer yerler için gerekli)
  SatisModel copyWith({
    int? id,
    String? globalId,
    String? fisNo,
    DateTime? tarih,
    int? cariId,
    String? cariAdi,
    double? toplamTutar,
    double? iskonto,
    double? iskontoOran,
    double? kdvTutar,
    double? genelToplam,
    double? odenenTutar,
    String? odemeYontemi,
    String? fisTipi,
    String? aciklama,
    double? kargoUcreti,
    int? kasiyerId,
    int? kullaniciId,
    int? vardiyaId,
    bool? iptal,
    String? iptalNedeni,
    List<SatisKalemModel>? kalemler,
  }) => SatisModel(
    id: id ?? this.id,
    globalId: globalId ?? this.globalId,
    fisNo: fisNo ?? this.fisNo,
    tarih: tarih ?? this.tarih,
    cariId: cariId ?? this.cariId,
    cariAdi: cariAdi ?? this.cariAdi,
    toplamTutar: toplamTutar ?? this.toplamTutar,
    iskonto: iskonto ?? this.iskonto,
    iskontoOran: iskontoOran ?? this.iskontoOran,
    kdvTutar: kdvTutar ?? this.kdvTutar,
    genelToplam: genelToplam ?? this.genelToplam,
    odenenTutar: odenenTutar ?? this.odenenTutar,
    odemeYontemi: odemeYontemi ?? this.odemeYontemi,
    fisTipi: fisTipi ?? this.fisTipi,
    aciklama: aciklama ?? this.aciklama,
    kargoUcreti: kargoUcreti ?? this.kargoUcreti,
    kasiyerId: kasiyerId ?? this.kasiyerId,
    // 🔴 Derin analizde bulundu: kullaniciId parametre olarak tanımlıydı
    // ama constructor çağrısına hiç aktarılmıyordu — her copyWith() bu
    // alanı sessizce null'a sıfırlardı (UrunModel'de bulunan aynı hata
    // sınıfı, bkz. o dosyadaki not).
    kullaniciId: kullaniciId ?? this.kullaniciId,
    vardiyaId: vardiyaId ?? this.vardiyaId,
    iptal: iptal ?? this.iptal,
    iptalNedeni: iptalNedeni ?? this.iptalNedeni,
    kalemler: kalemler ?? this.kalemler,
  );
}
