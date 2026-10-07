// lib/servisler/supabase_sync_sabitleri.dart
//
// supabase_sync_servisi.dart'ın parçası (part/part of) — senkron tablo sırası,
// global_id/last_updated/soft-delete/unique-alan haritaları ve gönderilmeyecek
// alan listesi. Önceden SupabaseSyncServisi içinde `static` sabitlerdi;
// değerler BİREBİR aynı, kütüphane düzeyinde private tanımlara taşındı
// (sınıf içinden aynı adla erişim değişmedi).
part of 'supabase_sync_servisi.dart';

const _tabloSirasi = [
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
  'satislar','satis_kalem',
  'iade','iade_kalem',
  'irsaliyeler','irsaliye_kalem',
  'promosyonlar','promosyon_tanim','promosyon_kosul','promosyon_aksiyon',
  'tedarikci_siparisler','tedarikci_siparis_kalem',
  // Tedarikçiye mal iadesi (v81) — cari ve urunler'e FK bağlı; onlardan sonra.
  'tedarikci_iadeler','tedarikci_iade_kalem',
  'giderler','faturalar','fatura_detaylari',
  // kasa_hareketleri cari_hareket'ten SONRA: referans_id'si satışa,
  // iadeye, gidere ve cari harekete işaret edebilir (polimorfik FK —
  // bkz. KolonHaritalama.polimorfikFkHaritasi); ebeveyn önce inmeli.
  'stok_hareket','cari_hareket','kasa_hareketleri','puan_hareket','personel',
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

  // 🔴 DÜZELTME (Supabase şema dosyası güncellenirken bulundu):
  // 'onay_talepleri' (Onay Merkezi, FAZ 9 — DB v57) BulutManager()
  // .upsert() ile sync_queue'ya düşüyordu ama bu listede HİÇ yoktu —
  // hem push hem pull tarafı _tabloSirasi üzerinden döndüğü için
  // kayıtlar asla buluta gitmiyor, diğer şube/cihazlarda görünmüyordu.
  // referans_id/referans_turu polimorfik (kolon_haritalama.dart'ta FK
  // hedefi yok) olduğu için sıra bağımsız, listenin sonuna eklendi.
  'onay_talepleri',

  // Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi FAZ 1
  // (2026-09-16, kullanıcı onaylı mimari plan raporu). 'donemler'
  // parent (diğer 6'sı ona FK ile bağlı) — en sonda eklenmesinin
  // sebebi, snapshot tablolarının bağımlı olduğu subeler/urunler/
  // cari/banka_hesaplar tabolarının bu noktada ZATEN senkron
  // edilmiş olması (yukarıdaki onay_talepleri ile aynı gerekçe).
  'donemler',
  'donem_sube_durumlari', 'devir_checkpoint',
  'stok_kapanis_snapshot', 'cari_kapanis_snapshot',
  'kasa_kapanis_snapshot', 'banka_kapanis_snapshot',
  // Çoklu cihaz kilidi (2026-09-21, FAZ 4) — donemler'e FK bağımlı
  // değil ama aynı gruba ait, sıra bağımsız.
  'donem_kilit',
];

const _globalIdVar = {
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
  'onay_talepleri',

  // Yıl Sonu Devir / Dönem Kapatma / Arşivleme (2026-09-16):
  'donemler', 'donem_sube_durumlari', 'devir_checkpoint',
  'stok_kapanis_snapshot', 'cari_kapanis_snapshot',
  'kasa_kapanis_snapshot', 'banka_kapanis_snapshot',
  'donem_kilit', // çoklu cihaz kilidi (2026-09-21, FAZ 4)
  'tedarikci_iadeler', 'tedarikci_iade_kalem', // tedarikçiye iade (v81)
};

// NOT (2026-09-27): burada ÖNCEDEN id haritası kurulacak ebeveyn
// tabloların elle tutulan bir listesi vardı (_idHaritasiKurulacakTablolar).
// Listeye eklenmeyi unutulan her ebeveyn için (masa_siparisleri,
// kullanicilar, kredi_kartlari, banka_hesaplar, borclar, fiyat_gruplari…
// — geçmişte defalarca) indirilen çocuk kaydın FK sütunu SİLİNİYORDU.
// Artık _buluttanAlCalistir içindeki idHaritasiGetir, satırın ihtiyaç
// duyduğu HER ebeveynin haritasını ilk ihtiyaçta kurar — bu hata sınıfı
// yapısal olarak kapandı.

// FK haritası: tek doğruluk kaynağı KolonHaritalama (satır bazlı —
// KolonHaritalama.satirFkHaritasi, polimorfik referanslar dahil).

/// Bu uygulama oturumunda geniş (48 sa) pencereyle çekilmiş tablolar.
final Set<String> _genisPencereYapilanlar = <String>{};

const _lastUpdatedVar = {
  'birimler','cari','cari_adres','cari_hareket','fatura_detaylari',
  'faturalar','gider_kategoriler','giderler','iade','iade_kalem',
  'kasa_hareketleri','kategoriler','kullanicilar','lot_seri',
  'musteri_puan','personel','promosyonlar','promosyon_tanim','puan_hareket',
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
  'onay_talepleri',

  // Yıl Sonu Devir / Dönem Kapatma / Arşivleme (2026-09-16):
  'donemler', 'donem_sube_durumlari', 'devir_checkpoint',
  'stok_kapanis_snapshot', 'cari_kapanis_snapshot',
  'kasa_kapanis_snapshot', 'banka_kapanis_snapshot',
  'donem_kilit', // çoklu cihaz kilidi (2026-09-21, FAZ 4)
  'tedarikci_iadeler', 'tedarikci_iade_kalem', // tedarikçiye iade (v81)
};

const Map<String, String> _uniqueAlan = {
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
  'onay_talepleri': 'global_id',

  // Yıl Sonu Devir / Dönem Kapatma / Arşivleme (2026-09-16):
  'donemler': 'global_id',
  'donem_sube_durumlari': 'global_id',
  'devir_checkpoint': 'global_id',
  'stok_kapanis_snapshot': 'global_id',
  'cari_kapanis_snapshot': 'global_id',
  'kasa_kapanis_snapshot': 'global_id',
  'banka_kapanis_snapshot': 'global_id',
  // Tedarikçiye mal iadesi (v81):
  'tedarikci_iadeler': 'global_id',
  'tedarikci_iade_kalem': 'global_id',
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
const _softDeleteKolonu = {
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
  'onay_talepleri': 'is_deleted',
  'tedarikci_iadeler': 'is_deleted', // v81
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
bool _silinmisMi(String tablo, Map<String, dynamic> m) {
  final kolon = _softDeleteKolonu[tablo];
  if (kolon == null) return false;
  if (kolon == 'aktif') return m['aktif'] == 0 || m['aktif'] == false;
  if (kolon == 'deleted_at') return m['deleted_at'] != null;
  return m['is_deleted'] == 1 || m['is_deleted'] == true;
}

const _softDelete = {
  'urunler','cari','satislar','faturalar','giderler','irsaliyeler',
  'masa_rezervasyon','kategoriler','markalar','promosyonlar','subeler',
};

const Set<String> _boolAlanlar = {
  'aktif', 'is_deleted', 'iptal', 'seri_no_takibi', 'lot_takibi',
  'otomatik_indirim', 'evrak_kontrol_aktif', 'promosyon_aktif',
  'varsayilan', 'okundu', 'silindi', 'onaylandi', 'tamamlandi', 'goruldu',
};

// NOT: 'masalar','masa_siparisleri','masa_siparis_kalem' önceden
// burada listeliydi çünkü Supabase'de is_deleted sütunları INTEGER
// kalmıştı — artık Supabase tarafında BOOLEAN'a çevrildiği için
// (bkz. supabase_sema_duzeltmeleri.sql) bu istisnaya gerek kalmadı.
const Set<String> _skipBoolDonusum = {};

const _damaGonderilmez = {
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
