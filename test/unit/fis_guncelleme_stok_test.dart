// test/unit/fis_guncelleme_stok_test.dart
//
// FİŞ GÜNCELLEME — STOK FARKI TESTİ
//
// Neden kritik: Kapatılmış bir fiş güncellendiğinde stok YANLIŞ
// hesaplanırsa envanter sessizce bozulur ve bunu fark etmek aylar
// alabilir. Bu testler `SatisDeposu.fisiGuncelle()` içindeki fark
// hesabının aynısını doğrular.
//
// KURAL:
//   fark = yeniMiktar - eskiMiktar
//   fark > 0  →  stoktan DÜŞ     (miktar arttı / yeni ürün eklendi)
//   fark < 0  →  stoğa GERİ VER  (miktar azaldı / kalem silindi)
//   fark = 0  →  dokunma
//
// Kalemleri silip yeniden yazmak YANLIŞ olurdu: eski kalemler için
// stok zaten düşülmüştü, ikinci kez düşülürse envanter eksilir.

import 'package:flutter_test/flutter_test.dart';

/// `SatisDeposu.fisiGuncelle()` içindeki hesabın birebir kopyası.
/// Orada değişirse burada da değişmeli — test o yüzden var.
Map<int, double> stokFarklariHesapla(
  Map<int, double> eskiMiktarlar,
  Map<int, double> yeniMiktarlar,
) {
  final farklar = <int, double>{};
  for (final uid in {...eskiMiktarlar.keys, ...yeniMiktarlar.keys}) {
    final fark = (yeniMiktarlar[uid] ?? 0) - (eskiMiktarlar[uid] ?? 0);
    if (fark.abs() > 0.0001) farklar[uid] = fark;
  }
  return farklar;
}

void main() {
  group('Ürün ekleme', () {
    test('yeni ürün eklenince sadece o üründen düşülür', () {
      final f = stokFarklariHesapla({1: 2, 2: 1}, {1: 2, 2: 1, 3: 1});
      expect(f, {3: 1.0});
    });

    test('mevcut üründen daha fazla eklenince fark kadar düşülür', () {
      final f = stokFarklariHesapla({1: 2}, {1: 5});
      expect(f, {1: 3.0});
    });
  });

  group('Düzeltme — azaltma ve silme', () {
    test('miktar azalınca stoğa GERİ VERİLİR (negatif fark)', () {
      final f = stokFarklariHesapla({1: 5}, {1: 2});
      expect(f, {1: -3.0});
    });

    test('kalem silinince tamamı stoğa geri verilir', () {
      final f = stokFarklariHesapla({1: 2, 2: 1}, {1: 2});
      expect(f, {2: -1.0});
    });

    test('tüm kalemler silinirse hepsi geri verilir', () {
      final f = stokFarklariHesapla({1: 2, 2: 1}, {});
      expect(f, {1: -2.0, 2: -1.0});
    });
  });

  group('Karma senaryolar', () {
    test('aynı anda artış + silme + ekleme', () {
      // Ekmek 2→3 (+1), Süt 1→0 (-1), Peynir 0→1 (+1)
      final f = stokFarklariHesapla({1: 2, 2: 1}, {1: 3, 3: 1});
      expect(f, {1: 1.0, 2: -1.0, 3: 1.0});
    });

    test('hiç değişiklik yoksa boş döner — gereksiz stok hareketi olmaz', () {
      final f = stokFarklariHesapla({1: 2, 2: 1}, {1: 2, 2: 1});
      expect(f, isEmpty);
    });

    test('ürünler yer değiştirse bile miktar aynıysa fark yok', () {
      // Sıra değişti ama miktarlar aynı
      final f = stokFarklariHesapla({1: 2, 2: 1}, {2: 1, 1: 2});
      expect(f, isEmpty);
    });
  });

  group('Tartılı (kg/lt) ürünler — ondalık miktar', () {
    test('0.5 kg → 1.25 kg farkı doğru hesaplanır', () {
      final f = stokFarklariHesapla({4: 0.5}, {4: 1.25});
      expect(f[4], closeTo(0.75, 0.0001));
    });

    test('çok küçük fark (yuvarlama gürültüsü) yok sayılır', () {
      // 0.0001 eşiğinin altı → gereksiz stok hareketi oluşturmamalı
      final f = stokFarklariHesapla({4: 1.0}, {4: 1.00005});
      expect(f, isEmpty);
    });

    test('eşiğin hemen üstündeki fark yakalanır', () {
      final f = stokFarklariHesapla({4: 1.0}, {4: 1.001});
      expect(f.containsKey(4), isTrue);
    });
  });

  group('Aynı ürün birden fazla kalemde', () {
    test('kalemler toplanarak tek fark üretilir', () {
      // Fişte Ekmek iki ayrı satırda (1+2=3), sepette tek satırda 4
      final f = stokFarklariHesapla({1: 3}, {1: 4});
      expect(f, {1: 1.0});
    });
  });
}
