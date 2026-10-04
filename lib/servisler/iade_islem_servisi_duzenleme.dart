// lib/servisler/iade_islem_servisi_duzenleme.dart
//
// iade_islem_servisi.dart'ın parçası (part/part of) — oturum iadesi silme/düzenleme.
// Davranış BİREBİR aynı: IadeIslemServisi üzerine extension; private
// üyelere (_kasaDepo, _stokDepo...) aynı kütüphane olduğu için erişir.
part of 'iade_islem_servisi.dart';

extension IadeIslemServisiDuzenleme on IadeIslemServisi {
  /// "İade Geçmişi" sekmesinden bir iade kalemini silme/iptal etme —
  /// bkz. iade_ekrani_gecmis.dart._oturumIadeSil (taşındığı yer). Stok
  /// geri alınır (İade İptali stok_hareket kaydıyla), iade 'iptal'
  /// durumuna işaretlenir (hard-delete yok), varsa kasa/cari ters
  /// çevrilir.
  Future<void> oturumIadeSil({
    required int? iadeId,
    required int? urunId,
    required double miktar,
    required double toplam,
    required int? cariId,
    String? fisNo,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    String? kasaGid;

    await db.transaction((txn) async {
      if (urunId != null && miktar > 0) {
        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
        if (urunRows.isNotEmpty) {
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
      }
      if (iadeId != null) {
        await txn.update('iade', {'durum': 'iptal', 'last_updated': now},
            where: 'id = ?', whereArgs: [iadeId]);
        final guncelIadeSatiri = await txn.query('iade',
            where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (guncelIadeSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
        }
      }
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 sabah —
      // gecmisFisIadeSil'de zaten düzeltilmiş AYNI hata sınıfı): burası
      // ÖNCEDEN [toplam] parametresine bakıp KOŞULSUZ bir "Iade Iptali"
      // (nakit GİRİŞ) kasa kaydı ekliyordu — orijinal iade GERÇEKTEN
      // nakit olarak mı verilmişti (sadece odemeYontemi=='Nakit' iken
      // kasa satırı yazılır) hiç kontrol edilmiyordu. Kart/Banka veya
      // Cari'ye işlenmiş bir iade silinince HİÇ VAR OLMAMIŞ bir nakit
      // giriş kaydı oluşuyor, kasa mutabakatını bozuyordu. Artık gerçekten
      // yazılmış kasa_hareketleri satırı (varsa) sorgulanıp SADECE o
      // satırın GERÇEK tutarıyla tersine çevriliyor.
      if (iadeId != null) {
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
            'tutar': kasaTutar,
            'bakiye_sonrasi': kasaBakiye,
            'referans_id': iadeId,
            'referans_turu': 'iade_iptal',
            'tarih': now,
            'sube_id': AktifSubeServisi().subeId,
            'aciklama': 'İade silindi: $fisNo',
          };
          final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
        }
      }
      // Bu DELETE (rawUpdate soft-delete) fis_tipi ile de sınırlı —
      // 'iade' ve 'satislar' tablolarının BAĞIMSIZ, tesadüfen aynı ID'yi
      // üretebilen sayaçları yüzünden fis_tipi kontrolsüz bir SATIŞIN
      // cari_hareket kaydını yanlışlıkla silebilirdi.
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
    });

    try {
      if (iadeId != null) {
        final iadeSatir =
            await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (iadeSatir.isNotEmpty) {
          BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
        }
      }
      if (urunId != null) {
        final urunSatir =
            await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        final stokSatir = await db.query('stok_hareket',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade_iptal'],
            orderBy: 'id DESC',
            limit: 1);
        if (stokSatir.isNotEmpty) {
          BulutManager()
              .upsert('stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        }
        // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): iade iptali = stok
        // AZALIŞI (pozitif fark — subeStokPayiUygula'nın beklediği yön).
        await _stokDepo.subeStokPayiUygula(urunId, miktar);
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
      if (kDebugMode) debugPrint('İade silme bulut bildirimi hatası: $e');
    }
  }

  /// "İade Geçmişi" sekmesinde mevcut bir iade kaleminin miktar/fiyat/
  /// iskonto/açıklamasını düzenleme — bkz.
  /// iade_ekrani_gecmis.dart._oturumIadeDuzenle (taşındığı yer). Stok
  /// farkı (yeni-eski miktar) uygulanır, iade+iade_kalem güncellenir,
  /// kasa farkı (varsa) ayrı bir "İade Düzeltme" hareketiyle işlenir,
  /// cari eski hareketleri soft-delete edilip yeni toplamla tek hareket
  /// yazılır.
  Future<void> oturumIadeDuzenle({
    required int? iadeId,
    required int? urunId,
    required int? cariId,
    required String? fisNo,
    required String urunAdi,
    required double eskiMiktar,
    required double eskiToplam,
    required double yeniMiktar,
    required double yeniFiyat,
    required double yeniToplam,
    required String yeniAciklama,
  }) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    final fark = yeniMiktar - eskiMiktar;
    String? kasaGid;

    await db.transaction((txn) async {
      if (urunId != null && fark != 0) {
        final urunRows = await txn.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
        if (urunRows.isNotEmpty) {
          final onceki = (urunRows.first['stok'] as num).toDouble();
          final sonraki = onceki + fark;
          await txn.update('urunler', {'stok': sonraki, 'last_updated': now},
              where: 'id = ?', whereArgs: [urunId]);
          final stokSatiri = {
            'global_id': const Uuid().v4(),
            'urun_id': urunId,
            'hareket_turu': 'İade Düzeltme',
            'miktar': fark.abs(),
            'onceki_stok': onceki,
            'sonraki_stok': sonraki,
            'tarih': now,
            'referans_id': iadeId,
            'referans_turu': 'iade_duzenle',
            'aciklama': 'İade miktarı değiştirildi',
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
      }
      if (iadeId != null) {
        await txn.update(
            'iade',
            {
              'toplam_tutar': yeniToplam,
              'iade_nedeni': yeniAciklama,
              'last_updated': now
            },
            where: 'id = ?',
            whereArgs: [iadeId]);
        await txn.rawUpdate(
            'UPDATE iade_kalem SET miktar=?, birim_fiyat=?, toplam=?, last_updated=? WHERE iade_id=?',
            [yeniMiktar, yeniFiyat, yeniToplam, now, iadeId]);
        final guncelIadeSatiri = await txn.query('iade',
            where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (guncelIadeSatiri.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'iade', veri: Map<String, dynamic>.from(guncelIadeSatiri.first));
        }
        final guncelKalemSatirlar = await txn.query('iade_kalem',
            where: 'iade_id = ?', whereArgs: [iadeId]);
        for (final k in guncelKalemSatirlar) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'iade_kalem', veri: Map<String, dynamic>.from(k));
        }
      }
      final tutarFark = yeniToplam - eskiToplam;
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22 sabah): burası
      // ÖNCEDEN tutarFark'a bakıp KOŞULSUZ kasa düzeltmesi yazıyordu —
      // orijinal iade GERÇEKTEN nakit olarak mı verilmişti hiç kontrol
      // edilmiyordu (bkz. oturumIadeSil'deki AYNI hata sınıfının
      // düzeltmesi). Kart/Banka veya Cari'ye işlenmiş bir iade kalemi
      // düzenlenince kasada hiç var olmamış bir hareket oluşuyordu.
      if (tutarFark.abs() > 0.01 && iadeId != null) {
        final orijinalKasaVarMi = await txn.query('kasa_hareketleri',
            where:
                "referans_id = ? AND referans_turu = 'iade' AND deleted_at IS NULL",
            whereArgs: [iadeId], limit: 1);
        if (orijinalKasaVarMi.isNotEmpty) {
          final oncekiBakiye = await _kasaDepo.sonBakiyeTxn(txn);
          final yeniBakiye = oncekiBakiye + tutarFark;
          kasaGid = const Uuid().v4();
          final kasaSatiri = {
            'global_id': kasaGid,
            'hareket_tipi': 'İade Düzeltme',
            'tutar': tutarFark,
            'bakiye_sonrasi': yeniBakiye,
            'referans_id': iadeId,
            'referans_turu': 'iade_duzeltme',
            'tarih': now,
            'sube_id': AktifSubeServisi().subeId,
            'aciklama': 'İade düzeltme: $fisNo',
          };
          final kasaId = await txn.insert('kasa_hareketleri', kasaSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'kasa_hareketleri', veri: {...kasaSatiri, 'id': kasaId});
        }
      }
      if (cariId != null && iadeId != null) {
        final cariRows = await txn
            .rawQuery('SELECT cari_tipi FROM cari WHERE id = ?', [cariId]);
        final cariTipiDuz = cariRows.isNotEmpty
            ? (cariRows.first['cari_tipi'] as String? ?? '')
            : '';
        final isTedarikciDuz = cariSafTedarikciMi(cariTipiDuz);

        // Bu iade kalemi GERÇEK cari etkisiyle mi (Veresiye/'Cari' ödeme
        // yöntemi) yoksa NÖTR (Nakit/Kart, sadece takip) mi yazılmıştı?
        // borc==alacak ise nötrdü — düzenlemede de nötr kalmalı, aksi
        // halde para fiziksel verilmişken bakiye de düşer (çift iade).
        final eskiSatir = await txn.rawQuery(
            "SELECT borc, alacak FROM cari_hareket WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi') AND is_deleted = 0",
            [iadeId, cariId]);
        final eskiBorcD =
            eskiSatir.isNotEmpty ? (eskiSatir.first['borc'] as num?)?.toDouble() ?? 0 : 0;
        final eskiAlacakD = eskiSatir.isNotEmpty
            ? (eskiSatir.first['alacak'] as num?)?.toDouble() ?? 0
            : 0;
        final gercekEtki = eskiSatir.isNotEmpty && eskiBorcD != eskiAlacakD;

        await txn.rawUpdate(
            "UPDATE cari_hareket SET is_deleted = 1, last_updated = ? WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
            [now, iadeId, cariId]);
        if (yeniToplam > 0) {
          final cariHareketSatiri = {
            'global_id': const Uuid().v4(),
            'cari_id': cariId,
            'tarih': now,
            'fis_tipi': isTedarikciDuz ? 'Alım İadesi' : 'İade',
            'fis_id': iadeId,
            'fis_no': fisNo,
            'aciklama': gercekEtki
                ? '$urunAdi - $fisNo — cari bakiyesine işlendi'
                : '$urunAdi - $fisNo — bakiyeyi etkilemez',
            'borc': gercekEtki ? (isTedarikciDuz ? yeniToplam : 0) : yeniToplam,
            'alacak': gercekEtki ? (isTedarikciDuz ? 0 : yeniToplam) : yeniToplam,
            'odeme_turu': gercekEtki ? 'Cari' : 'Nakit',
          };
          final cariHareketId = await txn.insert('cari_hareket', cariHareketSatiri);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket', veri: {...cariHareketSatiri, 'id': cariHareketId});
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
    });

    try {
      if (iadeId != null) {
        final iadeSatir =
            await db.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (iadeSatir.isNotEmpty) {
          BulutManager().upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
        }
        final kalemSatirlar =
            await db.query('iade_kalem', where: 'iade_id = ?', whereArgs: [iadeId]);
        for (final k in kalemSatirlar) {
          BulutManager().upsert('iade_kalem', Map<String, dynamic>.from(k));
        }
      }
      if (urunId != null) {
        final urunSatir =
            await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        final stokSatir = await db.query('stok_hareket',
            where: 'referans_id = ? AND referans_turu = ?',
            whereArgs: [iadeId, 'iade_duzenle'],
            orderBy: 'id DESC',
            limit: 1);
        if (stokSatir.isNotEmpty) {
          BulutManager()
              .upsert('stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        }
        // 🔴 FAZ 1 (DEEP_AUDIT_REPORT madde 1): şube payı hiç
        // güncellenmiyordu. fark>0 = ana stok ARTTI, bu yüzden ters işaret.
        await _stokDepo.subeStokPayiUygula(urunId, -fark);
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
      if (kDebugMode) debugPrint('İade düzenleme bulut bildirimi hatası: $e');
    }
  }

}
