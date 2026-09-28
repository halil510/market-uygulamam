// test/robot/robot_ortam.dart
//
// UYGULAMA ROBOTU — ortam: bellek içi test veritabanı, sahte eklenti
// kanalları ve tohum (sanal) verisi. Gerçek veritabanına, cihaz ayarlarına
// ve BULUTA hiçbir şekilde dokunmaz (bulut/QR/bildirim servisleri hiç
// başlatılmaz).
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/cekirdek/utils/sifre_hash.dart';
import 'package:market_plus/veri/database/tablolar/tablo_olusturucu.dart';
import 'package:market_plus/veri/database/veritabani.dart';

/// Tohumlanan kayıtların id'leri — detay ekranlarının (/cari/detay/:id
/// vb.) parametrelerini doldurmak için.
class RobotVeri {
  final Map<String, int> id = {};
}

class RobotOrtam {
  static final Map<String, String> _guvenliDepo = {};

  /// Bilinen eklenti kanallarına sahte yanıt verir. Bilinmeyen bir eklenti
  /// çağrısı MissingPluginException olarak raporda "ortam" sınıfında görünür
  /// (gerçek uygulama hatası sayılmaz).
  static void kanallariKur() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    void kur(String kanal, Future<Object?> Function(MethodCall c) f) =>
        m.setMockMethodCallHandler(MethodChannel(kanal), f);

    kur('plugins.it_nomads.com/flutter_secure_storage', (c) async {
      final a = (c.arguments as Map?) ?? {};
      final key = a['key'] as String?;
      switch (c.method) {
        case 'write':
          _guvenliDepo[key!] = a['value'] as String;
          return null;
        case 'read':
          return _guvenliDepo[key];
        case 'delete':
          _guvenliDepo.remove(key);
          return null;
        case 'containsKey':
          return _guvenliDepo.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(_guvenliDepo);
        case 'deleteAll':
          _guvenliDepo.clear();
          return null;
      }
      return null;
    });
    final tmp = Directory.systemTemp.createTempSync('robot_').path;
    kur('plugins.flutter.io/path_provider', (c) async => tmp);
    kur('dev.fluttercommunity.plus/connectivity', (c) async => ['wifi']);
    kur('dev.fluttercommunity.plus/package_info', (c) async => {
          'appName': 'BarkoPro', 'packageName': 'com.barkodhalkmarket.marketplus',
          'version': '2.3.0', 'buildNumber': '2',
        });
    kur('dev.fluttercommunity.plus/device_info', (c) async => <String, Object?>{});
    kur('plugins.flutter.io/local_auth', (c) async => false);
    kur('flutter.baseflow.com/permissions/methods', (c) async {
      if (c.method == 'checkPermissionStatus') return 1; // granted
      if (c.method == 'requestPermissions') return <int, int>{};
      return null;
    });
    kur('vibration', (c) async => false);
    kur('dexterous.com/flutter/local_notifications', (c) async => null);
    kur('plugins.flutter.io/url_launcher', (c) async => false);
    kur('flutter_blue_plus/methods', (c) async => null);
    // Kamera barkod tarayıcı (mobile_scanner 7.x): izin verilmiş, kamera
    // "açılmış" gibi yanıt verir — hiç barkod olayı gelmez. Böylece Fiyat Gör
    // gibi otomatik kamera açan ekranlar robotu kilitlemez.
    kur('dev.steenbakker.mobile_scanner/scanner/method', (c) async {
      switch (c.method) {
        case 'state':
          return 1; // authorized
        case 'request':
          return true;
        case 'start':
          return <String, Object?>{
            'textureId': 1,
            'cameraDirection': 1,
            'numberOfCameras': 1,
            'currentTorchState': -1,
            'size': {'width': 640.0, 'height': 480.0},
            'handlesCropAndRotation': true,
            'naturalDeviceOrientation': 'PORTRAIT_UP',
            'sensorOrientation': 90,
          };
        case 'getSupportedLenses':
          return <Object?>[];
      }
      return null;
    });
    // EventChannel dinle/iptal mesajları aynı adlı method kanalından gelir.
    kur('dev.steenbakker.mobile_scanner/scanner/event', (c) async => null);
    kur('dev.steenbakker.mobile_scanner/scanner/deviceOrientation', (c) async => null);
  }

  /// Bellek içi, AYNI isolate'te çalışan (sahte zamanlı widget testlerinde
  /// takılmayan) gerçek şemalı veritabanı.
  static Future<Database> veritabaniAc() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final db = await openDatabase(inMemoryDatabasePath,
        version: 1, onCreate: (db, _) => TabloOlusturucu.olustur(db));
    Veritabani.testVeritabani = db;
    return db;
  }

  static Future<void> hazirla() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'tema_adi': 'light'});
    _guvenliDepo.clear();
    kanallariKur();
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('tr');
  }

  /// Sanal işletme verisi: şube, admin (şifre 1234), kasiyer, kategoriler,
  /// ürünler, müşteri/tedarikçi/bayi, banka hesabı, masa.
  static Future<RobotVeri> tohumla(Database db) async {
    final v = RobotVeri();
    const u = Uuid();
    final tuz = SifreHash.tuzUret();
    v.id['sube'] = await db.insert('subeler',
        {'sube_kodu': 'MERKEZ', 'sube_adi': 'Merkez Şube', 'global_id': u.v4()});
    v.id['admin'] = await db.insert('kullanicilar', {
      'kullanici_adi': 'admin', 'sifre_hash': SifreHash.hashleTuzlu('1234', tuz),
      'tuz': tuz, 'ad_soyad': 'Robot Yönetici', 'rol': 'admin', 'aktif': 1,
      'global_id': u.v4(),
    });
    v.id['kategori'] = await db.insert('kategoriler', {'ad': 'Gıda'});
    // Gerçek kurulumda Veritabani ilk açılışta oluşturur (bkz. veritabani.dart).
    for (final k in ['Kira', 'Elektrik', 'Personel', 'Diğer']) {
      await db.insert('gider_kategoriler', {'ad': k});
    }
    await db.insert('birimler', {'ad': 'Adet', 'kisaltma': 'Adet'});
    await db.insert('birimler', {'ad': 'Kilogram', 'kisaltma': 'KG'});
    final urunler = [
      ('Robot Çikolata 80 G', '8690000000017', 25.0, 18.0, 80.0),
      ('Robot Deterjan 900 G', '8690000000024', 90.0, 60.0, 900.0),
      ('Robot Su 1.5 L', '8690000000031', 10.0, 6.0, 0.0),
    ];
    for (var i = 0; i < urunler.length; i++) {
      final (ad, barkod, satis, alis, gr) = urunler[i];
      v.id['urun$i'] = await db.insert('urunler', {
        'urun_adi': ad, 'barkod': barkod, 'satis_fiyati': satis, 'alis_fiyat': alis,
        'stok': 100.0, 'birim_adi': 'Adet', 'kdv_oran': '20', 'aktif': 1,
        'is_deleted': 0, 'kategori_id': v.id['kategori'], 'agirlik': gr,
        'global_id': u.v4(),
      });
    }
    v.id['urun'] = v.id['urun0']!;
    Future<int> cari(String unvan, String tip, String kod) => db.insert('cari', {
          'unvan': unvan, 'cari_tipi': tip, 'cari_kodu': kod, 'bakiye': 0,
          'aktif': 1, 'is_deleted': 0, 'global_id': u.v4(),
          'telefon': '05320000000', 'vade_gun': 30, 'limit_tutari': 5000,
        });
    v.id['cari'] = await cari('Robot Müşteri', 'Müşteri', 'CARIO-1');
    v.id['tedarikci'] = await cari('Robot Tedarikçi', 'Tedarikçi', 'CARIO-2');
    v.id['bayi'] = await cari('Robot Bayi', 'Hem Müşteri Hem Tedarikçi', 'CARIO-3');
    try {
      v.id['banka'] = await db.insert('bankalar', {'ad': 'Robot Bank', 'global_id': u.v4()});
      v.id['bankaHesap'] = await db.insert('banka_hesaplar', {
        'banka_id': v.id['banka'], 'hesap_adi': 'Robot Vadesiz', 'hesap_no': 'TR00', 'bakiye': 1000.0,
        'global_id': u.v4(),
      });
    } catch (_) {/* şema farkı — banka ekranları parametresiz denenir */}
    try {
      v.id['masa'] = await db.insert('masalar',
          {'ad': 'Masa 1', 'durum': 'bos', 'global_id': u.v4()});
    } catch (_) {}
    return v;
  }
}
