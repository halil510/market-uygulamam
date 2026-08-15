// lib/ekranlar/ayarlar/ai_asistan_ayar_ekrani.dart
//
// Önceden Gemini API anahtarı SADECE Ürün Ekle ekranına gömülü bir
// dialog üzerinden girilebiliyordu — genel bir "AI Asistan" ayarı
// olarak hiçbir yerde görünmüyordu. Artık hem ürün fotoğrafından
// bilgi çıkarma hem de AI Panel'deki genel sohbet asistanı AYNI
// anahtarı kullanıyor; buradan tek yerden yönetiliyor.
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../servisler/ai/ai_vision_servisi.dart';
import '../../servisler/ai/ai_genel_asistan.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class AiAsistanAyarEkrani extends StatefulWidget {
  const AiAsistanAyarEkrani({super.key});

  @override
  State<AiAsistanAyarEkrani> createState() => _AiAsistanAyarEkraniState();
}

class _AiAsistanAyarEkraniState extends State<AiAsistanAyarEkrani> {
  final _ctrl = TextEditingController();
  bool _gizli = true;
  bool _yukleniyor = true;
  bool _kayitli = false;
  bool _kaydediliyor = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final varMi = await AiVisionServisi().apiKeyVarMi();
      if (!mounted) return;
      setState(() {
        _kayitli = varMi;
        _yukleniyor = false;
      });
    } catch (e) {
      // 🔴 DÜZELTME: try-catch yoktu — servis hata verirse _yukleniyor
      // sonsuza kadar true kalıyordu.
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _kaydet() async {
    final key = _ctrl.text.trim();
    if (key.isEmpty) {
      BildirimServisi.uyari(context, 'API anahtarı girin');
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      await AiVisionServisi().setApiKey(key);
      AiGenelAsistan().sohbetiSifirla();
      if (mounted) {
        setState(() { _kayitli = true; _kaydediliyor = false; });
        BildirimServisi.basari(context, 'AI Asistan anahtarı kaydedildi ✓');
        _ctrl.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _kaydediliyor = false);
        BildirimServisi.hata(context, 'Kaydedilemedi: $e');
      }
    }
  }

  Future<void> _linkAc() async {
    final uri = Uri.parse('https://aistudio.google.com/app/apikey');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(baslik: 'AI Asistan Ayarları', gradyanli: true),
      body: _yukleniyor
          ? const TsYukleniyor()
          : ListView(
        padding: const EdgeInsets.all(TsBosluk.lg),
        children: [
          TsKart(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(
                _kayitli ? Icons.check_circle : Icons.info_outline,
                color: _kayitli ? TsRenk.basarili : TsRenk.uyari,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _kayitli
                      ? 'AI Asistan aktif. Ürün fotoğrafından bilgi çıkarma ve '
                        'genel sohbet asistanı (AI Panel) çalışıyor.'
                      : 'Henüz API anahtarı girilmedi. Rapor/stok/satış '
                        'sorularını yine de sorabilirsiniz — sadece genel '
                        'sorular ve fotoğraftan ürün doldurma çalışmaz.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _kayitli ? TsRenk.basarili : TsRenk.uyari,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: TsBosluk.xl),

          Text('Bu Anahtar Ne İşe Yarar?',
              style: TsMetin.baslikM.copyWith(color: TsRenk.metinIkincil(context))),
          const SizedBox(height: 8),
          TsKart(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ozellikSatiri(Icons.chat_bubble_outline, 'AI Panel Sohbet',
                  'Hazır rapor kalıplarına uymayan her türlü soruyu '
                  '("nasıl fatura keserim" gibi) yanıtlar.'),
              const Divider(height: 20),
              _ozellikSatiri(Icons.camera_alt_outlined, 'Ürün Fotoğrafından Doldurma',
                  'Ürün Ekle ekranında fotoğraf çekince ad, fiyat, KDV oranı '
                  'gibi alanları otomatik doldurur.'),
            ]),
          ),
          const SizedBox(height: TsBosluk.xl),

          TsInput(
            etiket: 'Gemini API Anahtarı',
            ipucu: 'AIza... ile başlayan anahtar',
            controller: _ctrl,
            sifreGizli: _gizli,
            oncilIkon: Icons.vpn_key_outlined,
            sonIkon: IconButton(
              icon: Icon(_gizli ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _gizli = !_gizli),
            ),
          ),
          const SizedBox(height: TsBosluk.sm),

          TextButton.icon(
            onPressed: _linkAc,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Ücretsiz API anahtarı almak için tıklayın'),
          ),
          const SizedBox(height: TsBosluk.md),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: TsButon(
              tamGenislik: true,
              yukleniyor: _kaydediliyor,
              metin: 'Kaydet',
              ikon: Icons.save_outlined,
              onPressed: _kaydediliyor ? null : _kaydet,
            ),
          ),
          const SizedBox(height: TsBosluk.lg),
          Center(
            child: Text(
              'Anahtarınız sadece bu cihazda saklanır, hiçbir sunucumuza gönderilmez.',
              style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ozellikSatiri(IconData ikon, String baslik, String aciklama) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(ikon, size: 20, color: TsRenk.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(baslik, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(aciklama, style: TextStyle(fontSize: 12, color: context.textSecondary)),
        ]),
      ),
    ],
  );
}
