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

/// SQLite'ın LIKE / lower() işlevi yalnızca ASCII harflerde büyük/küçük
/// harf duyarsızdır: "BİSKREM" kaydı "biskrem" aramasında bulunmaz.
/// Kolonu [aramaNormalize] ile AYNI kurallarla SQL tarafında normalize eden
/// ifade üretir; sorgu metni de [aramaNormalize]'dan geçirilip
/// `LIKE ?` ile karşılaştırılmalıdır. NULL kolon NULL kalır (eşleşmez).
String aramaSqlKolon(String kolon) {
  var e = kolon;
  const eslesme = {
    'İ': 'i', 'I': 'i', 'ı': 'i',
    'Ş': 's', 'ş': 's',
    'Ğ': 'g', 'ğ': 'g',
    'Ü': 'u', 'ü': 'u',
    'Ö': 'o', 'ö': 'o',
    'Ç': 'c', 'ç': 'c',
  };
  eslesme.forEach((k, v) => e = "REPLACE($e,'$k','$v')");
  return 'LOWER($e)';
}
