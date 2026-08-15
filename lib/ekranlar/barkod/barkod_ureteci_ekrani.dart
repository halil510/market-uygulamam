import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// lib/ekranlar/barkod/barkod_ureteci_ekrani.dart
import "dart:io";
import "dart:ui" as ui;
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:barcode_widget/barcode_widget.dart";
import "package:share_plus/share_plus.dart";
import "package:path_provider/path_provider.dart";
import "../../depolar/urun_deposu.dart";
import "../../modeller/urun_model.dart";
import "../../servisler/bildirim_servisi.dart";
import "../../tasarim_sistemi/tasarim_sistemi.dart";

class BarkodUreteciEkrani extends ConsumerStatefulWidget {
  final UrunModel? baslangicUrun;
  const BarkodUreteciEkrani({super.key, this.baslangicUrun});
  @override
  ConsumerState<BarkodUreteciEkrani> createState() => _BarkodUreteciEkraniState();
}

class _BarkodUreteciEkraniState extends ConsumerState<BarkodUreteciEkrani> {
  final _depo = UrunDeposu();
  final _barkodCtrl = TextEditingController();
  final _araCtrl = TextEditingController();
  final _repaintKey = GlobalKey();

  UrunModel? _seciliUrun;
  String _tip = "Code128";
  String _gosterilen = "";
  bool _kayit = false;
  List<UrunModel> _aramaSonuclari = [];

  static const _tipler = ["Code128", "EAN-13", "QR Code", "Code39"];

  @override
  void initState() {
    super.initState();
    if (widget.baslangicUrun != null) {
      _seciliUrun = widget.baslangicUrun;
      final b = widget.baslangicUrun!.barkod ?? "";
      _barkodCtrl.text = b;
      _gosterilen = b;
    }
  }

  @override
  void dispose() { _barkodCtrl.dispose(); _araCtrl.dispose(); super.dispose(); }

  Barcode get _barkodObj {
    switch (_tip) {
      case "EAN-13":  return Barcode.ean13();
      case "QR Code": return Barcode.qrCode();
      case "Code39":  return Barcode.code39();
      default:        return Barcode.code128();
    }
  }

  void _otomatikUret() {
    String yeni;
    if (_tip == "EAN-13") {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final b = ts.substring(ts.length - 12);
      int sum = 0;
      for (int i = 0; i < 12; i++) sum += int.parse(b[i]) * (i.isEven ? 1 : 3);
      yeni = "$b${(10 - (sum % 10)) % 10}";
    } else {
      yeni = "MP${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";
    }
    setState(() { _barkodCtrl.text = yeni; _gosterilen = yeni; });
  }

  Future<void> _ara(String q) async {
    try {  
      if (q.trim().length < 2) { setState(() => _aramaSonuclari = []); return; }
      final s = await _depo.ara(q.trim(), limit: 8);
      if (mounted) _aramaSonuclari = s;
      if (mounted) setState(() {});
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _kaydet() async {
    if (_seciliUrun == null || _gosterilen.isEmpty) {
      BildirimServisi.uyari(context, "Ürün seçin ve barkod girin");
      return;
    }
    setState(() => _kayit = true);
    try {
      // ÖNCEDEN BURADA CİDDİ BİR VERİ KAYBI HATASI VARDI: UrunModel sadece
      // 8 alanla (ad, barkod, fiyatlar, stok, birim, kdv) sıfırdan
      // oluşturuluyordu — ürünün ana grup, lot no, son kullanma tarihi,
      // resim gibi TÜM DİĞER ALANLARI varsayılan (boş/null) değerlere
      // dönüyordu. Sadece barkod eklemek isteyen kullanıcı, farkında
      // olmadan ürünün diğer bilgilerini siliyordu. copyWith kullanılarak
      // SADECE barkod alanı güncelleniyor, geri kalan her şey korunuyor.
      final guncellendi = _seciliUrun!.copyWith(barkod: _gosterilen);
      await _depo.guncelle(guncellendi);
      if (!mounted) return;
      setState(() => _seciliUrun = guncellendi);
      BildirimServisi.basari(context, "Barkod ürüne kaydedildi ✓");
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, "Kayıt hatası: $e");
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  Future<void> _paylas() async {
    if (_gosterilen.isEmpty) return;
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final f = File("${dir.path}/barkod_$_gosterilen.png");
      await f.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path)], text: "Barkod: $_gosterilen");
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, "Paylaşım hatası: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: "Barkod Üreteci",
        aksiyonlar: [
          if (_gosterilen.isNotEmpty)
            IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: _paylas, tooltip: "Paylaş"),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(TsBosluk.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Tip
          DropdownButtonFormField<String>(
            value: _tip,
            decoration: InputDecoration(labelText: "Barkod Tipi",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.qr_code_2),
                filled: true, fillColor: TsRenk.arkaplan(context)),
            items: _tipler.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) { if (v != null) setState(() => _tip = v); },
          ),
          const SizedBox(height: TsBosluk.md),
          // Değer
          Row(children: [
            Expanded(child: TsInput(
              etiket: "Barkod Değeri",
              controller: _barkodCtrl,
              oncilIkon: Icons.numbers,
              degisti: (v) => setState(() => _gosterilen = v),
            )),
            const SizedBox(width: 8),
            SizedBox(
              height: 54,
              child: TsButon(
                metin: "Üret",
                ikon: Icons.auto_fix_high,
                onPressed: _otomatikUret,
              ),
            ),
          ]),
          const SizedBox(height: TsBosluk.xl),
          // Önizleme
          if (_gosterilen.isNotEmpty) ...[
            TsKart(
              padding: const EdgeInsets.all(20),
              child: RepaintBoundary(
                key: _repaintKey,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: BarcodeWidget(
                    barcode: _barkodObj,
                    data: _gosterilen,
                    width: double.infinity,
                    height: _tip == "QR Code" ? 180 : 100,
                    drawText: true,
                    errorBuilder: (_, e) => Container(
                      height: 80, alignment: Alignment.center,
                      child: Text("Geçersiz: $e", style: TextStyle(color: TsRenk.hata))),
                  ),
                ),
              ),
            ),
            const SizedBox(height: TsBosluk.md),
          ],
          // Ürün seç
          Text("Ürüne Kaydet",
              style: TsMetin.baslikM.copyWith(color: TsRenk.metinBirincil(context))),
          const SizedBox(height: TsBosluk.sm),
          TextField(
            controller: _araCtrl,
            decoration: InputDecoration(
              hintText: "Ürün adı veya barkod ara...",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true, fillColor: TsRenk.arkaplan(context),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _seciliUrun != null
                  ? Chip(
                      label: Text(_seciliUrun!.urunAdi, overflow: TextOverflow.ellipsis),
                      onDeleted: () => setState(() { _seciliUrun = null; _araCtrl.clear(); _aramaSonuclari = []; }),
                    )
                  : null,
            ),
            onChanged: _ara,
          ),
          if (_aramaSonuclari.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TsKart(
                padding: EdgeInsets.zero,
                child: Column(children: _aramaSonuclari.map((u) => ListTile(
                  dense: true,
                  title: Text(u.urunAdi),
                  subtitle: Text(u.barkod ?? "Barkod yok"),
                  onTap: () {
                    setState(() {
                      _seciliUrun = u;
                      _aramaSonuclari = [];
                      _araCtrl.text = u.urunAdi;
                      if (u.barkod != null && _gosterilen.isEmpty) {
                        _barkodCtrl.text = u.barkod!;
                        _gosterilen = u.barkod!;
                      }
                    });
                  },
                )).toList()),
              ),
            ),
          const SizedBox(height: TsBosluk.lg),
          SizedBox(
            height: 54,
            child: TsButon(
              metin: "Ürüne Kaydet",
              ikon: Icons.save,
              tamGenislik: true,
              yukleniyor: _kayit,
              onPressed: (_kayit || _gosterilen.isEmpty || _seciliUrun == null) ? null : _kaydet,
            ),
          ),
        ]),
      ),
    );
  }
}
