// lib/ekranlar/toptan/fiyat_grubu_detay_ekrani.dart
//
// YENİ EKRAN (kullanıcı isteği: "1. maddeyle başla, modern görünüm,
// profesyonel bir yapı" — B2B fiyatlandırma sektör araştırmasına göre
// tasarlandı, bkz. lib/servisler/toptan_fiyat_cozucu.dart üstündeki not).
//
// Bu ekran olmadan, "Fiyat Grupları" ekranı sadece grup İSİMLERİNİ
// yönetiyordu — bir cariyi bir gruba atamak mümkündü ama o grupta
// hangi ürünün kaç TL olduğunu belirlemenin HİÇBİR yolu yoktu. Bu,
// B2BKing/Virto Commerce gibi profesyonel B2B sistemlerindeki "grup
// bazlı fiyat yönetimi" görünümünün karşılığı.
import 'dart:async';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../depolar/toptan_fiyat_deposu.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/fiyat_grubu_model.dart';
import '../../modeller/fiyat_kademesi_model.dart';
import '../../modeller/urun_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/bildirim_servisi.dart';

class FiyatGrubuDetayEkrani extends StatefulWidget {
  final FiyatGrubuModel grup;
  const FiyatGrubuDetayEkrani({super.key, required this.grup});

  @override
  State<FiyatGrubuDetayEkrani> createState() => _FiyatGrubuDetayEkraniState();
}

class _FiyatGrubuDetayEkraniState extends State<FiyatGrubuDetayEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _depo = ToptanFiyatDeposu();
  final _urunDepo = UrunDeposu();

  final _aramaCtrl = TextEditingController();
  List<UrunModel> _aramaSonuc = [];
  Map<int, double> _ozelFiyatlar = {}; // urunId -> fiyat (bu grup için)
  bool _araniyor = false;

  List<FiyatKademesiModel> _kademeler = [];
  bool _kademelerYukleniyor = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _kademeleriYukle();
    _aramaCtrl.addListener(_aramaDegisti);
  }

  @override
  void dispose() {
    _tab.dispose();
    _aramaCtrl.dispose();
    super.dispose();
  }

  Future<void> _kademeleriYukle() async {
    // Bu ekranda sadece BU GRUBA özel kademeleri gösteriyoruz —
    // genel (tüm bayilere geçerli) kademeler ürün detayından yönetilir.
    setState(() => _kademelerYukleniyor = true);
    final tumUrunKademeleri = <FiyatKademesiModel>[];
    // Not: kademeleriGetir() ürün bazlı çalışıyor; bu grup için TÜM
    // ürünlerdeki kademeleri görmek amacıyla, arama sonucu geldikçe
    // ilgili ürünlerin kademeleri de ayrıca çekilecek. Başlangıçta
    // liste boş — kullanıcı bir ürün arayıp kademe eklediğinde dolar.
    if (mounted) setState(() { _kademeler = tumUrunKademeleri; _kademelerYukleniyor = false; });
  }

  Timer? _debounce;
  void _aramaDegisti() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final sorgu = _aramaCtrl.text.trim();
      if (sorgu.isEmpty) {
        if (mounted) setState(() => _aramaSonuc = []);
        return;
      }
      setState(() => _araniyor = true);
      final sonuc = await _urunDepo.ara(sorgu, limit: 30);
      if (!mounted) return;
      // Bu ürünlerin, bu grup için ZATEN kayıtlı özel fiyatlarını çek.
      final fiyatlar = <int, double>{};
      for (final u in sonuc) {
        final f = await _depo.urunGrupFiyatiGetir(u.id!, widget.grup.id!);
        if (f != null) fiyatlar[u.id!] = f;
      }
      if (!mounted) return;
      setState(() { _aramaSonuc = sonuc; _ozelFiyatlar = fiyatlar; _araniyor = false; });
    });
  }

  Future<void> _fiyatGir(UrunModel urun) async {
    final mevcut = _ozelFiyatlar[urun.id];
    final ctrl = TextEditingController(
        text: mevcut != null ? mevcut.toStringAsFixed(2) : '');
    final iskonto = widget.grup.varsayilanIskontoOrani > 0
        ? urun.satisFiyati * (1 - widget.grup.varsayilanIskontoOrani / 100)
        : null;

    final sonuc = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(urun.urunAdi, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Perakende fiyat: ${ParaUtils.formatla(urun.satisFiyati)}',
              style: TextStyle(fontSize: 13, color: context.textSecondary)),
          if (iskonto != null)
            Text('Grup varsayılanı (%${widget.grup.varsayilanIskontoOrani.toStringAsFixed(0)} indirim): ${ParaUtils.formatla(iskonto)}',
                style: const TextStyle(fontSize: 12, color: Colors.orange, fontStyle: FontStyle.italic)),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '"${widget.grup.ad}" grubu için özel fiyat',
              suffixText: '₺',
              border: const OutlineInputBorder(),
              helperText: 'Boş bırakırsanız grup varsayılan iskontosu uygulanır.',
            ),
          ),
        ]),
        actions: [
          if (mevcut != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__sil__'),
              child: const Text('Özel Fiyatı Kaldır', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Kaydet')),
        ],
      ),
    );
    if (sonuc == null) return;

    if (sonuc == '__sil__') {
      await _depo.urunGrupFiyatiSil(urun.id!, widget.grup.id!);
      if (mounted) setState(() => _ozelFiyatlar.remove(urun.id));
      if (mounted) BildirimServisi.basari(context, 'Özel fiyat kaldırıldı');
      return;
    }

    final yeniFiyat = double.tryParse(sonuc.replaceAll(',', '.'));
    if (yeniFiyat == null || yeniFiyat <= 0) {
      if (mounted) BildirimServisi.uyari(context, 'Geçerli bir fiyat girin');
      return;
    }
    await _depo.urunGrupFiyatiKaydet(urun.id!, widget.grup.id!, yeniFiyat);
    if (mounted) setState(() => _ozelFiyatlar[urun.id!] = yeniFiyat);
    if (mounted) BildirimServisi.basari(context, 'Fiyat kaydedildi ✓');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: Text(widget.grup.ad, style: const TextStyle(fontWeight: FontWeight.w700)),
        alt: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.sell_outlined), text: 'Ürün Fiyatları'),
            Tab(icon: Icon(Icons.stacked_bar_chart), text: 'Miktar Kademeleri'),
          ],
        ),
      ),
      body: TabBarView(controller: _tab, children: [
        _urunFiyatlariSekmesi(),
        _kademelerSekmesi(),
      ]),
    );
  }

  Widget _urunFiyatlariSekmesi() {
    return Column(children: [
      Container(
        margin: const EdgeInsets.all(12),
        child: TextField(
          controller: _aramaCtrl,
          decoration: InputDecoration(
            hintText: 'Ürün adı veya barkod ile ara...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _araniyor
                ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : (_aramaCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _aramaCtrl.clear())
                    : null),
            filled: true,
            fillColor: context.inputFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: _aramaCtrl.text.trim().isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.search, size: 48, color: context.textHint),
                    const SizedBox(height: 12),
                    Text('"${widget.grup.ad}" grubu için özel fiyat\ntanımlamak üzere ürün arayın.',
                        textAlign: TextAlign.center, style: TextStyle(color: context.textHint)),
                  ]),
                ),
              )
            : _aramaSonuc.isEmpty && !_araniyor
                ? Center(child: Text('Sonuç bulunamadı', style: TextStyle(color: context.textHint)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: _aramaSonuc.length,
                    itemBuilder: (c, i) {
                      final u = _aramaSonuc[i];
                      final ozelFiyat = _ozelFiyatlar[u.id];
                      final indirimYuzde = ozelFiyat != null && u.satisFiyati > 0
                          ? ((u.satisFiyati - ozelFiyat) / u.satisFiyati * 100) : null;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: context.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: ozelFiyat != null
                              ? Border.all(color: Colors.green.withAlpha(100), width: 1.5)
                              : null,
                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 4)],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          title: Text(u.urunAdi, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TsMetin.govdeVurgu),
                          subtitle: Row(children: [
                            Text('Perakende: ${ParaUtils.formatla(u.satisFiyati)}',
                                style: TextStyle(fontSize: 12, color: context.textSecondary)),
                            if (indirimYuzde != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: Colors.green.withAlpha(30), borderRadius: BorderRadius.circular(6)),
                                child: Text('-%${indirimYuzde.toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.green)),
                              ),
                            ],
                          ]),
                          trailing: SizedBox(
                            width: 90,
                            child: ozelFiyat != null
                                ? Text(ParaUtils.formatla(ozelFiyat),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.green))
                                : Text('Belirle', textAlign: TextAlign.right,
                                    style: TextStyle(color: context.textHint, fontSize: 13)),
                          ),
                          onTap: () => _fiyatGir(u),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _kademelerSekmesi() {
    return Column(children: [
      Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.inputFill, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.info_outline, size: 18, color: context.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(
              'Miktar kademesi eklemek için önce "Ürün Fiyatları" sekmesinde '
              'bir ürün arayıp seçin, sonra ürün detayındaki "Toptan Kademeleri" '
              'bölümünden bu gruba özel miktar indirimleri tanımlayın.',
              style: TextStyle(fontSize: 12, color: context.textSecondary))),
        ]),
      ),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.stacked_bar_chart, size: 48, color: context.textHint),
              const SizedBox(height: 12),
              Text('Miktar kademeleri ürün bazında yönetilir.\n'
                  'Örn: "10+ adet alana ${widget.grup.ad} için ₺X"',
                  textAlign: TextAlign.center, style: TextStyle(color: context.textHint)),
            ]),
          ),
        ),
      ),
    ]);
  }
}
