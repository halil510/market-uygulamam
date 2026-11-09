// lib/servisler/alim_islem_servisi.dart
//
// Mal Alımı ekranının db.transaction() mantığını SCREEN→SERVICE→
// REPOSITORY mimarisine taşıyan servis. Davranış, önceden ekranın kendi
// _alimKaydet()'inde yürüttüğü mantıkla birebir aynıdır: alım fişi
// (yeni VEYA bekleyen bir siparişin teslim alınması) + kalemler + stok +
// (varsa) kasa/banka + (varsa) cari hareketi TEK transaction içinde,
// commit sonrası bulut senkronu.
import '../cekirdek/utils/para_utils.dart';
import '../depolar/cari_deposu.dart';
import '../depolar/kasa_deposu.dart';
import '../depolar/banka_hareket_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../depolar/urun_deposu.dart';
import '../modeller/kasa_hareket_model.dart';
import '../modeller/banka_hareket_model.dart';
import '../servisler/aktif_sube_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../veri/database/veritabani.dart';
import 'package:uuid/uuid.dart';

/// Bir alım kaleminin (ürün + miktar + alış fiyatı) DB yazımı için
/// gereken minimal bilgisi.
///
/// [lotNo]/[skt]: kullanıcıya soruldu — lot_takibi açık bir ürün alınınca
/// lot_seri kaydı HİÇ otomatik oluşturulmuyordu (P2 bulgusu), "alım
/// ekranına lot/SKT alanı ekle" seçildi. İkisi de OPSİYONEL: [lotNo]
/// boş/null bırakılırsa davranış birebir eskisi gibi kalır (lot'suz
/// stok artışı, kullanıcı isterse sonradan Lot/Seri ekranından elle
/// ekler) — hiçbir mevcut akış bozulmaz.
class AlimKalemGirdi {
  final int urunId;
  final double miktar;
  final double alisFiyat;
  final String? lotNo;
  final DateTime? skt;

  /// Alış KDV oranı (%). [alisFiyat] KDV HARİÇ birim fiyattır; kalem tutarı
  /// ve tedarikçiye borç/ödeme KDV DAHİL yazılır (tedarikçi KDV'yi de tahsil
  /// eder). 0 verilirse eski davranış (KDV'siz) korunur.
  final double kdvOran;
  const AlimKalemGirdi({
    required this.urunId,
    required this.miktar,
    required this.alisFiyat,
    this.lotNo,
    this.skt,
    this.kdvOran = 0,
  });

  /// KDV dahil kalem tutarı.
  double get kdvDahilToplam =>
      ParaUtils.yuvarla(miktar * alisFiyat * (1 + kdvOran / 100));
}

class AlimIslemServisi {
  final _kasaDepo = KasaDeposu();
  final _bankaDepo = BankaHareketDeposu();
  final _stokDepo = StokDeposu();

  /// Alımın bağlanacağı tedarikçi gerçekten var ve silinmemiş mi?
  /// 🔴 DÜZELTME (2026-11-06): ÖNCEDEN hiç kontrol edilmiyordu — form
  /// açıkken başka cihazda silinen bir tedarikçiye alım + veresiye borç
  /// yazılıyor, hiç olmayan bir id ise yetim kayıt üretiyordu. Satış
  /// tarafındaki (SatisDeposu.satisEkleTxn) cari doğrulamasının alım
  /// karşılığı; burada sessizce null'a çevirmek yerine reddedilir, çünkü
  /// tedarikçisiz bir veresiye alım borcu kaybettirir.
  /// [ex]: Database veya Transaction.
  Future<void> _tedarikciDogrula(dynamic ex, int? tedarikciId) async {
    if (tedarikciId == null) return;
    final satir = await ex.query('cari',
        columns: ['id'],
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [tedarikciId],
        limit: 1);
    if ((satir as List).isEmpty) {
      throw Exception(
          'Seçilen tedarikçi bulunamadı veya silinmiş. Listeyi yenileyip '
          'tedarikçiyi yeniden seçin.');
    }
  }

  /// cari_hareket satırını VE etkilediği cari satırını, ÇAĞIRANIN verilen
  /// [txn] içinde senkron kuyruğuna yazar (Madde 5 sertleştirmesi).
  Future<void> _cariveHareketiKuyrukla(
      dynamic txn, String cariHareketGid, int cariId) async {
    final cariHareketSatiri = await txn.query('cari_hareket',
        where: 'global_id = ?', whereArgs: [cariHareketGid], limit: 1);
    if (cariHareketSatiri.isNotEmpty) {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'cari_hareket',
          veri: Map<String, dynamic>.from(cariHareketSatiri.first));
    }
    final cariSatiri = await txn.query('cari',
        where: 'id = ?', whereArgs: [cariId], limit: 1);
    if (cariSatiri.isNotEmpty) {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'cari', veri: Map<String, dynamic>.from(cariSatiri.first));
    }
  }

  /// [mevcutSiparisId] doluysa YENİ fiş AÇILMAZ, var olan 'beklemede'
  /// sipariş 'teslim_alindi'ya güncellenir (kalem bazında teslim_mik
  /// işlenir, mükerrer kayıt olmaz). [odemeYontemi]: 'Nakit' | 'Havale' |
  /// 'Cari' | diğer (ör. 'Kredi Kartı' — peşin ama kayıt amaçlı cari
  /// hareketi net-sıfır etkiyle yazılır).
  Future<void> alimKaydet({
    required int? mevcutSiparisId,
    required List<AlimKalemGirdi> kalemler,
    required int? tedarikciId,
    required String? tedarikciAdi,
    required double genelToplam,
    required String odemeYontemi,
    int? bankaHesapId,
    required int? kullaniciId,
    required String? kullaniciAdi,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    final siparisModu = mevcutSiparisId != null;

    // Tedarikçi doğrulaması — fiş numarası harcanmadan ÖNCE (hızlı ret) ve
    // aşağıda transaction içinde tekrar (atomik). Bkz. _tedarikciDogrula.
    await _tedarikciDogrula(db, tedarikciId);

    var alimNo = '';
    if (!siparisModu) {
      alimNo = await Veritabani()
          .fisNoUret('alim', subeId: AktifSubeServisi().subeId ?? 1);
    }
    int alimId = mevcutSiparisId ?? 0;
    final alimGid = const Uuid().v4();
    final kalemGidler = <String>[];
    final stokHareketGidler = <String>[];
    final lotGidler = <String>[];
    final etkilenenUrunIdler = <int>{};
    final subePayiFarklari = <int, double>{};
    String? cariHareketGid;
    int? kasaHareketId;
    int? bankaHareketId;

    await db.transaction((txn) async {
      await _tedarikciDogrula(txn, tedarikciId);
      // 1. Alım fişi
      if (siparisModu) {
        final mevcut = await txn.query('tedarikci_siparisler',
            where: 'id = ?', whereArgs: [alimId], limit: 1);
        alimNo = mevcut.isNotEmpty
            ? (mevcut.first['siparis_no'] as String? ?? alimNo)
            : alimNo;
        // 🔴 Derin analizde bulundu: WHERE koşulu sadece id=? idi, mevcut
        // 'durum' hiç kontrol edilmiyordu — aynı 'beklemede' sipariş
        // (çift dokunma, geri tuşu + tekrar "Teslim Al", ağ gecikmesi)
        // iki kez "teslim alınırsa" stok/cari/kasa iki kez işlenirdi.
        // bekleyen_siparis_deposu.dart.onaylaVeSatisaCevir'deki AYNI
        // korumayla hizalandı: etkilenen satır 0 ise dur.
        final etkilenen = await txn.update(
            'tedarikci_siparisler',
            {
              'durum': 'teslim_alindi',
              'teslim_tarihi': now,
              'toplam_tutar': genelToplam,
              // 🔴 DERİN DENETİM (2026-11-09, #31): teslim alırken tedarikçi
              // değiştirilirse cari hareket YENİ tedarikçiye yazılıyor ama
              // belgedeki cari_id eski kalıyordu; alım silinince sil()
              // cariyi belgeden bulup ters kaydı üretmiyordu.
              if (tedarikciId != null) 'cari_id': tedarikciId,
              'last_updated': now,
            },
            where: 'id = ? AND durum = ?',
            whereArgs: [alimId, 'beklemede']);
        if (etkilenen == 0) {
          throw Exception(
              'Bu sipariş zaten teslim alınmış veya iptal edilmiş.');
        }
      } else {
        alimId = await txn.insert('tedarikci_siparisler', {
          'global_id': alimGid,
          'cari_id': tedarikciId,
          'siparis_no': alimNo,
          'siparis_tarihi': now,
          'toplam_tutar': genelToplam,
          'durum': 'teslim_alindi',
          'notlar': 'Alım: ${tedarikciAdi ?? "Manuel"}',
          'olusturan_id': kullaniciId,
          'last_updated': now,
        });
      }
      // Madde 5 sertleştirmesi: senkron kuyruğu kaydı business data ile
      // AYNI transaction içinde, atomik olarak yazılıyor (bkz.
      // SyncKuyrukYazici yorumu — yarıda kalan bir alım buluta hiç gitmez,
      // çünkü transaction'ın kendisi rollback olur).
      final guncelAlimSatiri = await txn.query('tedarikci_siparisler',
          where: 'id = ?', whereArgs: [alimId], limit: 1);
      if (guncelAlimSatiri.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'tedarikci_siparisler',
            veri: Map<String, dynamic>.from(guncelAlimSatiri.first));
      }

      // 2. Kalemler + stok
      for (final k in kalemler) {
        if (siparisModu) {
          final mevcutKalem = await txn.query('tedarikci_siparis_kalem',
              where: 'siparis_id = ? AND urun_id = ?',
              whereArgs: [alimId, k.urunId],
              limit: 1);
          if (mevcutKalem.isNotEmpty) {
            final mk = mevcutKalem.first;
            final kalemGid = (mk['global_id'] as String?) ?? const Uuid().v4();
            kalemGidler.add(kalemGid);
            await txn.update(
                'tedarikci_siparis_kalem',
                {
                  'global_id': kalemGid,
                  'teslim_mik': k.miktar,
                  'birim_fiyat': k.alisFiyat,
                  'toplam_tutar': k.kdvDahilToplam,
                  'last_updated': now,
                },
                where: 'id = ?',
                whereArgs: [mk['id']]);
          } else {
            final kalemGid = const Uuid().v4();
            kalemGidler.add(kalemGid);
            await txn.insert('tedarikci_siparis_kalem', {
              'global_id': kalemGid,
              'siparis_id': alimId,
              'urun_id': k.urunId,
              'siparis_mik': k.miktar,
              'teslim_mik': k.miktar,
              'birim_fiyat': k.alisFiyat,
              'kdv_oran': k.kdvOran,
              'toplam_tutar': k.kdvDahilToplam,
              'last_updated': now,
            });
          }
          final guncelKalemSatiri = await txn.query('tedarikci_siparis_kalem',
              where: 'global_id = ?', whereArgs: [kalemGidler.last], limit: 1);
          if (guncelKalemSatiri.isNotEmpty) {
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'tedarikci_siparis_kalem',
                veri: Map<String, dynamic>.from(guncelKalemSatiri.first));
          }
        } else {
          final kalemGid = const Uuid().v4();
          kalemGidler.add(kalemGid);
          final kalemId = await txn.insert('tedarikci_siparis_kalem', {
            'global_id': kalemGid,
            'siparis_id': alimId,
            'urun_id': k.urunId,
            'siparis_mik': k.miktar,
            'teslim_mik': k.miktar,
            'birim_fiyat': k.alisFiyat,
            'kdv_oran': k.kdvOran,
            'toplam_tutar': k.kdvDahilToplam,
            'last_updated': now,
          });
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'tedarikci_siparis_kalem',
              veri: {
                'id': kalemId,
                'global_id': kalemGid,
                'siparis_id': alimId,
                'urun_id': k.urunId,
                'siparis_mik': k.miktar,
                'teslim_mik': k.miktar,
                'birim_fiyat': k.alisFiyat,
                'kdv_oran': k.kdvOran,
                'toplam_tutar': k.kdvDahilToplam,
                'last_updated': now,
              });
        }
        // Stok güncelle
        final rows = await txn.query('urunler',
            columns: ['stok', 'alis_fiyat', 'alis_kdv_oran'],
            where: 'id = ?', whereArgs: [k.urunId]);
        if (rows.isNotEmpty) {
          final onceki = (rows.first['stok'] as num).toDouble();
          final urunGuncelleme = <String, dynamic>{
            'stok': onceki + k.miktar,
            'alis_fiyat': k.alisFiyat,
            // KDV dahil maliyet de yeni alış fiyatından yenilenir (kâr/maliyet
            // raporları bunu kullanır; önceden bayat kalıyordu).
            'alis_fiyat_kdv_dahil': k.alisFiyat *
                (1 + ((rows.first['alis_kdv_oran'] as num?)?.toDouble() ?? 0) / 100),
            'last_updated': now,
          };
          // Alış fiyatı değiştiyse Maliyet Güncelleme Tarihi damgalanır.
          UrunDeposu.fiyatMaliyetDamgala(urunGuncelleme,
              {'alis_fiyat': rows.first['alis_fiyat']}, now);
          await txn.update(
              'urunler',
              urunGuncelleme,
              where: 'id = ?',
              whereArgs: [k.urunId]);
          etkilenenUrunIdler.add(k.urunId);
          final guncelUrunSatiri = await txn.query('urunler',
              where: 'id = ?', whereArgs: [k.urunId], limit: 1);
          if (guncelUrunSatiri.isNotEmpty) {
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'urunler',
                veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
          }
          // Ana stok ARTTI (alım) — subeStokPayiUygula pozitif=düştü
          // bekliyor, bu yüzden negatif veriliyor.
          subePayiFarklari[k.urunId] =
              (subePayiFarklari[k.urunId] ?? 0) - k.miktar;

          // 🔴 Derin denetimde bulundu (P2, kullanıcı onayıyla): lot_takibi
          // açık ürünlerde alım anında lot_seri hiç oluşturulmuyordu.
          // Kullanıcı lot no girdiyse burada oluşturulur, stok_hareket
          // bu lota bağlanır (LotDeposu.kaydet()'in yaptığıyla aynı
          // alanlar) — girmediyse davranış birebir eskisi gibi kalır.
          int? lotId;
          final lotNo = k.lotNo?.trim();
          if (lotNo != null && lotNo.isNotEmpty) {
            final lotGid = const Uuid().v4();
            lotGidler.add(lotGid);
            lotId = await txn.insert('lot_seri', {
              'global_id': lotGid,
              'urun_id': k.urunId,
              'lot_no': lotNo,
              'miktar': k.miktar,
              'son_kullanma_tarihi': k.skt?.toIso8601String(),
              'tedarikci_cari_id': tedarikciId,
              'aciklama': 'Alım: $alimNo',
              'kayit_tarihi': now,
              'last_updated': now,
            });
            final lotSatiri = await txn.query('lot_seri',
                where: 'id = ?', whereArgs: [lotId], limit: 1);
            if (lotSatiri.isNotEmpty) {
              await SyncKuyrukYazici.ekleTxn(txn,
                  tablo: 'lot_seri', veri: Map<String, dynamic>.from(lotSatiri.first));
            }
          }

          final stokGid = const Uuid().v4();
          stokHareketGidler.add(stokGid);
          final stokSatiri = {
            'global_id': stokGid,
            'urun_id': k.urunId,
            'hareket_turu': 'Alim Giris',
            'miktar': k.miktar,
            'onceki_stok': onceki,
            'sonraki_stok': onceki + k.miktar,
            'birim_maliyet': k.alisFiyat,
            'tarih': now,
            'last_updated': now,
            'referans_id': alimId,
            'referans_turu': 'alim',
            'kullanici_id': kullaniciId,
            'aciklama': 'Alım: $alimNo',
            'lot_id': lotId,
          };
          final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
        }
      }

      // 3. Gerçek para hareketi
      if (odemeYontemi == 'Nakit' && genelToplam > 0.005) {
        kasaHareketId = await _kasaDepo.hareketEkleTxn(
            txn,
            KasaHareketModel(
              hareketTipi: 'Alım',
              tutar: genelToplam,
              referansId: alimId,
              referansTuru: 'alim',
              tarih: DateTime.now(),
              aciklama: 'Mal Alımı: $alimNo',
              kullaniciId: kullaniciId,
            ));
      } else if (odemeYontemi == 'Havale' && genelToplam > 0.005) {
        bankaHareketId = await _bankaDepo.ekleTxn(
            txn,
            BankaHareketModel(
              bankaHesapId: bankaHesapId!,
              islemTipi: 'Giden',
              tutar: genelToplam,
              aciklama: 'Mal Alımı: $alimNo',
              tarih: DateTime.now(),
              // 🔴 DERİN DENETİM (2026-11-09): referans verilmiyordu —
              // sil() banka satırını bulamıyor, havale alımı silinince
              // bankadan çıkan para hiç geri yazılmıyordu.
              referansId: alimId,
              referansTuru: 'alim',
            ));
      }

      // 4. Cari hareket
      if (tedarikciId != null && odemeYontemi == 'Cari') {
        cariHareketGid = const Uuid().v4();
        await txn.insert('cari_hareket', {
          'global_id': cariHareketGid,
          'cari_id': tedarikciId,
          'tarih': now,
          'fis_tipi': 'Alım',
          'fis_id': alimId,
          'fis_no': alimNo,
          'aciklama': 'Mal Alımı: $alimNo',
          'borc': 0,
          'alacak': genelToplam,
          'odeme_turu': 'Cari',
          'kullanici': kullaniciAdi,
          'last_updated': now,
        });
        await CariDeposu.bakiyeTazeleTxn(txn, tedarikciId);
        await _cariveHareketiKuyrukla(txn, cariHareketGid!, tedarikciId);
      } else if (tedarikciId != null && genelToplam > 0.005) {
        // Nakit/Kredi Kartı ile peşin ödense bile tedarikçinin cari
        // hareket geçmişinde görünsün — borc VE alacak AYNI tutarda
        // yazıldığı için (net sıfır etki) bakiyeyi DEĞİŞTİRMEZ, sadece
        // kayıt/geçmiş amaçlıdır.
        cariHareketGid = const Uuid().v4();
        await txn.insert('cari_hareket', {
          'global_id': cariHareketGid,
          'cari_id': tedarikciId,
          'tarih': now,
          'fis_tipi': 'Alım',
          'fis_id': alimId,
          'fis_no': alimNo,
          'aciklama': '$odemeYontemi Alım: $alimNo — bakiyeyi etkilemez',
          'borc': genelToplam,
          'alacak': genelToplam,
          'odeme_turu': odemeYontemi,
          'kullanici': kullaniciAdi,
          'last_updated': now,
        });
        await CariDeposu.bakiyeTazeleTxn(txn, tedarikciId);
        await _cariveHareketiKuyrukla(txn, cariHareketGid!, tedarikciId);
      }
    });

    // Transaction kapandıktan (veri kalıcı olduktan) sonra buluta bildir.
    try {
      await BulutManager().satiriBildir(db, 'tedarikci_siparisler', alimId);
      for (final gid in kalemGidler) {
        final s = await db.query('tedarikci_siparis_kalem',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager().upsert(
              'tedarikci_siparis_kalem', Map<String, dynamic>.from(s.first));
        }
      }
      for (final urunId in etkilenenUrunIdler) {
        await BulutManager().satiriBildir(db, 'urunler', urunId);
      }
      for (final gid in stokHareketGidler) {
        final s = await db.query('stok_hareket',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager()
              .upsert('stok_hareket', Map<String, dynamic>.from(s.first));
        }
      }
      for (final gid in lotGidler) {
        final s = await db.query('lot_seri',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager().upsert('lot_seri', Map<String, dynamic>.from(s.first));
        }
      }
      if (cariHareketGid != null) {
        final s = await db.query('cari_hareket',
            where: 'global_id = ?', whereArgs: [cariHareketGid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager()
              .upsert('cari_hareket', Map<String, dynamic>.from(s.first));
        }
        if (tedarikciId != null) {
          await BulutManager().satiriBildir(db, 'cari', tedarikciId);
        }
      }
      if (kasaHareketId != null) {
        await BulutManager().satiriBildir(db, 'kasa_hareketleri', kasaHareketId);
      }
      if (bankaHareketId != null) {
        await BulutManager().satiriBildir(db, 'banka_hareketler', bankaHareketId);
        await BulutManager().satiriBildir(db, 'banka_hesaplar', bankaHesapId);
      }
    } catch (_) {
      // Bulut bildirimi hatası asıl işlemi engellemez — orijinal ekran
      // davranışıyla aynı (sessizce yutulur).
    }

    // 🔴 Derin analizde bulundu: çok şubeli stok payı (sube_urun) hiç
    // güncellenmiyordu.
    for (final girdi in subePayiFarklari.entries) {
      await _stokDepo.subeStokPayiUygula(girdi.key, girdi.value);
    }
  }

  /// Bir Alım'ı (teslim alınmış tedarikçi siparişini) GÜVENLİ şekilde
  /// siler — stok geri düşer, kasa/banka (varsa) tersine çevrilir, cari
  /// hareketi tersine çevrilir. SatisDeposu.sil()'in (2026-09-21
  /// düzeltmesi) BİREBİR aynı deseni kullanır: hangi tutarın
  /// "gerçekleştiğini" satislar/tedarikci_siparisler alanlarından
  /// TAHMİN ETMEZ — bu alımın GERÇEKTEN yazdığı kasa_hareketleri/
  /// cari_hareket satırlarını sorgulayıp TAM TERSİNİ yazar.
  ///
  /// 🔴🔴 KRİTİK BULGU (kullanıcı bulgusu, 2026-09-22): bu fonksiyon
  /// ÖNCEDEN HİÇ YOKTU — Cari Hareketler ekranından bir "Alım" satırı
  /// silinince genel amaçlı CariDeposu.hareketIptalEt()'e düşüyordu:
  ///  1) tedarikci_siparisler'e hiç dokunmuyordu — silinen alım Alım
  ///     Listesi'nin "Teslim Alınan" sekmesinde AYNEN görünmeye devam
  ///     ediyordu.
  ///  2) Stok hiç geri düşülmüyordu — alınan mal stokta kalıyordu.
  ///  3) Kasa/Banka ters çevirmesi referans_turu='cari_hareket' arıyordu
  ///     ama alimKaydet() referans_turu='alim' yazıyordu — asla
  ///     eşleşmiyordu, Nakit/Havale ile yapılmış bir alım silinince
  ///     kasadan/bankadan çıkan para GERİ GELMİYORDU.
  /// Cari bakiye matematiği (SUM ile yeniden hesaplama) kendi başına
  /// doğruydu, ama stok/kasa tarafı sessizce bozuk kaldığı için genel
  /// tablo tutarsız görünüyordu.
  Future<void> sil(int alimId, {String? neden}) async {
    final db = await Veritabani().db;
    int? cariId;
    final kasaHareketIdleri = <int>[];
    int? bankaHareketId;
    final subePayiFarklari = <int, double>{};

    await db.transaction((txn) async {
      // 1. Alım başlığını al
      final alimRows = await txn.query('tedarikci_siparisler',
          where: 'id = ?', whereArgs: [alimId]);
      if (alimRows.isEmpty) return;
      final alim = alimRows.first;
      if (alim['durum'] != 'teslim_alindi') {
        throw Exception(
            'Sadece teslim alınmış (stok/kasa/cariyi etkilemiş) bir alım bu şekilde silinebilir.');
      }
      cariId = alim['cari_id'] as int?;
      final alimNo = alim['siparis_no'] as String? ?? '#$alimId';
      final now = DateTime.now().toIso8601String();

      // 2. Alımı iptal'e çevir — Alım Listesi'nin "Teslim Alınan"
      // sekmesinden düşer, "İptal" sekmesine geçer (durumaGoreListele()
      // zaten durum'a göre filtreliyor, ek bir sorgu değişikliği
      // gerekmiyor). is_deleted=1 ayrıca senkron için (bkz.
      // supabase_sync_servisi.dart tablo haritası: tedarikci_siparisler
      // → is_deleted).
      await txn.update(
          'tedarikci_siparisler',
          {
            'durum': 'iptal',
            'is_deleted': 1,
            'last_updated': now,
            'notlar': neden ?? 'Alım silindi',
          },
          where: 'id = ?',
          whereArgs: [alimId]);
      final iptalAlim = await txn.query('tedarikci_siparisler',
          where: 'id = ?', whereArgs: [alimId], limit: 1);
      if (iptalAlim.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'tedarikci_siparisler', veri: Map<String, dynamic>.from(iptalAlim.first));
      }

      // 3. Stok geri düş
      final kalemler = await txn.query('tedarikci_siparis_kalem',
          where: 'siparis_id = ?', whereArgs: [alimId]);
      for (final k in kalemler) {
        final urunId = k['urun_id'] as int?;
        final miktar = (k['teslim_mik'] as num?)?.toDouble() ?? 0;
        if (urunId == null || miktar <= 0) continue;
        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
        final onceki = urunRows.isNotEmpty
            ? (urunRows.first['stok'] as num).toDouble() : 0.0;
        final sonraki = onceki - miktar;
        await txn.update('urunler', {'stok': sonraki},
            where: 'id = ?', whereArgs: [urunId]);
        // 🔴 DERİN DENETİM (2026-11-09, #28): ters hareket global_id'siz
        // yazılıp kuyruğa hiç girmiyordu — diğer cihazların stok
        // mutabakatı alımı iptal edilmemiş sayıyordu.
        final tersHareket = <String, dynamic>{
          'global_id':     const Uuid().v4(),
          'urun_id':       urunId,
          'hareket_turu':  'Alım İptali',
          'miktar':        miktar,
          'onceki_stok':   onceki,
          'sonraki_stok':  sonraki,
          'referans_id':   alimId,
          'referans_turu': 'alim_iptal',
          'tarih':         now,
          'last_updated':  now,
          'aciklama':      'Alım iptali — Fiş $alimNo',
        };
        await txn.insert('stok_hareket', tersHareket);
        await SyncKuyrukYazici.ekleTxn(txn, tablo: 'stok_hareket', veri: tersHareket);
        // Ana stok AZALDI (alım iptali) — subeStokPayiUygula
        // pozitif=düştü bekliyor (alimKaydet()'teki AYNI mantığın tersi).
        subePayiFarklari[urunId] = (subePayiFarklari[urunId] ?? 0) + miktar;
      }

      // 4. Kasa/Banka hareketini tersine çevir — bu alımın GERÇEKTEN
      // yazdığı satırları sorgulayıp (odenen tutara/ödeme yöntemine göre
      // TAHMİN ETMEDEN) tersini yazıyoruz.
      final kasaRows = await txn.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ? AND deleted_at IS NULL',
          whereArgs: [alimId, 'alim']);
      for (final k in kasaRows) {
        final tutar = (k['tutar'] as num?)?.toDouble() ?? 0;
        if (tutar <= 0) continue;
        final kid = await _kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
          hareketTipi:  'Alım İptali',
          tutar:        tutar,
          referansId:   alimId,
          referansTuru: 'alim_iptal',
          tarih:        DateTime.parse(now),
          aciklama:     'Alım iptali: $alimNo',
        ));
        kasaHareketIdleri.add(kid);
      }
      // Eski kayıtlar (referans yazılmadan önceki havale alımları) alıma
      // özgü açıklamayla eşlenir — alım no benzersizdir.
      final bankaRows = await txn.query('banka_hareketler',
          where: '((referans_id = ? AND referans_turu = ?) OR '
              "(referans_id IS NULL AND islem_tipi = 'Giden' AND aciklama = ?)) "
              'AND (is_deleted IS NULL OR is_deleted = 0)',
          whereArgs: [alimId, 'alim', 'Mal Alımı: $alimNo']);
      for (final b in bankaRows) {
        final tutar = (b['tutar'] as num?)?.toDouble() ?? 0;
        final bankaHesapId = b['banka_hesap_id'] as int?;
        if (tutar <= 0 || bankaHesapId == null) continue;
        bankaHareketId = await _bankaDepo.ekleTxn(txn, BankaHareketModel(
          bankaHesapId: bankaHesapId,
          islemTipi:    'Gelen',
          tutar:        tutar,
          referansId:   alimId,
          referansTuru: 'alim_iptal',
          tarih:        DateTime.parse(now),
          aciklama:     'Alım iptali: $alimNo',
        ));
      }

      // 5. Cari hareketi tersine çevir — SatisDeposu.sil() ile AYNI
      // sorgu-tabanlı desen: bu alımın GERÇEKTEN yazdığı cari_hareket
      // satırları (fis_id + fis_tipi='Alım') sorgulanıp toplam borç/
      // alacağın TAM TERSİ TEK bir "Alım İptali" kaydıyla sıfırlanıyor.
      if (cariId != null) {
        final orijinalCariSatirlari = await txn.query('cari_hareket',
            where: 'fis_id = ? AND cari_id = ? AND fis_tipi = ? AND is_deleted = 0',
            whereArgs: [alimId, cariId, 'Alım']);
        final toplamBorc = orijinalCariSatirlari.fold(
            0.0, (s, r) => s + ((r['borc'] as num?)?.toDouble() ?? 0));
        final toplamAlacak = orijinalCariSatirlari.fold(
            0.0, (s, r) => s + ((r['alacak'] as num?)?.toDouble() ?? 0));
        if (toplamBorc > 0.005 || toplamAlacak > 0.005) {
          await txn.insert('cari_hareket', {
            'global_id':  const Uuid().v4(),
            'cari_id':    cariId,
            'tarih':      now,
            'last_updated': now,
            'fis_tipi':   'Alım İptali',
            'fis_id':     alimId,
            'fis_no':     alimNo,
            'aciklama':   'Alım iptali: $alimNo',
            'borc':       toplamAlacak,
            'alacak':     toplamBorc,
            'odeme_turu': 'Cari',
          });
        }
        await CariDeposu.bakiyeTazeleTxn(txn, cariId, lastUpdated: now);
      }
    });

    // Transaction kapandıktan sonra buluta bildir.
    try {
      await BulutManager().satiriBildir(db, 'tedarikci_siparisler', alimId);
      for (final kasaHareketId in kasaHareketIdleri) {
        await BulutManager().satiriBildir(db, 'kasa_hareketleri', kasaHareketId);
      }
      if (bankaHareketId != null) {
        await BulutManager().satiriBildir(db, 'banka_hareketler', bankaHareketId);
      }
      if (cariId != null) {
        final cariHareketSon = await db.query('cari_hareket',
            where: 'fis_id = ? AND cari_id = ? AND fis_tipi = ?',
            whereArgs: [alimId, cariId, 'Alım İptali'], orderBy: 'id DESC', limit: 1);
        for (final satir in cariHareketSon) {
          BulutManager().upsert('cari_hareket', Map<String, dynamic>.from(satir));
        }
        await BulutManager().satiriBildir(db, 'cari', cariId);
      }
    } catch (_) {
      // Bulut bildirimi hatası asıl işlemi engellemez.
    }

    for (final girdi in subePayiFarklari.entries) {
      await _stokDepo.subeStokPayiUygula(girdi.key, girdi.value);
    }
  }
}
