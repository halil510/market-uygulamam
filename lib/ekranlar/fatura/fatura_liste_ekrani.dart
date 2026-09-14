// lib/ekranlar/fatura/fatura_liste_ekrani.dart
// Fatura listesi - filtreli, PDF, detay görünümü

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../depolar/fatura_deposu.dart';
import '../../modeller/fatura_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';

class FaturaListeEkrani extends ConsumerStatefulWidget {
  const FaturaListeEkrani({super.key});
  @override
  ConsumerState<FaturaListeEkrani> createState() => _FaturaListeEkraniState();
}

class _FaturaListeEkraniState extends ConsumerState<FaturaListeEkrani>
    with SingleTickerProviderStateMixin {
  final _depo = FaturaDeposu();
  late final TabController _tab;

  List<FaturaModel> _faturalar = [];
  List<FaturaModel> _filtreli  = [];
  bool _yukleniyor = true;
  String? _filtreDurum; // 'beklemede', 'odendi', null
  String? _filtreEFatura; // null=Tümü, 'hazir', 'gonderildi', 'onaylandi', 'hata'
  // Kullanıcı sorusu: "gelen fatura ve giden fatura listeleme var mı?"
  // ÖNCEDEN böyle bir ayrım hiç yoktu — Satış (Giden) ve Alış (Gelen)
  // faturaları tek listede karışık duruyordu. Artık ayrı bir Yön filtresi
  // var: null=Tümü, 'giden'=Satış faturaları, 'gelen'=Alış faturaları.
  String? _filtreYon;
  bool _iptalleriGoster = false;
  DateTime? _filtreBas, _filtreBit;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(_tabDegisti);
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  void _tabDegisti() {
    if (_tab.indexIsChanging) return;
    setState(() {
      switch (_tab.index) {
        case 0: _filtreDurum = null; break;
        case 1: _filtreDurum = 'beklemede'; break;
        case 2: _filtreDurum = 'odendi'; break;
      }
      _filtrele();
    });
  }

  Future<void> _yukle() async {
    _yukleniyor = true;

    if (mounted) setState(() {});
    try {
      final list = await _depo.listele(limit: 200);
      if (!mounted) return;
      setState(() { _faturalar = list; _filtrele(); _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _filtrele() {
    var list = List<FaturaModel>.from(_faturalar);
    if (_filtreDurum != null) list = list.where((f) => f.odemeDurumu == _filtreDurum).toList();
    if (_filtreEFatura != null) {
      list = list.where((f) => (f.eFaturaDurum ?? 'hazir') == _filtreEFatura).toList();
    }
    if (_filtreYon == 'giden') {
      list = list.where((f) => f.faturaTipi != 'Alış' && f.faturaTipi != 'Alış Faturası').toList();
    } else if (_filtreYon == 'gelen') {
      list = list.where((f) => f.faturaTipi == 'Alış' || f.faturaTipi == 'Alış Faturası').toList();
    }
    list = list.where((f) => _iptalleriGoster ? f.durum == 'iptal' : f.durum != 'iptal').toList();
    if (_filtreBas != null && _filtreBit != null) {
      list = list.where((f) => f.tarih.isAfter(_filtreBas!) && f.tarih.isBefore(_filtreBit!)).toList();
    }
    _filtreli = list;
  }

  Future<void> _tarihSec(bool baslangicMi) async {
    try {  
      final d = await showDatePicker(context: context,
        initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
      if (d == null) return;
      if (!mounted) return;
      setState(() {
        if (baslangicMi) _filtreBas = DateTime(d.year, d.month, d.day);
        else _filtreBit = DateTime(d.year, d.month, d.day, 23, 59, 59);
        _filtrele();
      });
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  double get _toplamTutar => _filtreli.fold(0.0, (s, f) => s + f.genelToplam);
  double get _toplamKalan => _filtreli.fold(0.0, (s, f) => s + f.kalanTutar);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Faturalar',
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.inbox_outlined, color: Colors.white),
              tooltip: 'GİB Gelen Kutusu',
              onPressed: () => context.push('/fatura/gelen-kutusu')),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _yukle),
          TsYetkili(child: IconButton(icon: const Icon(Icons.add, color: Colors.white), tooltip: 'Yeni Fatura',
              onPressed: () => context.push('/fatura/yeni'))),
        ],
        alt: TabBar(controller: _tab,
          tabs: [
            const Tab(text: 'Tümü'),
            Tab(text: 'Bekleyen (${_faturalar.where((f) => f.odemeDurumu == 'beklemede').length})'),
            Tab(text: 'Ödenen (${_faturalar.where((f) => f.odendi).length})'),
          ],
        ),
        geriTusu: false,
        modul: TsModul.belge,
      ),
      body: Column(children: [
        // Özet kartlar
        Container(color: context.cardBg, padding: const EdgeInsets.all(12),
          child: Row(children: [
            _ozetKart('Toplam', _toplamTutar, Colors.blue),
            const SizedBox(width: 12),
            _ozetKart('Kalan', _toplamKalan, Colors.orange),
            const SizedBox(width: 12),
            _ozetKart('${_filtreli.length} Fatura', null, context.textSecondary),
          ]),
        ),
        // YÖN filtresi (Tümü / Giden-Satış / Gelen-Alış)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _yonChip('Tümü', null),
              const SizedBox(width: 6),
              _yonChip('Giden (Satış)', 'giden', renk: Colors.blue, ikon: Icons.north_east),
              const SizedBox(width: 6),
              _yonChip('Gelen (Alış)', 'gelen', renk: Colors.purple, ikon: Icons.south_west),
            ]),
          ),
        ),
        // e-Fatura durum filtresi (Tümü / Beklemede / Gönderildi / Hata) + İptaller
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _eFaturaChip('Tümü', null),
              const SizedBox(width: 6),
              _eFaturaChip('Beklemede', 'hazir', renk: Colors.orange),
              const SizedBox(width: 6),
              _eFaturaChip('Gönderildi', 'gonderildi', renk: Colors.green),
              const SizedBox(width: 6),
              _eFaturaChip('GİB Onayladı', 'onaylandi', renk: Colors.teal),
              const SizedBox(width: 6),
              _eFaturaChip('Reddedildi', 'reddedildi', renk: Colors.red),
              const SizedBox(width: 6),
              _eFaturaChip('GİB\'de İptal', 'gib_iptal', renk: Colors.grey),
              const SizedBox(width: 6),
              _eFaturaChip('Hata', 'hata', renk: Colors.red),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('İptaller', style: TextStyle(fontSize: 12)),
                selected: _iptalleriGoster,
                avatar: Icon(Icons.delete_outline, size: 16,
                    color: _iptalleriGoster ? Colors.white : context.textSecondary),
                selectedColor: Colors.red.shade400,
                labelStyle: TextStyle(color: _iptalleriGoster ? Colors.white : context.textSecondary),
                onSelected: (v) => setState(() { _iptalleriGoster = v; _filtrele(); }),
              ),
            ]),
          ),
        ),
        // Tarih filtresi
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 14),
              label: Text(_filtreBas != null
                  ? DateFormat('dd.MM.yyyy').format(_filtreBas!)
                  : 'Başlangıç', style: const TextStyle(fontSize: 12)),
              onPressed: () => _tarihSec(true),
            )),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 14),
              label: Text(_filtreBit != null
                  ? DateFormat('dd.MM.yyyy').format(_filtreBit!)
                  : 'Bitiş', style: const TextStyle(fontSize: 12)),
              onPressed: () => _tarihSec(false),
            )),
            if (_filtreBas != null || _filtreBit != null)
              IconButton(icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() { _filtreBas = null; _filtreBit = null; _filtrele(); })),
          ]),
        ),
        Expanded(child: _yukleniyor
          ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF4361EE)))
          : RefreshIndicator(
              onRefresh: _yukle,
              child: _filtreli.isEmpty
                  ? const TsBosDurum(ikon: Icons.receipt_long, baslik: 'Fatura bulunamadı')
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _filtreli.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _faturaKart(_filtreli[i]),
                    ),
            ),
        ),
      ]),
    );
  }

  // NOT: `renk` varsayılanı olarak context.textSecondary YAZILAMAZ —
  // varsayılan parametre değerleri derleme-zamanı sabiti olmak zorundadır.
  // Bu yüzden nullable yapılıp gövdede çözülüyor.
  Widget _yonChip(String label, String? deger, {Color? renk, IconData? ikon}) {
    final secili = _filtreYon == deger;
    final r = renk ?? context.textSecondary;
    return ChoiceChip(
      avatar: ikon != null ? Icon(ikon, size: 14, color: secili ? Colors.white : r) : null,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: secili,
      selectedColor: r,
      labelStyle: TextStyle(color: secili ? Colors.white : context.textSecondary,
          fontWeight: secili ? FontWeight.w700 : FontWeight.normal),
      onSelected: (_) => setState(() { _filtreYon = deger; _filtrele(); }),
    );
  }

  Widget _eFaturaChip(String label, String? deger, {Color? renk}) {
    final secili = _filtreEFatura == deger;
    final r = renk ?? context.textSecondary;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: secili,
      selectedColor: r,
      labelStyle: TextStyle(color: secili ? Colors.white : context.textSecondary,
          fontWeight: secili ? FontWeight.w700 : FontWeight.normal),
      onSelected: (_) => setState(() { _filtreEFatura = deger; _filtrele(); }),
    );
  }

  Widget _ozetKart(String label, double? tutar, Color renk) => Expanded(
    child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(color: Color.fromARGB(20, renk.red, renk.green, renk.blue), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color.fromARGB(51, renk.red, renk.green, renk.blue))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Color.fromARGB(204, renk.red, renk.green, renk.blue))),
        const SizedBox(height: 4),
        Text(tutar != null ? ParaUtils.formatla(tutar) : '',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: renk)),
      ]),
    ),
  );

  Widget _faturaKart(FaturaModel f) {
    final odendi = f.odendi;
    final vadesiGecti = f.vadesiGecti;
    final iptalEdilmis = f.durum == 'iptal';
    Color durum = odendi ? Colors.green : vadesiGecti ? Colors.red : Colors.orange;

    final eDurum = f.eFaturaDurum ?? 'hazir';
    // 🔴🔴 DÜZELTME (erp_roadmap madde 38 — e-Belge durum makinesi, 2026-09-14
    // ikinci tur derin analiz): GİB'in gerçekten REDDETTİĞİ bir belge (artık
    // gib_servisi.dart'taki durumSorgula() entegratör terimlerini
    // 'reddedildi'/'gib_iptal'e normalleştiriyor) bu ekranda hâlâ turuncu
    // "Beklemede" olarak görünüyordu — yasal geçerliliği OLMAYAN bir fatura,
    // sanki hâlâ gönderim bekliyormuş gibi duruyordu. Artık tanınıyor.
    final eRenk  = eDurum == 'onaylandi' ? Colors.teal
                 : eDurum == 'gonderildi' ? Colors.green
                 : eDurum == 'gonderiliyor' ? Colors.blue
                 : eDurum == 'reddedildi' ? Colors.red
                 : eDurum == 'gib_iptal' ? Colors.grey
                 : eDurum == 'hata' ? Colors.red : Colors.orange;
    final eEtiket = eDurum == 'onaylandi' ? 'GİB Onayladı'
                  : eDurum == 'gonderildi' ? 'Gönderildi'
                  : eDurum == 'gonderiliyor' ? 'Gönderiliyor'
                  : eDurum == 'reddedildi' ? 'GİB Reddetti'
                  : eDurum == 'gib_iptal' ? 'GİB\'de İptal'
                  : eDurum == 'hata' ? 'Gönderim Hatası' : 'Beklemede';
    final eIkon  = eDurum == 'onaylandi' ? Icons.verified_outlined
                 : eDurum == 'gonderildi' ? Icons.cloud_done_outlined
                 : eDurum == 'gonderiliyor' ? Icons.cloud_upload_outlined
                 : eDurum == 'reddedildi' ? Icons.cancel_outlined
                 : eDurum == 'gib_iptal' ? Icons.block_outlined
                 : eDurum == 'hata' ? Icons.error_outline : Icons.schedule_outlined;

    final kart = TsKart(
      onTap: () => context.push('/fatura/detay/${f.id}'),
      padding: const EdgeInsets.all(14),
      child: Opacity(
          opacity: iptalEdilmis ? 0.55 : 1,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                child: Text(f.faturaNo ?? '—', style: TsMetin.kucukVurgu.copyWith(color: Colors.blue))),
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(12)),
                child: Text(f.faturaTipi ?? 'Satış',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.textSecondary))),
              const Spacer(),
              Text(DateFormat('dd.MM.yyyy').format(f.tarih),
                  style: TextStyle(fontSize: 12, color: context.textSecondary)),
            ]),
            const SizedBox(height: 6),
            // Durum rozetleri: Ödeme + e-Fatura gönderim durumu
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (iptalEdilmis)
                _rozet('İptal Edildi', Icons.block, context.textSecondary)
              else
                _rozet(odendi ? 'Ödendi' : vadesiGecti ? 'Vadesi Geçti' : 'Beklemede',
                    odendi ? Icons.check_circle_outline : Icons.schedule, durum),
              _rozet(eEtiket, eIkon, eRenk),
            ]),
            const SizedBox(height: 8),
            Text(f.cariUnvan ?? 'Bilinmeyen Cari',
                style: TsMetin.govdeVurgu),
            if (f.vadeTarihi != null)
              Text('Vade: ${DateFormat('dd.MM.yyyy').format(f.vadeTarihi!)}',
                  style: TextStyle(fontSize: 12, color: vadesiGecti ? Colors.red : context.textSecondary)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Toplam', style: TextStyle(fontSize: 11, color: context.textSecondary)),
                Text(ParaUtils.formatla(f.genelToplam),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ]),
              if (f.kalanTutar > 0) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Kalan', style: TextStyle(fontSize: 11, color: context.textSecondary)),
                Text(ParaUtils.formatla(f.kalanTutar),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.orange)),
              ]),
            ]),
          ]),
        ),
    );

    if (iptalEdilmis) return kart; // iptal edilmiş faturada swipe yok

    return Dismissible(
      key: ValueKey('fatura_${f.id}'),
      direction: ref.watch(authProvider.select((s) => s.isMudur))
          ? DismissDirection.endToStart : DismissDirection.none,
      confirmDismiss: (_) async {
        final onay = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Faturayı İptal Et'),
            content: Text('${f.faturaNo ?? "Bu fatura"} iptal edilsin mi? '
                'Fatura silinmez, "İptaller" sekmesinde görüntülenmeye devam eder.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
                  onPressed: () => Navigator.pop(ctx, true), child: const Text('İptal Et')),
            ],
          ),
        );
        if (onay == true) {
          await _depo.iptalEt(f.id!);
          await _yukle();
        }
        return false; // listeyi _yukle yönetecek
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.block, color: Colors.white, size: 24),
          SizedBox(height: 2),
          Text('İptal Et', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
      child: kart,
    );
  }

  Widget _rozet(String etiket, IconData ikon, Color renk) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: Color.fromARGB(31, renk.red, renk.green, renk.blue), borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ikon, size: 12, color: renk),
      const SizedBox(width: 3),
      Text(etiket, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
    ]),
  );
}
