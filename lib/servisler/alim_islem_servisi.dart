// lib/servisler/alim_islem_servisi.dart
//
// Mal Alımı ekranının db.transaction() mantığını SCREEN→SERVICE→
// REPOSITORY mimarisine taşıyan servis. Davranış, önceden ekranın kendi
// _alimKaydet()'inde yürüttüğü mantıkla birebir aynıdır: alım fişi
// (yeni VEYA bekleyen bir siparişin teslim alınması) + kalemler + stok +
// (varsa) kasa/banka + (varsa) cari hareketi TEK transaction içinde,
// commit sonrası bulut senkronu.
import '../depolar/kasa_deposu.dart';
import '../depolar/banka_hareket_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../modeller/kasa_hareket_model.dart';
import '../modeller/banka_hareket_model.dart';
import '../servisler/aktif_sube_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';
import 'package:uuid/uuid.dart';

/// Bir alım kaleminin (ürün + miktar + alış fiyatı) DB yazımı için
/// gereken minimal bilgisi.
class AlimKalemGirdi {
  final int urunId;
  final double miktar;
  final double alisFiyat;
  const AlimKalemGirdi(
      {required this.urunId, required this.miktar, required this.alisFiyat});
}

class AlimIslemServisi {
  final _kasaDepo = KasaDeposu();
  final _bankaDepo = BankaHareketDeposu();
  final _stokDepo = StokDeposu();

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

    var alimNo = '';
    if (!siparisModu) {
      alimNo = await Veritabani()
          .fisNoUret('alim', subeId: AktifSubeServisi().subeId ?? 1);
    }
    int alimId = mevcutSiparisId ?? 0;
    final alimGid = const Uuid().v4();
    final kalemGidler = <String>[];
    final stokHareketGidler = <String>[];
    final etkilenenUrunIdler = <int>{};
    final subePayiFarklari = <int, double>{};
    String? cariHareketGid;
    int? kasaHareketId;
    int? bankaHareketId;

    await db.transaction((txn) async {
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
                  'toplam_tutar': k.miktar * k.alisFiyat,
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
              'kdv_oran': 0,
              'toplam_tutar': k.miktar * k.alisFiyat,
              'last_updated': now,
            });
          }
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
            'kdv_oran': 0,
            'toplam_tutar': k.miktar * k.alisFiyat,
            'last_updated': now,
          });
        }
        // Stok güncelle
        final rows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [k.urunId]);
        if (rows.isNotEmpty) {
          final onceki = (rows.first['stok'] as num).toDouble();
          await txn.update(
              'urunler',
              {
                'stok': onceki + k.miktar,
                'alis_fiyat': k.alisFiyat,
                'last_updated': now
              },
              where: 'id = ?',
              whereArgs: [k.urunId]);
          etkilenenUrunIdler.add(k.urunId);
          // Ana stok ARTTI (alım) — subeStokPayiUygula pozitif=düştü
          // bekliyor, bu yüzden negatif veriliyor.
          subePayiFarklari[k.urunId] =
              (subePayiFarklari[k.urunId] ?? 0) - k.miktar;
          final stokGid = const Uuid().v4();
          stokHareketGidler.add(stokGid);
          await txn.insert('stok_hareket', {
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
          });
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
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
            [tedarikciId, tedarikciId]);
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
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
            [tedarikciId, tedarikciId]);
      }
    });

    // Transaction kapandıktan (veri kalıcı olduktan) sonra buluta bildir.
    try {
      final alimSatir = await db.query('tedarikci_siparisler',
          where: 'id = ?', whereArgs: [alimId], limit: 1);
      if (alimSatir.isNotEmpty) {
        BulutManager().upsert(
            'tedarikci_siparisler', Map<String, dynamic>.from(alimSatir.first));
      }
      for (final gid in kalemGidler) {
        final s = await db.query('tedarikci_siparis_kalem',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager().upsert(
              'tedarikci_siparis_kalem', Map<String, dynamic>.from(s.first));
        }
      }
      for (final urunId in etkilenenUrunIdler) {
        final s = await db.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (s.isNotEmpty) {
          BulutManager().upsert('urunler', Map<String, dynamic>.from(s.first));
        }
      }
      for (final gid in stokHareketGidler) {
        final s = await db.query('stok_hareket',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager()
              .upsert('stok_hareket', Map<String, dynamic>.from(s.first));
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
          final cariSatir = await db.query('cari',
              where: 'id = ?', whereArgs: [tedarikciId], limit: 1);
          if (cariSatir.isNotEmpty) {
            BulutManager()
                .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
          }
        }
      }
      if (kasaHareketId != null) {
        final s = await db.query('kasa_hareketleri',
            where: 'id = ?', whereArgs: [kasaHareketId], limit: 1);
        if (s.isNotEmpty) {
          BulutManager()
              .upsert('kasa_hareketleri', Map<String, dynamic>.from(s.first));
        }
      }
      if (bankaHareketId != null) {
        final s = await db.query('banka_hareketler',
            where: 'id = ?', whereArgs: [bankaHareketId], limit: 1);
        if (s.isNotEmpty) {
          BulutManager()
              .upsert('banka_hareketler', Map<String, dynamic>.from(s.first));
        }
        final hesapSatir = await db.query('banka_hesaplar',
            where: 'id = ?', whereArgs: [bankaHesapId], limit: 1);
        if (hesapSatir.isNotEmpty) {
          BulutManager().upsert(
              'banka_hesaplar', Map<String, dynamic>.from(hesapSatir.first));
        }
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
}
