// lib/ekranlar/urun/fiyat_gor_ekrani.dart
//
// Kullanıcı isteği: "dashboardda fiyat gör ekranı yapabiliriz barkod
// okutma ve büyük fiyat" — müşterinin elindeki ürünün fiyatını hızlıca
// görmek için, tam bir satış işlemi açmadan kullanılan basit bir
// "fiyat kontrol" ekranı (marketlerdeki "fiyat kontrol terminali" gibi).
// Art arda birden fazla ürün taranabilir, hiçbir veri değişmez (salt
// okunur — stok/satış etkilenmez).
import 'package:flutter/material.dart';
import '../../servisler/barkod_servisi.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class FiyatGorEkrani extends StatelessWidget {
  const FiyatGorEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Fiyat Gör',
      ),
      body: const SafeArea(child: FiyatGorIcerik(otomatikTara: true)),
    );
  }
}

/// Gerçek "fiyat gör" mantığı — hem bağımsız ekranda (yukarıda) hem de
/// Dashboard'un Ana Menü/İstatistikler geçişine 3. sekme olarak
/// GÖMÜLEBİLMESİ için Scaffold'dan bağımsız, tekrar kullanılabilir bir
/// widget olarak ayrıldı.
class FiyatGorIcerik extends StatefulWidget {
  /// true ise widget ilk açıldığında otomatik tarama başlatır (bağımsız
  /// ekran için uygun); Dashboard içine gömülüyken kullanıcı elle
  /// başlatmalı diye false verilir (aksi halde her sekme değişiminde
  /// kamera açılırdı).
  final bool otomatikTara;
  const FiyatGorIcerik({super.key, this.otomatikTara = false});

  @override
  State<FiyatGorIcerik> createState() => _FiyatGorIcerikState();
}

class _FiyatGorIcerikState extends State<FiyatGorIcerik> {
  final _barkodSrv = BarkodServisi();
  final _urunDepo = UrunDeposu();
  final _araCtrl = TextEditingController();

  UrunModel? _urun;
  String? _hata;
  bool _yukleniyor = false;

  @override
  void initState() {
    super.initState();
    if (widget.otomatikTara) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tara());
    }
  }

  @override
  void dispose() {
    _araCtrl.dispose();
    super.dispose();
  }

  Future<void> _tara() async {
    final barkod = await _barkodSrv.barkodTara(context);
    if (barkod == null || barkod.trim().isEmpty || !mounted) return;
    await _urunGetir(barkod.trim());
  }

  Future<void> _urunGetir(String barkod) async {
    setState(() { _yukleniyor = true; _hata = null; });
    try {
      final u = await _urunDepo.barkodlaGetir(barkod) ??
          await _urunDepo.kodlaGetir(barkod);
      if (!mounted) return;
      setState(() {
        _urun = u;
        _hata = u == null ? 'Bu barkodla eşleşen ürün bulunamadı: $barkod' : null;
        _yukleniyor = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _hata = 'Hata: $e'; _yukleniyor = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Manuel barkod/kod arama (kamera olmadan da kullanılabilsin)
        TextField(
          controller: _araCtrl,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Barkod veya ürün kodu girin...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Kamerayla Tara',
              onPressed: _tara,
            ),
            filled: true,
            fillColor: TsRenk.kart(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onSubmitted: (v) { if (v.trim().isNotEmpty) _urunGetir(v.trim()); },
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Center(
            child: _yukleniyor
                ? const CircularProgressIndicator()
                : _hata != null
                    ? _hataGoster(_hata!)
                    : _urun != null
                        ? _fiyatGoster(_urun!)
                        : _bosDurum(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: TsButon(
            metin: 'Yeni Ürün Tara',
            ikon: Icons.qr_code_scanner_rounded,
            tamGenislik: true,
            onPressed: _tara,
          ),
        ),
      ]),
    );
  }

  Widget _bosDurum() => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.price_check_rounded, size: 96, color: TsRenk.metinIkincil(context)),
    const SizedBox(height: 16),
    Text('Fiyatını görmek istediğiniz ürünü tarayın',
        style: TextStyle(fontSize: 15, color: TsRenk.metinIkincil(context))),
  ]);

  Widget _hataGoster(String mesaj) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.error_outline_rounded, size: 72, color: TsRenk.hata),
    const SizedBox(height: 16),
    Text(mesaj, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: TsRenk.hata)),
  ]);

  Widget _fiyatGoster(UrunModel u) {
    final stokYok = u.stok <= 0;
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(u.urunAdi,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        if (u.anaGrup != null && u.anaGrup!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(u.anaGrup!,
                style: TextStyle(fontSize: 13, color: TsRenk.metinIkincil(context))),
          ),
        const SizedBox(height: 24),
        // BÜYÜK FİYAT — kullanıcının açıkça istediği kısım
        Text(
          '${ParaUtils.formatla(u.satisFiyati)} ₺',
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2E7D32),
            height: 1,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: stokYok ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            stokYok ? 'Stokta Yok' : 'Stok: ${u.stok.toStringAsFixed(0)} ${u.birimAdi}',
            style: TsMetin.govdeVurgu.copyWith(color: stokYok ? Colors.red.shade700 : Colors.green.shade700),
          ),
        ),
        if (u.barkod != null && u.barkod!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(u.barkod!,
                style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context), letterSpacing: 1)),
          ),
      ]),
    );
  }
}
