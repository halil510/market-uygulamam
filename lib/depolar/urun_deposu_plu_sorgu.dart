// lib/depolar/urun_deposu_plu_sorgu.dart
//
// urun_deposu.dart'ın parçası (part/part of) — PLU, tekil ürün sorguları, QR menü ve toptan satış işaretleri.
// Davranış BİREBİR aynı: UrunDeposu üzerine extension; private üyelere
// (_db vb.) aynı kütüphane olduğu için erişir.
part of 'urun_deposu.dart';

extension UrunDeposuPluSorgu on UrunDeposu {
  /// 'plu'/'plu_kart_boyut' kolonları yoksa ekler (migrasyon çalışmamış
  /// eski bir cihaz için savunma amaçlı self-heal — IF NOT EXISTS'siz
  /// ALTER TABLE olduğu için hata sessizce yutulur).
  Future<void> pluKolonlariniGarantiEt() async {
    final db = await _d;
    try {
      await db.execute('ALTER TABLE urunler ADD COLUMN plu INTEGER NOT NULL DEFAULT 0');
    } catch (_) {/* zaten var */}
    try {
      await db.execute('ALTER TABLE urunler ADD COLUMN plu_kart_boyut INTEGER NOT NULL DEFAULT 2');
    } catch (_) {/* zaten var */}
  }

  Future<List<UrunModel>> pluUrunleriGetir() async {
    final db = await _d;
    final rows = await db.rawQuery(
      'SELECT * FROM urunler WHERE plu = 1 AND is_deleted = 0 '
      'ORDER BY plu_sira ASC, urun_adi',
    );
    return rows.map(UrunModel.fromMap).toList();
  }

  /// PLU ekranının (POS hızlı satış paneli) ihtiyacı: ana_grup ÖNCE
  /// sıralanır ki "Tümü" sekmesinde ürünler kategori kategori bir arada
  /// görünsün (pluUrunleriGetir()'in düz plu_sira sıralaması burada
  /// grupları birbirine karıştırırdı — bilerek AYRI bir metod). Madde 2
  /// mimari denetimi: plu_ekrani.dart önceden bu sorguyu doğrudan
  /// kendisi çalıştırıyordu.
  Future<List<UrunModel>> pluUrunleriGrupluGetir() async {
    final db = await _d;
    final rows = await db.rawQuery(
      'SELECT * FROM urunler WHERE plu = 1 AND is_deleted = 0 '
      'ORDER BY ana_grup, plu_sira ASC, urun_adi',
    );
    return rows.map(UrunModel.fromMap).toList();
  }

  /// Ürünü PLU paneline ekler — yeni eklenen ürün listenin SONUNA
  /// gitsin diye mevcut en yüksek sıradan bir fazlası atanır.
  Future<void> pluyaEkle(int urunId) async {
    final db = await _d;
    final maxRow = await db.rawQuery(
        'SELECT MAX(plu_sira) as m FROM urunler WHERE plu = 1');
    final yeniSira = ((maxRow.first['m'] as num?)?.toInt() ?? -1) + 1;
    await alanGuncelle(urunId, {'plu': 1, 'plu_kart_boyut': 2, 'plu_sira': yeniSira});
  }

  Future<void> pludanCikar(int urunId) async {
    await alanGuncelle(urunId, {'plu': 0});
  }

  Future<void> pluKartBoyutuDegistir(int urunId, int boyut) async {
    await alanGuncelle(urunId, {'plu_kart_boyut': boyut});
  }

  // ── TEK KAYIT SORGULARI ────────────────────────────────────────────────

  Future<UrunModel?> idileGetir(int id) async {
    final db = await _d;
    final rows = await db.query(
      DbSabitler.urunler,
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : UrunModel.fromMap(rows.first);
  }

  Future<UrunModel?> barkodlaGetir(String barkod) async {
    final db = await _d;
    // 1. Tam barkod eşleşmesi
    var rows = await db.query(
      DbSabitler.urunler,
      where: 'barkod = ? AND is_deleted = 0 AND aktif = 1',
      whereArgs: [barkod],
    );
    if (rows.isNotEmpty) return UrunModel.fromMap(rows.first);
    // 2. barkodlar (virgülle ayrılmış) içinde ara
    rows = await db.rawQuery(
      "SELECT * FROM ${DbSabitler.urunler}"
      " WHERE (',' || barkodlar || ',') LIKE ?"
      "   AND is_deleted = 0 AND aktif = 1 LIMIT 1",
      ['%,$barkod,%'],
    );
    return rows.isEmpty ? null : UrunModel.fromMap(rows.first);
  }

  /// barkodlaGetir() ile AYNI ama pasif (aktif=0) ürünleri de eşleştirir.
  /// POS/barkod okutma akışları BİLEREK sadece aktif ürünleri bulur (pasif
  /// bir ürün satışta görünmemeli) — ama Excel içe aktarımı gibi "bu
  /// barkod zaten kayıtlı mı" kontrolü yapan senaryolarda, pasif bir ürün
  /// de GÜNCELLENMESİ gereken mevcut bir kayıttır. 🔴 Derin analizde
  /// bulundu: Excel içe aktarımı barkodlaGetir()'i (aktif=1 filtreli)
  /// kullandığı için, geçici olarak pasifleştirilmiş bir ürünün fiyat/
  /// stok güncellemesi içeren bir Excel satırı "mevcut ürün bulunamadı"
  /// sanılıp YENİ KAYIT olarak eklenmeye çalışılıyor, barkod sütunundaki
  /// UNIQUE kısıtına takılıp o satır sessizce "hatalı" sayılıyordu —
  /// pasif ürünler Excel ile hiç güncellenemiyordu.
  Future<UrunModel?> barkodlaGetirPasifDahil(String barkod) async {
    final db = await _d;
    var rows = await db.query(
      DbSabitler.urunler,
      where: 'barkod = ? AND is_deleted = 0',
      whereArgs: [barkod],
    );
    if (rows.isNotEmpty) return UrunModel.fromMap(rows.first);
    rows = await db.rawQuery(
      "SELECT * FROM ${DbSabitler.urunler}"
      " WHERE (',' || barkodlar || ',') LIKE ?"
      "   AND is_deleted = 0 LIMIT 1",
      ['%,$barkod,%'],
    );
    return rows.isEmpty ? null : UrunModel.fromMap(rows.first);
  }

  Future<UrunModel?> kodlaGetir(String kod) async {
    final db = await _d;
    final rows = await db.query(
      DbSabitler.urunler,
      where: 'kod = ? AND is_deleted = 0',
      whereArgs: [kod],
    );
    return rows.isEmpty ? null : UrunModel.fromMap(rows.first);
  }

  // ── LİSTE SORGULARI ────────────────────────────────────────────────────

  /// QR menüde gösterilecek/gösterilmeyecek ürünleri toplu olarak
  /// günceller. Kullanıcı isteği: 400 üründen sadece işaretlenenler
  /// (Kafe/Restoran ürünleri gibi) QR menüde görünsün.
  // 🔥 ÖNCEDEN qrMenuSecimleriniKaydet() TEK bir ürünü işaretlemek
  // için bile TÜM ürün ID listesini (4660 ürün!) döngüyle
  // güncelliyordu — kullanıcının yeni isteği doğrultusunda ("anlık
  // ekle/kaldır, ayrı kaydet butonu yok") bu, HER dokunuşta binlerce
  // gereksiz UPDATE çalıştırırdı. Artık tek satırlık, verimli bir
  // fonksiyon var.
  Future<void> qrMenuDurumDegistir(int urunId, bool deger) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    // 🔴🔴 KÖK NEDEN DÜZELTMESİ ("QR menüye ekliyorum, kayboluyor"):
    // Önceden bu fonksiyon SADECE 'qr_menude' sütununu güncelliyordu —
    // 'last_updated' hiç bümlenmiyordu VE BulutManager'a (kuyruğa) hiç
    // haber verilmiyordu. Sonuç: bu değişiklik ASLA buluta gönderilmedi.
    // Arka planda çalışan indirme (buluttan al) döngüsü, bir süre sonra
    // bulut'taki ESKİ değeri (qr_menude=0) geri getirip yerel
    // değişikliğin üzerine sessizce yazıyordu — kullanıcı ürünü
    // ekliyor, birkaç saniye/dakika sonra "kayboluyordu". Artık hem
    // last_updated bümleniyor hem de TAM satır BulutManager'a
    // (upsert kuyruğuna) veriliyor — diğer tüm güncelleme
    // fonksiyonlarıyla AYNI, kanıtlanmış desen.
    await db.update(DbSabitler.urunler,
        {'qr_menude': deger ? 1 : 0, 'last_updated': now},
        where: 'id = ?', whereArgs: [urunId]);
    final guncelSatir = await db.query(DbSabitler.urunler,
        where: 'id = ?', whereArgs: [urunId], limit: 1);
    if (guncelSatir.isNotEmpty) {
      BulutManager().upsert('urunler', Map<String, dynamic>.from(guncelSatir.first));
    }
  }

  // Kullanıcı isteği: "toptan satış tıkladık, o listede gözüksün,
  // diğerleri gözükmesin" — qrMenuDurumDegistir ile AYNI, kanıtlanmış
  // desen (last_updated + BulutManager bildirimi baştan doğru kurulu).
  Future<void> toptanSatistaDurumDegistir(int urunId, bool deger) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.update(DbSabitler.urunler,
        {'toptan_satista': deger ? 1 : 0, 'last_updated': now},
        where: 'id = ?', whereArgs: [urunId]);
    final guncelSatir = await db.query(DbSabitler.urunler,
        where: 'id = ?', whereArgs: [urunId], limit: 1);
    if (guncelSatir.isNotEmpty) {
      BulutManager().upsert('urunler', Map<String, dynamic>.from(guncelSatir.first));
    }
  }

  /// Şu an toptan satışta işaretli olan ürünleri getirir.
  Future<List<UrunModel>> toptanSatisUrunleriGetir() async {
    final db = await _d;
    final rows = await db.query(DbSabitler.urunler,
        where: 'toptan_satista = 1 AND is_deleted = 0', orderBy: 'urun_adi');
    return rows.map(UrunModel.fromMap).toList();
  }

  /// Şu an QR menüde işaretli olan ürünleri getirir (yeni "boş liste,
  /// arayarak ekle" tasarımının başlangıç listesi).
  Future<List<UrunModel>> qrMenuUrunleriGetir() async {
    final db = await _d;
    final rows = await db.query(DbSabitler.urunler,
        where: 'qr_menude = 1 AND is_deleted = 0', orderBy: 'urun_adi ASC');
    return rows.map(UrunModel.fromMap).toList();
  }

  Future<void> qrMenuSecimleriniKaydet(Set<int> secilenIdler, List<int> tumIdler) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      await db.transaction((txn) async {
        for (final id in tumIdler) {
          await txn.update(DbSabitler.urunler,
              {'qr_menude': secilenIdler.contains(id) ? 1 : 0, 'last_updated': now},
              where: 'id = ?', whereArgs: [id]);
        }
      });
      // 🔴 Derin analizde bulundu (şu an kullanılmıyor ama gelecek için
      // düzeltildi): last_updated hiç bump edilmiyordu, BulutManager
      // hiçbir ürün için çağrılmıyordu.
      await _topluBulutSenkronuGonder(tumIdler);
    } catch (e, st) {
      LogServisi().hata('UrunDeposu.qrMenuSecimleriniKaydet', hata: e, yigin: st);
      rethrow;
    }
  }

}
