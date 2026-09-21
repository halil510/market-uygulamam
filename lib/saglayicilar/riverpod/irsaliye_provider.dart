// lib/saglayicilar/riverpod/irsaliye_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../veri/database/veritabani.dart';

part 'irsaliye_provider.g.dart';

@riverpod
Future<List<Map<String, dynamic>>> irsaliyeListesi(IrsaliyeListesiRef ref) async {
  final db = await Veritabani().db;
  return db.rawQuery('''
    SELECT i.*, c.unvan as cari_adi FROM irsaliyeler i
    LEFT JOIN cari c ON i.cari_id = c.id
    ORDER BY i.tarih DESC LIMIT 100
  ''');
}
