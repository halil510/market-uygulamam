// lib/modeller/borc_model.dart
class BorcModel {
  final int? id;
  final String? globalId;
  final String baslik;
  final String tur; // 'kredi_karti', 'vergi', 'sgk', 'stopaj', 'kira', 'fatura'
  final String? altTur; // 'Vergi Dairesi', 'SGK', 'Kredi Kartı Bankası' vb.
  final double tutar;
  final double odenenTutar;
  final DateTime kesimTarihi; // Fatura kesim tarihi
  final DateTime sonOdemeTarihi;
  final DateTime? odemeTarihi;
  final int taksitSayisi;
  final int odenenTaksit;
  final String? aciklama;
  final String? dosyaNo;
  final String? referansNo;
  final bool odendi;
  final bool hatirlatmaGonderildi;
  final int oncelik; // 1=Kritik, 2=Orta, 3=Düşük
  final String? notlar;

  const BorcModel({
    this.id,
    this.globalId,
    required this.baslik,
    required this.tur,
    this.altTur,
    required this.tutar,
    this.odenenTutar = 0,
    required this.kesimTarihi,
    required this.sonOdemeTarihi,
    this.odemeTarihi,
    this.taksitSayisi = 1,
    this.odenenTaksit = 0,
    this.aciklama,
    this.dosyaNo,
    this.referansNo,
    this.odendi = false,
    this.hatirlatmaGonderildi = false,
    this.oncelik = 2,
    this.notlar,
  });

  double get kalanTutar => tutar - odenenTutar;
  bool get vadesiGecti => sonOdemeTarihi.isBefore(DateTime.now()) && !odendi;
  int get kalanGun => sonOdemeTarihi.difference(DateTime.now()).inDays;
  bool get kritik => kalanGun <= 3 && !odendi;
  double get odemeOrani => tutar > 0 ? (odenenTutar / tutar * 100) : 0;

  factory BorcModel.fromMap(Map<String, dynamic> m) {
    return BorcModel(
      id: m['id'] as int?,
      globalId: m['global_id'] as String?,
      baslik: m['baslik'] as String? ?? '',
      tur: m['tur'] as String? ?? 'kredi_karti',
      altTur: m['alt_tur'] as String?,
      tutar: (m['tutar'] as num?)?.toDouble() ?? 0,
      odenenTutar: (m['odenen_tutar'] as num?)?.toDouble() ?? 0,
      kesimTarihi: DateTime.tryParse(m['kesim_tarihi']?.toString() ?? '') ?? DateTime.now(),
      sonOdemeTarihi: DateTime.tryParse(m['son_odeme_tarihi']?.toString() ?? '') ?? DateTime.now(),
      odemeTarihi: m['odeme_tarihi'] != null ? DateTime.tryParse(m['odeme_tarihi'].toString()) : null,
      taksitSayisi: (m['taksit_sayisi'] as int?) ?? 1,
      odenenTaksit: (m['odenen_taksit'] as int?) ?? 0,
      aciklama: m['aciklama'] as String?,
      dosyaNo: m['dosya_no'] as String?,
      referansNo: m['referans_no'] as String?,
      odendi: (m['odendi'] as int?) == 1,
      hatirlatmaGonderildi: (m['hatirlatma_gonderildi'] as int?) == 1,
      oncelik: (m['oncelik'] as int?) ?? 2,
      notlar: m['notlar'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'baslik': baslik,
    'tur': tur,
    if (altTur != null) 'alt_tur': altTur,
    'tutar': tutar,
    'odenen_tutar': odenenTutar,
    'kesim_tarihi': kesimTarihi.toIso8601String(),
    'son_odeme_tarihi': sonOdemeTarihi.toIso8601String(),
    if (odemeTarihi != null) 'odeme_tarihi': odemeTarihi!.toIso8601String(),
    'taksit_sayisi': taksitSayisi,
    'odenen_taksit': odenenTaksit,
    if (aciklama != null) 'aciklama': aciklama,
    if (dosyaNo != null) 'dosya_no': dosyaNo,
    if (referansNo != null) 'referans_no': referansNo,
    'odendi': odendi ? 1 : 0,
    'hatirlatma_gonderildi': hatirlatmaGonderildi ? 1 : 0,
    'oncelik': oncelik,
    if (notlar != null) 'notlar': notlar,
  };
}