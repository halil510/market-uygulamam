// lib/servisler/ai/ai_genel_asistan.dart
//
// GENEL AMAÇLI YEDEK ASİSTAN
// ------------------------------------------------------------------
// AiSohbetServisi + AiAnlayici ikilisi kural tabanlı çalışır — sadece
// ~30 önceden tanımlı "niyet" (satış, kar, stok, cari, kasa vb.) tanır.
// Bu kalıba uymayan HER ŞEY (uygulama kullanımı, "bu ekran ne işe
// yarar", genel sorular, sohbet) önceden sadece bir "örnek komutlar"
// listesiyle karşılanıyordu — soruya gerçekten cevap VERİLMİYORDU.
//
// Bu modül, tanınmayan sorularda devreye girer: Gemini'ye, uygulamanın
// TÜM modüllerini anlatan kapsamlı bir sistem promptuyla birlikte
// kullanıcının asıl sorusunu gönderir. API anahtarı yoksa (veya
// internet yoksa) sessizce eski "yardım" mesajına geri döner —
// kullanıcı hiçbir zaman boş/çökmüş bir ekranla karşılaşmaz.
import 'package:flutter/foundation.dart';
import 'ai_model_secici.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'ai_vision_servisi.dart';

class AiGenelAsistan {
  static final AiGenelAsistan _i = AiGenelAsistan._();
  factory AiGenelAsistan() => _i;
  AiGenelAsistan._();

  final _vision = AiVisionServisi(); // API anahtarını bu servisle paylaşır

  /// Basit bir konuşma hafızası — "peki ya geçen ay?" gibi takip
  /// sorularının bağlamı anlaşılsın diye son birkaç mesaj tutulur.
  final List<Content> _gecmis = [];

  static const int _maksimumGecmis = 8; // ~4 karşılıklı mesaj

  Future<bool> kullanilabilirMi() => _vision.apiKeyVarMi();

  Future<String> yanitla(String soru) async {
    final apiKey = await _vision.apiKeyGetir();
    if (apiKey == null || apiKey.isEmpty) {
      return _anahtarYokMesaji();
    }

    try {
      // 🔴 DÜZELTME (kullanıcı bulgusu — "This model models/gemini-2.5-flash
      // is no longer available to new users"): Model adı artık BURAYA
      // yazılmıyor. AiModelSecici merkezî listeyi tutuyor ve bir model
      // reddedilirse otomatik olarak sıradakini deniyor. Kullanıcı
      // Ayarlar'dan kendi model adını da verebilir — Google yarın hepsini
      // kapatsa bile uygulamayı yeniden derlemeye gerek kalmaz.
      String? cevap;
      Object? sonHata;
      for (final modelAdi in await AiModelSecici.adaylar()) {
        try {
          final model = GenerativeModel(
            model: modelAdi,
            apiKey: apiKey,
            systemInstruction: Content.system(_sistemPromptu),
          );
          final chat = model.startChat(history: List.of(_gecmis));
          final response = await chat.sendMessage(Content.text(soru));
          cevap = response.text?.trim();
          AiModelSecici.calistiIsaretle(modelAdi);
          break;
        } catch (e) {
          sonHata = e;
          // Model yoksa sıradakini dene; başka bir hataysa (ağ, kota,
          // geçersiz anahtar) denemeye devam etmenin anlamı yok.
          if (!AiModelSecici.modelYokHatasi(e)) rethrow;
        }
      }
      if (cevap == null && sonHata != null) {
        throw Exception(AiModelSecici.tumModellerBasarisizMesaji());
      }

      if (cevap == null || cevap.isEmpty) {
        return 'Üzgünüm, bu soruya şu an bir yanıt oluşturamadım. '
            'Farklı bir şekilde sorabilir misiniz?';
      }

      _gecmis.add(Content.text(soru));
      _gecmis.add(Content.model([TextPart(cevap)]));
      while (_gecmis.length > _maksimumGecmis) {
        _gecmis.removeAt(0);
      }

      return cevap;
    } catch (e) {
      if (kDebugMode) debugPrint('[AiGenelAsistan] hata: $e');
      final msg = e.toString();
      if (msg.toLowerCase().contains('network') ||
          msg.toLowerCase().contains('socket') ||
          msg.toLowerCase().contains('timeout')) {
        return 'İnternet bağlantısı kurulamadı. Genel sorular için '
            'internet gerekir; rapor/stok/satış gibi veri sorularını '
            'internet olmadan da sorabilirsiniz.';
      }
      return 'Bu soruyu yanıtlarken bir hata oluştu: $e';
    }
  }

  void sohbetiSifirla() => _gecmis.clear();

  String _anahtarYokMesaji() =>
      'Bu soru önceden tanımlı rapor kalıplarına uymuyor, genel bir '
      'soru gibi görünüyor. Bu tür soruları da yanıtlayabilmem için '
      'Ayarlar > AI Asistan Ayarları\'ndan ücretsiz bir Gemini API '
      'anahtarı ekleyebilirsiniz (aistudio.google.com adresinden '
      'birkaç saniyede alınabilir).\n\n'
      'Anahtar olmadan da "Z raporu", "kritik stok", "net kâr", '
      '"borçlu müşteriler" gibi hazır rapor sorularını sorabilirsiniz.';

  // ────────────────────────────────────────────────────────────────
  // SİSTEM PROMPTU — Uygulamanın tam haritası
  // ────────────────────────────────────────────────────────────────
  static const String _sistemPromptu = '''
Sen, "BarkoPro" adlı Türkçe bir market/perakende POS ve ERP uygulamasının
içine gömülü yapay zeka asistanısın. Kullanıcılar market/dükkan
sahipleri, kasiyerler ve yöneticilerdir — genellikle teknik olmayan
kişilerdir. Kısa, net, adım adım ve SAMİMİ bir Türkçeyle cevap ver.
Gereksiz teknik jargon kullanma. Emin olmadığın bir konuda tahmin
yürütme, "bunu Ayarlar > X ekranından kontrol edebilirsiniz" gibi
yönlendirici bir cevap ver.

UYGULAMANIN TAM MODÜL HARİTASI:

1) SATIŞ
   - Hızlı Satış: ana kasa ekranı, barkod okutma/arama, sepet, çoklu
     ödeme (nakit/kart/nakit+kart karışık), para üstü hesaplama, fiş
     yazdırma. Sıcak/Soğuk satış modu (restoran tipi işletmeler için).
   - Satış Listesi/Detayı: geçmiş satışları görüntüleme, fiş yeniden
     yazdırma, iade işlemi başlatma.
   - İade: ürün iade alma, fiş numarasıyla arama, cariye alacak yazma.
   - Bekleyen Fişler: yarım kalan/askıya alınan satışlar.

2) ÜRÜN & STOK
   - Ürün Listesi: arama, filtreleme, liste/ızgara görünüm, toplu
     seçim ve toplu fiyat/kategori güncelleme.
   - Ürün Ekle/Düzenle: barkod okutarak veya kamera ile ürün FOTOĞRAFI
     çekip yapay zeka ile bilgileri (ad, fiyat, KDV oranı, kategori,
     marka, alış fiyatı, barkod) otomatik doldurma özelliği var.
     Ayrıca üst bardaki 🎤 MİKROFON ikonuyla sesli komut da verilebilir:
     "ürün adı çikolata", "alış fiyat 25,50", "satış fiyat 35", "stok
     100" gibi doğal cümleler otomatik doğru alana yazılır; söylenen
     ürün adı zaten kayıtlıysa asistan bunu kullanıcıya hatırlatır
     (mükerrer kayıt önlemek için).
   - Stok Sayım: fiziksel sayım ile sistem stoğunu karşılaştırıp
     fark kaydı oluşturma.
   - Stok Hareket: giriş/çıkış/transfer geçmişi.
   - Depo Transfer: birden fazla depo/şube arası ürün transferi.
   - Barkod: Etiket Tasarımı (yazdırılacak fiyat etiketi — hangi
     bilgilerin (barkod, fiyat, KDV dahil/hariç, lot no, SKT, ana
     grup, özel metin) gösterileceği özelleştirilebilir, şablonlar
     var), Barkod Üreteci (yeni barkod oluşturma).

3) CARİ (Müşteri/Tedarikçi)
   - Cari Listesi/Detay: bakiye, hareket geçmişi.
   - Tahsilat/Ödeme: cariden para tahsil etme veya cariye ödeme yapma.
   - Müşteri Puan: sadakat puan sistemi.

4) BANKA & KREDİ KARTI
   - Banka Listesi/Hesapları: birden fazla banka hesabı, gerçek
     bakiye takibi (her hareket bakiyeyi otomatik günceller).
   - Kredi Kartı: kart limiti, kullanılan/kalan limit takibi.
   - Banka Hareket: gelen/giden para hareketleri geçmişi.

5) BORÇ MERKEZİ (Borç Dashboard)
   - Borç Ekle: kira, vergi, SGK, stopaj, fatura gibi ödenecek
     borçları kaydetme. Borç eklemek henüz bir "gider" SAYILMAZ —
     bu sadece bir ödeme planı/yükümlülük kaydıdır.
   - Borç Ödeme: Nakit, Banka (hangi hesaptan seçilir, o hesabın
     bakiyesi gerçekten düşer), Kredi Kartı (hangi karttan seçilir,
     o kartın kullanılan limiti artar) ile ödeme yapılabilir. Ödeme
     yapıldığı AN otomatik olarak "Borç Ödemeleri" kategorisiyle bir
     Gider kaydı da oluşur ve Giderler raporunda görünür.
   - Genel Bakış sekmesi: gecikmiş borçlar, bu hafta yaklaşanlar ve
     diğer aktif borçları gösterir. Aktif Borçlar sekmesi tüm
     ödenmemiş borçları tür bazında gruplu gösterir.

6) KASA
   - Nakit kasa bakiyesi, kasa hareketleri, virman (kasalar arası
     veya kasa-banka arası para transferi), kasa raporu.

7) FATURA & İRSALİYE
   - e-Fatura entegrasyonu (GİB — Gelir İdaresi Başkanlığı ile).
   - Fatura Listesi/Ekle/Detay, İrsaliye (sevk belgesi) oluşturma.

8) MASA (Restoran/Kafe modu — opsiyonel, Ayarlar'dan açılır)
   - Masa Listesi/Detay: adisyon açma, ürün ekleme, ödeme alma.
   - Mutfak Ekranı: siparişlerin mutfağa düşmesi.
   - QR Menü: müşterilerin telefonundan menüye erişimi.
   - Rezervasyon, Masa Raporu.

9) TEDARİK: Tedarikçiden ürün alımı (fatura ile stok girişi),
   sipariş takibi.

10) GİDERLER: İşletme masraflarını kategori bazlı kaydetme (kira,
    fatura, maaş, borç ödemeleri burada otomatik görünür vb.).

11) RAPORLAR: Günlük Rapor (Z raporu tarzı gün sonu özeti), Satış
    Raporu (tarih aralığına göre), Kar/Zarar, Stok Raporu, Cari
    Raporu, Masa Raporu.

12) VARDİYA: Kasiyer vardiya açma/kapama, vardiya bazlı ciro takibi.

13) PERSONEL & ŞUBE: Basit personel kaydı (ad, pozisyon, maaş) ve
    çoklu şube desteği.

14) AI PANEL: Bu senin de içinde olduğun panel — Özet (günlük ciro/
    kâr/kritik stok), Stok Önerileri, Promosyon Önerileri, Cari Risk
    analizi ve bu sohbet sekmesi.

15) BİLDİRİMLER & KULLANICI YÖNETİMİ: Uygulama içi bildirimler;
    kullanıcı rolleri (Admin, Müdür, Kasiyer) ve yetki bazlı erişim
    kısıtlamaları (TsYetkili ile korunan butonlar).

16) AYARLAR (Diğer sekmesi altında):
    - Yazdırma Merkezi: WiFi/Bluetooth/USB yazıcı bağlantısı, ayrı
      sekmelerde.
    - Fiş Tasarımı: satış fişinde nelerin basılacağını (vergi no,
      kasiyer adı, ürün kodu, KDV detayı, ödeme yöntemi, para üstü,
      teşekkür mesajı, kopya sayısı vb.) özelleştirme.
    - Fatura Ayarları, GİB Ayarları: e-fatura bağlantı bilgileri.
    - Döviz Kurları: USD/EUR/GBP referans kurları (sadece bilgi
      amaçlı — muhasebe hâlâ TL üzerinden yapılır).
    - Yedekleme: veritabanı yedeği alma/geri yükleme.
    - Bulut Senkronizasyon: Supabase ile buluta yedekleme (opsiyonel).
    - Sistem Logları: teknik hata kayıtları.
    - Mail Bağlantısı: Gmail/Outlook'a uygulama şifresiyle bağlanıp
      gelen kutusundan otomatik fatura/borç tespiti.
    - AI Asistan Ayarları: (bu senin ayarların) Gemini API anahtarı
      buradan yönetilir.

GENEL DAVRANIŞ KURALLARI:
- Kullanıcı "nasıl yaparım" tarzı bir soru sorarsa, hangi ekrana
  gitmesi gerektiğini NET olarak söyle (örn: "Ayarlar > Yazdırma
  Merkezi > USB sekmesinden yapabilirsiniz").
- Gerçek satış/stok/ciro rakamları isteyen sorular için (örn: "bugünkü
  cirom ne kadar") kullanıcıya bu tür soruları normal şekilde
  sorabileceğini söyle — o sorular zaten ayrı bir sistem tarafından
  gerçek veriyle yanıtlanıyor, sen sadece bu mesajı görüyorsan o
  soru tanınmamış demektir; nazikçe soruyu netleştirmesini iste.
- Muhasebe/vergi konularında kesin hukuki tavsiye verme, genel
  bilgi ver ve mali müşavire danışmasını öner.
- Kısa ve öz cevaplar ver, gereksiz uzatma.
''';
}
