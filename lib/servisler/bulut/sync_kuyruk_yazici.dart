// lib/servisler/bulut/sync_kuyruk_yazici.dart
//
// MASTER ERP DEEP AUDIT — Madde 5 sertleştirmesi: iş verisi (satış,
// stok, cari, kasa hareketi vb.) yazılırken senkron kuyruğu kaydının
// AYNI SQLite transaction'ında, business data ile ATOMİK olarak
// yazılmasını sağlar. Uygulama transaction commit olduktan hemen sonra
// (ama gerçek ağ gönderiminden ÖNCE) çökse bile kuyruk satırı diskte
// kalıcı kalır — bir sonraki açılışta BulutManager onu bulur ve
// gönderir. Gerçek ağ gönderimi BURADA YAPILMAZ; bu sınıf sadece kuyruk
// SATIRINI yazar. Push işlemi her zaman transaction dışında,
// BulutManager._isle() içinde gerçekleşir — dış transaction rollback
// olursa buluta hiç var olmamış bir satır gönderilmiş olmaz (bkz.
// KasaDeposu.hareketEkleTxn'deki aynı gerekçe — o ilke burada da geçerli,
// sadece artık "bildirim" RAM'de değil diskte bekliyor).
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../cekirdek/sabitler/db_sabitleri.dart';

class SyncKuyrukYazici {
  /// [txn] içinde çağrılmalı — kendi transaction'ını AÇMAZ.
  ///
  /// [veri], ilgili tablonun YEREL (henüz Supabase kolon adlarına
  /// çevrilmemiş) satır haritasıdır — dönüşüm/temizlik merkezi olarak
  /// BulutManager._veriCoz() içinde, push anında yapılır (tek doğruluk
  /// kaynağı, iki kez uygulanma riski yok).
  static Future<void> ekleTxn(
    dynamic txn, {
    required String tablo,
    required Map<String, dynamic> veri,
    String islemTipi = 'UPSERT',
  }) async {
    if (islemTipi == 'UPSERT') await _kimlikTamamla(txn, tablo, veri);
    final globalId = veri['global_id']?.toString();
    // Aynı kayıt için bekleyen eski bir kuyruk satırı varsa önce sil —
    // eski RAM tabanlı kuyruğun "aynı global_id'yi güncelle" (replace)
    // davranışıyla AYNI: kuyrukta gereksiz eski kopyalar birikmez, her
    // zaman kaydın EN GÜNCEL hali gönderilir.
    if (globalId != null && globalId.isNotEmpty) {
      await txn.delete(
        DbSabitler.syncQueue,
        where: 'tablo_adi = ? AND kayit_global_id = ? AND durum = ?',
        whereArgs: [tablo, globalId, 'beklemede'],
      );
    }
    await txn.insert(DbSabitler.syncQueue, {
      'tablo_adi': tablo,
      'kayit_global_id': globalId,
      'islem_tipi': islemTipi,
      'veri_json': jsonEncode(veri, toEncodable: (v) => v.toString()),
      'deneme_sayisi': 0,
      'durum': 'beklemede',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// global_id'siz ama yerel id'li satırın kimliğini AYNI transaction'dan
  /// tamamlar (BulutManager.upsert'teki kuralın txn içi karşılığı). Kimliksiz
  /// satır buluta gidince on_conflict eşleşmez ve kimliksiz yeni satır açılır
  /// (Bulut Veri Güvenliği Raporu 2026-10-07, Bulgu 3). global_id sütunu
  /// olmayan tabloda okuma hata verir — o tabloya dokunulmaz.
  static Future<void> _kimlikTamamla(
      dynamic txn, String tablo, Map<String, dynamic> veri) async {
    final mevcut = veri['global_id']?.toString();
    final id = veri['id'];
    if ((mevcut != null && mevcut.isNotEmpty) || id == null) return;
    try {
      final r = await txn.query(tablo,
          columns: ['global_id'], where: 'id = ?', whereArgs: [id], limit: 1);
      if ((r as List).isEmpty) return;
      final yerel = (r.first as Map)['global_id']?.toString();
      if (yerel != null && yerel.isNotEmpty) {
        veri['global_id'] = yerel;
        return;
      }
      final yeni = const Uuid().v4();
      await txn.update(tablo, {'global_id': yeni},
          where: "id = ? AND (global_id IS NULL OR global_id = '')", whereArgs: [id]);
      veri['global_id'] = yeni;
    } catch (_) {
      // global_id sütunu yok (doğal anahtarlı tablo) — olduğu gibi gider.
    }
  }
}
