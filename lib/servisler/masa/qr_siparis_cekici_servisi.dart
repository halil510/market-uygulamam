// lib/servisler/masa/qr_siparis_cekici_servisi.dart
//
// Kullanıcı isteği: müşteri QR menüyü (Supabase'de barındırılan,
// internetten/mobil veriyle erişilebilen sayfa) kullanarak sipariş
// verdiğinde, bu sipariş "qr_siparisler" tablosunda BEKLEMEDE kalır.
// Bu servis, uygulama açıkken PERİYODİK OLARAK bu tabloyu kontrol
// eder, YENİ (henüz işlenmemiş) siparişleri bulur ve GÜVENLİ,
// kanıtlanmış QrMenuServisi.musteriSiparisKaydet() fonksiyonu
// üzerinden yerel masa siparişine dönüştürür — böylece sipariş
// otomatik olarak masaya düşer, personel Supabase panelini hiç
// açmak zorunda kalmaz.
import '../bulut/supabase_oturum.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../depolar/masa_deposu.dart';
import '../../uygulama/router/uygulama_router.dart' show rootNavigatorKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../saglayicilar/riverpod/masa_provider.dart';
import '../bulut/supabase_ayarlari.dart';
import 'qr_menu_servisi.dart';

class QrSiparisCekiciServisi {
  static final QrSiparisCekiciServisi _instance = QrSiparisCekiciServisi._();
  factory QrSiparisCekiciServisi() => _instance;
  QrSiparisCekiciServisi._();

  Timer? _timer;
  bool _isleniyor = false;
  // UI yenilemek için WidgetRef — masa ekranından set edilir.
  WidgetRef? _ref;

  void baslatRef(WidgetRef ref) {
    _ref = ref;
    baslat();
  }

  // 🔴🔴🔴 KRİTİK HATA DÜZELTMESİ (kullanıcı bulgusu — "html'den
  // sipariş girdim, masayı dolu göstermedi"): Bu servis TEK bir
  // PAYLAŞILAN (singleton) zamanlayıcı kullanıyor ve ana.dart'ta
  // uygulama AÇILDIĞINDA, TÜM oturum boyunca çalışması amacıyla
  // başlatılıyor. Ama MasaListeEkrani.dispose() burada durdur()'u
  // çağırıyordu — kasiyer "Masalar" ekranını AÇIP sonra BAŞKA bir
  // ekrana geçtiği (ör. Hızlı Satış'a döndüğü) AN, bu paylaşılan
  // zamanlayıcı TAMAMEN VE KALICI OLARAK duruyordu. Normal bir kasiyer
  // akışında (masalara göz atıp kasaya dönmek) bu, QR sipariş
  // çekmenin oturumun geri kalanında HİÇ ÇALIŞMAMASI anlamına
  // geliyordu — müşteri HTML'den sipariş verse bile masa asla "dolu"
  // olarak güncellenmiyordu, ta ki kasiyer TEKRAR Masalar ekranını
  // açana kadar (ve o da tekrar başka ekrana geçince yine ölüyordu).
  // Artık ekran kapanırken sadece UI-yenileme referansı (ref)
  // temizleniyor — arka plandaki paylaşılan zamanlayıcı, ana.dart'ın
  // amaçladığı gibi TÜM UYGULAMA OTURUMU boyunca çalışmaya devam ediyor.
  void ekranKapandi() {
    _ref = null;
  }

  void baslat() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _kontrolEt());
    _kontrolEt();
  }

  void durdur() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Sipariş uyarısı (kullanıcı isteği 2026-09-29): hangi ekranda olursa
  // olsun bip + küçük bildirim; birkaç sn sonra kendiliğinden kapanır.
  final Set<int> _bekleyenMasalar = {};
  Timer? _uyariKapatTimer;
  bool _uyariAcik = false;

  Future<void> _uyariGoster(Set<int> masaIdleri) async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    try { await SystemSound.play(SystemSoundType.alert); } catch (_) {}
    try { HapticFeedback.heavyImpact(); } catch (_) {}
    _bekleyenMasalar.addAll(masaIdleri);
    final adlar = await MasaDeposu().masaAdlariHaritasi();
    final liste = _bekleyenMasalar.map((id) => adlar[id] ?? 'Masa $id').toList();
    final baslik = liste.length == 1
        ? '${liste.first} için yeni sipariş var'
        : '${liste.length} masadan sipariş var';

    // Açık uyarı varsa kapatıp güncel listeyle yeniden aç.
    if (_uyariAcik) {
      rootNavigatorKey.currentState?.pop();
      _uyariAcik = false;
    }
    final ctx2 = rootNavigatorKey.currentContext;
    if (ctx2 == null || !ctx2.mounted) return;
    _uyariAcik = true;
    _uyariKapatTimer?.cancel();
    _uyariKapatTimer = Timer(const Duration(seconds: 12), () {
      if (_uyariAcik) {
        rootNavigatorKey.currentState?.pop();
      }
    });
    unawaited(showDialog(
      context: ctx2,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.notifications_active, color: Colors.orange, size: 36),
        title: Text(baslik, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17)),
        content: Text(liste.join(', '), textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Tamam')),
          FilledButton(
            onPressed: () {
              Navigator.of(d).pop();
              rootNavigatorKey.currentContext?.go('/masa');
            },
            child: const Text('Masalara Git'),
          ),
        ],
      ),
    ).whenComplete(() {
      _uyariAcik = false;
      _bekleyenMasalar.clear();
      _uyariKapatTimer?.cancel();
    }));
  }

  Future<void> _kontrolEt() async {
    if (_isleniyor) return;
    _isleniyor = true;
    try {
      final url = await SupabaseAyarlari.urlOku();
      final key = await SupabaseAyarlari.keyOku();
      if (url == null || key == null || url.isEmpty || key.isEmpty) return;

      final yanit = await http.get(
        Uri.parse('$url/rest/v1/qr_siparisler?islendi=eq.false&select=*'),
        headers: {'apikey': key, 'Authorization': 'Bearer ${SupabaseOturum.bearer(key)}'},
      ).timeout(const Duration(seconds: 10));

      if (yanit.statusCode != 200) return;
      final siparisler = jsonDecode(yanit.body) as List;
      if (siparisler.isEmpty) return;

      bool enAzBirIslendi = false;
      final yeniMasaIdleri = <int>{};

      for (final s in siparisler) {
        try {
          final sahiplenmeYaniti = await http.patch(
            Uri.parse('$url/rest/v1/qr_siparisler?id=eq.${s['id']}&islendi=eq.false'),
            headers: {
              'apikey': key, 'Authorization': 'Bearer ${SupabaseOturum.bearer(key)}',
              'Content-Type': 'application/json',
              'Prefer': 'return=representation',
            },
            body: jsonEncode({'islendi': true}),
          ).timeout(const Duration(seconds: 10));

          final sahiplenilenSatirlar = jsonDecode(sahiplenmeYaniti.body) as List;
          if (sahiplenilenSatirlar.isEmpty) continue;

          final kalemler = (s['kalemler'] as List).cast<Map<String, dynamic>>();
          await QrMenuServisi().musteriSiparisKaydet(
            masaId: (s['masa_id'] as num).toInt(),
            kalemler: kalemler,
            musteriAdi: (s['musteri_adi'] as String?) ?? '',
            musteriTel: (s['musteri_tel'] as String?) ?? '',
            not: s['not_'] as String?,
          );
          enAzBirIslendi = true;
          yeniMasaIdleri.add((s['masa_id'] as num).toInt());
          if (kDebugMode) debugPrint('QR sipariş işlendi: masa=${s['masa_id']}, ${kalemler.length} kalem');
        } catch (e) {
          if (kDebugMode) debugPrint('QR sipariş işleme hatası (id=${s['id']}): $e');
        }
      }

      if (yeniMasaIdleri.isNotEmpty) await _uyariGoster(yeniMasaIdleri);

      // En az bir sipariş işlendiyse masa listesini yenile
      if (enAzBirIslendi && _ref != null) {
        try {
          _ref!.invalidate(masaListesiProvider);
        } catch (_) { /* ağ/bulut erişilemedi — bir sonraki periyotta tekrar denenecek */ }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('QR sipariş çekme hatası: $e');
    } finally {
      _isleniyor = false;
    }
  }
}

