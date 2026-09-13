// lib/ekranlar/toptan/toptan_urun_listesi_ekrani.dart
//
// Kullanıcı isteği: "ürünlerde de buton eklesek, toptan satış tıkladık
// öyle kaydettik, bu toptan satış listesinde gözükse diğerleri
// gözükmesin. O ekranda da alış/kdvli gibi mantığı profesyonel olsun."
// qr_menu_urun_secim_ekrani.dart ile AYNI, kanıtlanmış "ara → dokun →
// anında ekle" desenini kullanıyor, ama toptan satış için PROFESYONEL
// fiyat detaylarını (alış, KDV dahil alış, toptan fiyatı, koli bilgisi)
// gösteriyor.
import 'dart:io';
import 'package:flutter/material.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';

class ToptanUrunListesiEkrani extends StatefulWidget {
  const ToptanUrunListesiEkrani({super.key});

  @override
  State<ToptanUrunListesiEkrani> createState() => _ToptanUrunListesiEkraniState();
}

class _ToptanUrunListesiEkraniState extends State<ToptanUrunListesiEkrani> {
  final _depo = UrunDeposu();
  final _aramaCtrl = TextEditingController();
  final _aramaOdak = FocusNode();

  List<UrunModel> _liste = [];
  List<UrunModel> _aramaSonuclari = [];
  final Set<int> _listeIdler = {};
  bool _yukleniyor = true;
  bool _araniyor = false;

  @override
  void initState() {
    super.initState();
    _yukle();
    _aramaCtrl.addListener(_aramaYap);
  }

  @override
  void dispose() {
    _aramaCtrl.dispose();
    _aramaOdak.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    final liste = await _depo.toptanSatisUrunleriGetir();
    if (!mounted) return;
    setState(() {
      _liste = liste;
      _listeIdler..clear()..addAll(liste.map((u) => u.id!));
      _yukleniyor = false;
    });
  }

  Future<void> _aramaYap() async {
    final q = _aramaCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _aramaSonuclari = []);
      return;
    }
    setState(() => _araniyor = true);
    final sonuclar = await _depo.ara(q, limit: 20, sadecaAktif: true);
    if (!mounted) return;
    setState(() {
      _aramaSonuclari = sonuclar.where((u) => !_listeIdler.contains(u.id)).toList();
      _araniyor = false;
    });
  }

  Future<void> _urunEkle(UrunModel u) async {
    if (u.id == null || _listeIdler.contains(u.id)) return;
    await _depo.toptanSatistaDurumDegistir(u.id!, true);
    if (!mounted) return;
    setState(() {
      _liste = [..._liste, u]..sort((a, b) => a.urunAdi.compareTo(b.urunAdi));
      _listeIdler.add(u.id!);
      _aramaCtrl.clear();
      _aramaSonuclari = [];
    });
    BildirimServisi.basari(context, '${u.urunAdi} toptan satış listesine eklendi');
    _aramaOdak.requestFocus();
  }

  Future<void> _urunKaldir(UrunModel u) async {
    if (u.id == null) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Toptan Listeden Kaldır'),
        content: Text('"${u.urunAdi}" ürünü toptan satış listesinden kaldırılsın mı?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    await _depo.toptanSatistaDurumDegistir(u.id!, false);
    if (!mounted) return;
    setState(() {
      _liste = _liste.where((x) => x.id != u.id).toList();
      _listeIdler.remove(u.id);
    });
    if (mounted) BildirimServisi.basari(context, '${u.urunAdi} listeden kaldırıldı');
  }

  Widget _resimGoster(UrunModel u, {double boyut = 48}) {
    Widget icerik;
    // 🔴 DÜZELTME (performans denetimi): cacheWidth/cacheHeight olmadan
    // bu resim (kamera fotoğrafı birkaç MB olabilir) tam çözünürlükte
    // decode ediliyordu — sadece $boyut px gösterilirken bile. Listede
    // çok sayıda ürün fotoğrafı varsa scroll sırasında bellek/jank riski.
    final px = (boyut * MediaQuery.of(context).devicePixelRatio).round();
    final yerelYol = u.resimYolu;
    if (yerelYol != null && yerelYol.isNotEmpty && File(yerelYol).existsSync()) {
      icerik = Image.file(File(yerelYol), width: boyut, height: boyut, fit: BoxFit.cover,
          cacheWidth: px, cacheHeight: px,
          errorBuilder: (_, __, ___) => _resimYer(boyut));
    } else if (u.resimUrl != null && u.resimUrl!.isNotEmpty) {
      icerik = Image.network(u.resimUrl!, width: boyut, height: boyut, fit: BoxFit.cover,
          cacheWidth: px, cacheHeight: px,
          errorBuilder: (_, __, ___) => _resimYer(boyut));
    } else {
      icerik = _resimYer(boyut);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: icerik);
  }

  Widget _resimYer(double boyut) => Container(
        width: boyut, height: boyut, color: context.inputFill,
        child: Icon(Icons.inventory_2_outlined, size: boyut * 0.5, color: context.textHint),
      );

  /// Profesyonel fiyat kırılımı satırı: Alış / Alış (KDV Dahil) / Satış / Toptan.
  Widget _fiyatSatiri(UrunModel u) {
    final stil = TextStyle(fontSize: 11, color: context.textSecondary);
    final vurgu = TextStyle(fontSize: 11, color: AppRenkler.primary, fontWeight: FontWeight.w700);
    return Wrap(spacing: 10, runSpacing: 2, children: [
      Text('Alış: ${ParaUtils.formatla(u.alisFiyat)}', style: stil),
      Text('KDV Dahil: ${ParaUtils.formatla(u.alisFiyatKdvDahil)}', style: stil),
      Text('Satış: ${ParaUtils.formatla(u.satisFiyati)}', style: stil),
      Text('Toptan: ${u.toptanFiyat > 0 ? ParaUtils.formatla(u.toptanFiyat) : "—"}', style: vurgu),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Toptan Satış Ürünleri',
        gradyanli: false,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            TextField(
              controller: _aramaCtrl,
              focusNode: _aramaOdak,
              decoration: InputDecoration(
                hintText: 'Ürün adı veya barkod ile ara...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true, fillColor: context.inputFill,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                isDense: true,
                suffixIcon: _aramaCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _aramaCtrl.clear())
                    : null,
              ),
            ),
            if (_araniyor)
              const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 2))
            else if (_aramaSonuclari.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                    color: context.cardBg, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8)]),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _aramaSonuclari.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: context.dividerColor),
                  itemBuilder: (c, i) {
                    final u = _aramaSonuclari[i];
                    return ListTile(
                      dense: true,
                      leading: _resimGoster(u, boyut: 40),
                      title: Text(u.urunAdi, style: TextStyle(fontSize: 14, color: context.textPrimary)),
                      subtitle: _fiyatSatiri(u),
                      trailing: const Icon(Icons.add_circle_outline, color: Colors.green, size: 22),
                      onTap: () => _urunEkle(u),
                    );
                  },
                ),
              )
            else if (_aramaCtrl.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Eşleşen ürün bulunamadı (veya zaten listede)',
                    style: TextStyle(fontSize: 13, color: context.textSecondary)),
              ),
          ]),
        ),
        Divider(height: 1, color: context.dividerColor),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Text('Toptan Satılan Ürünler',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textSecondary)),
            const Spacer(),
            Text('${_liste.length} ürün', style: TextStyle(fontSize: 12, color: context.textHint)),
          ]),
        ),
        Expanded(
          child: _yukleniyor
              ? const TsYukleniyor()
              : _liste.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.local_shipping_outlined, size: 48, color: context.textHint),
                          const SizedBox(height: 12),
                          Text('Henüz toptan satış ürünü yok',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.textSecondary)),
                          const SizedBox(height: 6),
                          Text('Yukarıdaki arama kutusundan ürün arayıp ekleyin',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: context.textHint)),
                        ]),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _liste.length,
                      itemBuilder: (c, i) {
                        final u = _liste[i];
                        return ListTile(
                          leading: _resimGoster(u),
                          title: Text(u.urunAdi, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: _fiyatSatiri(u),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Listeden Kaldır',
                            onPressed: () => _urunKaldir(u),
                          ),
                          isThreeLine: false,
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
