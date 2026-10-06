// lib/servisler/ai/urun_ses_ayristirici.dart
//
// Ürün Ekle/Düzenle formundaki sesli (veya yazılı) komutu AYRIŞTIRIR — saf
// ve test edilebilir. Tek cümlede istenen kadar alan söylenebilir:
//
//   "ülker çikolatalı gofret alış fiyatı yirmi beş buçuk satış otuz beş
//    kdv yüzde on stok yüz minimum stok on koli içi on iki raf a üç kaydet"
//
// Tanınanlar (hepsi birlikte/ayrı, sıra serbest, eş anlamlı ifadeler):
//   ürün adı • barkod (rakam veya yazıyla) • ürün kodu • alış / satış /
//   toptan fiyatı • KDV dahil alış • alış KDV / satış KDV / genel KDV •
//   stok / minimum / maksimum stok • koli içi miktarı / koli birimi •
//   birim (kilo, litre…) • ana grup / alt grup • marka / üretici / model •
//   raf no • indirim oranı • renk / beden / ağırlık • muhasebe kodu •
//   alan1-4 • aktif/pasif • lot/seri takibi
//   Eylemler: kaydet • barkod üret • grup öner • marka öner
//
// Hiç sayı uydurmaz: anlaşılamayan parça [UrunSesSonuc.anlasilmayan]'a
// konur, çağıran taraf (form) kullanıcıya gösterir.
import 'tr_sayi_ayristirici.dart';

enum _Tur { para, sayi, oran, metin, buyukMetin, barkod, birim, kod, rafKodu, ad }

class _Alan {
  final List<String> anahtarlar; // birden çok form alanını doldurabilir (genel KDV)
  final _Tur tur;
  final List<String> ifadeler; // boşlukla ayrılmış kelime dizileri
  const _Alan(this.anahtarlar, this.tur, this.ifadeler);
}

/// Ayrıştırma sonucu: alan → değer (double | String | bool), eylemler,
/// anlaşılamayan parçalar.
class UrunSesSonuc {
  final Map<String, Object> alanlar;
  final Set<String> eylemler;
  final List<String> anlasilmayan;
  const UrunSesSonuc(this.alanlar, this.eylemler, this.anlasilmayan);

  bool get bos => alanlar.isEmpty && eylemler.isEmpty;

  static const Map<String, String> etiketler = {
    'urunAdi': 'Ürün adı', 'barkod': 'Barkod', 'kod': 'Ürün kodu',
    'alisFiyat': 'Alış fiyatı', 'alisFiyatKdvDahil': 'Alış (KDV dahil)',
    'satisFiyati': 'Satış fiyatı', 'toptanFiyat': 'Toptan fiyat',
    'alisKdvOran': 'Alış KDV', 'kdvOran': 'Satış KDV',
    'stok': 'Stok', 'minimumStok': 'Minimum stok', 'maksimumStok': 'Maksimum stok',
    'koliIciMiktar': 'Koli içi miktar', 'koliBirimAdi': 'Koli birimi',
    'birim': 'Birim', 'satisBirimiTipi': 'Satış tipi',
    'anaGrup': 'Ana grup', 'altGrup': 'Alt grup', 'marka': 'Marka',
    'uretici': 'Üretici', 'model': 'Model', 'rafNo': 'Raf no',
    'indirimOrani': 'İndirim %', 'renk': 'Renk', 'beden': 'Beden',
    'agirlik': 'Ağırlık', 'muhasebeKodu': 'Muhasebe kodu',
    'alan1': 'Alan 1', 'alan2': 'Alan 2', 'alan3': 'Alan 3', 'alan4': 'Alan 4',
    'aktif': 'Aktif', 'lotTakibi': 'Lot takibi', 'seriTakibi': 'Seri takibi',
  };

  /// Kullanıcıya gösterilecek kısa özet satırları.
  List<String> ozetSatirlari() => [
        for (final e in alanlar.entries)
          '${etiketler[e.key] ?? e.key}: ${_degerMetni(e.value)}',
      ];

  static String _degerMetni(Object v) {
    if (v is bool) return v ? 'evet' : 'hayır';
    if (v is double) {
      return v == v.truncateToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(2).replaceAll('.', ',');
    }
    return v.toString();
  }
}

class UrunSesAyristirici {
  UrunSesAyristirici._();

  /// Geçerli KDV oranları (form dropdown'ıyla aynı).
  static const List<double> kdvOranlari = [0, 1, 8, 10, 18, 20];

  // ── Alan tablosu ──────────────────────────────────────────────────────────
  static const List<_Alan> _alanlar = [
    _Alan(['alisFiyatKdvDahil'], _Tur.para, [
      'kdv dahil alış fiyatı', 'kdv dahil alış fiyat', 'kdv dahil alış', 'kdvli alış',
      'alış fiyatı kdv dahil', 'alış fiyat kdv dahil', 'alış kdv dahil', 'alış kdvli',
      'alış fiyatı kdvli',
    ]),
    _Alan(['alisFiyat'], _Tur.para, [
      'alış fiyatı', 'alış fiyat', 'alış', 'maliyet fiyatı', 'maliyeti', 'maliyet',
      'geliş fiyatı', 'geliş', 'alım fiyatı', 'alım', 'kdv hariç alış', 'toptan alış',
    ]),
    _Alan(['alisKdvOran'], _Tur.oran, [
      'alış kdv oranı', 'alış kdv', 'alış kdvsi', 'alış vergisi',
    ]),
    _Alan(['kdvOran'], _Tur.oran, [
      'satış kdv oranı', 'satış kdv', 'satış kdvsi', 'satış vergisi',
    ]),
    _Alan(['alisKdvOran', 'kdvOran'], _Tur.oran, [
      'kdv oranı', 'kdv oran', 'kdv', 'vergi oranı', 'vergi',
    ]),
    _Alan(['toptanFiyat'], _Tur.para, [
      'toptan satış fiyatı', 'toptan fiyatı', 'toptan fiyat', 'toptan',
      'bayi fiyatı', 'bayi fiyat', 'bayi',
    ]),
    _Alan(['satisFiyati'], _Tur.para, [
      'satış fiyatı', 'satış fiyat', 'satiş fiyat', 'satış', 'etiket fiyatı', 'etiket',
      'raf fiyatı', 'perakende fiyatı', 'perakende', 'satılacak fiyat', 'fiyatı', 'fiyat',
    ]),
    _Alan(['minimumStok'], _Tur.sayi, [
      'minimum stok', 'min stok', 'en az stok', 'kritik stok', 'asgari stok',
      'alarm stok', 'minimum', 'min', 'kritik seviye', 'en az',
    ]),
    _Alan(['maksimumStok'], _Tur.sayi, [
      'maksimum stok', 'max stok', 'en fazla stok', 'azami stok', 'maksimum', 'max',
      'en fazla',
    ]),
    _Alan(['stok'], _Tur.sayi, [
      'başlangıç stok', 'açılış stok', 'stok miktarı', 'stok', 'stoğu', 'stoğa', 'stokta',
      'mevcut', 'mevcudu', 'miktar',
    ]),
    _Alan(['koliBirimAdi'], _Tur.birim, ['koli birimi', 'koli birim']),
    _Alan(['koliIciMiktar'], _Tur.sayi, [
      'koli içi adet', 'koli içi miktar', 'koli içi', 'koli içinde', 'kolide',
      'koli adedi', 'koli miktarı', 'koli', 'kolisi',
    ]),
    _Alan(['birim'], _Tur.birim, ['ölçü birimi', 'birimi', 'birim']),
    _Alan(['altGrup'], _Tur.metin, [
      'alt grup', 'alt grubu', 'alt kategori', 'alt kategorisi', 'alt bölüm',
    ]),
    _Alan(['anaGrup'], _Tur.metin, [
      'ana grup', 'ana grubu', 'ana kategori', 'kategori', 'kategorisi', 'grup',
      'grubu', 'reyon', 'bölüm',
    ]),
    _Alan(['marka'], _Tur.metin, ['markası', 'marka', 'markalı']),
    _Alan(['uretici'], _Tur.metin, ['üreticisi', 'üretici', 'imalatçı', 'firma']),
    _Alan(['model'], _Tur.buyukMetin, ['model']),
    _Alan(['alan1'], _Tur.metin, ['alan 1', 'alan bir']),
    _Alan(['alan2'], _Tur.metin, ['alan 2', 'alan iki']),
    _Alan(['alan3'], _Tur.metin, ['alan 3', 'alan üç']),
    _Alan(['alan4'], _Tur.metin, ['alan 4', 'alan dört']),
    _Alan(['rafNo'], _Tur.rafKodu, [
      'raf numarası', 'raf no', 'raf yeri', 'reyon yeri', 'raf', 'rafı',
    ]),
    _Alan(['indirimOrani'], _Tur.oran, [
      'indirim oranı', 'indirim yüzdesi', 'indirim', 'iskonto oranı', 'iskonto',
    ]),
    _Alan(['renk'], _Tur.metin, ['rengi', 'renk']),
    _Alan(['beden'], _Tur.buyukMetin, ['bedeni', 'beden']),
    _Alan(['agirlik'], _Tur.sayi, ['ağırlığı', 'ağırlık', 'gramaj']),
    _Alan(['muhasebeKodu'], _Tur.kod, ['muhasebe kodu', 'muhasebe']),
    _Alan(['kod'], _Tur.kod, ['ürün kodu', 'stok kodu', 'kodu', 'kod']),
    _Alan(['barkod'], _Tur.barkod, [
      'barkod numarası', 'barkod numara', 'barkod no', 'barkodu', 'barkod', 'barkot',
    ]),
    _Alan(['urunAdi'], _Tur.ad, [
      'ürünün adı', 'ürün adı', 'ürünün ismi', 'ürün ismi', 'ürün adi', 'adı', 'ismi',
      'isim',
    ]),
  ];

  static const Set<String> _dolgu = {
    'yüzde', 'olarak', 'olsun', 'olacak', 'yap', 'yapın', 'yaz', 'girin', 'gir', 'şu',
    'bu', 'si', 'sı', 'su', 'sü', 'şeklinde', 'tam', 'için', 'de', 'da', 'den', 'dan',
    've', 'ile', 'kadar', 'ye', 'ya', 'e', 'a', 'seç', 'seçin', 'ayarla', 'koy',
  };

  /// Metin değerlerinin (ad, marka, raf, kod…) başından/sonundan kırpılacak
  /// sözler. Ek artıkları (a, e, su, si…) BURADA YOK: "raf a 3" ve "su" ürün
  /// adı gibi gerçek değerleri yutmasın.
  static const Set<String> _metinDolgu = {
    'olarak', 'olsun', 'olacak', 'yap', 'yapın', 'yaz', 'girin', 'gir', 'seç', 'seçin',
    'ayarla', 'koy', 'şeklinde',
  };

  static const Set<String> _bastakiDolgu = {
    'yeni', 'ürün', 'urun', 'ürünü', 'ekle', 'ekleyelim', 'eklemek', 'ekleyeceğim',
    'ekleyecem', 'istiyorum', 'bir', 'şu', 'diye', 'kayıt', 'kaydı', 'aç', 'oluştur',
    'girelim', 'girmek', 'lütfen', 'hadi', 'şimdi', 'tamam', 'evet', 'asistan',
    'ürünün', 'bilgileri', 'bilgilerini', 'şunu', 'bunu',
  };

  static const Set<String> _sondakiDolgu = {
    'ekle', 'ekleyelim', 'olarak', 'diye', 'için', 'ürünü', 'ürün', 'olsun', 'olacak',
    'yap', 've', 'bir', 'de', 'da', 'ile', 'lütfen', 'kaydet', 'şu', 'şeklinde',
  };

  static const Map<String, String> _birimSozlugu = {
    'adet': 'ADET', 'tane': 'ADET', 'ad': 'ADET', 'parça': 'ADET',
    'kilo': 'KG', 'kg': 'KG', 'kilogram': 'KG', 'kilogramı': 'KG',
    'gram': 'GR', 'gr': 'GR', 'gramı': 'GR',
    'litre': 'LİTRE', 'lt': 'LİTRE', 'l': 'LİTRE',
    'mililitre': 'ML', 'ml': 'ML',
    'paket': 'PAKET', 'pk': 'PAKET', 'pakette': 'PAKET',
    'koli': 'KOLİ', 'kolide': 'KOLİ',
    'metre': 'METRE', 'mt': 'METRE', 'm': 'METRE',
    'kutu': 'KUTU', 'düzine': 'DÜZİNE', 'palet': 'PALET', 'kasa': 'KASA',
  };

  static const Map<String, String> _koliBirimleri = {
    'koli': 'Koli', 'paket': 'Paket', 'palet': 'Palet', 'kasa': 'Kasa', 'kutu': 'Koli',
  };

  // ── Eşleştirme ────────────────────────────────────────────────────────────
  static bool _kelimeEsles(String kelime, String ifade, {required bool son}) {
    if (kelime == ifade) return true;
    if (!son || ifade.length < 4) return false;
    return kelime.startsWith(ifade) && kelime.length - ifade.length <= 3;
  }

  static ({_Alan alan, int uzunluk})? _isaretciBul(List<String> k, int i) {
    ({_Alan alan, int uzunluk})? enIyi;
    for (final alan in _alanlar) {
      for (final ifade in alan.ifadeler) {
        final p = ifade.split(' ');
        if (i + p.length > k.length) continue;
        var tamam = true;
        for (var j = 0; j < p.length; j++) {
          if (!_kelimeEsles(k[i + j], p[j], son: j == p.length - 1)) {
            tamam = false;
            break;
          }
        }
        if (tamam && (enIyi == null || p.length > enIyi.uzunluk)) {
          enIyi = (alan: alan, uzunluk: p.length);
        }
      }
    }
    return enIyi;
  }

  // ── Yardımcılar ───────────────────────────────────────────────────────────
  static String basHarfBuyut(String s) {
    return s
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) {
      if (RegExp(r'^\d').hasMatch(w)) return w;
      final ilk = w[0] == 'i' ? 'İ' : (w[0] == 'ı' ? 'I' : w[0].toUpperCase());
      return ilk + w.substring(1);
    }).join(' ');
  }

  static String _buyuk(String s) =>
      s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  static List<String> _kirp(List<String> k, Set<String> bas, Set<String> son) {
    var b = 0;
    var e = k.length;
    while (b < e && bas.contains(k[b])) {
      b++;
    }
    while (e > b && son.contains(k[e - 1])) {
      e--;
    }
    return k.sublist(b, e);
  }

  /// Segmentin başındaki sayıyı okur (dolgu kelimeleri atlanır). Kalan
  /// kelimeleri de döndürür ("35 100 adet" → 35, kalan [100, adet]).
  static ({double? deger, List<String> kalan}) _sayiOku(List<String> seg) {
    for (var i = 0; i < seg.length && i < 3; i++) {
      if (_dolgu.contains(seg[i])) continue;
      final s = TrSayi.bastanOku(seg, i);
      if (s != null) return (deger: s.deger, kalan: seg.sublist(s.bitis));
      break;
    }
    return (deger: null, kalan: seg);
  }

  /// "100 adet" / "yüz tane" kalıbını bulur → stok.
  static double? _adetKalibi(List<String> k) {
    for (var i = 0; i < k.length - 1; i++) {
      if (k[i + 1] == 'adet' || k[i + 1] == 'tane' || k[i + 1] == 'parça') {
        // Sayı birkaç kelime olabilir: geriye doğru en uzun okunabilir sayıyı bul.
        for (var b = (i - 3 < 0 ? 0 : i - 3); b <= i; b++) {
          final s = TrSayi.bastanOku(k, b);
          if (s != null && s.bitis == i + 1) return s.deger;
        }
      }
    }
    return null;
  }

  static final RegExp _kaydetRe =
      RegExp(r'\b(kaydet\w*|kayıt et\w*|kayıt edin|kaydı tamamla)\b');
  static final RegExp _barkodUretRe = RegExp(
      r'\b(barkod\w*\s+(üret\w*|oluştur\w*|otomatik)|otomatik barkod\w*|barkodu sen üret\w*|barkod üret\w*)\b');
  static final RegExp _grupOnerRe = RegExp(
      r'\b(grup\w*|kategori\w*)\s+(öner\w*|bul\w*|belirle\w*|tahmin et\w*)\b');
  static final RegExp _markaOnerRe =
      RegExp(r'\b(marka\w*|alan\s*1)\s+(öner\w*|bul\w*|belirle\w*|tahmin et\w*)\b');

  // ── ANA ───────────────────────────────────────────────────────────────────
  static UrunSesSonuc ayristir(String metinHam) {
    final alanlar = <String, Object>{};
    final eylemler = <String>{};
    final anlasilmayan = <String>[];

    var metin = TrSayi.normalize(metinHam);
    if (metin.isEmpty) return UrunSesSonuc(alanlar, eylemler, anlasilmayan);

    // 1) Eylemler (alan ayrıştırmasını bozmasın diye metinden çıkarılır)
    if (_barkodUretRe.hasMatch(metin)) {
      eylemler.add('barkodUret');
      metin = metin.replaceAll(_barkodUretRe, ' ');
    }
    if (_grupOnerRe.hasMatch(metin)) {
      eylemler.add('grupOner');
      metin = metin.replaceAll(_grupOnerRe, ' ');
    }
    if (_markaOnerRe.hasMatch(metin)) {
      eylemler.add('markaOner');
      metin = metin.replaceAll(_markaOnerRe, ' ');
    }
    if (_kaydetRe.hasMatch(metin)) {
      eylemler.add('kaydet');
      metin = metin.replaceAll(_kaydetRe, ' ');
    }
    metin = metin.replaceAll(RegExp(r'\s+'), ' ').trim();

    var k = metin.isEmpty ? <String>[] : metin.split(' ');

    // 2) Doğrudan kelime ipuçları (değersiz): birim tipi, durum, takip.
    // Kullanılan kelimeler metinden SİLİNİR — ürün adına/değere karışmasın.
    final sil = <int>{};
    void isaretle(int bas, int adet) {
      for (var j = bas; j < bas + adet && j < k.length; j++) {
        sil.add(j);
      }
    }

    const satilir = {
      'satılır', 'satılıyor', 'satılan', 'satılacak', 'satılsın', 'satıyorum', 'satacağım',
    };
    const durumSozleri = {
      'yok', 'var', 'açık', 'kapalı', 'kapat', 'aç', 'olsun', 'olmasın', 'istemiyorum', 'hayır',
    };
    bool takipAcik(int i) {
      for (var j = i + 1; j < k.length && j <= i + 3; j++) {
        if (const {'yok', 'kapalı', 'kapat', 'olmasın', 'istemiyorum', 'hayır'}.contains(k[j])) {
          return false;
        }
      }
      return true;
    }

    for (var i = 0; i < k.length; i++) {
      final w = k[i];
      final bir = i + 1 < k.length ? k[i + 1] : '';
      final iki = i + 2 < k.length ? k[i + 2] : '';
      if (w == 'pasif' || (w == 'pasife' && bir == 'al')) {
        alanlar['aktif'] = false;
        isaretle(i, w == 'pasife' ? 2 : 1);
      } else if (w == 'aktif' || (w == 'aktife' && bir == 'al')) {
        if (!alanlar.containsKey('aktif')) alanlar['aktif'] = true;
        isaretle(i, w == 'aktife' ? 2 : 1);
      } else if ((w == 'lot' || w == 'seri') && (bir.startsWith('takip') || bir.startsWith('takib') || bir == 'no')) {
        final anahtar = w == 'lot' ? 'lotTakibi' : 'seriTakibi';
        alanlar[anahtar] = takipAcik(i);
        final uz = (bir == 'no' && (iki.startsWith('takip') || iki.startsWith('takib'))) ? 3 : 2;
        isaretle(i, uz);
        final son = i + uz;
        if (son < k.length && durumSozleri.contains(k[son])) sil.add(son);
      } else if (w == 'tartılı' || w == 'terazili' || w == 'kiloyla' || w == 'kiloluk' ||
          (w == 'kilo' && (bir == 'ile' || bir == 'ila'))) {
        alanlar['birim'] = 'KG';
        alanlar['satisBirimiTipi'] = 'kg';
        final uz = w == 'kilo' ? 2 : 1;
        isaretle(i, uz);
        if (i + uz < k.length && satilir.contains(k[i + uz])) sil.add(i + uz);
      }
    }
    if (sil.isNotEmpty) {
      k = [for (var j = 0; j < k.length; j++) if (!sil.contains(j)) k[j]];
    }

    // 3) İşaretçileri bul
    final isaretler = <({int idx, int uzunluk, _Alan alan})>[];
    var i = 0;
    while (i < k.length) {
      final m = _isaretciBul(k, i);
      if (m != null) {
        isaretler.add((idx: i, uzunluk: m.uzunluk, alan: m.alan));
        i += m.uzunluk;
      } else {
        i++;
      }
    }

    // 4) Baştaki serbest metin = ürün adı adayı
    var ilkIdx = isaretler.isEmpty ? k.length : isaretler.first.idx;
    // "yüzde on kdv ..." — ilk işaretçi değersizse ve öncesi "yüzde N" ise,
    // bu parça ürün adına katılmaz (segment aşamasında değer olarak okunur).
    if (isaretler.isNotEmpty && isaretler.first.alan.tur == _Tur.oran) {
      final m0 = isaretler.first;
      final sonrakiIdx = isaretler.length > 1 ? isaretler[1].idx : k.length;
      if (sonrakiIdx == m0.idx + m0.uzunluk) {
        for (var b = ilkIdx - 1; b >= 0 && b >= ilkIdx - 3; b--) {
          if (k[b] == 'yüzde') {
            ilkIdx = b;
            break;
          }
        }
      }
    }
    var lead = k.sublist(0, ilkIdx);

    // "X adında/adlı/isimli ürün" → X
    const adMarkerleri = {'adında', 'adinda', 'isminde', 'adlı', 'adli', 'isimli'};
    final adIdx = lead.indexWhere(adMarkerleri.contains);
    if (adIdx != -1) lead = lead.sublist(0, adIdx);

    // "N adet" → stok
    final leadAdet = _adetKalibi(lead);
    if (leadAdet != null && !alanlar.containsKey('stok')) {
      alanlar['stok'] = leadAdet;
      // Adedi ve sayıyı addan çıkar
      final a = lead.lastIndexOf(lead.firstWhere(
          (w) => w == 'adet' || w == 'tane' || w == 'parça',
          orElse: () => ''));
      if (a != -1) {
        var b = a;
        while (b > 0 && TrSayi.sayiParcasi(lead[b - 1])) {
          b--;
        }
        lead = [...lead.sublist(0, b), ...lead.sublist(a + 1)];
      }
    }
    lead = _kirp(lead, _bastakiDolgu, _sondakiDolgu);
    if (lead.isNotEmpty && !alanlar.containsKey('urunAdi')) {
      final ad = lead.join(' ');
      // Sadece sayı/dolgudan ibaretse ad sayma
      if (ad.replaceAll(RegExp(r'[\d\s]'), '').isNotEmpty) {
        alanlar['urunAdi'] = basHarfBuyut(ad);
      }
    }

    // 5) Segmentleri işle
    for (var s = 0; s < isaretler.length; s++) {
      final m = isaretler[s];
      final baslangic = m.idx + m.uzunluk;
      final bitis = s + 1 < isaretler.length ? isaretler[s + 1].idx : k.length;
      var seg = k.sublist(baslangic, bitis);

      // "yüzde on kdv" — sayı işaretçiden ÖNCE geldiyse
      if (seg.isEmpty && (m.alan.tur == _Tur.oran) && m.idx >= 2) {
        final onceki = k.sublist(m.idx >= 3 ? m.idx - 3 : 0, m.idx);
        final yIdx = onceki.lastIndexOf('yüzde');
        if (yIdx != -1) {
          final sn = _sayiOku(onceki.sublist(yIdx + 1));
          if (sn.deger != null) seg = [sn.deger!.toString()];
        }
      }

      final etiket = UrunSesSonuc.etiketler[m.alan.anahtarlar.first] ?? m.alan.anahtarlar.first;
      switch (m.alan.tur) {
        case _Tur.para:
        case _Tur.sayi:
        case _Tur.oran:
          final r = _sayiOku(seg);
          if (r.deger == null) {
            anlasilmayan.add('$etiket için sayı anlaşılamadı');
            break;
          }
          final v = r.deger!;
          if (v < 0) {
            anlasilmayan.add('$etiket negatif olamaz');
            break;
          }
          if (m.alan.anahtarlar.contains('alisKdvOran') || m.alan.anahtarlar.contains('kdvOran')) {
            if (!kdvOranlari.contains(v)) {
              anlasilmayan.add('KDV %${v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 1)} geçersiz '
                  '(geçerli: ${kdvOranlari.map((e) => e.toStringAsFixed(0)).join(', ')})');
              break;
            }
          } else if (m.alan.anahtarlar.contains('indirimOrani') && v >= 100) {
            anlasilmayan.add('İndirim % 0-100 arasında olmalı');
            break;
          }
          for (final a in m.alan.anahtarlar) {
            alanlar[a] = v;
          }
          // Kalanda "100 adet" → stok
          final ek = _adetKalibi(r.kalan);
          if (ek != null && !alanlar.containsKey('stok') && m.alan.anahtarlar.first != 'stok') {
            alanlar['stok'] = ek;
          }
        case _Tur.barkod:
          final d = TrSayi.basamakDizisi(seg, 0);
          if (d.length >= 4) {
            alanlar['barkod'] = d;
          } else if (d.isNotEmpty || seg.isNotEmpty) {
            anlasilmayan.add('Barkod anlaşılamadı');
          }
        case _Tur.kod:
          final t = _kirp(seg, _metinDolgu, const {});
          if (t.isEmpty) break;
          final d = TrSayi.basamakDizisi(t, 0);
          alanlar[m.alan.anahtarlar.first] =
              d.length >= t.length ? d : _buyuk(t.join(''));
        case _Tur.rafKodu:
          final t = _kirp(seg, _metinDolgu, const {});
          if (t.isEmpty) break;
          final b = StringBuffer();
          for (final w in t.take(3)) {
            b.write(TrSayi.tekHane(w) ?? w);
          }
          alanlar['rafNo'] = _buyuk(b.toString());
        case _Tur.birim:
          final t = _kirp(seg, _metinDolgu, const {});
          if (t.isEmpty) break;
          final sozluk = m.alan.anahtarlar.first == 'koliBirimAdi' ? _koliBirimleri : _birimSozlugu;
          final bulunan = sozluk[t.first];
          if (bulunan == null) {
            anlasilmayan.add('$etiket "${t.first}" tanınmadı');
          } else {
            alanlar[m.alan.anahtarlar.first] = bulunan;
            if (m.alan.anahtarlar.first == 'birim' && bulunan == 'KG') {
              alanlar['satisBirimiTipi'] = 'kg';
            }
          }
        case _Tur.metin:
        case _Tur.buyukMetin:
        case _Tur.ad:
          final t = _kirp(seg, _metinDolgu, _sondakiDolgu);
          if (t.isEmpty) break;
          final deger = t.join(' ');
          alanlar[m.alan.anahtarlar.first] = m.alan.tur == _Tur.buyukMetin
              ? _buyuk(deger)
              : basHarfBuyut(deger);
      }
    }

    // 6) Hiçbir işaretçi yok ama sadece "kaydet" gibi eylem dışı metin → adı
    //    çağıran taraf belirler (Gemini/son çare). Burada uydurma yapılmaz.
    return UrunSesSonuc(alanlar, eylemler, anlasilmayan);
  }
}

/// Gemini (veya başka bir kaynak) JSON'undan gelen çoklu alan sözlüğünü AYNI
/// doğrulamadan geçirir — model uydurma anahtar/negatif/geçersiz KDV üretse
/// bile forma yalnız güvenli değerler ulaşır.
extension UrunSesJson on UrunSesAyristirici {
  static UrunSesSonuc jsondan(Map<String, dynamic> json) {
    final alanlar = <String, Object>{};
    final anlasilmayan = <String>[];

    double? sayi(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return TrSayi.ilkSayi(v);
      return null;
    }

    const sayisal = {
      'alisFiyat', 'alisFiyatKdvDahil', 'satisFiyati', 'toptanFiyat', 'stok',
      'minimumStok', 'maksimumStok', 'koliIciMiktar', 'agirlik', 'indirimOrani',
      'alisKdvOran', 'kdvOran',
    };
    const metin = {
      'urunAdi', 'anaGrup', 'altGrup', 'marka', 'uretici', 'model', 'rafNo', 'renk',
      'beden', 'muhasebeKodu', 'kod', 'alan1', 'alan2', 'alan3', 'alan4',
    };
    for (final e in json.entries) {
      final k = e.key;
      final v = e.value;
      if (v == null) continue;
      if (sayisal.contains(k)) {
        final d = sayi(v);
        if (d == null || d < 0) {
          anlasilmayan.add('${UrunSesSonuc.etiketler[k] ?? k} değeri anlaşılamadı');
          continue;
        }
        if ((k == 'alisKdvOran' || k == 'kdvOran') &&
            !UrunSesAyristirici.kdvOranlari.contains(d)) {
          anlasilmayan.add('KDV %${d.toStringAsFixed(0)} geçersiz');
          continue;
        }
        if (k == 'indirimOrani' && d >= 100) {
          anlasilmayan.add('İndirim % 0-100 arasında olmalı');
          continue;
        }
        alanlar[k] = d;
      } else if (k == 'barkod') {
        final d = v.toString().replaceAll(RegExp(r'[^\d]'), '');
        if (d.length >= 4) alanlar['barkod'] = d;
      } else if (metin.contains(k)) {
        final s = v.toString().trim();
        if (s.isEmpty || s.toLowerCase() == 'null') continue;
        alanlar[k] = (k == 'model' || k == 'rafNo' || k == 'beden' || k == 'muhasebeKodu' || k == 'kod')
            ? s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase()
            : UrunSesAyristirici.basHarfBuyut(s);
      } else if (k == 'birim') {
        final b = UrunSesAyristirici._birimSozlugu[TrSayi.normalize(v.toString())];
        if (b != null) {
          alanlar['birim'] = b;
          if (b == 'KG') alanlar['satisBirimiTipi'] = 'kg';
        }
      } else if (k == 'aktif' || k == 'lotTakibi' || k == 'seriTakibi') {
        if (v is bool) alanlar[k] = v;
      }
    }
    return UrunSesSonuc(alanlar, <String>{}, anlasilmayan);
  }
}
