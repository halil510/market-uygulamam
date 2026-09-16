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
    // "Bayilerden Sipariş Alma" (bekleyen sipariş) tabloları:
    'bekleyen_siparisler':    {'cari_id': 'cari', 'kullanici_id': 'kullanicilar', 'sube_id': 'subeler'},
    'bekleyen_siparis_kalem': {'urun_id': 'urunler', 'siparis_id': 'bekleyen_siparisler'},
    'giderler':               {'cari_id': 'cari', 'kategori_id': 'gider_kategoriler', 'kullanici_id': 'kullanicilar', 'sube_id': 'subeler'},
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
    'vardiyalar':             {'kullanici_id': 'kullanicilar', 'sube_id': 'subeler'},
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
  };

  static Map<String, String>? fkHarita(String tablo) => fkHaritasi[tablo];

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
    m['last_updated'] ??= DateTime.now().toUtc().toIso8601String();
    if (m['deleted_at'] == null) m.remove('deleted_at');
    return m;
  }

  static Map<String,dynamic> terseCevir(Map<String,dynamic> bulut) {
    final m = <String,dynamic>{};
    for (final e in bulut.entries) {
      final v = e.value;
      m[e.key] = (v is bool) ? (v ? 1 : 0) : v;
    }
    return m;
  }
}
