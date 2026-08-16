// lib/ekranlar/satis/hizli_tus_yonetim_ekrani.dart
//
// 🆕 YENİ EKRAN — HIZLI TUŞ YÖNETİMİ
//
// İki sekme:
//   1) Tuşlarım  → mevcut hızlı tuşlar, sürükle-bırak ile sıralama,
//                  kaydırarak silme
//   2) Ürün Ekle → arama ile ürün bulup tuş olarak ekleme
//
// Ayrıca "en çok satılanlardan doldur" kısayolu var — ilk kurulumda
// kullanıcı sıfırdan tuş dizmek zorunda kalmasın diye.
//
// TASARIM: tamamen tasarim_sistemi (TsAppBar/TsRenk/TsBosluk) + tema
// uzantıları ile yazıldı — sabit renk yok, koyu temada doğru görünür.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modeller/urun_model.dart';
import '../../depolar/favori_urun_deposu.dart';
import '../../depolar/urun_deposu.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../cekirdek/utils/para_utils.dart';
import 'widgets/hizli_tus_paneli.dart' show tusRengi;

class HizliTusYonetimEkrani extends ConsumerStatefulWidget {
  const HizliTusYonetimEkrani({super.key});

  @override
  ConsumerState<HizliTusYonetimEkrani> createState() =>
      _HizliTusYonetimEkraniState();
}

class _HizliTusYonetimEkraniState extends ConsumerState<HizliTusYonetimEkrani>
    with SingleTickerProviderStateMixin {
  final _favoriDepo = FavoriUrunDeposu();
  final _urunDepo = UrunDeposu();

  late final TabController _tab;
  final _aramaCtrl = TextEditingController();
  Timer? _aramaGecikme;

  List<UrunModel> _favoriler = [];
  List<UrunModel> _aramaSonuc = [];
  Set<int> _favoriIdler = {};

  bool _yukleniyor = true;
  bool _araniyor = false;
  bool _degisiklikVar = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _yukle();
  }

  @override
  void dispose() {
    _tab.dispose();
    _aramaCtrl.dispose();
    _aramaGecikme?.cancel();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final liste = await _favoriDepo.favorileriGetir();
      final idler = await _favoriDepo.favoriIdleri();
      if (!mounted) return;
      setState(() {
        _favoriler = liste;
        _favoriIdler = idler;
        _yukleniyor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // ── Arama (debounce'lu — her tuşta sorgu atılmaz) ──────────────────────
  void _aramaDegisti(String q) {
    _aramaGecikme?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _aramaSonuc = [];
        _araniyor = false;
      });
      return;
    }
    setState(() => _araniyor = true);
    _aramaGecikme = Timer(const Duration(milliseconds: 320), () async {
      try {
        final r = await _urunDepo.ara(q.trim(), limit: 60);
        if (!mounted) return;
        setState(() {
          _aramaSonuc = r;
          _araniyor = false;
        });
      } catch (_) {
        if (mounted) setState(() => _araniyor = false);
      }
    });
  }

  // ── İşlemler ───────────────────────────────────────────────────────────
  Future<void> _tusEkle(UrunModel u) async {
    if (u.id == null) return;
    await _favoriDepo.ekle(u.id!);
    _degisiklikVar = true;
    await _yukle();
    if (!mounted) return;
    BildirimServisi.basari(context, '${u.urunAdi} hızlı tuşlara eklendi');
  }

  Future<void> _tusCikar(UrunModel u) async {
    if (u.id == null) return;
    await _favoriDepo.cikar(u.id!);
    _degisiklikVar = true;
    await _yukle();
    if (!mounted) return;
    BildirimServisi.uyari(context, '${u.urunAdi} tuşlardan çıkarıldı');
  }

  Future<void> _siraDegisti(int eski, int yeni) async {
    // ReorderableListView semantiği: hedef index, eleman çıkarılmadan
    // ÖNCEKİ listeye göre gelir — aşağı taşımada 1 düşülmeli.
    if (yeni > eski) yeni -= 1;
    setState(() {
      final tasinan = _favoriler.removeAt(eski);
      _favoriler.insert(yeni, tasinan);
    });
    _degisiklikVar = true;
    await _favoriDepo.sirayiKaydet(
        _favoriler.map((e) => e.id!).where((e) => e > 0).toList());
  }

  Future<void> _encokSatilandanDoldur() async {
    final oneri = await _favoriDepo.encokSatilanOneri(limit: 12);
    if (!mounted) return;
    if (oneri.isEmpty) {
      BildirimServisi.uyari(
          context, 'Henüz satış geçmişi yok — öneri oluşturulamadı');
      return;
    }
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: const Text('En çok satılanlardan doldur',
            style: TsMetin.baslikM),
        content: Text(
          'Satış geçmişine göre en çok satılan ${oneri.length} ürün '
          'hızlı tuşlara eklenecek.\n\n'
          '${oneri.take(6).map((e) => '• ${e.urunAdi}').join('\n')}'
          '${oneri.length > 6 ? '\n• …' : ''}',
          style: TsMetin.kucuk,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ekle')),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    for (final u in oneri) {
      if (u.id != null) await _favoriDepo.ekle(u.id!);
    }
    _degisiklikVar = true;
    await _yukle();
    if (!mounted) return;
    BildirimServisi.basari(context, '${oneri.length} tuş eklendi');
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _degisiklikVar);
      },
      child: Scaffold(
        backgroundColor: context.scaffoldBg,
        appBar: TsAppBar(
        baslik: 'Hızlı Tuşlar',
        alt: TabBar(
            controller: _tab,
            tabs: [
              Tab(text: 'Tuşlarım (${_favoriler.length})'),
              const Tab(text: 'Ürün Ekle'),
            ],
          ),
        lider: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _degisiklikVar),
          ),
        gradyanli: false,
      ),
        body: _yukleniyor
            ? const Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: TsRenk.primary))
            : TabBarView(
                controller: _tab,
                children: [_tuslarimSekmesi(), _urunEkleSekmesi()],
              ),
      ),
    );
  }

  // ── Sekme 1: Tuşlarım ──────────────────────────────────────────────────
  Widget _tuslarimSekmesi() {
    if (_favoriler.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(TsBosluk.xxl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                  color: TsRenk.zemin(TsRenk.primary), shape: BoxShape.circle),
              child: const Icon(Icons.bolt_rounded,
                  size: 38, color: TsRenk.primary),
            ),
            const SizedBox(height: TsBosluk.lg),
            Text('Henüz tuş yok',
                style: TsMetin.baslikM.copyWith(color: context.textPrimary)),
            const SizedBox(height: TsBosluk.sm),
            Text(
              '"Ürün Ekle" sekmesinden ürün seçin ya da satış '
              'geçmişinizden otomatik doldurun.',
              textAlign: TextAlign.center,
              style: TsMetin.kucuk
                  .copyWith(color: context.textSecondary, height: 1.45),
            ),
            const SizedBox(height: TsBosluk.xl),
            OutlinedButton.icon(
              onPressed: _encokSatilandanDoldur,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('En çok satılanlardan doldur'),
              style: OutlinedButton.styleFrom(
                foregroundColor: TsRenk.primary,
                side: const BorderSide(color: TsRenk.primary),
                padding: const EdgeInsets.symmetric(
                    horizontal: TsBosluk.xl, vertical: TsBosluk.md),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(TsRadius.md)),
              ),
            ),
          ]),
        ),
      );
    }

    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            horizontal: TsBosluk.lg, vertical: TsBosluk.sm),
        color: TsRenk.zemin(TsRenk.bilgi, opaklik: 0.10),
        child: Row(children: [
          const Icon(Icons.drag_indicator_rounded,
              size: 16, color: TsRenk.bilgi),
          const SizedBox(width: TsBosluk.sm),
          Expanded(
            child: Text(
              'Sürükleyerek sırayı değiştirin — kasadaki tuş düzeni bu sıraya göre olur.',
              style: TsMetin.kucuk.copyWith(color: context.textSecondary),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(
              TsBosluk.md, TsBosluk.md, TsBosluk.md, TsBosluk.xxxl),
          itemCount: _favoriler.length,
          onReorder: _siraDegisti,
          itemBuilder: (_, i) {
            final u = _favoriler[i];
            final renk = tusRengi(u.urunAdi);
            return Container(
              key: ValueKey('favori_${u.id}'),
              margin: const EdgeInsets.only(bottom: TsBosluk.sm),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(TsRadius.md),
                border: Border.all(color: context.borderColor),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(TsRadius.md)),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: renk.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(TsRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Text('${i + 1}',
                      style: TsMetin.govdeVurgu.copyWith(color: renk)),
                ),
                title: Text(u.urunAdi,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TsMetin.govdeVurgu
                        .copyWith(color: context.textPrimary)),
                subtitle: Text(
                  '${ParaUtils.formatla(u.satisFiyati)} • ${u.birimAdi}'
                  '${u.barkod?.isNotEmpty == true ? ' • ${u.barkod}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TsMetin.kucuk.copyWith(color: context.textSecondary),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded,
                        color: TsRenk.hata, size: 22),
                    tooltip: 'Tuşlardan çıkar',
                    onPressed: () => _tusCikar(u),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: Icon(Icons.drag_handle_rounded,
                        color: context.textHint),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ── Sekme 2: Ürün Ekle ─────────────────────────────────────────────────
  Widget _urunEkleSekmesi() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(TsBosluk.md),
        child: TextField(
          controller: _aramaCtrl,
          onChanged: _aramaDegisti,
          autofocus: false,
          style: TsMetin.govde.copyWith(color: context.textPrimary),
          decoration: InputDecoration(
            hintText: 'Ürün adı, barkod veya kod ile ara…',
            hintStyle: TsMetin.govde.copyWith(color: context.textHint),
            prefixIcon: Icon(Icons.search_rounded, color: context.textSecondary),
            suffixIcon: _aramaCtrl.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.clear_rounded, color: context.textSecondary),
                    onPressed: () {
                      _aramaCtrl.clear();
                      _aramaDegisti('');
                    },
                  ),
            filled: true,
            fillColor: context.inputFill,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: TsBosluk.lg, vertical: TsBosluk.md),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TsRadius.md),
              borderSide: BorderSide(color: context.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TsRadius.md),
              borderSide: BorderSide(color: context.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TsRadius.md),
              borderSide: const BorderSide(color: TsRenk.primary, width: 1.5),
            ),
          ),
        ),
      ),
      if (_aramaCtrl.text.trim().length < 2)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TsBosluk.lg),
          child: OutlinedButton.icon(
            onPressed: _encokSatilandanDoldur,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('En çok satılanlardan doldur'),
            style: OutlinedButton.styleFrom(
              foregroundColor: TsRenk.primary,
              side: const BorderSide(color: TsRenk.primary),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(TsRadius.md)),
            ),
          ),
        ),
      Expanded(
        child: _araniyor
            ? const Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: TsRenk.primary))
            : _aramaSonuc.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(TsBosluk.xxl),
                      child: Text(
                        _aramaCtrl.text.trim().length < 2
                            ? 'Aramak için en az 2 harf yazın.'
                            : 'Eşleşen ürün bulunamadı.',
                        textAlign: TextAlign.center,
                        style: TsMetin.kucuk
                            .copyWith(color: context.textSecondary),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        TsBosluk.md, TsBosluk.sm, TsBosluk.md, TsBosluk.xxxl),
                    itemCount: _aramaSonuc.length,
                    itemBuilder: (_, i) {
                      final u = _aramaSonuc[i];
                      final ekli = u.id != null && _favoriIdler.contains(u.id);
                      final renk = tusRengi(u.urunAdi);
                      return Container(
                        margin: const EdgeInsets.only(bottom: TsBosluk.sm),
                        decoration: BoxDecoration(
                          color: context.cardBg,
                          borderRadius: BorderRadius.circular(TsRadius.md),
                          border: Border.all(
                              color: ekli
                                  ? TsRenk.basarili.withValues(alpha: 0.5)
                                  : context.borderColor),
                        ),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(TsRadius.md)),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: renk.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(TsRadius.sm),
                            ),
                            child: Icon(Icons.inventory_2_outlined,
                                color: renk, size: 20),
                          ),
                          title: Text(u.urunAdi,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TsMetin.govdeVurgu
                                  .copyWith(color: context.textPrimary)),
                          subtitle: Text(
                            '${ParaUtils.formatla(u.satisFiyati)} • ${u.birimAdi}',
                            style: TsMetin.kucuk
                                .copyWith(color: context.textSecondary),
                          ),
                          trailing: ekli
                              ? IconButton(
                                  icon: const Icon(
                                      Icons.check_circle_rounded,
                                      color: TsRenk.basarili),
                                  tooltip: 'Tuşlardan çıkar',
                                  onPressed: () => _tusCikar(u),
                                )
                              : IconButton(
                                  icon: const Icon(
                                      Icons.add_circle_outline_rounded,
                                      color: TsRenk.primary),
                                  tooltip: 'Hızlı tuşlara ekle',
                                  onPressed: () => _tusEkle(u),
                                ),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
