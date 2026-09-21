// lib/ekranlar/kullanici/kullanici_liste_ekrani.dart
// Kullanıcı listesi - düzenleme, silme, yetki görüntüleme

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
          backgroundColor: Colors.red),
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
        return Colors.red;
      case 'mudur':
        return Colors.purple;
      case 'kasiyer':
        return Colors.blue;
      case 'personel':
        return Colors.green;
      case 'depocu':
        return Colors.orange;
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
    );

    if (ok != true) return;

    try {
      await _depo.sifreDegistir(k.id!, ctrl.text.trim());
      if (mounted) BildirimServisi.basari(context, 'Şifre değiştirildi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Şifre değiştirilemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
          : RefreshIndicator(
              onRefresh: _yukle,
              child: _kullanicilar.isEmpty
                  ? const TsBosDurum(ikon: Icons.people_outline, baslik: 'Kullanıcı bulunamadı')
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _kullanicilar.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                                      leading: Icon(Icons.delete, color: Colors.red),
                                      title: Text(
                                        'Sil',
                                        style: TextStyle(color: Colors.red),
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
      floatingActionButton: TsYetkili(child: FloatingActionButton.extended(
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