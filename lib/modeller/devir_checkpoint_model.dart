// lib/modeller/devir_checkpoint_model.dart
// Yıl Sonu Devir motoru — 10 fazlı, resumable state-machine (Madde 17/
// 27/28). Bu model 'devir_checkpoint' satırını taşır; asıl faz mantığı
// (DevirYoneticiServisi) İLERİKİ bir fazda eklenecek — FAZ 1 sadece
// tabloyu ve okuma/yazma için tip-güvenli bir model sağlar.

/// Madde 27'nin istediği state machine — sırasıyla ilerler, FAILED'dan
/// sadece ROLLBACK_REQUIRED'a, oradan da yeni bir devir denemesine geçilir.
class DevirDurumu {
  static const init = 'INIT';
  static const checking = 'CHECKING';
  static const backup = 'BACKUP';
  static const archiving = 'ARCHIVING';
  static const snapshotStok = 'SNAPSHOT_STOK';
  static const snapshotCari = 'SNAPSHOT_CARI';
  static const snapshotKasa = 'SNAPSHOT_KASA';
  static const snapshotBanka = 'SNAPSHOT_BANKA';
  static const opening = 'OPENING';
  static const verifying = 'VERIFYING';
  static const completed = 'COMPLETED';
  static const failed = 'FAILED';
  static const rollbackRequired = 'ROLLBACK_REQUIRED';
}

/// Madde 17'nin 10 fazı — devir_checkpoint.mevcut_faz bu sıraya göre ilerler.
class DevirFaz {
  static const kontrol = 1;
  static const yedek = 2;
  static const arsivHazirlama = 3;
  static const stokSnapshot = 4;
  static const cariSnapshot = 5;
  static const kasaSnapshot = 6;
  static const bankaSnapshot = 7;
  static const acilisKayitlari = 8;
  static const donemKapanisi = 9;
  static const dogrulama = 10;
}

class DevirCheckpointModel {
  final int? id;
  final String? globalId;
  final String devirId;
  final int kaynakDonemId;
  final int hedefDonemId;
  /// 0 = şubeye bağlı olmayan (şirket geneli — cari/banka) faz kaydı.
  /// SQLite UNIQUE kısıtı NULL'ı ayırt edemediğinden sentinel olarak
  /// 0 kullanılır (bkz. donem_semasi.dart baş yorumu).
  final int subeId;
  final String durum;
  final int mevcutFaz;
  final String? fazIlerlemeJson;
  final DateTime baslangicZamani;
  final DateTime? sonGuncelleme;
  final DateTime? tamamlanmaZamani;
  final String? hataMesaji;

  const DevirCheckpointModel({
    this.id,
    this.globalId,
    required this.devirId,
    required this.kaynakDonemId,
    required this.hedefDonemId,
    this.subeId = 0,
    this.durum = DevirDurumu.init,
    this.mevcutFaz = 0,
    this.fazIlerlemeJson,
    required this.baslangicZamani,
    this.sonGuncelleme,
    this.tamamlanmaZamani,
    this.hataMesaji,
  });

  bool get tamamlandiMi => durum == DevirDurumu.completed;
  bool get basarisizMi => durum == DevirDurumu.failed || durum == DevirDurumu.rollbackRequired;
  bool get devamEdebilirMi => !tamamlandiMi && !basarisizMi;

  factory DevirCheckpointModel.fromMap(Map<String, dynamic> m) => DevirCheckpointModel(
        id: m['id'] as int?,
        globalId: m['global_id'] as String?,
        devirId: m['devir_id'] as String? ?? '',
        kaynakDonemId: (m['kaynak_donem_id'] as num?)?.toInt() ?? 0,
        hedefDonemId: (m['hedef_donem_id'] as num?)?.toInt() ?? 0,
        subeId: (m['sube_id'] as num?)?.toInt() ?? 0,
        durum: m['durum'] as String? ?? DevirDurumu.init,
        mevcutFaz: (m['mevcut_faz'] as num?)?.toInt() ?? 0,
        fazIlerlemeJson: m['faz_ilerleme_json'] as String?,
        baslangicZamani:
            DateTime.tryParse(m['baslangic_zamani']?.toString() ?? '') ?? DateTime.now(),
        sonGuncelleme: m['son_guncelleme'] != null
            ? DateTime.tryParse(m['son_guncelleme'].toString())
            : null,
        tamamlanmaZamani: m['tamamlanma_zamani'] != null
            ? DateTime.tryParse(m['tamamlanma_zamani'].toString())
            : null,
        hataMesaji: m['hata_mesaji'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (globalId != null) 'global_id': globalId,
        'devir_id': devirId,
        'kaynak_donem_id': kaynakDonemId,
        'hedef_donem_id': hedefDonemId,
        'sube_id': subeId,
        'durum': durum,
        'mevcut_faz': mevcutFaz,
        if (fazIlerlemeJson != null) 'faz_ilerleme_json': fazIlerlemeJson,
        'baslangic_zamani': baslangicZamani.toIso8601String(),
        if (sonGuncelleme != null) 'son_guncelleme': sonGuncelleme!.toIso8601String(),
        if (tamamlanmaZamani != null) 'tamamlanma_zamani': tamamlanmaZamani!.toIso8601String(),
        if (hataMesaji != null) 'hata_mesaji': hataMesaji,
      };

  DevirCheckpointModel copyWith({
    String? durum,
    int? mevcutFaz,
    String? fazIlerlemeJson,
    DateTime? sonGuncelleme,
    DateTime? tamamlanmaZamani,
    String? hataMesaji,
  }) =>
      DevirCheckpointModel(
        id: id,
        globalId: globalId,
        devirId: devirId,
        kaynakDonemId: kaynakDonemId,
        hedefDonemId: hedefDonemId,
        subeId: subeId,
        durum: durum ?? this.durum,
        mevcutFaz: mevcutFaz ?? this.mevcutFaz,
        fazIlerlemeJson: fazIlerlemeJson ?? this.fazIlerlemeJson,
        baslangicZamani: baslangicZamani,
        sonGuncelleme: sonGuncelleme ?? this.sonGuncelleme,
        tamamlanmaZamani: tamamlanmaZamani ?? this.tamamlanmaZamani,
        hataMesaji: hataMesaji ?? this.hataMesaji,
      );
}
