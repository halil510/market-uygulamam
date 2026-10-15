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
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../servisler/log_servisi.dart';
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

  // 🔴🔴 KRİTİK DÜZELTME (kendi-keşif turu — Promosyon modülü denetimi,
  // kullanıcı onayıyla): satis_kalem.iskonto_oran/iskonto_tutar HER
  // ZAMAN 0 yazılıyordu — sepetteki GERÇEK indirim (promosyon, DB
  // kayıtlı indirimli fiyat, ürün indirim oranı, elle indirim — bkz.
  // SepetProvider._fiyatHesapla) doğrudan k.birimFiyat'a gömülüyor ama
  // kalem satırına hiç YAZILMIYORDU. Somut etki: Gün Sonu Excel
  // raporundaki "İndirim" sütunu (bkz. gunluk_rapor_ekrani.dart)
  // promosyon uygulanan satışlarda bile HER ZAMAN 0 gösteriyordu —
  // işletme promosyonların gerçek etkisini raporlardan asla göremiyordu.
  // Artık kalemin GERÇEKTEN ne kadar indirimli satıldığı, ürünün güncel
  // katalog fiyatı (k.urun.satisFiyati) ile fiilen tahsil edilen birim
  // fiyat (k.birimFiyat) arasındaki farktan hesaplanıp yazılıyor —
  // sepetin/fiyat hesaplama mantığının KENDİSİNE hiç dokunulmadı, sadece
  // KAYIT anında bu fark artık kayboluyor.
  SatisKalemModel _kalemOlustur(SepetKalem k, {required int satisId}) {
    // Müşterinin liste fiyatı (bayide toptan fiyatı): bayi fiyatı indirim
    // olarak kaydedilmez — Toptan Satış ekranıyla aynı (2026-10-08).
    final bazFiyat = k.listeFiyat;
    final indirimBirim = bazFiyat > k.birimFiyat ? bazFiyat - k.birimFiyat : 0.0;
    final iskontoOran = bazFiyat > 0 ? (indirimBirim / bazFiyat * 100) : 0.0;
    final iskontoTutar = indirimBirim * k.miktar;
    return SatisKalemModel(
      satisId: satisId,
      urunId: k.urun.id!,
      urunAdi: k.urun.urunAdi,
      barkod: k.urun.barkod,
      miktar: k.miktar,
      birimFiyat: k.birimFiyat,
      toplamTutar: k.toplamTutar,
      iskontoOran: iskontoOran,
      iskontoTutar: iskontoTutar,
      kdvOran: double.tryParse(k.urun.kdvOran) ?? 18,
      kdvTutar: k.kdvTutar,
      netFiyat: k.netFiyat,
      alisFiyat: k.urun.alisFiyat,
      alisFiyatKdv: k.urun.alisFiyatKdvDahil,
    );
  }

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

    final satisKalemler =
        kalemler.map((k) => _kalemOlustur(k, satisId: 0)).toList();

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
    // FAZ 5 (Lot/SKT — kullanıcı onayıyla): lot_takibi açık bir ürün
    // birden fazla lottan tüketilebildiği için artık ürün başına BİRDEN
    // FAZLA stok_hareket global_id'si olabiliyor (bkz. StokDeposu.
    // stokDusFefoTxn). Bulut senkronu buna göre her gid'i tek tek bildirir.
    final stokHareketGidleri = <int, List<String>>{};
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
        // Aynı ürün sepette birden fazla satırda olabilir (tartılı ürün,
        // farklı fiyat): kimlikler EKLENİR — önceden üzerine yazılıyordu ve
        // ilk satırın stok hareketi buluta anında bildirilmiyordu.
        (stokHareketGidleri[k.urun.id!] ??= []).addAll(await _stokDepo.stokDusFefoTxn(
          txn,
          urunId: k.urun.id!,
          miktar: k.miktar,
          kullaniciId: kullanici?.id,
          referansId: satisId,
          referansTuru: 'satis',
        ));
      }

      await _odemeHareketleriTxn(
        txn,
        satisId: satisId,
        fisNo: fisNo,
        tarih: tarih,
        cariId: musteri?.id,
        kullaniciAd: kullanici?.adSoyad,
        kullaniciId: kullanici?.id,
        genelToplam: genelToplam,
        odemeYontemi: odemeYontemi,
        odenenTutar: odenenTutar,
        karmaKalemler: karmaKalemler,
        kasaGlobalIdleri: kasaGlobalIdleri,
        cariGlobalIdleri: cariGlobalIdleri,
      );
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
      } catch (e, st) {
        // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, "tam ERP" denetimi,
        // 2026-09-22): burası ÖNCEDEN hatayı TAMAMEN sessizce yutuyordu
        // (boş catch) — musteri_puan.cari_id'de UNIQUE kısıt olmadığı
        // için PuanServisi.puanEkle()'deki ON CONFLICT(cari_id) cümlesi
        // HER ZAMAN SQL hatası fırlatıyordu (bkz. migrasyon v77'nin
        // düzelttiği kök neden) ve kimse fark etmedi çünkü hata hiçbir
        // yere düşmüyordu. Puan hatası satışı yine geçersiz kılmaz —
        // ama artık en azından loglanıyor, sessiz/görünmez kalmıyor.
        LogServisi().hata('SatisTamamlamaServisi.puanEkle', hata: e, yigin: st);
      }
    }

    return SatisTamamlamaSonucu(
      satisId: satisId,
      fisNo: fisNo,
      tarih: tarih,
      kalemler: satisKalemler,
    );
  }

  /// Ödeme yöntemine göre kasa + cari hareketlerini VERİLEN transaction
  /// içinde yazar. tamamla() ve fisiGuncelle() (ödeme yöntemi/cari değişince)
  /// AYNI kuralları kullansın diye ortak yerde (davranış birebir korundu).
  Future<void> _odemeHareketleriTxn(
    dynamic txn, {
    required int satisId,
    required String fisNo,
    required DateTime tarih,
    required int? cariId,
    required String? kullaniciAd,
    required int? kullaniciId,
    required double genelToplam,
    required String odemeYontemi,
    required double odenenTutar,
    required List<Map<String, dynamic>>? karmaKalemler,
    required List<String> kasaGlobalIdleri,
    required List<String> cariGlobalIdleri,
  }) async {
    if (karmaKalemler != null) {
      final digerYontemler =
          karmaKalemler.where((k) => k['yontem'] != 'Cari');
      final gruplar = <String, double>{};
      for (final k in digerYontemler) {
        final y = k['yontem'] as String;
        gruplar[y] = (gruplar[y] ?? 0) + (k['tutar'] as num).toDouble();
      }
      // Para üstü kasaya gelir yazılmasın: alınan toplam satış tutarını
      // aşıyorsa fazlalık Nakit grubundan düşülür (çekmeceye giren gerçek
      // tutar = genelToplam).
      // Çoklu ödeme ekranından tek yöntemle ödenen satış "Karma" etiketi
      // almasın (canlı test 2026-10-08: düz nakit satış "Nakit Satış
      // (Karma)" görünüyordu).
      final gercekKarma =
          karmaKalemler.map((k) => k['yontem']).toSet().length > 1;
      final cariKismi = karmaKalemler
          .where((k) => k['yontem'] == 'Cari')
          .fold(0.0, (s, k) => s + (k['tutar'] as num).toDouble());
      final fazla = gruplar.values.fold(0.0, (s, v) => s + v) +
          cariKismi -
          genelToplam;
      if (fazla > 0.005 && (gruplar['Nakit'] ?? 0) > 0) {
        final dus = fazla < gruplar['Nakit']! ? fazla : gruplar['Nakit']!;
        gruplar['Nakit'] = gruplar['Nakit']! - dus;
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
              aciklama: gercekKarma
                  ? 'Satış: $fisNo (Karma: ${girdi.key})'
                  : 'Satış: $fisNo',
              kullaniciId: kullaniciId,
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
            // Para üstü hariç: kasaya en fazla satış tutarı girer.
            tutar: odenenTutar > genelToplam ? genelToplam : odenenTutar,
            referansId: satisId,
            referansTuru: 'satis',
            tarih: tarih,
            aciklama: 'Satış: $fisNo',
            kullaniciId: kullaniciId,
            odemeYontemi: odemeYontemi,
          ));
      kasaGlobalIdleri.add(kgid);
    }

    if (karmaKalemler != null) {
      final cariTutar = karmaKalemler
          .where((k) => k['yontem'] == 'Cari')
          .fold(0.0, (s, k) => s + (k['tutar'] as num).toDouble());
      if (cariId != null && cariTutar > 0.005) {
        cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: cariId,
              tarih: tarih,
              fisTipi: 'Satış',
              fisId: satisId,
              fisNo: fisNo,
              aciklama: 'Veresiye (Karma): $fisNo',
              borc: cariTutar,
              alacak: 0,
              odemeTuru: 'Cari',
              kullanici: kullaniciAd,
            )));
      }
      final digerTutar = karmaKalemler
          .where((k) => k['yontem'] != 'Cari')
          .fold(0.0, (s, k) => s + (k['tutar'] as num).toDouble());
      if (cariId != null && digerTutar > 0.005) {
        final yontemler = karmaKalemler
            .where((k) => k['yontem'] != 'Cari')
            .map((k) => k['yontem'] as String)
            .toSet()
            .join('+');
        cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: cariId,
              tarih: tarih,
              fisTipi: 'Satış',
              fisId: satisId,
              fisNo: fisNo,
              aciklama:
                  karmaKalemler.map((k) => k['yontem']).toSet().length > 1
                  ? '$yontemler Satış (Karma): $fisNo — bakiyeyi etkilemez'
                  : '$yontemler Satış: $fisNo — bakiyeyi etkilemez',
              borc: digerTutar,
              alacak: digerTutar,
              odemeTuru: yontemler,
              kullanici: kullaniciAd,
            )));
      }
    } else if (cariId != null && odemeYontemi == 'Cari') {
      cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
          txn,
          CariHareketModel(
            cariId: cariId,
            tarih: tarih,
            fisTipi: 'Satış',
            fisId: satisId,
            fisNo: fisNo,
            aciklama: 'Veresiye: $fisNo',
            borc: genelToplam,
            alacak: 0,
            odemeTuru: 'Cari',
            kullanici: kullaniciAd,
          )));
    } else if (cariId != null && genelToplam > 0.005) {
      cariGlobalIdleri.add(await _cariDepo.hareketEkleTxn(
          txn,
          CariHareketModel(
            cariId: cariId,
            tarih: tarih,
            fisTipi: 'Satış',
            fisId: satisId,
            fisNo: fisNo,
            aciklama: '$odemeYontemi Satış: $fisNo — bakiyeyi etkilemez',
            borc: genelToplam,
            alacak: genelToplam,
            odemeTuru: odemeYontemi,
            kullanici: kullaniciAd,
          )));
    }
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
    required Map<int, List<String>> stokHareketGidleri,
    required List<String> kasaGlobalIdleri,
    required List<String> cariGlobalIdleri,
    required CariModel? musteri,
  }) async {
    try {
      // DB'den geri okuyarak (bkz. SatisDeposu.bulutaBildir — bellekteki
      // model buluta ikinci bir satış ve satis_id=0 kalemler yolluyordu).
      await _satisDepo.bulutaBildir(satisId);
      // Ürün başına BİR kez (aynı ürün birden fazla satırdaysa tekrar etmez).
      for (final MapEntry(key: urunId, value: gidler) in stokHareketGidleri.entries) {
        if (gidler.isEmpty) continue;
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        // FAZ 5: lot_takibi açık ürünlerde BİRDEN FAZLA stok_hareket
        // satırı oluşabiliyor (bkz. StokDeposu.stokDusFefoTxn) — her biri
        // tek tek bildirilir.
        for (final gid in gidler) {
          final stokSatir = await db.query('stok_hareket',
              where: 'global_id = ?', whereArgs: [gid], limit: 1);
          if (stokSatir.isNotEmpty) {
            BulutManager().upsert(
                'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
          }
        }
      }
      // 🔴🔴 FAZ 1 madde 2: karma ödemede artık BİRDEN FAZLA kasa hareketi
      // oluşabiliyor (her ödeme yöntemi için ayrı satır) — bu yüzden
      // "referans_id + ORDER BY id DESC LIMIT 1" yerine, oluşturulan HER
      // global_id tek tek buluta bildiriliyor (aksi halde karma ödemedeki
      // ilk kasa hareketi sessizce senkronsuz kalırdı).
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
      if (musteri != null &&
          musteri.id != null &&
          cariGlobalIdleri.isNotEmpty) {
        final cariSatir = await db.query('cari',
            where: 'id = ?', whereArgs: [musteri.id], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager()
              .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e, st) {
      // Bulut bildirimi best-effort — satış zaten kalıcı olarak kaydedildi,
      // sync hatası satışı geçersiz kılmamalı. Kuyruk kayıtları zaten
      // transaction içinde yazıldı; anlık bildirim bir sonraki turda gider.
      LogServisi().uyari('SatisTamamlamaServisi bulut bildirimi', hata: e, yigin: st);
    }

    // Şube bazlı stok payı (sube_urun). 🔴 Önceden yukarıdaki bulut
    // bildirimiyle AYNI try içindeydi: bulutaBildir() hata atınca satıştaki
    // HİÇBİR ürünün şube stoğu düşülmüyordu. Fark POZİTİF (stok DÜŞTÜ)
    // verilir — subeStokPayiUygula'nın beklediği yön; kendi hatasını yutar.
    for (final k in kalemler) {
      await _stokDepo.subeStokPayiUygula(k.urun.id!, k.miktar);
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
    // Ekranda seçilen yeni ödeme bilgisi. Fiş önceden PEŞİN (Nakit/Kart)
    // kesilmiş olsa bile kullanıcı düzenlerken "Cari"ye çevirebilir: bu
    // durumda eski kasa hareketi ters çevrilir, yeni ödeme (cari borç dahil)
    // yazılır ve fişin cari/ödeme yöntemi güncellenir.
    CariModel? musteri,
    String? odemeYontemi,
    double? odenenTutar,
    List<Map<String, dynamic>>? karmaKalemler,
    int? subeId,
  }) async {
    final eskiToplam = satis.genelToplam;
    // Fiş geri çağrılırken carisi sepete yüklenir; bu yüzden sepetteki müşteri
    // (yoksa: kasiyer kaldırdı) fişin yeni carisidir.
    final yeniCariId = musteri?.id;
    final yeniOdemeYontemi = odemeYontemi ?? satis.odemeYontemi;
    // Bir müşteriye PEŞİN (Nakit/Kart) kesilmiş fişin tutarı değişirse eski
    // "bakiyeyi etkilemez" cari satırı yanlış tutarda kalır; bu yüzden ödeme
    // baştan yazılır (eski kasa/cari kaydı geri alınır, yenisi yazılır).
    final pesinCariFisTutarDegisti = satis.cariId != null &&
        satis.odemeYontemi != 'Cari' &&
        (yeniGenelToplam - satis.genelToplam).abs() > 0.005;
    final odemeDegisti = odemeYontemi != null &&
        (karmaKalemler != null ||
            yeniOdemeYontemi != satis.odemeYontemi ||
            yeniCariId != satis.cariId ||
            pesinCariFisTutarDegisti);
    // Peşin (MKP...) kesilmiş fiş Cari'ye çevrilirse doğrudan cariye
    // satıştaki gibi CRI... numarası alır. Numara üretimi kendi transaction'ını
    // açtığı için, fiş transaction'ından ÖNCE yapılmalı (iç içe → kilitlenir).
    // Tersi de geçerli: cari kaldırılıp Nakit'e çevrilen CRI... fiş MKP... olur.
    String? yeniFisNo;
    final eskiNo = (satis.fisNo ?? '').toUpperCase();
    if (odemeDegisti && yeniCariId != null && eskiNo.startsWith('MKP')) {
      yeniFisNo = await Veritabani().fisNoUret('cari_satis', subeId: subeId ?? 1);
    } else if (odemeDegisti && yeniCariId == null && eskiNo.startsWith('CRI')) {
      yeniFisNo = await Veritabani().fisNoUret('satis', subeId: subeId ?? 1);
    }
    final yeniToplam = yeniGenelToplam;
    final tutarFarki = yeniToplam - eskiToplam;

    final yeniSatisKalemleri = yeniKalemler
        .map((k) => _kalemOlustur(k, satisId: satis.id!))
        .toList();

    final db = await Veritabani().db;
    final stokHareketGidleri = <int, String>{};
    String? cariHareketGlobalId;
    int? kasaHareketId;
    final ekKasaGidleri = <String>[];
    final ekCariGidleri = <String>[];

    late final Map<int, double> stokFarklari;
    var adim = 'fiş kalemleri';
    try {
    await db.transaction((txn) async {
      stokFarklari = await _satisDepo.fisiGuncelleTxn(
        txn,
        satisId: satis.id!,
        yeniKalemler: yeniSatisKalemleri,
        yeniGenelToplam: yeniToplam,
        yeniOdenenTutar: yeniToplam,
        guncelleyenKullanici: kullanici?.adSoyad,
      );

      adim = 'stok farkı';
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

      if (odemeDegisti) {
        final tarih = DateTime.now();
        adim = 'eski kasa hareketi okuma/ters çevirme';
        // 1) ESKİ ödemenin net etkisini ters çevir (bu fişe bağlı tüm
        //    önceki satış/güncelleme hareketlerinin toplamı).
        final kasaRows = await txn.rawQuery(
            'SELECT odeme_yontemi, hareket_tipi, tutar FROM kasa_hareketleri '
            "WHERE referans_id = ? AND referans_turu IN ('satis','fis_guncelleme') "
            'AND deleted_at IS NULL',
            [satis.id]);
        final kasaNet = <String, double>{};
        for (final r in kasaRows) {
          // Eski (yöntemi yazılmamış) satırlar tek yöntemli Nakit satıştır;
          // 'Karma' diye bir kasa yöntemi yoktur.
          final y = (r['odeme_yontemi'] as String?) ??
              (satis.odemeYontemi == 'Karma' ? 'Nakit' : satis.odemeYontemi);
          final t = (r['tutar'] as num?)?.toDouble() ?? 0;
          kasaNet[y] = (kasaNet[y] ?? 0) +
              (KasaHareketModel.girisMi(r['hareket_tipi'] as String? ?? '')
                  ? t
                  : -t);
        }
        for (final g in kasaNet.entries) {
          if (g.value.abs() <= 0.005) continue;
          final kgid = const Uuid().v4();
          await _kasaDepo.hareketEkleTxn(
              txn,
              KasaHareketModel(
                globalId: kgid,
                hareketTipi: g.value > 0 ? 'İade' : 'Satış',
                tutar: g.value.abs(),
                referansId: satis.id,
                referansTuru: 'fis_guncelleme',
                tarih: tarih,
                aciklama: 'Fiş ödeme değişti (eski ödeme düzeltmesi): ${satis.fisNo}',
                kullaniciId: kullanici?.id,
                odemeYontemi: g.key,
              ));
          ekKasaGidleri.add(kgid);
        }
        adim = 'eski cari hareketi';
        // Eski cari satırları (borç, nötr "bakiyeyi etkilemez", önceki fiş
        // güncelleme farkları) tamamen gizlenir (is_deleted=1, silinmez) ve
        // eski carinin bakiyesi yeniden hesaplanır. Ters kayıt eklenmez: aksi
        // halde cari ekstresinde ve fişin Satış Detayı'nda (ödeme dağılımı
        // 'alacak=0 ve borç>0' satırlardan okunur) fiş eski carinin ödemesi
        // gibi görünmeye devam ederdi.
        if (satis.cariId != null) {
          final cariRows = await txn.query('cari_hareket',
              // Toptan/bayi fişlerinin cari satırları 'Toptan Satış' tipiyle yazılır.
              where:
                  "fis_id = ? AND fis_tipi IN ('Satış','Toptan Satış','Toptan Satış (Sipariş)') "
                  'AND cari_id = ? AND is_deleted = 0',
              whereArgs: [satis.id, satis.cariId]);
          final simdi = tarih.toIso8601String();
          for (final r in cariRows) {
            await txn.update('cari_hareket',
                {'is_deleted': 1, 'last_updated': simdi},
                where: 'id = ?', whereArgs: [r['id']]);
            final gizlenen = await txn.query('cari_hareket',
                where: 'id = ?', whereArgs: [r['id']], limit: 1);
            if (gizlenen.isNotEmpty) {
              await SyncKuyrukYazici.ekleTxn(txn,
                  tablo: 'cari_hareket',
                  veri: Map<String, dynamic>.from(gizlenen.first));
              final gid = gizlenen.first['global_id']?.toString();
              if (gid != null && gid.isNotEmpty) ekCariGidleri.add(gid);
            }
          }
          if (cariRows.isNotEmpty) {
            await txn.rawUpdate('''
              UPDATE cari SET bakiye = ROUND((SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0)
                FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0
              ), 2), last_updated = ?
              WHERE id = ?
            ''', [satis.cariId, simdi, satis.cariId]);
            final guncelCari = await txn.query('cari',
                where: 'id = ?', whereArgs: [satis.cariId], limit: 1);
            if (guncelCari.isNotEmpty) {
              await SyncKuyrukYazici.ekleTxn(txn,
                  tablo: 'cari',
                  veri: Map<String, dynamic>.from(guncelCari.first));
            }
          }
        }

        // 2) YENİ ödemeyi, normal satıştaki kurallarla yaz.
        adim = 'yeni ödeme kasa/cari hareketi';
        await _odemeHareketleriTxn(
          txn,
          satisId: satis.id!,
          fisNo: yeniFisNo ?? satis.fisNo ?? '',
          tarih: tarih,
          cariId: yeniCariId,
          kullaniciAd: kullanici?.adSoyad,
          kullaniciId: kullanici?.id,
          genelToplam: yeniToplam,
          odemeYontemi: yeniOdemeYontemi,
          odenenTutar: odenenTutar ?? yeniToplam,
          karmaKalemler: karmaKalemler,
          kasaGlobalIdleri: ekKasaGidleri,
          cariGlobalIdleri: ekCariGidleri,
        );

        adim = 'fiş başlığı güncelleme';
        // 3) Fiş başlığı: cari + ödeme yöntemi + ödenen tutar (satislar'da cari_adi kolonu yok).
        await txn.update(
            'satislar',
            {
              if (yeniFisNo != null) 'fis_no': yeniFisNo,
              'cari_id': yeniCariId,
              'odeme_yontemi': yeniOdemeYontemi,
              'odenen_tutar': odenenTutar ?? yeniToplam,
              'last_updated': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [satis.id]);
        final basSatir = await txn
            .query('satislar', where: 'id = ?', whereArgs: [satis.id], limit: 1);
        if (basSatir.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'satislar', veri: Map<String, dynamic>.from(basSatir.first));
        }
      } else if (tutarFarki.abs() > 0.005) {
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
    } catch (e, st) {
      LogServisi().hata('SatisTamamlamaServisi.fisiGuncelle ($adim)', hata: e, yigin: st);
      throw Exception('Adım: $adim → $e');
    }

    // Transaction kalıcı oldu — bulut senkronunu şimdi tetikle.
    try {
      for (final girdi in stokHareketGidleri.entries) {
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [girdi.key], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        final stokSatir = await db.query('stok_hareket',
            where: 'global_id = ?', whereArgs: [girdi.value], limit: 1);
        if (stokSatir.isNotEmpty) {
          BulutManager().upsert(
              'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        }
        // Şube bazlı stok payı — best-effort (fark ana stok yönünde).
        await _stokDepo.subeStokPayiUygula(girdi.key, stokFarklari[girdi.key]!);
      }
      final basSatir = await db.query('satislar',
          where: 'id = ?', whereArgs: [satis.id], limit: 1);
      if (basSatir.isNotEmpty) {
        BulutManager()
            .upsert('satislar', Map<String, dynamic>.from(basSatir.first));
      }
      final kalemSatirlar = await db
          .query('satis_kalem', where: 'satis_id = ?', whereArgs: [satis.id]);
      for (final ks in kalemSatirlar) {
        BulutManager().upsert('satis_kalem', Map<String, dynamic>.from(ks));
      }
      if (cariHareketGlobalId != null) {
        final cariHareketSatir = await db.query('cari_hareket',
            where: 'global_id = ?', whereArgs: [cariHareketGlobalId], limit: 1);
        if (cariHareketSatir.isNotEmpty) {
          BulutManager().upsert('cari_hareket',
              Map<String, dynamic>.from(cariHareketSatir.first));
        }
        if (satis.cariId != null) {
          final cariSatir = await db.query('cari',
              where: 'id = ?', whereArgs: [satis.cariId], limit: 1);
          if (cariSatir.isNotEmpty) {
            BulutManager()
                .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
          }
        }
      }
      for (final gid in ekKasaGidleri) {
        final ks = await db.query('kasa_hareketleri',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (ks.isNotEmpty) {
          BulutManager()
              .upsert('kasa_hareketleri', Map<String, dynamic>.from(ks.first));
        }
      }
      for (final gid in ekCariGidleri) {
        final ch = await db.query('cari_hareket',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (ch.isNotEmpty) {
          BulutManager()
              .upsert('cari_hareket', Map<String, dynamic>.from(ch.first));
        }
      }
      if (odemeDegisti) {
        for (final cid in {satis.cariId, yeniCariId}) {
          if (cid == null) continue;
          final cs = await db.query('cari', where: 'id = ?', whereArgs: [cid], limit: 1);
          if (cs.isNotEmpty) {
            BulutManager().upsert('cari', Map<String, dynamic>.from(cs.first));
          }
        }
      }
      if (kasaHareketId != null) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'id = ?', whereArgs: [kasaHareketId], limit: 1);
        if (kasaSatir.isNotEmpty) {
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
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
