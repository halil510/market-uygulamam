// lib/ekranlar/toptan/cari_detay_paneli.dart
//
// Kullanıcı isteği: "toptan dashboarddan cariyi seçip o carinin içinde
// finans, satışlar, önceki tahsilatlar, faturalar gibi işler yapıyor —
// Eti/Ülker gibi firmalar bu şekilde yapıyor." Bu panel artık gerçek
// bir "cari 360" merkezi: Satışlar (ekstre + faturalandırma) /
// Faturalar / Tahsilatlar sekmeleri. Hiçbir yeni iş mantığı YAZILMADI
// — MEVCUT, kanıtlanmış servisler (FaturalandirmaServisi, FaturaDeposu,
// CariDeposu.hareketleriniGetir) çağrılıyor.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/satis_model.dart';
import '../../modeller/urun_model.dart';
import '../../widgetlar/ortak/il_ilce_alani.dart';
import '../../modeller/fatura_model.dart';
import '../../modeller/cari_hareket_model.dart';
import '../../depolar/satis_deposu.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/fatura_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/cari_adres_deposu.dart';
import '../../depolar/toptan_fiyat_deposu.dart';
import '../../depolar/irsaliye_deposu.dart';
import '../../modeller/fiyat_grubu_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../cekirdek/utils/hata_utils.dart';
import '../cari/fis_detay_ekrani.dart';
import '../satis/iade_ekrani.dart';
import 'toptan_satis_ekrani.dart';
import 'bayi_siparis_al_ekrani.dart';
import 'bekleyen_siparisler_ekrani.dart';

// God-class sertleştirmesi (2026-09-22, kullanıcı onayıyla): bu dosya
// 1294 satırdı. İçerik davranış DEĞİŞTİRİLMEDEN 3 parçaya ayrıldı:
//   - cari_detay_islemler_ext.dart     → İşlemler sekmesi (Satış/Fatura/Tahsilat)
//   - cari_detay_genel_ozet_ext.dart   → Genel + Özet sekmeleri
//   - cari_detay_satis_islem_paneli.dart → satış satırı yandan paneli
part 'cari_detay_islemler_ext.dart';
part 'cari_detay_genel_ozet_ext.dart';
part 'cari_detay_satis_islem_paneli.dart';

/// Yandan (sağdan) yarıya kadar kayarak açılan cari detay paneli.
// 🔴🔴 DÜZELTME (kullanıcı bulgusu — "toptan satış ekranları tam ekran
// olsun, yandan açılır olmasın"): Bu fonksiyon ÖNCEDEN showGeneralDialog
// ile SAĞDAN KAYAN, ekranın sadece %50-92'sini kaplayan DAR bir panel
// açıyordu (SlideTransition + Align(centerRight)). Artık normal, TAM
// EKRAN bir sayfa olarak açılıyor — _CariDetayPaneli zaten kendi
// Scaffold/AppBar'ına sahip olduğu için bu değişiklik güvenli.
Future<void> cariDetayPaneliAc(BuildContext context, CariModel cari) {
  return Navigator.push(context, MaterialPageRoute(
    builder: (_) => _CariDetayPaneli(cari: cari),
  ));
}

class _CariDetayPaneli extends StatefulWidget {
  final CariModel cari;
  const _CariDetayPaneli({required this.cari});

  @override
  State<_CariDetayPaneli> createState() => _CariDetayPaneliState();
}

class _CariDetayPaneliState extends State<_CariDetayPaneli> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _satisDepo = SatisDeposu();
  final _urunDepo = UrunDeposu();
  final _faturaDepo = FaturaDeposu();
  final _cariDepo = CariDeposu();
  final _adresDepo = CariAdresDeposu();

  List<SatisModel> _satislar = [];
  List<FaturaModel> _faturalar = [];
  List<CariHareketModel> _tahsilatlar = [];
  List<Map<String, dynamic>> _irsaliyeler = [];
  List<Map<String, dynamic>> _adresler = [];
  List<Map<String, dynamic>> _aylikSatis = [];
  List<Map<String, dynamic>> _enCokAlinanlar = [];
  FiyatGrubuModel? _fiyatGrubu;
  bool _yukleniyor = true;
  final Set<int> _islemYapiliyorSatisId = {};
  // Kullanıcı isteği: "ekran görünümü yapısı Logo gibi olacak."
  // Logo Mobile Sales'in gerçek yapısı: cari seçilince açılan ekranda
  // İŞLEMLER (varsayılan) / GENEL / ÖZET sekmeleri var — İşlemler
  // sekmesi altında fiş türü seçilerek işlem yapılır. Bu, "hangi fiş
  // listesi gösteriliyor" durumunu tutuyor.
  String _islemAlt = 'Satışlar'; // 'Satışlar' | 'Faturalar' | 'Tahsilatlar'

  static const _tahsilatTipleri = {'Tahsilat', 'Ödeme', 'Odeme', 'Tahsilat İptali'};

  // 🆕 Kullanıcı isteği (2026-09-22): perakende Cari Detay ekranında
  // (cari_detay_ekrani.dart) zaten var olan "satır üzerinde doğrudan
  // yazıcı ikonu" bu toptan/bayi cari 360 panelinde eksikti. AYNI
  // YazdirmaServisi.fisYazdir/makbuzYazdir kod yolu kullanılıyor.
  bool _yazdiriliyor = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _yukle();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    final satislar = await _satisDepo.cariSatislari(widget.cari.id!, limit: 50);
    final faturalar = await _faturaDepo.listele(cariId: widget.cari.id, limit: 50);
    final tumHareketler = await _cariDepo.hareketleriniGetir(widget.cari.id!, limit: 100);
    final tahsilatlar = tumHareketler.where((h) => _tahsilatTipleri.contains(h.fisTipi)).toList();
    // Kullanıcı isteği: "İrsaliye sekmesi" — Logo/Netsis cari kartında
    // standart bir menü seçeneği.
    final irsaliyeler = await IrsaliyeDeposu().cariIrsaliyeleriGetir(widget.cari.id!);
    // Kullanıcı isteği: "Sevkiyat Adresleri" — bir cariye birden fazla
    // teslimat adresi tanımlanabilmesi.
    final adresler = await _adresDepo.hepsiGetir(widget.cari.id!);
    // Kullanıcı isteği: "carinin raporları grafikleri" — son 6 ayın
    // aylık satış toplamı (Logo'daki cari analiz grafikleri gibi).
    final aylikSatis = await _satisDepo.cariAylikSatisGetir(widget.cari.id!);
    // En çok alınan ürünler (miktar bazlı, ilk 6).
    final enCokAlinanlar = await _satisDepo.cariEnCokAlinanlarGetir(widget.cari.id!);
    FiyatGrubuModel? grup;
    if (widget.cari.fiyatGrubuId != null) {
      grup = await ToptanFiyatDeposu().grupGetir(widget.cari.fiyatGrubuId!);
    }
    if (!mounted) return;
    setState(() {
      _satislar = satislar;
      _faturalar = faturalar;
      _tahsilatlar = tahsilatlar;
      _irsaliyeler = irsaliyeler;
      _adresler = adresler;
      _aylikSatis = aylikSatis;
      _enCokAlinanlar = enCokAlinanlar;
      _fiyatGrubu = grup;
      _yukleniyor = false;
    });
  }

  Future<void> _yeniSatis() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ToptanSatisEkrani(baslangicBayi: widget.cari),
    ));
    _yukle();
  }

  Future<void> _siparisAl() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => BayiSiparisAlEkrani(bayi: widget.cari),
    ));
    _yukle();
  }

  Future<void> _bekleyenSiparisler() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => BekleyenSiparislerEkrani(bayi: widget.cari),
    ));
    _yukle();
  }

  Future<void> _detayaGit(SatisModel s) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => FisDetayEkrani(fisId: s.id!, fisTipi: s.fisTipi, cariUnvan: widget.cari.unvan),
    ));
    _yukle();
  }

  /// 🔴 Kullanıcı isteği: "cariye tıklayıp girdiğimizde satışa/siparişe
  /// silme/düzenleme ekle." Muhasebe standart uygulaması, KESİLMİŞ bir
  /// faturayı doğrudan silmeyi/düzenlemeyi ÖNERMEZ — bunun yerine ters
  /// kayıt (iade faturası) düzenlenir (araştırdım: GİB/e-fatura süreçleri
  /// de aynı ilkeye dayanıyor). Bu yüzden burada:
  ///  - Fatura ZATEN kesilmişse: silme ENGELLENIR, kullanıcı "İade Et"e
  ///    yönlendirilir (doğru, denetim izi bırakan yol).
  ///  - Fatura kesilmemişse: silme onaylanır ve mevcut, zaten doğru
  ///    kurulmuş SatisDeposu.sil() (stok/kasa/cari ters kayıtları içeren)
  ///    kullanılır — tekerlek yeniden icat edilmedi.
  Future<void> _silmeyeCalis(SatisModel s) async {
    final faturaVarMi = await _faturaDepo.satisIcinFaturaVarMi(s.id!);
    if (faturaVarMi) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('Bu Satış Faturalandırılmış'),
          ]),
          content: const Text(
              'Zaten fatura kesilmiş bir satış doğrudan silinemez — bu, '
              'muhasebe ve e-Fatura mevzuatına aykırıdır. Düzeltme yapmak '
              'için "İade Et" ile ters kayıt (iade faturası) oluşturun.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam')),
            FilledButton(
              onPressed: () { Navigator.pop(c); _iadeEt(s); },
              child: const Text('İade Et'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Satışı Sil'),
        content: Text('"${s.fisNo}" numaralı satış silinsin mi? Stok, kasa ve '
            'cari bakiyesi otomatik olarak geri alınacak. Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await _satisDepo.sil(s.id!);
      if (mounted) {
        BildirimServisi.basari(context, 'Satış silindi, stok ve bakiye geri alındı');
        _yukle();
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Silinemedi: $e');
    }
  }

  Future<void> _iadeEt(SatisModel s) async {
    try {
      final satisDetay = await _satisDepo.idileGetir(s.id!);
      final kalemler = satisDetay?.kalemler ?? const [];
      if (kalemler.isEmpty) {
        if (mounted) BildirimServisi.uyari(context, 'Bu satışta iade edilecek kalem bulunamadı');
        return;
      }
      final urunler = <UrunModel>[];
      for (final k in kalemler) {
        final u = await _urunDepo.idileGetir(k.urunId);
        if (u != null) urunler.add(u);
      }
      if (!mounted) return;
      if (urunler.isEmpty) {
        BildirimServisi.uyari(context, 'Bu satışın ürünleri artık bulunamıyor (silinmiş olabilir)');
        return;
      }
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => IadeEkrani(baslangicUrunleri: urunler, otomatikKapat: true),
      ));
      _yukle();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'İade ekranı açılamadı: $e');
    }
  }

  Future<void> _cogalt(SatisModel s) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ToptanSatisEkrani(baslangicBayi: widget.cari, tekrarSatisId: s.id),
    ));
    _yukle();
  }

  /// Kullanıcı isteği: "carinin detayında önceden satış yapılmış o
  /// fişin faturalandırılması" — satis_detay_ekrani.dart'taki KANITLANMIŞ
  /// akışla birebir aynı: zaten faturalıysa ona git, değilse cari
  /// bilgisi kontrolü yap, eksikse uyar, tamamsa fatura oluştur.
  Future<void> _faturalandir(SatisModel s) async {
    if (s.id == null || _islemYapiliyorSatisId.contains(s.id)) return;
    setState(() => _islemYapiliyorSatisId.add(s.id!));
    try {
      final mevcut = await FaturalandirmaServisi.mevcutFaturaId(satisId: s.id);
      if (mevcut != null) {
        if (!mounted) return;
        BildirimServisi.bilgi(context, 'Bu satış için zaten bir fatura mevcut, ona yönlendiriliyorsunuz.');
        context.push('/fatura/detay/$mevcut');
        return;
      }

      final kontrol = await FaturalandirmaServisi.kontrolEt(widget.cari.id!);
      if (kontrol == null) {
        if (mounted) BildirimServisi.hata(context, 'Cari bulunamadı.');
        return;
      }

      if (!kontrol.hazir) {
        if (!mounted) return;
        final git = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${kontrol.cari.unvan.isEmpty ? 'Bu cari' : kontrol.cari.unvan} için "
                  "fatura kesilebilmesi için aşağıdaki bilgiler eksik:"),
              const SizedBox(height: 10),
              ...kontrol.eksikAlanlar.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(e),
                    ]),
                  )),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cari Düzenle')),
            ],
          ),
        );
        if (git == true && mounted) {
          await context.push('/cari/ekle', extra: kontrol.cari);
        }
        return;
      }

      // Kalemleri al (satış listesi kalemsiz gelir — tam satışı yeniden çek).
      final tamSatis = await _satisDepo.idileGetir(s.id!);
      if (tamSatis?.kalemler == null || tamSatis!.kalemler!.isEmpty) {
        if (mounted) BildirimServisi.uyari(context, 'Bu satışın kalemleri bulunamadı');
        return;
      }

      // 🔴 DÜZELTME (Madde 21 — GİB/fatura araToplam bulgusu devamı,
      // 2026-09-16): araToplam KDV DAHİL (brüt) doluyordu — bkz.
      // satis_detay_ekrani.dart'taki aynı düzeltme. Net (matrah) olmalı.
      final detaylar = tamSatis.kalemler!.map((k) => FaturaDetayModel(
            urunId: k.urunId,
            urunAdi: k.urunAdi,
            barkod: k.barkod,
            miktar: k.miktar,
            birimFiyat: k.birimFiyat,
            iskontoOrani: k.iskontoOran,
            iskontoTutari: k.iskontoTutar,
            kdvOrani: k.kdvOran,
            kdvTutari: k.kdvTutar,
            araToplam: k.toplamTutar - k.kdvTutar,
            toplamTutar: k.toplamTutar,
          )).toList();

      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol,
        kalemler: detaylar,
        faturaTipi: 'Satis',
        satisId: s.id,
        tarih: s.tarih,
        odenenTutar: s.odenenTutar,
      );

      if (!mounted) return;
      BildirimServisi.basari(context, 'Fatura oluşturuldu ✓');
      _yukle();
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Faturalandırma hatası: $e');
    } finally {
      if (mounted) setState(() => _islemYapiliyorSatisId.remove(s.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final limitAsimi = widget.cari.limitTutari > 0 && widget.cari.bakiye > widget.cari.limitTutari;
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: Text(widget.cari.unvan, overflow: TextOverflow.ellipsis),
        alt: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'İŞLEMLER', icon: Icon(Icons.bolt_outlined, size: 18)),
            Tab(text: 'GENEL', icon: Icon(Icons.info_outline, size: 18)),
            Tab(text: 'ÖZET', icon: Icon(Icons.pie_chart_outline, size: 18)),
          ],
        ),
        lider: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        gradyanli: false,
      ),
      body: Column(children: [
        // ── Bayi özet kartı ──────────────────────────────────────────
        Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF4E342E), Color(0xFF6D4C41)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withAlpha(38), borderRadius: BorderRadius.circular(8)),
                child: Text(widget.cari.musteriTipi, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              if (_fiyatGrubu != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                  child: Text(_fiyatGrubu!.ad, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ),
              ],
              const Spacer(),
              if (limitAsimi) ...[
                const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16),
                const SizedBox(width: 4),
              ],
              Text('Bakiye: ', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(ParaUtils.formatla(widget.cari.bakiye),
                  style: TextStyle(color: limitAsimi ? Colors.orangeAccent : Colors.white,
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ]),
          ]),
        ),
        // ── Sekme içerikleri: Logo Mobile Sales yapısı ────────────────
        // (İşlemler / Genel / Özet)
        Expanded(
          child: _yukleniyor
              ? const TsYukleniyor()
              : TabBarView(controller: _tabCtrl, children: [
                  _islemlerSekmesi(),
                  _genelSekmesi(),
                  _ozetSekmesi(),
                ]),
        ),
      ]),
    );
  }
}
