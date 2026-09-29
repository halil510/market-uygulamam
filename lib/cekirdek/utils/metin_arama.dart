/// Arama için Türkçe karakter ve büyük/küçük harf duyarsız normalizasyon:
/// "Gün Sonu" ↔ "gun sonu", "IŞIK" ↔ "isik".
String aramaNormalize(String s) => s
    .replaceAll('İ', 'i')
    .replaceAll('I', 'i')
    .replaceAll('ı', 'i')
    .toLowerCase()
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');
