// lib/servisler/excel_yardimcilar.dart
//
// excel_servisi.dart'ın parçası — sınıftan bağımsız sayı/tarih ayrıştırıcılar.
part of 'excel_servisi.dart';

/// Excel hücresindeki sayıyı Türkçe/İngilizce biçimlerin ikisinde de okur:
/// `1.234,50` · `1,234.50` · `1234,5` · `1.234.567` · `₺12,5 TL` · `-3`.
/// İki ayraç birlikte varsa SONUNCUSU ondalıktır; tek ayraç birden çok
/// kez geçiyorsa binliktir; tek bir virgül ondalık, tek bir nokta ondalık
/// (hücre sayısal ise Dart zaten `12.5` verir) sayılır.
/// Çözümlenemeyen/boş değer için null.
double? excelSayiAyristir(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();

  var str = value.toString().trim();
  if (str.isEmpty) return null;
  str = str.replaceAll('₺', '').replaceAll('TL', '').replaceAll(RegExp(r'\s'), '');
  str = str.replaceAll(RegExp(r'[^0-9.,-]'), '');
  if (str.isEmpty || str == '-') return null;

  final sonVirgul = str.lastIndexOf(',');
  final sonNokta = str.lastIndexOf('.');
  if (sonVirgul != -1 && sonNokta != -1) {
    final ondalik = sonVirgul > sonNokta ? ',' : '.';
    final bin = ondalik == ',' ? '.' : ',';
    str = str.replaceAll(bin, '');
    if (ondalik == ',') str = str.replaceAll(',', '.');
  } else if (sonVirgul != -1) {
    str = str.indexOf(',') == sonVirgul
        ? str.replaceAll(',', '.')
        : str.replaceAll(',', '');
  } else if (sonNokta != -1 && str.indexOf('.') != sonNokta) {
    str = str.replaceAll('.', '');
  }
  return double.tryParse(str);
}

/// ISO (`2025-12-31`, `2025-12-31T10:00`) ya da Türkçe (`31.12.2025`,
/// `31/12/2025`, isteğe bağlı saat) tarih metnini okur; çözümlenemezse null.
DateTime? excelTarihAyristir(String metin) {
  final s = metin.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})(?:[ T](\d{1,2}):(\d{2}))?')
      .firstMatch(s);
  if (m == null) return null;
  final g = int.parse(m.group(1)!), a = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
  if (a < 1 || a > 12 || g < 1 || g > 31) return null;
  final sa = int.tryParse(m.group(4) ?? '') ?? 0, dk = int.tryParse(m.group(5) ?? '') ?? 0;
  final d = DateTime(y, a, g, sa, dk);
  return d.month == a ? d : null; // 31.02 gibi taşmaları reddet
}
