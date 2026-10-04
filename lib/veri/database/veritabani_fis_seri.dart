// lib/veri/database/veritabani_fis_seri.dart
//
// veritabani.dart'ın parçası (part/part of) — fiş/irsaliye/sipariş numara üretimi ve fis_seri bulut uyumu.
// Davranış BİREBİR aynı: Veritabani üzerine extension; private üyelere aynı
// kütüphane olduğu için erişir.
part of 'veritabani.dart';

// Önceden Veritabani içinde static alandı; kütüphane düzeyinde (aynı tek örnek).
DateTime? _sonFisSeriUyum;

extension VeritabaniFisSeri on Veritabani {
  // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu fonksiyon
  // ÖNCEDEN 'WHERE sube_id = 1' olarak SABİT KODLANMIŞTI — uygulama
  // çoklu şube desteklediği (AktifSubeServisi, şube filtreleri her
  // yerde) halde, hangi şube aktif olursa olsun fiş numaralandırma
  // HER ZAMAN 1 numaralı şubenin sayacını kullanıyordu. Bir yönetici
  // aynı cihazdan farklı şubeler arasında geçiş yaptığında, fiş
  // numaraları o şubeye göre doğru sıralanmıyordu — Türkiye'de
  // e-fatura/e-irsaliye için şube bazlı sıralı numaralandırma yasal
  // bir gereklilik olabilir. Artık [subeId] parametre olarak alınıyor;
  // çağıran taraf vermezse (geriye dönük uyumluluk) varsayılan 1'dir.
  // 🔴 Derin analizde bulundu (P1 #11): fis_seri TAMAMEN yerel bir
  // sayaçtı — aynı şubede birden fazla POS terminali kullanılıyorsa her
  // biri kendi sayacını tutuyordu, biri diğerinin ürettiği numaradan
  // habersizdi. Aşağıdaki iki adım riski azaltır ama TAM bulletproof
  // DEĞİLDİR — iki terminal TAMAMEN AYNI ANDA, ikisi de offlineyken sayaç
  // üretirse çakışma yine mümkündür (çevrimdışı-öncelikli bir mimaride
  // kaçınılmaz bir ödünleşim; kesin çözüm online zorunluluğu getirir ki
  // bu, uygulamanın temel "internet olmadan da satış yapılabilir"
  // ilkesini bozar — bkz. kullanıcıyla yapılan görüşme):
  //   1) fisNoUret'in KENDİSİ ağdan ASLA etkilenmez/beklemez —
  //      _fisSeriBulutlaUyumla() burada unawaited'tir, sadece BİR
  //      SONRAKİ çağrıya fayda sağlar, mevcut satışı yavaşlatmaz/offline'ı
  //      bozmaz.
  //   2) Yeni sayaç DEĞERİ üretildikten (transaction commit olduktan)
  //      SONRA buluta best-effort itilir; Supabase tarafındaki BEFORE
  //      UPDATE tetikleyicisi (bkz. Supabase şema dosyası) son_fis_no'nun
  //      ASLA küçülmemesini (GREATEST) garanti eder — iki terminal farklı
  //      sırayla/farklı zamanlarda senkron olsa bile büyük olan değer
  //      kazanır, küçük bir yerel değer büyük olanın üzerine yazamaz.
  // Bilerek projenin genel "son_updated kazanır" senkron mekanizmasından
  // (SupabaseSyncServisi._tabloSirasi) AYRI, özel bir yol kullanıldı —
  // bir SAYAÇ için "son güncelleyen kazanır" semantiği YANLIŞTIR (geç
  // senkron olan küçük bir yerel değer, zaten kullanılmış büyük bir
  // numarayı sessizce geri alıp numara çakışmasına yeniden yol açabilir).
  Future<String> fisNoUret(String tip, {int subeId = 1}) async {
    unawaited(_fisSeriBulutlaUyumla());
    final database = await db;
    late final int yeniNo;
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — ekran görüntüsü:
    // "DatabaseException(FOREIGN KEY constraint failed (code 787 ...))
    // sql 'INSERT INTO fis_seri(sube_id, fis_tipi, son_fis_no)
    // VALUES(?, ?, ?)' args [1, satis, 1]"): fis_seri.sube_id,
    // subeler(id)'ye FK ile bağlı — bu fonksiyon HER ZAMAN subeId (ya da
    // varsayılan 1) ile INSERT/UPDATE deniyordu. O id'de GERÇEKTEN bir
    // şube yoksa (ör. "Veritabanını Temizle" sonrası oluşan bir
    // ara/yarış durumu, ya da subeler tablosu her nasılsa boşaldıysa)
    // INSERT anında FK ihlaliyle patlıyor ve kullanıcı HİÇ SATIŞ
    // YAPAMAZ hale geliyordu — satış ekranı sürekli "Satış hatası"
    // veriyordu. Artık kullanılan sube_id'nin GERÇEKTEN var olduğu
    // doğrulanıyor; yoksa mevcut ilk şubeye, o da yoksa yeni oluşturulan
    // bir "Merkez Şube"ye düşülüyor — kendi kendini onaran, satışı asla
    // engellemeyen bir yol.
    final gecerliSubeId = await _gecerliSubeIdGetir(database, subeId);
    // Kasa (terminal) bazlı numara serisi (2026-09-27, kullanıcı onaylı):
    // aynı şubedeki iki kasa İNTERNETSİZKEN aynı sayaçtan aynı fiş no'yu
    // üretebiliyordu — diğer kasanın gerçek satışı senkronda "kopya"
    // sanılıp raporlardan gizleniyordu. Artık her kasanın kendi sayacı
    // (fis_seri'de 'satis#T03' gibi anahtar — şema değişmedi) ve numarada
    // 2 haneli kasa no var: MKP 2026 03 0000012 (yine 16 hane → fiş barkodu
    // ve kısa gösterim çalışmaya devam eder). Terminal kaydı olmayan
    // cihaz eski biçimle (kasa no yok) devam eder. Fatura (GİB biçimi)
    // hariç — onun numarası merkezi blok sisteminden gelir.
    final kasaNo = tip == 'fatura' ? 0 : await _kasaNoGetir(database);
    final seriAnahtari =
        kasaNo > 0 ? '$tip#T${kasaNo.toString().padLeft(2, '0')}' : tip;
    final sonuc = await database.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT son_fis_no FROM ${DbSabitler.fisSeri} WHERE sube_id = ? AND fis_tipi = ?',
        [gecerliSubeId, seriAnahtari],
      );
      final sonNo =
          result.isNotEmpty ? (result.first['son_fis_no'] as int) : 0;
      final now = DateTime.now();
      // GIB Türkiye e-Fatura/e-Arşiv standartı:
      // Fatura: [A-Z]{3}[0-9]{4}[0-9]{9} = 3 harf + 4 yıl rakamı + 9 sıra no
      // Örnek: MKP2024000000001
      final prefix = switch (tip) {
        'satis'     => 'MKP',
        'masa'      => 'MSA',
        'cari_satis'=> 'CRI',
        'fatura'    => 'FAT',
        'irsaliye'  => 'IRS',
        'alim'      => 'ALM',
        'iade'      => 'IAD',
        'siparis'   => 'SIP',
        _ => tip.toUpperCase().substring(0, min(3, tip.length)).padRight(3, 'X'),
      };
      final yil = now.year.toString();
      String noYap(int n) => kasaNo > 0
          ? '$prefix$yil${kasaNo.toString().padLeft(2, '0')}${n.toString().padLeft(7, '0')}'
          : '$prefix$yil${n.toString().padLeft(9, '0')}';
      var aday = sonNo + 1;
      // 🔴 DÜZELTME (2026-09-27): sayaç, başka cihazdan senkronlanmış bir
      // satışın zaten kullandığı numarayı yeniden verebiliyordu.
      // satislar.fis_no UNIQUE olduğu için bu satışı patlatırdı.
      // Yerelde kullanılmış numaralar atlanır.
      if (tip == 'satis' || tip == 'cari_satis' || tip == 'masa') {
        for (var deneme = 0; deneme < 10000; deneme++) {
          final kullanilmis = await txn.rawQuery(
              'SELECT 1 FROM ${DbSabitler.satislar} WHERE fis_no = ? LIMIT 1',
              [noYap(aday)]);
          if (kullanilmis.isEmpty) break;
          aday++;
        }
      }
      yeniNo = aday;
      if (result.isEmpty) {
        // Satır yoksa ekle
        await txn.rawInsert(
          'INSERT INTO ${DbSabitler.fisSeri}(sube_id, fis_tipi, son_fis_no) VALUES(?, ?, ?)',
          [gecerliSubeId, seriAnahtari, yeniNo],
        );
      } else {
        await txn.rawUpdate(
          'UPDATE ${DbSabitler.fisSeri} SET son_fis_no = ? WHERE sube_id = ? AND fis_tipi = ?',
          [yeniNo, gecerliSubeId, seriAnahtari],
        );
      }
      return noYap(yeniNo); // 16 karakter
    });
    unawaited(_fisSeriBulutaPushla(gecerliSubeId, seriAnahtari, yeniNo));
    return sonuc;
  }

  /// Bu cihazın fiş numarasına girecek 2 haneli kasa no'su (1–99), buluttaki
  /// Terminal kaydından (yerel_terminal.terminal_id — şirket genelinde
  /// benzersiz). Terminal kaydı yoksa 0 (eski biçim). 99'u aşan id'ler
  /// 1–99'a sarılır.
  Future<int> _kasaNoGetir(Database database) async {
    try {
      final r = await database.query('yerel_terminal',
          columns: ['terminal_id'], where: 'id = 1', limit: 1);
      final id = r.isNotEmpty ? (r.first['terminal_id'] as num?)?.toInt() : null;
      if (id == null || id <= 0) return 0;
      return ((id - 1) % 99) + 1;
    } catch (_) {
      return 0;
    }
  }

  /// [istenenSubeId] gerçekten subeler tablosunda varsa aynen döner;
  /// yoksa mevcut ilk şubeye, hiç şube yoksa yeni oluşturulan bir
  /// "Merkez Şube"ye düşer. bkz. fisNoUret üzerindeki kritik düzeltme
  /// notu — bu, fis_seri.sube_id FK ihlalini kalıcı olarak önler.
  Future<int> _gecerliSubeIdGetir(Database database, int istenenSubeId) async {
    final istenen = await database.query(DbSabitler.subeler,
        columns: ['id'], where: 'id = ?', whereArgs: [istenenSubeId], limit: 1);
    if (istenen.isNotEmpty) return istenenSubeId;

    final ilkSube =
        await database.query(DbSabitler.subeler, columns: ['id'], orderBy: 'id', limit: 1);
    if (ilkSube.isNotEmpty) return ilkSube.first['id'] as int;

    final yeniId = await database.insert(
        DbSabitler.subeler, {'sube_kodu': 'MERKEZ', 'sube_adi': 'Merkez Şube'},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (yeniId > 0) return yeniId;

    // ignore nedeniyle 0 döndüyse (aynı sube_kodu'yla BAŞKA bir satır
    // araya girmiş) — o satırı bul.
    final tekrar =
        await database.query(DbSabitler.subeler, columns: ['id'], orderBy: 'id', limit: 1);
    return tekrar.isNotEmpty ? tekrar.first['id'] as int : istenenSubeId;
  }


  /// Bulut'taki fis_seri satırlarını çekip yerel sayaçla MAX-birleştirir
  /// (bkz. fisNoUret üzerindeki not) — başka bir terminalin bu şubede/bu
  /// tipte ÜRETTİĞİ daha yüksek bir numarayı öğrenirse yerel sayaç ona
  /// göre YUKARI çekilir, ASLA aşağı çekilmez (MAX(), tersini yapamaz).
  /// Tamamen best-effort: bulut yapılandırılmamışsa, offline'sa ya da
  /// herhangi bir hata olursa sessizce hiçbir şey yapmaz — fisNoUret'i
  /// asla ağa bağımlı hale getirmez. 30 saniyede bir kendini kısıtlar
  /// (her satışta ağ isteği atmasın diye).
  Future<void> _fisSeriBulutlaUyumla() async {
    final simdi = DateTime.now();
    if (_sonFisSeriUyum != null &&
        simdi.difference(_sonFisSeriUyum!) < const Duration(seconds: 30)) {
      return;
    }
    _sonFisSeriUyum = simdi;
    try {
      final saglayici = BulutManager().mevcutSaglayici;
      if (saglayici == null) return;
      final uzakSatirlar =
          await saglayici.cek(tablo: DbSabitler.fisSeri, limit: 500);
      if (uzakSatirlar.isEmpty) return;
      final database = await db;
      await database.transaction((txn) async {
        for (final satir in uzakSatirlar) {
          final uzakSubeId = (satir['sube_id'] as num?)?.toInt();
          final uzakTip = satir['fis_tipi']?.toString();
          final uzakSon = (satir['son_fis_no'] as num?)?.toInt();
          if (uzakSubeId == null || uzakTip == null || uzakSon == null) {
            continue;
          }
          // Satır yerelde yoksa önce oluştur (yoksayılabilir çakışma),
          // sonra HER KOŞULDA MAX() ile kelepçele — asla küçültme.
          await txn.rawInsert(
            'INSERT OR IGNORE INTO ${DbSabitler.fisSeri}'
            '(sube_id, fis_tipi, son_fis_no) VALUES(?, ?, ?)',
            [uzakSubeId, uzakTip, uzakSon],
          );
          await txn.rawUpdate(
            'UPDATE ${DbSabitler.fisSeri} SET son_fis_no = MAX(son_fis_no, ?) '
            'WHERE sube_id = ? AND fis_tipi = ?',
            [uzakSon, uzakSubeId, uzakTip],
          );
        }
      });
    } catch (_) {
      // best-effort — offline/hata sessizce yutulur
    }
  }

  /// Yeni üretilen yerel sayaç değerini buluta best-effort iter.
  /// BulutManager()'ın genel kuyruk/dedup mekanizması KASITLI OLARAK
  /// kullanılmıyor — o mekanizma kayıtları 'global_id' ile eşleştirip
  /// gruplandırıyor, fis_seri'nin ise hiç global_id'si yok (doğal
  /// anahtarı sube_id+fis_tipi). Bu, aynı tablo için kuyrukta bekleyen
  /// FARKLI (sube_id,fis_tipi) kayıtlarının birbirinin üzerine
  /// yazılmasına (kuyruktan sessizce düşmesine) yol açabilirdi — bu
  /// yüzden burada sağlayıcının tekli upsert'i DOĞRUDAN, kuyruğa
  /// girmeden çağrılıyor.
  Future<void> _fisSeriBulutaPushla(int subeId, String tip, int yeniNo) async {
    try {
      final saglayici = BulutManager().mevcutSaglayici;
      if (saglayici == null) return;
      await saglayici.upsert(
        tablo: DbSabitler.fisSeri,
        veri: {
          'sube_id': subeId,
          'fis_tipi': tip,
          'son_fis_no': yeniNo,
          'last_updated': DateTime.now().toUtc().toIso8601String(),
        },
        uniqueAlan: 'sube_id,fis_tipi',
      );
    } catch (e) {
      // best-effort — yerel numara zaten üretildi, satış bloklanmaz. AMA
      // ÖNCEDEN hata tamamen yutuluyordu: 2026-09-27 bulut kontrolünde
      // fis_seri tablosunun HİÇ dolmadığı görüldü ve sebep izlenemedi.
      // Artık log'a düşer (Ayarlar > Loglar).
      LogServisi().uyari('fis_seri buluta gönderilemedi ($tip, şube $subeId)', hata: e);
    }
  }
}
