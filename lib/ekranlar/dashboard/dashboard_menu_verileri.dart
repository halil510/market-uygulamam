// lib/ekranlar/dashboard/dashboard_menu_verileri.dart
// dashboard_ekrani.dart'ın parçası — dosya boyutu azaltma (god-class
// sertleştirmesi, 2026-09-22). Ana ekrandaki büyük butonlar ve "Tüm
// Uygulamalar" kategorili listesinin SABİT (const) verisi — hiç mantık
// içermez, davranış birebir korunarak buraya taşındı.
part of 'dashboard_ekrani.dart';

// ──────────────────────────────────────────────────────────────────────────────
// ANA EKRANDA GÖSTERİLECEK BÜYÜK BUTONLAR
// ──────────────────────────────────────────────────────────────────────────────
class _AnaButon {
  final String ad;
  final IconData ikon;
  final Color renk;
  final String rota;
  const _AnaButon(this.ad, this.ikon, this.renk, this.rota);
}

const List<_AnaButon> _anaButonlar = [
  _AnaButon('Hızlı Satış', Icons.point_of_sale, TsRenk.primary, '/satis'),
  _AnaButon('Ürün Listesi', Icons.inventory_2, TsRenk.primary, '/urun'),
  _AnaButon('Cariler', Icons.people, TsRenk.vurguTurkuaz, '/cari'),
  _AnaButon(
      'Satış Listesi', Icons.receipt_long, TsRenk.vurguTurkuaz, '/satis/liste'),
  _AnaButon('Masalar', Icons.table_restaurant, TsRenk.masaAcik, '/masa'),
  _AnaButon(
      'Mutfak/Bar', Icons.soup_kitchen_outlined, Color(0xFFE64A19), '/mutfak'),
  _AnaButon('İadeler', Icons.undo, TsRenk.uyari, '/satis/iade'),
  _AnaButon('Promosyon', Icons.local_offer, TsRenk.uyari, '/promosyon'),
  _AnaButon('Raporlar', Icons.bar_chart, TsRenk.bilgi, '/rapor/satis'),
  _AnaButon('Borç Takip', Icons.payment, TsRenk.hata, '/borc-dashboard'),
  _AnaButon('Finans', Icons.account_balance, TsRenk.basarili, '/finans'),
  _AnaButon('Ayarlar', Icons.settings, TsRenk.notr, '/ayarlar'),
];

// ──────────────────────────────────────────────────────────────────────────────
// TÜM UYGULAMALAR (Kategori Bazlı)
// ──────────────────────────────────────────────────────────────────────────────
class _UygulamaItem {
  final String ad, rota;
  final IconData ikon;
  final Color renk;
  const _UygulamaItem(this.ad, this.ikon, this.renk, this.rota);
}

class _Kategori {
  final String ad;
  final IconData ikon;
  final List<_UygulamaItem> uygulamalar;
  const _Kategori(this.ad, this.ikon, this.uygulamalar);
}

const List<_Kategori> _tumKategoriler = [
  _Kategori('Satış', Icons.point_of_sale, [
    _UygulamaItem(
        'Hızlı Satış', Icons.point_of_sale, TsRenk.bilgi, '/satis'),
    _UygulamaItem(
        'Satış Listesi', Icons.receipt_long, TsRenk.vurguTurkuaz, '/satis/liste'),
    _UygulamaItem('İadeler', Icons.undo, TsRenk.uyari, '/satis/iade'),
    _UygulamaItem('Sıcak Satış', Icons.local_fire_department, TsRenk.hata,
        '/satis/sicak'),
    _UygulamaItem(
        'Soğuk Satış', Icons.ac_unit, TsRenk.primaryKoyu, '/satis/soguk'),
    _UygulamaItem('Fiş Önizleme', Icons.receipt_outlined, TsRenk.basarili,
        '/satis/fis-onizleme'),
    _UygulamaItem('Toptan Satış', Icons.local_shipping_outlined,
        TsRenk.masaAcik, '/toptan/dashboard'),
    _UygulamaItem('Fiyat Grupları', Icons.storefront_outlined,
        Color(0xFF8D6E63), '/toptan/fiyat-gruplari'),
  ]),
  _Kategori('Ürün & Stok', Icons.inventory_2, [
    _UygulamaItem(
        'Ürün Listesi', Icons.inventory_2, TsRenk.primary, '/urun'),
    _UygulamaItem('Ürün Ekle', Icons.add_box, TsRenk.basarili, '/urun/ekle'),
    _UygulamaItem('Fiyat Gör', Icons.price_check_rounded, Color(0xFF00ACC1),
        '/fiyat-gor'),
    _UygulamaItem('Stok Listesi', Icons.warehouse, Color(0xFF673AB7), '/stok'),
    _UygulamaItem(
        'Stok Sayım', Icons.calculate, TsRenk.bilgi, '/stok/sayim'),
    _UygulamaItem(
        'Stok Hareket', Icons.swap_vert, TsRenk.primaryKoyu, '/stok/hareket'),
    _UygulamaItem('Depo Transfer', Icons.local_shipping, TsRenk.uyari,
        '/stok/transfer'),
    _UygulamaItem(
        'Kritik Stok', Icons.warning_amber, TsRenk.uyari, '/stok'),
    _UygulamaItem('Toplu İşlem', Icons.bolt_outlined, TsRenk.basarili,
        '/urun/toplu-islem'),
    _UygulamaItem('Toplu Fiyat', Icons.price_change_outlined, TsRenk.masaKoyu,
        '/urun/toplu-fiyat'),
    _UygulamaItem(
        'Kategoriler', Icons.category, TsRenk.vurguMor, '/urun/kategori'),
    _UygulamaItem(
        'Markalar', Icons.branding_watermark, TsRenk.primary, '/urun/marka'),
    _UygulamaItem('Birimler', Icons.straighten, Color(0xFF795548), '/birim'),
    _UygulamaItem(
        'Lot/Seri Takibi', Icons.qr_code_2, TsRenk.notr, '/lot'),
    _UygulamaItem('PLU Yönetimi', Icons.grid_view_rounded, TsRenk.basarili,
        '/urun/plu'),
  ]),
  _Kategori('Masa & Restoran', Icons.table_restaurant, [
    _UygulamaItem(
        'Masalar', Icons.table_restaurant, TsRenk.masaAcik, '/masa'),
    _UygulamaItem('Mutfak/Bar', Icons.soup_kitchen_outlined, Color(0xFFE64A19),
        '/mutfak'),
    _UygulamaItem('Rezervasyon', Icons.event_available, TsRenk.masaAcik,
        '/rezervasyon'),
    _UygulamaItem(
        'Masa Raporu', Icons.assessment, TsRenk.bilgi, '/masa-rapor'),
    _UygulamaItem('QR Menü', Icons.qr_code_2, TsRenk.masaAcik, '/masa'),
  ]),
  _Kategori('Cari & Fatura', Icons.people, [
    _UygulamaItem('Cariler', Icons.people, TsRenk.vurguTurkuaz, '/cari'),
    _UygulamaItem(
        'Cari Ekle', Icons.person_add, TsRenk.basarili, '/cari/ekle'),
    _UygulamaItem(
        'Cari Hareket', Icons.history, TsRenk.notr, '/cari/hareket'),
    _UygulamaItem('Faturalar', Icons.receipt, TsRenk.masaKoyu, '/fatura'),
    _UygulamaItem(
        'Fatura Oluştur', Icons.add, TsRenk.basarili, '/fatura/yeni'),
    _UygulamaItem(
        'İrsaliye', Icons.local_shipping, TsRenk.vurguTurkuaz, '/irsaliye'),
  ]),
  _Kategori('Promosyon', Icons.local_offer, [
    _UygulamaItem(
        'Promosyonlar', Icons.local_offer, TsRenk.uyari, '/promosyon'),
    _UygulamaItem('Promosyon Ekle', Icons.add, TsRenk.basarili, '/promosyon'),
  ]),
  _Kategori('Finans', Icons.account_balance, [
    _UygulamaItem(
        'Banka Yönetimi', Icons.business, TsRenk.bilgi, '/banka'),
    _UygulamaItem(
        'Kredi Kartları', Icons.credit_card, TsRenk.uyari, '/kredi-karti'),
    _UygulamaItem(
        'Borç Dashboard', Icons.payment, TsRenk.hata, '/borc-dashboard'),
    _UygulamaItem('Mail Bağlantısı', Icons.email_outlined, TsRenk.bilgi,
        '/mail-baglanti'),
    _UygulamaItem('Banka Hareketleri', Icons.history, TsRenk.vurguMor,
        '/banka-hareket'),
    _UygulamaItem('Kasa', Icons.account_balance, TsRenk.basarili, '/kasa'),
    _UygulamaItem('Kasa Raporu', Icons.account_balance_wallet,
        TsRenk.basarili, '/kasa/rapor'),
    _UygulamaItem(
        'Kasa Hareket', Icons.history, TsRenk.notr, '/kasa/hareket'),
    _UygulamaItem(
        'Virman', Icons.swap_horiz, TsRenk.vurguMor, '/kasa/virman'),
    _UygulamaItem('Giderler', Icons.money_off, TsRenk.hata, '/gider'),
    _UygulamaItem('Gider Ekle', Icons.add, TsRenk.basarili, '/gider/ekle'),
    _UygulamaItem(
        'Tahsilat/Ödeme', Icons.payments, TsRenk.basarili, '/cari/tahsilat'),
    _UygulamaItem('Borç Ekle', Icons.add_card, TsRenk.basarili, '/borc-ekle'),
  ]),
  _Kategori('Raporlar', Icons.bar_chart, [
    _UygulamaItem(
        'Günlük Rapor', Icons.assessment, TsRenk.vurguMor, '/rapor/gunluk'),
    _UygulamaItem(
        'Satış Raporu', Icons.timeline, TsRenk.bilgi, '/rapor/satis'),
    _UygulamaItem(
        'Kar / Zarar', Icons.trending_up, Color(0xFF006064), '/rapor/kar'),
    _UygulamaItem('Kasa Raporu', Icons.account_balance_wallet,
        TsRenk.basarili, '/kasa/rapor'),
    _UygulamaItem(
        'Stok Raporu', Icons.inventory_2, TsRenk.primary, '/rapor/stok'),
    _UygulamaItem(
        'Ürün Raporu', Icons.bar_chart, TsRenk.primaryKoyu, '/rapor/urun'),
    _UygulamaItem(
        'Cari Raporu', Icons.people, TsRenk.vurguTurkuaz, '/rapor/cari'),
    _UygulamaItem('ABC Stok Analizi', Icons.pie_chart_outline,
        TsRenk.vurguTurkuaz, '/rapor/abc-analiz'),
    _UygulamaItem('Fiyat Simülasyonu', Icons.calculate_outlined,
        TsRenk.vurguMor, '/urun/fiyat-simulasyon'),
    _UygulamaItem('Stok Devir Analizi', Icons.autorenew,
        Color(0xFF5D4037), '/rapor/stok-devir'),
    _UygulamaItem('AI Analiz', Icons.auto_graph, TsRenk.vurguMor, '/ai'),
    _UygulamaItem('Onay Merkezi', Icons.verified_user_outlined,
        TsRenk.hata, '/onay-merkezi'),
    _UygulamaItem('Risk Merkezi', Icons.shield_outlined,
        TsRenk.uyari, '/risk-merkezi'),
  ]),
  _Kategori('Tedarik & Alım', Icons.shopping_cart, [
    _UygulamaItem('Tedarikçi Sipariş', Icons.shopping_cart_outlined,
        TsRenk.basarili, '/tedarik'),
    _UygulamaItem(
        'Mal Alımı', Icons.shopping_cart, TsRenk.basarili, '/tedarik/alim'),
    _UygulamaItem('Satın Alma Önerileri', Icons.lightbulb_outline,
        TsRenk.uyari, '/tedarik/oneriler'),
    _UygulamaItem('Tedarikçi Performansı', Icons.local_shipping_outlined,
        TsRenk.notr, '/rapor/tedarikci-performans'),
  ]),
  _Kategori('Barkod & Etiket', Icons.qr_code_2, [
    _UygulamaItem(
        'Etiket Yazdır', Icons.qr_code_2, TsRenk.masaKoyu, '/barkod/etiket'),
    _UygulamaItem(
        'Barkod Üreteci', Icons.qr_code, TsRenk.bilgi, '/barkod/uret'),
  ]),
  _Kategori('Sistem', Icons.settings, [
    _UygulamaItem('Ayarlar', Icons.settings, TsRenk.notr, '/ayarlar'),
    _UygulamaItem(
        'Yazıcı Ayarları', Icons.print, TsRenk.notr, '/ayarlar/yazici'),
    _UygulamaItem(
        'Yedekleme', Icons.backup, TsRenk.basarili, '/ayarlar/yedek'),
    _UygulamaItem(
        'Kullanıcılar', Icons.people, Color(0xFFAD1457), '/kullanici'),
    _UygulamaItem(
        'Personel', Icons.badge_outlined, TsRenk.vurguMor, '/personel'),
    _UygulamaItem('Şubeler', Icons.store, TsRenk.primaryKoyu, '/sube'),
    _UygulamaItem('Vardiya', Icons.access_time, TsRenk.notr, '/vardiya'),
    _UygulamaItem(
        'Bildirimler', Icons.notifications, Color(0xFFE91E63), '/bildirimler'),
    _UygulamaItem(
        'Sistem Logları', Icons.history, TsRenk.notr, '/ayarlar/log'),
    _UygulamaItem(
        'GIB e-Fatura', Icons.receipt, TsRenk.hata, '/ayarlar/gib'),
    _UygulamaItem('Fatura Ayarları', Icons.description, Color(0xFF3E2723),
        '/ayarlar/fatura'),
    _UygulamaItem('Fiş Tasarımı', Icons.receipt_outlined, Color(0xFF263238),
        '/ayarlar/fis'),
    _UygulamaItem('Bulut Senkronizasyon', Icons.cloud_sync, TsRenk.primary,
        '/ayarlar/bulut-sync'),
    _UygulamaItem('Veri Aktarımı WiFi', Icons.sync_alt, TsRenk.bilgi,
        '/ayarlar/sync'),
    _UygulamaItem('Kullanıcı Değiştir', Icons.swap_horiz, TsRenk.primary,
        '/kullanici-degistir'),
  ]),
];

/// Masa/Restoran modülüne ait bir rota mı? — Masa Modu kapalıyken
/// bu rotalar dashboard'dan gizlenir.
bool _masaModulOgesi(String rota) =>
    rota == '/masa' ||
    rota == '/mutfak' ||
    rota == '/rezervasyon' ||
    rota == '/masa-rapor' ||
    rota == '/qr-menu';

/// Saate göre selamlama metni.
String _selamlama() {
  final h = DateTime.now().hour;
  if (h < 6) return 'İyi geceler';
  if (h < 12) return 'Günaydın';
  if (h < 18) return 'İyi günler';
  return 'İyi akşamlar';
}
