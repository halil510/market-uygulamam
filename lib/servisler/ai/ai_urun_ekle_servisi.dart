// lib/servisler/ai/ai_urun_ekle_servisi.dart
// v4.2 – Fiyat dönüşümü sağlam

import 'dart:convert';
import 'ai_model_secici.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'ai_vision_servisi.dart';
import '../../modeller/ocr_urun_model.dart';
import '../../modeller/urun_model.dart';
import '../../depolar/urun_deposu.dart';

class AiUrunEkleServisi {
  static final AiUrunEkleServisi _i = AiUrunEkleServisi._();
  factory AiUrunEkleServisi() => _i;
  AiUrunEkleServisi._();

  final _vision = AiVisionServisi();

  Future<List<Map<String, dynamic>>> faturaUrunleriCikar(dynamic dosya) async {
    try {
      final ocrUrunler = await _vision.faturaFotografindanUrunCikar(dosya);
      return ocrUrunler.map((ocr) => _ocrModelToMap(ocr)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('faturaUrunleriCikar hatası: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> urunFotografindanBilgiCikar(dynamic resim) async {
    try {
      final ocrList = await _vision.faturaFotografindanUrunCikar(resim);
      if (ocrList.isNotEmpty) {
        return _ocrModelToMap(ocrList.first);
      }
      return {};
    } catch (e) {
      if (kDebugMode) debugPrint('urunFotografindanBilgiCikar hatası: $e');
      return {};
    }
  }

  /// 🔴🔴🔴 KRİTİK "EKSİKLİK" DÜZELTMESİ (kullanıcı isteği — "asistanları
  /// geliştir, eksiklikler var, tam pro yap"): Bu fonksiyon ÖNCEDEN
  /// HER ZAMAN boş bir Map döndürüyordu — tam bir iskelet (stub). Ama
  /// çağıran ekran (urun_ekle_ekrani.dart _barkodTara()), barkod
  /// veritabanında bulunamadığında kullanıcıya "AI ile ürün bilgisi
  /// çıkarılıyor..." diye GERÇEKMİŞ GİBİ 10 saniyeye kadar bekleyen bir
  /// gösterge sunuyordu — sonra hep boş dönüyordu, kullanıcıya hiçbir
  /// açıklama da yapılmıyordu. Kullanıcı "AI çalışmıyor" sanıyordu; oysa
  /// hiç çağrılmıyordu bile.
  ///
  /// Gerçek düzeltme: Gemini'nin bir barkod NUMARASINDAN (fotoğraf
  /// olmadan) ürün bilgisi "bilmesi" güvenilir DEĞİLDİR — LLM'ler
  /// barkod/GTIN veritabanlarını güvenilir şekilde ezberlemez, bu
  /// yüzden burada "tahmin yürütme, sadece GERÇEKTEN eminsen cevap
  /// ver" talimatı verilerek halüsinasyon riski en aza indiriliyor.
  /// Emin değilse (ki çoğu zaman böyle olacaktır) hızlıca boş dönülür
  /// ve arayan ekran artık bunu net bir mesajla kullanıcıya iletir.
  Future<Map<String, dynamic>> urunBilgisiCikar(String metin) async {
    final barkod = metin.trim();
    if (barkod.isEmpty) return {};
    try {
      final apiKey = await _vision.apiKeyGetir();
      if (apiKey == null || apiKey.isEmpty) return {};

      final model = GenerativeModel(
        model: await AiModelSecici.ilkAday(),
        apiKey: apiKey,
        generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      );
      final prompt = '''
Bu bir market/perakende ürününün barkod numarası (GTIN/EAN/UPC): "$barkod"

Bu SADECE çok yaygın, dünyaca bilinen bir markanın barkodu ise (ör.
Coca-Cola, Nestle, Ülker gibi büyük, tanınmış markaların standart
ürünleri) ve gerçekten EMİNSEN ürün bilgilerini ver. EMİN DEĞİLSEN
veya bu barkodu tanımıyorsan, ASLA TAHMİN YÜRÜTME — "bilinmiyor": true
döndür. Yanlış/uydurma bilgi vermek, hiç bilgi vermemekten çok daha
kötüdür; bu veri doğrudan bir ürün veritabanına yazılacak.

SADECE şu JSON formatında cevap ver, başka hiçbir şey yazma:
{"bilinmiyor": true}
VEYA (sadece gerçekten eminsen):
{"bilinmiyor": false, "urun_adi": "string", "ana_grup": "kategori",
 "alan1": "marka veya null", "birim_adi": "ADET/KG/LİTRE/PAKET vb."}
''';
      final response = await model.generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 8));
      final cevapMetni = response.text?.trim();
      if (cevapMetni == null || cevapMetni.isEmpty) return {};

      final temiz = cevapMetni.replaceAll(RegExp(r'^```json\s*|\s*```$'), '').trim();
      final json = jsonDecode(temiz) as Map<String, dynamic>;
      if (json['bilinmiyor'] == true || json['urun_adi'] == null) return {};

      return _normalizeUrunBilgisi({
        'urun_adi': json['urun_adi'].toString(),
        if (json['ana_grup'] != null) 'ana_grup': json['ana_grup'].toString(),
        if (json['alan1'] != null && json['alan1'].toString().toLowerCase() != 'null')
          'alan1': json['alan1'].toString(),
        if (json['birim_adi'] != null) 'birim_adi': json['birim_adi'].toString(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('urunBilgisiCikar (barkod) hatası: $e');
      return {};
    }
  }

  // ÖNCEDEN BURASI "AI" OLARAK ETİKETLİYDİ AMA GERÇEKTE HİÇ AI
  // ÇAĞIRMIYORDU — sadece ~40 sabit marka ve ~7 sabit kategoriden oluşan
  // bir liste kontrolüydü. "Çikolatalı Fındık Kreması" gibi listede
  // olmayan bir ürün için hep "Diğer" dönerdi. Artık gerçekten Gemini'ye
  // soruluyor (API anahtarı yoksa/hata olursa aynı hızlı, sabit liste
  // kontrolüne sorunsuzca geri dönülüyor — kullanıcı hiçbir zaman boş
  // cevap almaz).
  Future<Map<String, String>> urunKategoriOner(String urunAdi) async {
    final aiSonuc = await _geminiIleKategoriMarkaTahmini(urunAdi);
    if (aiSonuc != null) return aiSonuc;

    // Yedek (API anahtarı yok / hata / internet yok): sabit liste kontrolü
    final ana = _normalizeKategori(urunAdi.toLowerCase());
    final marka = _markaCikar(urunAdi);
    return {
      'ana_grup': ana,
      if (marka != null) 'alan1': marka,
    };
  }

  Future<Map<String, String>?> _geminiIleKategoriMarkaTahmini(String urunAdi) async {
    if (urunAdi.trim().isEmpty) return null;
    try {
      final apiKey = await _vision.apiKeyGetir();
      if (apiKey == null || apiKey.isEmpty) return null;

      final model = GenerativeModel(
        model: await AiModelSecici.ilkAday(), // 🔴 kararlı sürüm — bkz. ai_genel_asistan.dart
        apiKey: apiKey,
        generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      );
      final prompt = '''
Bir markette satılan şu ürünü analiz et: "$urunAdi"

Şu JSON formatında SADECE cevap ver, başka hiçbir şey yazma:
{"ana_grup": "kategori adı", "marka": "marka adı veya null"}

Kategori Türkçe ve genel olsun (ör: Gıda, İçecek, Temizlik, Kişisel Bakım,
Elektronik, Tekstil, Kırtasiye, Süt Ürünleri, Atıştırmalık, Bebek Ürünleri,
Ev Gereçleri). Marka biliniyorsa (Ülker, Eti, Pınar, Coca-Cola, vb.) yaz,
bilinmiyorsa null yaz.
''';
      final response = await model.generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 8));
      final metin = response.text?.trim();
      if (metin == null || metin.isEmpty) return null;

      final temiz = metin.replaceAll(RegExp(r'^```json\s*|\s*```$'), '').trim();
      final json = jsonDecode(temiz) as Map<String, dynamic>;
      final sonuc = <String, String>{};
      if (json['ana_grup'] != null && json['ana_grup'].toString().trim().isNotEmpty) {
        sonuc['ana_grup'] = json['ana_grup'].toString().trim();
      }
      if (json['marka'] != null &&
          json['marka'].toString().trim().isNotEmpty &&
          json['marka'].toString().toLowerCase() != 'null') {
        sonuc['alan1'] = json['marka'].toString().trim();
      }
      return sonuc.isEmpty ? null : sonuc;
    } catch (e) {
      if (kDebugMode) debugPrint('Gemini kategori/marka tahmini başarısız: $e');
      return null; // sessizce sabit listeye düş
    }
  }

  /// Sesli komutla söylenen bir ürün adını, mevcut ürün veritabanında
  /// arar. Kullanıcı yeni ürün eklerken "Ülker Çubuk" gibi bir isim
  /// söylediğinde, bu isim zaten kayıtlıysa mükerrer kayıt yerine mevcut
  /// ürünü hatırlatmak / referans almak için kullanılır.
  Future<List<UrunModel>> benzerUrunleriAra(String urunAdi, {int limit = 5}) async {
    if (urunAdi.trim().length < 2) return [];
    try {
      return await UrunDeposu().ara(urunAdi.trim(), limit: limit);
    } catch (e) {
      if (kDebugMode) debugPrint('benzerUrunleriAra hatası: $e');
      return [];
    }
  }

  /// Sesli komutu (kural tabanlı ayrıştırıcı bir alan bulamadığında)
  /// Gemini'ye göndererek "hangi alana ne yazılacağını" akıllıca
  /// belirler. Örn: "bunun kilosu on iki lira elli" -> alış fiyatı.
  Future<Map<String, String>?> sesliKomutYorumla(String metin) async {
    if (metin.trim().isEmpty) return null;
    try {
      final apiKey = await _vision.apiKeyGetir();
      if (apiKey == null || apiKey.isEmpty) return null;

      final model = GenerativeModel(
        model: await AiModelSecici.ilkAday(), // 🔴 kararlı sürüm — bkz. ai_genel_asistan.dart
        apiKey: apiKey,
        generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      );
      final prompt = '''
Bir market ürün ekleme formunda kullanıcı şunu sesle söyledi: "$metin"

Bu ifadenin hangi form alanına ait olduğunu ve değerinin ne olduğunu
belirle. Olası alanlar: urunAdi, alisFiyat, satisFiyati, stok, barkod,
kdvOrani, anaGrup, marka.

SADECE şu JSON formatında cevap ver, başka hiçbir şey yazma:
{"alan": "alan_adi", "deger": "değer"}

Fiyat/stok/kdv gibi sayısal alanlarda "deger" SADECE sayı olsun (₺, TL,
lira gibi kelimeler OLMASIN, virgül yerine nokta kullan). Örnek: "alış
fiyat yirmi beş lira elli" -> {"alan": "alisFiyat", "deger": "25.50"}.
Hangi alana ait olduğu belirsizse "alan": "urunAdi" yaz (en yaygın
kullanım budur).
''';
      final response = await model.generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 8));
      final cevapMetni = response.text?.trim();
      if (cevapMetni == null || cevapMetni.isEmpty) return null;

      final temiz = cevapMetni.replaceAll(RegExp(r'^```json\s*|\s*```$'), '').trim();
      final json = jsonDecode(temiz) as Map<String, dynamic>;
      if (json['alan'] == null || json['deger'] == null) return null;
      return {'alan': json['alan'].toString(), 'deger': json['deger'].toString()};
    } catch (e) {
      if (kDebugMode) debugPrint('Gemini sesli komut yorumlama başarısız: $e');
      return null;
    }
  }

  // ============================================================
  // NORMALİZASYON METOTLARI
  // ============================================================

  Map<String, dynamic> _normalizeUrunBilgisi(Map<String, dynamic> json) {
    final sonuc = <String, dynamic>{};

    for (final key in json.keys) {
      final normalizedKey = _normalizeKey(key);
      final targetKey = normalizedKey ?? key;
      sonuc[targetKey] = json[key];
    }

    // ---- FİYAT DÖNÜŞÜMÜ: 'birim_fiyat' -> 'satis_fiyati' ----
    if (sonuc.containsKey('birim_fiyat')) {
      sonuc['satis_fiyati'] = sonuc['birim_fiyat'];
      sonuc.remove('birim_fiyat');
    }

    // Sayısal alanları dönüştür
    for (final field in [
      'kdv_orani',
      'alis_fiyat',
      'satis_fiyati',
      'miktar',
      'toplam_tutar',
      'iskonto_orani',
      'kdv_tutari'
    ]) {
      if (sonuc.containsKey(field)) {
        sonuc[field] = _toDouble(sonuc[field]);
      }
    }

    if (sonuc.containsKey('birim_adi')) {
      final b = sonuc['birim_adi'].toString().toUpperCase().trim();
      sonuc['birim_adi'] = _birimMap[b] ?? b;
    }

    if (sonuc.containsKey('ana_grup')) {
      sonuc['ana_grup'] = _normalizeKategori(sonuc['ana_grup'].toString());
    }

    if (!sonuc.containsKey('urun_adi') || sonuc['urun_adi'].toString().isEmpty) {
      if (sonuc.containsKey('kod')) {
        sonuc['urun_adi'] = sonuc['kod'];
      } else if (sonuc.containsKey('barkod')) {
        sonuc['urun_adi'] = sonuc['barkod'];
      }
    }

    return sonuc;
  }

  String? _normalizeKey(String key) {
    final lowerKey = key.toLowerCase().trim();
    for (final entry in _faturaAlanMap.entries) {
      for (final alias in entry.value) {
        if (lowerKey == alias.toLowerCase() ||
            lowerKey.contains(alias.toLowerCase()) ||
            alias.toLowerCase().contains(lowerKey)) {
          return entry.key;
        }
      }
    }
    if (lowerKey.contains('ad') || lowerKey.contains('name') || lowerKey.contains('tanım')) return 'urun_adi';
    if (lowerKey.contains('fiyat') && lowerKey.contains('satış')) return 'satis_fiyati';
    if (lowerKey.contains('fiyat') && lowerKey.contains('alış')) return 'alis_fiyat';
    if (lowerKey.contains('miktar') || lowerKey.contains('adet')) return 'miktar';
    if (lowerKey.contains('kdv') && lowerKey.contains('oran')) return 'kdv_orani';
    if (lowerKey.contains('kdv') && lowerKey.contains('tutar')) return 'kdv_tutari';
    if (lowerKey.contains('toplam') || lowerKey.contains('brüt')) return 'toplam_tutar';
    if (lowerKey.contains('iskonto') || lowerKey.contains('indirim')) {
      if (lowerKey.contains('oran')) return 'iskonto_orani';
      return 'iskonto_tutari';
    }
    if (lowerKey.contains('kod') || lowerKey.contains('barkod') || lowerKey.contains('gtin')) return 'kod';
    if (lowerKey.contains('birim') || lowerKey.contains('brm')) return 'birim_adi';
    return null;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v
          .replaceAll('TL', '')
          .replaceAll('₺', '')
          .replaceAll(' ', '')
          .replaceAll(',', '.')
          .trim();
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  String _normalizeKategori(String kategori) {
    final k = kategori.toLowerCase().trim();
    for (final entry in _kategoriMap.entries) {
      if (k.contains(entry.key) || entry.key.contains(k)) {
        return entry.value;
      }
    }
    return 'Diğer';
  }

  String? _markaCikar(String urunAdi) {
    final markalar = [
      'Ülker', 'Danone', 'Nestle', 'Pınar', 'Sütaş', 'Eti', 'Torku',
      'Arçelik', 'Vestel', 'Bosch', 'Siemens', 'Samsung', 'LG',
      'Unilever', 'Procter & Gamble', 'Henkel', 'Colgate',
      'Apple', 'Sony', 'Xiaomi', 'Huawei', 'Lenovo', 'HP', 'Dell',
      'Acer', 'Asus', 'Casper', 'Monster', 'MSI', 'Gigabyte',
      'Nike', 'Adidas', 'Puma', 'Reebok', 'New Balance',
      'Zara', 'Mango', 'H&M', 'LC Waikiki', 'Koton', 'DeFacto',
      'Beko', 'Profilo', 'Altus', 'Ariston'
    ];
    for (final m in markalar) {
      if (urunAdi.contains(m)) return m;
    }
    return null;
  }

  Map<String, dynamic> _ocrModelToMap(OcrUrunModel model) {
    final map = <String, dynamic>{
      'urun_adi': model.urunAdi,
      'miktar': model.miktar,
      'birim_adi': model.birimAdi,
      'birim_fiyat': model.birimFiyat,
      'toplam_tutar': model.toplamTutar,
      'kdv_orani': model.kdvOrani,
      'iskonto_orani': model.iskontoOrani,
      'kod': model.kod,
      'guven': model.guven,
    };
    return _normalizeUrunBilgisi(map);
  }

  static const Map<String, List<String>> _faturaAlanMap = {
    'urun_adi': [
      'Mal Hizmet', 'Ürün Adı', 'Açıklama', 'Description', 'Product Name',
      'Malzeme Adı', 'Ürün Tanımı', 'Goods Description', 'Item Description',
      'Ürün İsmi', 'Malın Cinsi', 'Cinsi', 'Mal', 'Hizmet'
    ],
    'miktar': [
      'Miktar', 'Top.Ad.', 'Toplam Adet', 'Adet', 'Kg', 'Lt', 'Quantity', 'Qty',
      'Mik.', 'MİK', 'MİKTAR', 'AĞIRLIK', 'AĞ.', 'Net', 'Brüt', 'Miktarı'
    ],
    'birim_adi': [
      'Brm', 'Birim', 'Unit', 'Birim Adı', 'Ölçü Birimi', 'UoM', 'Birimi',
      'Bir.', 'BRM'
    ],
    'birim_fiyat': [
      'Brm.Fiy.', 'Birim Fiyat', 'Fiyat', 'Price', 'Unit Price', 'Birim Fiyatı',
      'BF', 'BFİYAT', 'BRM FİYAT', 'B.Fiyat', 'Birim Fiyatı (TL)'
    ],
    'toplam_tutar': [
      'Brüt Tutar', 'Toplam', 'Tutar', 'KDV Dahil Toplam', 'Total', 'Amount',
      'Genel Toplam', 'Net Tutar', 'Satır Toplamı', 'Mal Hizmet Tutarı',
      'Tutarı', 'Toplam Tutar'
    ],
    'kdv_orani': [
      'KDV O.', 'KDV Oranı', 'VAT Rate', 'KDV %', 'KDV Oran', 'KDV', 'KDV (%)'
    ],
    'iskonto_orani': [
      'İsk.O.', 'İskonto Oranı', 'Discount %', 'İSK. %', 'İskonto Oran',
      'İskonto (%)'
    ],
    'kod': [
      'Kodu', 'Kod', 'Stok Kodu', 'Ürün Kodu', 'Product Code', 'Item Code',
      'Mal Kodu', 'Barkod'
    ],
  };

  static const Map<String, String> _birimMap = {
    'AD': 'ADET', 'ADET': 'ADET',
    'KL': 'KOLİ', 'KOLİ': 'KOLİ', 'KOL': 'KOLİ',
    'PK': 'PAKET', 'PAKET': 'PAKET', 'PAK': 'PAKET',
    'KG': 'KG', 'KILO': 'KG', 'KİLOGRAM': 'KG',
    'GR': 'GR', 'GRAM': 'GR', 'G': 'GR',
    'LT': 'LİTRE', 'LİTRE': 'LİTRE', 'L': 'LİTRE',
    'ML': 'ML', 'MİLİLİTRE': 'ML',
    'MT': 'METRE', 'M': 'METRE', 'METRE': 'METRE',
  };

  static const Map<String, String> _kategoriMap = {
    'gıda': 'Gıda', 'gida': 'Gıda',
    'içecek': 'İçecek', 'icecek': 'İçecek',
    'temizlik': 'Temizlik',
    'kişisel bakım': 'Kişisel Bakım', 'kisisel bakim': 'Kişisel Bakım',
    'elektronik': 'Elektronik',
    'tekstil': 'Tekstil',
    'kırtasiye': 'Kırtasiye', 'kirtasiye': 'Kırtasiye',
  };

  // ---- MEVCUT METODLAR ----
  Future<Map<String, dynamic>> gunlukOzet() async => {};
  Future<Map<String, double>> satisTahmini() async => {};
  Future<List<Map<String, dynamic>>> stokOnerisi() async => [];
  Future<List<Map<String, dynamic>>> promosyonOnerisi() async => [];
  Future<List<Map<String, dynamic>>> enCokSatanlar() async => [];
  Future<List<Map<String, dynamic>>> cariRisk() async => [];
}