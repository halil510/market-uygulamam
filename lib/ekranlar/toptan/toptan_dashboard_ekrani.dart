// lib/ekranlar/toptan/toptan_dashboard_ekrani.dart
//
// Kullanıcı isteği: "toptanın ekranı dashboard olacak, cariler orada,
// cariye girdiğimizde yandan açılır yarıya kadar ekran, burada tüm
// profesyonel toptan satım işlemleri (satış, iade, çoğalt) — Eti/
// Ülker gibi firmalar bu şekilde yapıyor. Sanki bu uygulama farklıymış
// gibi ayrı ekranlar olacak ama altyapı (satış/stok/cari) ortak
// kullanılacak."
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../modeller/cari_model.dart';
import '../../depolar/cari_deposu.dart';
import '../../veri/database/veritabani.dart';
import 'toptan_satis_ekrani.dart';
import 'cari_detay_paneli.dart';

class ToptanDashboardEkrani extends StatefulWidget {
  const ToptanDashboardEkrani({super.key});

  @override
  State<ToptanDashboardEkrani> createState() => _ToptanDashboardEkraniState();
}

class _ToptanDashboardEkraniState extends State<ToptanDashboardEkrani> {
  final _cariDepo = CariDeposu();
  final _aramaCtrl = TextEditingController();
  List<CariModel> _bayiler = [];
  List<CariModel> _filtreli = [];
  bool _yukleniyor = true;
  double _bugunkuToptanCiro = 0;

  @override
  void initState() {
    super.initState();
    _yukle();
    _aramaCtrl.addListener(_filtrele);
  }

  @override
  void dispose() {
    _aramaCtrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    final tumCariler = await _cariDepo.tumunuGetir();
    // 🔴 DÜZELTME (kullanıcı bulgusu — "bayi/müşteri/tedarikçi doğru
    // mu"): Bu filtre SADECE musteriTipi'ne bakıyordu, cariTipi'ni hiç
    // kontrol etmiyordu — saf bir TEDARİKÇİ'nin musteriTipi'si
    // (yanlışlıkla veya eski veriden) "Bayi"/"Toptan" ise, mantıksız
    // şekilde bu listede görünüyordu (bir tedarikçiye toptan satış
    // yapılmaz, ondan mal alınır). Artık cari gerçekten müşteri
    // olabiliyorsa (Müşteri veya Hem Müşteri Hem Tedarikçi) dahil
    // ediliyor.
    final bayiler = tumCariler.where((c) =>
        c.cariTipi.contains('Müşteri') &&
        (c.musteriTipi == 'Bayi' || c.musteriTipi == 'Toptan')).toList()
      ..sort((a, b) => a.unvan.compareTo(b.unvan));

    double bugunCiro = 0;
    try {
      final db = await Veritabani().db;
      final bugun = DateTime.now();
      final baslangic = DateTime(bugun.year, bugun.month, bugun.day).toIso8601String();
      final res = await db.rawQuery(
        "SELECT COALESCE(SUM(genel_toplam),0) AS toplam FROM satislar "
        "WHERE fis_tipi = 'Toptan Satış' AND iptal = 0 AND tarih >= ?",
        [baslangic],
      );
      bugunCiro = (res.first['toplam'] as num?)?.toDouble() ?? 0;
    } catch (_) { /* ciro okunamadı — 0 gösterilir, ekran yine de açılır */ }

    if (!mounted) return;
    setState(() {
      _bayiler = bayiler;
      _filtreli = bayiler;
      _bugunkuToptanCiro = bugunCiro;
      _yukleniyor = false;
    });
  }

  void _filtrele() {
    final q = _aramaCtrl.text.trim().toLowerCase();
    setState(() {
      _filtreli = q.isEmpty
          ? _bayiler
          : _bayiler.where((c) => c.unvan.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _paneliAc(CariModel cari) async {
    await cariDetayPaneliAc(context, cari);
    _yukle(); // panel kapandıktan sonra (satış/iade yapılmış olabilir) tazele
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 150,
          pinned: true,
          // ══════════════════════════════════════════════════════════════
          // 🔴 DÜZELTME (kullanıcı bulgusu — "ikonlar gözükmüyor")
          //
          // Bu ekran SliverAppBar kullandığı için 11. turdaki
          // AppBar→TsAppBar dönüşümünden KAÇMIŞTI ve iki ayrı hata
          // taşıyordu:
          //
          // 1) backgroundColor / foregroundColor / iconTheme HİÇ
          //    verilmemişti. `actions:` içindeki IconButton'lar temanın
          //    varsayılanını kullanıyordu:
          //      acik_tema.dart → actionsIconTheme: AppRenkler.primary
          //                       (#4361EE, indigo)
          //    Bu indigo ikonlar kahverengi gradyanın üstünde
          //    çiziliyordu. Ölçülen kontrast:
          //      #4361EE / #6D4C41  →  1.52:1
          //      #4361EE / #4E342E  →  2.26:1
          //    WCAG ikon/UI bileşeni minimumu 3:1 — yani ikonlar
          //    gerçekten görünmüyordu.
          //
          // 2) Gradyan MASA modülünün kahverengisiydi (#4E342E→#6D4C41).
          //    Burası toptan satış ekranı, restoranla ilgisi yok —
          //    11. turda fiyat_gruplari_ekrani'nda düzelttiğim
          //    kopyala-yapıştır hatasının aynısı.
          //
          // Artık TsModulRenk.ana kullanılıyor (TsAppBar'la aynı kaynak)
          // ve zemin/ön plan açıkça veriliyor. Beyaz ikon / ana gradyan
          // kontrastı: 5.02:1 – 11.92:1.
          //
          // backgroundColor ayrıca ZORUNLU: `pinned: true` olduğu için
          // kullanıcı kaydırınca bar daralıyor, gradyanlı `background`
          // kayboluyor ve geriye AppBar'ın kendi zemini kalıyor.
          // Verilmezse o an temanın açık `surface` rengine düşerdi.
          // ══════════════════════════════════════════════════════════════
          backgroundColor: TsModulRenk.koyu(TsModul.ana),
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: FlexibleSpaceBar(
            title: const Text('Toptan Satış',
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            background: DecoratedBox(
              decoration: BoxDecoration(
                gradient: TsModulRenk.gradyan(TsModul.ana),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 56, 16, 12),
                  child: Row(children: [
                    Expanded(child: _kpiKart('Bayi Sayısı', '${_bayiler.length}', Icons.storefront)),
                    const SizedBox(width: 10),
                    Expanded(child: _kpiKart('Bugünkü Toptan Ciro', ParaUtils.formatla(_bugunkuToptanCiro), Icons.trending_up)),
                  ]),
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Toptan Ürünler',
              onPressed: () => context.push('/toptan/urunler'),
            ),
            IconButton(
              icon: const Icon(Icons.pending_actions_outlined),
              tooltip: 'Bekleyen Siparişler',
              onPressed: () => context.push('/toptan/bekleyen-siparisler'),
            ),
            IconButton(
              icon: const Icon(Icons.storefront_outlined),
              tooltip: 'Fiyat Grupları',
              onPressed: () => context.push('/toptan/fiyat-gruplari'),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _aramaCtrl,
              decoration: InputDecoration(
                hintText: 'Bayi ara...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true, fillColor: context.inputFill,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ),
        ),
        if (_yukleniyor)
          const SliverFillRemaining(child: const TsYukleniyor())
        else if (_filtreli.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.storefront_outlined, size: 56, color: context.textHint),
                  const SizedBox(height: 12),
                  Text(_bayiler.isEmpty ? 'Henüz "Bayi/Toptan" tipinde cari yok' : 'Eşleşen bayi bulunamadı',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: context.textSecondary)),
                  if (_bayiler.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Cari kartından müşteri tipini "Bayi" veya "Toptan" yapın',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: context.textHint)),
                  ],
                ]),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (c, i) {
                  final bayi = _filtreli[i];
                  final limitAsimi = bayi.limitTutari > 0 && bayi.bakiye > bayi.limitTutari;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: context.cardBg, borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4)],
                    ),
                    child: ListTile(
                      onTap: () => _paneliAc(bayi),
                      leading: CircleAvatar(
                        backgroundColor: AppRenkler.primary.withAlpha(30),
                        child: Text(bayi.unvan.isNotEmpty ? bayi.unvan[0].toUpperCase() : '?',
                            style: const TextStyle(color: AppRenkler.primary, fontWeight: FontWeight.w700)),
                      ),
                      title: Text(bayi.unvan, style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
                      subtitle: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: AppRenkler.primary.withAlpha(25), borderRadius: BorderRadius.circular(6)),
                          child: Text(bayi.musteriTipi, style: const TextStyle(fontSize: 10, color: AppRenkler.primary, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        Text('Bakiye: ${ParaUtils.formatla(bayi.bakiye)}',
                            style: TextStyle(fontSize: 12, color: limitAsimi ? Colors.red : context.textSecondary,
                                fontWeight: limitAsimi ? FontWeight.w700 : FontWeight.normal)),
                      ]),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
                childCount: _filtreli.length,
              ),
            ),
          ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToptanSatisEkrani())),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Hızlı Toptan Satış'),
      ),
    );
  }

  Widget _kpiKart(String baslik, String deger, IconData ikon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withAlpha(28), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ikon, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Expanded(child: Text(baslik, style: const TextStyle(fontSize: 10.5, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Text(deger, style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w800)),
        ]),
      );
}
