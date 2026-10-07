import '../servisler/bulut/bulut_manager.dart';
import '../cekirdek/utils/metin_arama.dart';
// lib/depolar/urun_deposu.dart
//
// Düzeltmeler:
//   - ara(): aktif = 1 filtresi eklendi (pasif ürünler arama sonucuna gelmesin)
//   - ara(): alternatif_urun_adi ve marka alanları da aranıyor
//   - sayfaliGetir(): aynı iyileştirmeler uygulandı
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../servisler/log_servisi.dart';
import '../servisler/auth_servisi.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../veri/database/veritabani.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../modeller/urun_model.dart';

part 'urun_deposu_plu_sorgu.dart';
part 'urun_deposu_liste.dart';
part 'urun_deposu_toplu.dart';

class UrunDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;
  Future<Database> get db async => _db.db;

  /// Kullanıcı geri bildirimi: "Excel'den 4000 ürünü içe aktarırken
  /// uzun sürdü." Kök neden: normal `ekle()`/`guncelle()` fonksiyonları
  /// HER SATIR için ayrı ayrı veritabanı işlemi açıyor (4000 satır için
  /// binlerce ayrı disk yazması demek). Bu fonksiyon, mevcut ekle()/
  /// guncelle()'ye HİÇ DOKUNMADAN (diğer tüm çağıranlar aynı şekilde
  /// çalışmaya devam ediyor), SADECE toplu içe aktarım gibi
  /// performans-kritik senaryolar için TEK bir transaction içinde
  /// çalışan, çok daha hızlı bir alternatif sunuyor. Stok değişikliği
  /// takibi (event sourcing) burada da korunuyor.
  Future<Map<String, dynamic>> topluEkleGuncelle(
      List<({UrunModel urun, int? mevcutId})> satirlar) async {
    final db = await _d;
    var eklenen = 0, guncellenen = 0;
    // 🔴🔴 KRİTİK DÜZELTME (kendi-keşif turu — Excel modülü denetimi):
    // bir satır aşağıdaki catch'e düşünce (ör. mükerrer barkod/kod)
    // ÖNCEDEN sadece LogServisi'ne yazılıp SESSİZCE atlanıyordu —
    // dönen {'eklenen','guncellenen'} sayıları bu satırı hiç
    // YANSITMIYORDU. Sonuç: kullanıcı "Toplam 500 satır, 480 eklendi,
    // 5 hatalı" görüyordu ama aslında 15 satır burada sessizce
    // başarısız olmuş, ne dialogda ne hata listesinde hiç görünmüyordu.
    // Artık bu satırlar da toplanıp çağırana (ExcelServisi —
    // IceriAktarSonuc.hatalar'a eklenir) döndürülüyor.
    final basarisizSatirlar = <String>[];
    // ÖNCEDEN BURADA CİDDİ BİR HATA VARDI: TÜM satırlar TEK bir
    // transaction'a konmuştu — bu, hız için doğruydu AMA eğer
    // Excel'de TEK BİR satır bile sorunlu ise (örn. mükerrer barkod,
    // geçersiz veri), o TEK satırın hatası TÜM transaction'ı iptal
    // edip GERİ ALIYORDU — kullanıcının bildirdiği gibi "önceden
    // çalışıyordu, şimdi hiç çalışmıyor" tam olarak buydu. Artık her
    // satır KENDİ İÇ transaction'ında işleniyor — bir satır hata
    // verirse SADECE o satır atlanır, diğerleri (hız avantajı
    // korunarak) yine de kaydedilir.
    for (final s in satirlar) {
      try {
        int? etkilenenId;
        String? hareketGid;
        await db.transaction((txn) async {
          final m = s.urun.toMap()..remove('id');
          m['global_id'] ??= const Uuid().v4();
          m['last_updated'] = DateTime.now().toIso8601String();

          if (s.mevcutId == null) {
            // 🔴🔴 P0 (derin denetimde bulundu): ekle() ile AYNI hata —
            // bkz. oradaki not. Excel toplu içe aktarımda bu daha da
            // tehlikeli: yüzlerce satırlık bir dosyada tek bir mükerrer
            // barkod/kod, mevcut bir ürünü sessizce SİLİP YERİNE
            // GEÇEBİLİRDİ. abort ile artık bu satır normal şekilde
            // aşağıdaki catch'e düşüp ATLANIYOR (diğer satırlar
            // etkilenmiyor — dosyadaki mevcut per-satır izolasyon
            // deseniyle tam uyumlu).
            final id = await txn.insert(DbSabitler.urunler, m,
                conflictAlgorithm: ConflictAlgorithm.abort);
            etkilenenId = id;
            if (s.urun.stok > 0) {
              hareketGid = const Uuid().v4();
              final stokSatiri = {
                'global_id': hareketGid,
                'urun_id': id,
                'hareket_turu': 'İlk Stok',
                'miktar': s.urun.stok,
                'onceki_stok': 0,
                'sonraki_stok': s.urun.stok,
                'tarih': DateTime.now().toIso8601String(),
                'last_updated': DateTime.now().toIso8601String(),
                'referans_turu': 'excel_toplu_iceri_aktarim',
              };
              await txn.insert('stok_hareket', stokSatiri);
              await SyncKuyrukYazici.ekleTxn(txn,
                  tablo: 'stok_hareket', veri: stokSatiri);
            }
            eklenen++;
            // 🔴 DEEP_AUDIT_REPORT madde 3: kuyruk kaydı artık business
            // data ile AYNI transaction'da (bkz. guncelle()'deki aynı
            // gerekçe) — Excel toplu içe aktarımda uygulama satır
            // ortasında kapanırsa bile kuyruk kaydı diskte kalıcı olur.
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'urunler', veri: {...m, 'id': id});
          } else {
            etkilenenId = s.mevcutId;
            final eskiRows = await txn.query(DbSabitler.urunler,
                columns: ['stok', 'satis_fiyati', 'alis_fiyat'],
                where: 'id = ?', whereArgs: [s.mevcutId]);
            if (eskiRows.isNotEmpty) {
              final eskiStok = (eskiRows.first['stok'] as num?)?.toDouble() ?? 0;
              if (eskiStok != s.urun.stok) {
                hareketGid = const Uuid().v4();
                final stokSatiri = {
                  'global_id': hareketGid,
                  'urun_id': s.mevcutId,
                  'hareket_turu': 'Manuel Düzeltme',
                  'miktar': (s.urun.stok - eskiStok).abs(),
                  'onceki_stok': eskiStok,
                  'sonraki_stok': s.urun.stok,
                  'tarih': DateTime.now().toIso8601String(),
                  'last_updated': DateTime.now().toIso8601String(),
                  'referans_turu': 'excel_toplu_iceri_aktarim',
                };
                await txn.insert('stok_hareket', stokSatiri);
                await SyncKuyrukYazici.ekleTxn(txn,
                    tablo: 'stok_hareket', veri: stokSatiri);
              }
              final eskiSatis = (eskiRows.first['satis_fiyati'] as num?)?.toDouble() ?? 0;
              final eskiAlis  = (eskiRows.first['alis_fiyat'] as num?)?.toDouble() ?? 0;
              if (eskiSatis != s.urun.satisFiyati || eskiAlis != s.urun.alisFiyat) {
                // satış → Fiyat Güncelleme Tarihi, alış → Maliyet Güncelleme Tarihi
                fiyatMaliyetDamgala(
                    m, eskiRows.first, DateTime.now().toIso8601String());
              }
            }
            await txn.update(DbSabitler.urunler, m,
                where: 'id = ?', whereArgs: [s.mevcutId]);
            await SyncKuyrukYazici.ekleTxn(txn,
                tablo: 'urunler', veri: {...m, 'id': s.mevcutId});
            guncellenen++;
          }
        });
        // 🔴 Derin analizde bulundu: bu fonksiyon (Excel toplu içe
        // aktarım — yüzlerce ürünü aynı anda etkileyebilir) hem
        // 'urunler' hem 'stok_hareket' için BulutManager'ı HİÇ
        // çağırmıyordu, global_id de atamıyordu — toplu aktarılan
        // ürünler sadece manuel senkronla buluta gidiyordu.
        if (etkilenenId != null) {
          final urunSatir = await db.query(DbSabitler.urunler, where: 'id = ?', whereArgs: [etkilenenId], limit: 1);
          if (urunSatir.isNotEmpty) {
            BulutManager().upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
          }
        }
        if (hareketGid != null) {
          final hareketSatir = await db.query('stok_hareket', where: 'global_id = ?', whereArgs: [hareketGid], limit: 1);
          if (hareketSatir.isNotEmpty) {
            BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
          }
        }
      } catch (e) {
        LogServisi().hata('UrunDeposu.topluEkleGuncelle (satır atlandı)', hata: e);
        // Bu satır atlanıyor, döngü DEVAM EDİYOR — diğer satırlar etkilenmiyor.
        final tanimlayici = (s.urun.barkod?.isNotEmpty ?? false)
            ? s.urun.barkod!
            : (s.urun.urunAdi.isNotEmpty ? s.urun.urunAdi : '?');
        basarisizSatirlar.add('$tanimlayici: $e');
      }
    }
    return {
      'eklenen': eklenen,
      'guncellenen': guncellenen,
      'hatalar': basarisizSatirlar,
    };
  }

  // ── CRUD ────────────────────────────────────────────────────────────────

  /// Görsel buluta yüklendikten sonra oluşan adresi kaydeder.
  /// Kasıtlı olarak SADECE bu tek sütunu günceller — tam guncelle()
  /// çağrılmıyor, böylece stok/fiyat karşılaştırma mantığı gereksiz
  /// yere tekrar tetiklenmiyor.
  Future<void> resimUrlGuncelle(int urunId, String resimUrl) async {
    try {
      final db = await _d;
      await db.update(DbSabitler.urunler, {
        'resim_url': resimUrl,
        'last_updated': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [urunId]);
      // 🔴 DÜZELTME: last_updated doğru bümleniyordu (manuel "Buluta
      // Gönder" bu değişikliği zaten yakalardı) AMA BulutManager'a
      // hiç haber verilmiyordu — yani resim ANINDA/OTOMATİK olarak
      // gönderilmiyordu, sadece kullanıcı elle "Buluta Gönder"e
      // basarsa gidiyordu. Artık diğer güncelleme fonksiyonlarıyla
      // aynı desen: tam satır okunup kuyruğa veriliyor.
      final guncelSatir = await db.query(DbSabitler.urunler,
          where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('urunler', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('UrunDeposu.resimUrlGuncelle', hata: e, yigin: st);
    }
  }

  /// SATIŞ fiyatı değiştiyse "Fiyat Güncelleme Tarihi/Güncelleyen", ALIŞ
  /// fiyatı (maliyet) değiştiyse "Maliyet Güncelleme Tarihi/Güncelleyen"
  /// damgalanır. [yeni]: yazılacak alanlar (yerinde değiştirilir). [eski]:
  /// mevcut satır (null → yeni kayıt, mevcut anahtarların hepsi "değişmiş"
  /// sayılır). Eski satırda olmayan anahtar karşılaştırılmaz.
  static void fiyatMaliyetDamgala(
      Map<String, dynamic> yeni, Map<String, Object?>? eski, String now) {
    bool degisti(String k) {
      if (!yeni.containsKey(k)) return false;
      if (eski == null) return true;
      if (!eski.containsKey(k)) return false;
      final a = (yeni[k] as num?)?.toDouble() ?? 0;
      final b = (eski[k] as num?)?.toDouble() ?? 0;
      return (a - b).abs() > 1e-9;
    }

    final kul = AuthServisi().aktifAd;
    if (degisti('satis_fiyati')) {
      yeni['fiyat_guncelleme_tarih'] = now;
      if (kul.isNotEmpty) yeni['fiyat_guncelleyen_kullanici'] = kul;
    }
    if (degisti('alis_fiyat') || degisti('alis_fiyat_kdv_dahil')) {
      yeni['maliyet_guncelleme_tarih'] = now;
      if (kul.isNotEmpty) yeni['maliyet_guncelleyen_kullanici'] = kul;
    }
  }

  Future<int> ekle(UrunModel urun) async {
    final db = await _d;
    final m = urun.toMap()..remove('id');
    m['global_id'] ??= const Uuid().v4();
    // Yeni ürün: ilk fiyat ve maliyet de bir "güncelleme" sayılır — listede
    // Fiyat/Maliyet Güncelleme Tarihi boş kalmasın.
    final ilkTarih = DateTime.now().toIso8601String();
    m['fiyat_guncelleme_tarih'] ??= ilkTarih;
    m['maliyet_guncelleme_tarih'] ??= ilkTarih;
    // 🔴🔴 P0 (derin denetimde bulundu): ConflictAlgorithm.replace,
    // urunler.kod/barkod UNIQUE çakışmasında istisna FIRLATMAZ — SQLite
    // bunun yerine ÇAKIŞAN ESKİ SATIRI SESSİZCE SİLİP yeni bir id ile
    // yeniden ekler. Somut senaryo: kasiyer yeni ürün eklerken zaten
    // kayıtlı bir ürünün barkodunu (yanlışlıkla) girerse, o ESKİ ürüne
    // bağlı TÜM stok_hareket/satis_kalem/lot_seri/sube_urun kayıtları
    // artık var olmayan bir urun_id'ye işaret eder — geçmiş satışlarda/
    // raporlarda o kalemler sessizce kaybolur, kullanıcıya "Ürün
    // eklendi ✓" gösterilir. Aşağıdaki catch bloğu ("Bu barkod zaten
    // başka bir üründe kullanılıyor") TAM OLARAK bu senaryo için
    // yazılmıştı ama replace hiç istisna fırlatmadığı için pratikte
    // ASLA tetiklenmiyordu. abort (SQLite'ın varsayılanı) ile artık
    // gerçek bir UNIQUE ihlali doğru şekilde istisna fırlatıyor.
    final id = await db.insert(DbSabitler.urunler, m,
        conflictAlgorithm: ConflictAlgorithm.abort);
    BulutManager().upsert('urunler', {...m, 'id': id});
    // ÖNCEDEN başlangıç stoğu (yeni ürün eklenirken "50 adet ile
    // başla" gibi) hiçbir zaman bir hareket olarak kaydedilmiyordu.
    // Stok mutabakat sistemi (hareketlerin toplamı) bu ürünü hiç
    // görmediği bir "hayalet" başlangıç stoğuyla karşılaşırdı. Artık
    // stok > 0 ile eklenen her ürün için "İlk Stok" hareketi de
    // kaydediliyor.
    if (urun.stok > 0) {
      final hareketGid = const Uuid().v4();
      await db.insert('stok_hareket', {
        'global_id': hareketGid,
        'urun_id': id,
        'hareket_turu': 'İlk Stok',
        'miktar': urun.stok,
        'onceki_stok': 0,
        'sonraki_stok': urun.stok,
        'tarih': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
        'referans_turu': 'ilk_stok',
        'aciklama': 'Ürün eklenirken girilen başlangıç stoğu',
      });
      // 🔴 Derin analizde bulundu: global_id atanmıyordu, BulutManager
      // hiç çağrılmıyordu — yeni ürün başlangıç stoğu hareketi sadece
      // manuel senkronla buluta gidiyordu.
      final hareketSatir = await db.query('stok_hareket', where: 'global_id = ?', whereArgs: [hareketGid], limit: 1);
      if (hareketSatir.isNotEmpty) {
        BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
      }
    }
    return id;
  }

  /// Kullanıcı sorusu "kur değişti o zaman nasıl olacak?" için: döviz
  /// bazında takip edilen (dovizKodu dolu) tüm ürünleri getirir — "Toplu
  /// Döviz Güncelleme" ekranı bunları güncel kurla yeniden fiyatlandırır.
  Future<List<UrunModel>> dovizBazliUrunleriGetir() async {
    final db = await _d;
    final rows = await db.query(DbSabitler.urunler,
        where: "doviz_kodu IS NOT NULL AND doviz_kodu != '' AND is_deleted = 0",
        orderBy: 'urun_adi ASC');
    return rows.map(UrunModel.fromMap).toList();
  }

  /// Tek bir ürünün alış fiyatını (döviz tutarı × güncel kur ile) günceller.
  /// ÖNCEDEN BURADA GERÇEK BİR HATA VARDI: sadece KDV HARİÇ alış fiyatı
  /// güncelleniyordu, "KDV Dahil Alış" alanı ESKİ (yanlış/tutarsız)
  /// değerinde kalıyordu — kullanıcının bulduğu "kur değişti, KDV'li
  /// alışı yenilemiyor" sorunu tam olarak buydu. Artık ürünün kendi KDV
  /// oranı okunup, KDV dahil fiyat da (aynı formülle Ürün Ekle
  /// ekranındaki gibi) doğru şekilde yeniden hesaplanıp kaydediliyor.
  Future<void> alisFiyatiGuncelle(int urunId, double yeniAlisFiyat) async {
    final db = await _d;
    final rows = await db.query(DbSabitler.urunler,
        columns: ['alis_kdv_oran'], where: 'id = ?', whereArgs: [urunId]);
    final kdvOrani = rows.isNotEmpty
        ? ((rows.first['alis_kdv_oran'] as num?)?.toDouble() ?? 0)
        : 0.0;
    final yeniKdvDahil = yeniAlisFiyat * (1 + kdvOrani / 100);
    final now = DateTime.now().toIso8601String();
    // 🔴 Derin analizde bulundu: guncelle() (tekli ürün düzenleme akışı)
    // fiyat gerçekten değiştiğinde fiyat_guncelleme_tarih'i damgalıyordu
    // (bkz. o fonksiyondaki not) ama bu toplu/döviz fiyat güncelleme
    // yolu bunu hiç yapmıyordu — tutarsızlık için düzeltildi.
    // 🔴 DEEP_AUDIT_REPORT madde 3: kuyruk kaydı artık business data ile
    // AYNI transaction'da (bkz. guncelle()'deki aynı gerekçe).
    final guncelleme = {
      'alis_fiyat': yeniAlisFiyat, 'alis_fiyat_kdv_dahil': yeniKdvDahil,
      'last_updated': now,
    };
    // Alış fiyatı değişti → Maliyet Güncelleme Tarihi (satış fiyatı değil).
    fiyatMaliyetDamgala(guncelleme, null, now);
    await db.transaction((txn) async {
      await txn.update(DbSabitler.urunler, guncelleme,
          where: 'id = ?', whereArgs: [urunId]);
      // Kısmi harita DEĞİL tam satır: kısmi harita global_id taşımıyor,
      // bulutta kimliksiz hayalet ürün açıyordu (Bulut Veri Güvenliği
      // Raporu 2026-10-07, Bulgu 3).
      final satir = await txn.query(DbSabitler.urunler,
          where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (satir.isNotEmpty) {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'urunler', veri: Map<String, dynamic>.from(satir.first));
      }
    });
    final guncelSatir = await db.query(DbSabitler.urunler, where: 'id = ?', whereArgs: [urunId], limit: 1);
    if (guncelSatir.isNotEmpty) {
      BulutManager().upsert('urunler', Map<String, dynamic>.from(guncelSatir.first));
    }
  }

  // 🔴 DÜZELTME (Madde 19 — Silme Mantığı denetimi, 2026-09-16): bu
  // metodun (şu an hiçbir yerden çağrılmıyor, ama gelecekte "seçili
  // ürünleri getir" amaçlı kullanılabilir) 'is_deleted' filtresi yoktu —
  // dosyadaki diğer TÜM toplu sorgular (ara, tumunuGetir, sayfaliGetir
  // vb.) bunu uyguluyor, bu istisnaydı.
  Future<List<UrunModel>> idListesiyleGetir(List<int> idler) async {
    if (idler.isEmpty) return [];
    final db = await _d;
    final phs = idler.map((_) => '?').join(',');
    final rows = await db.rawQuery(
        'SELECT * FROM urunler WHERE id IN ($phs) AND is_deleted = 0 ORDER BY urun_adi',
        idler);
    return rows.map(UrunModel.fromMap).toList();
  }

  Future<void> guncelle(UrunModel urun) async {
    try {
      final db  = await _d;
      final now = DateTime.now().toIso8601String();
      final m   = urun.toMap()
        ..['guncelleme_tarihi'] = now
        ..['last_updated']      = now;

      // Kullanıcı isteği: "aynı ürünü başka cihazdan güncelleme nasıl
      // olacak" — alan bazlı çakışma koruması için, fiyat GERÇEKTEN
      // değiştiyse fiyat_guncelleme_tarih damgalanıyor (önceden bu
      // sütun veritabanında vardı ama HİÇBİR YERDE kullanılmıyordu).
      // Bu, senkronizasyon sırasında "fiyatı kim en son değiştirdi"
      // sorusunu, TÜM kaydın zaman damgasından BAĞIMSIZ olarak doğru
      // cevaplamamızı sağlıyor.
      double? eskiSatis;
      double? eskiAlis;
      if (urun.id != null) {
        final eski = await db.query(DbSabitler.urunler,
            columns: ['satis_fiyati', 'alis_fiyat', 'alis_fiyat_kdv_dahil'],
            where: 'id = ?', whereArgs: [urun.id]);
        if (eski.isNotEmpty) {
          eskiSatis = (eski.first['satis_fiyati'] as num?)?.toDouble() ?? 0;
          eskiAlis  = (eski.first['alis_fiyat'] as num?)?.toDouble() ?? 0;
          if (eskiSatis != urun.satisFiyati || eskiAlis != urun.alisFiyat) {
            // Satış fiyatı → Fiyat Güncelleme Tarihi, alış fiyatı → Maliyet
            // Güncelleme Tarihi (+ güncelleyen kullanıcı).
            fiyatMaliyetDamgala(m, eski.first, now);
            // 🔴 DÜZELTME (Madde 14 — Fiyat Onayı denetimi, 2026-09-16):
            // UI katmanında (urun_detay_ekrani.dart) artık TsYetkili ile
            // sadece Admin/Müdür bu forma ulaşabiliyor — ama bu SADECE
            // widget guard. Deep-link veya ileride eklenecek başka bir
            // giriş noktası bu kontrolü atlayabilir (Madde 15: "route
            // guard/widget guard/service guard/repository guard uyumlu
            // mu?"). Burası REPOSITORY GUARD katmanı — fiyat gerçekten
            // değiştiyse ve aktif kullanıcı Müdür/Admin DEĞİLSE, işlem
            // tamamen reddedilir (sessizce eski fiyata dönmek yerine —
            // bu, arayüzdeki bir hatayı gizler, kullanıcıyı yanıltır).
            if (!AuthServisi().isMudur) {
              throw StateError(
                  'Fiyat değişikliği için yetkiniz yok — sadece Müdür/Admin fiyat değiştirebilir.');
            }
          }
        } else {
          m['fiyat_guncelleme_tarih'] = now; // yeni kayıt gibi davran
          m['maliyet_guncelleme_tarih'] = now;
        }
      }

      // plu ve plu_kart_boyut korunur — ürün güncelleme PLU ayarını sıfırlamaz
      // 🔴 DEEP_AUDIT_REPORT madde 3 (Ürün yönetimi sync-atomikliği):
      // ÖNCEDEN stok_hareket ekleme ve urunler güncelleme İKİ AYRI,
      // transaction'sız yazımdı — aradaki bir çökme "stok hareketi var
      // ama urunler.stok hiç değişmedi" gibi tutarsız bir ara duruma yol
      // açabilirdi. satis_tamamlama_servisi/iade_islem_servisi'deki AYNI
      // desenle sarmalandı: TEK transaction + SyncKuyrukYazici.ekleTxn
      // (kuyruk kaydı business data ile atomik) — BulutManager().upsert()
      // (audit log + gerçek bulut bildirimi) transaction kapandıktan
      // SONRA, aynı şekilde çağrılmaya devam ediyor.
      String? stokHareketGid;
      await db.transaction((txn) async {
        if (urun.id != null) {
          final mevcut = await txn.query(DbSabitler.urunler,
              columns: ['plu', 'plu_kart_boyut', 'stok'],
              where: 'id = ?', whereArgs: [urun.id]);
          if (mevcut.isNotEmpty) {
            final mplu   = mevcut.first['plu']           as int? ?? 0;
            final mboyut = mevcut.first['plu_kart_boyut'] as int? ?? 2;
            if (mplu == 1) {
              m['plu']           = mplu;
              m['plu_kart_boyut'] = mboyut;
            }
            // ÖNCEDEN BURADA: kullanıcı Ürün Güncelle formundan stoğu
            // doğrudan değiştirip kaydettiğinde, bu değişiklik HİÇBİR
            // hareket kaydına dönüşmüyordu — stok mutabakat sistemi için
            // tamamen görünmezdi. Artık stok gerçekten değiştiyse,
            // otomatik bir "Manuel Düzeltme" hareketi oluşturuluyor.
            final eskiStok = (mevcut.first['stok'] as num?)?.toDouble() ?? 0;
            if (eskiStok != urun.stok) {
              stokHareketGid = const Uuid().v4();
              final stokSatiri = {
                'global_id': stokHareketGid,
                'urun_id': urun.id,
                'hareket_turu': 'Manuel Düzeltme',
                'miktar': (urun.stok - eskiStok).abs(),
                'onceki_stok': eskiStok,
                'sonraki_stok': urun.stok,
                'tarih': now,
                'last_updated': now,
                'referans_turu': 'urun_guncelle',
                'aciklama': 'Ürün Güncelle ekranından stok değiştirildi',
              };
              await txn.insert('stok_hareket', stokSatiri);
              await SyncKuyrukYazici.ekleTxn(txn,
                  tablo: 'stok_hareket', veri: stokSatiri);
            }
          }
        }

        await txn.update(DbSabitler.urunler, m,
            where: 'id = ?', whereArgs: [urun.id]);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'urunler', veri: {...m, 'id': urun.id});
      });

      if (stokHareketGid != null) {
        final hareketSatir = await db.query('stok_hareket',
            where: 'global_id = ?', whereArgs: [stokHareketGid], limit: 1);
        if (hareketSatir.isNotEmpty) {
          BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
        }
      }
      BulutManager().upsert('urunler', m,
          eskiVeri: eskiSatis != null ? {'satis_fiyati': eskiSatis, 'alis_fiyat': eskiAlis} : null);
    } catch (e, st) {
      LogServisi().hata('UrunDeposu.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sil(int id) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.update(
      DbSabitler.urunler,
      {'is_deleted': 1, 'aktif': 0, 'last_updated': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    final guncelSatir = await db.query(DbSabitler.urunler, where: 'id = ?', whereArgs: [id], limit: 1);
    if (guncelSatir.isNotEmpty) {
      BulutManager().upsert('urunler', Map<String, dynamic>.from(guncelSatir.first));
    }
  }

  /// Madde 2 sertleştirmesi (toplu_islem_ekrani.dart): sadece belirtilen
  /// alanları günceller — [guncelle] (tüm UrunModel'i yeniden yazan)
  /// metodunun aksine, toplu fiyat/stok/alan düzenleme gibi kısmi
  /// güncellemeler için. 'last_updated' otomatik damgalanır.
  Future<void> alanGuncelle(int id, Map<String, dynamic> degisenAlanlar) async {
    final db = await _d;
    final data = Map<String, dynamic>.from(degisenAlanlar);
    data['last_updated'] = DateTime.now().toIso8601String();
    final eskiSatir = await db.query(DbSabitler.urunler,
        where: 'id = ?', whereArgs: [id], limit: 1);
    fiyatMaliyetDamgala(
        data, eskiSatir.isEmpty ? null : eskiSatir.first, data['last_updated'] as String);
    await db.update(DbSabitler.urunler, data, where: 'id = ?', whereArgs: [id]);
    final satir = await db.query(DbSabitler.urunler, where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('urunler', Map<String, dynamic>.from(satir.first));
    }
  }

  /// Madde 2 sertleştirmesi (ayarlar_ekrani.dart — "Pasif ürünleri
  /// aktif yap" toplu bakım aracı). Soft-delete edilmemiş (is_deleted=0)
  /// ama pasif (aktif=0) TÜM ürünleri tek seferde aktif yapar. Döner:
  /// etkilenen satır sayısı.
  Future<int> tumPasifleriAktifYap() async {
    final db = await _d;
    final pasifler = await db.query(DbSabitler.urunler,
        columns: ['id'], where: 'aktif = 0 AND is_deleted = 0');
    final now = DateTime.now().toIso8601String();
    final adet = await db.rawUpdate(
        'UPDATE ${DbSabitler.urunler} SET aktif = 1, last_updated = ? WHERE aktif = 0 AND is_deleted = 0',
        [now]);
    // Önceden hiçbir ürün buluta bildirilmiyordu: diğer cihazlarda pasif kalırdı.
    for (final p in pasifler) {
      final u = await db.query(DbSabitler.urunler, where: 'id = ?', whereArgs: [p['id']], limit: 1);
      if (u.isNotEmpty) BulutManager().upsert(DbSabitler.urunler, Map<String, dynamic>.from(u.first));
    }
    return adet;
  }

  // ── PLU PANELİ (Madde 2 sertleştirmesi — plu_yonetim_ekrani.dart) ──────

}
