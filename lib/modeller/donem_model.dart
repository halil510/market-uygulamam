// lib/modeller/donem_model.dart
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — FAZ 1 (2026-09-16,
// kullanıcı onaylı mimari plan raporu).

/// 'donemler' tablosunun karşılığı — yıllık dönem kaydı (genel/özet
/// durum). Şube bazlı ilerleme için bkz. DonemSubeDurumuModel.
class DonemDurumu {
  static const acik = 'OPEN';
  static const kapaniyor = 'CLOSING';
  static const kapali = 'CLOSED';
  static const arsivlendi = 'ARCHIVED';
}

/// Alt-durum alanları (backup_durumu, arsiv_durumu, devir_durumu) için
/// ortak, basit bir sözlük — 'bekliyor' | 'devam_ediyor' | 'tamamlandi' | 'hatali'.
class AltDurum {
  static const bekliyor = 'bekliyor';
  static const devamEdiyor = 'devam_ediyor';
  static const tamamlandi = 'tamamlandi';
  static const hatali = 'hatali';
}

class DonemModel {
  final int? id;
  final String? globalId;
  final int donemYili;
  final DateTime baslangicTarihi;
  final DateTime bitisTarihi;
  final String durum;
  final DateTime? kapanisTarihi;
  final int? kapanisiYapanKullaniciId;
  final String? kapanisCihazi;
  final String backupDurumu;
  final String arsivDurumu;
  final String devirDurumu;

  const DonemModel({
    this.id,
    this.globalId,
    required this.donemYili,
    required this.baslangicTarihi,
    required this.bitisTarihi,
    this.durum = DonemDurumu.acik,
    this.kapanisTarihi,
    this.kapanisiYapanKullaniciId,
    this.kapanisCihazi,
    this.backupDurumu = AltDurum.bekliyor,
    this.arsivDurumu = AltDurum.bekliyor,
    this.devirDurumu = AltDurum.bekliyor,
  });

  bool get acikMi => durum == DonemDurumu.acik;
  bool get kapaliMi => durum == DonemDurumu.kapali || durum == DonemDurumu.arsivlendi;

  factory DonemModel.fromMap(Map<String, dynamic> m) => DonemModel(
        id: m['id'] as int?,
        globalId: m['global_id'] as String?,
        donemYili: (m['donem_yili'] as num?)?.toInt() ?? 0,
        baslangicTarihi:
            DateTime.tryParse(m['baslangic_tarihi']?.toString() ?? '') ?? DateTime.now(),
        bitisTarihi: DateTime.tryParse(m['bitis_tarihi']?.toString() ?? '') ?? DateTime.now(),
        durum: m['durum'] as String? ?? DonemDurumu.acik,
        kapanisTarihi: m['kapanis_tarihi'] != null
            ? DateTime.tryParse(m['kapanis_tarihi'].toString())
            : null,
        kapanisiYapanKullaniciId: m['kapanisi_yapan_kullanici_id'] as int?,
        kapanisCihazi: m['kapanis_cihazi'] as String?,
        backupDurumu: m['backup_durumu'] as String? ?? AltDurum.bekliyor,
        arsivDurumu: m['arsiv_durumu'] as String? ?? AltDurum.bekliyor,
        devirDurumu: m['devir_durumu'] as String? ?? AltDurum.bekliyor,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (globalId != null) 'global_id': globalId,
        'donem_yili': donemYili,
        'baslangic_tarihi': baslangicTarihi.toIso8601String(),
        'bitis_tarihi': bitisTarihi.toIso8601String(),
        'durum': durum,
        if (kapanisTarihi != null) 'kapanis_tarihi': kapanisTarihi!.toIso8601String(),
        if (kapanisiYapanKullaniciId != null)
          'kapanisi_yapan_kullanici_id': kapanisiYapanKullaniciId,
        if (kapanisCihazi != null) 'kapanis_cihazi': kapanisCihazi,
        'backup_durumu': backupDurumu,
        'arsiv_durumu': arsivDurumu,
        'devir_durumu': devirDurumu,
      };

  DonemModel copyWith({
    String? durum,
    DateTime? kapanisTarihi,
    int? kapanisiYapanKullaniciId,
    String? kapanisCihazi,
    String? backupDurumu,
    String? arsivDurumu,
    String? devirDurumu,
  }) =>
      DonemModel(
        id: id,
        globalId: globalId,
        donemYili: donemYili,
        baslangicTarihi: baslangicTarihi,
        bitisTarihi: bitisTarihi,
        durum: durum ?? this.durum,
        kapanisTarihi: kapanisTarihi ?? this.kapanisTarihi,
        kapanisiYapanKullaniciId: kapanisiYapanKullaniciId ?? this.kapanisiYapanKullaniciId,
        kapanisCihazi: kapanisCihazi ?? this.kapanisCihazi,
        backupDurumu: backupDurumu ?? this.backupDurumu,
        arsivDurumu: arsivDurumu ?? this.arsivDurumu,
        devirDurumu: devirDurumu ?? this.devirDurumu,
      );
}

/// 'donem_sube_durumlari' tablosunun karşılığı — bir dönemin BİR ŞUBE
/// için ilerleme durumu (Madde 29: genel şirket dönemi ancak tüm
/// şubeler tamamlandığında kapanabilir).
class DonemSubeDurumuModel {
  final int? id;
  final String? globalId;
  final int donemId;
  final int subeId;
  final String durum;
  final DateTime? kapanisTarihi;
  final int? kapanisiYapanKullaniciId;
  final String? kapanisCihazi;
  final String backupDurumu;
  final String arsivDurumu;
  final String devirDurumu;

  const DonemSubeDurumuModel({
    this.id,
    this.globalId,
    required this.donemId,
    required this.subeId,
    this.durum = DonemDurumu.acik,
    this.kapanisTarihi,
    this.kapanisiYapanKullaniciId,
    this.kapanisCihazi,
    this.backupDurumu = AltDurum.bekliyor,
    this.arsivDurumu = AltDurum.bekliyor,
    this.devirDurumu = AltDurum.bekliyor,
  });

  factory DonemSubeDurumuModel.fromMap(Map<String, dynamic> m) => DonemSubeDurumuModel(
        id: m['id'] as int?,
        globalId: m['global_id'] as String?,
        donemId: (m['donem_id'] as num?)?.toInt() ?? 0,
        subeId: (m['sube_id'] as num?)?.toInt() ?? 0,
        durum: m['durum'] as String? ?? DonemDurumu.acik,
        kapanisTarihi: m['kapanis_tarihi'] != null
            ? DateTime.tryParse(m['kapanis_tarihi'].toString())
            : null,
        kapanisiYapanKullaniciId: m['kapanisi_yapan_kullanici_id'] as int?,
        kapanisCihazi: m['kapanis_cihazi'] as String?,
        backupDurumu: m['backup_durumu'] as String? ?? AltDurum.bekliyor,
        arsivDurumu: m['arsiv_durumu'] as String? ?? AltDurum.bekliyor,
        devirDurumu: m['devir_durumu'] as String? ?? AltDurum.bekliyor,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (globalId != null) 'global_id': globalId,
        'donem_id': donemId,
        'sube_id': subeId,
        'durum': durum,
        if (kapanisTarihi != null) 'kapanis_tarihi': kapanisTarihi!.toIso8601String(),
        if (kapanisiYapanKullaniciId != null)
          'kapanisi_yapan_kullanici_id': kapanisiYapanKullaniciId,
        if (kapanisCihazi != null) 'kapanis_cihazi': kapanisCihazi,
        'backup_durumu': backupDurumu,
        'arsiv_durumu': arsivDurumu,
        'devir_durumu': devirDurumu,
      };
}
