// lib/ekranlar/urun/toplu_islem_ekrani.dart — Modern v2
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/stok_deposu.dart';
import '../../servisler/auth_servisi.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/barkod_servisi.dart';
import '../../servisler/excel_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

// ── Alan tanımları ────────────────────────────────────────────────────────────

class _AlanTanim {
  final String id, label, grup;
  final bool sayisal;
  final IconData? ikon;
  final Color renk;
  const _AlanTanim(this.id, this.label, {
    this.grup = 'Genel', this.sayisal = false,
    this.ikon, this.renk = AppRenkler.primary});
}

const _ALANLAR = [
  // Fiyat grubu
  _AlanTanim('alisFiyat',        'Alış Fiyatı (KDV Hariç)',  grup: 'Fiyat', sayisal: true,  ikon: Icons.south_east, renk: Color(0xFF1565C0)),
  _AlanTanim('alisFiyatKdvDahil','Alış Fiyatı (KDV Dahil)', grup: 'Fiyat', sayisal: true,  ikon: Icons.south_east, renk: Color(0xFF1565C0)),
  _AlanTanim('satisFiyati',      'Satış Fiyatı',             grup: 'Fiyat', sayisal: true,  ikon: Icons.north_east, renk: Color(0xFF2E7D32)),
  _AlanTanim('indirimOrani',     'İndirim Oranı %',          grup: 'Fiyat', sayisal: true,  ikon: Icons.discount_outlined, renk: Color(0xFFE65100)),
  _AlanTanim('indirimli_fiyat',  'İndirimli Fiyat',          grup: 'Fiyat', sayisal: true,  ikon: Icons.local_offer_outlined, renk: Color(0xFFE65100)),
  // Stok grubu
  _AlanTanim('stok',             'Stok Miktarı',             grup: 'Stok',  sayisal: true,  ikon: Icons.inventory_2_outlined, renk: Color(0xFF6A1B9A)),
  _AlanTanim('minimum_stok',     'Minimum Stok',             grup: 'Stok',  sayisal: true,  ikon: Icons.warning_amber_outlined, renk: Color(0xFFBF360C)),
  // KDV grubu
  _AlanTanim('kdvOran',          'KDV Oranı %',              grup: 'KDV',   sayisal: true,  ikon: Icons.percent, renk: Color(0xFF00695C)),
  // Grup/Sınıflandırma
  _AlanTanim('anaGrup',          'Ana Grup',                 grup: 'Sınıf', sayisal: false, ikon: Icons.folder_outlined, renk: Color(0xFF37474F)),
  _AlanTanim('altGrup',          'Alt Grup',                 grup: 'Sınıf', sayisal: false, ikon: Icons.folder_open_outlined, renk: Color(0xFF546E7A)),
  _AlanTanim('alan1',            'Alan 1',                   grup: 'Sınıf', sayisal: false, ikon: Icons.label_outlined, renk: Color(0xFF455A64)),
  _AlanTanim('alan2',            'Alan 2',                   grup: 'Sınıf', sayisal: false, ikon: Icons.label_outlined, renk: Color(0xFF455A64)),
  _AlanTanim('marka',            'Marka',                    grup: 'Sınıf', sayisal: false, ikon: Icons.star_border_outlined, renk: Color(0xFF4527A0)),
  _AlanTanim('mensei',           'Menşei',                   grup: 'Sınıf', sayisal: false, ikon: Icons.flag_outlined, renk: Color(0xFF2E7D32)),
  _AlanTanim('birimAdi',         'Birim',                    grup: 'Sınıf', sayisal: false, ikon: Icons.straighten_outlined, renk: Color(0xFF00838F)),
  _AlanTanim('puan_orani',       'Puan Oranı',               grup: 'Diğer', sayisal: true,  ikon: Icons.stars_outlined, renk: Color(0xFFF9A825)),
];

enum IslemTuru { degistir, artir, azalt }

// ── Ekran ─────────────────────────────────────────────────────────────────────

class TopluIslemEkrani extends ConsumerStatefulWidget {
  final List<int> secilenIds;
  const TopluIslemEkrani({super.key, this.secilenIds = const []});
  @override
  ConsumerState<TopluIslemEkrani> createState() => _TopluIslemEkraniState();
}

class _TopluIslemEkraniState extends ConsumerState<TopluIslemEkrani>
    with SingleTickerProviderStateMixin {
  final _depo      = UrunDeposu();
  final _araCtrl   = TextEditingController();
  final _degerCtrl = TextEditingController();
  late TabController _tab;

  List<UrunModel>  _tum          = [];
  List<UrunModel>  _filtrelenmis = [];
  Set<int>         _secili       = {};
  _AlanTanim?      _alan;
  IslemTuru        _islem        = IslemTuru.degistir;
  bool _yuzde = false; // artır/azalt için yüzde mi sabit mi
  bool _yukleniyor  = false;
  bool _islemYapiliyor = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _araCtrl.addListener(() => _filtrele());
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void dispose() {
    _tab.dispose();
    _araCtrl.dispose();
    _degerCtrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final urunler = await _depo.tumunuGetir(sadecaAktif: false);
      _tum = urunler;
      _filtrele();
      if (widget.secilenIds.isNotEmpty) _secili.addAll(widget.secilenIds);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yükleme hatası: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _filtrele() {
    final q = _araCtrl.text.toLowerCase();
    setState(() {
      _filtrelenmis = q.isEmpty ? _tum : _tum.where((u) =>
          u.urunAdi.toLowerCase().contains(q) ||
          (u.barkod?.toLowerCase().contains(q) ?? false) ||
          (u.anaGrup?.toLowerCase().contains(q) ?? false)).toList();
    });
  }

  void _tumunuSec() => setState(() => _secili = _filtrelenmis.map((u) => u.id!).toSet());
  void _secimTemizle() => setState(() => _secili.clear());
  void _toggle(int id) => setState(() {
    if (_secili.contains(id)) _secili.remove(id); else _secili.add(id);
  });

  // Yeni değer hesapla
  double _hesapla(double eski, double girilenDeger) {
    switch (_islem) {
      case IslemTuru.degistir: return girilenDeger;
      case IslemTuru.artir:
        return _yuzde ? eski * (1 + girilenDeger / 100) : eski + girilenDeger;
      case IslemTuru.azalt:
        return _yuzde ? eski * (1 - girilenDeger / 100) : eski - girilenDeger;
    }
  }

  Future<void> _topluGuncelle() async {
    if (_secili.isEmpty) { BildirimServisi.uyari(context, 'Ürün seçin'); return; }
    if (_alan == null) { BildirimServisi.uyari(context, 'Alan seçin'); return; }
    final degerMetin = _degerCtrl.text.trim().replaceAll(',', '.');
    if (degerMetin.isEmpty) { BildirimServisi.uyari(context, 'Değer girin'); return; }
    final sayisalDeger = double.tryParse(degerMetin);
    if (_alan!.sayisal && sayisalDeger == null) {
      BildirimServisi.uyari(context, 'Geçerli sayı girin'); return;
    }

    final onay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Text('Toplu Güncelleme'),
        content: RichText(text: TextSpan(style: TextStyle(color: TsRenk.metinBirincil(ctx), fontSize: 14),
          children: [
            TextSpan(text: '${_secili.length} ürün\n', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            TextSpan(text: '${_alan!.label}: '),
            TextSpan(text: _islemAcikla(degerMetin),
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppRenkler.primary)),
            const TextSpan(text: '\n\nOnaylıyor musunuz?'),
          ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Güncelle')),
        ],
      ));
    if (onay != true || !mounted) return;

    setState(() => _islemYapiliyor = true);
    int basarili = 0;
    try {
      for (final id in _secili) {
        final u = _tum.firstWhere((x) => x.id == id);

        // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): 'stok' alanı
        // burada diğer alanlar gibi doğrudan 'urunler.stok' sütununa
        // yazılıyordu — hiçbir stok_hareket kaydı oluşturulmadan. Stok
        // StokDeposu'nda event-sourcing ile (stok_hareket toplamından)
        // yönetiliyor; bu yolla değiştirilen bir stok, bir sonraki
        // stokMutabakatYap() turunda (senkron sonrası veya Veri Sağlığı
        // Merkezi'nden tetiklenebiliyor) sessizce ESKİ değerine geri
        // dönüyordu — kullanıcı "düzelttim" sanıp aslında kalıcı hiçbir
        // şey olmuyordu. Artık StokDeposu.stokDusTxn/stokGirTxn ile
        // (UrunDeposu.guncelle()'deki "Manuel Düzeltme" deseniyle aynı)
        // düzgün bir stok_hareket kaydı da oluşturuluyor.
        if (_alan!.id == 'stok') {
          try {
            final yeni = _hesapla(u.stok, sayisalDeger!).clamp(0, double.infinity);
            final fark = yeni - u.stok;
            if (fark.abs() > 0.0001) {
              // db.transaction() + BulutManager senkronu artık burada
              // elle açılmıyor — StokDeposu.stokGir/stokDus (Txn OLMAYAN
              // "kendi transaction'ını açan" varyantlar) zaten AYNI işi
              // yapıyor VE ayrıca şube payını (sube_urun) da güncelliyor
              // — bu ekranın elle yazdığı kod bunu hiç yapmıyordu, çok
              // şubeli kurulumlarda toplu stok düzeltmesi şube payını
              // atlıyordu. Aynı depo metodunu kullanmak bunu da düzeltiyor.
              if (fark > 0) {
                await StokDeposu().stokGir(
                    urunId: id, miktar: fark,
                    kullaniciId: AuthServisi().aktifId,
                    referansTuru: 'toplu_islem',
                    aciklama: 'Toplu işlem: stok düzeltmesi');
              } else {
                await StokDeposu().stokDus(
                    urunId: id, miktar: fark.abs(),
                    kullaniciId: AuthServisi().aktifId,
                    referansTuru: 'toplu_islem',
                    aciklama: 'Toplu işlem: stok düzeltmesi');
              }
            }
            basarili++;
          } catch (e) {
            if (kDebugMode) debugPrint('Toplu stok güncelleme satır hatası (id=$id): $e');
          }
          continue;
        }

        final Map<String, dynamic> data = {};
        if (_alan!.sayisal) {
          final yeni = _hesapla(
              _mevcutDeger(u, _alan!.id) ?? 0, sayisalDeger!);
          data[_alanKolonAdi(_alan!.id)] = yeni.clamp(0, double.infinity);

          // Bağımlı alanları güncelle
          if (_alan!.id == 'alisFiyat') {
            final kdv = double.tryParse(u.kdvOran) ?? 18;
            data['alis_fiyat_kdv_dahil'] = yeni * (1 + kdv / 100);
          } else if (_alan!.id == 'alisFiyatKdvDahil') {
            final kdv = double.tryParse(u.kdvOran) ?? 18;
            data['alis_fiyat'] = kdv > 0 ? yeni / (1 + kdv / 100) : yeni;
          } else if (_alan!.id == 'indirimOrani') {
            data['indirimli_fiyat'] = u.satisFiyati * (1 - yeni / 100);
          }
        } else {
          data[_alanKolonAdi(_alan!.id)] = degerMetin;
        }
        // last_updated güncellenmeli — yoksa "Buluta Gönder" bu değişikliği görmez
        data['last_updated'] = DateTime.now().toIso8601String();

        // Madde 2 sertleştirmesi: doğrudan _depo.db erişimi kaldırıldı —
        // UrunDeposu.alanGuncelle() üzerinden yazılıyor (last_updated +
        // BulutManager bildirimi orada merkezi olarak yapılıyor).
        try {
          await _depo.alanGuncelle(id, data);
          basarili++;
        } catch (e) {
          if (kDebugMode) debugPrint('Toplu güncelleme satır hatası (id=$id): $e');
        }
      }
      await _yukle();
      if (mounted) BildirimServisi.basari(context,
          '$basarili ürün güncellendi ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islemYapiliyor = false);
    }
  }

  String _islemAcikla(String deger) {
    switch (_islem) {
      case IslemTuru.degistir: return '"$deger" yapılıyor';
      case IslemTuru.artir:    return _yuzde ? '%$deger artırılıyor' : '+$deger ekleniyor';
      case IslemTuru.azalt:    return _yuzde ? '%$deger azaltılıyor' : '-$deger çıkarılıyor';
    }
  }

  double? _mevcutDeger(UrunModel u, String alanId) => switch (alanId) {
    'alisFiyat'         => u.alisFiyat,
    'alisFiyatKdvDahil' => u.alisFiyatKdvDahil,
    'satisFiyati'       => u.satisFiyati,
    'indirimOrani'      => u.indirimOrani,
    'indirimli_fiyat'   => u.indirimliFiyatKayitli,
    'stok'              => u.stok,
    'kdvOran'           => double.tryParse(u.kdvOran),
    'puan_orani'        => u.puanOrani,
    'minimum_stok'      => u.minimumStok,
    _                   => null,
  };

  String _alanKolonAdi(String alanId) => switch (alanId) {
    'alisFiyat'         => 'alis_fiyat',
    'alisFiyatKdvDahil' => 'alis_fiyat_kdv_dahil',
    'satisFiyati'       => 'satis_fiyati',
    'indirimOrani'      => 'indirim_orani',
    'indirimli_fiyat'   => 'indirimli_fiyat',
    'stok'              => 'stok',
    'kdvOran'           => 'kdv_oran',
    'birimAdi'          => 'birim_adi',
    'anaGrup'           => 'ana_grup',
    'altGrup'           => 'alt_grup',
    'marka'             => 'marka',
    'mensei'            => 'mensei',
    'puan_orani'        => 'puan_orani',
    'minimum_stok'      => 'minimum_stok',
    _                   => alanId,
  };

  Future<void> _excelDisa() async {
    final urunler = _secili.isEmpty
        ? _filtrelenmis
        : _tum.where((u) => _secili.contains(u.id!)).toList();
    try {
      await ExcelServisi().urunleriExcelEAktar(urunler);
      if (mounted) BildirimServisi.basari(context, 'Excel hazırlandı');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Gruplara ayır
    final gruplar = <String, List<_AlanTanim>>{};
    for (final a in _ALANLAR) {
      gruplar.putIfAbsent(a.grup, () => []).add(a);
    }

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: Text(_secili.isEmpty ? 'Toplu İşlem' : '${_secili.length} Seçili'),
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.file_download_outlined, color: Colors.white),
              tooltip: 'Excel', onPressed: _excelDisa),
          if (_secili.isNotEmpty)
            IconButton(icon: const Icon(Icons.deselect_outlined, color: Colors.white),
                tooltip: 'Seçimi Temizle', onPressed: _secimTemizle),
        ],
        alt: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'Ürünler'), Tab(text: 'Güncelleme Alanı')],
        ),
      ),
      body: TabBarView(controller: _tab, children: [
        // ── Tab 1: Ürün Listesi ───────────────────────────────────────────────
        Column(children: [
          // Arama + seç butonları
          Container(color: Colors.white, padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(
                controller: _araCtrl,
                decoration: InputDecoration(
                  hintText: 'Ürün adı, barkod, grup ara...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_araCtrl.text.isNotEmpty)
                      IconButton(icon: const Icon(Icons.clear, size: 16),
                        onPressed: () { _araCtrl.clear(); _filtrele(); }),
                    IconButton(icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                      tooltip: 'Barkod Tara',
                      onPressed: () async {
                        final b = await BarkodServisi().barkodTara(context);
                        if (b != null && mounted) { _araCtrl.text = b; _filtrele(); }
                      }),
                  ]),
                  filled: true, fillColor: context.borderColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Text('${_filtrelenmis.length} ürün',
                    style: TextStyle(fontSize: 12, color: context.textSecondary)),
                const Spacer(),
                TextButton.icon(icon: const Icon(Icons.select_all, size: 16),
                    label: const Text('Tümünü Seç', style: TextStyle(fontSize: 12)),
                    onPressed: _tumunuSec),
                TextButton.icon(icon: const Icon(Icons.deselect, size: 16),
                    label: const Text('Temizle', style: TextStyle(fontSize: 12)),
                    onPressed: _secimTemizle, style: TextButton.styleFrom(foregroundColor: context.textSecondary)),
              ]),
            ]),
          ),
          Expanded(child: _yukleniyor
            ? const Center(child: const AppYukleniyor())
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                itemCount: _filtrelenmis.length,
                itemBuilder: (_, i) {
                  final u = _filtrelenmis[i];
                  final secili = _secili.contains(u.id!);
                  return GestureDetector(
                    onTap: () => _toggle(u.id!),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: secili ? Color.fromARGB(20, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: secili ? AppRenkler.primary : Colors.transparent, width: 1.5),
                        boxShadow: secili ? [] : [BoxShadow(
                            color: Color(0x0A000000), blurRadius: 4)],
                      ),
                      child: Row(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: secili ? AppRenkler.primary : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: secili ? AppRenkler.primary : context.borderColor)),
                          child: secili
                              ? const Icon(Icons.check, color: Colors.white, size: 14)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(u.urunAdi,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${u.anaGrup ?? '—'} · Stok: ${u.stok.toStringAsFixed(0)}',
                              style: TextStyle(fontSize: 11, color: context.textSecondary)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(ParaUtils.formatla(u.satisFiyati),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          if (u.alisFiyat > 0)
                            Text('Alış: ${ParaUtils.formatla(u.alisFiyat)}',
                                style: TextStyle(fontSize: 10, color: context.textSecondary)),
                        ]),
                      ]),
                    ),
                  );
                },
              )),
        ]),

        // ── Tab 2: Güncelleme Alanı ───────────────────────────────────────────
        ListView(padding: const EdgeInsets.all(16), children: [
          // Seçili ürün sayısı
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _secili.isEmpty ? Colors.orange.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _secili.isEmpty ? Colors.orange.shade300 : Colors.green.shade300)),
            child: Row(children: [
              Icon(_secili.isEmpty ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: _secili.isEmpty ? Colors.orange : Colors.green),
              const SizedBox(width: 10),
              Text(
                _secili.isEmpty ? 'Önce ürünler sekmesinden seçim yapın'
                    : '${_secili.length} ürün seçili — güncelleme hazır',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13,
                    color: _secili.isEmpty ? Colors.orange.shade800 : Colors.green.shade800)),
            ]),
          ),
          const SizedBox(height: 16),

          // Alan grupları
          ...gruplar.entries.map((entry) => Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Text(entry.key, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: context.textSecondary, letterSpacing: 0.5))),
              Wrap(spacing: 8, runSpacing: 8,
                children: entry.value.map((a) {
                  final secili = _alan?.id == a.id;
                  return GestureDetector(
                    onTap: () => setState(() => _alan = a),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: secili ? a.renk : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: secili ? a.renk : context.borderColor),
                        boxShadow: secili ? [] :
                            [BoxShadow(color: Color(0x0A000000), blurRadius: 4)],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (a.ikon != null) Icon(a.ikon, size: 14,
                            color: secili ? Colors.white : a.renk),
                        if (a.ikon != null) const SizedBox(width: 6),
                        Text(a.label, style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: secili ? Colors.white : context.textSecondary)),
                      ]),
                    ),
                  );
                }).toList()),
              const SizedBox(height: 12),
            ])).toList(),

          if (_alan != null) ...[
            const Divider(),
            const SizedBox(height: 8),

            // İşlem tipi
            Text('İşlem Tipi', style: TsMetin.kucukVurgu.copyWith(color: context.textSecondary)),
            const SizedBox(height: 8),
            SegmentedButton<IslemTuru>(
              segments: const [
                ButtonSegment(value: IslemTuru.degistir,
                    label: Text('Değiştir'), icon: Icon(Icons.edit, size: 15)),
                ButtonSegment(value: IslemTuru.artir,
                    label: Text('Artır'), icon: Icon(Icons.trending_up, size: 15)),
                ButtonSegment(value: IslemTuru.azalt,
                    label: Text('Azalt'), icon: Icon(Icons.trending_down, size: 15)),
              ],
              selected: {_islem},
              onSelectionChanged: (s) => setState(() { _islem = s.first; }),
            ),

            // Artır/Azalt ise Yüzde/Sabit toggle
            if (_islem != IslemTuru.degistir && _alan!.sayisal) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Text('Yöntem:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(width: 10),
                ChoiceChip(label: const Text('Sabit Tutar'), selected: !_yuzde,
                    onSelected: (_) => setState(() => _yuzde = false),
                    selectedColor: AppRenkler.primary,
                    labelStyle: TextStyle(color: !_yuzde ? Colors.white : context.textSecondary)),
                const SizedBox(width: 6),
                ChoiceChip(label: const Text('Yüzde (%)'), selected: _yuzde,
                    onSelected: (_) => setState(() => _yuzde = true),
                    selectedColor: AppRenkler.primary,
                    labelStyle: TextStyle(color: _yuzde ? Colors.white : context.textSecondary)),
              ]),
            ],

            const SizedBox(height: 12),
            // Değer girişi
            TextField(
              controller: _degerCtrl,
              keyboardType: _alan!.sayisal
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              inputFormatters: _alan!.sayisal
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
                  : null,
              decoration: InputDecoration(
                labelText: _alan!.sayisal && _islem != IslemTuru.degistir
                    ? '${_islem == IslemTuru.artir ? "Artış" : "Azalış"} Miktarı'
                    : 'Yeni Değer',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true, fillColor: Colors.white,
                suffixText: _alan!.sayisal && _yuzde && _islem != IslemTuru.degistir ? '%' : null,
                prefixIcon: Icon(_alan!.ikon ?? Icons.edit_outlined, color: _alan!.renk),
              ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // Güncelle butonu
            SizedBox(height: 52, child: FilledButton.icon(
              onPressed: _islemYapiliyor ? null : _topluGuncelle,
              icon: _islemYapiliyor
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.bolt_outlined),
              label: Text(
                '${_secili.length} Ürünü Güncelle',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
          backgroundColor: _alan!.renk,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            )),
          ],
          const SizedBox(height: 80),
        ]),
      ]),
    );
  }
}
