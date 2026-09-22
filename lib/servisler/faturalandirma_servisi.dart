// lib/servisler/faturalandirma_servisi.dart
// SRP: Satış/İade fişlerinden fatura oluşturma sürecinin TEK ortak noktası.
//   - Cari'nin GİB için zorunlu alanlarını doğrular (ünvan, VKN/TC, vergi
//     dairesi, adres/il/ilçe).
//   - "Fatura No Ön Eki" ve "Varsayılan İskonto" ayarlarını uygular.
//   - FaturaModel + FaturaDetayModel kayıtlarını oluşturup kaydeder.
//
// satis_detay_ekrani ve iade_ekrani buradan tek bir API çağırır; ekranlar
// sadece kullanıcı etkileşimi ve kalem listesi hazırlamakla sorumludur.

import 'package:shared_preferences/shared_preferences.dart';
import '../depolar/cari_deposu.dart';
import '../depolar/fatura_deposu.dart';
import '../modeller/cari_model.dart';
import '../modeller/fatura_model.dart';
import '../veri/database/veritabani.dart';
import '../cekirdek/utils/vergi_no_dogrulayici.dart';

/// Cari'nin faturalandırma için hazır olup olmadığının sonucu.
class CariFaturaKontrolu {
  final CariModel cari;
  final String? adresMetni;
  final List<String> eksikAlanlar;
  bool get hazir => eksikAlanlar.isEmpty;

  const CariFaturaKontrolu({
    required this.cari,
    required this.adresMetni,
    required this.eksikAlanlar,
  });
}

class FaturalandirmaServisi {
  /// Cari kaydını ve `cari_adres` tablosundaki varsayılan adresi okuyup
  /// GİB için zorunlu alanları (Ünvan, VKN/TC, Vergi Dairesi, Adres/İl/İlçe)
  /// kontrol eder.
  static Future<CariFaturaKontrolu?> kontrolEt(int cariId) async {
    final cari = await CariDeposu().idileGetir(cariId);
    if (cari == null) return null;

    final db = await Veritabani().db;
    final adresRows = await db.query('cari_adres',
        where: 'cari_id = ?', whereArgs: [cariId],
        orderBy: 'varsayilan DESC', limit: 1);

    String? adresMetni;
    if (adresRows.isNotEmpty) {
      final a = adresRows.first;
      final adres = (a['adres'] as String?)?.trim() ?? '';
      final ilce  = (a['ilce']  as String?)?.trim() ?? '';
      final il    = (a['il']    as String?)?.trim() ?? '';
      final parcalar = <String>[];
      if (adres.isNotEmpty) parcalar.add(adres);
      // "İLÇE / İL - TR" — referans BarkoPOS formatına benzer
      if (ilce.isNotEmpty || il.isNotEmpty) {
        final ilceIl = [ilce, il].where((x) => x.isNotEmpty).join(' / ');
        parcalar.add('$ilceIl - TR');
      }
      if (parcalar.isNotEmpty) adresMetni = parcalar.join(' ');
    }

    final eksikler = <String>[];
    if (cari.unvan.trim().isEmpty) eksikler.add('Ünvan');
    // 🔴 Derin denetimde bulundu (P2): VKN/TC Kimlik No'nun sadece BOŞ
    // olup olmadığı kontrol ediliyordu, format/checksum'ı hiç
    // doğrulanmıyordu — hatalı (typo'lu) bir VKN GİB'e kadar gidip
    // reddedilebilirdi. VergiNoDogrulayici (tam checksum algoritması,
    // gib_ayar_ekrani.dart'ta şirketin kendi VKN'si için zaten
    // kullanılıyor) burada da uygulandı.
    final vergiNo = cari.vergiNo?.trim();
    final tcKimlik = cari.tcKimlik?.trim();
    if ((vergiNo == null || vergiNo.isEmpty) &&
        (tcKimlik == null || tcKimlik.isEmpty)) {
      eksikler.add('VKN veya TC Kimlik No');
    } else {
      final girilen = (vergiNo != null && vergiNo.isNotEmpty) ? vergiNo : tcKimlik!;
      if (!VergiNoDogrulayici.gecerliMi(girilen)) {
        eksikler.add('Geçerli bir VKN (10 hane) veya TC Kimlik No (11 hane) — rakamları kontrol edin');
      }
    }
    if (cari.vergiDairesi == null || cari.vergiDairesi!.isEmpty) {
      eksikler.add('Vergi Dairesi');
    }
    if (adresMetni == null || adresMetni.isEmpty) {
      eksikler.add('Adres / İl / İlçe');
    }

    return CariFaturaKontrolu(cari: cari, adresMetni: adresMetni, eksikAlanlar: eksikler);
  }

  /// Bu satış/iade için DAHA ÖNCE oluşturulmuş (iptal edilmemiş) bir fatura
  /// var mı? Varsa o faturanın id'sini döndürür — mükerrer fatura/numara
  /// üretimini önlemek için her faturalandırma akışının başında çağrılmalı.
  static Future<int?> mevcutFaturaId({int? satisId, int? iadeId}) async {
    if (satisId == null && iadeId == null) return null;
    final db = await Veritabani().db;
    final where = <String>["durum != 'iptal'"];
    final args = <Object?>[];
    if (satisId != null) { where.add('satis_id = ?'); args.add(satisId); }
    if (iadeId != null)  { where.add('iade_id = ?');  args.add(iadeId); }
    final rows = await db.query('faturalar',
        columns: ['id'], where: where.join(' AND '), whereArgs: args, limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  /// Ayarlardaki "Fatura No Ön Eki" + yıl + sıra no'dan yeni bir fatura
  /// numarası üretir. Ön ek boşsa varsayılan "FTR" kullanılır.
  /// Örnek: HLF2026000000007
  ///
  /// 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu fonksiyon önceden
  /// COUNT(*) tabanlıydı ("kaç fatura var, bir sonraki = başlangıç +
  /// sayı") — ama FaturaDeposu.siradakiFaturaNoUret() (aynı işi yapan,
  /// AYRI bir fonksiyon) MAX+1 (en yüksek mevcut numarayı bul, 1 ekle)
  /// tabanlıydı. Bu iki FARKLI algoritma aynı fatura_no dizisini
  /// paylaştığı için, bir fatura iptal/silinirse COUNT azalır ama
  /// MAX değişmez — bu durumda COUNT tabanlı yöntem, MAX tabanlı
  /// yöntemin ÜRETTİĞİ bir numarayla ÇAKIŞAN bir numara üretebilirdi
  /// (aynı fatura_no'ya sahip 2 fatura — resmi/yasal açıdan ciddi bir
  /// sorun). Artık her iki yol da AYNI (MAX+1) algoritmayı kullanıyor.
  static Future<String> sonrakiFaturaNo(DateTime tarih) async {
    final prefs = await SharedPreferences.getInstance();
    var onek = (prefs.getString('fatura_no_onek') ?? '').trim().toUpperCase();
    if (onek.isEmpty) onek = 'FTR';

    final yil = tarih.year;
    final db  = await Veritabani().db;
    final tamOnek = '$onek$yil';
    final rows = await db.rawQuery(
      'SELECT fatura_no FROM faturalar WHERE fatura_no LIKE ? ORDER BY fatura_no DESC LIMIT 1',
      ['$tamOnek%'],
    );
    final baslangic = int.tryParse(prefs.getString('fatura_baslangic_no') ?? '1') ?? 1;
    var sira = baslangic;
    if (rows.isNotEmpty) {
      final mevcut = rows.first['fatura_no'] as String?;
      if (mevcut != null && mevcut.length >= tamOnek.length + 9) {
        final siraStr = mevcut.substring(tamOnek.length, tamOnek.length + 9);
        final mevcutSira = int.tryParse(siraStr);
        if (mevcutSira != null) sira = mevcutSira + 1;
      }
    }
    return '$onek$yil${sira.toString().padLeft(9, '0')}';
  }

  /// Ayarlardaki "Varsayılan İskonto %" değerini döndürür (yoksa 0).
  static Future<double> varsayilanIskontoOrani() async {
    final prefs = await SharedPreferences.getInstance();
    return double.tryParse(prefs.getString('fatura_varsayilan_iskonto') ?? '0') ?? 0;
  }

  /// Kalem listesinden FaturaModel oluşturup kaydeder.
  /// - `satisId` ve `iadeId`'den sadece biri verilmelidir.
  /// - Eğer kalemlerin hiçbirinde iskonto yoksa ve ayarda varsayılan
  ///   iskonto > 0 ise, bu oran tüm kalemlere uygulanır.
  static Future<int> faturaOlustur({
    required CariFaturaKontrolu kontrol,
    required List<FaturaDetayModel> kalemler,
    required String faturaTipi, // 'Satış', 'İade'
    int? satisId,
    int? iadeId,
    required DateTime tarih,
    double odenenTutar = 0,
  }) async {
    final cari = kontrol.cari;
    final varsayilanIskonto = await varsayilanIskontoOrani();

    // Hiçbir kalemde iskonto yoksa ve ayarda varsayılan iskonto tanımlıysa uygula.
    var islenmisKalemler = kalemler;
    final hicIskontoYok = kalemler.every((k) => k.iskontoOrani == 0 && k.iskontoTutari == 0);
    if (hicIskontoYok && varsayilanIskonto > 0) {
      islenmisKalemler = kalemler.map((k) {
        final iskontoTutar = k.araToplam * varsayilanIskonto / 100;
        final netTutar = k.araToplam - iskontoTutar;
        final kdvTutar = netTutar * k.kdvOrani / 100;
        return FaturaDetayModel(
          urunId: k.urunId, urunAdi: k.urunAdi, barkod: k.barkod,
          miktar: k.miktar, birimFiyat: k.birimFiyat,
          iskontoOrani: varsayilanIskonto, iskontoTutari: iskontoTutar,
          kdvOrani: k.kdvOrani, kdvTutari: kdvTutar,
          // 🔴 DÜZELTME (kritik — derin denetimde bulundu): araToplam burada
          // YANLIŞLIKLA indirim UYGULANMADAN ÖNCEKİ (k.araToplam) değere
          // eşitleniyordu — codebase'in her yerinde geçerli olan
          // "araToplam = toplamTutar - kdvTutari" (Madde 21) kuralını bu
          // TEK dalda bozuyordu. Sonuç: bu dalın ürettiği faturalarda
          // basılan "Vergiler Hariç Toplam" indirimi İKİ KEZ düşüyordu
          // (bkz. fatura_detay_pdf_ext.dart'taki aynı düzeltme).
          araToplam: netTutar, toplamTutar: netTutar + kdvTutar,
        );
      }).toList();
    }

    final toplamAraToplam = islenmisKalemler.fold<double>(0, (t, d) => t + d.araToplam);
    final toplamIskonto   = islenmisKalemler.fold<double>(0, (t, d) => t + d.iskontoTutari);
    final toplamKdv       = islenmisKalemler.fold<double>(0, (t, d) => t + d.kdvTutari);
    final genelToplam     = islenmisKalemler.fold<double>(0, (t, d) => t + d.toplamTutar);

    final faturaNo = await sonrakiFaturaNo(tarih);

    final fatura = FaturaModel(
      faturaNo: faturaNo,
      faturaTipi: faturaTipi,
      satisId: satisId,
      iadeId: iadeId,
      cariId: cari.id,
      cariUnvan: cari.unvan,
      cariVergiNo: (cari.vergiNo?.isNotEmpty ?? false) ? cari.vergiNo : cari.tcKimlik,
      cariVergiDairesi: cari.vergiDairesi,
      // 🔴 DÜZELTME (derin analizde bulundu): GİB'de sorgulanmış
      // mükellefiyet durumu (cari.mukellefDurumu) buraya HİÇ
      // kaydedilmiyordu — bu alan tam bunun için tasarlanmıştı
      // (bkz. FaturaModel.cariMukellefDurumu yorumu) ama boş kalıyordu.
      // Faturanın OLUŞTURULDUĞU ANDAKİ mükellefiyet durumunu
      // kaydediyoruz (müşterinin durumu SONRADAN değişse bile, o
      // faturanın kesildiği andaki gerçeği yansıtması doğrudur).
      cariMukellefDurumu: cari.mukellefDurumu,
      cariAdres: kontrol.adresMetni,
      tarih: tarih,
      duzenlenmeTarihi: DateTime.now(),
      toplamAraToplam: toplamAraToplam,
      toplamIskonto: toplamIskonto,
      toplamKdv: toplamKdv,
      genelToplam: genelToplam,
      odenenTutar: odenenTutar,
      kalanTutar: (genelToplam - odenenTutar).clamp(0, double.infinity),
      odemeDurumu: odenenTutar >= genelToplam ? 'odendi' : 'beklemede',
    );

    return FaturaDeposu().ekle(fatura, islenmisKalemler);
  }
}
