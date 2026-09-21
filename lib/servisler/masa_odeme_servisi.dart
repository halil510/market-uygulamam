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
              kdvTutar: ParaUtils.kdvPayiCikar(k.toplam, k.kdvOran),
              netFiyat: ParaUtils.kdvHaricFiyat(k.toplam, k.kdvOran),
              alisFiyat: 0,
              alisFiyatKdv: 0,
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
      final satisSatir = await db.query('satislar',
          where: 'id = ?', whereArgs: [satisId], limit: 1);
      if (satisSatir.isNotEmpty)
        BulutManager()
            .upsert('satislar', Map<String, dynamic>.from(satisSatir.first));
      for (final k in satisKalemler) {
        BulutManager().upsert('satis_kalem', k.toMap());
      }
      for (final k in siparis.kalemler) {
        final gidler = stokHareketGidleri[k.urunId];
        if (gidler == null || gidler.isEmpty) continue;
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [k.urunId], limit: 1);
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
        // ile AYNI desen — masa satışı da şube bazlı stok payını
        // (sube_urun) güncellemeliydi, hiç yapılmıyordu.
        await _stokDepo.subeStokPayiUygula(k.urunId, k.miktar);
      }
      for (final gid in kasaGlobalIdleri) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (kasaSatir.isNotEmpty)
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
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
        if (cariSatir.isNotEmpty)
          BulutManager()
              .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
      }
      final siparisSatir = await db.query('masa_siparisleri',
          where: 'id = ?', whereArgs: [siparis.id], limit: 1);
      if (siparisSatir.isNotEmpty)
        BulutManager().upsert(
            'masa_siparisleri', Map<String, dynamic>.from(siparisSatir.first));
      final masaSatir = await db.query('masalar',
          where: 'id = ?', whereArgs: [siparis.masaId], limit: 1);
      if (masaSatir.isNotEmpty)
        BulutManager()
            .upsert('masalar', Map<String, dynamic>.from(masaSatir.first));
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
