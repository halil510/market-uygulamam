// test/widget/yazdirma_servisi_escpos_test.dart
//
// Kademe 2 (2026-11-06): YazdirmaServisi.fisYazdir() gerçekte hangi ESC/POS
// baytlarını üretiyor? Fiş, yazıcıya gitmeden @visibleForTesting
// YazdirmaServisi.testBaytYakalayici ile yakalanır; geri kalan her şey
// (ayarların DB'den okunması, Türkçe karakter temizliği, satır/toplam
// biçimi, kesme komutu) GERÇEK koddur.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';
import 'package:market_plus/modeller/satis_kalem_model.dart';
import 'package:market_plus/modeller/satis_model.dart';
import 'package:market_plus/servisler/yazdirma_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

bool _diziVar(List<int> b, List<int> aranan) {
  for (var i = 0; i + aranan.length <= b.length; i++) {
    var esit = true;
    for (var j = 0; j < aranan.length; j++) {
      if (b[i + j] != aranan[j]) {
        esit = false;
        break;
      }
    }
    if (esit) return true;
  }
  return false;
}

bool _metinVar(List<int> b, String s) => _diziVar(b, latin1.encode(s));

const _gsV = [0x1D, 0x56]; // GS V — kağıt kes

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  final yakalanan = <List<int>>[];

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    yakalanan.clear();
    YazdirmaServisi.testBaytYakalayici = yakalanan.add;
  });
  tearDown(() async {
    YazdirmaServisi.testBaytYakalayici = null;
    Veritabani.testVeritabani = null;
    await db.close();
  });

  SatisKalemModel kalem(String ad, double miktar, double fiyat) => SatisKalemModel(
        satisId: 1, urunId: 1, urunAdi: ad, miktar: miktar, birimFiyat: fiyat,
        netFiyat: fiyat, toplamTutar: ParaUtils.yuvarla(miktar * fiyat), kdvOran: 20,
        kdvTutar: ParaUtils.yuvarla(ParaUtils.kdvPayiCikar(miktar * fiyat, 20)));

  SatisModel satis(List<SatisKalemModel> kalemler) {
    final toplam = ParaUtils.yuvarla(kalemler.fold(0.0, (s, k) => s + k.toplamTutar));
    return SatisModel(
      fisNo: 'MKP2026000000123',
      tarih: DateTime(2026, 11, 6, 14, 30),
      toplamTutar: toplam,
      genelToplam: toplam,
      odenenTutar: toplam,
      odemeYontemi: 'Nakit',
      kalemler: kalemler,
    );
  }

  Future<List<int>> fisBas(SatisModel s, {String firma = 'Halk Market'}) async {
    await YazdirmaServisi().fisYazdir(s, firmaAdi: firma);
    expect(yakalanan, hasLength(1), reason: 'varsayılan kopya sayısı 1');
    return yakalanan.single;
  }

  test('örnek fiş: bayt üretilir ve kağıt kesme komutuyla (GS V) biter', () async {
    final b = await fisBas(satis([kalem('Ekmek', 2, 10), kalem('Süt', 1, 32.5)]));
    expect(b, isNotEmpty);
    expect(_diziVar(b, _gsV), isTrue, reason: 'GS V (kes) komutu olmalı');
    // Kesme komutundan sonra en fazla birkaç parametre baytı kalır.
    final sonKes = () {
      for (var i = b.length - 2; i >= 0; i--) {
        if (b[i] == 0x1D && b[i + 1] == 0x56) return i;
      }
      return -1;
    }();
    expect(b.length - sonKes, lessThanOrEqualTo(4));
  });

  test('fiş başlığında firma, tarih ve fiş no; altta TOPLAM var', () async {
    final b = await fisBas(satis([kalem('Ekmek', 2, 10)]));
    expect(_metinVar(b, 'Halk Market'), isTrue);
    expect(_metinVar(b, '06.11.2026 14:30'), isTrue);
    expect(_metinVar(b, 'MKP2026000000123'), isTrue);
    expect(_metinVar(b, 'TOPLAM'), isTrue);
  });

  test('Türkçe ş/ğ/ı/İ/Ş/Ğ ASCII karşılığına çevrilir, UTF-8 çok baytlı dizi kalmaz', () async {
    final b = await fisBas(satis([kalem('Şeker Ğıda İçecek', 1, 15)]),
        firma: 'Işık Şarküteri');
    // ı/ş/I ASCII'ye çevrilir; ü korunur ama yazıcı kod sayfasında tek baytla
    // (Latin-1'den farklı olabilir) kodlandığı için yalnız ASCII kısım aranır.
    expect(_metinVar(b, 'Isik Sark'), isTrue);
    expect(_metinVar(b, 'Seker Gida I'), isTrue, reason: 'Ş→S, Ğ→G, ı→i, İ→I');
    // UTF-8 'Ş' (C5 9E), 'ğ' (C4 9F), 'ı' (C4 B1) dizileri olmamalı.
    expect(_diziVar(b, [0xC5, 0x9E]), isFalse);
    expect(_diziVar(b, [0xC4, 0x9F]), isFalse);
    expect(_diziVar(b, [0xC4, 0xB1]), isFalse);
  });

  test('uzun fiş (25 kalem): tüm kalemler basılır ve sonda yine kesme komutu var', () async {
    final kalemler = [for (var i = 1; i <= 25; i++) kalem('Urun $i', 1, i.toDouble())];
    final b = await fisBas(satis(kalemler));
    expect(_metinVar(b, 'Urun 1'), isTrue);
    expect(_metinVar(b, 'Urun 25'), isTrue);
    expect(b[b.length - 3] == 0x1D || b[b.length - 2] == 0x1D || b[b.length - 4] == 0x1D,
        isTrue, reason: 'son komut GS V');
  });

  test('tutar biçimi ParaUtils.formatla (simgesiz) ile aynı', () async {
    final b = await fisBas(satis([kalem('Peynir', 1, 1234.5)]));
    final beklenen = ParaUtils.formatla(1234.5, simge: '');
    expect(beklenen, '1.234,50');
    expect(_metinVar(b, beklenen), isTrue);
  });

  test('temizleYaziciMetni: ₺ → TL, Latin-1 dışı karakterler atılır', () {
    expect(YazdirmaServisi.temizleYaziciMetni('10 ₺'), '10 TL');
    expect(YazdirmaServisi.temizleYaziciMetni('Elma 🍎'), 'Elma ');
    expect(YazdirmaServisi.temizleYaziciMetni('İŞĞışğ'), 'ISGisg');
  });
}
