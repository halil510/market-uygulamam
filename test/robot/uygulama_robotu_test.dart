// test/robot/uygulama_robotu_test.dart
//
// UYGULAMA ROBOTU — tüm ekranları bir kullanıcı gibi gezer:
//   1. Sanal işletme verisi tohumlar, admin (1234) ile gerçek giriş yapar.
//   2. Yönlendiricideki (GoRouter) TÜM rotaları otomatik toplar.
//   3. Her ekranı açar; çökme, kırmızı hata ekranı, taşma (overflow),
//      takılı kalan "yükleniyor" ve istemeden yönlendirmeyi kaydeder.
//   4. Formlardaki metin alanlarına etiketine uygun (benzersiz, geçerli
//      TCKN/VKN/EAN-13) sanal veri yazar, boş açılır listelerden seçer,
//      ürün arama kutusunda gerçek ürünü aratıp sonucu seçer, "Kaydet/Ekle"
//      butonuna basar, onay penceresini onaylar. Kaydedecek formu olmayan
//      liste ekranlarında "+" (FAB / ekle ikonu) ile yeni kayıt açar.
//      Her kayıttan sonra tablo satır sayılarını karşılaştırıp kaydın
//      GERÇEKTEN veritabanına yazıldığını doğrular ("kayıtsız" bulgusu).
//   5. Sonunda veri bütünlüğü kurallarını denetler (cari bakiye = hareketler).
//   6. Raporu build/robot_raporu.md dosyasına yazar.
//
// Çalıştırma:  flutter test test/robot --dart-define=ROBOT=true
// Varsayılan olarak RAPOR üretir, testi düşürmez. Kesin mod için:
//   flutter test test/robot --dart-define=ROBOT_KESIN=true
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/servisler/auth_servisi.dart';
import 'package:market_plus/servisler/masa/qr_siparis_cekici_servisi.dart';
import 'package:market_plus/uygulama/uygulama.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'robot_ortam.dart';

class _Bulgu {
  final String rota, tur, mesaj;
  _Bulgu(this.rota, this.tur, this.mesaj);
}

/// Tohum verisinden rota parametresi doldurur.
String _parametreDoldur(String yol, RobotVeri v) {
  int id(String k) => v.id[k] ?? 1;
  return yol.replaceAllMapped(RegExp(r':(\w+)'), (m) {
    final p = m.group(1)!;
    if (yol.startsWith('/cari')) return '${id('cari')}';
    if (yol.startsWith('/banka/hesap') || yol.startsWith('/banka/kredi')) return '${id('banka')}';
    if (yol.startsWith('/banka/detay')) return '${id('bankaHesap')}';
    if (yol.startsWith('/masa')) {
      if (p == 'masaAdi') return 'Masa 1';
      return '${id('masa')}';
    }
    if (yol.startsWith('/urun')) return '${id('urun')}';
    return '1';
  });
}

List<String> _rotalariTopla(List<RouteBase> rotalar, [String ust = '']) {
  final sonuc = <String>[];
  for (final r in rotalar) {
    var tam = ust;
    if (r is GoRoute) {
      tam = r.path.startsWith('/')
          ? r.path
          : '${ust.endsWith('/') ? ust : '$ust/'}${r.path}';
      sonuc.add(tam);
    }
    sonuc.addAll(_rotalariTopla(r.routes, tam));
  }
  return sonuc;
}

const _atlanacak = {'/splash', '/giris', '/kullanici-degistir'};

/// Tek ekranı ayrıntılı (tam hata yığınıyla) denemek için:
///   flutter test test/robot --dart-define=ROBOT_ROTA=/stok/transfer
const _tekRota = String.fromEnvironment('ROBOT_ROTA');

/// Gerçek cihazda tüm rotaları tek seferde koşmak telefonu zorlar: rota
/// listesini dilimlemek için (ör. --dart-define=ROBOT_BASLA=20 --dart-define=ROBOT_ADET=20).
const _dilimBasla = int.fromEnvironment('ROBOT_BASLA', defaultValue: 0);
const _dilimAdet = int.fromEnvironment('ROBOT_ADET', defaultValue: 0);

/// Bulgu sınıfı: HATA yalnızca gerçek uygulama hatası; eklenti eksikliği,
/// taşma, görsel uyarı ve gezinme (ekran parametresiz açılınca kendini
/// kapatma / robotun sayfa kapatması) ayrı sayılır.
String _sinifla(String m) {
  if (m.contains('MissingPluginException')) return 'ortam';
  if (m.contains('overflowed')) return 'taşma';
  if (m.contains('ink splashes may be invisible')) return 'görsel';
  if (m.contains('_debugLocked') || m.contains('nothing to pop') ||
      m.contains('popped the last page')) return 'gezinme';
  return 'HATA';
}

/// Her doldurmada artan sayaç: ekranlar arası ad/barkod/kullanıcı adı
/// çakışmasın (aksi halde "zaten kayıtlı" diye haklı olarak reddediliyordu).
var _sayac = 0;

/// Ürün arama alanlarına yazılan, tohumda var olan ürün.
const _aranacakUrun = 'Robot Çikolata';
const _aranabilir = {_aranacakUrun, 'Robot Tedarikçi', 'Robot Müşteri', 'Robot Bayi'};

/// Kaydet/işlem butonu veritabanına satır yazmayan (hesaplayıcı, sepete/
/// baskı listesine ekleyen, görsel üreten) ekranlar — "kayıtsız" sayılmaz.
const _kayitBeklenmeyen = {
  '/satis/para-ustu', '/barkod/uret', '/barkod/etiket', '/satis/sicak',
  '/satis/soguk', '/urun/fiyat-simulasyon',
};

/// 869 önekli, kontrol hanesi doğru, benzersiz EAN-13.
String _ean13(int n) {
  final govde = '869${(1000000 + n).toString().padLeft(9, '0')}';
  var t = 0;
  for (var i = 0; i < 12; i++) {
    t += int.parse(govde[i]) * (i.isEven ? 1 : 3);
  }
  return '$govde${(10 - t % 10) % 10}';
}

String _sanalDeger(TextField t) {
  final d = t.decoration;
  final etiket = '${d?.labelText ?? ''} ${d?.hintText ?? ''}'.toLowerCase();
  final sayisal = t.keyboardType == TextInputType.number ||
      RegExp(r'fiyat|tutar|miktar|stok|adet|oran|limit|bakiye|kdv|iskonto|indirim|puan|gün|vade|sayı|no\b|%|₺|kasa|maaş|kişi')
          .hasMatch(etiket);
  final n = ++_sayac;
  if (t.obscureText) return '1234';
  // Arama kutuları: tohumdaki gerçek bir kaydı arat (sonuç seçilebilsin).
  if (etiket.contains('ara') || etiket.contains('seç')) {
    if (etiket.contains('tedarikçi')) return 'Robot Tedarikçi';
    if (etiket.contains('cari') || etiket.contains('müşteri') || etiket.contains('bayi')) {
      return etiket.contains('bayi') ? 'Robot Bayi' : 'Robot Müşteri';
    }
    if (etiket.contains('ürün') || etiket.contains('barkod')) return _aranacakUrun;
  }
  // Belge numaraları boş bırakılır — uygulama merkezi seriden otomatik verir.
  if (RegExp(r'fatura no|fiş no|irsaliye no|belge no').hasMatch(etiket)) return '';
  if (etiket.contains('telefon') || etiket.contains('gsm')) return '0532${(1000000 + n).toString().padLeft(7, '0')}';
  if (etiket.contains('mail')) return 'robot$n@test.com';
  if (etiket.contains('barkod')) return _ean13(n);
  // Geçerli (kontrol haneli) numaralar — uygulama biçimi doğruluyor.
  if (RegExp(r'\btc\b|kimlik').hasMatch(etiket)) return '10000000146';
  if (etiket.contains('vergi no') || etiket.contains('vkn')) return '1234567890';
  if (etiket.contains('iban')) return 'TR330006100519786457841326';
  if (sayisal) return '12';
  return 'Robot ${etiket.trim().split(' ').first} $n'.trim();
}

/// "Yeni kayıt ekle" anlamındaki ikonlar (FAB dışındaki + düğmeleri).
final _ekleIkonlari = <IconData>{
  Icons.add, Icons.add_circle, Icons.add_circle_outline, Icons.add_box,
  Icons.add_box_outlined, Icons.person_add, Icons.person_add_alt_1,
  Icons.playlist_add, Icons.add_business, Icons.add_card,
};

/// Kayıt sayısı karşılaştırmasında sayılmayan (her işlemde yan etki olarak
/// büyüyen) günlük/kuyruk tabloları.
const _yanTablolar = {
  'audit_log', 'sync_queue', 'sync_log', 'log', 'hata_log', 'uygulama_log',
  'bildirimler', 'sqlite_sequence',
};

/// Doğrulama (validation) mesajı gibi görünen metinler — kayıt oluşmadığında
/// nedenini rapora yazmak için.
final _dogrulamaRe = RegExp(
    r'zorunlu|gerekli|giriniz|girin|seçiniz|seçin|boş olamaz|geçersiz|en az|hatalı|bulunamadı|zaten',
    caseSensitive: false);

/// Ekranda (metin/uyarı çubuğu olarak) görünen ham hata imzaları —
/// uygulama hatayı yakalayıp kullanıcıya "Hata: …" diye yazdıysa da bulgu.
final _ekranHataRe = RegExp(
    r'Exception|Error:|SqfliteFfiException|DatabaseException|Null check operator|'
    r'no such (table|column)|is not a subtype of|Bad state:|RangeError|NoSuchMethodError|'
    r'constraint failed|bir şeyler ters gitti');

/// Robotun asla basmadığı ikonlar (sil, çıkış, temizle…).
final _yikiciIkonlar = <IconData>{
  Icons.delete, Icons.delete_forever, Icons.delete_outline, Icons.delete_sweep,
  Icons.logout, Icons.power_settings_new, Icons.clear_all, Icons.restore,
  Icons.cloud_upload, Icons.cloud_download, Icons.backup, Icons.block,
};

/// Uygulamanın başarı bildirimleri (kayıt güncellendi / işlem tamam).
final _basariRe = RegExp(r'kaydedildi|eklendi|oluşturuldu|güncellendi|tamamlandı|başarı',
    caseSensitive: false);

final _kaydetRe = RegExp(r'^(kaydet|ekle|tamam|oluştur|onayla|güncelle|kaydet ve kapat|satışı tamamla)$',
    caseSensitive: false);
final _onayRe = RegExp(r'^(evet.*|tamam|onayla|kaydet|devam.*|sil)$', caseSensitive: false);

/// "Kaydet" dışındaki gerçek işlem butonları (Tahsilat Kaydet, Virmanı
/// Gerçekleştir, Faturayı Oluştur, Vardiya Aç, Borç Ekle, Sipariş Ver…).
final _islemRe = RegExp(
    r'kaydet|ekle$|oluştur|gerçekleştir|başlat|\baç$|al$|ver$|yap$|üret$|kullan$|değiştir$|güncelle',
    caseSensitive: false);

/// Robotun ASLA basmadığı butonlar: veri silen/sıfırlayan, dönem/devir
/// yapan, dış servise bağlanan/gönderen, kamera/ağ tarayan, gezinen.
final _yasakRe = RegExp(
    // Not: Dart'ta 'İ'.toLowerCase() noktalı i üretir; büyük İ'li kelimeler
    // (İptal, İade…) ayrıca yazılmalı.
    r'sil|sıfırla|temizle|iptal|İptal|vazgeç|kapat|test|bağla|tara|okut|dönem|devir|arşiv|geri yükle|gönder|çıkış|'
    r'doğrula|git$|ana sayfa|tümünü|seç|doldur|birim ekle|dövizle|kalem ekle|tekrar dene|'
    r'gör$|hareketler|ağı|manuel ip|şifre değiştir',
    caseSensitive: false);

void main() {
  testWidgets('UYGULAMA ROBOTU — tüm ekranlar', (tester) async {
    // Gerçek cihazda (Android) telefonun kendi ekran boyutu kullanılır;
    // masaüstü/CI'da sabit tablet boyutu.
    if (!Platform.isAndroid) {
      // ROBOT_EKRAN=telefon → Galaxy A51 (SM-A515F): 1080x2400, DPR 2.625
      // (411x914 dp) — gerçek telefon ölçüsünde taşma taraması.
      if (const String.fromEnvironment('ROBOT_EKRAN') == 'telefon') {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.625;
      } else {
        tester.view.physicalSize = const Size(1280, 2000);
        tester.view.devicePixelRatio = 1.0;
      }
      addTearDown(tester.view.reset);
    }

    await RobotOrtam.hazirla();
    final db = await RobotOrtam.veritabaniAc();
    final veri = await RobotOrtam.tohumla(db);
    expect(await AuthServisi().girisYap('admin', '1234'), isTrue,
        reason: 'robot admin ile giriş yapamadı');

    final bulgular = <_Bulgu>[];
    var aktifRota = '(açılış)';
    final eskiOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      final tur = _sinifla(m);
      bulgular.add(_Bulgu(aktifRota, tur, m.split('\n').first));
      if (_tekRota.isNotEmpty) FlutterError.dumpErrorToConsole(d, forceReport: true);
    };

    Future<void> bekle([int adim = 12]) async {
      for (var i = 0; i < adim; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      final e = tester.takeException();
      if (e != null) {
        final m = e.toString();
        bulgular.add(_Bulgu(aktifRota, _sinifla(m), m.split('\n').first));
      }
    }

    /// Bulunan pencerelerden hâlâ AKTİF ve EN ÜSTTE olanın rotasını kapatır.
    /// Kapanış animasyonundaki pencere ağaçta görünmeye devam eder; ona
    /// tekrar pop çağırmak alttaki SAYFAYI kapatıyordu (go_router "son sayfa
    /// kapatıldı" iddiası — Fiyat Gör kilidi).
    bool pencereKapat(Finder f) {
      for (final e in f.evaluate()) {
        final rota = ModalRoute.of(e);
        if (rota != null && rota.isActive && rota.isCurrent && rota is PopupRoute) {
          rota.navigator!.pop();
          return true;
        }
      }
      return false;
    }

    /// Tablo başına satır sayısı (yan günlük tabloları hariç).
    Future<Map<String, int>> tabloSayilari() async {
      final tablolar = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
      final m = <String, int>{};
      for (final t in tablolar) {
        final ad = t['name'] as String;
        if (_yanTablolar.contains(ad)) continue;
        final r = await db.rawQuery('SELECT COUNT(*) AS n FROM "$ad"');
        m[ad] = (r.first['n'] as int?) ?? 0;
      }
      return m;
    }

    String artanlar(Map<String, int> once, Map<String, int> sonra) => sonra.entries
        .where((e) => e.value > (once[e.key] ?? 0))
        .map((e) => '${e.key}+${e.value - (once[e.key] ?? 0)}')
        .join(',');

    /// Son formda robotun yazdığı "etiket=değer" çiftleri (kayıt
    /// oluşmadığında rapora eklenir).
    final sonDoldurulan = <String>[];

    /// Seçimi boş açılır listelerde ilk seçeneği seçer (zorunlu açılır
    /// listeler — ör. cari tipi, birim — boş kalıp kaydı engellemesin).
    Future<int> acilirListeSec() async {
      var secilen = 0;
      for (var i = 0; i < 4; i++) {
        // dynamic erişim: DropdownButton<int>'in onChanged'i
        // DropdownButton<dynamic> tipiyle okunursa tip hatası fırlatıyor.
        // Ekran dışına kaymış (ör. formun en üstündeki Cari) listeleri de
        // bul; önce görünür alana kaydır.
        final bos = find.byWidgetPredicate((w) {
          if (w is! DropdownButton) return false;
          final dw = w as dynamic;
          return dw.value == null && dw.onChanged != null &&
              ((dw.items as List?)?.isNotEmpty ?? false);
        });
        if (bos.evaluate().isEmpty) break;
        try {
          await tester.ensureVisible(bos.first);
          await bekle(4);
          await tester.tap(bos.first, warnIfMissed: false);
          await bekle(6);
          final ogeler = find.byWidgetPredicate((w) => w is DropdownMenuItem && w.value != null);
          if (ogeler.evaluate().isEmpty) break;
          await tester.tap(ogeler.last, warnIfMissed: false);
          await bekle(6);
          secilen++;
        } catch (_) {
          break;
        }
      }
      return secilen;
    }

    /// Görünen metin alanlarını sanal veriyle doldurur, açılır listeleri
    /// seçer, Kaydet/Ekle'ye basar ve onay penceresini onaylar.
    /// Döner: (doldurulan alan sayısı, basılan buton metni).
    /// En üstteki (kullanıcının gördüğü) rota — bir butonun yeni pencere/
    /// sayfa açıp açmadığını anlamak için.
    ModalRoute<dynamic>? ustRota() {
      final e = find.byType(Text).hitTestable().evaluate();
      return e.isEmpty ? null : ModalRoute.of(e.first);
    }

    /// Butonun görünen metni (içindeki Text'ler).
    String butonMetni(Element e) => find
        .descendant(of: find.byWidget(e.widget), matching: find.byType(Text))
        .evaluate()
        .map((t) => ((t.widget as Text).data ?? '').trim())
        .where((s) => s.isNotEmpty)
        .join(' ');

    /// Açık seçim penceresindeki (en üst popup) ilk kayda dokunur.
    Future<bool> ilkKaydiSec() async {
      final ust = ustRota();
      final ogeler = find.byWidgetPredicate((w) =>
          w is ListTile && w.onTap != null && w.enabled).hitTestable();
      for (final e in ogeler.evaluate()) {
        if (ModalRoute.of(e) != ust) continue;
        final m = butonMetni(e);
        if (_yasakRe.hasMatch(m)) continue;
        await tester.tap(find.byWidget(e.widget).first, warnIfMissed: false);
        await bekle(10);
        return true;
      }
      return false;
    }

    /// "Tedarikçi Seç / Cari Seç / Müşteri Seç…" seçicilerine dokunup
    /// açılan listeden ilk kaydı seçer.
    Future<void> seciciDoldur() async {
      final seciciler = find.byWidgetPredicate((w) =>
          w is Text && RegExp(r'^(Tedarikçi|Cari|Müşteri|Bayi|Banka Hesabı|Hesap) Seç',
              caseSensitive: false).hasMatch((w.data ?? '').trim())).hitTestable();
      for (var i = 0; i < 3; i++) {
        if (seciciler.evaluate().isEmpty) break;
        final onceki = ustRota();
        await tester.tap(seciciler.first, warnIfMissed: false);
        await bekle(10);
        if (ustRota() == onceki) break;
        final secildi = await ilkKaydiSec();
        if (!secildi) {
          pencereKapat(find.byWidgetPredicate((w) => w is Dialog || w is BottomSheet));
          await bekle(8);
          break;
        }
        sonDoldurulan.add('seçici=${find.byWidgetPredicate((w) => w is Text).evaluate().isEmpty ? '' : 'ilk kayıt'}');
      }
    }

    /// Buton/öğe sil-çıkış-temizle gibi yıkıcı bir ikon taşıyor mu?
    bool yikiciIkonluMu(Element e) => find
        .descendant(of: find.byWidget(e.widget), matching: find.byType(Icon))
        .evaluate()
        .any((i) => _yikiciIkonlar.contains((i.widget as Icon).icon));

    /// "Beyaz üstüne beyaz" — yazı rengi ile ÜSTÜNE ÇİZİLDİĞİ zemin arasındaki
    /// kontrast çok düşükse (okunmuyorsa) bulgu. Zemin: en yakın opak Material /
    /// ColoredBox / düz renkli kutu; gradyan veya resim görülürse kontrol edilmez.
    void okunmayanYazilar(String asama) {
      double parlaklik(Color c) {
        double k(double v) => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
        return 0.2126 * k(c.r) + 0.7152 * k(c.g) + 0.0722 * k(c.b);
      }
      double kontrast(Color a, Color b) {
        final x = parlaklik(a), y = parlaklik(b);
        return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
      }
      Color? zeminBul(Element e) {
        Color? sonuc;
        var bilinmiyor = false;
        e.visitAncestorElements((a) {
          final w = a.widget;
          Color? c;
          if (w is Material && w.type != MaterialType.transparency) c = w.color;
          if (w is ColoredBox) c = w.color;
          if (w is DecoratedBox && w.decoration is BoxDecoration) {
            final d = w.decoration as BoxDecoration;
            if (d.gradient != null || d.image != null) { bilinmiyor = true; return false; }
            c = d.color;
          }
          if (w is Ink) {
            // Çipler zeminlerini Ink(decoration: ShapeDecoration/BoxDecoration) ile çizer.
            final d = w.decoration;
            if (d is BoxDecoration && d.gradient == null && d.image == null) c = d.color;
            else if (d is ShapeDecoration && d.gradient == null && d.image == null) c = d.color;
            else { bilinmiyor = true; return false; }
          }
          // Degrade başlık çubukları / üst üste katmanlar: zemin yazının atası
          // değil yanındaki katman — güvenle bilinemez, kontrol edilmez.
          if (w is Image || w is AppBar || w is SliverAppBar || w is FlexibleSpaceBar ||
              w is Stack) { bilinmiyor = true; return false; }
          if (w is Scaffold) c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
          if (c != null && c.a > 0.85) { sonuc = c; return false; }
          return true;
        });
        return bilinmiyor ? null : sonuc;
      }
      final goruldu = <String>{};
      for (final e in find.byType(RichText).hitTestable().evaluate()) {
        final ro = e.renderObject;
        if (ro is! RenderParagraph) continue;
        final metin = ro.text.toPlainText().trim();
        if (metin.length < 2 || !goruldu.add(metin)) continue;
        Color? renk = ro.text.style?.color;
        ro.text.visitChildren((s) { renk ??= s.style?.color; return renk == null; });
        // Rengi tanımsız yazıyı çizim motoru BEYAZ çizer (txt varsayılanı).
        renk ??= const Color(0xFFFFFFFF);
        final zemin = zeminBul(e);
        const izle = String.fromEnvironment('ROBOT_RENK');
        if (izle.isNotEmpty && metin.contains(izle)) {
          // ignore: avoid_print
          print('RENK [$asama] "$metin": yazı=$renk zemin=$zemin '
              '${renk != null && zemin != null ? 'kontrast=${kontrast(renk!, zemin).toStringAsFixed(2)}' : ''}');
        }
        if (renk == null || zemin == null || renk!.a < 0.3) continue;
        final k = kontrast(renk!, zemin);
        if (k < 1.6) {
          final kisa = metin.length > 40 ? '${metin.substring(0, 40)}…' : metin;
          bulgular.add(_Bulgu(aktifRota, 'okunmuyor',
              '$asama: "$kisa" yazısı zeminle aynı renkte (kontrast ${k.toStringAsFixed(2)})'));
        }
      }
    }

    /// Ekranda görünen ham hata metinlerini (uygulamanın yakalayıp
    /// gösterdiği) bulgu olarak ekler.
    void ekranHataMetni(String asama) {
      final metinler = find
          .byWidgetPredicate((w) => w is Text && _ekranHataRe.hasMatch(w.data ?? ''))
          .evaluate()
          .map((e) => ((e.widget as Text).data ?? '').trim().split('\n').first)
          .toSet();
      for (final m in metinler.take(3)) {
        final kisa = m.length > 160 ? '${m.substring(0, 160)}…' : m;
        bulgular.add(_Bulgu(aktifRota,
            m.contains('MissingPluginException') ? 'ortam' : 'ekranda-hata',
            '$asama: "$kisa"'));
      }
      okunmayanYazilar(asama);
    }

    /// İzinli ilk işlem butonu (etkin, görünen, yasak listesinde olmayan).
    (Finder, String)? islemButonu() {
      final adaylar = find.byWidgetPredicate((w) =>
          (w is ButtonStyleButton && w.onPressed != null) ||
          (w is FloatingActionButton && w.onPressed != null)).hitTestable();
      for (var i = 0; i < adaylar.evaluate().length; i++) {
        final e = adaylar.evaluate().elementAt(i);
        final m = butonMetni(e);
        if (m.isEmpty || _yasakRe.hasMatch(m) || yikiciIkonluMu(e)) continue;
        if (_kaydetRe.hasMatch(m) || _islemRe.hasMatch(m)) return (adaylar.at(i), m);
      }
      return null;
    }

    Future<(int, String)> formuDoldurVeKaydet({int derinlik = 0}) async {
      if (derinlik == 0) sonDoldurulan.clear();
      final baslangicRota = ustRota();
      // Alanlar her adımda YENİDEN bulunur — bir alana yazmak ekranı
      // yeniden çizebilir, eski eleman referansı geçersiz kalır.
      final alanSayisi = find.byType(TextField).hitTestable().evaluate().length;
      var doldurulan = 0;
      for (var i = 0; i < alanSayisi && i < 12; i++) {
        final bul = find.byType(TextField).hitTestable();
        if (bul.evaluate().length <= i) break;
        final t = bul.evaluate().elementAt(i).widget as TextField;
        if (t.readOnly || t.enabled == false) continue;
        try {
          final deger = _sanalDeger(t);
          await tester.enterText(bul.at(i), deger);
          if (_aranabilir.contains(deger)) {
            // Arama sonucunda çıkan kayda dokun (metin kutusunun kendisi hariç).
            await bekle(12);
            final sonuc = find.byWidgetPredicate((w) =>
                w is Text && (w.data ?? '').startsWith(deger)).hitTestable();
            if (sonuc.evaluate().isNotEmpty) {
              await tester.tap(sonuc.first, warnIfMissed: false);
              await bekle(8);
            }
          }
          sonDoldurulan.add('${t.decoration?.labelText ?? t.decoration?.hintText ?? '?'}=$deger');
          doldurulan++;
        } catch (_) {}
      }
      await bekle(4);
      if (doldurulan > 0) await acilirListeSec();
      await seciciDoldur();
      // Bir arama sonucu/seçim başka sayfa ya da pencereye geçirdiyse
      // (ör. tedarikçi seçildi → Sipariş Oluştur sayfası) oradan devam et.
      if (derinlik < 2 && ustRota() != baslangicRota &&
          find.byType(TextField).hitTestable().evaluate().isNotEmpty) {
        final (d2, b2) = await formuDoldurVeKaydet(derinlik: derinlik + 1);
        return (doldurulan + d2, b2.isEmpty ? '' : '(geçiş) → $b2');
      }

      var basildi = '';
      Finder? hedef;
      final kaydetMetni = find.byWidgetPredicate((w) =>
          w is Text && _kaydetRe.hasMatch((w.data ?? '').trim())).hitTestable();
      if (doldurulan > 0 && kaydetMetni.evaluate().isNotEmpty) {
        basildi = (kaydetMetni.evaluate().first.widget as Text).data ?? '';
        hedef = kaydetMetni.first;
      } else {
        final islem = islemButonu();
        if (islem != null) (hedef, basildi) = islem;
      }
      if (hedef != null) {
        final onceki = ustRota();
        await tester.tap(hedef, warnIfMissed: false);
        await bekle(8);
        // Buton bir SEÇİM penceresi açtıysa (ör. "Sipariş Ver" → tedarikçi
        // listesi) ilk kaydı seç.
        if (ustRota() != onceki && ustRota() is PopupRoute &&
            find.byType(TextField).hitTestable().evaluate().isEmpty) {
          if (await ilkKaydiSec()) basildi = '$basildi → (seçildi)';
        }
        // Buton yeni pencere/sayfa açtıysa (ör. "Vardiya Aç" → açılış
        // kasası penceresi, "Cari Ekle" → form sayfası) onu da doldur.
        if (derinlik < 2 && ustRota() != onceki &&
            find.byType(TextField).hitTestable().evaluate().isNotEmpty) {
          final (d2, b2) = await formuDoldurVeKaydet(derinlik: derinlik + 1);
          doldurulan += d2;
          if (b2.isNotEmpty) basildi = '$basildi → $b2';
          return (doldurulan, basildi);
        }
        // Açılan onay penceresini onayla (bir tur).
        final onay = find.descendant(
            of: find.byType(Dialog),
            matching: find.byWidgetPredicate((w) =>
                w is Text && _onayRe.hasMatch((w.data ?? '').trim())));
        if (onay.evaluate().isNotEmpty) {
          await tester.tap(onay.first, warnIfMissed: false);
          await bekle(8);
        }
      }
      return (doldurulan, basildi);
    }

    /// Kayıt oluşmadıysa ekrandaki doğrulama mesajlarını toplar.
    String dogrulamaMesajlari() {
      // Alan altı hata metinleri (form doğrulaması) — hangi alanın olduğuyla.
      final alanHatalari = find
          .byType(InputDecorator)
          .evaluate()
          .map((e) => (e.widget as InputDecorator).decoration)
          .where((d) => d.errorText != null)
          .map((d) => '${d.labelText ?? d.hintText ?? '?'}: ${d.errorText}');
      final metinler = find
          .byWidgetPredicate((w) => w is Text && _dogrulamaRe.hasMatch(w.data ?? ''))
          .evaluate()
          .map((e) => ((e.widget as Text).data ?? '').trim())
          .where((s) => s.length < 90);
      // Uyarı çubuğu / pencere içindeki mesajlar (ör. "zaten kayıtlı").
      final bildirimler = find
          .descendant(
              of: find.byWidgetPredicate((w) => w is SnackBar || w is Dialog),
              matching: find.byType(Text))
          .evaluate()
          .map((e) => ((e.widget as Text).data ?? '').trim())
          .where((s) => s.length > 3 && s.length < 120);
      return {...alanHatalari, ...bildirimler, ...metinler}.take(4).join(' / ');
    }

    /// Ekranda görünen buton metinleri (sekme adları dahil).
    List<String> gorunenButonlar() {
      final butonlar = find.byWidgetPredicate((w) => w is ButtonStyleButton ||
          w is FloatingActionButton || w is Tab || w is ChoiceChip || w is FilterChip);
      return butonlar.hitTestable().evaluate().map((e) {
        final metin = find.descendant(of: find.byWidget(e.widget), matching: find.byType(Text))
            .evaluate()
            .map((t) => ((t.widget as Text).data ?? '').trim())
            .where((s) => s.isNotEmpty)
            .join(' ');
        return '${e.widget.runtimeType}:$metin';
      }).toSet().toList();
    }

    /// Ekrandaki "yeni ekle" düğmesi: önce FAB, yoksa + ikonlu düğme.
    Finder ekleDugmesi() {
      final fab = find.byType(FloatingActionButton).hitTestable();
      if (fab.evaluate().isNotEmpty) return fab;
      return find.byWidgetPredicate((w) =>
          w is IconButton && w.onPressed != null && w.icon is Icon &&
          _ekleIkonlari.contains((w.icon as Icon).icon)).hitTestable();
    }

    final gezilen = <String, String>{}; // rota → sonuç özeti
    final acilisMs = <String, int>{};   // rota → açılış süresi (gerçek saat)
    var kaydirma = 0;
    // Ekranların arka planda fırlattığı (yakalanmamış) hatalar da bulgu olur,
    // testi düşürmez.
    await runZonedGuarded(() async {
    await tester.pumpWidget(const ProviderScope(
        child: BarkoProApp(baslangicTema: robotTema)));
    await bekle(30);

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    var rotalar = _rotalariTopla(router.configuration.routes)
        .where((r) => !_atlanacak.contains(r) && !r.startsWith('/bayi'))
        .where((r) => _tekRota.isEmpty || r == _tekRota)
        .toSet()
        .toList()
      ..sort();
    // ignore: avoid_print
    print('🤖 TOPLAM ROTA: ${rotalar.length}');
    if (_dilimAdet > 0) {
      rotalar = rotalar.skip(_dilimBasla).take(_dilimAdet).toList();
    }

    for (final sablon in rotalar) {
      final yol = _parametreDoldur(sablon, veri);
      aktifRota = yol;
      // ignore: avoid_print
      print('🤖 $yol');
      final once = bulgular.length;
      final kronometre = Stopwatch()..start();
      try {
        // Gerçek kullanımdaki gibi ana sayfanın ÜSTÜNE aç: ekran kaydedip
        // kendini kapattığında (pop) altında bir sayfa bulunsun. Doğrudan
        // go ile açınca pop yığında sayfa bırakmıyor, yarım kalan geçiş
        // sonraki tüm ekranlara "animasyon" bulgusu olarak bulaşıyordu.
        if (yol != '/') {
          router.go('/');
          await bekle(6);
          unawaited(router.push(yol));
        } else {
          router.go(yol);
        }
        await bekle();
        acilisMs[yol] = kronometre.elapsedMilliseconds;
        ekranHataMetni('açılış');
        // push'ta uri alttaki sayfayı gösterir; en üstteki eşleşmeye bak.
        final yapi = router.routerDelegate.currentConfiguration;
        final varilan = yapi.isEmpty ? yapi.uri.path : Uri.parse(yapi.last.matchedLocation).path;
        if (Uri.decodeComponent(varilan) != yol && yol != '/') {
          bulgular.add(_Bulgu(yol, 'yönlendirildi', 'açılmadı, $varilan adresine gitti'));
        }
        if (find.byType(ErrorWidget).evaluate().isNotEmpty) {
          bulgular.add(_Bulgu(yol, 'HATA', 'kırmızı hata ekranı (ErrorWidget)'));
        }
        final spinner = find.byType(CircularProgressIndicator).evaluate().length;
        final icerik = find.byType(Text).evaluate().length;
        if (spinner > 0 && icerik < 3) {
          bulgular.add(_Bulgu(yol, 'uyarı', 'ekran yükleniyor durumunda kaldı'));
        }

        // Ekran açılışta kamera tarayıcıyı kendiliğinden açtıysa (ör. Fiyat
        // Gör) formlara dokunmadan kapat — test ortamında kamera yok, açık
        // kalırsa robotu kilitler.
        for (var i = 0; i < 3; i++) {
          if (!pencereKapat(find.byType(MobileScanner))) break;
          await bekle(8);
        }

        if (const bool.fromEnvironment('ROBOT_BUTONLAR')) {
          // ignore: avoid_print
          print('BUTONLAR $yol :: ${gorunenButonlar().join(' | ')}');
        }

        // ── 1) Ekranın kendi formu: doldur → Kaydet ──────────────────────
        final sayimOnce = await tabloSayilari();
        var (doldurulan, basildi) = await formuDoldurVeKaydet();
        if (basildi.isNotEmpty) ekranHataMetni('"$basildi" sonrası');
        var yazilan = artanlar(sayimOnce, await tabloSayilari());
        // Ekleme ekranında Kaydet'e basıldı ama hiçbir tabloya satır
        // eklenmediyse: sessizce kaydetmeyen form ya da robotun
        // dolduramadığı zorunlu alan — nedenini rapora yaz.
        // (Ayarlar ekranları ve "güncelle/değiştir" mevcut satırı günceller,
        // satır sayısı artmaz — onlar sayılmaz.)
        if (basildi.isNotEmpty && yazilan.isEmpty && !yol.startsWith('/ayarlar') && !_kayitBeklenmeyen.contains(yol) &&
            !RegExp(r'güncelle|değiştir', caseSensitive: false).hasMatch(basildi)) {
          final neden = dogrulamaMesajlari();
          // Başarı mesajı çıktıysa mevcut kayıt güncellenmiştir (ör. fatura
          // ödemesi) — satır sayısı artmaz ama hata değil.
          if (!_basariRe.hasMatch(neden)) {
            bulgular.add(_Bulgu(yol, 'kayıtsız',
                '"$basildi" basıldı, kayıt oluşmadı${neden.isNotEmpty ? ' — ekranda: $neden' : ''} [${sonDoldurulan.join("; ")}]'));
          }
        }

        // ── 2) Liste ekranı: "+" ile yeni kayıt ekle ─────────────────────
        var arti = '';
        if (basildi.isEmpty) {
          final dugme = ekleDugmesi();
          if (dugme.evaluate().isNotEmpty) {
            final onceArti = await tabloSayilari();
            await tester.tap(dugme.first, warnIfMissed: false);
            await bekle(10);
            // + düğmesi kamera tarayıcı açtıysa kapat.
            pencereKapat(find.byType(MobileScanner));
            final (d2, b2) = await formuDoldurVeKaydet();
            ekranHataMetni('+ ${b2.isEmpty ? 'açılışı' : '"$b2" sonrası'}');
            final y2 = artanlar(onceArti, await tabloSayilari());
            arti = b2.isEmpty ? '+ açıldı (alan:$d2, kaydet yok)' : '+ "$b2" → ${y2.isEmpty ? 'KAYIT YOK' : y2}';
            final neden2 = dogrulamaMesajlari();
            if (b2.isNotEmpty && y2.isEmpty && !_kayitBeklenmeyen.contains(yol) &&
                !_basariRe.hasMatch(neden2)) {
              final neden = neden2;
              bulgular.add(_Bulgu(yol, 'kayıtsız',
                  '+ ile açılan formda "$b2"e basıldı, kayıt oluşmadı${neden.isNotEmpty ? ' — ekranda: $neden' : ''} [${sonDoldurulan.join("; ")}]'));
            }
            doldurulan += d2;
          }
        }

        // Kalan pencereleri kapat.
        for (var i = 0; i < 3 && find.byType(Dialog).evaluate().isNotEmpty; i++) {
          final kapat = find.descendant(
              of: find.byType(Dialog),
              matching: find.byWidgetPredicate((w) =>
                  w is Text && RegExp(r'^(iptal|vazgeç|kapat|tamam)$', caseSensitive: false)
                      .hasMatch((w.data ?? '').trim())));
          if (kapat.evaluate().isEmpty) break;
          await tester.tap(kapat.first, warnIfMissed: false);
          await bekle(4);
        }
        for (var i = 0; i < 3; i++) {
          final p = find.byWidgetPredicate((w) => w is Dialog || w is BottomSheet || w is MobileScanner);
          if (!pencereKapat(p)) break;
          await bekle(8);
        }

        // ── 2b) Hızlı Satış: sepete ekle → Ödeme Al → Kart / Nakit ────────
        var satis = '';
        if (yol == '/satis') {
          for (final yontem in ['Kredi Kartı', 'Nakit']) {
            final once2 = await tabloSayilari();
            // Sepet boşsa ürünü aratıp ekle (ilk turda genel adım eklemişti).
            if (find.text('Sepet boş').evaluate().isNotEmpty) {
              final ara = find.byType(TextField).hitTestable();
              if (ara.evaluate().isNotEmpty) {
                await tester.enterText(ara.first, _aranacakUrun);
                await bekle(12);
                final sonuc = find.byWidgetPredicate((w) =>
                    w is Text && (w.data ?? '').startsWith('Robot Çikolata 80 G')).hitTestable();
                if (sonuc.evaluate().isNotEmpty) {
                  await tester.tap(sonuc.first, warnIfMissed: false);
                  await bekle(8);
                }
              }
            }
            final odeme = find.text('Ödeme Al').hitTestable();
            if (odeme.evaluate().isEmpty) {
              bulgular.add(_Bulgu(yol, 'kayıtsız', '$yontem: "Ödeme Al" bulunamadı (sepete ürün eklenemedi?)'));
              continue;
            }
            await tester.tap(odeme.first, warnIfMissed: false);
            await bekle(10);
            final secenek = find.descendant(of: find.byType(BottomSheet), matching: find.text(yontem));
            if (secenek.evaluate().isNotEmpty) {
              await tester.tap(secenek.first, warnIfMissed: false);
              await bekle(10);
            }
            if (yontem == 'Nakit') {
              final tamam = find.descendant(of: find.byType(Dialog), matching: find.text('Tamam'));
              if (tamam.evaluate().isNotEmpty) {
                await tester.tap(tamam.first, warnIfMissed: false);
                await bekle(12);
              }
            }
            final y = artanlar(once2, await tabloSayilari());
            satis += ' · $yontem satış → ${y.isEmpty ? 'KAYIT YOK' : y.split(',').where((s) => s.startsWith('satis')).join(',')}';
            if (!y.contains('satislar+1')) {
              bulgular.add(_Bulgu(yol, 'kayıtsız',
                  '$yontem ile ödeme alındı ama satış kaydı oluşmadı — ekranda: ${dogrulamaMesajlari()}'));
            }
            for (var i = 0; i < 4; i++) {
              final p = find.byWidgetPredicate((w) => w is Dialog || w is BottomSheet);
              if (!pencereKapat(p)) break;
              await bekle(8);
            }
            // Satış sonrası fiş önizleme gibi bir sayfaya geçildiyse geri dön.
            if (Uri.parse(router.routerDelegate.currentConfiguration.last.matchedLocation).path != '/satis') {
              router.go('/');
              await bekle(6);
              unawaited(router.push('/satis'));
              await bekle();
            }
          }
        }

        // ── 3) Sekmeler ve filtre çipleri: hepsini tek tek aç ─────────────
        // (Yalnız bu ekranın sayfasındakiler — robot başka sayfaya geçtiyse
        // atlanır.)
        var sekme = 0, cip = 0;
        final sayfaYolu = Uri.decodeComponent(Uri.parse(
            router.routerDelegate.currentConfiguration.last.matchedLocation).path);
        if (sayfaYolu == yol) {
          final sekmeSayisi = find.byType(Tab).hitTestable().evaluate().length;
          for (var i = 1; i < sekmeSayisi && i < 8; i++) {
            final s = find.byType(Tab).hitTestable();
            if (s.evaluate().length <= i) break;
            await tester.tap(s.at(i), warnIfMissed: false);
            await bekle(10);
            sekme++;
          }
          if (sekmeSayisi > 1) {
            await tester.tap(find.byType(Tab).hitTestable().first, warnIfMissed: false);
            await bekle(8);
          }
          final cipSayisi = find.byWidgetPredicate((w) => w is FilterChip || w is ChoiceChip)
              .hitTestable().evaluate().length;
          for (var i = 0; i < cipSayisi && i < 10; i++) {
            final c = find.byWidgetPredicate((w) => w is FilterChip || w is ChoiceChip).hitTestable();
            if (c.evaluate().length <= i) break;
            await tester.tap(c.at(i), warnIfMissed: false);
            await bekle(6);
            cip++;
          }
          if (sekme > 0 || cip > 0) ekranHataMetni('sekme/filtre');

          // Uzun listelerin altı: aşağı kaydır (tembel oluşturulan satırlar
          // da çizilsin), sonra başa dön.
          final kaydirilabilir = find.byType(Scrollable).hitTestable();
          if (kaydirilabilir.evaluate().isNotEmpty) {
            for (var i = 0; i < 3; i++) {
              await tester.drag(kaydirilabilir.first, const Offset(0, -400), warnIfMissed: false);
              await bekle(4);
            }
            ekranHataMetni('kaydırma');
            for (var i = 0; i < 3; i++) {
              if (find.byType(Scrollable).hitTestable().evaluate().isEmpty) break;
              await tester.drag(find.byType(Scrollable).hitTestable().first,
                  const Offset(0, 400), warnIfMissed: false);
              await bekle(4);
            }
            kaydirma++;
          }
        }

        // ── 4) Listedeki ilk kayda dokun (detay / düzenleme açılsın) ──────
        var detay = '';
        if (sayfaYolu == yol) {
          final kayitlar = find.byWidgetPredicate((w) =>
              w is ListTile && w.onTap != null && w.enabled).hitTestable();
          for (final e in kayitlar.evaluate().take(6)) {
            final m = butonMetni(e);
            if (m.isEmpty || _yasakRe.hasMatch(m) || yikiciIkonluMu(e)) continue;
            final onceki = ustRota();
            await tester.tap(find.byWidget(e.widget).first, warnIfMissed: false);
            await bekle(12);
            detay = ustRota() != onceki ? 'kayıt açıldı: "${m.split(' ').take(4).join(' ')}"' : '';
            ekranHataMetni('kayıt detayı');
            break;
          }
        }

        final yeni = bulgular.length - once;
        gezilen[yol] = '${yeni == 0 ? '✅' : '⚠️'} alan:$doldurulan'
            '${basildi.isNotEmpty ? ' buton:"$basildi" → ${yazilan.isEmpty ? 'yeni satır yok' : yazilan}' : ''}'
            '${arti.isNotEmpty ? ' · $arti' : ''}$satis'
            '${sekme > 0 ? ' · sekme:$sekme' : ''}${cip > 0 ? ' · filtre:$cip' : ''}'
            '${detay.isNotEmpty ? ' · $detay' : ''}${yeni > 0 ? ' bulgu:$yeni' : ''}';
      } catch (e, st) {
        // ignore: avoid_print
        if (_tekRota.isNotEmpty) print('ROBOT HATASI: $e\n$st');
        bulgular.add(_Bulgu(yol, 'HATA', 'robot: ${e.toString().split('\n').first}'));
        gezilen[yol] = '❌';
      }
      // Açık kalan PENCERELERİ (dialog / alt sayfa) kapat. Sayfalara
      // dokunulmaz — onları bir sonraki router.go zaten değiştirir; sayfayı
      // robot da kapatırsa ekranın kendi kapanışıyla çakışıp geçiş
      // animasyonunu yarıda bırakıyordu.
      for (var i = 0; i < 5; i++) {
        // Kamera barkod tarayıcı sayfası da kapatılır (test ortamında kamera
        // yok; açık kalırsa robotu kilitler — ör. Fiyat Gör otomatik açar).
        final pencere = find.byWidgetPredicate(
            (w) => w is Dialog || w is BottomSheet || w is MobileScanner);
        if (!pencereKapat(pencere)) break;
        await bekle(8);
      }
      // Bitmeyen sayfa geçişi (performans modu açık kaldı) — hangi ekran?
      await bekle(10);
      if (SchedulerBinding.instance.debugGetRequestedPerformanceMode() != null) {
        bulgular.add(_Bulgu(yol, 'animasyon',
            'sayfa geçişi tamamlanmadan kaldı (performans modu açık)'));
      }
    }
      // Kapanmadan önce ana sayfaya dön ve geçiş animasyonları bitsin —
      // animasyon ortasında kapatılan rota Flutter test değişmezini bozar.
      router.go('/');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

    }, (e, s) {
      final m = e.toString();
      // Arka plan hatası önceki ekrandan sarkmış olabilir — uygulamadaki
      // kaynak satırını da yaz ki hangi ekran/dosya olduğu belli olsun.
      final kaynak = RegExp(r'package:market_plus/(\S+?:\d+)')
          .firstMatch(s.toString())
          ?.group(1);
      bulgular.add(_Bulgu(aktifRota,
          m.contains('MissingPluginException') ? 'ortam' : 'HATA',
          'arka plan: ${m.split('\n').first}${kaynak != null ? ' [$kaynak]' : ''}'));
    });

    // ── Veri bütünlüğü ─────────────────────────────────────────────────────
    aktifRota = '(veri bütünlüğü)';
    final cariUyumsuz = await CariDeposu().bakiyeUyumsuzlukSayisi();
    if (cariUyumsuz > 0) {
      bulgular.add(_Bulgu(aktifRota, 'HATA', '$cariUyumsuz caride bakiye ≠ hareket toplamı'));
    }
    final stokUyumsuz = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM urunler u WHERE EXISTS (SELECT 1 FROM stok_hareket s WHERE s.urun_id = u.id)
        AND ABS(u.stok - (SELECT sonraki_stok FROM stok_hareket s WHERE s.urun_id = u.id ORDER BY s.id DESC LIMIT 1)) > 0.001''');
    final su = (stokUyumsuz.first['n'] as int?) ?? 0;
    if (su > 0) bulgular.add(_Bulgu(aktifRota, 'HATA', '$su üründe stok ≠ son stok hareketi'));

    FlutterError.onError = eskiOnError;

    // ── Rapor ──────────────────────────────────────────────────────────────
    final gercek = bulgular.where((b) => b.tur == 'HATA' || b.tur == 'ekranda-hata').toList();
    final sb = StringBuffer()
      ..writeln('# Uygulama Robotu Raporu — ${DateTime.now()}')
      ..writeln()
      ..writeln('Gezilen ekran: ${gezilen.length} · HATA: ${gercek.length} '
          '(ekranda yazılı hata: ${bulgular.where((b) => b.tur == 'ekranda-hata').length}) · '
          'kaydırılan ekran: $kaydirma · '
          'kayıt oluşmayan: ${bulgular.where((b) => b.tur == 'kayıtsız').length} · '
          'kayıt yazılan: ${gezilen.values.where((s) => RegExp(r'→ [a-z_]+\+').hasMatch(s)).length} · '
          'taşma: ${bulgular.where((b) => b.tur == 'taşma').length} · '
          'yönlendirme: ${bulgular.where((b) => b.tur == 'yönlendirildi').length} · '
          'uyarı: ${bulgular.where((b) => b.tur == 'uyarı').length} · '
          'görsel: ${bulgular.where((b) => b.tur == 'görsel').length} · '
          'gezinme: ${bulgular.where((b) => b.tur == 'gezinme').length} · '
          'ortam (eklenti, gerçek hata değil): ${bulgular.where((b) => b.tur == 'ortam').length}')
      ..writeln()
      ..writeln('## Bulgular')
      ..writeln('| Ekran | Tür | Mesaj |')
      ..writeln('|---|---|---|');
    final gorulen = <String>{};
    for (final b in bulgular.where((b) => b.tur != 'ortam')) {
      final anahtar = '${b.rota}|${b.tur}|${b.mesaj}';
      if (!gorulen.add(anahtar)) continue;
      sb.writeln('| ${b.rota} | ${b.tur} | ${b.mesaj.replaceAll('|', '/')} |');
    }
    final yavaslar = acilisMs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    sb
      ..writeln()
      ..writeln('## En yavaş açılan 5 ekran (gerçek süre, veritabanı sorguları dahil)')
      ..writeAll(yavaslar.take(5).map((e) => '- ${e.key}: ${e.value} ms\n'))
      ..writeln()
      ..writeln('## Ekranlar')
      ..writeln('| Ekran | Sonuç |')
      ..writeln('|---|---|');
    gezilen.forEach((k, v) => sb.writeln('| $k | $v |'));
    try {
      final klasor = Platform.isAndroid ? Directory.systemTemp : Directory('build');
      klasor.createSync(recursive: true);
      File('${klasor.path}/robot_raporu.md').writeAsStringSync(sb.toString());
    } catch (_) {/* rapor konsola da basılıyor */}
    // ignore: avoid_print
    print(sb.toString());

    // Masalar ekranının başlattığı oturum boyu QR sipariş zamanlayıcısı
    // (bilinçli olarak ekran kapanınca durmaz) test sonunda durdurulur.
    QrSiparisCekiciServisi().durdur();
    // Açık animasyon/geçiş kalmasın (Flutter test değişmezleri).
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(minutes: 2));
    Veritabani.testVeritabani = null;
    await db.close();

    if (const bool.fromEnvironment('ROBOT_KESIN')) {
      expect(gercek, isEmpty, reason: 'robot ${gercek.length} gerçek hata buldu');
    }
  },
      // İsteğe bağlı: normal 'flutter test' / CI'da çalışmaz. Çalıştırmak için:
      //   flutter test test/robot --dart-define=ROBOT=true
      skip: !const bool.fromEnvironment('ROBOT'),
      timeout: const Timeout(Duration(minutes: 20)));
}
