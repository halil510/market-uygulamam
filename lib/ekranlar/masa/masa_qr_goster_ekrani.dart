// lib/ekranlar/masa/masa_qr_goster_ekrani.dart
//
// Kullanıcı isteği: "müşteriler kendi telefonuyla masadaki QR'ı
// okutup sipariş versin." Bu ekran, o QR kodun GERÇEKTEN üretildiği
// ve gösterildiği yer — önceden bu adım hiç yoktu (qrKodUrlOlustur()
// fonksiyonu vardı ama hiçbir ekranda çağrılmıyordu).
import 'package:flutter/material.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../servisler/masa/qr_menu_sunucu_servisi.dart';

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

  @override
  void initState() {
    super.initState();
    _baslat();
  }

  Future<void> _baslat() async {
    setState(() { _yukleniyor = true; _hata = null; });
    try {
      // ÖNCELİK: kullanıcı isteği üzerine eklenen bulut (internet
      // üzerinden, mobil veriyle de erişilebilen) adres. Ayarlar'dan
      // girilmişse bu, yerel WiFi sunucusundan DAHA İYİ bir deneyim
      // sağlıyor — müşterinin işletme WiFi'sine bağlı olması
      // gerekmiyor.
      final prefs = await SharedPreferences.getInstance();
      final bulutUrl = prefs.getString('qr_menu_web_url');
      if (bulutUrl != null && bulutUrl.trim().isNotEmpty) {
        final ayrac = bulutUrl.contains('?') ? '&' : '?';
        setState(() {
          _url = '$bulutUrl${ayrac}masa=${widget.masaId}';
          _bulutModu = true;
          _yukleniyor = false;
        });
        return;
      }

      // Bulut adresi henüz girilmemişse, yerel WiFi sunucusuna dön
      // (işletme WiFi'si ile çalışır, mobil veriyle çalışmaz).
      final ip = await QrMenuSunucuServisi().baslatVeIpAl();
      if (ip == null) {
        if (!mounted) return;
        setState(() {
          _hata = 'WiFi bağlantısı bulunamadı. Bu cihazın (tablet/telefon) '
              'bir WiFi ağına bağlı olması gerekiyor — müşterilerin '
              'siparişi görebilmesi için AYNI WiFi ağında olmaları şart.\n\n'
              'İpucu: Ayarlar\'dan "QR Menü Web Adresi" girerseniz, '
              'müşteriler mobil veriyle de sipariş verebilir.';
          _yukleniyor = false;
        });
        return;
      }
      final url = QrMenuSunucuServisi().masaUrlOlustur(widget.masaId);
      setState(() { _url = url; _bulutModu = false; _yukleniyor = false; });
    } catch (e) {
      setState(() { _hata = 'Sunucu başlatılamadı: $e'; _yukleniyor = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: '${widget.masaAdi} — QR Menü',
        gradyanli: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _yukleniyor
              ? const CircularProgressIndicator()
              : _hata != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off, size: 56, color: Colors.orange.shade400),
                      const SizedBox(height: 16),
                      Text(_hata!, textAlign: TextAlign.center,
                          style: TextStyle(color: context.textSecondary)),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _baslat,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tekrar Dene'),
                      ),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(
                                color: Colors.black.withAlpha(20), blurRadius: 12)]),
                        child: QrImageView(data: _url!, version: QrVersions.auto, size: 220),
                      ),
                      const SizedBox(height: 20),
                      Text('Müşteriler bu kodu telefon kameralarıyla '
                          'okutarak menüye ulaşıp sipariş verebilir.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.textSecondary, fontSize: 13)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: context.inputFill,
                            borderRadius: BorderRadius.circular(10)),
                        child: SelectableText(_url!,
                            style: TextStyle(fontSize: 12, color: context.textPrimary)),
                      ),
                      const SizedBox(height: 16),
                      // Bulut modundaysa "mobil veriyle de çalışır"
                      // mesajı, yerel WiFi modundaysa "WiFi gerekir"
                      // uyarısı gösteriliyor — kullanıcıyı yanıltmamak
                      // için.
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_bulutModu ? Icons.public : Icons.info_outline,
                            size: 14, color: _bulutModu ? Colors.green : context.textHint),
                        const SizedBox(width: 6),
                        Flexible(child: Text(
                            _bulutModu
                                ? 'İnternet üzerinden çalışıyor — mobil veri (4G/5G) ile de sipariş verilebilir'
                                : 'Müşterinin işletme WiFi\'sine bağlı olması gerekir '
                                  '(mobil veri ile çalışmaz)',
                            style: TextStyle(fontSize: 11,
                                color: _bulutModu ? Colors.green : context.textHint))),
                      ]),
                    ]),
        ),
      ),
    );
  }
}
