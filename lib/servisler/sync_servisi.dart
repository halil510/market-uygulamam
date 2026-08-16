// lib/servisler/sync_servisi.dart
// Mobil↔Mobil ve Mobil↔PC WiFi veri aktarım servisi
// Özellikler: HTTP sunucu, DB aktarım, seçici tablo sync, progress callback
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../veri/database/veritabani.dart';

class SyncServisi {
  static final SyncServisi _i = SyncServisi._();
  factory SyncServisi() => _i;
  SyncServisi._();

  HttpServer? _server;
  bool _sunucuAktif = false;
  String? _sunucuIp;
  static const int _port = 8765;

  bool get sunucuAktif => _sunucuAktif;
  String? get sunucuIp => _sunucuIp;
  int get port => _port;
  String get sunucuAdres =>
      _sunucuIp != null ? 'http://$_sunucuIp:$_port' : '';

  // ── IP Tespiti ────────────────────────────────────────────────────────
  Future<String?> lokalIpAl() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      // WiFi ağlarını öncelik sırasıyla dene
      const oncelikli = ['192.168', '10.', '172.'];
      for (final prefix in oncelikli) {
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.address.startsWith(prefix)) {
              return addr.address;
            }
          }
        }
      }
      // Son çare: loopback olmayan herhangi bir IP
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) { /* ignore */ }
    return null;
  }

  // Tüm IP adreslerini döndür (kullanıcıya seçim yaptır)
  Future<List<String>> tumIpleriAl() async {
    final ips = <String>[];
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) ips.add(addr.address);
        }
      }
    } catch (e) { /* ignore */ }
    return ips;
  }

  // ── HTTP Sunucu ───────────────────────────────────────────────────────
  Future<bool> sunucuBaslat() async {
    if (_sunucuAktif) return true;
    try {
      _sunucuIp = await lokalIpAl();
      if (_sunucuIp == null) return false;

      _server = await HttpServer.bind(
          InternetAddress.anyIPv4, _port, shared: true);
      _sunucuAktif = true;
      if (kDebugMode) debugPrint('SyncServer: http://$_sunucuIp:$_port');
      _server!.listen(_istekIsle);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Sunucu hata: $e');
      _sunucuAktif = false;
      return false;
    }
  }

  Future<void> sunucuKapat() async {
    await _server?.close(force: true);
    _server = null;
    _sunucuAktif = false;
  }

  Future<void> _istekIsle(HttpRequest req) async {
    // CORS
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    req.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    req.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method == 'OPTIONS') {
      req.response.statusCode = 200;
      await req.response.close();
      return;
    }

    try {
      final yol = req.uri.path;
      final metod = req.method;

      // ── Ping ──
      if (metod == 'GET' && yol == '/api/ping') {
        _jsonYanit(req, {
          'ok': true,
          'app': 'MarketPlus',
          'version': '3.0',
          'cihaz': Platform.isAndroid ? 'Android' : Platform.isIOS ? 'iOS' : 'PC',
          'zaman': DateTime.now().toIso8601String(),
        });
      }

      // ── Tablo listesi ──
      else if (metod == 'GET' && yol == '/api/tablolar') {
        _jsonYanit(req, {'tablolar': _transferTablolari()});
      }

      // ── Seçili tablo dışa aktar ──
      else if (metod == 'GET' && yol.startsWith('/api/tablo/')) {
        final tabloAdi = yol.split('/').last;
        if (!_transferTablolari().contains(tabloAdi)) {
          req.response.statusCode = 400;
          _jsonYanit(req, {'hata': 'Geçersiz tablo: $tabloAdi'});
          return;
        }
        final data = await _tabloVeriAl(tabloAdi);
        _jsonYanit(req, {'tablo': tabloAdi, 'veri': data, 'sayi': data.length});
      }

      // ── Tüm veri JSON ──
      else if (metod == 'GET' && yol == '/api/export') {
        req.response.headers.set('Content-Type', 'application/json; charset=utf-8');
        final data = await _tumVeriAl();
        req.response.write(jsonEncode(data));
        await req.response.close();
      }

      // ── Seçili tablolar import ──
      else if (metod == 'POST' && yol == '/api/import') {
        final body = await utf8.decoder.bind(req).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final sonuc = await _veriIcerAktar(data);
        _jsonYanit(req, sonuc);
      }

      // ── DB dosyası indir ──
      else if (metod == 'GET' && yol == '/api/db') {
        final db = await Veritabani().db;
        final dbDosya = File(db.path);
        if (await dbDosya.exists()) {
          req.response.headers.contentType =
              ContentType('application', 'octet-stream');
          req.response.headers.add(
              'Content-Disposition', 'attachment; filename="market.db"');
          req.response.headers.add(
              'Content-Length', (await dbDosya.length()).toString());
          await req.response.addStream(dbDosya.openRead());
        } else {
          req.response.statusCode = 404;
          req.response.write('DB bulunamadi');
        }
        await req.response.close();
      }

      // ── DB dosyası yükle (POST binary) ──
      else if (metod == 'POST' && yol == '/api/db') {
        final bytes = await req
            .fold<List<int>>([], (a, b) => a..addAll(b));
        final db = await Veritabani().db;
        final tempYol = '${db.path}.transfer_temp';
        await File(tempYol).writeAsBytes(bytes);
        // Doğrulama - sqlite formatı
        final magic = bytes.length > 16
            ? String.fromCharCodes(bytes.take(6))
            : '';
        if (!magic.startsWith('SQLite')) {
          await File(tempYol).delete();
          req.response.statusCode = 400;
          _jsonYanit(req, {'hata': 'Geçerli SQLite dosyası değil'});
          return;
        }
        // ÖNCEDEN BURADA CİDDİ BİR GÜVENLİK AÇIĞI VARDI: mevcut
        // veritabanı hiçbir güvenlik yedeği alınmadan doğrudan üzerine
        // yazılıyordu — yanlış bir .db dosyası (kazayla eski bir yedek,
        // başka bir cihazın verisi vb.) yüklenirse, kullanıcının MEVCUT
        // verisi GERİ DÖNÜŞSÜZ kaybolurdu. Bu, YedeklemeServisi'nde
        // (geri yükleme) daha önce bulunup düzeltilen AYNI sınıf hataydı
        // — burada da aynı güvenlik önlemi uygulanıyor: önce mevcut DB'nin
        // bir kopyası alınıyor, yazma başarısız olursa oradan geri dönülüyor.
        final guvenlikYedegi = '${db.path}.wifi_yukleme_oncesi_${DateTime.now().millisecondsSinceEpoch}.bak';
        if (await File(db.path).exists()) {
          await File(db.path).copy(guvenlikYedegi);
        }
        try {
          await Veritabani().kapat();
          await File(tempYol).copy(db.path);
          await File(tempYol).delete();
          _jsonYanit(req, {'ok': true, 'mesaj': 'DB yüklendi, uygulama yeniden başlatılmalı'});
        } catch (e) {
          // Yazma başarısız oldu — güvenlik yedeğinden geri al
          if (await File(guvenlikYedegi).exists()) {
            await File(guvenlikYedegi).copy(db.path);
          }
          req.response.statusCode = 500;
          _jsonYanit(req, {'hata': 'DB yükleme başarısız, önceki veri geri yüklendi: $e'});
        }
      }

      // ── Durum/istatistik ──
      else if (metod == 'GET' && yol == '/api/durum') {
        final db = await Veritabani().db;
        final urunSayisi = Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM urunler WHERE is_deleted=0')) ??
            0;
        final cariSayisi = Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM cari WHERE is_deleted=0')) ??
            0;
        final satisSayisi = Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM satislar WHERE iptal=0')) ??
            0;
        _jsonYanit(req, {
          'urun_sayisi': urunSayisi,
          'cari_sayisi': cariSayisi,
          'satis_sayisi': satisSayisi,
          'db_boyutu': await File(db.path).length(),
          'zaman': DateTime.now().toIso8601String(),
        });
      }

      // ── Web Arayüzü (PC tarayıcısı için) ──
      else if (metod == 'GET' && (yol == '/' || yol == '/index.html')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write(_webArayuzu());
        await req.response.close();
      }

      else {
        req.response.statusCode = 404;
        _jsonYanit(req, {'hata': 'Endpoint bulunamadi: $yol'});
      }
    } catch (e) {
      req.response.statusCode = 500;
      _jsonYanit(req, {'hata': e.toString()});
    }
  }

  void _jsonYanit(HttpRequest req, Map<String, dynamic> data) {
    req.response.headers.set('Content-Type', 'application/json; charset=utf-8');
    req.response.write(jsonEncode(data));
    req.response.close();
  }

  List<String> _transferTablolari() => [
        'urunler', 'cari', 'cari_hareket', 'cari_adres',
        'satislar', 'satis_kalem', 'stok_hareket', 'lot_seri',
        'giderler', 'kasa_hareketleri', 'kategoriler',
        'promosyonlar', 'vardiyalar', 'faturalar', 'fatura_detaylari',
        'iade', 'iade_kalem', 'markalar', 'birimler',
        'tedarikci_siparisler', 'tedarikci_siparis_kalem',
      ];

  Future<List<Map<String, dynamic>>> _tabloVeriAl(String tablo) async {
    final db = await Veritabani().db;
    // is_deleted filtresi olan tablolar
    final filtreli = {'urunler', 'cari', 'satislar', 'faturalar'};
    final where = filtreli.contains(tablo) ? 'is_deleted = 0' : null;
    try {
      return await db.query(tablo, where: where);
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> _tumVeriAl() async {
    final Map<String, dynamic> data = {
      'meta': {
        'zaman': DateTime.now().toIso8601String(),
        'versiyon': 3,
        'kaynak': Platform.isAndroid ? 'Android' : 'PC',
      },
    };
    for (final tablo in _transferTablolari()) {
      data[tablo] = await _tabloVeriAl(tablo);
    }
    return data;
  }

  Future<Map<String, dynamic>> _veriIcerAktar(
      Map<String, dynamic> data, {
      List<String>? sadeceTablolar,
      }) async {
    final db = await Veritabani().db;
    int eklenen = 0;
    int guncellenen = 0;
    final hatalar = <String>[];

    final islenecek = sadeceTablolar ?? _transferTablolari();

    // Tablo sırası önemli (FK kısıtları)
    final sira = [
      'kategoriler', 'markalar', 'birimler',
      'urunler', 'cari', 'cari_adres',
      'satislar', 'satis_kalem', 'cari_hareket',
      'stok_hareket', 'lot_seri', 'giderler', 'kasa_hareketleri',
      'faturalar', 'fatura_detaylari', 'iade', 'iade_kalem',
      'promosyonlar', 'vardiyalar',
      'tedarikci_siparisler', 'tedarikci_siparis_kalem',
    ];

    final islemSirasi = sira.where((t) => islenecek.contains(t)).toList()
      ..addAll(islenecek.where((t) => !sira.contains(t)));

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      for (final tablo in islemSirasi) {
        if (!data.containsKey(tablo)) continue;
        final rows = (data[tablo] as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (final row in rows) {
          try {
            final temizRow = Map<String, dynamic>.from(row)
              ..remove('id'); // ID çakışmasını önle
            final existing = await _mevcutKayitBul(db, tablo, row);
            if (existing != null) {
              // LAST WRITE WINS: last_updated karşılaştır
              final yerelKayit = await db.query(tablo,
                  where: 'id = ?', whereArgs: [existing], limit: 1);
              final yerelZaman = yerelKayit.isNotEmpty
                  ? (yerelKayit.first['last_updated'] as String? ?? '')
                  : '';
              final gelenZaman = row['last_updated'] as String? ?? '';

              // Satışlar HİÇBİR ZAMAN üzerine yazılmaz - sadece ekle
              if (tablo == 'satislar' || tablo == 'satis_kalem' ||
                  tablo == 'cari_hareket' || tablo == 'stok_hareket' ||
                  tablo == 'kasa_hareketleri' || tablo == 'giderler') {
                // Hareket tabloları: zaten varsa atla
                continue;
              }

              // Diğer tablolar: daha yeni olan kazanır
              if (gelenZaman.compareTo(yerelZaman) > 0) {
                // Gelen daha yeni → güncelle
                await db.update(tablo, temizRow,
                    where: 'id = ?', whereArgs: [existing]);
                guncellenen++;
              }
              // Yerel daha yeni veya eşit → dokunma
            } else {
              // Yeni kayıt → ekle
              // 🔴 DÜZELTME: Burada 'row' (id dahil) kullanılıyordu —
              // ama 'temizRow' zaten id'siz hazırlanmıştı ve SADECE
              // güncelleme yolunda kullanılıyordu. İki cihazın id
              // sıraları TAMAMEN BAĞIMSIZ olduğu için, gönderenin
              // yerel id'si burada yerel bir kayıtla ÇAKIŞIRSA (farklı
              // bir kayıt olsa bile), ConflictAlgorithm.ignore bu yeni
              // kaydı SESSİZCE YOK SAYARDI — veri kaybı. Artık id
              // her zaman temizleniyor, SQLite kendi yeni yerel id'sini
              // otomatik üretiyor.
              await db.insert(tablo, temizRow,
                  conflictAlgorithm: ConflictAlgorithm.ignore);
              eklenen++;
            }
          } catch (e) {
            hatalar.add('$tablo: $e');
          }
        }
      }
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    return {
      'basarili': eklenen + guncellenen,
      'eklenen': eklenen,
      'guncellenen': guncellenen,
      'hata_sayisi': hatalar.length,
      'hatalar': hatalar.take(10).toList(),
    };
  }

  Future<int?> _mevcutKayitBul(
      Database db, String tablo, Map<String, dynamic> row) async {
    // global_id ile bul
    if (row.containsKey('global_id') && row['global_id'] != null) {
      final r = await db.query(tablo,
          where: 'global_id = ?', whereArgs: [row['global_id']], limit: 1);
      if (r.isNotEmpty) return r.first['id'] as int?;
    }
    // Tablo'ya göre unique key
    try {
      switch (tablo) {
        case 'urunler':
          if (row['global_id'] != null) {
            final r = await db.query(tablo,
                where: 'global_id = ?', whereArgs: [row['global_id']], limit: 1);
            if (r.isNotEmpty) return r.first['id'] as int?;
          }
          if (row['barkod'] != null) {
            final r = await db.query(tablo,
                where: 'barkod = ?', whereArgs: [row['barkod']], limit: 1);
            if (r.isNotEmpty) return r.first['id'] as int?;
          }
        case 'cari':
          if (row['global_id'] != null) {
            final r = await db.query(tablo,
                where: 'global_id = ?', whereArgs: [row['global_id']], limit: 1);
            if (r.isNotEmpty) return r.first['id'] as int?;
          }
          if (row['cari_kodu'] != null) {
            final r = await db.query(tablo,
                where: 'cari_kodu = ?', whereArgs: [row['cari_kodu']], limit: 1);
            if (r.isNotEmpty) return r.first['id'] as int?;
          }
        case 'satislar':
          // global_id ile eşleştir (çok cihaz sync güvenli)
          if (row['global_id'] != null) {
            final r = await db.query(tablo,
                where: 'global_id = ?', whereArgs: [row['global_id']], limit: 1);
            if (r.isNotEmpty) return r.first['id'] as int?;
          }
          // global_id yoksa fis_no ile dene
          if (row['fis_no'] != null) {
            final r = await db.query(tablo,
                where: 'fis_no = ?', whereArgs: [row['fis_no']], limit: 1);
            if (r.isNotEmpty) return r.first['id'] as int?;
          }
        case 'faturalar':
          if (row['global_id'] != null) {
            final r = await db.query(tablo,
                where: 'global_id = ?', whereArgs: [row['global_id']], limit: 1);
            if (r.isNotEmpty) return r.first['id'] as int?;
          }
          if (row['fatura_no'] != null) {
            final r = await db.query(tablo,
                where: 'fatura_no = ?', whereArgs: [row['fatura_no']], limit: 1);
            if (r.isNotEmpty) return r.first['id'] as int?;
          }
      }
    } catch (e) { /* ignore */ }
    return null;
  }

  // ── İstemci: Ping ─────────────────────────────────────────────────────
  Future<SyncPingResult> sunucuyaPingAt(String adres) async {
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final req =
          await client.getUrl(Uri.parse('${adres.trimRight()}/api/ping'));
      final res = await req.close();
      final body = await utf8.decoder.bind(res).join();
      client.close();
      sw.stop();
      if (res.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        return SyncPingResult(
          basarili: true,
          gecikmeMs: sw.elapsedMilliseconds,
          cihaz: data['cihaz']?.toString(),
          versiyon: data['version']?.toString(),
        );
      }
      return SyncPingResult(basarili: false, gecikmeMs: sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      return SyncPingResult(basarili: false, hata: e.toString());
    }
  }

  // ── İstemci: Durum Al ─────────────────────────────────────────────────
  Future<Map<String, dynamic>?> uzaktanDurumAl(String adres) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final req =
          await client.getUrl(Uri.parse('${adres.trimRight()}/api/durum'));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await utf8.decoder.bind(res).join();
        client.close();
        return jsonDecode(body) as Map<String, dynamic>;
      }
      client.close();
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── İstemci: JSON veri çek ────────────────────────────────────────────
  Future<Map<String, dynamic>?> uzaktanVeriAl(
    String adres, {
    void Function(String durum)? onDurum,
  }) async {
    try {
      onDurum?.call('Sunucuya bağlanılıyor...');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req =
          await client.getUrl(Uri.parse('${adres.trimRight()}/api/export'));
      req.headers.set('Accept', 'application/json');
      onDurum?.call('Veri indiriliyor...');
      final res = await req.close().timeout(const Duration(minutes: 5));
      if (res.statusCode == 200) {
        final chunks = <int>[];
        await for (final chunk in res) {
          chunks.addAll(chunk);
        }
        client.close();
        onDurum?.call('Veri ayrıştırılıyor...');
        final body = utf8.decode(chunks);
        return jsonDecode(body) as Map<String, dynamic>;
      }
      client.close();
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Uzak veri alma hatası: $e');
      return null;
    }
  }

  // ── İstemci: DB dosyası indir ─────────────────────────────────────────
  Future<String?> uzaktanDbIndir(
    String adres, {
    void Function(int alinan, int toplam)? onProgress,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req =
          await client.getUrl(Uri.parse('${adres.trimRight()}/api/db'));
      final res = await req.close();
      if (res.statusCode == 200) {
        final toplam = int.tryParse(
                res.headers.value('content-length') ?? '') ??
            0;
        int alinan = 0;
        final chunks = <int>[];
        await for (final chunk in res) {
          chunks.addAll(chunk);
          alinan += chunk.length;
          if (toplam > 0) onProgress?.call(alinan, toplam);
        }
        client.close();
        // Geçici dosyaya yaz
        final dir = await Directory.systemTemp.createTemp('marketplus_sync');
        final dosya = File('${dir.path}/market_indir.db');
        await dosya.writeAsBytes(chunks);
        return dosya.path;
      }
      client.close();
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('DB indirme hatası: $e');
      return null;
    }
  }

  // ── İstemci: Seçili tablolar gönder ──────────────────────────────────
  Future<Map<String, dynamic>> uzaktanVeriGonder(
    String adres,
    Map<String, dynamic> data,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client
          .postUrl(Uri.parse('${adres.trimRight()}/api/import'));
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      final jsonBody = jsonEncode(data);
      req.write(jsonBody);
      final res = await req.close().timeout(const Duration(minutes: 5));
      final body = await utf8.decoder.bind(res).join();
      client.close();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return {'hata': e.toString()};
    }
  }

  // ── Public wrapper ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>> tumVeriAlPublic() => _tumVeriAl();

  Future<String> dbYoluAl() async => (await Veritabani().db).path;

  Future<Map<String, dynamic>> veriIcerAktarPublic(
    Map<String, dynamic> data, {
    List<String>? sadeceTablolar,
  }) => _veriIcerAktar(data, sadeceTablolar: sadeceTablolar);

  // ── Bağlantı kontrolü ─────────────────────────────────────────────────
  Future<bool> wifiBaglantisiVar() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
  }

  // ── PC Tarayıcısı Web Arayüzü ─────────────────────────────────────────
  String _webArayuzu() => '''<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>MarketPlus Veri Merkezi</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#f0f2f5;color:#1a1a2e;min-height:100vh}
  .header{background:linear-gradient(135deg,#4361ee,#3a0ca3);color:#fff;padding:28px 32px;box-shadow:0 4px 20px rgba(67,97,238,.3)}
  .header h1{font-size:26px;font-weight:700;letter-spacing:.5px}
  .header p{opacity:.8;margin-top:4px;font-size:14px}
  .container{max-width:900px;margin:32px auto;padding:0 20px}
  .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:20px;margin-bottom:32px}
  .card{background:#fff;border-radius:16px;padding:24px;box-shadow:0 2px 12px rgba(0,0,0,.06);transition:transform .2s,box-shadow .2s}
  .card:hover{transform:translateY(-2px);box-shadow:0 8px 24px rgba(0,0,0,.1)}
  .card-icon{font-size:36px;margin-bottom:12px}
  .card h3{font-size:16px;font-weight:700;margin-bottom:6px;color:#1a1a2e}
  .card p{font-size:13px;color:#666;line-height:1.5;margin-bottom:16px}
  .btn{display:inline-flex;align-items:center;gap:8px;padding:10px 20px;border-radius:10px;font-size:14px;font-weight:600;cursor:pointer;text-decoration:none;border:none;transition:all .2s}
  .btn-primary{background:#4361ee;color:#fff}
  .btn-primary:hover{background:#3451d1}
  .btn-success{background:#2ec4b6;color:#fff}
  .btn-success:hover{background:#26a89d}
  .btn-warning{background:#f72585;color:#fff}
  .btn-warning:hover{background:#d91a6e}
  .btn-outline{background:#fff;color:#4361ee;border:2px solid #4361ee}
  .btn-outline:hover{background:#f0f3ff}
  .stats{background:#fff;border-radius:16px;padding:24px;margin-bottom:20px;box-shadow:0 2px 12px rgba(0,0,0,.06)}
  .stats h2{font-size:18px;font-weight:700;margin-bottom:16px;color:#1a1a2e;display:flex;align-items:center;gap:8px}
  .stat-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px}
  .stat-item{background:#f8f9ff;border-radius:12px;padding:16px;text-align:center}
  .stat-val{font-size:28px;font-weight:800;color:#4361ee}
  .stat-lbl{font-size:12px;color:#888;margin-top:4px;font-weight:500}
  .log{background:#1a1a2e;border-radius:12px;padding:16px;font-family:monospace;font-size:12px;color:#7ee8fa;max-height:180px;overflow-y:auto;margin-top:12px;white-space:pre-wrap;word-break:break-word}
  .badge{display:inline-block;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700}
  .badge-green{background:#d1fae5;color:#065f46}
  .badge-blue{background:#dbeafe;color:#1e40af}
  #progress{display:none;margin-top:12px}
  progress{width:100%;height:8px;border-radius:4px;appearance:none}
  progress::-webkit-progress-bar{background:#e9ecef;border-radius:4px}
  progress::-webkit-progress-value{background:#4361ee;border-radius:4px;transition:width .3s}
</style>
</head>
<body>
<div class="header">
  <h1>🏪 MarketPlus Veri Merkezi</h1>
  <p>WiFi üzerinden veri aktarım ve yönetim paneli</p>
</div>
<div class="container">
  <div class="stats" id="statsCard">
    <h2>📊 Veritabanı Durumu <span class="badge badge-green" id="statusBadge">Yükleniyor...</span></h2>
    <div class="stat-grid" id="statGrid">
      <div class="stat-item"><div class="stat-val" id="s1">-</div><div class="stat-lbl">Ürün</div></div>
      <div class="stat-item"><div class="stat-val" id="s2">-</div><div class="stat-lbl">Cari</div></div>
      <div class="stat-item"><div class="stat-val" id="s3">-</div><div class="stat-lbl">Satış</div></div>
      <div class="stat-item"><div class="stat-val" id="s4">-</div><div class="stat-lbl">DB Boyutu</div></div>
    </div>
  </div>

  <div class="cards">
    <div class="card">
      <div class="card-icon">📦</div>
      <h3>Veritabanını İndir</h3>
      <p>Tüm market.db dosyasını bilgisayara indirin. Yedek veya aktarım için kullanın.</p>
      <a class="btn btn-primary" href="/api/db" download="market.db">⬇ market.db İndir</a>
    </div>
    <div class="card">
      <div class="card-icon">📋</div>
      <h3>Ürünleri JSON Al</h3>
      <p>Ürün listesini JSON formatında dışa aktarın. Analiz veya başka sistemlere aktarım için.</p>
      <button class="btn btn-success" onclick="tabloIndir('urunler')">📥 Ürünleri Al</button>
    </div>
    <div class="card">
      <div class="card-icon">👥</div>
      <h3>Cari Listesi Al</h3>
      <p>Tüm müşteri ve tedarikçi kayıtlarını JSON olarak alın.</p>
      <button class="btn btn-success" onclick="tabloIndir('cari')">📥 Cari Al</button>
    </div>
    <div class="card">
      <div class="card-icon">💰</div>
      <h3>Satışları Al</h3>
      <p>Satış fiş kayıtlarını ve kalemlerini dışa aktarın.</p>
      <button class="btn btn-success" onclick="tabloIndir('satislar')">📥 Satışları Al</button>
    </div>
    <div class="card">
      <div class="card-icon">🔄</div>
      <h3>Tüm Veriyi Al</h3>
      <p>Tüm tabloları tek JSON dosyasında alın. Tam yedek için.</p>
      <a class="btn btn-outline" href="/api/export" download="marketplus_export.json">⬇ Tam Export</a>
    </div>
    <div class="card">
      <div class="card-icon">⬆</div>
      <h3>Veri Yükle</h3>
      <p>Daha önce alınan JSON veya DB dosyasını yükleyin.</p>
      <button class="btn btn-warning" onclick="dosyaSec()">📤 Dosya Seç & Yükle</button>
      <input type="file" id="dosyaInput" accept=".json,.db" style="display:none" onchange="dosyaYukle(event)">
    </div>
  </div>

  <div id="progress">
    <div class="log" id="logAlani">İşlem bekleniyor...</div>
    <progress id="bar" value="0" max="100" style="margin-top:8px"></progress>
  </div>
</div>

<script>
const log = (msg) => {
  const el = document.getElementById('logAlani');
  el.textContent += '\\n' + new Date().toLocaleTimeString() + ' > ' + msg;
  el.scrollTop = el.scrollHeight;
};

const showProgress = (show) => {
  document.getElementById('progress').style.display = show ? 'block' : 'none';
};

// İstatistik yükle
async function istatistikYukle() {
  try {
    const res = await fetch('/api/durum');
    const data = await res.json();
    document.getElementById('s1').textContent = data.urun_sayisi?.toLocaleString() || '-';
    document.getElementById('s2').textContent = data.cari_sayisi?.toLocaleString() || '-';
    document.getElementById('s3').textContent = data.satis_sayisi?.toLocaleString() || '-';
    const mb = ((data.db_boyutu || 0) / 1024 / 1024).toFixed(1);
    document.getElementById('s4').textContent = mb + ' MB';
    document.getElementById('statusBadge').textContent = 'Bağlı ✓';
    document.getElementById('statusBadge').style.cssText = 'background:#d1fae5;color:#065f46;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700';
  } catch(e) {
    document.getElementById('statusBadge').textContent = 'Bağlantı Hatası';
  }
}

async function tabloIndir(tablo) {
  showProgress(true);
  log('Tablo indiriliyor: ' + tablo + '...');
  try {
    const res = await fetch('/api/tablo/' + tablo);
    const data = await res.json();
    const blob = new Blob([JSON.stringify(data, null, 2)], {type: 'application/json'});
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = tablo + '_' + new Date().toISOString().split('T')[0] + '.json';
    a.click();
    log('✅ ' + (data.sayi || 0) + ' kayıt indirildi: ' + a.download);
  } catch(e) { log('❌ Hata: ' + e.message); }
}

function dosyaSec() { document.getElementById('dosyaInput').click(); }

async function dosyaYukle(event) {
  const dosya = event.target.files[0];
  if (!dosya) return;
  showProgress(true);
  log('Dosya yükleniyor: ' + dosya.name + ' (' + (dosya.size/1024).toFixed(0) + ' KB)');
  
  const reader = new FileReader();
  reader.onload = async (e) => {
    try {
      if (dosya.name.endsWith('.json')) {
        const data = JSON.parse(e.target.result);
        log('JSON ayrıştırıldı. Sunucuya gönderiliyor...');
        const res = await fetch('/api/import', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify(data)
        });
        const sonuc = await res.json();
        log('✅ Tamamlandı: ' + JSON.stringify(sonuc));
      } else if (dosya.name.endsWith('.db')) {
        const buf = e.target.result;
        log('DB dosyası gönderiliyor...');
        const res = await fetch('/api/db', {method:'POST', body: buf});
        const sonuc = await res.json();
        log('✅ ' + (sonuc.mesaj || JSON.stringify(sonuc)));
      }
      document.getElementById('bar').value = 100;
      istatistikYukle();
    } catch(e) { log('❌ Hata: ' + e.message); }
  };
  
  if (dosya.name.endsWith('.db')) reader.readAsArrayBuffer(dosya);
  else reader.readAsText(dosya, 'UTF-8');
}

// Simüle progress
let prog = 0;
const barTimer = setInterval(() => {
  const bar = document.getElementById('bar');
  if (prog < 90) prog += Math.random() * 3;
  bar.value = Math.min(prog, 90);
}, 500);

istatistikYukle();
</script>
</body>
</html>''';
}

// ── Sonuç Modelleri ───────────────────────────────────────────────────────
class SyncPingResult {
  final bool basarili;
  final int gecikmeMs;
  final String? cihaz;
  final String? versiyon;
  final String? hata;

  const SyncPingResult({
    required this.basarili,
    this.gecikmeMs = 0,
    this.cihaz,
    this.versiyon,
    this.hata,
  });
}