// lib/servisler/virman_servisi.dart
//
// Madde 2 mimari denetimi — katman ihlali temizliği: virman_ekrani.dart
// önceden Kasa/Banka/Kredi Kartı arası virmanı doğrudan kendisi, ekran
// içinde açtığı bir db.transaction ile yürütüyordu (business logic UI
// katmanında yaşıyordu). Atomik yazım + bulut bildirimi + onay merkezi
// kaydı BİREBİR buraya taşındı — DAVRANIŞ DEĞİŞMEDİ.
import '../depolar/kasa_deposu.dart';
import '../depolar/banka_hareket_deposu.dart';
import '../depolar/kredi_karti_deposu.dart';
import '../modeller/kasa_hareket_model.dart';
import '../modeller/banka_hesap_model.dart';
import '../modeller/banka_hareket_model.dart';
import '../modeller/kredi_karti_model.dart';
import 'onay_merkezi_servisi.dart';
import 'bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class VirmanServisi {
  final _kasaDepo = KasaDeposu();

  /// Kasa/Banka/Kredi Kartı arasındaki HER ikili kombinasyonu TEK
  /// transaction'da, HER İKİ tarafı da güncelleyerek yazar. "Havale/EFT"
  /// ve "Diğer" bakiyesi takip edilen gerçek bir hesap DEĞİL (salt
  /// kategori etiketi) — taraf olduklarında dürüstçe atlanır (yanlış bir
  /// "hesap" icat edilmez), çağıran taraf (ekran) bunu kullanıcıya
  /// açıklar.
  Future<void> virmanYap({
    required String kaynakHesap,
    required String hedefHesap,
    required double tutar,
    required String aciklama,
    BankaHesapModel? seciliBanka,
    KrediKartiModel? seciliKart,
  }) async {
    final now = DateTime.now();
    final kasaDahil = kaynakHesap == 'Kasa' || hedefHesap == 'Kasa';

    final db = await Veritabani().db;
    int? kartHareketId;
    await db.transaction((txn) async {
      if (kaynakHesap == 'Kasa') {
        await _kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
          hareketTipi: 'Virman Çıkış', tutar: tutar, tarih: now,
          aciklama: '$aciklama (Çıkış)', referansTuru: 'virman'));
      } else if (hedefHesap == 'Kasa') {
        await _kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
          hareketTipi: 'Virman Giriş', tutar: tutar, tarih: now,
          aciklama: '$aciklama (Giriş)', referansTuru: 'virman'));
      }
      if (kaynakHesap == 'Banka' && seciliBanka != null) {
        await BankaHareketDeposu().ekleTxn(txn, BankaHareketModel(
          bankaHesapId: seciliBanka.id!, islemTipi: 'Giden',
          tutar: tutar, tarih: now, aciklama: '$aciklama (Çıkış)'));
      } else if (hedefHesap == 'Banka' && seciliBanka != null) {
        await BankaHareketDeposu().ekleTxn(txn, BankaHareketModel(
          bankaHesapId: seciliBanka.id!, islemTipi: 'Gelen',
          tutar: tutar, tarih: now, aciklama: '$aciklama (Giriş)'));
      }
      if (kaynakHesap == 'Kredi Kartı' && seciliKart != null) {
        // Kart KAYNAK ise: para kart borcundan çıkıp başka hesaba gidiyor
        // demektir — bu bir "avans" gibi kartın kullanılan limitini
        // ARTIRIR (delta pozitif = harcama).
        kartHareketId = await KrediKartiDeposu().limitDegistirTxn(
            txn, seciliKart.id!, tutar, aciklama: '$aciklama (Avans)');
      } else if (hedefHesap == 'Kredi Kartı' && seciliKart != null) {
        // Kart HEDEF ise: kart ÖDENİYOR demektir — kullanılan limit
        // AZALIR (delta negatif = ödeme).
        kartHareketId = await KrediKartiDeposu().limitDegistirTxn(
            txn, seciliKart.id!, -tutar, aciklama: '$aciklama (Ödeme)');
      }
    });

    // KrediKartiDeposu.limitDegistirTxn kendi durable sync_queue yazımını
    // yapmıyor (bkz. KrediKartiDeposu.nakitOdemeYap'taki AYNI desen) —
    // bu yüzden transaction kapandıktan SONRA, o dosyadaki established
    // pattern'le aynı şekilde elle bildiriliyor. Kasa ve Banka tarafları
    // kendi ekleTxn'leri içinde ZATEN atomik/durable (SyncKuyrukYazici)
    // olduğundan burada tekrar bildirilmiyor.
    if (seciliKart != null && (kaynakHesap == 'Kredi Kartı' || hedefHesap == 'Kredi Kartı')) {
      final kartSatir = await db.query('kredi_kartlari',
          where: 'id = ?', whereArgs: [seciliKart.id], limit: 1);
      if (kartSatir.isNotEmpty) {
        BulutManager().upsert('kredi_kartlari', Map<String, dynamic>.from(kartSatir.first));
      }
      if (kartHareketId != null) {
        final kartHareketSatir = await db.query('kredi_karti_hareket',
            where: 'id = ?', whereArgs: [kartHareketId], limit: 1);
        if (kartHareketSatir.isNotEmpty) {
          BulutManager().upsert('kredi_karti_hareket',
              Map<String, dynamic>.from(kartHareketSatir.first));
        }
      }
    }

    if (kasaDahil && kaynakHesap == 'Kasa') {
      OnayMerkeziServisi().kaydet(
        tur: OnayTuru.kasaCikisi,
        tutar: tutar,
        esikTutar: OnayEsikleri.kasaCikisiTutari,
        referansTuru: 'virman',
        aciklama: '$kaynakHesap → $hedefHesap: $aciklama',
      );
    }
  }
}
