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

/// GİB durum sorgusunun sonucu — [durum] normalleştirilmiş durum,
/// [aciklama] entegratörün verdiği açıklama (ör. red sebebi), yoksa null.
class GibDurumSonucu {
  final String? durum;
  final String? aciklama;
  const GibDurumSonucu(this.durum, {this.aciklama});
}

/// Entegratör yanıtından insan-okunur açıklamayı (red sebebi vb.) çıkarır.
/// Alan adı entegratöre göre değişir; yaygın adlar sırayla denenir,
/// iç içe `error: {message}` de desteklenir. Durum kodunun kendisini
/// (ör. "REJECTED") açıklama olarak döndürmez.
String? gibAciklamaCikar(Map<String, dynamic>? govde) {
  if (govde == null) return null;
  const anahtarlar = [
    'reason', 'rejection_reason', 'rejectReason', 'red_sebebi',
    'message', 'description', 'status_description', 'statusDescription',
    'error_message', 'errorMessage', 'detail', 'aciklama', 'hata',
  ];
  final durum = govde['status']?.toString().trim().toLowerCase();
  for (final a in anahtarlar) {
    final d = govde[a];
    if (d is String && d.trim().isNotEmpty && d.trim().toLowerCase() != durum) {
      return d.trim();
    }
  }
  final hata = govde['error'];
  if (hata is String && hata.trim().isNotEmpty) return hata.trim();
  if (hata is Map) return gibAciklamaCikar(Map<String, dynamic>.from(hata));
  return null;
}
