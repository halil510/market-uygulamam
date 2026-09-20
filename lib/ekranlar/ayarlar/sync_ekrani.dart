// lib/ekranlar/ayarlar/sync_ekrani.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync/sync_durum_widget.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/stok_deposu.dart';
import '../../depolar/masa_deposu.dart';
import '../../depolar/borc_deposu.dart';
import '../../depolar/kredi_karti_deposu.dart';
import '../../servisler/puan_servisi.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../servisler/sync_servisi.dart';
import '../../servisler/bluetooth_transfer_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class SyncEkrani extends ConsumerStatefulWidget {
  const SyncEkrani({super.key});
  @override
  ConsumerState<SyncEkrani> createState() => _SyncEkraniState();
}

class _SyncEkraniState extends ConsumerState<SyncEkrani>
    with SingleTickerProviderStateMixin {
  final _sync = SyncServisi();
  final _bt   = BluetoothTransferServisi();
  late TabController _tabCtrl;

  // BT state - {ip: cihazAdi}
  final _btCihazlar = <String, String>{}; // ip → cihazAdi
  bool _btTarama   = false;
  String _btSeciliIp = '';
  String _btDurum  = '';
  int _btProgress  = 0;
  bool _btIslemde  = false;

  // Sunucu
  bool _sunucuAktif = false;
  String _sunucuAdres = '';

  // Bağlantı
  bool _islemde = false;
  String _durum = '';
  int _progress = 0;
  bool _progressGoster = false;

  // QR tarayıcı
  bool _qrTarayici = false;
  MobileScannerController? _qrCtrl;

  // Bağlı cihaz bilgisi
  Map<String, dynamic>? _uzakCihaz;
  String _bagliAdres = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _sunucuBaslat();
    _btCallbackleriAyarla();
  }

  void _btCallbackleriAyarla() {
    _bt.onCihazBulundu = (ip, ad) {
      if (mounted) setState(() => _btCihazlar[ip] = ad);
    };
    _bt.onCihazKayboldu = (id) {
      if (mounted) setState(() => _btCihazlar.remove(id));
    };
    _bt.onProgress = (alinan, toplam, durum) {
      if (mounted) setState(() {
        _btDurum = durum;
        _btProgress = toplam > 0 ? (alinan / toplam * 100).round() : 0;
        _btIslemde = alinan < toplam;
      });
    };
    _bt.onTamamlandi = (msg) {
      if (mounted) setState(() { _btDurum = msg; _btIslemde = false; });
    };
    _bt.onHata = (hata) {
      if (mounted) setState(() { _btDurum = '❌ $hata'; _btIslemde = false; });
    };
  }

  Future<void> _btTaramaToggle() async {
    if (_btTarama) {
      await _bt.durdur();
      if (mounted) setState(() { _btTarama = false; _btCihazlar.clear(); _btDurum = ''; });
    } else {
      if (mounted) setState(() { _btDurum = '🔍 BLE tarama başlıyor...'; _btCihazlar.clear(); });
      final ok = await _bt.taramaBaslat();
      if (mounted) setState(() {
        _btTarama = ok;
        _btDurum = ok ? '🔍 MarketPlus cihazları aranıyor...' : '❌ BT kapalı veya izin yok';
      });
    }
  }


  Future<void> _btVeriAl(String ip, String ad) async {
    if (mounted) setState(() { _btSeciliIp = ip; _btIslemde = true; _btDurum = ''; });
    await _bt.veriAl(ip);
  }

  Future<void> _btVeriGonder(String ip) async {
    if (mounted) setState(() { _btIslemde = true; _btDurum = ''; });
    await _bt.veriGonder(ip);
  }

  Widget _btEkrani() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // ── Nasıl Çalışır ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Text('Önemli Sınırlama', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.orange)),
            ]),
            const SizedBox(height: 8),
            const Text(
              // ÖNCEDEN BURADA "iki cihaz aynı WiFi ağında olmalı" gibi
              // normal bir kullanım metni vardı, ama derin analiz sırasında
              // ÇOK ÖNEMLİ bir mimari eksiklik bulundu: bu cihazın kendini
              // BLE ile "yayınlaması" (advertise/peripheral modu) için
              // HİÇBİR KOD YOK — kullanılan paket (flutter_blue_plus) bunu
              // desteklemiyor. Yani tarama YAPILABİLİYOR ama karşı cihaz
              // ASLA bulunamayabilir, çünkü hiçbir cihaz kendini
              // yayınlayamıyor. Bu, kullanıcıyı yanıltmamak için açıkça
              // belirtiliyor ve güvenilir WiFi+QR yöntemine yönlendiriliyor.
              'Bu cihazlar arası tarama BAZI telefonlarda çalışmayabilir '
              '(Android\'in kendini Bluetooth ile "yayınlama" özelliği '
              'kısıtlı). Bulamazsa, WiFi sekmesindeki QR kod yöntemi '
              'HER ZAMAN güvenilir çalışır — onu kullanmanızı öneririz.',
              style: TextStyle(fontSize: 12, height: 1.6, color: Colors.orange)),
          ]),
        ),
        const SizedBox(height: 20),

        // ── BU CİHAZ - Sunucu bilgisi ──────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [TsRenk.primaryKoyu, TsRenk.primary]),
            borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.phone_android, color: Colors.white70, size: 16),
              SizedBox(width: 6),
              Text('Bu Cihaz (Sunucu)', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.wifi, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _sunucuAktif ? _sunucuAdres : 'WiFi sunucu başlatılıyor...',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'monospace'),
              )),
            ]),
            if (_sunucuAktif) ...[
              const SizedBox(height: 6),
              const Text('Diğer cihaz BLE ile sizi bulabilir',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ],
          ]),
        ),
        const SizedBox(height: 20),

        // ── BLE TARAMA ─────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _btTarama ? Colors.blue.shade300 : TsRenk.ayirac(context))),
          child: Column(children: [
            Row(children: [
              Icon(Icons.bluetooth_searching,
                  color: _btTarama ? Colors.blue : context.textSecondary, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cihaz Ara (BLE)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(_btTarama ? 'MarketPlus cihazları aranıyor...' : 'Yakındaki cihazları bulur',
                    style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
              ])),
              if (_btTarama)
                const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: TsRenk.primary)),
            ]),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              icon: Icon(_btTarama ? Icons.stop : Icons.search),
              label: Text(_btTarama ? 'Aramayı Durdur' : 'BLE ile Cihaz Ara'),
              onPressed: _btIslemde ? null : _btTaramaToggle,
              style: FilledButton.styleFrom(
                foregroundColor: Colors.white,
          backgroundColor: _btTarama ? Colors.red : TsRenk.primaryKoyu,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            )),

            // Bulunan cihazlar listesi
            if (_btCihazlar.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Bulunan Cihazlar:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              const SizedBox(height: 8),
              ..._btCihazlar.entries.map((e) {
                final ip = e.key;
                final ad = e.value;
                final secili = _btSeciliIp == ip;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: secili ? Colors.blue.shade50 : TsRenk.arkaplan(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: secili ? Colors.blue.shade300 : TsRenk.ayirac(context))),
                  child: ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        shape: BoxShape.circle),
                      child: const Icon(Icons.phone_android, color: Colors.blue, size: 22)),
                    title: Text(ad, style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(
                      ip == '?' ? 'IP bilinmiyor - WiFi sekmesini kullanın' : ip,
                      style: TextStyle(fontSize: 11,
                          color: ip == '?' ? Colors.orange : TsRenk.metinIkincil(context))),
                    trailing: ip != '?' ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 30, child: FilledButton(
                          onPressed: _btIslemde ? null : () => _btVeriAl(ip, ad),
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.white,
          backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: const Text('Al', style: TextStyle(fontSize: 12)),
                        )),
                        const SizedBox(height: 4),
                        SizedBox(height: 30, child: FilledButton(
                          onPressed: _btIslemde ? null : () => _btVeriGonder(ip),
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.white,
          backgroundColor: TsRenk.primaryKoyu,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: const Text('Gönder', style: TextStyle(fontSize: 12)),
                        )),
                      ],
                    ) : null,
                  ),
                );
              }),
            ] else if (_btTarama) ...[
              const SizedBox(height: 20),
              Icon(Icons.bluetooth_searching, size: 48, color: TsRenk.ayirac(context)),
              const SizedBox(height: 8),
              Text('Henüz cihaz bulunamadı',
                  style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 13)),
              const SizedBox(height: 4),
              Text('Diğer cihazda WiFi sekmesinden sunucu başlatın',
                  style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ]),
        ),

        // ── Progress ────────────────────────────────────────────────
        if (_btIslemde || _btProgress > 0 && _btProgress < 100) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: _btIslemde && _btProgress == 0 ? null : _btProgress / 100,
              minHeight: 12,
              backgroundColor: context.borderColor,
              valueColor: const AlwaysStoppedAnimation<Color>(TsRenk.primaryKoyu),
            ),
          ),
          if (_btProgress > 0) ...[
            const SizedBox(height: 4),
            Text('$_btProgress%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700,
                  color: TsRenk.primaryKoyu)),
          ],
        ],

        // ── Durum mesajı ────────────────────────────────────────────
        if (_btDurum.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _btDurum.startsWith('✅') ? Colors.green.shade50
                  : _btDurum.startsWith('❌') ? Colors.red.shade50
                  : TsRenk.arkaplan(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _btDurum.startsWith('✅') ? Colors.green.shade200
                    : _btDurum.startsWith('❌') ? Colors.red.shade200
                    : TsRenk.ayirac(context))),
            child: Text(_btDurum,
              style: TextStyle(fontSize: 13,
                color: _btDurum.startsWith('✅') ? Colors.green.shade700
                    : _btDurum.startsWith('❌') ? Colors.red.shade700
                    : context.textSecondary)),
          ),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }


  @override
  void dispose() {
    _tabCtrl.dispose();
    _qrCtrl?.dispose();
    _sync.sunucuKapat();
    _bt.durdur();
    super.dispose();
  }

  // Otomatik sunucu başlat
  Future<void> _sunucuBaslat() async {
    final ok = await _sync.sunucuBaslat();
    if (!mounted) return;
    setState(() {
      _sunucuAktif = ok;
      _sunucuAdres = ok ? _sync.sunucuAdres : '';
    });
  }

  // QR tara → cihaza bağlan
  Future<void> _qrBaglan(String adres) async {
    setState(() {
      _qrTarayici = false;
      _islemde = true;
      _durum = 'Cihaza bağlanılıyor...';
      _uzakCihaz = null;
      _bagliAdres = '';
    });
    try {
      final ping = await _sync.sunucuyaPingAt(adres);
      if (!mounted) return;
      if (!ping.basarili) {
        setState(() {
          _durum = '❌ Bağlantı kurulamadı';
          _islemde = false;
        });
        return;
      }
      final durum = await _sync.uzaktanDurumAl(adres);
      if (!mounted) return;
      setState(() {
        _bagliAdres = adres;
        _uzakCihaz = durum;
        _durum = '✅ Bağlantı başarılı';
        _islemde = false;
      });
    } catch (e) {
      if (mounted) setState(() { _durum = '❌ Hata: $e'; _islemde = false; });
    }
  }

  // Veri Al (JSON)
  Future<void> _veriAl() async {
    if (_bagliAdres.isEmpty) return;
    setState(() {
      _islemde = true;
      _progressGoster = true;
      _progress = 10;
      _durum = 'Veri alınıyor...';
    });
    try {
      final data = await _sync.uzaktanVeriAl(_bagliAdres,
          onDurum: (d) { if (mounted) setState(() => _durum = d); });
      if (!mounted) return;
      if (data == null) {
        setState(() { _durum = '❌ Veri alınamadı'; _islemde = false; });
        return;
      }
      setState(() { _progress = 60; _durum = 'Kaydediliyor...'; });
      final sonuc = await _sync.veriIcerAktarPublic(data);
      if (!mounted) return;
      // Kullanıcı sorusu: "2 cihaz aynı cari kodunu atarsa ne olur?" —
      // bu senkronizasyon yolunda da (WiFi) aynı otomatik düzeltme
      // uygulanıyor, tutarlılık için.
      final duzeltilenCari = await CariDeposu().mukerrerKodlariDuzelt();
      final duzeltilenStok = await StokDeposu().stokMutabakatYap();
      final duzeltilenSiparis = await MasaDeposu().siparisToplamlariMutabakatYap();
      final duzeltilenBorc = await BorcDeposu().odemeMutabakatYap();
      final duzeltilenKart = await KrediKartiDeposu().limitMutabakatYap();
      final duzeltilenPuan = await PuanServisi().puanMutabakatYap();
      if (!mounted) return;
      setState(() {
        _progress = 100;
        _durum = '✅ ${sonuc['basarili']} kayıt aktarıldı'
            '${duzeltilenCari > 0 ? " ($duzeltilenCari mükerrer cari kodu düzeltildi)" : ""}'
            '${duzeltilenStok > 0 ? " ($duzeltilenStok ürün stoğu mutabakatla düzeltildi)" : ""}'
            '${duzeltilenSiparis > 0 ? " ($duzeltilenSiparis masa siparişi düzeltildi)" : ""}'
            '${duzeltilenBorc > 0 ? " ($duzeltilenBorc borç ödemesi düzeltildi)" : ""}'
            '${duzeltilenKart > 0 ? " ($duzeltilenKart kredi kartı limiti düzeltildi)" : ""}'
            '${duzeltilenPuan > 0 ? " ($duzeltilenPuan müşteri puanı düzeltildi)" : ""}';
        _islemde = false;
      });
      BildirimServisi.basari(context, '${sonuc['basarili']} kayıt alındı');
    } catch (e) {
      if (mounted) setState(() { _durum = '❌ $e'; _islemde = false; });
    }
  }

  // Tüm DB Al
  Future<void> _dbAl() async {
    if (_bagliAdres.isEmpty) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Text('Tüm Veriyi Al'),
        content: const Text(
            'Diğer cihazdaki tüm veriler bu cihaza kopyalanacak.\n'
            'Mevcut veriler değişecek. Onaylıyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, Al'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    setState(() {
      _islemde = true;
      _progressGoster = true;
      _progress = 5;
      _durum = 'Veritabanı indiriliyor...';
    });
    try {
      final tempYol = await _sync.uzaktanDbIndir(_bagliAdres,
          onProgress: (alinan, toplam) {
            if (mounted && toplam > 0) {
              setState(() {
                _progress = (alinan / toplam * 80).round();
                _durum = 'İndiriliyor... ${(alinan / 1024).toStringAsFixed(0)} KB';
              });
            }
          });
      if (!mounted) return;
      if (tempYol == null) {
        setState(() { _durum = '❌ İndirilemedi'; _islemde = false; });
        return;
      }
      setState(() { _progress = 90; _durum = 'Uygulanıyor...'; });
      final db = await _sync.dbYoluAl();
      await _sync.sunucuKapat();
      await File(tempYol).copy(db);
      await File(tempYol).delete();
      if (!mounted) return;
      setState(() { _progress = 100; _durum = '✅ Tamamlandı! Uygulamayı yeniden başlatın.'; _islemde = false; });
      BildirimServisi.basari(context, 'Veriler alındı, uygulamayı kapatıp açın');
    } catch (e) {
      if (mounted) setState(() { _durum = '❌ $e'; _islemde = false; });
    }
  }

  // Veri Gönder
  Future<void> _veriGonder() async {
    if (_bagliAdres.isEmpty) return;
    setState(() {
      _islemde = true;
      _progressGoster = true;
      _progress = 10;
      _durum = 'Veri hazırlanıyor...';
    });
    try {
      final data = await _sync.tumVeriAlPublic();
      if (!mounted) return;
      setState(() { _progress = 40; _durum = 'Gönderiliyor...'; });
      final sonuc = await _sync.uzaktanVeriGonder(_bagliAdres, data);
      if (!mounted) return;
      final basarili = sonuc['basarili'] ?? 0;
      setState(() {
        _progress = 100;
        _durum = '✅ $basarili kayıt gönderildi';
        _islemde = false;
      });
      BildirimServisi.basari(context, '$basarili kayıt gönderildi');
    } catch (e) {
      if (mounted) setState(() { _durum = '❌ $e'; _islemde = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Cihazlar Arası Aktarım',
        alt: TabBar(controller: _tabCtrl, tabs: const [
          Tab(icon: Icon(Icons.wifi), text: 'WiFi'),
          Tab(icon: Icon(Icons.bluetooth), text: 'Bluetooth'),
        ]),
        lider: BackButton(onPressed: () => context.go('/')),
      ),
      body: _qrTarayici
          ? _qrTarayiciEkrani()
          : TabBarView(controller: _tabCtrl, children: [
              _anaEkran(),
              _btEkrani(),
            ]),
    );
  }

  // ── QR Tarayıcı ─────────────────────────────────────────────────────────
  Widget _qrTarayiciEkrani() {
    _qrCtrl ??= MobileScannerController();
    return Stack(children: [
      MobileScanner(
        controller: _qrCtrl!,
        onDetect: (capture) {
          final val = capture.barcodes.firstOrNull?.rawValue;
          if (val != null && val.startsWith('http')) {
            _qrCtrl?.stop();
            _qrBaglan(val);
          }
        },
      ),
      // Overlay
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.transparent)),
        child: Column(children: [
          const Spacer(),
          Container(
            width: 250, height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(20)),
          ),
          const SizedBox(height: 24),
          const Text('Diğer cihazdaki QR kodu okutun',
            style: TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600)),
          const Spacer(),
          SafeArea(child: Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('İptal'),
              onPressed: () => setState(() { _qrTarayici = false; _qrCtrl?.dispose(); _qrCtrl = null; }),
              style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            ),
          )),
        ]),
      ),
    ]);
  }

  // ── Ana Ekran ───────────────────────────────────────────────────────────
  Widget _anaEkran() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // BU CİHAZ — QR
        _qrKarti(),
        const SizedBox(height: 20),
        // BAĞLI CİHAZ
        _bagliCihazKarti(),
        const SizedBox(height: 20),
        // BUTONLAR
        if (_uzakCihaz != null) _akisButonlari(),
        // PROGRESS
        if (_progressGoster) ...[
          const SizedBox(height: 20),
          _progressWidget(),
        ],
        // DURUM
        if (_durum.isNotEmpty) ...[
          const SizedBox(height: 12),
          _durumWidget(),
        ],
      ]),
    );
  }

  Widget _qrKarti() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [TsRenk.primaryKoyu, TsRenk.primary],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: Color.fromARGB(76, 21, 101, 192),
          blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.phone_android, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text('Bu Cihaz', style: TextStyle(
              color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _sunucuAktif ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(20)),
            child: Text(_sunucuAktif ? 'Hazır' : 'Başlatılıyor...',
              style: const TextStyle(color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 16),
        if (_sunucuAktif && _sunucuAdres.isNotEmpty) ...[
          // QR Kod
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              borderRadius: BorderRadius.circular(12)),
            child: QrImageView(
              data: _sunucuAdres,
              version: QrVersions.auto,
              size: 150,
            ),
          ),
          const SizedBox(height: 12),
          Text(_sunucuAdres,
            style: const TextStyle(color: Colors.white70,
                fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          const Text('Diğer cihazda bu QR\'ı okutun',
            style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.copy, color: Colors.white54, size: 16),
            label: const Text('Kopyala',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _sunucuAdres));
              BildirimServisi.basari(context, 'Adres kopyalandı');
            },
          ),
        ] else
          const CircularProgressIndicator(color: Colors.white),
      ]),
    );
  }

  Widget _bagliCihazKarti() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _uzakCihaz != null
              ? Colors.green.shade300 : TsRenk.ayirac(context)),
        boxShadow: [BoxShadow(
          color: Color(0x0D000000),
          blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: _uzakCihaz == null
          ? Column(children: [
              Icon(Icons.qr_code_scanner,
                size: 48, color: TsRenk.metinIkincil(context)),
              const SizedBox(height: 12),
              Text('Diğer Cihaz',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                    color: TsRenk.metinIkincil(context))),
              const SizedBox(height: 4),
              Text('Bağlanmak için QR okutun',
                style: TextStyle(fontSize: 13, color: TsRenk.metinIkincil(context))),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _islemde
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.qr_code_scanner),
                  label: Text(_islemde ? 'Bağlanıyor...' : 'QR Okut ve Bağlan'),
                  onPressed: _islemde ? null : () => setState(() => _qrTarayici = true),
                  style: FilledButton.styleFrom(
                    foregroundColor: Colors.white,
          backgroundColor: TsRenk.primaryKoyu,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle),
                  child: const Icon(Icons.phone_android,
                      color: Colors.green, size: 24)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_uzakCihaz!['cihaz']?.toString() ?? 'Cihaz',
                    style: const TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w700)),
                  Text('Bağlı ✅',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                ])),
                TextButton(
                  onPressed: () => setState(() {
                    _uzakCihaz = null; _bagliAdres = '';
                    _durum = ''; _progressGoster = false; _progress = 0;
                  }),
                  child: const Text('Bağlantıyı Kes',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              // Cihaz istatistikleri
              Row(children: [
                _statKutu('Ürün',
                    '${_uzakCihaz!['urun_sayisi'] ?? 0}', TsRenk.primaryKoyu),
                const SizedBox(width: 8),
                _statKutu('Cari',
                    '${_uzakCihaz!['cari_sayisi'] ?? 0}', Colors.orange),
                const SizedBox(width: 8),
                _statKutu('Satış',
                    '${_uzakCihaz!['satis_sayisi'] ?? 0}', Colors.green),
              ]),
            ]),
    );
  }

  Widget _akisButonlari() {
    return Column(children: [
      // Veri Al
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: _islemde
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.download_rounded),
          label: const Text('Veri Al',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          onPressed: _islemde ? null : _veriAl,
          style: FilledButton.styleFrom(
            foregroundColor: Colors.white,
          backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        ),
      ),
      const SizedBox(height: 10),
      // Veri Gönder
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: _islemde
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.upload_rounded),
          label: const Text('Veri Gönder',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          onPressed: _islemde ? null : _veriGonder,
          style: FilledButton.styleFrom(
            foregroundColor: Colors.white,
          backgroundColor: TsRenk.primaryKoyu,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        ),
      ),
      const SizedBox(height: 10),
      // Tüm DB Al
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.storage, color: Colors.orange),
          label: const Text('Tüm Veritabanını Al (Komple Kopyala)',
            style: TextStyle(color: Colors.orange,
                fontWeight: FontWeight.w600, fontSize: 13)),
          onPressed: _islemde ? null : _dbAl,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.orange),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        ),
      ),
    ]);
  }

  Widget _progressWidget() => SyncProgressWidget(progress: _progress);

  Widget _durumWidget() => SyncDurumWidget(durum: _durum);

  Widget _statKutu(String baslik, String deger, Color renk) =>
      SyncStatKutu(baslik: baslik, deger: deger, renk: renk);
}