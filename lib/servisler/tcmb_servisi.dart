// lib/servisler/tcmb_servisi.dart
//
// Kullanıcı isteği: "çoklu para birimini merkez bankasından gelsin...
// profesyonel programlar böyle çalışıyor" — TCMB'nin resmi, ücretsiz,
// kimlik doğrulama gerektirmeyen döviz kuru XML servisinden gerçek
// kurları çeker. Format, TCMB'nin yıllardır değişmeyen standart
// yapısıdır: https://www.tcmb.gov.tr/kurlar/today.xml
//
// XML yapısı (TCMB resmi):
// <Tarih_Date Tarih="04.07.2026" ...>
//   <Currency Kod="USD" CurrencyCode="USD">
//     <Unit>1</Unit>
//     <Isim>ABD DOLARI</Isim>
//     <CurrencyName>US DOLLAR</CurrencyName>
//     <ForexBuying>46.1932</ForexBuying>
//     <ForexSelling>46.2765</ForexSelling>
//     <BanknoteBuying>46.1609</BanknoteBuying>
//     <BanknoteSelling>46.3459</BanknoteSelling>
//   </Currency>
//   ...
// </Tarih_Date>
//
// Profesyonel muhasebe/ERP programları (Logo, Mikro vb.) fatura/ürün
// fiyatlandırmasında genellikle "Döviz Alış/Satış" (Forex) kurunu
// kullanır — "Efektif" (Banknote) kurlar fiziksel nakit değişimi
// içindir, market/ticari muhasebe için Forex kurları esastır.
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart' as xml;
import 'package:flutter/foundation.dart';

class TcmbDovizSonuc {
  final String kod;          // 'USD'
  final String ad;           // 'ABD DOLARI'
  final String ingilizceAd;  // 'US DOLLAR'
  final int birim;           // Unit — bazı para birimleri (JPY gibi) 100 birim üzerinden yayınlanır
  final double forexAlis;
  final double forexSatis;
  final double efektifAlis;
  final double efektifSatis;

  const TcmbDovizSonuc({
    required this.kod,
    required this.ad,
    required this.ingilizceAd,
    required this.birim,
    required this.forexAlis,
    required this.forexSatis,
    required this.efektifAlis,
    required this.efektifSatis,
  });

  /// Birim > 1 olan para birimlerinde (ör. JPY 100 birim üzerinden
  /// yayınlanır) TEK birim karşılığını verir — ürün fiyatlandırmasında
  /// kullanılacak gerçek çarpan budur.
  double get birimForexSatis => birim > 0 ? forexSatis / birim : forexSatis;
  double get birimForexAlis  => birim > 0 ? forexAlis / birim : forexAlis;
}

class TcmbServisi {
  static final TcmbServisi _instance = TcmbServisi._();
  factory TcmbServisi() => _instance;
  TcmbServisi._();

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 12),
  ));

  /// TCMB'nin güncel gün kur listesini çeker. Hafta sonu/resmi tatilde
  /// TCMB yayın yapmaz — bu durumda bir önceki iş gününün kurları
  /// döner (TCMB'nin kendi davranışı, bizim tarafımızda ek mantık
  /// gerekmez, today.xml zaten en son yayınlanan kuru verir).
  Future<List<TcmbDovizSonuc>> guncelKurlariGetir() async {
    try {
      final response = await _dio.get<List<int>>(
        'https://www.tcmb.gov.tr/kurlar/today.xml',
        options: Options(responseType: ResponseType.bytes),
      );
      final xmlMetni = utf8.decode(response.data!, allowMalformed: true);
      return _xmlAyristir(xmlMetni);
    } catch (e) {
      if (kDebugMode) debugPrint('TCMB kur çekme hatası: $e');
      rethrow;
    }
  }

  List<TcmbDovizSonuc> _xmlAyristir(String xmlMetni) {
    final doc = xml.XmlDocument.parse(xmlMetni);
    final sonuclar = <TcmbDovizSonuc>[];

    for (final node in doc.findAllElements('Currency')) {
      final kod = node.getAttribute('Kod') ?? node.getAttribute('CurrencyCode') ?? '';
      if (kod.isEmpty) continue;

      String metin(String etiket) {
        final elemanlar = node.findElements(etiket);
        return elemanlar.isEmpty ? '' : elemanlar.first.innerText.trim();
      }
      double sayi(String etiket) =>
          double.tryParse(metin(etiket).replaceAll(',', '.')) ?? 0;

      // Bazı satırlarda (ör. gösterge niteliğindeki çapraz kurlar) Forex
      // değerleri boş olabilir — bu durumda o para birimini atla, yarım/
      // yanlış veriyle devam etme.
      final forexSatis = sayi('ForexSelling');
      if (forexSatis <= 0) continue;

      sonuclar.add(TcmbDovizSonuc(
        kod: kod,
        ad: metin('Isim'),
        ingilizceAd: metin('CurrencyName'),
        birim: int.tryParse(metin('Unit')) ?? 1,
        forexAlis: sayi('ForexBuying'),
        forexSatis: forexSatis,
        efektifAlis: sayi('BanknoteBuying'),
        efektifSatis: sayi('BanknoteSelling'),
      ));
    }
    return sonuclar;
  }
}
