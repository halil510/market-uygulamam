// lib/ekranlar/dashboard/widgets/sync_mini_buton.dart
// dashboard_ekrani.dart'tan taşındı (god-class sertleştirmesi,
// 2026-09-22) — davranış birebir korundu, sadece bağımsız bir dosyaya
// ve genel (public) bir sınıf adına taşındı ki normal import ile
// kullanılabilsin.
//
// Kullanıcı isteği: "buluta gönderme ve alma ana menüde ikon olsa,
// tarih/saatin yan tarafına." Tek dokunuşla delta sync (sadece
// değişenler) yapar — uzun sürmez. Long-press ile tam sync seçeneği.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../servisler/supabase_sync_servisi.dart';
import '../../../veri/database/veritabani.dart';
import '../../../widgetlar/ortak/app_widgetlar.dart';

class SyncMiniButon extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const SyncMiniButon({super.key, required this.ref});

  @override
  ConsumerState<SyncMiniButon> createState() => _SyncMiniButonState();
}

class _SyncMiniButonState extends ConsumerState<SyncMiniButon>
    with SingleTickerProviderStateMixin {
  bool _calisiyor = false;
  bool _basarili = false;
  bool _hata = false;
  late AnimationController _dondurmeCtrl;

  @override
  void initState() {
    super.initState();
    _dondurmeCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat();
    _dondurmeCtrl.stop();
  }

  @override
  void dispose() {
    _dondurmeCtrl.dispose();
    super.dispose();
  }

  Future<void> _hizliSync() async {
    if (_calisiyor) return;
    setState(() {
      _calisiyor = true;
      _basarili = false;
      _hata = false;
    });
    _dondurmeCtrl.repeat();
    try {
      final db = Veritabani();
      // Gönder (sadece değişenler)
      final gonderSonuc = await SupabaseSyncServisi.bulutaGonder(
        veriGetir: (t, f) => db.supaTumKayitlariGetirTemiz(t, f),
        sadeceDegisenler: true,
      );
      // Al (sadece değişenler)
      final alSonuc = await SupabaseSyncServisi.buluttanAl(
        kayitEkle: (t, k) => db.supaKayitlariEkle(t, k),
        kayitGuncelle: (t, k) => db.supaKayitlariGuncelle(t, k),
        sadeceDegisenler: true,
      );
      final hatalar = [...gonderSonuc.hatalar, ...alSonuc.hatalar];
      if (mounted) {
        setState(() {
          _calisiyor = false;
          _basarili = hatalar.isEmpty;
          _hata = hatalar.isNotEmpty;
        });
        _dondurmeCtrl.stop();
        // 3 saniye sonra normal ikona dön
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted)
            setState(() {
              _basarili = false;
              _hata = false;
            });
        });
        if (hatalar.isNotEmpty && mounted) {
          hataMesaji(context,
              'Sync: ${hatalar.length} hata — Ayarlar\'dan detay alın');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _calisiyor = false;
          _hata = true;
        });
        _dondurmeCtrl.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ikon = _basarili
        ? Icons.check_circle_outline
        : _hata
            ? Icons.error_outline
            : Icons.sync;
    final renk = _basarili
        ? Colors.greenAccent
        : _hata
            ? Colors.redAccent
            : Colors.white70;

    return GestureDetector(
      onTap: _hizliSync,
      onLongPress: () => context.push('/ayarlar/bulut-sync'),
      // Kullanıcı geri bildirimi: "ikon tarih/saate çok yakın,
      // basılmıyor." behavior: opaque + padding ile DOKUNMA ALANI
      // ikonun kendisinden çok daha geniş; ikon 16→22'ye büyütüldü
      // ve hafif bir arka planla ayrı bir buton gibi görünüyor.
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: 'Hızlı Sync (sadece değişenler)\nUzun bas → Tam Sync ekranı',
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(28),
            borderRadius: BorderRadius.circular(12),
          ),
          child: RotationTransition(
            turns: _calisiyor ? _dondurmeCtrl : const AlwaysStoppedAnimation(0),
            child: Icon(ikon, size: 22, color: renk),
          ),
        ),
      ),
    );
  }
}
