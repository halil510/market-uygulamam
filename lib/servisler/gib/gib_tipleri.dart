// lib/servisler/gib/gib_tipleri.dart
//
// GİB e-Fatura/e-Arşiv modülü genelinde paylaşılan tipler — ayrı bir
// dosyada tutuluyor ki gib_servisi.dart (facade) ile gib_ayar_yoneticisi
// .dart / gib_ubl_olusturucu.dart (alt servisler) birbirini dairesel
// import etmek zorunda kalmasın; hepsi bu dosyayı import eder.
//
// (Madde 2 mimari denetimi — gib_servisi.dart'ın 1045 satırlık tek
// dosyadan tek sorumluluk prensibine göre bölünmesinin bir parçası.
// DAVRANIŞ DEĞİŞMEDİ, gib_servisi.dart bu dosyayı `export` ederek
// mevcut tüm çağıranların `import '.../gib_servisi.dart'` ile
// EFaturaTipi/GibGonderimSonucu'na erişmeye devam etmesini sağlıyor.)

enum EFaturaTipi { eFatura, eArsiv }

enum EFaturaDurum { taslak, gonderildi, onaylandi, reddedildi, iptal }

class GibGonderimSonucu {
  final bool basarili;
  final String? uuid;
  final String? yanit;
  final String? hata;
  const GibGonderimSonucu(
      {required this.basarili, this.uuid, this.yanit, this.hata});
}

/// Durum sorgusunda GİB/entegratör belgeyi hiç tanımıyor (HTTP 404) —
/// 'gonderiliyor'da kalmış bir belge GİB'e hiç ulaşmamış demektir; aynı
/// ETTN ile güvenle yeniden gönderilebilir.
class GibBelgeBulunamadi implements Exception {
  final String ettn;
  const GibBelgeBulunamadi(this.ettn);
  @override
  String toString() => 'GİB\'de bu ETTN ile kayıtlı belge bulunamadı ($ettn)';
}
