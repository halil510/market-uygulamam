// lib/modeller/banka_hesap_model.dart
class BankaHesapModel {
  final int? id;
  final String? globalId;
  final int bankaId;
  final String hesapAdi;
  final String hesapNo;
  final String? iban;
  final String? subeAdi;
  final String? subeKodu;
  final String paraBirimi;
  final double bakiye;
  final double kullanilabilirBakiye;
  final String? hesapTuru; // Vadesiz, Vadeli, Kredi, DÃ¶viz
  final bool aktif;

  const BankaHesapModel({
    this.id,
    this.globalId,
    required this.bankaId,
    required this.hesapAdi,
    required this.hesapNo,
    this.iban,
    this.subeAdi,
    this.subeKodu,
    this.paraBirimi = 'TRY',
    this.bakiye = 0,
    this.kullanilabilirBakiye = 0,
    this.hesapTuru,
    this.aktif = true,
  });

  factory BankaHesapModel.fromMap(Map<String, dynamic> m) => BankaHesapModel(
    id: m['id'] as int?,
    globalId: m['global_id'] as String?,
    bankaId: m['banka_id'] as int? ?? 0,
    hesapAdi: m['hesap_adi'] as String? ?? '',
    hesapNo: m['hesap_no'] as String? ?? '',
    iban: m['iban'] as String?,
    subeAdi: m['sube_adi'] as String?,
    subeKodu: m['sube_kodu'] as String?,
    paraBirimi: m['para_birimi'] as String? ?? 'TRY',
    bakiye: (m['bakiye'] as num?)?.toDouble() ?? 0,
    kullanilabilirBakiye: (m['kullanilabilir_bakiye'] as num?)?.toDouble() ?? 0,
    hesapTuru: m['hesap_turu'] as String?,
    aktif: (m['aktif'] as int?) == 1,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    if (globalId != null) 'global_id': globalId,
    'banka_id': bankaId,
    'hesap_adi': hesapAdi,
    'hesap_no': hesapNo,
    if (iban != null) 'iban': iban,
    if (subeAdi != null) 'sube_adi': subeAdi,
    if (subeKodu != null) 'sube_kodu': subeKodu,
    'para_birimi': paraBirimi,
    'bakiye': bakiye,
    'kullanilabilir_bakiye': kullanilabilirBakiye,
    if (hesapTuru != null) 'hesap_turu': hesapTuru,
    'aktif': aktif ? 1 : 0,
    'last_updated': DateTime.now().toIso8601String(),
  };
}
