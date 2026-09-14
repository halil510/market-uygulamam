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

  /// farklariBul() ile bulunan bir "fark"ın GERÇEK bir çakışma mı,
  /// yoksa bu cihazın hiç dokunmadığı, başka bir cihazın DAHA ÖNCE
  /// yaptığı normal (tek yönlü) bir senkron güncellemesinin bu cihaza
  /// İLK KEZ ulaşması mı olduğunu ayırt eder.
  ///
  /// ÖNCEDEN bu ayrım hiç yapılmıyordu — yerelde duran ESKİ bir sürüm
  /// ile buluttan gelen YENİ sürüm arasındaki her fark, kullanıcıya
  /// "iki cihaz aynı kaydı bağımsız değiştirdi" gibi gösteriliyordu.
  /// Oysa bu cihaz o kaydı hiç düzenlememiş olabilir — sadece henüz bu
  /// güncellemeyi görmemişti. Gerçek bir çakışma için, yerel kaydın
  /// bu cihazda EN SON BAŞARIYLA BULUTA GÖNDERİLDİĞİ andan SONRA yine
  /// bu cihazda değişmiş olması gerekir (yani hâlâ buluta gitmemiş,
  /// kaybolma riski taşıyan bir yerel değişiklik olması gerekir).
  ///
  /// [sonBasariliGonderim] bilinmiyorsa (bu tablo bu cihazdan hiç
  /// gönderilmediyse) emin olunamaz — güvenli/muhafazakâr tarafta
  /// kalınır ve true (gerçek çakışma sayılır) döner.
  static bool gercekCakismaMi({
    required DateTime? yerelSonGuncelleme,
    required DateTime? sonBasariliGonderim,
  }) {
    if (sonBasariliGonderim == null || yerelSonGuncelleme == null) return true;
    return yerelSonGuncelleme.isAfter(sonBasariliGonderim);
  }
}
