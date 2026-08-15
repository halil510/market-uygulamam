// lib/cekirdek/enumlar/kullanici_rolu.dart
enum KullaniciRolu {
  admin('admin'),
  mudur('mudur'),
  kasiyer('kasiyer'),
  personel('personel'),
  depocu('depocu');

  final String label;
  const KullaniciRolu(this.label);

  bool get yetkili => this == admin || this == mudur;

  static KullaniciRolu fromString(String v) =>
      KullaniciRolu.values.firstWhere((e) => e.label == v, orElse: () => KullaniciRolu.personel);
}


