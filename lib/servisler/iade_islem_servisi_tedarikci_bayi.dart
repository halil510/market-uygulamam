// lib/servisler/iade_islem_servisi_tedarikci_bayi.dart
//
// iade_islem_servisi.dart'ın parçası (part/part of) — TEDARİKÇİYE ve
// BAYİDEN iade. İki akışın para/stok yönü birbirinin TERSİDİR:
//
//                    Fiyat                         Stok      Cari
//   Tedarikçi iade   son alış maliyeti (KDV dahil) AZALIR    tedarikçiye borcumuz düşer (borç+)
//   Bayi iade        bayiye özel toptan fiyatı     ARTAR     bayinin borcu düşer (alacak+)
//
// Bugünkü perakende raf fiyatı HİÇBİRİNDE kullanılmaz.
//
// Kayıt yeri: bayi iadesi bir SATIŞ iadesidir → mevcut `iade`/`iade_kalem`
// (İade Geçmişi'ndeki düzenleme/silme mantığı ve iade raporları doğru
// çalışır). Tedarikçi iadesi bir ALIŞ iadesidir → ayrı `tedarikci_iadeler`/
// `tedarikci_iade_kalem` (bkz. TedarikSemasi.iadeTablolariniOlustur —
// `iade`'de dursaydı müşteri iadesi gibi ters yönde işlenirdi).
//
// Her iki akış da belge + kalemler + stok + cari'yi TEK transaction'da
// yazar (ya hepsi ya hiçbiri); senkron kuyruğu kayıtları aynı transaction'da,
// anlık bulut bildirimi ve şube stok payı commit'ten SONRA.
//
// 🔴 YENİ (2026-10-13, kullanıcı isteği — "tedarikçi/bayi iadesi de tek
// fiş altında toplansın"): İlk kayıtta belge açan `tedarikciyeIadeEt` /
// `bayidenIadeAl` metotlarının yanına MEVCUT belgeye kalem ekleyen
// `tedarikciIadeyeKalemEkle` / `bayiIadeyeKalemEkle` metotları eklendi.
// Böylece hem ekranda hem veritabanında tek fiş modeli uygulanır (müşteri
// iadesindeki `_oturumIadeId` deseninin aynısı).
part of 'iade_islem_servisi.dart';

/// Tedarikçi/bayi iadesinde bir satır: hangi üründen ne kadar.
class IadeMiktari {
  final int urunId;
  final double miktar;
  const IadeMiktari({required this.urunId, required this.miktar});
}

/// Kaydedilen tedarikçi/bayi iadesinin özeti.
class CariIadeSonucu {
  final int iadeId;
  final String fisNo;

  /// Cari bakiyesine işlenen tutar (tedarikçide KDV dahil).
  final double toplamTutar;

  /// Ürün id → iade birim fiyatı (tedarikçide KDV DAHİL birim maliyet).
  final Map<int, double> birimFiyatlar;

  const CariIadeSonucu({
    required this.iadeId,
    required this.fisNo,
    required this.toplamTutar,
    required this.birimFiyatlar,
  });
}

/// İade isteği iş kurallarına uymuyor (ör. cari tedarikçi değil, ürünün
/// maliyeti tanımsız). Mesaj doğrudan kullanıcıya gösterilebilir.
class IadeGecersizHatasi implements Exception {
  final String mesaj;
  const IadeGecersizHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Fiyatı belirlenmiş tek bir iade satırı.
typedef _FiyatliKalem = ({
  int urunId,
  String urunAdi,
  double miktar,
  double birimFiyat, // tedarikçide KDV hariç maliyet; bayide satış fiyatı
  double kdvOran, // yalnız tedarikçi
  double toplam, // cariye işlenen satır tutarı
});

extension IadeIslemServisiTedarikciBayi on IadeIslemServisi {
  // ── Tedarikçiye iade ─────────────────────────────────────────────────

  /// [tedarikci]ye mal iade eder: stok AZALIR (eksiye düşebilir — B2),
  /// tedarikçiye olan borcumuz iade tutarı kadar DÜŞER. Fiyat: ürünün son
  /// alış fiyatı (KDV dahil — alım tedarikçiye borcu KDV dahil yazdığı
  /// için). Maliyeti tanımsız ürün varsa [IadeGecersizHatasi].
  Future<CariIadeSonucu> tedarikciyeIadeEt({
    required CariModel tedarikci,
    required List<IadeMiktari> kalemler,
    required int? kullaniciId,
    required String kullaniciAdi,
    String? aciklama,
  }) async {
    final cariId = _cariIdDogrula(tedarikci);
    if (!cariTedarikciOlabilirMi(tedarikci.cariTipi)) {
      throw IadeGecersizHatasi('${tedarikci.unvan} bir tedarikçi değil — '
          'tedarikçiye iade yalnız tedarikçi carilere yapılabilir.');
    }
    final miktarlar = _miktarlariBirlestir(kalemler);
    final db = await Veritabani().db;
    // Maliyet dayanağı fiş no tüketilmeden doğrulanır; asıl hesap yazmayla
    // aynı transaction'da tekrarlanır.
    await _tedarikciMaliyetleriTxn(db, miktarlar);
    final subeId = AktifSubeServisi().subeId;
    final fisNo = await Veritabani().fisNoUret('tedarikci_iade', subeId: subeId ?? 1);
    final now = DateTime.now().toIso8601String();
    final iadeGid = const Uuid().v4();
    final kalemGidler = <String>[];
    final stokGidler = <String>[];
    late final int iadeId;
    late final List<_FiyatliKalem> satirlar;
    late final double toplam;
    late final String cariHareketGid;

    await db.transaction((txn) async {
      satirlar = await _tedarikciMaliyetleriTxn(txn, miktarlar);
      toplam = _toplam(satirlar);

      final baslik = {
        'global_id': iadeGid,
        'cari_id': cariId,
        'iade_no': fisNo,
        'tarih': now,
        'toplam_tutar': toplam,
        'aciklama': aciklama,
        'olusturan_id': kullaniciId,
        'sube_id': subeId,
        'last_updated': now,
      };
      iadeId = await txn.insert(DbSabitler.tedarikciIadeler, baslik);
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: DbSabitler.tedarikciIadeler, veri: {...baslik, 'id': iadeId});

      for (final s in satirlar) {
        final kalemGid = const Uuid().v4();
        kalemGidler.add(kalemGid);
        final kalem = {
          'global_id': kalemGid,
          'iade_id': iadeId,
          'urun_id': s.urunId,
          'urun_adi': s.urunAdi,
          'miktar': s.miktar,
          'birim_fiyat': s.birimFiyat,
          'kdv_oran': s.kdvOran,
          'toplam_tutar': s.toplam,
          'last_updated': now,
        };
        final kalemId = await txn.insert(DbSabitler.tedarikciIadeKalem, kalem);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: DbSabitler.tedarikciIadeKalem, veri: {...kalem, 'id': kalemId});

        stokGidler.addAll(await _stokDepo.stokDusFefoTxn(
          txn,
          urunId: s.urunId,
          miktar: s.miktar,
          kullaniciId: kullaniciId,
          referansId: iadeId,
          referansTuru: 'tedarikci_iade',
          aciklama: 'Tedarikçi iadesi: $fisNo',
          hareketTuru: 'Tedarikçi İadesi',
        ));
      }

      // Tedarikçinin bakiyesi (borç − alacak) alımda alacak+ ile eksiye
      // iner; iade BORÇ+ yazılarak ona olan borcumuz azaltılır.
      cariHareketGid = await CariDeposu().hareketEkleTxn(
          txn,
          CariHareketModel(
            cariId: cariId,
            tarih: DateTime.parse(now),
            fisTipi: 'Tedarikçi İadesi',
            fisId: iadeId,
            fisNo: fisNo,
            aciklama: 'Tedarikçiye iade: $fisNo — borcumuzdan düşüldü',
            borc: toplam,
            odemeTuru: 'Cari',
            kullanici: kullaniciAdi,
          ));
    });

    await _iadeSonrasiBildir(db, [
      (DbSabitler.tedarikciIadeler, [iadeGid]),
      (DbSabitler.tedarikciIadeKalem, kalemGidler),
      ('stok_hareket', stokGidler),
      ('cari_hareket', [cariHareketGid]),
    ], urunIdler: miktarlar.keys, cariId: cariId);
    // Şube payı: stok DÜŞTÜ → pozitif fark (subeStokPayiUygula yön kuralı).
    for (final s in satirlar) {
      await _stokDepo.subeStokPayiUygula(s.urunId, s.miktar);
    }

    return CariIadeSonucu(
      iadeId: iadeId,
      fisNo: fisNo,
      toplamTutar: toplam,
      birimFiyatlar: {
        for (final s in satirlar) s.urunId: ParaUtils.yuvarla(s.toplam / s.miktar),
      },
    );
  }

  // ── 🆕 TEK FİŞ MODELİ: mevcut tedarikçi iadesine kalem ekle ──────────
  /// 🔴 YENİ (2026-10-13): Mevcut bir tedarikçi iadesine YENİ kalem ekler.
  /// Belge açılmaz; başlık aynen kalır. Aynı ürün zaten varsa kalem
  /// satırı TOPLANIR (yeni satır açılmaz). Cari_hareket satırı toplanarak
  /// güncellenir (fis_tipi='Tedarikçi İadesi' + fis_id eşleşmesi). Stok
  /// AZALIR (tedarikçiye giden mal). Kasa hareketi YOKTUR (tedarikçi
  /// iadesi kasadan para çıkışı değildir — borç/alacak kaydıdır).
  ///
  /// Cari bakiye her seferinde `SUM(borç) − SUM(alacak)` formülüyle
  /// yeniden hesaplanır; elle bakiye yazımı yoktur → tutarsızlık imkânsız.
  Future<CariIadeSonucu> tedarikciIadeyeKalemEkle({
    required int iadeId,
    required CariModel tedarikci,
    required List<IadeMiktari> kalemler,
    required int? kullaniciId,
    required String kullaniciAdi,
    String? aciklama,
  }) async {
    final cariId = _cariIdDogrula(tedarikci);
    if (!cariTedarikciOlabilirMi(tedarikci.cariTipi)) {
      throw IadeGecersizHatasi('${tedarikci.unvan} bir tedarikçi değil.');
    }
    final miktarlar = _miktarlariBirlestir(kalemler);
    final db = await Veritabani().db;
    // Maliyet dayanağı önceden doğrulanır (boşa transaction açılmasın).
    await _tedarikciMaliyetleriTxn(db, miktarlar);

    final now = DateTime.now().toIso8601String();
    final stokGidler = <String>[];
    final kalemGidler = <String>[];
    late final List<_FiyatliKalem> satirlar;
    late final double ekToplam;
    late final String fisNo;
    late final double yeniToplam;
    late final String cariHareketGid;

    await db.transaction((txn) async {
      // Belge kontrolü
      final baslik = await txn.query(DbSabitler.tedarikciIadeler,
          where: 'id = ? AND COALESCE(is_deleted, 0) = 0',
          whereArgs: [iadeId],
          limit: 1);
      if (baslik.isEmpty) {
        throw const IadeGecersizHatasi('Tedarikçi iadesi bulunamadı.');
      }
      fisNo = (baslik.first['iade_no'] as String?) ?? '#$iadeId';
      final eskiToplam =
          (baslik.first['toplam_tutar'] as num?)?.toDouble() ?? 0;

      // Maliyetleri oku (stok düşme + kalem ekleme aynı transaction içinde)
      satirlar = await _tedarikciMaliyetleriTxn(txn, miktarlar);
      ekToplam = _toplam(satirlar);
      yeniToplam = ParaUtils.yuvarla(eskiToplam + ekToplam);

      for (final s in satirlar) {
        // Aynı ürün varsa mevcut kalem satırını topla, yoksa ekle.
        final mevcut = await txn.query(DbSabitler.tedarikciIadeKalem,
            where: 'iade_id = ? AND urun_id = ?',
            whereArgs: [iadeId, s.urunId],
            limit: 1);
        if (mevcut.isNotEmpty) {
          final eskiMiktar = (mevcut.first['miktar'] as num?)?.toDouble() ?? 0;
          final eskiKalemToplam =
              (mevcut.first['toplam_tutar'] as num?)?.toDouble() ?? 0;
          await txn.rawUpdate(
              'UPDATE ${DbSabitler.tedarikciIadeKalem} '
              'SET miktar = ?, toplam_tutar = ?, last_updated = ? WHERE id = ?',
              [
                eskiMiktar + s.miktar,
                ParaUtils.yuvarla(eskiKalemToplam + s.toplam),
                now,
                mevcut.first['id'],
              ]);
          final guncel = await txn.query(DbSabitler.tedarikciIadeKalem,
              where: 'id = ?', whereArgs: [mevcut.first['id']], limit: 1);
          if (guncel.isNotEmpty) {
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: DbSabitler.tedarikciIadeKalem,
                veri: Map<String, dynamic>.from(guncel.first));
          }
        } else {
          final kalemGid = const Uuid().v4();
          kalemGidler.add(kalemGid);
          final kalem = {
            'global_id': kalemGid,
            'iade_id': iadeId,
            'urun_id': s.urunId,
            'urun_adi': s.urunAdi,
            'miktar': s.miktar,
            'birim_fiyat': s.birimFiyat,
            'kdv_oran': s.kdvOran,
            'toplam_tutar': s.toplam,
            'last_updated': now,
          };
          final kalemId = await txn.insert(DbSabitler.tedarikciIadeKalem, kalem);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: DbSabitler.tedarikciIadeKalem,
              veri: {...kalem, 'id': kalemId});
        }

        // Stok AZALIR (mevcut tedarikciyeIadeEt ile aynı yön + aynı
        // referans_turu='tedarikci_iade' — iptal akışı bu referansla geri
        // alır, tüm hareketleri bulur).
        stokGidler.addAll(await _stokDepo.stokDusFefoTxn(
          txn,
          urunId: s.urunId,
          miktar: s.miktar,
          kullaniciId: kullaniciId,
          referansId: iadeId,
          referansTuru: 'tedarikci_iade',
          aciklama: 'Tedarikçi iadesi (ek kalem): $fisNo',
          hareketTuru: 'Tedarikçi İadesi',
        ));
      }

      // Başlık toplam_tutar güncelle (opsiyonel açıklama da yazılır).
      await txn.rawUpdate(
          'UPDATE ${DbSabitler.tedarikciIadeler} '
          'SET toplam_tutar = ?, last_updated = ?, '
          'aciklama = COALESCE(?, aciklama) WHERE id = ?',
          [yeniToplam, now, aciklama, iadeId]);
      final guncelBaslik = await txn.query(DbSabitler.tedarikciIadeler,
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelBaslik.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: DbSabitler.tedarikciIadeler,
            veri: Map<String, dynamic>.from(guncelBaslik.first));
      }

      // Cari hareket: aynı fis_id + fis_tipi='Tedarikçi İadesi' satırı
      // varsa BORC toplamı güncellenir; yoksa yeni satır eklenir.
      final mevcutCariHareket = await txn.query('cari_hareket',
          where:
              "fis_id = ? AND cari_id = ? AND fis_tipi = 'Tedarikçi İadesi' AND is_deleted = 0",
          whereArgs: [iadeId, cariId],
          limit: 1);
      if (mevcutCariHareket.isNotEmpty) {
        final eskiBorc =
            (mevcutCariHareket.first['borc'] as num?)?.toDouble() ?? 0;
        await txn.rawUpdate(
            "UPDATE cari_hareket SET borc = ?, last_updated = ?, "
            "aciklama = ? WHERE id = ?",
            [
              ParaUtils.yuvarla(eskiBorc + ekToplam),
              now,
              'Tedarikçiye iade (ek kalem): $fisNo — borcumuzdan düşüldü',
              mevcutCariHareket.first['id'],
            ]);
        final guncelCH = await txn.query('cari_hareket',
            where: 'id = ?',
            whereArgs: [mevcutCariHareket.first['id']],
            limit: 1);
        if (guncelCH.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket',
              veri: Map<String, dynamic>.from(guncelCH.first));
        }
        cariHareketGid = (guncelCH.isNotEmpty
                ? guncelCH.first['global_id'] as String?
                : null) ??
            '';
      } else {
        // Nadir durum: ilk kayıt cariId null olabilir — yine de dayanıklı.
        cariHareketGid = await CariDeposu().hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: cariId,
              tarih: DateTime.parse(now),
              fisTipi: 'Tedarikçi İadesi',
              fisId: iadeId,
              fisNo: fisNo,
              aciklama:
                  'Tedarikçiye iade (ek kalem): $fisNo — borcumuzdan düşüldü',
              borc: ekToplam,
              odemeTuru: 'Cari',
              kullanici: kullaniciAdi,
            ));
      }

      // Cari bakiye: kanonik formül (is_deleted=0 filtresiyle SUM).
      await txn.rawUpdate(
          'UPDATE cari SET bakiye = ROUND((SELECT COALESCE(SUM(borc),0) - '
          'COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0), 2) '
          'WHERE id = ?',
          [cariId, cariId]);
      final guncelCari = await txn.query('cari',
          where: 'id = ?', whereArgs: [cariId], limit: 1);
      if (guncelCari.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'cari', veri: Map<String, dynamic>.from(guncelCari.first));
      }
    });

    // Bulut bildirimi (commit sonrası — best-effort)
    await _iadeSonrasiBildir(db, [
      (DbSabitler.tedarikciIadeler, [
        for (final r in await db.query(DbSabitler.tedarikciIadeler,
            columns: ['global_id'],
            where: 'id = ?',
            whereArgs: [iadeId]))
          if (r['global_id'] != null) r['global_id'] as String,
      ]),
      (DbSabitler.tedarikciIadeKalem, kalemGidler),
      ('stok_hareket', stokGidler),
      if (cariHareketGid.isNotEmpty) ('cari_hareket', [cariHareketGid]),
    ], urunIdler: miktarlar.keys, cariId: cariId);
    // Şube payı: stok DÜŞTÜ → pozitif fark.
    for (final s in satirlar) {
      await _stokDepo.subeStokPayiUygula(s.urunId, s.miktar);
    }

    return CariIadeSonucu(
      iadeId: iadeId,
      fisNo: fisNo,
      toplamTutar: ekToplam,
      birimFiyatlar: {
        for (final s in satirlar)
          s.urunId: ParaUtils.yuvarla(s.toplam / s.miktar),
      },
    );
  }

  /// Bir tedarikçi iadesini GERİ ALIR (Cari Hareketler'den silinince de bu
  /// çalışır). AlimIslemServisi.sil() ile aynı desen — tahmin etmez, bu
  /// iadenin GERÇEKTEN yazdığı satırları sorgulayıp tersini yazar, tek
  /// transaction'da:
  ///  • belge is_deleted=1 (senkronla diğer cihazlara da düşer),
  ///  • stok: her 'tedarikci_iade' stok hareketi kadar geri girilir; FEFO'nun
  ///    düştüğü lot varsa lot miktarı da iade edilir,
  ///  • cari: orijinal 'Tedarikçi İadesi' satırlarının toplamının tersi tek
  ///    bir 'Tedarikçi İadesi İptali' kaydıyla — borcumuz eski hâline döner.
  Future<void> tedarikciIadesiniIptalEt(int iadeId, {String? neden}) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    final stokGidler = <String>[];
    final lotIdler = <int>{};
    final subePayi = <int, double>{};
    String? tersCariGid;
    late final int cariId;

    await db.transaction((txn) async {
      final rows = await txn.query(DbSabitler.tedarikciIadeler,
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (rows.isEmpty) throw const IadeGecersizHatasi('Tedarikçi iadesi bulunamadı.');
      final baslik = rows.first;
      if ((baslik['is_deleted'] as int? ?? 0) == 1) {
        throw const IadeGecersizHatasi('Bu tedarikçi iadesi zaten iptal edilmiş.');
      }
      cariId = baslik['cari_id'] as int;
      final fisNo = baslik['iade_no'] as String? ?? '#$iadeId';

      await txn.update(
          DbSabitler.tedarikciIadeler,
          {
            'is_deleted': 1,
            'aciklama': neden ?? 'İptal edildi',
            'last_updated': now,
          },
          where: 'id = ?',
          whereArgs: [iadeId]);
      final guncel = await txn.query(DbSabitler.tedarikciIadeler,
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: DbSabitler.tedarikciIadeler, veri: Map<String, dynamic>.from(guncel.first));

      // Stok: iadenin yazdığı çıkış hareketleri kadar geri gir.
      final hareketler = await txn.query('stok_hareket',
          where: 'referans_id = ? AND referans_turu = ?',
          whereArgs: [iadeId, 'tedarikci_iade']);
      for (final h in hareketler) {
        final urunId = h['urun_id'] as int;
        final dusulen = ((h['onceki_stok'] as num?)?.toDouble() ?? 0) -
            ((h['sonraki_stok'] as num?)?.toDouble() ?? 0);
        if (dusulen <= 0.0005) continue;
        final lotId = h['lot_id'] as int?;
        final gid = const Uuid().v4();
        stokGidler.add(gid);
        await _stokDepo.stokGirTxn(txn, gid,
            urunId: urunId,
            miktar: dusulen,
            aciklama: 'Tedarikçi iadesi iptali: $fisNo',
            referansId: iadeId,
            referansTuru: 'tedarikci_iade_iptal',
            hareketTuru: 'Tedarikçi İadesi İptali',
            lotId: lotId);
        if (lotId != null) {
          await txn.rawUpdate(
              'UPDATE lot_seri SET miktar = miktar + ?, last_updated = ? WHERE id = ?',
              [dusulen, now, lotId]);
          lotIdler.add(lotId);
        }
        subePayi[urunId] = (subePayi[urunId] ?? 0) - dusulen; // stok ARTTI
      }
      for (final lotId in lotIdler) {
        final lot = await txn.query('lot_seri', where: 'id = ?', whereArgs: [lotId], limit: 1);
        if (lot.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn, tablo: 'lot_seri', veri: Map<String, dynamic>.from(lot.first));
        }
      }

      // Cari: orijinal satırların tersi.
      final cariSatirlari = await txn.query('cari_hareket',
          where: 'fis_id = ? AND cari_id = ? AND fis_tipi = ? AND is_deleted = 0',
          whereArgs: [iadeId, cariId, 'Tedarikçi İadesi']);
      final borc = cariSatirlari.fold<double>(0, (t, r) => t + ((r['borc'] as num?)?.toDouble() ?? 0));
      final alacak = cariSatirlari.fold<double>(0, (t, r) => t + ((r['alacak'] as num?)?.toDouble() ?? 0));
      if (borc > 0.005 || alacak > 0.005) {
        tersCariGid = await CariDeposu().hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: cariId,
              tarih: DateTime.parse(now),
              fisTipi: 'Tedarikçi İadesi İptali',
              fisId: iadeId,
              fisNo: fisNo,
              aciklama: 'Tedarikçi iadesi iptali: $fisNo',
              borc: alacak,
              alacak: borc,
              odemeTuru: 'Cari',
            ));
      }
    });

    await _iadeSonrasiBildir(db, [
      (DbSabitler.tedarikciIadeler, [
        for (final r in await db.query(DbSabitler.tedarikciIadeler,
            columns: ['global_id'], where: 'id = ?', whereArgs: [iadeId]))
          if (r['global_id'] != null) r['global_id'] as String,
      ]),
      ('stok_hareket', stokGidler),
      ('cari_hareket', [?tersCariGid]),
    ], urunIdler: subePayi.keys, cariId: cariId);
    for (final MapEntry(key: urunId, value: fark) in subePayi.entries) {
      await _stokDepo.subeStokPayiUygula(urunId, fark);
    }
  }

  /// Son alış fiyatından (urunler.alis_fiyat — her alımda güncellenir) KDV
  /// dahil satır tutarları. KDV dahil birim: alımın yazdığı
  /// alis_fiyat_kdv_dahil; yoksa alis_fiyat × (1 + alis_kdv_oran).
  Future<List<_FiyatliKalem>> _tedarikciMaliyetleriTxn(
      DatabaseExecutor ex, Map<int, double> miktarlar) async {
    final satirlar = <_FiyatliKalem>[];
    final maliyetsiz = <String>[];
    for (final MapEntry(key: urunId, value: miktar) in miktarlar.entries) {
      final rows = await ex.query('urunler',
          columns: ['urun_adi', 'alis_fiyat', 'alis_kdv_oran', 'alis_fiyat_kdv_dahil'],
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [urunId],
          limit: 1);
      if (rows.isEmpty) throw IadeGecersizHatasi('Ürün bulunamadı (#$urunId).');
      final r = rows.first;
      final ad = r['urun_adi'] as String? ?? '#$urunId';
      final alis = (r['alis_fiyat'] as num?)?.toDouble() ?? 0;
      if (alis <= 0) {
        maliyetsiz.add(ad);
        continue;
      }
      final kdvOran = (r['alis_kdv_oran'] as num?)?.toDouble() ?? 0;
      final kdvDahilBirim = tedarikciIadeBirimMaliyeti(
        alisFiyat: alis,
        alisKdvOran: kdvOran,
        alisFiyatKdvDahil: (r['alis_fiyat_kdv_dahil'] as num?)?.toDouble() ?? 0,
      );
      satirlar.add((
        urunId: urunId,
        urunAdi: ad,
        miktar: miktar,
        birimFiyat: alis,
        kdvOran: kdvOran,
        toplam: ParaUtils.yuvarla(miktar * kdvDahilBirim),
      ));
    }
    if (maliyetsiz.isNotEmpty) {
      throw IadeGecersizHatasi('${maliyetsiz.join(', ')} için alış fiyatı (maliyet) '
          'tanımlı değil — tedarikçi iadesi maliyetten hesaplandığı için önce '
          'ürün kartına alış fiyatı girin.');
    }
    return satirlar;
  }

  // ── Bayiden iade ─────────────────────────────────────────────────────

  /// [bayi]den mal iadesi alır: stok ARTAR, bayinin borç bakiyesi iade
  /// tutarı kadar DÜŞER. Fiyat: bayiye özel toptan fiyatı — toptan satışla
  /// AYNI kural zinciri (FiyatHesaplamaServisi: kademe → gruba özel ürün
  /// fiyatı → grup iskontosu → genel toptan fiyatı). Kasaya dokunmaz.
  Future<CariIadeSonucu> bayidenIadeAl({
    required CariModel bayi,
    required List<IadeMiktari> kalemler,
    required int? kullaniciId,
    required String kullaniciAdi,
    String? aciklama,
  }) async {
    final cariId = _cariIdDogrula(bayi);
    if (!cariBayiMi(bayi)) {
      throw IadeGecersizHatasi('${bayi.unvan} bir bayi/toptan müşterisi değil — '
          'bayi iadesi yalnız Bayi/Toptan müşteri tipli carilerden alınır.');
    }
    final miktarlar = _miktarlariBirlestir(kalemler);
    // FiyatHesaplamaServisi kendi veritabanı bağlantısıyla okur: transaction
    // İÇİNDEN çağrılırsa sqflite kilidi bekleyip kilitlenir — fiyatlar önce.
    final satirlar = await _bayiFiyatlari(bayi, miktarlar);
    final toplam = _toplam(satirlar);
    final db = await Veritabani().db;
    final fisNo = await Veritabani()
        .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);
    final now = DateTime.now().toIso8601String();
    final iadeGid = const Uuid().v4();
    final kalemGidler = <String>[];
    final stokGidler = <String>[];
    late final int iadeId;
    late final String cariHareketGid;

    await db.transaction((txn) async {
      final baslik = {
        'global_id': iadeGid,
        'cari_id': cariId,
        'fis_no': fisNo,
        'tarih': now,
        'toplam_tutar': toplam,
        'iade_nedeni': aciklama == null || aciklama.trim().isEmpty
            ? 'Bayi iadesi'
            : 'Bayi iadesi: ${aciklama.trim()}',
        'durum': 'tamamlandi',
        'kasiyer_id': kullaniciId,
        'last_updated': now,
      };
      iadeId = await txn.insert('iade', baslik);
      await SyncKuyrukYazici.ekleTxn(txn, tablo: 'iade', veri: {...baslik, 'id': iadeId});

      for (final s in satirlar) {
        final kalemGid = const Uuid().v4();
        kalemGidler.add(kalemGid);
        final kalem = {
          'global_id': kalemGid,
          'iade_id': iadeId,
          'urun_id': s.urunId,
          'urun_adi': s.urunAdi,
          'miktar': s.miktar,
          'birim_fiyat': s.birimFiyat,
          'toplam': s.toplam,
          'last_updated': now,
        };
        final kalemId = await txn.insert('iade_kalem', kalem);
        await SyncKuyrukYazici.ekleTxn(txn, tablo: 'iade_kalem', veri: {...kalem, 'id': kalemId});

        // referans_turu 'iade': müşteri iadesiyle aynı — İade Geçmişi'nin
        // silme/düzenleme ters kayıtları ve Veri Sağlığı iade kontrolleri
        // bu kaydı doğru tanır.
        final stokGid = const Uuid().v4();
        stokGidler.add(stokGid);
        await _stokDepo.stokGirTxn(txn, stokGid,
            urunId: s.urunId,
            miktar: s.miktar,
            kullaniciId: kullaniciId,
            aciklama: 'Bayi iadesi: $fisNo',
            referansId: iadeId,
            referansTuru: 'iade',
            hareketTuru: 'Iade Giris');
      }

      // Bayinin bakiyesi (borç − alacak) satışta borç+ ile artar; iade
      // ALACAK+ yazılarak borcu düşürülür. fis_tipi 'İade' — mevcut iade
      // düzenleme/silme akışları cari satırını fis_id + bu tiple bulur.
      cariHareketGid = await CariDeposu().hareketEkleTxn(
          txn,
          CariHareketModel(
            cariId: cariId,
            tarih: DateTime.parse(now),
            fisTipi: 'İade',
            fisId: iadeId,
            fisNo: fisNo,
            aciklama: 'Bayi iadesi: $fisNo — cari bakiyesine işlendi',
            alacak: toplam,
            odemeTuru: 'Cari',
            kullanici: kullaniciAdi,
          ));
    });

    await _iadeSonrasiBildir(db, [
      ('iade', [iadeGid]),
      ('iade_kalem', kalemGidler),
      ('stok_hareket', stokGidler),
      ('cari_hareket', [cariHareketGid]),
    ], urunIdler: miktarlar.keys, cariId: cariId);
    // Şube payı: stok ARTTI → negatif fark.
    for (final s in satirlar) {
      await _stokDepo.subeStokPayiUygula(s.urunId, -s.miktar);
    }

    return CariIadeSonucu(
      iadeId: iadeId,
      fisNo: fisNo,
      toplamTutar: toplam,
      birimFiyatlar: {for (final s in satirlar) s.urunId: s.birimFiyat},
    );
  }

  // ── 🆕 TEK FİŞ MODELİ: mevcut bayi iadesine kalem ekle ───────────────
  /// 🔴 YENİ (2026-10-13): Mevcut bir bayi iadesine YENİ kalem ekler.
  /// Belge açılmaz; başlık aynen kalır. Aynı ürün zaten varsa kalem
  /// satırı TOPLANIR. Cari_hareket satırı toplanarak güncellenir
  /// (fis_tipi='İade' + fis_id eşleşmesi). Stok ARTAR (bayiden mal
  /// alıyoruz). Kasa hareketi YOKTUR.
  Future<CariIadeSonucu> bayiIadeyeKalemEkle({
    required int iadeId,
    required CariModel bayi,
    required List<IadeMiktari> kalemler,
    required int? kullaniciId,
    required String kullaniciAdi,
    String? aciklama,
  }) async {
    final cariId = _cariIdDogrula(bayi);
    if (!cariBayiMi(bayi)) {
      throw IadeGecersizHatasi(
          '${bayi.unvan} bir bayi/toptan müşterisi değil.');
    }
    final miktarlar = _miktarlariBirlestir(kalemler);
    // Fiyat önce (transaction dışında — FiyatHesaplamaServisi ayrı DB bağlantısı açar).
    final satirlar = await _bayiFiyatlari(bayi, miktarlar);
    final ekToplam = _toplam(satirlar);
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    final stokGidler = <String>[];
    final kalemGidler = <String>[];
    late final String fisNo;
    late final double yeniToplam;
    late final String cariHareketGid;

    await db.transaction((txn) async {
      // Belge kontrolü
      final baslik = await txn.query('iade',
          where: 'id = ? AND COALESCE(durum, "") != "iptal"',
          whereArgs: [iadeId],
          limit: 1);
      if (baslik.isEmpty) {
        throw const IadeGecersizHatasi('Bayi iadesi bulunamadı.');
      }
      fisNo = (baslik.first['fis_no'] as String?) ?? '#$iadeId';
      final eskiToplam =
          (baslik.first['toplam_tutar'] as num?)?.toDouble() ?? 0;
      yeniToplam = ParaUtils.yuvarla(eskiToplam + ekToplam);

      for (final s in satirlar) {
        // Aynı ürün varsa mevcut kalem satırını topla, yoksa ekle.
        final mevcut = await txn.query('iade_kalem',
            where: 'iade_id = ? AND urun_id = ?',
            whereArgs: [iadeId, s.urunId],
            limit: 1);
        if (mevcut.isNotEmpty) {
          final eskiMiktar = (mevcut.first['miktar'] as num?)?.toDouble() ?? 0;
          final eskiToplam = (mevcut.first['toplam'] as num?)?.toDouble() ?? 0;
          await txn.rawUpdate(
              'UPDATE iade_kalem SET miktar = ?, toplam = ?, last_updated = ? WHERE id = ?',
              [
                eskiMiktar + s.miktar,
                ParaUtils.yuvarla(eskiToplam + s.toplam),
                now,
                mevcut.first['id'],
              ]);
          final guncel = await txn.query('iade_kalem',
              where: 'id = ?', whereArgs: [mevcut.first['id']], limit: 1);
          if (guncel.isNotEmpty) {
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'iade_kalem',
                veri: Map<String, dynamic>.from(guncel.first));
          }
        } else {
          final kalemGid = const Uuid().v4();
          kalemGidler.add(kalemGid);
          final kalem = {
            'global_id': kalemGid,
            'iade_id': iadeId,
            'urun_id': s.urunId,
            'urun_adi': s.urunAdi,
            'miktar': s.miktar,
            'birim_fiyat': s.birimFiyat,
            'toplam': s.toplam,
            'last_updated': now,
          };
          final kalemId = await txn.insert('iade_kalem', kalem);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'iade_kalem', veri: {...kalem, 'id': kalemId});
        }

        // Stok ARTAR (mevcut bayidenIadeAl ile aynı yön + aynı referans_turu='iade').
        final stokGid = const Uuid().v4();
        stokGidler.add(stokGid);
        await _stokDepo.stokGirTxn(txn, stokGid,
            urunId: s.urunId,
            miktar: s.miktar,
            kullaniciId: kullaniciId,
            aciklama: 'Bayi iadesi (ek kalem): $fisNo',
            referansId: iadeId,
            referansTuru: 'iade',
            hareketTuru: 'Iade Giris');
      }

      // Başlık toplam_tutar güncelle (opsiyonel açıklama da yazılır).
      await txn.rawUpdate(
          'UPDATE iade SET toplam_tutar = ?, last_updated = ?, '
          'iade_nedeni = COALESCE(?, iade_nedeni) WHERE id = ?',
          [yeniToplam, now, aciklama, iadeId]);
      final guncelBaslik = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (guncelBaslik.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'iade', veri: Map<String, dynamic>.from(guncelBaslik.first));
      }

      // Cari hareket: aynı fis_id + fis_tipi='İade' satırı varsa
      // ALACAK toplamı güncellenir; yoksa yeni satır eklenir.
      final mevcutCH = await txn.query('cari_hareket',
          where:
              "fis_id = ? AND cari_id = ? AND fis_tipi = 'İade' AND is_deleted = 0",
          whereArgs: [iadeId, cariId],
          limit: 1);
      if (mevcutCH.isNotEmpty) {
        final eskiAlacak =
            (mevcutCH.first['alacak'] as num?)?.toDouble() ?? 0;
        await txn.rawUpdate(
            "UPDATE cari_hareket SET alacak = ?, last_updated = ?, "
            "aciklama = ? WHERE id = ?",
            [
              ParaUtils.yuvarla(eskiAlacak + ekToplam),
              now,
              'Bayi iadesi (ek kalem): $fisNo — cari bakiyesine işlendi',
              mevcutCH.first['id'],
            ]);
        final guncelCH = await txn.query('cari_hareket',
            where: 'id = ?',
            whereArgs: [mevcutCH.first['id']],
            limit: 1);
        if (guncelCH.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'cari_hareket',
              veri: Map<String, dynamic>.from(guncelCH.first));
        }
        cariHareketGid = (guncelCH.isNotEmpty
                ? guncelCH.first['global_id'] as String?
                : null) ??
            '';
      } else {
        cariHareketGid = await CariDeposu().hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: cariId,
              tarih: DateTime.parse(now),
              fisTipi: 'İade',
              fisId: iadeId,
              fisNo: fisNo,
              aciklama:
                  'Bayi iadesi (ek kalem): $fisNo — cari bakiyesine işlendi',
              alacak: ekToplam,
              odemeTuru: 'Cari',
              kullanici: kullaniciAdi,
            ));
      }

      // Cari bakiye: kanonik formül.
      await txn.rawUpdate(
          'UPDATE cari SET bakiye = ROUND((SELECT COALESCE(SUM(borc),0) - '
          'COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0), 2) '
          'WHERE id = ?',
          [cariId, cariId]);
      final guncelCari = await txn.query('cari',
          where: 'id = ?', whereArgs: [cariId], limit: 1);
      if (guncelCari.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'cari', veri: Map<String, dynamic>.from(guncelCari.first));
      }
    });

    // Bulut bildirimi
    await _iadeSonrasiBildir(db, [
      ('iade', [
        for (final r in await db.query('iade',
            columns: ['global_id'],
            where: 'id = ?',
            whereArgs: [iadeId]))
          if (r['global_id'] != null) r['global_id'] as String,
      ]),
      ('iade_kalem', kalemGidler),
      ('stok_hareket', stokGidler),
      if (cariHareketGid.isNotEmpty) ('cari_hareket', [cariHareketGid]),
    ], urunIdler: miktarlar.keys, cariId: cariId);
    // Şube payı: stok ARTTI → negatif fark.
    for (final s in satirlar) {
      await _stokDepo.subeStokPayiUygula(s.urunId, -s.miktar);
    }

    return CariIadeSonucu(
      iadeId: iadeId,
      fisNo: fisNo,
      toplamTutar: ekToplam,
      birimFiyatlar: {for (final s in satirlar) s.urunId: s.birimFiyat},
    );
  }

  Future<List<_FiyatliKalem>> _bayiFiyatlari(
      CariModel bayi, Map<int, double> miktarlar) async {
    final urunDepo = UrunDeposu();
    final satirlar = <_FiyatliKalem>[];
    for (final MapEntry(key: urunId, value: miktar) in miktarlar.entries) {
      final urun = await urunDepo.idileGetir(urunId);
      if (urun == null) throw IadeGecersizHatasi('Ürün bulunamadı (#$urunId).');
      final fiyat = await FiyatHesaplamaServisi()
          .hesapla(urun: urun, cari: bayi, miktar: miktar);
      satirlar.add((
        urunId: urunId,
        urunAdi: urun.urunAdi,
        miktar: miktar,
        birimFiyat: fiyat.birimFiyat,
        kdvOran: 0,
        toplam: ParaUtils.yuvarla(miktar * fiyat.birimFiyat),
      ));
    }
    return satirlar;
  }

  // ── Ortak yardımcılar ────────────────────────────────────────────────

  /// Commit sonrası anlık bulut bildirimi (kuyruk kayıtları zaten
  /// transaction içinde yazıldı — burası best-effort hızlandırma).
  Future<void> _iadeSonrasiBildir(
    Database db,
    List<(String tablo, List<String> globalIdler)> kayitlar, {
    required Iterable<int> urunIdler,
    required int cariId,
  }) async {
    try {
      for (final (tablo, gidler) in kayitlar) {
        for (final gid in gidler) {
          final s = await db.query(tablo, where: 'global_id = ?', whereArgs: [gid], limit: 1);
          if (s.isNotEmpty) BulutManager().upsert(tablo, Map<String, dynamic>.from(s.first));
        }
      }
      Future<void> idIleBildir(String tablo, int id) async {
        final s = await db.query(tablo, where: 'id = ?', whereArgs: [id], limit: 1);
        if (s.isNotEmpty) BulutManager().upsert(tablo, Map<String, dynamic>.from(s.first));
      }

      for (final urunId in urunIdler) {
        await idIleBildir('urunler', urunId);
      }
      await idIleBildir('cari', cariId);
    } catch (e) {
      if (kDebugMode) debugPrint('Cari iadesi bulut bildirimi hatası: $e');
    }
  }
}

/// Tedarikçi iadesinde tek birimin KDV DAHİL maliyeti: alımın yazdığı
/// alis_fiyat_kdv_dahil; yoksa alis_fiyat × (1 + alış KDV oranı). Ekrandaki
/// önizleme ve kayıt AYNI fonksiyonu kullanır.
double tedarikciIadeBirimMaliyeti({
  required double alisFiyat,
  required double alisKdvOran,
  required double alisFiyatKdvDahil,
}) =>
    alisFiyatKdvDahil > 0 ? alisFiyatKdvDahil : alisFiyat * (1 + alisKdvOran / 100);

int _cariIdDogrula(CariModel cari) {
  final id = cari.id;
  if (id == null) throw const IadeGecersizHatasi('Kayıtlı bir cari seçin.');
  return id;
}

/// Aynı ürün birden fazla satırda gelirse miktarları birleştirir; boş liste
/// ve sıfır/negatif miktar reddedilir.
Map<int, double> _miktarlariBirlestir(List<IadeMiktari> kalemler) {
  if (kalemler.isEmpty) throw const IadeGecersizHatasi('İade edilecek ürün yok.');
  final miktarlar = <int, double>{};
  for (final k in kalemler) {
    if (k.miktar <= 0) {
      throw const IadeGecersizHatasi('İade miktarı sıfırdan büyük olmalı.');
    }
    miktarlar[k.urunId] = (miktarlar[k.urunId] ?? 0) + k.miktar;
  }
  return miktarlar;
}

double _toplam(List<_FiyatliKalem> satirlar) =>
    ParaUtils.yuvarla(satirlar.fold<double>(0, (t, s) => t + s.toplam));