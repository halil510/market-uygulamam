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
import '../../veri/database/veritabani.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';

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
    _tab = TabController(length: 4, vsync: this);
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
      final db    = await Veritabani().db;
      final rows  = await db.query('ayarlar', where:
          "anahtar IN ('firma_adi','firma_adres','firma_telefon','fis_alt_yazi','fis_kagit','fis_kdv')");
      final m = {for (final r in rows) r['anahtar'] as String: r['deger'] as String};
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

  Future<void> _ayarKaydet(String k, String v) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    await db.rawInsert(
      'INSERT OR REPLACE INTO ayarlar(anahtar, deger, guncelleme, last_updated) VALUES(?,?,?,?)',
      [k, v, now, now],
    );
    // 🔴 Derin analizde bulundu: last_updated hiç ayarlanmıyordu,
    // BulutManager hiç çağrılmıyordu.
    final satir = await db.query('ayarlar', where: 'anahtar = ?', whereArgs: [k], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('ayarlar', Map<String, dynamic>.from(satir.first));
  }

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
          _usbTab(),
          _fisTab(),
        ]);

  PreferredSizeWidget _icSekmeBari() => TabBar(
        controller: _tab,
        indicatorColor: widget.gomulu ? _blue : Colors.white,
        labelColor: widget.gomulu ? _blue : Colors.white,
        unselectedLabelColor: widget.gomulu ? context.textSecondary : Colors.white60,
        tabs: const [
          Tab(icon: Icon(Icons.wifi, size: 20), text: 'WiFi/LAN'),
          Tab(icon: Icon(Icons.bluetooth, size: 20), text: 'Bluetooth'),
          Tab(icon: Icon(Icons.usb, size: 20), text: 'USB'),
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

  // ═════════════════════════════════════════════════════════════════════════
  // TAB 1 — WiFi/LAN
  // ═════════════════════════════════════════════════════════════════════════
  Widget _wifiTab() {
    final wifiKayitlilar = _kayitlilar.where((y) => y.tur == 'ag').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      // ── Bağlantı durumu ──
      _BaglantiDurumKarti(yazdirma: _yazdirma, onKes: () async {
        await _yazdirma.baglantiKes();
        if (!mounted) return;
        setState(() {});
        BildirimServisi.uyari(context, 'Bağlantı kesildi');
      }),
      const SizedBox(height: 16),

      // ── Butonlar ──
      Row(children: [
        Expanded(child: _ActionButon(
          label: _wifiTaraniyor ? 'Taranıyor...' : 'Ağı Tara',
          icon: _wifiTaraniyor ? null : Icons.search,
          loading: _wifiTaraniyor,
          onTap: _wifiTaraniyor ? null : _wifiTara,
          outlined: true,
          renk: _blue,
        )),
        const SizedBox(width: 10),
        Expanded(child: _ActionButon(
          label: 'Manuel IP',
          icon: Icons.add_link,
          onTap: _wifiManuelBaglan,
          renk: _blue,
        )),
      ]),
      const SizedBox(height: 16),

      // ── Bulunan cihazlar ──
      if (_wifiCihazlar.isNotEmpty) ...[
        _Seksiyon(baslik: 'Bulunan Yazıcılar', sayi: _wifiCihazlar.length),
        const SizedBox(height: 8),
        ..._wifiCihazlar.map((ip) => _CihazKarti(
          ikon: Icons.print,
          renkTon: Colors.green,
          baslik: ip,
          altBaslik: 'Port 9100 · TCP/IP',
          aksiyonEtiket: 'Bağlan',
          aksiyonRenk: _green,
          onAksiyon: () => _wifiBaglan(ip),
        )),
        const SizedBox(height: 8),
      ],

      // ── Bilgi kutusu ──
      _BilgiKutu(
        renk: _blue,
        ikon: Icons.info_outline,
        mesaj: 'Epson TM, Bixolon, Star Micronics ve diğer ağ yazıcıları TCP/IP '
            '(port 9100) üzerinden bağlanır. Yazıcı ve telefon aynı WiFi ağında olmalıdır.',
      ),

      // ── Kayıtlı yazıcılar ──
      if (wifiKayitlilar.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Seksiyon(baslik: 'Kayıtlı WiFi Yazıcılar', sayi: wifiKayitlilar.length),
        const SizedBox(height: 8),
        ...wifiKayitlilar.map((y) => _KayitliYaziciKarti(
          yazici: y, onSil: () => _yaziciKaldir(y))),
      ],
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB 2 — Bluetooth
  // ═════════════════════════════════════════════════════════════════════════
  Widget _btTab() {
    final btKayitlilar = _kayitlilar.where((y) => y.tur == 'bluetooth').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _BaglantiDurumKarti(yazdirma: _yazdirma, onKes: () async {
        await _yazdirma.baglantiKes();
        if (!mounted) return;
        setState(() {});
        BildirimServisi.uyari(context, 'Bağlantı kesildi');
      }),
      const SizedBox(height: 16),

      _ActionButon(
        label: _btTaraniyor ? 'Taranıyor...' : 'Bluetooth Cihazları Tara',
        icon: _btTaraniyor ? null : Icons.bluetooth_searching,
        loading: _btTaraniyor,
        onTap: _btTaraniyor ? null : _btTara,
        renk: _purple,
        genislik: true,
      ),
      const SizedBox(height: 16),

      if (_btCihazlar.isNotEmpty) ...[
        _Seksiyon(baslik: 'Bulunan BT Cihazlar', sayi: _btCihazlar.length),
        const SizedBox(height: 8),
        ..._btCihazlar.map((c) => _CihazKarti(
          ikon: Icons.bluetooth,
          renkTon: Colors.purple,
          baslik: c.platformName.isNotEmpty ? c.platformName : 'Bilinmeyen Cihaz',
          altBaslik: c.remoteId.str,
          altBaslikMono: true,
          aksiyonEtiket: 'Bağlan',
          aksiyonRenk: _purple,
          onAksiyon: () => _btBaglan(c),
        )),
        const SizedBox(height: 8),
      ],

      _BilgiKutu(
        renk: _purple,
        ikon: Icons.bluetooth,
        mesaj: 'Sewoo, Rongta, Bixolon SPP vb. taşınabilir yazıcılar için '
            'önce telefon Ayarlar > Bluetooth ekranından eşleştirin.',
      ),

      if (btKayitlilar.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Seksiyon(baslik: 'Kayıtlı BT Yazıcılar', sayi: btKayitlilar.length),
        const SizedBox(height: 8),
        ...btKayitlilar.map((y) => _KayitliYaziciKarti(
          yazici: y, onSil: () => _yaziciKaldir(y))),
      ],
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB — USB
  // ═════════════════════════════════════════════════════════════════════════
  Widget _usbTab() {
    final usbKayitlilar = _kayitlilar.where((y) => y.tur == 'usb').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _BaglantiDurumKarti(yazdirma: _yazdirma, onKes: () async {
        await _yazdirma.baglantiKes();
        if (!mounted) return;
        setState(() {});
        BildirimServisi.uyari(context, 'Bağlantı kesildi');
      }),
      const SizedBox(height: 16),

      _ActionButon(
        label: _usbTaraniyor ? 'Taranıyor...' : 'USB Cihazları Tara',
        icon: _usbTaraniyor ? null : Icons.usb,
        loading: _usbTaraniyor,
        onTap: _usbTaraniyor ? null : _usbTara,
        renk: _orange,
        genislik: true,
      ),
      const SizedBox(height: 16),

      if (_usbCihazlar.isNotEmpty) ...[
        _Seksiyon(baslik: 'Bulunan USB Cihazlar', sayi: _usbCihazlar.length),
        const SizedBox(height: 8),
        ..._usbCihazlar.map((c) => _CihazKarti(
          ikon: Icons.usb,
          renkTon: Colors.deepOrange,
          baslik: c.productName?.isNotEmpty == true ? c.productName! : 'Bilinmeyen USB Cihaz',
          altBaslik: 'VID:${c.vid?.toRadixString(16) ?? '?'} PID:${c.pid?.toRadixString(16) ?? '?'}',
          altBaslikMono: true,
          aksiyonEtiket: 'Bağlan',
          aksiyonRenk: _orange,
          onAksiyon: () => _usbBaglan(c),
        )),
        const SizedBox(height: 8),
      ],

      _BilgiKutu(
        renk: _orange,
        ikon: Icons.usb,
        mesaj: 'USB kablo ile takılı termal yazıcılar burada listelenir. '
            'Android ilk bağlantıda "USB cihazına erişime izin ver" '
            'sorabilir — izin verin. Yazıcı bir seri (CDC-ACM) cihaz olarak '
            'görünmelidir; bazı özel sürücü gerektiren modellerle çalışmayabilir.',
      ),

      if (usbKayitlilar.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Seksiyon(baslik: 'Kayıtlı USB Yazıcılar', sayi: usbKayitlilar.length),
        const SizedBox(height: 8),
        ...usbKayitlilar.map((y) => _KayitliYaziciKarti(
          yazici: y, onSil: () => _yaziciKaldir(y))),
      ],
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB 3 — Fiş Ayarları
  // ═════════════════════════════════════════════════════════════════════════
  Widget _fisTab() => ListView(padding: const EdgeInsets.all(16), children: [
    // ── Firma bilgileri ──
    _KartBolum(
      baslik: 'Firma Bilgileri',
      ikon: Icons.store,
      renk: _blue,
      children: [
        _inputField(context, _firmaAdiCtrl, 'Firma Adı *', 'MarketPlus', Icons.store),
        const SizedBox(height: 12),
        _inputField(context, _firmaAdresCtrl, 'Adres', 'Atatürk Cad. No:1', Icons.location_on),
        const SizedBox(height: 12),
        _inputField(context, _firmaTelCtrl, 'Telefon', '0532 000 00 00', Icons.phone,
            tip: TextInputType.phone),
      ],
    ),
    const SizedBox(height: 16),

    // ── Fiş tasarımı ──
    _KartBolum(
      baslik: 'Fiş Tasarımı',
      ikon: Icons.receipt_long,
      renk: _orange,
      children: [
        _inputField(context, _altYaziCtrl, 'Alt Yazı', 'Teşekkür ederiz!', Icons.text_fields),
        const SizedBox(height: 12),

        // Kağıt boyutu seçici
        DropdownButtonFormField<String>(
          value: _kagitBoy,
          decoration: InputDecoration(
            labelText: 'Kağıt Genişliği',
            prefixIcon: const Icon(Icons.straighten),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
          borderRadius: BorderRadius.circular(12),
          items: const [
            DropdownMenuItem(value: '58mm', child: Text('58mm — Mobil yazıcılar')),
            DropdownMenuItem(value: '80mm', child: Text('80mm — Masa yazıcıları (Standart)')),
            DropdownMenuItem(value: '57mm', child: Text('57mm — Kompakt termal')),
            DropdownMenuItem(value: 'A4',   child: Text('A4 — Lazer / Inkjet')),
            DropdownMenuItem(value: 'A4-PDF', child: Text('A4 PDF — Dijital fatura')),
          ],
          onChanged: (v) { if (v != null) setState(() => _kagitBoy = v); },
        ),
        const SizedBox(height: 8),

        // KDV toggle
        Container(
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: SwitchListTile(
            title: const Text('KDV Detayı Göster', style: TsMetin.govdeVurgu),
            subtitle: const Text('Fiş üzerinde KDV dökümünü göster', style: TextStyle(fontSize: 12)),
            value: _kdvGoster,
            onChanged: (v) => setState(() => _kdvGoster = v),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    ),
    const SizedBox(height: 24),

    // ── Eylemler ──
    Row(children: [
      Expanded(child: _ActionButon(
        label: 'Test Fişi',
        icon: Icons.print_outlined,
        onTap: _testFis,
        outlined: true,
        renk: _orange,
      )),
      const SizedBox(width: 12),
      Expanded(child: _ActionButon(
        label: 'Kaydet',
        icon: Icons.save_rounded,
        onTap: _fisAyarlariKaydet,
        renk: _green,
      )),
    ]),
    const SizedBox(height: 8),
  ]);
}

// ═════════════════════════════════════════════════════════════════════════════
// YARDIMCI WIDGETlar
// ═════════════════════════════════════════════════════════════════════════════

/// Aktif bağlantı durumu kartı
class _BaglantiDurumKarti extends StatelessWidget {
  final YazdirmaServisi yazdirma;
  final VoidCallback onKes;
  const _BaglantiDurumKarti({required this.yazdirma, required this.onKes});

  @override
  Widget build(BuildContext context) {
    final bagliMi = yazdirma.bagliMi;
    final renk    = bagliMi ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: renk.shade300),
        boxShadow: [BoxShadow(
          color: Color.fromARGB(20, renk.red, renk.green, renk.blue),
          blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Color.fromARGB(30, renk.red, renk.green, renk.blue),
            shape: BoxShape.circle),
          child: Icon(bagliMi ? Icons.print : Icons.print_disabled,
              color: renk.shade700, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bagliMi ? 'Yazıcı Bağlı' : 'Yazıcı Bağlı Değil',
              style: TextStyle(fontWeight: FontWeight.w700,
                  color: renk.shade800, fontSize: 14)),
          if (bagliMi)
            Text(yazdirma.baglantiDurumu,
                style: TextStyle(fontSize: 12, color: renk.shade600)),
          if (!bagliMi)
            Text('Aşağıdan bir yazıcı seçin',
                style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
        ])),
        if (bagliMi)
          OutlinedButton.icon(
            onPressed: onKes,
            icon: const Icon(Icons.link_off, size: 16),
            label: const Text('Kes', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
      ]),
    );
  }
}

/// Bulunan cihaz kartı (WiFi IP veya BT cihazı)
class _CihazKarti extends StatelessWidget {
  final IconData ikon;
  final MaterialColor renkTon;
  final String baslik, altBaslik, aksiyonEtiket;
  final Color aksiyonRenk;
  final bool altBaslikMono;
  final VoidCallback onAksiyon;

  const _CihazKarti({
    required this.ikon, required this.renkTon,
    required this.baslik, required this.altBaslik,
    required this.aksiyonEtiket, required this.aksiyonRenk,
    required this.onAksiyon, this.altBaslikMono = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.borderColor),
      boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6)],
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Color.fromARGB(30, renkTon.red, renkTon.green, renkTon.blue),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(ikon, color: renkTon.shade700, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(baslik, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text(altBaslik,
            style: TextStyle(
              fontSize: 11,
              color: TsRenk.metinIkincil(context),
              fontFamily: altBaslikMono ? 'monospace' : null)),
      ])),
      FilledButton(
        onPressed: onAksiyon,
        style: FilledButton.styleFrom(
          backgroundColor: aksiyonRenk,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(0, 36),
        ),
        child: Text(aksiyonEtiket, style: TsMetin.kucukVurgu),
      ),
    ]),
  );
}

/// Kayıtlı yazıcı kartı (bağlan + sil)
class _KayitliYaziciKarti extends StatelessWidget {
  final YaziciModel yazici;
  final VoidCallback onSil;
  const _KayitliYaziciKarti({required this.yazici, required this.onSil});

  @override
  Widget build(BuildContext context) {
    final wifimi = yazici.tur == 'ag';
    final renk   = wifimi ? Colors.blue : Colors.purple;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Color.fromARGB(25, renk.red, renk.green, renk.blue),
            borderRadius: BorderRadius.circular(12)),
          child: Icon(wifimi ? Icons.wifi : Icons.bluetooth,
              color: renk.shade600, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(yazici.adi, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(wifimi
              ? '${yazici.ip ?? "?"}:${yazici.port}'
              : (yazici.cihazId ?? ''),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace',
                  color: Color(0xFF607D8B))),
        ])),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
          onPressed: onSil,
          tooltip: 'Kaldır',
          style: IconButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
      ]),
    );
  }
}

/// Bölüm başlığı (Fiş tab içinde kart bazlı gruplar)
class _KartBolum extends StatelessWidget {
  final String baslik;
  final IconData ikon;
  final Color renk;
  final List<Widget> children;
  const _KartBolum({required this.baslik, required this.ikon,
      required this.renk, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.borderColor),
      boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Başlık satırı
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: Color.fromARGB(18, renk.red, renk.green, renk.blue),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(bottom: BorderSide(color: context.borderColor)),
        ),
        child: Row(children: [
          Icon(ikon, size: 18, color: renk),
          const SizedBox(width: 8),
          Text(baslik, style: TextStyle(fontWeight: FontWeight.w800,
              fontSize: 13, color: renk)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    ]),
  );
}

/// Liste bölüm başlığı + sayı rozeti
class _Seksiyon extends StatelessWidget {
  final String baslik;
  final int sayi;
  const _Seksiyon({required this.baslik, required this.sayi});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(baslik, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    const SizedBox(width: 8),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppRenkler.primary.withAlpha(31),
        borderRadius: BorderRadius.circular(10)),
      child: Text('$sayi', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, color: AppRenkler.primary)),
    ),
  ]);
}

/// Bilgi kutusu
class _BilgiKutu extends StatelessWidget {
  final Color renk;
  final IconData ikon;
  final String mesaj;
  const _BilgiKutu({required this.renk, required this.ikon, required this.mesaj});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Color.fromARGB(18, renk.red, renk.green, renk.blue),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Color.fromARGB(50, renk.red, renk.green, renk.blue)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(ikon, size: 16, color: renk),
      const SizedBox(width: 8),
      Expanded(child: Text(mesaj,
          style: TextStyle(fontSize: 12,
              color: Color.fromARGB(200, renk.red, renk.green, renk.blue)))),
    ]),
  );
}

/// Aksiyon butonu
class _ActionButon extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color renk;
  final bool outlined;
  final bool loading;
  final bool genislik;

  const _ActionButon({
    required this.label, required this.renk,
    this.icon, this.onTap,
    this.outlined = false, this.loading = false, this.genislik = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(
                strokeWidth: 2, color: outlined ? renk : Colors.white)),
            const SizedBox(width: 8),
            Text(label),
          ])
        : icon != null
          ? Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18), const SizedBox(width: 6), Text(label),
            ])
          : Text(label);

    final style = outlined
        ? OutlinedButton.styleFrom(
            foregroundColor: renk, side: BorderSide(color: renk),
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))
        : FilledButton.styleFrom(
            backgroundColor: renk, foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));

    return SizedBox(
      width: genislik ? double.infinity : null,
      child: outlined
          ? OutlinedButton(onPressed: onTap, style: style, child: child)
          : FilledButton(onPressed: onTap, style: style, child: child),
    );
  }
}

/// TextField yardımcısı
Widget _inputField(
  BuildContext context,
  TextEditingController ctrl, String label, String hint, IconData ikon, {
  TextInputType tip = TextInputType.text,
  List<TextInputFormatter> fmt = const [],
}) => TextField(
  controller: ctrl, keyboardType: tip, inputFormatters: fmt,
  decoration: InputDecoration(
    labelText: label, hintText: hint,
    prefixIcon: Icon(ikon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: TsRenk.ayirac(context))),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _blue, width: 1.5)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  ),
);
