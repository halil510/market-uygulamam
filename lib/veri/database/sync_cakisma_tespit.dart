// lib/veri/database/sync_cakisma_tespit.dart
//
// Saf (DB'siz) fark tespit mantığı — Veritabani.supaKayitlariGuncelle()'dan
// ayrıldı ki DB/singleton'a bağımlı olmadan izole test edilebilsin.
class SyncCakismaTespit {
  /// Karşılaştırmadan hariç tutulan, iş verisi olmayan sütunlar.
  static const Set<String> metaAlanlari = {'id', 'global_id', 'last_updated'};

  /// Yerel ve gelen (buluttan) satır arasındaki, metadata dışı gerçek
  /// alan farklarını döner: {alan: {'yerel': x, 'gelen': y}}.
  /// Boş map dönerse gerçek bir çakışma yoktur (ör. sadece last_updated
  /// bümlenmiş, veri aynı).
  static Map<String, dynamic> farklariBul(
    Map<String, dynamic> yerelSatir,
    Map<String, dynamic> gelenSatir,
  ) {
    final farklar = <String, dynamic>{};
    for (final alan in gelenSatir.keys) {
      if (metaAlanlari.contains(alan)) continue;
      final yerelDeger = yerelSatir[alan];
      final gelenDeger = gelenSatir[alan];
      if (!_esitMi(yerelDeger, gelenDeger)) {
        farklar[alan] = {'yerel': yerelDeger, 'gelen': gelenDeger};
      }
    }
    return farklar;
  }

  /// [a] ve [b]'yi tip-toleranslı karşılaştırır: her ikisi de sayıysa
  /// (int/double karışık olsa bile — SQLite ve JSON bunu sık karıştırır)
  /// sayısal olarak, aksi halde metin olarak karşılaştırır.
  static bool _esitMi(dynamic a, dynamic b) {
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    return (a?.toString() ?? '') == (b?.toString() ?? '');
  }
}
