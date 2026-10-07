// lib/servisler/kolon_haritalama.dart
// SQLite → Bulut veri dönüşümü — tek merkezi nokta
class KolonHaritalama {
  // Sadece SQLite'a özgü, buluta gönderilmeyecek alanlar.
  // 🔴 KRİTİK: 'id' listede OLMAK ZORUNDA — lokal SQLite id'si
  // (autoincrement) ile buluttaki BIGSERIAL id TAMAMEN ALAKASIZ iki
  // sayıdır. Önceden 'id' filtrelenmiyordu; Supabase, POST +
  // merge-duplicates isteğinde (on_conflict verilmediğinde) çakışmayı
  // PRIMARY KEY (id) üzerinden çözdüğü için, bir cihazın id=5 kaydı
  // buluttaki id=5 olan BAMBAŞKA bir kaydın üzerine yazılabiliyordu
  // (global_id'si dahil!) — sessiz veri bozulması. Eşleştirme artık
  // yalnızca global_id (on_conflict) üzerinden yapılıyor.
  static const Set<String> _filtrele = {'sync_status', 'id'};

  // Bool alanlar (SQLite int → bool)
  static const Set<String> _boollar = {
    'aktif','is_deleted','iptal','seri_no_takibi','lot_takibi',
    'otomatik_indirim','promosyon_aktif','varsayilan','okundu','deleted',
  };

  // Tablo → unique alan
  static const Map<String,String> _unique = {
    'urunler':'global_id','satislar':'global_id','satis_kalem':'global_id',
    'cari':'global_id','cari_hareket':'global_id','stok_hareket':'global_id',
    'kasa_hareketleri':'global_id','giderler':'global_id','faturalar':'global_id',
    'fatura_detaylari':'global_id','iade':'global_id','iade_kalem':'global_id',
    'irsaliyeler':'global_id','promosyonlar':'global_id','lot_seri':'global_id',
    'personel':'global_id','musteri_puan':'global_id','puan_hareket':'global_id',
    'vardiyalar':'global_id','tedarikci_siparisler':'global_id',
    'tedarikci_siparis_kalem':'global_id','yazicilar':'global_id',
    'bekleyen_siparisler':'global_id','bekleyen_siparis_kalem':'global_id',
    'kategoriler':'ad','birimler':'ad','gider_kategoriler':'ad','markalar':'ad',
    'subeler':'sube_kodu','kullanicilar':'kullanici_adi', 'bankalar':'global_id',
    'banka_hesaplar':'global_id', 'kredi_kartlari':'global_id',
    'sube_urun':'global_id',
    'ayarlar':'anahtar','sync_meta':'tablo_adi','gunluk_rapor_ozet':'rapor_tarihi',
    // 🔴 Derin analizde bulundu: fis_seri (fiş/irsaliye/sipariş sayacı)
    // buluta hiç gitmiyordu. Bu tablonun global_id'si YOK — doğal
    // anahtarı (sube_id, fis_tipi) çifti. PostgREST composite on_conflict
    // hedefini virgülle ayrılmış kolon listesi olarak kabul eder; MAX
    // birleştirmesi (küçük bir değerin büyüğün üzerine yazmaması) burada
    // DEĞİL, Supabase tarafındaki BEFORE UPDATE tetikleyicisinde
    // sağlanıyor (bkz. Supabase şema dosyasındaki fis_seri notu) —
    // bu harita sadece hangi sütun(lar)ın eşleşme anahtarı olduğunu
    // belirtir, MAX mantığını uygulamaz.
    'fis_seri':'sube_id,fis_tipi',
    // 🔴🔴🔴 KAPSAMLI DERİN ANALİZ (kullanıcı isteği — tek tek yama
    // değil, TÜM sistemi tara): bu harita, OTOMATİK/anlık senkron
    // yolunun (BulutManager -> bu fonksiyon) hangi sütunu on_conflict
    // hedefi olarak kullanacağını belirliyor. Aşağıdaki 24 tablo bu
    // haritada HİÇ YOKTU — BulutManager._isle() bulamayınca sessizce
    // 'id' sütununa DÜŞÜYORDU (`?? 'id'`). Ama gönderilen veriden
    // 'id' HER ZAMAN çıkarılıyor (yerel id ile bulut id alakasız
    // olduğu için) — yani PostgREST'e "id üzerinden çakışma çöz"
    // deniyor ama payload'da 'id' hiç yok. Sonuç: on_conflict hiçbir
    // zaman eşleşmiyor, her gönderim YENİ bir satır olarak ekleniyor
    // — tıpkı kod içindeki diğer yorumlarda anlatılan "stok_hareket
    // bulutta çoğalıyordu" hatasının AYNISI, ama bu 24 tabloda hâlâ
    // canlıydı (masalar, masa_siparisleri, promosyon_tanim, borclar,
    // audit_log, vb. — özellikle sık kullanılan, anlık senkronlanan
    // tablolar). Manuel senkron yolundaki (SupabaseSyncServisi)
    // _uniqueAlan haritası zaten doğruydu; bu değerler oradan alınıp
    // buraya da eklendi — artık iki yol da AYNI (tek doğruluk kaynağı
    // ilkesine tam uyumlu) davranıyor.
    'masalar':'global_id','masa_siparisleri':'global_id',
    'masa_siparis_kalem':'global_id','masa_rezervasyon':'global_id',
    'adisyon_log':'global_id','garson_cagri_log':'global_id',
    'masa_hareket_log':'global_id','banka_hareketler':'global_id',
    'kredi_karti_hareket':'global_id','borclar':'global_id',
    'borc_odemeler':'global_id','audit_log':'global_id',
    'urun_fiyat_gruplari':'global_id','fiyat_kademeleri':'global_id',
    'fiyat_gruplari':'global_id','promosyon_tanim':'global_id',
    'promosyon_kosul':'global_id','promosyon_aksiyon':'global_id',
    'rol_yetkileri':'global_id','roller_yetki':'global_id',
    'zaman_fiyat':'global_id','fiyat_gecmis':'global_id',
    'cari_adres':'global_id','irsaliye_kalem':'global_id',
    // Onay + dönem/devir tabloları haritada yoktu: BulutManager 'id'ye düşüp
    // ilk INSERT'ten sonra her UPDATE'i 409 (kalıcı hata) alıyordu.
    'onay_talepleri':'global_id','donemler':'global_id',
    'donem_sube_durumlari':'global_id','devir_checkpoint':'global_id',
    'donem_kilit':'global_id','stok_kapanis_snapshot':'global_id',
    'cari_kapanis_snapshot':'global_id','kasa_kapanis_snapshot':'global_id',
    'banka_kapanis_snapshot':'global_id',
    // Tedarikçiye mal iadesi (v81):
    'tedarikci_iadeler':'global_id','tedarikci_iade_kalem':'global_id',
  };

  static String? uniqueAlan(String tablo) => _unique[tablo];

  // FK (yabancı anahtar) haritası — hangi tablonun hangi kolonu,
  // hangi parent tablonun id'sine işaret ediyor. TEK DOĞRULUK KAYNAĞI:
  // hem manuel senkron (SupabaseSyncServisi) hem otomatik senkron
  // (SupabaseSaglayici) FK dönüşümü için BU haritayı kullanır.
  // Lokal SQLite id'leri ile buluttaki BIGSERIAL id'ler alakasız
  // olduğundan, FK kolonları gönderilirken lokal→bulut, indirilirken
  // bulut→lokal dönüştürülmek ZORUNDA.
  static const Map<String, Map<String, String>> fkHaritasi = {
    'satis_kalem':            {'urun_id': 'urunler', 'satis_id': 'satislar', 'lot_id': 'lot_seri'},
    'iade':                   {'satis_id': 'satislar', 'cari_id': 'cari', 'kasiyer_id': 'kullanicilar'},
    'iade_kalem':             {'urun_id': 'urunler', 'iade_id': 'iade'},
    'irsaliyeler':            {'cari_id': 'cari', 'kullanici_id': 'kullanicilar'},
    'irsaliye_kalem':         {'urun_id': 'urunler', 'irsaliye_id': 'irsaliyeler'},
    'cari_adres':             {'cari_id': 'cari'},
    'cari_hareket':           {'cari_id': 'cari'},
    'musteri_puan':           {'cari_id': 'cari'},
    'puan_hareket':           {'cari_id': 'cari'},
    'satislar':               {'cari_id': 'cari', 'kasiyer_id': 'kullanicilar', 'kullanici_id': 'kullanicilar', 'sube_id': 'subeler', 'vardiya_id': 'vardiyalar'},
    'tedarikci_siparisler':   {'cari_id': 'cari', 'olusturan_id': 'kullanicilar'},
    'tedarikci_siparis_kalem':{'urun_id': 'urunler', 'siparis_id': 'tedarikci_siparisler'},
    // Tedarikçiye mal iadesi (v81):
    'tedarikci_iadeler':      {'cari_id': 'cari', 'olusturan_id': 'kullanicilar', 'sube_id': 'subeler'},
    'tedarikci_iade_kalem':   {'urun_id': 'urunler', 'iade_id': 'tedarikci_iadeler'},
    // "Bayilerden Sipariş Alma" (bekleyen sipariş) tabloları:
    'bekleyen_siparisler':    {'cari_id': 'cari', 'kullanici_id': 'kullanicilar', 'sube_id': 'subeler'},
    'bekleyen_siparis_kalem': {'urun_id': 'urunler', 'siparis_id': 'bekleyen_siparisler'},
    'giderler':               {'cari_id': 'cari', 'kategori_id': 'gider_kategoriler', 'kullanici_id': 'kullanicilar', 'sube_id': 'subeler', 'banka_hesap_id': 'banka_hesaplar', 'kredi_karti_id': 'kredi_kartlari'},
    'faturalar':              {'satis_id': 'satislar', 'cari_id': 'cari', 'iade_id': 'iade', 'sube_id': 'subeler'},
    'fatura_detaylari':       {'urun_id': 'urunler', 'fatura_id': 'faturalar'},
    'stok_hareket':           {'urun_id': 'urunler', 'kullanici_id': 'kullanicilar', 'lot_id': 'lot_seri', 'sube_id': 'subeler'},
    'fiyat_gecmis':           {'urun_id': 'urunler'},
    'zaman_fiyat':            {'urun_id': 'urunler'},
    // 🔴 DÜZELTME (Supabase şema hazırlığı sırasında bulundu): sütun adı
    // 'tedarikci_id' değil, gerçekte 'tedarikci_cari_id' — bu yanlış
    // isim yüzünden lot_seri.tedarikci_cari_id'nin FK dönüşümü sessizce
    // HİÇ ÇALIŞMIYORDU (dict'te aranan anahtar hiç eşleşmiyordu).
    'lot_seri':               {'urun_id': 'urunler', 'tedarikci_cari_id': 'cari'},
    // 🔴 DÜZELTME (Supabase şema hazırlığı sırasında bulundu): Bu iki
    // tabloda 'urun_id' diye bir sütun HİÇ YOK — bu satırlar muhtemelen
    // eski/farklı bir şema varsayımından kalmıştı. Gerçek FK, kendi
    // promosyon tanımına bağlanan 'tanim_id' sütunu. Bu yanlış eşleme
    // yüzünden bu iki tablonun FK dönüşümü sessizce hiç çalışmıyordu
    // (aranan 'urun_id' anahtarı zaten gelen veride yoktu, bu yüzden
    // fark edilmemişti — ama gerçek 'tanim_id' hiç dönüştürülmüyordu).
    'promosyon_kosul':        {'tanim_id': 'promosyon_tanim'},
    'promosyon_aksiyon':      {'tanim_id': 'promosyon_tanim'},
    'promosyonlar':           {'urun_id': 'urunler'},
    'masa_siparisleri':       {'masa_id': 'masalar', 'cari_id': 'cari', 'satis_id': 'satislar', 'garson_id': 'kullanicilar', 'kullanici_id': 'kullanicilar'},
    'masa_siparis_kalem':     {'siparis_id': 'masa_siparisleri', 'urun_id': 'urunler'},
    'masa_rezervasyon':       {'masa_id': 'masalar', 'kullanici_id': 'kullanicilar'},
    'adisyon_log':            {'siparis_id': 'masa_siparisleri', 'yazdiran_kullanici_id': 'kullanicilar'},
    'garson_cagri_log':       {'masa_id': 'masalar', 'yanitlayan_id': 'kullanicilar'},
    'masa_hareket_log':       {'kaynak_masa_id': 'masalar', 'hedef_masa_id': 'masalar', 'siparis_id': 'masa_siparisleri', 'yapan_kullanici_id': 'kullanicilar'},
    'masalar':                {'sube_id': 'subeler'},
    'banka_hareketler':       {'banka_hesap_id': 'banka_hesaplar', 'kredi_karti_id': 'kredi_kartlari'},
    'kredi_kartlari':         {'banka_id': 'bankalar'},
    'kredi_karti_hareket':    {'kredi_karti_id': 'kredi_kartlari'},
    'borc_odemeler':          {'borc_id': 'borclar', 'banka_hesap_id': 'banka_hesaplar', 'kredi_karti_id': 'kredi_kartlari'},
    'urun_fiyat_gruplari':    {'urun_id': 'urunler', 'fiyat_grubu_id': 'fiyat_gruplari'},
    'fiyat_kademeleri':       {'urun_id': 'urunler', 'fiyat_grubu_id': 'fiyat_gruplari'},
    'cari':                   {'fiyat_grubu_id': 'fiyat_gruplari', 'sube_id': 'subeler'},
    // 🔴 Derin analizde bulundu: 'roller_yetki' (kullanıcıya özel yetki
    // override'ları) senkron sistemine YENİ eklendi — kullanici_id'nin
    // de FK dönüşümü gerekiyor, aksi halde farklı cihazlardaki farklı
    // yerel kullanici_id'ler karışırdı.
    'roller_yetki':           {'kullanici_id': 'kullanicilar'},
    'sube_urun':              {'urun_id': 'urunler', 'sube_id': 'subeler'},
    // 🔴🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — gerçek Supabase
    // hatası: "banka_hesaplar UPSERT 409: Key (banka_id)=(1) is not
    // present in table bankalar"): 'banka_hesaplar' bu haritada HİÇ
    // YOKTU — oysa banka_hesaplar.banka_id, bankalar(id)'ye FK ile
    // bağlı. FK dönüşümü hiç çalışmadığından, banka_id her zaman
    // YEREL SQLite id'si olarak (dönüştürülmeden) buluta gidiyordu —
    // bulutta o id'ye sahip bir banka olmadığı/başka bir banka olduğu
    // için kayıt ya reddediliyor ya da yanlış bankaya bağlanıyordu.
    'banka_hesaplar':         {'banka_id': 'bankalar'},

    // 🔴🔴🔴 KAPSAMLI DERİN ANALİZ (kullanıcı isteği — "bi burda bi
    // burda düzenleme yapıyorsun, iyi bak incele düzelt"): banka_hesaplar
    // hatası tek örnek değildi — TÜM tablolar, yerel şemadaki her
    // FOREIGN KEY tanımı ve gerçek Supabase şeması ile programatik
    // olarak tek tek karşılaştırıldı. Aşağıdaki tablolarda AYNI hata
    // sınıfı (bir *_id sütunu bulut kimliğine hiç çevrilmiyordu, ham
    // yerel id gönderiliyordu) tespit edildi ve düzeltildi:
    'kullanicilar':           {'sube_id': 'subeler'},
    'kategoriler':            {'ust_kategori_id': 'kategoriler'},
    'urunler':                {'kategori_id': 'kategoriler'},
    'vardiyalar':             {'kullanici_id': 'kullanicilar', 'sube_id': 'subeler', 'onaylayan_kullanici_id': 'kullanicilar'},
    // 'kasa_hareketleri.referans_id', 'stok_hareket.referans_id' ve
    // 'puan_hareket.referans_id' KASITLI OLARAK haritaya EKLENMEDİ —
    // bunlar polimorfik alanlar (yanlarında 'referans_turu'/'islem_tipi'
    // gibi bir tür sütunu var ve satıra göre FARKLI tablolara işaret
    // edebiliyorlar); tek bir sabit parent tabloya eşlenemezler. Aynı
    // şekilde 'cari_hareket.fis_id' de 'fis_tipi' ile polimorfik.
    'kasa_hareketleri':       {'kullanici_id': 'kullanicilar', 'sube_id': 'subeler'},
    'personel':               {'kullanici_id': 'kullanicilar'},
    'audit_log':              {'kullanici_id': 'kullanicilar', 'sube_id': 'subeler'},

    // Yıl Sonu Devir / Dönem Kapatma / Arşivleme (2026-09-16, kullanıcı
    // onaylı mimari plan raporu). 'donemler' yeni bir parent tablo —
    // aynı hata sınıfını (FK sütununun çevrilmeden ham yerel id ile
    // gitmesi) baştan önlemek için tüm 6 çocuk tablo burada tanımlı.
    'donem_sube_durumlari':   {'donem_id': 'donemler', 'sube_id': 'subeler'},
    'devir_checkpoint':       {'kaynak_donem_id': 'donemler', 'hedef_donem_id': 'donemler'},
    'stok_kapanis_snapshot':  {'donem_id': 'donemler', 'sube_id': 'subeler', 'urun_id': 'urunler'},
    'cari_kapanis_snapshot':  {'donem_id': 'donemler', 'cari_id': 'cari'},
    'kasa_kapanis_snapshot':  {'donem_id': 'donemler', 'sube_id': 'subeler'},
    'banka_kapanis_snapshot': {'donem_id': 'donemler', 'banka_hesap_id': 'banka_hesaplar'},
    // Çoklu cihaz kilidi (2026-09-21, FAZ 4) — sube_id, devir_checkpoint
    // ile AYNI 0-sentinel deseni (şirket geneli kilit) kullanabildiği
    // için BİLEREK 'subeler'e eşlenmedi (aynı gerekçe: 0 gerçek bir şube
    // id'si değil, çeviri denemesi hataya yol açardı).
    'donem_kilit': {'donem_id': 'donemler'},
  };

  static Map<String, String>? fkHarita(String tablo) => fkHaritasi[tablo];

  /// Yalnızca YEREL SQLite'ta olan (bulut şemasında karşılığı olmayan)
  /// sütunlar. Buluta giderse PostgREST o tablonun TÜM toplu gönderimini
  /// PGRST204 ile reddeder.
  ///
  /// 🔴 DÜZELTME (2026-09-27, kullanıcı hatası "could not find the
  /// sync_cakisma_kopyasi column of satislar"): bu ayıklama ÖNCEDEN yalnızca
  /// otomatik gönderimde (BulutManager._veriCoz) vardı; manuel "Buluta
  /// Gönder" (SupabaseSyncServisi._hazirla) atlıyordu. Artık iki yol da bu
  /// TEK listeyi kullanıyor — yeni bir yerel sütun eklenince buraya eklemek
  /// yeterli.
  static const Map<String, Set<String>> yereleOzguSutunlar = {
    'satislar': {'sync_cakisma_kopyasi'},
    // Eski adıyla kalmış, yerini yeni sütunun aldığı kolonlar:
    'faturalar': {'efatura_uuid', 'efatura_durum', 'efatura_tipi'},
    'personel': {'ise_baslama_tarihi'},
  };

  /// TÜRETİLMİŞ alanlar: başka tablodaki hareketlerin toplamıdır (stok ←
  /// stok_hareket, bakiye ← cari_hareket) ve her cihazda mutabakatla yeniden
  /// hesaplanır. Bu yüzden:
  ///  • değişmeleri satırın last_updated'ini İLERLETMEZ (ilerletseydi tam
  ///    satır LWW'de "en yeni" sayılıp başka kasanın ad/fiyat değişikliğini
  ///    ezerdi — Bulut Veri Güvenliği Raporu 2026-10-07, Bulgu 2);
  ///  • çekimde mevcut kayda UYGULANMAZ (yerel değer mutabakattan gelir);
  ///  • gönderimde LWW satırı atlarsa yalnız bu alanlar ayrıca (damgasız)
  ///    güncellenir — bulut değeri bayat kalmasın.
  static const Map<String, Set<String>> turetilmisAlanlar = {
    'urunler': {'stok'},
    'cari': {'bakiye'},
  };

  static void yereleOzguSutunlariAyikla(String tablo, Map<String, dynamic> satir) {
    final s = yereleOzguSutunlar[tablo];
    if (s != null) satir.removeWhere((k, _) => s.contains(k));
  }

  static const Map<String, String> _referansTuruTablo = {
    'satis': 'satislar', 'satis_iptal': 'satislar',
    'fis_guncelleme': 'satislar', 'toptan_satis': 'satislar',
    'iade': 'iade', 'iade_iptal': 'iade', 'iade_duzenle': 'iade',
    'iade_duzeltme': 'iade',
    'irsaliye': 'irsaliyeler', 'irsaliye_iptal': 'irsaliyeler',
    'fatura': 'faturalar',
    'gider': 'giderler',
    'alim': 'tedarikci_siparisler', 'alim_iptal': 'tedarikci_siparisler',
    'tedarikci_iade': 'tedarikci_iadeler', 'tedarikci_iade_iptal': 'tedarikci_iadeler',
    'toptan_siparis': 'bekleyen_siparisler',
    'cari_hareket': 'cari_hareket', 'cari_hareket_iptal': 'cari_hareket',
  };

  /// TÜR SÜTUNUNA GÖRE hedefi değişen (polimorfik) referanslar:
  /// tablo → (id sütunu, tür sütunu, tür değeri → hedef tablo).
  ///
  /// 🔴🔴 ÇOKLU TERMİNAL DÜZELTMESİ (2026-09-27): bu sütunlar ÖNCEDEN
  /// dönüştürülmeden, YEREL id ile buluta gidiyordu (fkHaritasi'ndaki
  /// notta "tek bir sabit tabloya eşlenemez" diye bilerek dışarıda
  /// bırakılmıştı). Başka kasada o sayı BAŞKA bir kaydı gösteriyordu:
  /// B kasasında bir iadeyi düzenleyip silmek, satışı iptal etmek ya da
  /// tahsilatı iptal etmek YANLIŞ kasa/stok/cari hareketini bulup ters
  /// çeviriyor veya hiç bulamıyordu (cari bakiyesi bozuluyordu). Artık
  /// her satır kendi tür değerine göre doğru tabloya çevriliyor. Listede
  /// olmayan tür değerleri (toplu_islem, excel_import …) bir kayda işaret
  /// etmediği için olduğu gibi kalır.
  static const Map<String, ({String kolon, String turKolon, Map<String, String> hedef})>
      polimorfikFkHaritasi = {
    'kasa_hareketleri': (kolon: 'referans_id', turKolon: 'referans_turu', hedef: _referansTuruTablo),
    'stok_hareket': (kolon: 'referans_id', turKolon: 'referans_turu', hedef: _referansTuruTablo),
    'banka_hareketler': (kolon: 'referans_id', turKolon: 'referans_turu', hedef: _referansTuruTablo),
    'kredi_karti_hareket': (kolon: 'referans_id', turKolon: 'referans_turu', hedef: _referansTuruTablo),
    'cari_hareket': (kolon: 'fis_id', turKolon: 'fis_tipi', hedef: {
      'Satış': 'satislar', 'Toptan Satış': 'satislar',
      'Toptan Satış (Sipariş)': 'satislar', 'Satış İptali': 'satislar',
      'İade': 'iade', 'Alım İadesi': 'iade',
      'Alım': 'tedarikci_siparisler', 'Alım İptali': 'tedarikci_siparisler',
      'Tedarikçi İadesi': 'tedarikci_iadeler', 'Tedarikçi İadesi İptali': 'tedarikci_iadeler',
      // CariDeposu.hareketIptalEt: ters kaydın fis_id'si İPTAL EDİLEN
      // cari_hareket'tir (bulutta 'Tahsilat İptali' fis_id=122 yerel id
      // olarak görüldü — asıl kayıt bulutta 1124).
      'Tahsilat İptali': 'cari_hareket', 'Odeme İptali': 'cari_hareket',
      'Ödeme İptali': 'cari_hareket',
    }),
  };

  /// Bu SATIR için geçerli FK haritası: sabit FK'lar + satırın tür
  /// değerine göre çözülen polimorfik referans.
  static Map<String, String>? satirFkHaritasi(String tablo, Map<String, dynamic> satir) {
    final sabit = fkHaritasi[tablo];
    final p = polimorfikFkHaritasi[tablo];
    if (p == null) return sabit;
    final hedef = p.hedef[satir[p.turKolon]?.toString()];
    if (hedef == null) return sabit;
    return {...?sabit, p.kolon: hedef};
  }

  /// Ebeveyn tablonun cihazlar arası EŞLEŞTİRME anahtarı (FK çevirisinde
  /// "yerel id → anahtar → bulut id" zinciri bu sütunla kurulur).
  ///
  /// 🔴 DÜZELTME (2026-09-28, uygulama robotu buldu): çeviri ÖNCEDEN her
  /// ebeveyni global_id ile arıyordu. Ama kategoriler/birimler/markalar/
  /// gider_kategoriler yerelde global_id sütunu HİÇ taşımıyor (bulutta 'ad'
  /// ile eşleşiyor), subeler/kullanicilar ise sube_kodu/kullanici_adi ile
  /// eşleşiyor. Sorgu hata verince ürünün kategori_id'si (ve satışın
  /// sube_id'si) ya yanlış bağlanıyor ya boş kalıyor ya da gönderim
  /// bekletiliyordu. Artık tablonun kendi eşleşme anahtarı kullanılır.
  static String ebeveynAnahtari(String parent) {
    final u = _unique[parent];
    if (u == null || u.contains(',')) return 'global_id';
    return u;
  }

  /// Tablonun (sabit + polimorfik) olası tüm ebeveyn tabloları.
  static Set<String> ebeveynler(String tablo) => {
        ...?fkHaritasi[tablo]?.values,
        ...?polimorfikFkHaritasi[tablo]?.hedef.values,
      };

  static final Map<String, int> _derinlikOnbellek = {};

  /// [fkHaritasi]'na göre tablonun ebeveyn zincirindeki derinliği:
  /// ebeveyni olmayan 0, ebeveyni 0 olan 1 … (satislar < satis_kalem).
  /// Gönderim sırası için kullanılır. Kendine referans (kategoriler)
  /// ve döngüler yok sayılır.
  static int derinlik(String tablo, [Set<String>? yol]) {
    final hazir = _derinlikOnbellek[tablo];
    if (hazir != null) return hazir;
    final ziyaret = yol ?? <String>{};
    if (!ziyaret.add(tablo)) return 0;
    var d = 0;
    for (final parent in ebeveynler(tablo)) {
      if (parent == tablo || ziyaret.contains(parent)) continue;
      final pd = derinlik(parent, ziyaret) + 1;
      if (pd > d) d = pd;
    }
    ziyaret.remove(tablo);
    return _derinlikOnbellek[tablo] = d;
  }

  // 🔴 Kullanıcının verdiği gerçek Supabase şemasıyla doğrulandı:
  // borc_odemeler tablosunda yerel 'tarih' sütunu YOK — bulutta
  // bunun karşılığı 'odeme_tarihi'. Böyle "aynı bilgi, farklı isim"
  // durumları için tablo → {yerel_ad: bulut_ad} yeniden adlandırma
  // haritası.
  static Map<String,dynamic> cevir(String tablo, Map<String,dynamic> ham) {
    final m = <String,dynamic>{};
    for (final e in ham.entries) {
      if (_filtrele.contains(e.key) || e.value == null) continue;
      final v = e.value;
      m[e.key] = (v is int && _boollar.contains(e.key)) ? v == 1 : v;
    }
    m['last_updated'] = utcDamga(m['last_updated']) ??
        DateTime.now().toUtc().toIso8601String();
    if (m['deleted_at'] == null) m.remove('deleted_at');
    return m;
  }

  /// Zaman damgasını AÇIK UTC ISO metnine çevirir (…Z).
  ///
  /// 🔴 DÜZELTME (2026-09-27): yerel kayıtların çoğu last_updated'i
  /// `DateTime.now().toIso8601String()` ile — saat dilimi OLMADAN, yerel
  /// saatle (TR: UTC+3) — yazıyor. Supabase'in TIMESTAMPTZ sütunu dilimsiz
  /// metni UTC sayar; damga bulutta 3 saat İLERİDE saklanıyordu. Bir kısım
  /// kod ise gerçek UTC yazıyordu. Bu karışım yüzünden (1) "Buluttan Al"
  /// filigranı 3 saat ileri kayıp başka cihazların sonraki değişikliklerini
  /// ATLIYOR, (2) "yerel mi bulut mu daha yeni" karşılaştırmaları ters
  /// sonuç verebiliyordu. Artık buluta giden damga her zaman gerçek UTC.
  /// Sadece last_updated'e uygulanır: tarih gibi iş alanları duvar-saati
  /// olarak tutulmaya devam eder (cihazlar arası gösterim tutarlı kalsın).
  ///
  /// 🔴 DÜZELTME (2026-09-28, bulut kontrolü): SQLite'ın CURRENT_TIMESTAMP /
  /// datetime('now') değerleri ("2026-09-28 09:26:48" — BOŞLUKLU) zaten UTC'dir
  /// ama dilimsiz olduğu için yerel sanılıp 3 saat daha geri kaydırılıyordu
  /// (satislar/cari/masa… DEFAULT CURRENT_TIMESTAMP). Dart'ın yazdığı yerel
  /// damgalar her zaman 'T' ayraçlı — boşluklu biçim güvenle UTC sayılır.
  static String? utcDamga(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toUtc().toIso8601String();
    final s = v.toString().trim();
    if (_sqliteUtcBicimi.hasMatch(s)) {
      return DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z')?.toIso8601String();
    }
    final t = DateTime.tryParse(s);
    return t?.toUtc().toIso8601String();
  }

  /// [utcDamga] ile aynı kurallarla, ama DateTime (UTC) döner. last_updated
  /// karşılaştırmalarında ham `DateTime.tryParse` yerine BU kullanılmalı:
  /// SQLite'ın dilimsiz UTC damgası ("2026-10-03 10:00:00") ham ayrıştırmada
  /// yerel saat sanılıp dilim farkı (TR: 3 saat) kadar kayar.
  static DateTime? utcZaman(dynamic v) {
    final s = utcDamga(v);
    return s == null ? null : DateTime.tryParse(s);
  }

  static final _sqliteUtcBicimi =
      RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)?$');

  static Map<String,dynamic> terseCevir(Map<String,dynamic> bulut) {
    final m = <String,dynamic>{};
    for (final e in bulut.entries) {
      final v = e.value;
      m[e.key] = (v is bool) ? (v ? 1 : 0) : v;
    }
    return m;
  }
}
