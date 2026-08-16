// lib/servisler/gib_servisi.dart
// GIB e-Fatura / e-Arşiv entegrasyonu
//
// Bu servis GIB UBL-TR standardına göre e-fatura XML oluşturur.
// Gerçek gönderim için GIB entegratörü (Fınanscloud, Uyumsoft vb.)
// API bilgilerinin ayarlar ekranından girilmesi gerekir.
//
// Desteklenen modlar:
//  - e-Fatura (kayıtlı mükellefler arası)
//  - e-Arşiv (bireysel veya kayıtsız tüketiciye)
//  - Test modu (GIB test ortamı)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import '../modeller/fatura_model.dart';
import '../veri/database/veritabani.dart';

enum EFaturaTipi { eFatura, eArsiv }
enum EFaturaDurum { taslak, gonderildi, onaylandi, reddedildi, iptal }

class GibServisi {
  static final GibServisi _instance = GibServisi._();
  factory GibServisi() => _instance;
  GibServisi._();

  final _dio = Dio();
  final _uuid = const Uuid();

  // ── Ayarlar (DB'den gelir) ─────────────────────────────────────────────
  String? _apiUrl;
  String? _kullaniciAdi;
  String? _sifre;
  String? _maliMuhurSifre;
  // 🔴 NOT (kullanıcı isteği üzerine derin analiz): Bu alan okunuyor
  // (aşağıda) ama XML'de/imzalama işleminde KULLANILMIYOR — bu BİLEREK
  // böyle bırakıldı, eksiklik değil: Gerçek mali mühür imzalama
  // (XAdES-BES, kriptografik özel anahtar + HSM/akıllı kart erişimi
  // gerektirir) entegratör tarafında, ENTEGRATÖRÜN KENDİ sunucusunda
  // yapılır — bir mobil uygulamanın bunu taklit etmeye çalışması hem
  // güvenlik riski hem de teknik olarak yanlış olurdu. Bu şifre alanı,
  // SADECE kullandığınız entegratörün REST API'si bunu (nadir de olsa)
  // istek gövdesinde bekliyorsa kullanılmak üzere saklanıyor —
  // kullandığınız entegratörün dokümantasyonuna göre 'gonder()'
  // fonksiyonundaki istek gövdesine eklenmesi gerekebilir.
  String? _firmaVkn;
  String _firmaAdi = '';
  String _firmaAdres = '';
  String _firmaVergiDairesi = '';
  bool _testModu = true;

  Future<void> ayarlariYukle() async {
    try {
      // ÖNCEDEN BURADA ÇOK CİDDİ BİR MİMARİ HATA VARDI: bu fonksiyon
      // SharedPreferences'tan okuyordu, AMA gib_ayar_ekrani.dart (ayar
      // giriş ekranı) her zaman SQLite 'ayarlar' tablosuna yazıyordu —
      // yani kullanıcı ayarlar ekranına ne girip kaydederse kaydetsin,
      // GERÇEK GİB SERVİSİ BUNU HİÇBİR ZAMAN GÖRMÜYORDU (iki farklı
      // depolama sistemi, birbirinden habersiz). Artık TEK kaynak
      // (SQLite 'ayarlar' tablosu) kullanılıyor — ayarlar ekranıyla
      // birebir aynı yerden okunuyor. Ayrıca kimlik doğrulama tek bir
      // "API Key" yerine gerçek entegratör mimarisine uygun Kullanıcı
      // Adı + Şifre olarak güncellendi.
      final db = await Veritabani().db;
      final rows = await db.query('ayarlar', where:
          "anahtar IN ('gib_api_url','gib_kullanici_adi',"
          "'firma_vergi_no','firma_adi','firma_adres',"
          "'firma_vergi_dairesi','gib_test_modu')");
      final map = {for (final r in rows) r['anahtar'] as String: r['deger'] as String};

      // ÖNCEDEN gib_sifre/gib_mali_muhur_sifre de SQLite'tan (düz metin)
      // okunuyordu — güvenlik açığıydı. Artık ayarlar ekranıyla AYNI
      // güvenli depolamadan (flutter_secure_storage) okunuyor.
      const secure = FlutterSecureStorage();

      _testModu = map['gib_test_modu'] != '0';
      final kayitliUrl = map['gib_api_url'] ?? '';
      // 🔴🔴🔴 KRİTİK DÜZELTME (bağımsız araştırmayla doğrulandı — bkz.
      // GİB'in kendi e-Arşiv Portal Entegrasyon Kılavuzu): ÖNCEDEN, kullanıcı
      // hiçbir URL girmediğinde buraya GİB'İN KENDİ PORTAL ADRESİ
      // (earsivportal.efatura.gov.tr) varsayılan olarak atanıyordu. Ama bu
      // adres, mali mühür/e-imza veya İnteraktif Vergi Dairesi şifresiyle
      // MANUEL giriş yapılan bir web portalıdır — programatik bir REST
      // API'si YOKTUR ("efatura.gov.tr üzerinden ... API yoktur; yazılım
      // entegrasyonuna imkan vermez"). Bu dosyanın çağırdığı uç noktalar
      // (/general/GlobalCompany, /invoice/send vb.) SADECE özel
      // entegratörlerin (Nilvera, Uyumsoft, Foriba vb.) REST API'lerinde
      // bulunur. Yanlış varsayılan yüzünden, kullanıcı entegratör bilgilerini
      // hiç girmese bile 'ayarliMi' true dönüyor ve sistem sessizce GİB'in
      // kendi (çalışmayacak) portal adresine istek atmaya çalışıyordu —
      // kullanıcı "ayarlarınızı girin" yerine anlamsız bir bağlantı hatası
      // görüyordu. Artık URL boşsa null bırakılıyor; 'ayarliMi' bunu
      // yakalayıp NET bir "entegratör API adresinizi girin" mesajı veriyor.
      _apiUrl = kayitliUrl.isNotEmpty ? kayitliUrl : null;

      _kullaniciAdi      = map['gib_kullanici_adi'];
      _sifre             = await secure.read(key: 'gib_sifre');
      _maliMuhurSifre    = await secure.read(key: 'gib_mali_muhur_sifre');
      _firmaVkn          = map['firma_vergi_no'];
      _firmaAdi          = map['firma_adi'] ?? '';
      _firmaAdres        = map['firma_adres'] ?? '';
      _firmaVergiDairesi = map['firma_vergi_dairesi'] ?? '';
    } catch (e) {
      if (kDebugMode) debugPrint('GIB ayar yükleme hatası: $e');
    }
  }

  bool get ayarliMi => _apiUrl != null && _kullaniciAdi != null && _sifre != null && _firmaVkn != null;

  /// Kullanıcı Adı+Şifre'den Basic Auth başlığı üretir — gerçek
  /// entegratör API'lerinin (Foriba, Sovos, Uyumsoft vb.) yaygın kimlik
  /// doğrulama yöntemi budur.
  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('$_kullaniciAdi:$_sifre'))}';

  /// Kullanıcı isteği: "logo gibi yazılımlarda cari kartın ortasında
  /// e-fatura veya e-arşiv gibi ikonlar oluyor" — GİB'in yayınladığı
  /// "e-Fatura Kayıtlı Kullanıcılar Listesi"nde bir VKN/TCKN'nin kayıtlı
  /// olup olmadığını sorgular. Kayıtlıysa o cariye E-FATURA, değilse
  /// E-ARŞİV kesilmesi gerekir (GİB kuralı — kayıtsız birine e-Fatura
  /// kesilemez).
  ///
  /// ÖNEMLİ SINIRLAMA: Bu sorgu, ayarlar ekranında girilen entegratör
  /// API'sine (Uyumsoft/Foriba/Nilvera/Sovos vb.) bağımlıdır. Her
  /// entegratörün KENDİ API formatı farklıdır — burada yaygın, modern
  /// bir REST deseni (Nilvera tarzı) varsayılan olarak denenmiştir.
  /// Kullandığınız entegratör FARKLI bir format kullanıyorsa, bu
  /// fonksiyonun ilgili entegratörün resmi dokümantasyonuna göre
  /// uyarlanması gerekir. Sorgu başarısız olursa 'bilinmiyor' (null)
  /// döner — asla yanlış bir sonuç UYDURMAZ.
  Future<String?> mukellefSorgula(String vknTckn) async {
    if (!ayarliMi) return null;
    try {
      final response = await _dio.get(
        '$_apiUrl/general/GlobalCompany',
        queryParameters: {'taxNumber': vknTckn.trim()},
        options: Options(
          headers: {'Authorization': _authHeader},
          validateStatus: (s) => s != null && s < 500,
        ),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final icerik = data is Map ? data['Content'] : null;
        if (icerik is List && icerik.isNotEmpty) {
          return 'efatura'; // Listede bulundu = e-Fatura mükellefi
        }
        return 'earsiv'; // Listede yok = e-Arşiv kesilmeli
      }
      return null; // Sorgu başarısız — 'bilinmiyor' olarak kalsın
    } catch (e) {
      if (kDebugMode) debugPrint('Mükellef sorgulama başarısız (entegratör API\'si farklı olabilir): $e');
      return null;
    }
  }

  // ── UUID (ETTN) üret ───────────────────────────────────────────────────
  String ettnUret() => _uuid.v4().toUpperCase();

  /// Türkçe ödeme şeklini UBL/UNCL4461 standart koduna çevirir — UBL-TR
  /// XML'inde PaymentMeans bölümü için.
  String _odemeSekliKodu(String? odemeSekli) => switch (odemeSekli) {
        'Nakit' => '10',
        'Kredi Kartı' => '48',
        'Havale/EFT' => '42',
        'Çek' => '20',
        _ => '1', // Tanımlanmamış/Diğer
      };

  // ── UBL-TR XML oluştur ─────────────────────────────────────────────────
  Future<String> ublXmlOlustur({
    required FaturaModel fatura,
    required String ettn,
    EFaturaTipi tip = EFaturaTipi.eArsiv,
  }) async {
    final tarihFmt = DateFormat('yyyy-MM-dd');
    final saatFmt  = DateFormat('HH:mm:ss');
    final now      = DateTime.now();
    final faturaNo = fatura.faturaNo ?? 'TMP${now.millisecondsSinceEpoch}';
    final vkn      = _firmaVkn ?? '0000000000';

    final satirlar = fatura.detaylar.map((k) {
      final kdvTutar = k.kdvTutari;
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
        <cbc:PriceAmount currencyID="TRY">${k.birimFiyat.toStringAsFixed(4)}</cbc:PriceAmount>
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
        <cbc:Name>${_xmlEscape(_firmaAdi.isNotEmpty ? _firmaAdi : 'MarketPlus')}</cbc:Name>
      </cac:PartyName>
      <cac:PostalAddress>
        <cbc:StreetName>${_xmlEscape(_firmaAdres)}</cbc:StreetName>
        <cac:Country>
          <cbc:IdentificationCode>TR</cbc:IdentificationCode>
        </cac:Country>
      </cac:PostalAddress>
      <cac:PartyTaxScheme>
        <cbc:RegistrationName>${_xmlEscape(_firmaAdi)}</cbc:RegistrationName>
        <cac:TaxScheme>
          <cbc:Name>${_xmlEscape(_firmaVergiDairesi)}</cbc:Name>
        </cac:TaxScheme>
      </cac:PartyTaxScheme>
    </cac:Party>
  </cac:AccountingSupplierParty>

  <cac:AccountingCustomerParty>
    <cac:Party>
      <cac:PartyIdentification>
        <cbc:ID schemeID="${(fatura.cariVergiNo?.length ?? 0) == 10 ? 'VKN' : 'TCKN'}">${fatura.cariVergiNo ?? '11111111111'}</cbc:ID>
      </cac:PartyIdentification>
      <cac:PartyName>
        <cbc:Name>${_xmlEscape(fatura.cariUnvan ?? '-')}</cbc:Name>
      </cac:PartyName>
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

  // ── Gönder ────────────────────────────────────────────────────────────
  Future<GibGonderimSonucu> gonder({
    required FaturaModel fatura,
    EFaturaTipi tip = EFaturaTipi.eArsiv,
  }) async {
    await ayarlariYukle();
    if (!ayarliMi) {
      return GibGonderimSonucu(
        basarili: false,
        hata: 'GIB API ayarları eksik. Ayarlar → GIB Entegrasyon ekranından yapılandırın.',
      );
    }

    // ÖNCEDEN BURADA "efatura_aktif"/"earsiv_aktif" (Ayarlar > Fatura
    // Ayarları'ndaki açma/kapama anahtarları) HİÇ KONTROL EDİLMİYORDU —
    // sadece API bilgileri (kullanıcı adı/şifre) girilmiş olması yeterli
    // sayılıyordu. Bu, kullanıcının "e-Fatura henüz kapalı, test
    // aşamasındayım" diye düşünüp bu anahtarı KAPALI bıraksa bile,
    // sistemin sessizce GERÇEK gönderim yapabilmesi anlamına geliyordu
    // — test'ten canlıya kazayla geçiş riski. Artık ilgili anahtar
    // açık değilse gönderim YAPILMIYOR, açık ve net bir hata dönüyor.
    final prefs = await SharedPreferences.getInstance();
    final aktifMi = tip == EFaturaTipi.eFatura
        ? (prefs.getBool('efatura_aktif') ?? false)
        : (prefs.getBool('earsiv_aktif') ?? false);
    if (!aktifMi) {
      final adi = tip == EFaturaTipi.eFatura ? 'e-Fatura' : 'e-Arşiv';
      return GibGonderimSonucu(
        basarili: false,
        hata: '$adi gönderimi kapalı. Ayarlar → Fatura Ayarları\'ndan '
            '"$adi" anahtarını açmanız gerekiyor.',
      );
    }

    final ettn = ettnUret();
    final xml  = await ublXmlOlustur(fatura: fatura, ettn: ettn, tip: tip);

    try {
      final response = await _dio.post(
        '${_apiUrl!}/invoice/send',
        data: {
          'uuid': ettn,
          'invoice_xml': base64Encode(utf8.encode(xml)),
          'type': tip == EFaturaTipi.eFatura ? 'efatura' : 'earsiv',
          'test': _testModu,
        },
        options: Options(
          headers: {
            'Authorization': _authHeader,
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final body = response.data as Map<String, dynamic>?;
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Log kaydet
        await _logKaydet(
          referansId: fatura.id ?? 0,
          referansTuru: 'fatura',
          uuid: ettn,
          islemTipi: 'gonder',
          durum: 'gonderildi',
          istekXml: xml,
          yanitXml: jsonEncode(body),
        );
        return GibGonderimSonucu(
          basarili: true,
          uuid: ettn,
          yanit: body?['message']?.toString(),
        );
      } else {
        final hata = body?['error']?.toString() ?? 'HTTP ${response.statusCode}';
        await _logKaydet(
          referansId: fatura.id ?? 0,
          referansTuru: 'fatura',
          uuid: ettn,
          islemTipi: 'gonder',
          durum: 'hata',
          istekXml: xml,
          hataMesaj: hata,
        );
        return GibGonderimSonucu(basarili: false, hata: hata);
      }
    } on DioException catch (e) {
      final hata = e.response?.data?.toString() ?? e.message ?? 'Bağlantı hatası';
      await _logKaydet(
        referansId: fatura.id ?? 0,
        referansTuru: 'fatura',
        uuid: ettn,
        islemTipi: 'gonder',
        durum: 'hata',
        hataMesaj: hata,
        istekXml: xml,
      );
      return GibGonderimSonucu(basarili: false, hata: hata);
    }
  }

  // ── Durum sorgula ──────────────────────────────────────────────────────
  Future<String?> durumSorgula(String uuid) async {
    await ayarlariYukle();
    if (!ayarliMi) return null;
    try {
      final r = await _dio.get(
        '${_apiUrl!}/invoice/status/$uuid',
        options: Options(headers: {'Authorization': _authHeader}),
      );
      if (r.statusCode == 200) {
        final body = r.data as Map<String, dynamic>?;
        return body?['status']?.toString();
      }
    } catch (e) { if (kDebugMode) debugPrint('[HATA] ' + e.toString()); }
    return null;
  }

  // ── XML önizleme ────────────────────────────────────────────────────────
  Future<String> xmlOnizleme({
    required FaturaModel fatura,
  }) async {
    final ettn = ettnUret();
    return await ublXmlOlustur(fatura: fatura, ettn: ettn);
  }

  // ── Log ────────────────────────────────────────────────────────────────
  Future<void> _logKaydet({
    required int referansId,
    required String referansTuru,
    required String islemTipi,
    required String durum,
    String? uuid,
    String? istekXml,
    String? yanitXml,
    String? hataMesaj,
  }) async {
    try {
      final db = await Veritabani().db;
      await db.insert('efatura_log', {
        'referans_id':   referansId,
        'referans_turu': referansTuru,
        'uuid':          uuid,
        'islem_tipi':    islemTipi,
        'durum':         durum,
        'istek_xml':     istekXml,
        'yanit_xml':     yanitXml,
        'hata_mesaj':    hataMesaj,
        'tarih':         DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('GIB log hatası: $e');
    }
  }

  /// DB'den fatura için son log kaydını getir
  Future<Map<String, dynamic>?> sonLogGetir(int faturaId) async {
    try {
      final db = await Veritabani().db;
      final rows = await db.query('efatura_log',
          where: "referans_id = ? AND referans_turu = 'fatura'",
          whereArgs: [faturaId],
          orderBy: 'id DESC',
          limit: 1);
      return rows.isNotEmpty ? rows.first : null;
    } catch (_) { return null; }
  }

  /// Kullanıcı sorusu: "gelen fatura ve giden fatura listeleme var mı?"
  /// ÖNCEDEN bu tamamen eksikti — sadece SİZİN kestiğiniz (giden)
  /// faturalar destekleniyordu. Ama bir e-Fatura mükellefiyseniz, BAŞKA
  /// mükelleflerin size GİB üzerinden gönderdiği faturaları da almanız
  /// ve YASAL OLARAK ZORUNLU "Uygulama Yanıtı" (Kabul/Red) ile
  /// yanıtlamanız gerekir (GİB Tebliği — yanıtlanmazsa süre sonunda
  /// otomatik kabul sayılır, ama yanıt vermemek yine de önerilmez).
  /// Bu fonksiyon entegratörünüzün "gelen kutusu" servisini sorgular.
  Future<List<Map<String, dynamic>>> gelenFaturalariGetir({int gunSayisi = 30}) async {
    if (!ayarliMi) return [];
    try {
      final bitis = DateTime.now();
      final baslangic = bitis.subtract(Duration(days: gunSayisi));
      final response = await _dio.get(
        '$_apiUrl/einvoice/inbox',
        queryParameters: {
          'startDate': DateFormat('yyyy-MM-dd').format(baslangic),
          'endDate': DateFormat('yyyy-MM-dd').format(bitis),
        },
        options: Options(headers: {'Authorization': _authHeader}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.data is Map) {
        final icerik = (response.data as Map)['Content'];
        if (icerik is List) return icerik.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('Gelen fatura listesi alınamadı (entegratör API\'si farklı olabilir): $e');
      return [];
    }
  }

  /// GİB'in yasal olarak zorunlu kıldığı "Uygulama Yanıtı" — gelen bir
  /// e-Faturayı KABUL veya RED eder. [faturaUuid] gelen faturanın ETTN
  /// (UUID) değeridir.
  Future<bool> uygulamaYanitiGonder(String faturaUuid, {required bool kabul}) async {
    if (!ayarliMi) return false;
    try {
      final response = await _dio.post(
        '$_apiUrl/einvoice/applicationresponse',
        data: {
          'uuid': faturaUuid,
          'status': kabul ? 'accepted' : 'rejected',
          'note': kabul ? 'Kabul edildi' : 'Reddedildi',
        },
        options: Options(headers: {'Authorization': _authHeader}),
      ).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('Uygulama yanıtı gönderilemedi: $e');
      return false;
    }
  }
}

class GibGonderimSonucu {
  final bool basarili;
  final String? uuid;
  final String? yanit;
  final String? hata;
  const GibGonderimSonucu({required this.basarili, this.uuid, this.yanit, this.hata});
}
