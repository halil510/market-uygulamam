// lib/servisler/gib/gib_ubl_olusturucu.dart
//
// GİB UBL-TR XML üretimi — e-Fatura/e-Arşiv (Invoice) ve e-İrsaliye
// (DespatchAdvice). Saf, ağ çağrısı yapmayan bir "belge üretici":
// girdi (FaturaModel / irsaliye map'i + ETTN) alır, UBL-TR XML string'i
// döner. Gönderim (HTTP) sorumluluğu bilerek burada DEĞİL, gib_servisi
// .dart'ta kalıyor — bu sınıf sadece "doğru XML'i nasıl üretirim?"
// sorusuna cevap veriyor.
//
// (Madde 2 mimari denetimi — gib_servisi.dart 1045 satırlık tek
// dosyaydı, bu iki XML üretici fonksiyon (~350 satır) kendi başına
// bağımsız bir sorumluluktu. Buraya TAŞINDI — DAVRANIŞ DEĞİŞMEDİ, saf
// bir extract class refactor'ü. Orijinal yorumlar/gerekçeler aynen
// korunuyor.)
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../modeller/fatura_model.dart';
import '../../veri/database/veritabani.dart';
import 'gib_ayar_yoneticisi.dart';
import 'gib_tipleri.dart';

class GibUblOlusturucu {
  final GibAyarYoneticisi _ayar;
  const GibUblOlusturucu(this._ayar);

  /// Türkçe ödeme şeklini UBL/UNCL4461 standart koduna çevirir — UBL-TR
  /// XML'inde PaymentMeans bölümü için.
  String _odemeSekliKodu(String? odemeSekli) => switch (odemeSekli) {
        'Nakit' => '10',
        'Kredi Kartı' => '48',
        'Havale/EFT' => '42',
        'Çek' => '20',
        _ => '1', // Tanımlanmamış/Diğer
      };

  // ── UBL-TR XML oluştur (e-Fatura/e-Arşiv) ───────────────────────────────
  Future<String> ublXmlOlustur({
    required FaturaModel fatura,
    required String ettn,
    EFaturaTipi tip = EFaturaTipi.eArsiv,
  }) async {
    final tarihFmt = DateFormat('yyyy-MM-dd');
    final saatFmt  = DateFormat('HH:mm:ss');
    final now      = DateTime.now();
    final faturaNo = fatura.faturaNo ?? 'TMP${now.millisecondsSinceEpoch}';
    final vkn      = _ayar.firmaVkn ?? '0000000000';

    final satirlar = fatura.detaylar.map((k) {
      final kdvTutar = k.kdvTutari;
      // 🔴 DÜZELTME (Madde 21, 2026-09-16): UBL-TR'de PriceAmount ×
      // InvoicedQuantity = LineExtensionAmount ilişkisi (ikisi de KDV
      // HARİÇ) beklenir. k.birimFiyat müşteriye gösterilen KDV DAHİL
      // birim fiyat olduğundan (PDF/fiş basımında doğru kullanımı budur,
      // bkz. yazdirma_servisi.dart), burada SADECE XML için ayrıca net
      // birim fiyat türetiliyor — k.birimFiyat alanının kendisi
      // değiştirilmedi.
      final netBirimFiyat = k.miktar > 0 ? k.araToplam / k.miktar : k.birimFiyat;
      return '''
    <cac:InvoiceLine>
      <cbc:ID>${fatura.detaylar.indexOf(k) + 1}</cbc:ID>
      <cbc:InvoicedQuantity unitCode="C62">${k.miktar.toStringAsFixed(4)}</cbc:InvoicedQuantity>
      <cbc:LineExtensionAmount currencyID="TRY">${k.araToplam.toStringAsFixed(2)}</cbc:LineExtensionAmount>
      <cac:TaxTotal>
        <cbc:TaxAmount currencyID="TRY">${kdvTutar.toStringAsFixed(2)}</cbc:TaxAmount>
        <cac:TaxSubtotal>
          <cbc:TaxableAmount currencyID="TRY">${k.araToplam.toStringAsFixed(2)}</cbc:TaxableAmount>
          <cbc:TaxAmount currencyID="TRY">${kdvTutar.toStringAsFixed(2)}</cbc:TaxAmount>
          <cbc:Percent>${k.kdvOrani.toStringAsFixed(0)}</cbc:Percent>
          <cac:TaxCategory>
            <cac:TaxScheme>
              <cbc:Name>KDV</cbc:Name>
              <cbc:TaxTypeCode>0015</cbc:TaxTypeCode>
            </cac:TaxScheme>
          </cac:TaxCategory>
        </cac:TaxSubtotal>
      </cac:TaxTotal>
      <cac:Item>
        <cbc:Description>${_xmlEscape(k.urunAdi)}</cbc:Description>
        <cbc:Name>${_xmlEscape(k.urunAdi)}</cbc:Name>
      </cac:Item>
      <cac:Price>
        <cbc:PriceAmount currencyID="TRY">${netBirimFiyat.toStringAsFixed(4)}</cbc:PriceAmount>
      </cac:Price>
    </cac:InvoiceLine>''';
    }).join('\n');

    final genelToplam = fatura.genelToplam;
    final kdvToplam   = fatura.toplamKdv;
    final matrah      = genelToplam - kdvToplam;

    // ÖNCEDEN BURADA CİDDİ BİR GİB UYUMLULUK HATASI VARDI: fatura
    // seviyesindeki KDV toplamı, kalemlerin GERÇEK oranlarına
    // bakılmaksızın SABİT "%18" olarak yazılıyordu — hem Türkiye'nin
    // güncel standart oranı artık %20 (Temmuz 2023'ten beri) hem de
    // farklı KDV oranlı ürünler (örn. bazı gıda %1, bazıları %10,
    // bazıları %20) içeren KARIŞIK bir faturada bu tamamen yanlış
    // olurdu. UBL-TR standardı, HER FARKLI KDV ORANI İÇİN AYRI bir
    // TaxSubtotal bloğu gerektirir — market faturalarında bu çok
    // yaygın bir senaryodur (aynı fişte hem temel gıda hem standart
    // oranlı ürün). Artık kalemler KDV oranına göre gruplanıp her
    // grup için doğru, ayrı bir TaxSubtotal üretiliyor.
    final oranGruplari = <double, ({double matrah, double kdv})>{};
    for (final k in fatura.detaylar) {
      final mevcut = oranGruplari[k.kdvOrani] ?? (matrah: 0.0, kdv: 0.0);
      oranGruplari[k.kdvOrani] = (
        matrah: mevcut.matrah + k.araToplam,
        kdv: mevcut.kdv + k.kdvTutari,
      );
    }
    final taxSubtotallar = oranGruplari.entries.map((e) => '''
    <cac:TaxSubtotal>
      <cbc:TaxableAmount currencyID="TRY">${e.value.matrah.toStringAsFixed(2)}</cbc:TaxableAmount>
      <cbc:TaxAmount currencyID="TRY">${e.value.kdv.toStringAsFixed(2)}</cbc:TaxAmount>
      <cbc:Percent>${e.key.toStringAsFixed(0)}</cbc:Percent>
      <cac:TaxCategory>
        <cac:TaxScheme>
          <cbc:Name>KDV</cbc:Name>
          <cbc:TaxTypeCode>0015</cbc:TaxTypeCode>
        </cac:TaxScheme>
      </cac:TaxCategory>
    </cac:TaxSubtotal>''').join('\n');

    // 🔴🔴🔴 KRİTİK DÜZELTME (bağımsız araştırmayla doğrulandı — GİB'in
    // resmi UBL-TR Kod Listeleri sirkülerleri): InvoiceTypeCode ÖNCEDEN
    // HER ZAMAN "SATIS" olarak sabitlenmişti — fatura.faturaTipi hiç
    // kontrol edilmiyordu. Bir İADE faturası bile "SATIS" tipinde GİB'e
    // gönderilebiliyordu, ki bu doğrudan mevzuata aykırıdır. Resmi geçerli
    // değerler: SATIS (normal satış), IADE (mal iadesi), TEVKIFAT (KDV
    // tevkifatlı satış). Tevkifat için tevkifatVar/tevkifatOrani
    // Ayarlar > Fatura Ayarları'ndan (aynı yerden fatura_detay_ekrani.dart
    // PDF'inde de okunan) alınıyor — artık GİB'e giden RESMİ belge ile
    // müşteriye gösterilen PDF ARTIK TUTARLI.
    final tevkifatPrefs = await SharedPreferences.getInstance();
    final tevkifatVar = tevkifatPrefs.getBool('tevkifat') ?? false;
    final tevkifatOrani = tevkifatPrefs.getString('tevkifat_orani') ?? '';

    // ══════════════════════════════════════════════════════════════════════
    // 🔴 KRİTİK — TEVKİFAT DESTEĞİ TAMAMLANMAMIŞ (analiz bulgusu)
    //
    // ÖNCEDEN: Ayarlar'da tevkifat açıksa InvoiceTypeCode 'TEVKIFAT'
    // yapılıyordu — AMA XML'e `cac:WithholdingTaxTotal` bloğu HİÇ
    // eklenmiyordu. `tevkifatOrani` okunuyor ama hiçbir yerde
    // kullanılmıyordu (analizör `unused_local_variable` ile yakaladı).
    //
    // UBL-TR şematronu, InvoiceTypeCode='TEVKIFAT' olan bir faturada
    // WithholdingTaxTotal bloğunu ZORUNLU tutar. Blok olmadan GİB
    // faturayı REDDEDER — kullanıcı sebebini anlamayan bir hata alır.
    //
    // NEDEN BURADA TAMAMLAMIYORUZ: Blok, oranın yanı sıra GİB'in
    // "Tevkifat Kodları" listesinden bir `TaxTypeCode` ister ve bu kod
    // HİZMET TÜRÜNE göre değişir (601 yapım işleri, 603 makine bakım,
    // 617 temizlik, 620 yemek servisi … ~25 kod). Uygulamada bu bilgiyi
    // tutan bir alan YOK. Rastgele bir kod yazmak, GİB'in KABUL ETTİĞİ
    // ama hukuken YANLIŞ bir fatura üretir — bu, reddedilmekten daha
    // kötüdür (yanlış vergi muamelesi, sonradan cezai işlem).
    //
    // TAMAMLAMAK İÇİN GEREKENLER:
    //   1) Ürün/hizmet ya da fatura düzeyinde "tevkifat kodu" alanı
    //   2) Ayarlar > Fatura'ya GİB tevkifat kodu seçimi
    //   3) Bu blok:
    //        <cac:WithholdingTaxTotal>
    //          <cbc:TaxAmount>tevkif edilen KDV</cbc:TaxAmount>
    //          <cac:TaxSubtotal>
    //            <cbc:TaxableAmount>toplam KDV</cbc:TaxableAmount>
    //            <cbc:TaxAmount>tevkif edilen</cbc:TaxAmount>
    //            <cbc:Percent>oran</cbc:Percent>
    //            <cac:TaxCategory><cac:TaxScheme>
    //              <cbc:Name>KDV TEVKİFATI</cbc:Name>
    //              <cbc:TaxTypeCode>601/617/620…</cbc:TaxTypeCode>
    //            </cac:TaxScheme></cac:TaxCategory>
    //          </cac:TaxSubtotal>
    //        </cac:WithholdingTaxTotal>
    //   4) LegalMonetaryTotal/PayableAmount'un tevkif edilen tutar kadar
    //      DÜŞÜRÜLMESİ
    //
    // O ZAMANA KADAR: sessizce bozuk fatura göndermek yerine açık hata.
    // ══════════════════════════════════════════════════════════════════════
    if (tevkifatVar && fatura.faturaTipi != 'İade') {
      throw Exception(
        'Tevkifatlı fatura gönderimi henüz desteklenmiyor.\n\n'
        'Ayarlar > Fatura Ayarları\'nda "Tevkifat (KDV Stopajı)" açık '
        '(oran: ${tevkifatOrani.isEmpty ? "belirtilmemiş" : tevkifatOrani}). '
        'Ancak e-Fatura XML\'ine zorunlu olan tevkifat bloğu henüz '
        'eklenmedi; GİB bu faturayı reddederdi.\n\n'
        'Bu faturayı gönderebilmek için Ayarlar > Fatura Ayarları\'ndan '
        'tevkifatı geçici olarak kapatın, ya da faturayı manuel olarak '
        'GİB portalından kesin.',
      );
    }

    final invoiceTypeCode = fatura.faturaTipi == 'İade' ? 'IADE' : 'SATIS';

    // GİB'in IADEInvoiceCheck şematron kuralı (2026 güncellemesiyle
    // zorunlu): bir İADE faturası, iadeye konu olan ORİJİNAL faturaya
    // BillingReference ile atıf yapmak ZORUNDADIR. fatura.iadeId ->
    // iade kaydı -> satis_id -> o satışın orijinal faturası (varsa)
    // zincirinden bulunuyor. Orijinal fatura bulunamazsa (henüz
    // kesilmemişse) bu blok atlanır — GİB'e boş/yanlış bir referans
    // göndermek, hiç göndermemekten kötüdür.
    String billingReferenceXml = '';
    if (fatura.faturaTipi == 'İade' && fatura.iadeId != null) {
      try {
        final db = await Veritabani().db;
        final iadeRows = await db.query('iade', columns: ['satis_id'], where: 'id = ?', whereArgs: [fatura.iadeId], limit: 1);
        if (iadeRows.isNotEmpty && iadeRows.first['satis_id'] != null) {
          final orijinalFaturaRows = await db.query('faturalar',
              columns: ['fatura_no'], where: 'satis_id = ? AND deleted_at IS NULL',
              whereArgs: [iadeRows.first['satis_id']], limit: 1);
          if (orijinalFaturaRows.isNotEmpty && orijinalFaturaRows.first['fatura_no'] != null) {
            final orijinalFaturaNo = orijinalFaturaRows.first['fatura_no'] as String;
            billingReferenceXml = '''
  <cac:BillingReference>
    <cac:InvoiceDocumentReference>
      <cbc:ID>$orijinalFaturaNo</cbc:ID>
      <cbc:DocumentTypeCode>IADE</cbc:DocumentTypeCode>
    </cac:InvoiceDocumentReference>
  </cac:BillingReference>
''';
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('İade referans faturası bulunamadı: $e');
      }
    }

    return '''<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
  xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
  xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
  xmlns:ext="urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2">
  <cbc:UBLVersionID>2.1</cbc:UBLVersionID>
  <cbc:CustomizationID>TR1.2</cbc:CustomizationID>
  <cbc:ProfileID>${tip == EFaturaTipi.eFatura ? 'TICARIFATURA' : 'EARSIVFATURA'}</cbc:ProfileID>
  <cbc:ID>$faturaNo</cbc:ID>
  <cbc:CopyIndicator>false</cbc:CopyIndicator>
  <cbc:UUID>$ettn</cbc:UUID>
  <cbc:IssueDate>${tarihFmt.format(now)}</cbc:IssueDate>
  <cbc:IssueTime>${saatFmt.format(now)}</cbc:IssueTime>
  <cbc:InvoiceTypeCode>$invoiceTypeCode</cbc:InvoiceTypeCode>
  <cbc:DocumentCurrencyCode>TRY</cbc:DocumentCurrencyCode>
  <cbc:LineCountNumeric>${fatura.detaylar.length}</cbc:LineCountNumeric>

  <cac:AccountingSupplierParty>
    <cac:Party>
      <cac:PartyIdentification>
        <cbc:ID schemeID="VKN">$vkn</cbc:ID>
      </cac:PartyIdentification>
      <cac:PartyName>
        <cbc:Name>${_xmlEscape(_ayar.firmaAdi.isNotEmpty ? _ayar.firmaAdi : 'MarketPlus')}</cbc:Name>
      </cac:PartyName>
      <cac:PostalAddress>
        <cbc:StreetName>${_xmlEscape(_ayar.firmaAdres)}</cbc:StreetName>
        <cac:Country>
          <cbc:IdentificationCode>TR</cbc:IdentificationCode>
        </cac:Country>
      </cac:PostalAddress>
      <cac:PartyTaxScheme>
        <cbc:RegistrationName>${_xmlEscape(_ayar.firmaAdi)}</cbc:RegistrationName>
        <cac:TaxScheme>
          <cbc:Name>${_xmlEscape(_ayar.firmaVergiDairesi)}</cbc:Name>
        </cac:TaxScheme>
      </cac:PartyTaxScheme>
    </cac:Party>
  </cac:AccountingSupplierParty>

  <!-- 🔴 Derin denetimde bulundu (P1): müşteri PostalAddress/
       PartyTaxScheme HİÇ gönderilmiyordu — aynı dosyadaki e-İrsaliye
       (DeliveryCustomerParty) bunu doğru dolduruyor, e-Fatura'da bu
       adım unutulmuştu. FaturaModel.cariAdres/cariVergiDairesi zaten
       doluyordu (faturalandirma_servisi.dart), sadece burada
       kullanılmıyordu. Gerçek B2B e-Fatura'da bu eksik zorunlu
       alanlar entegratör/GİB tarafından reddedilmeye yol açabilir. -->
  <cac:AccountingCustomerParty>
    <cac:Party>
      <cac:PartyIdentification>
        <cbc:ID schemeID="${(fatura.cariVergiNo?.length ?? 0) == 10 ? 'VKN' : 'TCKN'}">${fatura.cariVergiNo ?? '11111111111'}</cbc:ID>
      </cac:PartyIdentification>
      <cac:PartyName>
        <cbc:Name>${_xmlEscape(fatura.cariUnvan ?? '-')}</cbc:Name>
      </cac:PartyName>
      <cac:PostalAddress>
        <cbc:StreetName>${_xmlEscape(fatura.cariAdres ?? '')}</cbc:StreetName>
        <cac:Country>
          <cbc:IdentificationCode>TR</cbc:IdentificationCode>
        </cac:Country>
      </cac:PostalAddress>
      <cac:PartyTaxScheme>
        <cbc:RegistrationName>${_xmlEscape(fatura.cariUnvan ?? '-')}</cbc:RegistrationName>
        <cac:TaxScheme>
          <cbc:Name>${_xmlEscape(fatura.cariVergiDairesi ?? '')}</cbc:Name>
        </cac:TaxScheme>
      </cac:PartyTaxScheme>
    </cac:Party>
  </cac:AccountingCustomerParty>
$billingReferenceXml
  <cac:PaymentMeans>
    <cbc:PaymentMeansCode>${_odemeSekliKodu(fatura.odemeSekli)}</cbc:PaymentMeansCode>
    <cbc:PaymentDueDate>${DateFormat('yyyy-MM-dd').format(fatura.tarih)}</cbc:PaymentDueDate>
  </cac:PaymentMeans>

  <cac:TaxTotal>
    <cbc:TaxAmount currencyID="TRY">${kdvToplam.toStringAsFixed(2)}</cbc:TaxAmount>
$taxSubtotallar
  </cac:TaxTotal>

  <cac:LegalMonetaryTotal>
    <cbc:LineExtensionAmount currencyID="TRY">${matrah.toStringAsFixed(2)}</cbc:LineExtensionAmount>
    <cbc:TaxExclusiveAmount currencyID="TRY">${matrah.toStringAsFixed(2)}</cbc:TaxExclusiveAmount>
    <cbc:TaxInclusiveAmount currencyID="TRY">${genelToplam.toStringAsFixed(2)}</cbc:TaxInclusiveAmount>
    <cbc:PayableAmount currencyID="TRY">${genelToplam.toStringAsFixed(2)}</cbc:PayableAmount>
  </cac:LegalMonetaryTotal>
$satirlar
</Invoice>''';
  }

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  // ══════════════════════════════════════════════════════════════════════
  // e-İRSALİYE (DespatchAdvice) — kullanıcı isteği (2026-09-14): sevk
  // irsaliyelerinin GİB'e e-İrsaliye olarak gönderilmesi. Ayarlar'daki
  // "e-İrsaliye Aktif" anahtarı ÖNCEDEN hiçbir koda bağlı DEĞİLDİ — sadece
  // süslemelikti, hiçbir yerde gönderim yapılmıyordu. Bu bölüm o eksiği
  // kapatıyor.
  //
  // ⚠️ ÖNEMLİ DÜRÜSTLÜK NOTU: e-Fatura (Invoice) UBL-TR formatı yaygın
  // dokümante edilmiş, bu dosyadaki ublXmlOlustur() önceki oturumlarda
  // birkaç kez bağımsız araştırmayla çapraz kontrol edildi. e-İrsaliye
  // (DespatchAdvice) formatı GİB'in AYRI bir UBL-TR profili (TEMELIRSALIYE)
  // — burada üretilen XML, UBL-TR DespatchAdvice'ın genel/bilinen iskeletine
  // (parti bilgileri + sevk satırları, VERGİ/TUTAR İÇERMEZ) dayanıyor ama
  // BU ORTAMDA GERÇEK bir GİB şematronuna veya entegratör test ortamına
  // karşı DOĞRULANAMADI. e-Fatura'nın aksine (yanlış vergi/tutar riski),
  // bir irsaliyenin YANLIŞ İÇERİĞİ genelde sadece GİB/entegratör tarafından
  // REDDEDİLİR (parasal/vergisel bir yükümlülük içermediği için yanlış-ama-
  // kabul-edilmiş riski çok daha düşük) — yine de CANLI modda kullanmadan
  // önce entegratörünüzün TEST ortamında deneyip mali müşavirinizle teyit
  // etmenizi ÖNERİRİM.
  // ══════════════════════════════════════════════════════════════════════

  /// [irsaliye] en az şu anahtarları içermeli: id, irsaliye_no, tarih, tip
  /// ('Çıkış'/'Giriş'), cari_adi, cari_vergi_no, cari_vergi_dairesi,
  /// cari_adres (hepsi opsiyonel/null olabilir — eksikse XML'de '-' yazılır,
  /// gönderim ENGELLENMEZ). [kalemler]'in her biri: urun_adi, miktar,
  /// (opsiyonel) birim_fiyat.
  Future<String> ublDespatchAdviceOlustur({
    required Map<String, dynamic> irsaliye,
    required List<Map<String, dynamic>> kalemler,
    required String ettn,
  }) async {
    final tarihFmt = DateFormat('yyyy-MM-dd');
    final saatFmt  = DateFormat('HH:mm:ss');
    final now      = DateTime.now();
    final belgeTarihi = DateTime.tryParse(irsaliye['tarih']?.toString() ?? '') ?? now;
    final irsaliyeNo  = irsaliye['irsaliye_no']?.toString() ?? 'TMP${now.millisecondsSinceEpoch}';
    final vkn = _ayar.firmaVkn ?? '0000000000';
    final cariVergiNo = irsaliye['cari_vergi_no']?.toString() ?? '';
    final cariSchemeId = cariVergiNo.length == 10 ? 'VKN' : 'TCKN';

    final satirlar = kalemler.asMap().entries.map((e) {
      final i = e.key + 1;
      final k = e.value;
      final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
      final urunAdi = k['urun_adi']?.toString() ?? k['urun_adi_db']?.toString() ?? '-';
      return '''
    <cac:DespatchLine>
      <cbc:ID>$i</cbc:ID>
      <cbc:DeliveredQuantity unitCode="C62">${miktar.toStringAsFixed(4)}</cbc:DeliveredQuantity>
      <cac:Item>
        <cbc:Name>${_xmlEscape(urunAdi)}</cbc:Name>
      </cac:Item>
    </cac:DespatchLine>''';
    }).join('\n');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<DespatchAdvice xmlns="urn:oasis:names:specification:ubl:schema:xsd:DespatchAdvice-2"
  xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
  xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
  xmlns:ext="urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2">
  <cbc:UBLVersionID>2.1</cbc:UBLVersionID>
  <cbc:CustomizationID>TR1.2</cbc:CustomizationID>
  <cbc:ProfileID>TEMELIRSALIYE</cbc:ProfileID>
  <cbc:ID>$irsaliyeNo</cbc:ID>
  <cbc:CopyIndicator>false</cbc:CopyIndicator>
  <cbc:UUID>$ettn</cbc:UUID>
  <cbc:IssueDate>${tarihFmt.format(belgeTarihi)}</cbc:IssueDate>
  <cbc:IssueTime>${saatFmt.format(now)}</cbc:IssueTime>
  <cbc:DespatchAdviceTypeCode>SEVK</cbc:DespatchAdviceTypeCode>
  <cbc:Note>${_xmlEscape(irsaliye['aciklama']?.toString() ?? '')}</cbc:Note>
  <cbc:LineCountNumeric>${kalemler.length}</cbc:LineCountNumeric>

  <cac:DespatchSupplierParty>
    <cac:Party>
      <cac:PartyIdentification>
        <cbc:ID schemeID="VKN">$vkn</cbc:ID>
      </cac:PartyIdentification>
      <cac:PartyName>
        <cbc:Name>${_xmlEscape(_ayar.firmaAdi.isNotEmpty ? _ayar.firmaAdi : 'MarketPlus')}</cbc:Name>
      </cac:PartyName>
      <cac:PostalAddress>
        <cbc:StreetName>${_xmlEscape(_ayar.firmaAdres)}</cbc:StreetName>
        <cac:Country><cbc:IdentificationCode>TR</cbc:IdentificationCode></cac:Country>
      </cac:PostalAddress>
      <cac:PartyTaxScheme>
        <cbc:RegistrationName>${_xmlEscape(_ayar.firmaAdi)}</cbc:RegistrationName>
        <cac:TaxScheme><cbc:Name>${_xmlEscape(_ayar.firmaVergiDairesi)}</cbc:Name></cac:TaxScheme>
      </cac:PartyTaxScheme>
    </cac:Party>
  </cac:DespatchSupplierParty>

  <cac:DeliveryCustomerParty>
    <cac:Party>
      <cac:PartyIdentification>
        <cbc:ID schemeID="$cariSchemeId">${cariVergiNo.isNotEmpty ? cariVergiNo : '11111111111'}</cbc:ID>
      </cac:PartyIdentification>
      <cac:PartyName>
        <cbc:Name>${_xmlEscape(irsaliye['cari_adi']?.toString() ?? '-')}</cbc:Name>
      </cac:PartyName>
      <cac:PostalAddress>
        <cbc:StreetName>${_xmlEscape(irsaliye['cari_adres']?.toString() ?? '')}</cbc:StreetName>
        <cac:Country><cbc:IdentificationCode>TR</cbc:IdentificationCode></cac:Country>
      </cac:PostalAddress>
    </cac:Party>
  </cac:DeliveryCustomerParty>

  <cac:Shipment>
    <cbc:ID>1</cbc:ID>
    <cbc:HandlingCode>${irsaliye['tip'] == 'Giriş' ? 'GIRIS' : 'CIKIS'}</cbc:HandlingCode>
    <cac:Delivery>
      <cbc:ActualDeliveryDate>${tarihFmt.format(belgeTarihi)}</cbc:ActualDeliveryDate>
    </cac:Delivery>
  </cac:Shipment>
$satirlar
</DespatchAdvice>''';
  }
}
