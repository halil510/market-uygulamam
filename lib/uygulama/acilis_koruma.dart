// lib/uygulama/acilis_koruma.dart
//
// Açılışın elektrik kesintisi / yarım yazılmış dosyalara dayanıklılığı.
//
// OLAY (2026-10-08): uygulama açıkken elektrik gitti; bilgisayar açılınca
// uygulama BİR DAHA açılmadı (Windows'a çökme kaydı da düşmedi). Kök neden:
//  • shared_preferences_windows ayar dosyasını (shared_preferences.json)
//    flush/geçici-dosya olmadan doğrudan üzerine yazar; yazım sırasında
//    elektrik giderse dosya yarım/NUL dolu kalır. Okurken json.decode hatası
//    YAKALANMAZ ve dosya silinmez → her açılışta aynı hata.
//  • Açılıştaki servis başlatmaları (BulutManager.baslat ilk iş ayarı okur)
//    try bloğunun DIŞINDAYDI → hata runZonedGuarded'a düşüyor, runApp hiç
//    çağrılmıyor, pencere boş kalıyordu.
// Bu dosya: ayar dosyasını açılışta doğrulayıp son sağlam kopyadan onarır,
// her başlatma adımını ayrı korur, veritabanını hızlı kontrol eder ve
// bozuksa servisler (özellikle bulut senkronu) BAŞLAMADAN kurtarma ekranı
// gösterir.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../servisler/log_servisi.dart';
import '../servisler/yedekleme_servisi.dart';
import '../veri/database/veritabani.dart';

const _ayarDosyaAdi = 'shared_preferences.json';
const _saglamEk = '.son_saglam';

Future<File?> _ayarDosyasi() async {
  if (!Platform.isWindows) return null; // mobilde platformun kendi deposu
  final dizin = await getApplicationSupportDirectory();
  return File('${dizin.path}${Platform.pathSeparator}$_ayarDosyaAdi');
}

bool _gecerliJsonNesnesi(String metin) {
  if (metin.trim().isEmpty) return false;
  try {
    return jsonDecode(metin) is Map;
  } catch (_) {
    return false;
  }
}

/// SharedPreferences ilk kez okunmadan ÖNCE çağrılmalı. Ayar dosyası
/// bozuksa kenara alınır (silinmez) ve son sağlam kopya geri konur; o da
/// yoksa boş ayarla açılır (veriler veritabanında, ayarlar varsayılana döner).
Future<void> ayarDosyasiniOnar() async {
  final dosya = await _ayarDosyasi();
  if (dosya != null) await ayarDosyasiOnar(dosya);
}

@visibleForTesting
Future<void> ayarDosyasiOnar(File dosya) async {
  if (!await dosya.exists()) return;
  String metin;
  try {
    metin = await dosya.readAsString();
  } catch (_) {
    metin = ''; // UTF-8 olmayan çöp bayt da bozuk sayılır
  }
  if (_gecerliJsonNesnesi(metin)) return;

  final damga = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  await dosya.rename('${dosya.path}.bozuk_$damga');
  final saglam = File('${dosya.path}$_saglamEk');
  if (await saglam.exists() && _gecerliJsonNesnesi(await saglam.readAsString())) {
    await saglam.copy(dosya.path);
    LogServisi().uyari('Ayar dosyası bozuktu — son sağlam kopyadan onarıldı');
  } else {
    LogServisi().uyari('Ayar dosyası bozuktu — sağlam kopya yok, varsayılan ayarlarla açıldı');
  }
}

/// Açılış başarıyla bittikten sonra ayar dosyasının sağlam kopyasını alır
/// (geçici dosyaya yazıp yeniden adlandırarak — kopya da yarım kalmasın).
Future<void> ayarDosyasiniYedekle() async {
  final dosya = await _ayarDosyasi();
  if (dosya != null) await ayarDosyasiYedekle(dosya);
}

@visibleForTesting
Future<void> ayarDosyasiYedekle(File dosya) async {
  if (!await dosya.exists()) return;
  final metin = await dosya.readAsString();
  if (!_gecerliJsonNesnesi(metin)) return;
  final gecici = File('${dosya.path}$_saglamEk.tmp');
  await gecici.writeAsString(metin, flush: true);
  await gecici.rename('${dosya.path}$_saglamEk');
}

/// Bir başlatma adımını korur: hata verse de açılış sürer, hata loglanır.
Future<void> guvenliAdim(String ad, Future<void> Function() adim) async {
  try {
    await adim();
  } catch (e, st) {
    LogServisi().kritik('Açılış adımı başarısız: $ad', hata: e, yigin: st);
    if (kDebugMode) debugPrint('Açılış adımı başarısız ($ad): $e');
  }
}

/// Veritabanını açar (migrasyonlar dahil) ve hızlı bütünlük kontrolü yapar.
/// Sorun yoksa null, varsa kullanıcıya gösterilecek açıklama döner.
Future<String?> veritabaniniDogrula() async {
  try {
    final db = await Veritabani().db;
    final r = await db.rawQuery('PRAGMA quick_check');
    final sonuc = r.isEmpty ? 'ok' : '${r.first.values.first}';
    if (sonuc.toLowerCase() == 'ok') return null;
    return 'Veritabanı bütünlük kontrolü başarısız: $sonuc';
  } catch (e) {
    return 'Veritabanı açılamadı: $e';
  }
}

/// Veritabanı açılamadığında / bozuk olduğunda gösterilen kurtarma ekranı.
/// Bulut senkronu bu durumda hiç başlatılmaz (bozuk veri gönderilmesin).
class KurtarmaUygulamasi extends StatelessWidget {
  final String hata;
  const KurtarmaUygulamasi({super.key, required this.hata});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _KurtarmaEkrani(hata: hata),
      );
}

class _KurtarmaEkrani extends StatefulWidget {
  final String hata;
  const _KurtarmaEkrani({required this.hata});
  @override
  State<_KurtarmaEkrani> createState() => _KurtarmaEkraniState();
}

class _KurtarmaEkraniState extends State<_KurtarmaEkrani> {
  List<YedekBilgi> _yedekler = [];
  bool _yukleniyor = true;
  bool _isleniyor = false;
  String? _mesaj;
  bool _basarili = false;

  @override
  void initState() {
    super.initState();
    _listele();
  }

  Future<void> _listele() async {
    try {
      final l = await YedeklemeServisi().yedekListesi();
      if (mounted) setState(() => _yedekler = l);
    } catch (_) {}
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _geriYukle(YedekBilgi y) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Yedekten geri yükle'),
        content: Text(
            '${DateFormat('dd.MM.yyyy HH:mm').format(y.tarih)} tarihli yedek '
            'yüklenecek. Bu tarihten sonraki işlemler bu bilgisayardan '
            'silinir. Mevcut (bozuk) dosyanın kopyası saklanır.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Geri Yükle')),
        ],
      ),
    );
    if (onay != true) return;
    setState(() {
      _isleniyor = true;
      _mesaj = null;
    });
    try {
      await YedeklemeServisi().yedekiGeriYukle(y.yol);
      setState(() {
        _basarili = true;
        _mesaj = 'Yedek yüklendi. Uygulamayı kapatıp yeniden açın.';
      });
    } catch (e) {
      setState(() => _mesaj = 'Geri yükleme başarısız: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              const Icon(Icons.healing_outlined, size: 64, color: Colors.orange),
              const SizedBox(height: 12),
              const Text('Veritabanı açılamadı',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                  'Muhtemel neden: elektrik kesintisi ya da beklenmeyen kapanma. '
                  'Aşağıdaki otomatik yedeklerden birini geri yükleyebilirsiniz. '
                  'Bulut kullanıyorsanız, yükledikten sonra "Buluttan Al" ile '
                  'eksik kalan son işlemleri de çekebilirsiniz.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(widget.hata,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 20),
              if (_mesaj != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_mesaj!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _basarili ? Colors.green[800] : Colors.red[800])),
                ),
              if (_basarili)
                FilledButton(
                    onPressed: () => exit(0),
                    child: const Text('Uygulamayı Kapat'))
              else if (_yukleniyor || _isleniyor)
                const Center(child: CircularProgressIndicator())
              else if (_yedekler.isEmpty)
                const Text('Bu bilgisayarda yedek bulunamadı.',
                    textAlign: TextAlign.center)
              else
                for (final y in _yedekler)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.restore),
                      title: Text(DateFormat('dd.MM.yyyy HH:mm').format(y.tarih)),
                      subtitle: Text(
                          '${y.otomatik ? 'Otomatik' : 'Manuel'} · '
                          '${(y.boyutByte / 1024 / 1024).toStringAsFixed(1)} MB'),
                      trailing: const Text('Geri Yükle'),
                      onTap: () => _geriYukle(y),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
