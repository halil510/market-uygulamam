// lib/ekranlar/ai/ai_panel_ekrani.dart ✅ TAM YAZILDI
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../servisler/ai_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/ortak/mikrofon_butonu.dart';

class AiPanelEkrani extends ConsumerStatefulWidget {
  const AiPanelEkrani({super.key});
  @override
  ConsumerState<AiPanelEkrani> createState() => _AiPanelEkraniState();
}

class _AiPanelEkraniState extends ConsumerState<AiPanelEkrani>
    with SingleTickerProviderStateMixin {
  final AiServisi _ai = AiServisi();
  late TabController _tab;
  bool _yukleniyor = true;

  Map<String, dynamic> _gunlukOzet = {};
  Map<String, double> _tahmin = {};
  List<Map<String, dynamic>> _stokOnerisi = [];
  List<Map<String, dynamic>> _promosyon = [];
  List<Map<String, dynamic>> _enCokSatan = [];
  List<Map<String, dynamic>> _cariRisk = [];

  final _fmt = NumberFormat('#,##0.00 ₺', 'tr_TR');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final results = await Future.wait([
        _ai.gunlukOzet(),
        _ai.satisTahmini(),
        _ai.stokOnerisi(),
        _ai.promosyonOnerisi(),
        _ai.enCokSatanlar(),
        _ai.cariRisk(),
      ]);
      if (!mounted) return;
      setState(() {
        _gunlukOzet = results[0] as Map<String, dynamic>;
        _tahmin     = results[1] as Map<String, double>;
        _stokOnerisi = results[2] as List<Map<String, dynamic>>;
        _promosyon   = results[3] as List<Map<String, dynamic>>;
        _enCokSatan  = results[4] as List<Map<String, dynamic>>;
        _cariRisk    = results[5] as List<Map<String, dynamic>>;
        _yukleniyor  = false;
      });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
      if (kDebugMode) debugPrint('AI panel yukle: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Akıllı Analiz',
        aksiyonlar: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _yukle)],
        alt: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
          Tab(icon: Icon(Icons.dashboard), text: 'Özet'),
          Tab(icon: Icon(Icons.inventory_2), text: 'Stok'),
          Tab(icon: Icon(Icons.local_offer), text: 'Promosyon'),
          Tab(icon: Icon(Icons.people), text: 'Cari Risk'),
          Tab(icon: Icon(Icons.chat), text: 'AI Chat'),
        ]),
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : TabBarView(controller: _tab, children: [
              _OzetTab(ozet: _gunlukOzet, tahmin: _tahmin, enCokSatan: _enCokSatan),
              _StokTab(oneriler: _stokOnerisi),
              _PromosyonTab(oneriler: _promosyon),
              _CariRiskTab(riskler: _cariRisk),
              _AiChatTab(ai: _ai),
            ]),
    );
  }
}

// ── OZET TAB ────────────────────────────────────────────────────────────────
class _OzetTab extends StatelessWidget {
  final Map<String, dynamic> ozet;
  final Map<String, double> tahmin;
  final List<Map<String, dynamic>> enCokSatan;

  const _OzetTab({required this.ozet, required this.tahmin, required this.enCokSatan});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Bugun
      const _SectionTitle('Bugünkü Performans', Icons.today),
      Row(children: [
        Expanded(child: _StatKart('Satış Sayısı', '${ozet['satis_sayisi'] ?? 0}', Icons.shopping_cart, TsRenk.primary)),
        const SizedBox(width: 12),
        Expanded(child: _StatKart('Ciro', ParaUtils.formatla((ozet['ciro'] as num?)?.toDouble() ?? 0), Icons.trending_up, TsRenk.basarili)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _StatKart('Ort. Sepet', ParaUtils.formatla((ozet['ortalama_sepet'] as num?)?.toDouble() ?? 0), Icons.receipt_long, Colors.blue)),
        const SizedBox(width: 12),
        Expanded(child: _StatKart('Kritik Stok', '${ozet['kritik_stok'] ?? 0} ürün', Icons.warning_amber, TsRenk.uyari)),
      ]),
      const SizedBox(height: 20),

      // Tahmin
      const _SectionTitle('30 Gün Satış Tahmini', Icons.auto_graph),
      Container(decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        _TahminSatir('Yarın', tahmin['yarin'] ?? 0),
        _TahminSatir('Bu Hafta', tahmin['bu_hafta'] ?? 0),
        _TahminSatir('Bu Ay', tahmin['bu_ay'] ?? 0),
      ]))),
      const SizedBox(height: 20),

      // En cok satan
      if (enCokSatan.isNotEmpty) ...[
        const _SectionTitle('En Çok Satan Ürünler (30 Gün)', Icons.star),
        Container(decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))), child: Column(children: enCokSatan.asMap().entries.map((e) {
          final i = e.key;
          final r = e.value;
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: TsRenk.primary,
              child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            title: Text(r['urun_adi'] as String? ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${(r['toplam_adet'] as num?)?.toStringAsFixed(0) ?? 0} adet', style: TsMetin.kucukVurgu.copyWith(color: TsRenk.primary)),
              Text(ParaUtils.formatla((r['toplam_tutar'] as num?)?.toDouble() ?? 0), style: TextStyle(fontSize: 11, color: context.textSecondary)),
            ]),
          );
        }).toList())),
      ],
    ]);
  }
}

// ── STOK TAB ────────────────────────────────────────────────────────────────
class _StokTab extends StatelessWidget {
  final List<Map<String, dynamic>> oneriler;
  const _StokTab({required this.oneriler});

  @override
  Widget build(BuildContext context) {
    if (oneriler.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_outline, size: 64, color: TsRenk.basarili),
        const SizedBox(height: 12),
        const Text('Tüm stoklar yeterli seviyede!', style: TextStyle(fontSize: 16)),
      ]));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      _SectionTitle('Yenileme Gereken Ürünler (${oneriler.length})', Icons.warning_amber),
      ...oneriler.map((r) {
        final acil = r['acil'] as bool? ?? false;
        final stok = (r['stok'] as num?)?.toDouble() ?? 0;
        final minStok = (r['minimum_stok'] as num?)?.toDouble() ?? 0;
        final oneri = (r['oneri_miktar'] as num?)?.toDouble() ?? 0;
        return Container(
          decoration: BoxDecoration(
            color: acil ? TsRenk.zemin(TsRenk.hata, opaklik: 0.08) : TsRenk.kart(context),
            borderRadius: BorderRadius.circular(TsRadius.lg),
            border: Border.all(color: TsRenk.ayirac(context))),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(acil ? Icons.error : Icons.warning_amber,
                color: acil ? TsRenk.hata : TsRenk.uyari),
            title: Text(r['urun_adi'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mevcut: $stok | Min: $minStok | 30g Satış: ${(r['son30gun_satis'] as num?)?.toStringAsFixed(0) ?? 0}', style: const TextStyle(fontSize: 11)),
              LinearProgressIndicator(
                value: minStok > 0 ? (stok / minStok).clamp(0.0, 1.0) : 0,
                backgroundColor: TsRenk.ayirac(context),
                valueColor: AlwaysStoppedAnimation<Color>(acil ? TsRenk.hata : TsRenk.uyari),
              ),
            ]),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: TsRenk.zemin(TsRenk.primary), borderRadius: BorderRadius.circular(12)),
              child: Text('${oneri.toStringAsFixed(0)} al', style: const TextStyle(fontWeight: FontWeight.w700, color: TsRenk.primary)),
            ),
          ),
        );
      }),
    ]);
  }
}

// ── PROMOSYON TAB ────────────────────────────────────────────────────────────
class _PromosyonTab extends StatelessWidget {
  final List<Map<String, dynamic>> oneriler;
  const _PromosyonTab({required this.oneriler});

  @override
  Widget build(BuildContext context) {
    if (oneriler.isEmpty) {
      return const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Promosyon önerisi bulunamadı');
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      _SectionTitle('Promosyon Önerileri (${oneriler.length})', Icons.local_offer),
      Text('Bu ürünlerin satışları düşük veya stoklar fazla. İndirim yapmak satışları artırabilir.',
          style: TextStyle(fontSize: 12, color: context.textSecondary)),
      const SizedBox(height: 12),
      ...oneriler.map((r) {
        final fiyat = (r['satis_fiyati'] as num?)?.toDouble() ?? 0;
        final indirimli = (r['indirimli_fiyat'] as num?)?.toDouble() ?? 0;
        return Container(
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.local_offer, color: Colors.purple),
            title: Text(r['urun_adi'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(
              'Stok: ${(r['stok'] as num?)?.toStringAsFixed(0) ?? 0} | 30g Satış: ${(r['satis_adet'] as num?)?.toStringAsFixed(0) ?? 0}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(ParaUtils.formatla(fiyat), style: TextStyle(decoration: TextDecoration.lineThrough, fontSize: 11, color: context.textSecondary)),
              Text(ParaUtils.formatla(indirimli), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.purple, fontSize: 13)),
              const Text('%10 indirim', style: TextStyle(fontSize: 10, color: Colors.purple)),
            ]),
          ),
        );
      }),
    ]);
  }
}

// ── CARI RISK TAB ────────────────────────────────────────────────────────────
class _CariRiskTab extends StatelessWidget {
  final List<Map<String, dynamic>> riskler;
  const _CariRiskTab({required this.riskler});

  @override
  Widget build(BuildContext context) {
    if (riskler.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.shield_outlined, size: 64, color: TsRenk.basarili),
        const SizedBox(height: 12),
        const Text('Limit aşımı tespit edilmedi', style: TextStyle(fontSize: 16)),
      ]));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      _SectionTitle('Limit Riski Olan Cariler (${riskler.length})', Icons.warning),
      ...riskler.map((r) {
        final bakiye = (r['bakiye'] as num?)?.toDouble() ?? 0;
        final limit = (r['limit_tutari'] as num?)?.toDouble() ?? 0;
        final doluluk = (r['limit_doluluk'] as num?)?.toDouble() ?? 0;
        return Container(
          decoration: BoxDecoration(
            color: doluluk >= 100 ? TsRenk.zemin(TsRenk.hata, opaklik: 0.08) : TsRenk.zemin(TsRenk.uyari, opaklik: 0.08),
            borderRadius: BorderRadius.circular(TsRadius.lg),
            border: Border.all(color: TsRenk.ayirac(context))),
          margin: const EdgeInsets.only(bottom: TsBosluk.sm),
          child: ListTile(
            leading: Icon(doluluk >= 100 ? Icons.error : Icons.warning_amber,
                color: doluluk >= 100 ? TsRenk.hata : TsRenk.uyari),
            title: Text(r['unvan'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bakiye: ${ParaUtils.formatla(bakiye)} | Limit: ${ParaUtils.formatla(limit)}', style: const TextStyle(fontSize: 11)),
              LinearProgressIndicator(
                value: (doluluk / 100).clamp(0.0, 1.0),
                backgroundColor: TsRenk.ayirac(context),
                valueColor: AlwaysStoppedAnimation<Color>(doluluk >= 100 ? TsRenk.hata : TsRenk.uyari),
              ),
            ]),
            trailing: Text('%${doluluk.toStringAsFixed(0)}',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16,
                    color: doluluk >= 100 ? TsRenk.hata : TsRenk.uyari)),
            onTap: () => context.push('/cari/detay/${r['id']}'),
          ),
        );
      }),
    ]);
  }
}

// ── YARDIMCI WİDGETLAR ──────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String baslik;
  final IconData ikon;
  const _SectionTitle(this.baslik, this.ikon);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Icon(ikon, size: 18, color: TsRenk.primary),
      const SizedBox(width: 6),
      Expanded(child: Text(baslik,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          overflow: TextOverflow.ellipsis)),
    ]),
  );
}

class _StatKart extends StatelessWidget {
  final String baslik, deger;
  final IconData ikon;
  final Color renk;
  const _StatKart(this.baslik, this.deger, this.ikon, this.renk);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(TsBosluk.md),
    decoration: BoxDecoration(
      color: TsRenk.zemin(renk, opaklik: 0.08),
      borderRadius: BorderRadius.circular(TsRadius.lg),
      border: Border.all(color: TsRenk.zemin(renk, opaklik: 0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(ikon, color: renk, size: 16), const SizedBox(width: 6), Expanded(child: Text(baslik, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)), overflow: TextOverflow.ellipsis))]),
      const SizedBox(height: 6),
      Text(deger, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: renk)),
    ]),
  );
}

class _TahminSatir extends StatelessWidget {
  final String etiket;
  final double deger;
  const _TahminSatir(this.etiket, this.deger);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(etiket, style: const TextStyle(fontSize: 14)),
      Text(ParaUtils.formatla(deger), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: TsRenk.primary)),
    ]),
  );
}

// ── AI Chat Sekmesi ───────────────────────────────────────────────────────
class _AiChatTab extends ConsumerStatefulWidget {
  final AiServisi ai;
  const _AiChatTab({required this.ai});
  @override
  ConsumerState<_AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends ConsumerState<_AiChatTab> {
  final _ctrl    = TextEditingController();
  final _scroll  = ScrollController();
  final _mesajlar = <Map<String, dynamic>>[];
  bool _bekliyor = false;

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _sor() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _bekliyor) return;
    _ctrl.clear();
    setState(() {
      _mesajlar.add({'tip': 'kullanici', 'metin': q});
      _bekliyor = true;
    });
    _scrollaSon();
    try {
      final sonuc = await widget.ai.sor(q);
      if (!mounted) return;
      setState(() {
        _mesajlar.add({'tip': 'ai', 'metin': sonuc.cevap});
        _bekliyor = false;
      });
      _scrollaSon();
      // ÖNCEDEN: AI Chat sadece metin cevap veriyordu, "ürün listesi X'e
      // git" gibi komutlar hiçbir yere yönlendirmiyordu. Artık sonuç bir
      // rota içeriyorsa GERÇEKTEN o ekrana gidiliyor (varsa arama
      // terimiyle birlikte).
      // ÖNCEDEN BURADA CİDDİ BİR GEZİNME HATASI VARDI: AI Chat ekranı
      // (`/ai`) rootNavigatorKey ile shell'in DIŞINDA çalışıyor, ama
      // `/urun`/`/cari`/`/satis` gibi rotalar shell'in İÇİNDEKİ sekme
      // kökleri. Shell-dışı bir context'ten shell-içi bir rotaya
      // `context.push()` ile gidilirse GoRouter'ın shell/branch durumu
      // tutarsız kalıyor ve BEYAZ EKRAN'a yol açıyordu. Düzeltme: hedef
      // bir sekme köküyse `context.go()` (konumu düzgün yeniden kurar),
      // değilse `context.push()` (geri tuşu çalışan normal ekran)
      // kullanılıyor.
      if (sonuc.rota != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        const sekmeKokleri = {'/', '/satis', '/urun', '/cari'};
        if (sekmeKokleri.contains(sonuc.rota)) {
          context.go(sonuc.rota!, extra: sonuc.aramaTerimi);
        } else {
          context.push(sonuc.rota!, extra: sonuc.aramaTerimi);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mesajlar.add({'tip': 'ai', 'metin': 'Hata: $e'});
        _bekliyor = false;
      });
    }
  }

  void _scrollaSon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  static const _hizliSorular = [
    'Z raporu',
    'Ürün Z raporu',
    'Bu aylık rapor',
    'Bu ayın net karı',
    'Geçen ay net karı',
    'Bu hafta ciro',
    'Kritik stoklar',
    'Genel stok durumu',
    'En çok satan 10 ürün',
    'En karlı ürünler',
    'Gruplar neler kaç ürün',
    'Bu ay kategori raporu',
    'Bu hafta marka raporu',
    'Kasa durumu',
    'Borçlu müşteriler',
    'Stok değeri',
    '7 günlük tahmin',
    'Sipariş önerileri',
    'Kârım neden düştü',
    'Anormal işlem var mı',
    'Stok ne zaman tükenir',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Hızlı soru butonları
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          children: _hizliSorular.map((s) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(s, style: const TextStyle(fontSize: 12)),
              onPressed: () { _ctrl.text = s; _sor(); },
            ),
          )).toList(),
        ),
      ),
      // Mesajlar
      Expanded(
        child: _mesajlar.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.smart_toy_outlined, size: 56, color: TsRenk.ayirac(context)),
                const SizedBox(height: 12),
                Text('AI Asistanınıza soru sorun',
                    style: TextStyle(color: TsRenk.metinIkincil(context))),
                const SizedBox(height: 4),
                Text('"Z raporu", "Net kâr", "Kritik stok"...',
                    style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 12)),
              ]))
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _mesajlar.length + (_bekliyor ? 1 : 0),
                itemBuilder: (_, i) {
                  if (_bekliyor && i == _mesajlar.length) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 40, height: 20,
                            child: LinearProgressIndicator()),
                      ),
                    );
                  }
                  final m   = _mesajlar[i];
                  final isAi = m['tip'] == 'ai';
                  return Align(
                    alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.85),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isAi
                            ? context.cardBg
                            : Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.only(
                          topLeft:     const Radius.circular(16),
                          topRight:    const Radius.circular(16),
                          bottomLeft:  Radius.circular(isAi ? 2 : 16),
                          bottomRight: Radius.circular(isAi ? 16 : 2),
                        ),
                        boxShadow: [BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: SelectableText(
                        m['metin'] ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: isAi ? context.textPrimary : Colors.white,
                          fontFamily: isAi ? 'monospace' : null,
                          height: 1.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      // Giriş alanı
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: TsRenk.kart(context),
          boxShadow: [BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              onSubmitted: (_) => _sor(),
              decoration: InputDecoration(
                hintText: 'Soru sorun veya mikrofona konuşun...',
                filled: true,
                fillColor: TsRenk.arkaplan(context),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                isDense: true,
                suffixIcon: MikrofonButonu(
                  ipucu: 'Sorunuzu söyleyin',
                  onMetin: (metin) {
                    _ctrl.text = metin;
                    _sor();
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _bekliyor ? null : _sor,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
            child: const Icon(Icons.send, size: 20),
          ),
        ]),
      ),
    ]);
  }
}
