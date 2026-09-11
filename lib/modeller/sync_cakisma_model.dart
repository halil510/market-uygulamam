// lib/modeller/sync_cakisma_model.dart
//
// İki cihazın aynı kaydı bağımsız değiştirmesi sonucu oluşan senkron
// çakışması. Bkz. protokol §12 ve migrasyon v54.
import 'dart:convert';

class SyncCakismaModel {
  final int? id;
  final String tablo;
  final String? kayitGlobalId;
  final Map<String, dynamic> alanFarklari; // {alan: {yerel: x, gelen: y}}
  final Map<String, dynamic>? yerelKayit;
  final Map<String, dynamic>? gelenKayit;
  final DateTime tarih;
  final bool cozuldu;
  final String? cozumTipi; // 'yerel' | 'gelen' | 'manuel'
  final String? cozenKullanici;
  final DateTime? cozumTarihi;

  const SyncCakismaModel({
    this.id,
    required this.tablo,
    this.kayitGlobalId,
    required this.alanFarklari,
    this.yerelKayit,
    this.gelenKayit,
    required this.tarih,
    this.cozuldu = false,
    this.cozumTipi,
    this.cozenKullanici,
    this.cozumTarihi,
  });

  factory SyncCakismaModel.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic>? decode(dynamic v) {
      if (v == null) return null;
      try {
        return Map<String, dynamic>.from(jsonDecode(v as String) as Map);
      } catch (_) {
        return null;
      }
    }

    return SyncCakismaModel(
      id: m['id'] as int?,
      tablo: m['tablo'] as String? ?? '',
      kayitGlobalId: m['kayit_global_id'] as String?,
      alanFarklari: decode(m['alan_farklari']) ?? const {},
      yerelKayit: decode(m['yerel_kayit']),
      gelenKayit: decode(m['gelen_kayit']),
      tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
      cozuldu: (m['cozuldu'] as int?) == 1,
      cozumTipi: m['cozum_tipi'] as String?,
      cozenKullanici: m['cozen_kullanici'] as String?,
      cozumTarihi: m['cozum_tarihi'] != null
          ? DateTime.tryParse(m['cozum_tarihi'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'tablo': tablo,
    'kayit_global_id': kayitGlobalId,
    'alan_farklari': jsonEncode(alanFarklari),
    'yerel_kayit': yerelKayit != null ? jsonEncode(yerelKayit) : null,
    'gelen_kayit': gelenKayit != null ? jsonEncode(gelenKayit) : null,
    'tarih': tarih.toIso8601String(),
    'cozuldu': cozuldu ? 1 : 0,
    'cozum_tipi': cozumTipi,
    'cozen_kullanici': cozenKullanici,
    'cozum_tarihi': cozumTarihi?.toIso8601String(),
  };

  /// Kısa, ekranda gösterilecek özet: değişen alan adları.
  List<String> get degisenAlanlar => alanFarklari.keys.toList();
}
