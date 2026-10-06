// test/servisler/iade_coklu_kalem_duzenleme_test.dart
//
// Kullanıcı bulgusu: "önceki 2 idi, 4 ilave ettim → 6 olmalı; hep 4 adet
// kaydetmiş; cariye doğru tutar girmemiş". GERÇEK servislerle (robot
// ortamı, gerçek şema) doğrular:
//   • aynı ürüne ek iade kalemi TOPLANIR (2+4=6), stok ve cari buna uyar,
//   • çok ürünlü fişte bir kalemi düzenlemek DİĞER kalemleri ezmez,
//   • iade toplamı ve cari hareketi TÜM kalemlerin toplamıdır.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/auth_servisi.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/servisler/veri_sagligi_servisi.dart';
import '../robot/robot_ortam.dart';

void main() {
  late Database db;
  late RobotVeri v;
  final servis = IadeIslemServisi();

  Future<double> sayi(String sql, [List<Object?>? a]) async =>
      ((await db.rawQuery(sql, a)).first.values.first as num?)?.toDouble() ?? 0;

  setUp(() async {
    await RobotOrtam.hazirla();
    db = await RobotOrtam.veritabaniAc();
    v = await RobotOrtam.tohumla(db);
    expect(await AuthServisi().girisYap('admin', '1234'), isTrue);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await AuthServisi().cikisYap();
    await db.close();
  });

  Future<int> iadeyiKur() async {
    final cari = v.id['cari']!;
    final iadeId = await servis.manuelKalemEkle(
      oturumIadeId: null, cariId: cari, cariTipi: 'Müşteri', fisNo: 'IAD-T1',
      urunId: v.id['urun0']!, urunAdi: 'Robot Çikolata 80 G', miktar: 2, fiyat: 25,
      toplam: 50, neden: 'test', odemeYontemi: 'Cari', kullaniciId: 1, kullaniciAdi: 'Robot',
    );
    await servis.manuelKalemEkle(
      oturumIadeId: iadeId, cariId: cari, cariTipi: 'Müşteri', fisNo: 'IAD-T1',
      urunId: v.id['urun1']!, urunAdi: 'Robot Deterjan 900 G', miktar: 3, fiyat: 90,
      toplam: 270, neden: 'test', odemeYontemi: 'Cari', kullaniciId: 1, kullaniciAdi: 'Robot',
    );
    return iadeId;
  }

  Future<double> kalem(int iadeId, String urunKey) => sayi(
      'SELECT miktar FROM iade_kalem WHERE iade_id = ? AND urun_id = ?', [iadeId, v.id[urunKey]]);
  Future<double> cariAlacak(int iadeId) => sayi(
      "SELECT COALESCE(SUM(alacak),0) FROM cari_hareket WHERE fis_id = ? AND is_deleted = 0 AND fis_tipi = 'İade'",
      [iadeId]);

  test('kurulum: iki ürün, toplam 320, cari alacak 320, stok arttı', () async {
    final id = await iadeyiKur();
    expect(await kalem(id, 'urun0'), 2);
    expect(await kalem(id, 'urun1'), 3);
    expect(await sayi('SELECT toplam_tutar FROM iade WHERE id = ?', [id]), 320);
    expect(await cariAlacak(id), 320);
    expect(await sayi('SELECT stok FROM urunler WHERE id = ?', [v.id['urun0']]), 102);
  });

  test('aynı ürüne ek iade: 2 + 4 = 6; fiş, stok ve cari toplanır', () async {
    final id = await iadeyiKur();
    await servis.duzenlemeModuKalemEkle(
      iadeId: id, urunId: v.id['urun0']!, urunAdi: 'Robot Çikolata 80 G', miktar: 4,
      fiyat: 25, toplam: 100, fisNo: 'IAD-T1', cariId: v.id['cari'], cariTipi: 'Müşteri',
      kullaniciId: 1, kullaniciAdi: 'Robot', odemeYontemi: 'Cari',
    );
    expect(await kalem(id, 'urun0'), 6, reason: '2 + 4 toplanmalı, 4 olarak ezilmemeli');
    expect(await kalem(id, 'urun1'), 3);
    expect(await sayi('SELECT COUNT(*) FROM iade_kalem WHERE iade_id = ? AND urun_id = ?',
        [id, v.id['urun0']]), 1, reason: 'aynı ürün için tek satır');
    expect(await sayi('SELECT toplam_tutar FROM iade WHERE id = ?', [id]), 420);
    expect(await cariAlacak(id), 420);
    expect(await sayi('SELECT stok FROM urunler WHERE id = ?', [v.id['urun0']]), 106);
  });

  test('BULUT: düzenleme kuyruğa doğru değerleri ve eski cari satırının "silindi" bilgisini yazar', () async {
    final id = await iadeyiKur();
    await db.delete('sync_queue');
    await servis.oturumIadeDuzenle(
      iadeId: id, urunId: v.id['urun0'], cariId: v.id['cari'], fisNo: 'IAD-T1',
      urunAdi: 'Robot Çikolata 80 G', eskiMiktar: 2, eskiToplam: 50, yeniMiktar: 5,
      yeniFiyat: 25, yeniToplam: 125, yeniAciklama: 'test',
    );
    final q = await db.query('sync_queue');
    List<Map<String, dynamic>> tablo(String ad) => [
          for (final r in q)
            if (r['tablo_adi'] == ad) jsonDecode(r['veri_json'].toString()) as Map<String, dynamic>
        ];
    // iade_kalem: iki kalem de doğru miktarla (5 ve 3) kuyrukta
    final kalemler = tablo('iade_kalem');
    expect(kalemler.map((m) => (m['miktar'] as num).toDouble()).toList()..sort(), [3.0, 5.0]);
    // iade başlığı fiş toplamıyla (125 + 270)
    expect((tablo('iade').last['toplam_tutar'] as num).toDouble(), 395);
    // cari hareketi: eski (silindi=1) VE yeni (alacak 395) ikisi de kuyrukta
    final hareketler = tablo('cari_hareket');
    expect(hareketler.any((m) => m['is_deleted'] == 1), isTrue,
        reason: 'eski satırın silindi bilgisi buluta gitmeli');
    expect(hareketler.any((m) => (m['alacak'] as num?)?.toDouble() == 395 && m['is_deleted'] != 1), isTrue);
    expect((tablo('cari').last['bakiye'] as num).toDouble(), -395);
  });

  group('Veri Sağlığı: İade Kalem Miktarı', () {
    Future<SaglikKontrolSonucu> kontrol() async =>
        (await VeriSagligiServisi().tumKontrolleriCalistir())
            .firstWhere((k) => k.id == 'iade_kalem_stok');

    test('sağlıklı akış (ekle + ek kalem + düzenle) YEŞİL çıkar', () async {
      final id = await iadeyiKur();
      await servis.duzenlemeModuKalemEkle(
        iadeId: id, urunId: v.id['urun0']!, urunAdi: 'Robot Çikolata 80 G', miktar: 4,
        fiyat: 25, toplam: 100, fisNo: 'IAD-T1', cariId: v.id['cari'], cariTipi: 'Müşteri',
        kullaniciId: 1, kullaniciAdi: 'Robot', odemeYontemi: 'Cari',
      );
      await servis.oturumIadeDuzenle(
        iadeId: id, urunId: v.id['urun0'], cariId: v.id['cari'], fisNo: 'IAD-T1',
        urunAdi: 'Robot Çikolata 80 G', eskiMiktar: 6, eskiToplam: 150, yeniMiktar: 5,
        yeniFiyat: 25, yeniToplam: 125, yeniAciklama: 'test',
      );
      final k = await kontrol();
      expect(k.durum, SaglikDurum.yesil, reason: k.mesaj);
      expect(k.sayi, 0);
    });

    test('ESKİ HATANIN bozduğu fiş yakalanır ve miktarlar stok hareketinden onarılır', () async {
      final id = await iadeyiKur(); // çikolata 2, deterjan 3
      // Eski hatayı taklit et: tüm kalemler tek düzenlemeyle 5'e ezilmiş.
      await db.rawUpdate('UPDATE iade_kalem SET miktar = 5 WHERE iade_id = ?', [id]);
      var k = await kontrol();
      expect(k.durum, SaglikDurum.sari);
      expect(k.sayi, 2, reason: 'iki kalem de stok hareketinden (2 ve 3) farklı');
      expect(k.mesaj, contains('IAD-T1'));
      expect(k.duzelt, isNotNull);

      expect(await k.duzelt!(), 2);
      expect(await kalem(id, 'urun0'), 2);
      expect(await kalem(id, 'urun1'), 3);
      k = await kontrol();
      expect(k.durum, SaglikDurum.yesil);
    });

    test('silinmiş (iptal) iadeye dokunmaz', () async {
      final id = await iadeyiKur();
      await db.rawUpdate('UPDATE iade_kalem SET miktar = 9 WHERE iade_id = ?', [id]);
      await db.insert('stok_hareket', {
        'urun_id': v.id['urun0'], 'hareket_turu': 'İade İptali', 'miktar': 2,
        'onceki_stok': 102, 'sonraki_stok': 100, 'referans_id': id,
        'referans_turu': 'iade_iptal', 'tarih': DateTime.now().toIso8601String(),
      });
      final k = await kontrol();
      expect(k.sayi, 0, reason: 'iptal edilmiş iade karşılaştırılmaz');
    });
  });

  test('TEDARİKÇİ (alım iadesi): aynı kurallar, tutar BORÇ tarafında', () async {
    final ted = v.id['tedarikci']!;
    final id = await servis.manuelKalemEkle(
      oturumIadeId: null, cariId: ted, cariTipi: 'Tedarikçi', fisNo: 'IAD-T2',
      urunId: v.id['urun0']!, urunAdi: 'Robot Çikolata 80 G', miktar: 2, fiyat: 18,
      toplam: 36, neden: 'test', odemeYontemi: 'Cari', kullaniciId: 1, kullaniciAdi: 'Robot',
    );
    await servis.manuelKalemEkle(
      oturumIadeId: id, cariId: ted, cariTipi: 'Tedarikçi', fisNo: 'IAD-T2',
      urunId: v.id['urun1']!, urunAdi: 'Robot Deterjan 900 G', miktar: 1, fiyat: 60,
      toplam: 60, neden: 'test', odemeYontemi: 'Cari', kullaniciId: 1, kullaniciAdi: 'Robot',
    );
    await servis.duzenlemeModuKalemEkle(
      iadeId: id, urunId: v.id['urun0']!, urunAdi: 'Robot Çikolata 80 G', miktar: 4,
      fiyat: 18, toplam: 72, fisNo: 'IAD-T2', cariId: ted, cariTipi: 'Tedarikçi',
      kullaniciId: 1, kullaniciAdi: 'Robot', odemeYontemi: 'Cari',
    );
    expect(await kalem(id, 'urun0'), 6);
    expect(await kalem(id, 'urun1'), 1);
    Future<double> borc() => sayi(
        "SELECT COALESCE(SUM(borc),0) FROM cari_hareket WHERE fis_id = ? AND is_deleted = 0 AND fis_tipi = 'Alım İadesi'",
        [id]);
    expect(await borc(), 168, reason: '36 + 60 + 72');
    await servis.oturumIadeDuzenle(
      iadeId: id, urunId: v.id['urun0'], cariId: ted, fisNo: 'IAD-T2',
      urunAdi: 'Robot Çikolata 80 G', eskiMiktar: 6, eskiToplam: 108, yeniMiktar: 5,
      yeniFiyat: 18, yeniToplam: 90, yeniAciklama: 'test',
    );
    expect(await kalem(id, 'urun1'), 1, reason: 'diğer kalem ezilmemeli');
    expect(await sayi('SELECT toplam_tutar FROM iade WHERE id = ?', [id]), 150);
    expect(await borc(), 150, reason: 'cari borç = tüm fiş (90 + 60)');
  });

  test('çok ürünlü fişte bir kalemi düzenlemek DİĞERİNİ ezmez; toplam ve cari tüm kalemlerden', () async {
    final id = await iadeyiKur();
    await servis.duzenlemeModuKalemEkle(
      iadeId: id, urunId: v.id['urun0']!, urunAdi: 'Robot Çikolata 80 G', miktar: 4,
      fiyat: 25, toplam: 100, fisNo: 'IAD-T1', cariId: v.id['cari'], cariTipi: 'Müşteri',
      kullaniciId: 1, kullaniciAdi: 'Robot', odemeYontemi: 'Cari',
    );
    // Çikolata 6 → 5 adet olarak düzenlenir
    await servis.oturumIadeDuzenle(
      iadeId: id, urunId: v.id['urun0'], cariId: v.id['cari'], fisNo: 'IAD-T1',
      urunAdi: 'Robot Çikolata 80 G', eskiMiktar: 6, eskiToplam: 150, yeniMiktar: 5,
      yeniFiyat: 25, yeniToplam: 125, yeniAciklama: 'test',
    );
    expect(await kalem(id, 'urun0'), 5);
    expect(await kalem(id, 'urun1'), 3, reason: 'Deterjan kalemi ezilmemeli (eski hata: hepsi 5/4 oluyordu)');
    expect(await sayi('SELECT toplam FROM iade_kalem WHERE iade_id = ? AND urun_id = ?',
        [id, v.id['urun1']]), 270);
    expect(await sayi('SELECT toplam_tutar FROM iade WHERE id = ?', [id]), 395,
        reason: 'fiş toplamı = 125 + 270');
    expect(await cariAlacak(id), 395, reason: 'cari yalnız düzenlenen kalemin değil TÜM fişin toplamı');
    expect(await sayi('SELECT stok FROM urunler WHERE id = ?', [v.id['urun0']]), 105);
    // Cari bakiyesi: müşteri alacak yazıldı → bakiye -395
    expect(await sayi('SELECT bakiye FROM cari WHERE id = ?', [v.id['cari']]), -395);
  });
}
