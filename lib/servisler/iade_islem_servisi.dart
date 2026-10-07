// lib/servisler/iade_islem_servisi.dart
//
// İade ekranlarının (iade_ekrani.dart + part dosyaları) db.transaction()
// mantığını SCREEN→SERVICE→REPOSITORY mimarisine taşıyan servis. Her
// metod, taşındığı ekranın orijinal mantığını davranış olarak birebir
// korur — sadece sorumluluk UI katmanından buraya kaydırılmıştır.
import '../cekirdek/utils/para_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseExecutor;
import 'package:uuid/uuid.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../depolar/cari_deposu.dart';
import '../depolar/kasa_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../depolar/urun_deposu.dart';
import '../modeller/cari_hareket_model.dart';
import '../modeller/urun_model.dart';
import '../modeller/cari_model.dart';
import '../servisler/aktif_sube_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../servisler/fiyat_hesaplama_servisi.dart';
import '../veri/database/veritabani.dart';

part 'iade_islem_servisi_duzenleme.dart';
part 'iade_islem_servisi_gecmis.dart';
part 'iade_islem_servisi_tedarikci_bayi.dart';

/// Fiş iadesinde istenen miktar, o fişten hâlâ iade edilebilecek miktarı
/// aşıyor (ör. aynı kalem başka bir kasada / aynı anda iade edildi).
class IadeMiktariAsildiHatasi implements Exception {
  final String urunAdi;
  final double iadeEdilebilir;

  const IadeMiktariAsildiHatasi({required this.urunAdi, required this.iadeEdilebilir});

  @override
  String toString() {
    if (iadeEdilebilir <= 0.0005) return '$urunAdi bu fişten zaten tamamen iade edilmiş';
    final miktar = iadeEdilebilir % 1 == 0
        ? iadeEdilebilir.toStringAsFixed(0)
        : iadeEdilebilir.toStringAsFixed(3);
    return '$urunAdi için bu fişten en fazla $miktar iade edilebilir '
        '(bir kısmı başka bir işlemde iade edilmiş)';
  }
}

/// Hızlı iadede bir veya daha fazla ürünün iade fiyatına dayanak olacak
/// satış kaydı yok (bugünkü fiyatla iade yapılmaz — B4 kararı).
class IadeSatisFiyatiBulunamadiHatasi implements Exception {
  final List<String> urunAdlari;
  final bool cariyeGore;

  const IadeSatisFiyatiBulunamadiHatasi(this.urunAdlari, {required this.cariyeGore});

  @override
  String toString() =>
      '${urunAdlari.join(', ')} için ${cariyeGore ? 'bu müşteriye ait ' : ''}satış kaydı '
      'bulunamadı. İade, müşterinin ödediği fiyattan yapılabilmesi için satış '
      'kaydı gerektirir — fişi biliyorsanız "Fiş No ile İade" kullanın.';
}

/// Hızlı (barkod) iade sekmesinde biriken tek bir kalem.
class IadeKalemGirdi {
  final UrunModel urun;
  final int adet;
  const IadeKalemGirdi({required this.urun, required this.adet});
}

class IadeIslemServisi {
  final _kasaDepo = KasaDeposu();
  final _stokDepo = StokDeposu();

  /// Hızlı Barkod İade sekmesindeki "Toplu iade" akışı — bkz.
  /// iade_ekrani_hizli.dart._hizliOnaylaVeKaydet (taşındığı yer).
  /// iade + tüm kalemler + stok + (varsa) kasa + (varsa) cari TEK
  /// transaction içinde: ya hep birden yazılır ya hiç.
  ///
  /// 🔴 B4 KARARI (kullanıcı, 2026-10-07): iade tutarı ürünün BUGÜNKÜ
  /// satış fiyatından DEĞİL, müşterinin satışta gerçekten ödediği net
  /// fiyattan hesaplanır (bkz. [_satisFiyatlariTxn]). Önceden zam gelmiş bir
  /// ürünün iadesinde müşteriye ödediğinden fazla para veriliyordu. Dayanak
  /// satış bulunamazsa [IadeSatisFiyatiBulunamadiHatasi] — iade yapılmaz.
  ///
  /// Döner: (iadeId, fisNo, ürün id → iade birim fiyatı).
  Future<(int, String, Map<int, double>)> topluIadeKaydet({
    required List<IadeKalemGirdi> kalemler,
    required String odemeYontemi,
    required int? kullaniciId,
    required String kullaniciAdi,
    CariModel? cari,
  }) async {
    final db = await Veritabani().db;
    // Fiyat dayanağı fiş no tüketilmeden doğrulanır (boşa fiş no harcanmasın);
    // asıl hesap aşağıda yazmayla aynı transaction'da tekrarlanır.
    await _satisFiyatlariTxn(db, kalemler, cariId: cari?.id);
    final fisNo = await Veritabani()
        .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);
    final iadeGlobalId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    late final int iadeId;
    late final Map<int, double> fiyatlar;
    late final double toplamIade;

    await db.transaction((txn) async {
      fiyatlar = await _satisFiyatlariTxn(txn, kalemler, cariId: cari?.id);
      toplamIade = ParaUtils.yuvarla(kalemler.fold<double>(
          0.0, (s, i) => s + i.adet * fiyatlar[i.urun.id]!));
      final iadeSatiri = {
        'global_id': iadeGlobalId,
        'cari_id': cari?.id,
        'fis_no': fisNo,
        'tarih': now,
        'toplam_tutar': toplamIade,
        'iade_nedeni': 'Toplu iade',
        'durum': 'tamamlandi',
        'kasiyer_id': kullaniciId,
      };
      iadeId = await txn.insert('iade', iadeSatiri);
      // Madde 5 sertleştirmesi: her yazılan satır, business data ile
      // AYNI transaction'da senkron kuyruğuna yazılıyor (bkz.
      // SyncKuyrukYazici yorumu — rollback olursa hiçbiri kuyrukta kalmaz).
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'iade', veri: {...iadeSatiri, 'id': iadeId});

      for (final item in kalemler) {
        final fiyat = fiyatlar[item.urun.id]!;
        final toplam = ParaUtils.yuvarla(item.adet * fiyat);

        final kalemSatiri = {
          'global_id': const Uuid().v4(),
          'iade_id': iadeId,
          'urun_id': item.urun.id,
          'urun_adi': item.urun.urunAdi,
          'miktar': item.adet.toDouble(),
          'birim_fiyat': fiyat,
          'toplam': toplam,
        };
        final kalemId = await txn.insert('iade_kalem', kalemSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade_kalem', veri: {...kalemSatiri, 'id': kalemId});

        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [item.urun.id]);
        if (urunRows.isNotEmpty) {
          final onceki = (urunRows.first['stok'] as num).toDouble();
          await txn.update(
              'urunler', {'stok': onceki + item.adet},
              where: 'id = ?', whereArgs: [item.urun.id]);
          final stokSatiri = {
            'global_id': const Uuid().v4(),
            'urun_id': item.urun.id,
            'hareket_turu': 'Iade Giris',
            'miktar': item.adet.toDouble(),
            'onceki_stok': onceki,
            'sonraki_stok': onceki + item.adet,
            'tarih': now,
            'referans_id': iadeId,
            'referans_turu': 'iade',
            'kullanici_id': kullaniciId,
            'aciklama': 'Toplu iade: $fisNo',
          };
          final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
          final guncelUrunSatiri = await txn.query('urunler',
              where: 'id = ?', whereArgs: [item.urun.id], limit: 1);
          if (guncelUrunSatiri.isNotEmpty) {
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'urunler',
                veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
          }
        }
      }

      // Kasa — SADECE Nakit iade seçildiyse oluşturulur.
      if (odemeYontemi == 'Nakit' && toplamIade > 0) {
        final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) - toplamIade;
        final kasaSatiri = {
          'global_id': const Uuid().v4(),
          'hareket_tipi': 'İade',
          'tutar': toplamIade,
          'bakiye_sonrasi': kasaBakiye,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'tarih': now,
          'sube_id': AktifSubeServisi().subeId,
          'aciklama': 'Toplu iade: $fisNo',
          'kullanici_id': kullaniciId,
        };
        final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
      }

      if (cari != null && toplamIade > 0) {
        // 🔴🔴 KRİTİK DÜZELTME (kullanıcı kararı, 2026-09-22 sabah): bir
        // önceki "düzeltme" cari seçimini HER ZAMAN bakiyeyi etkilemeyen
        // salt-kayıt yapmıştı — ama bu, cari'ye GERÇEKTEN yazdırılan
        // (Veresiye/borç) iadelerde bakiyeyi hiç düşürmüyordu. Doğru ERP
        // kuralı: ödeme yöntemi ('Nakit'/'Kart/Banka' → para fiziksel
        // olarak zaten geri verildi, cari sadece takip amaçlı = nötr) ile
        // ('Cari' → para fiziksel verilmedi, tutar cari bakiyesinden
        // GERÇEKTEN düşülür/eklenir) birbirini DIŞLAR — kasiyer ikisini
        // birden seçemez (dropdown'da tek seçim), bu yüzden çift-iade
        // riski olmadan artık gerçek etki uygulanabiliyor.
        final isTedarikci = cariSafTedarikciMi(cari.cariTipi);
        final gercekEtki = odemeYontemi == 'Cari';
        final cariHareketSatiri = {
          'global_id': const Uuid().v4(),
          'cari_id': cari.id,
          'tarih': now,
          'fis_tipi': 'İade',
          'fis_id': iadeId,
          'fis_no': fisNo,
          'aciklama': gercekEtki
              ? 'Toplu iade: $fisNo — cari bakiyesine işlendi'
              : 'Toplu iade: $fisNo — bakiyeyi etkilemez',
          'borc': gercekEtki ? (isTedarikci ? toplamIade : 0) : toplamIade,
          'alacak': gercekEtki ? (isTedarikci ? 0 : toplamIade) : toplamIade,
          'odeme_turu': odemeYontemi,
          'kullanici': kullaniciAdi,
        };
        final cariHareketId = await txn.insert('cari_hareket', cariHareketSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'cari_hareket', veri: {...cariHareketSatiri, 'id': cariHareketId});
        // 'is_deleted = 0' filtresi — kanonik bakiye kuralı.
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = ROUND((SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0), 2) WHERE id=?',
            [cari.id, cari.id]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cari.id], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }
    });

    // Transaction kalıcı olduktan sonra buluta bildir — best-effort,
    // sync hatası ana işlemi geri almaz (orijinal ekran davranışıyla aynı).
    try {
      final iadeSatir =
          await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (iadeSatir.isNotEmpty) {
        BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
      }
      for (final item in kalemler) {
        final kalemSatir = await db.query('iade_kalem',
            where: 'iade_id = ? AND urun_id = ?',
            whereArgs: [iadeId, item.urun.id],
            limit: 1);
        if (kalemSatir.isNotEmpty) {
          BulutManager().upsert(
              'iade_kalem', Map<String, dynamic>.from(kalemSatir.first));
        }
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [item.urun.id], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        final stokSatir = await db.query('stok_hareket',
            where: 'referans_id = ? AND referans_turu = ? AND urun_id = ?',
            whereArgs: [iadeId, 'iade', item.urun.id],
            orderBy: 'id DESC',
            limit: 1);
        if (stokSatir.isNotEmpty) {
          BulutManager().upsert(
              'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        }
        // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): şube bazlı stok payı
        // (sube_urun) hiç güncellenmiyordu. İade = stok ARTIŞI, bu yüzden
        // negatif fark (subeStokPayiUygula'nın "ana stok yönü" kuralı).
        await _stokDepo.subeStokPayiUygula(item.urun.id!, -item.adet.toDouble());
      }
      if (toplamIade > 0) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade'],
            orderBy: 'id DESC',
            limit: 1);
        if (kasaSatir.isNotEmpty) {
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
      }
      if (cari != null && toplamIade > 0) {
        final cariHareketSatir = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi = 'İade'",
            whereArgs: [iadeId, cari.id],
            limit: 1);
        if (cariHareketSatir.isNotEmpty) {
          BulutManager().upsert(
              'cari_hareket', Map<String, dynamic>.from(cariHareketSatir.first));
        }
        final cariSatir =
            await db.query('cari', where: 'id = ?', whereArgs: [cari.id], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Toplu iade bulut bildirimi hatası: $e');
    }

    return (iadeId, fisNo, fiyatlar);
  }

  /// "Fiş No ile İade" sekmesindeki tek kalemlik iade akışı — bkz.
  /// iade_ekrani_fis.dart._fisKalemIade (taşındığı yer). Diğer iade
  /// akışlarından farklı olarak orijinal satışa (satisId) referans
  /// verdiği için, satışın lot tüketim ledger'ından (stok_hareket,
  /// FAZ 5 FEFO) hangi lot(lar)ın kullanıldığı bulunup iade miktarı
  /// AYNI lotlara geri eklenir (lot-farkındalıklı iade).
  ///
  /// Döner: (iadeId, fisNo, toplam) — çağıran taraf Onay Merkezi kaydı
  /// ve ekran içi görüntüleme için üçüne de ihtiyaç duyuyor.
  Future<(int, String, double)> fisKalemIadeKaydet({
    required int satisId,
    required int? cariId,
    required int urunId,
    required String urunAdi,
    required double birimFiyat,
    required double kalanMiktar,
    required double oncekiIadeMiktar,
    required String odemeYontemi,
    required int? kullaniciId,
    required String kullaniciAdi,
  }) async {
    final db = await Veritabani().db;
    final fisNo = await Veritabani()
        .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);
    final toplam = birimFiyat * kalanMiktar;
    final now = DateTime.now().toIso8601String();
    late final int iadeId;
    final guncellenenLotIdleri = <int>{};
    final stokHareketGidleri = <String>[];

    await db.transaction((txn) async {
      // 🔴 ÇİFT İADE KORUMASI (derin analiz 2026-10-07): "daha önce iade
      // edilen" miktar ekranda fiş arandığı an bir kez okunup bellekte
      // tutuluyordu; başka kasadan senkronla gelen ya da kayıt sürerken
      // ikinci kez başlatılan bir iade aynı kalemi İKİ KEZ iade edebiliyordu
      // (çift para + çift stok girişi). Sınır artık yazmayla aynı
      // transaction'da, veritabanının güncel hâlinden yeniden hesaplanır.
      final iadeEdilebilir =
          await _iadeEdilebilirMiktarTxn(txn, satisId: satisId, urunId: urunId);
      if (kalanMiktar > iadeEdilebilir + 0.0005) {
        throw IadeMiktariAsildiHatasi(urunAdi: urunAdi, iadeEdilebilir: iadeEdilebilir);
      }

      final iadeSatiri = {
        'global_id': const Uuid().v4(),
        'satis_id': satisId,
        'cari_id': cariId,
        'fis_no': fisNo,
        'tarih': now,
        'toplam_tutar': toplam,
        'iade_nedeni': 'Fiş iadesi',
        'durum': 'tamamlandi',
        'kasiyer_id': kullaniciId,
      };
      iadeId = await txn.insert('iade', iadeSatiri);
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'iade', veri: {...iadeSatiri, 'id': iadeId});

      final kalemSatiri = {
        'global_id': const Uuid().v4(),
        'iade_id': iadeId,
        'urun_id': urunId,
        'urun_adi': urunAdi,
        'miktar': kalanMiktar,
        'birim_fiyat': birimFiyat,
        'toplam': toplam,
      };
      final kalemId = await txn.insert('iade_kalem', kalemSatiri);
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'iade_kalem', veri: {...kalemSatiri, 'id': kalemId});

      final urunRows = await txn.query('urunler',
          columns: ['stok', 'lot_takibi'],
          where: 'id = ?', whereArgs: [urunId]);
      if (urunRows.isNotEmpty) {
        final onceki = (urunRows.first['stok'] as num).toDouble();
        final lotTakibi = (urunRows.first['lot_takibi'] as int? ?? 0) == 1;

        // (lotId veya null, miktar) — lot_takibi=0 ürünlerde davranış
        // BİREBİR eskisiyle aynı: tek satır, lot_id yok.
        final dagilim = <MapEntry<int?, double>>[];
        if (lotTakibi) {
          final tuketimSatirlari = await txn.query('stok_hareket',
              where: 'referans_id = ? AND referans_turu = ? AND urun_id = ?',
              whereArgs: [satisId, 'satis', urunId],
              orderBy: 'id ASC');
          // Daha önce bu üründen kısmen iade edilmiş olabilir — ledger'da
          // o kadarlık kısmı zaten "geri eklenmiş" sayıp atlıyoruz, aynı
          // lota mükerrer geri ekleme yapılmasın diye.
          var atla = oncekiIadeMiktar;
          var kalanDagitilacak = kalanMiktar;
          for (final satir in tuketimSatirlari) {
            if (kalanDagitilacak <= 0.005) break;
            var tSatirMiktar = (satir['miktar'] as num?)?.toDouble() ?? 0;
            if (atla > 0.005) {
              final atlanan = atla < tSatirMiktar ? atla : tSatirMiktar;
              tSatirMiktar -= atlanan;
              atla -= atlanan;
              if (tSatirMiktar <= 0.005) continue;
            }
            final buSatirdanIadeEdilecek =
                kalanDagitilacak < tSatirMiktar ? kalanDagitilacak : tSatirMiktar;
            if (buSatirdanIadeEdilecek <= 0.005) continue;
            dagilim
                .add(MapEntry(satir['lot_id'] as int?, buSatirdanIadeEdilecek));
            kalanDagitilacak -= buSatirdanIadeEdilecek;
          }
          // Orijinal tüketim ledger'ı eksik/yetersizse (ör. satış lot
          // özelliğinden ÖNCE yapılmış) kalanı lot bilgisi olmadan ekle —
          // iade ASLA engellenmez.
          if (kalanDagitilacak > 0.005) {
            dagilim.add(MapEntry(null, kalanDagitilacak));
          }
        } else {
          dagilim.add(MapEntry(null, kalanMiktar));
        }

        var su = onceki;
        for (final girdi in dagilim) {
          final miktar = girdi.value;
          final yeniSu = su + miktar;
          final gid = const Uuid().v4();
          final stokSatiri = {
            'global_id': gid,
            'urun_id': urunId,
            'hareket_turu': 'Iade Giris',
            'miktar': miktar,
            'onceki_stok': su,
            'sonraki_stok': yeniSu,
            'tarih': now,
            'referans_id': iadeId,
            'referans_turu': 'iade',
            'kullanici_id': kullaniciId,
            'aciklama': 'Fiş iadesi: $fisNo',
            if (girdi.key != null) 'lot_id': girdi.key,
          };
          final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
          stokHareketGidleri.add(gid);
          if (girdi.key != null) {
            await txn.rawUpdate(
                'UPDATE lot_seri SET miktar = miktar + ?, last_updated = ? WHERE id = ?',
                [miktar, now, girdi.key]);
            guncellenenLotIdleri.add(girdi.key!);
          }
          su = yeniSu;
        }
        await txn.update('urunler', {'stok': su},
            where: 'id = ?', whereArgs: [urunId]);
        final guncelUrunSatiri = await txn.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (guncelUrunSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'urunler',
              veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
        }
        for (final lotId in guncellenenLotIdleri) {
          final lotSatiri = await txn.query('lot_seri',
              where: 'id = ?', whereArgs: [lotId], limit: 1);
          if (lotSatiri.isNotEmpty) {
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'lot_seri', veri: Map<String, dynamic>.from(lotSatiri.first));
          }
        }
      }

      // Kasa — SADECE Nakit iade seçildiyse oluşturulur. Kart/Banka
      // iadesinde fiziksel kasadan hiç para çıkmıyor (POS'tan ayrıca
      // iade ediliyor), bu yüzden kasa_hareketleri'ne HİÇ yazılmaz.
      if (odemeYontemi == 'Nakit') {
        final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) - toplam;
        final kasaSatiri = {
          'global_id': const Uuid().v4(),
          'hareket_tipi': 'İade',
          'tutar': toplam,
          'bakiye_sonrasi': kasaBakiye,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'tarih': now,
          'sube_id': AktifSubeServisi().subeId,
          'aciklama': 'Fiş iadesi: $fisNo',
          'kullanici_id': kullaniciId,
        };
        final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
      }

      if (cariId != null) {
        // 🔴🔴 KRİTİK DÜZELTME (kullanıcı kararı, 2026-09-22 sabah) — bkz.
        // topluIadeKaydet'teki AYNI düzeltmenin gerekçesi: ödeme yöntemi
        // 'Cari' seçildiyse (para fiziksel verilmedi) bakiye GERÇEKTEN
        // düzeltilir; 'Nakit'/'Kart/Banka' seçildiyse (para zaten fiziksel
        // verildi) cari sadece takip amaçlı nötr kayıt alır.
        final cariRows = await txn
            .rawQuery('SELECT cari_tipi FROM cari WHERE id = ?', [cariId]);
        final cariTipiStr = cariRows.isNotEmpty
            ? (cariRows.first['cari_tipi'] as String? ?? '')
            : '';
        final isTedarikci = cariSafTedarikciMi(cariTipiStr);
        final gercekEtki = odemeYontemi == 'Cari';
        final cariHareketSatiri = {
          'global_id': const Uuid().v4(),
          'cari_id': cariId,
          'tarih': now,
          'fis_tipi': 'İade',
          'fis_id': iadeId,
          'fis_no': fisNo,
          'aciklama': gercekEtki
              ? 'Fiş iadesi: $fisNo — cari bakiyesine işlendi'
              : 'Fiş iadesi: $fisNo — bakiyeyi etkilemez',
          'borc': gercekEtki ? (isTedarikci ? toplam : 0) : toplam,
          'alacak': gercekEtki ? (isTedarikci ? 0 : toplam) : toplam,
          'odeme_turu': odemeYontemi,
          'kullanici': kullaniciAdi,
        };
        final cariHareketId = await txn.insert('cari_hareket', cariHareketSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'cari_hareket', veri: {...cariHareketSatiri, 'id': cariHareketId});
        // 'is_deleted = 0' filtresi — kanonik bakiye kuralı.
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = ROUND((SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0), 2) WHERE id=?',
            [cariId, cariId]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }
    });

    // Transaction başarıyla kapandıktan sonra buluta bildir (önce kalıcı
    // yaz, sonra bildir).
    try {
      final iadeSatir =
          await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (iadeSatir.isNotEmpty) {
        BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
      }
      final kalemSatir = await db.query('iade_kalem',
          where: 'iade_id = ? AND urun_id = ?',
          whereArgs: [iadeId, urunId],
          limit: 1);
      if (kalemSatir.isNotEmpty) {
        BulutManager().upsert(
            'iade_kalem', Map<String, dynamic>.from(kalemSatir.first));
      }
      final urunSatir =
          await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (urunSatir.isNotEmpty) {
        BulutManager()
            .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
      }
      // Lot-farkındalıklı iadede BİRDEN FAZLA stok_hareket satırı açılmış
      // olabilir (her tüketilen lot için ayrı) — hepsi tek tek bildirilir.
      for (final gid in stokHareketGidleri) {
        final s =
            await db.query('stok_hareket', where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(s.first));
        }
      }
      for (final lotId in guncellenenLotIdleri) {
        final l = await db.query('lot_seri', where: 'id = ?', whereArgs: [lotId], limit: 1);
        if (l.isNotEmpty) {
          BulutManager().upsert('lot_seri', Map<String, dynamic>.from(l.first));
        }
      }
      final kasaSatir = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?',
          whereArgs: [iadeId, 'iade'],
          orderBy: 'id DESC',
          limit: 1);
      if (kasaSatir.isNotEmpty) {
        BulutManager().upsert(
            'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
      }
      if (cariId != null) {
        final cariHareketSatir = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi = 'İade'",
            whereArgs: [iadeId, cariId],
            limit: 1);
        if (cariHareketSatir.isNotEmpty) {
          BulutManager().upsert(
              'cari_hareket', Map<String, dynamic>.from(cariHareketSatir.first));
        }
        final cariSatir =
            await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Fiş iadesi bulut bildirimi hatası: $e');
    }
    // Şube bazlı stok payı (FAZ 1 madde 1) bulut bildiriminden BAĞIMSIZ:
    // önceden aynı try içindeydi, bulut hatası şube stoğunu atlatıyordu.
    // Lotlara dağılmış olsa da ürün bazında tek artış (sube_urun lot izlemez).
    await _stokDepo.subeStokPayiUygula(urunId, -kalanMiktar);

    return (iadeId, fisNo, toplam);
  }

  /// Hızlı (fişsiz) iade için her ürünün iade birim fiyatı: o ürünün EN SON
  /// geçerli satış satırında müşterinin ödediği net birim fiyat (fiş
  /// iadesindeki kural: net_fiyat, yoksa birim_fiyat). [cariId] verilirse
  /// yalnız o müşterinin satışlarına bakılır. İptal edilmiş, silinmiş ve
  /// senkron-kopyası satışlar sayılmaz. Bulunamayan ürün varsa hata.
  static Future<Map<int, double>> _satisFiyatlariTxn(
      DatabaseExecutor ex, List<IadeKalemGirdi> kalemler, {int? cariId}) async {
    final fiyatlar = <int, double>{};
    final bulunamayan = <String>[];
    for (final k in kalemler) {
      final urunId = k.urun.id;
      if (urunId == null || fiyatlar.containsKey(urunId)) continue;
      final rows = await ex.rawQuery('''
        SELECT sk.net_fiyat, sk.birim_fiyat
          FROM satis_kalem sk
          JOIN satislar s ON s.id = sk.satis_id
         WHERE sk.urun_id = ?
           AND s.is_deleted = 0
           AND COALESCE(s.iptal, 0) = 0
           AND COALESCE(s.sync_cakisma_kopyasi, 0) = 0
           ${cariId != null ? 'AND s.cari_id = ?' : ''}
         ORDER BY s.tarih DESC, sk.id DESC
         LIMIT 1
      ''', [urunId, ?cariId]);
      if (rows.isEmpty) {
        bulunamayan.add(k.urun.urunAdi);
        continue;
      }
      final net = (rows.first['net_fiyat'] as num?)?.toDouble() ?? 0;
      final birim = (rows.first['birim_fiyat'] as num?)?.toDouble() ?? 0;
      fiyatlar[urunId] = net > 0 ? net : birim;
    }
    if (bulunamayan.isNotEmpty) {
      throw IadeSatisFiyatiBulunamadiHatasi(bulunamayan, cariyeGore: cariId != null);
    }
    return fiyatlar;
  }

  /// Hızlı iade onay penceresinde gösterilecek fiyatlar (kayıtla aynı kural).
  Future<Map<int, double>> hizliIadeFiyatlari(List<IadeKalemGirdi> kalemler,
          {int? cariId}) async =>
      _satisFiyatlariTxn(await Veritabani().db, kalemler, cariId: cariId);

  /// Satışta bu üründen satılan toplam miktar − iptal/silinmemiş iadelerde
  /// iade edilen toplam (ürün fişte birden fazla satırdaysa hepsi toplanır).
  /// [IadeDeposu.fisIadeliMiktarlariGetir] ile aynı iade tanımı.
  static Future<double> _iadeEdilebilirMiktarTxn(DatabaseExecutor txn,
      {required int satisId, required int urunId}) async {
    final rows = await txn.rawQuery('''
      SELECT
        (SELECT COALESCE(SUM(miktar), 0) FROM satis_kalem
          WHERE satis_id = ? AND urun_id = ?)
        -
        (SELECT COALESCE(SUM(ik.miktar), 0)
           FROM iade_kalem ik JOIN iade i ON ik.iade_id = i.id
          WHERE i.satis_id = ? AND ik.urun_id = ?
            AND COALESCE(i.durum, '') != 'iptal' AND i.deleted_at IS NULL) AS kalan
    ''', [satisId, urunId, satisId, urunId]);
    return (rows.first['kalan'] as num?)?.toDouble() ?? 0;
  }
}
