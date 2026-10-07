// lib/ekranlar/urun/masaustu/urun_masaustu_gorunum.dart
//
// Ürün Listesi — masaüstü (geniş pencere) görünümü: tablo + alt şerit +
// sağ tık menüsü + F1/F2/F3/F6 kısayolları. Veri ve iş mantığı çağıran
// ekrandan gelir (sadece görünüm).
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../depolar/urun_deposu.dart';
import 'package:intl/intl.dart';
import '../../../modeller/urun_model.dart';
import '../../../servisler/kolon_haritalama.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class UrunMasaustuGorunum extends StatefulWidget {
  final List<UrunModel> urunler;
  final ScrollController scrollController;
  final VoidCallback onEkle;
  final void Function(UrunModel urun) onSil;
  final VoidCallback onExcel;
  final VoidCallback onYenile;

  /// Görünen kolonların anahtarları (bkz. [katalog]).
  final Set<String> gorunenKolonlar;

  /// Çoklu seçim (Ctrl+tık, Shift+tık, fareyle sürükleme, Ctrl+A) — 2+ ürün
  /// seçiliyse ekranın toplu işlem çubuğu açılır.
  final Set<int> seciliIds;
  final ValueChanged<Set<int>> onCokluSecim;
  final VoidCallback onTopluSil;
  final VoidCallback onTopluIslem;

  const UrunMasaustuGorunum({
    super.key,
    required this.urunler,
    required this.scrollController,
    required this.onEkle,
    required this.onSil,
    required this.onExcel,
    required this.onYenile,
    required this.gorunenKolonlar,
    required this.seciliIds,
    required this.onCokluSecim,
    required this.onTopluSil,
    required this.onTopluIslem,
  });

  /// Kayıtlı kolon tercihini güncel kataloğla birleştirir. Tercih
  /// kaydedildikten SONRA kataloğa eklenen kolonlar (ör. Fiyat/Maliyet
  /// Güncelleme Tarihi) kullanıcının listesinde hiç görünmüyordu.
  /// [bilinen]: tercih kaydedilirken katalogda olan anahtarlar — bunda
  /// olmayan (yeni) kolonlar otomatik eklenir; kullanıcının bilerek
  /// kapattıkları (bilinen ama seçili olmayan) geri açılmaz. [bilinen]
  /// null ise (eski kayıt) yalnızca fiyat/maliyet güncelleme kolonları eklenir.
  static Set<String> kolonTercihiBirlestir({
    required List<String> kayitli,
    required List<String>? bilinen,
    required Set<String> gecerli,
  }) {
    final secim = kayitli.where(gecerli.contains).toSet()..add('urunAdi');
    if (bilinen == null) {
      secim.addAll(const {
        'fiyatGuncTarih', 'fiyatGuncKullanici',
        'maliyetGuncTarih', 'maliyetGuncKullanici',
      }.intersection(gecerli));
    } else {
      secim.addAll(gecerli.difference(bilinen.toSet()));
    }
    return secim;
  }

  static String _sayiYaz(double d) =>
      d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(3);

  static TabloKolon<UrunModel> _yazi(String baslik, double genislik,
          String? Function(UrunModel u) al,
          {bool esnek = false}) =>
      TabloKolon(
          baslik: baslik,
          genislik: genislik,
          esnek: esnek,
          deger: (u) => al(u) ?? '',
          sirala: (u) => (al(u) ?? '').toLowerCase());

  /// Tarih/saat kolonu: ham ISO metin yerine "gg.AA.yyyy SS:dd" (yerel saat)
  /// gösterilir; sıralama ham UTC zamana göre. SQLite UTC damgası ile Dart
  /// yerel damgası aynı şekilde doğru çevrilir.
  static TabloKolon<UrunModel> _tarih(String baslik, double genislik,
          String? Function(UrunModel u) al) =>
      TabloKolon(
          baslik: baslik,
          genislik: genislik,
          deger: (u) {
            final t = KolonHaritalama.utcZaman(al(u));
            return t == null
                ? ''
                : DateFormat('dd.MM.yyyy HH:mm').format(t.toLocal());
          },
          sirala: (u) =>
              KolonHaritalama.utcZaman(al(u))?.millisecondsSinceEpoch ?? 0);

  static TabloKolon<UrunModel> _tutar(String baslik, double genislik,
          double Function(UrunModel u) al) =>
      TabloKolon(
          baslik: baslik,
          genislik: genislik,
          sagaYasli: true,
          deger: (u) => ParaUtils.formatla(al(u), simge: ''),
          sirala: al);

  static TabloKolon<UrunModel> _miktar(String baslik, double genislik,
          double Function(UrunModel u) al) =>
      TabloKolon(
          baslik: baslik,
          genislik: genislik,
          sagaYasli: true,
          deger: (u) => _sayiYaz(al(u)),
          sirala: al);

  static TabloKolon<UrunModel> _evet(
          String baslik, double genislik, bool Function(UrunModel u) al) =>
      TabloKolon(
          baslik: baslik,
          genislik: genislik,
          deger: (u) => al(u) ? 'Evet' : 'Hayır',
          sirala: (u) => al(u) ? 1 : 0);

  static TabloKolon<UrunModel> _say(String baslik, double genislik,
          double Function(UrunModel u) al) =>
      TabloKolon(
          baslik: baslik,
          genislik: genislik,
          sagaYasli: true,
          deger: (u) => al(u) == 0 ? '' : _sayiYaz(al(u)),
          sirala: al);

  /// TÜM seçilebilir başlıklar (ürün tablosunun tüm alanları). Sıra, tablodaki
  /// sıradır. `temel` = eski, dar görünümün 10 kolonu.
  static final List<UrunKolonu> katalog = [
    UrunKolonu('kod', 'Kod', true, _yazi('Kod', 120, (u) => u.kod)),
    UrunKolonu('barkod', 'Barkod', true, _yazi('Barkod', 140, (u) => u.barkod)),
    UrunKolonu('urunAdi', 'Ürün Adı', true,
        _yazi('Ürün Adı', 220, (u) => u.urunAdi, esnek: true),
        zorunlu: true),
    UrunKolonu('birim', 'Birim', true,
        TabloKolon(baslik: 'Birim', genislik: 70, deger: (u) => u.birimAdi)),
    UrunKolonu('alis', 'Alış Fiyat', true,
        _tutar('Alış Fiyat', 95, (u) => u.alisFiyat)),
    UrunKolonu('alisKdv', 'Alış (KDV Dahil)', false,
        _tutar('Alış KDV Dahil', 110, (u) => u.alisFiyatKdvDahil)),
    UrunKolonu('satis', 'Satış Fiyatı', true,
        _tutar('Satış Fiyatı', 100, (u) => u.satisFiyati)),
    UrunKolonu('toptan', 'Toptan Fiyat', false,
        _tutar('Toptan Fiyat', 100, (u) => u.toptanFiyat)),
    UrunKolonu(
        'stok',
        'Stok',
        true,
        TabloKolon(
            baslik: 'Stok',
            genislik: 90,
            sagaYasli: true,
            deger: (u) => _sayiYaz(u.stok),
            sirala: (u) => u.stok,
            renk: (u) => u.stok <= 0
                ? TsRenk.hata
                : (u.kritikStok ? TsRenk.uyari : null))),
    UrunKolonu('minStok', 'Min. Stok', false,
        _miktar('Min. Stok', 85, (u) => u.minimumStok)),
    UrunKolonu('maksStok', 'Maks. Stok', false,
        _miktar('Maks. Stok', 85, (u) => u.maksimumStok)),
    UrunKolonu('kdv', 'KDV %', true,
        TabloKolon(baslik: 'KDV %', genislik: 60, sagaYasli: true, deger: (u) => u.kdvOran)),
    UrunKolonu('anaGrup', 'Ana Grup', true, _yazi('Ana Grup', 130, (u) => u.anaGrup)),
    UrunKolonu('altGrup', 'Alt Grup', false, _yazi('Alt Grup', 130, (u) => u.altGrup)),
    UrunKolonu('marka', 'Marka', false, _yazi('Marka', 120, (u) => u.marka)),
    UrunKolonu('model', 'Model', false, _yazi('Model', 110, (u) => u.model)),
    UrunKolonu('uretici', 'Üretici', false, _yazi('Üretici', 130, (u) => u.uretici)),
    UrunKolonu('mensei', 'Menşei', false, _yazi('Menşei', 100, (u) => u.mensei)),
    UrunKolonu('rafNo', 'Raf No', false, _yazi('Raf No', 90, (u) => u.rafNumarasi)),
    UrunKolonu('sonKullanma', 'Son Kullanma', false,
        _yazi('Son Kullanma', 110, (u) => u.sonKullanmaTarihi)),
    UrunKolonu(
        'karOran',
        'Kâr %',
        true,
        TabloKolon(
            baslik: 'Kâr %',
            genislik: 70,
            sagaYasli: true,
            deger: (u) => u.karOrani.toStringAsFixed(1),
            sirala: (u) => u.karOrani)),
    UrunKolonu('karTutari', 'Kâr Tutarı', false,
        _tutar('Kâr Tutarı', 95, (u) => u.satisFiyati - u.alisFiyatKdvDahil)),
    UrunKolonu('stokDegeri', 'Stok Değeri', false,
        _tutar('Stok Değeri', 105, (u) => u.stok * u.alisFiyatKdvDahil)),
    UrunKolonu('alan1', 'Alan 1', false, _yazi('Alan 1', 100, (u) => u.alan1)),
    UrunKolonu('alan2', 'Alan 2', false, _yazi('Alan 2', 100, (u) => u.alan2)),
    UrunKolonu('alan3', 'Alan 3', false, _yazi('Alan 3', 100, (u) => u.alan3)),
    UrunKolonu('alan4', 'Alan 4', false, _yazi('Alan 4', 100, (u) => u.alan4)),
    UrunKolonu('barkodlar', 'Ek Barkodlar', false, _yazi('Ek Barkodlar', 150, (u) => u.barkodlar)),
    UrunKolonu('altAd', 'Alternatif Ad', false, _yazi('Alternatif Ad', 160, (u) => u.alternatifUrunAdi)),
    UrunKolonu('plu', 'PLU No', false, _yazi('PLU No', 80, (u) => u.pluNumarasi)),
    UrunKolonu('kartTipi', 'Kart Tipi', false, _yazi('Kart Tipi', 90, (u) => u.kartTipi)),
    UrunKolonu('eskiKod', 'Eski Kod', false, _yazi('Eski Kod', 100, (u) => u.eskiKodu)),
    UrunKolonu('muhKod', 'Muhasebe Kodu', false, _yazi('Muhasebe Kodu', 110, (u) => u.muhasebeKodu)),
    UrunKolonu('muafKod', 'Muafiyet Kodu', false, _yazi('Muafiyet Kodu', 110, (u) => u.muafiyetKodu)),
    UrunKolonu('paraBirimi', 'Para Birimi', false, _yazi('Para Birimi', 90, (u) => u.paraBirimi)),
    UrunKolonu('dovizKodu', 'Döviz Kodu', false, _yazi('Döviz Kodu', 90, (u) => u.dovizKodu)),
    UrunKolonu('dovizTutari', 'Döviz Tutarı', false, _say('Döviz Tutarı', 100, (u) => u.dovizTutari ?? 0)),
    UrunKolonu('alisKdvOran', 'Alış KDV %', false, _say('Alış KDV %', 85, (u) => u.alisKdvOran)),
    UrunKolonu('netAlis', 'Net Alış Fiyatı', false, _tutar('Net Alış Fiyatı', 110, (u) => u.netAlisFiyat)),
    UrunKolonu('indirimOrani', 'İndirim %', false, _say('İndirim %', 85, (u) => u.indirimOrani)),
    UrunKolonu('indirimliFiyat', 'İndirimli Fiyat', false, _tutar('İndirimli Fiyat', 110, (u) => u.indirimliFiyatKayitli)),
    UrunKolonu('otoIndirim', 'Otomatik İndirim', false, _evet('Otomatik İndirim', 115, (u) => u.otomatikIndirim)),
    UrunKolonu('sonAlimIndirim', 'Son Alım İndirim %', false, _say('Son Alım İndirim %', 130, (u) => u.sonAlimIndirimOran)),
    UrunKolonu('maksSatir', 'Maks. Satır Miktarı', false, _say('Maks. Satır Miktarı', 135, (u) => u.maksimumSatirMiktari)),
    UrunKolonu('eskiFiyat', 'Eski Fiyat', false, _tutar('Eski Fiyat', 95, (u) => u.eskiFiyat)),
    UrunKolonu('eskiFiyatTarih', 'Eski Fiyat Tarihi', false, _yazi('Eski Fiyat Tarihi', 125, (u) => u.eskiFiyatTarih?.toIso8601String().split('T').first)),
    UrunKolonu('promoGrup', 'Promosyon Grubu', false, _yazi('Promosyon Grubu', 125, (u) => u.promosyonGrup)),
    UrunKolonu('promoAktif', 'Promosyon Aktif', false, _evet('Promosyon Aktif', 115, (u) => u.promosyonAktif)),
    UrunKolonu('renk', 'Renk', false, _yazi('Renk', 80, (u) => u.renk)),
    UrunKolonu('beden', 'Beden', false, _yazi('Beden', 80, (u) => u.beden)),
    UrunKolonu('sube', 'Şube', false, _yazi('Şube', 90, (u) => u.sube)),
    UrunKolonu('aktif', 'Aktif', false, _evet('Aktif', 70, (u) => u.aktif)),
    UrunKolonu('seriTakip', 'Seri No Takibi', false, _evet('Seri No Takibi', 105, (u) => u.seriNoTakibi)),
    UrunKolonu('seriNo', 'Seri No', false, _yazi('Seri No', 100, (u) => u.seriNumarasi)),
    UrunKolonu('lotTakip', 'Lot Takibi', false, _evet('Lot Takibi', 90, (u) => u.lotTakibi)),
    UrunKolonu('lotNo', 'Lot No', false, _yazi('Lot No', 90, (u) => u.lotNo)),
    UrunKolonu('lotAciklama', 'Lot Açıklama', false, _yazi('Lot Açıklama', 130, (u) => u.lotAciklama)),
    UrunKolonu('qrMenu', 'QR Menüde', false, _evet('QR Menüde', 85, (u) => u.qrMenude)),
    UrunKolonu('toptanSatista', 'Toptan Satışta', false, _evet('Toptan Satışta', 110, (u) => u.toptanSatista)),
    UrunKolonu('koliIci', 'Koli İçi Miktar', false, _say('Koli İçi Miktar', 110, (u) => u.koliIciMiktar)),
    UrunKolonu('koliBirim', 'Koli Birimi', false, _yazi('Koli Birimi', 90, (u) => u.koliBirimAdi)),
    UrunKolonu('satisBirimTipi', 'Satış Birimi Tipi', false, _yazi('Satış Birimi Tipi', 120, (u) => u.satisBirimiTipi)),
    UrunKolonu('asgariSiparis', 'Asgari Sipariş', false, _say('Asgari Sipariş', 105, (u) => u.asgariSiparisMiktari)),
    UrunKolonu('grupSorumlusu', 'Grup Sorumlusu', false, _yazi('Grup Sorumlusu', 120, (u) => u.grupSorumlusu)),
    UrunKolonu('rafOmru', 'Raf Ömrü', false, _say('Raf Ömrü', 85, (u) => (u.rafOmru ?? 0).toDouble())),
    UrunKolonu('puanOrani', 'Puan Oranı', false, _say('Puan Oranı', 90, (u) => u.puanOrani)),
    UrunKolonu('resmiBakiye', 'Resmi Bakiye', false, _say('Resmi Bakiye', 100, (u) => u.resmiBakiye)),
    UrunKolonu('barkodOlcu', 'Barkod Ölçü Birimi', false, _yazi('Barkod Ölçü Birimi', 130, (u) => u.barkodOlcuBirimi)),
    UrunKolonu('en', 'En', false, _say('En', 70, (u) => u.en)),
    UrunKolonu('boy', 'Boy', false, _say('Boy', 70, (u) => u.boy)),
    UrunKolonu('yukseklik', 'Yükseklik', false, _say('Yükseklik', 85, (u) => u.yukseklik)),
    UrunKolonu('agirlik', 'Ağırlık', false, _say('Ağırlık', 80, (u) => u.agirlik)),
    UrunKolonu('hacim', 'Hacim', false, _say('Hacim', 80, (u) => u.hacim)),
    UrunKolonu('toplamMaliyet', 'Toplam Maliyet', false, _tutar('Toplam Maliyet', 110, (u) => u.toplamMaliyet)),
    UrunKolonu('toplamStok', 'Toplam Stok', false, _say('Toplam Stok', 95, (u) => u.toplamStok)),
    UrunKolonu('receteKatsayi', 'Reçete Katsayısı', false, _say('Reçete Katsayısı', 115, (u) => u.receteKatsayi)),
    UrunKolonu('evrakKontrol', 'Evrak Kontrol', false, _evet('Evrak Kontrol', 100, (u) => u.evrakKontrolAktif)),
    UrunKolonu('fiyatGuncTarih', 'Fiyat Güncelleme Tarihi', false, _tarih('Fiyat Güncelleme Tarihi', 160, (u) => u.fiyatGuncellemeTarih)),
    UrunKolonu('fiyatGuncKullanici', 'Fiyatı Güncelleyen', false, _yazi('Fiyatı Güncelleyen', 130, (u) => u.fiyatGuncelleyenKullanici)),
    UrunKolonu('maliyetGuncTarih', 'Maliyet Güncelleme Tarihi', false, _tarih('Maliyet Güncelleme Tarihi', 170, (u) => u.maliyetGuncellemeTarih)),
    UrunKolonu('maliyetGuncKullanici', 'Maliyeti Güncelleyen', false, _yazi('Maliyeti Güncelleyen', 140, (u) => u.maliyetGuncelleyenKullanici)),
    UrunKolonu('barkodYazTarih', 'Barkod Yazdırma Tarihi', false, _tarih('Barkod Yazdırma Tarihi', 160, (u) => u.barkodYazdirmaTarih)),
    UrunKolonu('guncellemeTarihi', 'Güncelleme Tarihi', false, _tarih('Güncelleme Tarihi', 135, (u) => u.guncellemeTarihi)),
    UrunKolonu('guncelleyen', 'Güncelleyen', false, _yazi('Güncelleyen', 110, (u) => u.guncelleyenKullanici)),
    UrunKolonu('kayitTarihi', 'Kayıt Tarihi', false, _tarih('Kayıt Tarihi', 120, (u) => u.kayitTarihi)),
    UrunKolonu('kaydeden', 'Kaydeden', false, _yazi('Kaydeden', 100, (u) => u.kaydedenKullanici)),
    UrunKolonu('sonKullaniciGunc', 'Son Güncelleme', false, _tarih('Son Güncelleme', 140, (u) => u.lastUpdated)),
  ];

  /// Varsayılan: ürün tablosunun TÜM alanları (yana kaydırarak görülür).
  static Set<String> get varsayilanKolonlar =>
      {for (final k in katalog) k.anahtar};

  /// Eski dar görünüm (10 temel kolon).
  static Set<String> get temelKolonlar =>
      {for (final k in katalog) if (k.temel) k.anahtar};

  @override
  State<UrunMasaustuGorunum> createState() => _UrunMasaustuGorunumState();
}

class _UrunMasaustuGorunumState extends State<UrunMasaustuGorunum> {
  UrunModel? _secili;

  static String _sayi(double d) =>
      d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(3);

  /// Seçili anahtarlara göre (katalog sırasıyla) görünen kolonlar.
  List<TabloKolon<UrunModel>> get _kolonlar => [
        for (final k in UrunMasaustuGorunum.katalog)
          if (widget.gorunenKolonlar.contains(k.anahtar)) k.kolon,
      ];

  void _duzenle(UrunModel u) => context.push('/urun/ekle', extra: u).then((_) {
        widget.onYenile();
      });

  bool get _coklu => widget.seciliIds.length >= 2;

  void _cokluSecimDegisti(Set<Object> anahtarlar) {
    final ids = anahtarlar.whereType<int>().toSet();
    widget.onCokluSecim(ids);
    // Tek satıra inen seçimde F2/F3'ün hedefi o satır olsun.
    if (ids.length == 1) {
      final kalan = widget.urunler.where((u) => u.id == ids.first);
      if (kalan.isNotEmpty) setState(() => _secili = kalan.first);
    }
  }

  void _menu(UrunModel u, Offset konum) {
    if (_coklu) {
      final n = widget.seciliIds.length;
      masaustuMenuAc(context, konum, [
        MenuOge('Toplu İşlem ($n ürün)', widget.onTopluIslem, ikon: Icons.build_outlined),
        MenuOge('Seçimi Kaldır', () => widget.onCokluSecim({}), ikon: Icons.deselect),
        MenuOge('Seçilileri Sil ($n ürün)', widget.onTopluSil,
            ikon: Icons.delete_outline, ayiracOnce: true),
      ]);
      return;
    }
    masaustuMenuAc(context, konum, [
      MenuOge('Düzenle', () => _duzenle(u), ikon: Icons.edit_outlined),
      MenuOge('Ürün Detayı', () => context.push('/urun/detay/${u.id}'),
          ikon: Icons.info_outline),
      MenuOge('Stok Hareketleri', () => context.push('/stok/hareket'),
          ikon: Icons.swap_vert),
      MenuOge('PLU paneline ekle', () async {
        await UrunDeposu().pluyaEkle(u.id!);
        widget.onYenile();
      }, ikon: Icons.grid_view, ayiracOnce: true),
      MenuOge('Toplu İşlem', () => context.push('/urun/toplu-islem', extra: [u.id]),
          ikon: Icons.build_outlined),
      MenuOge('Excel Aktar', widget.onExcel, ikon: Icons.download_outlined),
      MenuOge('Sil', () => widget.onSil(u),
          ikon: Icons.delete_outline, ayiracOnce: true),
    ]);
  }

  // ── Klavye kısayolları (F1 ekle, F2 düzenle, F3 sil, F6 menü) ────────────
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tus);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tus);
    super.dispose();
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!ekranUstte(context)) return false;
    final k = e.logicalKey;
    final s = _secili;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && k == LogicalKeyboardKey.keyA) {
      // Metin kutusunda Ctrl+A metni seçsin — tablo tümünü yalnız odak
      // bir yazı alanında değilken seçer.
      final odak = FocusManager.instance.primaryFocus?.context;
      if (odak != null &&
          (odak.widget is EditableText ||
              odak.findAncestorWidgetOfExactType<EditableText>() != null)) {
        return false;
      }
      widget.onCokluSecim({for (final u in widget.urunler) if (u.id != null) u.id!});
    } else if (k == LogicalKeyboardKey.f1) {
      widget.onEkle();
    } else if (k == LogicalKeyboardKey.f2) {
      if (s != null && !_coklu) _duzenle(s);
    } else if (k == LogicalKeyboardKey.f3) {
      if (_coklu) {
        widget.onTopluSil();
      } else if (s != null) {
        widget.onSil(s);
      }
    } else if (k == LogicalKeyboardKey.f6) {
      if (s != null) {
        final box = context.findRenderObject() as RenderBox;
        _menu(s, box.localToGlobal(const Offset(300, 120)));
      }
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.urunler;
    final stokToplam = u.fold<double>(0, (t, x) => t + x.stok);
    final satisDeger = u.fold<double>(0, (t, x) => t + x.stok * x.satisFiyati);
    final maliyet = u.fold<double>(0, (t, x) => t + x.stok * x.alisFiyat);
    return Column(children: [
      Expanded(
        child: MasaustuTablo<UrunModel>(
          satirlar: u,
          kolonlar: _kolonlar,
          secili: _secili,
          scrollController: widget.scrollController,
          onSec: (x) => setState(() => _secili = x),
          onCift: _duzenle,
          onSagTik: _menu,
          anahtar: (x) => x.id ?? x,
          seciliAnahtarlar: widget.seciliIds,
          onCokluSecim: _cokluSecimDegisti,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          if (_coklu) AltOzet('Seçili', '${widget.seciliIds.length} ürün'),
          AltOzet('Çeşit Sayısı', '${u.length}'),
          AltOzet('Stok Miktarı', _sayi(stokToplam)),
          AltOzet('Satış Değeri', ParaUtils.formatla(satisDeger)),
          AltOzet('Maliyet Değeri', ParaUtils.formatla(maliyet)),
        ],
        tuslar: [
          AltTus('F1', 'Ekle', Icons.add, const Color(0xFF2E7D32), widget.onEkle),
          AltTus('F2', 'Düzenle', Icons.edit_outlined, const Color(0xFF1565C0),
              _secili == null || _coklu ? null : () => _duzenle(_secili!)),
          AltTus('F3', _coklu ? 'Seçilileri Sil' : 'Sil', Icons.delete_outline,
              const Color(0xFFC62828),
              _coklu
                  ? widget.onTopluSil
                  : (_secili == null ? null : () => widget.onSil(_secili!))),
          AltTus('F6', 'Menü', Icons.menu, const Color(0xFF546E7A),
              _secili == null ? null : () => _menu(_secili!, const Offset(400, 300))),
        ],
      ),
    ]);
  }
}

/// Tablo kolon kataloğundaki bir başlık.
class UrunKolonu {
  final String anahtar;
  final String etiket;
  final bool temel;

  /// Kapatılamaz (ör. Ürün Adı).
  final bool zorunlu;
  final TabloKolon<UrunModel> kolon;
  const UrunKolonu(this.anahtar, this.etiket, this.temel, this.kolon,
      {this.zorunlu = false});
}
