// lib/ekranlar/promosyon/promosyon_ekrani.dart
import 'package:flutter/foundation.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../saglayicilar/riverpod/promosyon_provider.dart';
import '../../modeller/promosyon_model.dart';
import '../../modeller/urun_model.dart';
import '../../depolar/promosyon_deposu.dart';
import '../../depolar/urun_deposu.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/barkod_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/ts_yetki.dart';

class PromosyonEkrani extends ConsumerStatefulWidget {
  const PromosyonEkrani({super.key});
  @override
  ConsumerState<PromosyonEkrani> createState() => _PromosyonEkraniState();
}

class _PromosyonEkraniState extends ConsumerState<PromosyonEkrani> {
  final _araCtrl = TextEditingController();
  static const _durumlar = ['Tümü', 'Aktif', 'Pasif', 'Süresi Dolmuş'];

  @override
  void initState() {
    super.initState();
    _araCtrl.addListener(() {
      ref.read(promosyonFiltresiProvider.notifier).aramaGuncelle(_araCtrl.text);
    });
  }

  @override
  void dispose() { _araCtrl.dispose(); super.dispose(); }

  Future<void> _aktiflikToggle(PromosyonModel p) async {
    try {  
      await PromosyonDeposu().aktiflikToggle(p.id!, !p.aktif);
      ref.invalidate(promosyonlarProvider);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _sil(PromosyonModel p) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Text('Promosyonu Sil'),
        content: Text('${p.promosyonAdi} silinecek. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay == true && mounted) {
      await PromosyonDeposu().sil(p.id!);
      ref.invalidate(promosyonlarProvider);
    }
  }

  Future<void> _promosyonDuzenle(PromosyonModel promo) async {
    final iskontoCtrl   = TextEditingController(text: promo.iskontoOran.toStringAsFixed(1));
    final minMiktarCtrl = TextEditingController(text: promo.minMiktar.toStringAsFixed(0));
    final adCtrl        = TextEditingController(text: promo.promosyonAdi);
    bool aktif          = promo.aktif;

    final sonuc = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(20, 20, 20,
            MediaQuery.of(ctx).viewInsets.bottom + 30),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: context.borderColor,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Text('Promosyon Düzenle',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ]),
          const SizedBox(height: 16),
          TextField(controller: adCtrl, decoration: const InputDecoration(
              labelText: 'Promosyon Adı', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: iskontoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'İskonto %',
                  border: OutlineInputBorder(), suffixText: '%'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: minMiktarCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Min. Miktar',
                  border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text('Aktif', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            value: aktif, onChanged: (v) => setS(() => aktif = v),
            dense: true, contentPadding: EdgeInsets.zero,
            activeColor: Colors.green),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Güncelle'))),
          ]),
        ]),
      )),
    );

    if (sonuc != true || !mounted) return;
    try {
      final guncellenmis = promo.copyWith(
        promosyonAdi: adCtrl.text.trim().isEmpty ? promo.promosyonAdi : adCtrl.text.trim(),
        iskontoOran: ParaUtils.sayiCoz(iskontoCtrl.text) ?? promo.iskontoOran,
        minMiktar:   ParaUtils.sayiCoz(minMiktarCtrl.text) ?? promo.minMiktar,
        aktif:       aktif,
      );
      await PromosyonDeposu().guncelle(guncellenmis);
      ref.invalidate(promosyonlarProvider);
      if (mounted) BildirimServisi.basari(context, 'Promosyon güncellendi ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<void> _promosyonEkleDialog() async {
    try {  
      final sonuc = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _PromosyonEkleSheet(),
      );
      if (sonuc == true) ref.invalidate(promosyonlarProvider);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtre = ref.watch(promosyonFiltresiProvider);
    final liste = ref.watch(filtreliPromosyonlarProvider);
    final async = ref.watch(promosyonlarProvider);
    final aktifSayisi = ref.watch(aktifPromosyonSayisiProvider);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Promosyonlar',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(promosyonlarProvider),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(children: [
            TextField(
              controller: _araCtrl,
              decoration: InputDecoration(
                hintText: 'Promosyon ara...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _araCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear),
                        onPressed: () { _araCtrl.clear(); ref.read(promosyonFiltresiProvider.notifier).aramaGuncelle(''); })
                    : null,
                filled: true, fillColor: context.borderColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _durumlar.map((d) {
                final secili = filtre.durum == d;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(d), selected: secili,
                    onSelected: (_) => ref.read(promosyonFiltresiProvider.notifier).durumAyarla(d),
                    selectedColor: AppRenkler.primary,
                    labelStyle: TextStyle(color: secili ? Colors.white : context.textSecondary, fontSize: 11),
                    backgroundColor: context.scaffoldBg, checkmarkColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList()),
            ),
          ]),
        ),
        if (async.hasValue)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              _Chip('$aktifSayisi Aktif', Colors.green.shade700),
              const SizedBox(width: 8),
              _Chip('${async.value!.length} Toplam', AppRenkler.primary),
            ]),
          ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: const AppYukleniyor()),
            error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Hata: $e', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => ref.invalidate(promosyonlarProvider), child: const Text('Tekrar Dene')),
            ])),
            data: (_) => liste.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.local_offer_outlined, size: 64, color: context.textHint),
                    const SizedBox(height: 12),
                    Text(_araCtrl.text.isNotEmpty ? 'Sonuç bulunamadı' : 'Promosyon yok',
                        style: TextStyle(color: context.textSecondary)),
                  ]))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: liste.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _PromosyonKarti(
                      promosyon: liste[i],
                      onToggle:   () => _aktiflikToggle(liste[i]),
                      onSil:      () => _sil(liste[i]),
                      onDuzenle:  () => _promosyonDuzenle(liste[i]),
                    ),
                  ),
          ),
        ),
      ]),
      floatingActionButton: TsYetkili(child: FloatingActionButton.extended(
        elevation: 6,
        onPressed: _promosyonEkleDialog,
        backgroundColor: AppRenkler.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.local_offer),
        label: const Text('Promosyon Ekle'),
      )),
    );
  }
}

// ── Promosyon Ekle Sheet ──────────────────────────────────────────────────────

class _PromosyonEkleSheet extends ConsumerStatefulWidget {
  const _PromosyonEkleSheet();
  @override
  ConsumerState<_PromosyonEkleSheet> createState() => _PromosyonEkleSheetState();
}

class _PromosyonEkleSheetState extends ConsumerState<_PromosyonEkleSheet> {
  final _formKey = GlobalKey<FormState>();
  final _adCtrl  = TextEditingController();
  final _oranCtrl = TextEditingController(text: '10');
  final _minMiktarCtrl  = TextEditingController(text: '1');
  final _araCtrl        = TextEditingController();
  final _indirimliCtrl  = TextEditingController();
  final _toplamCtrl     = TextEditingController(); // toplam tutar girişi
  Timer? _araDebounce;

  UrunModel? _seciliUrun;
  List<UrunModel> _aramaSonuclari = [];
  DateTime? _baslangic, _bitis;
  bool _kayit = false;

  @override
  void dispose() {
    _adCtrl.dispose(); _oranCtrl.dispose(); _minMiktarCtrl.dispose();
    _araCtrl.dispose(); _araDebounce?.cancel(); _indirimliCtrl.dispose(); _toplamCtrl.dispose();
    super.dispose();
  }

  void _aramaChanged(String q) {
    _araDebounce?.cancel();
    if (q.trim().length < 2) { setState(() => _aramaSonuclari = []); return; }
    _araDebounce = Timer(const Duration(milliseconds: 300), () async {
      final sonuclar = await UrunDeposu().ara(q.trim(), limit: 10);
      if (mounted) setState(() => _aramaSonuclari = sonuclar);
    });
  }

  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) return;
    if (_seciliUrun == null) {
      BildirimServisi.uyari(context, 'Ürün seçin');
      return;
    }
    setState(() => _kayit = true);
    try {
      await PromosyonDeposu().ekle(PromosyonModel(
        urunId:          _seciliUrun!.id!,
        urunAdi:         _seciliUrun!.urunAdi,
        promosyonAdi:    _adCtrl.text.trim(),
        iskontoOran:     double.tryParse(_oranCtrl.text.replaceAll(',', '.')) ?? 0,
        minMiktar:       double.tryParse(_minMiktarCtrl.text.replaceAll(',', '.')) ?? 1,
        baslangicTarihi: _baslangic,
        bitisTarihi:     _bitis,
        aktif:           true,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Yeni Promosyon',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),

          // Ürün arama
          TextFormField(
            controller: _araCtrl,
            decoration: InputDecoration(
              labelText: 'Ürün Ara *',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_seciliUrun != null)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                  tooltip: 'Barkod Tara',
                  onPressed: () async {
                    final b = await BarkodServisi().barkodTara(context);
                    if (b != null && mounted) {
                      _araCtrl.text = b;
                      _aramaChanged(b);
                    }
                  }),
              ]),
            ),
            onChanged: _aramaChanged,
          ),

          if (_seciliUrun != null) ...[
            Container(
              margin: const EdgeInsets.only(top: 6, bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.blue.shade50, Colors.green.shade50]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _HesapKutu('Normal Birim', ParaUtils.formatla(_seciliUrun!.satisFiyati), Colors.blue),
                  Icon(Icons.arrow_forward, size: 14, color: context.textSecondary),
                  _HesapKutu('İndirimli Birim',
                    _oranCtrl.text.isNotEmpty
                      ? ParaUtils.formatla(_seciliUrun!.satisFiyati * (1 - (ParaUtils.sayiCoz(_oranCtrl.text) ?? 0)/100))
                      : '—',
                    Colors.orange),
                  Icon(Icons.close, size: 14, color: context.textSecondary),
                  _HesapKutu('Min Miktar', _minMiktarCtrl.text.isEmpty ? '1' : _minMiktarCtrl.text, Colors.purple),
                  Icon(Icons.drag_handle, size: 14, color: context.textSecondary),
                  _HesapKutu('Toplam',
                    _toplamCtrl.text.isNotEmpty
                      ? ParaUtils.formatla(ParaUtils.sayiCoz(_toplamCtrl.text) ?? 0)
                      : '—',
                    Colors.green),
                ]),
                if (_oranCtrl.text.isNotEmpty && ParaUtils.sayiCoz(_oranCtrl.text) != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_minMiktarCtrl.text.isEmpty ? "1" : _minMiktarCtrl.text} adet alımda '
                    '%${_oranCtrl.text} indirim → '
                    '${_toplamCtrl.text.isNotEmpty ? ParaUtils.formatla(ParaUtils.sayiCoz(_toplamCtrl.text) ?? 0) : "—"} ödenecek',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade700,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ]),
            ),
          ],
          if (_seciliUrun != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200)),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_seciliUrun!.urunAdi,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                TextButton(onPressed: () => setState(() { _seciliUrun = null; _araCtrl.clear(); }),
                    child: const Text('Değiştir')),
              ]),
            ),

          if (_aramaSonuclari.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                  border: Border.all(color: context.borderColor),
                  borderRadius: BorderRadius.circular(12)),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _aramaSonuclari.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(_aramaSonuclari[i].urunAdi),
                  subtitle: Text(ParaUtils.formatla(_aramaSonuclari[i].satisFiyati)),
                  onTap: () => setState(() {
                    _seciliUrun = _aramaSonuclari[i];
                    _aramaSonuclari = [];
                    _araCtrl.text = _aramaSonuclari.isEmpty ? '' : _araCtrl.text;
                    if (_adCtrl.text.isEmpty)
                      _adCtrl.text = '${_seciliUrun!.urunAdi} İndirimi';
                  }),
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Promosyon adı
          TextFormField(
            controller: _adCtrl,
            decoration: const InputDecoration(
                labelText: 'Promosyon Adı *', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
          ),
          const SizedBox(height: 12),

          // İskonto % ↔ Toplam Tutar (iki yönlü)
          Row(children: [
            Expanded(child: TextFormField(
              controller: _oranCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(
                labelText: 'İskonto %', border: OutlineInputBorder(), suffixText: '%'),
              onChanged: (v) {
                if (_seciliUrun == null) return;
                final oran = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                if (oran > 0 && oran <= 100) {
                  final minMik = ParaUtils.sayiCoz(_minMiktarCtrl.text) ?? 1;
                  final indirimliB = _seciliUrun!.satisFiyati * (1 - oran / 100);
                  _toplamCtrl.text = (minMik * indirimliB).toStringAsFixed(2);
                  setState(() {});
                }
              },
              validator: (v) {
                final d = double.tryParse(v?.replaceAll(',', '.') ?? '');
                if (d == null || d <= 0 || d > 100) return '0-100 arası';
                return null;
              },
            )),
            const SizedBox(width: 8),
            // Ok ikonu
            Icon(Icons.sync_alt, color: context.textSecondary, size: 18),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(
              controller: _toplamCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Toplam Fiyat ₺',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.green.shade50,
                prefixText: '₺ ',
              ),
              onChanged: (v) {
                if (_seciliUrun == null) return;
                final toplam = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                final minMik = ParaUtils.sayiCoz(_minMiktarCtrl.text) ?? 1;
                final maxToplam = _seciliUrun!.satisFiyati * minMik;
                if (toplam > 0 && toplam < maxToplam) {
                  final birimIndirimli = toplam / minMik;
                  final oran = (1 - birimIndirimli / _seciliUrun!.satisFiyati) * 100;
                  if (oran >= 0 && oran <= 100) {
                    _oranCtrl.text = oran.toStringAsFixed(1);
                    setState(() {});
                  }
                }
              },
            )),
          ]),
          const SizedBox(height: 10),
          TextFormField(
            controller: _minMiktarCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(
                labelText: 'Min Miktar (Eşik)', 
                border: OutlineInputBorder(),
                helperText: 'Bu miktar ve üzeri alımda indirim uygulanır',
                prefixIcon: Icon(Icons.production_quantity_limits, size: 18)),
            onChanged: (v) {
              if (_seciliUrun == null) return;
              final minMik = double.tryParse(v.replaceAll(',', '.')) ?? 1;
              final oran = ParaUtils.sayiCoz(_oranCtrl.text) ?? 0;
              if (oran > 0 && minMik > 0) {
                final indirimliB = _seciliUrun!.satisFiyati * (1 - oran / 100);
                _toplamCtrl.text = (minMik * indirimliB).toStringAsFixed(2);
                setState(() {});
              }
            },
          ),
          const SizedBox(height: 12),

          // Tarih aralığı
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(_baslangic != null ? fmt.format(_baslangic!) : 'Başlangıç',
                  style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final dt = await showDatePicker(context: context,
                    initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (dt != null) setState(() => _baslangic = dt);
              },
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.event_available, size: 16),
              label: Text(_bitis != null ? fmt.format(_bitis!) : 'Bitiş',
                  style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final dt = await showDatePicker(context: context,
                    initialDate: _baslangic ?? DateTime.now(),
                    firstDate: _baslangic ?? DateTime.now(), lastDate: DateTime(2030));
                if (dt != null) setState(() => _bitis = dt);
              },
            )),
          ]),
          const SizedBox(height: 20),

          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            )),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(
              onPressed: _kayit ? null : _kaydet,
              style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: AppRenkler.primary),
              child: _kayit
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Kaydet'),
            )),
          ]),
        ])),
      ),
    );
  }
}

// ── Promosyon Kartı ──────────────────────────────────────────────────────────

class _PromosyonKarti extends StatelessWidget {
  final PromosyonModel promosyon;
  final VoidCallback onToggle, onSil, onDuzenle;
  const _PromosyonKarti({required this.promosyon, required this.onToggle, required this.onSil, required this.onDuzenle});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');
    final now = DateTime.now();
    final suresiDoldu = promosyon.bitisTarihi != null && promosyon.bitisTarihi!.isBefore(now);
    final renk = suresiDoldu ? context.textSecondary
        : promosyon.aktif ? Colors.green.shade700 : Colors.orange.shade700;
    final etiket = suresiDoldu ? 'Süresi Doldu' : promosyon.aktif ? 'Aktif' : 'Pasif';

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: promosyon.aktif && !suresiDoldu
            ? Colors.green.shade200 : context.borderColor),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: GestureDetector(
        onTap: onDuzenle,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(promosyon.promosyonAdi,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (promosyon.urunAdi.isNotEmpty)
              Text('Ürün: ${promosyon.urunAdi}',
                  style: TextStyle(fontSize: 12, color: context.textSecondary)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Color.fromARGB(26, renk.red, renk.green, renk.blue), borderRadius: BorderRadius.circular(12)),
            child: Text(etiket, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
          ),
          const SizedBox(width: 4),
          TsYetkili(child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) {
              if (v == 'duzenle') onDuzenle();
              if (v == 'toggle') onToggle();
              if (v == 'sil') onSil();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'duzenle',
                  child: Row(children: [Icon(Icons.edit_outlined, size: 16, color: Colors.blue), const SizedBox(width: 8), Text('Düzenle')])),
              PopupMenuItem(value: 'toggle',
                  child: Text(promosyon.aktif ? 'Pasife Al' : 'Aktife Al')),
              const PopupMenuItem(value: 'sil',
                  child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.red), const SizedBox(width: 8), Text('Sil', style: TextStyle(color: Colors.red))])),
            ],
          )),
        ]),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(children: [
          _BilgiChip(Icons.discount, '%${promosyon.iskontoOran.toStringAsFixed(0)} İndirim', Colors.orange.shade700),
          const SizedBox(width: 8),
          _BilgiChip(Icons.production_quantity_limits, 'Min: ${promosyon.minMiktar.toStringAsFixed(0)}', Colors.blue.shade700),
        ]),
        if (promosyon.baslangicTarihi != null || promosyon.bitisTarihi != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.calendar_today, size: 12, color: context.textSecondary),
            const SizedBox(width: 4),
            Text(
              [
                if (promosyon.baslangicTarihi != null) fmt.format(promosyon.baslangicTarihi!),
                if (promosyon.bitisTarihi != null) fmt.format(promosyon.bitisTarihi!),
              ].join(' – '),
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ]),
        ],
      ]),
      ),
    );
  }
}

class _BilgiChip extends StatelessWidget {
  final IconData ikon; final String metin; final Color renk;
  const _BilgiChip(this.ikon, this.metin, this.renk);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: Color.fromARGB(20, renk.red, renk.green, renk.blue), borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ikon, size: 12, color: renk),
      const SizedBox(width: 4),
      Text(metin, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: renk)),
    ]),
  );
}

class _Chip extends StatelessWidget {
  final String metin; final Color renk;
  const _Chip(this.metin, this.renk);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Color.fromARGB(26, renk.red, renk.green, renk.blue), borderRadius: BorderRadius.circular(12)),
    child: Text(metin, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: renk)),
  );
}

class _HesapKutu extends StatelessWidget {
  final String baslik, deger; final Color renk;
  const _HesapKutu(this.baslik, this.deger, this.renk);
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(baslik, style: TextStyle(fontSize: 9, color: renk.withAlpha(180))),
    Text(deger, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: renk)),
  ]);
}
