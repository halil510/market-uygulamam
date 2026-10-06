// lib/servisler/ai/eylem/ai_eylem_motoru.dart
//
// Asistanın İŞLEM motoru. Komutu (kural tabanlı veya Gemini) alır; ürün/cari
// adını veritabanında çözer; YETKİYİ denetler; kullanıcıya bir ÖNİZLEME
// (AiEylemOnerisi) üretir. Veri YALNIZCA kullanıcı "Onayla" deyince, MEVCUT
// depo/servislerin aynı atomik yolları (UrunDeposu.guncelle, StokDeposu.stokGir,
// CariTahsilatOdemeServisi.kaydet…) üzerinden değişir — asistanın kendi
// SQL'i yoktur, bu yüzden senkron kuyruğu/kasa/cari tutarlılığı ekranlarla
// birebir aynıdır.
//
// Güvenlik ilkeleri:
//  • Onaysız yazma yok; önizleme 15 dk sonra bayatlar; çift dokunma korumalı.
//  • Uygulamadan hemen önce kayıt YENİDEN okunur — önizlemeden sonra
//    değiştiyse işlem yapılmaz (bayat veriyle ezme yok).
//  • Belirsizlikte (birden çok ürün/cari) tahmin yok: seçenek sunulur.
//  • Silme asistana verilmedi (yalnız ekranlardan).
//  • Yetki, ekranlardan DAHA katı: Müdür/Admin + ilgili modül yetkisi.
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../depolar/birim_deposu.dart';
import '../../../depolar/cari_deposu.dart';
import '../../../depolar/gider_deposu.dart';
import '../../../depolar/stok_deposu.dart';
import '../../../depolar/urun_deposu.dart';
import '../../../modeller/cari_model.dart';
import '../../../modeller/gider_model.dart';
import '../../../modeller/urun_model.dart';
import '../../../cekirdek/utils/hata_utils.dart';
import '../../auth_servisi.dart';
import '../tr_sayi_ayristirici.dart';
import '../../cari_tahsilat_odeme_servisi.dart';
import '../../log_servisi.dart';
import '../../onay_merkezi_servisi.dart';
import 'ai_eylem_ayristirici.dart';
import 'ai_eylem_modeli.dart';
import 'ai_eylem_yonlendirici.dart';
import 'ai_varlik_arama.dart';

class AiEylemMotoru {
  static final AiEylemMotoru _i = AiEylemMotoru._();
  factory AiEylemMotoru() => _i;
  AiEylemMotoru._();

  final _urunDepo = UrunDeposu();
  final _cariDepo = CariDeposu();
  final _stokDepo = StokDeposu();
  final _giderDepo = GiderDeposu();

  static String _para(double v) => ParaUtils.formatla(v);
  static String _sayi(double v) => v == v.truncateToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceAll('.', ',');

  // ── BAĞLAM HAFIZASI ──────────────────────────────────────────────────────
  AiEylemOnerisi? _bekleyen; // yazıyla "evet" denirse uygulanacak tek öneri
  String? _sonUrunAdi; // "onu 40 yap" gibi devam cümleleri için

  static const Set<String> _onayKelimeleri = {
    'evet', 'onayla', 'onaylıyorum', 'uygula', 'kaydet', 'evet onayla', 'onay',
  };
  static const Set<String> _vazgecKelimeleri = {
    'hayır', 'hayir', 'vazgeç', 'vazgeçtim', 'iptal', 'iptal et', 'yapma', 'dur', 'olmasın',
  };

  /// Kullanıcı kartı kullanmak yerine "evet/onayla" veya "vazgeç" yazarsa/söylerse
  /// BEKLEYEN tek öneriyi uygular/iptal eder. Bekleyen yoksa null (normal akış).
  Future<AiEylemSonucu?> onayKomutu(String soru) async {
    final s = TrSayi.normalize(soru);
    final onay = _onayKelimeleri.contains(s);
    final vazgec = _vazgecKelimeleri.contains(s);
    if (!onay && !vazgec) return null;
    final b = _bekleyen;
    if (b == null || b.kullanildi || b.suresiDoldu) {
      _bekleyen = null;
      return null;
    }
    _bekleyen = null;
    if (vazgec) {
      b.iptalEt();
      return const AiEylemSonucu(mesaj: 'Tamam, işlemi iptal ettim. Hiçbir şey değişmedi.');
    }
    try {
      return AiEylemSonucu(mesaj: await b.calistir());
    } catch (e, st) {
      LogServisi().hata('AiEylemMotoru.onayKomutu', hata: e, yigin: st);
      return AiEylemSonucu(mesaj: '❌ İşlem tamamlanamadı: ${kullaniciyaHataMetni(e)}');
    }
  }

  /// UI kartından çağrılır (Onayla düğmesi).
  Future<String> uygula(AiEylemOnerisi o) async {
    if (identical(_bekleyen, o)) _bekleyen = null;
    try {
      return await o.calistir();
    } catch (e, st) {
      LogServisi().hata('AiEylemMotoru.uygula', hata: e, yigin: st);
      return '❌ İşlem tamamlanamadı: ${kullaniciyaHataMetni(e)}';
    }
  }

  // ── GİRİŞ ────────────────────────────────────────────────────────────────
  /// Cümle bir işlem isteğiyse sonuç (önizleme/seçenek/mesaj), değilse null.
  /// [aiYedek] true ise kuralların kaçırdığı SERBEST cümleler Gemini'ye
  /// sorulur (yalnız eylem ipucu varsa).
  Future<AiEylemSonucu?> coz(String soru, {bool aiYedek = true}) async {
    try {
      var komut = AiEylemAyristirici.ayristir(soru);
      if (komut == null && aiYedek && AiEylemYonlendirici.eylemIpucuVar(soru)) {
        komut = await AiEylemYonlendirici().yonlendir(soru);
      }
      if (komut == null) return null;
      final sonuc = await hazirla(komut);
      // Tek öneri → yazıyla "evet" ile de uygulanabilsin.
      _bekleyen = sonuc.oneri;
      return sonuc;
    } catch (e, st) {
      LogServisi().hata('AiEylemMotoru.coz', hata: e, yigin: st);
      return AiEylemSonucu(mesaj: '❌ İşlem hazırlanamadı: ${_hataMetni(e)}');
    }
  }

  static String _hataMetni(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  // ── YETKİ ────────────────────────────────────────────────────────────────
  /// Ekranlardan daha katı: yazma işlemleri Müdür/Admin + modül yetkisi ister
  /// (tahsilat ve cari ekleme için cari yetkisi yeterli).
  String? _yetkiHatasi(AiEylemTuru tur) {
    final a = AuthServisi();
    if (a.aktifKullanici == null) return 'İşlem yapmak için önce giriş yapmalısınız.';
    const mudurMesaji =
        'Bu işlemi asistan üzerinden yapmak için Müdür/Admin yetkisi gerekir. '
        'İlgili ekranı kullanabilirsiniz.';
    switch (tur) {
      case AiEylemTuru.urunEkle:
      case AiEylemTuru.fiyatGuncelle:
      case AiEylemTuru.urunDurum:
        return (a.isMudur && a.yetkiVarSync('urun')) ? null : mudurMesaji;
      case AiEylemTuru.stokDuzenle:
        return (a.isMudur && a.yetkiVarSync('stok')) ? null : mudurMesaji;
      case AiEylemTuru.giderEkle:
        return a.isMudur ? null : mudurMesaji;
      case AiEylemTuru.tahsilatOdeme:
      case AiEylemTuru.cariEkle:
        return a.yetkiVarSync('cari') ? null : 'Cari işlemleri için yetkiniz yok.';
    }
  }

  Future<AiEylemSonucu> hazirla(AiEylemKomutu k) async {
    var yetki = _yetkiHatasi(k.tur);
    // Para ÇIKIŞI (ödeme) ek olarak Müdür ister.
    if (yetki == null && k.tur == AiEylemTuru.tahsilatOdeme && k.islemTipi == 'Odeme' && !AuthServisi().isMudur) {
      yetki = 'Cariye ödeme yapmak için Müdür/Admin yetkisi gerekir.';
    }
    if (yetki != null) return AiEylemSonucu(mesaj: '🔒 $yetki');

    switch (k.tur) {
      case AiEylemTuru.fiyatGuncelle:
        return _urunleIsle(k.urunMetni, (u) => _fiyatOnerisi(k, u));
      case AiEylemTuru.stokDuzenle:
        return _urunleIsle(k.urunMetni, (u) => _stokOnerisi(k, u));
      case AiEylemTuru.urunDurum:
        return _urunleIsle(k.urunMetni, (u) => _durumOnerisi(k, u));
      case AiEylemTuru.urunEkle:
        return _urunEkleOnerisi(k);
      case AiEylemTuru.giderEkle:
        return _giderOnerisi(k);
      case AiEylemTuru.tahsilatOdeme:
        return _cariIsle(k.cariMetni, (c) => _tahsilatOnerisi(k, c));
      case AiEylemTuru.cariEkle:
        return _cariEkleOnerisi(k);
    }
  }

  // ── VARLIK ÇÖZME ─────────────────────────────────────────────────────────
  List<T> _sirala<T>(List<T> liste, String aday, String Function(T) ad) {
    final a = AiVarlikArama.anahtar(aday);
    int puan(T x) {
      final n = AiVarlikArama.anahtar(ad(x));
      if (n == a) return 0;
      if (n.startsWith(a)) return 1;
      return 2;
    }

    final kopya = List<T>.of(liste);
    kopya.sort((x, y) => puan(x).compareTo(puan(y)));
    return kopya;
  }

  Future<List<UrunModel>> _urunAra(String metin) async {
    for (final aday in AiVarlikArama.adaylar(metin)) {
      final r = await _urunDepo.ara(aday, limit: 12);
      if (r.isNotEmpty) return _sirala(r, aday, (u) => u.urunAdi);
    }
    // Sıralı eşleşme yoksa kelime kelime (VE): "gofret ülker" ↔ "Ülker ... Gofret"
    final gruplar = AiVarlikArama.kelimeAdaylari(metin);
    if (gruplar.length > 1) {
      Set<int>? kesisim;
      final harita = <int, UrunModel>{};
      for (final g in gruplar) {
        var bulunan = <UrunModel>[];
        for (final aday in g) {
          bulunan = await _urunDepo.ara(aday, limit: 60);
          if (bulunan.isNotEmpty) break;
        }
        for (final u in bulunan) {
          if (u.id != null) harita[u.id!] = u;
        }
        final idler = bulunan.where((u) => u.id != null).map((u) => u.id!).toSet();
        kesisim = kesisim == null ? idler : kesisim.intersection(idler);
        if (kesisim.isEmpty) break;
      }
      if (kesisim != null && kesisim.isNotEmpty) {
        return kesisim.map((i) => harita[i]!).toList();
      }
    }
    return const [];
  }

  Future<List<CariModel>> _cariAra(String metin) async {
    for (final aday in AiVarlikArama.adaylar(metin)) {
      final r = await _cariDepo.ara(aday, limit: 12);
      if (r.isNotEmpty) return _sirala(r, aday, (c) => c.unvan);
    }
    final gruplar = AiVarlikArama.kelimeAdaylari(metin);
    if (gruplar.length > 1) {
      Set<int>? kesisim;
      final harita = <int, CariModel>{};
      for (final g in gruplar) {
        var bulunan = <CariModel>[];
        for (final aday in g) {
          bulunan = await _cariDepo.ara(aday, limit: 60);
          if (bulunan.isNotEmpty) break;
        }
        for (final c in bulunan) {
          if (c.id != null) harita[c.id!] = c;
        }
        final idler = bulunan.where((c) => c.id != null).map((c) => c.id!).toSet();
        kesisim = kesisim == null ? idler : kesisim.intersection(idler);
        if (kesisim.isEmpty) break;
      }
      if (kesisim != null && kesisim.isNotEmpty) {
        return kesisim.map((i) => harita[i]!).toList();
      }
    }
    return const [];
  }

  /// Tek eşleşmede doğrudan, birkaç eşleşmede seçenek, çok/yok durumunda mesaj.
  Future<AiEylemSonucu> _secimliIsle<T>(
    String? metin,
    String tur,
    Future<List<T>> Function(String) ara,
    String Function(T) ad,
    Future<AiEylemSonucu> Function(T) olustur,
  ) async {
    if (metin == null || metin.trim().isEmpty) {
      return AiEylemSonucu(mesaj: 'Hangi $tur için? $tur adını da yazar mısınız?');
    }
    final liste = await ara(metin);
    if (liste.isEmpty) {
      return AiEylemSonucu(mesaj: '"$metin" ile eşleşen $tur bulunamadı. Adı biraz farklı yazarak deneyin.');
    }
    final anahtar = AiVarlikArama.anahtar(metin);
    final tam = liste.where((x) => AiVarlikArama.anahtar(ad(x)) == anahtar).toList();
    if (liste.length == 1 || tam.length == 1) {
      return olustur(tam.length == 1 ? tam.first : liste.first);
    }
    if (liste.length <= 5) {
      final secimler = <AiEylemOnerisi>[];
      for (final x in liste) {
        final s = await olustur(x);
        if (s.oneri != null) secimler.add(s.oneri!);
      }
      if (secimler.isEmpty) {
        return AiEylemSonucu(mesaj: '"$metin" için ${liste.length} $tur buldum ama hiçbiri için işlem uygun değil.');
      }
      return AiEylemSonucu(
        mesaj: '"$metin" için ${liste.length} $tur buldum, hangisi? (Seçmeden hiçbir şey değişmez.)',
        secimler: secimler,
      );
    }
    final ornek = liste.take(5).map(ad).join(', ');
    return AiEylemSonucu(
        mesaj: '"$metin" ile çok sayıda $tur eşleşti (${liste.length}): $ornek … '
            'Lütfen adı daha açık yazın.');
  }

  Future<AiEylemSonucu> _urunleIsle(String? metin, Future<AiEylemSonucu> Function(UrunModel) olustur) {
    // "onu 40 yap" / "bir de stoğunu 20 yap": ürün adı yoksa son konuşulan ürün.
    final aranan = (metin == null || metin.trim().isEmpty) ? _sonUrunAdi : metin;
    return _secimliIsle<UrunModel>(aranan, 'ürün', _urunAra, (u) => u.urunAdi, (u) {
      _sonUrunAdi = u.urunAdi;
      return olustur(u);
    });
  }

  Future<AiEylemSonucu> _cariIsle(String? metin, Future<AiEylemSonucu> Function(CariModel) olustur) =>
      _secimliIsle<CariModel>(metin, 'cari', _cariAra, (c) => c.unvan, olustur);

  int get _kullaniciId => AuthServisi().aktifKullanici?.id ?? 1;

  // ── FİYAT ────────────────────────────────────────────────────────────────
  double _fiyatDegeri(UrunModel u, String alan) => switch (alan) {
        'alisFiyat' => u.alisFiyat,
        'toptanFiyat' => u.toptanFiyat,
        _ => u.satisFiyati,
      };

  static String _alanAdi(String alan) => switch (alan) {
        'alisFiyat' => 'Alış fiyatı (KDV hariç)',
        'toptanFiyat' => 'Toptan fiyat',
        _ => 'Satış fiyatı',
      };

  Future<AiEylemSonucu> _fiyatOnerisi(AiEylemKomutu k, UrunModel u) async {
    final alan = k.fiyatAlani ?? 'satisFiyati';
    final eski = _fiyatDegeri(u, alan);
    final d = k.deger ?? 0;
    final ham = switch (k.islem) {
      'artir' => eski + d,
      'azalt' => eski - d,
      'yuzdeArtir' => eski * (1 + d / 100),
      'yuzdeAzalt' => eski * (1 - d / 100),
      _ => d,
    };
    final yeni = ParaUtils.yuvarla(ham);
    if (yeni < 0 || (yeni == 0 && alan != 'toptanFiyat')) {
      return AiEylemSonucu(
          mesaj: '❌ ${u.urunAdi}: sonuç fiyat ${_para(yeni)} olur — geçersiz. İşlem hazırlanmadı.');
    }
    if ((yeni - eski).abs() < 0.005) {
      return AiEylemSonucu(mesaj: 'ℹ️ ${u.urunAdi}: ${_alanAdi(alan).toLowerCase()} zaten ${_para(eski)}.');
    }

    final oran = eski > 0 ? ((yeni - eski) / eski * 100) : null;
    final uyarilar = <String>[];
    if (oran != null && oran.abs() >= 50) {
      uyarilar.add('Fiyat %${oran.abs().toStringAsFixed(0)} değişiyor — rakamı kontrol edin.');
    }
    if (alan == 'satisFiyati' && (u.indirimOrani > 0 || u.indirimliFiyatKayitli > 0)) {
      uyarilar.add('Üründeki kayıtlı indirim sıfırlanacak (eski indirim yeni fiyata miras kalmaz).');
    }
    if (alan == 'satisFiyati' && u.alisFiyatKdvDahil > 0 && yeni < u.alisFiyatKdvDahil) {
      uyarilar.add('Yeni satış fiyatı alış (KDV dahil) ${_para(u.alisFiyatKdvDahil)} değerinin ALTINDA — zararına satış.');
    }

    final satirlar = [
      'Ürün: ${u.urunAdi}${u.barkod != null ? '  (${u.barkod})' : ''}',
      '${_alanAdi(alan)}: ${_para(eski)} → ${_para(yeni)}'
          '${oran != null ? '  (${oran >= 0 ? '+' : ''}%${oran.toStringAsFixed(1).replaceAll('.', ',')})' : ''}',
    ];

    return AiEylemSonucu(
      mesaj: 'Şu işlemi yapacağım:',
      oneri: AiEylemOnerisi(
        id: const Uuid().v4(),
        tur: AiEylemTuru.fiyatGuncelle,
        baslik: 'Fiyat Güncelle',
        satirlar: satirlar,
        uyarilar: uyarilar,
        uygula: () async {
          final guncel = await _urunDepo.idileGetir(u.id!);
          if (guncel == null) return '❌ Ürün bulunamadı (silinmiş olabilir).';
          final mevcut = _fiyatDegeri(guncel, alan);
          if ((mevcut - eski).abs() > 0.005) {
            return '⚠️ ${u.urunAdi} fiyatı bu arada ${_para(mevcut)} olarak değişmiş. '
                'Eski veriyle ezmemek için işlem yapılmadı; isteği yeniden yazın.';
          }
          final yeniUrun = switch (alan) {
            'alisFiyat' => guncel.copyWith(
                alisFiyat: yeni,
                alisFiyatKdvDahil: ParaUtils.yuvarla(yeni * (1 + guncel.alisKdvOran / 100))),
            'toptanFiyat' => guncel.copyWith(toptanFiyat: yeni),
            _ => guncel.copyWith(satisFiyati: yeni, indirimOrani: 0, indirimliFiyatKayitli: 0),
          };
          await _urunDepo.guncelle(yeniUrun);
          if (alan == 'satisFiyati') {
            final o = fiyatDegisimOraniHesapla(eski, yeni);
            if (o != null) {
              OnayMerkeziServisi().kaydet(
                tur: OnayTuru.fiyatDegisimi,
                tutar: o,
                esikTutar: OnayEsikleri.fiyatDegisimiOrani,
                referansTuru: 'urunler',
                referansId: u.id,
                aciklama: '${u.urunAdi}: ${_para(eski)} → ${_para(yeni)} (asistan)',
              );
            }
          }
          LogServisi().bilgi('Asistan: ${u.urunAdi} ${_alanAdi(alan)} $eski → $yeni');
          return '✅ ${u.urunAdi}: ${_alanAdi(alan).toLowerCase()} ${_para(eski)} → ${_para(yeni)} olarak güncellendi.';
        },
      ),
    );
  }

  // ── STOK ─────────────────────────────────────────────────────────────────
  Future<AiEylemSonucu> _stokOnerisi(AiEylemKomutu k, UrunModel u) async {
    var miktar = k.deger ?? 0;
    final notlar = <String>[];
    if (k.birim == 'koli' || k.birim == 'paket' || k.birim == 'kutu') {
      if (u.koliIciMiktar > 0) {
        final koli = miktar;
        miktar = koli * u.koliIciMiktar;
        notlar.add('${_sayi(koli)} ${k.birim} × ${_sayi(u.koliIciMiktar)} = ${_sayi(miktar)} ${u.birimAdi.toLowerCase()}');
      } else {
        return AiEylemSonucu(
            mesaj: '❌ ${u.urunAdi} için koli içi miktarı tanımlı değil; '
                'adet olarak söyleyin ya da ürün kartından tanımlayın.');
      }
    }
    final onceki = u.stok;
    final islem = k.islem ?? 'ayarla';
    final yeni = switch (islem) {
      'artir' => onceki + miktar,
      'azalt' => onceki - miktar,
      _ => miktar,
    };
    if (miktar < 0 || (islem != 'ayarla' && miktar == 0)) {
      return const AiEylemSonucu(mesaj: '❌ Miktar geçersiz.');
    }
    if (yeni < 0) {
      return AiEylemSonucu(
          mesaj: '❌ ${u.urunAdi}: stok ${_sayi(onceki)}, ${_sayi(miktar)} düşülürse EKSİYE düşer. '
              'İşlem hazırlanmadı.');
    }
    if ((yeni - onceki).abs() < 0.0005) {
      return AiEylemSonucu(mesaj: 'ℹ️ ${u.urunAdi}: stok zaten ${_sayi(onceki)}.');
    }
    final fark = yeni - onceki;
    final uyarilar = <String>[];
    if (islem == 'ayarla' && onceki > 0 && yeni > onceki * 5 && yeni - onceki > 100) {
      uyarilar.add('Stok ${_sayi(onceki)} → ${_sayi(yeni)}: büyük artış, rakamı kontrol edin.');
    }
    final birimAdi = u.birimAdi.toLowerCase();

    return AiEylemSonucu(
      mesaj: 'Şu işlemi yapacağım:',
      oneri: AiEylemOnerisi(
        id: const Uuid().v4(),
        tur: AiEylemTuru.stokDuzenle,
        baslik: islem == 'artir'
            ? 'Stok Girişi'
            : islem == 'azalt'
                ? 'Stok Çıkışı'
                : 'Stok Sayım Düzeltme',
        satirlar: [
          'Ürün: ${u.urunAdi}${u.barkod != null ? '  (${u.barkod})' : ''}',
          'Stok: ${_sayi(onceki)} → ${_sayi(yeni)} $birimAdi  (${fark >= 0 ? '+' : ''}${_sayi(fark)})',
          ...notlar,
        ],
        uyarilar: uyarilar,
        uygula: () async {
          final guncel = await _urunDepo.idileGetir(u.id!);
          if (guncel == null) return '❌ Ürün bulunamadı (silinmiş olabilir).';
          if ((guncel.stok - onceki).abs() > 0.0005) {
            return '⚠️ ${u.urunAdi} stoğu bu arada ${_sayi(guncel.stok)} olmuş (satış/giriş yapılmış). '
                'İşlem yapılmadı; isteği yeniden yazın.';
          }
          switch (islem) {
            case 'artir':
              await _stokDepo.stokGir(
                  urunId: u.id!, miktar: miktar, kullaniciId: _kullaniciId, aciklama: 'Asistan: stok girişi');
            case 'azalt':
              await _stokDepo.stokDus(
                  urunId: u.id!, miktar: miktar, kullaniciId: _kullaniciId, aciklama: 'Asistan: stok çıkışı');
            default:
              await _stokDepo.stokDuzelt(u.id!, yeni, _kullaniciId, aciklama: 'Asistan: stok sayım düzeltme');
              OnayMerkeziServisi().kaydet(
                tur: OnayTuru.stokDuzeltme,
                tutar: fark.abs(),
                esikTutar: OnayEsikleri.stokDuzeltmeMiktari,
                referansTuru: 'urunler',
                referansId: u.id,
                aciklama: '${u.urunAdi}: ${_sayi(onceki)} → ${_sayi(yeni)} (asistan)',
              );
          }
          LogServisi().bilgi('Asistan: ${u.urunAdi} stok $onceki → $yeni ($islem)');
          return '✅ ${u.urunAdi}: stok ${_sayi(onceki)} → ${_sayi(yeni)} $birimAdi olarak güncellendi.';
        },
      ),
    );
  }

  // ── ÜRÜN DURUMU ──────────────────────────────────────────────────────────
  Future<AiEylemSonucu> _durumOnerisi(AiEylemKomutu k, UrunModel u) async {
    final hedef = k.aktif ?? false;
    if (u.aktif == hedef) {
      return AiEylemSonucu(mesaj: 'ℹ️ ${u.urunAdi} zaten ${hedef ? 'aktif' : 'pasif'}.');
    }
    return AiEylemSonucu(
      mesaj: 'Şu işlemi yapacağım:',
      oneri: AiEylemOnerisi(
        id: const Uuid().v4(),
        tur: AiEylemTuru.urunDurum,
        baslik: hedef ? 'Ürünü Aktife Al' : 'Ürünü Pasife Al',
        satirlar: [
          'Ürün: ${u.urunAdi}${u.barkod != null ? '  (${u.barkod})' : ''}',
          'Durum: ${u.aktif ? 'Aktif' : 'Pasif'} → ${hedef ? 'Aktif' : 'Pasif'}',
        ],
        uyarilar: hedef ? const [] : const ['Pasif ürün satış ekranında ve aramalarda görünmez; kayıtları silinmez.'],
        uygula: () async {
          final guncel = await _urunDepo.idileGetir(u.id!);
          if (guncel == null) return '❌ Ürün bulunamadı (silinmiş olabilir).';
          await _urunDepo.guncelle(guncel.copyWith(aktif: hedef));
          return '✅ ${u.urunAdi} ${hedef ? 'aktife alındı' : 'pasife alındı'}.';
        },
      ),
    );
  }

  // ── ÜRÜN EKLE ────────────────────────────────────────────────────────────
  Future<AiEylemSonucu> _urunEkleOnerisi(AiEylemKomutu k) async {
    final a = k.urunAlanlari ?? const <String, Object>{};
    final ad = (a['urunAdi'] as String?)?.trim() ?? '';
    if (ad.isEmpty) {
      return const AiEylemSonucu(mesaj: 'Ürünün adını da söyler misiniz? Örn: "Ülker gofret ekle alış 6 satış 10 stok 50".');
    }
    double d(String key) => a[key] is double ? a[key] as double : 0;
    String? s(String key) => a[key] is String ? a[key] as String : null;

    final uyarilar = <String>[...k.uyarilar];

    // Aynı adlı ürün var mı?
    final benzer = await _urunDepo.ara(ad, limit: 5, sadecaAktif: false);
    final tamAyni = benzer.where((u) => AiVarlikArama.anahtar(u.urunAdi) == AiVarlikArama.anahtar(ad)).toList();
    if (tamAyni.isNotEmpty) {
      return AiEylemSonucu(
          mesaj: '⚠️ "${tamAyni.first.urunAdi}" adlı ürün zaten kayıtlı '
              '(stok ${_sayi(tamAyni.first.stok)}, fiyat ${_para(tamAyni.first.satisFiyati)}). '
              'Mükerrer kayıt açmadım. Fiyat/stok değiştirmek için "…fiyatını X yap" veya "…stok ekle" diyebilirsiniz.');
    }
    if (benzer.isNotEmpty) {
      uyarilar.add('Benzer ürün var: ${benzer.take(2).map((u) => u.urunAdi).join(', ')} — yine de yeni kayıt açılacak.');
    }

    // Barkod çakışması
    final barkod = s('barkod');
    if (barkod != null) {
      final var_ = await _urunDepo.barkodlaGetirPasifDahil(barkod);
      if (var_ != null) {
        return AiEylemSonucu(mesaj: '❌ Bu barkod ($barkod) zaten "${var_.urunAdi}" ürününde kayıtlı.');
      }
    }

    // Birim
    final birimler = await BirimDeposu().hepsiGetir();
    var birim = s('birim');
    if (birim != null) {
      final eslesen = birimler.where((b) => b.toUpperCase() == birim!.toUpperCase()).toList();
      if (eslesen.isEmpty) {
        uyarilar.add('"$birim" birimi tanımlı değil; ADET olarak eklenecek.');
        birim = null;
      } else {
        birim = eslesen.first;
      }
    }
    final birimAdi = birim ??
        (birimler.firstWhere((b) => b.toUpperCase() == 'ADET', orElse: () => birimler.isEmpty ? 'ADET' : birimler.first));

    final alisKdv = a['alisKdvOran'] is double ? a['alisKdvOran'] as double : null;
    final satisKdv = a['kdvOran'] is double ? a['kdvOran'] as double : null;
    final alisKdvEfektif = alisKdv ?? 18;
    final satisKdvEfektif = satisKdv ?? alisKdv ?? 18;
    if (alisKdv == null && satisKdv == null) {
      uyarilar.add('KDV belirtilmedi: %18 uygulanacak (isterseniz "kdv 10" diye ekleyin).');
    }
    var alis = d('alisFiyat');
    final alisKdvDahilGirilen = d('alisFiyatKdvDahil');
    if (alis == 0 && alisKdvDahilGirilen > 0) {
      alis = ParaUtils.yuvarla(alisKdvDahilGirilen / (1 + alisKdvEfektif / 100));
    }
    final alisKdvDahil = alis > 0 ? ParaUtils.yuvarla(alis * (1 + alisKdvEfektif / 100)) : 0.0;
    final satis = d('satisFiyati');
    if (satis == 0) uyarilar.add('Satış fiyatı belirtilmedi (0 ₺); sonradan "…fiyatını X yap" diyebilirsiniz.');
    if (satis > 0 && alisKdvDahil > 0 && satis < alisKdvDahil) {
      uyarilar.add('Satış fiyatı alış (KDV dahil ${_para(alisKdvDahil)}) fiyatının ALTINDA — zararına satış.');
    }

    final satirlar = <String>[
      'Ürün adı: $ad',
      'Barkod: ${barkod ?? 'otomatik üretilecek'}',
      if (alis > 0) 'Alış: ${_para(alis)} (KDV dahil ${_para(alisKdvDahil)})',
      'Satış: ${_para(satis)}  •  KDV %${_sayi(satisKdvEfektif)}',
      if (d('stok') > 0) 'Açılış stoğu: ${_sayi(d('stok'))} ${birimAdi.toLowerCase()}',
      if (d('minimumStok') > 0) 'Minimum stok: ${_sayi(d('minimumStok'))}',
      if (d('toptanFiyat') > 0) 'Toptan fiyat: ${_para(d('toptanFiyat'))}',
      if (d('koliIciMiktar') > 0) 'Koli içi: ${_sayi(d('koliIciMiktar'))}',
      if (s('anaGrup') != null) 'Grup: ${s('anaGrup')}${s('altGrup') != null ? ' / ${s('altGrup')}' : ''}',
      if (s('marka') != null) 'Marka: ${s('marka')}',
      if (s('rafNo') != null) 'Raf: ${s('rafNo')}',
      'Birim: $birimAdi',
    ];

    return AiEylemSonucu(
      mesaj: 'Yeni ürün kaydını hazırladım:',
      oneri: AiEylemOnerisi(
        id: const Uuid().v4(),
        tur: AiEylemTuru.urunEkle,
        baslik: 'Yeni Ürün Ekle',
        satirlar: satirlar,
        uyarilar: uyarilar,
        uygula: () async {
          // Barkodu UYGULAMA anında üret (önizleme ile arasında çakışma olmasın)
          final b = barkod ?? await _urunDepo.benzersizBarkodUret();
          if (barkod != null && await _urunDepo.barkodlaGetirPasifDahil(b) != null) {
            return '❌ Bu barkod ($b) bu arada başka bir üründe kullanılmış. İşlem yapılmadı.';
          }
          final kod = s('kod') ?? b;
          final urun = UrunModel(
            kod: kod,
            barkod: b,
            urunAdi: ad,
            birimAdi: birimAdi,
            alisFiyat: alis,
            alisFiyatKdvDahil: alisKdvDahil,
            alisKdvOran: alisKdvEfektif,
            kdvOran: _sayi(satisKdvEfektif).replaceAll(',', '.'),
            satisFiyati: satis,
            stok: d('stok'),
            minimumStok: d('minimumStok'),
            maksimumStok: d('maksimumStok'),
            toptanFiyat: d('toptanFiyat'),
            koliIciMiktar: d('koliIciMiktar'),
            anaGrup: s('anaGrup'),
            altGrup: s('altGrup'),
            marka: s('marka'),
            uretici: s('uretici'),
            model: s('model'),
            rafNumarasi: s('rafNo'),
            satisBirimiTipi: (s('satisBirimiTipi') ?? 'adet'),
            aktif: a['aktif'] is bool ? a['aktif'] as bool : true,
          );
          await _urunDepo.ekle(urun);
          LogServisi().bilgi('Asistan: ürün eklendi: $ad ($b)');
          return '✅ "$ad" eklendi (barkod $b). Detay/resim için Ürünler ekranından düzenleyebilirsiniz.';
        },
      ),
    );
  }

  // ── GİDER ────────────────────────────────────────────────────────────────
  Future<AiEylemSonucu> _giderOnerisi(AiEylemKomutu k) async {
    final tutar = k.deger ?? 0;
    if (tutar <= 0) return const AiEylemSonucu(mesaj: '❌ Gider tutarı geçersiz.');
    if (k.odemeTuru != null && k.odemeTuru != 'Nakit') {
      return const AiEylemSonucu(
          mesaj: 'Banka/kredi kartı ile gideri, hangi hesap/kart olduğunu seçebilmeniz için '
              '"Gider Ekle" ekranından girin. Asistan yalnız NAKİT (kasadan) gider yazar.');
    }
    final kategoriler = await _giderDepo.kategorileriGetir();
    if (kategoriler.isEmpty) {
      return const AiEylemSonucu(mesaj: '❌ Tanımlı gider kategorisi yok. Önce Gider ekranından kategori ekleyin.');
    }
    final metin = k.metin ?? '';
    final anahtar = AiVarlikArama.anahtar(metin);
    Map<String, dynamic>? secilen;
    var secilenPuan = 0;
    for (final kat in kategoriler) {
      final ad = AiVarlikArama.anahtar((kat['ad'] as String?) ?? '');
      if (ad.isEmpty) continue;
      var puan = 0;
      if (anahtar.isNotEmpty && ad == anahtar) {
        puan = 3;
      } else if (anahtar.isNotEmpty && (anahtar.contains(ad) || ad.contains(anahtar))) {
        puan = 2;
      } else if (anahtar.split(' ').any((w) => w.length >= 3 && ad.contains(w))) {
        puan = 1;
      }
      if (puan > secilenPuan) {
        secilen = kat;
        secilenPuan = puan;
      }
    }
    final uyarilar = <String>[];
    if (secilen == null) {
      secilen = kategoriler.firstWhere(
        (kat) => const {'diger', 'genel'}.contains(AiVarlikArama.anahtar((kat['ad'] as String?) ?? '')),
        orElse: () => kategoriler.first,
      );
      uyarilar.add('"$metin" için eşleşen kategori bulunamadı; "${secilen['ad']}" kategorisine yazılacak.');
    }
    final katAd = secilen['ad'] as String;
    final katId = secilen['id'] as int;
    if (tutar >= 100000) uyarilar.add('Tutar çok yüksek (${_para(tutar)}) — rakamı kontrol edin.');

    return AiEylemSonucu(
      mesaj: 'Şu gideri yazacağım:',
      oneri: AiEylemOnerisi(
        id: const Uuid().v4(),
        tur: AiEylemTuru.giderEkle,
        baslik: 'Gider Ekle',
        kritik: true,
        satirlar: [
          'Kategori: $katAd',
          'Tutar: ${_para(tutar)}',
          'Ödeme: Nakit (kasadan düşer)',
          'Tarih: bugün',
          if (metin.isNotEmpty) 'Açıklama: $metin',
        ],
        uyarilar: uyarilar,
        uygula: () async {
          final id = await _giderDepo.ekle(GiderModel(
            kategoriId: katId,
            kategoriAdi: katAd,
            tutar: tutar,
            aciklama: metin.isEmpty ? 'Asistan ile eklendi' : '$metin (asistan)',
            tarih: DateTime.now(),
            odemeYontemi: 'Nakit',
            kullaniciId: _kullaniciId,
          ));
          if (tutar >= OnayEsikleri.yuksekGiderTutari) {
            OnayMerkeziServisi().kaydet(
              tur: OnayTuru.yuksekGider,
              tutar: tutar,
              esikTutar: OnayEsikleri.yuksekGiderTutari,
              referansTuru: 'giderler',
              referansId: id,
              aciklama: '$katAd ${_para(tutar)} (asistan)',
            );
          }
          LogServisi().bilgi('Asistan: gider eklendi $katAd $tutar');
          return '✅ $katAd gideri ${_para(tutar)} olarak kaydedildi (kasadan düşüldü).';
        },
      ),
    );
  }

  // ── TAHSİLAT / ÖDEME ─────────────────────────────────────────────────────
  Future<AiEylemSonucu> _tahsilatOnerisi(AiEylemKomutu k, CariModel c) async {
    final tutar = k.deger ?? 0;
    if (tutar <= 0) return const AiEylemSonucu(mesaj: '❌ Tutar geçersiz.');
    if (k.odemeTuru != null && k.odemeTuru != 'Nakit') {
      return const AiEylemSonucu(
          mesaj: 'Havale/kredi kartı ile tahsilat-ödemede hangi banka hesabı/kart olduğunu seçmeniz '
              'gerekir; lütfen Cari > Tahsilat/Ödeme ekranını kullanın. Asistan yalnız NAKİT işler.');
    }
    final tahsilat = k.islemTipi != 'Odeme';
    final uyarilar = <String>[];
    if (tutar >= 50000) uyarilar.add('Tutar çok yüksek (${_para(tutar)}) — rakamı kontrol edin.');
    final bakiye = c.bakiye;

    return AiEylemSonucu(
      mesaj: tahsilat ? 'Şu tahsilatı kaydedeceğim:' : 'Şu ödemeyi kaydedeceğim:',
      oneri: AiEylemOnerisi(
        id: const Uuid().v4(),
        tur: AiEylemTuru.tahsilatOdeme,
        baslik: tahsilat ? 'Tahsilat Al' : 'Ödeme Yap',
        kritik: true,
        satirlar: [
          'Cari: ${c.unvan}',
          'Güncel bakiye: ${_para(bakiye)}',
          '${tahsilat ? 'Tahsilat' : 'Ödeme'}: ${_para(tutar)} — Nakit',
          tahsilat ? 'Kasaya GİRİŞ yazılır' : 'Kasadan ÇIKIŞ yazılır',
        ],
        uyarilar: uyarilar,
        uygula: () async {
          final guncel = await _cariDepo.idileGetir(c.id!);
          if (guncel == null) return '❌ Cari bulunamadı (silinmiş olabilir).';
          if ((guncel.bakiye - bakiye).abs() > 0.005) {
            return '⚠️ ${c.unvan} bakiyesi bu arada ${_para(guncel.bakiye)} olmuş. '
                'İşlem yapılmadı; isteği yeniden yazın.';
          }
          await CariTahsilatOdemeServisi().kaydet(
            cariId: c.id!,
            cariUnvan: c.unvan,
            islemTipi: tahsilat ? 'Tahsilat' : 'Odeme',
            tutar: tutar,
            odemeTuru: 'Nakit',
            kullanici: AuthServisi().aktifAd,
            paraHareketEdiyor: true,
            paraCikiyor: !tahsilat,
            aciklama: 'Asistan ile ${tahsilat ? 'tahsil edildi' : 'ödendi'}',
          );
          LogServisi().bilgi('Asistan: ${tahsilat ? 'tahsilat' : 'ödeme'} ${c.unvan} $tutar');
          return '✅ ${c.unvan}: ${_para(tutar)} ${tahsilat ? 'tahsilat kaydedildi (kasaya girdi)' : 'ödeme kaydedildi (kasadan çıktı)'}.';
        },
      ),
    );
  }

  // ── CARİ EKLE ────────────────────────────────────────────────────────────
  Future<AiEylemSonucu> _cariEkleOnerisi(AiEylemKomutu k) async {
    final ad = (k.metin ?? '').trim();
    if (ad.isEmpty) return const AiEylemSonucu(mesaj: 'Cari adını da söyler misiniz?');
    final tip = k.islemTipi ?? 'Müşteri';
    final mevcut = await _cariDepo.ara(ad, limit: 5);
    final tam = mevcut.where((c) => AiVarlikArama.anahtar(c.unvan) == AiVarlikArama.anahtar(ad)).toList();
    if (tam.isNotEmpty) {
      return AiEylemSonucu(mesaj: '⚠️ "${tam.first.unvan}" adlı cari zaten kayıtlı; mükerrer kayıt açmadım.');
    }
    final uyarilar = <String>[
      if (mevcut.isNotEmpty) 'Benzer cari var: ${mevcut.take(2).map((c) => c.unvan).join(', ')} — yine de yeni kayıt açılacak.',
    ];
    return AiEylemSonucu(
      mesaj: 'Yeni cari kaydını hazırladım:',
      oneri: AiEylemOnerisi(
        id: const Uuid().v4(),
        tur: AiEylemTuru.cariEkle,
        baslik: 'Yeni Cari Ekle',
        satirlar: [
          'Ünvan: $ad',
          'Tip: $tip',
          if (k.telefon != null) 'Telefon: ${k.telefon}',
        ],
        uyarilar: uyarilar,
        uygula: () async {
          await _cariDepo.ekle(CariModel(unvan: ad, cariTipi: tip, telefon: k.telefon));
          LogServisi().bilgi('Asistan: cari eklendi $ad');
          return '✅ "$ad" ($tip) cari olarak eklendi.';
        },
      ),
    );
  }

  @visibleForTesting
  static String sayiMetni(double v) => _sayi(v);
}
