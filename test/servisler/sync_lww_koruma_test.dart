// test/servisler/sync_lww_koruma_test.dart
//
// Kuyruktaki ESKİ görüntünün buluttaki DAHA YENİ kaydı ezmemesi:
// saf mantık (SyncLwwKoruma) + SupabaseSaglayici.topluUpsert HTTP akışı.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_plus/servisler/bulut/supabase_saglayici.dart';
import 'package:market_plus/servisler/bulut/sync_lww_koruma.dart';

Map<String, dynamic> _kayit(String gid, String lu, {String ad = 'x'}) =>
    {'global_id': gid, 'urun_adi': ad, 'last_updated': lu};

void main() {
  group('SyncLwwKoruma (saf mantık)', () {
    test('bulut KESİN yeniyse atlanır; eşit ya da eskiyse gönderilir', () {
      final eski = _kayit('a', '2026-09-28T10:00:00.000Z');
      final esit = _kayit('b', '2026-09-28T10:00:00.000Z');
      final yeni = _kayit('c', '2026-09-28T10:00:01.000Z');
      final atlanan = SyncLwwKoruma.bulutuKesinDahaYeniOlanlar(
        kayitlar: [eski, esit, yeni],
        uniqueAlan: 'global_id',
        bulutZamanlari: {
          'a': DateTime.utc(2026, 9, 28, 10, 0, 5),
          'b': DateTime.utc(2026, 9, 28, 10, 0, 0),
          'c': DateTime.utc(2026, 9, 28, 10, 0, 0),
        },
      );
      expect(atlanan.length, 1);
      expect(atlanan.contains(eski), isTrue);
    });

    test('bulutta olmayan / zamanı bilinmeyen / yerel zamanı boş satır gönderilir', () {
      final yok = _kayit('yok', '2026-09-28T10:00:00Z');
      final zamansiz = {'global_id': 'z', 'last_updated': null};
      final bozuk = {'global_id': 'b', 'last_updated': 'bozuk'};
      final anahtarsiz = {'urun_adi': 'x', 'last_updated': '2026-09-28T10:00:00Z'};
      final atlanan = SyncLwwKoruma.bulutuKesinDahaYeniOlanlar(
        kayitlar: [yok, zamansiz, bozuk, anahtarsiz],
        uniqueAlan: 'global_id',
        bulutZamanlari: {'z': DateTime.utc(2030), 'b': DateTime.utc(2030)},
      );
      expect(atlanan, isEmpty);
    });

    test('saat dilimi farklı yazımlar aynı ana göre karşılaştırılır', () {
      final k = _kayit('a', '2026-09-28T13:00:00+03:00'); // = 10:00Z
      final atlanan = SyncLwwKoruma.bulutuKesinDahaYeniOlanlar(
        kayitlar: [k],
        uniqueAlan: 'global_id',
        bulutZamanlari: {'a': DateTime.parse('2026-09-28T10:00:00.5+00:00')},
      );
      expect(atlanan.contains(k), isTrue);
    });

    test('inListesi: tırnak, ters bölü, virgül ve parantez güvenle kaçırılır', () {
      expect(SyncLwwKoruma.inListesi(['a', 'b,c', 'd)e']), '("a","b,c","d)e")');
      expect(SyncLwwKoruma.inListesi([r'q"r', r'x\y']), r'("q\"r","x\\y")');
    });

    test('zamanHaritasi: geçersiz satırları yok sayar', () {
      final h = SyncLwwKoruma.zamanHaritasi([
        {'global_id': 'a', 'last_updated': '2026-09-28T10:00:00+00:00'},
        {'global_id': 'b', 'last_updated': null},
        'çöp',
        {'last_updated': '2026-09-28T10:00:00+00:00'},
      ], 'global_id');
      expect(h.keys, ['a']);
      expect(h['a'], DateTime.utc(2026, 9, 28, 10));
    });
  });

  group('SupabaseSaglayici.topluUpsert (HTTP akışı)', () {
    const saglayici = SupabaseSaglayici(url: 'https://x.supabase.co', key: 'k');

    /// [bulut]: {global_id: last_updated} — GET'e verilecek bulut durumu.
    /// [gonderilenler] POST gövdelerindeki global_id'leri toplar.
    Future<BulutSonucOzeti> calistir(
      List<Map<String, dynamic>> veriler, {
      required Map<String, String> bulut,
      int getDurum = 200,
      bool getAtar = false,
    }) async {
      final gonderilen = <String>[];
      final istekler = <http.Request>[];
      final client = MockClient((req) async {
        // Şema koruması (OpenAPI okuma) veri sorgusu değildir: sayıma girmez,
        // şema alınamamış gibi davranılır (koruma devre dışı → eski akış).
        if (req.method == 'GET' && req.url.path == '/rest/v1/') {
          return http.Response('', 404);
        }
        istekler.add(req);
        if (req.method == 'GET') {
          if (getAtar) throw http.ClientException('ağ yok');
          if (getDurum != 200) return http.Response('hata', getDurum);
          final satirlar = bulut.entries
              .map((e) => {'global_id': e.key, 'last_updated': e.value})
              .toList();
          return http.Response(jsonEncode(satirlar), 200);
        }
        for (final s in jsonDecode(req.body) as List) {
          gonderilen.add((s as Map)['global_id'] as String);
        }
        return http.Response('', 201);
      });
      final sonuc = await http.runWithClient(
        () => saglayici.topluUpsert(
            tablo: 'urunler', veriler: veriler, uniqueAlan: 'global_id'),
        () => client,
      );
      return BulutSonucOzeti(sonuc.basarili, sonuc.hata, gonderilen, istekler);
    }

    test('bulutta daha yeni olan atlanır, diğerleri gönderilir; hepsi başarılı sayılır', () async {
      final o = await calistir(
        [
          _kayit('eski', '2026-09-28T10:00:00.000Z', ad: 'eski görüntü'),
          _kayit('taze', '2026-09-28T10:00:10.000Z'),
          _kayit('yeni', '2026-09-28T10:00:00.000Z'),
        ],
        bulut: {
          'eski': '2026-09-28T10:05:00+00:00', // bulut yerelden yeni
          'taze': '2026-09-28T10:00:00+00:00', // yerel bulutdan yeni
        },
      );
      expect(o.gonderilen, ['taze', 'yeni']);
      expect(o.basarili, 3); // atlanan da kuyruktan düşer
      expect(o.hata, 0);
    });

    test('hepsi eskiyse hiç POST atılmaz', () async {
      final o = await calistir(
        [_kayit('a', '2026-09-28T10:00:00Z'), _kayit('b', '2026-09-28T10:00:00Z')],
        bulut: {'a': '2026-09-28T11:00:00+00:00', 'b': '2026-09-28T11:00:00+00:00'},
      );
      expect(o.istekler.where((r) => r.method == 'POST'), isEmpty);
      expect(o.basarili, 2);
      expect(o.hata, 0);
    });

    test('doğrulama isteği HTTP hatası verirse (fail-open) hepsi gönderilir', () async {
      final o = await calistir(
        [_kayit('a', '2026-09-28T10:00:00Z')],
        bulut: {'a': '2030-01-01T00:00:00+00:00'},
        getDurum: 400, // ör. tabloda last_updated yok
      );
      expect(o.gonderilen, ['a']);
    });

    test('doğrulama isteği ağ hatasıyla düşerse (fail-open) hepsi gönderilir', () async {
      final o = await calistir(
        [_kayit('a', '2026-09-28T10:00:00Z')],
        bulut: {'a': '2030-01-01T00:00:00+00:00'},
        getAtar: true,
      );
      expect(o.gonderilen, ['a']);
    });

    test('doğrulama sorgusu in.(...) filtresini tırnaklı ve kodlanmış gönderir', () async {
      final o = await calistir(
        [_kayit('g-1', '2026-09-28T10:00:00Z'), _kayit('g-2', '2026-09-28T10:00:00Z')],
        bulut: {},
      );
      final get = o.istekler.firstWhere((r) => r.method == 'GET');
      expect(get.url.queryParameters['select'], 'global_id,last_updated');
      expect(get.url.queryParameters['global_id'], 'in.("g-1","g-2")');
    });

    test('50\'den fazla anahtar parçalara bölünerek sorgulanır', () async {
      final veriler = [
        for (var i = 0; i < 120; i++) _kayit('g$i', '2026-09-28T10:00:00Z'),
      ];
      final o = await calistir(veriler, bulut: {});
      expect(o.istekler.where((r) => r.method == 'GET').length, 3);
      expect(o.gonderilen.length, 120);
    });
  });
}

class BulutSonucOzeti {
  final int basarili;
  final int hata;
  final List<String> gonderilen;
  final List<http.Request> istekler;
  BulutSonucOzeti(this.basarili, this.hata, this.gonderilen, this.istekler);
}
