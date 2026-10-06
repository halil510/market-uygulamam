// lib/veri/database/veritabani_supabase.dart
//
// veritabani.dart'ın parçası (part/part of) — Supabase senkron yardımcıları (filigran, çakışma koruması, kayıt yazma).
// Davranış BİREBİR aynı: Veritabani üzerine extension; private üyelere aynı
// kütüphane olduğu için erişir.
part of 'veritabani.dart';

String _kisalt(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;

extension VeritabaniSupabase on Veritabani {
  // ═══════════════════════════════════════════════════════════════
  // SUPABASE SYNC METODLARI
  // ═══════════════════════════════════════════════════════════════

  /// Supabase'e gönderilecek kayıtları getir
  Future<List<Map<String, dynamic>>> supaTumKayitlariGetir(
    String tablo,
    bool filtrele,
  ) async {
    final database = await db;
    try {
      // 🔴🔴🔴 KRİTİK KÖK NEDEN DÜZELTMESİ: Bu fonksiyon SADECE bulut
      // senkronuna GÖNDERİLECEK kayıtları toplamak için kullanılıyor.
      // Önceden 'urunler','cari','satislar','faturalar' için
      // is_deleted=1 (silinmiş) kayıtlar SORGUDAN TAMAMEN ÇIKARILIYORDU
      // — bu 4 tablodaki HİÇBİR SİLME İŞLEMİNİN buluta gitmemesi
      // demekti. Artık silinmiş kayıtlar da dahil TÜM kayıtlar
      // döndürülüyor — silme durumu doğru şekilde buluta yansıyor.
      return await database.query(tablo);
    } catch (e) {
      debugPrint('❌ supaTumKayitlariGetir hatası ($tablo): $e');
      return [];
    }
  }

  // 🔴🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — kredi_kartlari NOT
  // NULL hatası, Supabase TAMAMEN temizlenip tekrar gönderilmesine
  // rağmen AYNI hata devam ediyordu): BulutManager.upsert()'e
  // eklediğim kart_no_maskeli sanitizasyonu SADECE otomatik arka plan
  // senkronunda çalışıyordu. "Buluta Gönder" (manuel tam senkron) BU
  // FONKSİYONU (supaTumKayitlariGetir) kullanıyor — BulutManager'ı HİÇ
  // görmüyor, bu yüzden düzeltme hiç devreye girmiyordu. Artık bu
  // merkezi noktada da uygulanıyor.
  Future<List<Map<String, dynamic>>> supaTumKayitlariGetirTemiz(
    String tablo, bool filtrele,
  ) async {
    final satirlar = await supaTumKayitlariGetir(tablo, filtrele);
    if (tablo == 'kredi_kartlari') {
      final database = await db;
      for (final satir in satirlar) {
        final knm = satir['kart_no_maskeli'];
        if (knm == null || (knm is String && knm.isEmpty)) {
          satir['kart_no_maskeli'] = '**** **** **** ????';
          if (satir['id'] != null) {
            database.update('kredi_kartlari', {'kart_no_maskeli': '**** **** **** ????'},
                where: 'id = ?', whereArgs: [satir['id']]).catchError((_) => 0);
          }
        }
      }
    }
    return satirlar;
  }

  /// Yeni kayıtları ekle (Supabase'den gelen)
  /// 🔴🔴🔴 KULLANICI TARAFINDAN BULUNAN, GERÇEK VERİ KAYBI HATASI:
  /// 'cari' tablosunda cari_kodu, 'satislar'/'faturalar'da fiş/fatura
  /// no UNIQUE — 2 cihaz FARKLI global_id'li ama AYNI kod/numaralı
  /// kayıt oluşturduğunda, bu kayıt senkronize edilirken UNIQUE
  /// ihlaliyle patlıyordu (INSERT'te ConflictAlgorithm.replace bunu
  /// "çakışma" sayıp var olan kaydı SİLİP üzerine yazma riski
  /// taşıyordu; UPDATE'te ise SQL doğrudan hata fırlatıp o kaydı hiç
  /// güncellemiyordu — kullanıcının bildirdiği hata TAM OLARAK bu).
  ///
  /// 🔴 BU FONKSİYON ÖNCEDEN SADECE supaKayitlariEkle (INSERT) İÇİNDE
  /// VARDI — supaKayitlariGuncelle (UPDATE) hiç çağırmıyordu. Aynı
  /// çakışma sınıfı, kaydın zaten yerelde var olduğu (dolayısıyla
  /// UPDATE yoluna düştüğü) durumda korumasız kalıyordu. Artık HER
  /// İKİ yoldan da (ekleme VE güncelleme) önce bu uygulanıyor.
  Future<void> _cakismaKorumasiUygula(
      Database database, String tablo, List<Map<String, dynamic>> kayitlar) async {
    if (tablo == 'cari') {
      // 🔴 DÜZELTME (2026-10-02, kullanıcı bulgusu: Excel'den aktarılan cariler
      // bulutta 2 kez, 116'sı aynı "CARIO-128" koduyla görünüyordu): yeni kod
      // ÖNCEDEN yalnızca DB'deki en büyük numaradan türetiliyordu; gelen
      // kayıtlar henüz eklenmediği için aynı toplu çekmedeki TÜM çakışanlar
      // aynı kodu alıyordu. Bu çağrı boyunca atanan en büyük numara tutulur.
      var buCagriSonNo = 0;
      String unvanAnahtari(Object? u) =>
          (u?.toString() ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
      for (final kayit in List<Map<String, dynamic>>.of(kayitlar)) {
        final gelenKod = kayit['cari_kodu'];
        final gelenGlobalId = kayit['global_id'];
        if (gelenKod == null || gelenGlobalId == null) continue;
        final cakisan = await database.query('cari',
            columns: ['id', 'global_id', 'olusturma_tarihi', 'unvan'],
            where: 'cari_kodu = ? AND global_id != ?',
            whereArgs: [gelenKod, gelenGlobalId]);
        if (cakisan.isNotEmpty) {
          // Aynı kod + aynı unvan = büyük olasılıkla AYNI cari (ör. aynı Excel
          // iki kez içe aktarıldı). İkinci bir cari olarak saklanıp bakiyesi
          // (açılış hareketi) ikiye katlanmasın — gelen kopya yerele alınmaz.
          // Yalnızca gelen kayıt yerelden DAHA YENİ ise atlanır; daha eskiyse
          // veri kaybetmemek için eski davranış (yeniden adlandırma) sürer.
          final yerelKayit = cakisan.first;
          final ayniKisi =
              unvanAnahtari(kayit['unvan']) == unvanAnahtari(yerelKayit['unvan']);
          String sira(Object? tarih, Object? gid) => '${tarih ?? '9999'}|${gid ?? ''}';
          final gelenDahaYeni = sira(kayit['olusturma_tarihi'], gelenGlobalId)
                  .compareTo(sira(yerelKayit['olusturma_tarihi'], yerelKayit['global_id'])) >=
              0;
          if (ayniKisi && gelenDahaYeni) {
            kayitlar.remove(kayit);
            LogServisi().bilgi('Senkronizasyon: "${kayit['unvan']}" ($gelenKod) '
                'zaten aynı kod ve unvanla kayıtlı — gelen kopya yerele alınmadı.');
            continue;
          }
          final maxRows = await database.rawQuery(
              "SELECT cari_kodu FROM cari WHERE cari_kodu LIKE 'CARIO-%' "
              "ORDER BY CAST(SUBSTR(cari_kodu, 7) AS INTEGER) DESC LIMIT 1");
          var sonNo = 0;
          if (maxRows.isNotEmpty) {
            final kod = maxRows.first['cari_kodu'] as String?;
            sonNo = int.tryParse(kod?.replaceFirst('CARIO-', '') ?? '') ?? 0;
          }
          if (buCagriSonNo > sonNo) sonNo = buCagriSonNo;
          buCagriSonNo = sonNo + 1;
          final yeniKod = 'CARIO-${sonNo + 1}';
          // 🔴 DÜZELTME (2026-09-27, çoklu terminal): ÖNCEDEN her zaman GELEN
          // cari yeniden adlandırılıyor ve bu yalnızca YERELDE kalıyordu —
          // her kasa aynı cariye farklı kod veriyor, bulutta çakışma hiç
          // çözülmüyordu. Artık her kasada AYNI karar verilir: kodu önce
          // oluşturulan (eşitse küçük global_id'li) cari korur, diğeri yeni
          // kod alır ve bu buluta gönderilir — tüm kasalar aynı sonuca yakınsar.
          final yerel = cakisan.first;
          String anahtar(Object? tarih, Object? gid) =>
              '${tarih ?? '9999'}|${gid ?? ''}';
          final gelenOnce = anahtar(kayit['olusturma_tarihi'], gelenGlobalId)
                  .compareTo(anahtar(yerel['olusturma_tarihi'], yerel['global_id'])) <
              0;
          if (gelenOnce) {
            await database.update('cari', {
              'cari_kodu': yeniKod,
              'last_updated': DateTime.now().toIso8601String(),
            }, where: 'id = ?', whereArgs: [yerel['id']]);
            final satir = await database.query('cari',
                where: 'id = ?', whereArgs: [yerel['id']], limit: 1);
            if (satir.isNotEmpty) {
              BulutManager().upsert('cari', Map<String, dynamic>.from(satir.first));
            }
          } else {
            kayit['cari_kodu'] = yeniKod;
            BulutManager().upsert('cari', Map<String, dynamic>.from(kayit));
          }
          LogServisi().bilgi(
              'Senkronizasyon çakışması çözüldü: cari kodu $gelenKod — '
              '${gelenOnce ? 'yerel' : 'gelen'} cari yeni kod aldı ($yeniKod).');
        }
      }
    }

    if (tablo == 'satislar' || tablo == 'faturalar') {
      final alanAdi = tablo == 'satislar' ? 'fis_no' : 'fatura_no';
      for (final kayit in kayitlar) {
        final gelenNo = kayit[alanAdi];
        final gelenGlobalId = kayit['global_id'];
        if (gelenNo == null || gelenGlobalId == null) continue;
        final cakisan = await database.query(tablo,
            columns: ['global_id'],
            where: '$alanAdi = ? AND global_id != ?',
            whereArgs: [gelenNo, gelenGlobalId]);
        if (cakisan.isNotEmpty) {
          final kisaId = gelenGlobalId.toString().substring(0, 6);
          kayit[alanAdi] = '$gelenNo-SYNC$kisaId';
          // 🔴 DÜZELTME (kullanıcı bulgusu, 2026-09-21): bu satır ÖNCEDEN
          // sadece ⚠ ile işaretlenip Satış Listesi/Gün Sonu'nda sıradan
          // bir satış gibi TAM DEĞERLİ sayılıyordu — kullanıcı ekran
          // görüntüsünde tek bir ₺90'lık satışın Gün Sonu'nda ₺180 Cari
          // Satış olarak göründüğünü bildirdi ("kafa karıştırıyor").
          // Artık 'satislar' için ayrıca sync_cakisma_kopyasi=1
          // damgalanıyor (v73 migrasyonu) — SatisDeposu.tariheGoreGetir/
          // maliyetToplami/gunSonuDetayGetir bunu varsayılan olarak
          // dışlıyor, Sync Çakışmaları ekranı ayrı bir bölümde gösterip
          // kullanıcıya "gerçek satış" / "kopya, sil" seçimi sunuyor.
          // 'faturalar' tablosunda bu sütun yok (kapsam dışı bırakıldı,
          // GİB tarafında farklı bir inceleme akışı gerektirir).
          if (tablo == 'satislar') {
            kayit['sync_cakisma_kopyasi'] = 1;
          }
          // 🔴 DÜZELTME (kritik — derin denetimde bulundu, sadece
          // 'faturalar' için): Bu yeniden adlandırma ÖNCEDEN SADECE yerel
          // veritabanına yazılıyordu — Supabase'e (veya diğer cihazlara)
          // HİÇ geri gönderilmiyordu. Sonuç: bulutta AYNI fatura_no'ya
          // sahip İKİ satır kalıcı olarak duruyordu, ve iki cihaz bu
          // çakışmayı GÖRDÜKLERİ SIRAYA göre BAĞIMSIZ/FARKLI şekillerde
          // çözüyordu (A cihazı X satırını, B cihazı Y satırını "-SYNC"
          // yapabiliyordu) — resmi fatura numaralarında çoklu-cihaz
          // tutarsızlığı. Artık çözülmüş (yeni numaralı) hâli BULUTA DA
          // geri gönderiliyor ki diğer cihazlar bir sonraki senkronda
          // AYNI (çözülmüş) sonucu görsün.
          //
          // NOT: Bu, İKİ cihazın TAM OLARAK AYNI ANDA aynı fatura_no'yu
          // üretme riskinin KENDİSİNİ ortadan kaldırmaz (bu, çevrimdışı-
          // öncelikli mimariyi bozmadan ayrı, daha büyük bir tasarım
          // kararı gerektirir — bkz. proje notları) — sadece çakışma
          // TESPİT EDİLDİKTEN SONRA bulutun ve tüm cihazların AYNI
          // (çözülmüş) sonuca YAKINSAMASINI sağlar.
          if (tablo == 'faturalar') {
            try {
              BulutManager().upsert(tablo, Map<String, dynamic>.from(kayit));
            } catch (e) {
              LogServisi().bilgi('Fatura çakışma düzeltmesi buluta '
                  'gönderilemedi (bir sonraki senkronda tekrar denenecek): $e');
            }
          }
          LogServisi().bilgi(
              'Senkronizasyon çakışması önlendi: $tablo ($gelenGlobalId) '
              'yeni numara aldı, yerel kayıt korundu.');
        }
      }
    }

    if (tablo == 'urunler') {
      for (final kayit in kayitlar) {
        final gelenGlobalId = kayit['global_id'];
        if (gelenGlobalId == null) continue;
        for (final alan in ['kod', 'barkod']) {
          final gelenDeger = kayit[alan];
          if (gelenDeger == null) continue;
          final cakisan = await database.query('urunler',
              columns: ['global_id'],
              where: '$alan = ? AND global_id != ?',
              whereArgs: [gelenDeger, gelenGlobalId]);
          if (cakisan.isNotEmpty) {
            kayit[alan] = null; // çakışan alanı temizle, ürünü kaybetme
            LogServisi().bilgi(
                'Senkronizasyon çakışması önlendi: urunler.$alan '
                '($gelenGlobalId) temizlendi, yerel kayıt korundu.');
          }
        }
      }
    }

    // 🔴 Aynı çakışma sınıfının şemadaki DİĞER örnekleri — cari/satislar
    // hatası bildirilince şemadaki TÜM UNIQUE sütunlar tek tek tarandı.
    // Numara/kod alanları: çakışırsa yeniden numaralanır (veri kaybı yok).
    const numaraAlanlari = {
      'irsaliyeler': 'irsaliye_no',
      'tedarikci_siparisler': 'siparis_no',
      'subeler': 'sube_kodu',
    };
    if (numaraAlanlari.containsKey(tablo)) {
      final alanAdi = numaraAlanlari[tablo]!;
      for (final kayit in kayitlar) {
        final gelenNo = kayit[alanAdi];
        final gelenGlobalId = kayit['global_id'];
        if (gelenNo == null || gelenGlobalId == null) continue;
        final cakisan = await database.query(tablo,
            columns: ['global_id'],
            where: '$alanAdi = ? AND global_id != ?',
            whereArgs: [gelenNo, gelenGlobalId]);
        if (cakisan.isNotEmpty) {
          final kisaId = gelenGlobalId.toString().substring(0, 6);
          kayit[alanAdi] = '$gelenNo-SYNC$kisaId';
          LogServisi().bilgi(
              'Senkronizasyon çakışması önlendi: $tablo ($gelenGlobalId) '
              'yeni numara aldı, yerel kayıt korundu.');
        }
      }
    }

    // İsim alanları: rastgele numara yerine okunabilir bir ek uygun —
    // ör. "İçecek" çakışırsa "İçecek (SYNC)".
    // 🔴 KULLANICI TARAFINDAN BULUNAN HATA: 'masalar' bu listede hiç
    // yoktu — masa isimleri (ad) hiçbir çakışma koruması olmadan
    // senkronlanıyordu. Sonuç: "Masa 1" adında, farklı global_id'li
    // ikinci bir kayıt (başka bir cihazda oluşmuş / bir önceki kurulum
    // artığı vb.) buluttan gelince, aynı isimle SESSİZCE ikinci bir
    // satır olarak ekleniyordu — kullanıcı "Masa 1'den iki tane oluyor"
    // diye bildirdi. Artık masalar da bu korumaya dahil; çakışan gelen
    // kayıt "Masa 1 (SYNC)" gibi görünür bir adla eklenir, üzerine
    // yazma/veri kaybı olmaz ve kullanıcı ekranda ikisini görüp elle
    // birleştirip silebilir.
    const isimTablolari = {'kategoriler', 'birimler', 'markalar', 'masalar'};
    if (isimTablolari.contains(tablo)) {
      for (final kayit in kayitlar) {
        final gelenAd = kayit['ad'];
        final gelenGlobalId = kayit['global_id'];
        if (gelenAd == null || gelenGlobalId == null) continue;
        final cakisan = await database.query(tablo,
            columns: ['global_id'],
            where: 'ad = ? COLLATE NOCASE AND global_id != ?',
            whereArgs: [gelenAd, gelenGlobalId]);
        if (cakisan.isNotEmpty) {
          kayit['ad'] = '$gelenAd (SYNC)';
          LogServisi().bilgi(
              'Senkronizasyon çakışması önlendi: $tablo ($gelenGlobalId) '
              'yeni ad aldı, yerel kayıt korundu.');
        }
      }
    }
  }

  /// SupabaseSyncServisi._filigranAnahtari(tablo, 'gonder') İLE AYNI
  /// anahtar biçimi — bu cihazın o tabloyu buluta EN SON BAŞARIYLA
  /// gönderdiği zaman. Kasıtlı olarak o dosyayı import ETMİYORUZ (döngüsel
  /// bağımlılık) — sadece aynı anahtar sözleşmesini paylaşıyoruz. Manuel
  /// "Buluta Gönder" ve otomatik kuyruk gönderiminin (BulutManager) en yenisi.
  Future<DateTime?> _sonGonderFiligrani(String tablo) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('mp_sync_gonder_$tablo') ??
        prefs.getString('mp_sync_$tablo'); // eski tek-anahtar sürümü
    final manuel = s != null ? DateTime.tryParse(s) : null;
    final o = prefs.getString('mp_sync_otogonder_$tablo');
    final oto = o != null ? DateTime.tryParse(o) : null;
    if (manuel == null) return oto;
    if (oto == null) return manuel;
    return oto.isAfter(manuel) ? oto : manuel;
  }

  /// Bu kaydın bu cihazda henüz buluta GİTMEMİŞ bir değişikliği var mı —
  /// sync_queue'da bekleyen (veya kalıcı hatalı) satırı varsa evet. Bu,
  /// "yerel değişiklik kaybolur mu?" sorusunun kesin cevabıdır.
  Future<bool> _kuyruktaBekliyorMu(
      Database database, String tablo, String? globalId) async {
    if (globalId == null || globalId.isEmpty) return false;
    final r = await database.query(DbSabitler.syncQueue,
        columns: ['id'],
        where: 'tablo_adi = ? AND kayit_global_id = ?',
        whereArgs: [tablo, globalId],
        limit: 1);
    return r.isNotEmpty;
  }

  /// Bir kaydın gelen (buluttan) sürümüyle üzerine yazılmadan HEMEN önce
  /// çağrılır. Yerel ve gelen satır arasında metadata dışı gerçek bir alan
  /// farkı varsa 'sync_cakismalar' tablosuna kalıcı bir kayıt düşer —
  /// kaybedecek olan yerel değer(ler) böylece kaybolmadan önce arşivlenmiş
  /// olur. Fark tespiti saf/test edilebilir SyncCakismaTespit'te (bkz. o
  /// dosya).
  ///
  /// 🔴 FAZ 3 (madde 4, 2026-09-21): ÖNCEDEN bu fonksiyon LWW SONUCUNU
  /// HİÇ DEĞİŞTİRMİYORDU, sadece görünürlük ekliyordu — artık dönüş
  /// değeri (gerçek bir çakışma kaydedildi mi) çağırana taşınıyor ki
  /// "işlem verisi" tablolarında (bkz. SyncCakismaTespit.islemVerisiMi)
  /// otomatik üzerine yazmayı DURDURABİLSİN.
  Future<bool> _cakismaKaydetGerekirse(
    Database database,
    String tablo,
    Map<String, dynamic> yerelSatir,
    Map<String, dynamic> gelenSatir,
  ) async {
    try {
      final farklar = SyncCakismaTespit.farklariBul(yerelSatir, gelenSatir);
      if (farklar.isEmpty) return false; // gerçek bir fark yok, çakışma sayılmaz
      // Sadece boşluk dolduran fark (yerel boş, gelen dolu): kaybolacak yerel
      // değer yok → çakışma değil; çağıran gelen değeri normal uygular.
      if (SyncCakismaTespit.sadeceBoslukDoldurma(farklar)) return false;
      // Masa durumu (dolu/boş) canlı bir durumdur, kalıcı iş verisi değil —
      // iki kasanın anlık farkı kullanıcıdan karar istenecek çakışma değildir.
      if (tablo == 'masalar') return false;

      // 🔴🔴 KÖK NEDEN DÜZELTMESİ (kullanıcı bulgusu — "sync çakışma var
      // diyor"): ÖNCEDEN buraya, yerel satır ile gelen satır sadece
      // FARKLI diye düşülüyordu. Ama bu fark, BU cihazın yaptığı bir
      // değişiklikle hiç ilgisiz olabilir — sadece BAŞKA bir cihazın
      // DAHA ÖNCE yaptığı, tamamen normal bir güncellemenin bu cihaza
      // İLK KEZ ulaşması da (yerelde eski sürüm durduğu için) birebir
      // aynı şekilde "fark" üretiyordu. Sonuç: gerçekte kimse çakışmadı
      // — sadece normal, tek yönlü senkron yayılması oldu — ama bu her
      // seferinde "Sync Çakışmaları" ekranına gerçek bir çakışmaymış
      // gibi düşüp kullanıcıyı gereksiz yere karar vermeye zorluyordu.
      // Artık: bu cihazın o tabloyu EN SON BAŞARIYLA gönderdiği andan
      // BERİ yerel kayıt hiç değişmediyse (yani yerelde "kaybolacak",
      // henüz buluta gitmemiş bir değişiklik YOKSA) bu bir çakışma
      // sayılmıyor — sadece sessizce uygulanıyor. Emin olunamayan
      // durumlarda (bu tablo bu cihazdan hiç gönderilmediyse)
      // ESKİ (güvenli/muhafazakâr) davranışa dönülüyor: yine kaydedilir.
      final globalId = gelenSatir['global_id']?.toString();
      // Kuyrukta bekleyen yerel değişiklik varsa kesin çakışma; yoksa
      // (kuyruğa girmeyen eski/doğrudan yazımlar için) zaman sezgisi.
      if (!await _kuyruktaBekliyorMu(database, tablo, globalId)) {
        // 🔴 KÖK NEDEN DÜZELTMESİ (2026-10-06, canlı veride görüldü — iade
        // 970,03 ↔ 2086,59 "çözülmemiş çakışma"): zaman sezgisi ("yerel
        // last_updated bu cihazın son gönderiminden yeni mi?") yerel satırın
        // damgasının çoğu zaman BAŞKA cihazdan çekilmiş olduğunu hesaba
        // katmıyordu. Kalem kalem eklenen iadede başlık art arda güncellenir:
        // çekilen ilk sürümün damgası bu cihazın son gönderiminden "yeni"
        // görünür, ikinci güncelleme sahte çakışma olup işlem verisi
        // tablolarında (iade, cari_hareket…) HİÇ uygulanmazdı.
        // Ayrım damga biçiminden yapılır: Postgres damgayı '+00:00' ile
        // döndürür; bu cihazın kendi yazdığı damgalar hep 'Z' / dilimsiz.
        // Yerel damga '+00:00' ile bitiyorsa satır buluttan gelmiş ve bu
        // cihazda hiç değişmemiştir → ezilecek yerel değişiklik yok.
        final yerelDamga = yerelSatir['last_updated']?.toString().trim() ?? '';
        if (yerelDamga.endsWith('+00:00')) return false;
        final gonderFiligrani = await _sonGonderFiligrani(tablo);
        // Bu tablo bu cihazdan hiç gönderilmediyse ve kuyrukta da bir şey
        // yoksa kaybolacak yerel değişiklik yoktur (gelen zaten daha yeni
        // — daha eskiyse çağıran yukarıda atlıyor). ÖNCEDEN bu durum
        // "emin değilim → çakışma" sayılıyordu: hiç satış yapmamış bir
        // kasa, diğer kasadaki satış iptallerini ASLA uygulamıyordu.
        if (gonderFiligrani == null) return false;
        final yerelZaman =
            KolonHaritalama.utcZaman(yerelSatir['last_updated']);
        if (!SyncCakismaTespit.gercekCakismaMi(
            yerelSonGuncelleme: yerelZaman,
            sonBasariliGonderim: gonderFiligrani)) {
          return false; // yerel sürüm zaten buluta gönderilmişti — kayıp riski yok
        }
      }

      final now = DateTime.now().toIso8601String();
      // 🔴 DEEP_AUDIT (kendi-keşif turu, 2026-09-21): ÖNCEDEN her turda
      // koşulsuz INSERT yapılıyordu — kullanıcı bir çakışmayı hemen
      // çözmezse, her periyodik sync turunda AYNI (tablo, global_id)
      // için mükerrer "sync_cakismalar" satırı birikiyordu (FAZ 3'ün
      // "işlem verisi otomatik uygulanmaz" davranışıyla artık daha da
      // görünür — satır bir daha asla kendiliğinden "çözülmüş" olmuyor).
      // Artık aynı kayıt için ÇÖZÜLMEMİŞ bir çakışma zaten varsa, yeni
      // satır eklemek yerine o satır GÜNCELLENİYOR (en güncel alan
      // farkları/kayıtlarla) — kullanıcı "Sync Çakışmaları" ekranında
      // tek, güncel bir kayıt görür.
      final mevcutCakisma = globalId != null
          ? await database.query(DbSabitler.syncCakismalar,
              columns: ['id'],
              where: 'tablo = ? AND kayit_global_id = ? AND cozuldu = 0',
              whereArgs: [tablo, globalId],
              limit: 1)
          : const <Map<String, dynamic>>[];
      final satirVerisi = {
        'tablo': tablo,
        'kayit_global_id': globalId,
        'alan_farklari': jsonEncode(farklar),
        'yerel_kayit': jsonEncode(yerelSatir),
        'gelen_kayit': jsonEncode(gelenSatir),
        'tarih': now,
        'cozuldu': 0,
      };
      if (mevcutCakisma.isNotEmpty) {
        await database.update(DbSabitler.syncCakismalar, satirVerisi,
            where: 'id = ?', whereArgs: [mevcutCakisma.first['id']]);
      } else {
        await database.insert(DbSabitler.syncCakismalar, satirVerisi);
      }
      return true;
    } catch (e, st) {
      // Çakışma kaydı BEST-EFFORT'tur — burada bir hata olsa bile asıl
      // senkron akışını (gelen değerin uygulanmasını) DURDURMAMALI.
      LogServisi().hata('Veritabani._cakismaKaydetGerekirse', hata: e, yigin: st);
      return false;
    }
  }

  /// Bu kayıt için çözülmemiş çakışma varken gelen değer çakışmasız
  /// uygulandıysa (ör. eski sürümün bıraktığı sahte çakışma) kaydı kapatır.
  Future<void> _bekleyenCakismayiKapat(
      Database database, String tablo, String? globalId) async {
    if (globalId == null || globalId.isEmpty) return;
    try {
      await database.update(
        DbSabitler.syncCakismalar,
        {
          'cozuldu': 1,
          'cozum_tipi': 'otomatik',
          'cozum_tarihi': DateTime.now().toIso8601String(),
        },
        where: 'tablo = ? AND kayit_global_id = ? AND cozuldu = 0',
        whereArgs: [tablo, globalId],
      );
    } catch (_) {/* best-effort */}
  }

  Future<void> supaKayitlariEkle(
    String tablo,
    List<Map<String, dynamic>> kayitlar,
  ) async {
    if (kayitlar.isEmpty) return;
    final database = await db;
    // 🔴🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "buluttan veri al'ı
    // kontrol et, uyuşmayan yer olur"): Bu liste ÖNCEDEN sadece 18
    // tablo içeriyordu — proje 58 tabloyu senkronize ediyor. Listede
    // OLMAYAN bir tabloda, gelen kayıt global_id çakışmasına
    // uğrarsa (nadir ama interrupted/retry senaryolarında mümkün)
    // ConflictAlgorithm.ignore SESSİZCE atlıyordu — replace yerine.
    // Artık TÜM senkronize edilen tablolar burada.
    const globalIdTablosu = {
      'urunler', 'cari', 'satislar', 'iade', 'faturalar',
      'fatura_detaylari', 'promosyonlar', 'promosyon_tanim',
      'tedarikci_siparisler', 'giderler', 'kasa_hareketleri',
      'vardiyalar', 'personel', 'musteri_puan', 'lot_seri',
      'masalar', 'masa_siparisleri', 'masa_siparis_kalem',
      'subeler', 'kullanicilar', 'kategoriler', 'birimler',
      'markalar', 'gider_kategoriler', 'rol_yetkileri',
      'roller_yetki', 'ayarlar', 'zaman_fiyat', 'fiyat_gecmis',
      'fiyat_gruplari', 'cari_adres', 'satis_kalem', 'iade_kalem',
      'irsaliyeler', 'irsaliye_kalem', 'promosyon_kosul',
      'promosyon_aksiyon', 'tedarikci_siparis_kalem', 'stok_hareket',
      'cari_hareket', 'puan_hareket', 'masa_rezervasyon',
      'adisyon_log', 'garson_cagri_log', 'masa_hareket_log',
      'banka_hesaplar', 'bankalar', 'kredi_kartlari',
      'banka_hareketler', 'kredi_karti_hareket', 'borclar',
      'borc_odemeler', 'audit_log', 'urun_fiyat_gruplari',
      'fiyat_kademeleri', 'sube_urun',
      // 🔴 DÜZELTME: bu 3 tablo senkron sistemine (supabase_sync_servisi.dart
      // _tabloSirasi/_globalIdVar/_uniqueAlan) sonradan eklendiğinde bu
      // liste güncellenmemişti — global_id çakışması olursa (retry/kesinti
      // senaryosu) sessizce IGNORE ediliyordu, REPLACE yerine.
      'bekleyen_siparisler', 'bekleyen_siparis_kalem', 'onay_talepleri',
      // Yıl Sonu Devir / Dönem Kapatma / Arşivleme (2026-09-16):
      'donemler', 'donem_sube_durumlari', 'devir_checkpoint',
      'stok_kapanis_snapshot', 'cari_kapanis_snapshot',
      'kasa_kapanis_snapshot', 'banka_kapanis_snapshot',
      'donem_kilit', // çoklu cihaz kilidi (2026-09-21, FAZ 4)
    };
    final conflict = globalIdTablosu.contains(tablo)
        ? ConflictAlgorithm.replace
        : ConflictAlgorithm.ignore;

    await _cakismaKorumasiUygula(database, tablo, kayitlar);

    await database.execute('PRAGMA foreign_keys = OFF');
    // 🔴🔴 KRİTİK DÜZELTME (derin denetimde bulundu): `batch.commit(...,
    // continueOnError: true)` bir satır eklerken hata verirse SESSİZCE
    // atlıyordu — bu fonksiyon hiçbir istisna fırlatmadan normal dönüyordu.
    // Çağıran taraf (supabase_sync_servisi.dart._buluttanAlCalistir),
    // "her şey başarıyla yazıldı" sanıp senkron filigranını (watermark)
    // çekilen TÜM kayıtların en büyük last_updated'ine ilerletiyordu.
    // Sonuç: atlanan satır bu cihazda KALICI OLARAK kayboluyordu — bir
    // daha hiçbir zaman "last_updated > filigran" sorgusuna dahil
    // olmuyordu, senkron ekranı ise "başarılı" diyordu. Push tarafında
    // (aynı dosya, ~satır 1133) kısmi hatada filigranın İLERLETİLMEDİĞİ
    // zaten doğru yapılmış — pull tarafında bu koruma hiç yoktu.
    // Artık her satır TEK TEK denenip başarısız olanlar sayılıyor; en az
    // bir satır başarısız olursa fonksiyon istisna fırlatıyor (iyi
    // giden satırlar yine de yazılmış olarak kalır — eski dayanıklılık
    // korunuyor) — bu istisna _buluttanAlCalistir'in try/catch'ine düşer,
    // filigran o tablo için İLERLEMEZ, başarısız satır BİR SONRAKİ
    // senkronda tekrar çekilip denenir.
    var basarisizSayisi = 0;
    var yetimSayisi = 0;
    String? ilkHata;
    String? ilkYetimHata;
    Map<String, dynamic>? ilkHataliSatir;
    try {
      for (final kayit in kayitlar) {
        final temiz = Map<String, dynamic>.from(kayit);
        temiz.remove('id');
        temiz.removeWhere((_, v) => v == null);
        try {
          // 🔴 Kullanıcı bulgusu (2026-09-29): "şifreyi değiştiriyorum,
          // uygulamayı kapatıp açınca eski şifre (1234) geçerli". Yerel
          // 'admin' satırı buluttaki satırla global_id üzerinden eşleşmediği
          // için "yeni kayıt" sayılıp REPLACE ile (eski şifre hash'iyle)
          // ezilebiliyordu. Kullanıcılar kullanici_adi ile eşlenir; yerel
          // kayıt daha yeni/eşitse dokunulmaz, değilse id korunarak
          // yerinde güncellenir.
          if (tablo == DbSabitler.kullanicilar && temiz['kullanici_adi'] != null) {
            final mevcut = await database.query(tablo,
                where: 'kullanici_adi = ?',
                whereArgs: [temiz['kullanici_adi']],
                limit: 1);
            if (mevcut.isNotEmpty) {
              final yerelStr = mevcut.first['last_updated']?.toString();
              final gelenStr = temiz['last_updated']?.toString();
              final yerelZaman = yerelStr != null
                  ? DateTime.tryParse(KolonHaritalama.utcDamga(yerelStr) ?? yerelStr)
                  : null;
              final gelenZaman = gelenStr != null
                  ? DateTime.tryParse(KolonHaritalama.utcDamga(gelenStr) ?? gelenStr)
                  : null;
              if (yerelZaman != null &&
                  (gelenZaman == null || !gelenZaman.isAfter(yerelZaman))) {
                continue; // yerel kayıt daha yeni (örn. yeni şifre) — koru
              }
              await database.update(tablo, temiz,
                  where: 'id = ?', whereArgs: [mevcut.first['id']]);
              continue;
            }
          }
          await database.insert(tablo, temiz, conflictAlgorithm: conflict);
        } catch (e) {
          // Zorunlu ilişki sütunu boş kalan satır (ebeveyni bulutta/yerelde
          // olmayan yetim kayıt) hiçbir turda yazılamaz; hata sayıp tabloyu
          // ve filigranı kilitlemek yerine atlanır ve loglanır.
          if (e.toString().contains('NOT NULL constraint failed')) {
            yetimSayisi++;
            ilkYetimHata ??= _kisalt(e.toString());
            continue;
          }
          basarisizSayisi++;
          ilkHata ??= e.toString();
          ilkHataliSatir ??= temiz;
          if (kDebugMode) {
            debugPrint('supaKayitlariEkle ($tablo) satır hatası: $e');
          }
        }
      }
    } finally {
      await database.execute('PRAGMA foreign_keys = ON');
    }
    if (yetimSayisi > 0) {
      LogServisi().uyari('supaKayitlariEkle($tablo): $yetimSayisi yetim satır '
          'atlandı (zorunlu ilişki alanı boş)',
          ek: ilkYetimHata);
    }
    if (basarisizSayisi > 0) {
      // 🔴 (2026-09-28, kullanıcı bulgusu "cari_hareket: 119/119 kayıt
      // yazılamadı"): gerçek SQLite hatası yalnız debug'da yazılıyordu —
      // sahada nedeni görmek imkânsızdı. İlk hata + örnek satırın alanları
      // mesaja ve kalıcı log'a eklenir.
      final ornek = ilkHataliSatir == null
          ? ''
          : ' | örnek alanlar: ${ilkHataliSatir.keys.join(',')}';
      LogServisi().hata('supaKayitlariEkle($tablo)',
          hata: ilkHata, ek: 'örnek satır: ${ilkHataliSatir.toString()}');
      throw Exception('$tablo: $basarisizSayisi/${kayitlar.length} kayıt yazılamadı — '
          'ilk hata: ${_kisalt(ilkHata ?? '')}$ornek');
    }
  }


  /// Mevcut kayıtları güncelle (Supabase'den gelen)
  Future<void> supaKayitlariGuncelle(
    String tablo,
    List<Map<String, dynamic>> kayitlar,
  ) async {
    if (kayitlar.isEmpty) return;
    final database = await db;
    await _cakismaKorumasiUygula(database, tablo, kayitlar);
    await database.execute('PRAGMA foreign_keys = OFF');
    int atlanan = 0;
    try {
      for (final kayit in kayitlar) {
        final temiz = Map<String, dynamic>.from(kayit);
        temiz.remove('id');
        temiz.removeWhere((_, v) => v == null);
        // Cari bakiye bu cihazda hareketlerden türetilir (tetikleyici +
        // SenkronSonrasiMutabakat) — başka kasanın o anki hesabı olan bulut
        // değeri yerel bakiyeyi ezmesin, çakışma kaydına da düşmesin.
        if (tablo == DbSabitler.cari) temiz.remove('bakiye');
        if (temiz.containsKey('global_id') && temiz['global_id'] != null) {
          // 🔴🔴 GENELLEŞTİRİLMİŞ ÇAKIŞMA KORUMASI (kullanıcı isteği:
          // "tam ERP sistemi — internetsiz gelip bulutsuz çalışıp sonra
          // senkron olsun, hiçbir tabloda veri kaybı olmasın"):
          // ÖNCEDEN bu koruma SADECE 'urunler' fiyat alanları içindi —
          // diğer TÜM tablolarda gelen bulut kaydı yerel kaydın
          // TAMAMININ üzerine körü körüne yazılıyordu. Artık HER
          // TABLODA, HER KAYIT için: yerel last_updated, gelen bulut
          // kaydından DAHA YENİYSE, o kayıt TAMAMEN ATLANIYOR (yerel,
          // henüz gönderilmemiş değişiklik korunuyor).
          final mevcut = await database.query(tablo,
              where: 'global_id = ?', whereArgs: [temiz['global_id']], limit: 1);
          if (mevcut.isNotEmpty) {
            final yerelSatir = mevcut.first;
            final yerelStr = yerelSatir['last_updated']?.toString();
            final gelenStr = temiz['last_updated']?.toString();
            // Saat dilimi karışımı (SQLite CURRENT_TIMESTAMP = dilimsiz UTC,
            // Dart = yerel) yanlış tarafı kazandırmasın: ikisi de UTC'ye çevrilir.
            final yerelZaman = yerelStr != null
                ? DateTime.tryParse(KolonHaritalama.utcDamga(yerelStr) ?? yerelStr)
                : null;
            final gelenZaman = gelenStr != null
                ? DateTime.tryParse(KolonHaritalama.utcDamga(gelenStr) ?? gelenStr)
                : null;
            if (yerelZaman != null && gelenZaman != null &&
                yerelZaman.isAfter(gelenZaman)) {
              atlanan++;
              continue;
            }
            // 🆕 SYNC ÇAKIŞMASI KAYDI (protokol §12): Üzerine yazmadan ÖNCE,
            // yerel ve gelen satır arasında (metadata dışı) gerçek bir alan
            // farkı varsa çakışma tablosuna düşülüyor.
            // 🔴 FAZ 3 (madde 4, 2026-09-21, kullanıcı onaylı mimari
            // karar): "master veri" (urunler, cari vb.) için davranış
            // DEĞİŞMEDİ — LWW ile gelen kazanır. Ama "işlem verisi"
            // (satış/stok/kasa/banka hareketi vb. — bkz. SyncCakismaTespit.
            // islemTablolari dosya başı gerekçesi) için GERÇEK bir
            // çakışma tespit edilirse artık otomatik üzerine YAZILMAZ —
            // yerel kayıt korunur, kullanıcı "Sync Çakışmaları"
            // ekranından bilinçli olarak karar verir.
            final gercekCakisma = await _cakismaKaydetGerekirse(
                database, tablo, yerelSatir, temiz);
            if (gercekCakisma && SyncCakismaTespit.islemVerisiMi(tablo)) {
              atlanan++;
              continue;
            }
            // Çakışma yok ve gelen değer uygulanacak: bu kayıt için daha önce
            // kalmış ÇÖZÜLMEMİŞ çakışma artık geçersiz → otomatik kapat.
            if (!gercekCakisma) {
              await _bekleyenCakismayiKapat(
                  database, tablo, temiz['global_id']?.toString());
            }
          }
          await database.update(
            tablo,
            temiz,
            where: 'global_id = ?',
            whereArgs: [temiz['global_id']],
          );
        }
      }
      if (atlanan > 0 && kDebugMode) {
        debugPrint('supaKayitlariGuncelle ($tablo): $atlanan kayıt atlandı '
            '(yerel değişiklik daha yeniydi, korundu)');
      }
    } finally {
      await database.execute('PRAGMA foreign_keys = ON');
    }
  }

  /// Toplu UPSERT (ekle veya güncelle) - Tek metodla her şey
  // ⚠️ NOT: Bu fonksiyon projede HİÇBİR YERDEN ÇAĞRILMIYOR (ölü kod).
  // Aktif senkron yolu BulutManager.upsert() + buluttanAl()'dır.
  Future<void> supaKayitlariUpsert(
    String tablo,
    List<Map<String, dynamic>> kayitlar,
  ) async {
    if (kayitlar.isEmpty) return;
    final database = await db;
    
    const globalIdTablosu = {
      'urunler', 'lot_seri', 'cari', 'satislar', 'iade',
      'promosyonlar', 'promosyon_tanim', 'tedarikci_siparisler',
      'giderler', 'kasa_hareketleri', 'vardiyalar',
      'faturalar', 'fatura_detaylari', 'personel', 'musteri_puan',
      'masalar', 'masa_siparisleri', 'masa_siparis_kalem',
    };
    
    final conflict = globalIdTablosu.contains(tablo)
        ? ConflictAlgorithm.replace
        : ConflictAlgorithm.ignore;

    final batch = database.batch();
    for (final kayit in kayitlar) {
      final temiz = Map<String, dynamic>.from(kayit);
      temiz.remove('id');
      temiz.removeWhere((_, v) => v == null);
      batch.insert(tablo, temiz, conflictAlgorithm: conflict);
    }
    await batch.commit(noResult: true, continueOnError: true);
  }

  /// Soft delete: is_deleted=1 olan kayıtları işaretler
  Future<void> supaKayitlariSoftDelete(String tablo, List<int> ids) async {
    if (ids.isEmpty) return;
    final database = await db;
    final placeholders = ids.map((_) => '?').join(',');
    await database.rawUpdate(
      'UPDATE $tablo SET is_deleted = 1, last_updated = ? WHERE id IN ($placeholders)',
      [DateTime.now().toIso8601String(), ...ids],
    );
  }

  /// Global ID ile soft delete
  Future<void> supaKayitlariSoftDeleteByGlobalId(String tablo, List<String> globalIds) async {
    if (globalIds.isEmpty) return;
    final database = await db;
    final placeholders = globalIds.map((_) => '?').join(',');
    await database.rawUpdate(
      'UPDATE $tablo SET is_deleted = 1, last_updated = ? WHERE global_id IN ($placeholders)',
      [DateTime.now().toIso8601String(), ...globalIds],
    );
  }

  /// Tablodaki tüm kayıtları getir (senkronizasyon için)
  Future<List<Map<String, dynamic>>> supaLokalVerileriGetir(
    String tablo, {
    bool sadeceSilmemis = true,
  }) async {
    final database = await db;
    try {
      return await database.query(tablo);
    } catch (e) {
      return [];
    }
  }

  /// Lokal kayıt ekle (tek kayıt)
  Future<int> supaLokalKayitEkle(String tablo, Map<String, dynamic> kayit) async {
    final database = await db;
    final temiz = Map<String, dynamic>.from(kayit);
    temiz.remove('id');
    temiz.removeWhere((_, v) => v == null);
    return await database.insert(tablo, temiz);
  }

  /// Lokal kayıt güncelle (tek kayıt)
  Future<int> supaLokalKayitGuncelle(String tablo, Map<String, dynamic> kayit) async {
    final database = await db;
    final temiz = Map<String, dynamic>.from(kayit);
    temiz.remove('id');
    temiz.removeWhere((_, v) => v == null);
    
    if (temiz.containsKey('global_id') && temiz['global_id'] != null) {
      return await database.update(
        tablo,
        temiz,
        where: 'global_id = ?',
        whereArgs: [temiz['global_id']],
      );
    } else if (temiz.containsKey('id') && temiz['id'] != null) {
      return await database.update(
        tablo,
        temiz,
        where: 'id = ?',
        whereArgs: [temiz['id']],
      );
    }
    return 0;
  }

  /// Tablodaki tüm kayıtları sil (test için)
  Future<void> supaTabloyuTemizle(String tablo) async {
    final database = await db;
    await database.delete(tablo);
  }

  /// Son senkronizasyon zamanını al
  Future<DateTime?> supaSonSenkronZamani(String tablo) async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString('supabase_sync_$tablo');
    if (timeStr != null) {
      return DateTime.tryParse(timeStr);
    }
    return null;
  }

  /// Son senkronizasyon zamanını kaydet
  Future<void> supaSonSenkronZamaniKaydet(String tablo, DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('supabase_sync_$tablo', time.toIso8601String());
  }
}
