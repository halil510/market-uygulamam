// lib/ekranlar/ayarlar/site_fotograflari_ekrani.dart
//
// Kullanıcı isteği: web sitesindeki işyeri fotoğrafları uygulamadan
// yönetilsin — HTML dosyasını değiştirip Netlify'a yeniden yükleme
// zahmeti olmasın. Bu ekrandan eklenen/silinen fotoğraflar ANINDA
// buluta yazılır; web sitesi bir sonraki açılışta yeni listeyi çeker.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/masa/site_icerik_servisi.dart';
import '../../servisler/bildirim_servisi.dart';

class SiteFotograflariEkrani extends StatefulWidget {
  const SiteFotograflariEkrani({super.key});

  @override
  State<SiteFotograflariEkrani> createState() => _SiteFotograflariEkraniState();
}

class _SiteFotograflariEkraniState extends State<SiteFotograflariEkrani> {
  final _servis = SiteIcerikServisi();
  List<String> _adresler = [];
  bool _yukleniyor = true;
  bool _islemde = false;

  @override
  void initState() {
    super.initState();
    _getir();
  }

  Future<void> _getir() async {
    setState(() => _yukleniyor = true);
    try {
      final liste = await _servis.gorselleriGetir();
      if (mounted) setState(() { _adresler = liste; _yukleniyor = false; });
    } catch (e) {
      // 🔴 DÜZELTME: try-catch yoktu — servis hata verirse _yukleniyor
      // sonsuza kadar true kalıyordu.
      if (mounted) {
        setState(() => _yukleniyor = false);
        _snack('Fotoğraflar yüklenemedi: $e', Colors.red);
      }
    }
  }

  Future<void> _ekle() async {
    if (_islemde) return;
    final secilen = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1400, imageQuality: 82);
    if (secilen == null) return;
    if (!mounted) return;
    setState(() => _islemde = true);
    final adres = await _servis.fotoYukle(secilen.path);
    if (adres != null) {
      _adresler.add(adres);
      final ok = await _servis.gorselleriKaydet(_adresler);
      _snack(ok
          ? 'Fotoğraf eklendi — web sitesinde görünecek ✓'
          : 'Fotoğraf yüklendi ama liste kaydedilemedi, tekrar deneyin',
          ok ? Colors.green : Colors.orange);
    } else {
      _snack('Yükleme başarısız — internet ve bulut ayarlarını kontrol edin '
          '(SQL kurulumunun yapılmış olması gerekir)', Colors.red);
    }
    if (mounted) setState(() => _islemde = false);
  }

  Future<void> _sil(int i) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Fotoğrafı Sil'),
        content: const Text('Bu fotoğraf web sitesinden kaldırılacak. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    setState(() => _islemde = true);
    final adres = _adresler[i];
    final yedek = List<String>.from(_adresler);
    _adresler.removeAt(i);
    try {
      await _servis.gorselleriKaydet(_adresler);
      await _servis.fotoSil(adres);
      if (mounted) _snack('Fotoğraf silindi ✓', Colors.green);
    } catch (e) {
      // 🔴 DÜZELTME: try-catch yoktu — hata durumunda hem _islemde
      // sonsuza kadar true kalıyordu hem de listeden zaten çıkarılan
      // fotoğraf geri getirilmiyordu (silinmiş gibi görünüp aslında
      // buluttan silinmemiş olabilirdi).
      _adresler
        ..clear()
        ..addAll(yedek);
      if (mounted) _snack('Silinemedi: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _islemde = false);
    }
  }

  void _snack(String m, Color c) {
    if (!mounted) return;
    // 🔴 UX TUTARLILIK DÜZELTMESİ: bkz. aynı düzeltme diğer ekranlarda —
    // artık paylaşılan BildirimServisi kullanılıyor.
    if (c == Colors.red) {
      BildirimServisi.hata(context, m);
    } else if (c == Colors.orange) {
      BildirimServisi.uyari(context, m);
    } else {
      BildirimServisi.basari(context, m);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'İşyeri Fotoğrafları (Web Sitesi)',
        gradyanli: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _islemde ? null : _ekle,
        icon: _islemde
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_photo_alternate),
        label: Text(_islemde ? 'Yükleniyor...' : 'Fotoğraf Ekle'),
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : Column(children: [
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: context.inputFill,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 18, color: context.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                      'Buradan eklediğiniz fotoğraflar, web sitenizin '
                      '"Hakkımızda" sayfasındaki "İşyerimizden Kareler" '
                      'bölümünde otomatik görünür — HTML dosyasına dokunmanıza '
                      'gerek yok.',
                      style: TextStyle(fontSize: 12, color: context.textSecondary))),
                ]),
              ),
              Expanded(
                child: _adresler.isEmpty
                    ? Center(child: Text('Henüz fotoğraf yok.\n"Fotoğraf Ekle" ile başlayın.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textHint)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, crossAxisSpacing: 10,
                            mainAxisSpacing: 10, childAspectRatio: 1.25),
                        itemCount: _adresler.length,
                        itemBuilder: (c, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.network(_adresler[i], fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                    color: context.inputFill,
                                    child: const Icon(Icons.broken_image))),
                            Positioned(
                              top: 6, right: 6,
                              child: GestureDetector(
                                onTap: () => _sil(i),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(140),
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.white),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
              ),
            ]),
    );
  }
}
