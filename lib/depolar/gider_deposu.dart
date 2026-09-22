import '../servisler/bulut/bulut_manager.dart'; // sync hook
// lib/depolar/gider_deposu.dart
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../veri/database/veritabani.dart';
import '../modeller/gider_model.dart';
import '../modeller/kasa_hareket_model.dart';
import '../modeller/banka_hareket_model.dart';
import '../servisler/aktif_sube_servisi.dart';
import 'kasa_deposu.dart';
import 'banka_hareket_deposu.dart';
import 'kredi_karti_deposu.dart';

class GiderDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;
  final KasaDeposu _kasaDepo = KasaDeposu();
  final BankaHareketDeposu _bankaHareketDepo = BankaHareketDeposu();
  final KrediKartiDeposu _krediKartiDepo = KrediKartiDeposu();

  // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu depo (ve onu
  // kullanan gider_ekle_ekrani.dart) 'Nakit' ödeme yöntemiyle girilen
  // bir gideri SADECE 'giderler' tablosuna yazıyordu — kasa_hareketleri
  // HİÇ oluşturulmuyordu. KasaDeposu.gunlukOzet()/aralikOzet() SQL'i
  // ZATEN 'Gider' hareket_tipi'ni bir çıkış kalemi olarak SAYMAYA HAZIRDI
  // (bkz. o dosyadaki CASE WHEN hareket_tipi IN ('Gider',...)) — yani
  // sistem bu bağlantının var olmasını bekliyordu, ama hiçbir kod bunu
  // hiç kurmamıştı. Sonuç: nakit gider girildikçe kasa bakiyesi hiç
  // düşmüyor, gerçek kasadaki nakit ile sistemdeki bakiye kalıcı olarak
  // sapıyordu. Aşağıdaki üç fonksiyon (ekle/guncelle/sil) artık 'Nakit'
  // giderler için kasa_hareketleri kaydını da atomik olarak oluşturup
  // güncelliyor/tersine çeviriyor.
  //
  // NOT: Bu mantık BİLEREK ekleTxn()'e DEĞİL sadece ekle()'ye eklendi —
  // ekleTxn() ayrıca BorcOdemeIslemServisi.odemeYap() tarafından KENDİ
  // transaction'ı içinde çağrılıyor; o akış kasa/banka/kart hareketini
  // ZATEN kendisi oluşturuyor (gider kaydı orada sadece raporlama
  // amaçlı). ekleTxn()'e de kasa mantığı eklemek borç ödemelerinde
  // parayı İKİ KEZ kasadan düşerdi.
  Future<int> ekle(GiderModel g) async {
    try {
      final db = await _d;
      late int gid;
      int? kasaHareketId;
      int? bankaHareketId;
      int? krediHareketId;
      await db.transaction((txn) async {
        gid = await ekleTxn(txn, g);
        final aciklama = 'Gider: ${g.kategoriAdi.isNotEmpty ? g.kategoriAdi : (g.aciklama ?? '')}';
        if (g.odemeYontemi == 'Nakit') {
          kasaHareketId = await _kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
            hareketTipi: 'Gider',
            tutar: g.tutar,
            referansId: gid,
            referansTuru: 'gider',
            tarih: g.tarih,
            aciklama: aciklama,
            kullaniciId: g.kullaniciId,
          ));
        } else if (g.odemeYontemi == 'Banka' && g.bankaHesapId != null) {
          // 🔴🔴 KRİTİK DÜZELTME (paralel fork denetimi, 2026-09-22):
          // Banka ile ödenen giderler ÖNCEDEN hiçbir banka_hareketler
          // satırı oluşturmuyordu — para "kayboluyordu" (Virman/İade'de
          // daha önce bulunan AYNI hata sınıfı). Bir gider HER ZAMAN
          // parayı DIŞARI çıkarır — 'Giden'.
          bankaHareketId = await _bankaHareketDepo.ekleTxn(txn, BankaHareketModel(
            bankaHesapId: g.bankaHesapId!,
            islemTipi: 'Giden',
            tutar: g.tutar,
            aciklama: aciklama,
            tarih: g.tarih,
            referansId: gid,
            referansTuru: 'gider',
          ));
        } else if (g.odemeYontemi == 'Kredi Kartı' && g.krediKartiId != null) {
          // Gider = harcama → pozitif delta (kullanılan limit artar).
          krediHareketId = await _krediKartiDepo.limitDegistirTxn(
              txn, g.krediKartiId!, g.tutar,
              aciklama: aciklama, referansId: gid, referansTuru: 'gider');
        }
      });
      final satir = await db.query('giderler', where: 'id = ?', whereArgs: [gid], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('giderler', Map<String, dynamic>.from(satir.first));
      if (kasaHareketId != null) {
        final kasaSatir = await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [kasaHareketId], limit: 1);
        if (kasaSatir.isNotEmpty) BulutManager().upsert('kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
      }
      if (bankaHareketId != null) {
        final bankaSatir = await db.query('banka_hareketler', where: 'id = ?', whereArgs: [bankaHareketId], limit: 1);
        if (bankaSatir.isNotEmpty) BulutManager().upsert('banka_hareketler', Map<String, dynamic>.from(bankaSatir.first));
        final hesapSatir = await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [g.bankaHesapId], limit: 1);
        if (hesapSatir.isNotEmpty) BulutManager().upsert('banka_hesaplar', Map<String, dynamic>.from(hesapSatir.first));
      }
      if (krediHareketId != null) {
        final krediSatir = await db.query('kredi_karti_hareket', where: 'id = ?', whereArgs: [krediHareketId], limit: 1);
        if (krediSatir.isNotEmpty) BulutManager().upsert('kredi_karti_hareket', Map<String, dynamic>.from(krediSatir.first));
        final kartSatir = await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [g.krediKartiId], limit: 1);
        if (kartSatir.isNotEmpty) BulutManager().upsert('kredi_kartlari', Map<String, dynamic>.from(kartSatir.first));
      }
      return gid;
    } catch (e, st) {
      LogServisi().hata('Gider.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// [ekle] ile aynı mantık, VERİLEN transaction içinde çalışır.
  Future<int> ekleTxn(dynamic txn, GiderModel g) async {
    final now = DateTime.now().toIso8601String();
    final m = g.toMap();
    m.remove('id');
    // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): 'giderler'
    // tablosu global_id ile senkron sisteminde kayıtlı olduğu halde
    // (_uniqueAlan haritası) buraya HİÇ global_id atanmıyordu — her
    // yeni gider, senkron için gerekli çakışma anahtarı olmadan
    // buluta gönderiliyordu.
    m['global_id'] ??= const Uuid().v4();
    m['last_updated'] = now;
    // Kâr-Zarar raporunda giderler artık şubeye göre filtreleniyor —
    // yeni giderin de o filtrede görünmesi için boşsa aktif şubeden
    // otomatik dolduruluyor.
    m['sube_id'] ??= AktifSubeServisi().subeId;
    return await txn.insert('giderler', m);
  }

  /// Bu gidere bağlı (referans_id=giderId, referans_turu='gider'), henüz
  /// silinmemiş kasa_hareketleri satırlarının NET etkisini (giriş-çıkış)
  /// döner — yani "şu anda bu gider yüzünden kasadan gerçekten ne kadar
  /// çıkmış" tutarı. Orijinal işlem + varsa düzeltme/iptal kayıtlarının
  /// toplamı. Hiç kasa hareketi yoksa (gider hiç Nakit olmadıysa VEYA bu
  /// düzeltmeden ÖNCE eklenmiş eski bir kayıtsa) 0 döner — eski veri için
  /// var olmayan bir hareketi UYDURMAZ, sadece bundan sonraki
  /// değişikliklerde doğru tutara "yakalar".
  Future<double> _kasaNetHesapla(dynamic dbVeyaTxn, int giderId) async {
    final rows = await dbVeyaTxn.query('kasa_hareketleri',
        where: 'referans_id = ? AND referans_turu = ? AND deleted_at IS NULL',
        whereArgs: [giderId, 'gider']);
    double net = 0;
    for (final r in rows) {
      final tip = r['hareket_tipi'] as String? ?? '';
      final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
      net += KasaHareketModel.girisMi(tip) ? -tutar : tutar;
    }
    return net; // pozitif = kasadan net çıkmış tutar
  }

  /// [_kasaNetHesapla] ile AYNI mantık, banka_hareketler için — ama
  /// kasadan farklı olarak BİRDEN FAZLA hesap olabileceğinden (kasiyer
  /// bir düzenlemede bankayı değiştirebilir) HESAP BAZINDA net döner.
  /// Anahtar: banka_hesap_id, değer: o hesaptan bu gider yüzünden net
  /// çıkmış tutar (pozitif = çıkmış).
  Future<Map<int, double>> _bankaNetHesaplaTumHesaplar(
      dynamic dbVeyaTxn, int giderId) async {
    final rows = await dbVeyaTxn.query('banka_hareketler',
        where:
            "referans_id = ? AND referans_turu = 'gider' AND (is_deleted IS NULL OR is_deleted = 0)",
        whereArgs: [giderId]);
    final netler = <int, double>{};
    for (final r in rows) {
      final hesapId = r['banka_hesap_id'] as int?;
      if (hesapId == null) continue;
      final tip = r['islem_tipi'] as String? ?? '';
      final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
      netler[hesapId] = (netler[hesapId] ?? 0) + (tip == 'Giden' ? tutar : -tutar);
    }
    return netler;
  }

  /// [_bankaNetHesaplaTumHesaplar] ile AYNI mantık, kredi_karti_hareket
  /// için — kart bazında net kullanılan tutar döner.
  Future<Map<int, double>> _krediNetHesaplaTumKartlar(
      dynamic dbVeyaTxn, int giderId) async {
    final rows = await dbVeyaTxn.query('kredi_karti_hareket',
        where: "referans_id = ? AND referans_turu = 'gider' AND is_deleted = 0",
        whereArgs: [giderId]);
    final netler = <int, double>{};
    for (final r in rows) {
      final kartId = r['kredi_karti_id'] as int?;
      if (kartId == null) continue;
      final yon = r['yon'] as String? ?? '';
      final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
      netler[kartId] = (netler[kartId] ?? 0) + (yon == 'harcama' ? tutar : -tutar);
    }
    return netler;
  }

  // 🔴 DÜZELTME (derin analizde bulundu): Bu depoda hiç guncelle()
  // fonksiyonu YOKTU — kullanıcı yanlış girdiği bir gideri (tutar,
  // kategori, açıklama vb.) asla düzeltemiyordu; tek çare silip yeniden
  // eklemekti (ki bu da orijinal kaydın oluşturulma bilgisini kaybeder).
  //
  // 🔴🔴 Derin analizde AYRICA bulundu: tutar veya ödeme yöntemi
  // değiştirildiğinde kasa hiç düzeltilmiyordu (ekle()'deki aynı kök
  // sorun). Artık: bu gidere bağlı kasa hareketlerinin NET tutarı ile
  // "olması gereken" tutar (Nakit ise yeni tutar, değilse 0) arasındaki
  // FARK için tek bir telafi kaydı (Gider/Gider İptali) ekleniyor —
  // orijinal kayıtlar asla değiştirilmiyor (projenin geri kalanındaki
  // event-sourcing deseniyle tutarlı).
  Future<void> guncelle(GiderModel g) async {
    try {
      if (g.id == null) throw Exception('guncelle() için id gerekli');
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final m = g.toMap();
      m.remove('id');
      m.remove('global_id'); // global_id oluşturulduktan sonra değişmez
      m['last_updated'] = now;
      final duzeltmeAciklamasi =
          'Gider düzeltmesi: ${g.kategoriAdi.isNotEmpty ? g.kategoriAdi : (g.aciklama ?? '')}';
      int? kasaHareketId;
      final bankaHareketIdleri = <int>[];
      final krediHareketIdleri = <int>[];
      await db.transaction((txn) async {
        await txn.update('giderler', m, where: 'id = ?', whereArgs: [g.id]);

        // Kasa (Nakit)
        final mevcutKasaNet = await _kasaNetHesapla(txn, g.id!);
        final hedefKasaNet = g.odemeYontemi == 'Nakit' ? g.tutar : 0.0;
        final kasaFark = hedefKasaNet - mevcutKasaNet;
        if (kasaFark.abs() > 0.005) {
          kasaHareketId = await _kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
            hareketTipi: kasaFark > 0 ? 'Gider' : 'Gider İptali',
            tutar: kasaFark.abs(),
            referansId: g.id,
            referansTuru: 'gider',
            tarih: DateTime.now(),
            aciklama: duzeltmeAciklamasi,
            kullaniciId: g.kullaniciId,
          ));
        }

        // Banka — hesap DEĞİŞTİRİLMİŞ olabilir (eski hesap sıfırlanır,
        // yeni hesaba hedef tutar yazılır), HESAP BAZINDA uzlaştırılır.
        final bankaNetler = await _bankaNetHesaplaTumHesaplar(txn, g.id!);
        final bankaHedefler = <int, double>{
          if (g.odemeYontemi == 'Banka' && g.bankaHesapId != null)
            g.bankaHesapId!: g.tutar,
        };
        final etkilenenHesaplar = {...bankaNetler.keys, ...bankaHedefler.keys};
        for (final hesapId in etkilenenHesaplar) {
          final mevcut = bankaNetler[hesapId] ?? 0;
          final hedef = bankaHedefler[hesapId] ?? 0;
          final fark = hedef - mevcut;
          if (fark.abs() > 0.005) {
            final id = await _bankaHareketDepo.ekleTxn(txn, BankaHareketModel(
              bankaHesapId: hesapId,
              islemTipi: fark > 0 ? 'Giden' : 'Gelen',
              tutar: fark.abs(),
              aciklama: duzeltmeAciklamasi,
              tarih: DateTime.now(),
              referansId: g.id,
              referansTuru: 'gider',
            ));
            bankaHareketIdleri.add(id);
          }
        }

        // Kredi Kartı — kart DEĞİŞTİRİLMİŞ olabilir, KART BAZINDA
        // uzlaştırılır (banka bloğuyla AYNI desen).
        final krediNetler = await _krediNetHesaplaTumKartlar(txn, g.id!);
        final krediHedefler = <int, double>{
          if (g.odemeYontemi == 'Kredi Kartı' && g.krediKartiId != null)
            g.krediKartiId!: g.tutar,
        };
        final etkilenenKartlar = {...krediNetler.keys, ...krediHedefler.keys};
        for (final kartId in etkilenenKartlar) {
          final mevcut = krediNetler[kartId] ?? 0;
          final hedef = krediHedefler[kartId] ?? 0;
          final fark = hedef - mevcut;
          if (fark.abs() > 0.005) {
            final id = await _krediKartiDepo.limitDegistirTxn(
                txn, kartId, fark,
                aciklama: duzeltmeAciklamasi, referansId: g.id, referansTuru: 'gider');
            if (id != null) krediHareketIdleri.add(id);
          }
        }
      });
      final satir = await db.query('giderler', where: 'id = ?', whereArgs: [g.id], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('giderler', Map<String, dynamic>.from(satir.first));
      if (kasaHareketId != null) {
        final kasaSatir = await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [kasaHareketId], limit: 1);
        if (kasaSatir.isNotEmpty) BulutManager().upsert('kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
      }
      for (final id in bankaHareketIdleri) {
        final s = await db.query('banka_hareketler', where: 'id = ?', whereArgs: [id], limit: 1);
        if (s.isNotEmpty) BulutManager().upsert('banka_hareketler', Map<String, dynamic>.from(s.first));
      }
      for (final id in krediHareketIdleri) {
        final s = await db.query('kredi_karti_hareket', where: 'id = ?', whereArgs: [id], limit: 1);
        if (s.isNotEmpty) BulutManager().upsert('kredi_karti_hareket', Map<String, dynamic>.from(s.first));
      }
    } catch (e, st) {
      LogServisi().hata('Gider.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sil(int id) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      int? kasaHareketId;
      final bankaHareketIdleri = <int>[];
      final krediHareketIdleri = <int>[];
      await db.transaction((txn) async {
        // 🔴 DÜZELTME: Gerçek HARD DELETE yapılıyordu — tabloda zaten
        // 'deleted_at' sütunu vardı ama hiç kullanılmıyordu. Hard delete,
        // silmenin buluta hiç bildirilememesine ve bulut→yerel çekişte
        // silinen giderin "dirilmesine" yol açıyordu.
        await txn.update('giderler', {'deleted_at': now, 'last_updated': now},
            where: 'id = ?', whereArgs: [id]);
        // 🔴 Derin analizde bulundu: bu gidere bağlı bir kasa hareketi
        // (bkz. ekle()/guncelle()'deki düzeltme) varsa, gider silinince
        // o hareket hiç tersine çevrilmiyordu — kasadan çıkmış para
        // kayıtlarda "çıkmış" olarak kalıp gerçek kasa bakiyesinden
        // kalıcı olarak sapıyordu.
        final mevcutNet = await _kasaNetHesapla(txn, id);
        if (mevcutNet.abs() > 0.005) {
          kasaHareketId = await _kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
            hareketTipi: mevcutNet > 0 ? 'Gider İptali' : 'Gider',
            tutar: mevcutNet.abs(),
            referansId: id,
            referansTuru: 'gider',
            tarih: DateTime.now(),
            aciklama: 'Gider silindi (kasa düzeltmesi)',
          ));
        }

        // Banka/Kredi Kartı — AYNI koruma (paralel fork denetimi,
        // 2026-09-22): bu gidere bağlı gerçek banka/kart hareketi varsa,
        // silinince tersine çevrilmezse kalıcı sapma oluşurdu.
        final bankaNetler = await _bankaNetHesaplaTumHesaplar(txn, id);
        for (final entry in bankaNetler.entries) {
          if (entry.value.abs() <= 0.005) continue;
          final hareketId = await _bankaHareketDepo.ekleTxn(txn, BankaHareketModel(
            bankaHesapId: entry.key,
            islemTipi: entry.value > 0 ? 'Gelen' : 'Giden',
            tutar: entry.value.abs(),
            aciklama: 'Gider silindi (banka düzeltmesi)',
            tarih: DateTime.now(),
            referansId: id,
            referansTuru: 'gider',
          ));
          bankaHareketIdleri.add(hareketId);
        }
        final krediNetler = await _krediNetHesaplaTumKartlar(txn, id);
        for (final entry in krediNetler.entries) {
          if (entry.value.abs() <= 0.005) continue;
          final hareketId = await _krediKartiDepo.limitDegistirTxn(
              txn, entry.key, -entry.value,
              aciklama: 'Gider silindi (kart düzeltmesi)',
              referansId: id, referansTuru: 'gider');
          if (hareketId != null) krediHareketIdleri.add(hareketId);
        }
      });
      final satir = await db.query('giderler', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('giderler', Map<String, dynamic>.from(satir.first));
      if (kasaHareketId != null) {
        final kasaSatir = await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [kasaHareketId], limit: 1);
        if (kasaSatir.isNotEmpty) BulutManager().upsert('kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
      }
      for (final hid in bankaHareketIdleri) {
        final s = await db.query('banka_hareketler', where: 'id = ?', whereArgs: [hid], limit: 1);
        if (s.isNotEmpty) BulutManager().upsert('banka_hareketler', Map<String, dynamic>.from(s.first));
      }
      for (final hid in krediHareketIdleri) {
        final s = await db.query('kredi_karti_hareket', where: 'id = ?', whereArgs: [hid], limit: 1);
        if (s.isNotEmpty) BulutManager().upsert('kredi_karti_hareket', Map<String, dynamic>.from(s.first));
      }
    } catch (e, st) {
      LogServisi().hata('Gider.sil', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<GiderModel>> tumunuGetir({int limit = 200}) async {
    final db = await _d;
    final rows = await db.query(
      'giderler', where: 'deleted_at IS NULL', orderBy: 'tarih DESC', limit: limit);
    return rows.map(GiderModel.fromMap).toList();
  }

  Future<List<GiderModel>> tariheGoreGetir(DateTime bas, DateTime bit) async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        'SELECT g.*, k.ad as kategori_adi FROM giderler g '
        'LEFT JOIN gider_kategoriler k ON g.kategori_id = k.id '
        'WHERE datetime(g.tarih) BETWEEN datetime(?) AND datetime(?) AND g.deleted_at IS NULL ORDER BY g.tarih DESC',
        [bas.toIso8601String(), bit.toIso8601String()],
      );
      return rows.map(GiderModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Gider.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<GiderModel>> bugunkunler() async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        "SELECT g.*, k.ad as kategori_adi FROM giderler g "
        "LEFT JOIN gider_kategoriler k ON g.kategori_id = k.id "
        // 🔴 KRİTİK DÜZELTME (derin analiz — gün sonu raporu / kasa özeti):
      // SQLite'ın DATE('now') fonksiyonu VARSAYILAN OLARAK UTC kullanır.
      // Ama `tarih` sütunu DateTime.now().toIso8601String() ile YEREL
      // saatle yazılıyor (satis_model.dart, gider_model.dart, kasa
      // hareketleri — hepsi aynı desen).
      //
      // Türkiye UTC+3 olduğu için, YEREL saatle 00:00–03:00 arasında
      // (yani UTC henüz bir önceki güne ait sayılırken) yapılan HER
      // satış/gider/kasa hareketi bu sorgudan DÜŞÜYORDU:
      //
      //   Yerel 01:00 (27 Tem) → tarih sütunu: '2026-07-27T01:00:00'
      //   O ANDA UTC saati     : 26 Tem 22:00 → DATE('now') = '2026-07-26'
      //   DATE(tarih)='2026-07-27' ≠ DATE('now')='2026-07-26' → KAYIP
      //
      // 24 saat açık ya da gece geç saatlere çalışan bir markette, gece
      // yarısından sonraki 3 saatlik satışlar "Gün Sonu Raporu"na hiç
      // girmiyordu. 'localtime' değiştiricisi SQLite'a cihazın kendi
      // saat dilimini kullanmasını söyler — POS cihazı zaten işletmenin
      // kendi lokasyonunda olduğu için bu doğru varsayımdır.
        "WHERE DATE(g.tarih) = DATE('now','localtime') AND g.deleted_at IS NULL ORDER BY g.tarih DESC",
      );
      return rows.map(GiderModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Gider.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> kategorileriGetir() async {
    try {
      final db = await _d;
      return await db.query('gider_kategoriler', orderBy: 'ad');
    } catch (e, st) {
      LogServisi().hata('Gider.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<double> gunlukToplamGider() async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        "SELECT SUM(tutar) as toplam FROM giderler WHERE DATE(tarih) = DATE('now','localtime') AND deleted_at IS NULL",
      );
      return (res.first['toplam'] as num?)?.toDouble() ?? 0;
    } catch (e, st) {
      LogServisi().hata('Gider.gunlukToplamGider', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<Map<String, double>> aylikKategoriDagilimi() async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        "SELECT k.ad as kategori, SUM(g.tutar) as toplam "
        "FROM giderler g LEFT JOIN gider_kategoriler k ON g.kategori_id = k.id "
        "WHERE strftime('%Y-%m', g.tarih) = strftime('%Y-%m', 'now','localtime') AND g.deleted_at IS NULL "
        "GROUP BY g.kategori_id ORDER BY toplam DESC",
      );
      return {for (final r in res) (r['kategori'] as String? ?? ''): (r['toplam'] as num?)?.toDouble() ?? 0};
    } catch (e, st) {
      LogServisi().hata('Gider.metod', hata: e, yigin: st);
      rethrow;
    }
  }


  // aralikToplamGider - gün sonu raporu için eklendi
  Future<double> aralikToplamGider(DateTime bas, DateTime bit) async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        'SELECT SUM(tutar) as toplam FROM giderler WHERE datetime(tarih) BETWEEN datetime(?) AND datetime(?) AND deleted_at IS NULL',
        [bas.toIso8601String(), bit.toIso8601String()],
      );
      return (res.first['toplam'] as num?)?.toDouble() ?? 0;
    } catch (e, st) {
      LogServisi().hata('Gider.aralikToplamGider', hata: e, yigin: st);
      rethrow;
    }
  }
}
