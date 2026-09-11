// lib/servisler/borc_odeme_islem_servisi.dart
//
// BORÇ ÖDEME İŞ MANTIĞI — TEK MERKEZİ NOKTA
// ------------------------------------------------------------------
// Önceden bu mantık iki farklı yerde, iki farklı eksiklikle tekrarlanmıştı:
//   1) borc_dashboard_ekrani.dart içindeki _OdemeBottomSheet — banka
//      hesabı seçimi ve banka hareketi doğru çalışıyordu, ama kredi
//      kartı seçimi ve Gider (masraf) kaydı YOKTU.
//   2) borc_odeme_ekrani.dart (bağımsız ekran) — ödeme yöntemi sadece
//      görsel bir etiketti, hiçbir yere kaydedilmiyordu; banka/kredi
//      kartı/kasa hiçbiri güncellenmiyordu.
//
// Muhasebe mantığı: "Borç Ekle" sadece bir yükümlülük (ödenecek borç)
// kaydıdır — henüz kasadan/bankadan para çıkmadığı için bir Gider
// (masraf) OLUŞTURMAZ. Gerçek masraf, paranın fiilen çıktığı an olan
// "Borç Öde" işleminde oluşur. Bu sayede aynı borç iki kez masraf
// olarak sayılmaz (ekleme + ödeme).
//
// Bu servis, ödeme yöntemine göre:
//   - Nakit    → Kasa hareketi (çıkış) oluşturur
//   - Banka/Havale → Seçilen banka hesabından hareket oluşturur (bakiye düşer)
//   - Kredi Kartı  → Seçilen kartın kullanılan limitini artırır
// ve HER durumda, Giderler ekranında görünecek bir Gider kaydı oluşturur.
import '../depolar/borc_deposu.dart';
import '../depolar/borc_odeme_deposu.dart';
import '../depolar/banka_hareket_deposu.dart';
import '../depolar/kredi_karti_deposu.dart';
import '../depolar/kasa_deposu.dart';
import '../depolar/gider_deposu.dart';
import '../modeller/borc_model.dart';
import '../modeller/borc_odeme_model.dart';
import '../modeller/banka_hareket_model.dart';
import '../modeller/kasa_hareket_model.dart';
import '../modeller/gider_model.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

/// Borç ödemesi Gider kayıtlarının toplanacağı sabit kategori adı.
/// Kategori yoksa otomatik oluşturulur (kullanıcı Giderler ekranından
/// istediği gibi yeniden adlandırabilir/yönetebilir).
const String kBorcOdemeGiderKategoriAdi = 'Borç Ödemeleri';

class BorcOdemeIslemServisi {
  final _borcDepo = BorcDeposu();
  final _odemeDepo = BorcOdemeDeposu();
  final _bankaHareketDepo = BankaHareketDeposu();
  final _krediKartiDepo = KrediKartiDeposu();
  final _kasaDepo = KasaDeposu();
  final _giderDepo = GiderDeposu();

  /// [odemeYontemi]: 'Nakit' | 'Banka' | 'Kredi Kartı' | 'Havale'
  /// Banka/Havale seçiliyse [bankaHesapId] zorunludur.
  /// Kredi Kartı seçiliyse [krediKartiId] zorunludur.
  Future<void> odemeYap({
    required BorcModel borc,
    required double tutar,
    required String odemeYontemi,
    int? bankaHesapId,
    int? krediKartiId,
    String? aciklama,
    String? referansNo,
  }) async {
    if (tutar <= 0) throw Exception('Ödeme tutarı sıfırdan büyük olmalı');
    if (tutar > borc.kalanTutar + 0.01) {
      throw Exception('Kalan borçtan fazla ödeme yapılamaz');
    }
    final bankaGerekli = odemeYontemi == 'Banka' || odemeYontemi == 'Havale';
    final kartGerekli = odemeYontemi == 'Kredi Kartı';
    if (bankaGerekli && bankaHesapId == null) {
      throw Exception('Banka hesabı seçilmedi');
    }
    if (kartGerekli && krediKartiId == null) {
      throw Exception('Kredi kartı seçilmedi');
    }

    // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Önceden bu akışın
    // adım 1'i (_borcDepo.odemeYap) KENDİ İÇİNDE 'Nakit' etiketiyle bir
    // borc_odemeler kaydı oluşturuyordu, adım 2 de AYRICA (doğru ödeme
    // yöntemiyle) kendi kaydını oluşturuyordu — yani TEK bir ödeme için
    // borc_odemeler tablosuna İKİ satır giriyordu (biri hep 'Nakit'
    // etiketli, gerçek yöntem ne olursa olsun). Bu hem ödeme geçmişini
    // bozuyor hem de BorcDeposu.odemeMutabakatYap() borc_odemeler
    // toplamından odenen_tutar'ı yeniden hesapladığında borcu OLDUĞUNDAN
    // FAZLA ödenmiş gösterebiliyordu. Ayrıca hiçbiri ortak bir transaction
    // içinde değildi — adım 3 (gerçek para hareketi) başarısız olursa borç
    // "ödendi" görünüp kasada/bankada hiç hareket olmayabiliyordu.
    //
    // Artık TÜM adımlar TEK bir db.transaction() içinde, atomik olarak
    // yürütülüyor; borç güncellemesi kendi ödeme geçmişi kaydını OLUŞTURMUYOR
    // (gecmisKaydet: false) — tek kayıt, doğru yöntemle, adım 2'de oluşuyor.
    final db = await Veritabani().db;

    int? odemeGecmisId;
    int? bankaHareketId;
    int? krediHareketId;
    int? kasaHareketId;
    int? giderId;
    bool kategoriYeniOlusturuldu = false;
    late int kategoriId;

    await db.transaction((txn) async {
      // 1. Borcun ödenen tutarını güncelle — kendi ödeme geçmişi kaydını
      // OLUŞTURMAZ, onu adım 2 (doğru ödeme yöntemiyle) oluşturur.
      await _borcDepo.odemeYapTxn(txn, borc.id!, tutar, gecmisKaydet: false);

      // 2. Ödeme geçmişi kaydı (Borç Detayı'nda görünür)
      odemeGecmisId = await _odemeDepo.ekleTxn(txn, BorcOdemeModel(
        borcId: borc.id!,
        tutar: tutar,
        tarih: DateTime.now(),
        odemeYontemi: odemeYontemi,
        bankaHesapId: bankaGerekli ? bankaHesapId : null,
        krediKartiId: kartGerekli ? krediKartiId : null,
        aciklama: aciklama,
        referansNo: referansNo,
      ));

      // 3. Ödeme yöntemine göre gerçek para hareketi
      if (bankaGerekli) {
        bankaHareketId = await _bankaHareketDepo.ekleTxn(txn, BankaHareketModel(
          bankaHesapId: bankaHesapId!,
          islemTipi: 'Giden',
          tutar: tutar,
          aciklama: '${borc.baslik} - Borç Ödemesi',
          tarih: DateTime.now(),
          referansNo: referansNo,
        ));
      } else if (kartGerekli) {
        krediHareketId = await _krediKartiDepo.limitDegistirTxn(txn, krediKartiId!, tutar,
            aciklama: '${borc.baslik} - Borç Ödemesi');
      } else if (odemeYontemi == 'Nakit') {
        kasaHareketId = await _kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
          hareketTipi: 'Borç Ödemesi',
          tutar: tutar,
          referansId: borc.id,
          referansTuru: 'borc_odeme',
          aciklama: '${borc.baslik} - Borç Ödemesi',
          tarih: DateTime.now(),
        ));
      }

      // 4. Gerçek masraf kaydı — Giderler ekranında görünür (borç EKLENİRKEN
      // değil, ÖDENİRKEN oluşur; aksi halde aynı tutar iki kez sayılırdı).
      final kategoriSonuc = await _borcOdemeKategoriIdGetirTxn(txn);
      kategoriId = kategoriSonuc.$1;
      kategoriYeniOlusturuldu = kategoriSonuc.$2;
      giderId = await _giderDepo.ekleTxn(txn, GiderModel(
        kategoriId: kategoriId,
        kategoriAdi: kBorcOdemeGiderKategoriAdi,
        tutar: tutar,
        aciklama: '${borc.baslik}${aciklama != null ? ' — $aciklama' : ''}',
        tarih: DateTime.now(),
        odemeYontemi: odemeYontemi,
      ));
    });

    // Transaction başarıyla kapandı (kalıcı oldu) — şimdi bulut senkronunu
    // tetikle. KasaDeposu.hareketEkleTxn ile aynı gerekçe: commit'ten önce
    // senkron göndermek, transaction geri alınırsa buluta var olmayan bir
    // satır göndermiş olurdu.
    Future<void> sync(String tablo, int? id) async {
      if (id == null) return;
      final satir = await db.query(tablo, where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert(tablo, Map<String, dynamic>.from(satir.first));
    }

    final borcSatir = await db.query('borclar', where: 'id = ?', whereArgs: [borc.id], limit: 1);
    if (borcSatir.isNotEmpty) BulutManager().upsert('borclar', Map<String, dynamic>.from(borcSatir.first));
    await sync('borc_odemeler', odemeGecmisId);
    if (bankaGerekli) {
      await sync('banka_hareketler', bankaHareketId);
      final hesapSatir = await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [bankaHesapId], limit: 1);
      if (hesapSatir.isNotEmpty) BulutManager().upsert('banka_hesaplar', Map<String, dynamic>.from(hesapSatir.first));
    } else if (kartGerekli) {
      await sync('kredi_karti_hareket', krediHareketId);
      final kartSatir = await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [krediKartiId], limit: 1);
      if (kartSatir.isNotEmpty) BulutManager().upsert('kredi_kartlari', Map<String, dynamic>.from(kartSatir.first));
    } else if (odemeYontemi == 'Nakit') {
      await sync('kasa_hareketleri', kasaHareketId);
    }
    if (kategoriYeniOlusturuldu) await sync('gider_kategoriler', kategoriId);
    await sync('giderler', giderId);
  }

  /// "Borç Ödemeleri" gider kategorisini bulur, yoksa oluşturur.
  /// Döndürülen kayıt: (kategoriId, yeniOlusturulduMu).
  Future<(int, bool)> _borcOdemeKategoriIdGetirTxn(dynamic txn) async {
    final mevcut = await txn.query('gider_kategoriler',
        where: 'ad = ?', whereArgs: [kBorcOdemeGiderKategoriAdi], limit: 1);
    if (mevcut.isNotEmpty) return (mevcut.first['id'] as int, false);
    final now = DateTime.now().toIso8601String();
    final id = await txn.insert('gider_kategoriler', {'ad': kBorcOdemeGiderKategoriAdi, 'last_updated': now}) as int;
    return (id, true);
  }
}
