// lib/servisler/cari_tahsilat_odeme_servisi.dart
//
// Cari Tahsilat/Ödeme (tahsilat_odeme_ekrani.dart) iş mantığının depo
// katmanına taşınmış hali — BorcOdemeIslemServisi ile AYNI desen:
// cari_hareket kaydı + (varsa) gerçek para hareketi (kasa/banka/kredi
// kartı) TEK bir db.transaction() içinde atomik olarak yürütülür, commit
// sonrası bulut senkronu tetiklenir. Davranış, önceden ekranın kendi
// _kaydet()'inde yürüttüğü mantıkla birebir aynıdır.
import '../depolar/cari_deposu.dart';
import '../depolar/kasa_deposu.dart';
import '../depolar/banka_hareket_deposu.dart';
import '../depolar/kredi_karti_deposu.dart';
import '../modeller/cari_hareket_model.dart';
import '../modeller/kasa_hareket_model.dart';
import '../modeller/banka_hareket_model.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class CariTahsilatOdemeServisi {
  final _cariDepo = CariDeposu();
  final _kasaDepo = KasaDeposu();
  final _bankaHareketDepo = BankaHareketDeposu();
  final _krediKartiDepo = KrediKartiDeposu();

  /// [islemTipi]: 'Tahsilat' | 'Odeme'. [odemeTuru]: 'Nakit' | 'Banka' |
  /// 'Havale' | 'Kredi Kartı'. [paraHareketEdiyor] false ise (ör. tedarikçiye
  /// sadece veresiye "Borç Ekle") SADECE cari_hareket oluşur, hiçbir gerçek
  /// para hareketi yaratılmaz. [paraCikiyor] banka hareketinin yönünü
  /// (Giden/Gelen) belirler.
  Future<void> kaydet({
    required int cariId,
    required String cariUnvan,
    required String islemTipi,
    required double tutar,
    required String odemeTuru,
    required String kullanici,
    required bool paraHareketEdiyor,
    required bool paraCikiyor,
    String? aciklama,
    int? bankaHesapId,
    int? krediKartiId,
    // 🆕 Makbuz yeniden yazdırma (kullanıcı isteği 2026-09-22): önceden
    // makbuz numarası SADECE yazdırma anında üretilip cari_hareket'e HİÇ
    // kaydedilmiyordu — Cari Detay'dan sonradan "tekrar bas" denince
    // orijinal makbuz numarası kurtarılamıyordu. Artık çağıran taraf
    // (tahsilat_odeme_ekrani.dart) makbuz numarasını kaydetmeden ÖNCE
    // üretip buraya veriyor, cari_hareket.fis_no'ya yazılıyor.
    String? fisNo,
  }) async {
    final bankaGerekli =
        paraHareketEdiyor && (odemeTuru == 'Banka' || odemeTuru == 'Havale');
    // Şirket kartı yalnız para ÇIKIŞINDA (ödeme) seçilir; tahsilat POS'tur (#38).
    final kartGerekli = paraHareketEdiyor && odemeTuru == 'Kredi Kartı' && paraCikiyor;
    if (bankaGerekli && bankaHesapId == null) {
      throw Exception('Banka hesabı seçilmedi');
    }
    if (kartGerekli && krediKartiId == null) {
      throw Exception('Kredi kartı seçilmedi');
    }

    final db = await Veritabani().db;
    String? cariHareketGlobalId;
    int? kasaHareketId;
    int? bankaHareketId;
    int? krediHareketId;

    await db.transaction((txn) async {
      cariHareketGlobalId = await _cariDepo.hareketEkleTxn(
          txn,
          CariHareketModel(
            cariId: cariId,
            tarih: DateTime.now(),
            fisTipi: islemTipi,
            fisNo: fisNo,
            aciklama: (aciklama == null || aciklama.trim().isEmpty)
                ? '$islemTipi - $odemeTuru'
                : aciklama.trim(),
            borc: islemTipi == 'Odeme' ? tutar : 0,
            alacak: islemTipi == 'Tahsilat' ? tutar : 0,
            odemeTuru: odemeTuru,
            kullanici: kullanici,
          ));

      // Bu cari_hareket'in YEREL id'sini alıp kasa hareketine referans
      // olarak veriyoruz — cari_hareket_ekrani.dart bu iptal edildiğinde
      // bağlı kasa hareketini güvenilir şekilde bulup otomatik tersine
      // çevirebiliyor (bkz. CariDeposu.hareketIptalEt).
      int? cariHareketLocalId;
      if (cariHareketGlobalId != null) {
        final satir = await txn.query('cari_hareket',
            columns: ['id'],
            where: 'global_id = ?',
            whereArgs: [cariHareketGlobalId],
            limit: 1);
        if (satir.isNotEmpty) cariHareketLocalId = satir.first['id'] as int;
      }

      if (paraHareketEdiyor) {
        if (odemeTuru == 'Kredi Kartı' && !paraCikiyor) {
          // 🔴 DERİN DENETİM (2026-11-09, #38): müşteriden kartla tahsilat
          // ŞİRKETİN KENDİ kredi kartının kullanılan limitini düşürüyordu
          // (borcu ödenmiş gibi). Müşteri kartı POS'tan çekilir — satıştaki
          // kartlı ödemeyle aynı: kasaya 'Kredi Kartı' yöntemli giriş.
          kasaHareketId = await _kasaDepo.hareketEkleTxn(
              txn,
              KasaHareketModel(
                hareketTipi: 'Tahsilat',
                tutar: tutar,
                tarih: DateTime.now(),
                referansId: cariHareketLocalId,
                referansTuru: 'cari_hareket',
                aciklama: '$cariUnvan - $islemTipi (POS)',
                odemeYontemi: 'Kredi Kartı',
              ));
        } else if (odemeTuru == 'Nakit') {
          kasaHareketId = await _kasaDepo.hareketEkleTxn(
              txn,
              KasaHareketModel(
                hareketTipi: islemTipi == 'Tahsilat' ? 'Tahsilat' : 'Ödeme',
                tutar: tutar,
                tarih: DateTime.now(),
                referansId: cariHareketLocalId,
                referansTuru: 'cari_hareket',
                aciklama: '$cariUnvan - $islemTipi',
              ));
        } else if (odemeTuru == 'Banka' || odemeTuru == 'Havale') {
          bankaHareketId = await _bankaHareketDepo.ekleTxn(
              txn,
              BankaHareketModel(
                bankaHesapId: bankaHesapId!,
                islemTipi: paraCikiyor ? 'Giden' : 'Gelen',
                tutar: tutar,
                aciklama: '$cariUnvan - $islemTipi',
                tarih: DateTime.now(),
                // 🔴 DEEP_AUDIT (kendi-keşif turu, 2026-09-21):
                // CariDeposu.hareketIptalEt() bu hareketi bulup tersine
                // çevirebilsin diye (kasa dalıyla AYNI desen — nakit
                // tahsilat/ödeme zaten bunu yapıyordu, banka/kredi kartı
                // tarafı eksikti).
                referansId: cariHareketLocalId,
                referansTuru: 'cari_hareket',
              ));
        } else if (odemeTuru == 'Kredi Kartı') {
          // 🔴 Derin analizde bulundu: yön (paraCikiyor) hiç dikkate
          // alınmıyordu, tutar her zaman pozitif veriliyordu —
          // limitDegistirTxn pozitif delta'yı her zaman "harcama" (kullanılan
          // limiti artırma) sayıyor (bkz. o metodun içindeki 'yon' mantığı).
          // Banka/Havale dalı zaten paraCikiyor'a göre yön belirliyordu
          // (satır yukarıda: islemTipi: paraCikiyor ? 'Giden' : 'Gelen'),
          // kredi kartı dalı bunu hiç yapmıyordu. Somut hata: bir MÜŞTERİDEN
          // "Tahsilat" (para İÇERİ giriyor, paraCikiyor=false) ödeme şekli
          // "Kredi Kartı" seçilirse, şirketin kendi kartında yanlışlıkla bir
          // HARCAMA gibi işlenip kullanılan limit artıyordu. Artık para
          // dışarı çıkıyorsa (ödeme/harcama) pozitif, içeri giriyorsa
          // (tahsilat/iade — kart kullanımını azaltır) negatif delta veriliyor.
          krediHareketId = await _krediKartiDepo.limitDegistirTxn(
              txn, krediKartiId!, paraCikiyor ? tutar : -tutar,
              aciklama: '$cariUnvan - $islemTipi',
              // 🔴 DEEP_AUDIT (kendi-keşif turu, 2026-09-21): bkz. Banka
              // dalındaki aynı gerekçe.
              referansId: cariHareketLocalId,
              referansTuru: 'cari_hareket');
        }
      }
    });

    // Transaction kalıcı oldu — bulut senkronunu şimdi tetikle (bkz.
    // KasaDeposu.hareketEkleTxn'deki aynı gerekçe: commit'ten önce
    // senkronlamak, geri alınırsa buluta var olmayan satır gönderirdi).
    Future<void> sync(String tablo, dynamic id) async {
      if (id == null) return;
      await BulutManager().satiriBildir(db, tablo, id);
    }

    if (cariHareketGlobalId != null) {
      final satir = await db.query('cari_hareket',
          where: 'global_id = ?',
          whereArgs: [cariHareketGlobalId],
          limit: 1);
      if (satir.isNotEmpty) {
        BulutManager()
            .upsert('cari_hareket', Map<String, dynamic>.from(satir.first));
      }
    }
    await BulutManager().satiriBildir(db, 'cari', cariId);
    await sync('kasa_hareketleri', kasaHareketId);
    if (bankaHareketId != null) {
      await sync('banka_hareketler', bankaHareketId);
      await BulutManager().satiriBildir(db, 'banka_hesaplar', bankaHesapId);
    }
    if (krediHareketId != null) {
      await sync('kredi_karti_hareket', krediHareketId);
      await BulutManager().satiriBildir(db, 'kredi_kartlari', krediKartiId);
    }
  }
}
