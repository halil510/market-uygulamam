// lib/cekirdek/utils/dosya_paylasim.dart
//
// Dışa aktarılan dosyaları (Excel/PDF/CSV/yedek) platforma uygun şekilde
// kullanıcıya verir: mobilde paylaşım menüsü, Windows'ta dosya
// Belgeler\BarkoPro klasörüne kopyalanıp varsayılan programda (Excel/PDF
// okuyucu) açılır; açılamayan türlerde (zip/db/zpl) klasör gösterilir.
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class DosyaPaylasim {
  static const _acilabilir = {'.xlsx', '.xls', '.pdf', '.csv', '.txt'};

  /// [SharePlus.instance.share] yerine kullanılır.
  static Future<void> paylas(ShareParams params) async {
    if (!Platform.isWindows) {
      await SharePlus.instance.share(params);
      return;
    }
    final dosyalar = params.files ?? const <XFile>[];
    if (dosyalar.isEmpty) return;
    final hedef = await _belgelereKopyala(dosyalar.first.path);
    if (_acilabilir.contains(p.extension(hedef).toLowerCase())) {
      await Process.run('cmd', ['/c', 'start', '', hedef]);
    } else {
      await Process.run('explorer.exe', ['/select,$hedef']);
    }
  }

  /// [Printing.sharePdf] yerine: PDF'i kaydedip Windows'ta açar.
  static Future<void> pdfPaylas(Uint8List bytes, String dosyaAdi) async {
    if (!Platform.isWindows) {
      await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: dosyaAdi)],
          fileNameOverrides: [dosyaAdi]));
      return;
    }
    final klasor = _klasor();
    await klasor.create(recursive: true);
    final f = File(p.join(klasor.path, dosyaAdi));
    await f.writeAsBytes(bytes, flush: true);
    await Process.run('cmd', ['/c', 'start', '', f.path]);
  }

  static Directory _klasor() {
    final profil = Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
    return Directory(p.join(profil, 'Documents', 'BarkoPro'));
  }

  static Future<String> _belgelereKopyala(String kaynak) async {
    final klasor = _klasor();
    await klasor.create(recursive: true);
    final hedef = p.join(klasor.path, p.basename(kaynak));
    if (p.equals(kaynak, hedef)) return hedef;
    await File(kaynak).copy(hedef);
    return hedef;
  }
}
