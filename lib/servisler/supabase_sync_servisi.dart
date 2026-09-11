// lib/servisler/supabase_sync_servisi.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'kolon_haritalama.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../veri/database/veritabani.dart';
import 'bulut/supabase_ayarlari.dart';

class _Ayar {
  final String url, key;
  _Ayar({required this.url, required this.key});
  String get rest => '$url/rest/v1';
}

class BaglantiSonuc {
  final bool basarili;
  final String mesaj;
  BaglantiSonuc(this.basarili, this.mesaj);
}

class SyncSonuc {
  final Map<String, int> eklenen    = {};
  final Map<String, int> guncellenen = {};
  final Map<String, int> silinen    = {};
  final List<String> hatalar        = [];

  int get toplamEklenen    => eklenen.values.fold(0, (a, b) => a + b);
  int get toplamGuncellenen=> guncellenen.values.fold(0, (a, b) => a + b);
  int get toplamSilinen    => silinen.values.fold(0, (a, b) => a + b);
  bool get basarili        => hatalar.isEmpty;

  String get ozet {
    final p = <String>[];
    if (toplamEklenen > 0)     p.add('+$toplamEklenen eklendi');
    if (toplamGuncellenen > 0) p.add('~$toplamGuncellenen güncellendi');
    if (toplamSilinen > 0)     p.add('-$toplamSilinen silindi');
    if (hatalar.isNotEmpty)    p.add('${hatalar.length} hata');
    return p.isEmpty ? 'Değişiklik yok' : p.join(', ');
  }
}

class SupabaseSyncServisi {
  static const _prefCihaz = 'mp_cihaz_id';

  static const _tabloSirasi = [
    'subeler','kullanicilar','kategoriler','birimler','markalar',
    'gider_kategoriler','rol_yetkileri','roller_yetki','ayarlar',
    'urunler','zaman_fiyat','fiyat_gecmis',
    // fiyat_gruplari, 'cari'den ÖNCE olmalı — cari.fiyat_grubu_id bu
    // tabloya FK ile bağlı; sıra yanlış olursa FK dönüşümü sırasında
    // parent henüz buluta gitmemiş olabilir.
    'fiyat_gruplari',
    'cari','cari_adres','musteri_puan',
    // Kullanıcı isteği: "Bayilerden Sipariş Alma" — sipariş önce
    // "Bekleyen Sipariş" olarak kaydediliyor. 'cari' (bayi) ve
    // 'urunler'e FK ile bağlı olduğundan ikisinden SONRA senkronize
    // ediliyor (bkz. lot_seri'deki aynı sınıf hata ve düzeltmesi —
    // aynı hatayı burada baştan önlemek için).
    'bekleyen_siparisler','bekleyen_siparis_kalem',
    // 🔴🔴🔴 KRİTİK DÜZELTME (ikinci derin analizde bulundu):
    // 'lot_seri' ÖNCEDEN burada değil, 'urunler'in hemen yanında,
    // yani 'cari'DEN ÖNCE senkronize ediliyordu. Ama gerçek Supabase
    // şeması doğrulandı: lot_seri.tedarikci_cari_id BIGINT REFERENCES
    // cari(id) — GERÇEK bir FK kısıtlaması var. FK dönüşüm mekanizması
    // (hem gönderme hem alma yönünde) parent tabloların çocuklardan
    // ÖNCE işlenmiş olmasına bağımlı. Sıra yanlış olduğundan: boş/yeni
    // bir buluta ilk tam senkronda, tedarikçili bir lot/seri kaydının
    // tedarikci_cari_id'si ya FK kısıtlaması ihlali yüzünden
    // REDDEDİLİYOR, ya da (cari.id bulutta tesadüfen doluysa) YANLIŞ
    // bir cariye bağlanıyordu — sessiz veri bozulması. Artık 'cari'
    // tablosu buluta gittikten SONRA 'lot_seri' gönderiliyor.
    'lot_seri',
    'vardiyalar',
    'satislar','satis_kalem','kasa_hareketleri',
    'iade','iade_kalem',
    'irsaliyeler','irsaliye_kalem',
    'promosyonlar','promosyon_tanim','promosyon_kosul','promosyon_aksiyon',
    'tedarikci_siparisler','tedarikci_siparis_kalem',
    'giderler','faturalar','fatura_detaylari',
    'stok_hareket','cari_hareket','puan_hareket','personel',
    'masalar','masa_siparisleri','masa_siparis_kalem',
    'masa_rezervasyon',
    'adisyon_log',
    'garson_cagri_log',
    'masa_hareket_log',
  
    // Kullanıcı isteği: kredi kartı/banka hareketlerinin de çoklu
    // cihazda senkron olması. Bu iki tablo daha önce hiç senkron
    // listesinde değildi — sadece o cihazda kalıyordu.
    // 🔴 Derin analizde bulundu: FK dönüşüm mekanizması (kolon_haritalama.dart)
    // 'banka_hareketler.banka_hesap_id' için ZATEN 'banka_hesaplar' tablosunu
    // hedef olarak bekliyordu — ama bu iki tablo (bankalar, banka_hesaplar)
    // senkron sisteminde HİÇ yoktu. FK dönüşümü sessizce başarısız oluyordu.
    // Parent tablolar olarak banka_hareketler'den ÖNCE eklendi.
    'bankalar', 'banka_hesaplar', 'kredi_kartlari',
    'banka_hareketler','kredi_karti_hareket',

    // 🔴 Derin analizde bulundu: borç takip modülü SENKRON
    // SİSTEMİNİN TAMAMEN DIŞINDAYDI. borclar önce (parent),
    // borc_odemeler sonra (borc_id FK'sı borclar'a bağımlı).
    'borclar','borc_odemeler',
    // Audit log (kim ne yaptı ne zaman)
    'audit_log',
    // Toptan satış: fiyat_gruplari zaten yukarıda (cari'den önce)
    // eklendi — burada sadece ona bağımlı olanlar.
    'urun_fiyat_gruplari', 'fiyat_kademeleri', 'sube_urun',
  ];

  static const _globalIdVar = {
    'cari','cari_adres','fatura_detaylari','faturalar','giderler',
    'iade','irsaliyeler','kasa_hareketleri','kullanicilar','lot_seri',
    'musteri_puan','personel','promosyon_tanim','promosyonlar',
    'satis_kalem','satislar','stok_hareket','subeler',
    'tedarikci_siparisler','urunler','vardiyalar',
    'masalar','masa_siparisleri','masa_siparis_kalem',
    'masa_rezervasyon',
    'adisyon_log',
    'garson_cagri_log',
    'masa_hareket_log',
    
    'banka_hareketler','kredi_karti_hareket',
    'bankalar', 'banka_hesaplar', 'kredi_kartlari',
    // Kök neden düzeltmesi kapsamında eklendi (üstteki nota bkz.):
    'fiyat_gecmis', 'iade_kalem', 'irsaliye_kalem', 'promosyon_aksiyon', 'promosyon_kosul', 'puan_hareket', 'rol_yetkileri', 'roller_yetki', 'tedarikci_siparis_kalem', 'zaman_fiyat',
    // Borç modülü senkron entegrasyonu:
    'borclar', 'borc_odemeler', 'audit_log',
    'fiyat_gruplari', 'urun_fiyat_gruplari', 'fiyat_kademeleri', 'sube_urun',
    'cari_hareket', // 🔴 KRİTİK DÜZELTME: gerçekten global_id'ye sahip olduğu halde eksikti — PUSH öncesi global_id siliniyordu, yinelenen kayıt riski.
    // "Bayilerden Sipariş Alma" (bekleyen sipariş) tabloları:
    'bekleyen_siparisler', 'bekleyen_siparis_kalem',

  };

  // 🔴 DÜZELTME: 'masa_siparisleri' önceden bu listede YOKTU — oysa
  // _fkHaritasi'da masa_siparis_kalem.siparis_id, adisyon_log.siparis_id
  // ve masa_hareket_log.siparis_id için PARENT olarak kullanılıyor.
  // Haritası hiç kurulamadığı için, indirme sırasında bu kolonlar
  // eşleşme bulunamayıp SİLİNİYORDU → indirilen masa sipariş kalemleri
  // hiçbir siparişe bağlı olmadan geliyordu (diğer cihazda masanın
  // ürünleri görünmüyordu).
  // 🔴 Derin analizde bulundu: 'kullanicilar' bu listede hiç yoktu —
  // yeni eklenen 'roller_yetki.kullanici_id' FK dönüşümü (bkz.
  // kolon_haritalama.dart) bu harita olmadan çalışamazdı.
  // 🔴🔴 Derin analizde bulundu: 'kredi_kartlari' — banka_hareketler,
  // kredi_karti_hareket, borc_odemeler tablolarının FK HEDEFİ olduğu
  // halde bu listede HİÇ yoktu. Bu üç tablonun kredi_karti_id FK
  // dönüşümü, hedef tablonun id haritası hiç kurulmadığı için sessizce
  // başarısız oluyordu.
  // 🔴🔴🔴 KRİTİK, AKTİF VERİ KAYBI DÜZELTMESİ (kullanıcı bulgusu —
  // "hızlı al hızlı gönder onlara da baktın mı, tam gönder tam al iyice
  // incele"): Bu liste 'banka_hesaplar', 'bankalar', 'borclar',
  // 'fiyat_gruplari', 'promosyon_tanim' tablolarını İÇERMİYORDU — oysa
  // bu 5 tablo fkHaritasi'nde FK HEDEFİ (parent) olarak kullanılıyor.
  // Sonuç: idHaritasi[parentTablo] bu 5 tablo için HİÇ kurulmadığından
  // hep null dönüyordu, ve FK çevirme kodundaki
  // "localId == null ise m.remove(kolon)" mantığı devreye girip
  // İLGİLİ FK SÜTUNUNU TAMAMEN SİLİYORDU. Somut etki: borc_odemeler
  // çekilirken borc_id kayboluyor (ödeme hangi borca ait bilinmiyor —
  // Ödeme Geçmişi özelliği çok cihazlı kullanımda bozuluyor),
  // urun_fiyat_gruplari/fiyat_kademeleri çekilirken fiyat_grubu_id
  // kayboluyor (toptan fiyatlandırma bozuluyor), banka_hareketleri
  // çekilirken banka_hesap_id kayboluyor.
  // 🔴🔴🔴 KAPSAMLI DERİN ANALİZ EK GÜNCELLEMESİ: kolon_haritalama.dart
  // içindeki fkHaritasi'ye 25 tabloda 35 eksik FK dönüşümü eklendi
  // (banka_hesaplar sorunuyla AYNI hata sınıfı — bkz. o dosyadaki not).
  // Bu yeni FK hedeflerinin (parent) id haritası burada da kurulmazsa,
  // YUKARIDAKİ notta anlatılan AYNI veri kaybı (FK sütununun tamamen
  // silinmesi) bu yeni eklenen ilişkilerde de yaşanır. Yeni parent'lar:
  // kategoriler, gider_kategoriler, vardiyalar, lot_seri, irsaliyeler,
  // faturalar, tedarikci_siparisler.
  static const _idHaritasiKurulacakTablolar = ['cari', 'urunler', 'satislar', 'iade', 'masalar', 'masa_siparisleri', 'kullanicilar', 'kredi_kartlari', 'subeler', 'banka_hesaplar', 'bankalar', 'borclar', 'fiyat_gruplari', 'promosyon_tanim', 'kategoriler', 'gider_kategoriler', 'vardiyalar', 'lot_seri', 'irsaliyeler', 'faturalar', 'tedarikci_siparisler', 'bekleyen_siparisler'];

  // 🔄 TEK DOĞRULUK KAYNAĞI: FK haritası artık KolonHaritalama'da
  // (hem manuel hem otomatik senkron yolu aynı haritayı kullanıyor —
  // iki ayrı kopyanın zamanla birbirinden sapması riskine karşı).
  static const _fkHaritasi = KolonHaritalama.fkHaritasi;

  static const _lastUpdatedVar = {
    'birimler','cari','cari_adres','cari_hareket','fatura_detaylari',
    'faturalar','gider_kategoriler','giderler','iade','iade_kalem',
    'kasa_hareketleri','kategoriler','kullanicilar','lot_seri',
    'musteri_puan','personel','promosyonlar','puan_hareket',
    'satis_kalem','satislar','stok_hareket','tedarikci_siparis_kalem',
    'tedarikci_siparisler','urunler','vardiyalar',
    'masalar','masa_siparisleri','masa_siparis_kalem',
    'masa_rezervasyon',
    'garson_cagri_log',
    'masa_hareket_log',
    'adisyon_log',
    // Kök neden düzeltmesi kapsamında eklendi (delta çalışsın):
    'banka_hareketler', 'kredi_karti_hareket', 'fiyat_gecmis', 'irsaliye_kalem', 'promosyon_aksiyon', 'promosyon_kosul', 'rol_yetkileri', 'roller_yetki', 'zaman_fiyat',
    'bankalar', 'banka_hesaplar', 'kredi_kartlari',
    'borclar', 'borc_odemeler', 'audit_log',
    'fiyat_gruplari', 'urun_fiyat_gruplari', 'fiyat_kademeleri', 'sube_urun',
    // 🔴 DÜZELTME (kullanıcı bulgusu — "buluttan veri al'ı kontrol
    // et"): Bu 3 tablo gerçekten last_updated sütununa sahip olduğu
    // halde eksikti — delta senkron (sadece değişenleri çek)
    // ÇALIŞMIYORDU, her senkronda TÜM tablo baştan indiriliyordu
    // (küçük referans tabloları için performans kaybı).
    'subeler', 'markalar', 'ayarlar',

    // 🔴🔴 İKİNCİ DERİN ANALİZDE BULUNDU: 'irsaliyeler' bulut şemasında
    // last_updated sütununa sahip (TIMESTAMPTZ) — ama yerel tabloda bu
    // sütun hiç yoktu (bkz. migrasyon v48->v49) ve bu yüzden burada da
    // eksikti. Sonuç: irsaliyeler için delta senkron hiç çalışmıyordu,
    // her "Hızlı Sync"te TÜM irsaliyeler baştan indiriliyordu. Yerel
    // sütun artık eklendi (migrasyon v49), bu yüzden tablo buraya da
    // eklendi.
    'irsaliyeler',

    // "Bayilerden Sipariş Alma" (bekleyen sipariş) tabloları:
    'bekleyen_siparisler', 'bekleyen_siparis_kalem',

  };

  static const Map<String, String> _uniqueAlan = {
    'subeler':           'sube_kodu',
    'birimler':          'ad',
    'kategoriler':       'ad',
    'gider_kategoriler': 'ad',
    'markalar':          'ad',
    'kullanicilar':      'kullanici_adi',
    'ayarlar':           'anahtar',
    'urunler':           'global_id',
    'cari':              'global_id',
    'cari_adres':        'global_id',
    'cari_hareket':      'global_id',
    'satislar':          'global_id',
    'satis_kalem':       'global_id',
    'kasa_hareketleri':  'global_id',
    'giderler':          'global_id',
    'faturalar':         'global_id',
    'fatura_detaylari':  'global_id',
    'iade':              'global_id',
    'irsaliyeler':       'global_id',
    'promosyonlar':      'global_id',
    'promosyon_tanim':   'global_id',
    'tedarikci_siparisler':   'global_id',
    'lot_seri':          'global_id',
    'personel':          'global_id',
    'musteri_puan':      'global_id',
    'vardiyalar':        'global_id',
    'masalar':           'global_id',
    'masa_siparisleri':  'global_id',
    'masa_siparis_kalem':'global_id',
    'masa_rezervasyon':  'global_id',
    // 🔴 ÖNCEDEN bu üç log tablosu 'id' anahtarıyla insert-only
    // dalındaydı — global_id'siz kayıtlarda (adisyon_log insert'i gid
    // atamıyor) her senkron AYNI kayıtları YENİDEN ekliyordu (null
    // global_id UNIQUE'e takılmaz) → stok_hareket'teki şişme hastalığının
    // aynısı. 'global_id' yapılınca upsert dalına giriyorlar: merkezi
    // kimlik backfill + on_conflict + delta hepsi devreye giriyor.
    'adisyon_log':       'global_id',
    'garson_cagri_log':  'global_id',
    'masa_hareket_log':  'global_id',
    // 🔴🔴 GERÇEK KÖK NEDEN: Bu 14 tablo haritada HİÇ YOKTU —
    // hepsi kayıt-kayıt INSERT dalından gidiyordu: on_conflict yok,
    // kimlik backfill yok, delta ilerlemesi yok, batch yok. Sonuç:
    // stok_hareket'te 4667 kayıt × tekil istek (25 dk 'takılma') ve
    // her senkronda yeni kimliklerle ÇOĞALMA (bulutta 9000+ satır).
    'stok_hareket': 'global_id',
    'banka_hareketler': 'global_id',
    'bankalar': 'global_id',
    'banka_hesaplar': 'global_id',
    'kredi_kartlari': 'global_id',
    'kredi_karti_hareket': 'global_id',
    'fiyat_gecmis': 'global_id',
    'iade_kalem': 'global_id',
    'irsaliye_kalem': 'global_id',
    'promosyon_aksiyon': 'global_id',
    'promosyon_kosul': 'global_id',
    'puan_hareket': 'global_id',
    'rol_yetkileri': 'global_id',
    'roller_yetki': 'global_id',
    'tedarikci_siparis_kalem': 'global_id',
    'zaman_fiyat': 'global_id',
    'borclar': 'global_id',
    'borc_odemeler': 'global_id',
    'audit_log': 'global_id',
    'fiyat_gruplari': 'global_id',
    'urun_fiyat_gruplari': 'global_id',
    'fiyat_kademeleri': 'global_id',
    'sube_urun': 'global_id',
    // "Bayilerden Sipariş Alma" (bekleyen sipariş) tabloları:
    'bekleyen_siparisler': 'global_id',
    'bekleyen_siparis_kalem': 'global_id',

  };

  // 🔴🔴 Derin analizde bulundu: Bu oturumda soft-delete (is_deleted)
  // desteği eklediğim 'kategoriler', 'markalar', 'promosyonlar',
  // 'subeler' tabloları burada UNUTULMUŞTU. Etkisi: eğer silinmiş bir
  // kayıt (is_deleted=1) DAHA ÖNCE hiç senkronize olmadıysa (örn. bir
  // cihazda oluşturulup HEMEN silindiyse), buluttan_al() bu kaydı
  // "yeni kayıt" sanıp BAŞKA bir cihaza EKLERDİ — silinmiş bir
  // kategori/marka/promosyon/şube, onu hiç görmemiş bir cihazda
  // yeniden "dirilirdi".
  // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu mekanizma
  // (aşağıdaki _silinmisMi() ve kullanıldığı yerler) önceden HER ZAMAN
  // 'is_deleted' sütununu kontrol ediyordu — ama 'faturalar',
  // 'giderler', 'irsaliyeler', 'promosyonlar' tabloları aslında
  // 'deleted_at' (DATETIME veya null) kullanıyor, 'markalar' ise
  // 'aktif' (0=silinmiş) kullanıyor! Bu üç farklı isimlendirme
  // yüzünden, bu tabloların silinen kayıtları buluttan_al() sırasında
  // HİÇ tanınmıyordu — hiç senkronize olmamış silinmiş bir kayıt,
  // başka bir cihazda "yeni kayıt" gibi eklenip DİRİLEBİLİYORDU. Bu,
  // bu oturumda eklediğim tablolardan ÖNCE de var olan, gizli bir
  // hataydı.
  static const _softDeleteKolonu = {
    'urunler': 'is_deleted', 'cari': 'is_deleted', 'satislar': 'is_deleted',
    'masa_rezervasyon': 'is_deleted', 'kategoriler': 'is_deleted', 'subeler': 'is_deleted',
    'faturalar': 'deleted_at', 'giderler': 'deleted_at',
    'irsaliyeler': 'deleted_at', 'promosyonlar': 'deleted_at',
    'markalar': 'aktif',
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "buluttan veri al'ı
    // kontrol et, uyuşmayan yer olur"): Bu harita ÖNCEDEN sadece 11
    // tablo içeriyordu — geriye kalan tablolarda (özellikle bu
    // oturumda eklenen kredi_kartlari, borclar, sube_urun gibi
    // birçoğu) silme algılama TAMAMEN devre dışıydı: buluttan gelen
    // bir "silindi" bilgisi normal güncelleme olarak işleniyor,
    // senkron raporunda "silinen" sayısı hep 0 görünüyordu. Her
    // tablonun GERÇEK yerel şema sütunu (test veritabanından PRAGMA
    // table_info ile doğrulandı) eklendi.
    'kullanicilar': 'is_deleted', 'birimler': 'aktif', 'lot_seri': 'aktif',
    'zaman_fiyat': 'aktif', 'fiyat_gruplari': 'is_deleted',
    'kasa_hareketleri': 'deleted_at', 'iade': 'deleted_at',
    'promosyon_tanim': 'aktif', 'tedarikci_siparisler': 'is_deleted',
    'cari_hareket': 'is_deleted', 'personel': 'is_deleted',
    'masalar': 'is_deleted', 'masa_siparisleri': 'is_deleted',
    'masa_siparis_kalem': 'is_deleted', 'banka_hesaplar': 'aktif',
    'bankalar': 'aktif', 'kredi_kartlari': 'aktif',
    'banka_hareketler': 'is_deleted', 'kredi_karti_hareket': 'is_deleted',
    'borclar': 'is_deleted',
    // Not: gider_kategoriler, rol_yetkileri, roller_yetki, ayarlar,
    // fiyat_gecmis, cari_adres, musteri_puan, vardiyalar, satis_kalem,
    // iade_kalem, irsaliye_kalem, promosyon_kosul, promosyon_aksiyon,
    // tedarikci_siparis_kalem, fatura_detaylari, stok_hareket,
    // puan_hareket, adisyon_log, garson_cagri_log, masa_hareket_log,
    // borc_odemeler, audit_log, urun_fiyat_gruplari, fiyat_kademeleri,
    // sube_urun — bu tablolarda GERÇEKTEN soft-delete sütunu yok
    // (append-only/immutable hareket kayıtları veya hiç silinmeyen
    // referans veriler) — haritada bilinçli olarak YOK, _silinmisMi()
    // bunlar için doğru şekilde false döner.
  };

  /// Gelen bir kaydın (m), o tablonun GERÇEK silme sütununa göre
  /// "silinmiş" sayılıp sayılmayacağını doğru şekilde tespit eder.
  static bool _silinmisMi(String tablo, Map<String, dynamic> m) {
    final kolon = _softDeleteKolonu[tablo];
    if (kolon == null) return false;
    if (kolon == 'aktif') return m['aktif'] == 0 || m['aktif'] == false;
    if (kolon == 'deleted_at') return m['deleted_at'] != null;
    return m['is_deleted'] == 1 || m['is_deleted'] == true;
  }

  static const _softDelete = {
    'urunler','cari','satislar','faturalar','giderler','irsaliyeler',
    'masa_rezervasyon','kategoriler','markalar','promosyonlar','subeler',
  };

  static const Set<String> _boolAlanlar = {
    'aktif', 'is_deleted', 'iptal', 'seri_no_takibi', 'lot_takibi',
    'otomatik_indirim', 'evrak_kontrol_aktif', 'promosyon_aktif',
    'varsayilan', 'okundu', 'silindi', 'onaylandi', 'tamamlandi',
  };

  // NOT: 'masalar','masa_siparisleri','masa_siparis_kalem' önceden
  // burada listeliydi çünkü Supabase'de is_deleted sütunları INTEGER
  // kalmıştı — artık Supabase tarafında BOOLEAN'a çevrildiği için
  // (bkz. supabase_sema_duzeltmeleri.sql) bu istisnaya gerek kalmadı.
  static const Set<String> _skipBoolDonusum = {};

  static const _damaGonderilmez = {
    'sync_status', 'barkod_olcu_birimi', 'plu_kart_boyut', 'resmi_bakiye',
    'eski_kodu', 'seri_numarasi', 'fiyat_guncelleme_tarih','fiyat_guncelleyen_kullanici',
    'barkod_yazdirma_tarih','barkod_yazdiran_kullanici', 'maliyet_guncelleme_tarih',
    'maliyet_guncelleyen_kullanici', 'guncelleme_tarihi','guncelleyen_kullanici',
    'kaydeden_kullanici','grup_sorumlusu','mensei', 'raf_omru','lot_aciklama',
    'promosyon_grup','recete_katsayi', 'net_alis_fiyat','evrak_kontrol_aktif',
    'son_alim_indirim_oran', 'maksimum_satir_miktari','beden','renk','sube',
    'plu_numarasi','lot_no','kart_tipi', 'alan1','alan2','alan3','alan4',
    'alternatif_urun_adi','alt_grup','ana_grup', 'muafiyet_kodu','muhasebe_kodu',
    'uretici', 'para_birimi','model','marka',
  };

  // --------------------------------------------------------------
  // YARDIMCI METODLAR
  // --------------------------------------------------------------
  static Future<_Ayar?> _ayarGetir() async {
    final url = await SupabaseAyarlari.urlOku();
    final key = await SupabaseAyarlari.keyOku();
    if (url == null || url.isEmpty || key == null || key.isEmpty) return null;
    return _Ayar(url: url.trim(), key: key.trim());
  }

  static Future<void> ayarlariKaydet(String url, String key) async {
    final temiz = url.trim()
        .replaceAll(RegExp(r'/rest/v1/?$'), '')
        .replaceAll(RegExp(r'/$'), '');
    await SupabaseAyarlari.kaydet(url: temiz, key: key.trim());
  }

  static Future<String> cihazId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_prefCihaz);
    if (id == null) {
      id = 'cihaz_${DateTime.now().millisecondsSinceEpoch}';
      await p.setString(_prefCihaz, id);
    }
    return id;
  }

  static Map<String, String> _getH(String key) => {
    'apikey': key,
    'Authorization': 'Bearer $key',
    'Accept': 'application/json',
  };

  static Map<String, String> _upsertH(String key) => {
    'apikey': key,
    'Authorization': 'Bearer $key',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Prefer': 'resolution=merge-duplicates,return=minimal',
  };

  static Map<String, String> _insertH(String key) => {
    'apikey': key,
    'Authorization': 'Bearer $key',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Prefer': 'return=minimal',
  };

  // ══════════════════════════════════════════════════════════════════════
  // 🔴 KRİTİK ÇOKLU CİHAZ DÜZELTMESİ — PAYLAŞILAN FİLİGRAN
  //
  // ÖNCEDEN: gönderme ve çekme AYNI anahtarı ('mp_sync_<tablo>')
  // kullanıyordu. Oysa bu ikisi FARKLI ZAMAN EKSENİNDE:
  //
  //   • GÖNDERME filigranı, BU CİHAZIN yazdığı yerel kayıtların
  //     last_updated'iyle karşılaştırılır → cihaz saati ekseni.
  //   • ÇEKME filigranı, BAŞKA CİHAZLARIN yazdığı bulut kayıtlarının
  //     last_updated'iyle karşılaştırılır → sunucu/diğer cihaz ekseni.
  //
  // KAYIP SENARYOSU (tek anahtar paylaşılınca):
  //   • Cihaz çevrimdışıyken 10:15'te bir satış kaydediyor (gönderilmedi)
  //   • Sonra "Hızlı Al" yapılıyor; bulutta 10:30 damgalı kayıtlar var
  //     → filigran 10:30'a ilerliyor
  //   • "Hızlı Gönder" filtresi: last_updated > 10:30
  //     → 10:15'lik KENDİ SATIŞI ELENİYOR, buluta HİÇ gitmiyor.
  //   → Kalıcı kayıp. "Tam Gönder" yapılmadıkça fark edilmez.
  //
  // DÜZELTME: iki ayrı anahtar. Eski tek anahtar, ilk okumada her iki
  // yöne de TOHUM olarak verilir — güncelleme sonrası gereksiz tam
  // senkron olmaz.
  // ══════════════════════════════════════════════════════════════════════
  static String _filigranAnahtari(String tablo, String yon) =>
      'mp_sync_${yon}_$tablo';

  static Future<DateTime?> _sonSenkron(String tablo, String yon) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_filigranAnahtari(tablo, yon))
        // Eski sürümden gelen tek anahtar — ilk okumada tohum.
        ?? p.getString('mp_sync_$tablo');
    return s != null ? DateTime.tryParse(s) : null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🔴 KRİTİK ÇOKLU CİHAZ DÜZELTMESİ — SAAT KAYMASI VERİ KAYBI
  //
  // ÖNCEDEN: filigran her zaman `DateTime.now()` — yani BU CİHAZIN
  // saati — olarak kaydediliyordu. Ama çekme filtresi
  // `?last_updated=gt.<filigran>` bulut satırlarına uygulanıyor ve o
  // satırların `last_updated` değerleri BAŞKA CİHAZLARIN saatiyle
  // yazılmış.
  //
  // KAYIP SENARYOSU (iki kasa, saatleri 5 dk kaymış):
  //   • Kasa-B saat 10:00'da (B'nin saati) çekiyor → filigran = 10:00
  //   • Kasa-A'nın saati 5 dk GERİDE. A, gerçek saat 10:03'te bir satış
  //     kaydediyor; damga A'nın saatiyle 09:58 oluyor.
  //   • A gönderiyor, bulutta satır last_updated = 09:58.
  //   • B bir daha çektiğinde filtre "> 10:00" → 09:58 ELENİYOR.
  //   → O satış Kasa-B'ye ASLA gelmiyor. Sessiz, kalıcı veri kaybı.
  //     "Tam Al" yapılmadıkça fark edilmez.
  //
  // DÜZELTME: filigran artık cihaz saatinden değil, ÇEKİLEN VERİDEKİ
  // en büyük `last_updated` değerinden alınıyor. Böylece filigran her
  // zaman sunucudaki/diğer cihazlardaki zaman ekseninde kalır; yerel
  // saatin doğru olması gerekmez.
  //
  // Veri gelmediyse filigran İLERLETİLMEZ (eskisi korunur) — yoksa boş
  // bir çekim, henüz gönderilmemiş kayıtları geçmişte bırakırdı.
  // ══════════════════════════════════════════════════════════════════════
  static Future<void> _senkronKaydet(String tablo, String yon,
      [String? veridekiEnSonZaman]) async {
    final p = await SharedPreferences.getInstance();
    final anahtar = _filigranAnahtari(tablo, yon);

    // ÇEKME: filigran verideki en büyük last_updated'ten ilerler
    // (cihaz saatinden DEĞİL — saat kayması veri kaybı koruması).
    if (veridekiEnSonZaman != null && veridekiEnSonZaman.isNotEmpty) {
      final yeniZ = DateTime.tryParse(veridekiEnSonZaman);
      if (yeniZ != null) {
        final mevcutStr = p.getString(anahtar);
        final mevcut = mevcutStr != null ? DateTime.tryParse(mevcutStr) : null;
        if (mevcut == null || yeniZ.isAfter(mevcut)) {
          await p.setString(anahtar, yeniZ.toUtc().toIso8601String());
        }
        return;
      }
    }

    // GÖNDERME: yerel kayıtlarla karşılaştırıldığı için cihaz saati DOĞRU
    // eksendir. Çekmede ise (veri yoksa) mevcut filigran KORUNUR.
    if (yon == 'gonder') {
      await p.setString(anahtar, DateTime.now().toUtc().toIso8601String());
    } else if (p.getString(anahtar) == null) {
      await p.setString(anahtar, DateTime.now().toUtc().toIso8601String());
    }
  }

  /// Çekilen partideki en büyük `last_updated` — filigran için.
  static String? _enSonZaman(List<Map<String, dynamic>> kayitlar) {
    String? enSon;
    for (final r in kayitlar) {
      final s = r['last_updated']?.toString();
      if (s == null || s.isEmpty) continue;
      if (enSon == null || s.compareTo(enSon) > 0) enSon = s;
    }
    return enSon;
  }

  // --------------------------------------------------------------
  // VERİ HAZIRLAMA - TÜM NOT NULL SÜTUNLAR DOLDURULDU
  // --------------------------------------------------------------
  static Map<String, dynamic> _hazirla(
    Map<String, dynamic> row,
    String tablo,
    String cId,
    String now,
  ) {
    final m = Map<String, dynamic>.from(row);

    // Gönderilmeyecek kolonları temizle
    for (final k in _damaGonderilmez) m.remove(k);
    m.remove('id');

    // 🔥 EVRENSEL DÜZELTME: kullanıcının paylaştığı gerçek hata
    // kaydında ("cari_hareket INSERT 400: invalid input syntax for
    // type bigint: 'false'") görüldüğü gibi, bazı kayıtlarda BEKLENMEDİK
    // şekilde bir Dart boolean (true/false) değeri, Supabase'de
    // sayısal (bigint) olan bir sütuna gönderiliyordu. Kaynağını
    // (hangi kod yolunun bunu ürettiğini) kesin olarak izlemek yerine,
    // HANGİ TABLO/SÜTUN olursa olsun, göndermeden hemen önce TÜM
    // boolean değerleri güvenli şekilde 0/1'e çeviren evrensel bir
    // koruma ekleniyor — bu hata sınıfı bir daha hiçbir tabloda
    // çıkmayacak.
    for (final k in m.keys.toList()) {
      final v = m[k];
      if (v is bool) m[k] = v ? 1 : 0;
    }

    // 🔴🔴🔴 KAPSAMLI DERİN ANALİZ (kullanıcı isteği — "başka
    // tablolarda var mı bak"): 'faturalar' ve 'personel' tablolarının
    // migrasyon geçmişi tarandı — ESKİ bir migrasyon adımı bir sütun
    // ekledikten SONRA, DAHA SONRAKİ bir migrasyon adımı FARKLI bir
    // isimle onun YERİNE GEÇEN bir sütun daha eklemiş, ama eski sütun
    // hiç SİLİNMEMİŞ. Var olan (yükseltilmiş) her cihazda HER İKİ
    // sütun da hâlâ fiziksel olarak duruyor. Bulut şemasında sadece
    // YENİ isim var — eski isim buluta HİÇ gitmemiş. `_hazirla()`
    // gönderilecek sütun listesini payload'daki anahtarlardan kurduğu
    // için, eski sütun adı da listeye giriyor ve PostgREST TÜM
    // partiyi "column does not exist" hatasıyla reddediyordu — yani
    // 'faturalar' ve 'personel' senkronu, güncellenmiş (taze kurulum
    // olmayan) HER cihazda muhtemelen TAMAMEN çalışmıyordu. BUNU
    // GENEL (_damaGonderilmez) listesine EKLEMEDİM çünkü 'satislar'
    // tablosunda 'efatura_uuid'/'efatura_durum' aynı isimlerle
    // GERÇEKTEN kullanılıyor ve bulutta karşılığı var — genel bir
    // filtre onları da (yanlışlıkla) silerdi. Bu yüzden sadece BU İKİ
    // tabloda, nokta atışı olarak temizleniyor:
    //   faturalar: efatura_uuid  → yerini e_fatura_uuid aldı
    //   faturalar: efatura_durum → yerini e_fatura_durum aldı
    //   faturalar: efatura_tipi  → bulutta hiç karşılığı yok (kullanılmıyor)
    //   personel:  ise_baslama_tarihi → yerini ise_baslama aldı
    if (tablo == 'faturalar') {
      m.remove('efatura_uuid');
      m.remove('efatura_durum');
      m.remove('efatura_tipi');
    }
    if (tablo == 'personel') {
      m.remove('ise_baslama_tarihi');
    }

    // 🔥 SATISLAR için NOT NULL sütunları doldur
    if (tablo == 'satislar') {
      m['toplam_tutar'] ??= 0.0;
      m['iskonto_tutar'] ??= 0.0;
      m['iskonto_oran'] ??= 0.0;
      m['kdv_tutar'] ??= 0.0;
      m['genel_toplam'] ??= 0.0;
      m['odenen_tutar'] ??= 0.0;
      m['kargo_ucreti'] ??= 0.0;
      m['iptal'] ??= 0;
      m['is_deleted'] ??= 0;
      if (m['tarih'] == null) m['tarih'] = now;
      if (m['odeme_yontemi'] == null) m['odeme_yontemi'] = 'Nakit';
      if (m['fis_tipi'] == null) m['fis_tipi'] = 'Satış';
    }

    // 🔥 SATIS_KALEM için NOT NULL sütunları doldur
    if (tablo == 'satis_kalem') {
      m['miktar'] ??= 1.0;
      m['birim_fiyat'] ??= 0.0;
      m['iskonto_oran'] ??= 0.0;
      m['iskonto_tutar'] ??= 0.0;
      m['kdv_oran'] ??= 18.0;
      m['kdv_tutar'] ??= 0.0;
      m['net_fiyat'] ??= 0.0;
      m['toplam_tutar'] ??= 0.0;
      m['alis_fiyat'] ??= 0.0;
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
    }

    // 🔥 IADE_KALEM / IRSALIYE_KALEM / MASA_SIPARIS_KALEM /
    // TEDARIKCI_SIPARIS_KALEM için NOT NULL sütunları doldur
    // 🔴🔴 KAPSAMLI DERİN ANALİZ (kullanıcı isteği — "başka tablolarda
    // var mı bak"): satis_kalem'e ÖNCEDEN eklenmiş olan urun_adi
    // koruması, tam olarak AYNI riski taşıyan 3 kardeş "kalem" (kalem
    // satırı) tablosuna hiç uygulanmamıştı — hepsi urun_id yanında
    // DENORMALİZE bir urun_adi anlık görüntüsü tutuyor ve bulutta bu
    // sütun(lar) NOT NULL. kart_no_maskeli hatasında görüldüğü gibi,
    // aynı partideki başka bir kayıtta bu alan eksikse _normalizeBatch()
    // bunu null'a çevirebiliyor — burada da aynı savunma ekleniyor.
    if (tablo == 'iade_kalem') {
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
      m['miktar'] ??= 1.0;
      m['birim_fiyat'] ??= 0.0;
      m['toplam'] ??= 0.0;
    }
    if (tablo == 'irsaliye_kalem') {
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
      m['miktar'] ??= 1.0;
    }
    if (tablo == 'masa_siparis_kalem') {
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
    }
    if (tablo == 'tedarikci_siparis_kalem') {
      m['siparis_mik'] ??= 1.0;
      m['birim_fiyat'] ??= 0.0;
      m['toplam_tutar'] ??= 0.0;
    }

    // 🔥 KREDI_KARTLARI için NOT NULL sütunları doldur
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — gerçek Supabase hatası:
    // "kredi_kartlari UPSERT 400: ... kart_no_maskeli ... null ...").
    // Bu alan için koruma ÖNCEDEN sadece supaTumKayitlariGetirTemiz()
    // içinde (veritabani.dart) vardı — yani veri bu fonksiyona
    // ULAŞMADAN ÖNCEKİ bir adımda. Ama _normalizeBatch() (aşağıda),
    // aynı toplu istekteki kayıtları TÜM anahtarların BİRLEŞİMİNE göre
    // normalize ederken, bir kayıtta bu alan (herhangi bir sebeple)
    // eksikse ona AÇIKÇA `null` atıyor — yani bir kart için doğru
    // değer üretilse bile, aynı partideki BAŞKA bir kartta bu alan
    // eksikse, normalizasyon bunu yeniden null'a çevirebiliyordu. Artık
    // bu son kontrol noktasında (buluta gitmeden hemen önce, TEK
    // merkezi yerde) da garanti altına alınıyor — yukarı akıştaki
    // hiçbir adım bunu artık atlayamaz.
    if (tablo == 'kredi_kartlari') {
      final knm = m['kart_no_maskeli'];
      if (knm == null || (knm is String && knm.isEmpty)) {
        m['kart_no_maskeli'] = '**** **** **** ????';
      }
    }

    // 🔥 URUNLER için NOT NULL sütunları doldur
    if (tablo == 'urunler') {
      m['alis_fiyat'] ??= 0.0;
      m['alis_fiyat_kdv_dahil'] ??= 0.0;
      m['satis_fiyati'] ??= 0.0;
      m['stok'] ??= 0.0;
      m['toplam_maliyet'] ??= 0.0;
      m['toplam_stok'] ??= 0.0;
      m['alis_kdv_oran'] ??= 18.0;
      m['kdv_oran'] ??= '18';
      m['aktif'] ??= 1;
      m['seri_no_takibi'] ??= 0;
      m['lot_takibi'] ??= 0;
      m['indirim_orani'] ??= 0.0;
      m['otomatik_indirim'] ??= 0;
      m['son_alim_indirim_oran'] ??= 0.0;
      m['minimum_stok'] ??= 0.0;
      m['maksimum_stok'] ??= 0.0;
      m['maksimum_satir_miktari'] ??= 0.0;
      m['raf_omru'] ??= 0;
      m['plu'] ??= 0;
      m['plu_kart_boyut'] ??= 2;
      m['puan_orani'] ??= 0.0;
      m['en'] ??= 0.0;
      m['boy'] ??= 0.0;
      m['yukseklik'] ??= 0.0;
      m['agirlik'] ??= 0.0;
      m['is_deleted'] ??= 0;
      m['indirimli_fiyat'] ??= 0.0;
      m['hacim'] ??= 0.0;
      m['evrak_kontrol_aktif'] ??= 0;
      m['promosyon_aktif'] ??= 0;
      m['recete_katsayi'] ??= 1.0;
      m['net_alis_fiyat'] ??= 0.0;
      if (m['urun_adi'] == null || m['urun_adi'].toString().isEmpty) {
        m['urun_adi'] = 'Bilinmeyen Ürün';
      }
      if (m['birim_adi'] == null || m['birim_adi'].toString().isEmpty) {
        m['birim_adi'] = 'Adet';
      }
    }

    // Boolean dönüşümü
    final skipBool = _skipBoolDonusum.contains(tablo);
    for (final k in m.keys.toList()) {
      final v = m[k];
      if (!skipBool && v is int && _boolAlanlar.contains(k)) {
        m[k] = v == 1;
      }
    }

    // global_id kontrolü
    if (_globalIdVar.contains(tablo)) {
      if (m['global_id'] == null || m['global_id'].toString().isEmpty) {
        m['global_id'] = const Uuid().v4();
      }
    } else {
      m.remove('global_id');
    }

    // last_updated kontrolü
    if (_lastUpdatedVar.contains(tablo)) {
      m['last_updated'] ??= now;
    } else {
      m.remove('last_updated');
    }

    // cihaz_id kontrolü
    if (m.containsKey('cihaz_id')) {
      m['cihaz_id'] ??= cId;
    }

    // NULL değerleri JSON'dan çıkar
    m.removeWhere((_, v) => v == null);

    return m;
  }

  /// Batch içindeki tüm kayıtların aynı anahtarlara sahip olmasını sağlar.
  static List<Map<String, dynamic>> _normalizeBatch(List<Map<String, dynamic>> veriler) {
    if (veriler.isEmpty) return veriler;
    final allKeys = <String>{};
    for (final v in veriler) {
      allKeys.addAll(v.keys);
    }
    final normalized = <Map<String, dynamic>>[];
    for (final v in veriler) {
      final newMap = <String, dynamic>{};
      for (final key in allKeys) {
        newMap[key] = v[key];
      }
      normalized.add(newMap);
    }
    return normalized;
  }

  // --------------------------------------------------------------
  // BAĞLANTI TESTİ
  // --------------------------------------------------------------
  static Future<BaglantiSonuc> baglantiTest({String? url, String? key}) async {
    try {
      _Ayar ayar;
      if (url != null && key != null) {
        final temiz = url.trim()
            .replaceAll(RegExp(r'/rest/v1/?$'), '')
            .replaceAll(RegExp(r'/$'), '');
        ayar = _Ayar(url: temiz, key: key.trim());
      } else {
        final a = await _ayarGetir();
        if (a == null) return BaglantiSonuc(false, 'Bağlantı bilgileri girilmemiş');
        ayar = a;
      }
      final res = await http.get(
        Uri.parse('${ayar.rest}/urunler?limit=1&select=id'),
        headers: _getH(ayar.key),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return BaglantiSonuc(true, 'Bağlantı başarılı ✓');
      if (res.statusCode == 401) return BaglantiSonuc(false, 'API Key hatalı (401)');
      if (res.statusCode == 403) return BaglantiSonuc(false, 'Erişim reddedildi (403) — RLS kapatın');
      return BaglantiSonuc(false,
          'HTTP ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 100))}');
    } catch (e) {
      return BaglantiSonuc(false, 'Bağlanamadı: $e');
    }
  }

  // --------------------------------------------------------------
  // BULUTA GÖNDER
  // --------------------------------------------------------------
  /// Kullanıcı sorusu: "2 cihaz aynı kaydı değiştirirse ne olur?" —
  /// ÖNCEDEN bu kontrol hiç yoktu, "kim bulut'a son ulaşırsa o kazanır"
  /// mantığıydı (ağ gecikmesine bağlı, YANLIŞ olabilirdi). Artık
  /// göndermeden önce bulut'taki güncel last_updated değerleri
  /// çekiliyor; bulut'ta ZATEN daha yeni bir sürüm varsa o kayıt
  /// listeden çıkarılıyor (üzerine yazılmıyor) — gerçekten en son
  /// düzenlenen sürüm kazanıyor, ağ zamanlaması değil.
  static Future<List<Map<String, dynamic>>> _cakismaFiltrele(
    _Ayar ayar,
    String tablo,
    List<Map<String, dynamic>> batch,
    String uniqueAlan,
  ) async {
    final gidler = batch
        .map((r) => r[uniqueAlan]?.toString())
        .where((g) => g != null && g.isNotEmpty)
        .toSet();
    if (gidler.isEmpty) return batch;

    try {
      final gidListesi = gidler.map((g) => '"$g"').join(',');
      final res = await http.get(
        Uri.parse('${ayar.rest}/$tablo?select=$uniqueAlan,last_updated'
            '&$uniqueAlan=in.($gidListesi)'),
        headers: _getH(ayar.key),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return batch; // sorgu başarısızsa güvenli tarafta kal, eskisi gibi gönder

      final buluttakiler = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      final bulutZamanlari = <String, DateTime>{};
      for (final b in buluttakiler) {
        final gid = b[uniqueAlan]?.toString();
        final lu = b['last_updated']?.toString();
        if (gid != null && lu != null) {
          final t = DateTime.tryParse(lu);
          if (t != null) bulutZamanlari[gid] = t;
        }
      }

      return batch.where((r) {
        final gid = r[uniqueAlan]?.toString();
        final yerelLu = r['last_updated']?.toString();
        if (gid == null || yerelLu == null) return true; // bilgi eksikse eskisi gibi gönder
        final bulutZamani = bulutZamanlari[gid];
        if (bulutZamani == null) return true; // bulut'ta hiç yoksa gönder
        final yerelZamani = DateTime.tryParse(yerelLu);
        if (yerelZamani == null) return true;
        // Bulut ZATEN daha yeni ya da eşitse GÖNDERME (üzerine yazma).
        return yerelZamani.isAfter(bulutZamani);
      }).toList();
    } catch (_) {
      return batch; // kontrol başarısız olursa eski (güvenli) davranışa dön
    }
  }

  static Future<SyncSonuc> bulutaGonder({
    required Future<List<Map<String, dynamic>>> Function(String, bool) veriGetir,
    void Function(String)? log,
    // Delta sync: true ise sadece son senkronizasyondan bu yana
    // değişen kayıtlar gönderilir — çok daha hızlı çalışır.
    // false ise TÜM kayıtlar gönderilir (ilk kurulum için).
    bool sadeceDegisenler = true,
  }) async {
    final ayar = await _ayarGetir();
    if (ayar == null) {
      return SyncSonuc()..hatalar.add('Bağlantı bilgileri yok');
    }

    final cId  = await cihazId();
    final now  = DateTime.now().toUtc().toIso8601String();
    final sonuc = SyncSonuc();

    // 🔴 KRİTİK DÜZELTME (FK remap — GÖNDERME yönü): Önceden çocuk
    // tabloların FK kolonları (satis_kalem.satis_id, masa_siparis_kalem
    // .siparis_id vb.) buluta LOKAL id olarak gidiyordu. Buluttaki
    // BIGSERIAL id'ler lokal id'lerle alakasız olduğundan, indiren
    // cihaz (indirme yönündeki remap bu değeri "bulut id" sanır) kalemi
    // YANLIŞ parent'a bağlayabiliyordu — tek cihaz + boş buluttan
    // başlanmışsa sayılar şans eseri hizalı gittiği için fark
    // edilmiyordu, silme/ikinci cihaz girince sessizce bozuluyordu.
    // Artık gönderim öncesi: lokal_id → (lokal global_id) →
    // (buluttaki id) dönüşümü yapılıyor. Parent tablolar _tabloSirasi
    // gereği çocuklardan ÖNCE gönderildiği için, parent gönderimi
    // sonrası cache tazelenerek yeni eklenen parent'ların bulut id'leri
    // de görülebiliyor.
    final gidCloudCache = <String, Map<String, int>>{};   // parent → {gid: cloudId}
    final lokalGidCache = <String, Map<int, String>>{};   // parent → {lokalId: gid}
    final fkParentlar = _fkHaritasi.values
        .expand((m) => m.values)
        .toSet();

    for (final tablo in _tabloSirasi) {
      try {
        log?.call('📤 $tablo...');
        // Delta sync: sadeceDegisenler=true ise sadece son
        // senkronizasyondan bu yana değişen kayıtları gönder.
        DateTime? sonSenkronZamani;
        if (sadeceDegisenler && _lastUpdatedVar.contains(tablo)) {
          sonSenkronZamani = await _sonSenkron(tablo, 'gonder');
        }
        List<Map<String, dynamic>> rows = await veriGetir(tablo, _softDelete.contains(tablo));
        if (sonSenkronZamani != null) {
          rows = rows.where((r) {
            final lu = r['last_updated'];
            if (lu == null) return true;
            final luDate = lu is DateTime ? lu : DateTime.tryParse(lu.toString());
            return luDate != null && luDate.isAfter(sonSenkronZamani!);
          }).toList();
        }
        if (rows.isEmpty) { log?.call('   boş/değişim yok'); continue; }

        // sqflite sorgu sonuçları SALT-OKUNUR map'lerdir — hem backfill
        // hem sonraki adımlar için değiştirilebilir kopyaya çevriliyor.
        rows = rows.map((r) => Map<String, dynamic>.from(r)).toList();

        // Görünürlük: kullanıcı "stok_hareket'te 10 dakikadır bekliyor"
        // bildirdi ama loglar tablo İÇİ aşamaları göstermiyordu (tek
        // batch'lik küçük tablolarda ⏳ ilerleme logu da devreye
        // girmiyor). Artık her aşama loglanıyor — takılma olursa TAM
        // yeri anında görülür.
        log?.call('▶ $tablo: ${rows.length} kayıt hazırlanıyor...');

        // 🔴🔴 KÖK NEDEN DÜZELTMESİ (bulut şişmesi / id=12504 kanıtı):
        // Bazı tabloların (özellikle stok_hareket) lokal insert'lerinde
        // global_id HİÇ atanmıyordu. _hazirla, boş global_id'ye her
        // sync'te YENİ bir Uuid üretiyordu ama bunu LOKALE GERİ
        // YAZMIYORDU → aynı kayıt her gönderimde FARKLI kimlikle
        // gidiyor, on_conflict hiç eşleşmiyor, bulut her sync'te
        // ÇOĞALIYORDU (kullanıcının bulutunda 50 lokal kayda karşılık
        // id 12504'e ulaşmış satırlar!). Ayrıca last_updated de boş
        // olduğundan delta filtresi bu tabloda hiç çalışmıyor, her
        // sync TÜM kayıtları gönderiyordu. Artık: gönderimden önce
        // boş global_id'lere KALICI kimlik üretilip lokale yazılıyor
        // (bundan sonra hep aynı kimlikle gider), boş last_updated'e
        // tek seferlik damga vuruluyor (delta çalışır hale gelir).
        final uniqueAlanOnKontrol = _uniqueAlan[tablo];
        if (uniqueAlanOnKontrol == 'global_id') {
          final localDb = await Veritabani().db;
          // Önce kimlik/damga eksik kayıtları tespit et (bellekte, hızlı)
          final eksikler = <Map<String, dynamic>>[];
          for (final r in rows) {
            final gidBos = r['global_id'] == null ||
                r['global_id'].toString().isEmpty;
            final luBos = r['last_updated'] == null;
            if ((gidBos || luBos) && r['id'] != null) {
              if (gidBos) r['global_id'] = const Uuid().v4();
              if (luBos) r['last_updated'] = now;
              eksikler.add(r);
            }
          }
          if (eksikler.isNotEmpty) {
            log?.call('   ↳ ${eksikler.length} kayda kalıcı kimlik atanıyor (tek seferlik)...');
            final b = localDb.batch();
            for (final r in eksikler) {
              b.update(tablo,
                  {'global_id': r['global_id'], 'last_updated': r['last_updated']},
                  where: 'id = ?', whereArgs: [r['id']]);
            }
            var kalici = false;
            try {
              await b.commit(noResult: true);
              // 🔴 ÇELİK KORUMA — kalıcılık DOĞRULAMASI: Kullanıcının
              // bulutunda "kimliksiz=0, mükerrer=0 ama toplam sürekli
              // artıyor" görüldü — yani kayıtlar her turda YENİ
              // kimliklerle gidiyordu (kimlikler lokale kalıcı
              // OLMUYORDU). Artık yazımdan sonra örnek bir kayıt geri
              // OKUNARAK doğrulanıyor; kalıcı değilse bu tablo BU
              // TURDA GÖNDERİLMEZ (kalıcı olmayan kimlikle göndermek =
              // bulutta bir daha eşleşmeyecek satır = şişme).
              final kontrol = await localDb.query(tablo,
                  columns: ['global_id'],
                  where: 'id = ?', whereArgs: [eksikler.first['id']], limit: 1);
              kalici = kontrol.isNotEmpty &&
                  kontrol.first['global_id'] == eksikler.first['global_id'];
            } catch (_) {
              kalici = false;
            }
            if (kalici) {
              log?.call('   ↳ kimlik ataması tamam ✓ (kalıcılık doğrulandı)');
            } else {
              final hata = '❌ $tablo: kimlik ataması LOKALE YAZILAMADI — '
                  'bulut şişmesin diye bu tablo BU TURDA ATLANDI';
              sonuc.hatalar.add(hata);
              log?.call(hata);
              continue; // tabloyu gönderme!
            }
          }
        }


        final veriler = rows
            .map((r) => _hazirla(r, tablo, cId, now))
            .toList();

        // FK remap (lokal id → bulut id) — açıklama için döngü
        // öncesindeki 🔴 nota bakın.
        final fkMap = _fkHaritasi[tablo];
        if (fkMap != null) {
          log?.call('   ↳ ilişki (FK) dönüşümü...');
          final fkBaslangic = DateTime.now();
          await _fkLocalToCloudDonustur(
              ayar, tablo, veriler, fkMap, gidCloudCache, lokalGidCache, log);
          final fkSure = DateTime.now().difference(fkBaslangic).inSeconds;
          if (fkSure > 3) log?.call('   ↳ FK dönüşümü ${fkSure} sn sürdü');
        }

        final uniqueAlan = _uniqueAlan[tablo];
        int atlandi = 0;

        if (uniqueAlan != null) {
          int basarili = 0;
          int batchHatasi = 0;
          const batchSize = 100;
          final toplamBatch = (veriler.length / batchSize).ceil();
          for (int i = 0; i < veriler.length; i += batchSize) {
            var batch = veriler.sublist(i, (i + batchSize).clamp(0, veriler.length));
            final oncekiBoyut = batch.length;
            final batchNo = (i ~/ batchSize) + 1;

            // 🔴 KULLANICI GERİ BİLDİRİMİ ("stok hareketlere geliyor,
            // orada bekliyor"): Büyük tablolarda (stok_hareket en
            // kalabalık tablodur — her satış kalemi bir hareket üretir)
            // yüzlerce batch dakikalarca sürüyor ama tablo BİTENE KADAR
            // hiç log yazılmıyordu — kullanıcı donduğunu sanıyordu.
            // Artık her 5 batch'te canlı ilerleme gösteriliyor.
            if (toplamBatch > 5 && (batchNo == 1 || batchNo % 5 == 0)) {
              log?.call('⏳ $tablo: ${(i + batch.length).clamp(0, veriler.length)}'
                  '/${veriler.length} işleniyor...');
            }

            try {
              // ÖNCEDEN BURADA CİDDİ BİR ÇAKIŞMA (CONFLICT) HATASI VARDI:
              // iki cihaz AYNI kaydı neredeyse aynı anda değiştirirse,
              // hangi cihazın isteği bulut'a DAHA SONRA ULAŞIRSA o
              // kazanıyordu. Artık göndermeden ÖNCE bulut'taki mevcut
              // last_updated değerleri kontrol ediliyor; bulut'ta ZATEN
              // daha yeni bir kayıt varsa gönderilmiyor.
              batch = await _cakismaFiltrele(ayar, tablo, batch, uniqueAlan);
              atlandi += oncekiBoyut - batch.length;
              if (batch.isEmpty) continue;

              final normalizedBatch = _normalizeBatch(batch);
              // 🔴🔴🔴 KESİN KÖK NEDEN (GitHub supabase-js #1653'te
              // resmi olarak doğrulandı — "DEFAULT is not allowed in
              // this context", 42601): `columns` URL parametresi
              // belirtilmezse PostgREST, payload'da olmayan sütunları
              // da işleme dahil etmeye çalışıp "DEFAULT" anahtar
              // kelimesini kullanmaya çalışıyor — bu bazı bağlamlarda
              // sözdizimi hatası veriyor. normalizedBatch zaten TÜM
              // kayıtları AYNI anahtar kümesine sahip hâle getirdiği
              // için, ilk kaydın anahtarları columns listesi olarak
              // kullanılabilir.
              final sutunlar = normalizedBatch.isNotEmpty
                  ? normalizedBatch.first.keys.map(Uri.encodeComponent).join(',')
                  : '';
              // on_conflict=$uniqueAlan ile gerçek UPSERT (bkz. önceki
              // düzeltme notları).
              //
              // 🔴 YENİ — YENİDEN DENEME + HATA İZOLASYONU: Önceden bir
              // batch'te ağ kopması (ClientException/Timeout) olursa
              // exception TÜM TABLONUN kalan batch'lerini iptal ediyordu
              // → bir sonraki sync aynı dev yükü BAŞTAN deniyordu →
              // zayıf bağlantıda tablo asla bitmiyordu (kullanıcının
              // loglarındaki "Software caused connection abort" döngüsü).
              // Artık: her batch 2 kez denenir (arada 2 sn bekleyerek);
              // yine de başarısızsa YALNIZCA o batch hata sayılır,
              // SONRAKİ batch'ler devam eder. Kısmi ilerleme KALICIDIR:
              // bir sonraki sync'te _cakismaFiltrele, zaten gönderilmiş
              // kayıtları (bulut last_updated artık >= yerel olduğu
              // için) otomatik eler ve kaldığı yerden hızla devam eder.
              http.Response? res;
              for (int deneme = 1; deneme <= 2; deneme++) {
                try {
                  res = await http.post(
                    Uri.parse('${ayar.rest}/$tablo?on_conflict=$uniqueAlan&columns=$sutunlar'),
                    headers: _upsertH(ayar.key),
                    body: jsonEncode(normalizedBatch),
                  ).timeout(const Duration(seconds: 30));
                  break;
                } catch (e) {
                  if (deneme == 2) rethrow;
                  log?.call('🔄 $tablo: bağlantı koptu, yeniden deneniyor...');
                  await Future.delayed(const Duration(seconds: 2));
                }
              }

              if (res!.statusCode >= 200 && res.statusCode < 300) {
                basarili += batch.length;
              } else {
                batchHatasi++;
                final hata = '❌ $tablo UPSERT ${res.statusCode}: '
                    '${res.body.substring(0, res.body.length.clamp(0, 200))}';
                sonuc.hatalar.add(hata);
                log?.call(hata);
              }
            } catch (e) {
              batchHatasi++;
              final hata = '❌ $tablo batch $batchNo/$toplamBatch: $e';
              sonuc.hatalar.add(hata);
              log?.call(hata);
              // devam — sonraki batch'ler denensin
            }
          }
          sonuc.eklenen[tablo] = basarili;
          // Delta güvenliği: tabloda EN AZ BİR batch hata aldıysa
          // senkron zamanı GÜNCELLENMEZ — gönderilemeyen kayıtlar bir
          // sonraki delta'da yeniden yakalanır (gönderilmiş olanlar
          // _cakismaFiltrele sayesinde tekrar gönderilmez).
          if (batchHatasi == 0) {
            await _senkronKaydet(tablo, 'gonder');
          } else {
            log?.call('⚠️ $tablo: $batchHatasi batch gönderilemedi — '
                'bir sonraki senkronda kaldığı yerden devam edilecek');
          }
        } else {
          int basarili = 0;
          int kayitHatasi = 0;
          for (final kayit in veriler) {
            // Kayıt bazlı hata izolasyonu — tek kaydın ağ hatası tüm
            // tabloyu (ve delta ilerlemesini) düşürmesin.
            try {
              final res = await http.post(
                Uri.parse('${ayar.rest}/$tablo'),
                headers: _insertH(ayar.key),
                body: jsonEncode(kayit),
              ).timeout(const Duration(seconds: 15));

              if (res.statusCode >= 200 && res.statusCode < 300) {
                basarili++;
              } else if (res.statusCode == 409) {
                basarili++; // insert-only log tablosunda 409 = zaten var
              } else {
                kayitHatasi++;
                sonuc.hatalar.add('❌ $tablo INSERT ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 150))}');
              }
            } catch (e) {
              kayitHatasi++;
              sonuc.hatalar.add('❌ $tablo INSERT: $e');
            }
            await Future.delayed(const Duration(milliseconds: 5));
          }
          sonuc.eklenen[tablo] = basarili;
          // Delta güvenliği (üstteki upsert dalıyla aynı mantık)
          if (kayitHatasi == 0) {
            await _senkronKaydet(tablo, 'gonder');
          } else {
            log?.call('⚠️ $tablo: $kayitHatasi kayıt gönderilemedi — '
                'bir sonraki senkronda yeniden denenecek');
          }
        }

        // NOT: _senkronKaydet artık YUKARIDA, her dalın kendi içinde ve
        // YALNIZCA tablo hatasız bittiyse çağrılıyor — önceden burada
        // koşulsuz çağrılıyordu, bu da hatalı tabloda bile senkron
        // zamanını güncelleyip GÖNDERİLEMEYEN kayıtların bir sonraki
        // delta'nın dışında kalmasına (sessiz veri kaybına) yol açardı.
        // Bu tablo başka tabloların FK parent'ıysa, bulut id cache'ini
        // temizle — az önce eklenen YENİ kayıtların bulut id'leri,
        // sonraki (çocuk) tablo işlenirken taze çekilebilsin.
        if (fkParentlar.contains(tablo)) {
          gidCloudCache.remove(tablo);
          lokalGidCache.remove(tablo);
        }
        log?.call('✅ $tablo: ${sonuc.eklenen[tablo]} gönderildi'
            '${atlandi > 0 ? " ($atlandi bulut\'ta daha güncel olduğu için atlandı)" : ""}');
      } catch (e) {
        final hata = '❌ $tablo: $e';
        sonuc.hatalar.add(hata);
        log?.call(hata);
      }
    }

    log?.call('────────────────────────');
    log?.call('📊 ${sonuc.ozet}');
    return sonuc;
  }

  // --------------------------------------------------------------
  // FK DÖNÜŞÜMÜ — GÖNDERME YÖNÜ (lokal id → bulut id)
  // --------------------------------------------------------------
  /// Tek bir bulut tablosunun (global_id → bulut id) eşlemesini çeker.
  static Future<Map<String, int>> _tekTabloGidCloud(
      _Ayar ayar, String tablo) async {
    final gidToCloud = <String, int>{};
    int offset = 0;
    // Güvenlik sınırı: sayfalama hiçbir koşulda 200 turdan
    // (200.000 kayıt) fazla dönemez — uç durumlarda (sunucunun
    // beklenmedik yanıtı) sonsuz döngüyü fiziksel olarak engeller.
    int guvenlikSayaci1 = 0;
    while (guvenlikSayaci1++ < 200) {
      final res = await http.get(
        Uri.parse('${ayar.rest}/$tablo?select=id,global_id&limit=1000&offset=$offset'),
        headers: _getH(ayar.key),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) break;
      final batch = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      if (batch.isEmpty) break;
      for (final r in batch) {
        final gid = r['global_id']?.toString();
        final cid = r['id'];
        if (gid != null && gid.isNotEmpty && cid != null) {
          gidToCloud[gid] = cid is int ? cid : int.parse(cid.toString());
        }
      }
      if (batch.length < 1000) break;
      offset += 1000;
    }
    return gidToCloud;
  }

  /// Gönderilecek kayıtlardaki FK kolonlarını (lokal id) → (bulut id)
  /// olarak dönüştürür. Zincir: lokal id → lokal global_id → bulut id.
  /// Eşleşme bulunamazsa kolon OLDUĞU GİBİ bırakılır (eski davranış)
  /// ve log'a uyarı yazılır — parent bir sonraki senkronda buluta
  /// gidince, çocuk kaydın bir sonraki güncellemesi doğru id'yi yazar.
  static Future<void> _fkLocalToCloudDonustur(
    _Ayar ayar,
    String tablo,
    List<Map<String, dynamic>> veriler,
    Map<String, String> fkMap,
    Map<String, Map<String, int>> gidCloudCache,
    Map<String, Map<int, String>> lokalGidCache,
    void Function(String)? log,
  ) async {
    final localDb = await Veritabani().db;
    for (final entry in fkMap.entries) {
      final kolon = entry.key, parent = entry.value;
      try {
        // 1) Lokal: id → global_id (cache'li)
        if (lokalGidCache[parent] == null) {
          final rows = await localDb.query(parent, columns: ['id', 'global_id']);
          final h = <int, String>{};
          for (final r in rows) {
            final id = r['id'] as int?;
            final gid = r['global_id']?.toString();
            if (id != null && gid != null && gid.isNotEmpty) h[id] = gid;
          }
          lokalGidCache[parent] = h;
        }
        // 2) Bulut: global_id → bulut id (cache'li)
        if (gidCloudCache[parent] == null) {
          log?.call('   ↳ $parent bulut haritası çekiliyor...');
          gidCloudCache[parent] = await _tekTabloGidCloud(ayar, parent);
          log?.call('   ↳ $parent haritası hazır (${gidCloudCache[parent]!.length} kayıt)');
        }

        final lokalGid = lokalGidCache[parent]!;
        final gidCloud = gidCloudCache[parent]!;
        int bulunamadi = 0;
        for (final m in veriler) {
          final v = m[kolon];
          if (v == null) continue;
          final lid = v is int ? v : int.tryParse(v.toString());
          if (lid == null) continue;
          final gid = lokalGid[lid];
          final cid = gid != null ? gidCloud[gid] : null;
          if (cid != null) {
            m[kolon] = cid;
          } else {
            bulunamadi++;
          }
        }
        if (bulunamadi > 0) {
          log?.call('⚠️ $tablo.$kolon: $bulunamadi kayıtta $parent bulut '
              'eşleşmesi bulunamadı (lokal değer korundu)');
        }
      } catch (e) {
        log?.call('⚠️ $tablo.$kolon FK dönüşümü atlandı: $e');
      }
    }
  }

  // --------------------------------------------------------------
  // ID HARİTASI (FK DÖNÜŞÜM İÇİN)
  // --------------------------------------------------------------
  /// Bulut'taki (global_id -> cloud_id) eşlemesini TEK SEFER çeker —
  /// bu, senkronizasyon boyunca değişmez, tekrar tekrar çekmeye gerek
  /// yok. Yerel eşleme (cloud_id -> local_id) ise AYRI tutuluyor çünkü
  /// bu, her tablo eklendikçe DEĞİŞİR (bkz. _idHaritasiTabloGuncelle).
  static Future<Map<String, Map<String, int>>> _bulutGidHaritasiCek(
      _Ayar ayar, {void Function(String)? log}) async {
    final sonuc = <String, Map<String, int>>{};
    for (final tablo in _idHaritasiKurulacakTablolar) {
      try {
        final gidToCloud = <String, int>{};
        int offset = 0;
        // Güvenlik sınırı: sayfalama hiçbir koşulda 200 turdan
        // (200.000 kayıt) fazla dönemez — uç durumlarda (sunucunun
        // beklenmedik yanıtı) sonsuz döngüyü fiziksel olarak engeller.
        int guvenlikSayaci2 = 0;
        while (guvenlikSayaci2++ < 200) {
          final res = await http.get(
            Uri.parse('${ayar.rest}/$tablo?select=id,global_id&limit=1000&offset=$offset'),
            headers: _getH(ayar.key),
          ).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) break;
          final batch = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
          if (batch.isEmpty) break;
          for (final r in batch) {
            final gid = r['global_id']?.toString();
            final cid = r['id'];
            if (gid != null && gid.isNotEmpty && cid != null) {
              gidToCloud[gid] = cid is int ? cid : int.parse(cid.toString());
            }
          }
          if (batch.length < 1000) break;
          offset += 1000;
        }
        sonuc[tablo] = gidToCloud;
      } catch (e) {
        log?.call('⚠️ $tablo bulut id listesi çekilemedi: $e');
      }
    }
    return sonuc;
  }

  /// 🔴🔴🔴 KULLANICI TARAFINDAN BULUNAN, GERÇEK BİR HATA: ÖNCEDEN ID
  /// haritası (cloud_id -> local_id) senkronizasyonun EN BAŞINDA, TEK
  /// SEFER kuruluyordu. Ama bir satış Cihaz A için YENİYSE (Cihaz A'da
  /// hiç yoksa), harita kurulduğu anda o satış henüz yerelde
  /// olmadığı için haritada YER ALAMIYORDU. Sonra satış eklenirdi
  /// (yeni bir yerel id alırdı), AMA satis_kalem işlenirken hâlâ ESKİ
  /// (o satışı içermeyen) harita kullanıldığı için, `localId` hiç
  /// bulunamıyor, kod da 'satis_id' alanını TAMAMEN SİLİYORDU —
  /// kalem hiçbir satışa bağlı olmadan "havada" kalıyor, kullanıcı
  /// "sadece tutar geliyor, ürünler gelmiyor" diye bunu fark etti. Bu
  /// fonksiyon, TEK BİR tablonun yerel eşlemesini, o tablonun kayıtları
  /// eklendikten HEMEN SONRA tazeler.
  static Future<void> _idHaritasiTabloGuncelle(
    String tablo,
    Map<String, Map<String, int>> bulutGidHaritasi,
    Map<String, Map<int, int>> idHaritasi,
  ) async {
    if (!_idHaritasiKurulacakTablolar.contains(tablo)) return;
    final gidToCloud = bulutGidHaritasi[tablo];
    if (gidToCloud == null || gidToCloud.isEmpty) return;
    try {
      final localDb = await Veritabani().db;
      final localRows = await localDb.query(tablo, columns: ['id', 'global_id']);
      final harita = <int, int>{};
      for (final lr in localRows) {
        final gid = lr['global_id']?.toString();
        if (gid == null) continue;
        final cloudId = gidToCloud[gid];
        final localId = lr['id'] as int?;
        if (cloudId != null && localId != null) harita[cloudId] = localId;
      }
      idHaritasi[tablo] = harita;
    } catch (_) {
      // Sessizce geç — bir sonraki genel senkronizasyonda düzelir
    }
  }

  static Future<Map<String, Map<int, int>>> _idHaritasiOlustur(
      _Ayar ayar, {void Function(String)? log}) async {
    final sonuc = <String, Map<int, int>>{};
    final localDb = await Veritabani().db;

    for (final tablo in _idHaritasiKurulacakTablolar) {
      try {
        final gidToCloud = <String, int>{};
        int offset = 0;
        // Güvenlik sınırı: sayfalama hiçbir koşulda 200 turdan
        // (200.000 kayıt) fazla dönemez — uç durumlarda (sunucunun
        // beklenmedik yanıtı) sonsuz döngüyü fiziksel olarak engeller.
        int guvenlikSayaci3 = 0;
        while (guvenlikSayaci3++ < 200) {
          final res = await http.get(
            Uri.parse('${ayar.rest}/$tablo?select=id,global_id&limit=1000&offset=$offset'),
            headers: _getH(ayar.key),
          ).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) break;
          final batch = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
          if (batch.isEmpty) break;
          for (final r in batch) {
            final gid = r['global_id']?.toString();
            final cid = r['id'];
            if (gid != null && gid.isNotEmpty && cid != null) {
              gidToCloud[gid] = cid is int ? cid : int.parse(cid.toString());
            }
          }
          if (batch.length < 1000) break;
          offset += 1000;
        }
        if (gidToCloud.isEmpty) continue;

        final localRows = await localDb.query(tablo, columns: ['id', 'global_id']);
        final harita = <int, int>{};
        for (final lr in localRows) {
          final gid = lr['global_id']?.toString();
          if (gid == null) continue;
          final cloudId = gidToCloud[gid];
          final localId = lr['id'] as int?;
          if (cloudId != null && localId != null) harita[cloudId] = localId;
        }
        sonuc[tablo] = harita;
        log?.call('🔗 $tablo: ${harita.length} id eşleşti');
      } catch (e) {
        log?.call('⚠️ $tablo id haritası kurulamadı: $e');
      }
    }
    return sonuc;
  }

  // --------------------------------------------------------------
  // BULUTTAN AL
  // --------------------------------------------------------------

  // ══════════════════════════════════════════════════════════════════════
  // 🔴 KRİTİK DÜZELTME — BULUT/YEREL SÜTUN KAYMASI KORUMASI
  //
  // SORUN: buluttanAl(), bulut satırını OLDUĞU GİBİ yerel tabloya
  // yazıyordu. Bulutta olup yerelde OLMAYAN bir sütun varsa SQLite
  // "no such column" fırlatıyor ve o tablonun TÜM partisi düşüyordu.
  //
  // Gerçek örnek (derin analizde bulundu): `_lastUpdatedVar` listesi
  // 8 tabloda 'last_updated' olduğunu varsayıyor ama yerel şemada bu
  // sütun HİÇ YOK (ne CREATE'te ne migrasyonda):
  //   fiyat_gecmis, irsaliye_kalem, promosyon_aksiyon, promosyon_kosul,
  //   rol_yetkileri, zaman_fiyat
  //   (+ garson_cagri_log, masa_hareket_log → taze kurulumda yok)
  // Gönderirken kod bu sütunu ekliyor, bulut saklıyor, ÇEKERKEN yerel
  // tablo kabul etmiyor → "Hızlı Al"/"Tam Al" bu 8 tabloda hiç
  // çalışmıyordu (hata log'a düşüyor ama sonuç kartı yeşil görünüyor).
  //
  // ÇÖZÜM: yerel tablonun GERÇEK sütunları PRAGMA ile okunup, bulut
  // satırındaki fazlalıklar atılıyor. Bu, gelecekteki her bulut/yerel
  // kayması için de kalıcı koruma sağlar.
  // ══════════════════════════════════════════════════════════════════════
  static final Map<String, Set<String>> _yerelKolonOnbellek = {};

  static Future<Set<String>> _yerelKolonlar(dynamic localDb, String tablo) async {
    final onbellek = _yerelKolonOnbellek[tablo];
    if (onbellek != null) return onbellek;
    try {
      final rows = await localDb.rawQuery('PRAGMA table_info($tablo)');
      final k = rows
          .map<String>((r) => (r['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();
      _yerelKolonOnbellek[tablo] = k;
      return k;
    } catch (_) {
      // PRAGMA okunamadıysa filtreleme yapma (eski davranış)
      return <String>{};
    }
  }

  static final Map<String, Set<String>> _yerelZorunluKolonOnbellek = {};

  /// Hangi yerel sütunların NOT NULL olduğunu döner (PRAGMA table_info'nun
  /// 'notnull' alanı). FK çözümlenemediğinde: sütun ZORUNLU değilse sadece
  /// o sütunu at (eski davranış); ZORUNLU ise satırın TAMAMINI atla —
  /// aksi halde NOT NULL ihlali tüm toplu ekleme işlemini (batch) kırar.
  static Future<Set<String>> _yerelZorunluKolonlar(dynamic localDb, String tablo) async {
    final onbellek = _yerelZorunluKolonOnbellek[tablo];
    if (onbellek != null) return onbellek;
    try {
      final rows = await localDb.rawQuery('PRAGMA table_info($tablo)');
      final k = rows
          .where((r) => (r['notnull'] as int? ?? 0) == 1 && (r['dflt_value']) == null)
          .map<String>((r) => (r['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();
      _yerelZorunluKolonOnbellek[tablo] = k;
      return k;
    } catch (_) {
      return <String>{};
    }
  }

  static Future<SyncSonuc> buluttanAl({
    required Future<void> Function(String, List<Map<String, dynamic>>) kayitEkle,
    required Future<void> Function(String, List<Map<String, dynamic>>) kayitGuncelle,
    bool sadeceDegisenler = true,
    void Function(String)? log,
  }) async {
    final ayar = await _ayarGetir();
    if (ayar == null) {
      return SyncSonuc()..hatalar.add('Bağlantı bilgileri yok');
    }

    final sonuc = SyncSonuc();
    // Bulut'taki global_id->cloud_id eşlemesi TEK SEFER çekiliyor
    // (değişmez), ama YEREL eşleme (idHaritasi) artık MUTABLE — her
    // tablo işlendikçe TAZELENİYOR (bkz. _idHaritasiTabloGuncelle).
    final bulutGidHaritasi = await _bulutGidHaritasiCek(ayar, log: log);
    final idHaritasi = await _idHaritasiOlustur(ayar, log: log);

    for (final tablo in _tabloSirasi) {
      try {
        log?.call('📥 $tablo...');

        DateTime? sonSenkron;
        if (sadeceDegisenler && _lastUpdatedVar.contains(tablo)) {
          sonSenkron = await _sonSenkron(tablo, 'al');
        }

        final tumKayitlar = <Map<String, dynamic>>[];
        int offset = 0;

        // Güvenlik sınırı: sayfalama hiçbir koşulda 200 turdan
        // (200.000 kayıt) fazla dönemez — uç durumlarda (sunucunun
        // beklenmedik yanıtı) sonsuz döngüyü fiziksel olarak engeller.
        int guvenlikSayaci4 = 0;
        while (guvenlikSayaci4++ < 200) {
          var endpoint = '${ayar.rest}/$tablo?limit=500&offset=$offset';
          if (sonSenkron != null) {
            endpoint += '&last_updated=gt.'
                '${Uri.encodeComponent(sonSenkron.toUtc().toIso8601String())}';
            endpoint += '&order=last_updated.asc';
          }

          final res = await http
              .get(Uri.parse(endpoint), headers: _getH(ayar.key))
              .timeout(const Duration(seconds: 30));

          if (res.statusCode == 404) break;
          if (res.statusCode != 200) {
            if (res.statusCode != 406) {
              sonuc.hatalar.add('❌ $tablo GET ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 100))}');
            }
            break;
          }

          final batch = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
          if (batch.isEmpty) break;
          tumKayitlar.addAll(batch);
          if (batch.length < 500) break;
          offset += 500;
        }

        if (tumKayitlar.isEmpty) {
          log?.call('   değişiklik yok');
          await _senkronKaydet(tablo, 'al');
          continue;
        }

        final db      = Veritabani();
        final localDb = await db.db;
        final yeni    = <Map<String, dynamic>>[];
        final guncel  = <Map<String, dynamic>>[];

        final fkHaritasi = _fkHaritasi[tablo];

        // Yerel tablonun gerçek sütunları — bulut fazlalıklarını atmak için
        final yerelKolonSeti = await _yerelKolonlar(localDb, tablo);
        // 🔴 Derin analizde bulundu ("satış hareketleri buluttan tam
        // almada hatalı"): FK çözümlenemeyince sütun sessizce
        // atılıyordu. Sütun NOT NULL ise (ör. satis_kalem.urun_id,
        // satis_kalem.satis_id) bu, tüm satırı değil TEK bir alanı
        // eksik bırakıyor, INSERT NOT NULL ihlaliyle patlıyordu — ve
        // sqflite'ın toplu ekleme (batch) işlemi varsayılan olarak İLK
        // hatada durduğu için, tek bir çözülemeyen ürün/satış referansı
        // O TABLONUN TÜM "tam al" turunu (yüzlerce kayıt) iptal
        // ediyordu. Artık hangi sütunların zorunlu olduğu önceden
        // biliniyor.
        final zorunluKolonSeti = await _yerelZorunluKolonlar(localDb, tablo);

        for (final r in tumKayitlar) {
          final m = Map<String, dynamic>.from(r);
          m.remove('id');

          // 🔴 Bulutta olup yerelde OLMAYAN sütunları at.
          // (Boş set = PRAGMA okunamadı → filtreleme yapma.)
          if (yerelKolonSeti.isNotEmpty) {
            m.removeWhere((k, _) => !yerelKolonSeti.contains(k));
          }

          for (final k in m.keys.toList()) {
            if (m[k] is bool) m[k] = (m[k] as bool) ? 1 : 0;
            if (m[k] == null) m.remove(k);
          }

          var atlaSatir = false;
          if (fkHaritasi != null) {
            for (final entry in fkHaritasi.entries) {
              final kolon = entry.key, parentTablo = entry.value;
              final cloudVal = m[kolon];
              if (cloudVal == null) continue;
              final cloudId = cloudVal is int ? cloudVal : int.tryParse(cloudVal.toString());
              if (cloudId == null) continue;
              final localId = idHaritasi[parentTablo]?[cloudId];
              if (localId != null) {
                m[kolon] = localId;
              } else if (zorunluKolonSeti.contains(kolon)) {
                // Zorunlu bir FK çözülemedi — bu satırı ekleme, ama
                // TÜM tabloyu iptal ETME. (ör. ürünü silinmiş bir
                // satışın kalemi: o kalem atlanır, sipariş/satışın
                // geri kalanı ve tablonun diğer kayıtları kaybolmaz.)
                atlaSatir = true;
                break;
              } else {
                m.remove(kolon);
              }
            }
          }
          if (atlaSatir) continue;

          final gid = m['global_id']?.toString();
          if (gid != null && gid.isNotEmpty) {
            try {
              final existing = await localDb.query(
                tablo,
                where: 'global_id = ?',
                whereArgs: [gid],
                limit: 1,
              );
              if (existing.isNotEmpty) {
                if (_silinmisMi(tablo, m)) {
                  // 🔴 DÜZELTME: Önceden HER ZAMAN {'is_deleted': 1}
                  // yazılıyordu — 'deleted_at'/'aktif' kullanan
                  // tablolarda (faturalar, giderler, irsaliyeler,
                  // promosyonlar, markalar) bu ya YANLIŞ bir sütun
                  // yazmaya çalışırdı (SQL hatası) ya da hiçbir şey
                  // yapmazdı. Artık doğru sütun/değer kullanılıyor.
                  final kolon = _softDeleteKolonu[tablo]!;
                  final deger = kolon == 'aktif'
                      ? 0
                      : (kolon == 'deleted_at' ? (m['deleted_at'] ?? DateTime.now().toIso8601String()) : 1);
                  await localDb.update(tablo, {kolon: deger},
                      where: 'global_id = ?', whereArgs: [gid]);
                  sonuc.silinen[tablo] = (sonuc.silinen[tablo] ?? 0) + 1;
                } else {
                  guncel.add(m);
                }
              } else {
                if (!_silinmisMi(tablo, m)) {
                  yeni.add(m);
                }
              }
            } catch (_) {
              yeni.add(m);
            }
          } else {
            yeni.add(m);
          }
        }

        if (yeni.isNotEmpty) {
          await kayitEkle(tablo, yeni);
          sonuc.eklenen[tablo] = yeni.length;
        }
        if (guncel.isNotEmpty) {
          await kayitGuncelle(tablo, guncel);
          sonuc.guncellenen[tablo] = guncel.length;
        }

        // 🔴 KRİTİK: Bu tablo bir "ebeveyn" tablosuysa (cari, urunler,
        // satislar, iade, masalar), kayıtlar eklendikten HEMEN SONRA
        // ID haritası tazeleniyor — böylece bu tabloya bağımlı olan
        // SONRAKİ tablolar (ör. satis_kalem, satislar'a bağımlı),
        // BİRAZ ÖNCE eklenen YENİ kayıtların doğru yerel ID'sini
        // bulabiliyor. Önceden harita sadece başta kuruluyordu, bu
        // yüzden yeni satışların kalemleri "satis_id" alanını hiç
        // bulamayıp kayboluyordu.
        await _idHaritasiTabloGuncelle(tablo, bulutGidHaritasi, idHaritasi);

        log?.call('✅ $tablo: +${yeni.length} ~${guncel.length} -${sonuc.silinen[tablo] ?? 0}');
        // Filigran CİHAZ SAATİNDEN değil, çekilen verideki en büyük
        // last_updated'ten ilerletilir (saat kayması veri kaybı koruması)
        await _senkronKaydet(tablo, 'al', _enSonZaman(tumKayitlar));
      } catch (e) {
        final hata = '❌ $tablo: $e';
        sonuc.hatalar.add(hata);
        log?.call(hata);
      }
    }

    log?.call('────────────────────────');
    log?.call('📊 ${sonuc.ozet}');
    return sonuc;
  }
}