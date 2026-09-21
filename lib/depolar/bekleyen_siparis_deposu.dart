// lib/depolar/bekleyen_siparis_deposu.dart
//
// Kullanıcı isteği: "Bayilerden Sipariş Alma" — sipariş önce
// "Bekleyen Sipariş" olarak kaydedilir, ayrı bir onay ekranından
// satışa (ve isteğe bağlı faturaya/irsaliyeye) dönüştürülür.
//
// Onaylama adımı, ToptanSatisEkrani._satisiTamamla() ile AYNI,
// kanıtlanmış satış-oluşturma zincirini (SatisDeposu, StokDeposu,
// CariDeposu.hareketEkle) birebir kullanır — tekerleği yeniden icat
// etmek yerine mevcut, test edilmiş akışa bağlanır.
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../veri/database/veritabani.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../cekirdek/utils/para_utils.dart';
import '../modeller/cari_model.dart';
import '../modeller/satis_model.dart';
import '../modeller/satis_kalem_model.dart';
import '../modeller/cari_hareket_model.dart';
import '../depolar/satis_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../depolar/cari_deposu.dart';

/// Sepete eklenen tek bir kalem — sipariş alma ekranından depoya
/// aktarılan ham veri. UI'daki _SepetKalemi ile karışmasın diye
/// depo katmanında ayrı, sade bir taşıyıcı sınıf kullanılıyor.
class BekleyenSiparisKalemGirdi {
  final int urunId;
  final String urunAdi;
  final String birimAdi;
  final double birimCarpani; // "1 Paket = 24 Adet" -> 24
  final double
      miktar; // kullanıcının girdiği miktar (birim cinsinden, ör. "3 Paket")
  final double birimFiyat; // satış fiyatı (bayiye göre hesaplanmış, KDV dahil)
  final double alisFiyat; // maliyet — referans/kâr görünürlüğü için
  final double iskontoOran;
  final double kdvOran;

  const BekleyenSiparisKalemGirdi({
    required this.urunId,
    required this.urunAdi,
    required this.birimAdi,
    required this.birimCarpani,
    required this.miktar,
    required this.birimFiyat,
    required this.alisFiyat,
    this.iskontoOran = 0,
    this.kdvOran = 18,
  });

  /// Toplam miktar HER ZAMAN ana birime (Adet) çevrilmiş halidir —
  /// stoktan düşülecek/faturaya yazılacak gerçek miktar budur.
  double get toplamMiktar => miktar * birimCarpani;
  double get birimFiyatIskontolu => birimFiyat * (1 - iskontoOran / 100);
  double get toplamTutar => toplamMiktar * birimFiyatIskontolu;
  double get iskontoTutar => toplamMiktar * birimFiyat * (iskontoOran / 100);
  // 🔴 DÜZELTME (Madde 21 — Para Hesaplamaları denetimi, 2026-09-16):
  // birimFiyat GERÇEKTEN KDV DAHİL (bkz. sepet_model.dart baş yorumu,
  // kullanıcı onayıyla doğrulandı) — kdvTutar, toplamTutar İÇİNDEN
  // ayıklanmalı, üzerine eklenmemeli.
  double get kdvTutar => ParaUtils.kdvPayiCikar(toplamTutar, kdvOran);
  double get alisToplam => toplamMiktar * alisFiyat;
}

class BekleyenSiparisDeposu {
  Future<int> siparisOlustur({
    required CariModel cari,
    required List<BekleyenSiparisKalemGirdi> kalemler,
    String? not,
    int? kullaniciId,
    int? subeId,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    final siparisGid = const Uuid().v4();

    final araToplam =
        kalemler.fold(0.0, (s, k) => s + k.toplamMiktar * k.birimFiyat);
    final iskontoToplam = kalemler.fold(0.0, (s, k) => s + k.iskontoTutar);
    final kdvToplam = kalemler.fold(0.0, (s, k) => s + k.kdvTutar);
    final genelToplam = kalemler.fold(0.0, (s, k) => s + k.toplamTutar);
    final alisToplam = kalemler.fold(0.0, (s, k) => s + k.alisToplam);

    late int siparisId;
    await db.transaction((txn) async {
      siparisId = await txn.insert('bekleyen_siparisler', {
        'global_id': siparisGid,
        'cari_id': cari.id,
        'sube_id': subeId,
        'kullanici_id': kullaniciId,
        'tarih': now,
        'durum': 'bekliyor',
        'not_': not,
        'ara_toplam': araToplam,
        'iskonto_toplam': iskontoToplam,
        'kdv_toplam': kdvToplam,
        'genel_toplam': genelToplam,
        'alis_toplam': alisToplam,
        'created_at': now,
        'last_updated': now,
      });
      for (final k in kalemler) {
        await txn.insert('bekleyen_siparis_kalem', {
          'global_id': const Uuid().v4(),
          'siparis_id': siparisId,
          'urun_id': k.urunId,
          'urun_adi': k.urunAdi,
          'birim_adi': k.birimAdi,
          'birim_carpani': k.birimCarpani,
          'miktar': k.miktar,
          'toplam_miktar': k.toplamMiktar,
          'birim_fiyat': k.birimFiyat,
          'alis_fiyat': k.alisFiyat,
          'iskonto_oran': k.iskontoOran,
          'iskonto_tutar': k.iskontoTutar,
          'kdv_oran': k.kdvOran,
          'toplam_tutar': k.toplamTutar,
          'last_updated': now,
        });
      }
    });

    final satir = await db.query('bekleyen_siparisler',
        where: 'id = ?', whereArgs: [siparisId], limit: 1);
    if (satir.isNotEmpty)
      BulutManager().upsert(
          'bekleyen_siparisler', Map<String, dynamic>.from(satir.first));
    final kalemSatirlari = await db.query('bekleyen_siparis_kalem',
        where: 'siparis_id = ?', whereArgs: [siparisId]);
    for (final k in kalemSatirlari) {
      BulutManager()
          .upsert('bekleyen_siparis_kalem', Map<String, dynamic>.from(k));
    }
    return siparisId;
  }

  /// [durum] null verilirse durum filtrelenmez — bayinin kendi sipariş
  /// geçmişini (bekliyor+onaylandi+iptal hepsi) tek listede göstermek için
  /// kullanılır (bkz. BayiSiparislerimEkrani, Madde 2 katman ihlali
  /// temizliği: önceden bu ekran doğrudan db.query çağırıyordu).
  Future<List<Map<String, dynamic>>> bekleyenSiparisleriGetir(
      {int? cariId, String? durum = 'bekliyor'}) async {
    final db = await Veritabani().db;
    final where = <String>['s.deleted_at IS NULL'];
    final args = <Object?>[];
    if (durum != null) {
      where.add('s.durum = ?');
      args.add(durum);
    }
    if (cariId != null) {
      where.add('s.cari_id = ?');
      args.add(cariId);
    }
    return db.rawQuery('''
      SELECT s.*, c.unvan AS cari_unvan
      FROM bekleyen_siparisler s
      LEFT JOIN cari c ON c.id = s.cari_id
      WHERE ${where.join(' AND ')}
      ORDER BY s.tarih DESC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> siparisKalemleriGetir(
      int siparisId) async {
    final db = await Veritabani().db;
    return db.query('bekleyen_siparis_kalem',
        where: 'siparis_id = ?', whereArgs: [siparisId]);
  }

  /// Siparişi iptal eder (soft-delete — durum='iptal').
  Future<void> iptalEt(int siparisId) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    await db.update(
        'bekleyen_siparisler', {'durum': 'iptal', 'last_updated': now},
        where: 'id = ?', whereArgs: [siparisId]);
    final satir = await db.query('bekleyen_siparisler',
        where: 'id = ?', whereArgs: [siparisId], limit: 1);
    if (satir.isNotEmpty)
      BulutManager().upsert(
          'bekleyen_siparisler', Map<String, dynamic>.from(satir.first));
  }

  /// 🔴 Onaylama — ToptanSatisEkrani._satisiTamamla() ile AYNI, kanıtlanmış
  /// zinciri kullanır: SatisModel + SatisKalemModel oluştur, stoktan düş,
  /// cari hareketi işle. Faturalandırma/irsaliye AYRI, opsiyonel adımlardır
  /// (çağıran ekran, üretilen satisId ile bunları kendi başlatır — burada
  /// zorunlu tutulmuyor, kullanıcı "şimdi değil" diyebilsin diye).
  Future<int> onaylaVeSatisaCevir({
    required int siparisId,
    required CariModel cari,
    int? kullaniciId,
  }) async {
    final db = await Veritabani().db;
    final kalemSatirlari = await siparisKalemleriGetir(siparisId);
    if (kalemSatirlari.isEmpty) {
      throw Exception('Siparişte kalem bulunamadı');
    }

    final tarih = DateTime.now();
    final fisNo = await Veritabani().fisNoUret('cari_satis');
    final genelToplam = kalemSatirlari.fold(
        0.0, (s, k) => s + (k['toplam_tutar'] as num).toDouble());

    final satisKalemler = kalemSatirlari.map((k) {
      final toplamMiktar = (k['toplam_miktar'] as num).toDouble();
      final toplamTutar = (k['toplam_tutar'] as num).toDouble();
      final kdvOran = (k['kdv_oran'] as num).toDouble();
      // 🔴 DÜZELTME (Madde 21, 2026-09-16): toplamTutar KDV DAHİL —
      // kdvTutar İÇİNDEN ayıklanır, üzerine eklenmez.
      final kdvTutar = ParaUtils.kdvPayiCikar(toplamTutar, kdvOran);
      return SatisKalemModel(
        satisId: 0,
        urunId: k['urun_id'] as int,
        urunAdi:
            '${k['urun_adi']} (${k['birim_adi']} x${(k['miktar'] as num).toStringAsFixed((k['miktar'] as num) == (k['miktar'] as num).roundToDouble() ? 0 : 1)})',
        miktar: toplamMiktar,
        birimFiyat: toplamMiktar > 0 ? toplamTutar / toplamMiktar : 0,
        iskontoOran: (k['iskonto_oran'] as num).toDouble(),
        iskontoTutar: (k['iskonto_tutar'] as num).toDouble(),
        kdvOran: kdvOran,
        kdvTutar: kdvTutar,
        netFiyat: toplamMiktar > 0 ? toplamTutar / toplamMiktar : 0,
        toplamTutar: toplamTutar,
        alisFiyat: (k['alis_fiyat'] as num).toDouble(),
      );
    }).toList();

    final satis = SatisModel(
      fisNo: fisNo,
      tarih: tarih,
      cariId: cari.id,
      cariAdi: cari.unvan,
      toplamTutar: genelToplam,
      genelToplam: genelToplam,
      odenenTutar: 0,
      odemeYontemi: 'Cari',
      fisTipi: 'Toptan Satış (Sipariş)',
      kasiyerId: kullaniciId,
      kullaniciId: kullaniciId,
    );

    late final int satisId;
    // FAZ 5 (Lot/SKT — kullanıcı onayıyla): lot_takibi açık üründe
    // birden fazla lottan tüketilebildiği için ürün başına birden
    // fazla global_id olabiliyor (bkz. StokDeposu.stokDusFefoTxn).
    final stokHareketGidleri = <int, List<String>>{};
    late final String cariGlobalId;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // 🔴 Derin analizde bulundu: bu fonksiyon siparişin hâlâ 'bekliyor'
      // durumunda olduğunu HİÇ kontrol etmiyordu — çift dokunma veya bir
      // ağ/UI hatası sonrası tekrar deneme, AYNI sipariş için iki kez
      // satış oluşturup stoktan iki kez düşüp cariye borcu iki kez
      // yazabiliyordu. Önce durumu 'onaylandi' yapmaya çalışıyoruz;
      // etkilenen satır sayısı 0 ise (zaten onaylanmış/iptal edilmiş)
      // işlemi tamamen durduruyoruz.
      final etkilenen = await txn.update(
        'bekleyen_siparisler',
        {'durum': 'onaylandi', 'last_updated': now},
        where: 'id = ? AND durum = ?',
        whereArgs: [siparisId, 'bekliyor'],
      );
      if (etkilenen == 0) {
        throw Exception('Sipariş zaten onaylanmış veya iptal edilmiş.');
      }

      satisId = await SatisDeposu().satisEkleTxn(txn, satis, satisKalemler);

      for (final k in kalemSatirlari) {
        final urunId = k['urun_id'] as int;
        stokHareketGidleri[urunId] = await StokDeposu().stokDusFefoTxn(
          txn,
          urunId: urunId,
          miktar: (k['toplam_miktar'] as num).toDouble(),
          kullaniciId: kullaniciId,
          referansId: satisId,
          referansTuru: 'toptan_siparis',
        );
      }

      cariGlobalId = await CariDeposu().hareketEkleTxn(
          txn,
          CariHareketModel(
            cariId: cari.id!,
            tarih: tarih,
            fisTipi: 'Toptan Satış (Sipariş)',
            fisId: satisId,
            fisNo: fisNo,
            aciklama: 'Sipariş onayı: $fisNo',
            borc: genelToplam,
            alacak: 0,
            odemeTuru: 'Cari',
          ));

      await txn.update(
          'bekleyen_siparisler', {'satis_id': satisId, 'last_updated': now},
          where: 'id = ?', whereArgs: [siparisId]);
    }); // transaction sonu

    // Transaction kalıcı olduktan sonra buluta bildir.
    try {
      BulutManager().upsert('satislar',
          {...satis.toMap(), 'id': satisId, 'global_id': satis.globalId});
      for (final k in satisKalemler) {
        BulutManager().upsert('satis_kalem', k.toMap());
      }
      for (final k in kalemSatirlari) {
        final urunId = k['urun_id'] as int;
        final gidler = stokHareketGidleri[urunId];
        if (gidler == null || gidler.isEmpty) continue;
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (urunSatir.isNotEmpty)
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        for (final gid in gidler) {
          final stokSatir = await db.query('stok_hareket',
              where: 'global_id = ?', whereArgs: [gid], limit: 1);
          if (stokSatir.isNotEmpty)
            BulutManager().upsert(
                'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        }
        // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): satis_tamamlama_servisi
        // ile AYNI desen — bekleyen sipariş onayı da şube bazlı stok
        // payını (sube_urun) güncellemeliydi, hiç yapılmıyordu.
        await StokDeposu().subeStokPayiUygula(
            urunId, (k['toplam_miktar'] as num).toDouble());
      }
      final cariHareketSatir = await db.query('cari_hareket',
          where: 'global_id = ?', whereArgs: [cariGlobalId], limit: 1);
      if (cariHareketSatir.isNotEmpty) {
        BulutManager().upsert(
            'cari_hareket', Map<String, dynamic>.from(cariHareketSatir.first));
      }
      final cariSatir = await db.query('cari',
          where: 'id = ?', whereArgs: [cari.id], limit: 1);
      if (cariSatir.isNotEmpty)
        BulutManager()
            .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
      final satir = await db.query('bekleyen_siparisler',
          where: 'id = ?', whereArgs: [siparisId], limit: 1);
      if (satir.isNotEmpty)
        BulutManager().upsert(
            'bekleyen_siparisler', Map<String, dynamic>.from(satir.first));
    } catch (e) {
      if (kDebugMode) debugPrint('Sipariş onayı bulut bildirimi hatası: $e');
    }

    return satisId;
  }
}
