// lib/servisler/bulut/supabase_saglayici.dart
import 'supabase_oturum.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'bulut_saglayici.dart';
import 'supabase_ayarlari.dart';
import 'sync_lww_koruma.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../kolon_haritalama.dart';
import '../log_servisi.dart';
import '../../veri/database/veritabani.dart';

class SupabaseSaglayici implements IBulutSaglayici {
  final String url;
  final String key;

  const SupabaseSaglayici({required this.url, required this.key});

  // ── BULUT ŞEMA KORUMASI ─────────────────────────────────────────────────
  // Yerelde bir sütun eklenip bulut şeması (supabase_tam_sema.sql) henüz
  // güncellenmediyse, PostgREST tablonun TÜM gönderimini reddeder (PGRST204)
  // ve o tablodaki hiçbir satır buluta gitmez. Bunu önlemek için bulutun
  // GERÇEK şeması (OpenAPI) okunur ve bulutta OLMAYAN sütunlar gönderimden
  // ayıklanır; ayıklananlar [eksikBulutSutunlari]'nda tutulur ve Veri Sağlığı
  // Merkezi'nde "SQL'i çalıştırın" uyarısı olarak görünür. SQL çalıştırılınca
  // sütun otomatik gönderilmeye başlar (önbellek 30 dk'da bir ve PGRST204'te
  // yenilenir).
  static Map<String, Set<String>>? _bulutSutunlari;
  static DateTime? _bulutSemaZamani;

  /// "tablo.sütun" — yerelde olup bulutta bulunmadığı için GÖNDERİLMEYEN sütunlar.
  static final Set<String> eksikBulutSutunlari = <String>{};

  /// OpenAPI belgesinden (definitions / components.schemas) tablo → sütun
  /// kümesi çıkarır. Saf — test edilebilir.
  @visibleForTesting
  static Map<String, Set<String>> semaCoz(Map<String, dynamic> openapi) {
    final defs = (openapi['definitions'] ?? (openapi['components'] as Map?)?['schemas'])
        as Map<String, dynamic>?;
    final sonuc = <String, Set<String>>{};
    if (defs == null) return sonuc;
    defs.forEach((tablo, d) {
      final props = (d as Map?)?['properties'] as Map?;
      if (props != null) sonuc[tablo] = props.keys.map((k) => k.toString()).toSet();
    });
    return sonuc;
  }

  /// [kayitlar]dan [sema]da OLMAYAN sütunları siler; silinen sütun adlarını
  /// döner. Şema yok ya da tablo şemada yoksa HİÇBİR ŞEY silmez (güvenli taraf).
  @visibleForTesting
  static Set<String> sutunlariAyikla(
      String tablo, Iterable<Map<String, dynamic>> kayitlar, Map<String, Set<String>>? sema) {
    final izinli = sema?[tablo];
    if (izinli == null || izinli.isEmpty) return const {};
    final silinen = <String>{};
    for (final k in kayitlar) {
      final fazla = k.keys.where((a) => a != 'id' && !izinli.contains(a)).toList();
      for (final a in fazla) {
        k.remove(a);
        silinen.add(a);
      }
    }
    return silinen;
  }

  /// Bulutun sütun şeması (önbellekli). Ağ/yetki hatasında null → koruma
  /// devre dışı kalır, eski davranış sürer.
  Future<Map<String, Set<String>>?> bulutSutunlari({bool yenile = false}) async {
    final taze = _bulutSutunlari != null &&
        _bulutSemaZamani != null &&
        DateTime.now().difference(_bulutSemaZamani!) < const Duration(minutes: 30);
    if (!yenile && taze) return _bulutSutunlari;
    try {
      final r = await http.get(
        Uri.parse('$_rest/'),
        headers: {..._h, 'Accept': 'application/openapi+json'},
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final sema = semaCoz(jsonDecode(r.body) as Map<String, dynamic>);
        if (sema.isNotEmpty) {
          _bulutSutunlari = sema;
          _bulutSemaZamani = DateTime.now();
        }
      }
    } catch (_) {/* eski önbellek / koruma yok */}
    return _bulutSutunlari;
  }

  /// Ayıklanan sütunları bir kez günlüğe yazar ve listeye ekler.
  static void _eksikBildir(String tablo, Set<String> sutunlar) {
    for (final s in sutunlar) {
      if (eksikBulutSutunlari.add('$tablo.$s')) {
        LogServisi().uyari(
            'Bulut şemasında "$tablo.$s" sütunu YOK — bu sütun buluta GÖNDERİLMİYOR '
            '(diğer cihazlara ulaşmaz). supabase_tam_sema.sql dosyasını Supabase SQL '
            'Editor\'de çalıştırın; sonra otomatik gönderilmeye başlar.');
      }
    }
  }

  // ── FK dönüşümü (otomatik senkron yolu) ──
  // Lokal SQLite id'leri ile buluttaki BIGSERIAL id'ler alakasız
  // olduğundan, FK kolonları (satis_kalem.satis_id vb.) gönderilmeden
  // önce lokal→bulut dönüştürülmek zorunda (manuel senkron yolundaki
  // düzeltmenin simetriği). Zincir: lokal id → lokal anahtar (global_id ya
  // da doğal anahtar) → bulut id.
  //
  // 🔴 PERFORMANS DÜZELTMESİ (Bulut Veri Güvenliği Raporu 2026-10-07,
  // Bulgu 9): ÖNCEDEN ilk kullanımda ebeveyn tablonun TAMAMI buluttan
  // (1000'lik sayfalarla) ve yerelden okunuyor, her "ıskada" da tamamı
  // YENİDEN indiriliyordu. Her yeni satış bir ıskaya yol açtığından, büyük
  // satislar/urunler tablosunda her senkron turu on binlerce satır
  // indiriyordu. Artık yalnız GEREKEN kimlikler sorgulanır: yerelde
  // `id IN (…)`, bulutta `anahtar=in.(…)` (50'lik parçalar). Yerel eşleme
  // her çağrıda tazedir (PK sorgusu, ucuz); bulut eşlemesi önbellekte
  // tutulur (bir kaydın bulut id'si değişmez) ve yalnız bulunanlar
  // önbelleğe girer — henüz bulutta olmayan ebeveyn bir sonraki turda
  // yeniden sorulur.
  static final Map<String, Map<String, int>> _fkGidCloudCache = {};

  /// Bir turda bulutta sorgulanacak anahtar sayısı (URL uzunluğu sınırı).
  @visibleForTesting
  static const int fkSorguParcasi = 50;

  /// PostgREST `in.(…)` filtresi için değer listesi — her değer çift
  /// tırnağa alınır (virgül/parantez içeren doğal anahtarlar için), içteki
  /// `\` ve `"` kaçışlanır. Saf — test edilebilir.
  @visibleForTesting
  static String inFiltresi(Iterable<String> degerler) =>
      'in.(${degerler.map((d) => '"${d.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"').join(',')})';

  /// Yerel id → ebeveyn anahtarı. Anahtarı boş olan global_id'li satırlara
  /// kalıcı kimlik üretilir (aşağıdaki nota bkz.).
  Future<Map<int, String>> _fkLokalAnahtarlar(String parent, Set<int> idler) async {
    final db = await Veritabani().db;
    // Eşleşme anahtarı: global_id ya da tablonun doğal anahtarı (kategoriler
    // → ad, subeler → sube_kodu…) — bkz. KolonHaritalama.ebeveynAnahtari.
    final anahtar = KolonHaritalama.ebeveynAnahtari(parent);
    final h = <int, String>{};
    // 🔴🔴🔴 KRİTİK DÜZELTME (kök neden — kullanıcı bulgusu: "kredi
    // kartlarında sorun var, Supabase'e göndermemiş"): global_id'si
    // NULL/boş olan ebeveyn satırları ÖNCEDEN sessizce atlanıyor, çocuğun
    // FK'sı yerel id olarak buluta gidiyordu. Eksik bulunan HER global_id
    // burada kalıcı olarak (lokale yazılarak) doldurulur.
    final eksikler = <int>[];
    final liste = idler.toList();
    for (var i = 0; i < liste.length; i += 500) {
      final parca = liste.sublist(i, (i + 500).clamp(0, liste.length));
      final rows = await db.query(parent,
          columns: ['id', anahtar],
          where: 'id IN (${List.filled(parca.length, '?').join(',')})',
          whereArgs: parca);
      for (final r in rows) {
        final id = r['id'] as int?;
        if (id == null) continue;
        final gid = r[anahtar]?.toString();
        if (gid != null && gid.isNotEmpty) {
          h[id] = gid;
        } else {
          eksikler.add(id);
        }
      }
    }
    // Eksik kimlik yalnızca global_id eşleşmeli tabloda üretilir (doğal
    // anahtar boşsa o kayıt zaten eşleşemez).
    if (eksikler.isNotEmpty && anahtar == 'global_id') {
      final batch = db.batch();
      for (final id in eksikler) {
        final yeniGid = const Uuid().v4();
        h[id] = yeniGid;
        batch.update(parent, {'global_id': yeniGid},
            where: "id = ? AND (global_id IS NULL OR global_id = '')", whereArgs: [id]);
      }
      try {
        await batch.commit(noResult: true);
      } catch (_) {
        // Kalıcı yazım başarısız olsa bile bu turda gönderim için
        // haritada mevcut — bir sonraki senkron kalıcılığı sağlar.
      }
    }
    return h;
  }

  /// Önbellekte olmayan anahtarların bulut id'lerini hedefli sorguyla
  /// getirir. Ağ/HTTP hatasında istisna fırlatır (çağıran bekletir).
  Future<void> _fkBulutIdleriniGetir(String parent, Set<String> anahtarlar) async {
    final cache = _fkGidCloudCache.putIfAbsent(parent, () => {});
    final eksik = anahtarlar.where((a) => !cache.containsKey(a)).toList();
    if (eksik.isEmpty) return;
    final anahtar = KolonHaritalama.ebeveynAnahtari(parent);
    for (var i = 0; i < eksik.length; i += fkSorguParcasi) {
      final parca = eksik.sublist(i, (i + fkSorguParcasi).clamp(0, eksik.length));
      final uri = Uri.parse('$_rest/$parent').replace(queryParameters: {
        'select': 'id,$anahtar',
        anahtar: inFiltresi(parca),
      });
      final r = await http.get(uri, headers: _h).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        throw BulutIstekHatasi(r.statusCode, '$parent FK sorgusu: HTTP ${r.statusCode}');
      }
      for (final row in (jsonDecode(r.body) as List).cast<Map<String, dynamic>>()) {
        final gid = row[anahtar]?.toString();
        final cid = row['id'];
        if (gid != null && gid.isNotEmpty && cid != null) {
          cache[gid] = cid is int ? cid : int.parse(cid.toString());
        }
      }
    }
  }

  /// Kayıtlardaki FK kolonlarını lokal id → bulut id'ye dönüştürür.
  /// Zincir: lokal id → lokal global_id → buluttaki id.
  ///
  /// Dönüş: GÖNDERİLMEMESİ gereken (bekletilecek) kayıtlar — ebeveyni
  /// yerelde var ama henüz bulutta yok.
  ///
  /// 🔴🔴 DÜZELTME (2026-09-27): ÖNCEDEN eşleşme bulunamazsa yerel id
  /// "olduğu gibi" gönderiliyordu. Yerel id ile bulut id AYNI sayı
  /// uzayında olduğundan (ikisi de 1'den artan) bu, kalemi buluttaki
  /// BAŞKA bir satışa sessizce bağlıyordu (ör. yerel satış #57'nin
  /// kalemi, başka cihazın bulut #57 satışının detayında görünür).
  /// Artık: ebeveyn bulutta henüz yoksa kayıt bekletilir (sonraki turda,
  /// ebeveyn gittikten sonra doğru id ile gider); ebeveyn yerelde de
  /// yoksa (silinmiş/hiç olmamış) yanlış bağ yerine NULL gönderilir.
  Future<Set<Map<String, dynamic>>> _fkDonustur(
      String tablo, List<Map<String, dynamic>> kayitlar) async {
    final bekletilecek = Set<Map<String, dynamic>>.identity();
    if (kayitlar.isEmpty || KolonHaritalama.ebeveynler(tablo).isEmpty) {
      return bekletilecek;
    }
    // 1) Satır bazlı FK'ları topla. Polimorfik referanslar (kasa_hareketleri.
    // referans_id, cari_hareket.fis_id …) satırın tür değerine göre farklı
    // tabloya işaret eder (bkz. KolonHaritalama.polimorfikFkHaritasi).
    final satirFk = <(Map<String, dynamic>, String, String, int)>[];
    final gerekenIdler = <String, Set<int>>{};
    for (final m in kayitlar) {
      final fkMap = KolonHaritalama.satirFkHaritasi(tablo, m);
      if (fkMap == null) continue;
      for (final e in fkMap.entries) {
        final v = m[e.key];
        if (v == null) continue;
        final lid = v is int ? v : int.tryParse(v.toString());
        if (lid == null) continue;
        satirFk.add((m, e.key, e.value, lid));
        gerekenIdler.putIfAbsent(e.value, () => {}).add(lid);
      }
    }
    // 2) Ebeveyn başına yalnız gereken kimlikleri çöz (yerel + bulut).
    final lokal = <String, Map<int, String>>{};
    final hatali = <String>{};
    for (final e in gerekenIdler.entries) {
      try {
        final h = await _fkLokalAnahtarlar(e.key, e.value);
        lokal[e.key] = h;
        await _fkBulutIdleriniGetir(e.key, h.values.toSet());
      } catch (_) {
        // Dönüşüm yapılamadı (ör. ağ) — yanlış bağla gitmesin,
        // bu tur bekletilsin.
        hatali.add(e.key);
      }
    }
    // 3) Uygula.
    for (final (m, kolon, parent, lid) in satirFk) {
      if (hatali.contains(parent)) {
        bekletilecek.add(m);
        continue;
      }
      final gid = lokal[parent]![lid];
      if (gid == null) {
        m[kolon] = null; // ebeveyn yerelde yok — yanlış bağ kurma
        continue;
      }
      final cid = _fkGidCloudCache[parent]?[gid];
      if (cid != null) {
        m[kolon] = cid;
      } else {
        bekletilecek.add(m);
      }
    }
    return bekletilecek;
  }

  @override String get ad   => 'Supabase';
  @override String get ikon => '⚡';

  String get _rest => '$url/rest/v1';

  Map<String,String> get _h => {
    'apikey': key,
    'Authorization': 'Bearer ${SupabaseOturum.bearer(key)}',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String,String> _upsertH(String onConflict) => {
    ..._h,
    // Supabase UPSERT: resolution=merge-duplicates → varsa güncelle, yoksa ekle
    'Prefer': 'resolution=merge-duplicates,return=minimal',
  };

  @override
  Future<BaglantiSonuc> baglantiTest() async {
    final sw = Stopwatch()..start();
    try {
      final r = await http.get(
        Uri.parse('$_rest/urunler?limit=1&select=id'),
        headers: _h,
      ).timeout(const Duration(seconds: 10));
      sw.stop();
      if (r.statusCode == 200) {
        return BaglantiSonuc(
          basarili: true,
          mesaj: 'Bağlantı başarılı (${sw.elapsedMilliseconds}ms)',
          gecikmeMs: sw.elapsedMilliseconds,
        );
      }
      return BaglantiSonuc(basarili: false,
          mesaj: 'HTTP ${r.statusCode}: ${r.body.substring(0, r.body.length.clamp(0,100))}');
    } catch (e) {
      return BaglantiSonuc(basarili: false, mesaj: 'Bağlanamadı: $e');
    }
  }

  @override
  Future<void> upsert({
    required String tablo,
    required Map<String, dynamic> veri,
    required String uniqueAlan,
  }) async {
    // ÖNCEDEN BURADA (otomatik/anlık senkronizasyon yolu — BulutManager
    // her kayıt değiştiğinde bunu çağırır) ÇAKIŞMA KORUMASI YOKTU.
    // SupabaseSyncServisi'ndeki (manuel "Buluta Gönder" butonu) aynı
    // sorunu daha önce düzeltmiştim, ama bu OTOMATİK yol (muhtemelen
    // günlük kullanımda çok daha sık tetiklenen yol) korumasız kalmıştı.
    // İki cihaz aynı kaydı neredeyse aynı anda değiştirirse, ağ
    // gecikmesine bağlı olarak eski değişiklik yeni olanı ezebilirdi.
    // Artık göndermeden önce bulut'taki mevcut last_updated kontrol
    // ediliyor; bulut zaten daha yeniyse gönderilmiyor.
    if (veri.containsKey('last_updated') && veri[uniqueAlan] != null) {
      final atlaMi = await _bulutDahaYeniMi(tablo, uniqueAlan, veri[uniqueAlan], veri['last_updated']);
      if (atlaMi) {
        // bulut zaten daha güncel — üzerine yazma; yalnız türetilmiş alanlar
        await _turetilmisAlanlariGonder(tablo, uniqueAlan, [veri]);
        return;
      }
    }

    // 🔥 EVRENSEL DÜZELTME: SupabaseSyncServisi'nde (manuel senkronizasyon)
    // bulduğum AYNI hata sınıfı burada da (otomatik senkronizasyon)
    // önlenmesi gerekiyordu — bazı kayıtlarda beklenmedik bir Dart
    // boolean değeri, Supabase'de sayısal olan bir sütuna gönderiliyor
    // ("invalid input syntax for type bigint: 'false'" hatası). Hangi
    // tablo/sütun olursa olsun, göndermeden önce tüm boolean değerler
    // güvenli şekilde 0/1'e çevriliyor.
    for (final k in veri.keys.toList()) {
      final v = veri[k];
      if (v is bool) veri[k] = v ? 1 : 0;
    }

    // 🔴 KRİTİK DÜZELTME: Önceden URL'de "on_conflict" parametresi
    // YOKTU — PostgREST, on_conflict verilmediğinde merge-duplicates
    // çakışmasını PRIMARY KEY (id) üzerinden çözer. Lokal SQLite id'si
    // ile buluttaki BIGSERIAL id alakasız olduğundan bu, yanlış
    // kayıtların ezilmesine yol açabiliyordu. Artık eşleştirme, doğru
    // anahtar olan uniqueAlan (genelde global_id) üzerinden yapılıyor.
    // Ek güvence: lokal 'id' gönderilen veriden çıkarılıyor (bulutun
    // kendi id'sine asla dokunulmamalı).
    veri.remove('id');
    // Bulutta olmayan sütunları ayıkla (bkz. BULUT ŞEMA KORUMASI)
    _eksikBildir(tablo, sutunlariAyikla(tablo, [veri], await bulutSutunlari()));
    // FK kolonlarını lokal id → bulut id'ye dönüştür (üstteki nota bkz.)
    if ((await _fkDonustur(tablo, [veri])).isNotEmpty) {
      // Ebeveyn henüz bulutta yok — geçici (statusKodu yok) hata.
      throw BulutIstekHatasi(null, '$tablo: ebeveyn kayıt henüz bulutta yok, bekletildi');
    }
    // 🔴🔴🔴 KESİN KÖK NEDEN (GitHub supabase-js #1653'te resmi olarak
    // doğrulandı — "DEFAULT is not allowed in this context", 42601):
    // Tekli (dizi bile olsa) bir upsert'te `columns` URL parametresi
    // BELİRTİLMEZSE, PostgREST payload'da OLMAYAN sütunları da işleme
    // dahil etmeye çalışıyor ve bunlar için içeride "DEFAULT" anahtar
    // kelimesini kullanmaya çalışıp bazı bağlamlarda sözdizimi hatası
    // veriyor. Önceki "diziye sar" denemem YETERSİZ kalmıştı — asıl
    // çözüm, PostgREST'e SADECE payload'daki sütunlarla ilgilenmesini
    // AÇIKÇA söylemek: ?columns=col1,col2,...
    final sutunlar = veri.keys.map(Uri.encodeComponent).join(',');
    final r = await http.post(
      Uri.parse('$_rest/$tablo?on_conflict=$uniqueAlan&columns=$sutunlar'),
      headers: _upsertH(uniqueAlan),
      body: jsonEncode([veri]),
    ).timeout(const Duration(seconds: 15));
    if (r.statusCode >= 400) {
      if (r.body.contains('PGRST204')) _bulutSemaZamani = null; // şemayı yeniden oku
      throw BulutIstekHatasi(r.statusCode,
          '$tablo upsert: ${r.body.substring(0, r.body.length.clamp(0, 200))}');
    }
  }

  /// Bulut'taki mevcut kaydın last_updated'ı, göndermek üzere olduğumuz
  /// değerden DAHA YENİ ya da EŞİT mi diye kontrol eder — öyleyse
  /// üzerine yazılmaması gerektiğini (true) döndürür. Kontrol
  /// başarısız olursa (ağ hatası vb.) güvenli tarafta kalıp göndermeye
  /// izin verir (false).
  Future<bool> _bulutDahaYeniMi(
      String tablo, String uniqueAlan, dynamic deger, dynamic yerelLu) async {
    try {
      final yerelZaman = KolonHaritalama.utcZaman(yerelLu);
      if (yerelZaman == null) return false;
      final r = await http.get(
        Uri.parse('$_rest/$tablo?select=last_updated&$uniqueAlan=eq.$deger'),
        headers: _h,
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return false;
      final liste = jsonDecode(r.body) as List;
      if (liste.isEmpty) return false; // bulut'ta yok — gönder
      final bulutLu = KolonHaritalama.utcZaman(liste.first['last_updated']);
      if (bulutLu == null) return false;
      return !yerelZaman.isAfter(bulutLu); // bulut >= yerel ise atla
    } catch (_) {
      return false; // emin olamıyorsak göndermeye izin ver
    }
  }

  /// Toplu gönderim için: bulutta, satırdan KESİN olarak daha yeni sürümü
  /// olanları döner. Doğrulama yapılamazsa (ağ hatası, tabloda last_updated
  /// yok, yanıt beklenmedik) boş döner — gönderime izin verilir; kesin koruma
  /// sunucu tarafı tetikleyicidir (supabase_tam_sema.sql Bölüm I).
  Future<Set<Map<String, dynamic>>> _bulutunDahaYeniOldugu(
      String tablo, String uniqueAlan, List<Map<String, dynamic>> batch) async {
    final bos = Set<Map<String, dynamic>>.identity();
    final anahtarlar = <String>{
      for (final k in batch)
        if (k['last_updated'] != null && k[uniqueAlan] != null)
          k[uniqueAlan].toString(),
    };
    if (anahtarlar.isEmpty) return bos;
    final bulutZamanlari = <String, DateTime>{};
    try {
      final liste = anahtarlar.toList();
      const parca = 50; // URL uzunluğu sınırı
      for (var i = 0; i < liste.length; i += parca) {
        final dilim = liste.sublist(i, (i + parca).clamp(0, liste.length));
        final filtre = Uri.encodeComponent(SyncLwwKoruma.inListesi(dilim));
        final r = await http.get(
          Uri.parse('$_rest/$tablo?select=$uniqueAlan,last_updated'
              '&$uniqueAlan=in.$filtre'),
          headers: _h,
        ).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) return bos;
        bulutZamanlari.addAll(SyncLwwKoruma.zamanHaritasi(
            jsonDecode(r.body) as List, uniqueAlan));
      }
    } catch (_) {
      return bos;
    }
    return SyncLwwKoruma.bulutuKesinDahaYeniOlanlar(
      kayitlar: batch,
      uniqueAlan: uniqueAlan,
      bulutZamanlari: bulutZamanlari,
    );
  }

  /// LWW'nin atladığı satırlarda yalnız TÜRETİLMİŞ alanları (bkz.
  /// KolonHaritalama.turetilmisAlanlar — urunler.stok, cari.bakiye) damgasız
  /// PATCH ile günceller. last_updated gönderilmediği için sunucu LWW
  /// tetikleyicisi devreye girmez ve ad/fiyat gibi alanlara dokunulmaz.
  /// Best-effort: başarısızlık bir sonraki stok/bakiye değişiminde düzelir.
  Future<void> _turetilmisAlanlariGonder(
      String tablo, String uniqueAlan, Iterable<Map<String, dynamic>> satirlar) async {
    final alanlar = KolonHaritalama.turetilmisAlanlar[tablo];
    if (alanlar == null) return;
    for (final s in satirlar) {
      final deger = s[uniqueAlan]?.toString();
      if (deger == null || deger.isEmpty) continue;
      final govde = {for (final a in alanlar) if (s.containsKey(a)) a: s[a]};
      if (govde.isEmpty) continue;
      try {
        final r = await http.patch(
          Uri.parse('$_rest/$tablo?$uniqueAlan=eq.${Uri.encodeComponent(deger)}'),
          headers: _h,
          body: jsonEncode(govde),
        ).timeout(const Duration(seconds: 10));
        if (r.statusCode >= 400) {
          LogServisi().uyari('Türetilmiş alan güncellenemedi ($tablo.${govde.keys.join(',')})',
              ek: 'HTTP ${r.statusCode}');
        }
      } catch (_) {/* best-effort */}
    }
  }

  /// Kayıt indekslerini sütun kümesine göre gruplar (ilk görülme sırasıyla).
  @visibleForTesting
  static List<List<int>> sutunKumesineGoreGrupla(List<Map<String, dynamic>> veriler) {
    final gruplar = <String, List<int>>{};
    for (var j = 0; j < veriler.length; j++) {
      final imza = (veriler[j].keys.toList()..sort()).join(',');
      gruplar.putIfAbsent(imza, () => []).add(j);
    }
    return gruplar.values.toList();
  }

  @override
  Future<BulutSonuc> topluUpsert({
    required String tablo,
    required List<Map<String, dynamic>> veriler,
    required String uniqueAlan,
  }) async {
    if (veriler.isEmpty) return const BulutSonuc();
    int basarili = 0, hata = 0;
    final hatalar = <String>[];
    final bekletilenler = <int>{};
    int? sonStatusKodu;
    final bulutSema = await bulutSutunlari();

    // 🔴🔴 KRİTİK DÜZELTME: PostgREST'in bilinen bir davranışı — toplu
    // (bulk) upsert'te AYNI istekteki kayıtların FARKLI sütun kümelerine
    // sahip olması, Postgres'in eksik sütunlar için SQL DEFAULT kullanmaya
    // çalışıp "DEFAULT is not allowed in this context" (42601) hatası
    // vermesine yol açıyordu. ÖNCEDEN çözüm eksik alanlara null eklemekti —
    // ama bu, yalnız birkaç alan taşıyan bir kaydın (kısmi güncelleme)
    // bulutta DİĞER tüm alanlarını sessizce siliyordu (Bulut Veri Güvenliği
    // Raporu 2026-10-07, Bulgu 4). Artık kayıtlar sütun kümesine göre
    // gruplanır; her istek tek tip kayıt taşır, eksik alan doldurulmaz.
    // Sonuçtaki [bekletilenler] indeksleri [veriler]'deki sıraya göredir.
    for (final k in veriler) { k.remove('id'); }
    // Batch olarak gönder (max 200 kayıt/istek)
    const batchSize = 200;
    for (final grup in sutunKumesineGoreGrupla(veriler)) {
    for (int i = 0; i < grup.length; i += batchSize) {
      final indeksler = grup.sublist(i, (i + batchSize).clamp(0, grup.length));
      final batch = [for (final j in indeksler) veriler[j]];
      // 🔥 Aynı evrensel bool->int koruması (bkz. upsert() içindeki not)
      // + lokal 'id' temizliği (bkz. upsert() içindeki on_conflict notu)
      // Bulutta olmayan sütunları ayıkla (bkz. BULUT ŞEMA KORUMASI)
      _eksikBildir(tablo, sutunlariAyikla(tablo, batch, bulutSema));
      for (final kayit in batch) {
        kayit.remove('id');
        for (final k in kayit.keys.toList()) {
          final v = kayit[k];
          if (v is bool) kayit[k] = v ? 1 : 0;
        }
      }
      // Grup tek tip; ayıklama da tüm gruba aynı uygulandı. Yine de
      // birleşim alınır (columns parametresi için).
      final tumAnahtarlar = <String>{};
      for (final kayit in batch) { tumAnahtarlar.addAll(kayit.keys); }
      // Bulutta zaten daha yeni sürümü olan (eski çevrimdışı görüntü) satırlar
      // gönderilmez — aksi hâlde başka cihazın daha yeni kaydı sessizce geri
      // alınırdı. Atlananlar "tamamlandı" sayılır (kuyruktan düşer); doğru
      // sürüm zaten bulutta, bu cihaza da çekmede gelir.
      var aday = batch;
      final atlanan = await _bulutunDahaYeniOldugu(tablo, uniqueAlan, batch);
      if (atlanan.isNotEmpty) {
        // Satırın geri kalanı atlansa da türetilmiş alan (stok/bakiye) buluta
        // gitsin — bulut değeri bayat kalmasın.
        await _turetilmisAlanlariGonder(tablo, uniqueAlan, atlanan);
        basarili += atlanan.length;
        aday = batch.where((k) => !atlanan.contains(k)).toList();
        if (aday.isEmpty) continue;
      }
      var gonderilecek = aday;
      try {
        // FK kolonlarını lokal id → bulut id'ye dönüştür (sınıf
        // başındaki FK dönüşüm notuna bkz.). Ebeveyni henüz bulutta
        // olmayan kayıtlar bu tur gönderilmez, bekletilir.
        final bekle = await _fkDonustur(tablo, aday);
        if (bekle.isNotEmpty) {
          for (var j = 0; j < batch.length; j++) {
            if (bekle.contains(batch[j])) bekletilenler.add(indeksler[j]);
          }
          gonderilecek = aday.where((k) => !bekle.contains(k)).toList();
          if (gonderilecek.isEmpty) continue;
        }
        // 🔴🔴🔴 KESİN KÖK NEDEN (GitHub supabase-js #1653) — bkz.
        // upsert()'teki ayrıntılı not. Batch zaten normalize edildiği
        // (tüm kayıtlar aynı anahtar kümesine sahip) için buradaki
        // 'tumAnahtarlar' seti doğrudan columns parametresi olarak
        // kullanılabilir.
        final sutunlar = tumAnahtarlar.map(Uri.encodeComponent).join(',');
        final r = await http.post(
          Uri.parse('$_rest/$tablo?on_conflict=$uniqueAlan&columns=$sutunlar'),
          headers: _upsertH(uniqueAlan),
          body: jsonEncode(gonderilecek),
        ).timeout(const Duration(seconds: 30));
        if (r.statusCode >= 400) {
          hata += gonderilecek.length;
          sonStatusKodu = r.statusCode;
          if (r.body.contains('PGRST204')) _bulutSemaZamani = null; // şemayı yeniden oku
          final msg = '$tablo batch ${r.statusCode}: ${r.body.substring(0,r.body.length.clamp(0,150))}';
          if (!hatalar.contains(msg)) hatalar.add(msg);
        } else {
          basarili += gonderilecek.length;
        }
      } catch (e) {
        hata += gonderilecek.length;
        // Ham ağ/zaman aşımı istisnaları (SocketException/TimeoutException
        // vb.) statusKodu taşımaz — sonStatusKodu null kalır, bu da
        // BulutSonuc.tur'un bunu GEÇİCİ saymasını sağlar (doğru davranış).
        hatalar.add('$tablo batch hata: $e');
      }
    }
    }
    return BulutSonuc(
        basarili: basarili,
        hata: hata,
        hataMesajlari: hatalar,
        sonStatusKodu: sonStatusKodu,
        bekletilenler: bekletilenler);
  }

  @override
  Future<List<Map<String,dynamic>>> cek({
    required String tablo,
    DateTime? sonGuncelleme,
    int limit = 1000,
  }) async {
    var q = '$_rest/$tablo?limit=$limit&order=last_updated.asc';
    if (sonGuncelleme != null) {
      final iso = Uri.encodeComponent(sonGuncelleme.toUtc().toIso8601String());
      q += '&last_updated=gt.$iso';
    }
    final r = await http.get(Uri.parse(q), headers: _h)
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) return [];
    return (jsonDecode(r.body) as List).cast<Map<String,dynamic>>();
  }

  @override
  Future<void> sil({
    required String tablo,
    required String uniqueAlan,
    required String deger,
  }) async {
    final val = Uri.encodeComponent(deger);
    final r = await http.patch(
      Uri.parse('$_rest/$tablo?$uniqueAlan=eq.$val'),
      headers: _h,
      body: jsonEncode({
        'is_deleted': true,
        'last_updated': DateTime.now().toUtc().toIso8601String(),
      }),
    ).timeout(const Duration(seconds: 10));
    // 🔴 Madde 5 sertleştirmesi: bu fonksiyon ÖNCEDEN durum kodunu HİÇ
    // kontrol etmiyordu — 401/403/404 gibi kalıcı bir hata bile "başarılı"
    // sayılıp kuyruktan silinirdi, silme işlemi buluta HİÇ ulaşmamış
    // olurdu ama BulutManager bunu asla fark edip yeniden denemezdi.
    if (r.statusCode >= 400) {
      throw BulutIstekHatasi(r.statusCode,
          '$tablo sil: ${r.body.substring(0, r.body.length.clamp(0, 200))}');
    }
  }

  @override
  Future<void> kaliciSil({
    required String tablo,
    required String uniqueAlan,
    required String deger,
  }) async {
    if (deger.isEmpty) return; // boş filtre TÜM tabloyu silerdi
    final val = Uri.encodeComponent(deger);
    final r = await http.delete(
      Uri.parse('$_rest/$tablo?$uniqueAlan=eq.$val'),
      headers: _h,
    ).timeout(const Duration(seconds: 10));
    if (r.statusCode >= 400) {
      throw BulutIstekHatasi(r.statusCode,
          '$tablo kalıcı sil: ${r.body.substring(0, r.body.length.clamp(0, 200))}');
    }
  }

  @override
  Future<void> ayarlariKaydet(Map<String,String> ayarlar) async {
    final mevcutUrl = ayarlar['url'] ?? await SupabaseAyarlari.urlOku() ?? '';
    final mevcutKey = ayarlar['key'] ?? await SupabaseAyarlari.keyOku() ?? '';
    await SupabaseAyarlari.kaydet(url: mevcutUrl, key: mevcutKey);
  }

  @override
  Future<Map<String,String>> ayarlariYukle() async {
    return {
      'url': await SupabaseAyarlari.urlOku() ?? '',
      'key': await SupabaseAyarlari.keyOku() ?? '',
    };
  }

  /// Bir satırı ekler (varsa on_conflict ile idempotent upsert) VE
  /// sunucunun oluşturduğu/eşleşen satırı (ör. BIGSERIAL id) geri
  /// döndürür — normal upsert() (fire-and-forget, "return=minimal")
  /// yeterli DEĞİLDİR çünkü ör. Terminal kaydında sunucunun ürettiği
  /// id'yi hemen yerel cihaza yazmamız gerekiyor.
  Future<Map<String, dynamic>?> insertVeDondur(
      String tablo, Map<String, dynamic> veri, {String? onConflict}) async {
    final uri = onConflict != null
        ? Uri.parse('$_rest/$tablo?on_conflict=$onConflict')
        : Uri.parse('$_rest/$tablo');
    final headers = {
      ..._h,
      'Prefer': onConflict != null
          ? 'resolution=merge-duplicates,return=representation'
          : 'return=representation',
    };
    final r = await http.post(uri, headers: headers, body: jsonEncode(veri))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode >= 400) {
      throw BulutIstekHatasi(r.statusCode,
          '$tablo insert: ${r.body.substring(0, r.body.length.clamp(0, 300))}');
    }
    if (r.body.isEmpty) return null;
    final govde = jsonDecode(r.body);
    if (govde is List && govde.isNotEmpty) return govde.first as Map<String, dynamic>;
    if (govde is Map<String, dynamic>) return govde;
    return null;
  }

  /// PostgREST sorgu dizesiyle okuma (ör. 'select=id,ad&order=id.asc').
  /// Senkron akışındaki [cek]'ten farklı olarak hata SESSİZCE boş liste
  /// dönmez — yönetim ekranlarında "veri yok" ile "okunamadı" ayrılmalı.
  Future<List<Map<String, dynamic>>> sorgula(String tablo, String sorgu) async {
    final r = await http.get(Uri.parse('$_rest/$tablo?$sorgu'), headers: _h)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode >= 400) {
      throw BulutIstekHatasi(r.statusCode,
          '$tablo okuma: ${r.body.substring(0, r.body.length.clamp(0, 300))}');
    }
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  /// `id` ile tek satırı kısmen günceller (PATCH).
  Future<void> idIleGuncelle(String tablo, int id, Map<String, dynamic> veri) async {
    final r = await http.patch(Uri.parse('$_rest/$tablo?id=eq.$id'),
        headers: _h, body: jsonEncode(veri))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode >= 400) {
      throw BulutIstekHatasi(r.statusCode,
          '$tablo güncelle: ${r.body.substring(0, r.body.length.clamp(0, 300))}');
    }
  }

  /// PostgreSQL RPC (stored function) çağırır — ör.
  /// fatura_blok_tahsis_et() gibi ATOMİK sunucu-taraflı işlemler için.
  /// Normal REST tablo uçlarından FARKLI olarak burada Postgres'in
  /// kendi satır kilidi/transaction garantisi devreye girer — bu yüzden
  /// merkezi numara/blok tahsisi gibi concurrency-kritik işlemler
  /// BİLEREK buradan geçiyor, tablo upsert'inden değil (bkz.
  /// CENTRAL_DOCUMENT_NUMBERING_DEEP_AUDIT.md §20).
  Future<List<Map<String, dynamic>>> rpcCagir(
      String fonksiyonAdi, Map<String, dynamic> parametreler) async {
    final r = await http.post(
      Uri.parse('$_rest/rpc/$fonksiyonAdi'),
      headers: _h,
      body: jsonEncode(parametreler),
    ).timeout(const Duration(seconds: 20));
    if (r.statusCode >= 400) {
      throw BulutIstekHatasi(r.statusCode,
          'rpc $fonksiyonAdi: ${r.body.substring(0, r.body.length.clamp(0, 300))}');
    }
    if (r.body.isEmpty) return [];
    final govde = jsonDecode(r.body);
    if (govde is List) return govde.cast<Map<String, dynamic>>();
    if (govde is Map<String, dynamic>) return [govde];
    return [];
  }
}
