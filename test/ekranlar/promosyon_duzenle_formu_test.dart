// test/ekranlar/promosyon_duzenle_formu_test.dart
//
// Promosyon DÜZENLEME artık "Yeni Promosyon" formuyla aynı: ürün, iskonto %
// ↔ toplam fiyat, min. miktar, başlangıç/bitiş tarihi, tarih yenileme
// kısayolları ve aktif anahtarı. GERÇEK şema/depo ile uçtan uca.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/promosyon_deposu.dart';
import 'package:market_plus/ekranlar/promosyon/promosyon_ekrani.dart';
import 'package:market_plus/modeller/promosyon_model.dart';
import '../robot/robot_ortam.dart';

void main() {
  final fmt = DateFormat('dd.MM.yyyy');

  Future<void> sayfaKur(WidgetTester t, PromosyonModel p) async {
    t.view.physicalSize = const Size(420, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<bool>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => PromosyonFormSheet(duzenlenecek: p),
                ),
                child: const Text('ac'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('ac'));
    // Ürün yükleme (DB) bitsin
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
  }

  late PromosyonModel promo;
  late int promoId;

  Database? _db;

  tearDown(() async {
    await _db?.close();
    _db = null;
  });

  testWidgets('düzenleme formu dolu açılır; toplam fiyat hesaplanır; tarih yenile + güncelle kaydeder', (t) async {
    await t.runAsync(() async {
      await RobotOrtam.hazirla();
      final db = await RobotOrtam.veritabaniAc();
      _db = db;
      final v = await RobotOrtam.tohumla(db);
      promoId = await PromosyonDeposu().ekle(PromosyonModel(
        urunId: v.id['urun0']!, // satış fiyatı 25
        promosyonAdi: 'Çikolata 4lü',
        iskontoOran: 20,
        minMiktar: 4,
        baslangicTarihi: DateTime(2026, 1, 1),
        bitisTarihi: DateTime(2026, 1, 31),
      ));
      promo = (await PromosyonDeposu().tumunuGetir()).firstWhere((x) => x.id == promoId);
    });
    await sayfaKur(t, promo);
    expect(t.takeException(), isNull);

    // Alanlar dolu
    expect(find.text('Promosyonu Düzenle'), findsOneWidget);
    expect(find.text('Güncelle'), findsOneWidget);
    expect(find.text('Aktif'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Çikolata 4lü'), findsOneWidget);
    // Toplam: 4 × 25 × 0,80 = 80,00
    expect(find.widgetWithText(TextFormField, '80.00'), findsOneWidget);
    expect(find.text('01.01.2026'), findsOneWidget);
    expect(find.text('31.01.2026'), findsOneWidget);

    // Tarih yenileme: bugünden, önceki süre (30 gün) kadar
    await t.ensureVisible(find.text('Bugünden yenile'));
    await t.tap(find.text('Bugünden yenile'));
    await t.pumpAndSettle();
    final bugun = DateTime.now();
    final gun = DateTime(bugun.year, bugun.month, bugun.day);
    expect(find.text(fmt.format(gun)), findsOneWidget);
    expect(find.text(fmt.format(gun.add(const Duration(days: 30)))), findsOneWidget);

    // Toplam fiyat 60 yazınca iskonto % otomatik: 4×25=100 → %40
    await t.enterText(find.widgetWithText(TextFormField, '80.00'), '60');
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '40'), findsOneWidget);

    await t.ensureVisible(find.text('Güncelle'));
    await t.tap(find.text('Güncelle'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();

    final kayit = await t.runAsync(() async =>
        (await PromosyonDeposu().tumunuGetir()).firstWhere((x) => x.id == promoId));
    expect(kayit!.iskontoOran, closeTo(40, 0.01));
    expect(kayit.baslangicTarihi!.day, gun.day);
    expect(kayit.bitisTarihi!.difference(kayit.baslangicTarihi!).inDays, 30);
    expect(kayit.minMiktar, 4);
  });

  testWidgets('"Süresiz" tarihleri KALDIRIR ve kayıtta gerçekten silinir; aktif kapatılabilir', (t) async {
    await t.runAsync(() async {
      await RobotOrtam.hazirla();
      final db = await RobotOrtam.veritabaniAc();
      _db = db;
      final v = await RobotOrtam.tohumla(db);
      promoId = await PromosyonDeposu().ekle(PromosyonModel(
        urunId: v.id['urun0']!,
        promosyonAdi: 'Süreli',
        iskontoOran: 10,
        minMiktar: 1,
        baslangicTarihi: DateTime(2026, 3, 1),
        bitisTarihi: DateTime(2026, 3, 31),
      ));
      promo = (await PromosyonDeposu().tumunuGetir()).firstWhere((x) => x.id == promoId);
    });
    await sayfaKur(t, promo);

    await t.ensureVisible(find.text('Süresiz'));
    await t.tap(find.text('Süresiz'));
    await t.pumpAndSettle();
    expect(find.text('Başlangıç'), findsOneWidget);
    expect(find.text('Bitiş'), findsOneWidget);

    await t.ensureVisible(find.byType(Switch));
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Güncelle'));
    await t.tap(find.text('Güncelle'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();

    final kayit = await t.runAsync(() async =>
        (await PromosyonDeposu().tumunuGetir()).firstWhere((x) => x.id == promoId));
    expect(kayit!.baslangicTarihi, isNull, reason: 'tarih temizlenebilmeli');
    expect(kayit.bitisTarihi, isNull);
    expect(kayit.aktif, isFalse);
  });

  testWidgets('+30 gün: dolmuş promosyonu bugünden uzatır', (t) async {
    await t.runAsync(() async {
      await RobotOrtam.hazirla();
      final db = await RobotOrtam.veritabaniAc();
      _db = db;
      final v = await RobotOrtam.tohumla(db);
      promoId = await PromosyonDeposu().ekle(PromosyonModel(
        urunId: v.id['urun0']!, promosyonAdi: 'Dolmuş', iskontoOran: 10, minMiktar: 1,
        baslangicTarihi: DateTime(2025, 1, 1), bitisTarihi: DateTime(2025, 1, 31),
      ));
      promo = (await PromosyonDeposu().tumunuGetir()).firstWhere((x) => x.id == promoId);
    });
    await sayfaKur(t, promo);
    await t.ensureVisible(find.text('+30 gün'));
    await t.tap(find.text('+30 gün'));
    await t.pumpAndSettle();
    final bugun = DateTime.now();
    final beklenen = DateTime(bugun.year, bugun.month, bugun.day).add(const Duration(days: 30));
    expect(find.text(fmt.format(beklenen)), findsOneWidget,
        reason: 'süresi dolmuşsa bugünden itibaren uzatılır');
  });
}
