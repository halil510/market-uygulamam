// test/robot/uygulama_robotu_test.dart
//
// UYGULAMA ROBOTU — tüm ekranları bir kullanıcı gibi gezer:
//   1. Sanal işletme verisi tohumlar, admin (1234) ile gerçek giriş yapar.
//   2. Yönlendiricideki (GoRouter) TÜM rotaları otomatik toplar.
//   3. Her ekranı açar; çökme, kırmızı hata ekranı, taşma (overflow),
//      takılı kalan "yükleniyor" ve istemeden yönlendirmeyi kaydeder.
//   4. Formlardaki metin alanlarına etiketine uygun sanal veri yazar,
//      "Kaydet/Ekle/Tamam" butonuna basar, açılan onay penceresini onaylar.
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

String _sanalDeger(TextField t) {
  final d = t.decoration;
  final etiket = '${d?.labelText ?? ''} ${d?.hintText ?? ''}'.toLowerCase();
  final sayisal = t.keyboardType == TextInputType.number ||
      RegExp(r'fiyat|tutar|miktar|stok|adet|oran|limit|bakiye|kdv|iskonto|puan|gün|vade|sayı|no\b')
          .hasMatch(etiket);
  if (t.obscureText) return '1234';
  if (etiket.contains('telefon') || etiket.contains('gsm')) return '05321112233';
  if (etiket.contains('mail')) return 'robot@test.com';
  if (etiket.contains('barkod')) return '8690000000048';
  if (etiket.contains('vergi') || etiket.contains('tc')) return '1234567890';
  if (sayisal) return '12';
  return 'Robot ${etiket.trim().split(' ').first}'.trim();
}

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
      if (_tekRota.isNotEmpty) FlutterError.dumpErrorToConsole(d);
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

        // ── Sanal veri girişi ────────────────────────────────────────────
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
            await tester.enterText(bul.at(i), _sanalDeger(t));
            doldurulan++;
          } catch (_) {}
        }
        await bekle(4);

        // ── Kaydet / Ekle ────────────────────────────────────────────────
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
        }
        final yeni = bulgular.length - once;
        gezilen[yol] = '${yeni == 0 ? '✅' : '⚠️'} alan:$doldurulan'
            '${basildi.isNotEmpty ? ' buton:"$basildi"' : ''}${yeni > 0 ? ' bulgu:$yeni' : ''}';
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
      bulgular.add(_Bulgu(aktifRota,
          m.contains('MissingPluginException') ? 'ortam' : 'HATA', 'arka plan: ${m.split('\n').first}'));
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
