// lib/ekranlar/urun/urun_detay_ekrani.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../modeller/urun_model.dart';
import '../../depolar/stok_deposu.dart';
import '../../depolar/sube_urun_deposu.dart';
import '../../depolar/toptan_fiyat_deposu.dart';
import '../../modeller/stok_hareket_model.dart';
import '../../modeller/fiyat_kademesi_model.dart';
import '../../modeller/fiyat_grubu_model.dart';
import '../../saglayicilar/riverpod/urun_provider.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../saglayicilar/riverpod/doviz_provider.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class UrunDetayEkrani extends ConsumerStatefulWidget {
  final int urunId;
  const UrunDetayEkrani({super.key, required this.urunId});
  @override
  ConsumerState<UrunDetayEkrani> createState() => _UrunDetayEkraniState();
}

class _UrunDetayEkraniState extends ConsumerState<UrunDetayEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _sil(UrunModel u) async {
    final onay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ürün Sil'),
        content: Text('${u.urunAdi} silinecek. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil')),
        ],
      ));
    if (onay != true || !mounted) return;
    await ref.read(urunlerProvider.notifier).sil(u.id!);
    if (mounted) { context.pop(); BildirimServisi.basari(context, 'Ürün silindi'); }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(urunDetayProvider(widget.urunId));
    return async.when(
      loading: () => const Scaffold(body: const TsYukleniyor()),
      error:   (e, _) => Scaffold(
        appBar: TsAppBar(
        baslik: 'Hata',
        gradyanli: false,
      ),
        body: Center(child: Text('$e'))),
      data: (urun) {
        if (urun == null) return Scaffold(
          appBar: TsAppBar(
        baslik: 'Bulunamadı',
        gradyanli: false,
      ),
          body: const Center(child: Text('Ürün bulunamadı')));
        return Scaffold(
          backgroundColor: context.scaffoldBg,
          appBar: TsAppBar(
        baslikWidget: Text(urun.urunAdi, style: const TextStyle(fontSize: 15)),
        aksiyonlar: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                onPressed: () => context.push('/urun/ekle', extra: urun)
                    .then((_) => ref.invalidate(urunDetayProvider(widget.urunId))),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _sil(urun),
              ),
            ],
        alt: TabBar(
              controller: _tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: const [
                Tab(text: 'Bilgi'), Tab(text: 'Fiyat'), Tab(text: 'Stok'), Tab(text: 'Şube Stok'),
              ],
            ),
      ),
          body: TabBarView(controller: _tab, children: [
            _BilgiSekmesi(urun: urun),
            _FiyatSekmesi(urun: urun),
            _HareketSekmesi(urunId: urun.id!),
            _SubeStokSekmesi(urun: urun),
          ]),
        );
      },
    );
  }
}

class _BilgiSekmesi extends StatelessWidget {
  final UrunModel urun;
  const _BilgiSekmesi({required this.urun});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    _Kart(children: [
      _Satir('Ürün Adı',  urun.urunAdi),
      _Satir('Barkod',    urun.barkod ?? '—'),
      _Satir('Birim',     urun.birimAdi),
      _Satir('Ana Grup',  urun.anaGrup ?? '—'),
      _Satir('Alt Grup',  urun.altGrup ?? '—'),
      _Satir('Marka',     urun.marka ?? '—'),
      _Satir('Menşei',    urun.mensei ?? '—'),
      _Satir('KDV %',     urun.kdvOran),
      _Satir('Durum',     urun.aktif ? '✓ Aktif' : '✗ Pasif'),
    ]),
    if (urun.alan1 != null || urun.alan2 != null)
      _Kart(baslik: 'Özel Alanlar', children: [
        if (urun.alan1 != null) _Satir('Alan 1', urun.alan1!),
        if (urun.alan2 != null) _Satir('Alan 2', urun.alan2!),
      ]),
    const SizedBox(height: 80),
  ]);
}

class _FiyatSekmesi extends StatelessWidget {
  final UrunModel urun;
  const _FiyatSekmesi({required this.urun});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    _Kart(baslik: 'Satış', children: [
      _Satir('Satış Fiyatı',      ParaUtils.formatla(urun.satisFiyati), bold: true),
      _Satir('İndirimli Fiyat',   urun.indirimliFiyatKayitli > 0
          ? ParaUtils.formatla(urun.indirimliFiyatKayitli) : '—'),
      _Satir('İndirim Oranı',     urun.indirimOrani > 0
          ? '%${urun.indirimOrani.toStringAsFixed(1)}' : '—'),
      _Satir('Kar Marjı',         '%${urun.karOrani.toStringAsFixed(1)}'),
    ]),
    const SizedBox(height: 12),
    _Kart(baslik: 'Alış', children: [
      _Satir('Alış (KDV Hariç)',  ParaUtils.formatla(urun.alisFiyat)),
      _Satir('Alış (KDV Dahil)',  ParaUtils.formatla(urun.alisFiyatKdvDahil)),
    ]),
    if (urun.paraBirimi != 'TRY')
      Consumer(builder: (context, ref, _) {
        final kurAsync = ref.watch(dovizKuruProvider(urun.paraBirimi));
        return kurAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (kur) {
            if (kur == null || kur.kurGirilmemis) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TsKart(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 16, color: TsRenk.uyari),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      'Tedarikçi para birimi ${urun.paraBirimi} olarak işaretli ama '
                      'kur girilmemiş. Ayarlar > Döviz Kurları\'ndan girebilirsiniz.',
                      style: const TextStyle(fontSize: 11, color: TsRenk.uyari))),
                  ]),
                ),
              );
            }
            final yabanciTutar = kur.satisKuru > 0 ? urun.alisFiyat / kur.satisKuru : 0;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TsKart(
                padding: const EdgeInsets.all(10),
                child: Text(
                  'Tedarikçi fiyatı (referans): ${kur.sembol}${yabanciTutar.toStringAsFixed(2)} '
                  '${urun.paraBirimi} (güncel kur: ${ParaUtils.formatla(kur.satisKuru)})',
                  style: TextStyle(fontSize: 11.5, color: TsRenk.metinIkincil(context)),
                ),
              ),
            );
          },
        );
      }),
    // 🔴 YENİ (kullanıcı isteği: "1. maddeyle başla" — toptan
    // fiyatlandırma sistemi): Miktar bazlı kademe TANIMLAMANIN daha
    // önce HİÇBİR yolu yoktu (ToptanFiyatDeposu.kademeEkle() hazırdı
    // ama tetikleyecek buton yoktu). Sadece toptan satışa açık
    // ürünlerde gösteriliyor.
    if (urun.toptanSatista) ...[
      const SizedBox(height: 12),
      _ToptanKademeleriBolumu(urun: urun),
    ],
    const SizedBox(height: 80),
  ]);
}

class _ToptanKademeleriBolumu extends StatefulWidget {
  final UrunModel urun;
  const _ToptanKademeleriBolumu({required this.urun});
  @override
  State<_ToptanKademeleriBolumu> createState() => _ToptanKademeleriBolumuState();
}

class _ToptanKademeleriBolumuState extends State<_ToptanKademeleriBolumu> {
  final _depo = ToptanFiyatDeposu();
  List<FiyatKademesiModel> _kademeler = [];
  List<FiyatGrubuModel> _gruplar = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    final k = await _depo.kademeleriGetir(widget.urun.id!);
    final g = await _depo.gruplariGetir(sadeceAktif: true);
    if (!mounted) return;
    setState(() { _kademeler = k; _gruplar = g; _yukleniyor = false; });
  }

  String _grupAdi(int? id) {
    if (id == null) return 'Tüm Bayiler (Genel)';
    return _gruplar.firstWhere((g) => g.id == id,
        orElse: () => const FiyatGrubuModel(ad: 'Bilinmeyen Grup')).ad;
  }

  Future<void> _kademeEkleDuzenle([FiyatKademesiModel? mevcut]) async {
    final miktarCtrl = TextEditingController(
        text: mevcut != null ? mevcut.minMiktar.toStringAsFixed(0) : '');
    final fiyatCtrl = TextEditingController(
        text: mevcut != null ? mevcut.fiyat.toStringAsFixed(2) : '');
    String birim = mevcut?.birim ?? 'adet';
    int? fiyatGrubuId = mevcut?.fiyatGrubuId;

    final kaydet = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(mevcut == null ? 'Yeni Miktar Kademesi' : 'Kademeyi Düzenle'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: TextField(
                controller: miktarCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Min. Miktar', hintText: 'Örn: 10'),
              )),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                value: birim,
                decoration: const InputDecoration(labelText: 'Birim'),
                items: const [
                  DropdownMenuItem(value: 'adet', child: Text('Adet')),
                  DropdownMenuItem(value: 'koli', child: Text('Koli')),
                  DropdownMenuItem(value: 'kg', child: Text('Kg')),
                ],
                onChanged: (v) => setD(() => birim = v ?? 'adet'),
              )),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: fiyatCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Bu Miktar ve Üzeri İçin Birim Fiyat', suffixText: '₺'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: fiyatGrubuId,
              decoration: const InputDecoration(labelText: 'Hangi Bayi Grubu İçin?'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tüm Bayiler (Genel)')),
                ..._gruplar.map((g) => DropdownMenuItem(value: g.id, child: Text(g.ad))),
              ],
              onChanged: (v) => setD(() => fiyatGrubuId = v),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      )),
    );
    if (kaydet != true) return;

    final minMiktar = double.tryParse(miktarCtrl.text.replaceAll(',', '.'));
    final fiyat = double.tryParse(fiyatCtrl.text.replaceAll(',', '.'));
    if (minMiktar == null || minMiktar <= 0 || fiyat == null || fiyat <= 0) {
      if (mounted) BildirimServisi.uyari(context, 'Geçerli miktar ve fiyat girin');
      return;
    }
    await _depo.kademeEkle(FiyatKademesiModel(
      id: mevcut?.id, globalId: mevcut?.globalId,
      urunId: widget.urun.id!, fiyatGrubuId: fiyatGrubuId,
      minMiktar: minMiktar, birim: birim, fiyat: fiyat,
    ));
    await _yukle();
    if (mounted) BildirimServisi.basari(context, 'Kademe kaydedildi ✓');
  }

  Future<void> _sil(FiyatKademesiModel k) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kademeyi Sil'),
        content: Text('${k.minMiktar.toStringAsFixed(0)}+ ${k.birim} kademesi silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true || k.id == null) return;
    await _depo.kademeSil(k.id!);
    await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    return _Kart(baslik: 'Toptan Miktar Kademeleri', children: [
      if (_yukleniyor)
        const Padding(padding: EdgeInsets.all(16), child: const TsYukleniyor())
      else if (_kademeler.isEmpty)
        Padding(
          padding: const EdgeInsets.all(4),
          child: Text('Henüz kademe tanımlanmadı. Örn: "10+ adet alana ₺X" gibi '
              'miktar bazlı indirimler burada tanımlanır.',
              style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
        )
      else
        ..._kademeler.map((k) => InkWell(
          onTap: () => _kademeEkleDuzenle(k),
          onLongPress: () => _sil(k),
          child: _Satir(
            '${k.minMiktar.toStringAsFixed(0)}+ ${k.birim} · ${_grupAdi(k.fiyatGrubuId)}',
            ParaUtils.formatla(k.fiyat), bold: true,
          ),
        )),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _kademeEkleDuzenle(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Kademe Ekle'),
        ),
      ),
    ]);
  }
}

class _HareketSekmesi extends ConsumerStatefulWidget {
  final int urunId;
  const _HareketSekmesi({required this.urunId});
  @override
  ConsumerState<_HareketSekmesi> createState() => _HareketSekmesiState();
}

class _HareketSekmesiState extends ConsumerState<_HareketSekmesi> {
  final _depo = StokDeposu();
  List<StokHareketModel> _hareketler = [];
  bool _yukleniyor = true;
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      setState(() => _yukleniyor = true);
      final h = await _depo.hareketleriGetir(widget.urunId, limit: 50);
      if (mounted) setState(() { _hareketler = h; _yukleniyor = false; });
    } catch (e) {
      // 🔴 DÜZELTME: Hata durumunda _yukleniyor hiç false yapılmıyordu
      // — stok hareketleri çekilemezse ekran SONSUZA KADAR "yükleniyor"
      // durumunda kalıyordu.
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const TsYukleniyor();
    if (_hareketler.isEmpty) return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history_outlined, size: 48, color: context.textSecondary),
        const SizedBox(height: 8),
        Text('Stok hareketi yok', style: TextStyle(color: context.textSecondary)),
      ]));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _hareketler.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final h   = _hareketler[i];
        final mik = h.miktar;
        final pozitif = mik > 0;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.cardBg, borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Color.fromARGB(26, (pozitif ? Colors.green : Colors.red).red, (pozitif ? Colors.green : Colors.red).green, (pozitif ? Colors.green : Colors.red).blue),
                shape: BoxShape.circle),
              child: Icon(
                pozitif ? Icons.add : Icons.remove,
                color: pozitif ? Colors.green : Colors.red, size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.aciklama ?? h.hareketTuru,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              Text(_fmt.format(h.tarih),
                  style: TextStyle(fontSize: 11, color: context.textSecondary)),
            ])),
            Text('${pozitif ? '+' : ''}${mik.toStringAsFixed(mik.truncateToDouble() == mik ? 0 : 2)}',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15,
                    color: pozitif ? Colors.green : Colors.red)),
          ]),
        );
      },
    );
  }
}

class _Kart extends StatelessWidget {
  final String? baslik;
  final List<Widget> children;
  const _Kart({required this.children, this.baslik});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: context.cardBg, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 6)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (baslik != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Text(baslik!, style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13, color: AppRenkler.primary))),
      ...children,
    ]),
  );
}

class _Satir extends StatelessWidget {
  final String etiket, deger; final bool bold;
  const _Satir(this.etiket, this.deger, {this.bold = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: TsRenk.ayirac(context)))),
    child: Row(children: [
      Text(etiket, style: TextStyle(fontSize: 13, color: context.textSecondary)),
      const Spacer(),
      Text(deger, style: TextStyle(
          fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
    ]),
  );
}

// 🔴 YENİ: Şube bazlı stok görünürlüğü — derin analizde bulunan
// "sube_urun tablosu var ama hiç kullanılmıyor" eksikliğinin bir
// parçası olarak eklendi. urunler.stok (toplam) ile bu sekmedeki
// şube dağılımının TOPLAMI eşleşmelidir; eşleşmiyorsa bu, o ürünün
// henüz hiç şube bazlı hareket görmediği (eski/göç edilmemiş veri)
// anlamına gelir.
class _SubeStokSekmesi extends StatefulWidget {
  final UrunModel urun;
  const _SubeStokSekmesi({required this.urun});
  @override
  State<_SubeStokSekmesi> createState() => _SubeStokSekmesiState();
}

class _SubeStokSekmesiState extends State<_SubeStokSekmesi> {
  final _depo = SubeUrunDeposu();
  List<Map<String, dynamic>> _satirlar = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      setState(() => _yukleniyor = true);
      final s = await _depo.tumSubelerdekiStok(widget.urun.id!);
      if (mounted) setState(() { _satirlar = s; _yukleniyor = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('Şube stok yükleme hatası: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const TsYukleniyor();

    final subeToplami = _satirlar.fold<double>(0, (s, r) => s + ((r['stok'] as num?)?.toDouble() ?? 0));
    final toplamStok = widget.urun.stok;
    final tutmuyor = (subeToplami - toplamStok).abs() > 0.001;

    return RefreshIndicator(
      onRefresh: _yukle,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        _Kart(baslik: 'Toplam Stok', children: [
          _Satir('Toplam (tüm şubeler)', '${toplamStok.toStringAsFixed(2)} ${widget.urun.birimAdi}', bold: true),
          if (_satirlar.isNotEmpty)
            _Satir('Şubelerin toplamı', subeToplami.toStringAsFixed(2)),
        ]),
        if (tutmuyor && _satirlar.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Şube toplamı, genel toplamla tam eşleşmiyor. Bu ürün için '
                  'henüz Stok Sayımı yapılmamış olabilir — sayım yaptığınızda '
                  'düzelir.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                )),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        if (_satirlar.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text('Bu ürün için şube bazlı stok kaydı yok',
                style: TextStyle(color: context.textSecondary))),
          )
        else
          _Kart(baslik: 'Şubelere Göre Dağılım', children: _satirlar.map((r) {
            final subeAdi = r['sube_adi'] as String? ?? 'Bilinmeyen Şube';
            final stok = (r['stok'] as num?)?.toDouble() ?? 0;
            final kritik = (r['kritik_stok'] as num?)?.toDouble() ?? 0;
            final dusuk = kritik > 0 && stok <= kritik;
            return _Satir(subeAdi,
                '${stok.toStringAsFixed(2)}${dusuk ? " ⚠️" : ""}', bold: dusuk);
          }).toList()),
      ]),
    );
  }
}
