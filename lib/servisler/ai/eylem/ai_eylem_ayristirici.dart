// lib/servisler/ai/eylem/ai_eylem_ayristirici.dart
//
// Sohbetteki bir cümlenin bir İŞLEM isteği olup olmadığını (ve hangisi
// olduğunu) KURAL TABANLI çözer — saf, veritabanı/ağ bağımsız, test edilebilir.
// İnternet/API anahtarı olmadan da çalışır; kuralların kaçırdığı serbest
// cümleleri Gemini (ai_eylem_yonlendirici.dart) yakalar.
//
// Örnekler:
//   "kolanın satış fiyatını 35 yap"         → fiyat, ayarla 35
//   "ekmeğe yüzde 10 zam yap"               → fiyat, yuzdeArtir 10
//   "süte 50 adet stok ekle"                → stok, artir 50
//   "ekmeğin stoğunu 100 yap"               → stok, ayarla 100
//   "Ali Yılmaz'dan 500 lira tahsilat al"   → tahsilat, 500
//   "kira gideri 15000 ekle"                → gider, 15000, "kira"
//   "ülker gofret ekle alış 6 satış 10"     → ürün ekle (form alanlarıyla)
//   "yeni müşteri Ayşe Demir 0532..."       → cari ekle
//   "X ürününü pasife al"                   → ürün durumu
//
// Soru kalıpları ("nasıl eklerim", "stok kaç") İŞLEM SAYILMAZ — bunlar
// mevcut okuma/rapor akışına gider.
import '../tr_sayi_ayristirici.dart';
import '../urun_ses_ayristirici.dart';
import 'ai_eylem_modeli.dart';

class _Sayi {
  final int bas;
  final int bit; // son kelimenin bir sonraki indeksi
  final double deger;
  const _Sayi(this.bas, this.bit, this.deger);
}

class AiEylemAyristirici {
  AiEylemAyristirici._();

  // ── Fiil kümeleri (TAM eşleşme: "eklenir/eklenebilir" gibi soru kalıpları
  //    işlem sayılmasın) ──────────────────────────────────────────────────
  static const Set<String> _ekle = {
    'ekle', 'ekleyin', 'ekleyelim', 'ekler', 'ekleyiver', 'ekledim', 'oluştur',
    'oluşturun', 'kaydet', 'kaydedin', 'tanımla', 'tanımlayın', 'gir', 'girin',
    'girdim', 'yaz', 'yazın', 'yazar', 'açalım', 'kaydeder',
  };
  static const Set<String> _artir = {
    'artır', 'arttır', 'artırın', 'arttırın', 'artırır', 'yükselt', 'yükseltin',
    'zamla', 'zamlayın', 'artıralım',
  };
  static const Set<String> _azalt = {
    'azalt', 'azaltın', 'düş', 'düşür', 'düşürün', 'çıkar', 'çıkarın', 'eksilt',
    'indir', 'indirin', 'ucuzlat', 'azaltalım',
  };
  static const Set<String> _ayarla = {
    'yap', 'yapın', 'yapar', 'olsun', 'ayarla', 'ayarlayın', 'güncelle',
    'güncelleyin', 'değiştir', 'değiştirin', 'çevir', 'sıfırla', 'belirle', 'say',
    'yapalım', 'olarak',
  };
  static const Set<String> _soruKelimeleri = {
    'nasıl', 'nasil', 'neden', 'niye', 'nedir', 'kaçtır', 'hangi', 'kim', 'nerede',
    'neresinde', 'neresi', 'niçin',
  };
  static const Set<String> _birimler = {
    'adet', 'tane', 'kg', 'kilo', 'kilogram', 'koli', 'paket', 'litre', 'lt',
    'gram', 'gr', 'kutu', 'düzine', 'metre',
  };
  static const Set<String> _paraKelimeleri = {'lira', 'tl', 'kuruş', 'try'};
  static const Set<String> _ekParcaciklar = {
    'dan', 'den', 'tan', 'ten', 'a', 'e', 'ya', 'ye', 'na', 'ne', 'ın', 'in', 'un',
    'ün', 'nın', 'nin', 'nun', 'nün', 'yı', 'yi', 'yu', 'yü', 'ı', 'i', 'u', 'ü',
    'si', 'sı', 'su', 'sü', 'dır', 'dir', 'de', 'da',
  };
  static const Set<String> _genelDolgu = {
    'bir', 'bu', 'şu', 'o', 'için', 'ile', 've', 'ki', 'bana', 'benim', 'lütfen',
    'hadi', 'şimdi', 'ürün', 'ürünün', 'ürünü', 'ürününü', 'ürününün', 'olarak',
    'ayrıca', 'tamam', 'evet', 'sen', 'mısın', 'misin', 'musun', 'müsün', 'yeni',
    'asistan', 'rica', 'edeyim', 'eder', 'et', 'tüm', 'bugün', 'dün', 'son', 'gün',
    'hafta', 'ay', 'yıl', 'şunu', 'bunu', 'sistemde', 'sisteme', 'kayıt', 'kaydı',
    'ya', 'da', 'de', 'diye', 'tam', 'kadar', 'artık', 'bile', 'sadece', 'yalnızca',
  };
  /// Ürün adı çıkarılırken atlanan fiyat/stok sözcük kökleri. Cari/gider adı
  /// çıkarılırken ATLANMAZ ("Atlas Toptan" adındaki "toptan" kalmalı).
  static const List<String> _fiyatStokKokler = [
    'fiyat', 'stok', 'stoğ', 'satış', 'alış', 'toptan', 'zam', 'indirim', 'maliyet',
  ];
  static const List<String> _alanKokler = [
    'tahsil', 'ödeme', 'ödedim', 'gider', 'masraf', 'pasif', 'aktif', 'satıştan',
    'telefon', 'tel',
  ];

  /// Cari rol sözcükleri: "yeni müşteri Ali" içinde rol (atılır) ama "Robot
  /// Müşteri" adında ADIN PARÇASI (korunur) — bu yüzden ayrı tutulur.
  static const List<String> _rolKokler = ['cari', 'müşteri', 'tedarikçi', 'bayi', 'toptancı'];

  /// Ödeme türü sözcükleri komuttur, cari adına karışmaz.
  static bool _odemeSozcugu(String w) =>
      const {'nakit', 'havale', 'eft', 'kredi'}.contains(w) ||
      w.startsWith('banka') ||
      w.startsWith('kart');
  /// Komut fiilleri (işlem türünü belirler, ada karışmaz).
  static const Set<String> _komutFiilleri = {
    'al', 'alın', 'aldım', 'alındı', 'gönder', 'öde', 'ödedim', 'yaptım', 'kaldır',
    'kaldırın', 'et', 'edin',
  };

  // ── Yardımcılar ───────────────────────────────────────────────────────────
  static bool _kok(String w, String kok) =>
      w == kok || (kok.length >= 3 && w.startsWith(kok) && w.length - kok.length <= 6);

  static bool _herhangi(List<String> k, List<String> kokler) =>
      k.any((w) => kokler.any((r) => _kok(w, r)));

  static bool _fiilVar(List<String> k, Set<String> kume) => k.any(kume.contains);

  static const Set<String> _artikelSonrasi = {
    'buçuk', 'lira', 'tl', 'adet', 'tane', 'kg', 'kilo', 'koli', 'paket', 'litre',
    'yüzde', 'gram', 'bin', 'milyon', 'kutu',
  };

  /// Cümledeki tüm sayıları ve konumlarını bulur. Tek başına "bir" ("bir ürün
  /// ekle") sayı SAYILMAZ.
  static List<_Sayi> _sayilar(List<String> k) {
    final sonuc = <_Sayi>[];
    var i = 0;
    while (i < k.length) {
      if (k[i] == 'bir' && !(i + 1 < k.length && _artikelSonrasi.contains(k[i + 1]))) {
        i++;
        continue;
      }
      final s = TrSayi.bastanOku(k, i);
      if (s != null && s.bitis > i) {
        sonuc.add(_Sayi(i, s.bitis, s.deger));
        i = s.bitis;
      } else {
        i++;
      }
    }
    return sonuc;
  }

  /// "yüzde N" kalıbındaki yüzdeyi ve sayısını döndürür.
  static (_Sayi?, double?) _yuzde(List<String> k, List<_Sayi> sayilar) {
    for (var i = 0; i < k.length - 1; i++) {
      if (k[i] == 'yüzde') {
        for (final s in sayilar) {
          if (s.bas == i + 1) return (s, s.deger);
        }
      }
    }
    // "10 yüzde" (nadir)
    for (final s in sayilar) {
      if (s.bit < k.length && k[s.bit] == 'yüzde') return (s, s.deger);
    }
    return (null, null);
  }

  /// Anahtar sözcükler/sayılar/fiiller çıkarıldıktan sonra kalan serbest metin
  /// (ürün/cari/kategori adı). Sayı aralıkları [haricSayilar] ile atlanır.
  static String _kalanMetin(List<String> k, List<_Sayi> haric,
      {Set<String> ekAtlanan = const {},
      int? bas,
      int? bit,
      bool fiyatStokAt = true,
      bool rolAt = true}) {
    final sonuc = <String>[];
    final baslangic = bas ?? 0;
    final son = bit ?? k.length;
    for (var i = baslangic; i < son; i++) {
      if (haric.any((s) => i >= s.bas && i < s.bit)) continue;
      final w = k[i];
      if (_ekle.contains(w) || _artir.contains(w) || _azalt.contains(w) || _ayarla.contains(w)) continue;
      if (_genelDolgu.contains(w) || _birimler.contains(w) || _paraKelimeleri.contains(w)) continue;
      if (_ekParcaciklar.contains(w) || ekAtlanan.contains(w)) continue;
      if (w == 'yüzde') continue;
      if (_komutFiilleri.contains(w)) continue;
      if (_alanKokler.any((r) => _kok(w, r))) continue;
      if (rolAt && _rolKokler.any((r) => _kok(w, r))) continue;
      if (!rolAt && _odemeSozcugu(w)) continue;
      if (fiyatStokAt && _fiyatStokKokler.any((r) => _kok(w, r))) continue;
      if (RegExp(r'^\d+$').hasMatch(w) && haric.isEmpty) continue;
      sonuc.add(w);
    }
    return sonuc.join(' ').trim();
  }

  static String? _birimBul(List<String> k, _Sayi s) {
    if (s.bit < k.length && _birimler.contains(k[s.bit])) return k[s.bit];
    return null;
  }

  static String _odemeTuru(List<String> k) {
    if (k.any((w) => const {'havale', 'eft', 'banka', 'bankadan', 'bankaya'}.contains(w))) {
      return 'Havale';
    }
    if (k.any((w) => w.startsWith('kart') || w == 'kredi')) return 'Kredi Kartı';
    return 'Nakit';
  }

  /// Kurallar bir komutu çözemedi ama cümle İŞLEM gibi görünüyor mu? (Gemini
  /// yedeğine gitmeden önce ucuz kapı: gereksiz API çağrısını önler.)
  /// İşlem fiili + (sayı veya ürün/cari/stok/fiyat/gider sözcüğü) aranır;
  /// soru kalıpları elenir.
  static bool ipucuVar(String soru) {
    final k = TrSayi.kelimele(soru);
    if (k.length < 2) return false;
    if (k.any(_soruKelimeleri.contains)) return false;
    if (const {'mı', 'mi', 'mu', 'mü'}.contains(k.last)) return false;
    final fiil = _fiilVar(k, _ekle) ||
        _fiilVar(k, _artir) ||
        _fiilVar(k, _azalt) ||
        _fiilVar(k, _ayarla) ||
        k.any((w) => _komutFiilleri.contains(w)) ||
        _herhangi(k, ['tahsil', 'pasif', 'aktif', 'zam', 'indirim']);
    if (!fiil) return false;
    return _sayilar(k).isNotEmpty ||
        _herhangi(k, ['ürün', 'cari', 'müşteri', 'stok', 'stoğ', 'fiyat', 'gider', 'masraf', 'tedarikçi']);
  }

  // ── ANA GİRİŞ ─────────────────────────────────────────────────────────────
  /// Bir işlem isteği ise [AiEylemKomutu], değilse null.
  static AiEylemKomutu? ayristir(String soru) {
    final k = TrSayi.kelimele(soru);
    if (k.length < 2) return null;

    // Soru kalıpları işlem değildir.
    if (k.any(_soruKelimeleri.contains)) return null;
    final son = k.last;
    if (const {'mı', 'mi', 'mu', 'mü', 'miyim', 'mıyım', 'muyum', 'müyüm'}.contains(son)) {
      return null;
    }

    final sayilar = _sayilar(k);
    final (yuzdeSayi, yuzdeDeger) = _yuzde(k, sayilar);
    final tutarSayilari =
        sayilar.where((s) => yuzdeSayi == null || s.bas != yuzdeSayi.bas).toList();

    final herhangiFiil = _fiilVar(k, _ekle) ||
        _fiilVar(k, _artir) ||
        _fiilVar(k, _azalt) ||
        _fiilVar(k, _ayarla);

    final tahsilat = _herhangi(k, ['tahsil']);
    final odemeKelimesi = k.any((w) => _kok(w, 'ödeme') || w == 'ödedim' || w == 'ödüyorum');
    final giderKelimesi = _herhangi(k, ['gider', 'masraf']);
    final cariKelimesi = _herhangi(k, ['cari', 'müşteri', 'tedarikçi', 'bayi', 'toptancı']);
    final stokKelimesi = _herhangi(k, ['stok', 'stoğ']);
    final fiyatKelimesi = _herhangi(k, ['fiyat', 'zam', 'indirim', 'ucuzlat']);
    final urunKelimesi = k.any((w) => const {'ürün', 'ürünü', 'ürününü'}.contains(w));

    // 1) TAHSİLAT / ÖDEME (cari) ───────────────────────────────────────────
    if ((tahsilat || odemeKelimesi) && tutarSayilari.isNotEmpty && !giderKelimesi) {
      final ilkTutar = tutarSayilari.first;
      final odemeFiili = k.any((w) =>
          const {'yap', 'yapın', 'yaptım', 'gir', 'girin', 'kaydet', 'ekle', 'yaz', 'ödedim', 'gönder', 'öde'}
              .contains(w));
      final aldi = k.any((w) =>
          const {'al', 'alın', 'aldım', 'alındı', 'yap', 'et', 'edin', 'gir', 'kaydet'}.contains(w));
      final almaFiili =
          k.any((w) => const {'al', 'alın', 'aldım', 'alındı'}.contains(w));
      if (tahsilat ? (aldi || odemeFiili) : (odemeFiili || almaFiili)) {
        var tip = 'Tahsilat';
        if (!tahsilat) {
          // "ödeme aldım/al" → tahsilat; "ödeme yap/ödedim" → ödeme
          final alma = k.any((w) => const {'al', 'alın', 'aldım', 'alındı'}.contains(w));
          tip = alma ? 'Tahsilat' : 'Odeme';
        }
        // Ad: önce tutardan ÖNCEKİ metin, yoksa sonrası
        String adCikar(int? bas, int? bit) {
          final m = _kalanMetin(k, sayilar, bas: bas, bit: bit, fiyatStokAt: false, rolAt: false);
          // "cariden 500 tahsilat al" → yalnız rol sözcüğü var, gerçek ad yok.
          final sadeceRol = m.isNotEmpty &&
              m.split(' ').every((w) => _rolKokler.any((r) => _kok(w, r)));
          return sadeceRol ? '' : m;
        }

        var ad = adCikar(0, ilkTutar.bas);
        if (ad.isEmpty) ad = adCikar(ilkTutar.bit, null);
        if (ad.isNotEmpty) {
          return AiEylemKomutu(
            tur: AiEylemTuru.tahsilatOdeme,
            islemTipi: tip,
            cariMetni: ad,
            deger: ilkTutar.deger,
            odemeTuru: _odemeTuru(k),
          );
        }
      }
    }

    // 2) CARİ EKLE ─────────────────────────────────────────────────────────
    if (cariKelimesi && !tahsilat && !giderKelimesi) {
      const cariFiili = {'ekle', 'ekleyin', 'ekleyelim', 'oluştur', 'oluşturun', 'kaydet', 'kaydedin', 'tanımla'};
      final yeniMusteri = k.isNotEmpty && k.first == 'yeni';
      if (_fiilVar(k, cariFiili) || yeniMusteri) {
        // telefon: 10-11 haneli rakam dizisi (sayılar arasından ayıklanır)
        String? tel;
        final basamaklar = <int>{};
        for (var i = 0; i < k.length; i++) {
          final d = TrSayi.basamakDizisi(k, i);
          if (d.length >= 10 && d.length <= 11) {
            tel = d;
            basamaklar.addAll([for (var j = i; j < k.length; j++) j]);
            break;
          }
        }
        final kelimeler = [for (var i = 0; i < k.length; i++) if (!basamaklar.contains(i)) k[i]];
        // Yalnız İLK rol sözcüğü ("müşteri/tedarikçi/cari…") komuttur; adın
        // içindekiler ("Test Cari", "Robot Müşteri") korunur.
        final rolIdx = kelimeler.indexWhere((w) => _rolKokler.any((r) => _kok(w, r)));
        if (rolIdx != -1) kelimeler.removeAt(rolIdx);
        final ad = _kalanMetin(kelimeler, const [],
            ekAtlanan: {'yeni'}, fiyatStokAt: false, rolAt: false);
        if (ad.isNotEmpty) {
          final tedarikci = k.any((w) => _kok(w, 'tedarikçi') || _kok(w, 'toptancı'));
          return AiEylemKomutu(
            tur: AiEylemTuru.cariEkle,
            metin: UrunSesAyristirici.basHarfBuyut(ad),
            telefon: tel,
            islemTipi: tedarikci ? 'Tedarikçi' : 'Müşteri', // cari tipi
          );
        }
      }
    }

    // 3) GİDER EKLE ────────────────────────────────────────────────────────
    if (giderKelimesi && tutarSayilari.isNotEmpty &&
        (_fiilVar(k, _ekle) || _fiilVar(k, _ayarla) || k.contains('ödedim') || k.contains('yaptım'))) {
      final tutar = tutarSayilari.first;
      final kategori = _kalanMetin(k, sayilar, fiyatStokAt: false);
      return AiEylemKomutu(
        tur: AiEylemTuru.giderEkle,
        deger: tutar.deger,
        metin: kategori.isEmpty ? null : kategori,
        odemeTuru: _odemeTuru(k),
      );
    }

    // 4) ÜRÜN EKLE (açık: "ürün" sözcüğü + ekle, ya da fiyat alanı + ekle) ─
    final ekleFiili = _fiilVar(k, _ekle) && !_fiilVar(k, _ayarla.difference({'olarak'})) ;
    if (ekleFiili && !tahsilat && !giderKelimesi) {
      final r = UrunSesAyristirici.ayristir(soru);
      final fiyatAlani = r.alanlar.containsKey('satisFiyati') || r.alanlar.containsKey('alisFiyat');
      final stokEkleme = stokKelimesi && !fiyatAlani && !urunKelimesi;
      final adToken = r.alanlar['urunAdi'] is String
          ? TrSayi.kelimele(r.alanlar['urunAdi'] as String)
          : const <String>[];
      // "ürün ekle ekranını aç" gibi GEZİNME cümleleri ürün adı sayılmaz.
      final gezinme = adToken.any((w) =>
          const {'aç', 'git', 'göster', 'ac', 'goster'}.contains(w) ||
          ['ekran', 'sayfa', 'menü', 'liste'].any((r) => w.startsWith(r)));
      if (!gezinme && !stokEkleme &&
          (urunKelimesi || fiyatAlani || r.alanlar.containsKey('barkod')) &&
          r.alanlar['urunAdi'] is String) {
        return AiEylemKomutu(
          tur: AiEylemTuru.urunEkle,
          urunAlanlari: r.alanlar,
          urunMetni: r.alanlar['urunAdi'] as String,
          uyarilar: r.anlasilmayan,
        );
      }
    }

    // 5) FİYAT GÜNCELLE ────────────────────────────────────────────────────
    if (fiyatKelimesi && tutarSayilari.isNotEmpty || (fiyatKelimesi && yuzdeDeger != null)) {
      if (herhangiFiil || _herhangi(k, ['zam', 'indirim'])) {
        final alis = _herhangi(k, ['alış', 'maliyet']);
        final toptan = _herhangi(k, ['toptan']);
        final alan = alis ? 'alisFiyat' : (toptan ? 'toptanFiyat' : 'satisFiyati');
        final zam = _herhangi(k, ['zam', 'zamla']);
        final indirim = _herhangi(k, ['indirim', 'ucuzlat']);
        final art = zam || _fiilVar(k, _artir);
        final azl = indirim || (_fiilVar(k, _azalt) && !zam);

        String? islem;
        double? deger;
        if (yuzdeDeger != null) {
          if (art && !azl) {
            islem = 'yuzdeArtir';
          } else if (azl && !art) {
            islem = 'yuzdeAzalt';
          } else if (art && azl) {
            // "zam" + "düşür" gibi çelişki → zam/indirim sözcüğü belirleyici
            islem = zam ? 'yuzdeArtir' : 'yuzdeAzalt';
          }
          deger = yuzdeDeger;
        } else if (tutarSayilari.isNotEmpty) {
          deger = tutarSayilari.first.deger;
          if (zam) {
            islem = 'artir';
          } else if (indirim && !_fiilVar(k, _ayarla)) {
            islem = 'azalt';
          } else if (_fiilVar(k, _artir) && !_fiilVar(k, _ayarla)) {
            islem = 'artir';
          } else if (_fiilVar(k, _azalt) && !_fiilVar(k, _ayarla)) {
            // "5 lira düşür" → azalt; "40'a çıkar" aşağıda ayarla'ya düşer
            islem = 'azalt';
          } else {
            islem = 'ayarla';
          }
          // "40'a çıkar/indir" → belirli fiyata ayarlama (artış miktarı değil):
          // son sayıdan sonra yönelme eki ('a/e') varsa ayarla.
          final s0 = tutarSayilari.first;
          if (s0.bit < k.length && (k[s0.bit] == 'a' || k[s0.bit] == 'e' || k[s0.bit] == 'ya' || k[s0.bit] == 'ye') &&
              !zam && !indirim) {
            islem = 'ayarla';
          }
        }
        if (islem != null && deger != null) {
          final urun = _kalanMetin(k, sayilar);
          return AiEylemKomutu(
            tur: AiEylemTuru.fiyatGuncelle,
            urunMetni: urun.isEmpty ? null : urun,
            fiyatAlani: alan,
            islem: islem,
            deger: deger,
            uyarilar: stokKelimesi ? ['Stok için ayrıca isteyin: bir seferde tek işlem yapabilirim.'] : const [],
          );
        }
      }
    }

    // 6) STOK DÜZENLE ──────────────────────────────────────────────────────
    final birimliSayi = tutarSayilari.where((s) => _birimBul(k, s) != null).toList();
    final stokTetik = stokKelimesi || (birimliSayi.isNotEmpty && (_fiilVar(k, _ekle) || _fiilVar(k, _azalt) || _fiilVar(k, _artir)));
    if (stokTetik && tutarSayilari.isNotEmpty && herhangiFiil && !fiyatKelimesi && !giderKelimesi && !tahsilat) {
      final sayi = birimliSayi.isNotEmpty ? birimliSayi.first : tutarSayilari.first;
      String islem;
      var deger = sayi.deger;
      if (k.contains('sıfırla')) {
        islem = 'ayarla';
        deger = 0;
      } else if (_fiilVar(k, _azalt) && !_fiilVar(k, _artir) && !_fiilVar(k, _ekle)) {
        islem = 'azalt';
      } else if (_fiilVar(k, _artir) || _fiilVar(k, _ekle)) {
        islem = 'artir';
      } else {
        islem = 'ayarla';
      }
      final urun = _kalanMetin(k, sayilar);
      return AiEylemKomutu(
        tur: AiEylemTuru.stokDuzenle,
        urunMetni: urun.isEmpty ? null : urun,
        islem: islem,
        deger: deger,
        birim: _birimBul(k, sayi),
      );
    }
    if (stokKelimesi && k.contains('sıfırla')) {
      final urun = _kalanMetin(k, sayilar);
      return AiEylemKomutu(
        tur: AiEylemTuru.stokDuzenle,
        urunMetni: urun.isEmpty ? null : urun,
        islem: 'ayarla',
        deger: 0,
      );
    }

    // 7) ÜRÜN DURUMU (pasife al / aktife al / satıştan kaldır) ─────────────
    final pasifIstegi = _herhangi(k, ['pasif']) ||
        (k.contains('satıştan') && k.any((w) => w.startsWith('kald')));
    final aktifIstegi = k.any((w) => w == 'aktife' || w == 'aktif') && !pasifIstegi;
    if ((pasifIstegi || aktifIstegi) && sayilar.isEmpty &&
        (k.any((w) => const {'al', 'alın', 'yap', 'yapın', 'çevir', 'et', 'ayarla', 'kaldır', 'kaldırın'}.contains(w)) ||
            k.any((w) => w.startsWith('kald')))) {
      final urun = _kalanMetin(k, sayilar);
      if (urun.isNotEmpty) {
        return AiEylemKomutu(
          tur: AiEylemTuru.urunDurum,
          urunMetni: urun,
          aktif: !pasifIstegi,
        );
      }
    }

    return null;
  }
}
