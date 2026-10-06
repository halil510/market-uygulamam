// lib/servisler/ai/eylem/ai_eylem_yonlendirici.dart
//
// Kural tabanlı ayrıştırıcının ([AiEylemAyristirici]) çözemediği SERBEST
// işlem cümlelerini Gemini'ye "araç çağırma" (function calling) olarak sorar:
//   "bu kolayı artık 40 liraya satalım"  → urun_fiyat_guncelle
//   "depoya 3 koli süt girdi"            → urun_stok_duzenle
//   "Ayşe hanım dün 300 lira getirdi"    → cari_tahsilat_odeme
//
// Model YALNIZCA hangi işlemin hangi parametrelerle istendiğine karar verir.
// Veritabanına YAZMAZ; çıkan komut AYNI motordan (yetki + önizleme + onay)
// geçer. Hiçbir araç uymuyorsa (işlem istenmiyorsa) null döner.
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../ai_model_secici.dart';
import '../ai_vision_servisi.dart';
import '../urun_ses_ayristirici.dart';
import 'ai_eylem_ayristirici.dart';
import 'ai_eylem_modeli.dart';

class AiEylemYonlendirici {
  static final AiEylemYonlendirici _i = AiEylemYonlendirici._();
  factory AiEylemYonlendirici() => _i;
  AiEylemYonlendirici._();

  final _vision = AiVisionServisi();

  /// Ucuz kapı: cümle işlem gibi görünmüyorsa Gemini'ye hiç gidilmez.
  static bool eylemIpucuVar(String soru) => AiEylemAyristirici.ipucuVar(soru);

  static final List<Tool> araclar = [
    Tool(functionDeclarations: [
      FunctionDeclaration(
          'urun_fiyat_guncelle',
          'Bir ürünün satış/alış/toptan fiyatını değiştirir (yeni fiyata ayarla, tutar kadar artır/azalt veya yüzde zam/indirim).',
          Schema.object(properties: {
            'urun_adi': Schema.string(description: 'Ürün adı (ek almamış hâliyle)'),
            'alan': Schema.enumString(
                enumValues: ['satis', 'alis', 'toptan'],
                description: 'Hangi fiyat; belirtilmediyse satis'),
            'islem': Schema.enumString(
                enumValues: ['ayarla', 'artir', 'azalt', 'yuzde_artir', 'yuzde_azalt']),
            'deger': Schema.number(description: 'Yeni fiyat / tutar / yüzde değeri'),
          }, requiredProperties: ['urun_adi', 'islem', 'deger'])),
      FunctionDeclaration(
          'urun_stok_duzenle',
          'Bir ürünün stoğunu artırır (giriş), azaltır (çıkış) veya belirli bir sayıya ayarlar.',
          Schema.object(properties: {
            'urun_adi': Schema.string(),
            'islem': Schema.enumString(enumValues: ['ayarla', 'artir', 'azalt']),
            'miktar': Schema.number(),
            'birim': Schema.string(
                description: 'adet, kg, koli, paket… (söylenmediyse boş)', nullable: true),
          }, requiredProperties: ['urun_adi', 'islem', 'miktar'])),
      FunctionDeclaration(
          'urun_durum_degistir',
          'Bir ürünü pasife alır (satıştan kaldırır) veya yeniden aktife alır. SİLMEZ.',
          Schema.object(properties: {
            'urun_adi': Schema.string(),
            'aktif': Schema.boolean(description: 'true=aktife al, false=pasife al'),
          }, requiredProperties: ['urun_adi', 'aktif'])),
      FunctionDeclaration(
          'urun_ekle',
          'Yeni bir ürün kaydı oluşturur.',
          Schema.object(properties: {
            'urun_adi': Schema.string(),
            'satis_fiyati': Schema.number(nullable: true),
            'alis_fiyati': Schema.number(nullable: true),
            'stok': Schema.number(nullable: true),
            'barkod': Schema.string(nullable: true),
            'kdv_orani': Schema.number(
                description: 'Geçerli: 0,1,8,10,18,20', nullable: true),
            'marka': Schema.string(nullable: true),
            'kategori': Schema.string(nullable: true),
            'birim': Schema.string(nullable: true),
          }, requiredProperties: ['urun_adi'])),
      FunctionDeclaration(
          'gider_ekle',
          'Nakit bir gider kaydı oluşturur (kira, elektrik, maaş…).',
          Schema.object(properties: {
            'tutar': Schema.number(),
            'kategori': Schema.string(description: 'kira, elektrik, su, maaş…', nullable: true),
          }, requiredProperties: ['tutar'])),
      FunctionDeclaration(
          'cari_tahsilat_odeme',
          'Bir cariden tahsilat alır veya cariye ödeme yapar (nakit).',
          Schema.object(properties: {
            'cari_adi': Schema.string(),
            'tutar': Schema.number(),
            'islem': Schema.enumString(enumValues: ['tahsilat', 'odeme']),
            'odeme_turu': Schema.enumString(
                enumValues: ['nakit', 'havale', 'kart'], nullable: true),
          }, requiredProperties: ['cari_adi', 'tutar', 'islem'])),
      FunctionDeclaration(
          'cari_ekle',
          'Yeni bir müşteri/tedarikçi (cari) kaydı oluşturur.',
          Schema.object(properties: {
            'unvan': Schema.string(),
            'tip': Schema.enumString(enumValues: ['musteri', 'tedarikci']),
            'telefon': Schema.string(nullable: true),
          }, requiredProperties: ['unvan'])),
    ]),
  ];

  Future<AiEylemKomutu?> yonlendir(String soru) async {
    final apiKey = await _vision.apiKeyGetir();
    if (apiKey == null || apiKey.isEmpty) return null;

    for (final modelAdi in await AiModelSecici.adaylar()) {
      try {
        final model = GenerativeModel(
          model: modelAdi,
          apiKey: apiKey,
          tools: araclar,
          toolConfig: ToolConfig(
              functionCallingConfig: FunctionCallingConfig(mode: FunctionCallingMode.auto)),
        );
        final response = await model.generateContent([
          Content.text(
            'Bir market/perakende uygulamasının asistanısın. Kullanıcı şunu yazdı/söyledi: "$soru"\n\n'
            'Kullanıcı VERİTABANINDA BİR DEĞİŞİKLİK (fiyat/stok/ürün/gider/tahsilat/cari işlemi) '
            'İSTİYORSA uygun aracı çağır. Yalnız bilgi soruyorsa, rapor istiyorsa, "nasıl yapılır" '
            'diyorsa ya da sohbet ediyorsa HİÇBİR ARAÇ ÇAĞIRMA. Emin değilsen çağırma — '
            'yanlış işlem, işlem yapmamaktan kötüdür. Ürün/cari adındaki Türkçe ekleri at '
            '("kolanın" → "kola"). Sayı uydurma.',
          ),
        ]).timeout(const Duration(seconds: 12));
        AiModelSecici.calistiIsaretle(modelAdi);

        final call = response.functionCalls.isEmpty ? null : response.functionCalls.first;
        if (call == null) return null;
        return komutaCevir(call.name, call.args);
      } catch (e) {
        if (!AiModelSecici.modelYokHatasi(e)) {
          if (kDebugMode) debugPrint('[AiEylemYonlendirici] hata: $e');
          return null;
        }
      }
    }
    return null;
  }

  /// Gemini araç çağrısını motorun komutuna çevirir. Saf — test edilebilir.
  /// Geçersiz/eksik argümanda null döner (model uydurursa işlem YAPILMAZ).
  static AiEylemKomutu? komutaCevir(String ad, Map<String, Object?> args) {
    String? metin(String k) {
      final v = args[k];
      if (v is String && v.trim().isNotEmpty && v.toLowerCase() != 'null') return v.trim();
      return null;
    }

    double? sayi(String k) {
      final v = args[k];
      if (v is num && v.isFinite) return v.toDouble();
      return null;
    }

    switch (ad) {
      case 'urun_fiyat_guncelle':
        final urun = metin('urun_adi');
        final deger = sayi('deger');
        final islem = switch (metin('islem')) {
          'ayarla' => 'ayarla',
          'artir' => 'artir',
          'azalt' => 'azalt',
          'yuzde_artir' => 'yuzdeArtir',
          'yuzde_azalt' => 'yuzdeAzalt',
          _ => null,
        };
        if (urun == null || deger == null || islem == null || deger < 0) return null;
        final alan = switch (metin('alan')) {
          'alis' => 'alisFiyat',
          'toptan' => 'toptanFiyat',
          _ => 'satisFiyati',
        };
        return AiEylemKomutu(
            tur: AiEylemTuru.fiyatGuncelle, urunMetni: urun, fiyatAlani: alan, islem: islem, deger: deger);
      case 'urun_stok_duzenle':
        final urun = metin('urun_adi');
        final miktar = sayi('miktar');
        final islem = metin('islem');
        if (urun == null || miktar == null || miktar < 0) return null;
        if (islem != 'ayarla' && islem != 'artir' && islem != 'azalt') return null;
        return AiEylemKomutu(
            tur: AiEylemTuru.stokDuzenle,
            urunMetni: urun,
            islem: islem,
            deger: miktar,
            birim: metin('birim')?.toLowerCase());
      case 'urun_durum_degistir':
        final urun = metin('urun_adi');
        final aktif = args['aktif'];
        if (urun == null || aktif is! bool) return null;
        return AiEylemKomutu(tur: AiEylemTuru.urunDurum, urunMetni: urun, aktif: aktif);
      case 'urun_ekle':
        final urun = metin('urun_adi');
        if (urun == null) return null;
        final json = <String, dynamic>{
          'urunAdi': urun,
          if (sayi('satis_fiyati') != null) 'satisFiyati': sayi('satis_fiyati'),
          if (sayi('alis_fiyati') != null) 'alisFiyat': sayi('alis_fiyati'),
          if (sayi('stok') != null) 'stok': sayi('stok'),
          if (metin('barkod') != null) 'barkod': metin('barkod'),
          if (sayi('kdv_orani') != null) 'alisKdvOran': sayi('kdv_orani'),
          if (sayi('kdv_orani') != null) 'kdvOran': sayi('kdv_orani'),
          if (metin('marka') != null) 'marka': metin('marka'),
          if (metin('kategori') != null) 'anaGrup': metin('kategori'),
          if (metin('birim') != null) 'birim': metin('birim'),
        };
        final dogrulanmis = UrunSesJson.jsondan(json);
        if (dogrulanmis.alanlar['urunAdi'] is! String) return null;
        return AiEylemKomutu(
          tur: AiEylemTuru.urunEkle,
          urunMetni: urun,
          urunAlanlari: dogrulanmis.alanlar,
          uyarilar: dogrulanmis.anlasilmayan,
        );
      case 'gider_ekle':
        final tutar = sayi('tutar');
        if (tutar == null || tutar <= 0) return null;
        return AiEylemKomutu(
            tur: AiEylemTuru.giderEkle, deger: tutar, metin: metin('kategori'), odemeTuru: 'Nakit');
      case 'cari_tahsilat_odeme':
        final cari = metin('cari_adi');
        final tutar = sayi('tutar');
        final islem = metin('islem');
        if (cari == null || tutar == null || tutar <= 0) return null;
        if (islem != 'tahsilat' && islem != 'odeme') return null;
        final tur = switch (metin('odeme_turu')) {
          'havale' => 'Havale',
          'kart' => 'Kredi Kartı',
          _ => 'Nakit',
        };
        return AiEylemKomutu(
          tur: AiEylemTuru.tahsilatOdeme,
          cariMetni: cari,
          deger: tutar,
          islemTipi: islem == 'tahsilat' ? 'Tahsilat' : 'Odeme',
          odemeTuru: tur,
        );
      case 'cari_ekle':
        final unvan = metin('unvan');
        if (unvan == null) return null;
        return AiEylemKomutu(
          tur: AiEylemTuru.cariEkle,
          metin: unvan,
          islemTipi: metin('tip') == 'tedarikci' ? 'Tedarikçi' : 'Müşteri',
          telefon: metin('telefon'),
        );
    }
    return null;
  }
}
