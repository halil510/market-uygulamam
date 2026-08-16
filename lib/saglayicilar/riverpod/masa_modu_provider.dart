// lib/saglayicilar/riverpod/masa_modu_provider.dart
// Tek sorumluluk: "Masa Modu" (Restoran/Cafe modülünün dashboard'da
// görünüp görünmeyeceği) ayarını SharedPreferences'tan okur/yazar.
// Market-only şubelerde Masalar/Mutfak menüsünü gizlemek için kullanılır.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const masaModuAnahtari = 'masa_modu_aktif';

class MasaModuNotifier extends StateNotifier<bool> {
  // Varsayılan: açık (true) — restoran/cafe modülü zaten kurulu olduğundan
  // önceden eklenmiş masaları olan kullanıcılar için sürpriz kaybolma olmasın.
  MasaModuNotifier() : super(true) {
    _yukle();
  }

  Future<void> _yukle() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(masaModuAnahtari) ?? true;
  }

  Future<void> degistir(bool aktif) async {
    state = aktif;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(masaModuAnahtari, aktif);
  }
}

final masaModuProvider = StateNotifierProvider<MasaModuNotifier, bool>(
    (ref) => MasaModuNotifier());
