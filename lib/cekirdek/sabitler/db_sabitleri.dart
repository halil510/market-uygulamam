// lib/cekirdek/sabitler/db_sabitleri.dart
class DbSabitler {
  // DB dosya adı — Veritabani._baslatDb() ile aynı olmalı
  static const String dbAdi = 'market.db';

  // Tablo adları
  static const String subeler                = 'subeler';
  static const String kullanicilar           = 'kullanicilar';
  static const String kategoriler            = 'kategoriler';
  static const String birimler               = 'birimler';
  static const String markalar               = 'markalar';
  static const String urunler               = 'urunler';
  static const String fiyatGecmis           = 'fiyat_gecmis';
  static const String lotSeri               = 'lot_seri';
  static const String cari                  = 'cari';
  static const String cariAdres             = 'cari_adres';
  static const String cariHareket           = 'cari_hareket';
  static const String satislar              = 'satislar';
  static const String satisKalem            = 'satis_kalem';
  static const String stokHareket           = 'stok_hareket';
  static const String geciciSayim           = 'gecici_sayim';
  static const String iade                  = 'iade';
  static const String iadeKalem            = 'iade_kalem';
  static const String promosyonlar          = 'promosyonlar';
  static const String promosyonTanim        = 'promosyon_tanim';
  static const String promosyonKosul        = 'promosyon_kosul';
  static const String promosyonAksiyon      = 'promosyon_aksiyon';
  static const String tedarikciSiparisler   = 'tedarikci_siparisler';
  static const String tedarikciSiparisKalem = 'tedarikci_siparis_kalem';
  static const String bekleyenSiparisler    = 'bekleyen_siparisler';
  static const String bekleyenSiparisKalem  = 'bekleyen_siparis_kalem';
  static const String giderKategoriler      = 'gider_kategoriler';
  static const String giderler              = 'giderler';
  static const String kasaHareketleri       = 'kasa_hareketleri';
  static const String vardiyalar            = 'vardiyalar';
  static const String bildirimler           = 'bildirimler';
  static const String yazicilar             = 'yazicilar';
  static const String ayarlar              = 'ayarlar';
  static const String fisSeri              = 'fis_seri';
  static const String gunlukRaporOzet      = 'gunluk_rapor_ozet';
  static const String rollerYetki          = 'roller_yetki';
  static const String rolYetkileri         = 'rol_yetkileri';
  static const String faturalar            = 'faturalar';
  static const String faturaDetaylari      = 'fatura_detaylari';
  static const String subeUrun            = 'sube_urun';
  static const String syncQueue           = 'sync_queue';
  static const String syncMeta            = 'sync_meta';
  static const String syncCakismalar      = 'sync_cakismalar';
  static const String stokFifo            = 'stok_fifo';
  static const String subeFiyatGecmis     = 'sube_fiyat_gecmis';
  static const String personel            = 'personel';
  static const String irsaliyeler         = 'irsaliyeler';
  static const String irsaliyeKalem        = 'irsaliye_kalem';
  static const String musteriPuan         = 'musteri_puan';
  static const String puanHareket         = 'puan_hareket';
  static const String eFaturaLog          = 'efatura_log';
  static const String masalar             = 'masalar';
  static const String masaSiparisleri     = 'masa_siparisleri';
  static const String masaSiparisKalem    = 'masa_siparis_kalem';
  static const String masaRezervasyon     = 'masa_rezervasyon';
  static const String garsonCagriLog      = 'garson_cagri_log';
  static const String adisyonLog          = 'adisyon_log';
  static const String masaHareketLog      = 'masa_hareket_log';
  static const String appLog              = 'app_log';
  static const String zamanFiyat          = 'zaman_fiyat';
  static const String onayTalepleri       = 'onay_talepleri';
  static const String biyometrikKayitlari = 'biyometrik_kayitlar';

  // Banka / Kredi Kartı / Borç modülü
  static const String bankalar            = 'bankalar';
  static const String bankaHesaplar       = 'banka_hesaplar';
  static const String krediKartlari       = 'kredi_kartlari';
  static const String bankaHareketler     = 'banka_hareketler';
  static const String borclar             = 'borclar';
  static const String borcOdemeler        = 'borc_odemeler';

  // Çoklu para birimi / döviz kuru modülü
  static const String dovizKurlari        = 'doviz_kurlari';
}
