// test/servisler/iade_yarim_kalem_tamamlama_test.dart
//
// Gerçek olay: iade başka cihazda kalem kalem yüklenirken çekildi, diğer
// masaüstü yalnız ilk 6 kalemi aldı (970,03) — başlık 2086,59 idi ve imleç
// ilerlediği için kalanlar hiç inmedi. Artık kalem toplamı başlıkla
// uyuşmayan iadenin kalemleri imleçten bağımsız tamamlanır.
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/supabase_sync_servisi.dart';
import '../robot/robot_ortam.dart';

void main() {
  late Database db;
  late RobotVeri v;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'mp_supabase_url_secure': 'https://proje.supabase.co',
      'mp_supabase_key_secure': 'sb_secret_testanahtar1234567890',
    });
    await RobotOrtam.hazirla();
    db = await RobotOrtam.veritabaniAc();
    v = await RobotOrtam.tohumla(db);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await db.close();
  });

  test('başlık 100 ama yerelde tek kalem (40) → bulutun kalan kalemleri indirilir', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    final iadeId = await db.insert('iade', {
      'global_id': 'iade-g1', 'fis_no': 'IAD-X', 'toplam_tutar': 100.0,
      'durum': 'tamamlandi', 'tarih': now, 'last_updated': now,
    });
    await db.insert('iade_kalem', {
      'global_id': 'kalem-1', 'iade_id': iadeId, 'urun_id': v.id['urun0'],
      'urun_adi': 'A', 'miktar': 1.0, 'birim_fiyat': 40.0, 'toplam': 40.0, 'last_updated': now,
    });

    Map<String, dynamic> kalem(String g, num toplam, int urunId) => {
          'id': g.hashCode.abs() % 100000, 'global_id': g, 'iade_id': 500,
          'urun_id': urunId, 'urun_adi': 'A', 'miktar': 1.0, 'birim_fiyat': toplam,
          'toplam': toplam, 'iskonto_oran': 5.0, 'iskonto_tutar': 1.0, 'last_updated': now,
        };
    // bulut urunler eşlemesi: yerel global_id'ler, bulut id = yerel id
    final urunGid = await db.query('urunler', columns: ['id', 'global_id']);
    final client = MockClient((req) async {
      final yol = req.url.path;
      final q = req.url.query;
      if (yol.endsWith('/iade_kalem') && q.contains('iade_id=in.(500)')) {
        return http.Response(
            jsonEncode([
              kalem('kalem-1', 40, v.id['urun0']!),
              kalem('kalem-2', 30, v.id['urun0']!),
              kalem('kalem-3', 30, v.id['urun0']!),
            ]),
            200);
      }
      if (yol.endsWith('/iade') && q.contains('select=id')) {
        return http.Response(jsonEncode([{'id': 500, 'global_id': 'iade-g1'}]), 200);
      }
      if (yol.endsWith('/urunler') && q.contains('select=id')) {
        return http.Response(
            jsonEncode([for (final u in urunGid) {'id': u['id'], 'global_id': u['global_id']}]), 200);
      }
      return http.Response('[]', 200);
    });

    await http.runWithClient(
        () => SupabaseSyncServisi.yerelBuluttanAl(sadeceTablolar: {'iade'}), () => client);

    final toplam = (await db.rawQuery(
            'SELECT SUM(toplam) t, COUNT(*) n FROM iade_kalem WHERE iade_id = ?', [iadeId]))
        .first;
    expect(toplam['n'], 3, reason: 'eksik 2 kalem tamamlanmalı');
    expect((toplam['t'] as num).toDouble(), closeTo(100.0, 0.001));
  });
}
