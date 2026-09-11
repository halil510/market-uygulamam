// lib/depolar/kredi_karti_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../modeller/kredi_karti_model.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';

class KrediKartiDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(KrediKartiModel kart) async {
    try {
      final db = await _d;
      final m = kart.toMap();
      m.remove('id');
      m['global_id'] ??= const Uuid().v4();
      // 🔴 Derin analizde bulundu (gerçek Supabase hatasından): bazı
      // kayıtlarda kart_no_maskeli NULL/boş kalıp senkronun sürekli
      // "NOT NULL ihlali" ile başarısız olmasına yol açıyordu. Model
      // bunu normalde önlese de (maskele() asla null döndürmez), hangi
      // yoldan gelirse gelsin (ör. eski/farklı bir çağrı) bu alanın hiç
      // boş kalmamasını burada da garanti ediyoruz.
      if (m['kart_no_maskeli'] == null || (m['kart_no_maskeli'] as String).isEmpty) {
        m['kart_no_maskeli'] = '**** **** **** ????';
      }
      final id = await db.insert('kredi_kartlari', m);
      final satir = await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('kredi_kartlari', Map<String, dynamic>.from(satir.first));
      }
      return id;
    } catch (e, st) {
      LogServisi().hata('KrediKartiDeposu.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> guncelle(KrediKartiModel kart) async {
    try {
      final db = await _d;
      final m = kart.toMap();
      m['last_updated'] = DateTime.now().toIso8601String();
      if (m['kart_no_maskeli'] == null || (m['kart_no_maskeli'] as String).isEmpty) {
        m['kart_no_maskeli'] = '**** **** **** ????';
      }
      await db.update('kredi_kartlari', m, where: 'id = ?', whereArgs: [kart.id]);
      // 🔴 Bkz. BankaDeposu.guncelle() içindeki aynı not — kredi kartı
      // kaydının kendisi de bu tabloya sonradan senkron eklendiğinde
      // henüz oluşturulmuşsa global_id'siz kalmış olabilir.
      final mevcut = await db.query('kredi_kartlari', columns: ['global_id'], where: 'id = ?', whereArgs: [kart.id], limit: 1);
      if (mevcut.isNotEmpty && (mevcut.first['global_id'] == null || (mevcut.first['global_id'] as String).isEmpty)) {
        await db.update('kredi_kartlari', {'global_id': const Uuid().v4()}, where: 'id = ?', whereArgs: [kart.id]);
      }
      final satir = await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kart.id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('kredi_kartlari', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('KrediKartiDeposu.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu): Bu depoda hiç sil()
  // fonksiyonu YOKTU — bir kredi kartı eklendikten sonra ASLA
  // silinemiyor veya devre dışı bırakılamıyordu (ne UI'da bir buton
  // ne bir toggle vardı). Tablo 'is_deleted' değil 'aktif' sütununu
  // kullanıyor (bankalar tablosuyla aynı desen) — gerçek silme yerine
  // deaktivasyon kullanılıyor çünkü kredi_karti_hareket tablosu bu
  // karta FK ile bağlı (geçmiş işlem kayıtlarını bozmamak için).
  // tumunuGetir() zaten 'aktif = 1' filtrelediği için, bu işlem
  // sonrası kart standart listeden otomatik olarak kayboluyor.
  Future<void> sil(int id) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      await db.update('kredi_kartlari', {'aktif': 0, 'last_updated': now},
          where: 'id = ?', whereArgs: [id]);
      final satir = await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('kredi_kartlari', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('KrediKartiDeposu.sil', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<KrediKartiModel>> tumunuGetir({int? bankaId}) async {
    try {
      final db = await _d;
      final where = bankaId != null ? 'banka_id = ? AND aktif = 1' : 'aktif = 1';
      final args = bankaId != null ? [bankaId] : null;
      final rows = await db.query('kredi_kartlari',
          where: where, whereArgs: args, orderBy: 'kart_adi ASC');
      return rows.map(KrediKartiModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('KrediKartiDeposu.tumunuGetir', hata: e, yigin: st);
      rethrow; // hata artık gizlenmiyor — UI tarafında görünür olacak
    }
  }

  Future<KrediKartiModel?> idileGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.query('kredi_kartlari',
          where: 'id = ? AND aktif = 1', whereArgs: [id]);
      if (rows.isEmpty) return null;
      return KrediKartiModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('KrediKartiDeposu.idileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  /// ÖNCEDEN bu fonksiyon mutlak bir "kullanilanLimit" değeri alıp
  /// doğrudan yazıyordu — çağıran kod (kart.kullanilanLimit + tutar
  /// gibi) önce OKUYUP hesaplıyordu, bu da borçta/stokta bulup
  /// düzelttiğim AYNI "kayıp güncelleme" riskini taşıyordu (2 cihazdan
  /// aynı karta aynı anda işlem girilirse biri kaybolabilirdi). Artık
  /// bu fonksiyon bir DELTA (değişim miktarı, harcama için pozitif,
  /// ödeme için negatif) alıyor, kendi hareket kaydını oluşturup
  /// gerçek toplamdan hesaplıyor.
  Future<void> limitDegistir(int id, double delta, {String aciklama = ''}) async {
    try {
      final db = await _d;
      int? hareketId;
      await db.transaction((txn) async {
        hareketId = await limitDegistirTxn(txn, id, delta, aciklama: aciklama);
      });
      if (hareketId == null) return; // kart bulunamadı

      // 🔴 Derin analizde bulundu: bu fonksiyon hiçbir zaman BulutManager
      // çağırmıyordu — kredi kartı hareketleri ve limit güncellemeleri
      // sadece manuel "Buluta Gönder" ile senkronize oluyordu.
      final hareketSatir = await db.query('kredi_karti_hareket', where: 'id = ?', whereArgs: [hareketId], limit: 1);
      if (hareketSatir.isNotEmpty) {
        BulutManager().upsert('kredi_karti_hareket', Map<String, dynamic>.from(hareketSatir.first));
      }
      final kartSatir = await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [id], limit: 1);
      if (kartSatir.isNotEmpty) {
        BulutManager().upsert('kredi_kartlari', Map<String, dynamic>.from(kartSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('KrediKartiDeposu.limitDegistir', hata: e, yigin: st);
      rethrow;
    }
  }

  /// [limitDegistir] ile aynı mantık, VERİLEN transaction içinde çalışır.
  /// Kart bulunamazsa null döner (sessizce atlar — önceki davranışla aynı).
  Future<int?> limitDegistirTxn(dynamic txn, int id, double delta, {String aciklama = ''}) async {
    final kartRows = await txn.query('kredi_kartlari', where: 'id = ? AND aktif = 1', whereArgs: [id]);
    if (kartRows.isEmpty) return null;
    final kart = KrediKartiModel.fromMap(kartRows.first);

    final hareketId = await txn.insert('kredi_karti_hareket', {
      'global_id': const Uuid().v4(),
      'kredi_karti_id': id,
      'tutar': delta.abs(),
      'yon': delta >= 0 ? 'harcama' : 'odeme',
      'aciklama': aciklama,
      'tarih': DateTime.now().toIso8601String(),
      'last_updated': DateTime.now().toIso8601String(),
    });

    final toplamRows = await txn.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN yon = 'harcama' THEN tutar ELSE -tutar END), 0) as toplam
      FROM kredi_karti_hareket WHERE kredi_karti_id = ? AND is_deleted = 0
    ''', [id]);
    final yeniKullanilan = (toplamRows.first['toplam'] as num?)?.toDouble() ?? 0;
    final kalan = (kart.kartLimit - yeniKullanilan).clamp(0, double.infinity);
    await txn.update('kredi_kartlari', {
      'kullanilan_limit': yeniKullanilan,
      'kalan_limit': kalan,
      'last_updated': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);

    return hareketId;
  }

  Future<double> _kullanilanLimitHesapla(int kartId) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN yon = 'harcama' THEN tutar ELSE -tutar END), 0) as toplam
      FROM kredi_karti_hareket WHERE kredi_karti_id = ? AND is_deleted = 0
    ''', [kartId]);
    return (rows.first['toplam'] as num?)?.toDouble() ?? 0;
  }

  /// Senkronizasyon sonrası çağrılması önerilir — her kartın
  /// "kullanilan_limit"ini kendi hareketlerinin gerçek toplamından
  /// yeniden hesaplar (stok/borç mutabakatıyla aynı mimari).
  Future<int> limitMutabakatYap() async {
    try {
      final db = await _d;
      final kartlar = await db.query('kredi_kartlari', where: 'aktif = 1');
      var duzeltilen = 0;
      for (final k in kartlar) {
        final kartId = k['id'] as int;
        final eskiKullanilan = (k['kullanilan_limit'] as num?)?.toDouble() ?? 0;
        final dogruKullanilan = await _kullanilanLimitHesapla(kartId);
        if ((eskiKullanilan - dogruKullanilan).abs() > 0.01) {
          final kartLimit = (k['kartlimit'] as num?)?.toDouble() ?? 0;
          final kalan = (kartLimit - dogruKullanilan).clamp(0, double.infinity);
          await db.update('kredi_kartlari', {
            'kullanilan_limit': dogruKullanilan,
            'kalan_limit': kalan,
            'last_updated': DateTime.now().toIso8601String(),
          }, where: 'id = ?', whereArgs: [kartId]);
          final satir = await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId], limit: 1);
          if (satir.isNotEmpty) {
            BulutManager().upsert('kredi_kartlari', Map<String, dynamic>.from(satir.first));
          }
          duzeltilen++;
        }
      }
      if (duzeltilen > 0) {
        LogServisi().bilgi('Kredi kartı limit mutabakatı: $duzeltilen kart düzeltildi');
      }
      return duzeltilen;
    } catch (e, st) {
      LogServisi().hata('KrediKartiDeposu.limitMutabakatYap', hata: e, yigin: st);
      return 0;
    }
  }

  Future<void> limitGuncelle(int id, double kullanilanLimit) async {
    try {
      final db = await _d;
      final kart = await idileGetir(id);
      if (kart == null) return;
      final kalan = (kart.kartLimit - kullanilanLimit).clamp(0, double.infinity);  // <-- DÜZELTİLDİ
      await db.update('kredi_kartlari', {
        'kullanilan_limit': kullanilanLimit,
        'kalan_limit': kalan,
        'last_updated': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [id]);
      final satir = await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('kredi_kartlari', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('KrediKartiDeposu.limitGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }
}