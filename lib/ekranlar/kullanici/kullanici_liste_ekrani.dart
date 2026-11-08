// lib/ekranlar/kullanici/kullanici_liste_ekrani.dart
// Kullanıcı listesi - düzenleme, silme, yetki görüntüleme

import '../../cekirdek/utils/denetleyici_birak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../modeller/kullanici_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/auth_servisi.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../widgetlar/ortak/yonetici_sifre_dialogu.dart';
import '../../widgetlar/masaustu/basit_liste_masaustu.dart';
import '../../widgetlar/masaustu/masaustu_tablo.dart';

class KullaniciListeEkrani extends ConsumerStatefulWidget {
  const KullaniciListeEkrani({super.key});
  @override
  ConsumerState<KullaniciListeEkrani> createState() => _KullaniciListeEkraniState();
}

class _KullaniciListeEkraniState extends ConsumerState<KullaniciListeEkrani> {
  final _depo = KullaniciDeposu();
  List<KullaniciModel> _kullanicilar = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    _yukleniyor = true;

    if (mounted) setState(() {});
    try {
      final list = await _depo.tumunuGetir();
      if (!mounted) return;
        _kullanicilar = list;
        _yukleniyor = false;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _sil(KullaniciModel k) async {
    if (k.kullaniciAdi == AuthServisi().aktifKullanici?.kullaniciAdi) {
      BildirimServisi.uyari(context, 'Aktif kullanıcıyı silemezsiniz');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Kullanıcıyı Sil'),
        content: Text('${k.adSoyad} silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: TsRenk.hata),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 🔴 DEEP_AUDIT_REPORT madde 7 (Reauth kapsamı): kullanıcı silme
    // cari/borç silmeyle AYNI risk sınıfında (geri dönüşü zor, o
    // kullanıcının geçmiş işlemlerindeki kasiyer/kullanıcı bağlantısı
    // kaybolur) ama reauth istemiyordu.
    if (!mounted) return;
    final onaylandi = await yoneticiSifresiIleOnayIste(
      context,
      baslik: 'Kullanıcı Silme Onayı',
      aciklama: '${k.adSoyad} kalıcı olarak silinecek. Devam etmek için '
          'şifrenizi girin.',
    );
    if (!onaylandi || !mounted) return;
    if (!ref.read(authProvider).isMudur) return; // savunma: eylem anında ikinci kez doğrula

    await _depo.sil(k.id!);
    await _yukle();
    if (mounted) BildirimServisi.basari(context, 'Kullanıcı silindi');
  }

  Color _rolRenk(String rol) {
    switch (rol) {
      case 'admin':
        return TsRenk.hata;
      case 'mudur':
        return TsRenk.vurguMor;
      case 'kasiyer':
        return TsRenk.bilgi;
      case 'personel':
        return TsRenk.basarili;
      case 'depocu':
        return TsRenk.uyari;
      default:
        return context.textSecondary;
    }
  }

  Future<void> _sifreDegistir(KullaniciModel k) async {
    final ctrl = TextEditingController();
    bool goster = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Şifre Değiştir: ${k.adSoyad}'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: !goster,
            decoration: InputDecoration(
              labelText: 'Yeni Şifre (min. 4 karakter)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(goster ? Icons.visibility_off : Icons.visibility),
                onPressed: () => ss(() => goster = !goster),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().length < 4) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Şifre en az 4 karakter olmalı')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Değiştir'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogSonrasiBirak([ctrl]));

    if (ok != true) return;

    try {
      await _depo.sifreDegistir(k.id!, ctrl.text.trim());
      if (mounted) BildirimServisi.basari(context, 'Şifre değiştirildi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Şifre değiştirilemedi: $e');
    }
  }

  Future<void> _ekle() async {
    final ok = await context.push<bool>('/kullanici/ekle');
    if (ok == true) _yukle();
  }

  Future<void> _duzenle(KullaniciModel k) async {
    final ok = await context.push<bool>('/kullanici/ekle', extra: k);
    if (ok == true) _yukle();
  }

  bool _aktifMi(KullaniciModel k) =>
      AuthServisi().aktifKullanici?.kullaniciAdi == k.kullaniciAdi;

  /// Masaüstü tablo (Kategori/Marka düzeni). Ekle/Düzenle/Sil/Şifre yalnız
  /// Admin/Müdür'e (mobildeki TsYetkili ile aynı kural); aktif kullanıcı
  /// kendini silemez.
  Widget _masaustuTablo(bool yetkili) => BasitListeMasaustu<KullaniciModel>(
        satirlar: _kullanicilar,
        kolonlar: [
          TabloKolon(
              baslik: 'Ad Soyad',
              genislik: 240,
              esnek: true,
              deger: (k) => _aktifMi(k) ? '${k.adSoyad}  (oturum açık)' : k.adSoyad,
              sirala: (k) => k.adSoyad.toLowerCase()),
          TabloKolon(
              baslik: 'Kullanıcı Adı',
              genislik: 180,
              deger: (k) => k.kullaniciAdi,
              sirala: (k) => k.kullaniciAdi.toLowerCase()),
          TabloKolon(
              baslik: 'Rol',
              genislik: 140,
              deger: (k) => k.rol,
              sirala: (k) => k.rol,
              renk: (k) => _rolRenk(k.rol)),
          TabloKolon(
              baslik: 'Durum',
              genislik: 110,
              deger: (k) => k.aktif ? 'Aktif' : 'Pasif',
              sirala: (k) => k.aktif ? 0 : 1,
              renk: (k) => k.aktif ? TsRenk.basarili : TsRenk.hata),
          TabloKolon(
              baslik: 'Son Giriş',
              genislik: 170,
              deger: (k) => _tarih(k.sonGiris),
              sirala: (k) => k.sonGiris ?? ''),
        ],
        aramaMetniAl: (k) => '${k.adSoyad} ${k.kullaniciAdi} ${k.rol}',
        kayitEtiketi: 'Kullanıcı',
        bosMesaj: 'Kullanıcı bulunamadı',
        onEkle: yetkili ? _ekle : null,
        onDuzenle: yetkili ? _duzenle : null,
        onSil: yetkili ? _sil : null,
        silinebilir: (k) => !_aktifMi(k),
        ekEylemler: [
          if (yetkili) ('Şifre Değiştir', Icons.lock_reset, _sifreDegistir),
        ],
      );

  static String _tarih(String? iso) {
    final t = iso == null ? null : DateTime.tryParse(iso);
    if (t == null) return '—';
    final y = t.toLocal();
    String iki(int n) => n.toString().padLeft(2, '0');
    return '${iki(y.day)}.${iki(y.month)}.${y.year} ${iki(y.hour)}:${iki(y.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final masaustu = MediaQuery.sizeOf(context).width > 1100;
    final yetkili = ref.watch(authProvider.select((s) => s.isMudur));
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Kullanıcılar (${_kullanicilar.length})',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _yukle,
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _yukleniyor
          ? const TsYukleniyor(iskelet: true)
          : masaustu
          ? _masaustuTablo(yetkili)
          : RefreshIndicator(
              onRefresh: _yukle,
              child: _kullanicilar.isEmpty
                  ? const TsBosDurum(ikon: Icons.people_outline, baslik: 'Kullanıcı bulunamadı')
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _kullanicilar.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final k = _kullanicilar[i];
                        final aktifKullanici =
                            AuthServisi().aktifKullanici?.kullaniciAdi == k.kullaniciAdi;
                        final rolRenk = _rolRenk(k.rol);
                        return TsKart.liste(
                          secili: aktifKullanici,
                          ikon: Text(
                            k.adSoyad.isNotEmpty ? k.adSoyad[0].toUpperCase() : '?',
                            style: TextStyle(fontWeight: FontWeight.w700, color: rolRenk),
                          ),
                          baslik: k.adSoyad,
                          etiketler: [
                            if (aktifKullanici) const TsBadge(metin: 'AKTİF', tur: TsBadgeTuru.basarili),
                          ],
                          altBaslik: '@${k.kullaniciAdi}',
                          sagAksiyon: Row(mainAxisSize: MainAxisSize.min, children: [
                            TsBadge(metin: k.rol.toUpperCase(), tur: TsBadgeTuru.bilgi),
                            const SizedBox(width: 6),
                            TsBadge(
                              metin: k.aktif ? 'Aktif Hesap' : 'Pasif',
                              tur: k.aktif ? TsBadgeTuru.basarili : TsBadgeTuru.hata,
                            ),
                            TsYetkili(child: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'duzenle') {
                                  final ok = await context.push<bool>(
                                    '/kullanici/ekle',
                                    extra: k,
                                  );
                                  if (ok == true) _yukle();
                                }
                                if (v == 'sil') _sil(k);
                                if (v == 'sifreDegistir') _sifreDegistir(k);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'duzenle',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.edit, color: AppRenkler.primary),
                                    title: Text('Düzenle & Yetkiler'),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'sifreDegistir',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.lock_reset, color: AppRenkler.primary),
                                    title: Text('Şifre Değiştir'),
                                  ),
                                ),
                                if (!aktifKullanici)
                                  const PopupMenuItem(
                                    value: 'sil',
                                    child: ListTile(
                                      dense: true,
                                      leading: Icon(Icons.delete, color: TsRenk.hata),
                                      title: Text(
                                        'Sil',
                                        style: TextStyle(color: TsRenk.hata),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
      floatingActionButton: masaustu ? null : TsYetkili(child: FloatingActionButton.extended(
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: () async {
          final ok = await context.push<bool>('/kullanici/ekle');
          if (ok == true) _yukle();
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Kullanıcı Ekle'),
      )),
    );
  }
}