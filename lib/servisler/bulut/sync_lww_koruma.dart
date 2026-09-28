// lib/servisler/bulut/sync_lww_koruma.dart
//
// Saf (ağsız) "bulut daha yeniyse ezme" mantığı — SupabaseSaglayici.
// topluUpsert()'ten ayrıldı ki izole test edilebilsin.
//
// Neden gerekli: kuyruktaki satır, kuyruğa girdiği andaki anlık görüntüdür.
// Cihaz uzun süre çevrimdışı kaldıysa ya da pull başka bir cihazın daha yeni
// sürümünü zaten uyguladıysa, bu eski görüntü gönderildiğinde buluttaki daha
// yeni kaydı sessizce geri alırdı.
class SyncLwwKoruma {
  /// Bulutta, gönderilecek satırdan KESİN olarak daha yeni sürümü olan
  /// satırların referanslarını döner. Eşit zaman damgası atlanmaz: eşit
  /// gönderim idempotenttir ve last_updated'ı güncellemeyen yazımlar
  /// (eski kod yolları) yine de buluta ulaşabilsin.
  static Set<Map<String, dynamic>> bulutuKesinDahaYeniOlanlar({
    required List<Map<String, dynamic>> kayitlar,
    required String uniqueAlan,
    required Map<String, DateTime> bulutZamanlari,
  }) {
    final atlanacak = Set<Map<String, dynamic>>.identity();
    for (final k in kayitlar) {
      final anahtar = k[uniqueAlan]?.toString();
      if (anahtar == null || anahtar.isEmpty) continue;
      final bulut = bulutZamanlari[anahtar];
      if (bulut == null) continue; // bulutta yok ya da zamanı bilinmiyor
      final yerel = DateTime.tryParse(k['last_updated']?.toString() ?? '');
      if (yerel == null) continue; // yerel zaman yok — göndermeye izin ver
      if (bulut.isAfter(yerel)) atlanacak.add(k);
    }
    return atlanacak;
  }

  /// PostgREST `in.(...)` filtresi için değer listesi; her değer çift
  /// tırnaklanır, `"` ve `\` kaçırılır (virgül/parantez içeren doğal
  /// anahtarlar filtreyi bozmasın).
  static String inListesi(Iterable<String> degerler) {
    final parcalar = degerler.map((d) {
      final kacis = d.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      return '"$kacis"';
    });
    return '(${parcalar.join(',')})';
  }

  /// Bulut yanıtındaki satırlardan {anahtar: last_updated} haritası çıkarır.
  static Map<String, DateTime> zamanHaritasi(
      List<dynamic> satirlar, String uniqueAlan) {
    final h = <String, DateTime>{};
    for (final s in satirlar) {
      if (s is! Map) continue;
      final anahtar = s[uniqueAlan]?.toString();
      final zaman = DateTime.tryParse(s['last_updated']?.toString() ?? '');
      if (anahtar != null && zaman != null) h[anahtar] = zaman;
    }
    return h;
  }
}
