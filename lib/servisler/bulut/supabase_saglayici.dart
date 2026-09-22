// lib/servisler/bulut/supabase_saglayici.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'bulut_saglayici.dart';
import 'supabase_ayarlari.dart';
import '../kolon_haritalama.dart';
import '../../veri/database/veritabani.dart';

class SupabaseSaglayici implements IBulutSaglayici {
  final String url;
  final String key;

  const SupabaseSaglayici({required this.url, required this.key});

  // ── FK dönüşüm cache'leri (otomatik senkron yolu) ──
  // Lokal SQLite id'leri ile buluttaki BIGSERIAL id'ler alakasız
  // olduğundan, FK kolonları (satis_kalem.satis_id vb.) gönderilmeden
  // önce lokal→bulut dönüştürülmek zorunda (manuel senkron yolundaki
  // düzeltmenin simetriği). Cache'ler static (constructor const
  // kalabilsin diye); bir lokal id cache'te BULUNAMAZSA o parent'ın
  // cache'i bir kez tazelenir ("miss-refresh") — böylece az önce
  // eklenen yeni kayıtlar da yakalanır, bayat cache sorunu olmaz.
  static final Map<String, Map<int, String>> _fkLokalGidCache = {};
  static final Map<String, Map<String, int>> _fkGidCloudCache = {};

  Future<void> _fkLokalCacheYukle(String parent) async {
    final db = await Veritabani().db;
    final rows = await db.query(parent, columns: ['id', 'global_id']);
    final h = <int, String>{};
    // 🔴🔴🔴 KRİTİK DÜZELTME (kök neden — kullanıcı bulgusu: "kredi
    // kartlarında sorun var, Supabase'e göndermemiş"): Bu fonksiyon
    // ÖNCEDEN global_id'si NULL/boş olan satırları sessizce ATLIYORDU.
    // Bir parent tablo (ör. 'bankalar') senkron sistemine SONRADAN
    // eklendiğinde, o tablodaki ESKİ kayıtların global_id'si hâlâ NULL
    // olabiliyordu (hiçbir eski kod bu sütuna yazmıyordu). Sonuç: bu
    // eski bir kayda bağlı YENİ bir çocuk kayıt (ör. yeni bir kredi
    // kartı) gönderilmeye çalışıldığında, FK dönüşümü parent'ı HİÇ
    // BULAMIYOR, çocuk kaydın FK sütunu (banka_id gibi) YEREL id
    // olarak OLDUĞU GİBİ buluta gidiyordu — bulutta NOT NULL + FOREIGN
    // KEY kısıtlaması olan sütunlarda bu, kaydın tamamen reddedilmesine
    // ya da yanlış bir kayda bağlanmasına yol açıyordu. Artık eksik
    // bulunan HER global_id, burada kalıcı olarak (lokale yazılarak)
    // dolduruluyor — bu hata sınıfı, ileride sisteme eklenecek başka
    // bir tabloda da bir daha asla sessizce tekrarlanmayacak.
    final eksikler = <int>[];
    for (final r in rows) {
      final id = r['id'] as int?;
      if (id == null) continue;
      final gid = r['global_id']?.toString();
      if (gid != null && gid.isNotEmpty) {
        h[id] = gid;
      } else {
        eksikler.add(id);
      }
    }
    if (eksikler.isNotEmpty) {
      final batch = db.batch();
      for (final id in eksikler) {
        final yeniGid = const Uuid().v4();
        h[id] = yeniGid;
        batch.update(parent, {'global_id': yeniGid}, where: 'id = ?', whereArgs: [id]);
      }
      try {
        await batch.commit(noResult: true);
      } catch (_) {
        // Kalıcı yazım başarısız olsa bile bu turda gönderim için
        // haritada mevcut — bir sonraki senkron kalıcılığı sağlar.
      }
    }
    _fkLokalGidCache[parent] = h;
  }

  Future<void> _fkBulutCacheYukle(String parent) async {
    final h = <String, int>{};
    int offset = 0;
    int guvenlikSayaci = 0;
    // Güvenlik sınırı — sonsuz döngü fiziksel olarak engellenir
    while (guvenlikSayaci++ < 200) {
      final r = await http.get(
        Uri.parse('$_rest/$parent?select=id,global_id&limit=1000&offset=$offset'),
        headers: _h,
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) break;
      final batch = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
      if (batch.isEmpty) break;
      for (final row in batch) {
        final gid = row['global_id']?.toString();
        final cid = row['id'];
        if (gid != null && gid.isNotEmpty && cid != null) {
          h[gid] = cid is int ? cid : int.parse(cid.toString());
        }
      }
      if (batch.length < 1000) break;
      offset += 1000;
    }
    _fkGidCloudCache[parent] = h;
  }

  /// Kayıtlardaki FK kolonlarını lokal id → bulut id'ye dönüştürür.
  /// Zincir: lokal id → lokal global_id → buluttaki id. Eşleşme
  /// bulunamazsa değer olduğu gibi bırakılır (sonraki senkron düzeltir).
  Future<void> _fkDonustur(String tablo, List<Map<String, dynamic>> kayitlar) async {
    final fkMap = KolonHaritalama.fkHarita(tablo);
    if (fkMap == null || kayitlar.isEmpty) return;
    for (final e in fkMap.entries) {
      final kolon = e.key, parent = e.value;
      try {
        if (_fkLokalGidCache[parent] == null) await _fkLokalCacheYukle(parent);
        if (_fkGidCloudCache[parent] == null) await _fkBulutCacheYukle(parent);
        bool lokalTazelendi = false, bulutTazelendi = false;
        for (final m in kayitlar) {
          final v = m[kolon];
          if (v == null) continue;
          final lid = v is int ? v : int.tryParse(v.toString());
          if (lid == null) continue;
          var gid = _fkLokalGidCache[parent]![lid];
          if (gid == null && !lokalTazelendi) {
            await _fkLokalCacheYukle(parent); // miss-refresh
            lokalTazelendi = true;
            gid = _fkLokalGidCache[parent]![lid];
          }
          if (gid == null) continue;
          var cid = _fkGidCloudCache[parent]![gid];
          if (cid == null && !bulutTazelendi) {
            await _fkBulutCacheYukle(parent); // miss-refresh
            bulutTazelendi = true;
            cid = _fkGidCloudCache[parent]![gid];
          }
          if (cid != null) m[kolon] = cid;
        }
      } catch (_) {
        // dönüşüm başarısızsa mevcut değer korunur — senkron durmasın
      }
    }
  }

  @override String get ad   => 'Supabase';
  @override String get ikon => '⚡';

  String get _rest => '$url/rest/v1';

  Map<String,String> get _h => {
    'apikey': key,
    'Authorization': 'Bearer $key',
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
      if (atlaMi) return; // bulut zaten daha güncel — üzerine yazma
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
    // FK kolonlarını lokal id → bulut id'ye dönüştür (üstteki nota bkz.)
    await _fkDonustur(tablo, [veri]);
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
      final yerelZaman = DateTime.tryParse(yerelLu?.toString() ?? '');
      if (yerelZaman == null) return false;
      final r = await http.get(
        Uri.parse('$_rest/$tablo?select=last_updated&$uniqueAlan=eq.$deger'),
        headers: _h,
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return false;
      final liste = jsonDecode(r.body) as List;
      if (liste.isEmpty) return false; // bulut'ta yok — gönder
      final bulutLu = DateTime.tryParse(liste.first['last_updated']?.toString() ?? '');
      if (bulutLu == null) return false;
      return !yerelZaman.isAfter(bulutLu); // bulut >= yerel ise atla
    } catch (_) {
      return false; // emin olamıyorsak göndermeye izin ver
    }
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
    int? sonStatusKodu;

    // Batch olarak gönder (max 200 kayıt/istek)
    const batchSize = 200;
    for (int i = 0; i < veriler.length; i += batchSize) {
      final batch = veriler.sublist(i, (i + batchSize).clamp(0, veriler.length));
      // 🔥 Aynı evrensel bool->int koruması (bkz. upsert() içindeki not)
      // + lokal 'id' temizliği (bkz. upsert() içindeki on_conflict notu)
      for (final kayit in batch) {
        kayit.remove('id');
        for (final k in kayit.keys.toList()) {
          final v = kayit[k];
          if (v is bool) kayit[k] = v ? 1 : 0;
        }
      }
      // 🔴🔴 KRİTİK DÜZELTME: PostgREST'in bilinen bir davranışı —
      // toplu (bulk) upsert'te AYNI istekteki kayıtların FARKLI
      // sütun kümelerine sahip olması (biri 'printer_turu' gönderiyor,
      // diğeri o alan null olduğu için hiç göndermiyor), Postgres'in
      // eksik sütunlar için SQL DEFAULT anahtar kelimesini kullanmaya
      // çalışıp "DEFAULT is not allowed in this context" (42601)
      // hatası vermesine yol açıyordu. Çözüm: batch içindeki TÜM
      // kayıtları, o batch'teki anahtarların BİRLEŞİMİNE göre
      // normalize et — eksik olan alanlara JSON null ata (omit ETME).
      final tumAnahtarlar = <String>{};
      for (final kayit in batch) { tumAnahtarlar.addAll(kayit.keys); }
      for (final kayit in batch) {
        for (final anahtar in tumAnahtarlar) {
          kayit.putIfAbsent(anahtar, () => null);
        }
      }
      try {
        // FK kolonlarını lokal id → bulut id'ye dönüştür (sınıf
        // başındaki FK dönüşüm notuna bkz.)
        await _fkDonustur(tablo, batch);
        // 🔴🔴🔴 KESİN KÖK NEDEN (GitHub supabase-js #1653) — bkz.
        // upsert()'teki ayrıntılı not. Batch zaten normalize edildiği
        // (tüm kayıtlar aynı anahtar kümesine sahip) için buradaki
        // 'tumAnahtarlar' seti doğrudan columns parametresi olarak
        // kullanılabilir.
        final sutunlar = tumAnahtarlar.map(Uri.encodeComponent).join(',');
        final r = await http.post(
          Uri.parse('$_rest/$tablo?on_conflict=$uniqueAlan&columns=$sutunlar'),
          headers: _upsertH(uniqueAlan),
          body: jsonEncode(batch),
        ).timeout(const Duration(seconds: 30));
        if (r.statusCode >= 400) {
          hata += batch.length;
          sonStatusKodu = r.statusCode;
          final msg = '$tablo batch ${r.statusCode}: ${r.body.substring(0,r.body.length.clamp(0,150))}';
          if (!hatalar.contains(msg)) hatalar.add(msg);
        } else {
          basarili += batch.length;
        }
      } catch (e) {
        hata += batch.length;
        // Ham ağ/zaman aşımı istisnaları (SocketException/TimeoutException
        // vb.) statusKodu taşımaz — sonStatusKodu null kalır, bu da
        // BulutSonuc.tur'un bunu GEÇİCİ saymasını sağlar (doğru davranış).
        hatalar.add('$tablo batch hata: $e');
      }
    }
    return BulutSonuc(
        basarili: basarili,
        hata: hata,
        hataMesajlari: hatalar,
        sonStatusKodu: sonStatusKodu);
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
