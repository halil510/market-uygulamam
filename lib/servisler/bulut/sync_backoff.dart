// lib/servisler/bulut/sync_backoff.dart
//
// MASTER ERP DEEP AUDIT — Madde 5 sertleştirmesi: BulutManager'ın
// exponential backoff hesaplaması, DB/network'ten TAMAMEN bağımsız SAF
// (yan etkisiz) fonksiyonlar olarak burada tutuluyor — hem BulutManager
// bunları kullanır hem de doğrudan (BulutManager singleton'ını hiç
// kurmadan) birim testi yazılabilir.
//
// Taban gecikme 10 saniye, her başarısız denemede İKİYE KATLANIR (10,
// 20, 40, 80, ... saniye), en fazla 30 dakikada bir denenecek şekilde
// TAVANLANIR — sürekli başarısız olan bir kayıt sunucuyu/ağı gereksizce
// bombalamaz, ama asla tamamen durmaz (sınırsız yeniden deneme — veri
// kaybı yok).
const int backoffTabanSaniye = 10;
const int backoffMaxSaniye = 1800; // 30 dakika

/// [denemeSayisi] başarısız denemeden sonra bir sonraki denemeden önce
/// beklenmesi gereken süre (saniye). İlk deneme (0) için hiç bekleme yok.
int backoffSuresiSaniyeHesapla(int denemeSayisi) {
  if (denemeSayisi <= 0) return 0;
  final us = backoffTabanSaniye * (1 << denemeSayisi.clamp(0, 12));
  return us > backoffMaxSaniye ? backoffMaxSaniye : us;
}

/// Bir `sync_queue` satırının (deneme_sayisi/son_deneme sütunlarına göre)
/// şu an (backoff penceresi geçmiş olduğu için) yeniden denenmeye UYGUN
/// olup olmadığını belirler. İlk deneme (deneme_sayisi=0) veya
/// son_deneme kaydı yoksa/ayrıştırılamıyorsa her zaman uygundur (güvenli
/// taraf: belirsizlikte DENE, atlama).
///
/// [simdi] test edilebilirlik için verilebilir; verilmezse [DateTime.now]
/// kullanılır.
bool syncSatiriSimdiDenenebilirMi(
  Map<String, dynamic> satir, {
  DateTime? simdi,
}) {
  final denemeSayisi = (satir['deneme_sayisi'] as int?) ?? 0;
  if (denemeSayisi <= 0) return true;
  final sonDenemeStr = satir['son_deneme'] as String?;
  if (sonDenemeStr == null) return true;
  final sonDeneme = DateTime.tryParse(sonDenemeStr);
  if (sonDeneme == null) return true;
  final simdiKullan = simdi ?? DateTime.now();
  final gecenSaniye = simdiKullan.difference(sonDeneme).inSeconds;
  return gecenSaniye >= backoffSuresiSaniyeHesapla(denemeSayisi);
}
