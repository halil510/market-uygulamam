// lib/servisler/ai/eylem/ai_varlik_arama.dart
//
// Konuşmadaki ürün/cari adını ("kolanın", "ekmeğe", "sütten", "Ali Yılmaz'dan")
// veritabanında aranabilir ADAY köklere çevirir — saf, test edilebilir.
//
// Türkçe ekler ve ünsüz yumuşaması yüzünden "ekmeğe" ≠ "ekmek", "kitabı" ≠
// "kitap" gibi eşleşmezlikleri aşar: en uzun adaydan en kısaya doğru dener.
import '../tr_sayi_ayristirici.dart';

class AiVarlikArama {
  AiVarlikArama._();

  static const Set<String> _halEkleri = {
    'n', 'ın', 'in', 'un', 'ün', 'nın', 'nin', 'nun', 'nün', 'yı', 'yi', 'yu', 'yü',
    'yun', 'yün', 'yin', 'yın', 'a', 'e', 'ya', 'ye', 'na', 'ne', 'da', 'de', 'ta',
    'te', 'dan', 'den', 'tan', 'ten', 'la', 'le', 'yla', 'yle', 'ı', 'i', 'u', 'ü',
    'lar', 'ler', 'ları', 'leri', 'ndan', 'nden',
  };

  /// Ünsüz yumuşaması geri alma: ğ→k, b→p, c→ç, d→t (kök sonunda).
  static List<String> _yumusamaVaryantlari(String kok) {
    if (kok.isEmpty) return const [];
    final son = kok[kok.length - 1];
    final govde = kok.substring(0, kok.length - 1);
    return switch (son) {
      'ğ' => ['${govde}k', '${govde}g'],
      'b' => ['${govde}p'],
      'c' => ['$govdeç'],
      'd' => ['${govde}t'],
      _ => const [],
    };
  }

  /// [metin] için arama adaylarını EN UZUNDAN EN KISAYA, tekrarsız döndürür.
  /// Çok kelimeli adlarda yalnız SON kelimenin eki atılır:
  /// "ülker çikolatalı gofretin" → "ülker çikolatalı gofretin", "...gofret", ...
  static List<String> adaylar(String metin) {
    final kelimeler = TrSayi.kelimele(metin);
    if (kelimeler.isEmpty) return const [];
    final onek = kelimeler.length > 1 ? '${kelimeler.sublist(0, kelimeler.length - 1).join(' ')} ' : '';
    final son = kelimeler.last;

    final sonuc = <String>[];
    void ekle(String s) {
      final c = '$onek$s'.trim();
      if (c.isNotEmpty && !sonuc.contains(c)) sonuc.add(c);
    }

    ekle(son);
    // En fazla 5 harflik ek at. Kök en az 3 harf; 2 harflik kök ("su", "et",
    // "un") YALNIZ bilinen bir hâl/iyelik ekiyle kabul edilir ("suyun",
    // "etten") — "xyzabc"→"xy" gibi uydurma kısaltmalar yanlış ürünle
    // eşleşmesin.
    for (var n = 1; n <= 5; n++) {
      final kokUzunluk = son.length - n;
      if (kokUzunluk < 2) break;
      final kok = son.substring(0, kokUzunluk);
      if (kokUzunluk == 2 && !_halEkleri.contains(son.substring(kokUzunluk))) continue;
      ekle(kok);
      for (final v in _yumusamaVaryantlari(kok)) {
        ekle(v);
      }
    }
    return sonuc;
  }

  /// Tek tek kelimelerle (VE mantığıyla) arama için anlamlı kelime kökleri:
  /// çok kelimeli ad sıralı eşleşmediğinde kullanılır.
  static List<List<String>> kelimeAdaylari(String metin) {
    final kelimeler = TrSayi.kelimele(metin).where((w) => w.length >= 3).toList();
    return [for (final w in kelimeler) adaylar(w)];
  }

  /// Aday adın [aday] ile bir kayıt adının TAM eşleşip eşleşmediği
  /// (Türkçe-duyarsız).
  static String anahtar(String s) => TrSayi.normalize(s)
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll('ı', 'i');
}
