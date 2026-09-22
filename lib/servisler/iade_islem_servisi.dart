// lib/servisler/iade_islem_servisi.dart
//
// İade ekranlarının (iade_ekrani.dart + part dosyaları) db.transaction()
// mantığını SCREEN→SERVICE→REPOSITORY mimarisine taşıyan servis. Her
// metod, taşındığı ekranın orijinal mantığını davranış olarak birebir
// korur — sadece sorumluluk UI katmanından buraya kaydırılmıştır.
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../depolar/kasa_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../modeller/urun_model.dart';
import '../modeller/cari_model.dart';
import '../servisler/aktif_sube_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../veri/database/veritabani.dart';

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
  /// Döner: (iadeId, fisNo) — çağıran taraf ekran içi görüntüleme listesi
  /// için fişNo'ya ihtiyaç duyuyor.
  Future<(int, String)> topluIadeKaydet({
    required List<IadeKalemGirdi> kalemler,
    required String odemeYontemi,
    required int? kullaniciId,
    required String kullaniciAdi,
    CariModel? cari,
  }) async {
    final db = await Veritabani().db;
    final fisNo = await Veritabani()
        .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);
    final iadeGlobalId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final toplamIade =
        kalemler.fold<double>(0.0, (s, i) => s + i.adet * i.urun.satisFiyati);
    late final int iadeId;

    await db.transaction((txn) async {
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
        final fiyat = item.urun.satisFiyati;
        final toplam = item.adet * fiyat;

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
              'urunler', {'stok': onceki + item.adet, 'last_updated': now},
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
        final isTedarikci = (cari.cariTipi).contains('edarik') ||
            (cari.cariTipi).contains('upplier');
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
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
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

    return (iadeId, fisNo);
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
        await txn.update('urunler', {'stok': su, 'last_updated': now},
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
        final isTedarikci =
            cariTipiStr.contains('edarik') || cariTipiStr.contains('upplier');
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
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
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
      // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): şube bazlı stok payı hiç
      // güncellenmiyordu. Lotlara dağılmış olsa da toplam ürün bazında
      // TEK kalemMiktar artışı (sube_urun lot izlemez).
      await _stokDepo.subeStokPayiUygula(urunId, -kalanMiktar);
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

    return (iadeId, fisNo, toplam);
  }

  /// "İade Geçmişi" sekmesinden bir iade kalemini silme/iptal etme —
  /// bkz. iade_ekrani_gecmis.dart._oturumIadeSil (taşındığı yer). Stok
  /// geri alınır (İade İptali stok_hareket kaydıyla), iade 'iptal'
  /// durumuna işaretlenir (hard-delete yok), varsa kasa/cari ters
  /// çevrilir.
  Future<void> oturumIadeSil({
    required int? iadeId,
    required int? urunId,
    required double miktar,
    required double toplam,
    required int? cariId,
    String? fisNo,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    String? kasaGid;

    await db.transaction((txn) async {
      if (urunId != null && miktar > 0) {
        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
        if (urunRows.isNotEmpty) {
          final onceki = (urunRows.first['stok'] as num).toDouble();
          final sonraki = onceki - miktar;
          await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
              where: 'id = ?', whereArgs: [urunId]);
          final stokSatiri = {
            'global_id': const Uuid().v4(),
            'urun_id': urunId,
            'hareket_turu': 'İade İptali',
            'miktar': miktar,
            'onceki_stok': onceki,
            'sonraki_stok': sonraki,
            'tarih': now,
            'referans_id': iadeId,
            'referans_turu': 'iade_iptal',
          };
          final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
          final guncelUrunSatiri = await txn.query('urunler',
              where: 'id = ?', whereArgs: [urunId], limit: 1);
          if (guncelUrunSatiri.isNotEmpty) {
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'urunler',
                veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
          }
        }
      }
      if (iadeId != null) {
        await txn.update('iade', {'durum': 'iptal', 'last_updated': now},
            where: 'id = ?', whereArgs: [iadeId]);
        final guncelIadeSatiri = await txn.query('iade',
            where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (guncelIadeSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
        }
      }
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 sabah —
      // gecmisFisIadeSil'de zaten düzeltilmiş AYNI hata sınıfı): burası
      // ÖNCEDEN [toplam] parametresine bakıp KOŞULSUZ bir "Iade Iptali"
      // (nakit GİRİŞ) kasa kaydı ekliyordu — orijinal iade GERÇEKTEN
      // nakit olarak mı verilmişti (sadece odemeYontemi=='Nakit' iken
      // kasa satırı yazılır) hiç kontrol edilmiyordu. Kart/Banka veya
      // Cari'ye işlenmiş bir iade silinince HİÇ VAR OLMAMIŞ bir nakit
      // giriş kaydı oluşuyor, kasa mutabakatını bozuyordu. Artık gerçekten
      // yazılmış kasa_hareketleri satırı (varsa) sorgulanıp SADECE o
      // satırın GERÇEK tutarıyla tersine çevriliyor.
      if (iadeId != null) {
        final orijinalKasaSatirlari = await txn.query('kasa_hareketleri',
            where: 'referans_id = ? AND referans_turu = ? AND deleted_at IS NULL',
            whereArgs: [iadeId, 'iade']);
        for (final k in orijinalKasaSatirlari) {
          final kasaTutar = (k['tutar'] as num?)?.toDouble() ?? 0;
          if (kasaTutar <= 0) continue;
          kasaGid = const Uuid().v4();
          final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) + kasaTutar;
          final kasaSatiri = {
            'global_id': kasaGid,
            'hareket_tipi': 'Iade Iptali',
            'tutar': kasaTutar,
            'bakiye_sonrasi': kasaBakiye,
            'referans_id': iadeId,
            'referans_turu': 'iade_iptal',
            'tarih': now,
            'sube_id': AktifSubeServisi().subeId,
            'aciklama': 'İade silindi: $fisNo',
          };
          final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
        }
      }
      // Bu DELETE (rawUpdate soft-delete) fis_tipi ile de sınırlı —
      // 'iade' ve 'satislar' tablolarının BAĞIMSIZ, tesadüfen aynı ID'yi
      // üretebilen sayaçları yüzünden fis_tipi kontrolsüz bir SATIŞIN
      // cari_hareket kaydını yanlışlıkla silebilirdi.
      if (cariId != null) {
        await txn.rawUpdate(
            "UPDATE cari_hareket SET is_deleted = 1, last_updated = ? WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            [now, iadeId, cariId]);
        final etkilenenCariHareketler = await txn.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId]);
        for (final c in etkilenenCariHareketler) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket', veri: Map<String, dynamic>.from(c));
        }
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0) WHERE id = ?',
            [cariId, cariId]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }
    });

    try {
      if (iadeId != null) {
        final iadeSatir =
            await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (iadeSatir.isNotEmpty) {
          BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
        }
      }
      if (urunId != null) {
        final urunSatir =
            await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        final stokSatir = await db.query('stok_hareket',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade_iptal'],
            orderBy: 'id DESC',
            limit: 1);
        if (stokSatir.isNotEmpty) {
          BulutManager()
              .upsert('stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        }
        // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): iade iptali = stok
        // AZALIŞI (pozitif fark — subeStokPayiUygula'nın beklediği yön).
        await _stokDepo.subeStokPayiUygula(urunId, miktar);
      }
      if (kasaGid != null) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'global_id = ?', whereArgs: [kasaGid], limit: 1);
        if (kasaSatir.isNotEmpty) {
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
      }
      if (cariId != null) {
        final cariHareketSatirlar = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId]);
        for (final c in cariHareketSatirlar) {
          BulutManager().upsert('cari_hareket', Map<String, dynamic>.from(c));
        }
        final cariSatir =
            await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('İade silme bulut bildirimi hatası: $e');
    }
  }

  /// "İade Geçmişi" sekmesinde mevcut bir iade kaleminin miktar/fiyat/
  /// iskonto/açıklamasını düzenleme — bkz.
  /// iade_ekrani_gecmis.dart._oturumIadeDuzenle (taşındığı yer). Stok
  /// farkı (yeni-eski miktar) uygulanır, iade+iade_kalem güncellenir,
  /// kasa farkı (varsa) ayrı bir "İade Düzeltme" hareketiyle işlenir,
  /// cari eski hareketleri soft-delete edilip yeni toplamla tek hareket
  /// yazılır.
  Future<void> oturumIadeDuzenle({
    required int? iadeId,
    required int? urunId,
    required int? cariId,
    required String? fisNo,
    required String urunAdi,
    required double eskiMiktar,
    required double eskiToplam,
    required double yeniMiktar,
    required double yeniFiyat,
    required double yeniToplam,
    required String yeniAciklama,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    final fark = yeniMiktar - eskiMiktar;
    String? kasaGid;

    await db.transaction((txn) async {
      if (urunId != null && fark != 0) {
        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
        if (urunRows.isNotEmpty) {
          final onceki = (urunRows.first['stok'] as num).toDouble();
          final sonraki = onceki + fark;
          await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
              where: 'id = ?', whereArgs: [urunId]);
          final stokSatiri = {
            'global_id': const Uuid().v4(),
            'urun_id': urunId,
            'hareket_turu': 'İade Düzeltme',
            'miktar': fark.abs(),
            'onceki_stok': onceki,
            'sonraki_stok': sonraki,
            'tarih': now,
            'referans_id': iadeId,
            'referans_turu': 'iade_duzenle',
            'aciklama': 'İade miktarı değiştirildi',
          };
          final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
          final guncelUrunSatiri = await txn.query('urunler',
              where: 'id = ?', whereArgs: [urunId], limit: 1);
          if (guncelUrunSatiri.isNotEmpty) {
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'urunler',
                veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
          }
        }
      }
      if (iadeId != null) {
        await txn.update(
            'iade',
            {
              'toplam_tutar': yeniToplam,
              'iade_nedeni': yeniAciklama,
              'last_updated': now
            },
            where: 'id = ?',
            whereArgs: [iadeId]);
        await txn.rawUpdate(
            'UPDATE iade_kalem SET miktar=?, birim_fiyat=?, toplam=?, last_updated=? WHERE iade_id=?',
            [yeniMiktar, yeniFiyat, yeniToplam, now, iadeId]);
        final guncelIadeSatiri = await txn.query('iade',
            where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (guncelIadeSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
        }
        final guncelKalemSatirlar = await txn.query('iade_kalem',
            where: 'iade_id = ?', whereArgs: [iadeId]);
        for (final k in guncelKalemSatirlar) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'iade_kalem', veri: Map<String, dynamic>.from(k));
        }
      }
      final tutarFark = yeniToplam - eskiToplam;
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 sabah): burası
      // ÖNCEDEN tutarFark'a bakıp KOŞULSUZ kasa düzeltmesi yazıyordu —
      // orijinal iade GERÇEKTEN nakit olarak mı verilmişti hiç kontrol
      // edilmiyordu (bkz. oturumIadeSil'deki AYNI hata sınıfının
      // düzeltmesi). Kart/Banka veya Cari'ye işlenmiş bir iade kalemi
      // düzenlenince kasada hiç var olmamış bir hareket oluşuyordu.
      if (tutarFark.abs() > 0.01 && iadeId != null) {
        final orijinalKasaVarMi = await txn.query('kasa_hareketleri',
            where:
                "referans_id = ? AND referans_turu = 'iade' AND deleted_at IS NULL",
            whereArgs: [iadeId], limit: 1);
        if (orijinalKasaVarMi.isNotEmpty) {
          final oncekiBakiye = await _kasaDepo.sonBakiyeTxn(txn);
          final yeniBakiye = oncekiBakiye + tutarFark;
          kasaGid = const Uuid().v4();
          final kasaSatiri = {
            'global_id': kasaGid,
            'hareket_tipi': 'İade Düzeltme',
            'tutar': tutarFark,
            'bakiye_sonrasi': yeniBakiye,
            'referans_id': iadeId,
            'referans_turu': 'iade_duzeltme',
            'tarih': now,
            'sube_id': AktifSubeServisi().subeId,
            'aciklama': 'İade düzeltme: $fisNo',
          };
          final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
        }
      }
      if (cariId != null && iadeId != null) {
        final cariRows = await txn
            .rawQuery('SELECT cari_tipi FROM cari WHERE id = ?', [cariId]);
        final cariTipiDuz = cariRows.isNotEmpty
            ? (cariRows.first['cari_tipi'] as String? ?? '')
            : '';
        final isTedarikciDuz =
            cariTipiDuz.contains('edarik') || cariTipiDuz.contains('upplier');

        // Bu iade kalemi GERÇEK cari etkisiyle mi (Veresiye/'Cari' ödeme
        // yöntemi) yoksa NÖTR (Nakit/Kart, sadece takip) mi yazılmıştı?
        // borc==alacak ise nötrdü — düzenlemede de nötr kalmalı, aksi
        // halde para fiziksel verilmişken bakiye de düşer (çift iade).
        final eskiSatir = await txn.rawQuery(
            "SELECT borc, alacak FROM cari_hareket WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi') AND is_deleted = 0",
            [iadeId, cariId]);
        final eskiBorcD =
            eskiSatir.isNotEmpty ? (eskiSatir.first['borc'] as num?)?.toDouble() ?? 0 : 0;
        final eskiAlacakD = eskiSatir.isNotEmpty
            ? (eskiSatir.first['alacak'] as num?)?.toDouble() ?? 0
            : 0;
        final gercekEtki = eskiSatir.isNotEmpty && eskiBorcD != eskiAlacakD;

        await txn.rawUpdate(
            "UPDATE cari_hareket SET is_deleted = 1, last_updated = ? WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            [now, iadeId, cariId]);
        if (yeniToplam > 0) {
          final cariHareketSatiri = {
            'global_id': const Uuid().v4(),
            'cari_id': cariId,
            'tarih': now,
            'fis_tipi': isTedarikciDuz ? 'Alım İadesi' : 'İade',
            'fis_id': iadeId,
            'fis_no': fisNo,
            'aciklama': gercekEtki
                ? '$urunAdi - $fisNo — cari bakiyesine işlendi'
                : '$urunAdi - $fisNo — bakiyeyi etkilemez',
            'borc': gercekEtki ? (isTedarikciDuz ? yeniToplam : 0) : yeniToplam,
            'alacak': gercekEtki ? (isTedarikciDuz ? 0 : yeniToplam) : yeniToplam,
            'odeme_turu': gercekEtki ? 'Cari' : 'Nakit',
          };
          final cariHareketId = await txn.insert('cari_hareket', cariHareketSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket', veri: {...cariHareketSatiri, 'id': cariHareketId});
        }
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0) WHERE id = ?',
            [cariId, cariId]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }
    });

    try {
      if (iadeId != null) {
        final iadeSatir =
            await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (iadeSatir.isNotEmpty) {
          BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
        }
        final kalemSatirlar =
            await db.query('iade_kalem', where: 'iade_id = ?', whereArgs: [iadeId]);
        for (final k in kalemSatirlar) {
          BulutManager().upsert('iade_kalem', Map<String, dynamic>.from(k));
        }
      }
      if (urunId != null) {
        final urunSatir =
            await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        final stokSatir = await db.query('stok_hareket',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade_duzenle'],
            orderBy: 'id DESC',
            limit: 1);
        if (stokSatir.isNotEmpty) {
          BulutManager()
              .upsert('stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        }
        // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): şube payı hiç
        // güncellenmiyordu. fark>0 = ana stok ARTTI, bu yüzden ters işaret.
        await _stokDepo.subeStokPayiUygula(urunId, -fark);
      }
      if (kasaGid != null) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'global_id = ?', whereArgs: [kasaGid], limit: 1);
        if (kasaSatir.isNotEmpty) {
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
      }
      if (cariId != null) {
        final cariHareketSatirlar = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId]);
        for (final c in cariHareketSatirlar) {
          BulutManager().upsert('cari_hareket', Map<String, dynamic>.from(c));
        }
        final cariSatir =
            await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('İade düzenleme bulut bildirimi hatası: $e');
    }
  }

  /// "İade Geçmişi" düzenleme modunda mevcut bir iadeye YENİ kalem ekleme
  /// — bkz. iade_ekrani_gecmis.dart._duzenlemeModu_kalemEkle (taşındığı
  /// yer). Stok geri eklenir, iade_kalem (aynı ürün varsa güncellenir,
  /// yoksa eklenir), iade.toplam_tutar kalemlerden yeniden hesaplanır,
  /// cari hareketi (fis_id bazlı tek kayıt — varsa güncellenir, yoksa
  /// eklenir) ve kasa hareketi (İade) TEK transaction içinde yazılır.
  Future<void> duzenlemeModuKalemEkle({
    required int iadeId,
    required int urunId,
    required String urunAdi,
    required double miktar,
    required double fiyat,
    required double toplam,
    required String? fisNo,
    required int? cariId,
    required String? cariTipi,
    required int? kullaniciId,
    required String kullaniciAdi,
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 sabah) — bkz.
    // topluIadeKaydet'teki AYNI düzeltmenin gerekçesi. Bu fonksiyon hiç
    // kasa hareketi yazmaz (İade Geçmişi'nde mevcut/kapanmış bir fişe
    // ek kalem işlemidir, kasa tarafı bu turun BİLİNÇLİ OLARAK kapsamı
    // dışıdır) ama cari etkisini artık aynı 'Cari' ödeme yöntemi kuralına
    // göre gerçek/nötr olarak ayırt eder.
    required String odemeYontemi,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    late final int kalemId;

    await db.transaction((txn) async {
      // 1. Stok geri ekle
      final urunRows = await txn.query('urunler',
          columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
      if (urunRows.isNotEmpty) {
        final onceki = (urunRows.first['stok'] as num).toDouble();
        await txn.update('urunler', {'stok': onceki + miktar, 'last_updated': now},
            where: 'id = ?', whereArgs: [urunId]);
        final stokSatiri = {
          'global_id': const Uuid().v4(),
          'urun_id': urunId,
          'hareket_turu': 'Iade Giris',
          'miktar': miktar,
          'onceki_stok': onceki,
          'sonraki_stok': onceki + miktar,
          'tarih': now,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'kullanici_id': kullaniciId,
          'aciklama': 'İade ek kalem - $fisNo',
        };
        final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
        final guncelUrunSatiri = await txn.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (guncelUrunSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'urunler',
              veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
        }
      }

      // 2. iade_kalem: aynı ürün varsa güncelle, yoksa ekle
      final mevcutKalem2 = await txn.rawQuery(
          'SELECT id, miktar, toplam FROM iade_kalem WHERE iade_id=? AND urun_id=?',
          [iadeId, urunId]);
      if (mevcutKalem2.isNotEmpty) {
        final k = mevcutKalem2.first;
        kalemId = k['id'] as int;
        await txn.rawUpdate(
            'UPDATE iade_kalem SET miktar=?, toplam=?, last_updated=? WHERE id=?', [
          ((k['miktar'] as num?)?.toDouble() ?? 0) + miktar,
          ((k['toplam'] as num?)?.toDouble() ?? 0) + toplam,
          now,
          kalemId
        ]);
      } else {
        kalemId = await txn.insert('iade_kalem', {
          'global_id': const Uuid().v4(),
          'iade_id': iadeId,
          'urun_id': urunId,
          'urun_adi': urunAdi,
          'miktar': miktar,
          'birim_fiyat': fiyat,
          'toplam': toplam,
        });
      }
      final guncelKalemSatiri = await txn.query('iade_kalem',
          where: 'id = ?', whereArgs: [kalemId], limit: 1);
      if (guncelKalemSatiri.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade_kalem', veri: Map<String, dynamic>.from(guncelKalemSatiri.first));
      }

      // 3. İade toplam_tutar güncelle
      final mevcutToplam = (await txn.rawQuery(
              'SELECT COALESCE(SUM(toplam),0) as t FROM iade_kalem WHERE iade_id=?',
              [iadeId]))
          .first['t'] as num? ??
          0;
      await txn.update('iade', {'toplam_tutar': mevcutToplam.toDouble(), 'last_updated': now},
          where: 'id = ?', whereArgs: [iadeId]);
      final guncelIadeSatiri = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelIadeSatiri.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
      }

      // 4. Cari: fis_id bazlı tek kayıt - mevcut varsa güncelle, yoksa ekle
      //
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 sabah): 'Cari'
      // ödeme yöntemi seçilirse (para fiziksel verilmedi) bakiye GERÇEKTEN
      // düzeltilir; 'Nakit'/'Kart/Banka' seçilirse (para zaten fiziksel
      // verildi) cari sadece takip amaçlı nötr kayıt alır — bkz.
      // topluIadeKaydet'teki AYNI kuralın gerekçesi.
      if (cariId != null) {
        final isTedarikci =
            (cariTipi ?? 'Müşteri').contains('edarik') || (cariTipi ?? '').contains('upplier');
        final gercekEtki = odemeYontemi == 'Cari';
        final ekBorc = gercekEtki ? (isTedarikci ? toplam : 0) : toplam;
        final ekAlacak = gercekEtki ? (isTedarikci ? 0 : toplam) : toplam;
        final mevcut = await txn.rawQuery(
            "SELECT id, alacak, borc FROM cari_hareket WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            [iadeId, cariId]);
        if (mevcut.isNotEmpty) {
          final eskiAlacak = (mevcut.first['alacak'] as num?)?.toDouble() ?? 0;
          final eskiBorc = (mevcut.first['borc'] as num?)?.toDouble() ?? 0;
          await txn.rawUpdate(
              "UPDATE cari_hareket SET alacak = ?, borc = ?, last_updated = ? WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
              [
                eskiAlacak + ekAlacak,
                eskiBorc + ekBorc,
                now,
                iadeId,
                cariId,
              ]);
        } else {
          await txn.insert('cari_hareket', {
            'global_id': const Uuid().v4(),
            'cari_id': cariId,
            'tarih': now,
            'fis_tipi': isTedarikci ? 'Alım İadesi' : 'İade',
            'fis_id': iadeId,
            'fis_no': fisNo,
            'aciklama': gercekEtki
                ? '${fisNo ?? ''} — cari bakiyesine işlendi'
                : '${fisNo ?? ''} — bakiyeyi etkilemez',
            'borc': ekBorc,
            'alacak': ekAlacak,
            'odeme_turu': odemeYontemi,
            'kullanici': kullaniciAdi,
          });
        }
        final guncelCariHareketSatirlar = await txn.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId]);
        for (final c in guncelCariHareketSatirlar) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket', veri: Map<String, dynamic>.from(c));
        }
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0) WHERE id = ?',
            [cariId, cariId]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }

      // 5. Kasa hareketi
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
        'aciklama': 'İade: $fisNo - $urunAdi',
        'kullanici_id': kullaniciId,
      };
      final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
    });

    try {
      final kalemSatir =
          await db.query('iade_kalem', where: 'id = ?', whereArgs: [kalemId], limit: 1);
      if (kalemSatir.isNotEmpty) {
        BulutManager()
            .upsert('iade_kalem', Map<String, dynamic>.from(kalemSatir.first));
      }
      final iadeSatir =
          await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (iadeSatir.isNotEmpty) {
        BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
      }
      final urunSatir =
          await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (urunSatir.isNotEmpty) {
        BulutManager().upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
      }
      final stokSatir = await db.query('stok_hareket',
          where: 'referans_id = ? AND referans_turu = ? AND urun_id = ?',
          whereArgs: [iadeId, 'iade', urunId],
          orderBy: 'id DESC',
          limit: 1);
      if (stokSatir.isNotEmpty) {
        BulutManager()
            .upsert('stok_hareket', Map<String, dynamic>.from(stokSatir.first));
      }
      // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): ek kalem = stok ARTIŞI.
      await _stokDepo.subeStokPayiUygula(urunId, -miktar);
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
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
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
      if (kDebugMode) debugPrint('İade ek kalem bulut bildirimi hatası: $e');
    }
  }

  /// "İade Geçmişi" sekmesinden TÜM fişi (bir iade kaydının tüm
  /// kalemleri) silme/iptal etme — bkz. iade_ekrani_gecmis.dart.
  /// _gecmisIadeSil (taşındığı yer). Her kalem için stok geri alınır,
  /// GERÇEK yazılmış kasa satırı (varsa) tersine çevrilir, cari
  /// hareketleri soft-delete edilir, iade 'iptal' durumuna işaretlenir.
  ///
  /// [kalemler] çağıranın önceden çektiği ham `iade_kalem` satırları
  /// (en az 'urun_id' ve 'miktar' anahtarlarını içermeli).
  ///
  /// 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 — Satış/Alım
  /// silmede bulunan AYNI hata sınıfı): kasa reversal'ı ÖNCEDEN [toplamTutar]
  /// parametresine bakıp KOŞULSUZ bir "Iade Iptali" (nakit GİRİŞ) kasa
  /// kaydı ekliyordu — orijinal iade GERÇEKTEN nakit olarak mı verilmişti
  /// (topluIadeKaydet/fisKalemIadeKaydet/manuelKalemEkle SADECE
  /// nakitIade==true iken kasa satırı yazar) hiç kontrol edilmiyordu.
  /// Kart/Banka veya Cari'ye işlenmiş bir iade fişi silinince, HİÇ VAR
  /// OLMAMIŞ bir nakit giriş kaydı OLUŞTURULUYOR, kasa mutabakatını
  /// bozuyordu. Artık tahmin yok: bu iadenin GERÇEKTEN yazdığı
  /// kasa_hareketleri satırı (varsa) sorgulanıp SADECE o satırın GERÇEK
  /// tutarıyla tersine çevriliyor.
  Future<void> gecmisFisIadeSil({
    required int iadeId,
    required List<Map<String, dynamic>> kalemler,
    required double toplamTutar,
    required int? cariId,
    String? fisNo,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    String? kasaGid;

    await db.transaction((txn) async {
      // 🆕 İkinci bir giriş noktası eklendi (cari_hareket_ekrani.dart,
      // 2026-09-22) — aynı iade artık İade Geçmişi'nden VEYA Cari
      // Hareketler'den silinebiliyor. Zaten iptal edilmiş bir fişi
      // TEKRAR işlemek stoğu/kasayı İKİNCİ KEZ tersine çevirirdi
      // (AlimIslemServisi.sil()'deki AYNI korumayla hizalandı).
      final guncelIade = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelIade.isNotEmpty && guncelIade.first['durum'] == 'iptal') {
        throw Exception('Bu iade zaten iptal edilmiş.');
      }
      for (final k in kalemler) {
        final urunId = k['urun_id'] as int?;
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        if (urunId == null || miktar <= 0) continue;
        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
        if (urunRows.isEmpty) continue;
        final onceki = (urunRows.first['stok'] as num).toDouble();
        final sonraki = onceki - miktar;
        await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
            where: 'id = ?', whereArgs: [urunId]);
        final stokSatiri = {
          'global_id': const Uuid().v4(),
          'urun_id': urunId,
          'hareket_turu': 'İade İptali',
          'miktar': miktar,
          'onceki_stok': onceki,
          'sonraki_stok': sonraki,
          'tarih': now,
          'referans_id': iadeId,
          'referans_turu': 'iade_iptal',
        };
        final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
        final guncelUrunSatiri = await txn.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (guncelUrunSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'urunler',
              veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
        }
      }

      final orijinalKasaSatirlari = await txn.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ? AND deleted_at IS NULL',
          whereArgs: [iadeId, 'iade']);
      for (final k in orijinalKasaSatirlari) {
        final kasaTutar = (k['tutar'] as num?)?.toDouble() ?? 0;
        if (kasaTutar <= 0) continue;
        kasaGid = const Uuid().v4();
        final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) + kasaTutar;
        final kasaSatiri = {
          'global_id': kasaGid,
          'hareket_tipi': 'Iade Iptali',
          'tutar': kasaTutar, // Pozitif: kasa artar (iade geri alındı)
          'bakiye_sonrasi': kasaBakiye,
          'referans_id': iadeId,
          'referans_turu': 'iade_iptal',
          'tarih': now,
          // 🔴 Derin analizde bulundu: sube_id eksikti (bkz. oturumIadeSil'deki
          // aynı düzeltmenin gerekçesi).
          'sube_id': AktifSubeServisi().subeId,
          'aciklama': 'Iade silindi: $fisNo',
        };
        final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
      }

      if (cariId != null) {
        await txn.rawUpdate(
            "UPDATE cari_hareket SET is_deleted = 1, last_updated = ? WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            [now, iadeId, cariId]);
        final etkilenenCariHareketler = await txn.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId]);
        for (final c in etkilenenCariHareketler) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket', veri: Map<String, dynamic>.from(c));
        }
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0) WHERE id = ?',
            [cariId, cariId]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }

      await txn.update('iade', {'durum': 'iptal', 'last_updated': now},
          where: 'id = ?', whereArgs: [iadeId]);
      final guncelIadeSatiri = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelIadeSatiri.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
      }
    });

    try {
      final iadeSatir =
          await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (iadeSatir.isNotEmpty) {
        BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
      }
      for (final k in kalemler) {
        final urunId = k['urun_id'] as int?;
        if (urunId == null) continue;
        final urunSatir =
            await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): tüm fiş iptali = her
        // kalem için stok AZALIŞI (pozitif fark).
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        if (miktar > 0) {
          await _stokDepo.subeStokPayiUygula(urunId, miktar);
        }
      }
      final stokSatirlar = await db.query('stok_hareket',
          where: 'referans_id = ? AND referans_turu = ?',
          whereArgs: [iadeId, 'iade_iptal']);
      for (final s in stokSatirlar) {
        BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(s));
      }
      if (kasaGid != null) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'global_id = ?', whereArgs: [kasaGid], limit: 1);
        if (kasaSatir.isNotEmpty) {
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
      }
      if (cariId != null) {
        final cariHareketSatirlar = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId]);
        for (final c in cariHareketSatirlar) {
          BulutManager().upsert('cari_hareket', Map<String, dynamic>.from(c));
        }
        final cariSatir =
            await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Fiş silme bulut bildirimi hatası: $e');
    }
  }

  /// "Manuel" (ürün seç + miktar/fiyat gir) sekmesindeki kaydetme akışı —
  /// bkz. iade_ekrani.dart._kaydet (taşındığı yer, sadece "yeni oturum
  /// başlat / mevcut oturuma ekle" dalı — düzenleme modu dalı zaten
  /// IadeIslemServisi.duzenlemeModuKalemEkle'yi kullanıyor). Bir oturumda
  /// aynı ürün tekrar eklenirse iade_kalem satırı TOPLANARAK güncellenir
  /// (yeni satır açılmaz). iade + kalem + stok + (varsa) kasa + (varsa)
  /// cari TEK transaction içinde.
  ///
  /// Döner: yeni oluşturulan veya güncellenen iadeId — [oturumIadeId]
  /// null ise çağıran taraf bunu oturumun kalıcı iade id'si olarak
  /// saklamalı.
  Future<int> manuelKalemEkle({
    required int? oturumIadeId,
    required int? cariId,
    required String? cariTipi,
    required String fisNo,
    required int urunId,
    required String urunAdi,
    required double miktar,
    required double fiyat,
    required double toplam,
    required String neden,
    required String odemeYontemi,
    required int? kullaniciId,
    required String kullaniciAdi,
  }) async {
    final db = await Veritabani().db;
    final isTedarikci =
        (cariTipi ?? 'Müşteri').contains('edarik') || (cariTipi ?? '').contains('upplier');
    final now = DateTime.now().toIso8601String();
    int iadeId = oturumIadeId ?? 0;

    await db.transaction((txn) async {
      // 1. İade kaydı
      if (oturumIadeId != null) {
        await txn.rawUpdate(
            'UPDATE iade SET toplam_tutar = toplam_tutar + ?, iade_nedeni = ? WHERE id = ?',
            [toplam, neden, iadeId]);
      } else {
        iadeId = await txn.insert('iade', {
          'global_id': const Uuid().v4(),
          'cari_id': cariId,
          'fis_no': fisNo,
          'tarih': now,
          'toplam_tutar': toplam,
          'iade_nedeni': neden,
          'durum': 'tamamlandi',
          'kasiyer_id': kullaniciId,
        });
      }
      final guncelIadeSatiri = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelIadeSatiri.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
      }

      // 2. İade kalem
      final mevcutKalem = await txn.rawQuery(
          'SELECT id, miktar, toplam FROM iade_kalem WHERE iade_id=? AND urun_id=?',
          [iadeId, urunId]);
      if (mevcutKalem.isNotEmpty) {
        final k = mevcutKalem.first;
        await txn.rawUpdate('UPDATE iade_kalem SET miktar=?, toplam=? WHERE id=?', [
          ((k['miktar'] as num?)?.toDouble() ?? 0) + miktar,
          ((k['toplam'] as num?)?.toDouble() ?? 0) + toplam,
          k['id']
        ]);
      } else {
        await txn.insert('iade_kalem', {
          'global_id': const Uuid().v4(),
          'iade_id': iadeId,
          'urun_id': urunId,
          'urun_adi': urunAdi,
          'miktar': miktar,
          'birim_fiyat': fiyat,
          'toplam': toplam,
        });
      }
      final guncelKalemSatir = await txn.query('iade_kalem',
          where: 'iade_id = ? AND urun_id = ?',
          whereArgs: [iadeId, urunId], limit: 1);
      if (guncelKalemSatir.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade_kalem', veri: Map<String, dynamic>.from(guncelKalemSatir.first));
      }

      // 3. Stok geri ekle
      final urunRows = await txn.query('urunler',
          columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
      if (urunRows.isNotEmpty) {
        final onceki = (urunRows.first['stok'] as num).toDouble();
        await txn.update('urunler', {'stok': onceki + miktar},
            where: 'id = ?', whereArgs: [urunId]);
        final stokSatiri = {
          'global_id': const Uuid().v4(),
          'urun_id': urunId,
          'hareket_turu': 'Iade Giris',
          'miktar': miktar,
          'onceki_stok': onceki,
          'sonraki_stok': onceki + miktar,
          'tarih': now,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'kullanici_id': kullaniciId,
          'aciklama': 'Iade: $fisNo',
        };
        final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
        final guncelUrunSatiri = await txn.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (guncelUrunSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'urunler',
              veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
        }
      }

      // 4. Kasa — SADECE Nakit iade seçildiyse. KasaDeposu ile AYNI
      // güvenli bakiye sorgusu (deleted_at IS NULL + tarih DESC).
      if (odemeYontemi == 'Nakit') {
        final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) - toplam;
        final kasaSatiri = {
          'global_id': const Uuid().v4(),
          'hareket_tipi': 'Iade',
          'tutar': toplam,
          'bakiye_sonrasi': kasaBakiye,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'tarih': now,
          'sube_id': AktifSubeServisi().subeId,
          'aciklama': 'Iade: $fisNo - $urunAdi',
          'kullanici_id': kullaniciId,
        };
        final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
      }

      // 5. Cari — fis_tipi ile de kontrol edilir: 'iade' ve 'satislar'
      // tablolarının BAĞIMSIZ sayaçları tesadüfen aynı id'yi üretebilir.
      //
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı kararı, 2026-09-22 sabah) — bkz.
      // topluIadeKaydet'teki AYNI düzeltmenin gerekçesi: 'Cari' ödeme
      // yöntemi seçilirse (para fiziksel verilmedi) bakiye GERÇEKTEN
      // düzeltilir; 'Nakit'/'Kart/Banka' seçilirse (para zaten fiziksel
      // verildi) cari sadece takip amaçlı nötr kayıt alır. odemeYontemi
      // TEK seçimli dropdown olduğundan çift-iade riski yok.
      if (cariId != null) {
        final gercekEtki = odemeYontemi == 'Cari';
        final yeniBorc = gercekEtki ? (isTedarikci ? toplam : 0) : toplam;
        final yeniAlacak = gercekEtki ? (isTedarikci ? 0 : toplam) : toplam;
        final mevcut = await txn.rawQuery(
            "SELECT id, alacak, borc FROM cari_hareket WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            [iadeId, cariId]);
        if (mevcut.isNotEmpty) {
          final eskiAlacak = (mevcut.first['alacak'] as num?)?.toDouble() ?? 0;
          final eskiBorc = (mevcut.first['borc'] as num?)?.toDouble() ?? 0;
          await txn.rawUpdate(
              "UPDATE cari_hareket SET alacak=?, borc=? WHERE fis_id=? AND cari_id=? AND fis_tipi IN ('İade','Alım İadesi')",
              [eskiAlacak + yeniAlacak, eskiBorc + yeniBorc, iadeId, cariId]);
        } else {
          await txn.insert('cari_hareket', {
            'global_id': const Uuid().v4(),
            'cari_id': cariId,
            'tarih': now,
            'fis_tipi': isTedarikci ? 'Alım İadesi' : 'İade',
            'fis_id': iadeId,
            'fis_no': fisNo,
            'aciklama': gercekEtki
                ? '$fisNo — cari bakiyesine işlendi'
                : '$fisNo — bakiyeyi etkilemez',
            'borc': yeniBorc,
            'alacak': yeniAlacak,
            'odeme_turu': odemeYontemi,
            'kullanici': kullaniciAdi,
          });
        }
        final guncelCariHareketSatir = await txn.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId], limit: 1);
        if (guncelCariHareketSatir.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket',
              veri: Map<String, dynamic>.from(guncelCariHareketSatir.first));
        }
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
            [cariId, cariId]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }
    });

    // Transaction kapandıktan sonra buluta bildir — 7 farklı tablo
    // (iade, iade_kalem, urunler, stok_hareket, kasa_hareketleri,
    // cari_hareket, cari) değişebilir, her birinin EN SON değişen
    // satırı sorgulanıp bildirilir.
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
        BulutManager()
            .upsert('iade_kalem', Map<String, dynamic>.from(kalemSatir.first));
      }
      final urunSatir =
          await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (urunSatir.isNotEmpty) {
        BulutManager().upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
      }
      final stokSatir = await db.query('stok_hareket',
          where: 'referans_id = ? AND referans_turu = ?',
          whereArgs: [iadeId, 'iade'],
          orderBy: 'id DESC',
          limit: 1);
      if (stokSatir.isNotEmpty) {
        BulutManager()
            .upsert('stok_hareket', Map<String, dynamic>.from(stokSatir.first));
      }
      // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): manuel iade = stok ARTIŞI.
      await _stokDepo.subeStokPayiUygula(urunId, -miktar);
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
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
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
      if (kDebugMode) debugPrint('İade bulut bildirimi hatası: $e');
    }

    return iadeId;
  }
}
