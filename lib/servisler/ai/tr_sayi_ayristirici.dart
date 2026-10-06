// lib/servisler/ai/tr_sayi_ayristirici.dart
//
// Konuşma/yazı dilindeki Türkçe sayıları anlar — saf (Flutter/DB bağımsız),
// bu yüzden izole test edilebilir. Asistanın hem ürün formu sesli komutunda
// hem sohbet eylemlerinde ("kolanın fiyatını yirmi beş buçuk yap") kullanılır.
//
// Desteklenenler:
//   • Rakam:        25   25,50   25.50   1.250,75   1250   %18
//   • Yazıyla:      yirmi beş, yüz elli, bin iki yüz, on iki bin beş yüz
//   • Yarım/buçuk:  iki buçuk (2,5), bir buçuk, yarım (0,5), çeyrek (0,25)
//   • Para:         yirmi beş lira elli (25,50), on lira elli kuruş, 25 lira 5 kuruş
//   • Ondalık:      yirmi beş virgül elli (25,5 değil 25,50 → 25.5), üç nokta beş
//   • Karışık:      25 buçuk, 3 bin 500, 2 milyon
class TrSayi {
  TrSayi._();

  // ── Metni normalize et ────────────────────────────────────────────────────
  /// Türkçe'ye duyarlı küçük harf (İ→i, I→ı) + noktalama temizliği. Rakam
  /// içindeki ondalık/binlik ayracı (, .) korunur; kesme işareti (40'a)
  /// kelimeyi böler; "%" → " yüzde ".
  static String normalize(String s) {
    var t = s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
    t = t.replaceAll('%', ' yüzde ').replaceAll('₺', ' lira ');
    t = t.replaceAll(RegExp("['’`´]"), ' ');
    // Rakamla bitişik harfleri ayır: "25tl" → "25 tl", "kdv18" → "kdv 18".
    t = t.replaceAllMapped(RegExp(r'(\d)([a-zçğıöşü])'), (m) => '${m[1]} ${m[2]}');
    t = t.replaceAllMapped(RegExp(r'([a-zçğıöşü])(\d)'), (m) => '${m[1]} ${m[2]}');
    // Rakam dışı ayraçları boşluğa çevir; "1.250,5" gibi sayıları bozma.
    t = t.replaceAllMapped(RegExp(r'[.,;:!?()\[\]{}"/\\-]'), (m) {
      final i = m.start;
      final onceRakam = i > 0 && RegExp(r'\d').hasMatch(t[i - 1]);
      final sonraRakam = i + 1 < t.length && RegExp(r'\d').hasMatch(t[i + 1]);
      if ((m[0] == ',' || m[0] == '.') && onceRakam && sonraRakam) return m[0]!;
      return ' ';
    });
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> kelimele(String s) {
    final n = normalize(s);
    return n.isEmpty ? <String>[] : n.split(' ');
  }

  // ── Sözlükler ─────────────────────────────────────────────────────────────
  static const Map<String, int> _birler = {
    'sıfır': 0, 'sifir': 0,
    'bir': 1, 'iki': 2, 'üç': 3, 'uc': 3, 'dört': 4, 'dort': 4, 'beş': 5,
    'bes': 5, 'altı': 6, 'alti': 6, 'yedi': 7, 'sekiz': 8, 'dokuz': 9,
  };
  static const Map<String, int> _onlar = {
    'on': 10, 'yirmi': 20, 'otuz': 30, 'kırk': 40, 'kirk': 40, 'elli': 50,
    'altmış': 60, 'altmis': 60, 'yetmiş': 70, 'yetmis': 70, 'seksen': 80,
    'doksan': 90,
  };

  static bool _sayiKelimesi(String k) =>
      _birler.containsKey(k) ||
      _onlar.containsKey(k) ||
      k == 'yüz' ||
      k == 'yuz' ||
      k == 'bin' ||
      k == 'milyon';

  /// Tek rakam kelimesi mi (barkod diktesi için): "sekiz" → 8.
  static int? tekHane(String k) {
    final v = _birler[k];
    return (v != null && v <= 9) ? v : null;
  }

  // ── Rakamla yazılmış sayı ─────────────────────────────────────────────────
  static final RegExp _rakamDizisi = RegExp(r'^\d+([.,]\d+)*$');

  /// "1.250,75" → 1250.75, "25,5" → 25.5, "25.50" → 25.5, "1.250" → 1250.
  static double? rakamCoz(String k) {
    if (!_rakamDizisi.hasMatch(k)) return null;
    final nokta = '.'.allMatches(k).length;
    final virgul = ','.allMatches(k).length;
    var t = k;
    if (nokta > 0 && virgul > 0) {
      // Son görülen ayraç ondalıktır.
      final sonNokta = k.lastIndexOf('.');
      final sonVirgul = k.lastIndexOf(',');
      if (sonVirgul > sonNokta) {
        t = k.replaceAll('.', '').replaceAll(',', '.');
      } else {
        t = k.replaceAll(',', '');
      }
    } else if (nokta > 1) {
      t = k.replaceAll('.', ''); // 1.250.000
    } else if (nokta == 1) {
      final kuyruk = k.substring(k.indexOf('.') + 1);
      // "1.250" binlik; "25.50" / "0.5" ondalık.
      t = (kuyruk.length == 3 && k.indexOf('.') >= 1 && k.indexOf('.') <= 3)
          ? k.replaceAll('.', '')
          : k;
    } else if (virgul > 1) {
      t = k.replaceAll(',', '');
    } else if (virgul == 1) {
      t = k.replaceAll(',', '.');
    }
    return double.tryParse(t);
  }

  // ── Ana okuyucu ───────────────────────────────────────────────────────────
  /// [kelimeler] listesinin [bas] indeksinden başlayarak bir sayı okur.
  /// Dönüş: değer + bir sonraki okunmamış kelimenin indeksi; sayı yoksa null.
  static ({double deger, int bitis})? bastanOku(List<String> kelimeler, int bas) {
    var i = bas;
    if (i >= kelimeler.length) return null;

    double? tamKisim;

    final ilk = kelimeler[i];
    final rakam = rakamCoz(ilk);
    if (rakam != null) {
      tamKisim = rakam;
      i++;
      // "3 bin 500", "2 milyon"
      if (rakam == rakam.truncateToDouble()) {
        final carpan = i < kelimeler.length ? kelimeler[i] : '';
        if (carpan == 'bin' || carpan == 'milyon') {
          var toplam = rakam * (carpan == 'bin' ? 1000.0 : 1000000.0);
          i++;
          final devam = i < kelimeler.length ? rakamCoz(kelimeler[i]) : null;
          if (devam != null && devam < (carpan == 'bin' ? 1000 : 1000000)) {
            toplam += devam;
            i++;
          } else {
            final yazi = _yaziyla(kelimeler, i);
            if (yazi != null) {
              toplam += yazi.deger;
              i = yazi.bitis;
            }
          }
          tamKisim = toplam;
        }
      }
    } else {
      final y = _yaziyla(kelimeler, i);
      if (y != null) {
        tamKisim = y.deger;
        i = y.bitis;
      } else if (ilk == 'yarım' || ilk == 'yarim') {
        return (deger: 0.5, bitis: i + 1);
      } else if (ilk == 'çeyrek' || ilk == 'ceyrek') {
        return (deger: 0.25, bitis: i + 1);
      } else if (ilk == 'buçuk' || ilk == 'bucuk') {
        return null; // tek başına anlamsız
      }
    }
    if (tamKisim == null) return null;

    var deger = tamKisim;

    // "buçuk" → +0.5  ("iki buçuk", "25 buçuk")
    if (i < kelimeler.length &&
        (kelimeler[i] == 'buçuk' || kelimeler[i] == 'bucuk')) {
      deger += 0.5;
      i++;
      return (deger: deger, bitis: i);
    }

    // "virgül/nokta" → ondalık basamaklar: "yirmi beş virgül elli"
    if (i < kelimeler.length &&
        (kelimeler[i] == 'virgül' || kelimeler[i] == 'virgul' || kelimeler[i] == 'nokta') &&
        i + 1 < kelimeler.length) {
      final ondalik = _ondalikBasamaklar(kelimeler, i + 1);
      if (ondalik != null) {
        deger += ondalik.deger;
        return (deger: deger, bitis: ondalik.bitis);
      }
    }

    // "lira" / "tl" → ardından kuruş: "yirmi beş lira elli (kuruş)"
    if (i < kelimeler.length && _liraKelimesi(kelimeler[i])) {
      i++;
      final kurus = i < kelimeler.length ? bastanOku(kelimeler, i) : null;
      // "35 lira 50 adet" → 50 kuruş DEĞİL, adet (stok) bilgisidir.
      final sonrakiAdet = kurus != null &&
          kurus.bitis < kelimeler.length &&
          const {'adet', 'tane', 'parça', 'kutu', 'koli', 'paket', 'kilo', 'kg'}
              .contains(kelimeler[kurus.bitis]);
      if (kurus != null &&
          !sonrakiAdet &&
          kurus.deger >= 0 &&
          kurus.deger < 100 &&
          kurus.deger == kurus.deger.truncateToDouble()) {
        var son = kurus.bitis;
        deger += kurus.deger / 100;
        if (son < kelimeler.length && _kurusKelimesi(kelimeler[son])) son++;
        return (deger: deger, bitis: son);
      }
      return (deger: deger, bitis: i);
    }
    return (deger: deger, bitis: i);
  }

  static bool _liraKelimesi(String k) =>
      k == 'lira' || k == 'tl' || k == 'lirası' || k == 'liraya' || k == 'liradan' || k == 'try';
  static bool _kurusKelimesi(String k) => k == 'kuruş' || k == 'kurus' || k == 'kuruşa';

  /// "virgül"den sonraki basamaklar: rakam ("5", "50") ya da yazıyla
  /// ("beş", "elli"). "virgül elli" → 0.50; "virgül beş" → 0.5 (tek hane = onda).
  static ({double deger, int bitis})? _ondalikBasamaklar(List<String> k, int bas) {
    final r = rakamCoz(k[bas]);
    if (r != null && !k[bas].contains(RegExp(r'[.,]'))) {
      final hane = k[bas];
      return (deger: double.parse('0.$hane'), bitis: bas + 1);
    }
    final y = _yaziyla(k, bas);
    if (y != null) {
      final tam = y.deger.toInt();
      final hane = tam.toString();
      // "sıfır beş" gibi baştaki sıfırlar atlandığı için ayrıca bakılır.
      if (k[bas] == 'sıfır' || k[bas] == 'sifir') {
        final sonra = _yaziyla(k, bas + 1);
        if (sonra != null) {
          return (deger: double.parse('0.0${sonra.deger.toInt()}'), bitis: sonra.bitis);
        }
      }
      return (deger: double.parse('0.$hane'), bitis: y.bitis);
    }
    return null;
  }

  /// "yüz elli", "iki bin beş yüz", "on iki" gibi yazıyla sayıyı okur.
  /// Ardışık iki "birler" kelimesi ("bir iki") tek sayı SAYILMAZ.
  static ({double deger, int bitis})? _yaziyla(List<String> k, int bas) {
    var i = bas;
    var toplam = 0;
    var grup = 0;
    var okundu = false;
    var son = 0; // 0 yok, 1 birler, 2 onlar, 3 yüz, 4 bin/milyon
    while (i < k.length) {
      final w = k[i];
      if (_birler.containsKey(w)) {
        if (son == 1) break;
        final v = _birler[w]!;
        if (v == 0 && okundu) break; // "sıfır" ancak başta olur
        grup += v;
        son = 1;
      } else if (_onlar.containsKey(w)) {
        if (son == 1 || son == 2) break;
        grup += _onlar[w]!;
        son = 2;
      } else if (w == 'yüz' || w == 'yuz') {
        if (son == 2 || son == 3) break;
        grup = (grup == 0 ? 1 : grup) * 100;
        son = 3;
      } else if (w == 'bin' || w == 'milyon') {
        if (son == 4) break;
        final carpan = w == 'bin' ? 1000 : 1000000;
        toplam += (grup == 0 ? 1 : grup) * carpan;
        grup = 0;
        son = 4;
      } else {
        break;
      }
      okundu = true;
      i++;
    }
    if (!okundu) return null;
    return (deger: (toplam + grup).toDouble(), bitis: i);
  }

  // ── Kolay arayüzler ───────────────────────────────────────────────────────
  /// Metnin BAŞINDAKİ sayıyı okur (gerisi yok sayılır); yoksa null.
  /// "yüzde", "olarak", "olsun" gibi dolgu kelimelerini atlar.
  static double? ilkSayi(String metin) {
    final k = kelimele(metin);
    for (var i = 0; i < k.length && i < 4; i++) {
      if (_dolgu.contains(k[i])) continue;
      final s = bastanOku(k, i);
      if (s != null) return s.deger;
      break;
    }
    return null;
  }

  static const Set<String> _dolgu = {
    'yüzde', 'olarak', 'olsun', 'olacak', 'yap', 'yapın', 'şu', 'bu', 'tane',
    'adet', 'den', 'dan', 'ye', 'ya', 'e', 'a', 'i', 'ı', 'u', 'ü', 'de', 'da',
    'şeklinde', 'kadar', 'tam', 'için', 'girin', 'gir', 'yaz',
  };

  /// Metindeki TÜM sayıları sırayla döndürür (ör. "25 lira 5 adet" → [25, 5]).
  static List<double> tumSayilar(String metin) {
    final k = kelimele(metin);
    final sonuc = <double>[];
    var i = 0;
    while (i < k.length) {
      final s = bastanOku(k, i);
      if (s != null && s.bitis > i) {
        sonuc.add(s.deger);
        i = s.bitis;
      } else {
        i++;
      }
    }
    return sonuc;
  }

  /// Sesle okunan bir basamak dizisini (barkod, kod, telefon) rakam
  /// string'ine çevirir: ["sekiz","altı","dokuz","869000"] → "869869000".
  /// Rakam olmayan ilk kelimede durur.
  static String basamakDizisi(List<String> kelimeler, int bas) {
    final b = StringBuffer();
    for (var i = bas; i < kelimeler.length; i++) {
      final w = kelimeler[i];
      if (RegExp(r'^\d+$').hasMatch(w)) {
        b.write(w);
      } else if (tekHane(w) != null) {
        b.write(tekHane(w));
      } else if (w == 'sıfır' || w == 'sifir') {
        b.write('0');
      } else if (w == 'sonra' || w == 've' || w == 'tire') {
        continue;
      } else {
        break;
      }
    }
    return b.toString();
  }

  /// Bu kelime sayı parçası mı (yardımcı: segment sınırı için).
  static bool sayiParcasi(String k) => rakamCoz(k) != null || _sayiKelimesi(k);
}
