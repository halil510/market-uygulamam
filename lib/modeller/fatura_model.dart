// lib/modeller/fatura_model.dart
// Bu dosya, fatura ve fatura detaylarını temsil eden modelleri içerir.

// FaturaModel.cariAdres'i "ADRES İLÇE / İL - TR" formatında oluşturur.
// cari_adres tablosundan canlı (LEFT JOIN) gelen ham alanlar kullanılır.
// Eğer kayıt zaten birleşik 'cari_adres' string'i içeriyorsa (geriye dönük
// uyumluluk) onu kullanır.
String? _adresBirlestir(Map<String, dynamic> m) {
  if (m['cari_adres'] is String && (m['cari_adres'] as String).isNotEmpty) {
    return m['cari_adres'] as String;
  }
  final adres = (m['cari_adres_ham'] as String?)?.trim() ?? '';
  final ilce  = (m['cari_ilce'] as String?)?.trim() ?? '';
  final il    = (m['cari_il'] as String?)?.trim() ?? '';
  final parcalar = <String>[];
  if (adres.isNotEmpty) parcalar.add(adres);
  if (ilce.isNotEmpty || il.isNotEmpty) {
    final ilceIl = [ilce, il].where((x) => x.isNotEmpty).join(' / ');
    parcalar.add('$ilceIl - TR');
  }
  return parcalar.isEmpty ? null : parcalar.join(' ');
}

// ========================= FATURA MODEL =========================
class FaturaModel {
  // Temel alanlar
  final int? id;
  final String? globalId;
  final String? faturaNo;
  final String? faturaTipi; // Satış, Alış, İade, Proforma, e-Fatura, e-Arşiv
  final int? satisId;
  final int? iadeId;
  final int? cariId;
  final String? cariUnvan;
  final String? cariVergiNo;
  /// GİB'de gerçekten sorgulanmış e-Fatura mükellefiyet durumu
  /// ('efatura'/'earsiv'/null) — VKN uzunluğuna göre TAHMİN değil.
  final String? cariMukellefDurumu;
  final String? cariVergiDairesi;
  final String? cariAdres;
  final int? subeId;
  final DateTime tarih;
  final DateTime? duzenlenmeTarihi;
  final DateTime? sevkTarihi;
  final DateTime? vadeTarihi;
  final String? malinNereye;
  final String? teslimEden;
  final String? teslimAlan;
  final double toplamAraToplam;
  final double toplamIskonto;
  final double toplamKdv;
  final double genelToplam;
  final double odenenTutar;
  final double kalanTutar;
  final String odemeDurumu; // 'beklemede', 'odendi', 'kısmen'
  /// Ödeme şekli (Nakit/Kredi Kartı/Havale-EFT/Çek) — ÖNCEDEN bu alan
  /// hiç yoktu, ne basılan faturada ne UBL-TR XML'inde gösteriliyordu.
  final String? odemeSekli;
  final String? eFaturaUuid;
  final String? eFaturaDurum; // 'hazir','gonderiliyor','gonderildi','onaylandi','reddedildi','gib_iptal','hata'
  final int eFaturaDenemeNo;
  final String? eFaturaHtml;
  final String? eFaturaXml;
  final DateTime? gonderimTarihi;
  final String? uygulamaYaniti;
  final String? htmlIcerik;
  final String? xmlIcerik;
  final String durum; // 'aktif', 'iptal'
  final List<FaturaDetayModel> detaylar; // Fatura satırları

  // Yardımcı getter'lar
  bool get odendi => odemeDurumu == 'odendi';
  bool get eFaturaGonderildi => eFaturaDurum == 'gonderildi';
  bool get vadesiGecti => vadeTarihi != null &&
      DateTime.now().isAfter(vadeTarihi!) && !odendi;

  // Constructor
  const FaturaModel({
    this.id, this.globalId, this.faturaNo,
    this.faturaTipi = 'Satış',
    this.satisId, this.iadeId, this.cariId, this.cariUnvan, this.cariVergiNo,
    this.cariMukellefDurumu,
    this.cariVergiDairesi, this.cariAdres, this.subeId,
    required this.tarih,
    this.duzenlenmeTarihi, this.sevkTarihi, this.vadeTarihi,
    this.malinNereye, this.teslimEden, this.teslimAlan,
    this.toplamAraToplam = 0, this.toplamIskonto = 0,
    this.toplamKdv = 0, this.genelToplam = 0,
    this.odenenTutar = 0, this.kalanTutar = 0,
    this.odemeDurumu = 'beklemede',
    this.odemeSekli,
    this.eFaturaUuid, this.eFaturaDurum = 'hazir',
    this.eFaturaDenemeNo = 0,
    this.eFaturaHtml, this.eFaturaXml,
    this.gonderimTarihi, this.uygulamaYaniti,
    this.htmlIcerik, this.xmlIcerik,
    this.durum = 'aktif',
    this.detaylar = const [],
  });

  // JSON/Map dönüşümlerinde double değerleri güvenle okumak için yardımcı metod
  static double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  // Map'ten FaturaModel oluşturma (veritabanı veya JSON için)
  factory FaturaModel.fromMap(Map<String, dynamic> m,
      {List<FaturaDetayModel>? detaylar}) {
    return FaturaModel(
      id: m['id'] as int?,
      globalId: m['global_id'] as String?,
      faturaNo: m['fatura_no'] as String?,
      faturaTipi: m['fatura_tipi'] as String?,
      satisId: m['satis_id'] as int?,
      iadeId: m['iade_id'] as int?,
      cariId: m['cari_id'] as int?,
      cariUnvan: m['cari_unvan'] as String?,
      cariVergiNo: m['cari_vergi_no'] as String?,
      cariMukellefDurumu: m['cari_mukellef_durumu'] as String?,
      cariVergiDairesi: m['cari_vergi_dairesi'] as String?,
      cariAdres: _adresBirlestir(m),
      subeId: m['sube_id'] as int?,
      tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
      duzenlenmeTarihi: m['duzenlenme_tarihi'] != null
          ? DateTime.tryParse(m['duzenlenme_tarihi'].toString()) : null,
      sevkTarihi: m['sevk_tarihi'] != null
          ? DateTime.tryParse(m['sevk_tarihi'].toString()) : null,
      vadeTarihi: m['vade_tarihi'] != null
          ? DateTime.tryParse(m['vade_tarihi'].toString()) : null,
      malinNereye: m['malin_nereye'] as String?,
      teslimEden: m['teslim_eden'] as String?,
      teslimAlan: m['teslim_alan'] as String?,
      toplamAraToplam: _d(m['toplam_ara_toplam']),
      toplamIskonto: _d(m['toplam_iskonto']),
      toplamKdv: _d(m['toplam_kdv']),
      genelToplam: _d(m['genel_toplam']),
      odenenTutar: _d(m['odenen_tutar']),
      kalanTutar: _d(m['kalan_tutar']),
      odemeDurumu: m['odeme_durumu'] as String? ?? 'beklemede',
      odemeSekli: m['odeme_sekli'] as String?,
      eFaturaUuid: m['e_fatura_uuid'] as String?,
      eFaturaDurum: m['e_fatura_durum'] as String? ?? 'hazir',
      eFaturaDenemeNo: (m['e_fatura_deneme_no'] as int?) ?? 0,
      eFaturaHtml: m['e_fatura_html'] as String?,
      eFaturaXml: m['e_fatura_xml'] as String?,
      gonderimTarihi: m['gonderim_tarihi'] != null
          ? DateTime.tryParse(m['gonderim_tarihi'].toString()) : null,
      uygulamaYaniti: m['uygulama_yaniti'] as String?,
      htmlIcerik: m['html_icerik'] as String?,
      xmlIcerik: m['xml_icerik'] as String?,
      durum: m['durum'] as String? ?? 'aktif',
      detaylar: detaylar ?? [],
    );
  }

  // NOT: Buraya ait copyWith metodu YOKTUR, çünkü FaturaModel için copyWith
  // genellikle kullanılmaz (fatura bilgileri çoğunlukla değiştirilmez).
  // Eğer ihtiyaç duyarsanız, sadece FaturaModel alanlarını kullanarak
  // ayrıca yazabilirsiniz. Ancak bu dosyadaki hata, yanlışlıkla
  // FaturaDetayModel'e ait copyWith'in buraya yapıştırılmasıydı.
  // O hatalı metod KALDIRILMIŞTIR.

  // FaturaModel'i Map'e dönüştürme (veritabanı kaydı için)
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    if (faturaNo != null) 'fatura_no': faturaNo,
    if (faturaTipi != null) 'fatura_tipi': faturaTipi,
    if (satisId != null) 'satis_id': satisId,
    if (iadeId != null) 'iade_id': iadeId,
    if (cariId != null) 'cari_id': cariId,
    if (subeId != null) 'sube_id': subeId,
    'tarih': tarih.toIso8601String(),
    if (duzenlenmeTarihi != null) 'duzenlenme_tarihi': duzenlenmeTarihi!.toIso8601String(),
    if (sevkTarihi != null) 'sevk_tarihi': sevkTarihi!.toIso8601String(),
    if (vadeTarihi != null) 'vade_tarihi': vadeTarihi!.toIso8601String(),
    if (malinNereye != null) 'malin_nereye': malinNereye,
    if (teslimEden != null) 'teslim_eden': teslimEden,
    if (teslimAlan != null) 'teslim_alan': teslimAlan,
    'toplam_ara_toplam': toplamAraToplam, 'toplam_iskonto': toplamIskonto,
    'toplam_kdv': toplamKdv, 'genel_toplam': genelToplam,
    'odenen_tutar': odenenTutar, 'kalan_tutar': kalanTutar,
    'odeme_durumu': odemeDurumu,
    if (odemeSekli != null) 'odeme_sekli': odemeSekli,
    if (eFaturaUuid != null) 'e_fatura_uuid': eFaturaUuid,
    'e_fatura_durum': eFaturaDurum ?? 'hazir',
    if (eFaturaHtml != null) 'e_fatura_html': eFaturaHtml,
    if (eFaturaXml != null) 'e_fatura_xml': eFaturaXml,
    if (gonderimTarihi != null) 'gonderim_tarihi': gonderimTarihi!.toIso8601String(),
    if (uygulamaYaniti != null) 'uygulama_yaniti': uygulamaYaniti,
    if (htmlIcerik != null) 'html_icerik': htmlIcerik,
    if (xmlIcerik != null) 'xml_icerik': xmlIcerik,
    'durum': durum,
  };
}

// ========================= FATURA DETAY MODEL =========================
// Bu sınıf fatura kalemlerini (ürün satırlarını) temsil eder.
// NOT: Bu sınıf zaten doğru bir copyWith metoduna sahiptir.
class FaturaDetayModel {
  final int? id;
  final String? globalId;
  final int? faturaId;      // Hangi faturaya ait olduğu
  final int? urunId;
  final String urunAdi;
  final String? barkod;
  final double miktar;
  final double birimFiyat;
  final double iskontoOrani;
  final double iskontoTutari;
  final double kdvOrani;
  final double kdvTutari;
  final double araToplam;
  final double toplamTutar;
  final String? lotSeriNo;

  const FaturaDetayModel({
    this.id, this.globalId, this.faturaId, this.urunId,
    required this.urunAdi, this.barkod,
    required this.miktar, required this.birimFiyat,
    this.iskontoOrani = 0, this.iskontoTutari = 0,
    required this.kdvOrani,
    this.kdvTutari = 0, this.araToplam = 0, this.toplamTutar = 0,
    this.lotSeriNo,
  });

  static double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  factory FaturaDetayModel.fromMap(Map<String, dynamic> m) => FaturaDetayModel(
    id: m['id'] as int?, globalId: m['global_id'] as String?,
    faturaId: m['fatura_id'] as int?, urunId: m['urun_id'] as int?,
    urunAdi: m['urun_adi'] as String? ?? '', barkod: m['barkod'] as String?,
    miktar: _d(m['miktar']), birimFiyat: _d(m['birim_fiyat']),
    iskontoOrani: _d(m['iskonto_orani']), iskontoTutari: _d(m['iskonto_tutari']),
    kdvOrani: _d(m['kdv_orani']), kdvTutari: _d(m['kdv_tutari']),
    araToplam: _d(m['ara_toplam']), toplamTutar: _d(m['toplam_tutar']),
    lotSeriNo: m['lot_seri_no'] as String?,
  );

  // Doğru copyWith metodu - sadece FaturaDetayModel alanlarını kullanır
  FaturaDetayModel copyWith({
    int? id,
    String? globalId,
    int? faturaId,
    int? urunId,
    String? urunAdi,
    String? barkod,
    double? miktar,
    double? birimFiyat,
    double? iskontoOrani,
    double? iskontoTutari,
    double? kdvOrani,
    double? kdvTutari,
    double? araToplam,
    double? toplamTutar,
    String? lotSeriNo,
  }) => FaturaDetayModel(
      id: id ?? this.id,
      globalId: globalId ?? this.globalId,
      faturaId: faturaId ?? this.faturaId,
      urunId: urunId ?? this.urunId,
      urunAdi: urunAdi ?? this.urunAdi,
      barkod: barkod ?? this.barkod,
      miktar: miktar ?? this.miktar,
      birimFiyat: birimFiyat ?? this.birimFiyat,
      iskontoOrani: iskontoOrani ?? this.iskontoOrani,
      iskontoTutari: iskontoTutari ?? this.iskontoTutari,
      kdvOrani: kdvOrani ?? this.kdvOrani,
      kdvTutari: kdvTutari ?? this.kdvTutari,
      araToplam: araToplam ?? this.araToplam,
      toplamTutar: toplamTutar ?? this.toplamTutar,
      lotSeriNo: lotSeriNo ?? this.lotSeriNo,
    );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    if (faturaId != null) 'fatura_id': faturaId,
    if (urunId != null) 'urun_id': urunId,
    'urun_adi': urunAdi, if (barkod != null) 'barkod': barkod,
    'miktar': miktar, 'birim_fiyat': birimFiyat,
    'iskonto_orani': iskontoOrani, 'iskonto_tutari': iskontoTutari,
    'kdv_orani': kdvOrani, 'kdv_tutari': kdvTutari,
    'ara_toplam': araToplam, 'toplam_tutar': toplamTutar,
    if (lotSeriNo != null) 'lot_seri_no': lotSeriNo,
  };
}