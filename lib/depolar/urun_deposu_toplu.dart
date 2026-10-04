// lib/depolar/urun_deposu_toplu.dart
//
// urun_deposu.dart'ın parçası (part/part of) — PLU sıralama, toplu fiyat uygulama ve barkod üretimi.
// Davranış BİREBİR aynı: UrunDeposu üzerine extension; private üyelere
// (_db vb.) aynı kütüphane olduğu için erişir.
part of 'urun_deposu.dart';

extension UrunDeposuToplu on UrunDeposu {
  /// PLU Yönetimi ekranından taşındı — bkz.
  /// plu_yonetim_ekrani.dart._siralamaKaydet. Sürükle-bırak ile
  /// belirlenen yeni sıra (liste indeksi = plu_sira) TEK transaction
  /// içinde atomik olarak yazılır, commit sonrası her ürün buluta
  /// bildirilir.
  Future<void> pluSiralamaKaydet(List<int> siraliUrunIdler) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (var i = 0; i < siraliUrunIdler.length; i++) {
        await txn.update(DbSabitler.urunler, {'plu_sira': i, 'last_updated': now},
            where: 'id = ?', whereArgs: [siraliUrunIdler[i]]);
      }
    });
    await _topluBulutSenkronuGonder(siraliUrunIdler);
  }

  /// Toplu Fiyat Güncelleme ekranından taşındı — bkz.
  /// toplu_fiyat_ekrani.dart._guncelle. Nihai fiyat (zam/indirim/sabit/
  /// alış-üstüne modlarının hesabı) çağıran tarafta hesaplanır (bu, UI'a
  /// özgü bir iş kuralı); burası SADECE hesaplanmış {urunId: yeniFiyat}
  /// haritasını TEK transaction içinde atomik olarak yazar (ya hepsi
  /// güncellenir ya hiçbiri) ve commit sonrası her ürünü buluta bildirir.
  Future<List<int>> topluFiyatUygula(Map<int, double> yeniFiyatlar) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final guncellenenIds = <int>[];
    await db.transaction((txn) async {
      for (final entry in yeniFiyatlar.entries) {
        await txn.update(DbSabitler.urunler,
            {
              'satis_fiyati': entry.value, 'last_updated': now,
              'fiyat_guncelleme_tarih': now,
              if (AuthServisi().aktifAd.isNotEmpty)
                'fiyat_guncelleyen_kullanici': AuthServisi().aktifAd,
            },
            where: 'id = ?', whereArgs: [entry.key]);
        guncellenenIds.add(entry.key);
      }
    });
    await _topluBulutSenkronuGonder(guncellenenIds);
    return guncellenenIds;
  }

  /// Birden fazla ürünün FARKLI alan/değer kombinasyonlarını TEK
  /// transaction'da (ya hepsi ya hiçbiri) günceller — toplu_islem_ekrani
  /// .dart için (Madde 4 sertleştirmesi, 2026-09-16). ÖNCEDEN bu ekran
  /// her ürünü ayrı ayrı alanGuncelle() ile (N ayrı yazma, atomik
  /// DEĞİL) güncelliyordu — kullanıcıya "Bu işlem geri alınamaz!"
  /// denip atomik bir işlem izlenimi veriliyordu, ama ortasında bir
  /// kesinti (uygulama çökmesi/güç kesintisi) olsaydı KISMİ güncelleme
  /// kalır, geri alınamazdı. Commit sonrası tüm güncellenen ürünler tek
  /// (parçalı) sorguyla buluta bildirilir.
  Future<List<int>> topluAlanGuncelle(
      Map<int, Map<String, dynamic>> guncellemeler) async {
    if (guncellemeler.isEmpty) return [];
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final guncellenenIds = <int>[];
    await db.transaction((txn) async {
      for (final entry in guncellemeler.entries) {
        final data = Map<String, dynamic>.from(entry.value);
        data['last_updated'] = now;
        final eskiSatir = await txn.query(DbSabitler.urunler,
            where: 'id = ?', whereArgs: [entry.key], limit: 1);
        UrunDeposu.fiyatMaliyetDamgala(data, eskiSatir.isEmpty ? null : eskiSatir.first, now);
        await txn.update(DbSabitler.urunler, data,
            where: 'id = ?', whereArgs: [entry.key]);
        guncellenenIds.add(entry.key);
      }
    });
    await _topluBulutSenkronuGonder(guncellenenIds);
    return guncellenenIds;
  }

  /// Verilen id listesindeki ürünleri TEK (parçalı) SELECT ile çekip her
  /// birini buluta bildirir. 🔴 Madde 25 (N+1 sertleştirmesi, 2026-09-16):
  /// dört toplu-yazma fonksiyonu (qrMenuSecimleriniKaydet,
  /// topluFiyatGuncelle, pluSiralamaKaydet, topluFiyatUygula) aynı hatalı
  /// deseni tekrarlıyordu — "toplu yaz, sonra bulut senkronu için her
  /// kaydı tek tek tekrar oku" (N ayrı SELECT). Ürün kataloğu binlerce
  /// satır olabildiğinden bu, büyük toplu işlemlerde ciddi bir I/O
  /// yükü ve gecikme birikimiydi. SQLite'ın IN(...) değişken sayısı
  /// sınırına takılmamak için 500'lük parçalar halinde sorgulanır.
  Future<void> _topluBulutSenkronuGonder(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _d;
    const parcaBoyutu = 500;
    for (var i = 0; i < ids.length; i += parcaBoyutu) {
      final bitis = (i + parcaBoyutu < ids.length) ? i + parcaBoyutu : ids.length;
      final parca = ids.sublist(i, bitis);
      final yerTutucular = List.filled(parca.length, '?').join(',');
      final satirlar = await db.query(DbSabitler.urunler,
          where: 'id IN ($yerTutucular)', whereArgs: parca);
      for (final satir in satirlar) {
        BulutManager().upsert(DbSabitler.urunler, Map<String, dynamic>.from(satir));
      }
    }
  }

  // 🔴 MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi, devam
  // (2026-09-22): urun_ekle_ekrani_ai_ses.dart doğrudan Veritabani().db
  // üzerinden bu sorguyu çalıştırıyordu (repository katmanını
  // atlıyordu). Davranış (P2 düzeltmesiyle birlikte) birebir korunarak
  // buraya taşındı: 'M' önekli barkodlar arasında GERÇEK en yüksek
  // numarayı (sayısal CAST ile, ekleniş sırasına göre değil) bulup bir
  // sonrakini üretir.
  Future<String> benzersizBarkodUret() async {
    final db = await _d;
    final sonuc = await db.rawQuery('''
      SELECT barkod FROM ${DbSabitler.urunler}
      WHERE barkod LIKE 'M%'
        AND barkod IS NOT NULL
        AND barkod != ''
        AND is_deleted = 0
      ORDER BY CAST(SUBSTR(barkod, 2) AS INTEGER) DESC LIMIT 1
    ''');
    int yeniNumara = 1;
    if (sonuc.isNotEmpty) {
      final sonBarkod = sonuc.first['barkod'] as String;
      final numaraStr = sonBarkod.substring(1);
      yeniNumara = (int.tryParse(numaraStr) ?? 0) + 1;
    }
    return "M${yeniNumara.toString().padLeft(6, '0')}";
  }

  // 🔴 Derin analizde bulundu: stokGuncelle(id, yeniStok) burada duruyordu
  // ama projede HİÇBİR YERDEN çağrılmıyordu (ölü kod) — ve çağrılsaydı
  // TEHLİKELİYDİ: urunler.stok'u stok_hareket tablosuna hiç kayıt
  // düşmeden doğrudan değiştiriyordu. Stok, StokDeposu'nda stok_hareket
  // toplamından yeniden hesaplanan bir event-sourcing modeliyle yönetiliyor
  // (bkz. stokMutabakatYap) — bu fonksiyonla değiştirilen bir stok, bir
  // sonraki mutabakatta sessizce eski değere geri dönerdi. İleride birinin
  // bu tuzağı fark etmeden kullanmasını önlemek için tamamen kaldırıldı;
  // stok değişikliği gereken her yer StokDeposu.stokDusTxn/stokGirTxn
  // kullanmalı.

}
