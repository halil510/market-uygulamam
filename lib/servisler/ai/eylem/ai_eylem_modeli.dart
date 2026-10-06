// lib/servisler/ai/eylem/ai_eylem_modeli.dart
//
// Asistanın YAZMA (işlem) yeteneklerinin ortak modelleri.
//
// ALTIN KURAL: Asistan hiçbir veriyi kullanıcı onayı olmadan DEĞİŞTİRMEZ.
// Her işlem önce bir [AiEylemOnerisi] (önizleme) olarak sohbette gösterilir;
// "Onayla" denince [AiEylemOnerisi.uygula] çalışır. Belirsizlikte (birden
// fazla ürün/cari eşleşirse) asistan tahmin yürütmez, seçenek sunar.

/// Asistanın yapabildiği işlem türleri.
enum AiEylemTuru {
  urunEkle,
  fiyatGuncelle,
  stokDuzenle,
  urunDurum,
  giderEkle,
  tahsilatOdeme,
  cariEkle,
}

extension AiEylemTuruAd on AiEylemTuru {
  String get ad => switch (this) {
        AiEylemTuru.urunEkle => 'Ürün Ekle',
        AiEylemTuru.fiyatGuncelle => 'Fiyat Güncelle',
        AiEylemTuru.stokDuzenle => 'Stok Düzenle',
        AiEylemTuru.urunDurum => 'Ürün Durumu',
        AiEylemTuru.giderEkle => 'Gider Ekle',
        AiEylemTuru.tahsilatOdeme => 'Tahsilat / Ödeme',
        AiEylemTuru.cariEkle => 'Cari Ekle',
      };
}

/// Kural tabanlı veya Gemini'nin çözdüğü ham komut (henüz veritabanına
/// bakılmamış; ürün/cari adı metin olarak durur).
class AiEylemKomutu {
  final AiEylemTuru tur;

  /// Fiyat/stok/durum için aranacak ürün metni ("kola", "ülker gofret").
  final String? urunMetni;

  /// Tahsilat/ödeme için aranacak cari metni.
  final String? cariMetni;

  /// 'satisFiyati' | 'alisFiyat' | 'toptanFiyat'
  final String? fiyatAlani;

  /// 'ayarla' | 'artir' | 'azalt' | 'yuzdeArtir' | 'yuzdeAzalt'
  final String? islem;

  /// Miktar / tutar / yüzde.
  final double? deger;

  /// urunDurum için hedef durum.
  final bool? aktif;

  /// tahsilatOdeme: 'Tahsilat' | 'Odeme'. cariEkle: cari tipi
  /// ('Müşteri' | 'Tedarikçi').
  final String? islemTipi;

  /// 'Nakit' | 'Havale' | 'Kredi Kartı'
  final String? odemeTuru;

  /// Stok miktarında söylenen birim ('adet' | 'kg' | 'koli' | …).
  final String? birim;

  /// Gider kategorisi/açıklaması veya yeni cari adı.
  final String? metin;

  /// urunEkle: ayrıştırılmış form alanları (alan → double|String|bool).
  final Map<String, Object>? urunAlanlari;

  /// Komutla birlikte söylenen ek bilgi (ör. yeni cari telefonu).
  final String? telefon;

  /// Ayrıştırma sırasında fark edilen uyarılar (geçersiz KDV vb.).
  final List<String> uyarilar;

  const AiEylemKomutu({
    required this.tur,
    this.urunMetni,
    this.cariMetni,
    this.fiyatAlani,
    this.islem,
    this.deger,
    this.aktif,
    this.islemTipi,
    this.odemeTuru,
    this.birim,
    this.metin,
    this.urunAlanlari,
    this.telefon,
    this.uyarilar = const [],
  });
}

/// Kullanıcıya gösterilen, ONAY BEKLEYEN işlem.
class AiEylemOnerisi {
  final String id;
  final AiEylemTuru tur;
  final String baslik;

  /// Önizleme satırları ("Kola: satış fiyatı 30,00 → 35,00 ₺").
  final List<String> satirlar;

  /// Dikkat edilmesi gereken noktalar (benzer ürün var, indirim sıfırlanır…).
  final List<String> uyarilar;

  /// Para/kasa/bakiye etkileyen işlem — önizlemede ayrıca vurgulanır.
  final bool kritik;

  /// Onaylanınca çalışır; kullanıcıya gösterilecek sonuç metnini döndürür.
  /// Hata fırlatırsa çağıran anlaşılır mesaja çevirir.
  final Future<String> Function() _uygula;

  final DateTime olusturma;
  bool _kullanildi = false;

  AiEylemOnerisi({
    required this.id,
    required this.tur,
    required this.baslik,
    required this.satirlar,
    required Future<String> Function() uygula,
    this.uyarilar = const [],
    this.kritik = false,
    DateTime? olusturma,
  })  : _uygula = uygula,
        olusturma = olusturma ?? DateTime.now();

  /// Önizleme bu süreden sonra bayat sayılır (veri değişmiş olabilir).
  static const Duration gecerlilik = Duration(minutes: 15);

  bool get kullanildi => _kullanildi;
  bool get suresiDoldu => DateTime.now().difference(olusturma) > gecerlilik;

  /// Çift dokunmaya karşı korumalı: ikinci çağrı işlem YAPMAZ.
  Future<String> calistir() async {
    if (_kullanildi) return 'Bu işlem zaten uygulandı veya iptal edildi.';
    if (suresiDoldu) {
      _kullanildi = true;
      return 'Bu önizlemenin süresi doldu (veri değişmiş olabilir). '
          'Lütfen isteği yeniden yazın.';
    }
    _kullanildi = true;
    return _uygula();
  }

  /// Kullanıcı "Vazgeç" dediğinde işaretlenir.
  void iptalEt() => _kullanildi = true;
}

/// Motorun bir komuta cevabı: ya tek onay önerisi, ya seçenekler, ya da
/// sadece bir mesaj (anlaşılamadı / yetki yok / eksik bilgi).
class AiEylemSonucu {
  final String mesaj;
  final AiEylemOnerisi? oneri;
  final List<AiEylemOnerisi> secimler;

  const AiEylemSonucu({
    required this.mesaj,
    this.oneri,
    this.secimler = const [],
  });
}
