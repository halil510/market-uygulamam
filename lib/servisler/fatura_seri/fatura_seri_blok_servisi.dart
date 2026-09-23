// lib/servisler/fatura_seri/fatura_seri_blok_servisi.dart
//
// MERKEZİ FATURA SERİ/BLOK YÖNETİMİ — bkz. proje kökünde
// CENTRAL_DOCUMENT_NUMBERING_DEEP_AUDIT.md (tam analiz/gerekçe) ve
// supabase_fatura_seri_bloklari.sql (bulut tarafı: fatura_blok_tahsis_et
// RPC'si — atomik satır kilidi, iki terminal ASLA aynı aralığı alamaz).
//
// Bu servis OFFLINE tüketimi yönetir: bir terminale önceden tahsis
// edilmiş bir blok varsa, fatura numarası TAMAMEN YEREL ve ATOMİK
// olarak (aynı SQLite transaction'ı içinde, gerçek INSERT ile birlikte)
// üretilir — ağ gerekmez. Blok azaldıkça/tükendikçe, internet varsa
// arka planda (ya da gerekirse senkron olarak) yeni bir blok RPC ile
// alınır. Blok tükenip internet de yoksa, fatura oluşturma AÇIK bir
// hatayla ENGELLENİR — dokümanın 8. maddesindeki kural: "sessizce aynı
// numarayı üretmeye çalışma."
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../../veri/database/veritabani.dart';
import '../bulut/bulut_saglayici.dart';
import '../bulut/supabase_ayarlari.dart';
import '../bulut/supabase_saglayici.dart';
import 'terminal_servisi.dart';

/// Yerelde bu seri için tüketilebilir bir blok kalmadığını (ve yeni
/// bir tane alınamadığını/henüz alınmadığını) belirtir.
class BlokTukendiException implements Exception {
  final String mesaj;
  BlokTukendiException(this.mesaj);
  @override
  String toString() => mesaj;
}

class FaturaSeriBlokServisi {
  static final FaturaSeriBlokServisi _instance = FaturaSeriBlokServisi._();
  factory FaturaSeriBlokServisi() => _instance;
  FaturaSeriBlokServisi._();

  static const int _blokBoyutu = 10;
  static const double _yenilemeEsikOrani = 0.2; // kalan %20'nin altına düşünce proaktif yenile

  final Set<String> _yenilemeSurmekte = {};

  /// Bu seri için TÜKETİLEBİLİR bir yerel blok olduğundan emin olur —
  /// yoksa/tükendiyse SENKRON olarak yeni bir tane alır (ağ gerektirir,
  /// bu yüzden bu fonksiyon SQLite transaction'ı DIŞINDA, ondan ÖNCE
  /// çağrılmalı). Azalmış ama hâlâ kullanılabilir bir blok varsa,
  /// arka planda (beklemeden) proaktif bir yenileme başlatır.
  Future<void> blokHazirOldugundanEminOl(String seri) async {
    final db = await Veritabani().db;
    final rows = await db.query(
      'yerel_fatura_blok',
      where: 'seri = ? AND durum = ? AND siradaki <= blok_bitis',
      whereArgs: [seri, 'aktif'],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final r = rows.first;
      final baslangic = r['blok_baslangic'] as int;
      final bitis = r['blok_bitis'] as int;
      final siradaki = r['siradaki'] as int;
      final toplam = (bitis - baslangic + 1).clamp(1, 1 << 30);
      final kalan = (bitis - siradaki + 1).clamp(0, toplam);
      if (kalan / toplam > _yenilemeEsikOrani) return; // yeterli — hiçbir şey yapma
      // Az kaldı — mevcut blok hâlâ kullanılabilir olduğu için
      // BEKLEMEDEN arka planda yeni blok iste (çevrimdışıysa sessizce
      // başarısız olur, bir sonraki çağrıda tekrar denenir).
      _arkaPlandaYenile(seri);
      return;
    }
    // Hiç kullanılabilir blok yok — buradan devam edebilmek için ZORUNLU.
    await _yeniBlokAl(seri);
  }

  void _arkaPlandaYenile(String seri) {
    if (_yenilemeSurmekte.contains(seri)) return;
    _yenilemeSurmekte.add(seri);
    _yeniBlokAl(seri).catchError((_) {
      // Sessizce yut — bu proaktif bir iyileştirme, mevcut blok zaten
      // kullanılabilir durumda; bir sonraki blokHazirOldugundanEminOl
      // çağrısı gerekirse tekrar dener.
    }).whenComplete(() => _yenilemeSurmekte.remove(seri));
  }

  Future<void> _yeniBlokAl(String seri) async {
    final url = await SupabaseAyarlari.urlOku();
    final key = await SupabaseAyarlari.keyOku();
    if (url == null || url.isEmpty || key == null || key.isEmpty) {
      throw BlokTukendiException(
          'Yeni fatura numarası bloğu almak için Supabase bağlantısı '
          'yapılandırılmış olmalı (Ayarlar > Bulut Senkronizasyon).');
    }
    // 🔴 Geçiş dönemi netliği: supabase_fatura_seri_bloklari.sql henüz
    // Supabase'de ÇALIŞTIRILMADIYSA (terminaller/fatura_seri_bloklari
    // tabloları veya RPC yok), aşağıdaki çağrılar ham bir PostgREST/
    // Postgres hatası (ör. "relation does not exist") fırlatır — bu,
    // kullanıcıya anlamsız gelir. Burada YAKALANIP açık bir mesaja
    // çevriliyor.
    try {
      final terminal = await TerminalServisi().terminalGarantiEt();
      final saglayici = SupabaseSaglayici(url: url, key: key);
      final sonuc = await saglayici.rpcCagir('fatura_blok_tahsis_et', {
        'p_terminal_id': terminal.terminalId,
        'p_seri': seri,
        'p_blok_boyutu': _blokBoyutu,
      });
      if (sonuc.isEmpty) {
        throw BlokTukendiException(
            'Fatura numarası bloğu alınamadı — sunucudan boş yanıt geldi.');
      }
      await _blogKaydet(seri, sonuc.first);
    } on BlokTukendiException {
      rethrow;
    } on BulutIstekHatasi catch (e) {
      // RPC'nin EXECUTE yetkisi yalnızca service_role'de (bkz.
      // supabase_fatura_blok_tahsis_yetki_kisitla.sql) — publishable
      // anahtarla kalmış bir cihaz 401/403 alır; bu "script çalışmadı"
      // değil, yanlış anahtar demektir.
      if (e.statusKodu == 401 || e.statusKodu == 403) {
        throw BlokTukendiException(
            'Fatura numarası bloğu alınamadı — bu cihazda herkese açık '
            '(publishable) Supabase anahtarı kayıtlı. Ayarlar > Bulut '
            'Senkronizasyon ekranından sb_secret_ ile başlayan anahtarı '
            'girin. (Teknik ayrıntı: $e)');
      }
      throw BlokTukendiException(
          'Fatura numarası bloğu alınamadı. Bu genelde '
          'supabase_fatura_seri_bloklari.sql henüz Supabase\'de '
          'çalıştırılmadığı anlamına gelir — lütfen bu script\'i '
          'Supabase SQL Editor\'de çalıştırıp tekrar deneyin. '
          '(Teknik ayrıntı: $e)');
    } catch (e) {
      // Ağ hatası (çevrimdışı/zaman aşımı) vb.
      throw BlokTukendiException(
          'Fatura numarası bloğu alınamadı — Supabase\'e ulaşılamıyor. '
          'İnternet bağlantınızı kontrol edip tekrar deneyin. '
          '(Teknik ayrıntı: $e)');
    }
  }

  Future<void> _blogKaydet(String seri, Map<String, dynamic> r) async {
    final baslangic = (r['blok_baslangic'] as num).toInt();
    final bitis = (r['blok_bitis'] as num).toInt();
    final yil = (r['yil'] as num).toInt();
    final db = await Veritabani().db;
    await db.insert('yerel_fatura_blok', {
      'seri': seri,
      'yil': yil,
      'blok_baslangic': baslangic,
      'blok_bitis': bitis,
      'siradaki': baslangic,
      'durum': 'aktif',
      'tahsis_zamani': DateTime.now().toIso8601String(),
    });
  }

  /// Yerel bloktan bir sonraki numarayı ATOMİK olarak tüketir — [txn]
  /// zaten AÇIK olan bir SQLite transaction'ı olmalı (fatura INSERT'i
  /// ile AYNI transaction — böylece "numarayı oku" ile "faturayı
  /// kaydet" arasında hiçbir boşluk kalmaz, aynı cihaz içi bir yarış
  /// durumu bile artık mümkün değil). Blok tükenmişse
  /// [BlokTukendiException] fırlatır — çağıran taraf transaction'ı
  /// (otomatik olarak) geri alıp [blokHazirOldugundanEminOl]'u tekrar
  /// çağırarak bir kez daha denemeli.
  Future<({int numara, int yil})> faturaNoTuket(
      Transaction txn, String seri) async {
    final rows = await txn.query(
      'yerel_fatura_blok',
      where: 'seri = ? AND durum = ? AND siradaki <= blok_bitis',
      whereArgs: [seri, 'aktif'],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) {
      throw BlokTukendiException('$seri için hazır fatura numarası bloğu kalmadı.');
    }
    final r = rows.first;
    final id = r['id'] as int;
    final numara = r['siradaki'] as int;
    final bitis = r['blok_bitis'] as int;
    final yil = r['yil'] as int;
    final yeniSiradaki = numara + 1;
    await txn.update(
      'yerel_fatura_blok',
      {
        'siradaki': yeniSiradaki,
        if (yeniSiradaki > bitis) 'durum': 'tukendi',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return (numara: numara, yil: yil);
  }
}
