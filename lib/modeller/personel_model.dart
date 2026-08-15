// lib/modeller/personel_model.dart
// DB şeması: id, kullanici_id, ad_soyad, tc_kimlik, pozisyon, telefon,
// email, maas, ise_baslama, isten_cikis, aktif, notlar

class PersonelModel {
  final int     id;
  final int?    kullaniciId;
  final String  adSoyad;
  final String? tcKimlik;
  final String? pozisyon;
  final String? telefon;
  final String? email;
  final double  maas;
  final DateTime? iseBaslama;
  final DateTime? istenCikis;
  final bool    aktif;
  final String? notlar;

  const PersonelModel({
    required this.id,
    this.kullaniciId,
    required this.adSoyad,
    this.tcKimlik,
    this.pozisyon,
    this.telefon,
    this.email,
    this.maas      = 0,
    this.iseBaslama,
    this.istenCikis,
    this.aktif     = true,
    this.notlar,
  });

  // Geriye dönük uyumluluk için alias getter
  String? get departman   => pozisyon;
  double? get calismaSaati => null;

  factory PersonelModel.fromMap(Map<String, dynamic> m) => PersonelModel(
    id:           m['id'] as int,
    kullaniciId:  m['kullanici_id'] as int?,
    adSoyad:      m['ad_soyad'] as String? ?? '',
    tcKimlik:     m['tc_kimlik'] as String?,
    pozisyon:     m['pozisyon'] as String?,
    // ÖNCEDEN: telefon/email her zaman null döndüren sabit getter'lardı —
    // veritabanında sütun bile yoktu, form doldurulsa da veri
    // kayboluyordu. Artık gerçek sütunlardan okunuyor (bkz. migration v23).
    telefon:      m['telefon'] as String?,
    email:        m['email'] as String?,
    maas:         (m['maas'] as num?)?.toDouble() ?? 0,
    iseBaslama:   m['ise_baslama'] != null
        ? DateTime.tryParse(m['ise_baslama'].toString()) : null,
    istenCikis:   m['isten_cikis'] != null
        ? DateTime.tryParse(m['isten_cikis'].toString()) : null,
    aktif:        (m['aktif'] as int? ?? 1) == 1,
    notlar:       m['notlar'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'kullanici_id': kullaniciId,
    'ad_soyad':     adSoyad,
    'tc_kimlik':    tcKimlik,
    'pozisyon':     pozisyon,
    'telefon':      telefon,
    'email':        email,
    'maas':         maas,
    'ise_baslama':  iseBaslama?.toIso8601String().split('T').first,
    'isten_cikis':  istenCikis?.toIso8601String().split('T').first,
    'aktif':        aktif ? 1 : 0,
    'notlar':       notlar,
  };

  PersonelModel copyWith({
    int? id, int? kullaniciId, String? adSoyad, String? tcKimlik,
    String? pozisyon, String? telefon, String? email, double? maas,
    DateTime? iseBaslama, DateTime? istenCikis, bool? aktif, String? notlar,
  }) => PersonelModel(
    id: id ?? this.id, kullaniciId: kullaniciId ?? this.kullaniciId,
    adSoyad: adSoyad ?? this.adSoyad, tcKimlik: tcKimlik ?? this.tcKimlik,
    pozisyon: pozisyon ?? this.pozisyon,
    telefon: telefon ?? this.telefon, email: email ?? this.email,
    maas: maas ?? this.maas,
    iseBaslama: iseBaslama ?? this.iseBaslama, istenCikis: istenCikis ?? this.istenCikis,
    aktif: aktif ?? this.aktif, notlar: notlar ?? this.notlar,
  );
}
