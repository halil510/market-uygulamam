// lib/servisler/yazdirma_servisi.dart
// v4.0 — Profesyonel çok protokollü yazıcı servisi
// Desteklenen: WiFi/LAN (TCP:9100), Bluetooth LE, USB (via usb_serial)
// Profesyonel uygulamalar bu 3 protokolü destekler (Square, Clover, iiko vb.)

import 'dart:async';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:barcode/barcode.dart' as bcode;
import 'package:intl/intl.dart';
import '../modeller/fatura_model.dart';
import '../cekirdek/utils/sayi_yaziya_cevir.dart';
import '../modeller/satis_model.dart';
import '../modeller/urun_model.dart';
import '../modeller/yazici_model.dart';
import '../depolar/yazici_deposu.dart';
import '../veri/database/veritabani.dart';

// ─── Bağlantı türü ────────────────────────────────────────────────────────────
enum YaziciTur { wifi, bluetooth, usb, rawbt }

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
  static String _t(String s) => s
      .replaceAll('İ', 'I').replaceAll('ı', 'i')
      .replaceAll('Ş', 'S').replaceAll('ş', 's')
      .replaceAll('Ğ', 'G').replaceAll('ğ', 'g');

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
  List<int> _barkodBas(Generator generator, String veri) {
    final bytes = <int>[];
    final tamGenislik = _kagit == PaperSize.mm58 ? 384 : 576;
    final resim = _barkodResmiUret(
      veri,
      genislikPx: (tamGenislik * 0.75).round(),
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
  String _firmaAdi   = 'MarketPlus';

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
          "'fis_cari_goster')");
      final m = {for (final r in rows) r['anahtar'] as String: r['deger'] as String};
      _firmaAdi   = m['firma_adi']     ?? 'MarketPlus';
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
      // ignore: close_sinks
      // YANLIŞ POZİTİF: soketin sahipliği hemen aşağıda YaziciBaglanti'ya
      // devrediliyor (`baglanti._tcpSocket = socket`) ve bağlantı
      // `YaziciBaglanti.kapat()` içinde `_tcpSocket?.close()` ile
      // kapatılıyor. Lint sahiplik devrini takip edemediği için burada
      // "kapatılmamış Sink" sanıyor.
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 6));
      socket.setOption(SocketOption.tcpNoDelay, true);

      final baglanti = YaziciBaglanti(yazici: yazici, tur: YaziciTur.wifi, bagliMi: true);
      baglanti._tcpSocket = socket;
      _aktif = baglanti;

      // Socket kapandığında durumu güncelle
      socket.done.then((_) {
        if (_aktif?.yazici.id == yazici.id) {
          _aktif?.bagliMi = false;
        }
      }).catchError((_) {
        if (_aktif?.yazici.id == yazici.id) {
          _aktif?.bagliMi = false;
        }
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
    // ignore: close_sinks
    // YANLIŞ POZİTİF: burada yeni soket AÇILMIYOR — zaten açık olan
    // bağlantının soketi okunuyor. Kapatma sorumluluğu
    // YaziciBaglanti.kapat()'ta.
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
    } catch (e) {
      if (kDebugMode) debugPrint('[Yazdırma] WiFi yazma HATASI: $e');
      rethrow;
    }
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
                !addr.isLoopback && addr.address.startsWith('192.')) {
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

    // MTU'ya göre parçala
    const mtu = 20;
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
    await port.write(Uint8List.fromList(bytes));
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

  Future<void> _yazdir(List<int> bytes) async {
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
      final yenidenBaglandi = await otomatikBaglan();
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
      _aktif?.bagliMi = false;
      _aktif = null;
      final yenidenBaglandi = await otomatikBaglan();
      if (!yenidenBaglandi || _aktif == null || !_aktif!.bagliMi) {
        throw Exception('Yazıcıya yazılamadı ve yeniden bağlanma başarısız oldu: $e');
      }
      await _tekYazmaDene(bytes); // ikinci deneme — başarısız olursa hatayı yukarı fırlat
    }
  }

  Future<void> _tekYazmaDene(List<int> bytes) async {
    switch (_aktif!.tur) {
      case YaziciTur.wifi:      await _wifiYaz(bytes);
      case YaziciTur.bluetooth: await _btYaz(bytes);
      case YaziciTur.rawbt: await _rawbtYaz(Uint8List.fromList(bytes));
      case YaziciTur.usb: await _usbYaz(bytes);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FİŞ YAZDIRMA
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> fisYazdir(SatisModel satis, {
    String? firmaAdi, String? firmaAdres, String? firmaTel, String? altYazi,
    String? cariUnvan, String? kasiyerAdi,
    // 🔴 YENİ (kullanıcı bulgusu): Satış bir cariye (veresiye/hesaba)
    // yapıldıysa, müşterinin fişte önceki ve yeni bakiyesini görmesi
    // gerekiyor — bu iki parametre opsiyonel, sadece cari satışlarda
    // doldurulur.
    double? cariOncekiBakiye, double? cariSonBakiye,
  }) async {
    await ayarlariYukle();
    final profile   = await CapabilityProfile.load();
    final generator = Generator(_kagit, profile);

    final fa  = firmaAdi   ?? _firmaAdi;
    final fadr = firmaAdres ?? _firmaAdres;
    final ft  = firmaTel   ?? _firmaTel;
    final ay  = altYazi    ?? (_fisTesekkurGoster ? _fisTesekkurMetni : '');
    final tarih = DateFormat('dd.MM.yyyy HH:mm').format(satis.tarih);

    // Kopya sayısı kadar aynı fişi yazdır (Fiş Tasarım > Kopya Sayısı ayarı)
    for (int kopya = 0; kopya < _fisKopyaSayisi.clamp(1, 5); kopya++) {
      final List<int> bytes = [];

      bytes.addAll(generator.text(_t(fa),
          styles: const PosStyles(bold: true, align: PosAlign.center,
              height: PosTextSize.size2, width: PosTextSize.size1)));
      if (fadr.isNotEmpty)
        bytes.addAll(generator.text(_t(fadr), styles: const PosStyles(align: PosAlign.center)));
      if (ft.isNotEmpty)
        bytes.addAll(generator.text(_t('Tel: $ft'), styles: const PosStyles(align: PosAlign.center)));
      if (_fisVergiNoGoster && _firmaVergiNo.isNotEmpty)
        bytes.addAll(generator.text(_t('VKN: $_firmaVergiNo'), styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.hr(ch: '='));

      bytes.addAll(generator.row([
        PosColumn(text:_t('Tarih:'), width: 4, styles: const PosStyles(bold: true)),
        PosColumn(text:_t(tarih), width: 8),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text:_t('Fiş No:'), width: 4, styles: const PosStyles(bold: true)),
        PosColumn(text:_t(satis.fisNo ?? '-'), width: 8),
      ]));
      if (_fisKasiyerGoster && kasiyerAdi != null && kasiyerAdi.isNotEmpty)
        bytes.addAll(generator.row([
          PosColumn(text:_t('Kasiyer:'), width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text:_t(kasiyerAdi), width: 8),
        ]));
      // ══════════════════════════════════════════════════════════════════
      // 🆕 CARİ (MÜŞTERİ) ADI
      //
      // ÖNCEDEN: sadece `cariUnvan` parametresi doluysa basılıyordu —
      // ama fisYazdir()'ı çağıran 5 ekranın HİÇBİRİ bu parametreyi
      // geçmiyordu, dolayısıyla cari adı fişte HİÇ görünmüyordu.
      //
      // ARTIK: parametre boşsa satışın kendi `cariAdi` alanına geri
      // düşülüyor. SatisModel zaten cari_id ile JOIN'den geliyor, yani
      // veri elimizde — sadece kullanılmıyordu.
      //
      // Ayrıca `fis_cari_goster` ayarına bağlandı; perakende satış
      // yapan işletmeler kapatabilsin.
      // ══════════════════════════════════════════════════════════════════
      final gosterilecekCari =
          (cariUnvan != null && cariUnvan.isNotEmpty)
              ? cariUnvan
              : (satis.cariAdi ?? '');
      if (_fisCariGoster && gosterilecekCari.isNotEmpty)
        bytes.addAll(generator.row([
          PosColumn(text:_t('Cari:'), width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text:_t(gosterilecekCari), width: 8),
        ]));
      bytes.addAll(generator.hr());

      bytes.addAll(generator.row([
        PosColumn(text:_t('Urun'), width: 6, styles: const PosStyles(bold: true)),
        PosColumn(text:_t('Mkt'), width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
        PosColumn(text:_t('Fiy'), width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
        PosColumn(text:_t('Top'), width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]));
      bytes.addAll(generator.hr());

      double topIsk = 0, topKdv = 0;
      for (final k in satis.kalemler) {
        final mkt = k.miktar % 1 == 0
            ? '${k.miktar.toInt()}' : k.miktar.toStringAsFixed(2);
        // 🔴 DÜZELTME (kullanıcı bulgusu): Ürün adı 20 karakterden uzunsa
        // ikinci bir satıra KAYDIRILIYORDU (taşma) — 80mm kağıtta bu,
        // fişin okunmasını zorlaştırıyor ve dağınık görünüyordu. Artık
        // "…" ile KESİLİYOR, tek satırda kalıyor.
        final ad = k.urunAdi.length > 20 ? '${k.urunAdi.substring(0, 17)}...' : k.urunAdi;
        // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu): "Fiyat" sütunu
        // ÖNCEDEN her zaman k.birimFiyat (İNDİRİMSİZ, orijinal fiyat)
        // gösteriyordu — ama "Toplam" sütunu k.toplamTutar (netFiyat ×
        // miktar, yani İNDİRİMLİ) gösteriyordu. Bir üründe indirim
        // varsa, fişte "Fiyat × Miktar ≠ Toplam" gibi kafa karıştırıcı
        // bir tutarsızlık oluşuyordu. Artık indirim varsa NET (indirimli)
        // birim fiyat gösteriliyor — matematik tutarlı.
        final gosterilecekFiyat = k.iskontoTutar > 0 ? k.netFiyat : k.birimFiyat;
        bytes.addAll(generator.row([
          PosColumn(text:_t(ad),  width: 6),
          PosColumn(text:_t(mkt), width: 2, styles: const PosStyles(align: PosAlign.center)),
          PosColumn(text:_t(_fmt.format(gosterilecekFiyat)), width: 2, styles: const PosStyles(align: PosAlign.right)),
          PosColumn(text:_t(_fmt.format(k.toplamTutar)), width: 2, styles: const PosStyles(align: PosAlign.right)),
        ]));
        if (_fisUrunKoduGoster && (k.barkod?.isNotEmpty ?? false))
          bytes.addAll(generator.text(_t('  Kod: ${k.barkod}'),
              styles: const PosStyles(align: PosAlign.left)));
        if (k.iskontoTutar > 0)
          bytes.addAll(generator.text(_t('  İnd: -${_fmt.format(k.iskontoTutar)}')));
        if (_fisKdvGosterAna && _fisKdvDetayGoster && k.kdvTutar > 0)
          bytes.addAll(generator.text(_t('  KDV(%${k.kdvOran.toStringAsFixed(0)}): ${_fmt.format(k.kdvTutar)}')));
        topIsk += k.iskontoTutar;
        topKdv += k.kdvTutar;
      }
      bytes.addAll(generator.hr());

      if (topIsk > 0.001)
        bytes.addAll(generator.row([
          PosColumn(text:_t('ISKONTO'), width: 8),
          PosColumn(text:_t('-${_fmt.format(topIsk)}'), width: 4,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
      // KDV detay kapalıysa toplu KDV özeti gösterilir; açıksa yukarıda
      // satır satır zaten gösterildiği için burada tekrar edilmez.
      if (_fisKdvGosterAna && !_fisKdvDetayGoster && topKdv > 0.001)
        bytes.addAll(generator.row([
          PosColumn(text:_t('KDV'), width: 8),
          PosColumn(text:_t(_fmt.format(topKdv)), width: 4,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
      bytes.addAll(generator.row([
        PosColumn(text:_t('TOPLAM'), width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text:_t(_fmt.format(satis.genelToplam)), width: 4,
            styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]));
      if (_fisOdemeYontemiGoster)
        bytes.addAll(generator.row([
          PosColumn(text:_t('ODENEN (${satis.odemeYontemi})'), width: 8),
          PosColumn(text:_t(_fmt.format(satis.odenenTutar)), width: 4,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
      final paraUstu = satis.odenenTutar - satis.genelToplam;
      if (_fisParaUstuGoster && paraUstu > 0.01)
        bytes.addAll(generator.row([
          PosColumn(text:_t('PARA ÜSTÜ'), width: 8, styles: const PosStyles(bold: true)),
          PosColumn(text:_t(_fmt.format(paraUstu)), width: 4,
              styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]));

      bytes.addAll(generator.hr());

      // ══════════════════════════════════════════════════════════════════
      // 🆕 CARİ HESAP ÖZETİ — "Eski Bakiye / İşlem / Son Bakiye" üçlüsü
      //
      // Cariye (veresiye/hesaba) yapılan satışlarda müşteri fişte kendi
      // hesap durumunu görür. Profesyonel ön muhasebe programlarındaki
      // (Paraşüt, Uyumsoft vb.) cari ekstre satırının fiş karşılığıdır.
      //
      // İŞARET KURALI — bakiye = SUM(borc) - SUM(alacak) (cari_deposu):
      //   • Bakiye POZİTİF  → müşteri BİZE borçlu   → "Borç"
      //   • Bakiye NEGATİF  → biz müşteriye borçlu  → "Alacak"
      // Kullanıcı "-1.500,00" gibi çıplak bir eksi görüp kafası
      // karışmasın diye tutar mutlak değerle, yanına etiketle basılır.
      // ══════════════════════════════════════════════════════════════════
      if (_fisCariBakiyeGoster &&
          cariOncekiBakiye != null && cariSonBakiye != null) {
        bytes.addAll(generator.text(_t('CARI HESAP OZETI'),
            styles: const PosStyles(bold: true, align: PosAlign.center)));
        bytes.addAll(generator.row([
          PosColumn(text: _t('Eski Bakiye'), width: 7),
          PosColumn(text: _t(_bakiyeYaz(cariOncekiBakiye)), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
        // Bu satışın cariye yansıyan tutarı (bakiye farkı) — genel
        // toplamdan değil, iki bakiyenin farkından hesaplanır ki kısmi
        // ödeme yapılmış satışlarda da doğru olsun.
        final fark = cariSonBakiye - cariOncekiBakiye;
        bytes.addAll(generator.row([
          PosColumn(text: _t(fark >= 0 ? '(+) Bu Fis' : '(-) Bu Fis'), width: 7),
          PosColumn(text: _t(_fmt.format(fark.abs())), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
        bytes.addAll(generator.hr());
        bytes.addAll(generator.row([
          PosColumn(text: _t('SON BAKIYE'), width: 7,
              styles: const PosStyles(bold: true)),
          PosColumn(text: _t(_bakiyeYaz(cariSonBakiye)), width: 5,
              styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]));
        bytes.addAll(generator.hr(ch: '='));
      }

      if (ay.isNotEmpty)
        bytes.addAll(generator.text(_t(ay), styles: const PosStyles(align: PosAlign.center, bold: true)));

      // ══════════════════════════════════════════════════════════════════
      // 🆕 FİŞ BARKODU — fiş numarasını Code128 olarak basar
      //
      // Kasiyer bu barkodu Hızlı Satış ekranında okuttuğunda o satış
      // geri çağrılır (bkz. hizli_satis_ekrani._barkodIleEkle).
      //
      // Neden Code128: fiş no GİB standardında 16 KARAKTER ve harf
      // içeriyor (MKP2026000000001). EAN-13 sadece 13 rakam alır,
      // yetmez. Code128 alfanümerik ve değişken uzunlukludur.
      // ══════════════════════════════════════════════════════════════════
      if (_fisBarkodGoster && (satis.fisNo ?? '').isNotEmpty) {
        bytes.addAll(generator.feed(1));
        // Barkod RESİM olarak basılıyor — ESC/POS'un yerel barkod
        // komutunu (GS k) ucuz yazıcıların çoğu desteklemiyordu.
        bytes.addAll(_barkodBas(generator, satis.fisNo!));
      }

      bytes.addAll(generator.feed(_fisBeslemeKagit.clamp(0, 10)));
      bytes.addAll(generator.cut());

      await _yazdir(bytes);
      if (kopya < _fisKopyaSayisi - 1) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 TAHSİLAT / TEDİYE MAKBUZU
  //
  // Türkiye'de bu İKİ AYRI belgedir ve araştırma sonucu şu ayrım standart:
  //   • TAHSİLAT MAKBUZU — parayı ALAN taraf keser.
  //       Müşteriden tahsilat yaptığımızda biz keseriz.
  //   • TEDİYE MAKBUZU   — parayı VEREN taraf keser.
  //       Tedarikçiye ödeme yaptığımızda biz keseriz.
  // Başlık buna göre değişir; kalan alanlar aynıdır.
  //
  // ZORUNLU/STANDART ALANLAR (Paraşüt, Uyumsoft, Evobulut kaynaklarında
  // ortak olarak geçenler):
  //   makbuz no · tarih · cari unvan · tutar (RAKAM + YAZIYLA) ·
  //   ödeme türü · açıklama · eski/yeni bakiye · kesen kişi · imza yeri
  //
  // "Tutar yazıyla" isteğe bağlı bir süs değil: rakamın sonradan
  // değiştirilmesine (tahrifat) karşı standart güvenlik önlemidir.
  // Bu yüzden varsayılan olarak AÇIK gelir.
  //
  // NOT: Makbuz FATURA YERİNE GEÇMEZ — sadece para hareketini belgeler.
  // Bu uyarı makbuzun altına basılır ki kullanıcı yanlış kullanmasın.
  // ══════════════════════════════════════════════════════════════════════
  Future<void> makbuzYazdir({
    required String makbuzNo,
    required DateTime tarih,
    required String cariUnvan,
    required double tutar,
    required String odemeTuru,
    /// 'Tahsilat' → parayı biz aldık   → TAHSİLAT MAKBUZU
    /// 'Odeme'    → parayı biz verdik  → TEDİYE MAKBUZU
    required String islemTipi,
    String? aciklama,
    String? kesenKisi,
    double? oncekiBakiye,
    double? sonBakiye,
    String? firmaAdi,
    String? firmaAdres,
    String? firmaTel,
  }) async {
    await ayarlariYukle();
    final profile   = await CapabilityProfile.load();
    final generator = Generator(_kagit, profile);

    final tahsilatMi = islemTipi == 'Tahsilat';
    final baslik = tahsilatMi ? 'TAHSILAT MAKBUZU' : 'TEDIYE MAKBUZU';
    final tutarEtiketi = tahsilatMi ? 'Tahsil Edilen' : 'Odenen Tutar';
    final tarihStr = DateFormat('dd.MM.yyyy HH:mm').format(tarih);

    final fa   = firmaAdi   ?? _firmaAdi;
    final fadr = firmaAdres ?? _firmaAdres;
    final ft   = firmaTel   ?? _firmaTel;

    for (int kopya = 0; kopya < _fisKopyaSayisi.clamp(1, 5); kopya++) {
      final List<int> bytes = [];

      // ── Firma başlığı ────────────────────────────────────────────────
      bytes.addAll(generator.text(_t(fa),
          styles: const PosStyles(bold: true, align: PosAlign.center,
              height: PosTextSize.size2, width: PosTextSize.size1)));
      if (fadr.isNotEmpty) {
        bytes.addAll(generator.text(_t(fadr),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (ft.isNotEmpty) {
        bytes.addAll(generator.text(_t('Tel: $ft'),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (_fisVergiNoGoster && _firmaVergiNo.isNotEmpty) {
        bytes.addAll(generator.text(_t('VKN: $_firmaVergiNo'),
            styles: const PosStyles(align: PosAlign.center)));
      }
      bytes.addAll(generator.hr(ch: '='));

      // ── Belge başlığı ────────────────────────────────────────────────
      bytes.addAll(generator.text(_t(baslik),
          styles: const PosStyles(bold: true, align: PosAlign.center,
              height: PosTextSize.size2, width: PosTextSize.size1)));
      bytes.addAll(generator.hr(ch: '='));

      // ── Belge künyesi ────────────────────────────────────────────────
      bytes.addAll(generator.row([
        PosColumn(text: _t('Makbuz No:'), width: 4,
            styles: const PosStyles(bold: true)),
        PosColumn(text: _t(makbuzNo), width: 8),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text: _t('Tarih:'), width: 4,
            styles: const PosStyles(bold: true)),
        PosColumn(text: _t(tarihStr), width: 8),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text: _t(tahsilatMi ? 'Odeyen:' : 'Alan:'), width: 4,
            styles: const PosStyles(bold: true)),
        PosColumn(text: _t(cariUnvan), width: 8),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text: _t('Odeme:'), width: 4,
            styles: const PosStyles(bold: true)),
        PosColumn(text: _t(odemeTuru), width: 8),
      ]));
      if (aciklama != null && aciklama.trim().isNotEmpty) {
        bytes.addAll(generator.row([
          PosColumn(text: _t('Aciklama:'), width: 4,
              styles: const PosStyles(bold: true)),
          PosColumn(text: _t(aciklama.trim()), width: 8),
        ]));
      }
      bytes.addAll(generator.hr());

      // ── Tutar (rakam) ────────────────────────────────────────────────
      bytes.addAll(generator.row([
        PosColumn(text: _t(tutarEtiketi), width: 6,
            styles: const PosStyles(bold: true, height: PosTextSize.size2)),
        PosColumn(text: _t(_fmt.format(tutar)), width: 6,
            styles: const PosStyles(bold: true, align: PosAlign.right,
                height: PosTextSize.size2)),
      ]));

      // ── Tutar (yazıyla) — tahrifat önlemi ───────────────────────────
      if (_fisYaziylaTutar) {
        bytes.addAll(generator.text(_t('Yalniz: ${tutariYaziyaCevir(tutar)}'),
            styles: const PosStyles(bold: true)));
      }
      bytes.addAll(generator.hr());

      // ── Cari hesap özeti ────────────────────────────────────────────
      if (_fisCariBakiyeGoster &&
          oncekiBakiye != null && sonBakiye != null) {
        bytes.addAll(generator.text(_t('CARI HESAP OZETI'),
            styles: const PosStyles(bold: true, align: PosAlign.center)));
        bytes.addAll(generator.row([
          PosColumn(text: _t('Eski Bakiye'), width: 7),
          PosColumn(text: _t(_bakiyeYaz(oncekiBakiye)), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
        final fark = sonBakiye - oncekiBakiye;
        bytes.addAll(generator.row([
          PosColumn(text: _t(fark >= 0 ? '(+) Bu Makbuz' : '(-) Bu Makbuz'),
              width: 7),
          PosColumn(text: _t(_fmt.format(fark.abs())), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
        bytes.addAll(generator.hr());
        bytes.addAll(generator.row([
          PosColumn(text: _t('SON BAKIYE'), width: 7,
              styles: const PosStyles(bold: true)),
          PosColumn(text: _t(_bakiyeYaz(sonBakiye)), width: 5,
              styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]));
        bytes.addAll(generator.hr(ch: '='));
      }

      // ── Kesen + imza ────────────────────────────────────────────────
      if (kesenKisi != null && kesenKisi.isNotEmpty) {
        bytes.addAll(generator.row([
          PosColumn(text: _t(tahsilatMi ? 'Tahsil Eden:' : 'Odeyen:'),
              width: 5, styles: const PosStyles(bold: true)),
          PosColumn(text: _t(kesenKisi), width: 7),
        ]));
      }
      bytes.addAll(generator.feed(1));
      bytes.addAll(generator.text(_t('Imza / Kase'),
          styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text(_t('........................'),
          styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.hr());

      // ── Yasal uyarı ─────────────────────────────────────────────────
      // Araştırmadaki tüm kaynaklar (Paraşüt, Uyumsoft, Evobulut) bunu
      // vurguluyor: makbuz fatura yerine geçmez. Kullanıcı yanlış
      // kullanıp usulsüzlüğe düşmesin diye belgenin üstüne basılıyor.
      bytes.addAll(generator.text(
          _t('Bu belge fatura yerine gecmez.'),
          styles: const PosStyles(align: PosAlign.center)));

      // ── Makbuz barkodu ──────────────────────────────────────────────
      if (_fisBarkodGoster && makbuzNo.isNotEmpty) {
        bytes.addAll(generator.feed(1));
        bytes.addAll(_barkodBas(generator, makbuzNo));
      }

      bytes.addAll(generator.feed(_fisBeslemeKagit.clamp(0, 10)));
      bytes.addAll(generator.cut());

      await _yazdir(bytes);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FATURA — 80mm/58mm termal yazıcıya RAW ESC/POS
  // PDF tabanlı 80mm çıktı bazı termal yazıcılarda küçük/yanlış ölçekte
  // basıldığı için, yazıcı bağlıysa fatura da fiş gibi RAW gönderilir.
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> faturaYazdir(FaturaModel f) async {
    await ayarlariYukle();
    final profile   = await CapabilityProfile.load();
    final generator = Generator(_kagit, profile);
    final List<int> bytes = [];
    final tarih = DateFormat('dd.MM.yyyy HH:mm').format(f.duzenlenmeTarihi ?? f.tarih);

    bytes.addAll(generator.text(_t(_firmaAdi),
        styles: const PosStyles(bold: true, align: PosAlign.center,
            height: PosTextSize.size2, width: PosTextSize.size1)));
    if (_firmaAdres.isNotEmpty)
      bytes.addAll(generator.text(_t(_firmaAdres), styles: const PosStyles(align: PosAlign.center)));
    if (_firmaTel.isNotEmpty)
      bytes.addAll(generator.text(_t('Tel: $_firmaTel'), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.hr(ch: '='));

    bytes.addAll(generator.text(_t((f.faturaTipi ?? 'FATURA').toUpperCase()),
        styles: const PosStyles(bold: true, align: PosAlign.center)));
    bytes.addAll(generator.row([
      PosColumn(text:_t('No:'), width: 4, styles: const PosStyles(bold: true)),
      PosColumn(text:_t(f.faturaNo ?? '-'), width: 8),
    ]));
    bytes.addAll(generator.row([
      PosColumn(text:_t('Tarih:'), width: 4, styles: const PosStyles(bold: true)),
      PosColumn(text:_t(tarih), width: 8),
    ]));
    if (f.eFaturaUuid != null)
      bytes.addAll(generator.text(_t('ETTN: ${f.eFaturaUuid}'), styles: const PosStyles(align: PosAlign.left)));
    bytes.addAll(generator.hr());

    bytes.addAll(generator.text(_t('SAYIN'), styles: const PosStyles(bold: true)));
    bytes.addAll(generator.text(_t(f.cariUnvan ?? '-'), styles: const PosStyles(bold: true)));
    if (f.cariAdres != null && f.cariAdres!.isNotEmpty)
      bytes.addAll(generator.text(_t(f.cariAdres!)));
    bytes.addAll(generator.text(_t('VD: ${f.cariVergiDairesi ?? "-"}  VKN/TC: ${f.cariVergiNo ?? "-"}')));
    bytes.addAll(generator.hr());

    bytes.addAll(generator.row([
      PosColumn(text:_t('Ürün'), width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text:_t('Mik'), width: 2, styles: const PosStyles(align: PosAlign.center, bold: true)),
      PosColumn(text:_t('Fiyat'), width: 2, styles: const PosStyles(align: PosAlign.right, bold: true)),
      PosColumn(text:_t('Tutar'), width: 2, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]));
    for (final d in f.detaylar) {
      final mkt = d.miktar == d.miktar.roundToDouble()
          ? '${d.miktar.toInt()}' : d.miktar.toStringAsFixed(2);
      // 🔴 DÜZELTME (kullanıcı bulgusu — satış fişindeki AYNI hata
      // sınıfı): ürün adı kesiliyor (kaydırma yerine), ve indirim
      // varsa "Fiyat" sütunu indirimli net birim fiyatı gösteriyor
      // (toplamTutar zaten indirimli olduğu için miktar'a bölerek
      // güvenle türetiliyor — modeldeki alan adı farklılıklarına
      // bağımlı olmadan).
      final ad = d.urunAdi.length > 20 ? '${d.urunAdi.substring(0, 17)}...' : d.urunAdi;
      final netBirimFiyat = d.miktar > 0 ? d.toplamTutar / d.miktar : d.birimFiyat;
      final indirimliMi = d.iskontoTutari > 0.005;
      bytes.addAll(generator.row([
        PosColumn(text:_t(ad), width: 6),
        PosColumn(text:_t(mkt), width: 2, styles: const PosStyles(align: PosAlign.center)),
        PosColumn(text:_t(_fmt.format(indirimliMi ? netBirimFiyat : d.birimFiyat)), width: 2, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(text:_t(_fmt.format(d.toplamTutar)), width: 2, styles: const PosStyles(align: PosAlign.right)),
      ]));
      if (indirimliMi)
        bytes.addAll(generator.text(_t('  İnd: -${_fmt.format(d.iskontoTutari)}')));
    }
    bytes.addAll(generator.hr());

    bytes.addAll(generator.row([
      PosColumn(text:_t('Ara Toplam'), width: 8),
      PosColumn(text:_t(_fmt.format(f.toplamAraToplam)), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]));
    if (f.toplamIskonto > 0)
      bytes.addAll(generator.row([
        PosColumn(text:_t('İndirim'), width: 8),
        PosColumn(text:_t('-${_fmt.format(f.toplamIskonto)}'), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]));
    bytes.addAll(generator.row([
      PosColumn(text:_t('KDV'), width: 8),
      PosColumn(text:_t(_fmt.format(f.toplamKdv)), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(generator.row([
      PosColumn(text:_t('GENEL TOPLAM'), width: 8, styles: const PosStyles(bold: true)),
      PosColumn(text:_t(_fmt.format(f.genelToplam)), width: 4,
          styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(_t(tutariYaziyaCevir(f.genelToplam)),
        styles: const PosStyles(align: PosAlign.center)));

    try {
      final qrVeri = f.eFaturaUuid ?? f.faturaNo ?? 'MarketPlus';
      bytes.addAll(generator.qrcode(qrVeri));
    } catch (_) {/* QR desteklenmiyorsa atla */}

    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.text(_t(_altYazi), styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    await _yazdir(bytes);
  }

  Future<void> testFisYazdir() async {
    await ayarlariYukle();
    final profile   = await CapabilityProfile.load();
    final generator = Generator(_kagit, profile);
    final bytes     = <int>[];

    bytes.addAll(generator.text(_t(_firmaAdi),
        styles: const PosStyles(bold: true, align: PosAlign.center,
            height: PosTextSize.size2)));
    if (_firmaAdres.isNotEmpty)
      bytes.addAll(generator.text(_t(_firmaAdres), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(_t('*** TEST FİŞİ ***'),
        styles: const PosStyles(bold: true, align: PosAlign.center)));
    bytes.addAll(generator.text(_t(
        DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())),
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.row([
      PosColumn(text:_t('Test Ürün 1'), width: 8),
      PosColumn(text:_t('50,00'), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(generator.row([
      PosColumn(text:_t('Test Ürün 2'), width: 8),
      PosColumn(text:_t('35,00'), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.row([
      PosColumn(text:_t('TOPLAM'), width: 8, styles: const PosStyles(bold: true)),
      PosColumn(text:_t('85,00'), width: 4,
          styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(_t(_altYazi),
        styles: const PosStyles(align: PosAlign.center)));

    final tur = _aktif?.tur == YaziciTur.wifi ? 'WiFi/LAN'
        : _aktif?.tur == YaziciTur.bluetooth ? 'Bluetooth'
        : 'USB';
    bytes.addAll(generator.text(_t('Bağlantı: $tur'),
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    await _yazdir(bytes);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ETİKET YAZDIRMA
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> etiketYazdir(
    UrunModel urun, {
    bool barkodGoster    = true,
    bool fiyatGoster     = true,
    bool adGoster        = true,
    bool birimFiyatliMod = false,
    bool indirimliMod    = false,
    double? indirimFiyat,
    PaperSize etiketBoy  = PaperSize.mm58,
    int adet             = 1,
    // Aşağıdaki ayarlar önceden ekranda tanımlı ama hiçbir yere
    // bağlanmamıştı (arayüzde değiştirilse bile etikete yansımıyordu).
    // Artık gerçekten etikete basılıyor.
    bool firmaGoster     = false,
    bool lotNoGoster     = false,
    bool sktGoster       = false,
    bool anaGrupGoster   = false,
    bool kdvDahilFiyat   = true,
    bool aciklamaGoster  = false,
    String? ozelMetin,
  }) async {
    await ayarlariYukle();
    final profile   = await CapabilityProfile.load();
    final generator = Generator(etiketBoy, profile);

    for (int i = 0; i < adet; i++) {
      final bytes = <int>[];
      if (firmaGoster && _firmaAdi.isNotEmpty) {
        bytes.addAll(generator.text(_t(_firmaAdi),
            styles: const PosStyles(bold: false, align: PosAlign.center)));
      }
      if (adGoster) {
        final ad = urun.urunAdi;
        bytes.addAll(generator.text(_t(
          ad.length > 24 ? ad.substring(0, 24) : ad),
          styles: const PosStyles(bold: true, align: PosAlign.center),
        ));
        if (ad.length > 24)
          bytes.addAll(generator.text(_t(
            ad.substring(24, ad.length > 48 ? 48 : ad.length)),
            styles: const PosStyles(bold: true, align: PosAlign.center),
          ));
      }
      if (anaGrupGoster && (urun.anaGrup?.isNotEmpty ?? false)) {
        bytes.addAll(generator.text(_t(urun.anaGrup!),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (barkodGoster && urun.barkod != null && urun.barkod!.isNotEmpty) {
        // 🔴 ÜRÜN ETİKETİ BARKODU — fiş barkoduyla AYNI sorunu taşıyordu.
        // `generator.barcode()` (GS k komutu) ucuz termal yazıcıların
        // çoğunda çalışmıyor; etiketlerde de sadece barkod NUMARASI
        // basılıyor, çizgi çıkmıyordu. Artık resim olarak basılıyor.
        bytes.addAll(_barkodBas(generator, urun.barkod!));
      }
      if (lotNoGoster && (urun.lotNo?.isNotEmpty ?? false)) {
        bytes.addAll(generator.text(_t('Lot: ${urun.lotNo}'),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (sktGoster && (urun.sonKullanmaTarihi?.isNotEmpty ?? false)) {
        bytes.addAll(generator.text(_t('SKT: ${urun.sonKullanmaTarihi}'),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (aciklamaGoster && (urun.lotAciklama?.isNotEmpty ?? false)) {
        bytes.addAll(generator.text(_t(urun.lotAciklama!),
            styles: const PosStyles(align: PosAlign.center)));
      }
      if (fiyatGoster) {
        final tabanFiyat = indirimliMod && indirimFiyat != null ? indirimFiyat : urun.satisFiyati;
        // KDV Dahil anahtarı: kapalıysa KDV hariç (net) fiyat basılır.
        final kdv = double.tryParse(urun.kdvOran) ?? 0;
        final fiyat = kdvDahilFiyat ? tabanFiyat : tabanFiyat / (1 + kdv / 100);
        if (birimFiyatliMod) {
          bytes.addAll(generator.row([
            PosColumn(text:_t(urun.birimAdi.isEmpty ? 'Adet' : urun.birimAdi), width: 6,
                styles: const PosStyles(align: PosAlign.center)),
            PosColumn(text:_t('${_fmt.format(fiyat)} TL'), width: 6,
                styles: const PosStyles(bold: true, align: PosAlign.right)),
          ]));
        } else {
          bytes.addAll(generator.text(_t('${_fmt.format(fiyat)} TL'),
              styles: const PosStyles(bold: true, align: PosAlign.center,
                  height: PosTextSize.size2, width: PosTextSize.size1)));
        }
      }
      if (ozelMetin != null && ozelMetin.trim().isNotEmpty) {
        bytes.addAll(generator.text(_t(ozelMetin.trim()),
            styles: const PosStyles(align: PosAlign.center)));
      }
      bytes.addAll(generator.feed(1));
      bytes.addAll(generator.cut(mode: PosCutMode.partial));
      await _yazdir(bytes);
      if (adet > 1 && i < adet - 1)
        await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  // Legacy compat
  Future<void> _rawbtYaz(Uint8List bytes) async {
    final b64 = base64Encode(bytes);
    final encoded = Uri.encodeComponent(b64);
    final uri = Uri.parse('rawbt://print?base64=$encoded');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('RawBT uygulaması bulunamadı');
      }
    } catch (e) {
      throw Exception('RawBT hatası: $e');
    }
  }


  // ══════════════════════════════════════════════════════════════════════════
  // ZEBRA / ZPL — Doğrudan Ağ veya Bluetooth Etiket Yazıcısına Gönderim
  // BarTender'a gerek kalmadan, ZPL komutlarını mevcut bağlı yazıcıya
  // (WiFi:9100 veya BT) ham metin/byte olarak yollar. Yazıcı Zebra/ZPL
  // uyumlu olmalıdır (ZD/GK/GC/TLP serisi vb.).
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> zplGonder(String zpl) async {
    if (_aktif == null || !_aktif!.bagliMi) {
      throw Exception('Etiket yazıcısı bağlı değil. Ayarlar > Yazıcılar bölümünden '
          'Zebra yazıcınızı (WiFi veya Bluetooth) bağlayın.');
    }
    final bytes = utf8.encode(zpl);
    await _yazdir(bytes);
  }

  Future<bool> get yaziciBagliMi async => bagliMi;


  Future<bool> get btBagliMi async => bagliMi && _aktif?.tur == YaziciTur.bluetooth;
}
