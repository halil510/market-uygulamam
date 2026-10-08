// lib/servisler/masa_odeme_servisi.dart
// Tek sorumluluk: Açık bir masa siparişini SATIŞ kaydına çevirmek.
//   - satislar / satis_kalem oluşturur (fis_tipi: 'Masa Satış')
//   - stok düşer
//   - kasa hareketi (nakit/kart/havale kısmı) ekler
//   - varsa cari hareketi (veresiye kısmı) ekler
//   - masa_siparisleri kaydını 'odendi' yapar, masayı boşaltır
//
// Hızlı Satış ekranındaki _satisiTamamla ile aynı muhasebe mantığını
// masa/restoran akışına taşır — kod tekrarını önlemek için ortak bir
// "SatisYazimi" yardımcı tipi kullanılabilir, ancak farklı context
// (masa adı, sipariş id) nedeniyle burada bağımsız tutuldu.
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../depolar/satis_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../depolar/kasa_deposu.dart';
import '../depolar/cari_deposu.dart';
import '../veri/database/veritabani.dart';
import '../modeller/satis_model.dart';
import '../modeller/satis_kalem_model.dart';
import '../modeller/kasa_hareket_model.dart';
import '../modeller/cari_hareket_model.dart';
import '../modeller/masa_siparis_model.dart';
import '../servisler/auth_servisi.dart';
import '../servisler/aktif_sube_servisi.dart';
import '../cekirdek/utils/para_utils.dart';

class MasaOdemeSonuc {
  final int satisId;
  final String fisNo;
  final List<SatisKalemModel> kalemler;
  final double genelToplam;
  final double odenenTutar;
  final double paraUstu;
  final String odemeYontemi;
  MasaOdemeSonuc({
    required this.satisId,
    required this.fisNo,
    required this.kalemler,
    required this.genelToplam,
    required this.odenenTutar,
    required this.paraUstu,
    required this.odemeYontemi,
  });
}

/// Ödeme sırasında siparişin (başka cihazdan) değiştiği anlaşıldı — hiçbir
/// kayıt yazılmadı; ekran yenilenip tutar kontrol edilerek tekrar denenmeli.
class MasaSiparisDegistiHatasi implements Exception {
  @override
  String toString() =>
      'Sipariş, ödeme ekranı açıkken değişti (başka bir cihazdan ürün '
      'eklenmiş/silinmiş olabilir). Hiçbir ödeme alınmadı. Ekran '
      'yenilendi — güncel tutarı kontrol edip tekrar deneyin.';
}

class MasaOdemeServisi {
  final _satisDepo = SatisDeposu();
  final _stokDepo = StokDeposu();
  final _kasaDepo = KasaDeposu();
  final _cariDepo = CariDeposu();

  /// [odemeKalemleri]: [{'yontem': 'Nakit'|'Kredi Kartı'|'Havale/EFT'|'Cari', 'tutar': double}, ...]
  /// Çoklu Ödeme (karma) ekranından gelen formatla aynı.
  Future<MasaOdemeSonuc> odemeYap({
    required MasaSiparisModel siparis,
    required String masaAdi,
    required List<Map<String, dynamic>> odemeKalemleri,
    required double paraUstu,
    int? cariId,
    String? cariAdi,
  }) async {
    if (siparis.id == null) throw Exception('Sipariş bulunamadı');
    if (siparis.kalemler.isEmpty) throw Exception('Masada ürün yok');

    final tarih = DateTime.now();
    final kullanici = await AuthServisi().mevcutKullanici();
    // ÖNCEDEN masa satışları da normal satışlarla AYNI "satis" (MKP)
    // sayacını kullanıyordu — kullanıcı isteği: masa satışlarının kendi
    // ayrı, farklı ön ekli (MSA) fiş numarası serisi olsun.
    final fisNo = await Veritabani()
        .fisNoUret('masa', subeId: AktifSubeServisi().subeId ?? 1);
    final genelTop = siparis.hesaplananToplam;

    // Alış maliyeti satış anında kaleme yazılır (raporların tarihsel
    // maliyeti). Önceden 0 yazılıyordu (canlı test 2026-10-08).
    final urunIdler = siparis.kalemler.map((k) => k.urunId).toSet().toList();
    final maliyetDb = await Veritabani().db;
    final alisMap = <int, ({double alis, double alisKdv})>{
      for (final r in await maliyetDb.query('urunler',
          columns: ['id', 'alis_fiyat', 'alis_fiyat_kdv_dahil'],
          where: 'id IN (${List.filled(urunIdler.length, '?').join(',')})',
          whereArgs: urunIdler))
        r['id'] as int: (
          alis: (r['alis_fiyat'] as num?)?.toDouble() ?? 0,
          alisKdv: (r['alis_fiyat_kdv_dahil'] as num?)?.toDouble() ?? 0,
        ),
    };

    final satisKalemler = siparis.kalemler
        .map((k) => SatisKalemModel(
              satisId: 0,
              urunId: k.urunId,
              urunAdi: k.urunAdi,
              barkod: null,
              miktar: k.miktar,
              birimFiyat: k.birimFiyat,
              toplamTutar: k.toplam,
              iskontoOran: 0,
              iskontoTutar: 0,
              kdvOran: k.kdvOran,
              // toplam KDV DAHİL (bkz. sepet_model.dart baş yorumu) —
              // kdvTutar/netFiyat ParaUtils.kdvPayiCikar/kdvHaricFiyat ile
              // aynı bölme tabanlı formülü artık merkezi olarak kullanıyor.
              kdvTutar: ParaUtils.yuvarla(ParaUtils.kdvPayiCikar(k.toplam, k.kdvOran)),
              // net_fiyat = KDV DAHİL birim fiyat (SepetKalem.netFiyat ile AYNI
              // anlam; iade ekranı bunu iade birim fiyatı olarak okur). Önceden
              // KDV HARİÇ satır TOPLAMI yazılıyordu → masa satışı iadesi yanlış tutar.
              netFiyat: k.birimFiyat,
              alisFiyat: alisMap[k.urunId]?.alis ?? 0,
              alisFiyatKdv: alisMap[k.urunId]?.alisKdv ?? 0,
            ))
        .toList();

    final toplamOdenen =
        odemeKalemleri.fold(0.0, (s, k) => s + (k['tutar'] as num).toDouble());
    final odemeYontemi = odemeKalemleri.length == 1
        ? odemeKalemleri.first['yontem'] as String
        : 'Karma';

    final satis = SatisModel(
      fisNo: fisNo,
      tarih: tarih,
      cariId: cariId ?? siparis.cariId,
      cariAdi: cariAdi ?? siparis.cariAdi,
      toplamTutar: genelTop,
      genelToplam: genelTop,
      odenenTutar: toplamOdenen,
      odemeYontemi: odemeYontemi,
      fisTipi: 'Masa Satış',
      aciklama: 'Masa: $masaAdi',
      kasiyerId: kullanici?.id,
      kullaniciId: kullanici?.id,
    );

    // ══════════════════════════════════════════════════════════════
    // 🔴 DERİN ANALİZDE BULUNDU: masada ödeme alma — kullanıcının asıl
    // sorduğu akışın ta kendisi — satış + stok + kasa + cari + masa
    // kapatma AYRI transaction'larda yapılıyordu. Hızlı satış, toptan
    // satış ve bekleyen sipariş onayında bulunup düzeltilen AYNI hata
    // sınıfının beşinci, hiç dokunulmamış örneğiydi. Uygulama ortada
    // kapanırsa: satış oluşur, stok düşmez, kasa/cari işlenmez VE masa
    // hâlâ "dolu/ödenmedi" görünüp aynı sipariş tekrar ödenebilirdi
    // (mükerrer tahsilat riski). Artık hepsi TEK transaction'da.
    // ══════════════════════════════════════════════════════════════
    final db = await Veritabani().db;
    late final int satisId;
    // FAZ 5 (Lot/SKT — kullanıcı onayıyla): satis_tamamlama_servisi.dart
    // ile AYNI düzeltme — lot_takibi açık üründe birden fazla lottan
    // tüketilebildiği için ürün başına birden fazla global_id olabiliyor.
    final stokHareketGidleri = <int, List<String>>{};
    // 🔴🔴 FAZ 1 madde 2 (kullanıcı onayıyla, Vardiya/Kasa mutabakatı):
    // satis_tamamlama_servisi.dart'taki AYNI düzeltme — karma ödemede
    // her yöntem için AYRI, odeme_yontemi etiketli kasa hareketi.
    final kasaGlobalIdleri = <String>[];
    final cariGlobalIdleri = <String>[];
    final now = tarih.toIso8601String();

    // Cari hareketi — veresiye kısmı
    final cariTutar = odemeKalemleri
        .where((k) => k['yontem'] == 'Cari')
        .fold(0.0, (s, k) => s + (k['tutar'] as num).toDouble());
    final efektifCariId = cariId ?? siparis.cariId;

    await db.transaction((txn) async {
      // Bayat sipariş koruması: ödeme penceresi açıkken başka bir cihaz /
      // QR sipariş masaya ürün eklediyse (veya birini sildiyse), ekrandaki
      // kopya güncel değildir. Bu haliyle ödeme alınırsa yeni kalemler
      // satışa/stoğa/kasaya HİÇ girmeden sipariş 'ödendi' kapanır.
      // Kalemler transaction içinde yeniden okunur; fark varsa ödeme
      // yapılmaz (tüm yazımlar geri alınır), kullanıcı yenileyip tekrar dener.
      final guncelKalemler = await txn.query('masa_siparis_kalem',
          columns: ['id', 'miktar', 'birim_fiyat'],
          where: 'siparis_id = ? AND is_deleted = 0',
          whereArgs: [siparis.id]);
      final guncelIdler = {for (final k in guncelKalemler) k['id'] as int};
      final ekrandakiIdler = {for (final k in siparis.kalemler) k.id};
      final guncelToplam = ParaUtils.yuvarla(guncelKalemler.fold(
          0.0,
          (s, k) =>
              s +
              (k['miktar'] as num).toDouble() *
                  (k['birim_fiyat'] as num).toDouble()));
      if (guncelIdler.length != ekrandakiIdler.length ||
          !guncelIdler.containsAll(ekrandakiIdler.whereType<int>()) ||
          (guncelToplam - genelTop).abs() > 0.01) {
        throw MasaSiparisDegistiHatasi();
      }

      satisId = await _satisDepo.satisEkleTxn(txn, satis, satisKalemler);

      for (final k in siparis.kalemler) {
        stokHareketGidleri[k.urunId] = await _stokDepo.stokDusFefoTxn(
          txn,
          urunId: k.urunId,
          miktar: k.miktar,
          kullaniciId: kullanici?.id,
          referansId: satisId,
          referansTuru: 'satis',
          aciklama: 'Masa Satış: $masaAdi ($fisNo)',
        );
      }

      final digerYontemler = odemeKalemleri.where((k) => k['yontem'] != 'Cari');
      final gruplar = <String, double>{};
      for (final k in digerYontemler) {
        final y = k['yontem'] as String;
        gruplar[y] = (gruplar[y] ?? 0) + (k['tutar'] as num).toDouble();
      }
      // Para üstü kasaya gelir yazılmasın: fazlalık Nakit'ten düşülür.
      final fazlaOdeme = toplamOdenen - genelTop;
      if (fazlaOdeme > 0.005 && (gruplar['Nakit'] ?? 0) > 0) {
        final dus =
            fazlaOdeme < gruplar['Nakit']! ? fazlaOdeme : gruplar['Nakit']!;
        gruplar['Nakit'] = gruplar['Nakit']! - dus;
      }
      // 🔴 Derin analizde bulundu (kendi-keşif turu — Masa modülü
      // denetimi): SatisTamamlamaServisi.tamamla() (Hızlı Satış) bir
      // müşteri bağlıyken Nakit/Kart payı için de bakiyeyi ETKİLEMEYEN
      // (borc=alacak, self-cancelling) bir "bilgi" cari_hareket satırı
      // yazar — böylece o satış müşterinin Cari ekstresinde/geçmişinde
      // görünür. Masa akışı bunu HİÇ yapmıyordu: bir müşteriye bağlı
      // masa hesabı Nakit/Kart ile (kısmen veya tamamen) ödenirse,
      // kasada/satışta doğru işlenir ama o müşterinin cari geçmişinde
      // HİÇ görünmezdi. Artık Hızlı Satış ile AYNI desen uygulanıyor.
      final digerTutar = gruplar.values.fold(0.0, (s, v) => s + v);
      if (efektifCariId != null && digerTutar > 0.005) {
        final yontemler = gruplar.keys.join('+');
        cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: efektifCariId,
              tarih: tarih,
              fisTipi: 'Satış',
              fisId: satisId,
              fisNo: fisNo,
              aciklama:
                  '$yontemler Masa Satış: $masaAdi ($fisNo) — bakiyeyi etkilemez',
              borc: digerTutar,
              alacak: digerTutar,
              odemeTuru: yontemler,
              kullanici: kullanici?.adSoyad,
            )));
      }
      for (final girdi in gruplar.entries) {
        if (girdi.value <= 0.005) continue;
        final kid = const Uuid().v4();
        kasaGlobalIdleri.add(kid);
        await _kasaDepo.hareketEkleTxn(
            txn,
            KasaHareketModel(
              globalId: kid,
              hareketTipi: 'Satış',
              tutar: girdi.value,
              referansId: satisId,
              referansTuru: 'satis',
              tarih: tarih,
              aciklama: 'Masa Satış: $masaAdi — $fisNo (${girdi.key})',
              kullaniciId: kullanici?.id,
              odemeYontemi: girdi.key,
            ));
      }

      if (efektifCariId != null && cariTutar > 0.005) {
        cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: efektifCariId,
              tarih: tarih,
              fisTipi: 'Satış',
              fisId: satisId,
              fisNo: fisNo,
              aciklama: 'Masa Veresiye: $masaAdi ($fisNo)',
              borc: cariTutar,
              alacak: 0,
              odemeTuru: 'Cari',
              kullanici: kullanici?.adSoyad,
            )));
      }

      // Masayı kapat — aynı transaction içinde, siparisKapat()'ın
      // yaptığının birebir aynısı (masa_siparisleri + masalar).
      // 🔴 Derin denetimde bulundu (P1): bu UPDATE'te sadece 'id = ?'
      // vardı, mevcut 'durum' hiç kontrol edilmiyordu — iki terminal/
      // garson aynı masanın ödemesini eşzamanlı işlerse (ya da çift
      // dokunma/geri-ileri) ikisi de "sipariş hâlâ açık" sanıp devam
      // edebilir, mükerrer satış+stok+kasa/cari kaydı oluşurdu.
      // alim_islem_servisi.dart/bekleyen_siparis_deposu.dart'taki AYNI
      // korumayla hizalandı: etkilenen satır 0 ise dur.
      final etkilenen = await txn.update(
          'masa_siparisleri',
          {
            'durum': 'odendi',
            'kapanis_zamani': now,
            'satis_id': satisId,
            'last_updated': now,
          },
          where: 'id = ? AND durum = ?',
          whereArgs: [siparis.id, 'acik']);
      if (etkilenen == 0) {
        throw Exception('Bu sipariş zaten ödenmiş veya kapatılmış.');
      }
      await txn.update('masalar', {'durum': 'bos', 'last_updated': now},
          where: 'id = ?', whereArgs: [siparis.masaId]);
    }); // transaction sonu

    // Transaction kalıcı olduktan sonra buluta bildir.
    try {
      // Kalemler de DB'den geri okunur (bkz. SatisDeposu.bulutaBildir —
      // k.toMap() satis_id=0 ve kimliksiz kalem satırı yolluyordu).
      await _satisDepo.bulutaBildir(satisId);
      for (final k in siparis.kalemler) {
        final gidler = stokHareketGidleri[k.urunId];
        if (gidler == null || gidler.isEmpty) continue;
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [k.urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        for (final gid in gidler) {
          final stokSatir = await db.query('stok_hareket',
              where: 'global_id = ?', whereArgs: [gid], limit: 1);
          if (stokSatir.isNotEmpty) {
            BulutManager().upsert(
                'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
          }
        }
        // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): satis_tamamlama_servisi
        // ile AYNI desen — masa satışı da şube bazlı stok payını
        // (sube_urun) güncellemeliydi, hiç yapılmıyordu.
        await _stokDepo.subeStokPayiUygula(k.urunId, k.miktar);
      }
      for (final gid in kasaGlobalIdleri) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (kasaSatir.isNotEmpty) {
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
      }
      for (final gid in cariGlobalIdleri) {
        final cariHareketSatir = await db.query('cari_hareket',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (cariHareketSatir.isNotEmpty) {
          BulutManager().upsert('cari_hareket',
              Map<String, dynamic>.from(cariHareketSatir.first));
        }
      }
      if (cariGlobalIdleri.isNotEmpty) {
        final cariSatir = await db.query('cari',
            where: 'id = ?', whereArgs: [efektifCariId], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager()
              .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
      final siparisSatir = await db.query('masa_siparisleri',
          where: 'id = ?', whereArgs: [siparis.id], limit: 1);
      if (siparisSatir.isNotEmpty) {
        BulutManager().upsert(
            'masa_siparisleri', Map<String, dynamic>.from(siparisSatir.first));
      }
      final masaSatir = await db.query('masalar',
          where: 'id = ?', whereArgs: [siparis.masaId], limit: 1);
      if (masaSatir.isNotEmpty) {
        BulutManager()
            .upsert('masalar', Map<String, dynamic>.from(masaSatir.first));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Masa ödemesi bulut bildirimi hatası: $e');
    }

    return MasaOdemeSonuc(
      satisId: satisId,
      fisNo: fisNo,
      kalemler: satisKalemler,
      genelToplam: genelTop,
      odenenTutar: toplamOdenen,
      paraUstu: paraUstu,
      odemeYontemi: odemeYontemi,
    );
  }
}
