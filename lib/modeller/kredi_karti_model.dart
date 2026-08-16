// lib/modeller/kredi_karti_model.dart
//
// GÜVENLİK NOTU: Bu model artık kart numarasını TAM olarak tutmuyor.
// `kartNoMaskeli` alanı sadece görüntüleme amaçlı son 4 haneyi içerir
// (ör. "**** **** **** 4242"). CVC hiçbir koşulda saklanmaz/taşınmaz.
// Tam kart numarası girişi formda alınabilir ama diske yazılmadan önce
// KrediKartiModel.maskele() ile dönüştürülmelidir.
class KrediKartiModel {
  final int? id;
  final String? globalId;
  final int bankaId;
  final String kartAdi;
  final String kartNoMaskeli;
  final String? sonKullanma;
  final String kartTipi;
  final double kartLimit;
  final double kullanilanLimit;
  final double kalanLimit;
  final double faizOrani;
  final int taksitSayisi;
  final DateTime? kesimTarihi;
  final DateTime? sonOdemeTarihi;
  final bool aktif;

  const KrediKartiModel({
    this.id,
    this.globalId,
    required this.bankaId,
    required this.kartAdi,
    required this.kartNoMaskeli,
    this.sonKullanma,
    this.kartTipi = 'Diğer',
    this.kartLimit = 0,
    this.kullanilanLimit = 0,
    this.kalanLimit = 0,
    this.faizOrani = 0,
    this.taksitSayisi = 1,
    this.kesimTarihi,
    this.sonOdemeTarihi,
    this.aktif = true,
  });

  /// Kullanıcının formda girdiği TAM kart numarasını, diske asla
  /// yazılmayacak şekilde son-4-hane maskeli forma çevirir.
  /// Ekranlar bu metodu kullanmalı, ham numarayı hiçbir yere kaydetmemeli.
  static String maskele(String tamNumara) {
    final temiz = tamNumara.replaceAll(RegExp(r'\s'), '');
    if (temiz.isEmpty) return '**** **** **** ????';
    final son4 = temiz.length >= 4 ? temiz.substring(temiz.length - 4) : temiz;
    return '**** **** **** $son4';
  }

  factory KrediKartiModel.fromMap(Map<String, dynamic> m) => KrediKartiModel(
    id: m['id'] as int?,
    globalId: m['global_id'] as String?,
    bankaId: m['banka_id'] as int? ?? 0,
    kartAdi: m['kart_adi'] as String? ?? '',
    kartNoMaskeli: (m['kart_no_maskeli'] as String?) ??
        (m['kart_no'] as String?) ?? // eski (göç etmemiş) kayıtlar için geriye dönük okuma
        '**** **** **** ????',
    sonKullanma: m['son_kullanma'] as String?,
    kartTipi: m['kart_tipi'] as String? ?? 'Diğer',
    kartLimit: (m['kartlimit'] as num?)?.toDouble() ?? 0,
    kullanilanLimit: (m['kullanilan_limit'] as num?)?.toDouble() ?? 0,
    kalanLimit: (m['kalan_limit'] as num?)?.toDouble() ?? 0,
    faizOrani: (m['faiz_orani'] as num?)?.toDouble() ?? 0,
    taksitSayisi: (m['taksit_sayisi'] as int?) ?? 1,
    kesimTarihi: m['kesim_tarihi'] != null ? DateTime.tryParse(m['kesim_tarihi'].toString()) : null,
    sonOdemeTarihi: m['son_odeme_tarihi'] != null ? DateTime.tryParse(m['son_odeme_tarihi'].toString()) : null,
    aktif: (m['aktif'] as int?) == 1,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'banka_id': bankaId,
    'kart_adi': kartAdi,
    'kart_no_maskeli': kartNoMaskeli,
    if (sonKullanma != null) 'son_kullanma': sonKullanma,
    'kart_tipi': kartTipi,
    'kartlimit': kartLimit,
    'kullanilan_limit': kullanilanLimit,
    'kalan_limit': kalanLimit,
    'faiz_orani': faizOrani,
    'taksit_sayisi': taksitSayisi,
    if (kesimTarihi != null) 'kesim_tarihi': kesimTarihi!.toIso8601String(),
    if (sonOdemeTarihi != null) 'son_odeme_tarihi': sonOdemeTarihi!.toIso8601String(),
    'aktif': aktif ? 1 : 0,
    'last_updated': DateTime.now().toIso8601String(),
  };

  // 🔴 DÜZELTME (derin analizde bulundu — CariModel'de bulunanla AYNI
  // hata sınıfı): Bu modelde copyWith() HİÇ YOKTU. Kart düzenleme ekranı
  // bu yüzden sıfırdan yeni bir KrediKartiModel(...) oluşturuyordu —
  // 'kullanilan_limit'/'kalan_limit' KOŞULSUZ yazıldığı ve formda hiç
  // YER ALMADIĞI için, kartın ADINI değiştirmek bile o kartın GÜNCEL
  // KULLANIM TUTARINI sessizce sıfıra düşürüyordu.
  KrediKartiModel copyWith({
    int? bankaId,
    String? kartAdi,
    String? kartNoMaskeli,
    String? sonKullanma,
    String? kartTipi,
    double? kartLimit,
    double? kullanilanLimit,
    double? kalanLimit,
    double? faizOrani,
    int? taksitSayisi,
    DateTime? kesimTarihi,
    DateTime? sonOdemeTarihi,
    bool? aktif,
  }) => KrediKartiModel(
    id: id, globalId: globalId,
    bankaId: bankaId ?? this.bankaId,
    kartAdi: kartAdi ?? this.kartAdi,
    kartNoMaskeli: kartNoMaskeli ?? this.kartNoMaskeli,
    sonKullanma: sonKullanma ?? this.sonKullanma,
    kartTipi: kartTipi ?? this.kartTipi,
    kartLimit: kartLimit ?? this.kartLimit,
    kullanilanLimit: kullanilanLimit ?? this.kullanilanLimit,
    kalanLimit: kalanLimit ?? this.kalanLimit,
    faizOrani: faizOrani ?? this.faizOrani,
    taksitSayisi: taksitSayisi ?? this.taksitSayisi,
    kesimTarihi: kesimTarihi ?? this.kesimTarihi,
    sonOdemeTarihi: sonOdemeTarihi ?? this.sonOdemeTarihi,
    aktif: aktif ?? this.aktif,
  );
}
