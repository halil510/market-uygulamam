// lib/servisler/ai/ai_niyet_yonlendirici.dart
//
// KÖK NEDEN DÜZELTMESİ (kullanıcı bulgusu — "Akıllı Analiz'de AI
// asistanı konuşmama göre herşeyi getiremiyor, tam pro hale getir"):
// AiAnlayici SAF anahtar-kelime eşleştirmesiyle çalışır (~30 sabit
// kalıp, ai_anlayici.dart). Kullanıcı bu kalıplardan biraz farklı bir
// şekilde sorduğunda (ör. "geçen hafta ne kadar kâr ettik acaba" —
// "kâr" kelimesi var ama "düştü/azaldı" gibi tetikleyiciler yok, kalıp
// tam oturmuyor, ya da tamamen farklı bir cümle yapısı) hiçbir kalıba
// UYMAYIP doğrudan AiGenelAsistan'a (GERÇEK VERİYE ERİŞİMİ OLMAYAN genel
// sohbet) düşüyordu — kullanıcı "hiçbir şey getirmiyor" izlenimine
// kapılıyordu.
//
// Bu modül, AiAnlayici bir soruyu TANIYAMADIĞINDA devreye girer:
// AiSohbetServisi'ndeki AYNI ~27 rapor/sorgu fonksiyonunu Gemini'ye
// "araç" (function calling) olarak tanımlar ve modelden EN UYGUN olanı
// (varsa) seçmesini ister.
//
// ÇOK ÖNEMLİ — VERİ GÜVENLİĞİ: Gemini SAYILARI KENDİSİ ÜRETMEZ. Sadece
// hangi fonksiyonun çağrılacağına ve hangi parametrelerle (tarih
// aralığı, ürün/müşteri adı, limit) karar verir; gerçek rakamlar HER
// ZAMAN ai_sohbet_servisi.dart'taki AYNI, değişmemiş SQL sorgularından
// gelir. Doğal dil anlama çok esnekleşirken veri doğruluğu hiçbir
// zaman LLM'in inisiyatifine bırakılmaz — bu yüzden mevcut ~30 kalıbı
// büyütmek yerine, niyet TESPİTİNİ Gemini'ye devrettik.
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'ai_model_secici.dart';
import 'ai_modeller.dart';
import 'ai_vision_servisi.dart';

class AiNiyetYonlendirici {
  static final AiNiyetYonlendirici _i = AiNiyetYonlendirici._();
  factory AiNiyetYonlendirici() => _i;
  AiNiyetYonlendirici._();

  final _vision = AiVisionServisi(); // API anahtarını bu servisle paylaşır

  /// Gemini'nin seçtiği araç adı -> mevcut AiIntent eşlemesi. Birden
  /// fazla araç, switch'te AYNI koda gittiği için AYNI intent'e
  /// bağlanabilir (ör. tüm satış periyotları tek fonksiyonu çağırıyor).
  static const Map<String, AiIntent> fonksiyonIntent = {
    'gunluk_z_raporu': AiIntent.zRaporu,
    'urun_z_raporu': AiIntent.urunZRaporu,
    'aylik_rapor': AiIntent.aylikRapor,
    'kategori_rapor': AiIntent.grupRaporu,
    'marka_rapor': AiIntent.markaRaporu,
    'kar_degisim_aciklama': AiIntent.karDegisimAciklama,
    'net_kar': AiIntent.netKar,
    'anormal_islem_tespiti': AiIntent.anormalTespit,
    'stok_tukenme_tahmini': AiIntent.stokTukenmeTahmini,
    'satis_raporu': AiIntent.gunlukSatis,
    'kritik_stok': AiIntent.kritikStok,
    'stok_degeri': AiIntent.stokDeger,
    'stok_hareketleri': AiIntent.stokHareket,
    'urun_stok_sorgula': AiIntent.stokSorgula,
    'en_cok_satan_urunler': AiIntent.enCokSatan,
    'en_karli_urunler': AiIntent.enKarli,
    'urun_ara': AiIntent.urunAra,
    'urun_listele': AiIntent.urunListele,
    'kasa_durumu': AiIntent.kasaDurumu,
    'odeme_dagilimi': AiIntent.odemeYontemi,
    'cari_listele': AiIntent.cariListele,
    'musteri_bakiye_sorgula': AiIntent.cariBorc,
    'cari_hareketleri': AiIntent.cariHareket,
    'tahsilat_odeme_ozeti': AiIntent.tahsilat,
    'satis_tahmini': AiIntent.tahmin,
    'siparis_onerileri': AiIntent.oneri,
    'grup_detaylari': AiIntent.grupDetay,
    'alan1_detaylari': AiIntent.alan1Detay,
    'genel_stok_durumu': AiIntent.stokGenelDurum,
  };

  static final List<Tool> araclar = [
    Tool(functionDeclarations: [
      FunctionDeclaration(
          'gunluk_z_raporu',
          'Bir günün Z raporu / gün sonu satış özeti (varsayılan bugün).',
          Schema.object(properties: {
            'tarih': Schema.string(
                description: 'YYYY-AA-GG formatında gün, belirtilmezse bugün',
                nullable: true),
          })),
      FunctionDeclaration(
          'urun_z_raporu',
          'Bir günün ürün bazlı Z raporu (hangi üründen kaç adet satıldı).',
          Schema.object(properties: {
            'tarih': Schema.string(nullable: true),
          })),
      FunctionDeclaration(
          'aylik_rapor',
          'Belirli bir ayın satış özeti (varsayılan bu ay).',
          Schema.object(properties: {
            'tarih': Schema.string(
                description: 'Ayın herhangi bir günü, YYYY-AA-GG',
                nullable: true),
          })),
      FunctionDeclaration(
          'kategori_rapor',
          'Ana gruba/kategoriye göre satış dağılımı raporu.',
          Schema.object(properties: {
            'baslangic_tarih': Schema.string(nullable: true),
            'bitis_tarih': Schema.string(nullable: true),
          })),
      FunctionDeclaration(
          'marka_rapor',
          'Markaya göre satış dağılımı raporu.',
          Schema.object(properties: {
            'baslangic_tarih': Schema.string(nullable: true),
            'bitis_tarih': Schema.string(nullable: true),
          })),
      FunctionDeclaration('kar_degisim_aciklama',
          'Kârın önceki döneme göre neden arttığını/azaldığını açıklar.', null),
      FunctionDeclaration(
          'net_kar',
          'Belirli bir dönemin net kârı (ciro eksi maliyet eksi giderler).',
          Schema.object(properties: {
            'baslangic_tarih': Schema.string(nullable: true),
            'bitis_tarih': Schema.string(nullable: true),
            'periyot_adi': Schema.string(
                description: 'Örn: "Bu Ay", "Geçen Hafta", "Bugün"',
                nullable: true),
          })),
      FunctionDeclaration('anormal_islem_tespiti',
          'Şüpheli/olağandışı satış veya iade işlemlerini tespit eder.', null),
      FunctionDeclaration(
          'stok_tukenme_tahmini',
          'Ürünlerin mevcut satış hızına göre ne zaman tükeneceğini tahmin eder.',
          null),
      FunctionDeclaration(
          'satis_raporu',
          'Belirli bir dönemin satış/ciro özeti (işlem sayısı, ciro, iskonto, KDV).',
          Schema.object(properties: {
            'baslangic_tarih': Schema.string(nullable: true),
            'bitis_tarih': Schema.string(nullable: true),
            'periyot_adi': Schema.string(nullable: true),
          })),
      FunctionDeclaration('kritik_stok',
          'Stoğu minimum seviyenin altına düşmüş ürünlerin listesi.', null),
      FunctionDeclaration(
          'stok_degeri', 'Depodaki tüm stoğun alış/satış değeri toplamı.', null),
      FunctionDeclaration(
          'stok_hareketleri',
          'Belirli bir dönemdeki stok giriş/çıkış hareketleri özeti.',
          Schema.object(properties: {
            'baslangic_tarih': Schema.string(nullable: true),
            'bitis_tarih': Schema.string(nullable: true),
            'periyot_adi': Schema.string(nullable: true),
          })),
      FunctionDeclaration(
          'urun_stok_sorgula',
          'Belirli TEK BİR ürünün stok/fiyat bilgisini sorgular.',
          Schema.object(properties: {
            'urun_adi':
                Schema.string(description: 'Aranan ürünün adı veya bir kısmı'),
          }, requiredProperties: [
            'urun_adi'
          ])),
      FunctionDeclaration(
          'en_cok_satan_urunler',
          'Belirli dönemde en çok satan ürünler listesi.',
          Schema.object(properties: {
            'baslangic_tarih': Schema.string(nullable: true),
            'bitis_tarih': Schema.string(nullable: true),
            'limit': Schema.integer(
                description: 'Kaç ürün gösterilsin, varsayılan 10',
                nullable: true),
          })),
      FunctionDeclaration(
          'en_karli_urunler', 'En yüksek kâr marjına sahip ürünler listesi.', null),
      FunctionDeclaration(
          'urun_ara',
          'Ürün adı, barkod veya koduna göre ürün arar (fiyat/stok bilgisiyle, birden fazla sonuç dönebilir).',
          Schema.object(properties: {
            'arama_metni': Schema.string(),
          }, requiredProperties: [
            'arama_metni'
          ])),
      FunctionDeclaration(
          'urun_listele',
          'Tüm aktif ürünleri listeler.',
          Schema.object(properties: {
            'limit': Schema.integer(nullable: true),
          })),
      FunctionDeclaration('kasa_durumu', 'Güncel kasa (nakit) bakiyesi.', null),
      FunctionDeclaration(
          'odeme_dagilimi',
          'Belirli dönemde nakit/kart ödeme yöntemi dağılımı.',
          Schema.object(properties: {
            'baslangic_tarih': Schema.string(nullable: true),
            'bitis_tarih': Schema.string(nullable: true),
            'periyot_adi': Schema.string(nullable: true),
          })),
      FunctionDeclaration(
          'cari_listele', 'Bakiyesi olan carilerin (müşteri/tedarikçi) listesi.', null),
      FunctionDeclaration(
          'musteri_bakiye_sorgula',
          'Belirli TEK BİR müşterinin/carinin bakiye ve borç bilgisi.',
          Schema.object(properties: {
            'musteri_adi': Schema.string(),
          }, requiredProperties: [
            'musteri_adi'
          ])),
      FunctionDeclaration(
          'cari_hareketleri',
          'Son cari hareketleri (tahsilat/ödeme/borç) listesi.',
          Schema.object(properties: {
            'limit': Schema.integer(nullable: true),
          })),
      FunctionDeclaration(
          'tahsilat_odeme_ozeti',
          'Belirli dönemde yapılan tahsilat ve ödemelerin toplamı.',
          Schema.object(properties: {
            'baslangic_tarih': Schema.string(nullable: true),
            'bitis_tarih': Schema.string(nullable: true),
            'periyot_adi': Schema.string(nullable: true),
          })),
      FunctionDeclaration(
          'satis_tahmini',
          'Geçmiş satış ortalamasına göre gelecek N günün ciro tahmini.',
          Schema.object(properties: {
            'gun_sayisi': Schema.integer(nullable: true),
          })),
      FunctionDeclaration('siparis_onerileri',
          'Stoğu azalan ürünler için tedarikçiden sipariş önerileri.', null),
      FunctionDeclaration('grup_detaylari',
          'Tüm ürün gruplarının/kategorilerin ürün sayısı ve stok özeti.', null),
      FunctionDeclaration('alan1_detaylari',
          "Ürünlerin 'alan1' (marka/etiket) alanına göre dağılımı.", null),
      FunctionDeclaration('genel_stok_durumu',
          'Tüm envanterin genel stok sağlığı özeti (stoksuz/kritik/normal ürün sayıları, depo değeri).',
          null),
    ]),
  ];

  /// AiAnlayici bir soruyu TANIYAMADIĞINDA (AiIntent.bilinmiyor)
  /// çağrılır. Gemini bir araç seçerse, bunu AiSoru'ya (mevcut
  /// intent/params sözleşmesiyle) çevirip döner — çağıran taraf mevcut
  /// switch üzerinden AYNI, değişmemiş rapor fonksiyonlarını çalıştırır.
  /// Hiçbir araç uymuyorsa (gerçekten genel bir soru/komutsa) null
  /// döner — çağıran taraf mevcut genel sohbet akışına devam eder.
  Future<AiSoru?> yonlendir(String soru) async {
    final apiKey = await _vision.apiKeyGetir();
    if (apiKey == null || apiKey.isEmpty) return null;

    for (final modelAdi in await AiModelSecici.adaylar()) {
      try {
        final model = GenerativeModel(
          model: modelAdi,
          apiKey: apiKey,
          tools: araclar,
          toolConfig: ToolConfig(
              functionCallingConfig:
                  FunctionCallingConfig(mode: FunctionCallingMode.auto)),
        );
        final bugun = DateTime.now();
        final bugunStr = '${bugun.year}-${bugun.month.toString().padLeft(2, '0')}-'
            '${bugun.day.toString().padLeft(2, '0')}';
        final response = await model.generateContent([
          Content.text(
            'Bugünün tarihi: $bugunStr.\n'
            'Kullanıcının market/perakende POS uygulamasına sorduğu soru: '
            '"$soru"\n\n'
            'Bu soru mağaza verileriyle (satış, stok, cari, kâr, rapor) '
            'ilgiliyse en uygun aracı çağır. Tarih belirtilmemişse ilgili '
            'aracın varsayılan davranışına güven. İlgili hiçbir araç yoksa '
            '(genel sohbet, "nasıl yaparım" tarzı yönlendirme sorusu veya '
            'bir ekrana gitme komutuysa) HİÇBİR ARAÇ ÇAĞIRMA.',
          ),
        ]).timeout(const Duration(seconds: 12));
        AiModelSecici.calistiIsaretle(modelAdi);

        final call =
            response.functionCalls.isEmpty ? null : response.functionCalls.first;
        if (call == null) return null;

        final intent = fonksiyonIntent[call.name];
        if (intent == null) return null; // bilinmeyen araç adı — güvenli tarafta kal

        return AiSoru(metin: soru, intent: intent, params: paramlariCoz(call.args));
      } catch (e) {
        if (!AiModelSecici.modelYokHatasi(e)) {
          if (kDebugMode) debugPrint('[AiNiyetYonlendirici] hata: $e');
          return null; // ağ/kota/başka bir hata — genel sohbete düşülsün
        }
        // model artık yoksa (404/no longer available) sıradaki denenir
      }
    }
    return null;
  }

  /// Gemini'nin araç çağrısından gelen ham argümanları, mevcut
  /// AiSoru.params sözleşmesine (bas/bit/periyot/sayi/urunAdi/musteriAdi)
  /// çevirir. DB/ağ bağımlılığı olmadan izole test edilebilsin diye
  /// static/saf tutuldu (bkz. sync_cakisma_tespit.dart'taki aynı desen).
  static Map<String, dynamic> paramlariCoz(Map<String, Object?> args) {
    final p = <String, dynamic>{};

    DateTime? tarihCoz(Object? v) {
      if (v is! String || v.trim().isEmpty) return null;
      return DateTime.tryParse(v.trim());
    }

    final gun = tarihCoz(args['tarih']);
    final bas = tarihCoz(args['baslangic_tarih']) ?? gun;
    final bit = tarihCoz(args['bitis_tarih']) ?? gun;

    if (bas != null) p['bas'] = DateTime(bas.year, bas.month, bas.day);
    if (bit != null) p['bit'] = DateTime(bit.year, bit.month, bit.day, 23, 59, 59);
    if (args['periyot_adi'] is String) p['periyot'] = args['periyot_adi'];

    final limit = args['limit'] ?? args['gun_sayisi'];
    if (limit is num) p['sayi'] = limit.toInt();

    if (args['urun_adi'] is String) p['urunAdi'] = args['urun_adi'];
    if (args['arama_metni'] is String) p['urunAdi'] = args['arama_metni'];
    if (args['musteri_adi'] is String) p['musteriAdi'] = args['musteri_adi'];

    return p;
  }
}
