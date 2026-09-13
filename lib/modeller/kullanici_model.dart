// lib/modeller/kullanici_model.dart
class KullaniciModel {
  final int? id;
  final String kullaniciAdi;
  final String sifreHash;
  final String? tuz;
  final String adSoyad;
  final String rol;
  final String? email;
  final String? telefon;
  final bool aktif;
  final String? sonGiris;
  final int? subeId;
  /// Doluysa bu kullanıcı bir Bayi Portalı hesabıdır (rol hâlâ 'personel'
  /// kalabilir) — değeri, kullanıcının SADECE kendi verisini görebileceği
  /// cari.id'dir (bkz. erp_roadmap madde 39, FAZ — Bayi Portalı).
  final int? bayiCariId;

  bool get isAdmin => rol == 'admin';
  bool get isMudur => rol == 'mudur' || rol == 'admin';
  bool get isBayi => bayiCariId != null;

  const KullaniciModel({
    this.id, required this.kullaniciAdi, required this.sifreHash,
    this.tuz,
    required this.adSoyad, this.rol = 'personel',
    this.email, this.telefon, this.aktif = true,
    this.sonGiris, this.subeId, this.bayiCariId,
  });

  factory KullaniciModel.fromMap(Map<String, dynamic> m) => KullaniciModel(
    id: m['id'] as int?,
    kullaniciAdi: m['kullanici_adi'] as String? ?? '',
    sifreHash: m['sifre_hash'] as String? ?? '',
    tuz: m['tuz'] as String?,
    adSoyad: m['ad_soyad'] as String? ?? '',
    rol: m['rol'] as String? ?? 'personel',
    email: m['email'] as String?,
    telefon: m['telefon'] as String?,
    aktif: (m['aktif'] as int?) == 1,
    sonGiris: m['son_giris'] as String?,
    subeId: m['sube_id'] as int?,
    bayiCariId: m['bayi_cari_id'] as int?,
  );


  KullaniciModel copyWith({
    int? id,
    String? kullaniciAdi,
    String? sifreHash,
    String? tuz,
    String? adSoyad,
    String? rol,
    String? email,
    String? telefon,
    bool? aktif,
    String? sonGiris,
    int? subeId,
    int? bayiCariId,
  }) => KullaniciModel(
      id: id ?? this.id,
      kullaniciAdi: kullaniciAdi ?? this.kullaniciAdi,
      sifreHash: sifreHash ?? this.sifreHash,
      tuz: tuz ?? this.tuz,
      adSoyad: adSoyad ?? this.adSoyad,
      rol: rol ?? this.rol,
      email: email ?? this.email,
      telefon: telefon ?? this.telefon,
      aktif: aktif ?? this.aktif,
      sonGiris: sonGiris ?? this.sonGiris,
      subeId: subeId ?? this.subeId,
      bayiCariId: bayiCariId ?? this.bayiCariId,
    );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'kullanici_adi': kullaniciAdi, 'sifre_hash': sifreHash,
    if (tuz != null) 'tuz': tuz,
    'ad_soyad': adSoyad, 'rol': rol,
    if (email != null) 'email': email,
    if (telefon != null) 'telefon': telefon,
    'aktif': aktif ? 1 : 0,
    if (sonGiris != null) 'son_giris': sonGiris,
    if (subeId != null) 'sube_id': subeId,
    if (bayiCariId != null) 'bayi_cari_id': bayiCariId,
  };
}
