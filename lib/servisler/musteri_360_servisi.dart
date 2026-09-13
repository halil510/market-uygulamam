// lib/servisler/musteri_360_servisi.dart
//
// FAZ 7 — Müşteri 360 / CRM (erp_roadmap madde 19-20): mevcut cari kartını
// CRM seviyesine çıkaran SALT OKUNUR analiz katmanı. Hiçbir tabloya yazma
// yapmaz, hiçbir finansal/iş kuralını değiştirmez — sadece satislar/
// satis_kalem/cari tablolarından türetilmiş özet istatistik + segment
// rozeti üretir (görüntüleme amaçlı, karar motoru değil).
//
// ÖNEMLİ: "recency" (son satıştan bu yana geçen gün) hesabı BİLEREK SQL
// datetime('now', ...) ile DEĞİL, Dart tarafında DateTime.now() ile
// yapılıyor — bu projede daha önce 6 ayrı yerde bulunup düzeltilen
// UTC(SQLite) vs local(DateTime.now().toIso8601String()) tarih hatasına
// yeni bir örnek eklememek için.
import '../veri/database/veritabani.dart';

enum MusteriSegmenti { yeni, riskli, kaybedilmekUzere, vip, sadik, standart }

extension MusteriSegmentiUzanti on MusteriSegmenti {
  String get etiket => switch (this) {
        MusteriSegmenti.yeni => 'Yeni',
        MusteriSegmenti.riskli => 'Riskli',
        MusteriSegmenti.kaybedilmekUzere => 'Kaybedilmek Üzere',
        MusteriSegmenti.vip => 'VIP',
        MusteriSegmenti.sadik => 'Sadık',
        MusteriSegmenti.standart => 'Standart',
      };
}

class UrunSikligi {
  final String urunAdi;
  final double miktar;
  final double tutar;
  const UrunSikligi(
      {required this.urunAdi, required this.miktar, required this.tutar});
}

class MusteriIstatistik {
  final int islemSayisi;
  final double toplamCiro;
  final double ortalamaSepet;
  final DateTime? sonSatisTarihi;
  final DateTime? ilkSatisTarihi;
  /// Ardışık satışlar arası ortalama gün — tek/hiç satış varsa null.
  final double? ortalamaGunAraligi;
  final List<UrunSikligi> enCokAlinanUrunler;

  const MusteriIstatistik({
    required this.islemSayisi,
    required this.toplamCiro,
    required this.ortalamaSepet,
    required this.sonSatisTarihi,
    required this.ilkSatisTarihi,
    required this.ortalamaGunAraligi,
    required this.enCokAlinanUrunler,
  });

  static const bos = MusteriIstatistik(
    islemSayisi: 0,
    toplamCiro: 0,
    ortalamaSepet: 0,
    sonSatisTarihi: null,
    ilkSatisTarihi: null,
    ortalamaGunAraligi: null,
    enCokAlinanUrunler: [],
  );

  int? sonSatistanGecenGun(DateTime simdi) =>
      sonSatisTarihi == null ? null : simdi.difference(sonSatisTarihi!).inDays;
}

/// Basit RFM (Recency/Frequency) + risk kullanım oranı tabanlı segment
/// sınıflandırması. Saf fonksiyon (DB'ye bağımlı değil) — kolayca test
/// edilebilir ve eşikler tek yerden değiştirilebilir.
///
/// Öncelik sırası (madde 21'deki "Risk Merkezi"yle çakışmayı önlemek
/// için risk EN ÖNCE kontrol edilir — riskli bir cari aynı zamanda sık
/// alışveriş yapıyor olsa bile önce riskli olarak işaretlenir):
/// 1. Hiç satışı yoksa → Yeni
/// 2. Kredi limitinin ≥%90'ı kullanılmışsa → Riskli
/// 3. En az 3 satışı olup son 90 günde hiç alışveriş yapmamışsa → Kaybedilmek Üzere
/// 4. Son 180 günde ≥6 işlem → VIP
/// 5. Son 180 günde ≥2 işlem → Sadık
/// 6. Aksi halde → Standart
MusteriSegmenti musteriSegmentiHesapla({
  required int islemSayisi,
  required int? sonSatistanGecenGun,
  required double riskKullanimOrani,
  required int son180GunIslemSayisi,
}) {
  if (islemSayisi == 0) return MusteriSegmenti.yeni;
  if (riskKullanimOrani >= 0.9) return MusteriSegmenti.riskli;
  if (islemSayisi >= 3 &&
      sonSatistanGecenGun != null &&
      sonSatistanGecenGun > 90) {
    return MusteriSegmenti.kaybedilmekUzere;
  }
  if (son180GunIslemSayisi >= 6) return MusteriSegmenti.vip;
  if (son180GunIslemSayisi >= 2) return MusteriSegmenti.sadik;
  return MusteriSegmenti.standart;
}

class Musteri360Servisi {
  Future<MusteriIstatistik> istatistikGetir(int cariId) async {
    final db = await Veritabani().db;
    final satirlar = await db.rawQuery('''
      SELECT tarih, genel_toplam FROM satislar
      WHERE cari_id = ? AND iptal = 0 AND is_deleted = 0
      ORDER BY tarih ASC
    ''', [cariId]);

    if (satirlar.isEmpty) return MusteriIstatistik.bos;

    final tarihler = satirlar
        .map((s) => DateTime.tryParse(s['tarih'] as String? ?? ''))
        .whereType<DateTime>()
        .toList();
    final toplam = satirlar.fold<double>(
        0, (t, s) => t + ((s['genel_toplam'] as num?)?.toDouble() ?? 0));

    double? ortGunAralik;
    if (tarihler.length >= 2) {
      var toplamGun = 0;
      for (var i = 1; i < tarihler.length; i++) {
        toplamGun += tarihler[i].difference(tarihler[i - 1]).inDays;
      }
      ortGunAralik = toplamGun / (tarihler.length - 1);
    }

    final urunSatirlari = await db.rawQuery('''
      SELECT sk.urun_adi AS urun_adi, SUM(sk.miktar) AS miktar, SUM(sk.toplam_tutar) AS tutar
      FROM satis_kalem sk
      JOIN satislar s ON s.id = sk.satis_id
      WHERE s.cari_id = ? AND s.iptal = 0 AND s.is_deleted = 0
      GROUP BY sk.urun_adi
      ORDER BY tutar DESC
      LIMIT 5
    ''', [cariId]);

    return MusteriIstatistik(
      islemSayisi: satirlar.length,
      toplamCiro: toplam,
      ortalamaSepet: toplam / satirlar.length,
      sonSatisTarihi: tarihler.isEmpty ? null : tarihler.last,
      ilkSatisTarihi: tarihler.isEmpty ? null : tarihler.first,
      ortalamaGunAraligi: ortGunAralik,
      enCokAlinanUrunler: urunSatirlari
          .map((u) => UrunSikligi(
                urunAdi: u['urun_adi'] as String? ?? '—',
                miktar: (u['miktar'] as num?)?.toDouble() ?? 0,
                tutar: (u['tutar'] as num?)?.toDouble() ?? 0,
              ))
          .toList(),
    );
  }

  Future<MusteriSegmenti> segmentGetir(
    int cariId, {
    required MusteriIstatistik istatistik,
    required double bakiye,
    required double limitTutari,
  }) async {
    final simdi = DateTime.now();
    final son180 = istatistik.sonSatisTarihi == null
        ? 0
        : await _son180GunIslemSayisi(cariId, simdi);
    final riskOrani = limitTutari > 0 ? (bakiye / limitTutari) : 0.0;
    return musteriSegmentiHesapla(
      islemSayisi: istatistik.islemSayisi,
      sonSatistanGecenGun: istatistik.sonSatistanGecenGun(simdi),
      riskKullanimOrani: riskOrani,
      son180GunIslemSayisi: son180,
    );
  }

  Future<int> _son180GunIslemSayisi(int cariId, DateTime simdi) async {
    final db = await Veritabani().db;
    final satirlar = await db.rawQuery('''
      SELECT tarih FROM satislar
      WHERE cari_id = ? AND iptal = 0 AND is_deleted = 0
    ''', [cariId]);
    var adet = 0;
    for (final s in satirlar) {
      final t = DateTime.tryParse(s['tarih'] as String? ?? '');
      if (t != null && simdi.difference(t).inDays <= 180) adet++;
    }
    return adet;
  }
}
