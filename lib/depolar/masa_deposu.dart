// lib/depolar/masa_deposu.dart
// Masa / Restoran modülü repository.
// Tek sorumluluk: masalar, masa_siparisleri, masa_siparis_kalem tablolarına erişim.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../modeller/masa_model.dart';
import '../modeller/masa_siparis_model.dart';
import '../modeller/masa_siparis_kalem_model.dart';
import '../modeller/promosyon_model.dart';
import '../modeller/urun_model.dart';
import '../servisler/urun_fiyat_hesaplayici.dart';
import 'promosyon_deposu.dart';

class MasaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Tüm açık siparişleri (tüm masalardan), kalemleriyle birlikte getirir.
  /// Mutfak/Bar ekranı bu metodu kullanır.
  Future<List<MasaSiparisModel>> tumAcikSiparisler() async {
    final db = await _d;
    final siparisler = await db.query(DbSabitler.masaSiparisleri,
        where: 'durum = ? AND is_deleted = 0', whereArgs: ['acik'],
        orderBy: 'acilis_zamani ASC');

    final kalemHaritasi = await _kalemleriTopluGetir(
        db, [for (final s in siparisler) s['id'] as int]);
    return [
      for (final s in siparisler)
        MasaSiparisModel.fromMap(s,
            kalemler: (kalemHaritasi[s['id'] as int] ?? const [])
                .map(MasaSiparisKalemModel.fromMap)
                .toList()),
    ];
  }

  /// Birden çok siparişin (silinmemiş) kalemlerini TEK sorguda getirir —
  /// önceden her sipariş/masa için ayrı sorgu atılıyordu (N+1); masa ve
  /// mutfak ekranları 5-15 sn'de bir yenilendiği için sürekli tekrarlanıyordu.
  Future<Map<int, List<Map<String, Object?>>>> _kalemleriTopluGetir(
      Database db, List<int> siparisIdleri) async {
    final harita = <int, List<Map<String, Object?>>>{};
    if (siparisIdleri.isEmpty) return harita;
    final yerTutucu = List.filled(siparisIdleri.length, '?').join(',');
    final rows = await db.rawQuery(
        'SELECT * FROM ${DbSabitler.masaSiparisKalem} '
        'WHERE is_deleted = 0 AND siparis_id IN ($yerTutucu) ORDER BY id ASC',
        siparisIdleri);
    for (final r in rows) {
      (harita[r['siparis_id'] as int] ??= []).add(r);
    }
    return harita;
  }

  /// Masa adını id ile getirir (mutfak ekranında gösterim için).
  Future<Map<int, String>> masaAdlariHaritasi() async {
    final db = await _d;
    final rows = await db.query(DbSabitler.masalar, columns: ['id', 'ad']);
    return {for (final r in rows) r['id'] as int: r['ad'] as String};
  }

  // ── Masalar ──────────────────────────────────────────────────────────────

  /// Tüm masaları, varsa açık siparişlerinin toplamı/zamanı ile birlikte getirir.
  Future<List<MasaModel>> masalariGetir() async {
    final db = await _d;
    final masalar = await db.query(DbSabitler.masalar,
        where: 'is_deleted = 0', orderBy: 'sira ASC, ad ASC');

    final acikSiparisler = await db.query(DbSabitler.masaSiparisleri,
        where: 'durum = ? AND is_deleted = 0', whereArgs: ['acik']);

    final kalemHaritasi = await _kalemleriTopluGetir(
        db, [for (final s in acikSiparisler) s['id'] as int]);

    final rezervasyonlar = await _yaklasanRezervasyonlar(db);

    final sonuc = <MasaModel>[];
    for (final m in masalar) {
      final masa = MasaModel.fromMap(m);
      final siparis = acikSiparisler.where((s) => s['masa_id'] == m['id']).toList();
      if (siparis.isEmpty) {
        // Boş masa, yaklaşan/yeni başlamış bir rezervasyona sahipse "rezerve"
        // GÖSTERİLİR — durum veritabanına yazılmaz (rezervasyon iptal/geç
        // kalma durumunda eski bir 'rezerve' satırı masayı kilitli bırakırdı).
        final rez = rezervasyonlar[m['id']];
        if (masa.durum == 'bos' && rez != null) {
          sonuc.add(masa.copyWith(durum: 'rezerve', aktifOzet: rez));
        } else {
          sonuc.add(masa);
        }
        continue;
      }

      final s = siparis.first;
      final kalemler = kalemHaritasi[s['id'] as int] ?? const <Map<String, Object?>>[];
      final toplam = kalemler.fold<double>(0.0, (acc, k) =>
          acc + (k['miktar'] as num).toDouble() * (k['birim_fiyat'] as num).toDouble());

      String? ozet;
      if (kalemler.isNotEmpty) {
        final adlar = kalemler.map((k) => k['urun_adi'] as String).toList();
        ozet = adlar.length <= 2
            ? adlar.join(', ')
            : '${adlar.take(2).join(', ')} +${adlar.length - 2}';
      }

      sonuc.add(masa.copyWith(
        // Kalemi olan masa 'bos' satırıyla (senkron/eski kayıt) gelirse bile
        // dolu gösterilir.
        durum: masa.durum == 'bos' && kalemler.isNotEmpty ? 'dolu' : null,
        aktifSiparisId: s['id'] as int,
        aktifToplam: toplam,
        aktifOzet: ozet,
        acilisZamani: DateTime.tryParse(s['acilis_zamani']?.toString() ?? ''),
      ));
    }
    return sonuc;
  }

  /// Rezervasyon saatine [rezervasyonOncesi] kala masa "rezerve" görünür;
  /// misafir [rezervasyonGecikme] süresi içinde gelmezse görünüm kalkar.
  static const rezervasyonOncesi = Duration(minutes: 60);
  static const rezervasyonGecikme = Duration(minutes: 30);

  /// masa_id → "19:30 Ahmet Yılmaz" özeti (iptal/tamamlanan/geldi hariç).
  Future<Map<int, String>> _yaklasanRezervasyonlar(Database db) async {
    final simdi = DateTime.now();
    final rows = await db.query(DbSabitler.masaRezervasyon,
        columns: ['masa_id', 'saat', 'musteri_adi'],
        where: "is_deleted = 0 AND durum IN ('beklemede', 'onaylandi')");
    final sonuc = <int, ({DateTime saat, String ozet})>{};
    for (final r in rows) {
      final saat = DateTime.tryParse(r['saat']?.toString() ?? '');
      final masaId = r['masa_id'] as int?;
      if (saat == null || masaId == null) continue;
      if (saat.isAfter(simdi.add(rezervasyonOncesi)) ||
          saat.isBefore(simdi.subtract(rezervasyonGecikme))) {
        continue;
      }
      final onceki = sonuc[masaId];
      if (onceki != null && onceki.saat.isBefore(saat)) continue;
      final hh = saat.hour.toString().padLeft(2, '0');
      final mm = saat.minute.toString().padLeft(2, '0');
      sonuc[masaId] = (saat: saat, ozet: '$hh:$mm ${r['musteri_adi'] ?? ''}'.trim());
    }
    return {for (final e in sonuc.entries) e.key: e.value.ozet};
  }

  /// Aynı adlı (büyük/küçük harf ve baştaki/sondaki boşluk duyarsız) aktif
  /// masa var mı? [haricId] düzenlenen masanın kendisini saymamak için.
  Future<bool> adKullanimda(String ad, {int? haricId}) async {
    final db = await _d;
    final rows = await db.query(DbSabitler.masalar,
        columns: ['id', 'ad'], where: 'is_deleted = 0');
    final aranan = ad.trim().toLowerCase();
    return rows.any((r) =>
        r['id'] != haricId &&
        ((r['ad'] as String?) ?? '').trim().toLowerCase() == aranan);
  }

  /// Düzenleme diyaloğu için: YALNIZCA ad/kategori/kapasite yazılır.
  /// Önceden [masaGuncelle] ile tüm satır (durum dahil) ekrandaki eski
  /// kopyadan yazılıyordu — diyalog açıkken başka bir cihaz masayı açarsa
  /// kaydet masayı "boş"a geri çeviriyordu (açık siparişli ama boş masa).
  Future<void> masaBilgiGuncelle(int id,
      {required String ad, required String kategori, required int kapasite}) async {
    final temiz = ad.trim();
    if (temiz.isEmpty) throw Exception('Masa adı boş olamaz.');
    if (await adKullanimda(temiz, haricId: id)) {
      throw Exception('"$temiz" adında bir masa zaten var.');
    }
    await _yaz((txn, k) async {
      await txn.update(
          DbSabitler.masalar,
          {
            'ad': temiz,
            'kategori': kategori,
            'kapasite': kapasite,
            'last_updated': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id]);
      k.masa(id);
    });
  }

  Future<int> masaEkle(MasaModel masa) async {
    if (masa.ad.trim().isEmpty) throw Exception('Masa adı boş olamaz.');
    if (await adKullanimda(masa.ad)) {
      throw Exception('"${masa.ad.trim()}" adında bir masa zaten var.');
    }
    final m = masa.toMap();
    m['global_id'] = const Uuid().v4();
    m['last_updated'] = DateTime.now().toIso8601String();
    return _yaz((txn, k) async {
      final id = await txn.insert(DbSabitler.masalar, m);
      k.masa(id);
      return id;
    });
  }

  /// [onek] ile başlayan masaların (örn. "Salon 7") en yüksek numarasının
  /// bir fazlasını döner; hiç yoksa 1.
  Future<int> sonrakiNo(String onek) async {
    final db = await _d;
    final rows = await db.query(DbSabitler.masalar,
        columns: ['ad'], where: 'is_deleted = 0');
    final desen = RegExp('^${RegExp.escape(onek.trim())}\s+(\d+)\$',
        caseSensitive: false);
    var enBuyuk = 0;
    for (final r in rows) {
      final m = desen.firstMatch((r['ad'] as String? ?? '').trim());
      final n = m == null ? null : int.tryParse(m.group(1)!);
      if (n != null && n > enBuyuk) enBuyuk = n;
    }
    return enBuyuk + 1;
  }

  /// "10 masa ekle" gibi toplu masa oluşturma — her biri kalıcı, ayrı bir
  /// satır olarak `masalar` tablosuna yazılır (sabit kalırlar).
  /// Örn: onek='Salon', adet=10, baslangic=1 → "Salon 1".."Salon 10"
  Future<void> topluMasaEkle({
    required String onek,
    required int adet,
    required String kategori,
    int kapasite = 4,
    int baslangic = 1,
  }) async {
    // Aynı önekle mevcut masa numaralarını çakıştırma: Salon 1..10 varken
    // "Başlangıç 1" girilse bile 11'den devam eder.
    baslangic = baslangic > await sonrakiNo(onek)
        ? baslangic
        : await sonrakiNo(onek);
    await _yaz((txn, k) async {
      // Mevcut en yüksek sira değerinden devam et — sıralama bozulmasın
      final maxSira = await txn.rawQuery('SELECT MAX(sira) as m FROM ${DbSabitler.masalar}');
      int sira = (maxSira.first['m'] as int?) ?? 0;
      for (var i = 0; i < adet; i++) {
        sira++;
        final id = await txn.insert(DbSabitler.masalar, {
          'global_id': const Uuid().v4(),
          'ad': '$onek ${baslangic + i}',
          'kategori': kategori,
          'kapasite': kapasite,
          'durum': 'bos',
          'sira': sira,
          'last_updated': DateTime.now().toIso8601String(),
        });
        k.masa(id);
      }
    });
  }

  Future<void> masaGuncelle(MasaModel masa) async {
    await _yaz((txn, k) async {
      await txn.update(DbSabitler.masalar, masa.toMap(),
          where: 'id = ?', whereArgs: [masa.id]);
      k.masa(masa.id!);
    });
  }

  Future<void> masaSil(int id) async {
    await _yaz((txn, k) async {
      // Açık siparişi varsa silmeye izin verme (kontrol + silme aynı txn)
      final acik = await txn.query(DbSabitler.masaSiparisleri,
          where: 'masa_id = ? AND durum = ? AND is_deleted = 0', whereArgs: [id, 'acik']);
      if (acik.isNotEmpty) {
        throw Exception('Bu masada açık bir hesap var, önce kapatın.');
      }
      await txn.update(DbSabitler.masalar,
          {'is_deleted': 1, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [id]);
      k.masa(id);
    });
  }

  Future<void> masaDurumGuncelle(int id, String durum) async {
    await _yaz((txn, k) => _masaDurumTxn(txn, k, id, durum));
  }

  Future<void> _masaDurumTxn(
      Transaction txn, _Kuyruk k, int id, String durum) async {
    await txn.update(DbSabitler.masalar,
        {'durum': durum, 'last_updated': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
    k.masa(id);
  }

  // ── Atomik yazma altyapısı ──────────────────────────────────────────────

  /// Tüm yazmalar TEK transaction'da yapılır ve değişen satırların senkron
  /// kuyruğu kaydı (sync_queue) AYNI transaction'da diske yazılır: commit
  /// ile kuyruk kaydı birlikte var olur ya da birlikte hiç olmaz. Önceden
  /// `BulutManager().upsert()` commit'ten sonra RAM kuyruğuna ekleniyordu —
  /// arada uygulama kapanırsa masa/sipariş değişikliği buluta hiç gitmiyordu.
  /// Ağ gönderimi transaction dışında (`zorlaGonder`) tetiklenir.
  Future<T> _yaz<T>(Future<T> Function(Transaction txn, _Kuyruk k) islem) async {
    final db = await _d;
    final sonuc = await db.transaction((txn) async {
      final k = _Kuyruk();
      final r = await islem(txn, k);
      await k.yaz(txn);
      return r;
    });
    BulutManager().zorlaGonder();
    return sonuc;
  }

  // ── Siparişler ───────────────────────────────────────────────────────────

  /// Masanın açık siparişini (varsa kalemleriyle) getirir.
  Future<MasaSiparisModel?> acikSiparisGetir(int masaId) async {
    final db = await _d;
    final rows = await db.query(DbSabitler.masaSiparisleri,
        where: 'masa_id = ? AND durum = ? AND is_deleted = 0',
        whereArgs: [masaId, 'acik'], limit: 1);
    if (rows.isEmpty) return null;

    final kalemRows = await db.query(DbSabitler.masaSiparisKalem,
        where: 'siparis_id = ? AND is_deleted = 0',
        whereArgs: [rows.first['id']], orderBy: 'id ASC');
    final kalemler = kalemRows.map(MasaSiparisKalemModel.fromMap).toList();
    return MasaSiparisModel.fromMap(rows.first, kalemler: kalemler);
  }

  /// Masada açık sipariş yoksa yeni bir sipariş açar, varsa onu döner.
  Future<MasaSiparisModel> siparisAcVeyaGetir(int masaId) async {
    final simdi = DateTime.now();
    final gid = const Uuid().v4();
    // Kontrol + ekleme + masa durumu TEK transaction: iki dokunuş/cihaz
    // aynı anda "ilk ürünü ekle" derse aynı masada iki açık sipariş
    // oluşuyordu (biri ekranda kayboluyor, kalemleri ödenmiyordu).
    var mevcutVar = false;
    late int yeniId;
    await _yaz((txn, k) async {
      final acik = await txn.query(DbSabitler.masaSiparisleri,
          columns: ['id'],
          where: 'masa_id = ? AND durum = ? AND is_deleted = 0',
          whereArgs: [masaId, 'acik'], limit: 1);
      if (acik.isNotEmpty) {
        mevcutVar = true;
        // Son kalem silinince masa 'bos' olur ama sipariş açık kalır; aynı
        // siparişe tekrar ürün eklenecekse masa yeniden 'dolu' olmalı —
        // yoksa ürünlü masa listede boş görünüyordu.
        final masa = await txn.query(DbSabitler.masalar,
            columns: ['durum'], where: 'id = ?', whereArgs: [masaId], limit: 1);
        if (masa.isNotEmpty && masa.first['durum'] == 'bos') {
          await _masaDurumTxn(txn, k, masaId, 'dolu');
        }
        return;
      }
      yeniId = await txn.insert(DbSabitler.masaSiparisleri, {
        'global_id': gid,
        'masa_id': masaId,
        'durum': 'acik',
        'acilis_zamani': simdi.toIso8601String(),
        'toplam_tutar': 0,
        'last_updated': simdi.toIso8601String(),
      });
      k.siparis(yeniId);
      await _masaDurumTxn(txn, k, masaId, 'dolu');
    });
    if (mevcutVar) {
      final mevcut = await acikSiparisGetir(masaId);
      if (mevcut != null) return mevcut;
    }
    return MasaSiparisModel(id: yeniId, masaId: masaId, acilisZamani: simdi);
  }

  /// Açık siparişe ürün ekler. Aynı ürün+not zaten varsa miktarı artırır.
  /// Kalem + sipariş toplamı + kuyruk kaydı tek transaction'da yazılır.
  Future<void> kalemEkle(int siparisId, {
    required int urunId, required String urunAdi,
    required double birimFiyat, required double kdvOran,
    double miktar = 1, String? not_,
  }) async {
    // Çağıran ürünün LİSTE fiyatını verdiyse (normal akış) promosyon/indirim
    // Hızlı Satış'taki kuralla uygulanır; farklı (elle verilmiş) bir fiyat
    // geldiyse aynen korunur.
    final fiyatci = await _fiyatciGetir(urunId, birimFiyat);
    await _yaz((txn, k) async {
      final mevcut = await txn.query(DbSabitler.masaSiparisKalem,
          where: 'siparis_id = ? AND urun_id = ? AND is_deleted = 0 AND durum = ?'
              '${not_ == null ? ' AND (not_ IS NULL)' : ' AND not_ = ?'}',
          whereArgs: not_ == null ? [siparisId, urunId, 'beklemede'] : [siparisId, urunId, 'beklemede', not_]);

      if (mevcut.isNotEmpty) {
        final mevcutMiktar = (mevcut.first['miktar'] as num).toDouble();
        final kalemId = mevcut.first['id'] as int;
        final yeniMiktar = mevcutMiktar + miktar;
        await txn.update(DbSabitler.masaSiparisKalem,
            {
              'miktar': yeniMiktar,
              // Miktar eşikli promosyonlar için fiyat yeni miktara göre tazelenir.
              if (fiyatci != null) 'birim_fiyat': fiyatci(yeniMiktar),
              'last_updated': DateTime.now().toIso8601String(),
            },
            where: 'id = ?', whereArgs: [kalemId]);
        k.kalem(kalemId);
      } else {
        final kalemId = await txn.insert(DbSabitler.masaSiparisKalem, {
          'global_id': const Uuid().v4(),
          'siparis_id': siparisId,
          'urun_id': urunId,
          'urun_adi': urunAdi,
          'miktar': miktar,
          'birim_fiyat': fiyatci != null ? fiyatci(miktar) : birimFiyat,
          'kdv_oran': kdvOran,
          'not_': not_,
          'durum': 'beklemede',
          'eklenme_zamani': DateTime.now().toIso8601String(),
          'last_updated': DateTime.now().toIso8601String(),
        });
        k.kalem(kalemId);
      }
      await _toplamGuncelleTxn(txn, k, siparisId);
    });
  }

  Future<void> kalemMiktarGuncelle(int kalemId, double miktar) async {
    // Kalem otomatik fiyatlıysa (liste/promosyon fiyatı) yeni miktara göre
    // yeniden hesaplanır; elle değiştirilmiş fiyatlara dokunulmaz.
    final onKalem = await (await _d).query(DbSabitler.masaSiparisKalem,
        columns: ['urun_id', 'birim_fiyat', 'miktar'],
        where: 'id = ?', whereArgs: [kalemId], limit: 1);
    _OtoFiyat? oto;
    if (onKalem.isNotEmpty && miktar > 0) {
      oto = await _otoFiyatGetir(onKalem.first['urun_id'] as int?);
    }
    await _yaz((txn, k) async {
      final rows = await txn.query(DbSabitler.masaSiparisKalem,
          where: 'id = ?', whereArgs: [kalemId], limit: 1);
      if (rows.isEmpty) return;
      final siparisId = rows.first['siparis_id'] as int;

      if (miktar <= 0) {
        await txn.update(DbSabitler.masaSiparisKalem,
            {'is_deleted': 1, 'last_updated': DateTime.now().toIso8601String()},
            where: 'id = ?', whereArgs: [kalemId]);
      } else {
        final eskiFiyat = (rows.first['birim_fiyat'] as num).toDouble();
        final eskiMiktar = (rows.first['miktar'] as num).toDouble();
        double? yeniFiyat;
        if (oto != null && (eskiFiyat - oto.hesapla(eskiMiktar)).abs() < 0.005) {
          yeniFiyat = oto.hesapla(miktar);
        }
        await txn.update(DbSabitler.masaSiparisKalem,
            {
              'miktar': miktar,
              if (yeniFiyat != null) 'birim_fiyat': yeniFiyat,
              'last_updated': DateTime.now().toIso8601String(),
            },
            where: 'id = ?', whereArgs: [kalemId]);
      }
      k.kalem(kalemId);
      await _toplamGuncelleTxn(txn, k, siparisId);
      // Miktar 0'a düşürülerek kalem silindiğinde de masa 'dolu' kalmasın.
      if (miktar <= 0) await _siparisBossaMasayiBosalt(txn, k, siparisId);
    });
  }

  /// Ürün + geçerli promosyonları bir kez yükler; miktara göre otomatik
  /// birim fiyat hesaplayan nesneyi döner (ürün bulunamazsa null).
  Future<_OtoFiyat?> _otoFiyatGetir(int? urunId) async {
    if (urunId == null) return null;
    try {
      final db = await _d;
      final rows = await db.query(DbSabitler.urunler,
          where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (rows.isEmpty) return null;
      final promolar = await PromosyonDeposu().urunPromosyonlari(urunId);
      return _OtoFiyat(UrunModel.fromMap(rows.first), promolar);
    } catch (_) {
      return null; // fiyat hesaplanamazsa ham fiyatla devam
    }
  }

  /// [kalemEkle] için: çağıranın verdiği fiyat ürünün liste fiyatıyla aynıysa
  /// miktara göre hesaplayan fonksiyon, aksi halde (elle fiyat) null.
  Future<double Function(double)?> _fiyatciGetir(int urunId, double verilenFiyat) async {
    final oto = await _otoFiyatGetir(urunId);
    if (oto == null || (oto.urun.satisFiyati - verilenFiyat).abs() > 0.005) return null;
    return oto.hesapla;
  }

  Future<void> kalemDurumGuncelle(int kalemId, String durum) async {
    await _yaz((txn, k) async {
      await txn.update(DbSabitler.masaSiparisKalem,
          {'durum': durum, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [kalemId]);
      k.kalem(kalemId);
    });
  }

  Future<void> kalemNotGuncelle(int kalemId, String? not_) async {
    await _yaz((txn, k) async {
      await txn.update(DbSabitler.masaSiparisKalem,
          {'not_': not_, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [kalemId]);
      k.kalem(kalemId);
    });
  }

  Future<void> kalemSil(int kalemId) async {
    await _yaz((txn, k) async {
      final rows = await txn.query(DbSabitler.masaSiparisKalem,
          where: 'id = ?', whereArgs: [kalemId], limit: 1);
      if (rows.isEmpty) return;
      final siparisId = rows.first['siparis_id'] as int;
      await txn.update(DbSabitler.masaSiparisKalem,
          {'is_deleted': 1, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [kalemId]);
      k.kalem(kalemId);
      await _toplamGuncelleTxn(txn, k, siparisId);
      // Siparişte hiç (silinmemiş) kalem kalmadıysa masa 'bos'a çekilir
      // ("masada ürün ekledim, sildim, masa hâlâ dolu" hatası).
      await _siparisBossaMasayiBosalt(txn, k, siparisId);
    });
  }

  Future<void> _siparisBossaMasayiBosalt(
      Transaction txn, _Kuyruk k, int siparisId) async {
    final kalan = await txn.query(DbSabitler.masaSiparisKalem,
        where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [siparisId], limit: 1);
    if (kalan.isNotEmpty) return;
    final siparis = await txn.query(DbSabitler.masaSiparisleri,
        columns: ['masa_id'], where: 'id = ?', whereArgs: [siparisId], limit: 1);
    if (siparis.isNotEmpty) {
      await _masaDurumTxn(txn, k, siparis.first['masa_id'] as int, 'bos');
    }
  }

  /// Kullanıcı isteği: "3+ terminal, hepsi çakışabilir, hatasız olsun" —
  /// birden fazla personel AYNI masaya farklı cihazlardan sipariş
  /// eklerse, her yeni ürün kendi global_id'siyle ayrı bir satır olduğu
  /// için düzgün birleşiyor. AMA sipariş toplamı (`toplam_tutar`)
  /// SADECE yerel bir değişiklik olduğunda yeniden hesaplanıyordu —
  /// senkronizasyon sonrası, başka bir cihazdan gelen kalemler eklenince
  /// toplam OTOMATİK güncellenmiyordu. Bu fonksiyon, tıpkı stok
  /// mutabakatı gibi, TÜM aktif siparişlerin toplamını kalemlerinin
  /// gerçek toplamından yeniden hesaplar — senkronizasyon sonrası
  /// çağrılması önerilir.
  Future<int> siparisToplamlariMutabakatYap() async {
    try {
      // 'odendi' ve 'iptal' kapanmış sayılır (gerçek kapanış durumu 'odendi').
      return await _yaz((txn, k) async {
        final siparisler = await txn.query(DbSabitler.masaSiparisleri,
            where: "durum != 'odendi' AND durum != 'iptal'",
            columns: ['id', 'toplam_tutar']);
        var duzeltilen = 0;
        for (final s in siparisler) {
          final siparisId = s['id'] as int;
          final eskiToplam = (s['toplam_tutar'] as num?)?.toDouble() ?? 0;
          final dogruToplam = await _kalemToplamiTxn(txn, siparisId);
          if ((eskiToplam - dogruToplam).abs() > 0.01) {
            await txn.update(DbSabitler.masaSiparisleri,
                {'toplam_tutar': dogruToplam, 'last_updated': DateTime.now().toIso8601String()},
                where: 'id = ?', whereArgs: [siparisId]);
            k.siparis(siparisId);
            duzeltilen++;
          }
        }
        if (duzeltilen > 0) {
          LogServisi().bilgi('Masa siparişi mutabakatı: $duzeltilen sipariş düzeltildi');
        }
        return duzeltilen;
      });
    } catch (e, st) {
      LogServisi().hata('Masa.siparisToplamlariMutabakatYap', hata: e, yigin: st);
      return 0;
    }
  }

  Future<double> _kalemToplamiTxn(Transaction txn, int siparisId) async {
    final kalemler = await txn.query(DbSabitler.masaSiparisKalem,
        where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [siparisId]);
    return kalemler.fold<double>(0.0, (acc, k) =>
        acc + (k['miktar'] as num).toDouble() * (k['birim_fiyat'] as num).toDouble());
  }

  Future<void> _toplamGuncelleTxn(
      Transaction txn, _Kuyruk k, int siparisId) async {
    final toplam = await _kalemToplamiTxn(txn, siparisId);
    await txn.update(DbSabitler.masaSiparisleri,
        {'toplam_tutar': toplam, 'last_updated': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [siparisId]);
    k.siparis(siparisId);
  }

  /// Müşteri (cari) bağla — fatura/cari ödeme için.
  Future<void> musteriBagla(int siparisId, int? cariId, String? cariAdi) async {
    await _yaz((txn, k) async {
      await txn.update(DbSabitler.masaSiparisleri,
          {'cari_id': cariId, 'cari_adi': cariAdi, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [siparisId]);
      k.siparis(siparisId);
    });
  }

  /// "Hesap istensin" — garson çağırma / ödeme bekleniyor durumu.
  Future<void> hesapIstendi(int masaId) async {
    await masaDurumGuncelle(masaId, 'hesap_istendi');
  }

  /// Siparişi ödenmiş olarak kapatır, masayı boşa çevirir (tek transaction).
  Future<void> siparisKapat(int siparisId, int masaId, {int? satisId}) async {
    await _yaz((txn, k) async {
      await txn.update(DbSabitler.masaSiparisleri, {
        'durum': 'odendi',
        'kapanis_zamani': DateTime.now().toIso8601String(),
        'satis_id': satisId,
        'last_updated': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [siparisId]);
      k.siparis(siparisId);
      await _masaDurumTxn(txn, k, masaId, 'bos');
    });
  }

  /// Açık siparişi tamamen iptal eder (yanlış açılan masa için).
  Future<void> siparisIptal(int siparisId, int masaId) async {
    await _yaz((txn, k) async {
      await txn.update(DbSabitler.masaSiparisleri, {
        'durum': 'iptal',
        'kapanis_zamani': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [siparisId]);
      k.siparis(siparisId);
      await _masaDurumTxn(txn, k, masaId, 'bos');
    });
  }

  /// Bir masadaki kalemleri başka bir masaya taşır — "Masa Taşı / Birleştir".
  /// Hedef masa boşsa yeni sipariş açılır (taşıma); doluysa kalemler onun
  /// açık siparişine eklenir (birleştirme).
  ///
  /// 🔴 DÜZELTME (2026-09-28): önceden 5 ayrı adımdı (hedef sipariş açma,
  /// kalem taşıma, toplam, kaynak iptal, masa durumları) — arada uygulama
  /// kapanır/hata olursa kalemler hedefe geçmiş ama kaynak sipariş açık
  /// kalabiliyor ya da hedef masa "dolu" ama siparişsiz kalıyordu. Artık TEK
  /// transaction: ya hepsi olur ya hiçbiri. Ayrıca: kaynak = hedef masa
  /// seçilirse sipariş kendini iptal edip kayboluyordu (engellendi); masaya
  /// bağlı müşteri (cari) yeni masaya taşınmıyordu (taşınıyor; hedefin kendi
  /// müşterisi varsa o korunur); silinmiş kalemler de taşınıyordu (artık hayır).
  /// Kuyruk kaydı aynı transaction'da yazılır, ağ gönderimi commit'ten sonra.
  Future<void> masaTasi(int kaynakSiparisId, int hedefMasaId) async {
    late int hedefSiparisId;
    late int kaynakMasaId;

    await _yaz((txn, k) async {
      final simdi = DateTime.now().toIso8601String();
      final kaynakRows = await txn.query(DbSabitler.masaSiparisleri,
          where: 'id = ? AND durum = ? AND is_deleted = 0',
          whereArgs: [kaynakSiparisId, 'acik'], limit: 1);
      if (kaynakRows.isEmpty) {
        throw Exception('Taşınacak açık sipariş bulunamadı (başka bir cihazda kapatılmış olabilir).');
      }
      final kaynak = kaynakRows.first;
      kaynakMasaId = kaynak['masa_id'] as int;
      if (kaynakMasaId == hedefMasaId) {
        throw Exception('Hedef masa, sipariş zaten bu masada.');
      }

      final hedefRows = await txn.query(DbSabitler.masaSiparisleri,
          where: 'masa_id = ? AND durum = ? AND is_deleted = 0',
          whereArgs: [hedefMasaId, 'acik'], limit: 1);
      if (hedefRows.isNotEmpty) {
        // Birleştirme: hedefin kendi müşterisi yoksa kaynağınki geçer.
        hedefSiparisId = hedefRows.first['id'] as int;
        if (hedefRows.first['cari_id'] == null && kaynak['cari_id'] != null) {
          await txn.update(DbSabitler.masaSiparisleri,
              {'cari_id': kaynak['cari_id'], 'cari_adi': kaynak['cari_adi'], 'last_updated': simdi},
              where: 'id = ?', whereArgs: [hedefSiparisId]);
        }
      } else {
        // Taşıma: boş masada yeni sipariş — açılış zamanı, müşteri ve garson
        // kaynaktan devralınır (masa değişti, hesap aynı).
        hedefSiparisId = await txn.insert(DbSabitler.masaSiparisleri, {
          'global_id': const Uuid().v4(),
          'masa_id': hedefMasaId,
          'durum': 'acik',
          'acilis_zamani': kaynak['acilis_zamani'] ?? simdi,
          'toplam_tutar': 0,
          'cari_id': kaynak['cari_id'],
          'cari_adi': kaynak['cari_adi'],
          'garson_id': kaynak['garson_id'],
          'garson_adi': kaynak['garson_adi'],
          'last_updated': simdi,
        });
      }

      await txn.update(DbSabitler.masaSiparisKalem,
          {'siparis_id': hedefSiparisId, 'last_updated': simdi},
          where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [kaynakSiparisId]);

      final kalemler = await txn.query(DbSabitler.masaSiparisKalem,
          where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [hedefSiparisId]);
      final toplam = kalemler.fold<double>(0.0, (acc, k) =>
          acc + (k['miktar'] as num).toDouble() * (k['birim_fiyat'] as num).toDouble());
      await txn.update(DbSabitler.masaSiparisleri,
          {'toplam_tutar': toplam, 'last_updated': simdi},
          where: 'id = ?', whereArgs: [hedefSiparisId]);

      await txn.update(DbSabitler.masaSiparisleri, {
        'durum': 'iptal',
        'toplam_tutar': 0,
        'kapanis_zamani': simdi,
        'last_updated': simdi,
      }, where: 'id = ?', whereArgs: [kaynakSiparisId]);

      await txn.update(DbSabitler.masalar, {'durum': 'dolu', 'last_updated': simdi},
          where: 'id = ?', whereArgs: [hedefMasaId]);
      await txn.update(DbSabitler.masalar, {'durum': 'bos', 'last_updated': simdi},
          where: 'id = ?', whereArgs: [kaynakMasaId]);

      // Kuyruk kaydı AYNI transaction'da (commit ile birlikte kalıcı).
      k.siparis(hedefSiparisId);
      k.siparis(kaynakSiparisId);
      k.masa(hedefMasaId);
      k.masa(kaynakMasaId);
      final tasinanlar = await txn.query(DbSabitler.masaSiparisKalem,
          columns: ['id'], where: 'siparis_id = ?', whereArgs: [hedefSiparisId]);
      for (final kl in tasinanlar) {
        k.kalem(kl['id'] as int);
      }
    });
  }
}

/// Ürün + promosyonlar → miktara göre otomatik birim fiyat.
class _OtoFiyat {
  final UrunModel urun;
  final List<PromosyonModel> promolar;
  _OtoFiyat(this.urun, this.promolar);
  double hesapla(double miktar) =>
      UrunFiyatHesaplayici.hesapla(urun, miktar, promolar);
}

/// Bir masa işleminde değişen satırları toplar; transaction bitmeden hemen
/// önce hepsinin güncel hali sync_queue'ya (aynı transaction'da) yazılır.
class _Kuyruk {
  final _kayitlar = <String, Set<int>>{};

  void masa(int id) => (_kayitlar[DbSabitler.masalar] ??= {}).add(id);
  void siparis(int id) => (_kayitlar[DbSabitler.masaSiparisleri] ??= {}).add(id);
  void kalem(int id) => (_kayitlar[DbSabitler.masaSiparisKalem] ??= {}).add(id);

  Future<void> yaz(Transaction txn) async {
    for (final e in _kayitlar.entries) {
      for (final id in e.value) {
        final r = await txn.query(e.key, where: 'id = ?', whereArgs: [id], limit: 1);
        if (r.isEmpty) continue;
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: e.key, veri: Map<String, dynamic>.from(r.first));
      }
    }
  }
}
