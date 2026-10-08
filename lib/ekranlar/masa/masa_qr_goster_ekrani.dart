// lib/ekranlar/masa/masa_qr_goster_ekrani.dart
//
// Kullanıcı isteği: "müşteriler kendi telefonuyla masadaki QR'ı
// okutup sipariş versin." Bu ekran, o QR kodun GERÇEKTEN üretildiği
// ve gösterildiği yer.
//
// 🔴 DÜZELTME (derin analiz 2026-10-07): ağ koptuğunda/değiştiğinde QR
// eski (ölü) adreste kilitli kalıyordu — adres yalnız ekran açılışında
// çözülüyor, yerel IP sunucu servisinde sonsuza dek önbellekte tutuluyordu.
// Artık bağlantı değişimi dinlenir, adres yeniden çözülür ve değiştiyse
// kullanıcı uyarılır (yazdırılmış eski kartlar geçersiz olabilir).
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../cekirdek/utils/hata_utils.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/masa/masa_qr_yazdir_servisi.dart';
import '../../servisler/masa/qr_menu_adresi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

const _wifiYokMesaji = 'WiFi bağlantısı bulunamadı. Bu cihazın (tablet/telefon) '
    'bir WiFi ağına bağlı olması gerekiyor — müşterilerin '
    'siparişi görebilmesi için AYNI WiFi ağında olmaları şart.\n\n'
    'İpucu: Ayarlar\'dan "QR Menü Web Adresi" girerseniz, '
    'müşteriler mobil veriyle de sipariş verebilir.';

class MasaQrGosterEkrani extends StatefulWidget {
  final int masaId;
  final String masaAdi;
  const MasaQrGosterEkrani({super.key, required this.masaId, required this.masaAdi});

  @override
  State<MasaQrGosterEkrani> createState() => _MasaQrGosterEkraniState();
}

class _MasaQrGosterEkraniState extends State<MasaQrGosterEkrani> {
  String? _url;
  String? _hata;
  bool _yukleniyor = true;
  bool _bulutModu = false;
  bool _yazdiriliyor = false;

  StreamSubscription<List<ConnectivityResult>>? _baglantiAboneligi;
  Timer? _yenilemeGecikmesi;

  /// Eski bir çözümlemenin geç gelen sonucu yenisinin üzerine yazmasın.
  int _cozumNo = 0;

  @override
  void initState() {
    super.initState();
    _adresiCoz();
    // Bağlantı bilgisi alınamazsa (eklenti yok/izin) ekran yine çalışır;
    // kullanıcı appBar'daki "Adresi yenile" ile elle yenileyebilir.
    _baglantiAboneligi = Connectivity().onConnectivityChanged.listen(
      (_) => _baglantiDegisti(),
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _baglantiAboneligi?.cancel();
    _yenilemeGecikmesi?.cancel();
    super.dispose();
  }

  /// Bağlantı olayları art arda gelir (WiFi kapanır → mobil veri açılır);
  /// ağ arayüzü IP alana kadar kısa bir süre beklenip tek çözümleme yapılır.
  void _baglantiDegisti() {
    _yenilemeGecikmesi?.cancel();
    _yenilemeGecikmesi = Timer(const Duration(seconds: 2), () {
      if (mounted) _adresiCoz(sessiz: true);
    });
  }

  /// [sessiz]: arka plan yenilemesinde mevcut QR, yeni sonuç gelene kadar
  /// ekranda kalır (yükleniyor göstergesiyle titremez).
  Future<void> _adresiCoz({bool sessiz = false}) async {
    if (!mounted) return;
    final no = ++_cozumNo;
    if (!sessiz) setState(() { _yukleniyor = true; _hata = null; });
    final oncekiUrl = _url;
    try {
      final adres = await QrMenuAdresi.coz();
      if (!mounted || no != _cozumNo) return;
      setState(() {
        _yukleniyor = false;
        _url = adres?.masaUrl(widget.masaId);
        _bulutModu = adres?.bulut ?? false;
        _hata = adres == null ? _wifiYokMesaji : null;
      });
      if (sessiz && oncekiUrl != null && _url != null && _url != oncekiUrl) {
        BildirimServisi.uyari(context,
            'Ağ adresi değişti, QR güncellendi. Daha önce yazdırılan kartları yenileyin.');
      }
    } catch (e) {
      if (!mounted || no != _cozumNo) return;
      setState(() {
        _yukleniyor = false;
        _url = null;
        _hata = 'QR adresi oluşturulamadı: ${kullaniciyaHataMetni(e)}';
      });
    }
  }

  Future<void> _yazdir() async {
    if (!mounted) return;
    if (_yazdiriliyor) return;
    setState(() => _yazdiriliyor = true);
    try {
      final ok = await MasaQrYazdirServisi.yazdir([(id: widget.masaId, ad: widget.masaAdi)]);
      if (!ok && mounted) BildirimServisi.hata(context, 'QR adresi üretilemedi (WiFi yok)');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yazdırılamadı: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _yazdiriliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: '${widget.masaAdi} — QR Menü',
        gradyanli: false,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Adresi yenile',
            onPressed: _yukleniyor ? null : _adresiCoz,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _yukleniyor
              ? const TsYukleniyor()
              : url == null
                  ? _QrHataGorunumu(mesaj: _hata ?? _wifiYokMesaji, onTekrar: _adresiCoz)
                  : _QrKartGorunumu(
                      url: url,
                      bulutModu: _bulutModu,
                      yazdiriliyor: _yazdiriliyor,
                      onYazdir: _yazdir,
                    ),
        ),
      ),
    );
  }
}

class _QrHataGorunumu extends StatelessWidget {
  final String mesaj;
  final VoidCallback onTekrar;

  const _QrHataGorunumu({required this.mesaj, required this.onTekrar});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.wifi_off, size: 56, color: Colors.orange.shade400),
      const SizedBox(height: 16),
      Text(mesaj, textAlign: TextAlign.center, style: TextStyle(color: context.textSecondary)),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: onTekrar,
        icon: const Icon(Icons.refresh),
        label: const Text('Tekrar Dene'),
      ),
    ]);
  }
}

class _QrKartGorunumu extends StatelessWidget {
  final String url;
  final bool bulutModu;
  final bool yazdiriliyor;
  final VoidCallback onYazdir;

  const _QrKartGorunumu({
    required this.url,
    required this.bulutModu,
    required this.yazdiriliyor,
    required this.onYazdir,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      DecoratedBox(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 12)]),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: QrImageView(data: url, version: QrVersions.auto, size: 220),
        ),
      ),
      const SizedBox(height: 20),
      Text('Müşteriler bu kodu telefon kameralarıyla '
          'okutarak menüye ulaşıp sipariş verebilir.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textSecondary, fontSize: 13)),
      const SizedBox(height: 12),
      DecoratedBox(
        decoration: BoxDecoration(
            color: context.inputFill, borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: SelectableText(url, style: TextStyle(fontSize: 12, color: context.textPrimary)),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: yazdiriliyor ? null : onYazdir,
        icon: yazdiriliyor
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.print_outlined),
        label: Text(yazdiriliyor ? 'Hazırlanıyor…' : 'QR Kartını Yazdır'),
      ),
      const SizedBox(height: 16),
      _ErisimNotu(bulutModu: bulutModu),
    ]);
  }
}

/// Bulut modunda "mobil veriyle de çalışır", yerel modda "WiFi gerekir" —
/// kullanıcıyı yanıltmamak için.
class _ErisimNotu extends StatelessWidget {
  final bool bulutModu;

  const _ErisimNotu({required this.bulutModu});

  @override
  Widget build(BuildContext context) {
    final renk = bulutModu ? Colors.green : context.textHint;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(bulutModu ? Icons.public : Icons.info_outline, size: 14, color: renk),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          bulutModu
              ? 'İnternet üzerinden çalışıyor — mobil veri (4G/5G) ile de sipariş verilebilir'
              : 'Müşterinin işletme WiFi\'sine bağlı olması gerekir (mobil veri ile '
                  'çalışmaz). Ağ adresi değişirse yazdırılmış kartlar yenilenmelidir.',
          style: TextStyle(fontSize: 11, color: renk),
        ),
      ),
    ]);
  }
}
