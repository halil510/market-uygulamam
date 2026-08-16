// lib/servisler/mail/imap_ham_istemci.dart
//
// MİNİMAL, HAM IMAP4rev1 İSTEMCİSİ
// ------------------------------------------------------------------
// enough_mail paketi, projenin diğer bağımlılıklarıyla (intl/archive/excel
// üçgeni) kesin çözülemez bir sürüm çakışması yarattığı için (bkz.
// DERIN_YOL_HARITASI.md), bu minimal istemci sıfır harici bağımlılıkla
// yazıldı — sadece dart:io SecureSocket kullanır (WiFi yazıcı bağlantısı
// için zaten kullanılan aynı yöntem, bkz. yazdirma_servisi.dart).
//
// Kapsam BİLİNÇLİ OLARAK sınırlı: sadece gelen kutusundaki SON N mesajın
// Konu/Gönderen/Tarih/Metin özetini okur (fatura/borç tespiti için yeterli).
// Tam bir MIME/ekli-dosya ayrıştırıcısı DEĞİLDİR.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ImapHamMesaj {
  final String konu;
  final String gonderen;
  final DateTime tarih;
  final String metinOzeti;
  const ImapHamMesaj({
    required this.konu,
    required this.gonderen,
    required this.tarih,
    required this.metinOzeti,
  });
}

class ImapHamIstemciException implements Exception {
  final String mesaj;
  ImapHamIstemciException(this.mesaj);
  @override
  String toString() => mesaj;
}

class ImapHamIstemci {
  final String host;
  final int port;
  SecureSocket? _soket;
  final _tamponlar = <int>[];
  int _etiketSayaci = 0;
  final _bekleyenYanitlar = <String, Completer<List<String>>>{};
  final _satirBiriktir = <String>[];
  StreamSubscription? _dinleyici;

  ImapHamIstemci({required this.host, this.port = 993});

  String _sonrakiEtiket() => 'A${(++_etiketSayaci).toString().padLeft(3, '0')}';

  Future<void> baglan() async {
    _soket = await SecureSocket.connect(host, port,
        timeout: const Duration(seconds: 12));
    final tamamlaici = Completer<void>();
    var ilkSatirGeldi = false;
    _dinleyici = _soket!.listen((veri) {
      _tamponlar.addAll(veri);
      _tamponuIsle();
      if (!ilkSatirGeldi && _satirBiriktir.isNotEmpty) {
        ilkSatirGeldi = true;
        if (!tamamlaici.isCompleted) tamamlaici.complete();
      }
    }, onError: (e) {
      if (!tamamlaici.isCompleted) tamamlaici.completeError(e);
    });
    await tamamlaici.future.timeout(const Duration(seconds: 12),
        onTimeout: () => throw ImapHamIstemciException('Sunucu yanıt vermedi'));
    _satirBiriktir.clear();
  }

  void _tamponuIsle() {
    while (true) {
      final idx = _indexOfCRLF();
      if (idx < 0) break;
      final satirBytes = _tamponlar.sublist(0, idx);
      _tamponlar.removeRange(0, idx + 2);
      final satir = latin1.decode(satirBytes);
      _satirBiriktir.add(satir);
      _etiketliYanitKontrol(satir);
    }
  }

  int _indexOfCRLF() {
    for (int i = 0; i < _tamponlar.length - 1; i++) {
      if (_tamponlar[i] == 13 && _tamponlar[i + 1] == 10) return i;
    }
    return -1;
  }

  void _etiketliYanitKontrol(String satir) {
    for (final etiket in _bekleyenYanitlar.keys.toList()) {
      if (satir.startsWith('$etiket ')) {
        final tamamlaici = _bekleyenYanitlar.remove(etiket)!;
        if (!tamamlaici.isCompleted) {
          tamamlaici.complete(List<String>.from(_satirBiriktir));
        }
        _satirBiriktir.clear();
        return;
      }
    }
  }

  Future<List<String>> _komutGonder(String komut) async {
    final etiket = _sonrakiEtiket();
    final tamamlaici = Completer<List<String>>();
    _bekleyenYanitlar[etiket] = tamamlaici;
    _soket!.add(utf8.encode('$etiket $komut\r\n'));
    await _soket!.flush();
    return tamamlaici.future.timeout(const Duration(seconds: 20),
        onTimeout: () => throw ImapHamIstemciException('Zaman aşımı: $komut'));
  }

  Future<void> girisYap(String email, String appSifre) async {
    // Kullanıcı adı/şifre IMAP quoted-string olarak gönderiliyor; içindeki
    // " ve \ karakterleri kaçırılıyor (RFC 3501).
    String kacir(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    final yanit = await _komutGonder('LOGIN "${kacir(email)}" "${kacir(appSifre)}"');
    final sonSatir = yanit.isNotEmpty ? yanit.last : '';
    if (!sonSatir.contains('OK')) {
      throw ImapHamIstemciException(
          'Giriş başarısız — e-posta veya uygulama şifresi hatalı olabilir.');
    }
  }

  Future<int> gelenKutusunuSec() async {
    final yanit = await _komutGonder('SELECT INBOX');
    int mesajSayisi = 0;
    for (final satir in yanit) {
      final m = RegExp(r'^\* (\d+) EXISTS').firstMatch(satir);
      if (m != null) mesajSayisi = int.tryParse(m.group(1)!) ?? 0;
    }
    if (!(yanit.isNotEmpty && yanit.last.contains('OK'))) {
      throw ImapHamIstemciException('Gelen kutusu açılamadı');
    }
    return mesajSayisi;
  }

  /// Son [limit] mesajın konu/gönderen/tarih/metin özetini getirir.
  Future<List<ImapHamMesaj>> sonMesajlariGetir({int limit = 30}) async {
    final toplam = await gelenKutusunuSec();
    if (toplam == 0) return [];
    final baslangic = (toplam - limit + 1).clamp(1, toplam);
    final yanit = await _komutGonder(
        '$baslangic:$toplam FETCH (BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)] BODY.PEEK[TEXT]<0.1500>)');
    return _fetchYanitiniAyristir(yanit);
  }

  /// IMAP FETCH yanıtındaki literal ({n}\r\n<n bayt>) bloklarını ayrıştırır.
  /// Tam RFC-uyumlu bir ayrıştırıcı değildir — Gmail/Outlook'un tipik
  /// yanıt formatı için yeterlidir.
  List<ImapHamMesaj> _fetchYanitiniAyristir(List<String> satirlar) {
    final mesajlar = <ImapHamMesaj>[];
    final tamMetin = satirlar.join('\r\n');
    // Her "* N FETCH (...)" bloğunu ayır
    final bloklar = tamMetin.split(RegExp(r'\*\s+\d+\s+FETCH'));
    for (final blok in bloklar.skip(1)) {
      String konu = '(Konu yok)';
      String gonderen = 'Bilinmiyor';
      DateTime tarih = DateTime.now();
      String govde = '';

      final konuM = RegExp(r'Subject:\s*(.*)', caseSensitive: false).firstMatch(blok);
      if (konuM != null) konu = _decodeMimeHeader(konuM.group(1)!.trim());

      final fromM = RegExp(r'From:\s*(.*)', caseSensitive: false).firstMatch(blok);
      if (fromM != null) gonderen = _decodeMimeHeader(fromM.group(1)!.trim());

      final dateM = RegExp(r'Date:\s*(.*)', caseSensitive: false).firstMatch(blok);
      if (dateM != null) {
        final ayristirilan = _tarihAyristir(dateM.group(1)!.trim());
        if (ayristirilan != null) tarih = ayristirilan;
      }

      // BODY[TEXT] kısmındaki literal içeriği kabaca al: son literal bloğu
      final literalM = RegExp(r'\{(\d+)\}\r?\n').allMatches(blok).toList();
      if (literalM.isNotEmpty) {
        final son = literalM.last;
        final uzunluk = int.tryParse(son.group(1)!) ?? 0;
        final baslangicIdx = son.end;
        if (baslangicIdx + uzunluk <= blok.length) {
          govde = blok.substring(baslangicIdx, baslangicIdx + uzunluk);
        } else if (baslangicIdx < blok.length) {
          govde = blok.substring(baslangicIdx);
        }
      }

      mesajlar.add(ImapHamMesaj(
        konu: konu,
        gonderen: gonderen,
        tarih: tarih,
        metinOzeti: govde.trim(),
      ));
    }
    return mesajlar.reversed.toList(); // en yeni üstte
  }

  /// =?UTF-8?B?...?= gibi MIME encoded-word başlıklarını çözer (kabaca).
  String _decodeMimeHeader(String ham) {
    try {
      final m = RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]*)\?=').firstMatch(ham);
      if (m == null) return ham;
      final kodlama = m.group(2)!.toUpperCase();
      final veri = m.group(3)!;
      if (kodlama == 'B') {
        return utf8.decode(base64.decode(veri), allowMalformed: true);
      } else {
        // Q-encoding: kabaca alt çizgiyi boşluğa çevir, =XX çöz
        final duz = veri.replaceAll('_', ' ');
        return duz.replaceAllMapped(RegExp(r'=([0-9A-Fa-f]{2})'),
            (mm) => String.fromCharCode(int.parse(mm.group(1)!, radix: 16)));
      }
    } catch (_) {
      return ham;
    }
  }

  DateTime? _tarihAyristir(String rfc2822) {
    try {
      // "Mon, 3 Jul 2026 14:32:10 +0300" tarzı — basitleştirilmiş ayrıştırma
      final temiz = rfc2822.replaceAll(RegExp(r'\s+\([^)]*\)$'), '').trim();
      final parcalar = temiz.split(' ').where((p) => p.isNotEmpty).toList();
      if (parcalar.length < 5) return null;
      const aylar = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final gun = int.tryParse(parcalar[1]) ?? 1;
      final ay = aylar[parcalar[2]] ?? 1;
      final yil = int.tryParse(parcalar[3]) ?? DateTime.now().year;
      final saatParcalari = parcalar[4].split(':');
      final saat = int.tryParse(saatParcalari[0]) ?? 0;
      final dakika = saatParcalari.length > 1 ? int.tryParse(saatParcalari[1]) ?? 0 : 0;
      return DateTime(yil, ay, gun, saat, dakika);
    } catch (_) {
      return null;
    }
  }

  Future<void> cikisYap() async {
    try {
      await _komutGonder('LOGOUT');
    } catch (_) {
      // sorun değil, zaten kapatıyoruz
    }
  }

  Future<void> kapat() async {
    await _dinleyici?.cancel();
    try {
      await _soket?.close();
    } catch (_) { /* soket zaten kapalı olabilir — kapatma hatası önemsiz */ }
    _soket = null;
  }
}
