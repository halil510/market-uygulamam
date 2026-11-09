// lib/veri/database/yerel_arsiv_araliklari.dart
//
// Bu cihazın yıl sonu devriyle aktif tablolardan SİLDİĞİ (arşivlediği)
// tarih aralıkları — yalnız bu cihaza ait (SharedPreferences).
//
// Neden (derin denetim 2026-11-09, kritik): devir eski dönem hareketlerini
// yalnız yerelden siler, bulutta korunur; yerine yalnız-yerel bir açılış
// satırı yazar. "Tam Al" / yeni çekim o eski hareketleri buluttan geri
// indirseydi açılış satırıyla birlikte dönem İKİ KEZ sayılırdı. Çekim bu
// aralıklara düşen satırları yazmaz (bkz. Veritabani.supaKayitlariEkle).
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class YerelArsivAraligi {
  final int subeId;
  final String bas; // 'YYYY-MM-DDTHH:MM:SS' (yerel duvar saati)
  final String bit;
  const YerelArsivAraligi(this.subeId, this.bas, this.bit);

  Map<String, Object> toJson() => {'sube': subeId, 'bas': bas, 'bit': bit};
  static YerelArsivAraligi fromJson(Map m) =>
      YerelArsivAraligi((m['sube'] as num).toInt(), m['bas'] as String, m['bit'] as String);
}

class YerelArsivAraliklari {
  YerelArsivAraliklari._();

  static const _anahtar = 'mp_yerel_arsiv_araliklari';

  /// Devirde silinen tablolar → şube bazlı mı (false: şirket geneli).
  static const Map<String, bool> tablolar = {
    'satislar': true,
    'stok_hareket': true,
    'kasa_hareketleri': true,
    'cari_hareket': false,
    'banka_hareketler': false,
  };

  static String _saniye(Object? t) {
    final s = t?.toString().replaceFirst(' ', 'T') ?? '';
    return s.length >= 19 ? s.substring(0, 19) : s;
  }

  static Future<List<YerelArsivAraligi>> hepsi() async {
    final p = await SharedPreferences.getInstance();
    final ham = p.getString(_anahtar);
    if (ham == null || ham.isEmpty) return const [];
    return (jsonDecode(ham) as List).cast<Map>().map(YerelArsivAraligi.fromJson).toList();
  }

  static Future<void> ekle(
      {required int subeId, required DateTime baslangic, required DateTime bitis}) async {
    final yeni = YerelArsivAraligi(
        subeId, _saniye(baslangic.toIso8601String()), _saniye(bitis.toIso8601String()));
    final mevcut = await hepsi();
    if (mevcut.any((a) => a.subeId == yeni.subeId && a.bas == yeni.bas && a.bit == yeni.bit)) {
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _anahtar, jsonEncode([...mevcut, yeni].map((a) => a.toJson()).toList()));
  }

  /// [satir] bu cihazın arşivlediği bir aralıkta mı (çekimde yazılmamalı)?
  static bool arsivlenmisMi(
      String tablo, Map<String, dynamic> satir, List<YerelArsivAraligi> araliklar) {
    final subeBazli = tablolar[tablo];
    if (subeBazli == null || araliklar.isEmpty) return false;
    final tarih = _saniye(satir['tarih']);
    if (tarih.isEmpty) return false;
    final sube = (satir['sube_id'] as num?)?.toInt();
    for (final a in araliklar) {
      if (subeBazli && sube != a.subeId) continue;
      if (tarih.compareTo(a.bas) >= 0 && tarih.compareTo(a.bit) <= 0) return true;
    }
    return false;
  }
}
