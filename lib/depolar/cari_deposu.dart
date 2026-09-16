// lib/depolar/cari_deposu.dart
// ✅ DÜZELTİLDİ:
//   1. hareketEkle: bakiye artık trigger ile güncelleniyor (veri tutarsızlığı yok)
//   2. bakiyeYenidenHesapla metodu eklendi
//   3. Arama geliştirildi
//   4. Çift sil metodu düzeltildi
//   5. KRİTİK: hareketEkle içinde bakiye güncelleme EKLENDİ
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../servisler/auth_servisi.dart';
import '../veri/database/veritabani.dart';
import '../modeller/cari_model.dart';
import '../modeller/cari_hareket_model.dart';
import '../modeller/kasa_hareket_model.dart';
import '../cekirdek/utils/para_utils.dart';
import 'kasa_deposu.dart';

class CariDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  // Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
  // profesyonel sistem." Araştırma sonucu: kredi limiti/risk limiti
  // kontrolü, B2B toptan satış sistemlerinin olmazsa olmazı.
  //
  // 🔴 ÖNEMLİ BULGU: CariModel'de 'limitTutari' alanı ZATEN VARDI ve
  // ekranda GÖSTERİLİYORDU ama HİÇBİR YERDE KONTROL EDİLMİYORDU —
  // yani bir cariye "5.000 TL limit" yazsanız bile, satış sırasında
  // bu limit hiçbir şekilde uygulanmıyordu. Artık bu fonksiyon, yeni
  // bir satış öncesi çağrılarak limit aşımını tespit ediyor.
  //
  // NOT: Bilinçli olarak sert bir ENGELLEME değil, UYARI döndürüyor —
  // çağıran ekran, kullanıcıya onay sorup devam etmesine izin
  // verebilir (birçok işletme "limit aşıldı ama güvenilir müşteri,
  // yine de satayım" esnekliğini ister).
  Future<({bool asildi, double mevcutBakiye, double limit, double asimTutari})>
      limitKontrolEt(int cariId, double eklenecekTutar) async {
    try {
      final cari = await idileGetir(cariId);
      if (cari == null || cari.limitTutari <= 0) {
        // Limit hiç tanımlanmamışsa (0 veya negatif) kontrol devre dışı.
        return (asildi: false, mevcutBakiye: cari?.bakiye ?? 0.0, limit: 0.0, asimTutari: 0.0);
      }
      final yeniBakiye = cari.bakiye + eklenecekTutar;
      final asildi = yeniBakiye > cari.limitTutari;
      return (
        asildi: asildi,
        mevcutBakiye: cari.bakiye,
        limit: cari.limitTutari,
        asimTutari: asildi ? yeniBakiye - cari.limitTutari : 0.0,
      );
    } catch (e, st) {
      LogServisi().hata('Cari.limitKontrolEt', hata: e, yigin: st);
      return (asildi: false, mevcutBakiye: 0.0, limit: 0.0, asimTutari: 0.0);
    }
  }

  /// Kullanıcı sorusu: "2 mobil cihaz var, orada da aynı kodu atadı,
  /// veritabanı tek, o zaman nasıl olacak?" — İki cihaz İNTERNETSİZ
  /// (veya henüz senkronize olmadan) aynı anda yeni cari eklerse,
  /// ikisi de kendi yerel verisine bakıp AYNI "sıradaki numarayı"
  /// hesaplayabilir — bu, gerçek zamanlı koordinasyon olmadan
  /// %100 önlenemeyen, dağıtık sistemlerin bilinen bir sorunudur.
  ///
  /// Gerçek kimlik zaten `global_id` (UUID) — o her zaman benzersiz.
  /// `cari_kodu` sadece görünen bir etiket. Bu fonksiyon, senkronizasyon
  /// SONRASI çağrılarak aynı kodu taşıyan (ama global_id'si FARKLI,
  /// yani gerçekten farklı) carileri tespit edip, en eski olan HARİÇ
  /// diğerlerine otomatik yeni, benzersiz bir kod veriyor — kullanıcı
  /// hiçbir şey yapmadan, sessizce düzeltiliyor.
  Future<int> mukerrerKodlariDuzelt() async {
    try {
      final db = await _d;
      final mukerrerler = await db.rawQuery('''
        SELECT cari_kodu FROM cari
        WHERE cari_kodu IS NOT NULL AND is_deleted = 0
        GROUP BY cari_kodu HAVING COUNT(*) > 1
      ''');
      var duzeltilen = 0;
      for (final grup in mukerrerler) {
        final kod = grup['cari_kodu'] as String;
        // Aynı kodu taşıyan tüm carileri, oluşturulma tarihine göre
        // eskiden yeniye sırala — en eski kodu korur, diğerleri
        // yeniden numaralanır.
        final ayniKodlular = await db.query('cari',
            where: 'cari_kodu = ? AND is_deleted = 0', whereArgs: [kod],
            orderBy: 'olusturma_tarihi ASC, id ASC');
        for (var i = 1; i < ayniKodlular.length; i++) {
          final yeniNo = await sonrakiCariNo();
          await db.update('cari', {
            'cari_kodu': 'CARIO-$yeniNo',
            'last_updated': DateTime.now().toIso8601String(),
          }, where: 'id = ?', whereArgs: [ayniKodlular[i]['id']]);
          duzeltilen++;
        }
      }
      if (duzeltilen > 0) {
        LogServisi().bilgi('$duzeltilen mükerrer cari kodu otomatik düzeltildi');
      }
      return duzeltilen;
    } catch (e, st) {
      LogServisi().hata('Cari.mukerrerKodlariDuzelt', hata: e, yigin: st);
      return 0;
    }
  }

  Future<int> ekle(CariModel cari) async {
    try {
      final db = await _d;
      final m = cari.toMap();
      m.remove('id');
      m['global_id'] ??= const Uuid().v4();
      // Otomatik cari kodu üret (boşsa) — artık gerçekten benzersiz
      // olan sonrakiCariNo() kullanılıyor (bkz. o fonksiyondaki not).
      if (!m.containsKey('cari_kodu') || m['cari_kodu'] == null) {
        final no = await sonrakiCariNo();
        m['cari_kodu'] = 'CARIO-$no';
      }
      final id = await db.insert('cari', m);
      // 🔴 Derin analizde bulundu: bu fonksiyon dosyadaki TEK yazma
      // metoduydu ve yeni kaydı buluta hiç bildirmiyordu — bir işlem
      // görmeden önce bir cari asla diğer cihazlara/Supabase'e ulaşmıyordu.
      final yeniSatir = await db.query('cari', where: 'id = ?', whereArgs: [id], limit: 1);
      if (yeniSatir.isNotEmpty) {
        BulutManager().upsert('cari', Map<String, dynamic>.from(yeniSatir.first));
      }
      return id;
    } catch (e, st) {
      LogServisi().hata('Cari.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> guncelle(CariModel cari) async {
    try {
      final db = await _d;
      final m = cari.toMap();
      m['last_updated'] = DateTime.now().toIso8601String();
      await db.update('cari', m, where: 'id = ?', whereArgs: [cari.id]);
      final guncelSatir = await db.query('cari', where: 'id = ?', whereArgs: [cari.id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('cari', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Cari.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// GİB mükellef sorgusu sonucunu (efatura/earsiv/null) önbelleğe alır —
  /// her fatura kesiminde tekrar sorgulamamak için.
  Future<void> mukellefDurumuGuncelle(int cariId, String? durum) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      await db.update('cari', {
        'mukellef_durumu': durum,
        'mukellef_sorgu_tarihi': now,
        'last_updated': now,
      }, where: 'id = ?', whereArgs: [cariId]);
      final guncelSatir = await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('cari', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Cari.mukellefDurumuGuncelle', hata: e, yigin: st);
    }
  }

  Future<void> sil(int id) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      // 🔴 ÖNEMLİ DÜZELTME: silinen bir cari (müşteri/tedarikçi)
      // önceden diğer cihazlarda aktif görünmeye devam ederdi.
      await db.update('cari', {'is_deleted': 1, 'last_updated': now},
          where: 'id = ?', whereArgs: [id]);
      final guncelSatir = await db.query('cari', where: 'id = ?', whereArgs: [id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('cari', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Cari.sil', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<CariModel?> idileGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.query('cari',
          where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
      if (rows.isEmpty) return null;
      return CariModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('Cari.idileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<CariModel>> tumunuGetir({String? tip, int limit = 500}) async {
    try {
      final db = await _d;
      // 🔴 DÜZELTME: 'cari_tipi = ?' TAM eşleşme kullanıyordu — bu
      // yüzden "Hem Müşteri Hem Tedarikçi" tipindeki bir cari, ne
      // "Müşteri" sekmesinde ne "Tedarikçi" sekmesinde HİÇ
      // görünmüyordu (istatistikler()'de bulduğum AYNI hata sınıfı).
      // LIKE ile her iki kategoriye de dahil ediliyor.
      final where = tip != null
          ? 'cari_tipi LIKE ? AND is_deleted = 0 AND aktif = 1'
          : 'is_deleted = 0 AND aktif = 1';
      final args = tip != null ? ['%$tip%'] : null;
      // ÖNCEDEN "limit" parametresi TANIMLIYDI ama sorguda hiç
      // KULLANILMIYORDU — bu fonksiyon her zaman TÜM kayıtları
      // getiriyordu (limit'in hiçbir etkisi yoktu). Çok sayıda cari
      // olan bir işletmede (binlerce kayıt) bu, Cari Liste ekranının
      // yavaşlamasına/donmasına yol açabilirdi. Artık gerçekten
      // uygulanıyor.
      final rows = await db.query('cari',
          where: where, whereArgs: args, orderBy: 'unvan ASC', limit: limit);
      return rows.map(CariModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Cari.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  // 🔴 DÜZELTME (performans denetiminde bulundu): urunler.ara()'nın
  // aksine bu fonksiyonun hiç LIMIT'i yoktu — büyük bir cari tabanında
  // (binlerce müşteri/tedarikçi) kısa/genel bir arama terimi TÜM
  // eşleşen satırları tek seferde belleğe çekebiliyordu.
  // tumunuGetir()'deki AYNI varsayılan (500) ile tutarlı tutuldu.
  Future<List<CariModel>> ara(String sorgu, {String? tip, int limit = 500}) async {
    try {
      if (sorgu.isEmpty) return tumunuGetir(tip: tip, limit: limit);
      final db = await _d;
      final q = '%$sorgu%';
      // 🔴 DÜZELTME: 'cari_tipi = ...' hem TAM eşleşme (dual-tip
      // carileri dışlıyordu, tumunuGetir()'deki AYNI hata) hem de
      // doğrudan string enjeksiyonuydu (parametreli değildi) hem de
      // 'aktif = 1' filtresi eksikti (tumunuGetir ile tutarsız).
      final params = <Object?>[q, q, q, q, q];
      final tipFilt = tip != null ? " AND cari_tipi LIKE ?" : '';
      if (tip != null) params.add('%$tip%');
      params.add(limit);
      final rows = await db.rawQuery(
        '''SELECT * FROM cari
           WHERE (unvan LIKE ? OR cari_kodu LIKE ? OR telefon LIKE ? OR vergi_no LIKE ? OR email LIKE ?)
           AND is_deleted = 0 AND aktif = 1$tipFilt
           ORDER BY unvan ASC LIMIT ?''',
        params,
      );
      return rows.map(CariModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Cari.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  /// ÖNCEDEN BURADA, bu oturumda fatura numarasında bulup düzelttiğim
  /// AYNI hata sınıfı vardı: `COUNT(*)+1` kullanılıyordu — bu, cari
  /// SİLİNDİĞİNDE (sayı azalır, eski bir kod tekrar üretilir) VEYA
  /// senkronizasyon sonrası (başka cihazlardan gelen cariler sayıyı
  /// etkiler ama kodun kendisini değil) MÜKERRER "CARIO-N" kodları
  /// üretiyordu — kullanıcının paylaştığı gerçek veride 3 farklı
  /// müşterinin "CARIO-1" koduna sahip olması tam olarak buydu. Artık
  /// veritabanında KAYITLI EN YÜKSEK "CARIO-N" numarası bulunup bir
  /// fazlası veriliyor — gerçekten benzersiz.
  Future<int> sonrakiCariNo() async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        "SELECT cari_kodu FROM cari WHERE cari_kodu LIKE 'CARIO-%' "
        "ORDER BY CAST(SUBSTR(cari_kodu, 7) AS INTEGER) DESC LIMIT 1",
      );
      if (rows.isEmpty) return 1;
      final kod = rows.first['cari_kodu'] as String?;
      final sayiKismi = kod?.replaceFirst('CARIO-', '');
      final sonNo = int.tryParse(sayiKismi ?? '') ?? 0;
      return sonNo + 1;
    } catch (e, st) {
      LogServisi().hata('Cari.sonrakiCariNo', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> bakiyeGuncelle(int cariId) async {
    try {
      final db = await _d;
      await db.rawUpdate(
        'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0) WHERE id = ?',
        [cariId, cariId]);
      final satir = await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('cari', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Cari.bakiyeGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  // ✅ DÜZELTİLDİ: hareket ekledikten sonra bakiye güncelleniyor
  Future<void> hareketEkle(CariHareketModel hareket) async {
    try {
      final db = await _d;
      final globalId = await db.transaction((txn) => hareketEkleTxn(txn, hareket));
      final hareketSatir = await db.query('cari_hareket',
          where: 'global_id = ?', whereArgs: [globalId], limit: 1);
      if (hareketSatir.isNotEmpty) {
        BulutManager().upsert('cari_hareket', Map<String, dynamic>.from(hareketSatir.first));
      }
      final cariSatir = await db.query('cari', where: 'id = ?', whereArgs: [hareket.cariId], limit: 1);
      if (cariSatir.isNotEmpty) {
        BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Cari.hareketEkle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// [hareketEkle] ile AYNI mantık, VERİLEN transaction içinde çalışır —
  /// kendi transaction'ını açmaz. BulutManager bildirimi YAPMAZ (dış
  /// transaction commit olmadan buluta göndermek riskli — bkz. KasaDeposu
  /// .hareketEkleTxn'deki aynı not). Bildirim çağıranın sorumluluğunda.
  /// Geriye eklenen kaydın global_id'sini döner — çağıran bu id ile
  /// transaction kapandıktan sonra TAM OLARAK eklenen satırı bulabilir.
  Future<String> hareketEkleTxn(dynamic txn, CariHareketModel hareket) async {
    final hm = hareket.toMap();
    hm.remove('id');
    final globalId = (hm['global_id'] as String?) ?? const Uuid().v4();
    hm['global_id'] = globalId;
    await txn.insert('cari_hareket', hm);
    await txn.rawUpdate('''
      UPDATE cari SET bakiye = (
        SELECT COALESCE(SUM(borc), 0) - COALESCE(SUM(alacak), 0)
        FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0
      ) WHERE id = ?
    ''', [hareket.cariId, hareket.cariId]);
    // Madde 5 sertleştirmesi: hareket kaydı VE etkilediği cari bakiyesi
    // AYNI transaction içinde kuyruğa yazılıyor — ikisi de business
    // data ile atomik (bkz. SyncKuyrukYazici yorumu).
    await SyncKuyrukYazici.ekleTxn(txn, tablo: 'cari_hareket', veri: hm);
    final guncelCariSatiri = await txn.query('cari',
        where: 'id = ?', whereArgs: [hareket.cariId], limit: 1);
    if (guncelCariSatiri.isNotEmpty) {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'cari', veri: Map<String, dynamic>.from(guncelCariSatiri.first));
    }
    return globalId;
  }

  Future<void> bakiyeYenidenHesapla(int cariId) async {
    try {
      final db = await _d;
      // 🔴🔴 KRİTİK DÜZELTME (kullanıcı isteği — "veri sağlığı merkezine
      // düzgün bak"): StokDeposu.stokMutabakatYap()'ta AYNI hata sınıfı
      // daha önce bulunup düzeltilmişti ama buraya (Cari Mutabakat)
      // hiç uygulanmamıştı — last_updated hiç bümlenmiyor, BulutManager
      // hiç çağrılmıyordu. Sonuç: Veri Sağlığı Merkezi'nden "Cari
      // Mutabakat" düzeltmesi çalıştırıldığında, düzeltilen bakiye
      // SADECE bu cihazda kalıyordu — normal "Hızlı Gönder" (delta,
      // last_updated'a bakar) bunu ASLA yakalamıyor, diğer cihazlar/
      // bulut hâlâ eski (hatalı) bakiyeyi görmeye devam ediyordu.
      final now = DateTime.now().toIso8601String();
      await db.rawUpdate('''
        UPDATE cari SET bakiye = (
          SELECT COALESCE(SUM(borc), 0) - COALESCE(SUM(alacak), 0)
          FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0
        ), last_updated = ? WHERE id = ?
      ''', [cariId, now, cariId]);
      final satir = await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('cari', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Cari.bakiyeYenidenHesapla', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Veri Sağlığı Merkezi (protokol §13/§8) için: HER carinin bakiyesini
  /// cari_hareket'ten yeniden hesaplayıp gerçekte tutmayanları düzeltir.
  /// stokMutabakatYap() ile aynı desen — hangi sırayla senkron olursa
  /// olsun sonuç her zaman doğru olur.
  Future<int> bakiyeMutabakatYap() async {
    try {
      final db = await _d;
      final uyumsuzlar = await db.rawQuery('''
        SELECT c.id FROM cari c
        WHERE c.is_deleted = 0 AND ABS(c.bakiye - (
          SELECT COALESCE(SUM(borc), 0) - COALESCE(SUM(alacak), 0)
          FROM cari_hareket WHERE cari_id = c.id AND is_deleted = 0
        )) > 0.01
      ''');
      for (final r in uyumsuzlar) {
        await bakiyeYenidenHesapla(r['id'] as int);
      }
      return uyumsuzlar.length;
    } catch (e, st) {
      LogServisi().hata('Cari.bakiyeMutabakatYap', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Yalnızca SAYIYI döner, düzeltme yapmaz — Veri Sağlığı Merkezi'nde
  /// "kontrol et" adımında (henüz düzeltme onayı almadan) durumu
  /// göstermek için.
  Future<int> bakiyeUyumsuzlukSayisi() async {
    try {
      final db = await _d;
      final rows = await db.rawQuery('''
        SELECT COUNT(*) as n FROM cari c
        WHERE c.is_deleted = 0 AND ABS(c.bakiye - (
          SELECT COALESCE(SUM(borc), 0) - COALESCE(SUM(alacak), 0)
          FROM cari_hareket WHERE cari_id = c.id AND is_deleted = 0
        )) > 0.01
      ''');
      return (rows.first['n'] as int?) ?? 0;
    } catch (e, st) {
      LogServisi().hata('Cari.bakiyeUyumsuzlukSayisi', hata: e, yigin: st);
      return 0;
    }
  }

  Future<List<CariHareketModel>> hareketleriniGetir(int cariId,
      {DateTime? basTarih, DateTime? bitTarih, String? fisTipi, int limit = 100}) async {
    final db = await _d;
    final whereParts = ['cari_id = ?', 'is_deleted = 0'];
    final args = <dynamic>[cariId];

    if (basTarih != null) {
      whereParts.add('datetime(tarih) >= datetime(?)');
      args.add(basTarih.toIso8601String());
    }
    if (bitTarih != null) {
      whereParts.add('datetime(tarih) <= datetime(?)');
      args.add(bitTarih.toIso8601String());
    }
    if (fisTipi != null) {
      whereParts.add('fis_tipi = ?');
      args.add(fisTipi);
    }

    final rows = await db.rawQuery(
      'SELECT * FROM cari_hareket WHERE ${whereParts.join(' AND ')} ORDER BY tarih DESC LIMIT $limit',
      args,
    );
    return rows.map(CariHareketModel.fromMap).toList();
  }

  /// Bir cari hareketi iptal eder: orijinal kayıt SOFT-DELETE edilir
  /// (is_deleted=1, hard-delete edilmez — bulut senkron için gerekli),
  /// audit-trail amaçlı borc=0/alacak=0 bir "... İptali" kaydı eklenir,
  /// bakiye hareketlerden yeniden hesaplanır (her zaman is_deleted=0
  /// filtresiyle — kanonik kural), ve varsa bağlı (referans_turu=
  /// 'cari_hareket') NAKİT kasa hareketi otomatik ters çevrilir. Banka/
  /// Kredi Kartı bağlı kayıtlar otomatik geri alınmaz — güvenli fallback,
  /// kullanıcı o tarafı elle düzeltmeli.
  ///
  /// Ters kaydın borc=0/alacak=0 olması BİLİNÇLİDİR: orijinal kayıt zaten
  /// bakiye SUM'ından (is_deleted=0 filtresiyle) dışlandığı için, sıfır
  /// olmayan bir ters tutar eklemek bakiyeyi orijinal tutarın TERSİ kadar
  /// kaydırırdı (10 TL'lik hareket silinince bakiye 0'a değil +10'a giderdi).
  Future<void> hareketIptalEt(CariHareketModel h) async {
    if (h.id == null) throw Exception('Hareket id boş olamaz');
    try {
      final db = await _d;
      String? tersCariGid;
      int? tersKasaId;
      await db.transaction((txn) async {
        final guncelRows = await txn
            .query('cari_hareket', where: 'id = ?', whereArgs: [h.id]);
        if (guncelRows.isEmpty) throw Exception('Hareket bulunamadı');
        final guncel = guncelRows.first;
        if ((guncel['is_deleted'] as int? ?? 0) == 1) {
          throw Exception('Bu hareket zaten iptal edilmiş');
        }
        final now = DateTime.now().toIso8601String();

        await txn.update('cari_hareket',
            {'is_deleted': 1, 'last_updated': now},
            where: 'id = ?', whereArgs: [h.id]);

        final tersGid = const Uuid().v4();
        await txn.insert('cari_hareket', {
          'global_id': tersGid,
          'cari_id': h.cariId,
          'tarih': now,
          'fis_tipi': '${h.fisTipi} İptali',
          'fis_id': h.id,
          'fis_no': h.fisNo,
          'aciklama': 'İptal: ${h.aciklama} '
              '(${ParaUtils.formatla(h.borc > 0 ? h.borc : h.alacak)})',
          'borc': 0,
          'alacak': 0,
          'odeme_turu': h.odemeTuru,
          'kullanici': AuthServisi().aktifAd,
          'last_updated': now,
          'is_deleted': 0,
        });
        tersCariGid = tersGid;

        await txn.rawUpdate('''
          UPDATE cari SET bakiye = (
            SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0)
            FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0
          ), last_updated = ?
          WHERE id = ?
        ''', [h.cariId, now, h.cariId]);

        final kasaRows = await txn.query('kasa_hareketleri',
            where:
                'referans_turu = ? AND referans_id = ? AND deleted_at IS NULL',
            whereArgs: ['cari_hareket', h.id]);
        if (kasaRows.isNotEmpty) {
          final orijinalKasa = kasaRows.first;
          final orijinalTip = orijinalKasa['hareket_tipi'] as String? ?? '';
          final orijinalTutar =
              (orijinalKasa['tutar'] as num?)?.toDouble() ?? 0;
          final tersTip = orijinalTip == 'Tahsilat'
              ? 'Tahsilat İptali'
              : orijinalTip == 'Ödeme'
                  ? 'Ödeme Girişi'
                  : null;
          if (tersTip != null && orijinalTutar > 0) {
            tersKasaId = await KasaDeposu().hareketEkleTxn(
                txn,
                KasaHareketModel(
                  hareketTipi: tersTip,
                  tutar: orijinalTutar,
                  referansId: h.id,
                  referansTuru: 'cari_hareket_iptal',
                  tarih: DateTime.parse(now),
                  aciklama: 'İptal: ${h.aciklama}',
                ));
          }
        }
      });

      final orijinalSatir = await db.query('cari_hareket',
          where: 'id = ?', whereArgs: [h.id], limit: 1);
      if (orijinalSatir.isNotEmpty) {
        BulutManager().upsert(
            'cari_hareket', Map<String, dynamic>.from(orijinalSatir.first));
      }
      if (tersCariGid != null) {
        final satir = await db.query('cari_hareket',
            where: 'global_id = ?', whereArgs: [tersCariGid], limit: 1);
        if (satir.isNotEmpty) {
          BulutManager()
              .upsert('cari_hareket', Map<String, dynamic>.from(satir.first));
        }
      }
      final cariSatir = await db.query('cari',
          where: 'id = ?', whereArgs: [h.cariId], limit: 1);
      if (cariSatir.isNotEmpty) {
        BulutManager()
            .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
      }
      if (tersKasaId != null) {
        final kasaSatir = await db.query('kasa_hareketleri',
            where: 'id = ?', whereArgs: [tersKasaId], limit: 1);
        if (kasaSatir.isNotEmpty) {
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
      }
    } catch (e, st) {
      LogServisi().hata('Cari.hareketIptalEt', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<Map<String, double>> istatistikler() async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        "SELECT COUNT(*) as toplam, "
        // 🔴 DÜZELTME: "Hem Müşteri Hem Tedarikçi" tipi (bu oturumda
        // cari ekle ekranına eklenen 3. seçenek) ne 'musteri' ne
        // 'tedarikci' sayısına dahil edilmiyordu — tam eşleşme (=)
        // yerine LIKE ile her iki kategoriye de sayılıyor.
        "COUNT(CASE WHEN cari_tipi LIKE '%Müşteri%' THEN 1 END) as musteri, "
        "COUNT(CASE WHEN cari_tipi LIKE '%Tedarikçi%' THEN 1 END) as tedarikci, "
        "SUM(CASE WHEN bakiye > 0 THEN bakiye ELSE 0 END) as toplam_alacak, "
        "SUM(CASE WHEN bakiye < 0 THEN ABS(bakiye) ELSE 0 END) as toplam_borc "
        "FROM cari WHERE is_deleted = 0",
      );
      if (res.isEmpty) return {};
      final r = res.first;
      return {
        'toplam': (r['toplam'] as num?)?.toDouble() ?? 0,
        'musteri': (r['musteri'] as num?)?.toDouble() ?? 0,
        'tedarikci': (r['tedarikci'] as num?)?.toDouble() ?? 0,
        'toplam_alacak': (r['toplam_alacak'] as num?)?.toDouble() ?? 0,
        'toplam_borc': (r['toplam_borc'] as num?)?.toDouble() ?? 0,
      };
    } catch (e, st) {
      LogServisi().hata('Cari.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<CariModel>> vadesiGecmisler() async {
    try {
      final db = await _d;
      // 🔴 DÜZELTME (cari ekranları derin analizi, 2026-09-14): ch.tarih
      // DateTime.now().toIso8601String() ile (CİHAZIN YEREL SAATİYLE, UTC
      // DEĞİL) yazılıyor — ama datetime('now') SQLite'ta VARSAYILAN OLARAK
      // UTC döner. Bu ikisini karşılaştırmak, Türkiye'de (+3) sistematik
      // ~3 saatlik bir kaymaya yol açıyordu — bir alacak, gerçekte vadesi
      // geçtikten SAATLER SONRA "vadesi geçmiş" listesine düşüyordu. Aynı
      // hata sınıfı bu oturumdan önce 6 ayrı yerde bulunup 'localtime'
      // değiştiricisiyle düzeltilmişti (bkz. rapor_deposu.dart,
      // kar_zarar_provider.dart vb.) — bu yedinci örnek o turda
      // kapsanmamış.
      final rows = await db.rawQuery('''
        SELECT c.* FROM cari c
        WHERE c.is_deleted = 0 AND c.aktif = 1 AND c.bakiye > 0
          AND c.vade_gun > 0
          AND EXISTS (
            SELECT 1 FROM cari_hareket ch
            WHERE ch.cari_id = c.id AND ch.borc > 0 AND ch.is_deleted = 0
            AND datetime(ch.tarih, '+' || c.vade_gun || ' days') < datetime('now', 'localtime')
          )
        ORDER BY c.bakiye DESC
      ''');
      return rows.map(CariModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Cari.metod', hata: e, yigin: st);
      rethrow;
    }
  }
}