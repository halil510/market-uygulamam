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
  _AnaButon('Hızlı Satış', Icons.point_of_sale, Color(0xFF4361EE), '/satis'),
  _AnaButon('Ürün Listesi', Icons.inventory_2, Color(0xFF3F51B5), '/urun'),
  _AnaButon('Cariler', Icons.people, Color(0xFF0097A7), '/cari'),
  _AnaButon(
      'Satış Listesi', Icons.receipt_long, Color(0xFF00BCD4), '/satis/liste'),
  _AnaButon('Masalar', Icons.table_restaurant, Color(0xFF6D4C41), '/masa'),
  _AnaButon(
      'Mutfak/Bar', Icons.soup_kitchen_outlined, Color(0xFFE64A19), '/mutfak'),
  _AnaButon('İadeler', Icons.undo, Color(0xFFF57F17), '/satis/iade'),
  _AnaButon('Promosyon', Icons.local_offer, Color(0xFFE65100), '/promosyon'),
  _AnaButon('Raporlar', Icons.bar_chart, Color(0xFF1565C0), '/rapor/satis'),
  _AnaButon('Borç Takip', Icons.payment, Color(0xFFD32F2F), '/borc-dashboard'),
  _AnaButon('Finans', Icons.account_balance, Color(0xFF2E7D32), '/finans'),
  _AnaButon('Ayarlar', Icons.settings, Color(0xFF546E7A), '/ayarlar'),
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
        'Hızlı Satış', Icons.point_of_sale, Color(0xFF2196F3), '/satis'),
    _UygulamaItem(
        'Satış Listesi', Icons.receipt_long, Color(0xFF00BCD4), '/satis/liste'),
    _UygulamaItem('İadeler', Icons.undo, Color(0xFFF57F17), '/satis/iade'),
    _UygulamaItem('Sıcak Satış', Icons.local_fire_department, Color(0xFFB71C1C),
        '/satis/sicak'),
    _UygulamaItem(
        'Soğuk Satış', Icons.ac_unit, Color(0xFF1A237E), '/satis/soguk'),
    _UygulamaItem('Fiş Önizleme', Icons.receipt_outlined, Color(0xFF4CAF50),
        '/satis/fis-onizleme'),
    _UygulamaItem('Toptan Satış', Icons.local_shipping_outlined,
        Color(0xFF6D4C41), '/toptan/dashboard'),
    _UygulamaItem('Fiyat Grupları', Icons.storefront_outlined,
        Color(0xFF8D6E63), '/toptan/fiyat-gruplari'),
  ]),
  _Kategori('Ürün & Stok', Icons.inventory_2, [
    _UygulamaItem(
        'Ürün Listesi', Icons.inventory_2, Color(0xFF3F51B5), '/urun'),
    _UygulamaItem('Ürün Ekle', Icons.add_box, Color(0xFF4CAF50), '/urun/ekle'),
    _UygulamaItem('Fiyat Gör', Icons.price_check_rounded, Color(0xFF00ACC1),
        '/fiyat-gor'),
    _UygulamaItem('Stok Listesi', Icons.warehouse, Color(0xFF673AB7), '/stok'),
    _UygulamaItem(
        'Stok Sayım', Icons.calculate, Color(0xFF1976D2), '/stok/sayim'),
    _UygulamaItem(
        'Stok Hareket', Icons.swap_vert, Color(0xFF283593), '/stok/hareket'),
    _UygulamaItem('Depo Transfer', Icons.local_shipping, Color(0xFFE65100),
        '/stok/transfer'),
    _UygulamaItem(
        'Kritik Stok', Icons.warning_amber, Color(0xFFE65100), '/stok'),
    _UygulamaItem('Toplu İşlem', Icons.bolt_outlined, Color(0xFF1B5E20),
        '/urun/toplu-islem'),
    _UygulamaItem('Toplu Fiyat', Icons.price_change_outlined, Color(0xFF4E342E),
        '/urun/toplu-fiyat'),
    _UygulamaItem(
        'Kategoriler', Icons.category, Color(0xFF9C27B0), '/urun/kategori'),
    _UygulamaItem(
        'Markalar', Icons.branding_watermark, Color(0xFF3F51B5), '/urun/marka'),
    _UygulamaItem('Birimler', Icons.straighten, Color(0xFF795548), '/birim'),
    _UygulamaItem(
        'Lot/Seri Takibi', Icons.qr_code_2, Color(0xFF607D8B), '/lot'),
    _UygulamaItem('PLU Yönetimi', Icons.grid_view_rounded, Color(0xFF2E7D32),
        '/urun/plu'),
  ]),
  _Kategori('Masa & Restoran', Icons.table_restaurant, [
    _UygulamaItem(
        'Masalar', Icons.table_restaurant, Color(0xFF6D4C41), '/masa'),
    _UygulamaItem('Mutfak/Bar', Icons.soup_kitchen_outlined, Color(0xFFE64A19),
        '/mutfak'),
    _UygulamaItem('Rezervasyon', Icons.event_available, Color(0xFF6D4C41),
        '/rezervasyon'),
    _UygulamaItem(
        'Masa Raporu', Icons.assessment, Color(0xFF1565C0), '/masa-rapor'),
    _UygulamaItem('QR Menü', Icons.qr_code_2, Color(0xFF6D4C41), '/masa'),
  ]),
  _Kategori('Cari & Fatura', Icons.people, [
    _UygulamaItem('Cariler', Icons.people, Color(0xFF0097A7), '/cari'),
    _UygulamaItem(
        'Cari Ekle', Icons.person_add, Color(0xFF4CAF50), '/cari/ekle'),
    _UygulamaItem(
        'Cari Hareket', Icons.history, Color(0xFF607D8B), '/cari/hareket'),
    _UygulamaItem('Faturalar', Icons.receipt, Color(0xFF4E342E), '/fatura'),
    _UygulamaItem(
        'Fatura Oluştur', Icons.add, Color(0xFF4CAF50), '/fatura/yeni'),
    _UygulamaItem(
        'İrsaliye', Icons.local_shipping, Color(0xFF00695C), '/irsaliye'),
  ]),
  _Kategori('Promosyon', Icons.local_offer, [
    _UygulamaItem(
        'Promosyonlar', Icons.local_offer, Color(0xFFE65100), '/promosyon'),
    _UygulamaItem('Promosyon Ekle', Icons.add, Color(0xFF4CAF50), '/promosyon'),
  ]),
  _Kategori('Finans', Icons.account_balance, [
    _UygulamaItem(
        'Banka Yönetimi', Icons.business, Color(0xFF1565C0), '/banka'),
    _UygulamaItem(
        'Kredi Kartları', Icons.credit_card, Color(0xFFE65100), '/kredi-karti'),
    _UygulamaItem(
        'Borç Dashboard', Icons.payment, Color(0xFFD32F2F), '/borc-dashboard'),
    _UygulamaItem('Mail Bağlantısı', Icons.email_outlined, Color(0xFF1976D2),
        '/mail-baglanti'),
    _UygulamaItem('Banka Hareketleri', Icons.history, Color(0xFF6A1B9A),
        '/banka-hareket'),
    _UygulamaItem('Kasa', Icons.account_balance, Color(0xFF2E7D32), '/kasa'),
    _UygulamaItem('Kasa Raporu', Icons.account_balance_wallet,
        Color(0xFF1B5E20), '/kasa/rapor'),
    _UygulamaItem(
        'Kasa Hareket', Icons.history, Color(0xFF607D8B), '/kasa/hareket'),
    _UygulamaItem(
        'Virman', Icons.swap_horiz, Color(0xFF4527A0), '/kasa/virman'),
    _UygulamaItem('Giderler', Icons.money_off, Color(0xFFC62828), '/gider'),
    _UygulamaItem('Gider Ekle', Icons.add, Color(0xFF4CAF50), '/gider/ekle'),
    _UygulamaItem(
        'Tahsilat/Ödeme', Icons.payments, Color(0xFF2E7D32), '/cari/tahsilat'),
    _UygulamaItem('Borç Ekle', Icons.add_card, Color(0xFF4CAF50), '/borc-ekle'),
  ]),
  _Kategori('Raporlar', Icons.bar_chart, [
    _UygulamaItem(
        'Günlük Rapor', Icons.assessment, Color(0xFF6A1B9A), '/rapor/gunluk'),
    _UygulamaItem(
        'Satış Raporu', Icons.timeline, Color(0xFF1565C0), '/rapor/satis'),
    _UygulamaItem(
        'Kar / Zarar', Icons.trending_up, Color(0xFF006064), '/rapor/kar'),
    _UygulamaItem('Kasa Raporu', Icons.account_balance_wallet,
        Color(0xFF1B5E20), '/kasa/rapor'),
    _UygulamaItem(
        'Stok Raporu', Icons.inventory_2, Color(0xFF3F51B5), '/rapor/stok'),
    _UygulamaItem(
        'Cari Raporu', Icons.people, Color(0xFF0097A7), '/rapor/cari'),
    _UygulamaItem('ABC Stok Analizi', Icons.pie_chart_outline,
        Color(0xFF00838F), '/rapor/abc-analiz'),
    _UygulamaItem('Fiyat Simülasyonu', Icons.calculate_outlined,
        Color(0xFF6A1B9A), '/urun/fiyat-simulasyon'),
    _UygulamaItem('Stok Devir Analizi', Icons.autorenew,
        Color(0xFF5D4037), '/rapor/stok-devir'),
    _UygulamaItem('AI Analiz', Icons.auto_graph, Color(0xFF4527A0), '/ai'),
    _UygulamaItem('Onay Merkezi', Icons.verified_user_outlined,
        Color(0xFFB71C1C), '/onay-merkezi'),
    _UygulamaItem('Risk Merkezi', Icons.shield_outlined,
        Color(0xFFD84315), '/risk-merkezi'),
  ]),
  _Kategori('Tedarik & Alım', Icons.shopping_cart, [
    _UygulamaItem('Tedarikçi Sipariş', Icons.shopping_cart_outlined,
        Color(0xFF558B2F), '/tedarik'),
    _UygulamaItem(
        'Mal Alımı', Icons.shopping_cart, Color(0xFF558B2F), '/tedarik/alim'),
    _UygulamaItem('Satın Alma Önerileri', Icons.lightbulb_outline,
        Color(0xFFEF6C00), '/tedarik/oneriler'),
    _UygulamaItem('Tedarikçi Performansı', Icons.local_shipping_outlined,
        Color(0xFF37474F), '/rapor/tedarikci-performans'),
  ]),
  _Kategori('Barkod & Etiket', Icons.qr_code_2, [
    _UygulamaItem(
        'Etiket Yazdır', Icons.qr_code_2, Color(0xFF4E342E), '/barkod/etiket'),
    _UygulamaItem(
        'Barkod Üreteci', Icons.qr_code, Color(0xFF2196F3), '/barkod/uret'),
  ]),
  _Kategori('Sistem', Icons.settings, [
    _UygulamaItem('Ayarlar', Icons.settings, Color(0xFF546E7A), '/ayarlar'),
    _UygulamaItem(
        'Yazıcı Ayarları', Icons.print, Color(0xFF546E7A), '/ayarlar/yazici'),
    _UygulamaItem(
        'Yedekleme', Icons.backup, Color(0xFF2E7D32), '/ayarlar/yedek'),
    _UygulamaItem(
        'Kullanıcılar', Icons.people, Color(0xFFAD1457), '/kullanici'),
    _UygulamaItem(
        'Personel', Icons.badge_outlined, Color(0xFF7B1FA2), '/personel'),
    _UygulamaItem('Şubeler', Icons.store, Color(0xFF1A237E), '/sube'),
    _UygulamaItem('Vardiya', Icons.access_time, Color(0xFF37474F), '/vardiya'),
    _UygulamaItem(
        'Bildirimler', Icons.notifications, Color(0xFFE91E63), '/bildirimler'),
    _UygulamaItem(
        'Sistem Logları', Icons.history, Color(0xFF607D8B), '/ayarlar/log'),
    _UygulamaItem(
        'GIB e-Fatura', Icons.receipt, Color(0xFFC62828), '/ayarlar/gib'),
    _UygulamaItem('Fatura Ayarları', Icons.description, Color(0xFF3E2723),
        '/ayarlar/fatura'),
    _UygulamaItem('Fiş Tasarımı', Icons.receipt_outlined, Color(0xFF263238),
        '/ayarlar/fis'),
    _UygulamaItem('Bulut Senkronizasyon', Icons.cloud_sync, Color(0xFF4361EE),
        '/ayarlar/bulut-sync'),
    _UygulamaItem('Veri Aktarımı WiFi', Icons.sync_alt, Color(0xFF1565C0),
        '/ayarlar/sync'),
    _UygulamaItem('Kullanıcı Değiştir', Icons.swap_horiz, Color(0xFF4361EE),
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
