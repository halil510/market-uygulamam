// lib/depolar/urun_deposu_liste.dart
//
// urun_deposu.dart'ın parçası (part/part of) — ürün listesi, kritik stok, satış hızı, istatistik ve grup sorguları.
// Davranış BİREBİR aynı: UrunDeposu üzerine extension; private üyelere
// (_db vb.) aynı kütüphane olduğu için erişir.
part of 'urun_deposu.dart';

extension UrunDeposuListe on UrunDeposu {
  Future<List<UrunModel>> tumunuGetir({bool sadecaAktif = true, int limit = 2000}) async {
    final db = await _d;
    final where = sadecaAktif
        ? 'is_deleted = 0 AND aktif = 1'
        : 'is_deleted = 0';
    final rows = await db.query(
      DbSabitler.urunler,
      where: where,
      orderBy: 'urun_adi ASC',
      // limit kaldırıldı - tüm ürünleri getirir
    );
    return rows.map(UrunModel.fromMap).toList();
  }

  /// Sayfalı arama — ürün listesi ekranı için kullanılır.
  Future<List<UrunModel>> sayfaliGetir(
    int offset,
    int limit, {
    String? aramaMetni,
    String? grup,
    bool sadecaAktif = true,
    // Kullanıcı isteği: filtreleme ekranına "stok azalan, en son
    // güncellenen, satış fiyatı, grup, alan1 gibi" daha çok sıralama
    // seçeneği eklenmesi. Aşağıdaki değerler destekleniyor:
    // 'isim' (varsayılan), 'stok_azalan', 'stok_artan',
    // 'guncelleme_yeni', 'fiyat_yuksek', 'fiyat_dusuk', 'grup', 'alan1'
    String siralama = 'isim',
  }) async {
    final db = await _d;
    final whereParts = ['is_deleted = 0'];
    final args = <dynamic>[];
    if (sadecaAktif) whereParts.add('aktif = 1');
    if (grup != null) {
      whereParts.add('ana_grup = ?');
      args.add(grup);
    }
    if (aramaMetni != null && aramaMetni.isNotEmpty) {
      final q = '%${aramaNormalize(aramaMetni)}%';
      // bkz. ara() üzerindeki aynı kullanıcı bulgusu notu — alternatif
      // barkodlar (`barkodlar`) da aranıyor.
      whereParts.add(
        '(${aramaSqlKolon('urun_adi')} LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?'
        ' OR ${aramaSqlKolon('ana_grup')} LIKE ? OR ${aramaSqlKolon('alternatif_urun_adi')} LIKE ? OR ${aramaSqlKolon('marka')} LIKE ?)',
      );
      args.addAll([q, q, q, q, q, q, q]);
    }
    final orderBy = switch (siralama) {
      'stok_azalan'     => 'stok DESC',
      'stok_artan'      => 'stok ASC',
      'guncelleme_yeni' => 'last_updated DESC',
      'fiyat_yuksek'    => 'satis_fiyati DESC',
      'fiyat_dusuk'     => 'satis_fiyati ASC',
      'grup'            => 'ana_grup ASC, urun_adi ASC',
      'alan1'           => 'alan1 ASC, urun_adi ASC',
      _                 => 'urun_adi ASC',
    };
    final rows = await db.query(
      DbSabitler.urunler,
      where: whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return rows.map(UrunModel.fromMap).toList();
  }

  /// Hızlı satış arama — aktif ürünler, DB'ye sorgu atar (bellekte tam liste tutmaz).
  // 🔴 Derin denetimde bulundu (P3): [sadeceToptan] eklendi — Bayi
  // Portalı'ndaki ürün araması bu filtreyi hiç kullanmıyordu, bir bayi
  // toptan satışa açık işaretlenmemiş (perakende-only) ürünleri de
  // arayıp sipariş edebiliyordu. Güvenlik açığı değil (bayi verisi
  // zaten kendi cari'siyle izole) — iş mantığı boşluğu. Varsayılan
  // false: diğer TÜM çağıranların davranışı birebir korunuyor.
  Future<List<UrunModel>> ara(String sorgu,
      {int limit = 80,
      int offset = 0,
      bool sadecaAktif = true,
      bool sadeceToptan = false}) async {
    if (sorgu.isEmpty) return [];
    final db = await _d;
    final q = '%${aramaNormalize(sorgu)}%';
    final aktifFiltre = sadecaAktif ? ' AND aktif = 1' : '';
    final toptanFiltre = sadeceToptan ? ' AND toptan_satista = 1' : '';
    // ÖNCEDEN bu fonksiyonun offset parametresi yoktu — "daha fazla
    // yükle" (sonsuz kaydırma) her zaman AYNI ilk sonuçları tekrar
    // getiriyordu, listeye aynı ürünler tekrar tekrar ekleniyordu
    // (arama sonucu 50'den fazla eşleşme varsa). Artık gerçek
    // sayfalama destekleniyor.
    // 🔴 Kullanıcı bulgusu: bir ürünün EK/alternatif barkodları
    // (`barkodlar` — virgülle ayrılmış) taranmıyordu. Kamera ile okutma
    // (barkodlaGetir) zaten ikisini de kontrol ediyordu — arama kutusuna
    // ELLE yazılan/okutulan bir alternatif barkod ise hiç bulamıyordu.
    // Diğer alanlarla AYNI serbest (substring) eşleşme kullanılıyor —
    // barkodlaGetir()'deki sıkı virgül-sınırlı eşleşme burada uygun
    // değil, bu bir metin arama kutusu.
    final rows = await db.rawQuery(
      'SELECT * FROM ${DbSabitler.urunler}'
      ' WHERE (${aramaSqlKolon('urun_adi')} LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?'
      '       OR ${aramaSqlKolon('alternatif_urun_adi')} LIKE ? OR ${aramaSqlKolon('marka')} LIKE ?)'
      '   AND is_deleted = 0$aktifFiltre$toptanFiltre'
      ' ORDER BY urun_adi ASC LIMIT ? OFFSET ?',
      [q, q, q, q, q, q, limit, offset],
    );
    return rows.map(UrunModel.fromMap).toList();
  }

  // ── ÖZEL SORGULAR ──────────────────────────────────────────────────────

  Future<List<UrunModel>> kritikStoklar({int limit = 50}) async {
    final db = await _d;
    final rows = await db.rawQuery(
      'SELECT * FROM ${DbSabitler.urunler}'
      ' WHERE is_deleted = 0 AND aktif = 1'
      '   AND minimum_stok > 0 AND stok <= minimum_stok'
      ' ORDER BY stok ASC LIMIT ?',
      [limit],
    );
    return rows.map(UrunModel.fromMap).toList();
  }

  /// Verilen ürün id'leri için son [gunSayisi] gündeki toplam satılan
  /// miktarı döner (FAZ 8 — Akıllı Satın Alma önerisine gerekçe eklemek
  /// için: "son 30 günde X satıldı, stok ~Y günde tükenir" gibi).
  /// Salt okunur — hiçbir tabloya yazmaz.
  Future<Map<int, double>> satisHiziGetir(List<int> urunIdleri, {int gunSayisi = 30}) async {
    if (urunIdleri.isEmpty) return {};
    final db = await _d;
    final yerTutucular = List.filled(urunIdleri.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT sk.urun_id AS urun_id, SUM(sk.miktar) AS miktar
      FROM satis_kalem sk
      JOIN satislar s ON s.id = sk.satis_id
      WHERE s.iptal = 0 AND s.is_deleted = 0 AND s.sync_cakisma_kopyasi = 0
        AND DATE(s.tarih) >= DATE('now', 'localtime', ?)
        AND sk.urun_id IN ($yerTutucular)
      GROUP BY sk.urun_id
    ''', ['-$gunSayisi days', ...urunIdleri]);
    return {
      for (final r in rows) r['urun_id'] as int: (r['miktar'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<Map<String, dynamic>> istatistikler() async {
    final db = await _d;
    // 🔴🔴 DÜZELTME (komple derin analizde bulundu): 'kritik' ve
    // 'stoksuz' ÖNCEDEN 'aktif = 1' filtresi içermiyordu (sadece 'aktif'
    // sayacı içeriyordu) VE iki küme ÖRTÜŞÜYORDU (stok=0 + minimum_stok>0
    // olan bir ürün ikisine de sayılıyordu). Bu, çağıranların kurduğu
    // 'saglikli = aktif - kritik - stoksuz' formülünü (bkz.
    // stok_rapor_ekrani.dart) bozuyordu — pasif ürünler ve örtüşen
    // kayıtlar yüzünden "Sağlıklı" sayısı olması gerekenden düşük
    // görünüyordu. Artık üçü de 'aktif=1' bazlı VE birbirini dışlıyor:
    // stoksuz (stok<=0) ile kritik (0'dan büyük ama minimum altında)
    // ayrık kümeler, toplamları her zaman 'aktif' sayısına eşit.
    final res = await db.rawQuery('''
      SELECT
        COUNT(*)                                                           AS toplam,
        COUNT(CASE WHEN aktif = 1 AND is_deleted = 0 THEN 1 END)          AS aktif,
        COUNT(CASE WHEN aktif = 1 AND is_deleted = 0
                        AND stok > 0 AND stok <= minimum_stok
                        AND minimum_stok > 0 THEN 1 END)                  AS kritik,
        COUNT(CASE WHEN aktif = 1 AND is_deleted = 0
                        AND stok <= 0 THEN 1 END)                         AS stoksuz,
        COALESCE(SUM(CASE WHEN is_deleted = 0 AND aktif = 1
                          THEN MAX(stok, 0) * alis_fiyat END), 0)       AS stok_degeri
      FROM ${DbSabitler.urunler}
      WHERE is_deleted = 0
    ''');
    if (res.isEmpty) return {};
    final r = res.first;
    return {
      'toplam':      (r['toplam']      as int?)    ?? 0,
      'aktif':       (r['aktif']       as int?)    ?? 0,
      'kritik':      (r['kritik']      as int?)    ?? 0,
      'stoksuz':     (r['stoksuz']     as int?)    ?? 0,
      'stok_degeri': (r['stok_degeri'] as num?)?.toDouble() ?? 0.0,
    };
  }

  Future<List<String>> anaGruplariGetir() async {
    final db = await _d;
    final rows = await db.rawQuery(
      'SELECT DISTINCT ana_grup FROM ${DbSabitler.urunler}'
      ' WHERE ana_grup IS NOT NULL AND is_deleted = 0'
      ' ORDER BY ana_grup',
    );
    return rows.map((r) => r['ana_grup'] as String).toList();
  }

  Future<void> topluFiyatGuncelle(
    List<int> ids,
    double oran, {
    String tip = 'satis',
    String yon = 'artir',
  }) async {
    final db = await _d;
    final kolon = tip == 'alis' ? 'alis_fiyat' : 'satis_fiyati';
    // Satış fiyatı → fiyat tarihi, alış fiyatı → maliyet tarihi.
    final tarihKolon =
        tip == 'alis' ? 'maliyet_guncelleme_tarih' : 'fiyat_guncelleme_tarih';
    final now = DateTime.now().toIso8601String();
    final guncellenenIds = <int>[];
    for (final id in ids) {
      try {
        // 🔴 DÜZELTME: Bu fonksiyon (toplu fiyat güncelleme — tek
        // seferde yüzlerce ürünü etkileyebilir) senkron sisteminin
        // izlediği 'last_updated' sütununu DEĞİL, ayrı/farklı bir alan
        // olan 'guncelleme_tarihi'ni güncelliyordu — bulk fiyat
        // değişiklikleri ne otomatik ne de manuel senkrona hiç
        // yakalanmıyordu. Artık last_updated da bump ediliyor ve her
        // ürün için BulutManager çağrılıyor.
        if (yon == 'esitle') {
          await db.rawUpdate(
            'UPDATE ${DbSabitler.urunler}'
            ' SET $kolon = ?, guncelleme_tarihi = ?, last_updated = ?, $tarihKolon = ? WHERE id = ?',
            [oran, now, now, now, id],
          );
        } else if (yon == 'azalt') {
          await db.rawUpdate(
            'UPDATE ${DbSabitler.urunler}'
            ' SET $kolon = $kolon * ?, guncelleme_tarihi = ?, last_updated = ?, $tarihKolon = ? WHERE id = ?',
            [1 - (oran / 100), now, now, now, id],
          );
        } else {
          await db.rawUpdate(
            'UPDATE ${DbSabitler.urunler}'
            ' SET $kolon = $kolon * ?, guncelleme_tarihi = ?, last_updated = ?, $tarihKolon = ? WHERE id = ?',
            [1 + (oran / 100), now, now, now, id],
          );
        }
        // Alış fiyatı değiştiyse KDV dahil maliyet de yeniden hesaplanır
        // (kâr/maliyet raporları alis_fiyat_kdv_dahil'i kullanır; önceden
        // bayat kalıyordu).
        if (tip == 'alis') {
          await db.rawUpdate(
            'UPDATE ${DbSabitler.urunler} SET alis_fiyat_kdv_dahil = '
            'alis_fiyat * (1 + COALESCE(alis_kdv_oran, 0) / 100.0) WHERE id = ?',
            [id],
          );
        }
        guncellenenIds.add(id);
      } catch (e) {
        if (kDebugMode) debugPrint('topluFiyatGuncelle id=$id hata: $e');
      }
    }
    // 🔴 Madde 25 (N+1 sertleştirmesi, 2026-09-16): önceden her id için
    // ayrı ayrı SELECT + upsert çağrılıyordu (yüzlerce/binlerce ürünü
    // etkileyen bir toplu işlemde N ayrı sorgu). Artık güncellenen
    // id'ler TEK (parçalı) IN (...) sorgusuyla toplu okunup buluta
    // bildiriliyor — bkz. _topluBulutSenkronuGonder.
    await _topluBulutSenkronuGonder(guncellenenIds);
  }

}
