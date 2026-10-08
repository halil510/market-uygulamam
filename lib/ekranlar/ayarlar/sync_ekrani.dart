// lib/ekranlar/ayarlar/sync_ekrani.dart
import '../../cekirdek/utils/hata_utils.dart';
import '../../servisler/veritabani_dosya_servisi.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync/sync_durum_widget.dart';
import '../../servisler/senkron_sonrasi_mutabakat.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../servisler/sync_servisi.dart';
import '../../servisler/bluetooth_transfer_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../widgetlar/ortak/yonetici_sifre_dialogu.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

part 'sync_ekrani_bluetooth.dart';
part 'sync_ekrani_gorunum.dart';

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
      if (mounted) {
        setState(() {
        _btDurum = durum;
        _btProgress = toplam > 0 ? (alinan / toplam * 100).round() : 0;
        _btIslemde = alinan < toplam;
      });
      }
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
      if (mounted) {
        setState(() {
        _btTarama = ok;
        _btDurum = ok ? '🔍 BarkoPro cihazları aranıyor...' : '❌ BT kapalı veya izin yok';
      });
      }
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
    if (!mounted) return;
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
      if (mounted) setState(() { _durum = '❌ Hata: ${bildirimMetniniSadelestir(e.toString())}'; _islemde = false; });
    }
  }

  // Veri Al (JSON)
  Future<void> _veriAl() async {
    if (!mounted) return;
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
      // Bulut senkronuyla AYNI merkezî mutabakat adımları (mükerrer cari
      // kodu, cari bakiye, stok, masa, borç, kart, puan). Her adım ayrı
      // korunur: biri başarısız olsa diğerleri yine çalışır ve hata loglanır.
      final duzeltmeler = <String>[];
      await SenkronSonrasiMutabakat.calistir(log: duzeltmeler.add);
      if (!mounted) return;
      setState(() {
        _progress = 100;
        _durum = '✅ ${sonuc['basarili']} kayıt aktarıldı'
            '${duzeltmeler.isEmpty ? '' : '\n${duzeltmeler.join('\n')}'}';
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
    // Yedek geri yükleme ile aynı koruma: bu cihazın TÜM verisinin üzerine
    // yazılıyor (öncesinde yedek de alınmıyor) — şifre istemiyordu (2026-09-23).
    final onaylandi = await yoneticiSifresiIleOnayIste(
      context,
      baslik: 'Tüm Veriyi Alma Onayı',
      aciklama: 'Bu cihazdaki TÜM veriler diğer cihazın verisiyle '
          'değiştirilecek. Devam etmek için şifrenizi girin.',
    );
    if (!onaylandi || !mounted) return;
    if (!AuthServisi().isMudur) return; // savunma: eylem anında ikinci kez doğrula

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
      await _sync.sunucuKapat();
      // Güvenli yol: imza + bütünlük kontrolü, güvenlik kopyası, -wal/-shm
      // temizliği (açık DB'nin üstüne düz kopyalama WAL'ı bozabiliyordu).
      await VeritabaniDosyaServisi().iceAktar(tempYol);
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
    if (!mounted) return;
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
}
