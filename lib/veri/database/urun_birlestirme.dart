// lib/veri/database/urun_birlestirme.dart
//
// Aynı ürünün iki cihazda internetsizken ayrı ayrı açılması (çoklu cihaz
// analizi, 2026-11-08).
//
// ÖNCEDEN: senkronda gelen ürünün barkodu yereldeki başka bir ürünle
// çakışınca gelenin barkodu/kodu SİLİNİYORDU. Sonuç: her kasada biri
// barkodlu biri barkodsuz İKİ ürün; stok ikisine bölünüyor, barkod okutunca
// yalnız kendi kasanın ürünü bulunuyordu.
//
// ARTIK: aynı barkod gerçekten aynı ürünse (gerçek barkod — 8+ rakam — ya da
// aynı ad) ikisi BİRLEŞTİRİLİR. Hangisinin kalacağı her cihazda AYNI kuralla
// seçilir (küçük global_id — saatten/sıradan bağımsız), böylece tüm kasalar
// aynı sonuca yakınsar. Kopyaya bağlı satış/stok/iade… satırları kalan ürüne
// taşınır ve buluta gönderilir (kuyruk); kopya silinmiş olarak kalır.
// Birleştirilemeyen çakışmada (kısa/elle barkod + farklı ad) eski davranış
// sürer: gelenin çakışan alanı boşaltılır.
import 'package:sqflite/sqflite.dart';
import '../../servisler/bulut/sync_kuyruk_yazici.dart';
import '../../servisler/kolon_haritalama.dart';
import '../../servisler/log_servisi.dart';

/// (kopya ürünün global_id'si, kalan ürünün global_id'si)
typedef UrunBirlesmesi = (String kopyaGid, String hedefGid);

class UrunBirlestirme {
  UrunBirlestirme._();

  static String _adAnahtari(Object? ad) =>
      (ad?.toString() ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

  static bool _silinmis(Map<String, dynamic> u) =>
      u['is_deleted'] == 1 || u['is_deleted'] == true;

  /// Aynı barkodlu iki ürün aynı ürün sayılır mı?
  static bool birlestirilebilir(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (_silinmis(a) || _silinmis(b)) return false;
    final ba = a['barkod']?.toString().trim() ?? '';
    final bb = b['barkod']?.toString().trim() ?? '';
    if (ba.isEmpty || ba.toLowerCase() != bb.toLowerCase()) return false;
    final gercekBarkod = RegExp(r'^\d{8,}$').hasMatch(ba);
    return gercekBarkod || _adAnahtari(a['urun_adi']) == _adAnahtari(b['urun_adi']);
  }

  /// [aGid] kalan (hedef) ürün mü? Her cihazda aynı sonucu verir.
  static bool hedefMi(String aGid, String bGid) => aGid.compareTo(bGid) < 0;

  /// Kopya ürüne yazılacak alanlar: barkod/kod serbest kalır, ürün silinir.
  static Map<String, Object?> kopyaAlanlari(String zaman) =>
      {'barkod': null, 'kod': null, 'is_deleted': 1, 'aktif': 0, 'last_updated': zaman};

  /// Birleşmeleri uygular: kopyaya bağlı satırları hedefe taşır, kopyayı
  /// silinmiş yapar; değişen her satır senkron kuyruğuna yazılır (diğer
  /// cihazlar ve bulut da aynı sonucu alsın). Döner: taşınan satır sayısı.
  static Future<int> uygula(Database db, List<UrunBirlesmesi> birlesmeler) async {
    var tasinan = 0;
    for (final (kopyaGid, hedefGid) in birlesmeler) {
      final k = await db.query('urunler',
          columns: ['id'], where: 'global_id = ?', whereArgs: [kopyaGid], limit: 1);
      final h = await db.query('urunler',
          columns: ['id'], where: 'global_id = ?', whereArgs: [hedefGid], limit: 1);
      if (k.isEmpty || h.isEmpty) {
        LogServisi().uyari('Ürün birleştirme atlandı: kopya ($kopyaGid) ya da '
            'hedef ($hedefGid) bu cihazda yok');
        continue;
      }
      final kopyaId = k.first['id'] as int;
      final hedefId = h.first['id'] as int;
      if (kopyaId == hedefId) continue;
      tasinan += await db.transaction((txn) async {
        final zaman = DateTime.now().toIso8601String();
        var n = 0;
        for (final ref in _urunReferanslari) {
          final (tablo, kolon) = ref;
          final List<Map<String, Object?>> satirlar;
          try {
            satirlar = await txn.query(tablo, where: '$kolon = ?', whereArgs: [kopyaId]);
          } on DatabaseException catch (e) {
            if (e.toString().contains('no such table')) continue; // eski şema
            rethrow;
          }
          for (final s in satirlar) {
            final degisen = <String, Object?>{
              kolon: hedefId,
              if (s.containsKey('last_updated')) 'last_updated': zaman,
            };
            // Hedefte aynı benzersiz satır zaten varsa (ör. aynı şubenin
            // sube_urun satırı) taşınmaz — kopyada kalır, zararsızdır.
            final guncellendi = await txn.update(tablo, degisen,
                where: 'id = ?', whereArgs: [s['id']],
                conflictAlgorithm: ConflictAlgorithm.ignore);
            if (guncellendi == 0) continue;
            n++;
            if (KolonHaritalama.uniqueAlan(tablo) != null) {
              await SyncKuyrukYazici.ekleTxn(txn,
                  tablo: tablo, veri: {...s, ...degisen});
            }
          }
        }
        await txn.update('urunler', kopyaAlanlari(zaman),
            where: 'id = ?', whereArgs: [kopyaId]);
        final kopyaSatir = await txn.query('urunler',
            where: 'id = ?', whereArgs: [kopyaId], limit: 1);
        if (kopyaSatir.isNotEmpty) {
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'urunler', veri: Map<String, dynamic>.from(kopyaSatir.first));
        }
        return n;
      });
      LogServisi().bilgi('Aynı ürün iki cihazda açılmıştı — birleştirildi: '
          '$kopyaGid → $hedefGid');
    }
    return tasinan;
  }

  /// urunler'e işaret eden (tablo, sütun) çiftleri — tek kaynak FK haritası.
  static List<(String, String)> get _urunReferanslari => [
        for (final t in KolonHaritalama.fkHaritasi.entries)
          for (final k in t.value.entries)
            if (k.value == 'urunler' && t.key != 'urunler') (t.key, k.key),
      ];
}
