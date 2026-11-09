// lib/servisler/cihaz_aktarim_birlestirici.dart
//
// Cihazdan cihaza (WiFi, QR/adres ile) veri aktarımının
// dışa/içe aktarım çekirdeği.
//
// 🔴 NEDEN YENİDEN YAZILDI (çoklu cihaz analizi, 2026-11-08): eski içe
// aktarım (SyncServisi._veriIcerAktar) satırların yerel `id`'sini silip
// ilişki sütunlarını (satis_kalem.satis_id, cari_hareket.cari_id,
// stok_hareket.urun_id …) GÖNDEREN cihazın yerel id'leriyle olduğu gibi
// yazıyordu. Yerel id'ler her cihazda farklı olduğundan satış kalemleri
// başka fişe, cari hareketleri başka müşteriye bağlanabiliyordu. Ayrıca
// ürün barkodla / cari kodla eşlenip eşleşen kaydın global_id'si
// gönderenin kimliğiyle eziliyor (bulutta çift kimlik), silmeler ve
// iptaller hiç aktarılmıyordu.
//
// Artık:
//  • Dışa aktarımda her ilişki sütunu için ebeveynin cihazlar arası
//    anahtarı (KolonHaritalama.ebeveynAnahtari — çoğunlukla global_id)
//    satırın `_fk` alanına yazılır.
//  • İçe aktarımda yerel ebeveyn id'si bu anahtardan bulunur; kayıtlar
//    YALNIZ global_id ile eşleşir; yazma işi bulut çekiminin AYNI test
//    edilmiş yoluyla yapılır (Veritabani.supaKayitlariEkle /
//    supaKayitlariGuncelle: kod/barkod/fiş no çakışma koruması, son yazan
//    kazanır, türetilmiş alanlar korunur, işlem verisi çakışma kaydı).
//  • Silinmiş kayıtlar da aktarılır, bulut çekimindeki gibi uygulanır.
//  • Sonunda bulut senkronuyla aynı mutabakat (stok, cari bakiye …) çalışır.
//  • `_fk` taşımayan eski sürüm verisi REDDEDİLİR — karışık sürümle
//    aktarım ilişkileri bozardı; kullanıcıya iki cihazı güncellemesi söylenir.
import 'package:sqflite/sqflite.dart';
import '../veri/database/veritabani.dart';
import 'kolon_haritalama.dart';
import 'log_servisi.dart';
import 'senkron_sonrasi_mutabakat.dart';
import 'supabase_sync_servisi.dart';

class CihazAktarimBirlestirici {
  CihazAktarimBirlestirici._();

  /// Aktarım biçimi sürümü. 4: ilişkiler `_fk` ile anahtar üzerinden taşınır.
  static const int surum = 4;

  /// Satırda ilişki anahtarlarının taşındığı alan.
  static const String fkAlani = '_fk';

  /// Aktarılan tablolar — bulut senkronuyla aynı küme ve sıra.
  static List<String> get tablolar => SupabaseSyncServisi.senkronTablolari;

  /// [tablo]'nun tüm satırları (silinmişler dahil — silme karşıya geçsin),
  /// her satıra ilişki anahtarları (`_fk`) eklenmiş olarak.
  static Future<List<Map<String, dynamic>>> tabloDisaAktar(String tablo) async {
    final db = await Veritabani().db;
    final List<Map<String, dynamic>> satirlar;
    try {
      satirlar = await db.query(tablo);
    } on DatabaseException catch (e) {
      // Bu cihazın şemasında olmayan (eski sürüm) tablo — aktarılacak veri yok.
      if (e.toString().contains('no such table')) return [];
      rethrow;
    }
    final anahtarlar = <String, Map<int, Object>>{};
    Future<Map<int, Object>> anahtarHaritasi(String parent) async =>
        anahtarlar[parent] ??= await _yerelIdAnahtarHaritasi(db, parent);

    final sonuc = <Map<String, dynamic>>[];
    for (final s in satirlar) {
      // Yıl sonu devir açılış satırı yalnız bu cihazda kalır — karşı cihaz
      // eski dönem hareketlerini zaten taşıyor, açılışla iki kez sayardı.
      if (KolonHaritalama.yerelKalirMi(tablo, s)) continue;
      final m = Map<String, dynamic>.from(s);
      final fk = <String, Object?>{};
      final harita = KolonHaritalama.satirFkHaritasi(tablo, m);
      if (harita != null) {
        for (final e in harita.entries) {
          final deger = m[e.key];
          if (deger == null) continue;
          final id = deger is int ? deger : int.tryParse(deger.toString());
          // Ebeveyn bu cihazda yoksa anahtar null gider; karşı tarafta
          // zorunlu ilişkiyse satır yetim sayılıp atlanır.
          fk[e.key] = id == null ? null : (await anahtarHaritasi(e.value))[id];
        }
      }
      m[fkAlani] = fk;
      sonuc.add(m);
    }
    return sonuc;
  }

  /// Tüm aktarım verisi (meta + tablolar).
  static Future<Map<String, dynamic>> tumunuDisaAktar({String? kaynak}) async {
    final data = <String, dynamic>{
      'meta': {
        'zaman': DateTime.now().toIso8601String(),
        'versiyon': surum,
        'kaynak': ?kaynak,
      },
    };
    for (final t in tablolar) {
      data[t] = await tabloDisaAktar(t);
    }
    return data;
  }

  /// Karşı cihazdan gelen veriyi bu cihaza birleştirir. Dönüş:
  /// basarili/eklenen/guncellenen/silinen/atlanan/hata_sayisi/hatalar/duzeltmeler.
  ///
  /// [sadeceTablolar] verilirse yalnız onlar işlenir.
  static Future<Map<String, dynamic>> iceAktar(
    Map<String, dynamic> data, {
    List<String>? sadeceTablolar,
  }) async {
    final eskiSurum = _eskiSurumTablosu(data);
    if (eskiSurum != null) {
      throw Exception('Karşı cihazdaki uygulama eski sürüm ($eskiSurum tablosu '
          'ilişki bilgisi taşımıyor). Veri bozulmasın diye aktarım yapılmadı — '
          'iki cihazı da güncelleyip tekrar deneyin.');
    }

    final db = await Veritabani().db;
    final islenecek = <String>[
      for (final t in tablolar)
        if (data.containsKey(t) && (sadeceTablolar == null || sadeceTablolar.contains(t))) t,
    ];
    var eklenen = 0, guncellenen = 0, silinen = 0, atlanan = 0;
    final hatalar = <String>[];
    final degisenTablolar = <String>{};

    for (final tablo in islenecek) {
      final satirlar = (data[tablo] as List?)?.cast<Map>() ?? const [];
      if (satirlar.isEmpty) continue;
      try {
        final kolonlar = await _kolonlar(db, tablo);
        final zorunlu = await _zorunluKolonlar(db, tablo);
        // Ebeveyn haritaları bu tablo için taze kurulur: aynı aktarımda
        // ÖNCE işlenen ebeveyn tabloların yeni satırları da bulunabilsin.
        final ebeveynHaritalari = <String, Map<String, int>>{};
        Future<Map<String, int>> ebeveyn(String parent) async =>
            ebeveynHaritalari[parent] ??= await _anahtarYerelIdHaritasi(db, parent);

        final yeni = <Map<String, dynamic>>[];
        final guncel = <Map<String, dynamic>>[];
        for (final ham in satirlar) {
          final gelenFk = (ham[fkAlani] as Map?) ?? const {};
          final m = Map<String, dynamic>.from(ham)
            ..remove(fkAlani)
            ..remove('id');
          if (kolonlar.isNotEmpty) m.removeWhere((k, _) => !kolonlar.contains(k));
          for (final k in m.keys.toList()) {
            if (m[k] is bool) m[k] = (m[k] as bool) ? 1 : 0;
          }

          var atla = false;
          final harita = KolonHaritalama.satirFkHaritasi(tablo, m);
          if (harita != null) {
            for (final e in harita.entries) {
              final kolon = e.key;
              if (m[kolon] == null) continue; // gönderende de boş
              final anahtar = gelenFk[kolon]?.toString();
              final yerelId = anahtar == null ? null : (await ebeveyn(e.value))[anahtar];
              if (yerelId != null) {
                m[kolon] = yerelId;
              } else if (zorunlu.contains(kolon)) {
                atla = true; // ebeveyni bu cihazda yok — yetim, yazılmaz
                break;
              } else {
                m.remove(kolon); // isteğe bağlı ilişki: yerel bağ korunur
              }
            }
          }
          if (atla) {
            atlanan++;
            continue;
          }

          final gid = m['global_id']?.toString();
          if (gid != null && gid.isNotEmpty) {
            final mevcut = await db.query(tablo,
                columns: ['id'], where: 'global_id = ?', whereArgs: [gid], limit: 1);
            if (mevcut.isNotEmpty) {
              if (SupabaseSyncServisi.silinmisMi(tablo, m)) {
                // Bulut çekimiyle aynı: yalnız silme sütunu uygulanır.
                final kolon = SupabaseSyncServisi.softDeleteKolonu(tablo)!;
                final deger = kolon == 'aktif'
                    ? 0
                    : (kolon == 'deleted_at'
                        ? (m['deleted_at'] ?? DateTime.now().toIso8601String())
                        : 1);
                await db.update(tablo, {kolon: deger},
                    where: 'global_id = ?', whereArgs: [gid]);
                silinen++;
                degisenTablolar.add(tablo);
              } else {
                guncel.add(m);
              }
              continue;
            }
            if (SupabaseSyncServisi.silinmisMi(tablo, m)) continue; // hiç gelmemiş, silinmiş
          }
          yeni.add(m);
        }

        if (yeni.isNotEmpty) {
          await Veritabani().supaKayitlariEkle(tablo, yeni);
          eklenen += yeni.length;
          degisenTablolar.add(tablo);
        }
        if (guncel.isNotEmpty) {
          await Veritabani().supaKayitlariGuncelle(tablo, guncel);
          guncellenen += guncel.length;
          degisenTablolar.add(tablo);
        }
      } catch (e, st) {
        // Bir tablonun hatası diğerlerini durdurmaz; hata görünür ve loglanır.
        LogServisi().hata('CihazAktarimBirlestirici.iceAktar($tablo)', hata: e, yigin: st);
        hatalar.add('$tablo: $e');
      }
    }

    final duzeltmeler = <String>[];
    if (degisenTablolar.isNotEmpty) {
      await SenkronSonrasiMutabakat.calistir(
          log: duzeltmeler.add, degisenTablolar: degisenTablolar);
    }

    return {
      'basarili': eklenen + guncellenen + silinen,
      'eklenen': eklenen,
      'guncellenen': guncellenen,
      'silinen': silinen,
      'atlanan': atlanan,
      'hata_sayisi': hatalar.length,
      'hatalar': hatalar.take(10).toList(),
      'duzeltmeler': duzeltmeler,
    };
  }

  /// İlişkili tablosu olup `_fk` taşımayan ilk tablo (eski sürüm verisi) ya da null.
  static String? _eskiSurumTablosu(Map<String, dynamic> data) {
    for (final t in tablolar) {
      final satirlar = data[t];
      if (satirlar is! List || satirlar.isEmpty) continue;
      final ilk = satirlar.first;
      if (ilk is Map && !ilk.containsKey(fkAlani)) return t;
    }
    return null;
  }

  /// parent: yerel id → cihazlar arası anahtar.
  static Future<Map<int, Object>> _yerelIdAnahtarHaritasi(Database db, String parent) async {
    final anahtar = KolonHaritalama.ebeveynAnahtari(parent);
    final h = <int, Object>{};
    for (final r in await db.query(parent, columns: ['id', anahtar])) {
      final id = r['id'] as int?;
      final a = r[anahtar];
      if (id != null && a != null && a.toString().isNotEmpty) h[id] = a;
    }
    return h;
  }

  /// parent: cihazlar arası anahtar → yerel id.
  static Future<Map<String, int>> _anahtarYerelIdHaritasi(Database db, String parent) async {
    final anahtar = KolonHaritalama.ebeveynAnahtari(parent);
    final h = <String, int>{};
    for (final r in await db.query(parent, columns: ['id', anahtar])) {
      final id = r['id'] as int?;
      final a = r[anahtar]?.toString();
      if (id != null && a != null && a.isNotEmpty) h[a] = id;
    }
    return h;
  }

  static Future<Set<String>> _kolonlar(Database db, String tablo) async => {
        for (final c in await db.rawQuery('PRAGMA table_info($tablo)'))
          if (c['name'] != null) c['name'].toString(),
      };

  static Future<Set<String>> _zorunluKolonlar(Database db, String tablo) async => {
        for (final c in await db.rawQuery('PRAGMA table_info($tablo)'))
          if ((c['notnull'] as int? ?? 0) == 1 && c['dflt_value'] == null && c['name'] != null)
            c['name'].toString(),
      };
}
