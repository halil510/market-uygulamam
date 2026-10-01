// lib/servisler/fis_fiyat_guncelleme_servisi.dart
//
// Cari Detay'da seçilen Cari satış fişlerini ÜRÜN LİSTESİNDEKİ GÜNCEL satış
// fiyatına göre yeniden fiyatlar (kullanıcı isteği 2026-10-01: "Biskrem
// carideki fişlerde 15'ti, satış 20 oldu; fişlerdeki fiyatı 20 yap, fiş
// tutarı ve bakiye değişsin").
//
// Muhasebe kuralı: eski fiş kalemlerini sessizce ezmek yerine, tutar FARKI
// fişin kendisine bağlı ('Satış', aynı fis_id) ek bir cari_hareket satırı
// olarak yazılır — cari.bakiye mevcut mekanizmayla (hareketEkleTxn) yeniden
// hesaplanır, Cari Detay'da aynı fis_id'li satırlar tek kartta birleştirilir
// (bkz. cariHareketleriniGrupla). Hepsi TEK transaction'da atomiktir.
//
// Güncellenmeyen (atlanan) fişler: iptal/silinmiş, Cari-dışı veya Karma
// ödemeli (fark kimin hesabına yazılacağı belirsiz), faturalandırılmış
// (mevzuat gereği değiştirilemez). Stok ve maliyet DEĞİŞMEZ.
import 'package:uuid/uuid.dart';
import '../cekirdek/utils/para_utils.dart';
import '../depolar/cari_deposu.dart';
import '../modeller/cari_hareket_model.dart';
import '../servisler/audit_log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../veri/database/veritabani.dart';

class FisFiyatPlani {
  final int satisId;
  final String fisNo;
  final double eskiToplam;
  final double yeniToplam;
  final List<String> degisenUrunler;
  final String? atlamaNedeni;
  final int? cariId;

  // Uygulama için ham veri (kalem satır id -> yeni birim fiyat).
  final Map<int, double> _kalemFiyatlari;
  final double _kdvFarki;

  const FisFiyatPlani._({
    required this.satisId,
    required this.fisNo,
    required this.eskiToplam,
    required this.yeniToplam,
    required this.degisenUrunler,
    required this.atlamaNedeni,
    required this.cariId,
    required Map<int, double> kalemFiyatlari,
    required double kdvFarki,
  })  : _kalemFiyatlari = kalemFiyatlari,
        _kdvFarki = kdvFarki;

  double get fark => yeniToplam - eskiToplam;
  bool get degisecekMi => atlamaNedeni == null && degisenUrunler.isNotEmpty;
}

class FisFiyatSonucu {
  final int guncellenen;
  final int degismeyen;
  final int atlanan;
  final double toplamFark;
  const FisFiyatSonucu(
      this.guncellenen, this.degismeyen, this.atlanan, this.toplamFark);
}

class FisFiyatGuncellemeServisi {
  final _cariDepo = CariDeposu();

  /// Salt okunur: hiçbir şey yazmaz, her fiş için ne olacağını döner.
  Future<List<FisFiyatPlani>> onizle(List<int> satisIdleri) async {
    final db = await Veritabani().db;
    final sonuc = <FisFiyatPlani>[];
    for (final id in satisIdleri.toSet()) {
      sonuc.add(await _planla(db, id));
    }
    return sonuc;
  }

  /// Önizlemedeki değişecek fişleri uygular. Fiyatlar uygulama anında
  /// YENİDEN okunur (önizleme ile onay arasında değişmiş olabilir).
  Future<FisFiyatSonucu> uygula(List<int> satisIdleri,
      {String? kullanici}) async {
    final db = await Veritabani().db;
    final cariHareketGidleri = <String>[];
    final etkilenenCariler = <int>{};
    final etkilenenSatislar = <int>[];
    var guncellenen = 0, degismeyen = 0, atlanan = 0;
    var toplamFark = 0.0;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final id in satisIdleri.toSet()) {
        final plan = await _planla(txn, id);
        if (plan.atlamaNedeni != null) {
          atlanan++;
          continue;
        }
        if (!plan.degisecekMi) {
          degismeyen++;
          continue;
        }

        for (final e in plan._kalemFiyatlari.entries) {
          final satir = await txn.query('satis_kalem',
              where: 'id = ?', whereArgs: [e.key], limit: 1);
          if (satir.isEmpty) continue;
          final miktar = (satir.first['miktar'] as num?)?.toDouble() ?? 0;
          final kdvOran = (satir.first['kdv_oran'] as num?)?.toDouble() ?? 0;
          final toplam = e.value * miktar;
          final guncel = <String, Object?>{
            'birim_fiyat': e.value,
            'net_fiyat': e.value,
            'iskonto_oran': 0,
            'iskonto_tutar': 0,
            'toplam_tutar': toplam,
            'kdv_tutar': ParaUtils.kdvPayiCikar(toplam, kdvOran),
            'last_updated': now,
          };
          if ((satir.first['global_id']?.toString() ?? '').isEmpty) {
            guncel['global_id'] = const Uuid().v4();
          }
          await txn.update('satis_kalem', guncel,
              where: 'id = ?', whereArgs: [e.key]);
          final yeniSatir = await txn.query('satis_kalem',
              where: 'id = ?', whereArgs: [e.key], limit: 1);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'satis_kalem',
              veri: Map<String, dynamic>.from(yeniSatir.first));
        }

        final baslik = (await txn.query('satislar',
                where: 'id = ?', whereArgs: [id], limit: 1))
            .first;
        final eskiGenel = (baslik['genel_toplam'] as num?)?.toDouble() ?? 0;
        final eskiOdenen = (baslik['odenen_tutar'] as num?)?.toDouble() ?? 0;
        final eskiToplamTutar = (baslik['toplam_tutar'] as num?)?.toDouble() ?? 0;
        final eskiKdv = (baslik['kdv_tutar'] as num?)?.toDouble() ?? 0;
        final fark = plan.fark;
        final eskiAciklama = (baslik['aciklama'] as String?) ?? '';
        final not = '[Fiyat güncellendi ${now.substring(0, 16)}'
            '${kullanici != null ? " / $kullanici" : ""}]';
        await txn.update(
            'satislar',
            {
              'genel_toplam': eskiGenel + fark,
              'toplam_tutar': eskiToplamTutar + fark,
              'kdv_tutar': eskiKdv + plan._kdvFarki,
              // Fiş tam borç olarak yazılmışsa ödenen de yeni toplama eşit kalsın.
              'odenen_tutar':
                  (eskiOdenen - eskiGenel).abs() < 0.005 ? eskiGenel + fark : eskiOdenen,
              'aciklama': eskiAciklama.isEmpty ? not : '$eskiAciklama $not',
              'last_updated': now,
            },
            where: 'id = ?',
            whereArgs: [id]);
        final yeniBaslik = await txn.query('satislar',
            where: 'id = ?', whereArgs: [id], limit: 1);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'satislar',
            veri: Map<String, dynamic>.from(yeniBaslik.first));

        final gid = await _cariDepo.hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: plan.cariId!,
              tarih: DateTime.now(),
              fisTipi: 'Satış',
              fisId: id,
              fisNo: plan.fisNo,
              aciklama: 'Fiyat güncelleme: ${plan.fisNo}',
              borc: fark > 0 ? fark : 0,
              alacak: fark < 0 ? -fark : 0,
              odemeTuru: 'Cari',
              kullanici: kullanici,
            ));
        cariHareketGidleri.add(gid);
        etkilenenCariler.add(plan.cariId!);
        etkilenenSatislar.add(id);
        toplamFark += fark;
        guncellenen++;
      }
    });

    // Transaction kalıcı — bulut bildirimi best-effort (satış tamamla ile aynı desen).
    try {
      for (final id in etkilenenSatislar) {
        final s = await db.query('satislar', where: 'id = ?', whereArgs: [id]);
        if (s.isNotEmpty) {
          BulutManager().upsert('satislar', Map<String, dynamic>.from(s.first));
        }
        final k = await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [id]);
        for (final r in k) {
          BulutManager().upsert('satis_kalem', Map<String, dynamic>.from(r));
        }
      }
      for (final gid in cariHareketGidleri) {
        final h = await db.query('cari_hareket', where: 'global_id = ?', whereArgs: [gid]);
        if (h.isNotEmpty) {
          BulutManager().upsert('cari_hareket', Map<String, dynamic>.from(h.first));
        }
      }
      for (final cid in etkilenenCariler) {
        final c = await db.query('cari', where: 'id = ?', whereArgs: [cid]);
        if (c.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(c.first));
        }
      }
    } catch (_) {}

    if (guncellenen > 0) {
      await AuditLogServisi().olayKaydet(
        tabloAdi: 'satislar',
        islemTuru: 'FIS_FIYAT_GUNCELLEME',
        ozet: '$guncellenen fiş güncel ürün fiyatına çekildi '
            '(toplam fark: ${toplamFark.toStringAsFixed(2)} TL)',
      );
    }
    return FisFiyatSonucu(guncellenen, degismeyen, atlanan, toplamFark);
  }

  Future<FisFiyatPlani> _planla(dynamic db, int satisId) async {
    FisFiyatPlani atla(String fisNo, String neden, [int? cariId]) =>
        FisFiyatPlani._(
          satisId: satisId,
          fisNo: fisNo,
          eskiToplam: 0,
          yeniToplam: 0,
          degisenUrunler: const [],
          atlamaNedeni: neden,
          cariId: cariId,
          kalemFiyatlari: const {},
          kdvFarki: 0,
        );

    final rows = await db.query('satislar',
        where: 'id = ?', whereArgs: [satisId], limit: 1);
    if (rows.isEmpty) return atla('#$satisId', 'Fiş bulunamadı');
    final s = rows.first;
    final fisNo = (s['fis_no'] as String?) ?? '#$satisId';
    final cariId = s['cari_id'] as int?;
    if ((s['iptal'] as int?) == 1 || (s['is_deleted'] as int?) == 1) {
      return atla(fisNo, 'İptal edilmiş/silinmiş');
    }
    if ((s['fis_tipi'] as String?) != 'Satış') {
      return atla(fisNo, 'Satış fişi değil');
    }
    if (cariId == null || (s['odeme_yontemi'] as String?) != 'Cari') {
      return atla(fisNo, 'Tamamı Cari (veresiye) değil');
    }
    final fatura = await db.query('faturalar',
        columns: ['id'],
        where: "satis_id = ? AND durum != 'iptal'",
        whereArgs: [satisId],
        limit: 1);
    if (fatura.isNotEmpty) return atla(fisNo, 'Faturalandırılmış');

    final kalemler = await db.query('satis_kalem',
        where: 'satis_id = ?', whereArgs: [satisId]);
    final fiyatlar = <int, double>{};
    final urunler = <String>[];
    var fark = 0.0, kdvFarki = 0.0;
    for (final k in kalemler) {
      final urunId = k['urun_id'] as int?;
      if (urunId == null) continue;
      final u = await db.query('urunler',
          columns: ['satis_fiyati'],
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [urunId],
          limit: 1);
      if (u.isEmpty) continue;
      final yeni = (u.first['satis_fiyati'] as num?)?.toDouble() ?? 0;
      final eski = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
      if (yeni <= 0 || (yeni - eski).abs() < 0.005) continue;
      final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
      final kdvOran = (k['kdv_oran'] as num?)?.toDouble() ?? 0;
      final eskiToplam = (k['toplam_tutar'] as num?)?.toDouble() ?? eski * miktar;
      final yeniToplam = yeni * miktar;
      fark += yeniToplam - eskiToplam;
      kdvFarki += ParaUtils.kdvPayiCikar(yeniToplam, kdvOran) -
          ((k['kdv_tutar'] as num?)?.toDouble() ?? 0);
      fiyatlar[k['id'] as int] = yeni;
      urunler.add('${k['urun_adi']}: ${eski.toStringAsFixed(2)} → ${yeni.toStringAsFixed(2)}');
    }
    final eskiGenel = (s['genel_toplam'] as num?)?.toDouble() ?? 0;
    return FisFiyatPlani._(
      satisId: satisId,
      fisNo: fisNo,
      eskiToplam: eskiGenel,
      yeniToplam: eskiGenel + fark,
      degisenUrunler: urunler,
      atlamaNedeni: null,
      cariId: cariId,
      kalemFiyatlari: fiyatlar,
      kdvFarki: kdvFarki,
    );
  }
}
