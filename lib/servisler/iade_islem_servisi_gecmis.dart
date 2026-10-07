// lib/servisler/iade_islem_servisi_gecmis.dart
//
// iade_islem_servisi.dart'ın parçası (part/part of) — düzenleme modunda kalem ekleme, geçmiş fiş iadesi silme, manuel kalem.
// Davranış BİREBİR aynı: IadeIslemServisi üzerine extension; private
// üyelere (_kasaDepo, _stokDepo...) aynı kütüphane olduğu için erişir.
part of 'iade_islem_servisi.dart';

extension IadeIslemServisiGecmis on IadeIslemServisi {
  /// "İade Geçmişi" düzenleme modunda mevcut bir iadeye YENİ kalem ekleme
  /// — bkz. iade_ekrani_gecmis.dart._duzenlemeModuKalemEkle (taşındığı
  /// yer). Stok geri eklenir, iade_kalem (aynı ürün varsa güncellenir,
  /// yoksa eklenir), iade.toplam_tutar kalemlerden yeniden hesaplanır,
  /// cari hareketi (fis_id bazlı tek kayıt — varsa güncellenir, yoksa
  /// eklenir) ve kasa hareketi (İade) TEK transaction içinde yazılır.
  Future<void> duzenlemeModuKalemEkle({
    required int iadeId,
    required int urunId,
    required String urunAdi,
    required double miktar,
    required double fiyat,
    required double toplam,
    required String? fisNo,
    required int? cariId,
    required String? cariTipi,
    required int? kullaniciId,
    required String kullaniciAdi,
    /// Satırın indirim oranı/tutarı (iade_kalem'e KAYDEDİLİR → başka
    /// cihazda ve fiş yeniden açılınca indirim görünür). [toplam] NET tutardır.
    double iskontoOran = 0,
    double iskontoTutar = 0,
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 sabah) — bkz.
    // topluIadeKaydet'teki AYNI düzeltmenin gerekçesi. Bu fonksiyon hiç
    // kasa hareketi yazmaz (İade Geçmişi'nde mevcut/kapanmış bir fişe
    // ek kalem işlemidir, kasa tarafı bu turun BİLİNÇLİ OLARAK kapsamı
    // dışıdır) ama cari etkisini artık aynı 'Cari' ödeme yöntemi kuralına
    // göre gerçek/nötr olarak ayırt eder.
    required String odemeYontemi,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    late final int kalemId;

    await db.transaction((txn) async {
      // 1. Stok geri ekle
      final urunRows = await txn.query('urunler',
          columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
      if (urunRows.isNotEmpty) {
        final onceki = (urunRows.first['stok'] as num).toDouble();
        await txn.update('urunler', {'stok': onceki + miktar, 'last_updated': now},
            where: 'id = ?', whereArgs: [urunId]);
        final stokSatiri = {
          'global_id': const Uuid().v4(),
          'urun_id': urunId,
          'hareket_turu': 'Iade Giris',
          'miktar': miktar,
          'onceki_stok': onceki,
          'sonraki_stok': onceki + miktar,
          'tarih': now,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'kullanici_id': kullaniciId,
          'aciklama': 'İade ek kalem - $fisNo',
        };
        final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
        final guncelUrunSatiri = await txn.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (guncelUrunSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'urunler',
              veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
        }
      }

      // 2. iade_kalem: aynı ürün varsa güncelle, yoksa ekle
      final mevcutKalem2 = await txn.rawQuery(
          'SELECT id, miktar, toplam FROM iade_kalem WHERE iade_id=? AND urun_id=?',
          [iadeId, urunId]);
      if (mevcutKalem2.isNotEmpty) {
        final k = mevcutKalem2.first;
        kalemId = k['id'] as int;
        final eskiMiktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        final yeniMiktar = eskiMiktar + miktar;
        final yeniIskTutar = ((k['iskonto_tutar'] as num?)?.toDouble() ?? 0) + iskontoTutar;
        final brutToplam = yeniMiktar * ((k['birim_fiyat'] as num?)?.toDouble() ?? fiyat);
        await txn.rawUpdate(
            'UPDATE iade_kalem SET miktar=?, toplam=?, iskonto_tutar=?, iskonto_oran=?, last_updated=? WHERE id=?', [
          yeniMiktar,
          ((k['toplam'] as num?)?.toDouble() ?? 0) + toplam,
          yeniIskTutar,
          brutToplam > 0 ? (yeniIskTutar / brutToplam * 100).clamp(0, 99.99) : iskontoOran,
          now,
          kalemId
        ]);
      } else {
        kalemId = await txn.insert('iade_kalem', {
          'global_id': const Uuid().v4(),
          'iade_id': iadeId,
          'urun_id': urunId,
          'urun_adi': urunAdi,
          'miktar': miktar,
          'birim_fiyat': fiyat,
          'toplam': toplam,
          'iskonto_oran': iskontoOran,
          'iskonto_tutar': iskontoTutar,
          'last_updated': now,
        });
      }
      final guncelKalemSatiri = await txn.query('iade_kalem',
          where: 'id = ?', whereArgs: [kalemId], limit: 1);
      if (guncelKalemSatiri.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade_kalem', veri: Map<String, dynamic>.from(guncelKalemSatiri.first));
      }

      // 3. İade toplam_tutar güncelle
      final mevcutToplam = (await txn.rawQuery(
              'SELECT COALESCE(SUM(toplam),0) as t FROM iade_kalem WHERE iade_id=?',
              [iadeId]))
          .first['t'] as num? ??
          0;
      await txn.update('iade', {'toplam_tutar': mevcutToplam.toDouble(), 'last_updated': now},
          where: 'id = ?', whereArgs: [iadeId]);
      final guncelIadeSatiri = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelIadeSatiri.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
      }

      // 4. Cari: fis_id bazlı tek kayıt - mevcut varsa güncelle, yoksa ekle
      //
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 sabah): 'Cari'
      // ödeme yöntemi seçilirse (para fiziksel verilmedi) bakiye GERÇEKTEN
      // düzeltilir; 'Nakit'/'Kart/Banka' seçilirse (para zaten fiziksel
      // verildi) cari sadece takip amaçlı nötr kayıt alır — bkz.
      // topluIadeKaydet'teki AYNI kuralın gerekçesi.
      if (cariId != null) {
        final isTedarikci = cariSafTedarikciMi(cariTipi);
        final gercekEtki = odemeYontemi == 'Cari';
        final ekBorc = gercekEtki ? (isTedarikci ? toplam : 0) : toplam;
        final ekAlacak = gercekEtki ? (isTedarikci ? 0 : toplam) : toplam;
        final mevcut = await txn.rawQuery(
            "SELECT id, alacak, borc FROM cari_hareket WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            [iadeId, cariId]);
        if (mevcut.isNotEmpty) {
          final eskiAlacak = (mevcut.first['alacak'] as num?)?.toDouble() ?? 0;
          final eskiBorc = (mevcut.first['borc'] as num?)?.toDouble() ?? 0;
          await txn.rawUpdate(
              "UPDATE cari_hareket SET alacak = ?, borc = ?, last_updated = ? WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
              [
                eskiAlacak + ekAlacak,
                eskiBorc + ekBorc,
                now,
                iadeId,
                cariId,
              ]);
        } else {
          await txn.insert('cari_hareket', {
            'global_id': const Uuid().v4(),
            'cari_id': cariId,
            'tarih': now,
            'fis_tipi': isTedarikci ? 'Alım İadesi' : 'İade',
            'fis_id': iadeId,
            'fis_no': fisNo,
            'aciklama': gercekEtki
                ? '${fisNo ?? ''} — cari bakiyesine işlendi'
                : '${fisNo ?? ''} — bakiyeyi etkilemez',
            'borc': ekBorc,
            'alacak': ekAlacak,
            'odeme_turu': odemeYontemi,
            'kullanici': kullaniciAdi,
          });
        }
        final guncelCariHareketSatirlar = await txn.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId]);
        for (final c in guncelCariHareketSatirlar) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket', veri: Map<String, dynamic>.from(c));
        }
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = ROUND((SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0), 2) WHERE id = ?',
            [cariId, cariId]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }

      // 5. Kasa hareketi — SADECE Nakit iade seçildiyse.
      //
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 — devam turu):
      // bu satır ÖNCEDEN [odemeYontemi] ne olursa olsun KOŞULSUZ bir kasa
      // çıkışı yazıyordu — İade Geçmişi'nde düzenleme moduna girip
      // Kart/Banka VEYA Cari seçerek kalem eklenirse bile kasadan GERÇEKTE
      // hiç çıkmamış bir tutar düşülüyordu (dosyadaki diğer tüm oluşturma
      // fonksiyonlarının — topluIadeKaydet/fisKalemIadeKaydet/
      // manuelKalemEkle — zaten uyduğu 'SADECE Nakit' kuralıyla tutarsızdı).
      if (odemeYontemi == 'Nakit') {
        final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) - toplam;
        final kasaSatiri = {
          'global_id': const Uuid().v4(),
          'hareket_tipi': 'İade',
          'tutar': toplam,
          'bakiye_sonrasi': kasaBakiye,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'tarih': now,
          'sube_id': AktifSubeServisi().subeId,
          'aciklama': 'İade: $fisNo - $urunAdi',
          'kullanici_id': kullaniciId,
        };
        final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
      }
    });

    try {
      final kalemSatir =
          await db.query('iade_kalem', where: 'id = ?', whereArgs: [kalemId], limit: 1);
      if (kalemSatir.isNotEmpty) {
        BulutManager()
            .upsert('iade_kalem', Map<String, dynamic>.from(kalemSatir.first));
      }
      final iadeSatir =
          await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (iadeSatir.isNotEmpty) {
        BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
      }
      final urunSatir =
          await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (urunSatir.isNotEmpty) {
        BulutManager().upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
      }
      final stokSatir = await db.query('stok_hareket',
          where: 'referans_id = ? AND referans_turu = ? AND urun_id = ?',
          whereArgs: [iadeId, 'iade', urunId],
          orderBy: 'id DESC',
          limit: 1);
      if (stokSatir.isNotEmpty) {
        BulutManager()
            .upsert('stok_hareket', Map<String, dynamic>.from(stokSatir.first));
      }
      // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): ek kalem = stok ARTIŞI.
      await _stokDepo.subeStokPayiUygula(urunId, -miktar);
      final kasaSatir = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?',
          whereArgs: [iadeId, 'iade'],
          orderBy: 'id DESC',
          limit: 1);
      if (kasaSatir.isNotEmpty) {
        BulutManager().upsert(
            'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
      }
      if (cariId != null) {
        final cariHareketSatir = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId],
            limit: 1);
        if (cariHareketSatir.isNotEmpty) {
          BulutManager().upsert(
              'cari_hareket', Map<String, dynamic>.from(cariHareketSatir.first));
        }
        final cariSatir =
            await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('İade ek kalem bulut bildirimi hatası: $e');
    }
  }

  /// "İade Geçmişi" sekmesinden TÜM fişi (bir iade kaydının tüm
  /// kalemleri) silme/iptal etme — bkz. iade_ekrani_gecmis.dart.
  /// _gecmisIadeSil (taşındığı yer). Her kalem için stok geri alınır,
  /// GERÇEK yazılmış kasa satırı (varsa) tersine çevrilir, cari
  /// hareketleri soft-delete edilir, iade 'iptal' durumuna işaretlenir.
  ///
  /// [kalemler] çağıranın önceden çektiği ham `iade_kalem` satırları
  /// (en az 'urun_id' ve 'miktar' anahtarlarını içermeli).
  ///
  /// 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 — Satış/Alım
  /// silmede bulunan AYNI hata sınıfı): kasa reversal'ı ÖNCEDEN [toplamTutar]
  /// parametresine bakıp KOŞULSUZ bir "Iade Iptali" (nakit GİRİŞ) kasa
  /// kaydı ekliyordu — orijinal iade GERÇEKTEN nakit olarak mı verilmişti
  /// (topluIadeKaydet/fisKalemIadeKaydet/manuelKalemEkle SADECE
  /// nakitIade==true iken kasa satırı yazar) hiç kontrol edilmiyordu.
  /// Kart/Banka veya Cari'ye işlenmiş bir iade fişi silinince, HİÇ VAR
  /// OLMAMIŞ bir nakit giriş kaydı OLUŞTURULUYOR, kasa mutabakatını
  /// bozuyordu. Artık tahmin yok: bu iadenin GERÇEKTEN yazdığı
  /// kasa_hareketleri satırı (varsa) sorgulanıp SADECE o satırın GERÇEK
  /// tutarıyla tersine çevriliyor.
  Future<void> gecmisFisIadeSil({
    required int iadeId,
    required List<Map<String, dynamic>> kalemler,
    required double toplamTutar,
    required int? cariId,
    String? fisNo,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    String? kasaGid;

    await db.transaction((txn) async {
      // 🆕 İkinci bir giriş noktası eklendi (cari_hareket_ekrani.dart,
      // 2026-09-22) — aynı iade artık İade Geçmişi'nden VEYA Cari
      // Hareketler'den silinebiliyor. Zaten iptal edilmiş bir fişi
      // TEKRAR işlemek stoğu/kasayı İKİNCİ KEZ tersine çevirirdi
      // (AlimIslemServisi.sil()'deki AYNI korumayla hizalandı).
      final guncelIade = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelIade.isNotEmpty && guncelIade.first['durum'] == 'iptal') {
        throw Exception('Bu iade zaten iptal edilmiş.');
      }
      for (final k in kalemler) {
        final urunId = k['urun_id'] as int?;
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        if (urunId == null || miktar <= 0) continue;
        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
        if (urunRows.isEmpty) continue;
        final onceki = (urunRows.first['stok'] as num).toDouble();
        final sonraki = onceki - miktar;
        await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
            where: 'id = ?', whereArgs: [urunId]);
        final stokSatiri = {
          'global_id': const Uuid().v4(),
          'urun_id': urunId,
          'hareket_turu': 'İade İptali',
          'miktar': miktar,
          'onceki_stok': onceki,
          'sonraki_stok': sonraki,
          'tarih': now,
          'referans_id': iadeId,
          'referans_turu': 'iade_iptal',
        };
        final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
        final guncelUrunSatiri = await txn.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (guncelUrunSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'urunler',
              veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
        }
      }

      final orijinalKasaSatirlari = await txn.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ? AND deleted_at IS NULL',
          whereArgs: [iadeId, 'iade']);
      for (final k in orijinalKasaSatirlari) {
        final kasaTutar = (k['tutar'] as num?)?.toDouble() ?? 0;
        if (kasaTutar <= 0) continue;
        kasaGid = const Uuid().v4();
        final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) + kasaTutar;
        final kasaSatiri = {
          'global_id': kasaGid,
          'hareket_tipi': 'Iade Iptali',
          'tutar': kasaTutar, // Pozitif: kasa artar (iade geri alındı)
          'bakiye_sonrasi': kasaBakiye,
          'referans_id': iadeId,
          'referans_turu': 'iade_iptal',
          'tarih': now,
          // 🔴 Derin analizde bulundu: sube_id eksikti (bkz. oturumIadeSil'deki
          // aynı düzeltmenin gerekçesi).
          'sube_id': AktifSubeServisi().subeId,
          'aciklama': 'Iade silindi: $fisNo',
        };
        final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
      }

      if (cariId != null) {
        await txn.rawUpdate(
            "UPDATE cari_hareket SET is_deleted = 1, last_updated = ? WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            [now, iadeId, cariId]);
        final etkilenenCariHareketler = await txn.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId]);
        for (final c in etkilenenCariHareketler) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket', veri: Map<String, dynamic>.from(c));
        }
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = ROUND((SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0), 2) WHERE id = ?',
            [cariId, cariId]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }

      await txn.update('iade', {'durum': 'iptal', 'last_updated': now},
          where: 'id = ?', whereArgs: [iadeId]);
      final guncelIadeSatiri = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelIadeSatiri.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
      }
    });

    try {
      final iadeSatir =
          await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (iadeSatir.isNotEmpty) {
        BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
      }
      for (final k in kalemler) {
        final urunId = k['urun_id'] as int?;
        if (urunId == null) continue;
        final urunSatir =
            await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): tüm fiş iptali = her
        // kalem için stok AZALIŞI (pozitif fark).
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        if (miktar > 0) {
          await _stokDepo.subeStokPayiUygula(urunId, miktar);
        }
      }
      final stokSatirlar = await db.query('stok_hareket',
          where: 'referans_id = ? AND referans_turu = ?',
          whereArgs: [iadeId, 'iade_iptal']);
      for (final s in stokSatirlar) {
        BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(s));
      }
      if (kasaGid != null) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'global_id = ?', whereArgs: [kasaGid], limit: 1);
        if (kasaSatir.isNotEmpty) {
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
      }
      if (cariId != null) {
        final cariHareketSatirlar = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId]);
        for (final c in cariHareketSatirlar) {
          BulutManager().upsert('cari_hareket', Map<String, dynamic>.from(c));
        }
        final cariSatir =
            await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Fiş silme bulut bildirimi hatası: $e');
    }
  }

  /// "Manuel" (ürün seç + miktar/fiyat gir) sekmesindeki kaydetme akışı —
  /// bkz. iade_ekrani.dart._kaydet (taşındığı yer, sadece "yeni oturum
  /// başlat / mevcut oturuma ekle" dalı — düzenleme modu dalı zaten
  /// IadeIslemServisi.duzenlemeModuKalemEkle'yi kullanıyor). Bir oturumda
  /// aynı ürün tekrar eklenirse iade_kalem satırı TOPLANARAK güncellenir
  /// (yeni satır açılmaz). iade + kalem + stok + (varsa) kasa + (varsa)
  /// cari TEK transaction içinde.
  ///
  /// Döner: yeni oluşturulan veya güncellenen iadeId — [oturumIadeId]
  /// null ise çağıran taraf bunu oturumun kalıcı iade id'si olarak
  /// saklamalı.
  Future<int> manuelKalemEkle({
    required int? oturumIadeId,
    required int? cariId,
    required String? cariTipi,
    required String fisNo,
    required int urunId,
    required String urunAdi,
    required double miktar,
    required double fiyat,
    required double toplam,
    required String neden,
    required String odemeYontemi,
    required int? kullaniciId,
    required String kullaniciAdi,
    /// İndirim % (0-100). [fiyat] indirimsiz birim fiyat, [toplam] NET tutardır
    /// (miktar × fiyat × (1 − indirim)). iade_kalem'e KAYDEDİLİR ve senkronlanır.
    double iskontoOran = 0,
  }) async {
    final db = await Veritabani().db;
    final isTedarikci = cariSafTedarikciMi(cariTipi);
    final now = DateTime.now().toIso8601String();
    int iadeId = oturumIadeId ?? 0;
    final iskontoTutar = iskontoOran > 0 && iskontoOran < 100
        ? ((miktar * fiyat * iskontoOran / 100) * 100).round() / 100
        : 0.0;

    await db.transaction((txn) async {
      // 1. İade kaydı
      if (oturumIadeId != null) {
        // last_updated İLERLETİLİR: aksi halde bulut/diğer cihaz imleci bu
        // değişikliği hiç çekmez (bkz. senkron denetimi 2026-10-07).
        await txn.rawUpdate(
            'UPDATE iade SET toplam_tutar = toplam_tutar + ?, iade_nedeni = ?, last_updated = ? WHERE id = ?',
            [toplam, neden, now, iadeId]);
      } else {
        iadeId = await txn.insert('iade', {
          'global_id': const Uuid().v4(),
          'cari_id': cariId,
          'fis_no': fisNo,
          'tarih': now,
          'toplam_tutar': toplam,
          'iade_nedeni': neden,
          'durum': 'tamamlandi',
          'kasiyer_id': kullaniciId,
          'last_updated': now,
        });
      }
      final guncelIadeSatiri = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelIadeSatiri.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
      }

      // 2. İade kalem
      final mevcutKalem = await txn.rawQuery(
          'SELECT id, miktar, toplam, birim_fiyat, iskonto_tutar FROM iade_kalem WHERE iade_id=? AND urun_id=?',
          [iadeId, urunId]);
      if (mevcutKalem.isNotEmpty) {
        final k = mevcutKalem.first;
        final yeniMiktar = ((k['miktar'] as num?)?.toDouble() ?? 0) + miktar;
        final yeniIskTutar = ((k['iskonto_tutar'] as num?)?.toDouble() ?? 0) + iskontoTutar;
        final brut = yeniMiktar * ((k['birim_fiyat'] as num?)?.toDouble() ?? fiyat);
        await txn.rawUpdate(
            'UPDATE iade_kalem SET miktar=?, toplam=?, iskonto_tutar=?, iskonto_oran=?, last_updated=? WHERE id=?', [
          yeniMiktar,
          ((k['toplam'] as num?)?.toDouble() ?? 0) + toplam,
          yeniIskTutar,
          brut > 0 ? (yeniIskTutar / brut * 100).clamp(0, 99.99) : iskontoOran,
          now,
          k['id']
        ]);
      } else {
        await txn.insert('iade_kalem', {
          'global_id': const Uuid().v4(),
          'iade_id': iadeId,
          'urun_id': urunId,
          'urun_adi': urunAdi,
          'miktar': miktar,
          'birim_fiyat': fiyat,
          'toplam': toplam,
          'iskonto_oran': iskontoOran,
          'iskonto_tutar': iskontoTutar,
          'last_updated': now,
        });
      }
      final guncelKalemSatir = await txn.query('iade_kalem',
          where: 'iade_id = ? AND urun_id = ?',
          whereArgs: [iadeId, urunId], limit: 1);
      if (guncelKalemSatir.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade_kalem', veri: Map<String, dynamic>.from(guncelKalemSatir.first));
      }

      // 3. Stok geri ekle
      final urunRows = await txn.query('urunler',
          columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
      if (urunRows.isNotEmpty) {
        final onceki = (urunRows.first['stok'] as num).toDouble();
        await txn.update('urunler', {'stok': onceki + miktar, 'last_updated': now},
            where: 'id = ?', whereArgs: [urunId]);
        final stokSatiri = {
          'global_id': const Uuid().v4(),
          'urun_id': urunId,
          'hareket_turu': 'Iade Giris',
          'miktar': miktar,
          'onceki_stok': onceki,
          'sonraki_stok': onceki + miktar,
          'tarih': now,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'kullanici_id': kullaniciId,
          'aciklama': 'Iade: $fisNo',
          'last_updated': now,
        };
        final stokHareketId = await txn.insert('stok_hareket', stokSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'stok_hareket', veri: {...stokSatiri, 'id': stokHareketId});
        final guncelUrunSatiri = await txn.query('urunler',
            where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (guncelUrunSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'urunler',
              veri: Map<String, dynamic>.from(guncelUrunSatiri.first));
        }
      }

      // 4. Kasa — SADECE Nakit iade seçildiyse. KasaDeposu ile AYNI
      // güvenli bakiye sorgusu (deleted_at IS NULL + tarih DESC).
      if (odemeYontemi == 'Nakit') {
        final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) - toplam;
        final kasaSatiri = {
          'global_id': const Uuid().v4(),
          'hareket_tipi': 'Iade',
          'tutar': toplam,
          'bakiye_sonrasi': kasaBakiye,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'tarih': now,
          'sube_id': AktifSubeServisi().subeId,
          'aciklama': 'Iade: $fisNo - $urunAdi',
          'kullanici_id': kullaniciId,
        };
        final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
      }

      // 5. Cari — fis_tipi ile de kontrol edilir: 'iade' ve 'satislar'
      // tablolarının BAĞIMSIZ sayaçları tesadüfen aynı id'yi üretebilir.
      //
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı kararı, 2026-09-22 sabah) — bkz.
      // topluIadeKaydet'teki AYNI düzeltmenin gerekçesi: 'Cari' ödeme
      // yöntemi seçilirse (para fiziksel verilmedi) bakiye GERÇEKTEN
      // düzeltilir; 'Nakit'/'Kart/Banka' seçilirse (para zaten fiziksel
      // verildi) cari sadece takip amaçlı nötr kayıt alır. odemeYontemi
      // TEK seçimli dropdown olduğundan çift-iade riski yok.
      if (cariId != null) {
        final gercekEtki = odemeYontemi == 'Cari';
        final yeniBorc = gercekEtki ? (isTedarikci ? toplam : 0) : toplam;
        final yeniAlacak = gercekEtki ? (isTedarikci ? 0 : toplam) : toplam;
        final mevcut = await txn.rawQuery(
            "SELECT id, alacak, borc FROM cari_hareket WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            [iadeId, cariId]);
        if (mevcut.isNotEmpty) {
          final eskiAlacak = (mevcut.first['alacak'] as num?)?.toDouble() ?? 0;
          final eskiBorc = (mevcut.first['borc'] as num?)?.toDouble() ?? 0;
          await txn.rawUpdate(
              "UPDATE cari_hareket SET alacak=?, borc=?, last_updated=? WHERE fis_id=? AND cari_id=? AND fis_tipi IN ('İade','Alım İadesi')",
              [eskiAlacak + yeniAlacak, eskiBorc + yeniBorc, now, iadeId, cariId]);
        } else {
          await txn.insert('cari_hareket', {
            'global_id': const Uuid().v4(),
            'cari_id': cariId,
            'tarih': now,
            'fis_tipi': isTedarikci ? 'Alım İadesi' : 'İade',
            'fis_id': iadeId,
            'fis_no': fisNo,
            'aciklama': gercekEtki
                ? '$fisNo — cari bakiyesine işlendi'
                : '$fisNo — bakiyeyi etkilemez',
            'borc': yeniBorc,
            'alacak': yeniAlacak,
            'odeme_turu': odemeYontemi,
            'kullanici': kullaniciAdi,
          });
        }
        final guncelCariHareketSatir = await txn.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId], limit: 1);
        if (guncelCariHareketSatir.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket',
              veri: Map<String, dynamic>.from(guncelCariHareketSatir.first));
        }
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = ROUND((SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0), 2) WHERE id=?',
            [cariId, cariId]);
        final guncelCariSatiri = await txn.query('cari',
            where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (guncelCariSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
        }
      }
    });

    // Transaction kapandıktan sonra buluta bildir — 7 farklı tablo
    // (iade, iade_kalem, urunler, stok_hareket, kasa_hareketleri,
    // cari_hareket, cari) değişebilir, her birinin EN SON değişen
    // satırı sorgulanıp bildirilir.
    try {
      final iadeSatir =
          await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (iadeSatir.isNotEmpty) {
        BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
      }
      final kalemSatir = await db.query('iade_kalem',
          where: 'iade_id = ? AND urun_id = ?',
          whereArgs: [iadeId, urunId],
          limit: 1);
      if (kalemSatir.isNotEmpty) {
        BulutManager()
            .upsert('iade_kalem', Map<String, dynamic>.from(kalemSatir.first));
      }
      final urunSatir =
          await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (urunSatir.isNotEmpty) {
        BulutManager().upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
      }
      final stokSatir = await db.query('stok_hareket',
          where: 'referans_id = ? AND referans_turu = ?',
          whereArgs: [iadeId, 'iade'],
          orderBy: 'id DESC',
          limit: 1);
      if (stokSatir.isNotEmpty) {
        BulutManager()
            .upsert('stok_hareket', Map<String, dynamic>.from(stokSatir.first));
      }
      // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): manuel iade = stok ARTIŞI.
      await _stokDepo.subeStokPayiUygula(urunId, -miktar);
      final kasaSatir = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?',
          whereArgs: [iadeId, 'iade'],
          orderBy: 'id DESC',
          limit: 1);
      if (kasaSatir.isNotEmpty) {
        BulutManager().upsert(
            'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
      }
      if (cariId != null) {
        final cariHareketSatir = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            whereArgs: [iadeId, cariId],
            limit: 1);
        if (cariHareketSatir.isNotEmpty) {
          BulutManager().upsert(
              'cari_hareket', Map<String, dynamic>.from(cariHareketSatir.first));
        }
        final cariSatir =
            await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
        if (cariSatir.isNotEmpty) {
          BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('İade bulut bildirimi hatası: $e');
    }

    return iadeId;
  }
}
