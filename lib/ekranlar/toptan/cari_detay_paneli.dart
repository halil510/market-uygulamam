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
import 'package:uuid/uuid.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/satis_model.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/fatura_model.dart';
import '../../modeller/cari_hareket_model.dart';
import '../../depolar/satis_deposu.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/fatura_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/toptan_fiyat_deposu.dart';
import '../../modeller/fiyat_grubu_model.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../cari/fis_detay_ekrani.dart';
import '../satis/iade_ekrani.dart';
import 'toptan_satis_ekrani.dart';
import 'bayi_siparis_al_ekrani.dart';
import 'bekleyen_siparisler_ekrani.dart';

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
    final db = await Veritabani().db;
    final satislar = await _satisDepo.cariSatislari(widget.cari.id!, limit: 50);
    final faturalar = await _faturaDepo.listele(cariId: widget.cari.id, limit: 50);
    final tumHareketler = await _cariDepo.hareketleriniGetir(widget.cari.id!, limit: 100);
    final tahsilatlar = tumHareketler.where((h) => _tahsilatTipleri.contains(h.fisTipi)).toList();
    // Kullanıcı isteği: "İrsaliye sekmesi" — Logo/Netsis cari kartında
    // standart bir menü seçeneği.
    final irsaliyeler = await db.rawQuery(
      "SELECT * FROM irsaliyeler WHERE cari_id = ? AND deleted_at IS NULL "
      "ORDER BY tarih DESC LIMIT 50",
      [widget.cari.id],
    );
    // Kullanıcı isteği: "Sevkiyat Adresleri" — bir cariye birden fazla
    // teslimat adresi tanımlanabilmesi.
    final adresler = await db.query('cari_adres', where: 'cari_id = ?', whereArgs: [widget.cari.id], orderBy: 'varsayilan DESC');
    // Kullanıcı isteği: "carinin raporları grafikleri" — son 6 ayın
    // aylık satış toplamı (Logo'daki cari analiz grafikleri gibi).
    final aylikSatis = await db.rawQuery('''
      SELECT strftime('%Y-%m', tarih) AS ay, SUM(genel_toplam) AS toplam
      FROM satislar
      WHERE cari_id = ? AND iptal = 0 AND is_deleted = 0
        AND tarih >= date('now', 'localtime', '-6 months')
      GROUP BY ay ORDER BY ay ASC
    ''', [widget.cari.id]);
    // En çok alınan ürünler (miktar bazlı, ilk 6).
    final enCokAlinanlar = await db.rawQuery('''
      SELECT sk.urun_adi, SUM(sk.miktar) AS toplam_miktar, SUM(sk.toplam_tutar) AS toplam_tutar
      FROM satis_kalem sk
      JOIN satislar s ON sk.satis_id = s.id
      WHERE s.cari_id = ? AND s.iptal = 0 AND s.is_deleted = 0
      GROUP BY sk.urun_adi ORDER BY toplam_tutar DESC LIMIT 6
    ''', [widget.cari.id]);
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
    final db = await Veritabani().db;
    final faturaVarMi = await db.query('faturalar',
        where: 'satis_id = ? AND (deleted_at IS NULL)', whereArgs: [s.id], limit: 1);
    if (faturaVarMi.isNotEmpty) {
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
      final db = await Veritabani().db;
      final kalemler = await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [s.id]);
      if (kalemler.isEmpty) {
        if (mounted) BildirimServisi.uyari(context, 'Bu satışta iade edilecek kalem bulunamadı');
        return;
      }
      final urunler = <UrunModel>[];
      for (final k in kalemler) {
        final urunId = k['urun_id'] as int?;
        if (urunId == null) continue;
        final u = await _urunDepo.idileGetir(urunId);
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
            araToplam: k.miktar * k.birimFiyat,
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

  // ══════════════════ 1) İŞLEMLER (Logo: fiş türü seçip işlem yap) ══════
  Widget _islemlerSekmesi() {
    return Column(children: [
      // Hızlı işlem butonları (Logo'nun "işlemler sekmesi altından fiş
      // türü seçilerek işlem yapılır" mantığı).
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.6,
          children: [
            _islemKisayolu('Yeni Satış', Icons.add_shopping_cart, AppRenkler.primary, _yeniSatis),
            _islemKisayolu('Sipariş Al', Icons.playlist_add_check_circle_outlined, Colors.deepPurple, _siparisAl),
            _islemKisayolu('Bekleyen Siparişler', Icons.pending_actions_outlined, Colors.orange, _bekleyenSiparisler),
            _islemKisayolu('Toptan Ürünler', Icons.inventory_2_outlined, Colors.teal,
                () => context.push('/toptan/urunler')),
          ],
        ),
      ),
      // Alt seçim: hangi fiş listesi gösterilsin (Satışlar/Faturalar/Tahsilatlar).
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'Satışlar', label: Text('Satışlar (${_satislar.length})')),
            ButtonSegment(value: 'Faturalar', label: Text('Faturalar (${_faturalar.length})')),
            ButtonSegment(value: 'Tahsilatlar', label: Text('Tahsilat (${_tahsilatlar.length})')),
          ],
          selected: {_islemAlt},
          onSelectionChanged: (s) => setState(() => _islemAlt = s.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: switch (_islemAlt) {
          'Faturalar' => _faturalarSekmesi(),
          'Tahsilatlar' => _tahsilatlarSekmesi(),
          _ => _satislarSekmesi(),
        },
      ),
    ]);
  }

  Widget _islemKisayolu(String etiket, IconData ikon, Color renk, VoidCallback onTap) {
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Icon(ikon, color: renk, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(etiket, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }

  // ══════════════════ 2) GENEL (Logo: cari hesabın detay bilgileri) ═════
  Widget _genelSekmesi() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _genelSatir(Icons.storefront_outlined, 'Unvan', widget.cari.unvan),
            _genelSatir(Icons.category_outlined, 'Müşteri Tipi', widget.cari.musteriTipi),
            if (_fiyatGrubu != null) _genelSatir(Icons.local_offer_outlined, 'Fiyat Grubu', _fiyatGrubu!.ad),
            if (widget.cari.telefon != null) _genelSatir(Icons.phone_outlined, 'Telefon', widget.cari.telefon!),
            if (widget.cari.email != null) _genelSatir(Icons.email_outlined, 'E-posta', widget.cari.email!),
            if (widget.cari.vergiNo != null) _genelSatir(Icons.badge_outlined, 'Vergi No', widget.cari.vergiNo!),
            if (widget.cari.vergiDairesi != null) _genelSatir(Icons.account_balance_outlined, 'Vergi Dairesi', widget.cari.vergiDairesi!),
            if (widget.cari.vadeGun > 0) _genelSatir(Icons.event_outlined, 'Vade', '${widget.cari.vadeGun} gün'),
            if (widget.cari.limitTutari > 0) _genelSatir(Icons.account_balance_wallet_outlined, 'Kredi Limiti', ParaUtils.formatla(widget.cari.limitTutari), sonSatir: true),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Text('SEVKİYAT ADRESLERİ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: context.textSecondary)),
          const Spacer(),
          TextButton.icon(onPressed: _adresEkle, icon: const Icon(Icons.add, size: 16), label: const Text('Ekle', style: TextStyle(fontSize: 12))),
        ]),
        const SizedBox(height: 4),
        ..._adresler.map((a) => _adresSatiri(a)),
        if (_adresler.isEmpty) Text('Kayıtlı adres yok', style: TextStyle(fontSize: 12, color: context.textHint)),
        const SizedBox(height: 16),
        Text('İRSALİYELER (${_irsaliyeler.length})', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: context.textSecondary)),
        const SizedBox(height: 8),
        _irsaliyeSekmesiIcerik(),
      ],
    );
  }

  Widget _genelSatir(IconData ikon, String etiket, String deger, {bool sonSatir = false}) => Padding(
        padding: EdgeInsets.only(bottom: sonSatir ? 0 : 10),
        child: Row(children: [
          Icon(ikon, size: 16, color: context.textHint),
          const SizedBox(width: 10),
          Text(etiket, style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
          const Spacer(),
          Flexible(child: Text(deger, textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary))),
        ]),
      );

  Widget _adresSatiri(Map<String, dynamic> a) {
    final varsayilan = (a['varsayilan'] as int?) == 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.cardBg, borderRadius: BorderRadius.circular(10),
        border: varsayilan ? Border.all(color: AppRenkler.primary.withAlpha(120)) : null,
      ),
      child: Row(children: [
        Icon(Icons.place_outlined, color: varsayilan ? AppRenkler.primary : context.textHint, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['adres_tipi']?.toString() ?? 'Sevkiyat', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: context.textPrimary)),
            Text('${a['adres']}${a['ilce'] != null ? ', ${a['ilce']}' : ''}${a['il'] != null ? '/${a['il']}' : ''}',
                style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
          ]),
        ),
        IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _adresSil(a['id'] as int)),
      ]),
    );
  }

  // ══════════════════ 3) ÖZET (Logo: bakiye+rapor+grafik) ═══════════════
  Widget _ozetSekmesi() {
    final yaslandirma = _vadeYaslandirma();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (yaslandirma.values.any((v) => v > 0)) ...[
          Text('BORÇ TAKİP (VADE YAŞLANDIRMA)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: context.textSecondary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(14)),
            child: Row(children: yaslandirma.entries.map((e) {
              final renk = switch (e.key) {
                'Vadesi Gelmemiş' => Colors.green,
                '1-30 Gün' => Colors.amber.shade700,
                '31-60 Gün' => Colors.orange,
                _ => Colors.red,
              };
              return Expanded(
                child: Column(children: [
                  Text(ParaUtils.formatla(e.value), style: TextStyle(color: renk, fontSize: 12, fontWeight: FontWeight.w800),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(e.key, style: TextStyle(color: context.textHint, fontSize: 8.5), textAlign: TextAlign.center, maxLines: 1),
                ]),
              );
            }).toList()),
          ),
          const SizedBox(height: 16),
        ],
        ..._ozetIcerik(),
      ]),
    );
  }

  // ══════════════════ SATIŞLAR (Cari Ekstre) ══════════════════
  Widget _satislarSekmesi() {
    if (_satislar.isEmpty) return Center(child: Text('Henüz satış yok', style: TextStyle(color: context.textHint)));
    double bakiyeIz = widget.cari.bakiye;
    final bakiyeler = <double>[];
    for (final s in _satislar) {
      bakiyeler.add(bakiyeIz);
      bakiyeIz -= s.genelToplam;
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.dividerColor),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(children: [
            _ekstreBaslik('TARİH', flex: 3),
            _ekstreBaslik('BELGE NO', flex: 3),
            _ekstreBaslik('TUTAR', flex: 3, sagaYasla: true),
            _ekstreBaslik('BAKİYE', flex: 3, sagaYasla: true),
            const SizedBox(width: 26),
          ]),
        ),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: context.dividerColor),
              right: BorderSide(color: context.dividerColor),
              bottom: BorderSide(color: context.dividerColor),
            ),
          ),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _satislar.length,
            itemBuilder: (c, i) {
              final s = _satislar[i];
              final ciftMi = i.isEven;
              return Column(children: [
                InkWell(
                  // Kullanıcı isteği: "alt panel değil yandan açılır
                  // olacak, profesyoneller gibi." Satıra dokununca
                  // YENİ bir yandan panel (drill-down / stacked
                  // master-detail) açılıyor — İade/Faturalandır/
                  // Çoğalt gibi işlemler ORADA, düzgün boyutlu
                  // butonlar olarak duruyor. Satırın kendisi artık
                  // sıkışık ikonlarla dolu değil.
                  onTap: () async {
                    await satisIslemPaneliAc(
                      context, s, widget.cari,
                      onDetay: () => _detayaGit(s),
                      onFaturalandir: () => _faturalandir(s),
                      onIadeEt: () => _iadeEt(s),
                      onCogalt: () => _cogalt(s),
                      onSil: () => _silmeyeCalis(s),
                    );
                    _yukle();
                  },
                  child: Container(
                    color: ciftMi ? context.inputFill.withAlpha(120) : Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                    child: Row(children: [
                      _ekstreHucre(DateFormat('dd.MM.yy\nHH:mm').format(s.tarih), flex: 3),
                      _ekstreHucre(s.fisNo ?? '—', flex: 3, sonuk: true),
                      _ekstreHucre(ParaUtils.formatla(s.genelToplam), flex: 3, sagaYasla: true, kalin: true),
                      _ekstreHucre(ParaUtils.formatla(bakiyeler[i]), flex: 3, sagaYasla: true,
                          renk: bakiyeler[i] > 0 ? Colors.red.shade400 : Colors.green.shade600),
                      Icon(Icons.chevron_right, size: 18, color: context.textHint),
                    ]),
                  ),
                ),
                if (i < _satislar.length - 1) Divider(height: 1, color: context.dividerColor),
              ]);
            },
          ),
        ),
      ),
    ]);
  }

  // ══════════════════ FATURALAR ══════════════════
  Widget _faturalarSekmesi() {
    if (_faturalar.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.description_outlined, size: 44, color: context.textHint),
        const SizedBox(height: 8),
        Text('Bu cariye ait fatura yok', style: TextStyle(color: context.textHint)),
        const SizedBox(height: 4),
        Text('Satışlar sekmesinden bir satışı faturalandırabilirsiniz',
            style: TextStyle(fontSize: 12, color: context.textHint)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      itemCount: _faturalar.length,
      itemBuilder: (c, i) {
        final f = _faturalar[i];
        final (renk, etiket) = switch (f.odemeDurumu) {
          'odendi' => (Colors.green, 'Ödendi'),
          'kısmen' => (Colors.orange, 'Kısmi Ödeme'),
          _ => (Colors.red, 'Beklemede'),
        };
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: () => context.push('/fatura/detay/${f.id}'),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: renk.withAlpha(30), shape: BoxShape.circle),
                child: Icon(Icons.description_outlined, color: renk, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.faturaNo ?? '—', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary)),
                  Text(DateFormat('dd.MM.yyyy').format(f.tarih), style: TextStyle(fontSize: 11, color: context.textHint)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(ParaUtils.formatla(f.genelToplam), style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: renk.withAlpha(30), borderRadius: BorderRadius.circular(6)),
                  child: Text(etiket, style: TextStyle(fontSize: 9.5, color: renk, fontWeight: FontWeight.w700)),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  // ══════════════════ TAHSİLATLAR ══════════════════
  Widget _tahsilatlarSekmesi() {
    if (_tahsilatlar.isEmpty) {
      return Center(child: Text('Bu cariden henüz tahsilat yapılmamış', style: TextStyle(color: context.textHint)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      itemCount: _tahsilatlar.length,
      itemBuilder: (c, i) {
        final t = _tahsilatlar[i];
        final tutar = t.alacak > 0 ? t.alacak : t.borc;
        final iptalMi = t.fisTipi.contains('İptal');
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: (iptalMi ? context.textSecondary : Colors.green).withAlpha(30), shape: BoxShape.circle),
              child: Icon(iptalMi ? Icons.undo : Icons.payments_outlined,
                  color: iptalMi ? context.textSecondary : Colors.green, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.odemeTuru ?? t.fisTipi, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary)),
                Text(DateFormat('dd.MM.yyyy HH:mm').format(t.tarih), style: TextStyle(fontSize: 11, color: context.textHint)),
                if (t.aciklama.isNotEmpty)
                  Text(t.aciklama, style: TextStyle(fontSize: 11, color: context.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Text(ParaUtils.formatla(tutar),
                style: TextStyle(fontWeight: FontWeight.w700, color: iptalMi ? context.textSecondary : Colors.green)),
          ]),
        );
      },
    );
  }

  // ══════════════════ VADE YAŞLANDIRMA (Borç Takip) ══════════════════
  /// Kullanıcı isteği: "Borç Takip / Vade Yaşlandırma (30-60-90 gün)".
  /// FIFO mantığıyla: tahsilatlar EN ESKİ borçtan başlayarak düşülür,
  /// kalan bakiyeler vade tarihine (satış tarihi + cari.vadeGun) göre
  /// yaş gruplarına ayrılır — Logo/Netsis'teki "Borç Takip Toplamları"
  /// ile aynı mantık.
  Map<String, double> _vadeYaslandirma() {
    final sonuc = <String, double>{
      'Vadesi Gelmemiş': 0, '1-30 Gün': 0, '31-60 Gün': 0, '90+ Gün': 0,
    };
    if (_satislar.isEmpty) return sonuc;

    // En eskiden en yeniye sırala (FIFO tahsis için).
    final kronolojik = List<SatisModel>.from(_satislar.reversed);
    var kullanilabilirTahsilat = _tahsilatlar
        .where((t) => !t.fisTipi.contains('İptal'))
        .fold<double>(0, (s, t) => s + (t.alacak > 0 ? t.alacak : 0));

    final bugun = DateTime.now();
    for (final s in kronolojik) {
      var kalan = s.genelToplam;
      if (kullanilabilirTahsilat > 0) {
        final dusulen = kullanilabilirTahsilat >= kalan ? kalan : kullanilabilirTahsilat;
        kalan -= dusulen;
        kullanilabilirTahsilat -= dusulen;
      }
      if (kalan <= 0.01) continue;

      final vadeTarihi = s.tarih.add(Duration(days: widget.cari.vadeGun));
      final gecikme = bugun.difference(vadeTarihi).inDays;
      if (gecikme <= 0) {
        sonuc['Vadesi Gelmemiş'] = sonuc['Vadesi Gelmemiş']! + kalan;
      } else if (gecikme <= 30) {
        sonuc['1-30 Gün'] = sonuc['1-30 Gün']! + kalan;
      } else if (gecikme <= 60) {
        sonuc['31-60 Gün'] = sonuc['31-60 Gün']! + kalan;
      } else {
        sonuc['90+ Gün'] = sonuc['90+ Gün']! + kalan;
      }
    }
    return sonuc;
  }

  // ══════════════════ İRSALİYE ══════════════════
  Widget _irsaliyeSekmesiIcerik() {
    if (_irsaliyeler.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Bu cariye ait irsaliye yok', style: TextStyle(fontSize: 12, color: context.textHint)),
      );
    }
    return Column(children: _irsaliyeler.map((irs) {
      final tarih = DateTime.tryParse(irs['tarih']?.toString() ?? '');
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.teal.withAlpha(30), shape: BoxShape.circle),
            child: const Icon(Icons.local_shipping_outlined, color: Colors.teal, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(irs['irsaliye_no']?.toString() ?? '—', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary)),
              Text(tarih != null ? DateFormat('dd.MM.yyyy').format(tarih) : '—', style: TextStyle(fontSize: 11, color: context.textHint)),
            ]),
          ),
          Text(ParaUtils.formatla((irs['toplam_tutar'] as num?)?.toDouble() ?? 0),
              style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
        ]),
      );
    }).toList());
  }

  // ══════════════════ SEVKİYAT ADRESLERİ (artık _genelSekmesi içinde gömülü) ══════════════════
  Future<void> _adresEkle() async {
    final adresCtrl = TextEditingController();
    final ilceCtrl = TextEditingController();
    final ilCtrl = TextEditingController();
    String tip = 'Sevkiyat';

    final kaydet = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
        title: const Text('Yeni Sevkiyat Adresi'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: tip,
            decoration: const InputDecoration(labelText: 'Adres Tipi'),
            items: const [
              DropdownMenuItem(value: 'Sevkiyat', child: Text('Sevkiyat')),
              DropdownMenuItem(value: 'Fatura', child: Text('Fatura')),
              DropdownMenuItem(value: 'Depo', child: Text('Depo')),
            ],
            onChanged: (v) => setD(() => tip = v ?? 'Sevkiyat'),
          ),
          const SizedBox(height: 10),
          TextField(controller: adresCtrl, decoration: const InputDecoration(labelText: 'Adres'), maxLines: 2, autofocus: true),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: ilceCtrl, decoration: const InputDecoration(labelText: 'İlçe'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: ilCtrl, decoration: const InputDecoration(labelText: 'İl'))),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      )),
    );
    if (kaydet != true || adresCtrl.text.trim().isEmpty) return;

    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    final varsayilan = _adresler.isEmpty; // ilk eklenen adres otomatik varsayılan
    final yeniId = await db.insert('cari_adres', {
      'global_id': const Uuid().v4(),
      'cari_id': widget.cari.id,
      'adres_tipi': tip,
      'adres': adresCtrl.text.trim(),
      'ilce': ilceCtrl.text.trim().isEmpty ? null : ilceCtrl.text.trim(),
      'il': ilCtrl.text.trim().isEmpty ? null : ilCtrl.text.trim(),
      'varsayilan': varsayilan ? 1 : 0,
      'last_updated': now,
    });
    final satir = await db.query('cari_adres', where: 'id = ?', whereArgs: [yeniId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('cari_adres', Map<String, dynamic>.from(satir.first));
    if (mounted) BildirimServisi.basari(context, 'Adres eklendi');
    _yukle();
  }

  Future<void> _adresSil(int id) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Adresi Sil'),
        content: const Text('Bu sevkiyat adresi silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
              onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    final db = await Veritabani().db;
    await db.delete('cari_adres', where: 'id = ?', whereArgs: [id]);
    if (mounted) BildirimServisi.basari(context, 'Adres silindi');
    _yukle();
  }

  // ══════════════════ RAPORLAR / GRAFİKLER ══════════════════
  List<Widget> _ozetIcerik() {
    if (_satislar.isEmpty) {
      return [
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bar_chart_outlined, size: 44, color: context.textHint),
          const SizedBox(height: 8),
          Text('Rapor oluşturmak için henüz yeterli veri yok', style: TextStyle(color: context.textHint)),
        ])),
      ];
    }

    // Ödeme performansı: vade yaşlandırmadaki "vadesi gelmemiş" oranına
    // bakarak yaklaşık bir "zamanında ödeme" göstergesi.
    final yaslandirma = _vadeYaslandirma();
    final toplamAcikBakiye = yaslandirma.values.fold(0.0, (a, b) => a + b);
    final zamanindaOran = toplamAcikBakiye <= 0.01
        ? 1.0
        : (yaslandirma['Vadesi Gelmemiş'] ?? 0) / toplamAcikBakiye;
    final ortalamaSepet = _satislar.isEmpty
        ? 0.0
        : _satislar.fold(0.0, (s, x) => s + x.genelToplam) / _satislar.length;

    return [
      // ── Özet istatistik kartları ──────────────────────────────
      Row(children: [
        Expanded(child: _raporKarti('Toplam İşlem', '${_satislar.length}', Icons.receipt_long_outlined, AppRenkler.primary)),
        const SizedBox(width: 8),
        Expanded(child: _raporKarti('Ort. Sepet', ParaUtils.formatla(ortalamaSepet), Icons.shopping_basket_outlined, Colors.blue)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _raporKarti('Zamanında Ödeme', '%${(zamanindaOran * 100).toStringAsFixed(0)}',
            Icons.verified_outlined, zamanindaOran > 0.7 ? Colors.green : Colors.orange)),
        const SizedBox(width: 8),
        Expanded(child: _raporKarti('Açık Bakiye', ParaUtils.formatla(toplamAcikBakiye), Icons.account_balance_wallet_outlined, Colors.red)),
      ]),

      // ── Aylık satış grafiği (Logo Mobile Sales: "Haftalık/Aylık Satış") ──
      if (_aylikSatis.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('SON 6 AY SATIŞ TRENDİ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
            letterSpacing: 0.4, color: context.textSecondary)),
        const SizedBox(height: 12),
        Container(
          height: 160,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(14)),
          child: _aylikSatisGrafigi(),
        ),
      ],

      // ── En çok alınan ürünler (Logo Mobile Sales: "En Çok Satılan 10 Ürün") ──
      if (_enCokAlinanlar.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('EN ÇOK ALINAN ÜRÜNLER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
            letterSpacing: 0.4, color: context.textSecondary)),
        const SizedBox(height: 8),
        ..._enCokAlinanlar.map((u) {
          final maxTutar = (_enCokAlinanlar.first['toplam_tutar'] as num).toDouble();
          final buTutar = (u['toplam_tutar'] as num).toDouble();
          final oran = maxTutar <= 0 ? 0.0 : buTutar / maxTutar;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(u['urun_adi']?.toString() ?? '—',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(ParaUtils.formatla(buTutar), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: oran, minHeight: 5,
                    backgroundColor: context.inputFill, color: AppRenkler.primary),
              ),
              const SizedBox(height: 3),
              Text('${(u['toplam_miktar'] as num).toStringAsFixed(0)} adet/birim alındı',
                  style: TextStyle(fontSize: 10, color: context.textHint)),
            ]),
          );
        }),
      ],
    ];
  }

  Widget _raporKarti(String baslik, String deger, IconData ikon, Color renk) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ikon, size: 14, color: renk),
            const SizedBox(width: 5),
            Expanded(child: Text(baslik, style: TextStyle(fontSize: 10, color: context.textHint), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Text(deger, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary)),
        ]),
      );

  Widget _aylikSatisGrafigi() {
    final maxY = _aylikSatis.fold(0.0, (m, e) => (e['toplam'] as num).toDouble() > m ? (e['toplam'] as num).toDouble() : m);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY <= 0 ? 1 : maxY * 1.15,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final idx = group.x.toInt();
              final ay = idx >= 0 && idx < _aylikSatis.length ? _aylikSatis[idx]['ay'].toString() : '';
              return BarTooltipItem('$ay\n${ParaUtils.formatla(rod.toY)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11));
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, _) {
                final idx = val.toInt();
                if (idx < 0 || idx >= _aylikSatis.length) return const SizedBox.shrink();
                final ay = _aylikSatis[idx]['ay'].toString();
                final kisa = ay.length >= 7 ? ay.substring(5) : ay; // "2026-03" -> "03"
                return Text(kisa, style: TextStyle(fontSize: 9, color: context.textSecondary, fontWeight: FontWeight.w500));
              },
            ),
          ),
        ),
        gridData: FlGridData(drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: context.borderColor, strokeWidth: 0.5)),
        borderData: FlBorderData(show: false),
        barGroups: _aylikSatis.asMap().entries.map((e) {
          final toplam = (e.value['toplam'] as num?)?.toDouble() ?? 0;
          return BarChartGroupData(x: e.key, barRods: [
            BarChartRodData(
              toY: toplam, width: 20,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF6D4C41), Color(0xFFA1887F)],
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _ekstreBaslik(String metin, {required int flex, bool sagaYasla = false}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Text(metin, textAlign: sagaYasla ? TextAlign.right : TextAlign.left,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: context.textHint)),
        ),
      );

  Widget _ekstreHucre(String metin, {required int flex, bool sagaYasla = false, bool kalin = false, bool sonuk = false, Color? renk}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(metin, textAlign: sagaYasla ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontSize: 11,
                fontWeight: kalin ? FontWeight.w700 : FontWeight.w500,
                color: renk ?? (sonuk ? context.textSecondary : context.textPrimary),
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      );
}

/// Kullanıcı isteği: "alt panel değil yandan açılır olacak,
/// profesyoneller gibi." Araştırma sonucu: bu, "Stacked Master-Detail"
/// (yığılmalı ana-detay) deseni — cari paneli üstüne, bir üst katman
/// olarak (mevcut panel yerini almadan, ÜSTÜNE yığılarak) yeni bir
/// yandan panel açılıyor. Burada satışın özeti + net, düzgün boyutlu
/// işlem butonları (Detay/Faturalandır/İade Et/Çoğalt) var — önceki
/// hâldeki sıkışık ikon şeridi YERİNE.
Future<void> satisIslemPaneliAc(
  BuildContext context,
  SatisModel satis,
  CariModel cari, {
  required Future<void> Function() onDetay,
  required Future<void> Function() onFaturalandir,
  required Future<void> Function() onIadeEt,
  required Future<void> Function() onCogalt,
  required Future<void> Function() onSil,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.black.withAlpha(80),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (c, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (c, anim, secAnim, child) {
      final ekranGenislik = MediaQuery.of(c).size.width;
      return Align(
        alignment: Alignment.centerRight,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: Material(
            elevation: 16,
            child: SizedBox(
              width: ekranGenislik > 700 ? ekranGenislik * 0.42 : ekranGenislik * 0.86,
              height: double.infinity,
              child: _SatisIslemPaneli(
                satis: satis, cari: cari,
                onDetay: onDetay, onFaturalandir: onFaturalandir,
                onIadeEt: onIadeEt, onCogalt: onCogalt, onSil: onSil,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SatisIslemPaneli extends StatelessWidget {
  final SatisModel satis;
  final CariModel cari;
  final Future<void> Function() onDetay;
  final Future<void> Function() onFaturalandir;
  final Future<void> Function() onIadeEt;
  final Future<void> Function() onCogalt;
  final Future<void> Function() onSil;

  const _SatisIslemPaneli({
    required this.satis, required this.cari,
    required this.onDetay, required this.onFaturalandir,
    required this.onIadeEt, required this.onCogalt, required this.onSil,
  });

  /// Butona basınca: önce BU paneli kapat, sonra asıl işlemi yap
  /// (ör. iade ekranına git) — iki panelin üst üste açık kalmaması için.
  void _kapatVeCalistir(BuildContext context, Future<void> Function() aksiyon) {
    Navigator.pop(context);
    aksiyon();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Satış İşlemleri',
        lider: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        gradyanli: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Fiş özeti ────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4E342E), Color(0xFF6D4C41)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(satis.fisNo ?? '—', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(DateFormat('dd.MM.yyyy HH:mm').format(satis.tarih), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Tutar', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                Text(ParaUtils.formatla(satis.genelToplam),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                const Text('Cari', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                Flexible(
                  child: Text(cari.unvan, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          Text('İŞLEMLER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              letterSpacing: 0.4, color: context.textSecondary)),
          const SizedBox(height: 10),
          // ── Net, düzgün boyutlu işlem butonları ─────────────────
          _islemButonu(context, 'Fiş Detayını Gör', 'Kalemleri ve tam dökümü görüntüle',
              Icons.receipt_long_outlined, AppRenkler.primary, () => _kapatVeCalistir(context, onDetay)),
          const SizedBox(height: 10),
          _islemButonu(context, 'Faturalandır', 'Bu satıştan e-Fatura/e-Arşiv oluştur',
              Icons.description_outlined, Colors.purple, () => _kapatVeCalistir(context, onFaturalandir)),
          const SizedBox(height: 10),
          _islemButonu(context, 'İade Et', 'Bu satıştaki ürünleri iade al',
              Icons.undo, Colors.orange, () => _kapatVeCalistir(context, onIadeEt)),
          const SizedBox(height: 10),
          _islemButonu(context, 'Çoğalt (Tekrar Sipariş)', 'Aynı kalemlerle güncel fiyattan yeni satış başlat',
              Icons.copy_all_outlined, Colors.blue, () => _kapatVeCalistir(context, onCogalt)),
          const SizedBox(height: 10),
          _islemButonu(context, 'Satışı Sil', 'Faturalandırılmamışsa siler; stok/kasa/bakiye otomatik geri alınır',
              Icons.delete_outline, TsRenk.hata, () => _kapatVeCalistir(context, onSil)),
        ]),
      ),
    );
  }

  Widget _islemButonu(BuildContext context, String baslik, String aciklama, IconData ikon, Color renk, VoidCallback onTap) {
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: renk.withAlpha(60))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: renk.withAlpha(30), shape: BoxShape.circle),
              child: Icon(ikon, color: renk, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(baslik, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
                const SizedBox(height: 2),
                Text(aciklama, style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
              ]),
            ),
            Icon(Icons.chevron_right, color: context.textHint),
          ]),
        ),
      ),
    );
  }
}
