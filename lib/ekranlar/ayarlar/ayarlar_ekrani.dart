import '../../cekirdek/utils/dosya_paylasim.dart';

import 'package:flutter/foundation.dart';

import '../../cekirdek/utils/denetleyici_birak.dart';
// lib/ekranlar/ayarlar/ayarlar_ekrani.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgetlar/masaustu/ekran_ustte.dart';

import '../../widgetlar/ortak/app_widgetlar.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../../servisler/auth_servisi.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../widgetlar/ortak/yonetici_sifre_dialogu.dart';
import '../../depolar/ayarlar_deposu.dart';
import '../../servisler/excel_servisi.dart';
import '../../saglayicilar/riverpod/masa_modu_provider.dart';
import '../../depolar/urun_deposu.dart';
import '../../servisler/veritabani_dosya_servisi.dart';
import '../../cekirdek/sabitler/db_sabitleri.dart';
import '../../cekirdek/sabitler/uygulama_sabitleri.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/ortak/yukleniyor_widget.dart';
import '../../widgetlar/ortak/onay_dialog.dart';
import '../../saglayicilar/riverpod/tema_provider.dart';
import '../../servisler/bulut/supabase_ayarlari.dart';
import '../../cekirdek/utils/metin_arama.dart';
part 'ayarlar_ekrani_islemler.dart';
part 'ayarlar_ekrani_kategoriler.dart';

class AyarlarEkrani extends ConsumerStatefulWidget {
  const AyarlarEkrani({super.key});
  @override
  ConsumerState<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends ConsumerState<AyarlarEkrani> {
  final _ayarlarDepo = AyarlarDeposu();
  final _urunDepo = UrunDeposu();
  Map<String, String> _ayarlar = {};
  bool _yukleniyor = true;

  // Kategori düzeni (bkz. ayarlar_ekrani_kategoriler.dart).
  final _aramaCtrl = TextEditingController();
  late final _aramaOdak = FocusNode(onKeyEvent: _aramaTus);
  String _arama = '';
  String? _kategori;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
    IcGeri.ekle(_escIcGeri);
  }

  @override
  void dispose() {
    IcGeri.cikar(_escIcGeri);
    _aramaCtrl.dispose();
    _aramaOdak.dispose();
    super.dispose();
  }

  void _aramaDegis(String v) => setState(() => _arama = v);
  void _kategoriSec(String? ad) => setState(() => _kategori = ad);
  void _aramaTemizle() => setState(() {
    _aramaCtrl.clear();
    _arama = '';
  });

  /// Masaüstü Esc / üst "Geri" (bkz. IcGeri) — yalnız bu ekran üstteyken.
  bool _escIcGeri() => mounted && ekranUstte(context) && _icGeri();

  /// Arama kutusundayken Esc: doluysa temizler (genel Esc yazı alanında
  /// çalışmaz), boşsa odaktan çıkar.
  KeyEventResult _aramaTus(FocusNode node, KeyEvent olay) {
    if (olay is! KeyDownEvent || olay.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_arama.isNotEmpty) {
      _aramaTemizle();
    } else {
      node.unfocus();
    }
    return KeyEventResult.handled;
  }

  /// Geri: önce arama/kategori kapanır, sonra ekrandan çıkılır.
  bool _icGeri() {
    if (_arama.isNotEmpty) {
      setState(() {
        _aramaCtrl.clear();
        _arama = '';
      });
      return true;
    }
    if (_kategori != null) {
      setState(() => _kategori = null);
      return true;
    }
    return false;
  }

  Future<void> _yukle() async {
    if (mounted) setState(() => _yukleniyor = true);
    try {
      final ayarlar = await _ayarlarDepo.hepsiGetir();
      if (mounted) {
        setState(() {
          _ayarlar = ayarlar;
          _yukleniyor = false;
        });
      }
    } catch (e) {
      // 🔴 DÜZELTME: catch bloğu _yukleniyor'u hiç false yapmıyordu —
      // hata olursa ekran sonsuza kadar "yükleniyor" durumunda kalıyordu.
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ayarGuncelle(String anahtar, String deger) async {
    try {
      await _ayarlarDepo.kaydet(anahtar, deger);
      if (mounted) setState(() => _ayarlar[anahtar] = deger);
    } catch (e) {
      if (kDebugMode) debugPrint('Ayar kaydetme hatası: $e');
    }
  }

  Future<void> _cikisYap() async {
    bool onay = false;
    try {
      onay = await OnayDialog.goster(
        context,
        baslik: 'Çıkış Yap',
        icerik: 'Oturumu kapatmak istiyor musunuz?',
        onayYazi: 'Çıkış Yap',
        onayRengi: TsRenk.hata,
        ikon: Icons.logout,
      );
    } catch (_) {
      onay = false;
    }
    if (!onay || !mounted) return;
    try {
      await ref.read(authProvider.notifier).cikisYap();
      if (mounted) context.go('/giris');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Çıkış hatası: $e');
    }
  }

  void _temaDegistir(String tema) {
    // ÖNEMLİ DÜZELTME: Önceden sadece SharedPreferences'a yazılıyordu,
    // canlı tema (MaterialApp) hiç güncellenmiyordu — kullanıcı "Koyu Tema"
    // seçtiğinde uygulama yeniden başlatılana kadar hiçbir şey değişmiyordu.
    // Artık temaProvider üzerinden değiştiriliyor; ekran anında güncelleniyor.
    ref.read(temaProvider.notifier).degistir(tema);
    setState(() => _ayarlar['tema'] = tema);
  }

  // ── VERİTABANINI TEMİZLE (DÜZELTİLMİŞ) ─────────────────────────────────────
  // lib/ekranlar/ayarlar/ayarlar_ekrani.dart
  // ... (üstteki kodlar aynı) ...

  Future<bool> _onWillPop() async {
    final isFirst = ModalRoute.of(context)?.isFirst ?? false;
    if (isFirst) {
      final exitConfirmed = await OnayDialog.goster(
        context,
        baslik: 'Uygulamadan Çık',
        icerik: 'Uygulamadan çıkmak istediğinize emin misiniz?',
        onayYazi: 'Evet, Çık',
        onayRengi: TsRenk.hata,
      );
      if (exitConfirmed) exit(0);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final aktif = AuthServisi().aktifKullanici;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !_icGeri()) await _onWillPop();
      },
      child: Scaffold(
        appBar: TsAppBar(
          baslik: 'Ayarlar',
          lider: BackButton(
            onPressed: () {
              if (!_icGeri()) context.go('/');
            },
          ),
        ),
        body: _yukleniyor
            ? const AppYukleniyor()
            : Builder(
                builder: (context) {
                  final kategoriler = _kategoriler();
                  final secili = _kategori == null
                      ? null
                      : kategoriler.where((k) => k.ad == _kategori).firstOrNull;
                  return ListView(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [TsRenk.primary, TsRenk.primaryKoyu],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              aktif?.adSoyad.isNotEmpty == true
                                  ? aktif!.adSoyad[0]
                                  : 'K',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        title: Text(aktif?.adSoyad ?? ''),
                        subtitle: Text(aktif?.rol ?? ''),
                        trailing: TextButton(
                          onPressed: () => context.push('/sifre'),
                          child: const Text('Şifre Değiştir'),
                        ),
                      ),
                      _aramaKutusu(),
                      if (_arama.trim().isNotEmpty)
                        ..._aramaSonucu(kategoriler)
                      else if (secili != null)
                        ..._kategoriIcerigi(secili)
                      else
                        _kategoriIzgarasi(kategoriler),
                      const SizedBox(height: 8),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.logout, color: TsRenk.hata),
                        title: const Text(
                          'Çıkış Yap',
                          style: TextStyle(
                            color: TsRenk.hata,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: _cikisYap,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'BarkoPro v${UygSabitler.versiyon}',
                          style: TextStyle(
                            color: TsRenk.metinIkincil(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

// ── Yardımcı widget'lar ───────────────────────────────────────────────────────
