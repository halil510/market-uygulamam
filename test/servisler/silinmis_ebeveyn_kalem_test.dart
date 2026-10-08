// test/servisler/silinmis_ebeveyn_kalem_test.dart
//
// Canlı bulgu 2026-10-08: yeni kurulan masaüstünde "Bulut Al" her seferinde
// "satis_kalem: 2 satırın ebeveyni henüz yok — sonraki turda yeniden
// denenecek" diyordu. Kalemler bulutta SİLİNMİŞ iki satışa aitti; satış
// yeni cihaza hiç eklenmediği için kalemler sonsuza dek bekliyordu.
// Ebeveyn bulutta silinmişse kalem kalıcı yetimdir: sessizce atlanır.
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

  Future<SyncSonuc> cek({required bool ebeveynSilinmis}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final urunGid = await db.query('urunler', columns: ['id', 'global_id']);
    final client = MockClient((req) async {
      final yol = req.url.path;
      final q = Uri.decodeComponent(req.url.query);
      if (yol.endsWith('/satis_kalem') && !q.contains('select=id,global_id')) {
        return http.Response(
            jsonEncode([
              {
                'id': 900, 'global_id': 'kalem-silinmis', 'satis_id': 292,
                'urun_id': v.id['urun0'], 'urun_adi': 'A', 'miktar': 1.0,
                'birim_fiyat': 60.0, 'toplam_tutar': 60.0, 'last_updated': now,
                'sunucu_zamani': now,
              }
            ]),
            200);
      }
      if (yol.endsWith('/satislar') && q.contains('id=eq.292')) {
        return http.Response(
            jsonEncode([{'id': 292, 'is_deleted': ebeveynSilinmis}]), 200);
      }
      if (yol.endsWith('/satislar') && q.contains('select=id')) {
        return http.Response(jsonEncode([{'id': 292, 'global_id': 'satis-g292'}]), 200);
      }
      if (yol.endsWith('/urunler') && q.contains('select=id')) {
        return http.Response(
            jsonEncode([for (final u in urunGid) {'id': u['id'], 'global_id': u['global_id']}]), 200);
      }
      return http.Response('[]', 200);
    });
    return http.runWithClient(
        () => SupabaseSyncServisi.yerelBuluttanAl(sadeceTablolar: {'satis_kalem'}),
        () => client);
  }

  test('ebeveyn satış bulutta silinmişse kalem sessizce atlanır (uyarı yok)', () async {
    final sonuc = await cek(ebeveynSilinmis: true);
    expect(sonuc.hatalar.where((h) => h.contains('ebeveyn')), isEmpty);
    final n = (await db.rawQuery(
            "SELECT COUNT(*) n FROM satis_kalem WHERE global_id = 'kalem-silinmis'"))
        .first['n'];
    expect(n, 0);
  });

  test('ebeveyn bulutta duruyorsa (henüz gelmedi) yeniden denenir', () async {
    final sonuc = await cek(ebeveynSilinmis: false);
    expect(sonuc.hatalar.any((h) => h.contains('ebeveyni henüz yok')), isTrue);
  });
}
