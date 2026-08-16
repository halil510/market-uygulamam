// lib/cekirdek/utils/sayi_yaziya_cevir.dart
// SRP: Para tutarlarini Turkce yaziya cevirme (fatura "Yalniz ... TL ... Kr" notu
// ve termal fis cikislari icin ortak yardimci).

const _birler = ['', 'Bir', 'İki', 'Üç', 'Dört', 'Beş', 'Altı', 'Yedi', 'Sekiz', 'Dokuz'];
const _onlar  = ['', 'On', 'Yirmi', 'Otuz', 'Kırk', 'Elli', 'Altmış', 'Yetmiş', 'Seksen', 'Doksan'];
const _gruplar = ['', 'Bin', 'Milyon', 'Milyar'];

String _ucBasamakYaziya(int n) {
  if (n == 0) return '';
  final yuzler = n ~/ 100;
  final kalan  = n % 100;
  final onlar  = kalan ~/ 10;
  final birler = kalan % 10;
  var s = '';
  if (yuzler > 0) {
    s += (yuzler == 1 ? '' : '${_birler[yuzler]}') + 'Yüz';
  }
  s += _onlar[onlar];
  s += _birler[birler];
  return s;
}

/// Tam sayıyı Türkçe yazıya çevirir (örn. 5079 → "BeşBinYetmişDokuz")
String sayiyiYaziyaCevir(int sayi) {
  if (sayi == 0) return 'Sıfır';
  if (sayi < 0) return 'Eksi ${sayiyiYaziyaCevir(-sayi)}';

  final gruplar = <int>[];
  var n = sayi;
  while (n > 0) {
    gruplar.add(n % 1000);
    n ~/= 1000;
  }

  var sonuc = '';
  for (var i = gruplar.length - 1; i >= 0; i--) {
    final grup = gruplar[i];
    if (grup == 0) continue;
    if (i == 1 && grup == 1) {
      // "BirBin" değil, sadece "Bin"
      sonuc += 'Bin';
    } else {
      sonuc += _ucBasamakYaziya(grup) + _gruplar[i];
    }
  }
  return sonuc;
}

/// Para tutarını "Yalnız: BeşBinYetmişDokuz TL Yetmiş Kr." formatında yazıya çevirir.
String tutariYaziyaCevir(double tutar) {
  final tl   = tutar.floor();
  final kurus = ((tutar - tl) * 100).round();
  final tlYazi = sayiyiYaziyaCevir(tl);
  if (kurus == 0) return '$tlYazi TL.';
  final kurusYazi = sayiyiYaziyaCevir(kurus);
  return '$tlYazi TL $kurusYazi Kr.';
}
