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
      RegExp(r'fiyat|tutar|miktar|stok|adet|oran|limit|bakiye|kdv|iskonto|indirim|puan|gün|vade|sayı|no\b|%')
          .hasMatch(etiket);
  final n = ++_sayac;
  if (t.obscureText) return '1234';
  // Ürün arama kutusu: tohumdaki gerçek bir ürünü arat (sonuç seçilebilsin).
  if (etiket.contains('ürün') && etiket.contains('ara')) return _aranacakUrun;
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

final _kaydetRe = RegExp(r'^(kaydet|ekle|tamam|oluştur|onayla|güncelle|kaydet ve kapat|satışı tamamla)$',
    caseSensitive: false);
final _onayRe = RegExp(r'^(evet.*|tamam|onayla|kaydet|devam.*|sil)$', caseSensitive: false);

void main() {
  testWidgets('UYGULAMA ROBOTU — tüm ekranlar', (tester) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
        final bos = find.byWidgetPredicate((w) {
          if (w is! DropdownButton) return false;
          final dw = w as dynamic;
          return dw.value == null && dw.onChanged != null &&
              ((dw.items as List?)?.isNotEmpty ?? false);
        }).hitTestable();
        if (bos.evaluate().isEmpty) break;
        try {
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
    Future<(int, String)> formuDoldurVeKaydet() async {
      sonDoldurulan.clear();
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
          if (deger == _aranacakUrun) {
            // Arama sonucunda çıkan ürüne dokun (metin kutusunun kendisi hariç).
            await bekle(12);
            final sonuc = find.byWidgetPredicate((w) =>
                w is Text && (w.data ?? '').startsWith('Robot Çikolata 80 G')).hitTestable();
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

      var basildi = '';
      final butonMetni = find.byWidgetPredicate((w) =>
          w is Text && _kaydetRe.hasMatch((w.data ?? '').trim())).hitTestable();
      if (doldurulan > 0 && butonMetni.evaluate().isNotEmpty) {
        basildi = (butonMetni.evaluate().first.widget as Text).data ?? '';
        await tester.tap(butonMetni.first, warnIfMissed: false);
        await bekle(8);
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

    /// Ekrandaki "yeni ekle" düğmesi: önce FAB, yoksa + ikonlu düğme.
    Finder ekleDugmesi() {
      final fab = find.byType(FloatingActionButton).hitTestable();
      if (fab.evaluate().isNotEmpty) return fab;
      return find.byWidgetPredicate((w) =>
          w is IconButton && w.onPressed != null && w.icon is Icon &&
          _ekleIkonlari.contains((w.icon as Icon).icon)).hitTestable();
    }

    final gezilen = <String, String>{}; // rota → sonuç özeti
    // Ekranların arka planda fırlattığı (yakalanmamış) hatalar da bulgu olur,
    // testi düşürmez.
    await runZonedGuarded(() async {
    await tester.pumpWidget(const ProviderScope(
        child: MarketPlusApp(baslangicTema: 'light')));
    await bekle(30);

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    final rotalar = _rotalariTopla(router.configuration.routes)
        .where((r) => !_atlanacak.contains(r) && !r.startsWith('/bayi'))
        .where((r) => _tekRota.isEmpty || r == _tekRota)
        .toSet()
        .toList()
      ..sort();

    for (final sablon in rotalar) {
      final yol = _parametreDoldur(sablon, veri);
      aktifRota = yol;
      // ignore: avoid_print
      print('🤖 $yol');
      final once = bulgular.length;
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

        // ── 1) Ekranın kendi formu: doldur → Kaydet ──────────────────────
        final sayimOnce = await tabloSayilari();
        var (doldurulan, basildi) = await formuDoldurVeKaydet();
        var yazilan = artanlar(sayimOnce, await tabloSayilari());
        // Ekleme ekranında Kaydet'e basıldı ama hiçbir tabloya satır
        // eklenmediyse: sessizce kaydetmeyen form ya da robotun
        // dolduramadığı zorunlu alan — nedenini rapora yaz.
        if (basildi.isNotEmpty && yazilan.isEmpty && yol.contains('ekle')) {
          final neden = dogrulamaMesajlari();
          bulgular.add(_Bulgu(yol, 'kayıtsız',
              'Kaydet\'e basıldı, kayıt oluşmadı${neden.isNotEmpty ? ' — ekranda: $neden' : ''} [${sonDoldurulan.join("; ")}]'));
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
            final y2 = artanlar(onceArti, await tabloSayilari());
            arti = b2.isEmpty ? '+ açıldı (alan:$d2, kaydet yok)' : '+ "$b2" → ${y2.isEmpty ? 'KAYIT YOK' : y2}';
            if (b2.isNotEmpty && y2.isEmpty) {
              final neden = dogrulamaMesajlari();
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
        final yeni = bulgular.length - once;
        gezilen[yol] = '${yeni == 0 ? '✅' : '⚠️'} alan:$doldurulan'
            '${basildi.isNotEmpty ? ' buton:"$basildi" → ${yazilan.isEmpty ? 'yeni satır yok' : yazilan}' : ''}'
            '${arti.isNotEmpty ? ' · $arti' : ''}${yeni > 0 ? ' bulgu:$yeni' : ''}';
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
    final gercek = bulgular.where((b) => b.tur == 'HATA').toList();
    final sb = StringBuffer()
      ..writeln('# Uygulama Robotu Raporu — ${DateTime.now()}')
      ..writeln()
      ..writeln('Gezilen ekran: ${gezilen.length} · HATA: ${gercek.length} · '
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
    sb
      ..writeln()
      ..writeln('## Ekranlar')
      ..writeln('| Ekran | Sonuç |')
      ..writeln('|---|---|');
    gezilen.forEach((k, v) => sb.writeln('| $k | $v |'));
    Directory('build').createSync(recursive: true);
    File('build/robot_raporu.md').writeAsStringSync(sb.toString());
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
