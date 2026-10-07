// lib/servisler/fatura/fatura_gorsel_servisi.dart
//
// Faturaya basılan logo ve imza/kaşe görselinin seçilip uygulama klasörüne
// kopyalanması — fatura_ayar_ekrani.dart'tan ayrıldı (2026-10-07 refactor).
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class FaturaGorselServisi {
  FaturaGorselServisi._();

  /// Galeriden görsel seçtirir; vazgeçilirse null.
  static Future<String?> galeridenSec({required bool logoMu}) async {
    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: logoMu ? 600 : 800,
      maxHeight: logoMu ? 600 : 400,
      imageQuality: 90,
    );
    return xFile?.path;
  }

  /// Seçilen görseli `fatura_gorseller/logo.png` veya `imza.png` olarak
  /// kopyalar (öncekinin üzerine yazar) ve kalıcı yolu döndürür.
  static Future<String> kaydet(String kaynakYol, {required bool logoMu}) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/fatura_gorseller');
    if (!await dir.exists()) await dir.create(recursive: true);
    final hedef = File('${dir.path}/${logoMu ? 'logo.png' : 'imza.png'}');
    await File(kaynakYol).copy(hedef.path);
    return hedef.path;
  }
}
