// lib/ekranlar/ayarlar/sync_ekrani.dart
import '../../cekirdek/utils/hata_utils.dart';
import '../../servisler/veritabani_dosya_servisi.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync/sync_durum_widget.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../servisler/sync_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../widgetlar/ortak/yonetici_sifre_dialogu.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

part 'sync_ekrani_gorunum.dart';

class SyncEkrani extends ConsumerStatefulWidget {
  const SyncEkrani({super.key});
  @override
  ConsumerState<SyncEkrani> createState() => _SyncEkraniState();
}

class _SyncEkraniState extends ConsumerState<SyncEkrani> {
  final _sync = SyncServisi();

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
    _sunucuBaslat();
  }

  // 🔴 Bluetooth sekmesi kaldırıldı (çoklu cihaz analizi, 2026-11-08):
  // uygulama kendini BLE'de yayınlayamıyordu (flutter_blue_plus çevre birimi
  // modunu desteklemiyor) — tarama hiçbir cihaz bulamazdı; bulsa bile
  // istek oturum anahtarı taşımadığı için sunucu 401 ile reddederdi.
  // Aktarım zaten WiFi üzerindeydi; tek yol artık WiFi + QR/adres.

  @override
  void dispose() {
    _qrCtrl?.dispose();
    _sync.sunucuKapat();
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
      // Bulut senkronuyla AYNI merkezî mutabakat adımları (stok, cari
      // bakiye …) artık içe aktarımın kendisinde çalışıyor (karşı cihazın
      // "Veri Gönder"iyle gelen veride de) — sonuç listesi buradan okunur.
      final duzeltmeler =
          ((sonuc['duzeltmeler'] as List?) ?? const []).cast<String>();
      final hatalar = ((sonuc['hatalar'] as List?) ?? const []).cast<String>();
      final atlanan = sonuc['atlanan'] as int? ?? 0;
      setState(() {
        _progress = 100;
        _durum = '${hatalar.isEmpty ? '✅' : '⚠️'} ${sonuc['basarili']} kayıt aktarıldı'
            '${atlanan > 0 ? '\n$atlanan kayıt atlandı (bağlı olduğu kayıt bu cihazda yok)' : ''}'
            '${duzeltmeler.isEmpty ? '' : '\n${duzeltmeler.join('\n')}'}'
            '${hatalar.isEmpty ? '' : '\nHatalar:\n${hatalar.join('\n')}'}';
        _islemde = false;
      });
      if (hatalar.isEmpty) {
        BildirimServisi.basari(context, '${sonuc['basarili']} kayıt alındı');
      } else {
        BildirimServisi.uyari(context,
            '${sonuc['basarili']} kayıt alındı, ${hatalar.length} tabloda hata var');
      }
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
          backgroundColor: TsRenk.hata),
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
        baslik: 'Cihazlar Arası Aktarım (WiFi)',
        lider: BackButton(onPressed: () => context.go('/')),
      ),
      body: _qrTarayici ? _qrTarayiciEkrani() : _anaEkran(),
    );
  }
}
