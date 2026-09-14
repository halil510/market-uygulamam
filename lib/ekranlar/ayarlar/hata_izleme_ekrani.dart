// lib/ekranlar/ayarlar/hata_izleme_ekrani.dart
//
// BARKOPRO ULTIMATE denetiminde bulunan eksiklik: uygulama hataları
// SADECE cihazın kendi Sistem Logları'na kaydediliyordu — birden fazla
// müşteriye dağıtılmış bir üründe, ofisten UZAKTAN hiçbir hata
// görünürlüğü yoktu. Bu ekran, kullanıcının KENDİ (ücretsiz) Sentry
// hesabından aldığı DSN'i girip aktif etmesini sağlar — AI Asistan
// Ayarları'ndaki API anahtarı ekranıyla AYNI desen (girilmezse hiçbir
// şey değişmez, dışarıya hiçbir veri gitmez).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../servisler/hata_izleme_ayarlari.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

class HataIzlemeEkrani extends StatefulWidget {
  const HataIzlemeEkrani({super.key});

  @override
  State<HataIzlemeEkrani> createState() => _HataIzlemeEkraniState();
}

class _HataIzlemeEkraniState extends State<HataIzlemeEkrani> {
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
      final dsn = await HataIzlemeAyarlari.dsnOku();
      if (!mounted) return;
      setState(() {
        _kayitli = dsn != null && dsn.trim().isNotEmpty;
        _yukleniyor = false;
      });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _kaydet() async {
    final dsn = _ctrl.text.trim();
    if (dsn.isEmpty) {
      BildirimServisi.uyari(context, 'DSN girin');
      return;
    }
    if (!dsn.startsWith('http')) {
      BildirimServisi.uyari(context, 'Geçersiz DSN — Sentry projenizin '
          '"Client Keys (DSN)" sayfasından kopyaladığınızdan emin olun');
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      await HataIzlemeAyarlari.kaydet(dsn);
      if (mounted) {
        setState(() { _kayitli = true; _kaydediliyor = false; });
        BildirimServisi.basari(context,
            'Kaydedildi ✓ — uygulamayı yeniden başlatınca aktif olur');
        _ctrl.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _kaydediliyor = false);
        BildirimServisi.hata(context, 'Kaydedilemedi: $e');
      }
    }
  }

  Future<void> _kaldir() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hata İzlemeyi Kapat'),
        content: const Text('DSN silinsin mi? Uzaktan hata bildirimi devre '
            'dışı kalır, hatalar sadece cihazda (Sistem Logları) kalmaya '
            'devam eder.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kapat')),
        ],
      ),
    );
    if (onay != true) return;
    await HataIzlemeAyarlari.temizle();
    if (mounted) {
      setState(() => _kayitli = false);
      BildirimServisi.basari(context, 'Hata izleme kapatıldı');
    }
  }

  Future<void> _linkAc() async {
    final uri = Uri.parse('https://sentry.io/signup/');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(baslik: 'Hata İzleme', gradyanli: true),
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
                      ? 'Hata izleme aktif. Uygulamada beklenmeyen bir hata '
                        'oluşursa Sentry hesabınıza otomatik bildirim gider.'
                      : 'Henüz aktif değil. Hatalar sadece bu cihazın kendi '
                        'Sistem Logları\'nda kalıyor — uzaktan görülemiyor.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _kayitli ? TsRenk.basarili : TsRenk.uyari,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: TsBosluk.xl),

          Text('Bu Ne İşe Yarar?',
              style: TsMetin.baslikM.copyWith(color: TsRenk.metinIkincil(context))),
          const SizedBox(height: 8),
          TsKart(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ozellikSatiri(Icons.wifi_tethering_error_rounded, 'Uzaktan Görünürlük',
                  'Bir müşteride/şubede hata çıkarsa, o cihazın ekranını '
                  'görmeden ofisten fark edip düzeltebilirsiniz.'),
              const Divider(height: 20),
              _ozellikSatiri(Icons.shield_outlined, 'Gizlilik',
                  'DSN girmezseniz hiçbir şey değişmez — hiçbir veri hiçbir '
                  'yere gönderilmez. Sadece siz kendi Sentry hesabınızı '
                  'bağlarsınız, veriler sadece SİZİN hesabınıza gider.'),
            ]),
          ),
          const SizedBox(height: TsBosluk.xl),

          TsInput(
            etiket: 'Sentry DSN',
            ipucu: 'https://xxxx@xxxx.ingest.sentry.io/xxxx',
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
            label: const Text('Ücretsiz Sentry hesabı açmak için tıklayın'),
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
          if (_kayitli) ...[
            const SizedBox(height: TsBosluk.sm),
            TextButton.icon(
              onPressed: _kaldir,
              icon: Icon(Icons.link_off, size: 16, color: TsRenk.hata),
              label: Text('Hata İzlemeyi Kapat',
                  style: TextStyle(color: TsRenk.hata)),
            ),
          ],
          const SizedBox(height: TsBosluk.lg),
          Center(
            child: Text(
              'Yeni bir DSN kaydettikten sonra aktif olması için uygulamayı '
              'yeniden başlatın.',
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
