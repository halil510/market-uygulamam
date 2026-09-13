// lib/servisler/stok_devir_analizi_servisi.dart
//
// FAZ 8 — Stok Devir Analizi (erp_roadmap madde 16). Seçilen dönemde
// hangi ürünlerin stoğu hızlı/yavaş döndüğünü, hangilerinin HİÇ
// satılmadığını (hareketsiz/ölü stok) gösteren salt-okunur rapor.
//
// NOT: Gerçek "ortalama stok" için zaman-serisi stok geçmişi gerekirdi
// (bu şemada yok) — bu yüzden bu analiz, çoğu basit ERP raporunda olduğu
// gibi MEVCUT stok miktarını proxy olarak kullanıyor. Bu bilinçli bir
// basitleştirme; ekranda açıkça belirtiliyor.
import '../veri/database/veritabani.dart';

enum DevirSinifi { hareketsiz, yavas, normal, hizli }

extension DevirSinifiUzanti on DevirSinifi {
  String get etiket => switch (this) {
        DevirSinifi.hareketsiz => 'Hareketsiz',
        DevirSinifi.yavas => 'Yavaş',
        DevirSinifi.normal => 'Normal',
        DevirSinifi.hizli => 'Hızlı',
      };
}

class DevirGirdi {
  final int urunId;
  final String urunAdi;
  final double satilanMiktar;
  final double mevcutStok;
  const DevirGirdi({
    required this.urunId,
    required this.urunAdi,
    required this.satilanMiktar,
    required this.mevcutStok,
  });
}

class DevirSatiri {
  final int urunId;
  final String urunAdi;
  final double satilanMiktar;
  final double mevcutStok;
  /// Satılan miktar / mevcut stok. Stok 0 ise null (sonsuz — "stok tükendi").
  final double? devirHizi;
  final DevirSinifi sinif;
  const DevirSatiri({
    required this.urunId,
    required this.urunAdi,
    required this.satilanMiktar,
    required this.mevcutStok,
    required this.devirHizi,
    required this.sinif,
  });
}

/// Saf fonksiyon: tek bir ürünün devir hızını ve sınıfını hesaplar.
/// Eşikler (madde başına): satış yok + stok var → Hareketsiz (en kritik
/// bulgu — ölü stok adayı). Stok tükendiyse ama satış varsa → Hızlı.
/// Aksi halde devir hızı (satılan/stok) >= 3 → Hızlı, >= 0.5 → Normal,
/// altı → Yavaş.
DevirSatiri stokDevirSatiriHesapla(DevirGirdi g) {
  if (g.satilanMiktar <= 0 && g.mevcutStok > 0) {
    return DevirSatiri(
      urunId: g.urunId,
      urunAdi: g.urunAdi,
      satilanMiktar: g.satilanMiktar,
      mevcutStok: g.mevcutStok,
      devirHizi: 0,
      sinif: DevirSinifi.hareketsiz,
    );
  }
  if (g.mevcutStok <= 0) {
    return DevirSatiri(
      urunId: g.urunId,
      urunAdi: g.urunAdi,
      satilanMiktar: g.satilanMiktar,
      mevcutStok: g.mevcutStok,
      devirHizi: null,
      sinif: DevirSinifi.hizli,
    );
  }
  final devir = g.satilanMiktar / g.mevcutStok;
  final sinif = devir >= 3
      ? DevirSinifi.hizli
      : devir >= 0.5
          ? DevirSinifi.normal
          : DevirSinifi.yavas;
  return DevirSatiri(
    urunId: g.urunId,
    urunAdi: g.urunAdi,
    satilanMiktar: g.satilanMiktar,
    mevcutStok: g.mevcutStok,
    devirHizi: devir,
    sinif: sinif,
  );
}

List<DevirSatiri> stokDevirAnaliziHesapla(List<DevirGirdi> girdiler) =>
    girdiler.map(stokDevirSatiriHesapla).toList()
      ..sort((a, b) {
        // Hareketsizler her zaman en üstte (en actionable bulgu).
        if (a.sinif == DevirSinifi.hareketsiz && b.sinif != DevirSinifi.hareketsiz) return -1;
        if (b.sinif == DevirSinifi.hareketsiz && a.sinif != DevirSinifi.hareketsiz) return 1;
        return (a.devirHizi ?? 999999).compareTo(b.devirHizi ?? 999999);
      });

class StokDevirAnaliziServisi {
  /// [gunSayisi]: analiz penceresi (varsayılan son 90 gün). Sadece
  /// stokta ürünü olan (stok > 0) aktif ürünler değerlendirilir — stoğu
  /// zaten 0 olan pasif/tükenmiş ürünler bu raporun kapsamı dışında
  /// (onlar "Kritik Stok" / "Satın Alma Önerileri" ekranının işi).
  Future<List<DevirSatiri>> analizGetir({int gunSayisi = 90}) async {
    final db = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT u.id AS urun_id, u.urun_adi AS urun_adi, u.stok AS stok,
             COALESCE(SUM(sk.miktar), 0) AS satilan
      FROM urunler u
      LEFT JOIN satis_kalem sk ON sk.urun_id = u.id
      LEFT JOIN satislar s ON s.id = sk.satis_id
        AND s.iptal = 0 AND s.is_deleted = 0
        AND DATE(s.tarih) >= DATE('now', 'localtime', ?)
      WHERE u.is_deleted = 0 AND u.aktif = 1 AND u.stok > 0
      GROUP BY u.id
    ''', ['-$gunSayisi days']);

    final girdiler = rows
        .map((r) => DevirGirdi(
              urunId: r['urun_id'] as int,
              urunAdi: r['urun_adi'] as String? ?? '—',
              satilanMiktar: (r['satilan'] as num?)?.toDouble() ?? 0,
              mevcutStok: (r['stok'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
    return stokDevirAnaliziHesapla(girdiler);
  }
}
