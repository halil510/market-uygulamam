// lib/ekranlar/ayarlar/site_icerik_ekrani.dart
//
// Kullanıcı isteği: QR menü web sitesindeki (qr_menu_sayfasi.html) işletme
// adı, alt yazı, "Hakkımızda" metni, iletişim bilgileri, konum ve istatistik
// kartları ARTIK uygulamadan düzenlensin — HTML dosyasına elle dokunup
// yeniden yükleme zahmeti olmasın. Fotoğraf galerisiyle (site_fotograflari_ekrani.dart)
// AYNI kanıtlanmış desen: site_icerik key-value tablosu, web sitesi açılışta
// bu değerleri çekip kendi hardcoded yedeğinin üzerine yazıyor.
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/masa/site_icerik_servisi.dart';
import '../../servisler/bildirim_servisi.dart';

class SiteIcerikEkrani extends StatefulWidget {
  const SiteIcerikEkrani({super.key});

  @override
  State<SiteIcerikEkrani> createState() => _SiteIcerikEkraniState();
}

class _IstatistikCtrl {
  final sayi = TextEditingController();
  final etiket = TextEditingController();
  void dispose() {
    sayi.dispose();
    etiket.dispose();
  }
}

class _SiteIcerikEkraniState extends State<SiteIcerikEkrani> {
  final _servis = SiteIcerikServisi();
  bool _yukleniyor = true;
  bool _kaydediliyor = false;

  final _isletmeAdi = TextEditingController();
  final _altYazi = TextEditingController();
  final _hakkimizda = TextEditingController();
  final _adres = TextEditingController();
  final _telefon = TextEditingController();
  final _eposta = TextEditingController();
  final _instagram = TextEditingController();
  final _facebook = TextEditingController();
  final _calismaSaatleri = TextEditingController();
  final _konum = TextEditingController();
  final _istatistikler = List.generate(3, (_) => _IstatistikCtrl());

  @override
  void initState() {
    super.initState();
    _getir();
  }

  @override
  void dispose() {
    _isletmeAdi.dispose();
    _altYazi.dispose();
    _hakkimizda.dispose();
    _adres.dispose();
    _telefon.dispose();
    _eposta.dispose();
    _instagram.dispose();
    _facebook.dispose();
    _calismaSaatleri.dispose();
    _konum.dispose();
    for (final i in _istatistikler) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _getir() async {
    setState(() => _yukleniyor = true);
    try {
      final v = await _servis.isletmeBilgileriGetir();
      if (v != null) {
        _isletmeAdi.text = v['isletmeAdi']?.toString() ?? '';
        _altYazi.text = v['altYazi']?.toString() ?? '';
        _hakkimizda.text = v['hakkimizda']?.toString() ?? '';
        final iletisim = v['iletisim'] as Map<String, dynamic>? ?? {};
        _adres.text = iletisim['adres']?.toString() ?? '';
        _telefon.text = iletisim['telefon']?.toString() ?? '';
        _eposta.text = iletisim['eposta']?.toString() ?? '';
        _instagram.text = iletisim['instagram']?.toString() ?? '';
        _facebook.text = iletisim['facebook']?.toString() ?? '';
        _calismaSaatleri.text = iletisim['calismaSaatleri']?.toString() ?? '';
        _konum.text = v['konum']?.toString() ?? '';
        final ist = v['istatistikler'] as List? ?? [];
        for (var i = 0; i < _istatistikler.length && i < ist.length; i++) {
          final m = ist[i] as Map<String, dynamic>;
          _istatistikler[i].sayi.text = m['sayi']?.toString() ?? '';
          _istatistikler[i].etiket.text = m['etiket']?.toString() ?? '';
        }
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    setState(() => _kaydediliyor = true);
    final veri = {
      'isletmeAdi': _isletmeAdi.text.trim(),
      'altYazi': _altYazi.text.trim(),
      'hakkimizda': _hakkimizda.text.trim(),
      'iletisim': {
        'adres': _adres.text.trim(),
        'telefon': _telefon.text.trim(),
        'eposta': _eposta.text.trim(),
        'instagram': _instagram.text.trim(),
        'facebook': _facebook.text.trim(),
        'calismaSaatleri': _calismaSaatleri.text.trim(),
      },
      'konum': _konum.text.trim(),
      'istatistikler': _istatistikler
          .where((i) => i.sayi.text.trim().isNotEmpty)
          .map((i) =>
              {'sayi': i.sayi.text.trim(), 'etiket': i.etiket.text.trim()})
          .toList(),
    };
    final ok = await _servis.isletmeBilgileriKaydet(veri);
    if (mounted) {
      setState(() => _kaydediliyor = false);
      if (ok) {
        BildirimServisi.basari(context,
            'Kaydedildi — web sitesinde bir sonraki açılışta görünecek ✓');
      } else {
        BildirimServisi.hata(context,
            'Kaydedilemedi — internet ve bulut ayarlarını kontrol edin');
      }
    }
  }

  Widget _bolum(String baslik, List<Widget> alanlar) => Container(
        margin: const EdgeInsets.only(bottom: TsBosluk.lg),
        padding: const EdgeInsets.all(TsBosluk.lg),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(TsRadius.lg),
          boxShadow: TsGolge.yumusak,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(baslik,
              style: TsMetin.baslikM
                  .copyWith(color: TsRenk.metinBirincil(context))),
          const SizedBox(height: TsBosluk.md),
          ...alanlar,
        ]),
      );

  Widget _alan(String etiket, TextEditingController c,
          {int maxLines = 1, String? ipucu}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: TsBosluk.md),
        child: TsInput(
            etiket: etiket, controller: c, maksSatir: maxLines, ipucu: ipucu),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(baslik: 'Site İçeriği (Web Sitesi)', gradyanli: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _kaydediliyor ? null : _kaydet,
        icon: _kaydediliyor
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_outlined),
        label: Text(_kaydediliyor ? 'Kaydediliyor...' : 'Kaydet'),
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  TsBosluk.lg, TsBosluk.lg, TsBosluk.lg, 90),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: TsBosluk.lg),
                      padding: const EdgeInsets.all(TsBosluk.md),
                      decoration: BoxDecoration(
                          color: context.inputFill,
                          borderRadius: BorderRadius.circular(TsRadius.md)),
                      child: Row(children: [
                        Icon(Icons.info_outline,
                            size: 18, color: context.textSecondary),
                        const SizedBox(width: TsBosluk.sm),
                        Expanded(
                          child: Text(
                            'Bir alanı boş bırakırsanız web sitesi kendi varsayılan '
                            'metnini gösterir — hiçbir şey bozulmaz.',
                            style: TextStyle(
                                fontSize: 12, color: context.textSecondary),
                          ),
                        ),
                      ]),
                    ),
                    _bolum('Genel', [
                      _alan('İşletme Adı', _isletmeAdi, ipucu: 'Örn: DoğalOra'),
                      _alan('Alt Yazı', _altYazi,
                          ipucu: 'Örn: Lezzetin Doğal Hâli'),
                    ]),
                    _bolum('Hakkımızda', [
                      _alan('Hakkımızda Metni', _hakkimizda, maxLines: 8),
                    ]),
                    _bolum('İstatistik Kartları (Hakkımızda sayfası)', [
                      for (var i = 0; i < _istatistikler.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                          child: Row(children: [
                            Expanded(
                              flex: 2,
                              child: TsInput(
                                  etiket: 'Sayı',
                                  controller: _istatistikler[i].sayi,
                                  ipucu: '1993'),
                            ),
                            const SizedBox(width: TsBosluk.sm),
                            Expanded(
                              flex: 3,
                              child: TsInput(
                                  etiket: 'Etiket',
                                  controller: _istatistikler[i].etiket,
                                  ipucu: "'ten Beri Hizmetinizde"),
                            ),
                          ]),
                        ),
                    ]),
                    _bolum('İletişim', [
                      _alan('Adres', _adres, maxLines: 2),
                      _alan('Telefon', _telefon, ipucu: '05550020005'),
                      _alan('E-posta', _eposta),
                      _alan('Instagram Kullanıcı Adı', _instagram,
                          ipucu: '@ olmadan'),
                      _alan('Facebook Sayfa Adı', _facebook),
                      _alan('Çalışma Saatleri', _calismaSaatleri,
                          ipucu: 'Her gün 07:00 – 24:00'),
                    ]),
                    _bolum('Konum', [
                      _alan('Enlem,Boylam', _konum,
                          ipucu:
                              'Google Haritalar\'da konuma sağ tıklayıp koordinatı kopyalayın'),
                    ]),
                  ]),
            ),
    );
  }
}
