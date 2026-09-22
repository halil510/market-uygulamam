import '../servisler/bulut/bulut_manager.dart';
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
                m['fiyat_guncelleme_tarih'] = DateTime.now().toIso8601String();
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

  Future<int> ekle(UrunModel urun) async {
    final db = await _d;
    final m = urun.toMap()..remove('id');
    m['global_id'] ??= const Uuid().v4();
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
    final _id = await db.insert(DbSabitler.urunler, m,
        conflictAlgorithm: ConflictAlgorithm.abort);
    BulutManager().upsert('urunler', {...m, 'id': _id});
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
        'urun_id': _id,
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
    return _id;
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
      'fiyat_guncelleme_tarih': now, 'last_updated': now,
    };
    await db.transaction((txn) async {
      await txn.update(DbSabitler.urunler, guncelleme,
          where: 'id = ?', whereArgs: [urunId]);
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {...guncelleme, 'id': urunId});
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
            columns: ['satis_fiyati', 'alis_fiyat'],
            where: 'id = ?', whereArgs: [urun.id]);
        if (eski.isNotEmpty) {
          eskiSatis = (eski.first['satis_fiyati'] as num?)?.toDouble() ?? 0;
          eskiAlis  = (eski.first['alis_fiyat'] as num?)?.toDouble() ?? 0;
          if (eskiSatis != urun.satisFiyati || eskiAlis != urun.alisFiyat) {
            m['fiyat_guncelleme_tarih'] = now;
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
    return db.rawUpdate(
        'UPDATE ${DbSabitler.urunler} SET aktif = 1 WHERE aktif = 0 AND is_deleted = 0');
  }

  // ── PLU PANELİ (Madde 2 sertleştirmesi — plu_yonetim_ekrani.dart) ──────

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
      final q = '%$aramaMetni%';
      // bkz. ara() üzerindeki aynı kullanıcı bulgusu notu — alternatif
      // barkodlar (`barkodlar`) da aranıyor.
      whereParts.add(
        '(urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?'
        ' OR ana_grup LIKE ? OR alternatif_urun_adi LIKE ? OR marka LIKE ?)',
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
    final q = '%$sorgu%';
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
      ' WHERE (urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?'
      '       OR alternatif_urun_adi LIKE ? OR marka LIKE ?)'
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
      WHERE s.iptal = 0 AND s.is_deleted = 0
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
                          THEN stok * alis_fiyat END), 0)                 AS stok_degeri
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
            ' SET $kolon = ?, guncelleme_tarihi = ?, last_updated = ? WHERE id = ?',
            [oran, now, now, id],
          );
        } else if (yon == 'azalt') {
          await db.rawUpdate(
            'UPDATE ${DbSabitler.urunler}'
            ' SET $kolon = $kolon * ?, guncelleme_tarihi = ?, last_updated = ? WHERE id = ?',
            [1 - (oran / 100), now, now, id],
          );
        } else {
          await db.rawUpdate(
            'UPDATE ${DbSabitler.urunler}'
            ' SET $kolon = $kolon * ?, guncelleme_tarihi = ?, last_updated = ? WHERE id = ?',
            [1 + (oran / 100), now, now, id],
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

  /// PLU Yönetimi ekranından taşındı — bkz.
  /// plu_yonetim_ekrani.dart._siralamaKaydet. Sürükle-bırak ile
  /// belirlenen yeni sıra (liste indeksi = plu_sira) TEK transaction
  /// içinde atomik olarak yazılır, commit sonrası her ürün buluta
  /// bildirilir.
  Future<void> pluSiralamaKaydet(List<int> siraliUrunIdler) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (var i = 0; i < siraliUrunIdler.length; i++) {
        await txn.update(DbSabitler.urunler, {'plu_sira': i, 'last_updated': now},
            where: 'id = ?', whereArgs: [siraliUrunIdler[i]]);
      }
    });
    await _topluBulutSenkronuGonder(siraliUrunIdler);
  }

  /// Toplu Fiyat Güncelleme ekranından taşındı — bkz.
  /// toplu_fiyat_ekrani.dart._guncelle. Nihai fiyat (zam/indirim/sabit/
  /// alış-üstüne modlarının hesabı) çağıran tarafta hesaplanır (bu, UI'a
  /// özgü bir iş kuralı); burası SADECE hesaplanmış {urunId: yeniFiyat}
  /// haritasını TEK transaction içinde atomik olarak yazar (ya hepsi
  /// güncellenir ya hiçbiri) ve commit sonrası her ürünü buluta bildirir.
  Future<List<int>> topluFiyatUygula(Map<int, double> yeniFiyatlar) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final guncellenenIds = <int>[];
    await db.transaction((txn) async {
      for (final entry in yeniFiyatlar.entries) {
        await txn.update(DbSabitler.urunler,
            {'satis_fiyati': entry.value, 'last_updated': now},
            where: 'id = ?', whereArgs: [entry.key]);
        guncellenenIds.add(entry.key);
      }
    });
    await _topluBulutSenkronuGonder(guncellenenIds);
    return guncellenenIds;
  }

  /// Birden fazla ürünün FARKLI alan/değer kombinasyonlarını TEK
  /// transaction'da (ya hepsi ya hiçbiri) günceller — toplu_islem_ekrani
  /// .dart için (Madde 4 sertleştirmesi, 2026-09-16). ÖNCEDEN bu ekran
  /// her ürünü ayrı ayrı alanGuncelle() ile (N ayrı yazma, atomik
  /// DEĞİL) güncelliyordu — kullanıcıya "Bu işlem geri alınamaz!"
  /// denip atomik bir işlem izlenimi veriliyordu, ama ortasında bir
  /// kesinti (uygulama çökmesi/güç kesintisi) olsaydı KISMİ güncelleme
  /// kalır, geri alınamazdı. Commit sonrası tüm güncellenen ürünler tek
  /// (parçalı) sorguyla buluta bildirilir.
  Future<List<int>> topluAlanGuncelle(
      Map<int, Map<String, dynamic>> guncellemeler) async {
    if (guncellemeler.isEmpty) return [];
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final guncellenenIds = <int>[];
    await db.transaction((txn) async {
      for (final entry in guncellemeler.entries) {
        final data = Map<String, dynamic>.from(entry.value);
        data['last_updated'] = now;
        await txn.update(DbSabitler.urunler, data,
            where: 'id = ?', whereArgs: [entry.key]);
        guncellenenIds.add(entry.key);
      }
    });
    await _topluBulutSenkronuGonder(guncellenenIds);
    return guncellenenIds;
  }

  /// Verilen id listesindeki ürünleri TEK (parçalı) SELECT ile çekip her
  /// birini buluta bildirir. 🔴 Madde 25 (N+1 sertleştirmesi, 2026-09-16):
  /// dört toplu-yazma fonksiyonu (qrMenuSecimleriniKaydet,
  /// topluFiyatGuncelle, pluSiralamaKaydet, topluFiyatUygula) aynı hatalı
  /// deseni tekrarlıyordu — "toplu yaz, sonra bulut senkronu için her
  /// kaydı tek tek tekrar oku" (N ayrı SELECT). Ürün kataloğu binlerce
  /// satır olabildiğinden bu, büyük toplu işlemlerde ciddi bir I/O
  /// yükü ve gecikme birikimiydi. SQLite'ın IN(...) değişken sayısı
  /// sınırına takılmamak için 500'lük parçalar halinde sorgulanır.
  Future<void> _topluBulutSenkronuGonder(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _d;
    const parcaBoyutu = 500;
    for (var i = 0; i < ids.length; i += parcaBoyutu) {
      final bitis = (i + parcaBoyutu < ids.length) ? i + parcaBoyutu : ids.length;
      final parca = ids.sublist(i, bitis);
      final yerTutucular = List.filled(parca.length, '?').join(',');
      final satirlar = await db.query(DbSabitler.urunler,
          where: 'id IN ($yerTutucular)', whereArgs: parca);
      for (final satir in satirlar) {
        BulutManager().upsert(DbSabitler.urunler, Map<String, dynamic>.from(satir));
      }
    }
  }

  // 🔴 MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi, devam
  // (2026-09-22): urun_ekle_ekrani_ai_ses.dart doğrudan Veritabani().db
  // üzerinden bu sorguyu çalıştırıyordu (repository katmanını
  // atlıyordu). Davranış (P2 düzeltmesiyle birlikte) birebir korunarak
  // buraya taşındı: 'M' önekli barkodlar arasında GERÇEK en yüksek
  // numarayı (sayısal CAST ile, ekleniş sırasına göre değil) bulup bir
  // sonrakini üretir.
  Future<String> benzersizBarkodUret() async {
    final db = await _d;
    final sonuc = await db.rawQuery('''
      SELECT barkod FROM ${DbSabitler.urunler}
      WHERE barkod LIKE 'M%'
        AND barkod IS NOT NULL
        AND barkod != ''
        AND is_deleted = 0
      ORDER BY CAST(SUBSTR(barkod, 2) AS INTEGER) DESC LIMIT 1
    ''');
    int yeniNumara = 1;
    if (sonuc.isNotEmpty) {
      final sonBarkod = sonuc.first['barkod'] as String;
      final numaraStr = sonBarkod.substring(1);
      yeniNumara = (int.tryParse(numaraStr) ?? 0) + 1;
    }
    return "M${yeniNumara.toString().padLeft(6, '0')}";
  }

  // 🔴 Derin analizde bulundu: stokGuncelle(id, yeniStok) burada duruyordu
  // ama projede HİÇBİR YERDEN çağrılmıyordu (ölü kod) — ve çağrılsaydı
  // TEHLİKELİYDİ: urunler.stok'u stok_hareket tablosuna hiç kayıt
  // düşmeden doğrudan değiştiriyordu. Stok, StokDeposu'nda stok_hareket
  // toplamından yeniden hesaplanan bir event-sourcing modeliyle yönetiliyor
  // (bkz. stokMutabakatYap) — bu fonksiyonla değiştirilen bir stok, bir
  // sonraki mutabakatta sessizce eski değere geri dönerdi. İleride birinin
  // bu tuzağı fark etmeden kullanmasını önlemek için tamamen kaldırıldı;
  // stok değişikliği gereken her yer StokDeposu.stokDusTxn/stokGirTxn
  // kullanmalı.

}
