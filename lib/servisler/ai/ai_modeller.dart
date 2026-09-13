// lib/servisler/ai/ai_modeller.dart
enum AiIntent {
  // Satış
  gunlukSatis, haftalikSatis, aylikSatis, yillikSatis,
  netKar, odemeYontemi, ciroRaporu,
  // Stok
  kritikStok, stokSorgula, stokDeger, stokHareket,
  // Ürün
  enCokSatan, enKarli, urunAra, urunListele, kategoriAnaliz,
  // Cari
  cariListele, cariBorc, cariHareket, tahsilat, kasaDurumu,
  // Raporlar
  zRaporu, urunZRaporu, aylikRapor, grupRaporu, markaRaporu, alan1Raporu,
  // Diğer
  tahmin, oneri, sohbet, bilinmiyor,
  grupDetay, alan1Detay, stokGenelDurum,
  // FAZ 10 — AI analiz derinliği (erp_roadmap madde 24)
  karDegisimAciklama, anormalTespit, stokTukenmeTahmini,
}

class AiSoru {
  final String metin;
  final AiIntent intent;
  final Map<String, dynamic> params;
  const AiSoru({required this.metin, required this.intent, this.params = const {}});
}
