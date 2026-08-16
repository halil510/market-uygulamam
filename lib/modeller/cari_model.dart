// lib/modeller/cari_model.dart
class CariModel {
  final int? id;
  final String? globalId;
  final String? cariKodu;
  final String unvan;
  final String cariTipi; // Müşteri | Tedarikçi | Hem Müşteri Hem Tedarikçi
  final String? telefon;
  final String? telefon2;
  final String? email;
  final String? email2;
  final String? vergiDairesi;
  final String? vergiNo;
  final String? tcKimlik;
  final double bakiye;
  final double limitTutari;
  final int vadeGun;
  final String? anaGrup;
  final String? altGrup;
  final String? temsilci;
  final String? notlar;
  final String? webSitesi;
  final bool aktif;
  final String? olusturmaTarihi;
  final String? guncelleyen;
  final int? subeId;
  /// GİB e-Fatura Kayıtlı Kullanıcılar Listesi sorgusu sonucu — 'efatura'
  /// | 'earsiv' | null (henüz sorgulanmadı). LOGO gibi profesyonel
  /// yazılımlardaki cari kartı üzerindeki mükellefiyet rozetinin karşılığı.
  final String? mukellefDurumu;
  final String? mukellefSorguTarihi;
  // Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
  // profesyonel sistem." Bu carinin bağlı olduğu fiyat grubu (null =
  // perakende/standart fiyat kullanılır) ve müşteri tipi.
  final int? fiyatGrubuId;
  final String musteriTipi; // 'Perakende' | 'Bayi' | 'Toptan'

  const CariModel({
    this.id, this.globalId, this.cariKodu,
    required this.unvan,
    this.cariTipi = 'Müşteri',
    this.telefon, this.telefon2, this.email, this.email2,
    this.vergiDairesi, this.vergiNo, this.tcKimlik,
    this.bakiye = 0, this.limitTutari = 0, this.vadeGun = 0,
    this.anaGrup, this.altGrup, this.temsilci, this.notlar, this.webSitesi,
    this.aktif = true, this.olusturmaTarihi, this.guncelleyen, this.subeId,
    this.mukellefDurumu, this.mukellefSorguTarihi,
    this.fiyatGrubuId, this.musteriTipi = 'Perakende',
  });

  factory CariModel.fromMap(Map<String, dynamic> m) {
    double toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    return CariModel(
      id: m['id'] as int?,
      globalId: m['global_id'] as String?,
      cariKodu: m['cari_kodu'] as String?,
      unvan: m['unvan'] as String? ?? '',
      cariTipi: m['cari_tipi'] as String? ?? 'Müşteri',
      telefon: m['telefon'] as String?,
      telefon2: m['telefon2'] as String?,
      email: m['email'] as String?,
      email2: m['email2'] as String?,
      vergiDairesi: m['vergi_dairesi'] as String?,
      vergiNo: m['vergi_no'] as String?,
      tcKimlik: m['tc_kimlik'] as String?,
      bakiye: toD(m['bakiye']),
      limitTutari: toD(m['limit_tutari']),
      vadeGun: (m['vade_gun'] as int?) ?? 0,
      anaGrup: m['ana_grup'] as String?,
      altGrup: m['alt_grup'] as String?,
      temsilci: m['temsilci'] as String?,
      notlar: m['notlar'] as String?,
      webSitesi: m['web_sitesi'] as String?,
      aktif: (m['aktif'] as int?) == 1,
      olusturmaTarihi: m['olusturma_tarihi'] as String?,
      guncelleyen: m['guncelleyen'] as String?,
      subeId: m['sube_id'] as int?,
      mukellefDurumu: m['mukellef_durumu'] as String?,
      mukellefSorguTarihi: m['mukellef_sorgu_tarihi'] as String?,
      fiyatGrubuId: m['fiyat_grubu_id'] as int?,
      musteriTipi: m['musteri_tipi'] as String? ?? 'Perakende',
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    if (cariKodu != null) 'cari_kodu': cariKodu,
    'unvan': unvan,
    'cari_tipi': cariTipi,
    if (telefon != null) 'telefon': telefon,
    if (telefon2 != null) 'telefon2': telefon2,
    if (email != null) 'email': email,
    if (email2 != null) 'email2': email2,
    if (vergiDairesi != null) 'vergi_dairesi': vergiDairesi,
    if (vergiNo != null) 'vergi_no': vergiNo,
    if (tcKimlik != null) 'tc_kimlik': tcKimlik,
    'bakiye': bakiye,
    'limit_tutari': limitTutari,
    'vade_gun': vadeGun,
    if (anaGrup != null) 'ana_grup': anaGrup,
    if (altGrup != null) 'alt_grup': altGrup,
    if (temsilci != null) 'temsilci': temsilci,
    if (notlar != null) 'notlar': notlar,
    if (webSitesi != null) 'web_sitesi': webSitesi,
    'aktif': aktif ? 1 : 0,
    if (guncelleyen != null) 'guncelleyen': guncelleyen,
    if (subeId != null) 'sube_id': subeId,
    if (mukellefDurumu != null) 'mukellef_durumu': mukellefDurumu,
    if (mukellefSorguTarihi != null) 'mukellef_sorgu_tarihi': mukellefSorguTarihi,
    if (fiyatGrubuId != null) 'fiyat_grubu_id': fiyatGrubuId,
    'musteri_tipi': musteriTipi,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CariModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  CariModel copyWith({
    String? cariKodu, String? unvan, String? cariTipi, String? telefon, String? email,
    String? vergiDairesi, String? vergiNo, String? tcKimlik, double? bakiye,
    double? limitTutari, int? vadeGun, String? notlar, bool? aktif,
    int? fiyatGrubuId, String? musteriTipi,
  }) => CariModel(
    id: id, globalId: globalId, cariKodu: cariKodu ?? this.cariKodu,
    unvan: unvan ?? this.unvan,
    cariTipi: cariTipi ?? this.cariTipi,
    telefon: telefon ?? this.telefon,
    telefon2: this.telefon2,
    email: email ?? this.email, email2: this.email2,
    vergiDairesi: vergiDairesi ?? this.vergiDairesi,
    vergiNo: vergiNo ?? this.vergiNo,
    tcKimlik: tcKimlik ?? this.tcKimlik,
    bakiye: bakiye ?? this.bakiye,
    limitTutari: limitTutari ?? this.limitTutari,
    vadeGun: vadeGun ?? this.vadeGun,
    anaGrup: this.anaGrup, altGrup: this.altGrup,
    temsilci: this.temsilci, notlar: notlar ?? this.notlar,
    webSitesi: this.webSitesi, aktif: aktif ?? this.aktif,
    olusturmaTarihi: this.olusturmaTarihi, guncelleyen: this.guncelleyen,
    subeId: this.subeId,
    // 🔴 DÜZELTME: önceden bu iki alan copyWith'te HİÇ aktarılmıyordu
    // — herhangi bir copyWith() çağrısı bu bilgileri sessizce sıfırlardı.
    mukellefDurumu: this.mukellefDurumu,
    mukellefSorguTarihi: this.mukellefSorguTarihi,
    fiyatGrubuId: fiyatGrubuId ?? this.fiyatGrubuId,
    musteriTipi: musteriTipi ?? this.musteriTipi,
  );
}
