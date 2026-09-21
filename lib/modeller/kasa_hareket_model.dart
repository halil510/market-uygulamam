// lib/modeller/kasa_hareket_model.dart
class KasaHareketModel {
  // 🔴 MERKEZİ KAYNAK: Bu sınıflandırma önceden 3 farklı dosyada ayrı
  // ayrı (2'si doğru, 1'i EKSİK — 'Giriş','Virman Giriş','Iade Iptali',
  // 'İade İptali','Ödeme Girişi' unutulmuş) tanımlanmıştı. Eksik olan
  // kopya, o ekranda bu hareket tiplerinin YANLIŞLIKLA "çıkış" (kırmızı,
  // eksi işaretli) gösterilmesine yol açıyordu. Artık TEK kaynak —
  // hangi ekran/servis kullanırsa kullansın buradan referans alınmalı.
  static const Set<String> girisTipleri = {
    'Satış',
    'Tahsilat',
    'AçılışKasa',
    'Giriş',
    'Virman Giriş',
    'Iade Iptali',
    'İade İptali',
    'Ödeme Girişi',
    'Gider İptali',
    // 🆕 (kullanıcı bulgusu, 2026-09-22 — Alım silme akışı eklendi):
    // 'Alım' kendisi ÇIKIŞ'tır (mal alırken kasadan para çıkar), bu
    // yüzden burada YOK — ama bir Alım'ın İPTALİ (silinmesi) kasaya
    // parayı GERİ koyar, dolayısıyla GİRİŞ'tir.
    'Alım İptali',
  };
  static bool girisMi(String hareketTipi) => girisTipleri.contains(hareketTipi);

  final int? id;
  // 🔴 Derin analizde bulundu: bu alan hiç yoktu — bu modelle eklenen
  // HER kasa hareketi (uygulamadaki neredeyse tüm satış/tahsilat/ödeme
  // akışı) buluta kimliksiz (global_id=NULL) gidiyordu.
  final String? globalId;
  final String hareketTipi;
  final double tutar;
  final double? bakiyeSonrasi;
  final int? referansId;
  final String? referansTuru;
  final DateTime tarih;
  final String? aciklama;
  final int? kullaniciId;
  // FAZ 1 madde 2 (Vardiya/Kasa mutabakatı): 'Satış' hareketinin hangi
  // ödeme yöntemiyle (Nakit/Kredi Kartı/Banka) yapıldığını taşır — bu
  // olmadan kasa_hareketleri zinciri Nakit ile Kart'ı ayıramıyordu.
  // Nullable: eski kayıtlar ve Satış-dışı hareket tipleri bunu set etmez.
  final String? odemeYontemi;

  const KasaHareketModel({
    this.id,
    this.globalId,
    required this.hareketTipi,
    required this.tutar,
    this.bakiyeSonrasi,
    this.referansId,
    this.referansTuru,
    required this.tarih,
    this.aciklama,
    this.kullaniciId,
    this.odemeYontemi,
  });

  factory KasaHareketModel.fromMap(Map<String, dynamic> m) {
    double toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return KasaHareketModel(
      id: m['id'] as int?,
      globalId: m['global_id'] as String?,
      hareketTipi: m['hareket_tipi'] as String? ?? '',
      tutar: toD(m['tutar']),
      bakiyeSonrasi:
          m['bakiye_sonrasi'] != null ? toD(m['bakiye_sonrasi']) : null,
      referansId: m['referans_id'] as int?,
      referansTuru: m['referans_turu'] as String?,
      tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
      aciklama: m['aciklama'] as String?,
      kullaniciId: m['kullanici_id'] as int?,
      odemeYontemi: m['odeme_yontemi'] as String?,
    );
  }

  KasaHareketModel copyWith({
    int? id,
    String? globalId,
    String? hareketTipi,
    double? tutar,
    double? bakiyeSonrasi,
    int? referansId,
    String? referansTuru,
    DateTime? tarih,
    String? aciklama,
    int? kullaniciId,
    String? odemeYontemi,
  }) =>
      KasaHareketModel(
        id: id ?? this.id,
        globalId: globalId ?? this.globalId,
        hareketTipi: hareketTipi ?? this.hareketTipi,
        tutar: tutar ?? this.tutar,
        bakiyeSonrasi: bakiyeSonrasi ?? this.bakiyeSonrasi,
        referansId: referansId ?? this.referansId,
        referansTuru: referansTuru ?? this.referansTuru,
        tarih: tarih ?? this.tarih,
        aciklama: aciklama ?? this.aciklama,
        kullaniciId: kullaniciId ?? this.kullaniciId,
        odemeYontemi: odemeYontemi ?? this.odemeYontemi,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (globalId != null) 'global_id': globalId,
        'hareket_tipi': hareketTipi,
        'tutar': tutar,
        if (bakiyeSonrasi != null) 'bakiye_sonrasi': bakiyeSonrasi,
        if (referansId != null) 'referans_id': referansId,
        if (referansTuru != null) 'referans_turu': referansTuru,
        'tarih': tarih.toIso8601String(),
        if (aciklama != null) 'aciklama': aciklama,
        if (kullaniciId != null) 'kullanici_id': kullaniciId,
        if (odemeYontemi != null) 'odeme_yontemi': odemeYontemi,
      };
}
