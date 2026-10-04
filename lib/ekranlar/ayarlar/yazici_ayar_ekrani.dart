// lib/ekranlar/ayarlar/yazici_ayar_ekrani.dart
// v4.0 - Modern kart bazlı tasarım, WiFi/BT/Fiş tek ekranda
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../depolar/yazici_deposu.dart';
import '../../modeller/yazici_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/ayarlar_deposu.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';

part 'yazici_ayar_sekmeleri.dart';
part 'yazici_ayar_widgetlari.dart';

// ─── Renk sabitleri ───────────────────────────────────────────────────────────
const _blue   = Color(0xFF4361EE);
const _green  = Color(0xFF2E7D32);
const _purple = Color(0xFF6A1B9A);
const _orange = Color(0xFFE65100);

class YaziciAyarEkrani extends ConsumerStatefulWidget {
  /// true ise kendi Scaffold/AppBar'ını çizmez — Yazdırma Merkezi
  /// (YazdirmaMerkeziEkrani) içine sekme olarak gömülür.
  final bool gomulu;
  const YaziciAyarEkrani({super.key, this.gomulu = false});
  @override
  ConsumerState<YaziciAyarEkrani> createState() => _YaziciAyarEkraniState();
}

class _YaziciAyarEkraniState extends ConsumerState<YaziciAyarEkrani>
    with SingleTickerProviderStateMixin {
  final _yazdirma = YazdirmaServisi();
  final _depo     = YaziciDeposu();
  final _ayarlarDepo = AyarlarDeposu();
  late TabController _tab;

  List<YaziciModel>     _kayitlilar   = [];
  List<BluetoothDevice> _btCihazlar   = [];
  List<String>          _wifiCihazlar = [];
  List<UsbDevice>       _usbCihazlar  = [];
  bool _btTaraniyor   = false;
  bool _wifiTaraniyor = false;
  bool _usbTaraniyor  = false;
  bool _yukleniyor    = true;

  // Fiş ayarları
  final _firmaAdiCtrl   = TextEditingController();
  final _firmaAdresCtrl = TextEditingController();
  final _firmaTelCtrl   = TextEditingController();
  final _altYaziCtrl    = TextEditingController();
  String _kagitBoy = '80mm';
  bool   _kdvGoster = true;

  // WiFi manuel
  final _ipCtrl   = TextEditingController();
  final _portCtrl = TextEditingController(text: '9100');

  @override
  void initState() {
    super.initState();
    // Windows'ta kurulu yazıcılar sekmesi (3.) varsayılan açılır.
    _tab = TabController(length: 4, vsync: this, initialIndex: Platform.isWindows ? 2 : 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void dispose() {
    _tab.dispose();
    _firmaAdiCtrl.dispose(); _firmaAdresCtrl.dispose();
    _firmaTelCtrl.dispose(); _altYaziCtrl.dispose();
    _ipCtrl.dispose(); _portCtrl.dispose();
    super.dispose();
  }

  // ── Yükle ────────────────────────────────────────────────────────────────
  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final liste = await _depo.tumunuGetir();
      final m = await _ayarlarDepo.coguGetir(
          const ['firma_adi', 'firma_adres', 'firma_telefon', 'fis_alt_yazi', 'fis_kagit', 'fis_kdv']);
      if (!mounted) return;
      setState(() {
        _kayitlilar          = liste;
        _firmaAdiCtrl.text   = m['firma_adi']     ?? '';
        _firmaAdresCtrl.text = m['firma_adres']   ?? '';
        _firmaTelCtrl.text   = m['firma_telefon'] ?? '';
        _altYaziCtrl.text    = m['fis_alt_yazi']  ?? 'Teşekkür ederiz!';
        _kagitBoy            = m['fis_kagit']      ?? '80mm';
        _kdvGoster           = m['fis_kdv']        != '0';
        _yukleniyor          = false;
      });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ayarKaydet(String k, String v) => _ayarlarDepo.kaydet(k, v);

  Future<void> _fisAyarlariKaydet() async {
    try {
      await Future.wait([
        _ayarKaydet('firma_adi',     _firmaAdiCtrl.text.trim()),
        _ayarKaydet('firma_adres',   _firmaAdresCtrl.text.trim()),
        _ayarKaydet('firma_telefon', _firmaTelCtrl.text.trim()),
        _ayarKaydet('fis_alt_yazi',  _altYaziCtrl.text.trim()),
        _ayarKaydet('fis_kagit',     _kagitBoy),
        _ayarKaydet('fis_kdv',       _kdvGoster ? '1' : '0'),
      ]);
      if (mounted) BildirimServisi.basari(context, 'Fiş ayarları kaydedildi ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Kayıt hatası: $e');
    }
  }

  // ── WiFi ─────────────────────────────────────────────────────────────────
  Future<void> _wifiTara() async {
    setState(() { _wifiTaraniyor = true; _wifiCihazlar = []; });
    try {
      final bulunanlar = await YazdirmaServisi.wifiYazicilariTara();
      if (!mounted) return;
      setState(() => _wifiCihazlar = bulunanlar);
      if (bulunanlar.isEmpty && mounted)
        BildirimServisi.uyari(context, 'Ağda yazıcı bulunamadı. Port 9100 açık mı?');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Tarama hatası: $e');
    } finally {
      if (mounted) setState(() => _wifiTaraniyor = false);
    }
  }

  Future<void> _wifiBaglan(String ip, {int port = 9100}) async {
    final yazici = YaziciModel(tur: 'ag', adi: 'WiFi Yazıcı ($ip)',
        ip: ip, port: port, kategori: 'fis', varsayilan: true, aktif: true);
    _spinner('$ip:$port bağlanılıyor...');
    try {
      final ok = await _yazdirma.wifiBaglan(yazici);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (ok) { await _depo.ekle(yazici); await _yukle();
        if (mounted) BildirimServisi.basari(context, 'WiFi yazıcı bağlandı ✓'); }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      BildirimServisi.hata(context, 'Bağlantı hatası: $e');
    }
  }

  void _wifiManuelBaglan() => showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.wifi, color: _blue), SizedBox(width: 8), Text('Manuel IP'),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _inputField(context, _ipCtrl, 'IP Adresi', '192.168.1.100', Icons.router,
            tip: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 12),
        _inputField(context, _portCtrl, 'Port', '9100', Icons.settings_ethernet,
            tip: TextInputType.number,
            fmt: [FilteringTextInputFormatter.digitsOnly]),
        const SizedBox(height: 8),
        Text('Çoğu termal yazıcıda port: 9100',
            style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        FilledButton.icon(
          icon: const Icon(Icons.link, size: 16),
          label: const Text('Bağlan'),
          onPressed: () {
            final ip   = _ipCtrl.text.trim();
            final port = int.tryParse(_portCtrl.text.trim()) ?? 9100;
            if (ip.isEmpty) return;
            Navigator.pop(ctx);
            _wifiBaglan(ip, port: port);
          },
        ),
      ],
    ),
  );

  // ── Bluetooth ────────────────────────────────────────────────────────────
  Future<bool> _btIzinIste() async {
    if (!Platform.isAndroid) return true;
    final sonuclar = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();
    final kalici = sonuclar.values.any((v) => v.isPermanentlyDenied);
    if (kalici) {
      if (mounted) showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Bluetooth İzni Gerekli'),
        content: const Text('Ayarlar > Uygulama izinlerinden Bluetooth iznini açın.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(onPressed: () { Navigator.pop(ctx); openAppSettings(); },
              child: const Text('Ayarlara Git')),
        ],
      ));
      return false;
    }
    if (sonuclar.values.any((v) => v.isDenied)) {
      if (mounted) BildirimServisi.uyari(context, 'Bluetooth izni verilmedi');
      return false;
    }
    final btDurumu = await FlutterBluePlus.adapterState.first;
    if (btDurumu != BluetoothAdapterState.on) {
      if (mounted) showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Bluetooth Kapalı'),
        content: const Text("Yazıcı için Bluetooth'u açın."),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
      ));
      return false;
    }
    return true;
  }

  Future<void> _btTara() async {
    final izin = await _btIzinIste();
    if (!izin || !mounted) return;
    setState(() { _btTaraniyor = true; _btCihazlar = []; });
    try {
      final cihazlar = await _yazdirma.btCihazlariTara();
      if (!mounted) return;
      setState(() => _btCihazlar = cihazlar);
      if (cihazlar.isEmpty && mounted)
        BildirimServisi.uyari(context,
            'Eşleştirilmiş BT yazıcı bulunamadı.\nÖnce Bluetooth ayarlarından eşleştirin.');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Bluetooth hatası: $e');
    } finally {
      if (mounted) setState(() => _btTaraniyor = false);
    }
  }

  Future<void> _btBaglan(BluetoothDevice cihaz) async {
    final yazici = YaziciModel(tur: 'bluetooth',
        adi: cihaz.platformName.isNotEmpty ? cihaz.platformName : 'BT Yazıcı',
        cihazId: cihaz.remoteId.str, kategori: 'fis', varsayilan: true, aktif: true);
    _spinner('${yazici.adi} bağlanılıyor...');
    try {
      final ok = await _yazdirma.btBaglan(yazici, cihaz);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (ok) { await _depo.ekle(yazici); await _yukle();
        if (mounted) BildirimServisi.basari(context, '${yazici.adi} bağlandı ✓'); }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      BildirimServisi.hata(context, 'Bağlanamadı: $e');
    }
  }

  Future<void> _usbTara() async {
    if (!mounted) return;
    setState(() { _usbTaraniyor = true; _usbCihazlar = []; });
    try {
      final cihazlar = await _yazdirma.usbCihazlariTara();
      if (!mounted) return;
      setState(() => _usbCihazlar = cihazlar);
      if (cihazlar.isEmpty && mounted) {
        BildirimServisi.uyari(context,
            'USB yazıcı bulunamadı.\nKablonun takılı olduğundan emin olun.');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'USB tarama hatası: $e');
    } finally {
      if (mounted) setState(() => _usbTaraniyor = false);
    }
  }

  // ── Windows: kurulu yazıcılar ────────────────────────────────────────────
  List<String> _winYazicilar = [];
  bool _winYukleniyor = false;

  Future<void> _winYenile() async {
    setState(() => _winYukleniyor = true);
    final l = await _yazdirma.windowsYazicilar();
    if (!mounted) return;
    setState(() { _winYazicilar = l; _winYukleniyor = false; });
  }

  Future<void> _winSec(String ad) async {
    final yazici = YaziciModel(tur: 'windows', adi: ad, cihazId: ad,
        kategori: 'fis', varsayilan: true, aktif: true);
    final ok = await _yazdirma.windowsBaglan(yazici);
    if (!mounted) return;
    if (ok) {
      await _depo.ekle(yazici);
      await _yukle();
      if (mounted) BildirimServisi.basari(context, '$ad seçildi ✓');
    } else {
      BildirimServisi.hata(context, 'Yazıcıya bağlanılamadı: $ad');
    }
  }

  Widget _windowsTab() {
    if (_winYazicilar.isEmpty && !_winYukleniyor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _winYazicilar.isEmpty && !_winYukleniyor) _winYenile();
      });
    }
    final kayitli = _kayitlilar.where((y) => y.tur == 'windows').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _BaglantiDurumKarti(yazdirma: _yazdirma, onKes: () async {
        await _yazdirma.baglantiKes();
        if (!mounted) return;
        setState(() {});
        BildirimServisi.uyari(context, 'Bağlantı kesildi');
      }),
      const SizedBox(height: 16),
      _ActionButon(
        label: _winYukleniyor ? 'Yükleniyor...' : 'Yazıcıları Yenile',
        icon: _winYukleniyor ? null : Icons.refresh,
        loading: _winYukleniyor,
        onTap: _winYukleniyor ? null : _winYenile,
        renk: _orange,
        genislik: true,
      ),
      const SizedBox(height: 16),
      if (_winYazicilar.isNotEmpty) ...[
        _Seksiyon(baslik: 'Windows\'a Kurulu Yazıcılar', sayi: _winYazicilar.length),
        const SizedBox(height: 8),
        ..._winYazicilar.map((ad) => _CihazKarti(
          ikon: Icons.print,
          renkTon: Colors.deepOrange,
          baslik: ad,
          altBaslik: 'Windows yazıcı',
          altBaslikMono: false,
          aksiyonEtiket: 'Seç',
          aksiyonRenk: _orange,
          onAksiyon: () => _winSec(ad),
        )),
        const SizedBox(height: 8),
      ],
      _BilgiKutu(
        renk: _orange,
        ikon: Icons.print,
        mesaj: 'Yazıcıyı Windows\'a normal şekilde kurun (Ayarlar > Yazıcılar ve '
            'tarayıcılar). Burada listelenen herhangi bir yazıcı seçilebilir; '
            'fiş ve etiketler kurulu sürücü üzerinden doğrudan (RAW ESC/POS) '
            'gönderilir. Termal yazıcının sürücüsü "Generic / Text Only" ya da '
            'üretici sürücüsü olabilir.',
      ),
      if (kayitli.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Seksiyon(baslik: 'Kayıtlı Yazıcılar', sayi: kayitli.length),
        const SizedBox(height: 8),
        ...kayitli.map((y) => _KayitliYaziciKarti(
          yazici: y, onSil: () => _yaziciKaldir(y))),
      ],
    ]);
  }

  Future<void> _usbBaglan(UsbDevice cihaz) async {
    final yazici = YaziciModel(tur: 'usb',
        adi: cihaz.productName?.isNotEmpty == true ? cihaz.productName! : 'USB Yazıcı',
        cihazId: '${cihaz.vid}:${cihaz.pid}', kategori: 'fis', varsayilan: true, aktif: true);
    _spinner('${yazici.adi} bağlanılıyor...');
    try {
      final ok = await _yazdirma.usbBaglan(yazici, cihaz);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (ok) { await _depo.ekle(yazici); await _yukle();
        if (mounted) BildirimServisi.basari(context, '${yazici.adi} bağlandı ✓'); }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      BildirimServisi.hata(context, 'Bağlanamadı: $e');
    }
  }

  Future<void> _yaziciKaldir(YaziciModel y) async {
    final onay = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Yazıcıyı Kaldır'),
      content: Text('${y.adi} kaldırılsın mı?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Kaldır')),
      ],
    ));
    if (onay != true) return;
    if (_yazdirma.aktifYazici?.id == y.id) await _yazdirma.baglantiKes();
    await _depo.sil(y.id!);
    await _yukle();
    if (mounted) BildirimServisi.basari(context, '${y.adi} kaldırıldı');
  }

  Future<void> _testFis() async {
    if (!_yazdirma.bagliMi) { BildirimServisi.uyari(context, 'Önce bir yazıcıya bağlanın'); return; }
    try {
      await _yazdirma.testFisYazdir();
      if (mounted) BildirimServisi.basari(context, 'Test fişi gönderildi ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yazıcı hatası: $e');
    }
  }

  void _spinner(String mesaj) => showDialog(
    context: context, barrierDismissible: false,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Row(children: [
        const CircularProgressIndicator(strokeWidth: 2, color: _blue),
        const SizedBox(width: 16),
        Expanded(child: Text(mesaj)),
      ]),
    ),
  );

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════
  Widget _govde() => _yukleniyor
      ? const Center(child: AppYukleniyor())
      : TabBarView(controller: _tab, children: [
          _wifiTab(),
          _btTab(),
          Platform.isWindows ? _windowsTab() : _usbTab(),
          _fisTab(),
        ]);

  PreferredSizeWidget _icSekmeBari() => TabBar(
        controller: _tab,
        indicatorColor: widget.gomulu ? _blue : Colors.white,
        labelColor: widget.gomulu ? _blue : Colors.white,
        unselectedLabelColor: widget.gomulu ? context.textSecondary : Colors.white60,
        tabs: [
          Tab(icon: Icon(Icons.wifi, size: 20), text: 'WiFi/LAN'),
          Tab(icon: Icon(Icons.bluetooth, size: 20), text: 'Bluetooth'),
          Tab(icon: Icon(Platform.isWindows ? Icons.print : Icons.usb, size: 20), text: Platform.isWindows ? 'Windows Yazıcı' : 'USB'),
          Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'Fiş Ayarı'),
        ],
      );

  @override
  Widget build(BuildContext context) {
    // Yazdırma Merkezi içine gömülüyken kendi AppBar'ını çizmez; sadece
    // cihaz sekmelerini + gövdeyi döndürür (tek sayfa yapısı).
    if (widget.gomulu) {
      return Column(
        children: [
          Material(color: Theme.of(context).cardColor, child: _icSekmeBari()),
          Expanded(child: _govde()),
        ],
      );
    }

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: const Text('Yazıcı Ayarları',
            style: TextStyle(fontWeight: FontWeight.w700)),
        alt: _icSekmeBari(),
      ),
      body: _govde(),
    );
  }
}
