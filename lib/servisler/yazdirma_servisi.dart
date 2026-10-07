// lib/servisler/yazdirma_servisi.dart
// v4.0 — Profesyonel çok protokollü yazıcı servisi
// Desteklenen: WiFi/LAN (TCP:9100), Bluetooth LE, USB (via usb_serial)
// Profesyonel uygulamalar bu 3 protokolü destekler (Square, Clover, iiko vb.)

import 'dart:async';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:printing/printing.dart' as pr;
import 'package:permission_handler/permission_handler.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:barcode/barcode.dart' as bcode;
import 'package:intl/intl.dart';
import '../modeller/fatura_model.dart';
import '../cekirdek/utils/sayi_yaziya_cevir.dart';
import '../modeller/satis_model.dart';
import '../modeller/urun_model.dart';
import '../cekirdek/utils/etiket_yardimci.dart';
import '../modeller/yazici_model.dart';
import '../depolar/yazici_deposu.dart';
import '../veri/database/veritabani.dart';

part 'yazdirma_servisi_belgeler.dart';
part 'yazdirma_servisi_etiket.dart';

// ─── Bağlantı türü ────────────────────────────────────────────────────────────
enum YaziciTur { wifi, bluetooth, usb, rawbt, windows }

// ─── Yazıcı bağlantı durumu ───────────────────────────────────────────────────
class YaziciBaglanti {
  final YaziciModel yazici;
  final YaziciTur tur;
  bool bagliMi;

  // WiFi
  Socket? _tcpSocket;
  // Bluetooth
  BluetoothDevice? _btCihaz;
  BluetoothCharacteristic? _btKaraktar;
  // 🔴 Derin analizde bulundu: btBaglan()'daki connectionState.listen()
  // aboneliği hiç saklanmıyor/iptal edilmiyordu — bu bağlantı kapatılınca
  // (kapat() ile) dinleyici canlı kalmaya devam ediyordu. Kararsız bir
  // Bluetooth yazıcıyla uzun bir oturumda, her otomatik yeniden bağlanma
  // denemesi kalıcı bir dinleyici daha ekleyip sınırsız birikiyordu.
  StreamSubscription<dynamic>? _btBaglantiAbonelik;
  // USB
  UsbPort? _usbPort;

  YaziciBaglanti({required this.yazici, required this.tur, this.bagliMi = false});

  Future<void> kapat() async {
    try { await _btBaglantiAbonelik?.cancel(); } catch (e) { /* ignore */ }
    try { await _tcpSocket?.close(); } catch (e) { /* ignore */ }
    try { await _btCihaz?.disconnect(); } catch (e) { /* ignore */ }
    try { await _usbPort?.close(); } catch (e) { /* ignore */ }
    _tcpSocket = null;
    _btCihaz = null;
    _btKaraktar = null;
    _btBaglantiAbonelik = null;
    _usbPort = null;
    bagliMi = false;
  }
}

// ─── Ana Servis ───────────────────────────────────────────────────────────────
class YazdirmaServisi {
  static final YazdirmaServisi _i = YazdirmaServisi._();
  factory YazdirmaServisi() => _i;
  YazdirmaServisi._();

  YaziciBaglanti? _aktif;
  final _fmt = NumberFormat('#,##0.00', 'tr_TR');

  // 🔴 KRİTİK DÜZELTME (paralel fork denetimi, 2026-09-22 — "tam ERP"
  // turu): _yazdir() yazıcıya erişilemediğinde otomatikBaglan()'ın TAM
  // kademeli-retry kaskadını (WiFi için 4 deneme × [0,2,4,6]sn gecikme +
  // 6sn timeout ≈ tek seferde ~26sn'ye kadar) tetikliyordu — hem
  // yazdırma ÖNCESİ (bağlı değilse) HEM DE yazma başarısız olursa TEKRAR
  // (yeniden bağlan + tek deneme daha). fisYazdir/makbuzYazdir'deki kopya
  // döngüsü (_fisKopyaSayisi'ne kadar) her kopya için bu iki denemeyi
  // AYRI AYRI tetikleyebiliyordu — yazıcı tamamen erişilemezse, çok
  // kopyalı bir yazdırma teorik olarak dakikalarca sürebiliyordu (bugün
  // tahsilat_odeme_ekrani.dart'ta bulunup düzeltilen kök sorunla AYNI
  // aile). Artık son başarısız deneme zaman damgası tutuluyor — 20
  // saniye içinde tekrar denenirse pahalı kaskad ATLANIR, doğrudan
  // başarısız sayılır. İlk deneme (splash ekranındaki otomatikBaglan()
  // çağrısı dahil) buna tabi DEĞİL — sadece _yazdir()'in kendi içindeki
  // yeniden-bağlanma yolu bunu kullanır.
  // Yetenek profili (68 KB JSON) her yazdırmada yeniden ayrıştırılıyordu.
  CapabilityProfile? _profilOnbellek;
  Future<CapabilityProfile> _profil() async =>
      _profilOnbellek ??= await CapabilityProfile.load();

  DateTime? _sonBasarisizYenidenBaglanma;
  static const _yenidenBaglanmaBeklemeSuresi = Duration(seconds: 20);

  Future<bool> _yenidenBaglanCircuitBreaker() async {
    final sonDeneme = _sonBasarisizYenidenBaglanma;
    if (sonDeneme != null &&
        DateTime.now().difference(sonDeneme) < _yenidenBaglanmaBeklemeSuresi) {
      if (kDebugMode) {
        debugPrint('🔴 Yazıcı yeniden bağlanma devre dışı (circuit breaker) — '
            'son deneme ${DateTime.now().difference(sonDeneme).inSeconds}sn önce başarısız oldu');
      }
      return false;
    }
    final basarili = await otomatikBaglan();
    _sonBasarisizYenidenBaglanma = basarili ? null : DateTime.now();
    return basarili;
  }

  /// Termal yazıcıların varsayılan kod sayfaları (CP437/CP1252/PC850 vb.)
  /// Türkçe'ye özgü ş,Ş,ğ,Ğ,ı,İ karakterlerini İÇERMEZ. Bu karakterler
  /// `generator.text(_t())`/`row()` çağrılarına gönderildiğinde
  /// "Invalid argument(s): string contains invalid characters" hatası
  /// fırlatılır (örn. "Fiş No:", "İndirim", "İskonto" gibi metinler).
  ///
  /// ö,ü,ç,Ö,Ü,Ç Latin-1/CP1252 içinde olduğundan SORUNSUZDUR — onlara
  /// dokunulmaz, sadece sorunlu 6 karakter ASCII karşılığına çevrilir.
  /// Tüm yazdırma metinleri (sabit + dinamik: ürün adı, masa adı, fiş no,
  /// cari adı, notlar...) bu fonksiyondan geçer.
  ///
  /// Latin-1 dışındaki karakterler (₺ – “ ” … € emoji…) `generator.text`'i
  /// exception ile patlatıp TÜM fişi/etiketi basılmaz hale getiriyordu
  /// (Excel'den içe aktarılan ürün adlarında yaygın) — eşlenir ya da atılır.
  @visibleForTesting
  static String temizleYaziciMetni(String s) => _t(s);

  static String _t(String s) {
    final ilk = s
        .replaceAll('İ', 'I').replaceAll('ı', 'i')
        .replaceAll('Ş', 'S').replaceAll('ş', 's')
        .replaceAll('Ğ', 'G').replaceAll('ğ', 'g')
        .replaceAll('₺', 'TL').replaceAll('€', 'EUR')
        .replaceAll('–', '-').replaceAll('—', '-')
        .replaceAll('“', '"').replaceAll('”', '"')
        .replaceAll('‘', "'").replaceAll('’', "'")
        .replaceAll('…', '...');
    if (ilk.codeUnits.every((c) => c <= 255)) return ilk;
    final sb = StringBuffer();
    for (final r in ilk.runes) {
      if (r <= 255) sb.writeCharCode(r);
    }
    return sb.toString();
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🔴 BARKODU RESİM OLARAK ÜRET (kullanıcı bulgusu — "çizgi oluşmuyor")
  //
  // SORUN: `generator.barcode()` ESC/POS'un yerel barkod komutunu
  // (GS k) gönderiyor. Ucuz/klon termal yazıcıların ÇOĞU bu komutu
  // desteklemiyor — komutu sessizce yok sayıyor ya da hata veriyor.
  // Sonuç: fişte sadece fiş numarası metni çıkıyor, çizgi çıkmıyor.
  // ({B kod seti öneki eklenmesine rağmen sorun devam etti.)
  //
  // ÇÖZÜM: barkodu ÇİZGİ ÇİZGİ bir resme çizip resim olarak basmak.
  // Resim basma (GS v 0) neredeyse TÜM termal yazıcılarda çalışır —
  // logo basımı için zaten kullanılan komuttur.
  //
  // `barcode` paketi barkodun geometrisini veriyor (BarcodeBar: left,
  // top, width, height, black), `image` paketiyle çiziliyor. İkisi de
  // projede zaten kurulu (pubspec: barcode ^2.2.8, image ^4.2.0).
  //
  // NOT: `bcode` takma adı zorunlu — esc_pos_utils_plus de `Barcode`
  // adında bir sınıf ihraç ediyor, çakışırdı.
  // ══════════════════════════════════════════════════════════════════════
  img.Image? _barkodResmiUret(
    String veri, {
    required int genislikPx,
    int yukseklikPx = 60,
  }) {
    try {
      if (veri.trim().isEmpty) return null;
      final bc = bcode.Barcode.code128();
      if (!bc.isValid(veri)) return null;

      final resim = img.Image(width: genislikPx, height: yukseklikPx);
      img.fill(resim, color: img.ColorRgb8(255, 255, 255));
      final siyah = img.ColorRgb8(0, 0, 0);

      for (final e in bc.make(
        veri,
        width: genislikPx.toDouble(),
        height: yukseklikPx.toDouble(),
      )) {
        if (e is bcode.BarcodeBar && e.black) {
          final x1 = e.left.round();
          final y1 = e.top.round();
          final x2 = (e.left + e.width).round() - 1;
          final y2 = (e.top + e.height).round() - 1;
          if (x2 < x1 || y2 < y1) continue;
          img.fillRect(resim,
              x1: x1.clamp(0, genislikPx - 1),
              y1: y1.clamp(0, yukseklikPx - 1),
              x2: x2.clamp(0, genislikPx - 1),
              y2: y2.clamp(0, yukseklikPx - 1),
              color: siyah);
        }
      }
      return resim;
    } catch (e) {
      if (kDebugMode) debugPrint('Barkod resmi uretilemedi: $e');
      return null;
    }
  }

  /// Fişe barkod basar. Resim yolu başarısızsa metne düşer.
  ///
  /// Genişlik kâğıt boyutuna göre: 58 mm → 384 nokta, 80 mm → 576 nokta.
  /// Barkod kâğıt genişliğinin tamamını kaplamasın diye ~%75 kullanılıyor.
  /// [genislikPx] verilirse barkod o genişlikte üretilir (etiket yazdırma —
  /// etiketin GERÇEK genişliği). Verilmezse fiş kâğıdı ayarına göre.
  List<int> _barkodBas(Generator generator, String veri, {int? genislikPx}) {
    final bytes = <int>[];
    final tamGenislik = _kagit == PaperSize.mm58 ? 384 : 576;
    final resim = _barkodResmiUret(
      veri,
      genislikPx: genislikPx ?? (tamGenislik * 0.75).round(),
      yukseklikPx: 60,
    );

    if (resim != null) {
      try {
        bytes.addAll(generator.imageRaster(resim, align: PosAlign.center));
        bytes.addAll(generator.text(_t(veri),
            styles: const PosStyles(align: PosAlign.center)));
        return bytes;
      } catch (e) {
        if (kDebugMode) debugPrint('Barkod resmi basilamadi: $e');
      }
    }

    // Resim de basılamadıysa en azından numarayı oku­nur bırak
    bytes.addAll(generator.text(_t(veri),
        styles: const PosStyles(align: PosAlign.center, bold: true)));
    return bytes;
  }

  /// Fiş üstüne firma logosunu basar (Fiş Tasarımı ekranında yüklenen
  /// PNG/JPG). Görsel kağıt genişliğine göre orantılı küçültülür; okunamaz
  /// veya bozuksa sessizce atlanır (fiş logosuz devam eder, hata vermez).
  Future<List<int>> _logoBas(Generator generator) async {
    final bytes = <int>[];
    if (!_fisLogoGoster || _fisLogoYolu.isEmpty) return bytes;
    try {
      final dosya = File(_fisLogoYolu);
      if (!await dosya.exists()) return bytes;
      final ham = await dosya.readAsBytes();
      final decoded = img.decodeImage(ham);
      if (decoded == null) return bytes;
      final tamGenislik = _kagit == PaperSize.mm58 ? 384 : 576;
      final hedefGenislik = (tamGenislik * 0.6).round();
      final oran = hedefGenislik / decoded.width;
      final resim = img.copyResize(decoded,
          width: hedefGenislik, height: (decoded.height * oran).round());
      bytes.addAll(generator.imageRaster(resim, align: PosAlign.center));
    } catch (e) {
      if (kDebugMode) debugPrint('Fiş logosu basılamadı: $e');
    }
    return bytes;
  }

  /// Cari bakiyesini insan okunur biçimde yazar.
  ///
  /// `cari.bakiye = SUM(borc) - SUM(alacak)` olduğu için:
  ///   • POZİTİF → müşteri bize borçlu  → "1.500,00 B" (Borç)
  ///   • NEGATİF → biz müşteriye borçlu → "1.500,00 A" (Alacak)
  ///   • SIFIR   → "0,00" (etiketsiz)
  ///
  /// Muhasebede standart olan B/A kısaltması kullanılır; çıplak eksi
  /// işareti kasiyeri ve müşteriyi yanıltıyordu.
  String _bakiyeYaz(double bakiye) {
    if (bakiye.abs() < 0.005) return _fmt.format(0);
    final etiket = bakiye > 0 ? 'B' : 'A';
    return '${_fmt.format(bakiye.abs())} $etiket';
  }
  final _depo = YaziciDeposu();

  // Ayarlar (DB'den okunur)
  String _firmaAdi   = 'BarkoPro';

  /// Etiket/fiş önizlemelerinde işletme adını göstermek için genel erişim.
  String get firmaAdiOnizleme => _firmaAdi;
  String _firmaAdres = '';
  String _firmaTel   = '';
  String _altYazi    = 'Teşekkür ederiz!';
  PaperSize _kagit   = PaperSize.mm80;

  // Fiş Tasarım ekranındaki ayarlar — önceden SharedPreferences'a
  // kaydediliyordu ama BURASI (gerçek yazdırma) onları hiç okumuyordu.
  // Artık aynı `ayarlar` tablosundan, tek doğru kaynaktan okunuyor.
  String _firmaVergiNo    = '';
  bool _fisVergiNoGoster  = true;
  bool _fisKasiyerGoster  = true;
  bool _fisUrunKoduGoster = false;
  bool _fisKdvDetayGoster = true;
  bool _fisKdvGosterAna   = true;
  bool _fisTesekkurGoster = true;

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 CARİ BAKİYE + FİŞ BARKODU AYARLARI
  //
  // `fis_cari_bakiye_goster`  : Cariye yapılan satışta / tahsilatta /
  //                             tedarikçi ödemesinde fişe
  //                             "Eski Bakiye → İşlem → Son Bakiye"
  //                             üçlüsünü basar.
  // `fis_yaziyla_tutar`       : Makbuzlarda tutarı rakamın yanı sıra
  //                             YAZIYLA da basar. Türkiye'de tahsilat/
  //                             tediye makbuzlarında tahrifata karşı
  //                             standart uygulamadır.
  // `fis_alt_barkod_goster`   : Fişin ALTINA fiş numarasını kodlayan
  //                             Code128 barkod basar (kasadan okutup
  //                             fişi geri çağırmak için).
  //
  //   ⚠ ÇAKIŞMA NOTU: Fiş Tasarım ekranında ZATEN bir
  //   `fis_barkod_goster` anahtarı var — o, ÜRÜN SATIRLARINDAKİ
  //   barkodu kastediyor (varsayılan KAPALI) ve bugüne dek hiçbir
  //   yerde okunmuyordu. Yeni özellik onun üstüne yazsaydı,
  //   kullanıcının kapalı sandığı bir ayar fişin altına barkod
  //   basmaya başlardı. Bu yüzden AYRI anahtar kullanıldı.
  // ══════════════════════════════════════════════════════════════════════
  bool _fisCariGoster       = true;   // Fişte cari (müşteri) adı
  bool _fisCariBakiyeGoster = true;
  bool _fisYaziylaTutar     = true;
  bool _fisBarkodGoster     = true;
  String _fisTesekkurMetni = 'Bizi tercih ettiğiniz için teşekkürler!';
  bool _fisOdemeYontemiGoster = true;
  bool _fisParaUstuGoster = true;
  int _fisKopyaSayisi = 1;
  int _fisBeslemeKagit = 3;
  bool _fisLogoGoster = false;
  String _fisLogoYolu = '';

  // ── Durum ─────────────────────────────────────────────────────────────────
  bool get bagliMi => _aktif?.bagliMi == true;

  /// Kullanıcı isteği: "yazıcı otomatik bağlansın, uygulama açılıp
  /// kapanmada / güncellemeden sonra açmıyor" — ÖNCEDEN uygulama her
  /// açıldığında yazıcı bağlantısı sıfırlanıyordu, kullanıcı her
  /// seferinde Yazdırma Merkezi'ne gidip elle "Bağlan" demek zorunda
  /// kalıyordu. Artık uygulama açılışında (splash ekranında) bu
  /// fonksiyon çağrılıyor: varsayılan yazıcı bulunursa türüne göre
  /// (WiFi/Bluetooth/USB) otomatik bağlanmayı dener.
  ///
  /// 🔴 İKİNCİ TUR DÜZELTME: tek denemelik "ateşle-unut" yaklaşımı,
  /// özellikle "kapatıp açma" ve "güncelleme sonrası ilk açılış"
  /// senaryolarında yetersizdi — bu durumlarda işletim sistemi WiFi'ı
  /// henüz yeniden ilişkilendirmemiş / IP almamış olabiliyor, ilk
  /// bağlantı denemesi bu yüzden başarısız oluyor ve BİR DAHA HİÇ
  /// tekrar denenmiyordu. Artık (a) WiFi yazıcılar için önce gerçekten
  /// bir ağ bağlantısı var mı kısaca bekleniyor, (b) bağlantı denemesi
  /// başarısız olursa artan gecikmelerle birkaç kez daha deneniyor.
  /// Başarısız olursa yine sessizce geçer — uygulama açılışını
  /// engellemez, kullanıcı yine de manuel bağlanabilir.
  Future<bool> otomatikBaglan() async {
    try {
      final yazici = await _depo.varsayilanGetir();
      if (yazici == null) return false;
      if (kDebugMode) debugPrint('🖨️ Varsayılan yazıcıya otomatik bağlanılıyor: ${yazici.adi} (${yazici.tur})');

      switch (yazici.tur) {
        case 'ag':
          if (yazici.ip == null || yazici.ip!.isEmpty) return false;
          await _agHazirOlanaKadarBekle();
          // Kapatıp-açma / güncelleme sonrası ilk deneme WiFi henüz
          // hazır olmadığı için başarısız olabilir — artan gecikmelerle
          // birkaç kez daha dene (toplam ~4 deneme, ~14 sn'ye kadar).
          for (final gecikmeSn in [0, 2, 4, 6]) {
            if (gecikmeSn > 0) await Future.delayed(Duration(seconds: gecikmeSn));
            final basarili = await wifiBaglan(yazici).timeout(const Duration(seconds: 6), onTimeout: () => false);
            if (basarili) return true;
          }
          return false;

        case 'bluetooth':
          if (yazici.cihazId == null || yazici.cihazId!.isEmpty) return false;
          // Taramaya gerek yok — kayıtlı cihaz ID'siyle (MAC adresi)
          // doğrudan bir BluetoothDevice nesnesi kurulup bağlanılıyor.
          final cihaz = BluetoothDevice(remoteId: DeviceIdentifier(yazici.cihazId!));
          return await btBaglan(yazici, cihaz).timeout(const Duration(seconds: 8), onTimeout: () => false);

        case 'usb':
          // USB için önce cihazın hâlâ takılı olup olmadığına bakılıyor.
          final cihazlar = await UsbSerial.listDevices();
          if (cihazlar.isEmpty) return false;
          final eslesen = cihazlar.firstWhere(
              (c) => c.deviceId.toString() == yazici.cihazId,
              orElse: () => cihazlar.first);
          return await usbBaglan(yazici, eslesen).timeout(const Duration(seconds: 6), onTimeout: () => false);

        case 'windows':
          return await windowsBaglan(yazici);

        default:
          return false;
      }
    } catch (e) {
      // Otomatik bağlanma başarısız olsa bile uygulama normal şekilde
      // açılmaya devam etmeli — bu yüzden hata YUKARI FIRLATILMIYOR.
      if (kDebugMode) debugPrint('🔴 Otomatik yazıcı bağlantısı başarısız (normal, sessizce geçildi): $e');
      return false;
    }
  }

  /// En fazla ~5 saniye, cihazın gerçek bir ağ bağlantısı (WiFi/Ethernet)
  /// bildirmesini bekler. Uygulama soğuk açılışta / güncelleme sonrası
  /// ilk açılışta işletim sistemi henüz WiFi'ı yeniden bağlamamış
  /// olabilir — bu bekleme olmadan ilk deneme neredeyse her zaman
  /// başarısız oluyordu.
  Future<void> _agHazirOlanaKadarBekle() async {
    for (var i = 0; i < 10; i++) {
      try {
        final durum = await Connectivity().checkConnectivity();
        if (durum.contains(ConnectivityResult.wifi) || durum.contains(ConnectivityResult.ethernet)) return;
      } catch (_) { /* connectivity kontrolü başarısız olursa direkt denemeye geç */ return; }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
  YaziciModel? get aktifYazici => _aktif?.yazici;
  YaziciTur? get aktifTur => _aktif?.tur;
  String get baglantiDurumu {
    if (_aktif == null) return 'Bağlı değil';
    final t = _aktif!.tur == YaziciTur.wifi ? 'WiFi'
        : _aktif!.tur == YaziciTur.bluetooth ? 'Bluetooth'
        : _aktif!.tur == YaziciTur.windows ? 'Windows'
        : 'USB';
    return '$t — ${_aktif!.yazici.adi}';
  }

  // ── Ayarlar ───────────────────────────────────────────────────────────────
  Future<void> ayarlariYukle() async {
    try {
      final db = await Veritabani().db;
      final rows = await db.query('ayarlar', where:
          "anahtar IN ('firma_adi','firma_adres','firma_telefon','firma_vergi_no',"
          "'fis_alt_yazi','fis_kagit','fis_kdv','fis_vergi_no_goster','fis_kasiyer_goster',"
          "'fis_urun_kodu_goster','fis_kdv_detay_goster','fis_tesekkur_goster',"
          "'fis_tesekkur_metni','fis_odeme_yontemi_goster','fis_para_ustu_goster',"
          "'fis_kopya_sayisi','fis_besleme_kagit',"
          "'fis_cari_bakiye_goster','fis_yaziyla_tutar','fis_alt_barkod_goster',"
          "'fis_cari_goster','fis_logo_goster','fis_logo_yolu')");
      final m = {for (final r in rows) r['anahtar'] as String: r['deger'] as String};
      _firmaAdi   = m['firma_adi']     ?? 'BarkoPro';
      _firmaAdres = m['firma_adres']   ?? '';
      _firmaTel   = m['firma_telefon'] ?? '';
      _altYazi    = m['fis_alt_yazi']  ?? 'Teşekkür ederiz!';
      _kagit      = (m['fis_kagit'] ?? '80mm') == '58mm' ? PaperSize.mm58 : PaperSize.mm80;
      _firmaVergiNo        = m['firma_vergi_no'] ?? '';
      // 'fis_kdv': Yazdırma Merkezi > Fiş Ayarı sekmesindeki basit ana
      // anahtar — kapalıysa hiçbir KDV bilgisi basılmaz (detaylı/özet fark
      // etmeksizin). Fiş Tasarımı ekranındaki 'KDV Detay' ise bu anahtar
      // açıkken satır bazlı mı yoksa toplu mu gösterileceğini belirler.
      _fisKdvGosterAna     = (m['fis_kdv'] ?? '1') == '1';
      _fisVergiNoGoster    = (m['fis_vergi_no_goster'] ?? '1') == '1';
      _fisKasiyerGoster    = (m['fis_kasiyer_goster'] ?? '1') == '1';
      _fisUrunKoduGoster   = (m['fis_urun_kodu_goster'] ?? '0') == '1';
      _fisKdvDetayGoster   = (m['fis_kdv_detay_goster'] ?? '1') == '1';
      _fisTesekkurGoster   = (m['fis_tesekkur_goster'] ?? '1') == '1';
      _fisTesekkurMetni    = m['fis_tesekkur_metni'] ?? 'Bizi tercih ettiğiniz için teşekkürler!';
      _fisOdemeYontemiGoster = (m['fis_odeme_yontemi_goster'] ?? '1') == '1';
      _fisParaUstuGoster   = (m['fis_para_ustu_goster'] ?? '1') == '1';
      _fisKopyaSayisi      = int.tryParse(m['fis_kopya_sayisi'] ?? '1') ?? 1;
      _fisBeslemeKagit     = int.tryParse(m['fis_besleme_kagit'] ?? '3') ?? 3;
      _fisCariGoster       = (m['fis_cari_goster'] ?? '1') == '1';
      _fisCariBakiyeGoster = (m['fis_cari_bakiye_goster'] ?? '1') == '1';
      _fisYaziylaTutar     = (m['fis_yaziyla_tutar'] ?? '1') == '1';
      _fisBarkodGoster     = (m['fis_alt_barkod_goster'] ?? '1') == '1';
      _fisLogoGoster       = (m['fis_logo_goster'] ?? '0') == '1';
      _fisLogoYolu         = m['fis_logo_yolu'] ?? '';
    } catch (e) {
      if (kDebugMode) debugPrint('Ayar okuma hatası: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WİFİ / LAN — TCP Raw Socket (Port 9100)
  // Tüm profesyonel POS sistemlerinin standart protokolü
  // ══════════════════════════════════════════════════════════════════════════

  /// WiFi yazıcıya bağlan: IP + Port (varsayılan 9100)
  Future<bool> wifiBaglan(YaziciModel yazici) async {
    await _aktif?.kapat();
    final ip   = yazici.ip ?? '';
    final port = yazici.port;

    if (ip.isEmpty) throw Exception('IP adresi boş');

    try {
      if (kDebugMode) debugPrint('WiFi yazıcıya bağlanılıyor: $ip:$port');
      // YANLIŞ POZİTİF: soketin sahipliği hemen aşağıda YaziciBaglanti'ya
      // devrediliyor (`baglanti._tcpSocket = socket`) ve bağlantı
      // `YaziciBaglanti.kapat()` içinde `_tcpSocket?.close()` ile
      // kapatılıyor. Lint sahiplik devrini takip edemediği için burada
      // "kapatılmamış Sink" sanıyor.
      // ignore: close_sinks
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 6));
      socket.setOption(SocketOption.tcpNoDelay, true);

      final baglanti = YaziciBaglanti(yazici: yazici, tur: YaziciTur.wifi, bagliMi: true);
      baglanti._tcpSocket = socket;
      _aktif = baglanti;
      _sonAgYazma = DateTime.now();

      // Socket kapandığında durumu güncelle
      // Yalnız BU bağlantı nesnesi işaretlenir — eski soketin geç gelen
      // done olayı, yenilenmiş (aynı yazıcı id'li) yeni bağlantıyı
      // yanlışlıkla "bağlı değil" yapmasın.
      socket.done.then((_) {
        baglanti.bagliMi = false;
      }).catchError((_) {
        baglanti.bagliMi = false;
      });

      if (kDebugMode) debugPrint('WiFi yazıcı bağlandı: $ip:$port');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('WiFi bağlantı hatası: $e');
      rethrow;
    }
  }

  /// WiFi'dan veri yaz.
  ///
  /// 🔴🔴🔴 KÖK NEDEN DÜZELTMESİ (kullanıcı bulgusu — "bağlı gösteriyor
  /// lakin yazdırmıyor, silip tekrar bağlanınca yazıyor"): `socket.add()`
  /// + `flush()`, SADECE yerel gönderim tamponunun boşaldığını doğrular
  /// — yazıcının gerçekten aldığını ASLA doğrulamaz. Bağlantı "zombi"
  /// ise (yazıcı uyudu/WiFi kesildi ama TCP resmi olarak kopmadı), bu
  /// ikili HİÇBİR HATA FIRLATMADAN "başarılı" görünür.
  ///
  /// 🔴 İKİNCİ TUR (bir önceki düzeltmemin YARATTIĞI hata — "yazıcı hiç
  /// yazdırmaz oldu"): Her seferinde eski bağlantıyı kapatıp YENİ bir
  /// tane açmayı denedim — ama çoğu ucuz termal yazıcı muhtemelen
  /// AYNI ANDA SADECE TEK bağlantı kabul ediyor VE hızlı kapat→aç
  /// döngüsüne (100-200ms içinde) düzgün yanıt vermiyor, bu da
  /// yazdırmayı TAMAMEN bozdu.
  ///
  /// 🔴🔴 ÜÇÜNCÜ TUR (kullanıcı bulgusu — "önceden yazıyordu şimdi hiç
  /// yazdırıyor"): İkinci düzeltmemdeki 3 SANİYELİK zaman aşımı ÇOK
  /// KISAYMIŞ — yerel ağda bile WiFi gecikmesi, yazıcının o anki
  /// yoğunluğu veya büyük bir fiş içeriğinin aktarımı rahatlıkla 3
  /// saniyeyi geçebiliyor. SAĞLIKLI, ÇALIŞAN bir bağlantı bile "zaman
  /// aşımına uğradı, ölü" sayılıp HER SEFERİNDE hataya düşürülüyordu —
  /// bu tam olarak "artık hiç yazdırmıyor" şikayetini açıklıyor. Süre
  /// artık çok daha güvenli (12 saniye): gerçekten ölü bir bağlantı
  /// için hâlâ makul bir üst sınır, ama sağlıklı-fakat-yavaş bir
  /// aktarımı ASLA yanlışlıkla kesmeyecek kadar geniş. Teşhis
  /// kolaylığı için debug loglaması da eklendi.
  Future<void> _wifiYaz(List<int> bytes) async {
    // YANLIŞ POZİTİF: burada yeni soket AÇILMIYOR — zaten açık olan
    // bağlantının soketi okunuyor. Kapatma sorumluluğu
    // YaziciBaglanti.kapat()'ta.
    // ignore: close_sinks
    final s = _aktif?._tcpSocket;
    if (s == null) throw Exception('WiFi yazıcı bağlı değil');
    final baslangic = DateTime.now();
    try {
      s.add(bytes);
      await s.flush().timeout(const Duration(seconds: 12),
          onTimeout: () => throw Exception(
              'Yazıcıya veri gönderilemedi (12sn zaman aşımı — bağlantı muhtemelen ölü)'));
      if (kDebugMode) {
        final gecenMs = DateTime.now().difference(baslangic).inMilliseconds;
        debugPrint('[Yazdırma] WiFi yazma başarılı (${bytes.length} bayt, ${gecenMs}ms)');
      }
      _sonAgYazma = DateTime.now();
    } catch (e) {
      if (kDebugMode) debugPrint('[Yazdırma] WiFi yazma HATASI: $e');
      rethrow;
    }
  }

  /// Özel (yerel) IPv4 aralıkları: 10/8, 172.16/12, 192.168/16. Önceden
  /// yalnız '192.' aranıyordu — 10.x / 172.x ağlarında tarama boş dönüyordu.
  static bool _yerelAgMi(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.contains(null)) return false;
    return p[0] == 10 ||
        (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) ||
        (p[0] == 192 && p[1] == 168);
  }

  /// WiFi yazıcıyı tara (ağdaki potansiyel yazıcıları bul)
  /// Port 9100'de dinleyen cihazları bul
  static Future<List<String>> wifiYazicilariTara({
    String subnet = '',
    int timeout = 300,
  }) async {
    final bulunanlar = <String>[];
    String networkBase = subnet;

    if (networkBase.isEmpty) {
      // Cihazın IP'sini bul, subnet'i çıkar
      try {
        final interfaces = await NetworkInterface.list();
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (addr.type == InternetAddressType.IPv4 &&
                !addr.isLoopback && _yerelAgMi(addr.address)) {
              final parts = addr.address.split('.');
              networkBase = '${parts[0]}.${parts[1]}.${parts[2]}';
              break;
            }
          }
          if (networkBase.isNotEmpty) break;
        }
      } catch (e) { /* ignore */ }
    }

    if (networkBase.isEmpty) return bulunanlar;

    // 1-254 arasını paralel tara (port 9100)
    final futures = <Future>[];
    for (int i = 1; i <= 254; i++) {
      final ip = '$networkBase.$i';
      futures.add(
        Socket.connect(ip, 9100, timeout: Duration(milliseconds: timeout))
            .then((s) { s.destroy(); bulunanlar.add(ip); })
            .catchError((_) {}),
      );
    }
    await Future.wait(futures);
    return bulunanlar;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BLUETOOTH LE
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<BluetoothDevice>> btCihazlariTara() async {
    // Android 12+ izinleri
    if (Platform.isAndroid) {
      final izinler = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      final reddedilen = izinler.values.where((s) => s.isDenied || s.isPermanentlyDenied);
      if (reddedilen.isNotEmpty) return [];
    }
    final Set<BluetoothDevice> bulunanlar = {};

    // bondedDevices sadece Android'de çalışır
    if (Platform.isAndroid) {
      try {
        final bonded = await FlutterBluePlus.bondedDevices;
        bulunanlar.addAll(bonded);
      } catch (e) { /* ignore */ }
    }

    // Scan her platformda çalışır
    try {
      await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 5),
          androidUsesFineLocation: false);
      await Future.delayed(const Duration(seconds: 5));
      await FlutterBluePlus.stopScan();
    } catch (e) { /* ignore */ }

    final taranan = FlutterBluePlus.lastScanResults.map((r) => r.device);
    bulunanlar.addAll(taranan);
    return bulunanlar.toList();
  }

  Future<bool> btBaglan(YaziciModel yazici, BluetoothDevice cihaz) async {
    await _aktif?.kapat();
    try {
      await cihaz.connect(timeout: const Duration(seconds: 10));
      final services = await cihaz.discoverServices();

      BluetoothCharacteristic? karaktar;
      // Termal yazıcı UUID'leri: FFE1, 0002 (en yaygın)
      const yaziciUUIDs = ['ffe1', '0002', 'ff02', 'bef8d6c9'];
      outer:
      for (final s in services) {
        for (final c in s.characteristics) {
          final uuid = c.uuid.toString().toLowerCase();
          if (c.properties.write || c.properties.writeWithoutResponse) {
            for (final u in yaziciUUIDs) {
              if (uuid.contains(u)) { karaktar = c; break outer; }
            }
            karaktar ??= c; // Hiç eşleşme yoksa ilk write karakteristiği
          }
        }
      }

      if (karaktar == null) {
        await cihaz.disconnect();
        throw Exception('Yazıcı servisi bulunamadı');
      }

      final baglanti = YaziciBaglanti(yazici: yazici, tur: YaziciTur.bluetooth, bagliMi: true);
      baglanti._btCihaz    = cihaz;
      baglanti._btKaraktar = karaktar;
      _aktif = baglanti;

      // Bağlantı kopunca güncelle
      baglanti._btBaglantiAbonelik = cihaz.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            _aktif?.yazici.id == yazici.id) {
          _aktif?.bagliMi = false;
        }
      });

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('BT bağlantı hatası: $e');
      rethrow;
    }
  }

  Future<void> _btYaz(List<int> bytes) async {
    final c = _aktif?._btKaraktar;
    if (c == null) throw Exception('Bluetooth yazıcı bağlı değil');

    // 🔴 Derin denetimde bulundu (P2): _wifiYaz'ın aksine burada hiç
    // zaman aşımı yoktu — zombi bir GATT bağlantısı (disconnected
    // event'i hiç gelmeyen, donmuş bir bağlantı) c.write()'ı süresiz
    // beklemede bırakabilirdi, _yazdir()'in yeniden deneme sarmalayıcısı
    // (satır ~700) hiç devreye giremez, kullanıcı hiç hata görmeden
    // "yazdırılıyor" durumunda sonsuza kadar kilitli kalabilirdi.
    // _wifiYaz ile AYNI 12sn zaman aşımı deseni uygulandı.
    await () async {
      // MTU'ya göre parçala
      // Sabit 20 baytlık parça, 5 KB'lık barkodlu fişte ~250 yazma × 6 ms
      // + BLE gidiş-dönüşü demekti. Anlaşılan MTU kadar (en az 20) gönderilir.
      int mtu = 20;
      try {
        mtu = (c.device.mtuNow - 3).clamp(20, 244);
      } catch (_) {}
      for (int i = 0; i < bytes.length; i += mtu) {
        final son   = (i + mtu < bytes.length) ? i + mtu : bytes.length;
        final parca = Uint8List.fromList(bytes.sublist(i, son));
        if (c.properties.writeWithoutResponse) {
          await c.write(parca, withoutResponse: true);
        } else {
          await c.write(parca);
        }
        await Future.delayed(const Duration(milliseconds: 6));
      }
    }().timeout(const Duration(seconds: 12),
        onTimeout: () => throw Exception(
            'Yazıcıya veri gönderilemedi (12sn zaman aşımı — Bluetooth bağlantısı muhtemelen donmuş)'));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // USB — Android USB Host API (CDC-ACM / seri termal yazıcılar)
  // Not: USB termal yazıcıların büyük çoğunluğu bilgisayara "seri port"
  // olarak görünür (CDC-ACM) — bu yöntem bu tip yazıcılarla çalışır. Tamamen
  // vendor-specific bulk-transfer protokolü kullanan nadir modellerde
  // (üretici özel sürücü isteyen) çalışmayabilir.
  // ══════════════════════════════════════════════════════════════════════════

  /// Cihaza takılı USB yazıcı/seri cihazları listeler. Android'de USB Host
  /// izni ilk bağlantıda sistem tarafından otomatik sorulur.
  Future<List<UsbDevice>> usbCihazlariTara() async {
    if (!Platform.isAndroid) return [];
    try {
      return await UsbSerial.listDevices();
    } catch (e) {
      if (kDebugMode) debugPrint('USB tarama hatası: $e');
      return [];
    }
  }

  Future<bool> usbBaglan(YaziciModel yazici, UsbDevice cihaz) async {
    await _aktif?.kapat();
    try {
      final port = await cihaz.create();
      if (port == null) throw Exception('USB port oluşturulamadı');

      final acildi = await port.open();
      if (!acildi) throw Exception('USB port açılamadı (izin reddedilmiş olabilir)');

      // Çoğu termal yazıcı 9600-115200 baud arasında çalışır; ESC/POS
      // yazıcılarda genellikle baud hızı önemli değildir (bulk transfer),
      // ama CDC-ACM sürücüsü bir değer bekler.
      await port.setDTR(true);
      await port.setRTS(true);
      await port.setPortParameters(
        9600,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      final baglanti = YaziciBaglanti(yazici: yazici, tur: YaziciTur.usb, bagliMi: true);
      baglanti._usbPort = port;
      _aktif = baglanti;

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('USB bağlantı hatası: $e');
      rethrow;
    }
  }

  Future<void> _usbYaz(List<int> bytes) async {
    final port = _aktif?._usbPort;
    if (port == null) throw Exception('USB yazıcı bağlı değil');
    // 🔴 Derin denetimde bulundu (P2): _wifiYaz ile AYNI zaman aşımı
    // eksikliği — port.write() donarsa yazdırma süresiz asılı kalırdı.
    await port.write(Uint8List.fromList(bytes)).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception(
            'Yazıcıya veri gönderilemedi (12sn zaman aşımı — USB bağlantısı muhtemelen donmuş)'));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WINDOWS YAZICI (Yazıcılar ve Tarayıcılar'a kurulu herhangi bir yazıcı)
  // ══════════════════════════════════════════════════════════════════════════
  // Kurulu yazıcı sürücüsü üzerinden Windows yazdırma kuyruğuna (spooler)
  // RAW veri olarak ESC/POS/ZPL baytları gönderilir — marka/bağlantı türü
  // (USB, ağ, paylaşımlı) fark etmez.

  Future<List<String>> windowsYazicilar() async {
    if (!Platform.isWindows) return [];
    try {
      final liste = await pr.Printing.listPrinters();
      return liste.map((p) => p.name).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Windows yazıcı listesi hatası: $e');
      return [];
    }
  }

  /// [yazici.cihazId] = Windows'taki yazıcı adı.
  Future<bool> windowsBaglan(YaziciModel yazici) async {
    if (!Platform.isWindows) return false;
    final ad = yazici.cihazId;
    if (ad == null || ad.isEmpty) return false;
    final kurulular = await windowsYazicilar();
    if (!kurulular.contains(ad)) return false;
    await _aktif?.kapat();
    _aktif = YaziciBaglanti(yazici: yazici, tur: YaziciTur.windows, bagliMi: true);
    return true;
  }

  static const _rawPs = r'''
param([string]$Printer, [string]$File)
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class RawPrn {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
  public class DOCINFO { [MarshalAs(UnmanagedType.LPStr)] public string n; [MarshalAs(UnmanagedType.LPStr)] public string o; [MarshalAs(UnmanagedType.LPStr)] public string d; }
  [DllImport("winspool.drv", CharSet=CharSet.Ansi, SetLastError=true)] public static extern bool OpenPrinter(string p, out IntPtr h, IntPtr d);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool ClosePrinter(IntPtr h);
  [DllImport("winspool.drv", CharSet=CharSet.Ansi, SetLastError=true)] public static extern bool StartDocPrinter(IntPtr h, int l, [In] DOCINFO di);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool EndDocPrinter(IntPtr h);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool StartPagePrinter(IntPtr h);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool EndPagePrinter(IntPtr h);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool WritePrinter(IntPtr h, byte[] b, int c, out int w);
  public static void Send(string printer, byte[] bytes) {
    IntPtr h; if (!OpenPrinter(printer, out h, IntPtr.Zero)) throw new Exception("Yazici acilamadi: " + printer);
    try {
      var di = new DOCINFO { n = "BarkoPro", o = null, d = "RAW" };
      if (!StartDocPrinter(h, 1, di)) throw new Exception("StartDoc basarisiz");
      StartPagePrinter(h); int w;
      bool ok = WritePrinter(h, bytes, bytes.Length, out w);
      EndPagePrinter(h); EndDocPrinter(h);
      if (!ok) throw new Exception("WritePrinter basarisiz");
    } finally { ClosePrinter(h); }
  }
}
"@
[RawPrn]::Send($Printer, [System.IO.File]::ReadAllBytes($File))
''';

  Future<void> _windowsYaz(List<int> bytes) async {
    final ad = _aktif?.yazici.cihazId;
    if (ad == null || ad.isEmpty) throw Exception('Windows yazıcı seçilmemiş');
    final klasor = await Directory.systemTemp.createTemp('barkopro_yazdir');
    try {
      final ps = File('${klasor.path}\\raw.ps1');
      // PowerShell 5.1 BOM'suz dosyayı ANSI okur; script ASCII olduğundan sorun yok.
      await ps.writeAsString(_rawPs);
      final veri = File('${klasor.path}\\veri.bin');
      await veri.writeAsBytes(bytes);
      final sonuc = await Process.run('powershell', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps.path,
        '-Printer', ad, '-File', veri.path,
      ]).timeout(const Duration(seconds: 20));
      if (sonuc.exitCode != 0) {
        throw Exception('Yazdırma hatası: ${(sonuc.stderr as Object).toString().trim()}');
      }
    } finally {
      try { await klasor.delete(recursive: true); } catch (_) {}
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BAĞLANTIYI KES
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> baglantiKes() async {
    await _aktif?.kapat();
    _aktif = null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ORTAK: byte yazma (WiFi veya BT'ye göre yönlendir)
  // ══════════════════════════════════════════════════════════════════════════

  // Yazdırma işleri sırayla çalışır: iki eşzamanlı çağrı (satış sonrası fiş +
  // etiket) birbirinin soketini kapatıp baytları karıştırabiliyordu.
  Future<void> _yazdirKuyrukSonu = Future.value();

  Future<void> _yazdir(List<int> bytes) {
    final sonuc = _yazdirKuyrukSonu.then((_) => _yazdirSirali(bytes));
    _yazdirKuyrukSonu = sonuc.catchError((_) {});
    return sonuc;
  }

  Future<void> _yazdirSirali(List<int> bytes) async {
    // ÖNCEDEN BURADA CİDDİ BİR HATA VARDI: bağlantı (_aktif) herhangi
    // bir nedenle kopmuşsa (uygulama arka plana atılıp WiFi/Bluetooth
    // kısa süreliğine kesilmesi, yazıcının uykuya geçmesi, splash'teki
    // otomatikBaglan()'ın geçici bir nedenle başarısız olması vb.) bu
    // fonksiyon SADECE hata fırlatıp duruyordu — kayıtlı yazıcı bilgisi
    // veritabanında dururken bile HİÇBİR ZAMAN otomatik yeniden
    // bağlanmayı denemiyordu. Kullanıcının "yazıcı kayıtlı ama tetiklemiyor,
    // silip tekrar bağlanmak zorunda kalıyorum" şikayeti tam olarak
    // buydu. Artık bağlantı kopmuşsa, yazdırmadan ÖNCE kayıtlı
    // varsayılan yazıcıyla otomatik yeniden bağlanma deneniyor.
    if (_aktif == null || !_aktif!.bagliMi) {
      final yenidenBaglandi = await _yenidenBaglanCircuitBreaker();
      if (!yenidenBaglandi || _aktif == null || !_aktif!.bagliMi) {
        throw Exception('Yazıcı bağlı değil (otomatik yeniden bağlanma da başarısız oldu)');
      }
    }

    // DAHA DERİN BİR SORUN: `bagliMi` bayrağı gerçek zamanlı bir
    // canlılık kontrolü DEĞİL — sadece bağlantı ilk kurulduğunda "true"
    // olarak set edilen, önbelleğe alınmış bir durum. Yazıcı sessizce
    // kapanır/WiFi kesilirse (soket seviyesinde "zombi bağlantı"),
    // `bagliMi` hâlâ yanlışlıkla "true" görünebilir — ve gerçek yazma
    // işlemi (_wifiYaz/_btYaz) hiç try-catch içermediği için, hata
    // sessizce yukarı fırlayıp bir yerde yutulabiliyordu (örn. satış
    // sonrası otomatik yazdırmada). Artık yazma başarısız olursa,
    // bağlantı ÖLÜ kabul edilip TAM bir yeniden bağlanma + TEK seferlik
    // tekrar deneme yapılıyor.
    try {
      await _tekYazmaDene(bytes);
    } catch (e) {
      if (kDebugMode) debugPrint('🔴 Yazdırma başarısız, yeniden bağlanıp tekrar deneniyor: $e');
      // Eski bağlantı KAPATILMALI: tek bağlantı kabul eden yazıcılar açık
      // kalan (ölü ya da yavaş) soketi tutarken yenisini reddeder; ayrıca
      // her başarısız yazmada bir soket/GATT bağlantısı sızıyordu.
      final eski = _aktif;
      _aktif = null;
      await eski?.kapat();
      final yenidenBaglandi = await _yenidenBaglanCircuitBreaker();
      if (!yenidenBaglandi || _aktif == null || !_aktif!.bagliMi) {
        throw Exception('Yazıcıya yazılamadı ve yeniden bağlanma başarısız oldu: $e');
      }
      await _tekYazmaDene(bytes); // ikinci deneme — başarısız olursa hatayı yukarı fırlat
    }
  }

  /// Ağ yazıcısında bir süredir işlem yapılmadıysa soket "zombi" olabilir
  /// (yazıcı sessizce bağlantıyı bıraktı; add()+flush() hata vermeden
  /// başarılı görünür ama fiş çıkmaz, 12 sn'lik bekleme sonra hata gelir).
  /// Boşta kalan bağlantı yazmadan ÖNCE taze soketle yenilenir — LAN'da
  /// birkaç ms sürer, "geç çıkıyor / bazen hiç çıkmıyor" durumunu önler.
  DateTime? _sonAgYazma;
  Future<void> _agSoketiTazele() async {
    final a = _aktif;
    if (a == null || a.tur != YaziciTur.wifi) return;
    final son = _sonAgYazma;
    if (son != null &&
        DateTime.now().difference(son) < const Duration(seconds: 20)) {
      return;
    }
    try {
      await wifiBaglan(a.yazici);
    } catch (_) {/* yazma denemesi hatayı zaten yönetir */}
  }

  Future<void> _tekYazmaDene(List<int> bytes) async {
    await _agSoketiTazele();
    switch (_aktif!.tur) {
      case YaziciTur.wifi:      await _wifiYaz(bytes);
      case YaziciTur.bluetooth: await _btYaz(bytes);
      case YaziciTur.rawbt: await _rawbtYaz(Uint8List.fromList(bytes));
      case YaziciTur.usb: await _usbYaz(bytes);
      case YaziciTur.windows: await _windowsYaz(bytes);
    }
  }

}
