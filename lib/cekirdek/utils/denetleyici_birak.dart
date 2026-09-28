// lib/cekirdek/utils/denetleyici_birak.dart
import 'package:flutter/foundation.dart';

/// Bir dialog/alt sayfa için oluşturulan controller'ları, dialog'un KAPANMA
/// ANİMASYONU bittikten sonra bırakır.
///
/// NEDEN (uygulama robotu bulgusu): `await showDialog(...)` Navigator.pop
/// çağrıldığı anda döner ama dialog birkaç yüz ms daha ekranda kapanarak
/// çizilir; içindeki TextField controller'ı o arada hemen dispose edilirse
/// "TextEditingController was used after being disposed" hatası oluşur.
void dialogSonrasiBirak(List<ChangeNotifier> denetleyiciler) {
  Future<void>.delayed(const Duration(milliseconds: 600), () {
    for (final d in denetleyiciler) {
      d.dispose();
    }
  });
}
