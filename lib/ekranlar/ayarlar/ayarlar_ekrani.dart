import '../../cekirdek/utils/dosya_paylasim.dart';
import 'package:flutter/foundation.dart';
import '../../cekirdek/utils/denetleyici_birak.dart';
// lib/ekranlar/ayarlar/ayarlar_ekrani.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../servisler/auth_servisi.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../widgetlar/ortak/yonetici_sifre_dialogu.dart';
import '../../depolar/ayarlar_deposu.dart';
import '../../servisler/excel_servisi.dart';
import '../../saglayicilar/riverpod/masa_modu_provider.dart';
import '../../depolar/urun_deposu.dart';
import '../../servisler/veritabani_dosya_servisi.dart';
import '../../cekirdek/sabitler/db_sabitleri.dart';
import '../../cekirdek/sabitler/uygulama_sabitleri.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/ortak/yukleniyor_widget.dart';
import '../../widgetlar/ortak/onay_dialog.dart';
import '../../saglayicilar/riverpod/tema_provider.dart';
import '../../servisler/bulut/supabase_ayarlari.dart';
part 'ayarlar_ekrani_islemler.dart';

class AyarlarEkrani extends ConsumerStatefulWidget {
  const AyarlarEkrani({super.key});
  @override
  ConsumerState<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends ConsumerState<AyarlarEkrani> {
  final _ayarlarDepo = AyarlarDeposu();
  final _urunDepo = UrunDeposu();
  Map<String, String> _ayarlar = {};
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (mounted) setState(() => _yukleniyor = true);
    try {
      final ayarlar = await _ayarlarDepo.hepsiGetir();
      if (mounted) {
        setState(() {
          _ayarlar = ayarlar;
          _yukleniyor = false;
        });
      }
    } catch (e) {
      // 🔴 DÜZELTME: catch bloğu _yukleniyor'u hiç false yapmıyordu —
      // hata olursa ekran sonsuza kadar "yükleniyor" durumunda kalıyordu.
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ayarGuncelle(String anahtar, String deger) async {
    try {
      await _ayarlarDepo.kaydet(anahtar, deger);
      if (mounted) setState(() => _ayarlar[anahtar] = deger);
    } catch (e) {
      if (kDebugMode) debugPrint('Ayar kaydetme hatası: $e');
    }
  }

  Future<void> _cikisYap() async {
    bool onay = false;
    try {
      onay = await OnayDialog.goster(
        context,
        baslik: 'Çıkış Yap',
        icerik: 'Oturumu kapatmak istiyor musunuz?',
        onayYazi: 'Çıkış Yap',
        onayRengi: Colors.red,
        ikon: Icons.logout,
      );
    } catch (_) {
      onay = false;
    }
    if (!onay || !mounted) return;
    try {
      await ref.read(authProvider.notifier).cikisYap();
      if (mounted) context.go('/giris');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Çıkış hatası: $e');
    }
  }

  void _temaDegistir(String tema) {
    // ÖNEMLİ DÜZELTME: Önceden sadece SharedPreferences'a yazılıyordu,
    // canlı tema (MaterialApp) hiç güncellenmiyordu — kullanıcı "Koyu Tema"
    // seçtiğinde uygulama yeniden başlatılana kadar hiçbir şey değişmiyordu.
    // Artık temaProvider üzerinden değiştiriliyor; ekran anında güncelleniyor.
    ref.read(temaProvider.notifier).degistir(tema);
    setState(() => _ayarlar['tema'] = tema);
  }

  // ── VERİTABANINI TEMİZLE (DÜZELTİLMİŞ) ─────────────────────────────────────
  // lib/ekranlar/ayarlar/ayarlar_ekrani.dart
// ... (üstteki kodlar aynı) ...

  Future<bool> _onWillPop() async {
    final isFirst = ModalRoute.of(context)?.isFirst ?? false;
    if (isFirst) {
      final exitConfirmed = await OnayDialog.goster(
        context,
        baslik: 'Uygulamadan Çık',
        icerik: 'Uygulamadan çıkmak istediğinize emin misiniz?',
        onayYazi: 'Evet, Çık',
        onayRengi: Colors.red,
      );
      if (exitConfirmed) exit(0);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final aktif = AuthServisi().aktifKullanici;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        appBar: TsAppBar(
          baslik: 'Ayarlar',
          lider: BackButton(onPressed: () => context.go('/')),
        ),
        body: _yukleniyor
            ? const AppYukleniyor()
            : ListView(children: [
                const _AyarBaslik('Hesap'),
                ListTile(
                  leading: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Color(0xFF4361EE), Color(0xFF3A0CA3)]),
                          shape: BoxShape.circle),
                      child: Center(
                          child: Text(
                              aktif?.adSoyad.isNotEmpty == true
                                  ? aktif!.adSoyad[0]
                                  : 'K',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)))),
                  title: Text(aktif?.adSoyad ?? ''),
                  subtitle: Text(aktif?.rol ?? ''),
                  trailing: TextButton(
                      onPressed: () => context.push('/sifre'),
                      child: const Text('Şifre Değiştir')),
                ),
                const Divider(),
                const _AyarBaslik('Firma'),
                ListTile(
                  leading:
                      const Icon(Icons.business, color: AppRenkler.primary),
                  title: Text(_ayarlar['firma_adi'] ?? 'BarkoPro'),
                  subtitle: Text(_ayarlar['firma_adres'] ?? 'Adres girilmemiş'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _firmaBilgisiDuzenle,
                ),
                const Divider(),
                const _AyarBaslik('Görünüm'),
                RadioGroup<String>(
                  groupValue: _ayarlar['tema'] ?? 'light',
                  onChanged: (v) => _temaDegistir(v!),
                  child: const Column(mainAxisSize: MainAxisSize.min, children: [
                    RadioListTile<String>(title: Text('Açık Tema'), value: 'light'),
                    RadioListTile<String>(title: Text('Koyu Tema'), value: 'dark'),
                  ]),
                ),
                const Divider(),
                // 🆕 Hızlı tuş yönetimi — kasadaki favori ürün panelini
                // buradan da düzenlenebilir yaptık (birincil giriş yolu
                // Hızlı Satış ekranındaki şimşek butonu).
                const _AyarBaslik('Satış'),
                ListTile(
                  leading:
                      const Icon(Icons.bolt_rounded, color: Color(0xFF4361EE)),
                  title: const Text('Hızlı Tuşlar'),
                  subtitle: const Text(
                      'Barkodsuz/sık satılan ürünler için kasa tuşları '
                      '(ekmek, poşet, çay, su)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/satis/hizli-tuslar'),
                ),
                const Divider(),
                const _AyarBaslik('Sistem'),
                SwitchListTile(
                  secondary: const Icon(Icons.table_restaurant,
                      color: Color(0xFF6D4C41)),
                  title: const Text('Masa / Restoran Modülü'),
                  subtitle: const Text(
                      'Sadece kafe/lokanta hizmeti olan şubelerde açın. '
                      'Kapatırsanız "Masalar" ve "Mutfak/Bar" ana ekrandan gizlenir.'),
                  value: ref.watch(masaModuProvider),
                  onChanged: (v) =>
                      ref.read(masaModuProvider.notifier).degistir(v),
                ),
                if (ref.watch(masaModuProvider))
                  ListTile(
                      leading: const Icon(Icons.add_box_outlined,
                          color: Color(0xFF6D4C41)),
                      title: const Text('Masa Ekle / Yönet'),
                      subtitle: const Text(
                          'Tek veya toplu masa ekle · QR menü kartlarını yazdır'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/masa/yonet')),
                ListTile(
                    leading: const Icon(Icons.print, color: AppRenkler.primary),
                    title: const Text('Yazdırma Merkezi'),
                    subtitle: const Text(
                        'Yazıcılar · Fiş Tasarımı · Fatura Ayarları — tek sayfa'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/yazdirma')),
                ListTile(
                    leading: const Icon(Icons.store, color: Colors.indigo),
                    title: const Text('Şube Yönetimi'),
                    subtitle: const Text('Çoklu şube ekle ve yönet'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/sube')),
                ListTile(
                    leading:
                        const Icon(Icons.local_shipping, color: Colors.teal),
                    title: const Text('İrsaliye / Sevkiyat'),
                    subtitle: const Text('Sevk irsaliyeleri yönetimi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/irsaliye')),
                ListTile(
                    leading: const Icon(Icons.inventory_2, color: Colors.brown),
                    title: const Text('Lot / Seri No Takibi'),
                    subtitle: const Text('SKT ve lot takibi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/lot')),
                ListTile(
                    leading: const Icon(Icons.auto_graph, color: Colors.purple),
                    title: const Text('Akıllı Analiz'),
                    subtitle:
                        const Text('Yapay zeka destekli satış analizleri'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ai')),
                ListTile(
                    leading: const Icon(Icons.receipt_long, color: Colors.red),
                    title: const Text('GIB e-Fatura Entegrasyonu'),
                    subtitle: const Text('e-Fatura / e-Arşiv yapılandırması'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/gib')),
                ListTile(
                    leading:
                        const Icon(Icons.backup, color: AppRenkler.primary),
                    title: const Text('Yedekleme'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/yedek')),
                ListTile(
                    leading:
                        const Icon(Icons.people, color: AppRenkler.primary),
                    title: const Text('Kullanıcı Yönetimi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/kullanici')),
                ListTile(
                    leading:
                        const Icon(Icons.bar_chart, color: AppRenkler.primary),
                    title: const Text('Günlük Rapor'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/rapor/gunluk')),
                const Divider(),
                const _AyarBaslik('Kategoriler & Diğer'),
                ListTile(
                    leading:
                        const Icon(Icons.category, color: AppRenkler.primary),
                    title: const Text('Kategoriler'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/urun/kategori')),
                ListTile(
                    leading: const Icon(Icons.branding_watermark,
                        color: AppRenkler.primary),
                    title: const Text('Markalar'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/urun/marka')),
                ListTile(
                    leading: const Icon(Icons.label, color: AppRenkler.primary),
                    title: const Text('Etiket Yazdır'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/barkod/etiket')),
                ListTile(
                    leading:
                        const Icon(Icons.qr_code_2, color: Colors.deepPurple),
                    title: const Text('Barkod Üreteci'),
                    subtitle: const Text('EAN-13, QR, Code128 üret ve kaydet'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/barkod/uret')),
                ListTile(
                    leading: const Icon(Icons.local_offer,
                        color: AppRenkler.primary),
                    title: const Text('Promosyonlar'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/promosyon')),
                ListTile(
                    leading: const Icon(Icons.local_shipping,
                        color: AppRenkler.primary),
                    title: const Text('Tedarikçi Siparişleri'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/tedarik')),
                ListTile(
                    leading: const Icon(Icons.lightbulb_outline,
                        color: AppRenkler.primary),
                    title: const Text('Satın Alma Önerileri'),
                    subtitle: const Text('Kritik stoktaki ürünler için sipariş önerisi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/tedarik/oneriler')),
                ListTile(
                    leading: const Icon(Icons.straighten, color: Colors.brown),
                    title: const Text('Birim Yönetimi'),
                    subtitle: const Text('Adet, kg, lt gibi birimler'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/birim')),
                ListTile(
                    leading: Icon(Icons.history, color: context.textSecondary),
                    title: const Text('Sistem Logları'),
                    subtitle: const Text('Hata ve işlem kayıtları'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/log')),
                ListTile(
                    leading: Icon(Icons.currency_exchange,
                        color: context.textSecondary),
                    title: const Text('Döviz Kurları'),
                    subtitle: const Text('USD, EUR, GBP karşılıkları'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/doviz')),
                ListTile(
                    leading: Icon(Icons.smart_toy_outlined,
                        color: context.textSecondary),
                    title: const Text('AI Asistan Ayarları'),
                    subtitle: const Text(
                        'Gemini API anahtarı, akıllı sohbet ve foto doldurma'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/ai-asistan')),
                ListTile(
                  leading: const Icon(Icons.cloud_sync, color: Colors.blue),
                  title: const Text('Bulut Senkronizasyon'),
                  subtitle:
                      const Text('Supabase ile bulut veri senkronizasyonu'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/bulut-sync'),
                ),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined, color: Colors.deepOrange),
                  title: const Text('Hata İzleme'),
                  subtitle: const Text(
                      'Uygulama hatalarını uzaktan görmek için Sentry bağlayın (isteğe bağlı)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/hata-izleme'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined,
                      color: Colors.teal),
                  title: const Text('İşyeri Fotoğrafları (Web Sitesi)'),
                  subtitle: const Text(
                      'QR menü sitesindeki fotoğrafları buradan yönetin'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/site-fotograflari'),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.edit_note_outlined, color: Colors.teal),
                  title: const Text('Site İçeriği (Web Sitesi)'),
                  subtitle: const Text(
                      'İşletme adı, hakkımızda, iletişim ve konum bilgilerini buradan düzenleyin'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/site-icerik'),
                ),
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.deepPurple),
                  title: const Text('İşlem Geçmişi (Audit Log)'),
                  subtitle: const Text('Kim, ne zaman, ne değiştirdi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/audit-log'),
                ),
                ListTile(
                  leading: const Icon(Icons.format_list_numbered,
                      color: Colors.indigo),
                  title: const Text('Fatura Seri Mutabakatı'),
                  subtitle: const Text(
                      'Numara blokları, kullanılan/kalan numaralar, boşluk kontrolü'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/seri-mutabakati'),
                ),
                ListTile(
                  leading: const Icon(Icons.point_of_sale_outlined,
                      color: Colors.indigo),
                  title: const Text('Terminaller'),
                  subtitle: const Text(
                      'Fatura kesen cihazlar — ad verme, kaybolan cihazı pasife alma'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/terminaller'),
                ),
                ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined,
                      color: Colors.green),
                  title: const Text('Veri Sağlığı Merkezi'),
                  subtitle: const Text(
                      'Mutabakat, negatif stok, mükerrer barkod, sync durumu'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/veri-sagligi'),
                ),
                ListTile(
                  leading: const Icon(Icons.event_repeat_outlined,
                      color: Colors.indigo),
                  title: const Text('Dönem Yönetimi / Yıl Sonu Devir'),
                  subtitle: const Text(
                      'Yıl sonu kontrolü, yedekleme, dönem kapatma'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/donem-yonetimi'),
                ),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined,
                      color: Colors.brown),
                  title: const Text('Fiyat Grupları (Bayi/Toptan)'),
                  subtitle: const Text('Bayi tipleri ve toptan fiyatlandırma'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/toptan/fiyat-gruplari'),
                ),
                ListTile(
                    leading:
                        const Icon(Icons.sync_alt, color: AppRenkler.primary),
                    title: const Text('Veri Aktarımı WiFi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/sync')),
                const Divider(),
                const _AyarBaslik('Veri İşlemleri'),
                ListTile(
                    leading: const Icon(Icons.bolt_outlined,
                        color: Colors.deepPurple),
                    title: const Text('Toplu Ürün İşlemi'),
                    subtitle: const Text('Fiyat, grup, KDV toplu güncelleme'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/urun/toplu-islem')),
                ListTile(
                    leading: const Icon(Icons.price_change_outlined,
                        color: Colors.orange),
                    title: const Text('Toplu Fiyat Güncelleme'),
                    subtitle: const Text('Kategori/marka bazlı zam/indirim'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/urun/toplu-fiyat')),
                ListTile(
                    leading: const Icon(Icons.trending_up, color: Colors.green),
                    title: const Text('Kar / Zarar Raporu'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/rapor/kar')),
                ListTile(
                    leading: const Icon(Icons.visibility, color: Colors.green),
                    title: const Text('Pasif Ürünleri Aktif Yap'),
                    subtitle: const Text(
                        'Listede görünmeyen ürünleri aktif hale getir'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pasifleriAktifYap),
                ListTile(
                    leading: const Icon(Icons.upload_file, color: Colors.green),
                    title: const Text('Ürünleri Excel\'e Aktar'),
                    subtitle: const Text('Tüm ürünleri xlsx olarak paylaş'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _urunleriExcelEAktar),
                ListTile(
                    leading: const Icon(Icons.download_for_offline,
                        color: Colors.blue),
                    title: const Text('Excel\'den Ürün Al'),
                    subtitle:
                        const Text('Xlsx dosyasından toplu yükle/güncelle'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _exceldenUrunIceAl),
                ListTile(
                    leading: const Icon(Icons.download, color: Colors.purple),
                    title: const Text('Veritabanını İçe Aktar'),
                    subtitle: const Text('.db dosyasından geri yükleme yap'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _veritabaniniIceriAl),
                ListTile(
                    leading:
                        const Icon(Icons.upload_file, color: Colors.orange),
                    title: const Text('Veritabanını Dışa Aktar'),
                    subtitle: const Text(
                        '${DbSabitler.dbAdi} dosyasını kaydet/paylaş'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _dbDisariAktar),
                ListTile(
                    leading: const Icon(Icons.delete_sweep, color: Colors.red),
                    title: const Text('Veritabanını Temizle',
                        style: TextStyle(color: Colors.red)),
                    subtitle: const Text('Tüm verileri kalıcı olarak siler'),
                    trailing:
                        const Icon(Icons.warning_amber, color: Colors.red),
                    onTap: _veritabaniniTemizle),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Çıkış Yap',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600)),
                  onTap: _cikisYap,
                ),
                const SizedBox(height: 8),
                Center(
                    child: Text('BarkoPro v${UygSabitler.versiyon}',
                        style: TextStyle(
                            color: TsRenk.metinIkincil(context),
                            fontSize: 12))),
                const SizedBox(height: 16),
              ]),
      ),
    );
  }
}

// ── Yardımcı widget'lar ───────────────────────────────────────────────────────
