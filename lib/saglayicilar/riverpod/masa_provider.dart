// lib/saglayicilar/riverpod/masa_provider.dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../depolar/masa_deposu.dart';
import '../../modeller/masa_model.dart';
import '../../modeller/masa_siparis_model.dart';
import '../../servisler/supabase_sync_servisi.dart';
import '../../veri/database/veritabani.dart';

final masaDeposuProvider = Provider<MasaDeposu>((ref) => MasaDeposu());

// ═══════════════════════════════════════════════════════════════════════
// 🔴 Derin analizde bulundu — "masa dolu olmasına rağmen boş görünüyor":
// Masa listesi, masa sipariş detayı ve mutfak/bar ekranlarının HİÇBİRİ
// buluttan otomatik veri ÇEKMİYORDU. Alttaki timer'lar (5-6 saniyede
// bir) sadece YEREL veritabanını yeniden okuyordu — başka bir cihazda
// (garsonun telefonu, QR sipariş, ikinci kasa) açılan/değişen bir masa,
// SADECE elle "Ayarlar > Buluttan Al" basılırsa bu cihaza geliyordu.
// Profesyonel restoran POS sistemlerinde masa durumu ya WebSocket ile
// anlık, ya da (yerel ağ değil, bulut REST API üzerinden senkron olan
// sistemlerde yaygın olduğu gibi) birkaç saniyede bir otomatik çekme
// ile güncel tutulur. Burada, mevcut mimariye (WebSocket altyapısı yok)
// en uygun ve en düşük riskli çözüm: delta (sadece değişen kayıt) bulut
// çekme, üç ekranın da zaten var olan periyodik yenileme döngüsüne
// eklendi. Birden fazla ekran aynı anda açıksa gereksiz TEKRARLANAN tam
// çekme olmasın diye paylaşımlı bir "en son ne zaman çekildi" kilidi var.
// ═══════════════════════════════════════════════════════════════════════
DateTime? _sonOtoCekme;
bool _otoCekmeCalisiyor = false;

/// Masa/mutfak ekranlarının paylaştığı, kilitli, delta bulut çekme.
/// En az [Duration(seconds: 12)] arayla çalışır — aynı anda birden
/// fazla ekran açık olsa bile en fazla bir tanesi gerçek ağ isteği atar.
Future<void> otoMasaBulutCek() async {
  if (_otoCekmeCalisiyor) return;
  final simdi = DateTime.now();
  if (_sonOtoCekme != null && simdi.difference(_sonOtoCekme!) < const Duration(seconds: 12)) {
    return;
  }
  _otoCekmeCalisiyor = true;
  try {
    final db = Veritabani();
    await SupabaseSyncServisi.buluttanAl(
      kayitEkle: (t, k) => db.supaKayitlariEkle(t, k),
      kayitGuncelle: (t, k) => db.supaKayitlariGuncelle(t, k),
      sadeceDegisenler: true,
    );
    _sonOtoCekme = DateTime.now();
  } catch (_) {
    // Sessizce yut — bu arka plan otomatik çekmesi, kullanıcıya hata
    // göstermez (elle "Buluttan Al" zaten kendi hata mesajını veriyor).
    // Bir sonraki periyodik denemede tekrar çalışılır.
  } finally {
    _otoCekmeCalisiyor = false;
  }
}

class MasaListesiNotifier extends StateNotifier<AsyncValue<List<MasaModel>>> {
  final MasaDeposu _depo;
  Timer? _otoYenilemeTimer;

  MasaListesiNotifier(this._depo) : super(const AsyncValue.loading()) {
    yukle();
    // Masa listesi (kat planı) daha önce hiç otomatik yenilenmiyordu —
    // sadece ekrana ilk girişte bir kez yükleniyordu.
    _otoYenilemeTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await otoMasaBulutCek();
      await yukle();
    });
  }

  @override
  void dispose() {
    _otoYenilemeTimer?.cancel();
    super.dispose();
  }

  Future<void> yukle() async {
    try {
      final masalar = await _depo.masalariGetir();
      state = AsyncValue.data(masalar);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final masaListesiProvider =
    StateNotifierProvider<MasaListesiNotifier, AsyncValue<List<MasaModel>>>(
        (ref) => MasaListesiNotifier(ref.watch(masaDeposuProvider)));

class MasaSiparisNotifier extends StateNotifier<AsyncValue<MasaSiparisModel?>> {
  final MasaDeposu _depo;
  final int masaId;
  Timer? _autoRefreshTimer;
  
  MasaSiparisNotifier(this._depo, this.masaId) : super(const AsyncValue.loading()) {
    yukle();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await otoMasaBulutCek();
      await yukle();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> yukle() async {
    try {
      final siparis = await _depo.acikSiparisGetir(masaId);
      state = AsyncValue.data(siparis);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> urunEkle({
    required int urunId, required String urunAdi,
    required double birimFiyat, required double kdvOran,
    double miktar = 1, String? not_,
  }) async {
    final siparis = await _depo.siparisAcVeyaGetir(masaId);
    await _depo.kalemEkle(siparis.id!,
        urunId: urunId, urunAdi: urunAdi, birimFiyat: birimFiyat,
        kdvOran: kdvOran, miktar: miktar, not_: not_);
    await yukle();
  }

  Future<void> miktarGuncelle(int kalemId, double miktar) async {
    await _depo.kalemMiktarGuncelle(kalemId, miktar);
    await yukle();
  }

  Future<void> kalemSil(int kalemId) async {
    await _depo.kalemSil(kalemId);
    await yukle();
  }

  Future<void> kalemDurumGuncelle(int kalemId, String durum) async {
    await _depo.kalemDurumGuncelle(kalemId, durum);
    await yukle();
  }

  Future<void> kalemNotGuncelle(int kalemId, String? not_) async {
    await _depo.kalemNotGuncelle(kalemId, not_);
    await yukle();
  }

  Future<void> musteriBagla(int? cariId, String? cariAdi) async {
    final s = state.valueOrNull;
    if (s?.id == null) return;
    await _depo.musteriBagla(s!.id!, cariId, cariAdi);
    await yukle();
  }
}

final masaSiparisProvider = StateNotifierProvider.family<
    MasaSiparisNotifier, AsyncValue<MasaSiparisModel?>, int>(
  (ref, masaId) => MasaSiparisNotifier(ref.watch(masaDeposuProvider), masaId),
);

class MutfakDurum {
  final List<MasaSiparisModel> siparisler;
  final Map<int, String> masaAdlari;
  const MutfakDurum({this.siparisler = const [], this.masaAdlari = const {}});
}

class MutfakNotifier extends StateNotifier<AsyncValue<MutfakDurum>> {
  final MasaDeposu _depo;
  Timer? _timer;
  bool _ilkYukleme = true;
  Set<int> _bilinenBeklemedeKalemler = {};

  MutfakNotifier(this._depo) : super(const AsyncValue.loading()) {
    yukle();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) async {
      await otoMasaBulutCek();
      await yukle();
    });
  }

  Future<void> yukle() async {
    try {
      final siparisler = await _depo.tumAcikSiparisler();
      final adlar = await _depo.masaAdlariHaritasi();

      final guncelBeklemede = siparisler
          .expand((s) => s.kalemler)
          .where((k) => k.durum == 'beklemede')
          .map((k) => k.id!)
          .toSet();

      if (!_ilkYukleme) {
        final yeniler = guncelBeklemede.difference(_bilinenBeklemedeKalemler);
        if (yeniler.isNotEmpty) _yeniSiparisUyarisi();
      }
      _bilinenBeklemedeKalemler = guncelBeklemede;
      _ilkYukleme = false;

      state = AsyncValue.data(MutfakDurum(siparisler: siparisler, masaAdlari: adlar));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _yeniSiparisUyarisi() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 400), () => HapticFeedback.heavyImpact());
  }

  Future<void> kalemDurumGuncelle(int kalemId, String durum) async {
    await _depo.kalemDurumGuncelle(kalemId, durum);
    await yukle();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final mutfakProvider = StateNotifierProvider<MutfakNotifier, AsyncValue<MutfakDurum>>(
    (ref) => MutfakNotifier(ref.watch(masaDeposuProvider)));