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
//
// (Madde 2 mimari denetimi — 2026-09-20: bu dosya 1045 satırlık tek bir
// "god-service" idi — ayar yükleme, XML üretimi, loglama ve gönderim
// orkestrasyonu hepsi burada birleşmişti. Tek sorumluluk prensibine göre
// üç alt parçaya bölündü:
//   servisler/gib/gib_ayar_yoneticisi.dart  — ayar yükleme/taşıma
//   servisler/gib/gib_ubl_olusturucu.dart   — UBL-TR XML üretimi
//   depolar/efatura_log_deposu.dart         — efatura_log tablosu
// GibServisi artık sadece bunları orkestre eden bir CEPHE (facade):
// dosyanın geri kalanındaki HİÇBİR ekran/test bunu bilmiyor — GibServisi()
// public API'si (metod adı/imzası/davranışı) BİREBİR AYNI kaldı, sadece
// gövdeler alt servislere delege ediyor. DAVRANIŞ DEĞİŞMEDİ.)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import '../modeller/fatura_model.dart';
import 'gib/gib_ayar_yoneticisi.dart';
import 'gib/gib_ubl_olusturucu.dart';
import '../depolar/efatura_log_deposu.dart';

export 'gib/gib_tipleri.dart';
import 'gib/gib_tipleri.dart';

class GibServisi {
  static final GibServisi _instance = GibServisi._();
  factory GibServisi() => _instance;
  GibServisi._();

  final _dio = Dio();
  final _uuid = const Uuid();

  final GibAyarYoneticisi _ayar = GibAyarYoneticisi();
  late final GibUblOlusturucu _ubl = GibUblOlusturucu(_ayar);
  final EfaturaLogDeposu _log = EfaturaLogDeposu();

  Future<void> ayarlariYukle() => _ayar.yukle();

  bool get ayarliMi => _ayar.ayarliMi;

  String get _authHeader => _ayar.authHeader;

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
        '${_ayar.apiUrl}/general/GlobalCompany',
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

  // 🔴 Derin analizde bulundu (mükerrer e-belge gönderim riski): gonder()
  // her çağrıda ettnUret() ile TAMAMEN YENİ, rastgele bir ETTN
  // üretiyordu. İstek entegratöre ULAŞTIKTAN SONRA bağlantı koparsa
  // (istemci başarı yanıtını hiç görmez), kullanıcının "Gönder"e tekrar
  // basması FARKLI bir ETTN ile ayrı, yasal bağlayıcılığı olan bir
  // e-belge gönderimi daha yapıyordu — entegratörün bunu aynı faturanın
  // tekrar denemesi olarak tanıyabileceği hiçbir ortak kimlik yoktu.
  // Bu sabit (namespace UUID'si sadece bir tuz, herhangi bir dış anlamı
  // yok) ile UUID v5 (isim tabanlı, DETERMİNİSTİK) üretimi kullanılıyor:
  // aynı fatura (global_id) için HER ZAMAN aynı ETTN üretilir — uygulama
  // yeniden başlatılsa, farklı bir cihazdan denense bile. Böylece bir
  // entegratör ETTN'ye göre tekilleştirme yapıyorsa mükerrer gönderim
  // artık otomatik olarak engellenir; yapmıyorsa bile durum kötüleşmez.
  static const String _ettnNamespace = '2f6a8c1e-4b3d-4e7a-9c2f-1a5b7d9e3c6f';

  // 🔴 GÜNCELLEME (e-Belge durum makinesi genişletmesi): eğer fatura DAHA
  // ÖNCE GİB tarafından REDDEDİLDİYSE, kullanıcı düzeltip yeniden
  // gönderdiğinde deneme_no artık > 0 olur (bkz. FaturaDeposu.
  // yenidenGondermeyeHazirla) — bu, aynı fatura için AYNI ETTN'nin
  // reddedilmiş bir belgeye yeniden atanmasını önler. deneme_no=0 (ilk
  // gönderim VEYA GİB'e hiç ulaşmamış bir ağ hatası sonrası tekrar
  // deneme) için davranış TAMAMEN ESKİSİYLE AYNI — mevcut mükerrer
  // gönderim koruması bozulmuyor.
  String _ettnUret2(String ad, int denemeNo) {
    final anahtar = denemeNo > 0 ? '$ad#$denemeNo' : ad;
    return _uuid.v5(_ettnNamespace, anahtar).toUpperCase();
  }

  String _ettnFaturaIcin(FaturaModel fatura) {
    final ad = fatura.globalId ?? fatura.faturaNo ?? fatura.id?.toString() ??
        DateTime.now().toIso8601String();
    return _ettnUret2(ad, fatura.eFaturaDenemeNo);
  }

  /// Madde 23 (Fatura/E-Belge) denetimi, 2026-09-20: `_ettnFaturaIcin`nin
  /// PUBLIC sarmalayıcısı. Bir fatura 'gonderiliyor' durumundayken
  /// (gönderim isteği GİB'e yollandı ama yanıt uygulama tarafında hiç
  /// işlenemedi — ör. gönderim sırasında uygulama çöktü) `eFaturaUuid`
  /// hâlâ null'dır (bkz. eFaturaDurumGuncelle(..., 'gonderiliyor')
  /// çağrısının UUID'siz yapılması, fatura_detay_ekrani.dart). Ama ETTN
  /// DETERMİNİSTİK olduğundan (bkz. _ettnUret2 — aynı fatura+deneme_no
  /// HER ZAMAN aynı ETTN'i üretir), durum sorgulamak için hiç saklanmış
  /// bir UUID'ye ihtiyaç YOK — burada yeniden hesaplanabilir.
  String ettnHesapla(FaturaModel fatura) => _ettnFaturaIcin(fatura);

  // ── UBL-TR XML oluştur ─────────────────────────────────────────────────
  Future<String> ublXmlOlustur({
    required FaturaModel fatura,
    required String ettn,
    EFaturaTipi tip = EFaturaTipi.eArsiv,
  }) => _ubl.ublXmlOlustur(fatura: fatura, ettn: ettn, tip: tip);

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

    final ettn = _ettnFaturaIcin(fatura);
    final xml  = await ublXmlOlustur(fatura: fatura, ettn: ettn, tip: tip);

    try {
      final response = await _dio.post(
        '${_ayar.apiUrl!}/invoice/send',
        data: {
          'uuid': ettn,
          'invoice_xml': base64Encode(utf8.encode(xml)),
          'type': tip == EFaturaTipi.eFatura ? 'efatura' : 'earsiv',
          'test': _ayar.testModu,
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
        await _log.kaydet(
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
        await _log.kaydet(
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
      await _log.kaydet(
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

  /// [irsaliye] en az şu anahtarları içermeli: id, irsaliye_no, tarih, tip
  /// ('Çıkış'/'Giriş'), cari_adi, cari_vergi_no, cari_vergi_dairesi,
  /// cari_adres (hepsi opsiyonel/null olabilir — eksikse XML'de '-' yazılır,
  /// gönderim ENGELLENMEZ). [kalemler]'in her biri: urun_adi, miktar,
  /// (opsiyonel) birim_fiyat.
  Future<String> ublDespatchAdviceOlustur({
    required Map<String, dynamic> irsaliye,
    required List<Map<String, dynamic>> kalemler,
    required String ettn,
  }) => _ubl.ublDespatchAdviceOlustur(irsaliye: irsaliye, kalemler: kalemler, ettn: ettn);

  /// e-İrsaliyeyi GİB'e gönderir — mimari olarak [gonder]'ın (e-Fatura)
  /// birebir aynısı (ayarlar/aktiflik kontrolü, ETTN, log) ama Invoice
  /// yerine DespatchAdvice XML'i kullanır.
  Future<GibGonderimSonucu> irsaliyeGonder({
    required Map<String, dynamic> irsaliye,
    required List<Map<String, dynamic>> kalemler,
  }) async {
    await ayarlariYukle();
    if (!ayarliMi) {
      return GibGonderimSonucu(
        basarili: false,
        hata: 'GIB API ayarları eksik. Ayarlar → GİB Entegrasyon ekranından yapılandırın.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('eirsaliye_aktif') ?? false)) {
      return GibGonderimSonucu(
        basarili: false,
        hata: 'e-İrsaliye gönderimi kapalı. Ayarlar → Fatura Ayarları\'ndan '
            '"e-İrsaliye Aktif" anahtarını açmanız gerekiyor.',
      );
    }

    final irsaliyeId = irsaliye['id'] as int? ?? 0;
    final globalId = irsaliye['global_id']?.toString() ?? irsaliye['irsaliye_no']?.toString() ?? 'irsaliye-$irsaliyeId';
    final denemeNo = (irsaliye['e_irsaliye_deneme_no'] as int?) ?? 0;
    final ettn = _ettnUret2(globalId, denemeNo);
    final xml = await ublDespatchAdviceOlustur(irsaliye: irsaliye, kalemler: kalemler, ettn: ettn);

    try {
      final response = await _dio.post(
        '${_ayar.apiUrl!}/despatch/send',
        data: {
          'uuid': ettn,
          'despatch_xml': base64Encode(utf8.encode(xml)),
          'type': 'despatch',
          'test': _ayar.testModu,
        },
        options: Options(
          headers: {'Authorization': _authHeader, 'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final body = response.data as Map<String, dynamic>?;
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _log.kaydet(
          referansId: irsaliyeId, referansTuru: 'irsaliye', uuid: ettn,
          islemTipi: 'gonder', durum: 'gonderildi', istekXml: xml, yanitXml: jsonEncode(body),
        );
        return GibGonderimSonucu(basarili: true, uuid: ettn, yanit: body?['message']?.toString());
      } else {
        final hata = body?['error']?.toString() ?? 'HTTP ${response.statusCode}';
        await _log.kaydet(
          referansId: irsaliyeId, referansTuru: 'irsaliye', uuid: ettn,
          islemTipi: 'gonder', durum: 'hata', istekXml: xml, hataMesaj: hata,
        );
        return GibGonderimSonucu(basarili: false, hata: hata);
      }
    } on DioException catch (e) {
      final hata = e.response?.data?.toString() ?? e.message ?? 'Bağlantı hatası';
      await _log.kaydet(
        referansId: irsaliyeId, referansTuru: 'irsaliye', uuid: ettn,
        islemTipi: 'gonder', durum: 'hata', hataMesaj: hata, istekXml: xml,
      );
      return GibGonderimSonucu(basarili: false, hata: hata);
    }
  }

  // ── Durum sorgula ──────────────────────────────────────────────────────
  // 🔴 DÜZELTME (e-Belge durum makinesi genişletmesi, derin analiz
  // bulgusu): ÖNCEDEN entegratörden gelen ham 'status' string'i AYNEN
  // döndürülüyordu — çağıran taraf (fatura_liste/detay_ekrani.dart)
  // sadece 'onaylandi' değerini tanıyordu, başka HER ŞEY (özellikle GİB
  // gerçekten REDDETMİŞSE dönen 'rejected'/'reddedildi' gibi bir değer)
  // sessizce "Beklemede" (turuncu, hiçbir şey olmamış gibi) gösteriliyordu.
  // Yasal geçerliliği OLMAYAN reddedilmiş bir fatura, hâlâ "gönderim
  // bekliyor" gibi görünüyordu — bu ciddi bir risktir. Artık yaygın
  // entegratör terimleri kendi iç durum kelime dağarcığımıza (onaylandi/
  // reddedildi/gib_iptal) NORMALLEŞTİRİLİYOR. Hangi entegratörün TAM
  // OLARAK hangi string'i döndürdüğü burada doğrulanamadı (bkz. dosya
  // başındaki genel uyarı) — tanınmayan bir değer gelirse ham hâliyle
  // döndürülüyor (en azından teşhis edilebilir kalır, sessizce yutulmuyor).
  String? _durumNormallestir(String? ham) {
    if (ham == null) return null;
    final h = ham.trim().toLowerCase();
    const onay = {'onaylandi', 'approved', 'accepted', 'success', 'successful', 'basarili'};
    const ret = {'reddedildi', 'rejected', 'declined', 'refused', 'red'};
    const iptal = {'iptal', 'iptal_edildi', 'cancelled', 'canceled', 'voided'};
    if (onay.contains(h)) return 'onaylandi';
    if (ret.contains(h)) return 'reddedildi';
    if (iptal.contains(h)) return 'gib_iptal';
    return ham; // tanınmayan değer — olduğu gibi, teşhis için korunuyor
  }

  // 🔴 DÜZELTME (GİB Fatura denetimi, 2026-09-20): ÖNCEDEN hem HTTP
  // hatası (statusCode != 200) hem ağ/timeout istisnası SESSİZCE
  // yutulup AYNI şekilde null döndürülüyordu — çağıran ekran (bkz.
  // fatura_detay_ekrani.dart _durumEtiketi) null'ı "Beklemede" olarak
  // gösteriyordu. Sonuç: kullanıcı "GİB'e sorduk, hâlâ bekliyor" ile
  // "sorgu GİB'e hiç ulaşamadı" durumlarını AYIRT EDEMİYORDU — resmi
  // belge takibi için yanıltıcı. Artık gerçek bir hata (HTTP hatası veya
  // istisna) fırlatılıyor — HER İKİ çağıran taraf (fatura_detay_ekrani.dart,
  // irsaliye_ekrani.dart) zaten bu çağrıyı try/catch içine alıp
  // BildirimServisi.hata(...) ile açık bir hata mesajı gösteriyor, yani
  // bu değişiklik yeni bir crash riski YARATMIYOR — sadece önceden
  // sessizce yutulan hatayı kullanıcıya görünür kılıyor. "Yapılandırılmamış"
  // (ayarliMi==false) durumu davranışsal olarak DEĞİŞMEDİ — hâlâ null
  // döner (bu bir sorgu hatası değil, bir ön-koşul eksikliği).
  Future<String?> durumSorgula(String uuid) async {
    await ayarlariYukle();
    if (!ayarliMi) return null;
    try {
      final r = await _dio.get(
        '${_ayar.apiUrl!}/invoice/status/$uuid',
        options: Options(headers: {'Authorization': _authHeader}),
      );
      if (r.statusCode == 200) {
        final body = r.data as Map<String, dynamic>?;
        return _durumNormallestir(body?['status']?.toString());
      }
      throw Exception('GİB durum sorgusu başarısız (HTTP ${r.statusCode})');
    } catch (e) {
      if (kDebugMode) debugPrint('[HATA] ' + e.toString());
      rethrow;
    }
  }

  /// GİB'e gönderilmiş bir e-Fatura/e-Arşivi iptal eder. GİB kuralları
  /// (e-Arşiv için genelde aynı gün/kısa süreli bir pencere) ve gerçek
  /// uç nokta/istek formatı ENTEGRATÖRE göre değişir — burada yaygın bir
  /// REST deseni (mukellefSorgula/gonder ile AYNI mimari yaklaşım)
  /// varsayılan olarak kullanıldı. Kullandığınız entegratör farklıysa bu
  /// fonksiyonun onun dokümantasyonuna göre uyarlanması gerekir. SADECE
  /// GİB'e zaten ULAŞMIŞ ('gonderildi'/'onaylandi') bir belge için
  /// anlamlıdır — çağıran taraf bu kontrolü yapar.
  Future<bool> iptalEt({required String uuid, String? aciklama}) async {
    await ayarlariYukle();
    if (!ayarliMi) return false;
    try {
      final r = await _dio.post(
        '${_ayar.apiUrl!}/invoice/cancel',
        data: {'uuid': uuid, 'reason': aciklama ?? 'İptal'},
        options: Options(headers: {
          'Authorization': _authHeader,
          'Content-Type': 'application/json',
        }),
      ).timeout(const Duration(seconds: 20));
      final basarili = r.statusCode == 200 || r.statusCode == 201;
      await _log.kaydet(
        referansId: 0, referansTuru: 'fatura', uuid: uuid,
        islemTipi: 'iptal', durum: basarili ? 'basarili' : 'hata',
        hataMesaj: basarili ? null : 'HTTP ${r.statusCode}',
      );
      return basarili;
    } catch (e) {
      if (kDebugMode) debugPrint('GİB iptal hatası (entegratör API\'si farklı olabilir): $e');
      return false;
    }
  }

  // ── XML önizleme ────────────────────────────────────────────────────────
  Future<String> xmlOnizleme({
    required FaturaModel fatura,
  }) async {
    final ettn = ettnUret();
    return await ublXmlOlustur(fatura: fatura, ettn: ettn);
  }

  /// DB'den fatura için son log kaydını getir
  Future<Map<String, dynamic>?> sonLogGetir(int faturaId) => _log.sonLogGetir(faturaId);

  /// Kullanıcı sorusu: "gelen fatura ve giden fatura listeleme var mı?"
  /// ÖNCEDEN bu tamamen eksikti — sadece SİZİN kestiğiniz (giden)
  /// faturalar destekleniyordu. Ama bir e-Fatura mükellefiyseniz, BAŞKA
  /// mükelleflerin size GİB üzerinden gönderdiği faturaları da almanız
  /// ve YASAL OLARAK ZORUNLU "Uygulama Yanıtı" (Kabul/Red) ile
  /// yanıtlamanız gerekir (GİB Tebliği — yanıtlanmazsa süre sonunda
  /// otomatik kabul sayılır, ama yanıt vermemek yine de önerilmez).
  /// Bu fonksiyon entegratörünüzün "gelen kutusu" servisini sorgular.
  // 🔴 DÜZELTME (GİB Fatura denetimi, 2026-09-20): ÖNCEDEN ağ/API hatası
  // sessizce yutulup BOŞ liste döndürülüyordu — gib_gelen_kutusu_ekrani.dart
  // bunu "gerçekten gelen fatura yok" ile "sorgu başarısız oldu" arasında
  // AYIRT EDEMİYORDU, her ikisi de aynı boş-durum mesajını gösteriyordu.
  // Artık gerçek bir hata (HTTP hatası veya istisna) fırlatılıyor — çağıran
  // ekran try/catch ile yakalayıp _hata alanını dolduruyor.
  Future<List<Map<String, dynamic>>> gelenFaturalariGetir({int gunSayisi = 30}) async {
    if (!ayarliMi) return [];
    final bitis = DateTime.now();
    final baslangic = bitis.subtract(Duration(days: gunSayisi));
    final response = await _dio.get(
      '${_ayar.apiUrl}/einvoice/inbox',
      queryParameters: {
        'startDate': DateFormat('yyyy-MM-dd').format(baslangic),
        'endDate': DateFormat('yyyy-MM-dd').format(bitis),
      },
      options: Options(headers: {'Authorization': _authHeader}),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200 && response.data is Map) {
      final icerik = (response.data as Map)['Content'];
      if (icerik is List) return icerik.cast<Map<String, dynamic>>();
      return [];
    }
    throw Exception('GİB gelen kutusu sorgusu başarısız (HTTP ${response.statusCode})');
  }

  /// GİB'in yasal olarak zorunlu kıldığı "Uygulama Yanıtı" — gelen bir
  /// e-Faturayı KABUL veya RED eder. [faturaUuid] gelen faturanın ETTN
  /// (UUID) değeridir.
  Future<bool> uygulamaYanitiGonder(String faturaUuid, {required bool kabul}) async {
    if (!ayarliMi) return false;
    try {
      final response = await _dio.post(
        '${_ayar.apiUrl}/einvoice/applicationresponse',
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
