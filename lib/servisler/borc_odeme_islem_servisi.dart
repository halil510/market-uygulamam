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

    // 1. Borcun ödenen tutarını güncelle (mevcut, doğru çalışan metod)
    await _borcDepo.odemeYap(borc.id!, tutar);

    // 2. Ödeme geçmişi kaydı (Borç Detayı'nda görünür)
    await _odemeDepo.ekle(BorcOdemeModel(
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
      await _bankaHareketDepo.ekle(BankaHareketModel(
        bankaHesapId: bankaHesapId!,
        islemTipi: 'Giden',
        tutar: tutar,
        aciklama: '${borc.baslik} - Borç Ödemesi',
        tarih: DateTime.now(),
        referansNo: referansNo,
      ));
    } else if (kartGerekli) {
      final kart = await _krediKartiDepo.idileGetir(krediKartiId!);
      if (kart != null) {
        await _krediKartiDepo.limitDegistir(krediKartiId, tutar,
            aciklama: '${borc.baslik} - Borç Ödemesi');
      }
    } else if (odemeYontemi == 'Nakit') {
      await _kasaDepo.hareketEkle(KasaHareketModel(
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
    final kategoriId = await _borcOdemeKategoriIdGetir();
    await _giderDepo.ekle(GiderModel(
      kategoriId: kategoriId,
      kategoriAdi: kBorcOdemeGiderKategoriAdi,
      tutar: tutar,
      aciklama: '${borc.baslik}${aciklama != null ? ' — $aciklama' : ''}',
      tarih: DateTime.now(),
      odemeYontemi: odemeYontemi,
    ));
  }

  /// "Borç Ödemeleri" gider kategorisini bulur, yoksa oluşturur.
  Future<int> _borcOdemeKategoriIdGetir() async {
    final db = await Veritabani().db;
    final mevcut = await db.query('gider_kategoriler',
        where: 'ad = ?', whereArgs: [kBorcOdemeGiderKategoriAdi], limit: 1);
    if (mevcut.isNotEmpty) return mevcut.first['id'] as int;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('gider_kategoriler', {'ad': kBorcOdemeGiderKategoriAdi, 'last_updated': now});
    // 🔴 Derin analizde bulundu: last_updated hiç ayarlanmıyordu,
    // BulutManager hiç çağrılmıyordu.
    final satir = await db.query('gider_kategoriler', where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('gider_kategoriler', Map<String, dynamic>.from(satir.first));
    return id;
  }
}
