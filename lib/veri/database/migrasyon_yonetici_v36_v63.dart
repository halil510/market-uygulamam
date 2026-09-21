// lib/veri/database/migrasyon_yonetici_v36_v63.dart
// migrasyon_yonetici.dart'ın parçası — bkz. migrasyon_yonetici_v1_v12.dart
// başındaki not. _calistir() yardımcı fonksiyonu da (tüm parçalar
// tarafından kullanılıyor) bu dosyada.
part of 'migrasyon_yonetici.dart';

// ==================== v36 -> v37 ====================
// Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
// profesyonel sistem." Araştırma sonucu üç katmanlı fiyatlandırma
// (fiyat grubu + miktar kademesi + genel toptan fiyatı) ve koli/
// adet/kg karma birim desteği tasarlandı.
Future<void> _v36denV37e(Database db) async {
  // 1) Fiyat grupları (Altın Bayi, Gümüş Bayi, Standart Toptan gibi)
  await _calistir(db, """
    CREATE TABLE IF NOT EXISTS fiyat_gruplari (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      ad TEXT NOT NULL,
      aciklama TEXT,
      varsayilan_iskonto_orani REAL NOT NULL DEFAULT 0,
      aktif INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      last_updated DATETIME
    )
  """);

  // 2) Ürün × fiyat grubu özel fiyatı (girilmezse grubun varsayılan
  //    iskonto oranı perakende fiyata uygulanır)
  await _calistir(db, """
    CREATE TABLE IF NOT EXISTS urun_fiyat_gruplari (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      urun_id INTEGER NOT NULL,
      fiyat_grubu_id INTEGER NOT NULL,
      fiyat REAL NOT NULL,
      last_updated DATETIME,
      UNIQUE(urun_id, fiyat_grubu_id)
    )
  """);
  await _calistir(db,
      "CREATE INDEX IF NOT EXISTS idx_ufg_urun ON urun_fiyat_gruplari(urun_id)");

  // 3) Miktar bazlı kademeli fiyat (10+ adet X, 50+ adet Y gibi).
  //    fiyat_grubu_id NULL ise TÜM toptan/bayi müşterileri için geçerli.
  await _calistir(db, """
    CREATE TABLE IF NOT EXISTS fiyat_kademeleri (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      urun_id INTEGER NOT NULL,
      fiyat_grubu_id INTEGER,
      min_miktar REAL NOT NULL,
      birim TEXT NOT NULL DEFAULT 'adet',
      fiyat REAL NOT NULL,
      last_updated DATETIME
    )
  """);
  await _calistir(db,
      "CREATE INDEX IF NOT EXISTS idx_fk_urun ON fiyat_kademeleri(urun_id)");

  // 4) Ürün kartına toptan satış alanları
  await _calistir(db,
      "ALTER TABLE urunler ADD COLUMN toptan_fiyat REAL NOT NULL DEFAULT 0");
  await _calistir(db,
      "ALTER TABLE urunler ADD COLUMN koli_ici_miktar REAL NOT NULL DEFAULT 0");
  await _calistir(db,
      "ALTER TABLE urunler ADD COLUMN koli_birim_adi TEXT NOT NULL DEFAULT 'Koli'");
  await _calistir(db,
      "ALTER TABLE urunler ADD COLUMN satis_birimi_tipi TEXT NOT NULL DEFAULT 'adet'");

  // 5) Cari karta bayi/fiyat grubu bağlantısı
  await _calistir(db, "ALTER TABLE cari ADD COLUMN fiyat_grubu_id INTEGER");
  await _calistir(db,
      "ALTER TABLE cari ADD COLUMN musteri_tipi TEXT NOT NULL DEFAULT 'Perakende'");
  // NOT: kredi limiti (limit_tutari) ve vade (vade_gun) ZATEN vardı —
  // bu migrasyon onları eklemiyor, sadece artık AKTİF OLARAK
  // (satış sırasında) kontrol edilecekler (kod tarafında).
}

// ==================== v37 -> v38 ====================
// Kullanıcı isteği: "ürünlerde de buton eklesek — toptan satış
// tıkladık, o listede gözüksün, diğerleri gözükmesin." QR Menü'deki
// 'qr_menude' desenine BİREBİR benzer bir alan.
Future<void> _v37denV38e(Database db) async {
  await _calistir(db,
      "ALTER TABLE urunler ADD COLUMN toptan_satista INTEGER NOT NULL DEFAULT 0");
  await _calistir(db,
      "CREATE INDEX IF NOT EXISTS idx_urunler_toptan_satista ON urunler(toptan_satista)");
}

// ==================== v38 -> v39 ====================
// 🔴🔴 GÜVENLİK AĞI MİGRASYONU: Kullanıcı hâlâ "adisyon_log kimlik
// ataması LOKALE YAZILAMADI" hatası alıyordu — bu, düzeltmenin daha
// önce YANLIŞ bir dbVersiyon numarasıyla (kullanıcının cihazı zaten
// o numaraya ulaşmış olabileceği için migrasyon hiç TETİKLENMEDEN)
// paketlenmiş olabileceğini gösteriyor. SQLite migrasyonları sadece
// eskiVersiyon < yeniVersiyon olduğunda çalışır — cihazdaki sürüm
// numarası koddan ilerideyse, ALTER TABLE'lar hiç işlenmez.
//
// Çözüm: dbVersiyon'u YENİ bir numaraya (39) çıkarmak — bu, cihazın
// önceki durumu ne olursa olsun migrasyonun KESİN çalışmasını
// garantiler. Ayrıca, bu oturumda eklenen TÜM last_updated
// sütunları burada TEKRAR (güvenli/idempotent — _calistir zaten
// "duplicate column" hatasını yutuyor) uygulanıyor; böylece
// hangisinin gerçekten eksik kaldığından bağımsız olarak hepsi
// garanti altına alınmış oluyor.
Future<void> _v38denV39a(Database db) async {
  for (final sql in [
    "ALTER TABLE adisyon_log ADD COLUMN last_updated DATETIME",
    // 🔴 Aynı sınıf hata — bu ikisi de hiç last_updated almamıştı.
    "ALTER TABLE garson_cagri_log ADD COLUMN last_updated DATETIME",
    "ALTER TABLE masa_hareket_log ADD COLUMN last_updated DATETIME",
    "ALTER TABLE borc_odemeler ADD COLUMN last_updated DATETIME",
    "ALTER TABLE borc_odemeler ADD COLUMN tarih DATETIME",
    "ALTER TABLE borc_odemeler ADD COLUMN odeme_yontemi TEXT DEFAULT 'Nakit'",
    "ALTER TABLE borc_odemeler ADD COLUMN referans_no TEXT",
    "ALTER TABLE urunler ADD COLUMN toptan_satista INTEGER NOT NULL DEFAULT 0",
    "ALTER TABLE urunler ADD COLUMN toptan_fiyat REAL NOT NULL DEFAULT 0",
    "ALTER TABLE urunler ADD COLUMN koli_ici_miktar REAL NOT NULL DEFAULT 0",
    "ALTER TABLE urunler ADD COLUMN koli_birim_adi TEXT NOT NULL DEFAULT 'Koli'",
    "ALTER TABLE urunler ADD COLUMN satis_birimi_tipi TEXT NOT NULL DEFAULT 'adet'",
    "ALTER TABLE cari ADD COLUMN fiyat_grubu_id INTEGER",
    "ALTER TABLE cari ADD COLUMN musteri_tipi TEXT NOT NULL DEFAULT 'Perakende'",
  ]) {
    await _calistir(db, sql);
  }
  // audit_log / bildirim_okundu / fiyat_gruplari / urun_fiyat_gruplari /
  // fiyat_kademeleri tabloları da aynı güvenlik ağı mantığıyla
  // garantiye alınıyor (zaten varsa CREATE TABLE IF NOT EXISTS
  // hiçbir şey yapmaz, zararsız).
  await _calistir(db, """
    CREATE TABLE IF NOT EXISTS fiyat_gruplari (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      ad TEXT NOT NULL,
      aciklama TEXT,
      varsayilan_iskonto_orani REAL NOT NULL DEFAULT 0,
      aktif INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      last_updated DATETIME
    )
  """);
  await _calistir(db, """
    CREATE TABLE IF NOT EXISTS urun_fiyat_gruplari (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      urun_id INTEGER NOT NULL,
      fiyat_grubu_id INTEGER NOT NULL,
      fiyat REAL NOT NULL,
      last_updated DATETIME,
      UNIQUE(urun_id, fiyat_grubu_id)
    )
  """);
  await _calistir(db, """
    CREATE TABLE IF NOT EXISTS fiyat_kademeleri (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      urun_id INTEGER NOT NULL,
      fiyat_grubu_id INTEGER,
      min_miktar REAL NOT NULL,
      birim TEXT NOT NULL DEFAULT 'adet',
      fiyat REAL NOT NULL,
      last_updated DATETIME
    )
  """);
  await _calistir(db, """
    CREATE TABLE IF NOT EXISTS audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      tablo_adi TEXT NOT NULL,
      kayit_id TEXT,
      islem_turu TEXT NOT NULL,
      ozet TEXT,
      kullanici_id INTEGER,
      kullanici_adi TEXT,
      cihaz_id TEXT,
      sube_id INTEGER,
      tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated DATETIME
    )
  """);
}

// ==================== v39 -> v40 ====================
// 🔴🔴 Derin analizde bulundu: 'cari_hareket' tablosunda HİÇ silme
// takip sütunu yoktu — CariDeposu.hareketSil() gerçek bir HARD
// DELETE yapıyordu. Bu, senkron sistemi için ciddi bir sorun: silinen
// kayıt buluta hiç bildirilemiyor (silindiğini gösterecek bir alan
// yok), ve bulut→yerel çekişte aynı kayıt "dirilebilir". Bu turda
// bulunan diğer kök neden: hem CariDeposu.hareketEkle() hem de
// SatisDeposu.satisIptal()'daki cari_hareket eklemeleri global_id
// atamıyordu ve BulutManager'ı hiç çağırmıyordu.
Future<void> _v39danV40a(Database db) async {
  await _calistir(db,
      "ALTER TABLE cari_hareket ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0");
  await _calistir(db,
      "CREATE INDEX IF NOT EXISTS idx_cari_hareket_deleted ON cari_hareket(is_deleted)");
}

// ==================== v40 -> v41 ====================
// 🔴 Derin analizde bulundu: 'kategoriler' tablosunda hiç silme
// takibi (is_deleted/aktif) yoktu — kategori silme ekranı gerçek
// HARD DELETE yapıyordu, onay istemeden. 'markalar' tablosunda ise
// last_updated sütunu HİÇ yoktu — bu tablo senkron sisteminde olduğu
// halde değişiklikler asla algılanamıyordu.
Future<void> _v40danV41a(Database db) async {
  await _calistir(db,
      "ALTER TABLE kategoriler ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0");
  await _calistir(
      db, "ALTER TABLE markalar ADD COLUMN last_updated DATETIME");
}

// ==================== v41 -> v42 ====================
// 🔴🔴 KRİTİK/SİSTEMİK DÜZELTME: 'ayarlar' tablosu senkron sisteminde
// olduğu halde SADECE 'guncelleme' sütununa sahipti — ama TÜM
// senkron mekanizması (supabase_sync_servisi.dart) evrensel olarak
// 'last_updated' sütununu arıyor. Bu isim uyuşmazlığı yüzünden
// 'ayarlar' tablosundaki değişikliklerin senkron zamanlaması
// güvenilir çalışmıyordu. last_updated eklendi; mevcut 'guncelleme'
// değerleri ilk migrasyonda kopyalanıyor (veri kaybı olmasın diye).
Future<void> _v41denV42e(Database db) async {
  await _calistir(db, "ALTER TABLE ayarlar ADD COLUMN last_updated DATETIME");
  await _calistir(db,
      "UPDATE ayarlar SET last_updated = guncelleme WHERE last_updated IS NULL");
}

// ==================== v42 -> v43 ====================
// 🔴🔴 KRİTİK GÜVENLİK BULGUSU: 'roller_yetki' (kullanıcıya özel
// yetki override'ları — "bu kullanıcıya normal rolünün dışında şu
// ekstra yetkiyi ver" gibi) tablosu 'rol_yetkileri' (rol şablonları)
// ile KARIŞTIRILMAMALI — bunlar farklı tablolar ve 'roller_yetki'
// senkron sisteminde HİÇ yoktu. Sonuç: bir yönetici bir çalışana
// özel yetki verdiğinde, bu SADECE o cihazda geçerli oluyordu — aynı
// çalışan BAŞKA bir terminalden giriş yaparsa farklı (varsayılan
// rol) yetkilerle karşılaşabiliyordu.
Future<void> _v42denV43e(Database db) async {
  await _calistir(db, "ALTER TABLE roller_yetki ADD COLUMN global_id TEXT");
  await _calistir(
      db, "ALTER TABLE roller_yetki ADD COLUMN last_updated DATETIME");
}

// ==================== v43 -> v44 ====================
// 🔴🔴 SİSTEMİK DÜZELTME (ayarlar.guncelleme ile AYNI hata sınıfı):
// 'subeler' tablosu senkron sisteminde olduğu halde 'updated_at'/
// 'deleted' kullanıyordu — senkron mekanizması evrensel olarak
// 'last_updated'/'is_deleted' arıyor. Şubeler çok şubeli işletmelerde
// EN TEMEL veri — bu isim uyuşmazlığı yüzünden yeni şube eklemek
// diğer cihazlara hiç yansımıyordu.
Future<void> _v43denV44e(Database db) async {
  await _calistir(db, "ALTER TABLE subeler ADD COLUMN last_updated DATETIME");
  await _calistir(db,
      "ALTER TABLE subeler ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0");
  await _calistir(db,
      "UPDATE subeler SET last_updated = updated_at WHERE last_updated IS NULL");
  await _calistir(db,
      "UPDATE subeler SET is_deleted = deleted WHERE deleted IS NOT NULL");
}

// ==================== v44 -> v45 ====================
// 🔴🔴 Derin analizde bulundu: 'masa_rezervasyon' (masa senkron
// sisteminde zaten kayıtlı) tablosunda hiç is_deleted sütunu yoktu —
// RezervasyonServisi.sil() gerçek HARD DELETE yapıyordu ve HİÇBİR
// fonksiyon BulutManager çağırmıyordu. Restoran rezervasyonları
// birden fazla terminal arasında hiç senkronize olmuyordu.
Future<void> _v44denV45e(Database db) async {
  await _calistir(db,
      "ALTER TABLE masa_rezervasyon ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0");
}

// ==================== v45 -> v46 (şube bazlı stok) ====================
// 🔴🔴 Derin analizde bulundu: 'sube_urun' (per-şube stok) tablosu
// şemada VARDI (global_id bile v14→v15'te eklenmişti) ama HİÇBİR
// depo/servis/ekran onu kullanmıyordu — tamamen atıl bir özellikti.
// Ayrıca senkron sisteminin evrensel olarak beklediği 'last_updated'
// yerine 'son_guncelleme' kullanıyordu (ayarlar.guncelleme ile AYNI
// hata sınıfı). Bu migrasyon, tabloyu gerçekten kullanılabilir hale
// getiriyor: last_updated ekleniyor, ve HER ürün için HER aktif
// şubede bir başlangıç satırı oluşturuluyor (mevcut urunler.stok
// değeri, o an aktif tek şubeye ilk değer olarak aktarılıyor —
// birden fazla şube varsa, ilk şubeye tam değer, diğerlerine 0
// verilir; bu sadece bir BAŞLANGIÇ noktasıdır, gerçek dağılımı
// kullanıcı Stok Sayımı ile düzeltmelidir).
Future<void> _v45denV46e(Database db) async {
  await _calistir(
      db, "ALTER TABLE sube_urun ADD COLUMN last_updated DATETIME");
  await _calistir(db,
      "UPDATE sube_urun SET last_updated = son_guncelleme WHERE last_updated IS NULL");
  await _calistir(db,
      "CREATE INDEX IF NOT EXISTS idx_sube_urun_urun ON sube_urun(urun_id)");
  await _calistir(db,
      "CREATE INDEX IF NOT EXISTS idx_sube_urun_sube ON sube_urun(sube_id)");

  try {
    final subeler = await db.query('subeler',
        columns: ['id'], where: 'is_deleted = 0 AND aktif = 1');
    if (subeler.isEmpty)
      return; // Tek şubeli / şube hiç kurulmamış kurulumlarda gerek yok
    final ilkSubeId = subeler.first['id'] as int;
    final urunler = await db.query('urunler',
        columns: ['id', 'stok'], where: 'is_deleted = 0');
    final now = DateTime.now().toIso8601String();
    for (final u in urunler) {
      final urunId = u['id'] as int;
      final toplamStok = (u['stok'] as num?)?.toDouble() ?? 0;
      for (final s in subeler) {
        final subeId = s['id'] as int;
        final mevcut = await db.query('sube_urun',
            where: 'urun_id = ? AND sube_id = ?',
            whereArgs: [urunId, subeId],
            limit: 1);
        if (mevcut.isNotEmpty) continue; // Zaten satırı varsa dokunma
        await db.insert('sube_urun', {
          'urun_id': urunId,
          'sube_id': subeId,
          'stok': subeId == ilkSubeId ? toplamStok : 0,
          'last_updated': now,
          'son_guncelleme': now,
        });
      }
    }
  } catch (_) {
    // Başlangıç verisi oluşturulamazsa sessizce geç — tablo yine de
    // kullanılabilir durumda, sadece başlangıç satırları eksik kalır
    // (StokDeposu ilk hareket sırasında zaten satırı oluşturacak).
  }
}

// ==================== v46 -> v47 ====================
// 🔴🔴 Derin analizde bulundu (gerçek Supabase hatasından):
// 'kredi_kartlari.kart_no_maskeli' bazı (muhtemelen eski/senkronla
// başka cihazdan gelmiş) kayıtlarda NULL kalmıştı — sütun yerelde
// NOT NULL olmasa da, bulut şemasında NOT NULL olduğu için senkron
// "23502 null value violates not-null constraint" hatasıyla
// sürekli başarısız oluyordu. Bu migrasyon, NULL kalan tüm
// kayıtları güvenli bir yer tutucuyla dolduruyor.
Future<void> _v46denV47e(Database db) async {
  await _calistir(
      db,
      "UPDATE kredi_kartlari SET kart_no_maskeli = '**** **** **** ????', last_updated = datetime('now') "
      "WHERE kart_no_maskeli IS NULL OR kart_no_maskeli = ''");
}

// ==================== v47 -> v48 ====================
// 🔴🔴 Derin analizde bulundu (kullanıcı bulgusu — "toptan bölümde
// bayi/müşteri/tedarikçi doğru mu"): 'cari_ekle_ekrani.dart'ta
// "Müşteri Tipi" (Perakende/Bayi/Toptan) alanı cari_tipi ne olursa
// olsun HER ZAMAN gösteriliyordu — saf bir TEDARİKÇİ'ye
// "Bayi"/"Toptan" musteri_tipi atanabiliyordu. Toptan modülü SADECE
// musteri_tipi'ne bakıp cari_tipi'ni HİÇ kontrol etmediği için, bu
// tedarikçiler mantıksız şekilde "toptan satış yapılabilecek bayi"
// listesinde görünüyordu. Form artık bunu engelliyor (yeni
// kayıtlar için); bu migrasyon MEVCUT hatalı kayıtları temizliyor.
Future<void> _v47denV48e(Database db) async {
  await _calistir(db, '''
    UPDATE cari SET musteri_tipi = 'Perakende', last_updated = datetime('now')
    WHERE cari_tipi NOT LIKE '%Müşteri%' AND musteri_tipi IN ('Bayi', 'Toptan')
  ''');
}

// ==================== v48 -> v49 ====================
// 🔴 DERİN ANALİZDE BULUNDU (kullanıcı isteği üzerine ikinci bir
// derinlemesine inceleme): 'irsaliyeler' tablosunda 'last_updated'
// sütunu HİÇ YOKTU (ne ilk kurulum şemasında, ne önceki
// migrasyonlarda) — ama irsaliye_ekrani.dart'taki _durumGuncelle()
// fonksiyonu bu sütuna YAZMAYA ÇALIŞIYORDU. Sonuç: bir irsaliyenin
// durumunu (Bekliyor/Tamamlandı/İptal) değiştirmeye çalışan HER
// kullanıcı "no such column: last_updated" SQL hatası alıyordu —
// durum hiç güncellenmiyor, buluta da hiç gönderilmiyordu (hata,
// BulutManager().upsert() çağrılmadan ÖNCE fırlıyordu). Ayrıca bu
// sütun olmadığı için 'irsaliyeler' _lastUpdatedVar'a hiç
// eklenememişti — bulut şemasında last_updated OLDUĞU HALDE, bu
// tablo için delta (sadece değişenler) senkronu hiç çalışmıyor,
// her "Hızlı Sync"te TÜM irsaliyeler baştan indiriliyordu.
Future<void> _v48denV49a(Database db) async {
  await _calistir(
      db, 'ALTER TABLE irsaliyeler ADD COLUMN last_updated DATETIME');
}

// ==================== v49 -> v50 ====================
// 🔴🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "kredi kartlarında
// sorun var, Supabase'e göndermemiş"): Kök neden bulundu.
// 'bankalar', 'banka_hesaplar', 'kredi_kartlari' (ve aynı şekilde
// 'borclar', 'fiyat_gruplari', 'promosyon_tanim') tabloları bulut
// senkron sistemine SONRADAN eklendi (bkz. supabase_sync_servisi.dart
// içindeki "bu tablolar daha önce hiç senkron listesinde değildi"
// notları). 'global_id' sütunu bu tablolarda EN BAŞTAN beri vardı,
// ama o zamanlar hiçbir kod bu sütuna yazmıyordu — yani senkron
// eklenmeden ÖNCE oluşturulmuş TÜM eski kayıtların global_id'si
// NULL. Model katmanı (BankaModel/KrediKartiModel...toMap()) da
// global_id'yi SADECE zaten doluysa gönderiyor — yani bir eski
// banka/kart düzenlense BİLE global_id hâlâ boş kalıyor.
//
// Somut etki: bir kullanıcı ESKİ bir bankaya (global_id'si NULL)
// bağlı YENİ bir kredi kartı eklediğinde, otomatik (anlık) senkron
// yolu FK dönüşümü için bankanın global_id'sini arıyor, bulamıyor
// (_fkLokalGidCache sadece dolu global_id'li satırları içeriyor) ve
// kredi_kartlari.banka_id'yi OLDUĞU GİBİ (yerel SQLite id'si olarak)
// buluta gönderiyordu. Bulutta banka_id NOT NULL + FOREIGN KEY
// kısıtlaması olduğundan (REFERENCES bankalar(id)), bu kayıt ya
// tamamen REDDEDİLİYOR ya da yanlış bir bankaya bağlanıyordu — kart
// hiç Supabase'e gitmiyordu ya da orada görünmüyordu. Sadece elle
// "Tam Sync — Buluta Gönder" çalıştırmak bunu (o an için) düzeltiyordu
// çünkü SupabaseSyncServisi.bulutaGonder() eksik global_id'leri
// göndermeden önce otomatik dolduruyor — ama otomatik/anlık senkron
// yolu bunu hiç yapmıyordu.
//
// Kalıcı çözüm: bu 6 tabloda global_id'si eksik olan TÜM satırlara,
// bir daha hiç tekrarlanmasın diye, uygulama ilk açılışta KALICI
// bir kimlik atıyor.
Future<void> _v49danV50ye(Database db) async {
  const tablolar = [
    'bankalar',
    'banka_hesaplar',
    'kredi_kartlari',
    'borclar',
    'fiyat_gruplari',
    'promosyon_tanim',
  ];
  for (final tablo in tablolar) {
    try {
      final eksikler = await db.query(
        tablo,
        columns: ['id'],
        where: "global_id IS NULL OR global_id = ''",
      );
      if (eksikler.isEmpty) continue;
      final batch = db.batch();
      for (final row in eksikler) {
        batch.update(
          tablo,
          {'global_id': const Uuid().v4()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {
      // Tablo bu cihazda yoksa/farklıysa sessizce atla — diğer
      // tabloların düzeltilmesini engellemesin.
    }
  }
}

// ==================== v50 -> v51 ====================
// Kullanıcı isteği: "Bayilerden Sipariş Alma" ekranı — ürün arama +
// barkod ile bayiye sipariş alınabilsin, alış fiyatı (maliyet)
// görünür olsun, kalem bazında iskonto yapılabilsin, Adet/Koli/Paket
// gibi birimler için Ölçü Birimleri ekranından tanımlı çarpanlar
// kullanılsın. Sipariş önce "Bekleyen Sipariş" olarak kaydedilir,
// ayrı bir onay ekranından satışa/faturaya/irsaliyeye dönüştürülür.
Future<void> _v50denV51e(Database db) async {
  // 1) Ölçü Birimleri: her birime (Adet, Koli, Paket, Kutu...) kendi
  // çarpanı — "1 Paket = 24 Adet" gibi — tanımlanabilsin. Ana birim
  // (ör. Adet) çarpanı 1 kalır.
  await _calistir(
      db, 'ALTER TABLE birimler ADD COLUMN carpan REAL NOT NULL DEFAULT 1');

  // 2) Bekleyen sipariş başlığı
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS bekleyen_siparisler (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id     TEXT UNIQUE,
      cari_id       INTEGER NOT NULL,
      sube_id       INTEGER,
      kullanici_id  INTEGER,
      tarih         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      durum         TEXT NOT NULL DEFAULT 'bekliyor',
      not_          TEXT,
      ara_toplam    REAL NOT NULL DEFAULT 0,
      iskonto_toplam REAL NOT NULL DEFAULT 0,
      kdv_toplam    REAL NOT NULL DEFAULT 0,
      genel_toplam  REAL NOT NULL DEFAULT 0,
      alis_toplam   REAL NOT NULL DEFAULT 0,
      satis_id      INTEGER,
      created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
      last_updated  DATETIME,
      deleted_at    DATETIME,
      FOREIGN KEY(cari_id) REFERENCES cari(id)
    )
  ''');

  // 3) Bekleyen sipariş kalemleri
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS bekleyen_siparis_kalem (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id     TEXT UNIQUE,
      siparis_id    INTEGER NOT NULL,
      urun_id       INTEGER NOT NULL,
      urun_adi      TEXT NOT NULL,
      birim_adi     TEXT NOT NULL DEFAULT 'Adet',
      birim_carpani REAL NOT NULL DEFAULT 1,
      miktar        REAL NOT NULL,
      toplam_miktar REAL NOT NULL,
      birim_fiyat   REAL NOT NULL,
      alis_fiyat    REAL NOT NULL DEFAULT 0,
      iskonto_oran  REAL NOT NULL DEFAULT 0,
      iskonto_tutar REAL NOT NULL DEFAULT 0,
      kdv_oran      REAL NOT NULL DEFAULT 18,
      toplam_tutar  REAL NOT NULL,
      last_updated  DATETIME,
      FOREIGN KEY(siparis_id) REFERENCES bekleyen_siparisler(id) ON DELETE CASCADE,
      FOREIGN KEY(urun_id) REFERENCES urunler(id)
    )
  ''');

  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_bekleyen_sip_kalem ON bekleyen_siparis_kalem(siparis_id)');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_bekleyen_sip_cari ON bekleyen_siparisler(cari_id)');
}

Future<void> _calistir(Database db, String sql) async {
  try {
    await db.execute(sql);
  } catch (e) {
    final mesaj = e.toString().toLowerCase();
    // 🔴 Derin analizde bulundu: 'syntax error' bu "zararsız/beklenen"
    // listesindeydi — ama bir ALTER/CREATE ifadesindeki gerçek bir SQL
    // yazım hatası HİÇBİR ZAMAN zararsız/idempotent bir durum değildir
    // (aksine 'duplicate column'/'already exists'/'no such column'/
    // 'no such table' — bunlar hep "bu değişiklik zaten uygulanmış"
    // anlamına gelir). 'syntax error'ı burada yutmak, gelecekteki
    // gerçekten bozuk bir migration ifadesini sessizce no-op'a
    // çevirip şemayı eksik bırakabilir — hata çok daha sonra, ilgisiz
    // bir "no such column" çökmesi olarak ve çok daha zor teşhis
    // edilebilir şekilde ortaya çıkardı.
    final bilinen = mesaj.contains('duplicate column') ||
        mesaj.contains('already exists') ||
        mesaj.contains('table already') ||
        mesaj.contains('no such column') ||
        mesaj.contains('no such table');
    if (!bilinen) rethrow;
  }
}

// ══════════════════════════════════════════════════════════════════════
// v51 → v52  (26.07.2026)
//
// SENKRON SÜTUN KAYMASI DÜZELTMESİ
//
// `supabase_sync_servisi._lastUpdatedVar` 9 tabloda 'last_updated'
// olduğunu varsayıyordu ama yerel şemada yoktu. Gönderimde kod sütunu
// payload'a ekliyor (bulutta var, kabul ediliyor), ÇEKERKEN yerel tablo
// kabul etmiyor → "no such column: last_updated" → o tablonun tüm
// partisi düşüyordu. Ayrıca değer yerelde saklanamadığı için delta
// hiç ilerlemiyor, her senkronda tablo baştan iniyordu.
//
// Sütunlar KolonTamamlayici'da tek yerde tanımlı; taze kurulum
// (TabloOlusturucu) ve bu migrasyon aynı listeyi kullanır.
// ══════════════════════════════════════════════════════════════════════
Future<void> _v51denV52ye(Database db) async {
  await KolonTamamlayici.tamamla(db);
  await KolonTamamlayici.indeksle(db);
}

// ══════════════════════════════════════════════════════════════════════
// v53: Toptan satış — "asgari sipariş miktarı" (MOQ). Profesyonel B2B
// sistemlerin standart kuralı: bayi bir üründen tanımlı asgari miktarın
// altında sipariş veremez. 0 = sınır yok (mevcut ürünler etkilenmez).
// ══════════════════════════════════════════════════════════════════════
Future<void> _v52denV53e(Database db) async {
  await _calistir(db,
      "ALTER TABLE urunler ADD COLUMN asgari_siparis_miktari REAL NOT NULL DEFAULT 0");
}

// ══════════════════════════════════════════════════════════════════════
// v54: Sync Çakışmaları — iki cihaz aynı kaydı bağımsız değiştirdiğinde
// (ör. Cihaz A fiyatı 125, Cihaz B aynı anda 129 yapmışsa), senkron
// pull akışı önceden bunu SESSİZCE "son-yazan-kazanır" ile çözüyordu —
// kaybeden değişiklik hiçbir iz bırakmadan kayboluyordu. Artık üzerine
// yazmadan ÖNCE bu tabloya bir çakışma kaydı düşülüyor (Ayarlar → Sync
// Çakışmaları ekranından görülüp A/B/manuel çözülebiliyor); senkron
// DAVRANIŞI (hangi değerin kazanacağı) DEĞİŞMEDİ — sadece artık
// görünür ve denetlenebilir.
// ══════════════════════════════════════════════════════════════════════
Future<void> _v53denV54e(Database db) async {
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS sync_cakismalar (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tablo TEXT NOT NULL,
      kayit_global_id TEXT,
      alan_farklari TEXT,
      yerel_kayit TEXT,
      gelen_kayit TEXT,
      tarih DATETIME NOT NULL,
      cozuldu INTEGER NOT NULL DEFAULT 0,
      cozum_tipi TEXT,
      cozen_kullanici TEXT,
      cozum_tarihi DATETIME
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_sync_cakisma_cozuldu ON sync_cakismalar(cozuldu)');
}

// ==================== v54 -> v55 ====================
// 🔴🔴 KRİTİK SENKRON HATASI (derin analizde bulundu): 'urunler'
// tablosunda İKİ ayrı tetikleyici (trg_urun_updated — yükseltilen
// kurulumlarda, trg_urun_guncelle — yeni kurulumlarda) her UPDATE
// sonrası last_updated'ı datetime('now') ile YENİDEN yazıyordu.
// SQLite'ın datetime('now') fonksiyonu VARSAYILAN OLARAK UTC döner ve
// saat dilimi işareti (Z/±hh:mm) İÇERMEZ — ama uygulama kodu (ör.
// UrunDeposu.guncelle()) last_updated'ı zaten DOĞRU şekilde
// DateTime.now().toIso8601String() (YEREL saat) ile set ediyordu.
// Tetikleyici bu doğru değerin üzerine, saat dilimsiz UTC bir değer
// yazıyordu — Dart'ın DateTime.tryParse()'ı saat dilimi işareti
// olmayan bir string'i YEREL saat olarak yorumlar, yani Türkiye
// (UTC+3) için her ürün güncellemesinin last_updated'ı GERÇEKTEN
// OLDUĞUNDAN ~3 SAAT ESKİ görünüyordu. Bu, last_updated'a dayanan TÜM
// senkron çakışma çözümünü (last-write-wins) etkiliyordu: yerelde
// yapılan gerçekten daha YENİ bir değişiklik, buluttaki daha ESKİ bir
// sürüme karşı yanlışlıkla "kaybedebiliyordu". Uygulama kodu
// last_updated'ı zaten her yazma yolunda doğru şekilde set ettiği
// için bu tetikleyiciler gereksizdi (ve zararlıydı) — kaldırıldı.
Future<void> _v54denV55e(Database db) async {
  await _calistir(db, 'DROP TRIGGER IF EXISTS trg_urun_updated');
  await _calistir(db, 'DROP TRIGGER IF EXISTS trg_urun_guncelle');
}

// v55'ten v56'ya — FAZ 1 madde 2 (Vardiya/Kasa Mutabakatı, kullanıcı
// onayıyla): kasa_hareketleri'nde ödeme yöntemi ayrımı YOKTU — bir satış
// Nakit mi Kart mı ödenmiş fark etmeksizin (Cari hariç) aynı 'Satış'
// hareketine, aynı zincire yazılıyordu. Bu, "kasa bakiyesi" olarak
// gösterilen değerin aslında Nakit+Kart karışımı olmasına yol açıyordu
// (fiziksel kasadaki gerçek nakit değil). Nullable, default'suz TEK
// sütun — mevcut hiçbir sorgu/rapor bu sütunu okumadığı için sessizce
// NULL kalır, davranış değişmez. Eski kayıtlar KASITLI OLARAK NULL
// bırakıldı (geriye dönük "tahmin" yapılmadı — bkz. rapor: karma
// ödemeli eski satışlarda hangi kasa hareketinin hangi ödeme parçasına
// ait olduğu bilgisi kayıp, yanlış backfill'den kaçınıldı).
Future<void> _v55denV56ya(Database db) async {
  await _calistir(
      db, 'ALTER TABLE kasa_hareketleri ADD COLUMN odeme_yontemi TEXT');
}

// v56'dan v57'ye — FAZ 9 (Onay Merkezi, kullanıcı onayıyla): sekiz
// riskli akışta (yüksek iskonto, yüksek iade, risk limiti aşımı, kasa
// çıkışı, fiyat değişimi, stok düzeltme, yüksek gider, borç silme)
// eşik aşıldığında işlem NORMAL TAMAMLANIR — bu tablo sadece BİLDİRİM
// amaçlı, hiçbir akışı ENGELLEMEZ/kesintiye uğratmaz. Mevcut hiçbir
// tabloya dokunmuyor, tamamen izole yeni bir tablo.
Future<void> _v56denV57ye(Database db) async {
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS onay_talepleri (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      tur TEXT NOT NULL,
      referans_turu TEXT,
      referans_id INTEGER,
      tutar REAL,
      esik_tutar REAL,
      aciklama TEXT,
      kullanici_id INTEGER,
      kullanici_adi TEXT,
      sube_id INTEGER,
      tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      goruldu INTEGER NOT NULL DEFAULT 0,
      goren_kullanici_id INTEGER,
      goruldu_tarihi DATETIME,
      last_updated DATETIME,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_onay_talepleri_goruldu ON onay_talepleri(goruldu, tarih DESC)');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_onay_talepleri_tur ON onay_talepleri(tur)');
}

// v58 — Bayi Portalı (erp_roadmap madde 39, kullanıcı onayıyla "aynı
// uygulama içinde Bayi rolü"): kullanicilar.rol'ün CHECK kısıtına
// dokunmadan (mevcut tabloyu yeniden oluşturmak riskli olurdu), yeni
// nullable bir kolon — bir kullanıcı bu alanda bir cari.id taşıyorsa
// "bayi" modundadır (rol hâlâ 'personel' kalabilir, CHECK ihlali yok).
Future<void> _v57denV58e(Database db) async {
  await _calistir(db,
      'ALTER TABLE kullanicilar ADD COLUMN bayi_cari_id INTEGER REFERENCES cari(id)');
}

// 🔴🔴 KRİTİK DÜZELTME (Borç Silme özelliği eklenirken bulundu — dosya
// yolları arası şema sapması): fresh-install şeması (semalar/borc_semasi
// .dart) 'borclar' tablosuna is_deleted sütununu baştan koyuyordu, ama
// BU migrasyon zincirindeki CREATE TABLE (yukarıda ~satır 1096, borç
// takip modülü ilk eklendiğinde) is_deleted'i HİÇ İÇERMİYORDU ve hiçbir
// sonraki migrasyon adımı da eklemiyordu. Sonuç: borç takip modülü bir
// önceki sürümden YÜKSELTİLEREK gelen (yani neredeyse tüm gerçek
// kullanıcı) cihazlarda is_deleted sütunu HİÇ YOKTU — BorcDeposu.sil()
// (ve is_deleted=0 filtresi kullanan tumunuGetir/idileGetir/
// vadesiGecenleriGetir/yaklasanlariGetir) bu cihazlarda "no such column:
// is_deleted" hatasıyla çökerdi. Borç Silme özelliği bu sütuna bağımlı
// olduğu için önce bu kök neden düzeltildi.
Future<void> _v58denV59a(Database db) async {
  await _calistir(db,
      'ALTER TABLE borclar ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
}

// v59'dan v60'a — güvenlik düzeltmesi: parmak izi ile giriş ÖNCEDEN
// kullanıcının ham şifresini FlutterSecureStorage'a yazıyordu (OS
// seviyesinde şifreli ama yine de düz metin şifre). Artık şifre hiç
// saklanmıyor; her cihaz için rastgele üretilen 256-bit bir "biyometrik
// token" tuzlanıp hash'i bu YENİ, tamamen İZOLE ve bilerek Supabase'e
// senkron EDİLMEYEN tabloya yazılıyor (cihaza özel bir sır — başka
// cihaza/kullanıcıya sızması anlamsız/riskli olurdu, bu yüzden
// supabase_sync_servisi.dart'ın tablo listesine BİLİNÇLİ OLARAK
// eklenmedi). kullanicilar tablosuna dokunulmuyor.
Future<void> _v59denV60a(Database db) async {
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS biyometrik_kayitlar (
      kullanici_id INTEGER PRIMARY KEY REFERENCES kullanicilar(id),
      token_hash TEXT NOT NULL,
      tuz TEXT NOT NULL,
      olusturma_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
}

// v60'tan v61'e — e-Belge durum makinesi genişletmesi (erp_roadmap madde
// 38, 2026-09-14 derin analiz). GİB bir e-Faturayı REDDEDERSE, kullanıcı
// aynı faturayı düzeltip yeniden göndermek isteyebilir. Ama gib_servisi
// .dart'taki ETTN, faturanın global_id'sinden DETERMİNİSTİK üretiliyor
// (mükerrer gönderim korumasının kalbi — bkz. o dosyadaki not) — yani
// düzeltmeden sonra yeniden gönderilse bile AYNI ETTN kullanılırdı, ki
// bu bir entegratörün "zaten reddedilmiş bu belgeyi" diye ikinci kez
// reddetmesine ya da kafa karışıklığına yol açabilir. Bu sayaç, SADECE
// bir RET sonrası yeniden gönderimde artırılıp ETTN'ye karıştırılıyor —
// network hatası sonrası yapılan (GİB'e hiç ulaşmamış) normal
// tekrar denemelerde sayaç ARTMIYOR, o yüzden mevcut "kazara çift
// gönderim" koruması BOZULMUYOR.
Future<void> _v60danV61e(Database db) async {
  await _calistir(db,
      'ALTER TABLE faturalar ADD COLUMN e_fatura_deneme_no INTEGER NOT NULL DEFAULT 0');
}

// v61'den v62'ye — e-İrsaliye GİB gönderimi (kullanıcı isteği, 2026-09-14
// derin analiz: "e irsaliye türkiyeye göre tam doğru olmalı"). Ayarlar'da
// ÖNCEDEN "e-İrsaliye Aktif" anahtarı vardı ama hiçbir kod göndermiyordu —
// tamamen süslemelikti. faturalar tablosuyla AYNI desende (e_fatura_*)
// yeni sütunlar eklendi.
Future<void> _v61denV62ye(Database db) async {
  await _calistir(db, "ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_durum TEXT DEFAULT 'hazir'");
  await _calistir(db, 'ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_uuid TEXT');
  await _calistir(db, 'ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_xml TEXT');
  await _calistir(db, 'ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_deneme_no INTEGER NOT NULL DEFAULT 0');
  await _calistir(db, 'ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_gonderim_tarihi DATETIME');
}

// ==================== v62 -> v63 ====================
// 🔴🔴🔴 KRİTİK VERİ BOZULMASI (komple uygulama derin analizinde
// bulundu — v54→v55'teki 'trg_urun_updated' düzeltmesiyle AYNI SINIF
// hata, farklı bir tetikleyicide): 'cari' bakiyesini her yeni
// cari_hareket eklendiğinde otomatik yeniden hesaplayan tetikleyici
// (yükseltilen kurulumlarda 'trg_cari_bakiye_ins', taze kurulumlarda
// 'trg_cari_hareket_bakiye' — semalar/diger_semasi.dart) SUM
// sorgusunda 'is_deleted = 0' FİLTRESİ İÇERMİYORDU. Oysa uygulamanın
// HER YERDEKİ (CariDeposu.hareketEkle/bakiyeYenidenHesapla, Veri
// Sağlığı Merkezi mutabakatı, cari_hareket_ekrani.dart'taki iptal
// akışı, iade_ekrani_gecmis.dart'taki 3 iade-iptal noktası) KANONİK
// kuralı şudur: soft-delete edilmiş (is_deleted=1, ör. iptal edilmiş
// bir tahsilat/iade) bir hareket bakiyeye HİÇ katkı vermemeli.
//
// Bu "kanonik" uygulama kodu yollarının HEPSİ, kendi INSERT'lerinden
// HEMEN SONRA, AYNI transaction içinde, DOĞRU (is_deleted=0 filtreli)
// bir UPDATE ile bakiyeyi kendileri yeniden hesaplıyor — bu yüzden
// tetikleyicinin ürettiği YANLIŞ ara değer, o an İÇİN her zaman
// hemen üzerine yazılıp gizleniyordu.
//
// AMA TEK BİR YOL bunu YAPMIYOR: Veritabani.supaKayitlariEkle() —
// yani BULUTTAN GELEN cari_hareket satırlarını (başka bir cihazda
// oluşturulmuş) bu cihaza EKLERKEN kullanılan GENEL/JENERİK toplu
// ekleme yolu. Bu yol, hiçbir tabloya özel takip mantığı içermez;
// sadece INSERT eder. Sonuç: bir müşterinin GEÇMİŞTE iptal edilmiş
// (is_deleted=1) bir hareketi varsa, o müşteri için BAŞKA bir
// cihazdan senkronize olan HERHANGİ bir YENİ cari_hareket (normal bir
// satış, tahsilat, ödeme — iptalle hiç ilgisi olmayan bir işlem),
// "Hızlı Al"/"Tam Al" sırasında bu tetikleyiciyi ateşleyip müşterinin
// bakiyesini o ESKİ, İPTAL EDİLMİŞ tutar kadar YANLIŞ şişiriyordu —
// sessizce, kalıcı olarak, sadece "Veri Sağlığı Merkezi > Cari
// Mutabakat > Düzelt" ile fark edilip düzeltilebilecek şekilde.
//
// Düzeltme: her iki olası isimdeki eski, hatalı tetikleyici DROP
// edilip, is_deleted=0 filtresi eklenmiş TEK bir doğru tetikleyici
// (fresh-install ile AYNI ada sahip: trg_cari_hareket_bakiye) yeniden
// oluşturuluyor. Kasıtlı olarak MEVCUT (muhtemelen zaten bozulmuş)
// bakiye değerleri burada OTOMATİK toplu düzeltilmiyor — bu
// dosyanın/protokolün "hiçbir kontrol kullanıcı onayı olmadan veri
// değiştirmez" ilkesiyle tutarlı olarak, kullanıcı bunu Veri Sağlığı
// Merkezi'nden kendi onayıyla çalıştırır.
Future<void> _v62denV63e(Database db) async {
  await _calistir(db, 'DROP TRIGGER IF EXISTS trg_cari_bakiye_ins');
  await _calistir(db, 'DROP TRIGGER IF EXISTS trg_cari_hareket_bakiye');
  await _calistir(db, """CREATE TRIGGER trg_cari_hareket_bakiye
    AFTER INSERT ON cari_hareket BEGIN
    UPDATE cari SET bakiye = (
      SELECT COALESCE(SUM(borc - alacak), 0) FROM cari_hareket
      WHERE cari_id = NEW.cari_id AND is_deleted = 0
    ) WHERE id = NEW.cari_id; END""");
}

// v63'ten v64'e — fis_seri (fiş/irsaliye/sipariş numara sayacı) artık
// buluta senkronize oluyor.
//
// 🔴 Derin analizde bulundu: fis_seri tablosu senkron sisteminin
// TAMAMEN DIŞINDAYDı (global_id/last_updated hiç yoktu, ne push ne pull
// yolunda hiç göründü) — aynı şubede birden fazla POS cihazı kullanılan
// kurulumlarda her cihaz kendi lokal sayacını tutuyordu, biri diğerinin
// ürettiği numaralardan habersizdi. son_fis_no bir SAYAÇ olduğu için bu
// tabloyu projenin standart global_id tabanlı, "son güncelleme kazanır"
// senkron yoluna sokmak YANLIŞ olur: iki cihaz aynı şubede farklı
// zamanlarda senkron olursa, geç senkron olan cihazın DAHA KÜÇÜK yerel
// sayacı, buluttaki DAHA BÜYÜK sayacın üzerine yazıp aynı numaraların
// tekrar üretilmesine yol açabilirdi. last_updated eklendi (yalnızca
// push zamanlaması için); asıl güvenlik MAX-birleştirme'de —
// bkz. veritabani.dart.fisNoUret() ve _fisSeriBulutlaUyumla().
Future<void> _v63denV64e(Database db) async {
  await _calistir(db, 'ALTER TABLE fis_seri ADD COLUMN last_updated TEXT');
}

// ==================== v64 -> v65 ====================
// MASTER ERP DEEP AUDIT — Madde 5 (Senkronizasyon) sertleştirmesi:
// 'sync_queue' tablosu ÖNCEDEN de kuruluyordu (bkz. sync_semasi.dart) ama
// hiçbir kod ona yazmıyordu — gerçek kuyruk BulutManager._kuyruk adlı
// RAM-only bir listeydi, uygulama çökerse henüz gönderilmemiş kayıtlar
// kalıcı olarak kayboluyordu. BulutManager artık bu tabloyu tek kaynak
// olarak kullanıyor; 'hata_mesaji' son başarısız deneme mesajını
// görünür kılmak için eklendi (taze kurulumlar zaten sync_semasi.dart
// üzerinden bu kolonla geliyor — bu migrasyon SADECE mevcut cihazlar
// içindir).
Future<void> _v64denV65e(Database db) async {
  await _calistir(db, 'ALTER TABLE sync_queue ADD COLUMN hata_mesaji TEXT');
}

// ==================== v65 -> v66 ====================
// MASTER ERP DEEP AUDIT — Madde 3 (Veritabanı Denetimi): "kritik hareket
// tabloları" (satış/stok/cari/kasa/iade/fatura/tedarik/vardiya) PRIMARY
// KEY/global_id/UNIQUE/last_updated/is_deleted/deleted_at/sube_id
// açısından tarandı — bu alanların hepsi zaten mevcuttu. Bulunan GERÇEK
// eksikler INDEX tarafındaydı: bu tablolardaki en sık çalışan sorgu
// kalıpları (kasa bakiye hesabı, iade/fatura/irsaliye detay ekranları,
// tedarikçi sipariş listesi, vardiya aktif/geçmiş sorgusu) hiç
// indekslenmemiş sütunlarda filtreleme yapıyordu — veri büyüdükçe tam
// tablo taraması (full table scan) kaçınılmazdı. Liste, taze kurulum
// tarafının (IndexSemasi._indeksler) BİREBİR aynısıdır — bkz. o
// dosyadaki "Madde 3" notu.
//
// 🔴 BİLİNÇLİ OLARAK YAPILMAYAN: yeni FOREIGN KEY eklenmedi. İki sebep:
// (1) SQLite ALTER TABLE'ın kendisi mevcut bir tabloya FK constraint
// eklemeyi DESTEKLEMEZ (tablo yeniden oluşturulup veri kopyalanmadan
// mümkün değil — "mevcut verileri bozmadan güvenli" ilkesiyle çelişir).
// (2) Bu kod tabanında (bkz. SatisDeposu.satisEkleTxn'deki cari_id/
// sube_id/kasiyer_id doğrulama notu) FK ihlalleri ÇOK ŞUBELİ/ÇOK
// CİHAZLI SENKRONDA gerçek production hatalarına yol açtığı için
// KASITLI OLARAK stok_hareket/kasa_hareketleri gibi tablolarda hareket
// satırlarının referans kolonlarına hiç FK konulmamış — bir cihazda
// henüz senkronlanmamış bir kullanıcı/şube/lot'a referans veren bir
// hareket, FK varsa INSERT anında patlar. Yeni FK eklemek bu bilinçli
// tasarımı bozar ve aynı hata sınıfını yeniden üretir.
Future<void> _v65denV66ya(Database db) async {
  const indeksler = [
    'CREATE INDEX IF NOT EXISTS idx_kasa_sube_silinmemis ON kasa_hareketleri(sube_id, deleted_at)',
    'CREATE INDEX IF NOT EXISTS idx_kasa_referans ON kasa_hareketleri(referans_id, referans_turu)',
    'CREATE INDEX IF NOT EXISTS idx_stokh_referans ON stok_hareket(referans_id, referans_turu)',
    'CREATE INDEX IF NOT EXISTS idx_carih_fis ON cari_hareket(fis_id, cari_id)',
    'CREATE INDEX IF NOT EXISTS idx_iade_kalem_iade ON iade_kalem(iade_id)',
    'CREATE INDEX IF NOT EXISTS idx_fatura_detay_fatura ON fatura_detaylari(fatura_id)',
    'CREATE INDEX IF NOT EXISTS idx_irsaliye_kalem_irsaliye ON irsaliye_kalem(irsaliye_id)',
    'CREATE INDEX IF NOT EXISTS idx_tedsip_durum ON tedarikci_siparisler(durum)',
    'CREATE INDEX IF NOT EXISTS idx_tedsip_cari ON tedarikci_siparisler(cari_id)',
    'CREATE INDEX IF NOT EXISTS idx_tedsip_kalem_siparis ON tedarikci_siparis_kalem(siparis_id)',
    'CREATE INDEX IF NOT EXISTS idx_vardiya_sube_kapanis ON vardiyalar(sube_id, kapanis_tarihi)',
    'CREATE INDEX IF NOT EXISTS idx_vardiya_kullanici ON vardiyalar(kullanici_id)',
  ];
  for (final sql in indeksler) {
    await _calistir(db, sql);
  }

  // 'vardiyalar' tablosunda deleted_at/is_deleted hiç yoktu — Madde 3
  // kontrol listesinin istediği soft-delete alanı tamamlandı. Şu an
  // hiçbir kod bir vardiyayı silmiyor (audit amaçlı kalıcı kayıt) — bu
  // sütun ileride bir "yanlışlıkla açılan vardiyayı iptal et" özelliği
  // için hazırlık, nullable olduğu için mevcut hiçbir sorguyu etkilemez.
  await _calistir(db, 'ALTER TABLE vardiyalar ADD COLUMN deleted_at DATETIME');
}

// ==================== v66 -> v67 ====================
// MASTER ERP DEEP AUDIT — Madde 25/26 (Performans / Database Index
// Audit): cari_hareket_ekrani.dart (cari ekstre ekranı) doğrudan
// Veritabani().db üzerinden 'SELECT * FROM cari_hareket WHERE cari_id=?
// AND is_deleted=0 ORDER BY tarih DESC' çalıştırıyordu — HİÇ LIMIT yoktu
// ve mevcut ayrı cari_id/is_deleted indeksleri bu bileşik sorguyu tek
// geçişte karşılamıyordu. Ekran artık CariDeposu.hareketleriniGetir()
// (mevcut, sınırlı/parametrik repository metodu) üzerinden güvenli bir
// tavanla (5000) çağırıyor; bu bileşik indeks o sorguyu (ve aynı deseni
// kullanan her yeri) hızlandırır.
Future<void> _v66danV67ye(Database db) async {
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_carih_cari_silinmemis_tarih ON cari_hareket(cari_id, is_deleted, tarih)');
}

// ==================== v67 -> v68 ====================
// YIL SONU DEVİR / DÖNEM KAPATMA / ARŞİVLEME SİSTEMİ — FAZ 1 (2026-09-16,
// kullanıcı onaylı mimari plan raporu). Mevcut kurulumlar için 7 yeni
// tablo — tanımlar donem_semasi.dart (fresh install) ile BİREBİR aynı,
// tek doğruluk kaynağı orası; buradaki SQL'ler o dosyadan kopyalanmıştır.
// Devir motoru mantığı (DevirYoneticiServisi) İLERİKİ bir fazda gelecek —
// bu migrasyon SADECE şemayı hazırlar.
Future<void> _v67denV68e(Database db) async {
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS donemler (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      donem_yili INTEGER NOT NULL UNIQUE,
      baslangic_tarihi TEXT NOT NULL,
      bitis_tarihi TEXT NOT NULL,
      durum TEXT NOT NULL DEFAULT 'OPEN',
      kapanis_tarihi TEXT,
      kapanisi_yapan_kullanici_id INTEGER,
      kapanis_cihazi TEXT,
      backup_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      arsiv_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      devir_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_donem_yili ON donemler(donem_yili)');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_donem_durum ON donemler(durum)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS donem_sube_durumlari (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL,
      durum TEXT NOT NULL DEFAULT 'OPEN',
      kapanis_tarihi TEXT,
      kapanisi_yapan_kullanici_id INTEGER,
      kapanis_cihazi TEXT,
      backup_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      arsiv_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      devir_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      last_updated TEXT,
      UNIQUE(donem_id, sube_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_donemsube_donem ON donem_sube_durumlari(donem_id)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS devir_checkpoint (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL UNIQUE,
      kaynak_donem_id INTEGER NOT NULL,
      hedef_donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL DEFAULT 0,
      durum TEXT NOT NULL DEFAULT 'INIT',
      mevcut_faz INTEGER NOT NULL DEFAULT 0,
      faz_ilerleme_json TEXT,
      baslangic_zamani TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      son_guncelleme TEXT,
      tamamlanma_zamani TEXT,
      hata_mesaji TEXT,
      last_updated TEXT,
      UNIQUE(kaynak_donem_id, hedef_donem_id, sube_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_devir_durum ON devir_checkpoint(durum)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS stok_kapanis_snapshot (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL,
      donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL,
      urun_id INTEGER NOT NULL,
      miktar REAL NOT NULL,
      kaynak_hash TEXT,
      olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, sube_id, urun_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_stoksnap_donem ON stok_kapanis_snapshot(donem_id, sube_id)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS cari_kapanis_snapshot (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL,
      donem_id INTEGER NOT NULL,
      cari_id INTEGER NOT NULL,
      bakiye REAL NOT NULL,
      kaynak_hash TEXT,
      olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, cari_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_carisnap_donem ON cari_kapanis_snapshot(donem_id)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS kasa_kapanis_snapshot (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL,
      donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL,
      bakiye REAL NOT NULL,
      kaynak_hash TEXT,
      olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, sube_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_kasasnap_donem ON kasa_kapanis_snapshot(donem_id)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS banka_kapanis_snapshot (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL,
      donem_id INTEGER NOT NULL,
      banka_hesap_id INTEGER NOT NULL,
      bakiye REAL NOT NULL,
      kaynak_hash TEXT,
      olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, banka_hesap_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_bankasnap_donem ON banka_kapanis_snapshot(donem_id)');
}

// Madde 12 denetimi (2026-09-16, kullanıcı onaylı UX: "Anında PIN
// onayı") — Kasa Kapanış'ta "Müdür Onayı" alanı. Vardiyayı kapatan
// kişi Müdür/Admin değilse, kapanış anında bir yöneticinin kimlik
// bilgileriyle (KullaniciDeposu.girisKontrol) onayladığı kullanıcı
// burada kaydedilir — Müdür/Admin kendi vardiyasını kapatırken bu
// adım atlanır (zaten yetkili).
Future<void> _v68denV69a(Database db) async {
  await _calistir(
      db, 'ALTER TABLE vardiyalar ADD COLUMN onaylayan_kullanici_id INTEGER');
  await _calistir(
      db, 'ALTER TABLE vardiyalar ADD COLUMN onaylanma_tarihi TEXT');
}

// v69'dan v70'e — Yıl Sonu Devir çoklu cihaz kilidi (2026-09-21,
// kullanıcı onayı, FAZ 4). Tanım donem_semasi.dart (fresh install) ile
// BİREBİR aynı, tek doğruluk kaynağı orası.
Future<void> _v69danV70e(Database db) async {
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS donem_kilit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL DEFAULT 0,
      cihaz_id TEXT NOT NULL,
      kilit_zamani TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      son_yenileme TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, sube_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_donemkilit_donem ON donem_kilit(donem_id)');
}

// v70'den v71'e — DEEP_AUDIT_REPORT FAZ 5 (Performans, 2026-09-21):
// FEFO satış düşümü lot_seri'de hiç indekslenmemiş bir sorgu
// çalıştırıyordu (bkz. index_semasi.dart'taki aynı gerekçe — o dosya
// sadece TAZE kurulumları kapsar, mevcut cihazlar için bu migrasyon
// gerekli).
Future<void> _v70denV71e(Database db) async {
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_lot_seri_urun_aktif ON lot_seri(urun_id, aktif)');
}
