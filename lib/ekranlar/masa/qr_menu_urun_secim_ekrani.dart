// lib/ekranlar/masa/qr_menu_urun_secim_ekrani.dart
//
// Kullanıcı isteği: "kaydetme yok, sayfa boş gelsin, arayarak veya
// barkodla listeye eklensin, listeden silme olsun." Önceki tasarım
// (4660 ürünün TAMAMINI checkbox listesi olarak gösterip sonda tek
// bir "Kaydet" butonuyla topluca kaydetme) hem çok hantaldı hem de
// kullanıcının istediği modelle uyuşmuyordu. Bu ekran artık, uygulamanın
// başka yerlerinde (Hızlı Satış sepeti gibi) kullanılan "ara → dokun
// → anında ekle" desenini takip ediyor:
//   1. Ekran AÇILDIĞINDA sadece HÂLİHAZIRDA QR menüde işaretli olan
//      ürünler listelenir (boşsa "henüz ürün yok" mesajı)
//   2. Üstteki arama kutusuna isim VEYA barkod yazılınca, eşleşen
//      ürünler ANINDA bir öneri listesinde görünür
//   3. Bir öneriye dokunulunca, o ürün ANINDA (ayrı kaydet butonuna
//      gerek olmadan) QR menü listesine eklenir ve veritabanına yazılır
//   4. Barkod okuyucu ikonuna basılınca kamera açılır, okutulan barkod
//      TAM eşleşirse ürün doğrudan eklenir
//   5. Listedeki her ürünün yanında bir "kaldır" ikonu var — dokununca
//      ANINDA listeden ve veritabanından kaldırılır
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../satis/widgets/kamera_paneli.dart';

class QrMenuUrunSecimEkrani extends StatefulWidget {
  const QrMenuUrunSecimEkrani({super.key});

  @override
  State<QrMenuUrunSecimEkrani> createState() => _QrMenuUrunSecimEkraniState();
}

class _QrMenuUrunSecimEkraniState extends State<QrMenuUrunSecimEkrani> {
  // Kullanıcı isteği: "ürünlerin resmi kartda gözüksün." Önce cihazın
  // kendi dosyasını (hızlı, internetsiz) dener; yoksa bulut adresini
  // (resimUrl) yükler; o da yoksa nötr bir ikon gösterir.
  Widget _resimGoster(UrunModel u, {double boyut = 44}) {
    Widget icerik;
    // 🔴 DÜZELTME (performans denetimi): cacheWidth/cacheHeight yoktu —
    // kamera fotoğrafı $boyut px'lik bir kutuda tam çözünürlükte decode
    // ediliyordu (bellek/jank riski, ürün fotoğraflı menülerde scroll
    // sırasında hissedilir).
    final px = (boyut * MediaQuery.of(context).devicePixelRatio).round();
    final yerelYol = u.resimYolu;
    if (yerelYol != null && yerelYol.isNotEmpty && File(yerelYol).existsSync()) {
      icerik = Image.file(File(yerelYol), width: boyut, height: boyut, fit: BoxFit.cover,
          cacheWidth: px, cacheHeight: px,
          errorBuilder: (_, __, ___) => _resimYer(boyut));
    } else if (u.resimUrl != null && u.resimUrl!.isNotEmpty) {
      icerik = Image.network(u.resimUrl!, width: boyut, height: boyut, fit: BoxFit.cover,
          cacheWidth: px, cacheHeight: px,
          errorBuilder: (_, __, ___) => _resimYer(boyut),
          loadingBuilder: (c, child, prog) => prog == null ? child : _resimYer(boyut));
    } else {
      icerik = _resimYer(boyut);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(TsRadius.sm), child: icerik);
  }

  Widget _resimYer(double boyut) => Container(
        width: boyut, height: boyut,
        color: TsRenk.zemin(TsRenk.primary, opaklik: 0.08),
        child: Icon(Icons.inventory_2_outlined, size: boyut * 0.5, color: TsRenk.primary),
      );

  final _depo = UrunDeposu();
  final _aramaCtrl = TextEditingController();
  final _aramaOdak = FocusNode();

  List<UrunModel> _qrListesi = [];
  List<UrunModel> _aramaSonuclari = [];
  final Set<int> _qrListesiIdler = {}; // hızlı "zaten listede mi?" kontrolü
  bool _yukleniyor = true;
  bool _araniyor = false;

  // Barkod kamerası
  MobileScannerController? _kameraCtrl;
  bool _kameraAcik = false;
  bool _flashAcik = false;

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
    _kameraCtrl?.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    final liste = await _depo.qrMenuUrunleriGetir();
    if (!mounted) return;
    setState(() {
      _qrListesi = liste;
      _qrListesiIdler..clear()..addAll(liste.map((u) => u.id!));
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
    // "ara()" fonksiyonu zaten ürün adı VE barkod alanında birlikte
    // arıyor — kullanıcı ister isim ister barkod numarası yazsın,
    // aynı arama kutusu ikisini de buluyor.
    final sonuclar = await _depo.ara(q, limit: 20, sadecaAktif: true);
    if (!mounted) return;
    setState(() {
      // Zaten listede olanları öneri sonuçlarında tekrar gösterme
      _aramaSonuclari = sonuclar.where((u) => !_qrListesiIdler.contains(u.id)).toList();
      _araniyor = false;
    });
  }

  Future<void> _urunEkle(UrunModel u) async {
    if (u.id == null || _qrListesiIdler.contains(u.id)) return;
    await _depo.qrMenuDurumDegistir(u.id!, true);
    if (!mounted) return;
    setState(() {
      _qrListesi = [..._qrListesi, u]..sort((a, b) => a.urunAdi.compareTo(b.urunAdi));
      _qrListesiIdler.add(u.id!);
      _aramaCtrl.clear();
      _aramaSonuclari = [];
    });
    BildirimServisi.basari(context, '${u.urunAdi} QR menüye eklendi');
    _aramaOdak.requestFocus();
  }

  Future<void> _urunKaldir(UrunModel u) async {
    if (u.id == null) return;
    // Kullanıcı isteği: "silme işlemi de silinsin mi diye uyarsın."
    // Yanlışlıkla dokunup ürünü QR menüden düşürmeyi önlemek için
    // onay soruluyor.
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('QR Menüden Kaldır'),
        content: Text('"${u.urunAdi}" ürünü QR menüden kaldırılsın mı? '
            'Müşteriler bu ürünü artık web menüde göremeyecek.'),
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
    await _depo.qrMenuDurumDegistir(u.id!, false);
    if (!mounted) return;
    setState(() {
      _qrListesi = _qrListesi.where((x) => x.id != u.id).toList();
      _qrListesiIdler.remove(u.id);
    });
    if (mounted) BildirimServisi.basari(context, '${u.urunAdi} QR menüden kaldırıldı');
  }

  void _kamerayiAc() {
    _kameraCtrl = MobileScannerController();
    setState(() => _kameraAcik = true);
  }

  Future<void> _barkodOkundu(String barkod) async {
    setState(() => _kameraAcik = false);
    _kameraCtrl?.dispose();
    _kameraCtrl = null;
    final urun = await _depo.barkodlaGetir(barkod);
    if (!mounted) return;
    if (urun == null) {
      BildirimServisi.hata(context, 'Bu barkodla eşleşen ürün bulunamadı');
      return;
    }
    if (_qrListesiIdler.contains(urun.id)) {
      BildirimServisi.uyari(context, '${urun.urunAdi} zaten listede');
      return;
    }
    await _urunEkle(urun);
  }

  String _fiyatAltYazi(UrunModel u) =>
      '${u.satisFiyati.toStringAsFixed(2)} ₺${u.anaGrup != null ? " · ${u.anaGrup}" : ""}';

  @override
  Widget build(BuildContext context) {
    if (_kameraAcik && _kameraCtrl != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SatisKameraPaneli(
          controller: _kameraCtrl!,
          flash: _flashAcik,
          onBarkod: _barkodOkundu,
          onKapat: () {
            setState(() => _kameraAcik = false);
            _kameraCtrl?.dispose();
            _kameraCtrl = null;
          },
          onFlashToggle: () {
            setState(() => _flashAcik = !_flashAcik);
            _kameraCtrl?.toggleTorch();
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'QR Menü Ürünleri',
        altBaslik: _yukleniyor ? null : '${_qrListesi.length} ürün web menüde görünüyor',
        gradyanli: true,
        // ÖNCEDEN burada bir "Kaydet" butonu vardı — artık her
        // ekleme/kaldırma anında kaydedildiği için gerek kalmadı.
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(TsBosluk.lg),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _aramaCtrl,
                  focusNode: _aramaOdak,
                  decoration: InputDecoration(
                    hintText: 'Ürün adı veya barkod ile ara...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: TsRenk.zemin(TsRenk.notr, opaklik: 0.06),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(TsRadius.md), borderSide: BorderSide.none),
                    isDense: true,
                    suffixIcon: _aramaCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _aramaCtrl.clear(),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: TsBosluk.sm),
              Container(
                decoration: BoxDecoration(
                    color: TsRenk.kart(context),
                    borderRadius: BorderRadius.circular(TsRadius.md),
                    border: Border.all(color: TsRenk.ayirac(context)),
                    boxShadow: TsGolge.yumusak),
                child: IconButton(
                  icon: Icon(Icons.qr_code_scanner, color: TsRenk.primary),
                  tooltip: 'Barkod Okut',
                  onPressed: _kamerayiAc,
                ),
              ),
            ]),
            // Arama sonuçları — yazarken anında öneri olarak görünür,
            // dokununca ANINDA listeye eklenir.
            if (_araniyor)
              const Padding(
                padding: EdgeInsets.only(top: TsBosluk.md),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_aramaSonuclari.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: TsBosluk.sm),
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                    color: TsRenk.kart(context),
                    borderRadius: BorderRadius.circular(TsRadius.lg),
                    border: Border.all(color: TsRenk.ayirac(context)),
                    boxShadow: TsGolge.yumusak),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(TsBosluk.sm),
                  itemCount: _aramaSonuclari.length,
                  separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.xs),
                  itemBuilder: (ctx, i) {
                    final u = _aramaSonuclari[i];
                    return TsKart.liste(
                      baslik: u.urunAdi,
                      altBaslik: _fiyatAltYazi(u),
                      ikon: ClipRRect(
                        borderRadius: BorderRadius.circular(TsRadius.sm),
                        child: _resimGoster(u, boyut: 40),
                      ),
                      sagAksiyon: Icon(Icons.add_circle_rounded, color: TsRenk.basarili, size: 26),
                      onTap: () => _urunEkle(u),
                    );
                  },
                ),
              )
            else if (_aramaCtrl.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: TsBosluk.md),
                child: Text('Eşleşen ürün bulunamadı (veya zaten listede)',
                    style: TsMetin.govde.copyWith(color: TsRenk.metinIkincil(context))),
              ),
          ]),
        ),
        Divider(height: 1, color: TsRenk.ayirac(context)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TsBosluk.lg, vertical: TsBosluk.sm),
          child: Row(children: [
            Text('QR MENÜDE GÖRÜNEN ÜRÜNLER', style: TsMetin.etiket.copyWith(color: TsRenk.metinIkincil(context))),
            const Spacer(),
            TsBadge(metin: '${_qrListesi.length} ürün', tur: TsBadgeTuru.bilgi),
          ]),
        ),
        Expanded(
          child: _yukleniyor
              ? const TsYukleniyor(iskelet: true)
              : _qrListesi.isEmpty
                  ? TsBosDurum(
                      ikon: Icons.qr_code_2,
                      baslik: 'Henüz QR menüde ürün yok',
                      altyazi: 'Yukarıdaki arama kutusundan ürün adı veya barkod ile arayıp ekleyin',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: TsBosluk.lg, vertical: TsBosluk.sm),
                      itemCount: _qrListesi.length,
                      separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
                      itemBuilder: (ctx, i) {
                        final u = _qrListesi[i];
                        return TsKart.liste(
                          baslik: u.urunAdi,
                          altBaslik: _fiyatAltYazi(u),
                          ikon: ClipRRect(
                            borderRadius: BorderRadius.circular(TsRadius.sm),
                            child: _resimGoster(u, boyut: 44),
                          ),
                          sagAksiyon: IconButton(
                            icon: Icon(Icons.delete_outline, color: TsRenk.hata),
                            tooltip: 'Listeden Kaldır',
                            onPressed: () => _urunKaldir(u),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
