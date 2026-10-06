// test/servisler/bulut_sema_koruma_test.dart
//
// Bulut şema koruması: yerelde olup bulutta OLMAYAN sütun gönderimden
// ayıklanır (tablonun tamamı PGRST204 ile reddedilmesin), eksik sütunlar
// kaydedilir ve Veri Sağlığı'nda görünür; sütun bulutta varsa dokunulmaz.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_plus/servisler/bulut/supabase_saglayici.dart';
import 'package:market_plus/servisler/veri_sagligi_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Map<String, dynamic> _openapi() => {
      'definitions': {
        'markalar': {
          'properties': {
            'id': {}, 'global_id': {}, 'ad': {}, 'aktif': {}, 'last_updated': {},
          }
        },
        'iade_kalem': {
          'properties': {
            'id': {}, 'global_id': {}, 'iade_id': {}, 'urun_id': {}, 'urun_adi': {},
            'miktar': {}, 'birim_fiyat': {}, 'toplam': {}, 'last_updated': {},
          }
        },
      }
    };

void main() {
  group('saf yardımcılar', () {
    test('semaCoz: OpenAPI → tablo → sütun kümesi', () {
      final s = SupabaseSaglayici.semaCoz(_openapi());
      expect(s['markalar'], {'id', 'global_id', 'ad', 'aktif', 'last_updated'});
      expect(s['iade_kalem'], contains('toplam'));
      expect(SupabaseSaglayici.semaCoz({}), isEmpty);
    });

    test('sutunlariAyikla: bulutta olmayan sütunlar silinir, olanlar kalır', () {
      final sema = SupabaseSaglayici.semaCoz(_openapi());
      final kayit = <String, dynamic>{
        'global_id': 'g1', 'iade_id': 1, 'miktar': 2.0, 'toplam': 180.0,
        'iskonto_oran': 10.0, 'iskonto_tutar': 20.0,
      };
      final silinen = SupabaseSaglayici.sutunlariAyikla('iade_kalem', [kayit], sema);
      expect(silinen, {'iskonto_oran', 'iskonto_tutar'});
      expect(kayit.keys, containsAll(['global_id', 'iade_id', 'miktar', 'toplam']));
      expect(kayit.containsKey('iskonto_oran'), isFalse);
    });

    test('şema yok ya da tablo şemada yoksa HİÇBİR ŞEY silinmez (güvenli taraf)', () {
      final kayit = <String, dynamic>{'a': 1, 'b': 2};
      expect(SupabaseSaglayici.sutunlariAyikla('x', [kayit], null), isEmpty);
      expect(SupabaseSaglayici.sutunlariAyikla('x', [kayit], {'y': {'a'}}), isEmpty);
      expect(kayit.length, 2);
    });
  });

  group('gerçek upsert akışı (sahte HTTP)', () {
    test('bulutta olmayan sütun GÖNDERİLMEZ ve eksik listesine düşer; olanlar gider', () async {
      SupabaseSaglayici.eksikBulutSutunlari.clear();
      final istekler = <http.Request>[];
      final client = MockClient((req) async {
        istekler.add(req);
        if (req.method == 'GET' && req.url.path == '/rest/v1/') {
          return http.Response(jsonEncode(_openapi()), 200);
        }
        if (req.method == 'GET') return http.Response('[]', 200); // bulut daha yeni mi?
        return http.Response('', 201);
      });

      await http.runWithClient(() async {
        final s = const SupabaseSaglayici(url: 'https://proje.supabase.co', key: 'anahtar');
        await s.upsert(
          tablo: 'markalar',
          veri: {
            'global_id': 'g-1', 'ad': 'Ülker', 'aktif': 1,
            'last_updated': '2026-10-07T10:00:00Z',
            'yeni_sutun': 'x', // bulutta yok
          },
          uniqueAlan: 'global_id',
        );
      }, () => client);

      final post = istekler.firstWhere((r) => r.method == 'POST');
      final govde = (jsonDecode(post.body) as List).first as Map<String, dynamic>;
      expect(govde.containsKey('yeni_sutun'), isFalse, reason: 'bulutta olmayan sütun gönderilmemeli');
      expect(govde['ad'], 'Ülker');
      expect(post.url.queryParameters['columns'], isNot(contains('yeni_sutun')));
      expect(SupabaseSaglayici.eksikBulutSutunlari, contains('markalar.yeni_sutun'));
    });

    test('Veri Sağlığı "Bulut Şema Uyumu" eksik sütunu SARI gösterir', () async {
      final db = await TestVeritabani.olustur(); // gerçek veritabanına DOKUNMA
      Veritabani.testVeritabani = db;
      addTearDown(() => db.close());
      SupabaseSaglayici.eksikBulutSutunlari
        ..clear()
        ..add('iade_kalem.iskonto_oran');
      final k = (await VeriSagligiServisi().tumKontrolleriCalistir())
          .firstWhere((x) => x.id == 'bulut_sema');
      expect(k.durum, SaglikDurum.sari);
      expect(k.mesaj, contains('iade_kalem.iskonto_oran'));
      expect(k.mesaj, contains('supabase_tam_sema.sql'));
      SupabaseSaglayici.eksikBulutSutunlari.clear();
      final temiz = (await VeriSagligiServisi().tumKontrolleriCalistir())
          .firstWhere((x) => x.id == 'bulut_sema');
      expect(temiz.durum, SaglikDurum.yesil);
    });
  });
}
