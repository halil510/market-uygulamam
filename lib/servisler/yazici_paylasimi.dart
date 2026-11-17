// lib/servisler/yazici_paylasimi.dart
//
// Ürün Güncelleme'deki lib/etiket/yazici_paylasimi.dart ile aynı mantık (yalnız ayar SharedPreferences'ta).
//
// Windows'a USB ile takılı etiket yazıcısını ağa açar: telefon (Ürün Güncelleme / market uygulaması) bilgisayarın
// IP adresine, 9100 portuna bağlanıp TSPL / ESC/POS komutu gönderir; gelen bayt olduğu gibi (RAW) yazıcıya aktarılır.
//
// İş sınırı: bağlantı kapanınca ya da [bekleme] süresi boyunca veri gelmeyince biriken veri basılır (market uygulaması
// bağlantıyı açık tutar). İşler sırayla aynı yazıcıya gittiği için bir işin ikiye bölünmesi baskıyı değiştirmez.
// Bağlantı hatayla koparsa yarım kalan parça basılmaz (yarım BITMAP komutu yazıcıyı bekletir).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'windows_etiket_yazici.dart';

const paylasimPortu = 9100;
const _ayarAnahtari = 'etiket_yazici_paylasim';

class YaziciPaylasimi extends ChangeNotifier {
  final String yazici;
  final ServerSocket _sunucu;
  final Future<void> Function(Uint8List) _gonder;
  final Duration bekleme;
  final int enFazlaTampon;

  int isSayisi = 0;
  int baytSayisi = 0;
  DateTime? sonIs;
  String? sonHata;

  final _baglantilar = <Socket>{};
  Future<void> _sira = Future.value();
  bool _kapali = false;

  YaziciPaylasimi._(this.yazici, this._sunucu, this._gonder, this.bekleme, this.enFazlaTampon) {
    _sunucu.listen(_baglan, onError: (Object e) => _hata('Bağlantı kabul edilemedi: $e'));
  }

  /// Sunucuyu açar. [gonder] verilmezse veri Windows'ta [yazici]ya RAW olarak gider.
  static Future<YaziciPaylasimi> baslat(
    String yazici, {
    int port = paylasimPortu,
    InternetAddress? adres,
    Future<void> Function(Uint8List veri)? gonder,
    Duration bekleme = const Duration(milliseconds: 1500),
    int enFazlaTampon = 4 << 20,
  }) async {
    final s = await ServerSocket.bind(adres ?? InternetAddress.anyIPv4, port);
    return YaziciPaylasimi._(
      yazici,
      s,
      gonder ?? (v) async => windowsHamGonder(yazici, v),
      bekleme,
      enFazlaTampon,
    );
  }

  int get port => _sunucu.port;
  bool get kapali => _kapali;

  void _baglan(Socket s) {
    _baglantilar.add(s);
    final tampon = BytesBuilder(copy: false);
    Timer? zaman;
    void bitir() {
      zaman?.cancel();
      zaman = null;
      if (tampon.isNotEmpty) _isEkle(tampon.takeBytes());
    }

    s.listen(
      (d) {
        tampon.add(d);
        zaman?.cancel();
        if (tampon.length >= enFazlaTampon) {
          bitir();
        } else {
          zaman = Timer(bekleme, bitir);
        }
      },
      onDone: () {
        bitir();
        _baglantilar.remove(s);
        s.destroy();
      },
      onError: (Object e) {
        zaman?.cancel();
        tampon.clear();
        _baglantilar.remove(s);
        s.destroy();
        _hata('Telefonla bağlantı koptu, yarım kalan etiket basılmadı ($e)');
      },
      cancelOnError: true,
    );
  }

  void _isEkle(Uint8List veri) {
    _sira = _sira.then((_) async {
      try {
        await _gonder(veri);
        isSayisi++;
        baytSayisi += veri.length;
        sonIs = DateTime.now();
        sonHata = null;
        if (!_kapali) notifyListeners();
      } catch (e) {
        _hata('$e');
      }
    });
  }

  void _hata(String m) {
    sonHata = m;
    if (!_kapali) notifyListeners();
  }

  /// Sıradaki işler bitene kadar bekler (test).
  Future<void> bosalt() => _sira;

  Future<void> kapat() async {
    if (_kapali) return;
    _kapali = true;
    await _sunucu.close();
    for (final s in _baglantilar.toList()) {
      s.destroy();
    }
    _baglantilar.clear();
    await _sira;
  }
}

/// Bilgisayarın telefondan erişilebilecek IPv4 adresleri.
Future<List<String>> yerelAdresler() async {
  try {
    final l = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in l)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.address.startsWith('169.254.')) a.address,
    ];
  } catch (_) {
    return const [];
  }
}

/// Uygulama genelinde tek paylaşım (Windows).
class PaylasimYoneticisi {
  PaylasimYoneticisi._();

  static final etkin = ValueNotifier<YaziciPaylasimi?>(null);
  static final baslatmaHatasi = ValueNotifier<String?>(null);

  static Future<String?> kayitliYazici() async {
    final v = (await SharedPreferences.getInstance()).getString(_ayarAnahtari);
    return v == null || v.isEmpty ? null : v;
  }

  /// Uygulama açılırken: ayarda yazıcı varsa paylaşımı başlatır. Hata uygulamayı durdurmaz.
  static Future<void> ayardanBaslat() async {
    if (!Platform.isWindows) return;
    try {
      final y = await kayitliYazici();
      if (y != null) await _baslat(y);
    } catch (e) {
      baslatmaHatasi.value = 'Yazıcı ağa açılamadı: $e';
    }
  }

  static Future<bool> ac(String yazici) async {
    await (await SharedPreferences.getInstance()).setString(_ayarAnahtari, yazici);
    return _baslat(yazici);
  }

  static Future<void> kapat() async {
    await (await SharedPreferences.getInstance()).remove(_ayarAnahtari);
    await _durdur();
    baslatmaHatasi.value = null;
  }

  static Future<void> _durdur() async {
    final e = etkin.value;
    etkin.value = null;
    await e?.kapat();
  }

  static Future<bool> _baslat(String yazici) async {
    await _durdur();
    try {
      etkin.value = await YaziciPaylasimi.baslat(yazici);
      baslatmaHatasi.value = null;
      return true;
    } on SocketException catch (e) {
      baslatmaHatasi.value = 'Port $paylasimPortu açılamadı (başka bir program kullanıyor olabilir): ${e.osError?.message ?? e.message}';
      return false;
    } catch (e) {
      baslatmaHatasi.value = 'Yazıcı ağa açılamadı: $e';
      return false;
    }
  }

  /// Windows güvenlik duvarında 9100 portuna gelen bağlantılara izin verir (yönetici onayı ister).
  /// Başarılıysa null, değilse hata metni döner.
  static Future<String?> guvenlikDuvarinaIzinVer() async {
    const kural = 'UrunGuncellemeYazici$paylasimPortu';
    const komut = "\$p = Start-Process cmd -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList "
        "'/c netsh advfirewall firewall delete rule name=$kural >nul 2>&1 & "
        "netsh advfirewall firewall add rule name=$kural dir=in action=allow protocol=TCP localport=$paylasimPortu profile=any'; "
        "exit \$p.ExitCode";
    try {
      final r = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', komut]);
      if (r.exitCode == 0) return null;
      return 'Güvenlik duvarı izni verilemedi (yönetici onayı verilmedi ya da reddedildi).';
    } catch (e) {
      return 'Güvenlik duvarı izni verilemedi: $e';
    }
  }
}
