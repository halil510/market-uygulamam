// lib/cekirdek/utils/excel_guvenlik_utils.dart
//
// Excel/CSV formül enjeksiyonu koruması (OWASP: CSV Injection). Excel,
// bir hücre '='/'+'/'-'/'@' ile başlıyorsa içeriği FORMÜL olarak
// çalıştırabilir — kullanıcının serbestçe girdiği bir alan (ürün adı,
// cari unvanı vb.) kazara ya da kasıtlı olarak böyle başlarsa, dışa
// aktarılan dosya başka bir bilgisayarda açıldığında rastgele bir
// formül tetiklenebilir. Serbest metin alanları Excel'e yazılmadan
// önce bu fonksiyondan geçirilmeli.
String excelIcinGuvenliMetin(String? deger) {
  final metin = deger ?? '';
  if (metin.isEmpty) return metin;
  const tehlikeliOnekler = ['=', '+', '-', '@'];
  return tehlikeliOnekler.contains(metin[0]) ? "'$metin" : metin;
}
