// lib/servisler/satis_tamamlama_servisi.dart
//
// Kademeli mimari refactor (protokol §6/§35): "Hızlı Satış Tamamla" iş
// mantığı önceden doğrudan hizli_satis_ekrani.dart (2000+ satırlık ekran
// dosyası) içinde yaşıyordu — satış kaydı, stok düşümü, kasa/banka
// hareketi ve cari hareketi TEK transaction'da doğru şekilde
// yürütülüyordu (depoların xxxTxn varyantları zaten kullanılıyordu),
// ama bu orkestrasyon bir SERVİSTE değil bir EKRANDA yaşıyordu — aynı
// mantık masa_odeme_servisi.dart'ta ayrı bir kopya olarak da vardı.
// Bu servis, ekranın doğrudan Veritabani()/db.query çağırmasını
// kaldırıyor ve mantığı test edilebilir, tek bir yere taşıyor.
//
// DAVRANIŞ DEĞİŞMEDİ — bu saf bir taşıma (extract method) refactor'ü,
// transaction sırası ve iş kuralları BİREBİR korundu.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../depolar/cari_deposu.dart';
import '../depolar/kasa_deposu.dart';
import '../depolar/satis_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../modeller/cari_hareket_model.dart';
import '../modeller/cari_model.dart';
import '../modeller/kasa_hareket_model.dart';
import '../modeller/kullanici_model.dart';
import '../modeller/satis_kalem_model.dart';
import '../modeller/satis_model.dart';
import '../modeller/sepet_model.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/puan_servisi.dart';
import '../veri/database/veritabani.dart';

class SatisTamamlamaSonucu {
  final int satisId;
  final String fisNo;
  final DateTime tarih;
  final List<SatisKalemModel> kalemler;

  const SatisTamamlamaSonucu({
    required this.satisId,
    required this.fisNo,
    required this.tarih,
    required this.kalemler,
  });
}

class FisGuncellemeSonucu {
  final SatisModel guncelSatis;
  final double tutarFarki;

  const FisGuncellemeSonucu(
      {required this.guncelSatis, required this.tutarFarki});
}

class SatisTamamlamaServisi {
  final _satisDepo = SatisDeposu();
  final _stokDepo = StokDeposu();
  final _kasaDepo = KasaDeposu();
  final _cariDepo = CariDeposu();

  /// Sepeti bir satışa dönüştürür: fiş no üretir, satış+kalemleri
  /// kaydeder, stok düşer, ödeme yöntemine göre kasa/cari hareketi
  /// oluşturur — hepsi TEK transaction'da. Commit sonrası bulut
  /// senkronu tetiklenir ve (varsa) müşteri puanı işlenir.
  Future<SatisTamamlamaSonucu> tamamla({
    required List<SepetKalem> kalemler,
    required CariModel? musteri,
    required double genelToplam,
    required String odemeYontemi,
    required double odenenTutar,
    List<Map<String, dynamic>>? karmaKalemler,
    KullaniciModel? kullanici,
    int? subeId,
  }) async {
    final tarih = DateTime.now();
    final fisNo = await Veritabani().fisNoUret(
        musteri != null ? 'cari_satis' : 'satis',
        subeId: subeId ?? 1);

    final satisKalemler = kalemler
        .map((k) => SatisKalemModel(
              satisId: 0,
              urunId: k.urun.id!,
              urunAdi: k.urun.urunAdi,
              barkod: k.urun.barkod,
              miktar: k.miktar,
              birimFiyat: k.birimFiyat,
              toplamTutar: k.toplamTutar,
              iskontoOran: 0,
              iskontoTutar: 0,
              kdvOran: double.tryParse(k.urun.kdvOran) ?? 18,
              kdvTutar: k.kdvTutar,
              netFiyat: k.netFiyat,
              alisFiyat: k.urun.alisFiyat,
              alisFiyatKdv: k.urun.alisFiyatKdvDahil,
            ))
        .toList();

    final satis = SatisModel(
      fisNo: fisNo,
      tarih: tarih,
      cariId: musteri?.id,
      cariAdi: musteri?.unvan,
      toplamTutar: genelToplam,
      genelToplam: genelToplam,
      odenenTutar: odenenTutar,
      odemeYontemi: odemeYontemi,
      fisTipi: 'Satış',
      kasiyerId: kullanici?.id,
      kullaniciId: kullanici?.id,
    );

    final db = await Veritabani().db;
    late final int satisId;
    final stokHareketGidleri = <int, String>{};
    // 🔴🔴 FAZ 1 madde 2 (kullanıcı onayıyla, Vardiya/Kasa mutabakatı):
    // ÖNCEDEN karma ödemede TÜM Cari-dışı yöntemler (Nakit+Kart+Banka)
    // tek bir 'Satış' kasa hareketinde toplanıyordu — bu, kasa_hareketleri
    // zincirini fiziksel nakitle Kart'ı ayırt edemez hale getiriyordu.
    // Artık her ödeme yöntemi için AYRI bir kasa_hareketleri satırı
    // açılıyor, her biri odeme_yontemi ile etiketleniyor — KasaDeposu
    // .guncelBakiyeNakit() artık sadece gerçek nakit zincirini toplayabiliyor.
    final kasaGlobalIdleri = <String>[];
    final cariGlobalIdleri = <String>[];

    await db.transaction((txn) async {
      satisId = await _satisDepo.satisEkleTxn(txn, satis, satisKalemler);

      for (final k in kalemler) {
        final gid = const Uuid().v4();
        stokHareketGidleri[k.urun.id!] = gid;
        await _stokDepo.stokDusTxn(
          txn,
          gid,
          urunId: k.urun.id!,
          miktar: k.miktar,
          kullaniciId: kullanici?.id,
          referansId: satisId,
          referansTuru: 'satis',
        );
      }

      if (karmaKalemler != null) {
        final digerYontemler =
            karmaKalemler.where((k) => k['yontem'] != 'Cari');
        final gruplar = <String, double>{};
        for (final k in digerYontemler) {
          final y = k['yontem'] as String;
          gruplar[y] = (gruplar[y] ?? 0) + (k['tutar'] as num).toDouble();
        }
        for (final girdi in gruplar.entries) {
          if (girdi.value <= 0.005) continue;
          final kgid = const Uuid().v4();
          await _kasaDepo.hareketEkleTxn(
              txn,
              KasaHareketModel(
                globalId: kgid,
                hareketTipi: 'Satış',
                tutar: girdi.value,
                referansId: satisId,
                referansTuru: 'satis',
                tarih: tarih,
                aciklama: 'Satış: $fisNo (Karma: ${girdi.key})',
                kullaniciId: kullanici?.id,
                odemeYontemi: girdi.key,
              ));
          kasaGlobalIdleri.add(kgid);
        }
      } else if (odenenTutar > 0 && odemeYontemi != 'Cari') {
        final kgid = const Uuid().v4();
        await _kasaDepo.hareketEkleTxn(
            txn,
            KasaHareketModel(
              globalId: kgid,
              hareketTipi: 'Satış',
              tutar: odenenTutar,
              referansId: satisId,
              referansTuru: 'satis',
              tarih: tarih,
              aciklama: 'Satış: $fisNo',
              kullaniciId: kullanici?.id,
              odemeYontemi: odemeYontemi,
            ));
        kasaGlobalIdleri.add(kgid);
      }

      if (karmaKalemler != null) {
        final cariTutar = karmaKalemler
            .where((k) => k['yontem'] == 'Cari')
            .fold(0.0, (s, k) => s + (k['tutar'] as num).toDouble());
        if (musteri != null && cariTutar > 0.005) {
          cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
              txn,
              CariHareketModel(
                cariId: musteri.id!,
                tarih: tarih,
                fisTipi: 'Satış',
                fisId: satisId,
                fisNo: fisNo,
                aciklama: 'Veresiye (Karma): $fisNo',
                borc: cariTutar,
                alacak: 0,
                odemeTuru: 'Cari',
                kullanici: kullanici?.adSoyad,
              )));
        }
        final digerTutar = karmaKalemler
            .where((k) => k['yontem'] != 'Cari')
            .fold(0.0, (s, k) => s + (k['tutar'] as num).toDouble());
        if (musteri != null && digerTutar > 0.005) {
          final yontemler = karmaKalemler
              .where((k) => k['yontem'] != 'Cari')
              .map((k) => k['yontem'] as String)
              .toSet()
              .join('+');
          cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
              txn,
              CariHareketModel(
                cariId: musteri.id!,
                tarih: tarih,
                fisTipi: 'Satış',
                fisId: satisId,
                fisNo: fisNo,
                aciklama:
                    '$yontemler Satış (Karma): $fisNo — bakiyeyi etkilemez',
                borc: digerTutar,
                alacak: digerTutar,
                odemeTuru: yontemler,
                kullanici: kullanici?.adSoyad,
              )));
        }
      } else if (musteri != null && odemeYontemi == 'Cari') {
        cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: musteri.id!,
              tarih: tarih,
              fisTipi: 'Satış',
              fisId: satisId,
              fisNo: fisNo,
              aciklama: 'Veresiye: $fisNo',
              borc: genelToplam,
              alacak: 0,
              odemeTuru: 'Cari',
              kullanici: kullanici?.adSoyad,
            )));
      } else if (musteri != null && genelToplam > 0.005) {
        cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: musteri.id!,
              tarih: tarih,
              fisTipi: 'Satış',
              fisId: satisId,
              fisNo: fisNo,
              aciklama: '$odemeYontemi Satış: $fisNo — bakiyeyi etkilemez',
              borc: genelToplam,
              alacak: genelToplam,
              odemeTuru: odemeYontemi,
              kullanici: kullanici?.adSoyad,
            )));
      }
    });

    await _bulutSenkronEt(
      db,
      satis: satis,
      satisId: satisId,
      fisNo: fisNo,
      satisKalemler: satisKalemler,
      kalemler: kalemler,
      stokHareketGidleri: stokHareketGidleri,
      kasaGlobalIdleri: kasaGlobalIdleri,
      cariGlobalIdleri: cariGlobalIdleri,
      musteri: musteri,
    );

    if (musteri != null && musteri.id != null && genelToplam > 0) {
      try {
        await PuanServisi().puanEkle(
          cariId: musteri.id!,
          tutar: genelToplam,
          satisId: satisId,
        );
      } catch (_) {/* puan hatası satışı geçersiz kılmaz */}
    }

    return SatisTamamlamaSonucu(
      satisId: satisId,
      fisNo: fisNo,
      tarih: tarih,
      kalemler: satisKalemler,
    );
  }

  /// Transaction commit olduktan SONRA çağrılır — commit'ten önce
  /// senkronlamak, geri alınırsa buluta var olmayan satır gönderirdi
  /// (bkz. KasaDeposu.hareketEkleTxn'deki aynı gerekçe).
  Future<void> _bulutSenkronEt(
    Database db, {
    required SatisModel satis,
    required int satisId,
    required String fisNo,
    required List<SatisKalemModel> satisKalemler,
    required List<SepetKalem> kalemler,
    required Map<int, String> stokHareketGidleri,
    required List<String> kasaGlobalIdleri,
    required List<String> cariGlobalIdleri,
    required CariModel? musteri,
  }) async {
    try {
      BulutManager().upsert('satislar',
          {...satis.toMap(), 'id': satisId, 'global_id': satis.globalId});
      for (final k in satisKalemler) {
        BulutManager().upsert('satis_kalem', k.toMap());
      }
      for (final k in kalemler) {
        final gid = stokHareketGidleri[k.urun.id!];
        if (gid == null) continue;
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [k.urun.id], limit: 1);
        if (urunSatir.isNotEmpty)
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        final stokSatir = await db.query('stok_hareket',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (stokSatir.isNotEmpty)
          BulutManager().upsert(
              'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
      }
      // 🔴🔴 FAZ 1 madde 2: karma ödemede artık BİRDEN FAZLA kasa hareketi
      // oluşabiliyor (her ödeme yöntemi için ayrı satır) — bu yüzden
      // "referans_id + ORDER BY id DESC LIMIT 1" yerine, oluşturulan HER
      // global_id tek tek buluta bildiriliyor (aksi halde karma ödemedeki
      // ilk kasa hareketi sessizce senkronsuz kalırdı).
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
      if (musteri != null &&
          musteri.id != null &&
          cariGlobalIdleri.isNotEmpty) {
        final cariSatir = await db.query('cari',
            where: 'id = ?', whereArgs: [musteri.id], limit: 1);
        if (cariSatir.isNotEmpty)
          BulutManager()
              .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
      }
    } catch (_) {
      // Bulut bildirimi best-effort — satış zaten kalıcı olarak kaydedildi,
      // sync hatası satışı geçersiz kılmamalı (mevcut davranışla aynı).
    }
  }

  /// Bekleyen (kaydedilmiş) bir fişi düzenler: kalemleri değiştirir, stok
  /// farkını uygular, tutar farkına göre cari/kasa hareketi oluşturur —
  /// hepsi TEK transaction'da atomik olarak.
  ///
  /// 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Önceden bu akış
  /// hizli_satis_ekrani.dart'ta 4 AYRI, transaction'sız çağrıdan
  /// oluşuyordu (fisiGuncelle + her ürün için stokDus/stokGir + cari/kasa
  /// hareketi) — ortadaki bir adım başarısız olursa fiş güncellenmiş ama
  /// stok/kasa/cari hiç değişmemiş gibi kalabiliyordu. Artık
  /// SatisTamamlamaServisi.tamamla()'daki AYNI desenle atomik.
  Future<FisGuncellemeSonucu> fisiGuncelle({
    required SatisModel satis,
    required List<SepetKalem> yeniKalemler,
    required double yeniGenelToplam,
    KullaniciModel? kullanici,
  }) async {
    final eskiToplam = satis.genelToplam;
    final yeniToplam = yeniGenelToplam;
    final tutarFarki = yeniToplam - eskiToplam;

    final yeniSatisKalemleri = yeniKalemler
        .map((k) => SatisKalemModel(
              satisId: satis.id!,
              urunId: k.urun.id!,
              urunAdi: k.urun.urunAdi,
              barkod: k.urun.barkod,
              miktar: k.miktar,
              birimFiyat: k.birimFiyat,
              toplamTutar: k.toplamTutar,
              iskontoOran: 0,
              iskontoTutar: 0,
              kdvOran: double.tryParse(k.urun.kdvOran) ?? 18,
              kdvTutar: k.kdvTutar,
              netFiyat: k.netFiyat,
              alisFiyat: k.urun.alisFiyat,
              alisFiyatKdv: k.urun.alisFiyatKdvDahil,
            ))
        .toList();

    final db = await Veritabani().db;
    final stokHareketGidleri = <int, String>{};
    String? cariHareketGlobalId;
    int? kasaHareketId;

    late final Map<int, double> stokFarklari;
    await db.transaction((txn) async {
      stokFarklari = await _satisDepo.fisiGuncelleTxn(
        txn,
        satisId: satis.id!,
        yeniKalemler: yeniSatisKalemleri,
        yeniGenelToplam: yeniToplam,
        yeniOdenenTutar: yeniToplam,
        guncelleyenKullanici: kullanici?.adSoyad,
      );

      for (final girdi in stokFarklari.entries) {
        final urunId = girdi.key;
        final fark = girdi.value;
        final gid = const Uuid().v4();
        stokHareketGidleri[urunId] = gid;
        if (fark > 0) {
          await _stokDepo.stokDusTxn(
            txn,
            gid,
            urunId: urunId,
            miktar: fark,
            kullaniciId: kullanici?.id,
            referansId: satis.id,
            referansTuru: 'fis_guncelleme',
            aciklama: 'Fiş güncelleme (artış): ${satis.fisNo}',
          );
        } else {
          await _stokDepo.stokGirTxn(
            txn,
            gid,
            urunId: urunId,
            miktar: -fark,
            kullaniciId: kullanici?.id,
            referansId: satis.id,
            referansTuru: 'fis_guncelleme',
            aciklama: 'Fiş güncelleme (iade): ${satis.fisNo}',
          );
        }
      }

      if (tutarFarki.abs() > 0.005) {
        if (satis.cariId != null) {
          cariHareketGlobalId = await _cariDepo.hareketEkleTxn(
              txn,
              CariHareketModel(
                cariId: satis.cariId!,
                tarih: DateTime.now(),
                fisTipi: 'Satış',
                fisId: satis.id,
                fisNo: satis.fisNo,
                aciklama: 'Fiş güncelleme: ${satis.fisNo}',
                borc: tutarFarki > 0 ? tutarFarki : 0,
                alacak: tutarFarki < 0 ? -tutarFarki : 0,
                odemeTuru: satis.odemeYontemi,
                kullanici: kullanici?.adSoyad,
              ));
        } else if (satis.odemeYontemi != 'Cari') {
          // 🔴 Derin analizde bulundu: bu dal sadece 'Nakit' ödemeyi
          // kontrol ediyordu — tamamla()'daki orijinal akış ise HER
          // Cari-olmayan ödeme yöntemi (Kredi Kartı, Banka, Havale) için
          // kasa hareketi oluşturuyordu. Kartla/banka ile ödenmiş bir fiş
          // düzenlendiğinde (ürün eklenip/çıkarılıp tutar değiştiğinde)
          // hiçbir kasa/banka düzeltmesi yazılmıyor, kasa raporu fiş
          // tutarından kalıcı olarak sapıyordu.
          kasaHareketId = await _kasaDepo.hareketEkleTxn(
              txn,
              KasaHareketModel(
                hareketTipi: tutarFarki > 0 ? 'Satış' : 'İade',
                tutar: tutarFarki.abs(),
                referansId: satis.id,
                referansTuru: 'fis_guncelleme',
                tarih: DateTime.now(),
                aciklama: 'Fiş güncelleme: ${satis.fisNo}',
                odemeYontemi: satis.odemeYontemi,
              ));
        }
      }
    });

    // Transaction kalıcı oldu — bulut senkronunu şimdi tetikle.
    try {
      for (final girdi in stokHareketGidleri.entries) {
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [girdi.key], limit: 1);
        if (urunSatir.isNotEmpty)
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        final stokSatir = await db.query('stok_hareket',
            where: 'global_id = ?', whereArgs: [girdi.value], limit: 1);
        if (stokSatir.isNotEmpty)
          BulutManager().upsert(
              'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        // Şube bazlı stok payı — best-effort (fark ana stok yönünde).
        await _stokDepo.subeStokPayiUygula(girdi.key, stokFarklari[girdi.key]!);
      }
      final basSatir = await db.query('satislar',
          where: 'id = ?', whereArgs: [satis.id], limit: 1);
      if (basSatir.isNotEmpty)
        BulutManager()
            .upsert('satislar', Map<String, dynamic>.from(basSatir.first));
      final kalemSatirlar = await db
          .query('satis_kalem', where: 'satis_id = ?', whereArgs: [satis.id]);
      for (final ks in kalemSatirlar) {
        BulutManager().upsert('satis_kalem', Map<String, dynamic>.from(ks));
      }
      if (cariHareketGlobalId != null) {
        final cariHareketSatir = await db.query('cari_hareket',
            where: 'global_id = ?', whereArgs: [cariHareketGlobalId], limit: 1);
        if (cariHareketSatir.isNotEmpty)
          BulutManager().upsert('cari_hareket',
              Map<String, dynamic>.from(cariHareketSatir.first));
        if (satis.cariId != null) {
          final cariSatir = await db.query('cari',
              where: 'id = ?', whereArgs: [satis.cariId], limit: 1);
          if (cariSatir.isNotEmpty)
            BulutManager()
                .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
      if (kasaHareketId != null) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'id = ?', whereArgs: [kasaHareketId], limit: 1);
        if (kasaSatir.isNotEmpty)
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
      }
    } catch (_) {
      // Bulut bildirimi best-effort (mevcut davranışla aynı).
    }

    final guncelSatis = await _satisDepo.idileGetir(satis.id!);
    return FisGuncellemeSonucu(
      guncelSatis: guncelSatis ?? satis,
      tutarFarki: tutarFarki,
    );
  }
}
