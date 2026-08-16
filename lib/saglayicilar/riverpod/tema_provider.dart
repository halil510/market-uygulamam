// lib/saglayicilar/riverpod/tema_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'tema_provider.g.dart';

@riverpod
class Tema extends _$Tema {
  static const _key = 'tema_adi';

  @override
  String build() {
    Future.microtask(_yukle);
    return 'light';
  }

  Future<void> _yukle() async {
    final p = await SharedPreferences.getInstance();
    final k = p.getString(_key) ?? 'light';
    if (state != k) state = k;
  }

  Future<void> degistir(String yeniTema) async {
    state = yeniTema;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, yeniTema);
  }

  Future<void> karanlikToggle() => degistir(state == 'dark' ? 'light' : 'dark');
}
