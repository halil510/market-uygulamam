// lib/servisler/etiket_ag_gonderici.dart
//
// Etiket yazıcısına (TSPL) ağ üzerinden doğrudan gönderim — fiş yazıcısı bağlantısından (YazdirmaServisi) BAĞIMSIZ.
// Adres: ağdaki etiket yazıcısı ya da yazıcının USB ile takılı olduğu bilgisayar ("Yazıcıyı ağa aç", port 9100).
// Ürün Güncelleme'deki etiket_yazicisi.dart'ın ağ bölümüyle aynı.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class EtiketAgHatasi implements Exception {
  final String mesaj;
  EtiketAgHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// "192.168.1.50" ya da "192.168.1.50:9100" → (ip, port). Geçersizse null.
(String, int)? etiketAdresCoz(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?::(\d{1,5}))?$').firstMatch(t);
  if (m == null) return null;
  for (var i = 1; i <= 4; i++) {
    if (int.parse(m.group(i)!) > 255) return null;
  }
  final port = m.group(5) == null ? 9100 : int.parse(m.group(5)!);
  if (port < 1 || port > 65535) return null;
  return ('${m.group(1)}.${m.group(2)}.${m.group(3)}.${m.group(4)}', port);
}

/// [veri]yi [adres]e gönderir ve bağlantıyı kapatır.
Future<void> etiketAgaGonder(String adres, Uint8List veri) async {
  final a = etiketAdresCoz(adres);
  if (a == null) throw EtiketAgHatasi('Etiket yazıcısının adresi geçersiz (ör. 192.168.1.50 ya da 192.168.1.50:9100)');
  Socket? s;
  try {
    s = await Socket.connect(a.$1, a.$2, timeout: const Duration(seconds: 6));
    s.add(veri);
    await s.flush().timeout(const Duration(seconds: 60));
    await s.close().timeout(const Duration(seconds: 10));
  } on SocketException catch (e) {
    throw EtiketAgHatasi('${a.$1}:${a.$2} adresine bağlanılamadı (${e.osError?.message ?? e.message}). '
        'Aynı ağda mısınız, IP doğru mu? Yazıcı bir bilgisayara USB ile takılıysa o bilgisayarda '
        '"Yazıcıyı ağa aç" açık olmalı (market: Ayarlar > Yazıcılar > Windows Yazıcı; ya da Ürün Güncelleme > Ayarlar).');
  } on TimeoutException {
    throw EtiketAgHatasi('${a.$1}:${a.$2} yanıt vermedi');
  } finally {
    s?.destroy();
  }
}
