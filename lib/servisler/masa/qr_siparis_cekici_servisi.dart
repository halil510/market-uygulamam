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
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  Future<void> _kontrolEt() async {
    if (_isleniyor) return;
    _isleniyor = true;
    try {
      final url = await SupabaseAyarlari.urlOku();
      final key = await SupabaseAyarlari.keyOku();
      if (url == null || key == null || url.isEmpty || key.isEmpty) return;

      final yanit = await http.get(
        Uri.parse('$url/rest/v1/qr_siparisler?islendi=eq.false&select=*'),
        headers: {'apikey': key, 'Authorization': 'Bearer $key'},
      ).timeout(const Duration(seconds: 10));

      if (yanit.statusCode != 200) return;
      final siparisler = jsonDecode(yanit.body) as List;
      if (siparisler.isEmpty) return;

      bool enAzBirIslendi = false;

      for (final s in siparisler) {
        try {
          final sahiplenmeYaniti = await http.patch(
            Uri.parse('$url/rest/v1/qr_siparisler?id=eq.${s['id']}&islendi=eq.false'),
            headers: {
              'apikey': key, 'Authorization': 'Bearer $key',
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
          if (kDebugMode) debugPrint('QR sipariş işlendi: masa=${s['masa_id']}, ${kalemler.length} kalem');
        } catch (e) {
          if (kDebugMode) debugPrint('QR sipariş işleme hatası (id=${s['id']}): $e');
        }
      }

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

