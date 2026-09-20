// lib/servisler/bluetooth_transfer_servisi.dart
// BLE keşif + WiFi transfer (AirDrop prensibi)
// - Sunucu: WiFi HTTP server + BLE ile IP yayını
// - İstemci: BLE scan → IP al → WiFi transfer
import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'sync_servisi.dart';

class BluetoothTransferServisi {
  static final BluetoothTransferServisi _i = BluetoothTransferServisi._();
  factory BluetoothTransferServisi() => _i;
  BluetoothTransferServisi._();

  final _sync = SyncServisi();

  // Callbacks
  Function(String ip, String cihazAdi)? onCihazBulundu;
  Function(String cihazAdi)? onCihazKayboldu;
  Function(int alinan, int toplam, String durum)? onProgress;
  Function(String mesaj)? onTamamlandi;
  Function(String hata)? onHata;

  StreamSubscription? _scanSub;
  bool _tarama = false;
  bool _islemde = false;
  bool get tarama => _tarama;
  bool get islemde => _islemde;

  // ── SUNUCU: BLE ile IP yayını ──────────────────────────────────────────
  // Not: flutter_blue_plus peripheral modunu desteklemiyor
  // Çözüm: sync_servisi zaten WiFi HTTP server kuruyor
  // BT sekmesinde sunucu rolü = WiFi server + manuel IP paylaşımı
  // İstemci rolü = BLE scan ile cihaz bulma (mevcut WiFi server'a bağlanır)

  // ── İSTEMCİ: BLE Scan ─────────────────────────────────────────────────
  Future<bool> taramaBaslat() async {
    if (_tarama) return true;
    try {
      final btState = await FlutterBluePlus.adapterState.first;
      if (btState != BluetoothAdapterState.on) {
        onHata?.call('Bluetooth kapalı. Lütfen açın.');
        return false;
      }

      _tarama = true;
      final bulunanlar = <String>{};

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          // MarketPlus cihazlarını filtrele (isim veya service UUID ile)
          final ad = r.device.platformName;
          final id = r.device.remoteId.str;

          if ((ad.startsWith('MKP-') || ad.startsWith('MarketPlus')) &&
              !bulunanlar.contains(id)) {
            bulunanlar.add(id);
            // Advertisement data'dan IP'yi çıkar
            final mfgData = r.advertisementData.manufacturerData;
            String ip = '';
            if (mfgData.isNotEmpty) {
              try {
                final bytes = mfgData.values.first;
                ip = utf8.decode(bytes).trim();
              } catch (e) { /* ignore */ }
            }
            if (ip.isEmpty) ip = '?'; // IP bilinmiyor
            onCihazBulundu?.call(ip, ad);
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 30),
        withKeywords: ['MKP-', 'MarketPlus'],
      );
      return true;
    } catch (e) {
      _tarama = false;
      onHata?.call('BLE tarama hatası: $e');
      return false;
    }
  }

  Future<void> taramaDurdur() async {
    _tarama = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
  }

  // ── VERİ AL: Bulunan cihazdan WiFi ile veri çek ───────────────────────
  Future<void> veriAl(String sunucuIp) async {
    if (sunucuIp == '?' || sunucuIp.isEmpty) {
      onHata?.call('IP adresi bilinmiyor. Karşı cihazdan IP\'yi manuel alın.');
      return;
    }
    _islemde = true;
    final adres = 'http://$sunucuIp:8765';
    try {
      onProgress?.call(0, 100, 'Bağlanıyor...');
      final ping = await _sync.sunucuyaPingAt(adres);
      if (!ping.basarili) {
        onHata?.call('Bağlantı kurulamadı. Aynı WiFi ağında mısınız?');
        _islemde = false;
        return;
      }
      onProgress?.call(20, 100, 'Veri indiriliyor...');
      final data = await _sync.uzaktanVeriAl(adres,
          onDurum: (d) => onProgress?.call(40, 100, d));
      if (data == null) {
        onHata?.call('Veri alınamadı');
        _islemde = false;
        return;
      }
      onProgress?.call(70, 100, 'Kaydediliyor...');
      final sonuc = await _sync.veriIcerAktarPublic(data);
      onProgress?.call(100, 100, 'Tamamlandı');
      onTamamlandi?.call('✅ ${sonuc['basarili']} kayıt alındı');
    } catch (e) {
      onHata?.call('Hata: $e');
    } finally {
      _islemde = false;
    }
  }

  // ── VERİ GÖNDER: Karşı cihaza WiFi ile gönder ────────────────────────
  Future<void> veriGonder(String hedefIp) async {
    if (hedefIp == '?' || hedefIp.isEmpty) {
      onHata?.call('Hedef IP bilinmiyor');
      return;
    }
    _islemde = true;
    final adres = 'http://$hedefIp:8765';
    try {
      onProgress?.call(0, 100, 'Veri hazırlanıyor...');
      final data = await _sync.tumVeriAlPublic();
      onProgress?.call(40, 100, 'Gönderiliyor...');
      final sonuc = await _sync.uzaktanVeriGonder(adres, data);
      onProgress?.call(100, 100, 'Tamamlandı');
      final basarili = sonuc['basarili'] ?? 0;
      onTamamlandi?.call('✅ $basarili kayıt gönderildi');
    } catch (e) {
      onHata?.call('Gönderme hatası: $e');
    } finally {
      _islemde = false;
    }
  }

  Future<void> durdur() async {
    await taramaDurdur();
    _islemde = false;
  }
}
