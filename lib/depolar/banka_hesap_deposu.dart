// lib/depolar/banka_hesap_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../modeller/banka_hesap_model.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';

class BankaHesapDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(BankaHesapModel hesap) async {
    try {
      final db = await _d;
      final m = hesap.toMap();
      m.remove('id');
      m['global_id'] ??= const Uuid().v4();
      m['last_updated'] = DateTime.now().toIso8601String();
      final id = await db.insert('banka_hesaplar', m);
      final satir = await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('banka_hesaplar', Map<String, dynamic>.from(satir.first));
      }
      return id;
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> guncelle(BankaHesapModel hesap) async {
    try {
      final db = await _d;
      final m = hesap.toMap();
      m['last_updated'] = DateTime.now().toIso8601String();
      await db.update('banka_hesaplar', m, where: 'id = ?', whereArgs: [hesap.id]);
      // 🔴 Bkz. BankaDeposu.guncelle() içindeki aynı not — bu tablo da
      // sonradan senkron sistemine eklendi, eski kayıtlarda global_id
      // NULL olabilir.
      final mevcut = await db.query('banka_hesaplar', columns: ['global_id'], where: 'id = ?', whereArgs: [hesap.id], limit: 1);
      if (mevcut.isNotEmpty && (mevcut.first['global_id'] == null || (mevcut.first['global_id'] as String).isEmpty)) {
        await db.update('banka_hesaplar', {'global_id': const Uuid().v4()}, where: 'id = ?', whereArgs: [hesap.id]);
      }
      final satir = await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesap.id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('banka_hesaplar', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<BankaHesapModel>> tumunuGetir({int? bankaId}) async {
    try {
      final db = await _d;
      final where = bankaId != null ? 'banka_id = ? AND aktif = 1' : 'aktif = 1';
      final args = bankaId != null ? [bankaId] : null;
      final rows = await db.query('banka_hesaplar',
          where: where, whereArgs: args, orderBy: 'hesap_adi ASC');
      return rows.map(BankaHesapModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.tumunuGetir', hata: e, yigin: st);
      rethrow; // hata artık gizlenmiyor
    }
  }

  Future<BankaHesapModel?> idileGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.query('banka_hesaplar',
          where: 'id = ? AND aktif = 1', whereArgs: [id]);
      if (rows.isEmpty) return null;
      return BankaHesapModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.idileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> bakiyeGuncelle(int id, double yeniBakiye) async {
    try {
      final db = await _d;
      await db.update('banka_hesaplar',
          {'bakiye': yeniBakiye, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [id]);
      final satir = await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('banka_hesaplar', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.bakiyeGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Veri Sağlığı Merkezi (protokol §13): hesabın 'bakiye' alanı, KENDİ
  /// hareket geçmişinin son 'sonraki_bakiye' değeriyle uyumlu mu?
  ///
  /// NOT: Cari/stok mutabakatının aksine banka için SIFIRDAN toplam
  /// (SUM) hesaplamıyoruz — çünkü hesap açılışındaki başlangıç bakiyesi
  /// ayrı bir sütunda saklanmıyor (mevcut tasarım). Bunun yerine daha
  /// dar ama güvenli bir kontrol yapıyoruz: normal akışta her hareket
  /// (BankaHareketDeposu.ekleTxn) 'bakiye'yi kendi 'sonraki_bakiye'siyle
  /// EŞ ZAMANLI günceller — ikisi arasında bir sapma varsa, hesap
  /// hareketleri atlanarak (ör. elle düzenleme) değiştirilmiş demektir.
  Future<int> bakiyeUyumsuzlukSayisi() async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(_uyumsuzHesaplarSql);
      return rows.length;
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.bakiyeUyumsuzlukSayisi', hata: e, yigin: st);
      return 0;
    }
  }

  Future<int> bakiyeMutabakatYap() async {
    try {
      final db = await _d;
      final uyumsuzlar = await db.rawQuery(_uyumsuzHesaplarSql);
      final now = DateTime.now().toIso8601String();
      for (final r in uyumsuzlar) {
        final dogru = (r['dogru_bakiye'] as num?)?.toDouble() ?? 0;
        await db.update('banka_hesaplar',
            {'bakiye': dogru, 'kullanilabilir_bakiye': dogru, 'last_updated': now},
            where: 'id = ?', whereArgs: [r['id']]);
      }
      return uyumsuzlar.length;
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.bakiyeMutabakatYap', hata: e, yigin: st);
      rethrow;
    }
  }

  static const _uyumsuzHesaplarSql = '''
    SELECT h.id, (
      SELECT bh2.sonraki_bakiye FROM banka_hareketler bh2
      WHERE bh2.banka_hesap_id = h.id ORDER BY bh2.tarih DESC, bh2.id DESC LIMIT 1
    ) as dogru_bakiye
    FROM banka_hesaplar h
    WHERE h.aktif = 1
      AND EXISTS (SELECT 1 FROM banka_hareketler bh WHERE bh.banka_hesap_id = h.id)
      AND ABS(h.bakiye - (
        SELECT bh2.sonraki_bakiye FROM banka_hareketler bh2
        WHERE bh2.banka_hesap_id = h.id ORDER BY bh2.tarih DESC, bh2.id DESC LIMIT 1
      )) > 0.01
  ''';
}