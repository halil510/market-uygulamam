// lib/servisler/fatura_seri/terminal_servisi.dart
//
// MERKEZİ FATURA SERİ/BLOK YÖNETİMİ — bkz. proje kökünde
// CENTRAL_DOCUMENT_NUMBERING_DEEP_AUDIT.md (tam analiz/gerekçe).
//
// "Terminal" — bu cihazın merkezi fatura numaralandırma sistemindeki
// kimliği. BİLEREK `cihaz_id`'den (kendiliğinden üretilir, sunucuda
// hiç doğrulanmaz, uygulama verisi silinince kaybolur) FARKLI bir
// kavram: Terminal, Şube gibi bulutta KAYITLI, kalıcı bir varlık —
// `terminaller` tablosunda bir satır. İlk kullanımda otomatik
// kaydedilir (kullanıcıdan bir şey istemeden, tek cihazlı kurulumlar
// için sürtünmesiz) — birden fazla cihaz kullanılacaksa Ayarlar'dan
// yeniden adlandırılabilir/yönetilebilir (bkz. rapor §18, karar 2).
import 'package:sqflite/sqflite.dart';
import '../../veri/database/veritabani.dart';
import '../aktif_sube_servisi.dart';
import '../supabase_sync_servisi.dart';
import '../bulut/supabase_ayarlari.dart';
import '../bulut/supabase_saglayici.dart';

class YerelTerminal {
  final int terminalId;
  final String terminalKodu;
  final int? subeId;
  const YerelTerminal(
      {required this.terminalId, required this.terminalKodu, this.subeId});
}

class TerminalServisi {
  static final TerminalServisi _instance = TerminalServisi._();
  factory TerminalServisi() => _instance;
  TerminalServisi._();

  YerelTerminal? _onbellek;

  /// Bu cihaz daha önce bir Terminal olarak kaydedildiyse onu döner
  /// (yerelden, ağ gerektirmez). Kaydedilmediyse null döner —
  /// [terminalGarantiEt] ile kaydettirin.
  Future<YerelTerminal?> mevcutTerminal() async {
    if (_onbellek != null) return _onbellek;
    final db = await Veritabani().db;
    final rows = await db.query('yerel_terminal', where: 'id = 1', limit: 1);
    if (rows.isEmpty || rows.first['terminal_id'] == null) return null;
    final r = rows.first;
    _onbellek = YerelTerminal(
      terminalId: r['terminal_id'] as int,
      terminalKodu: r['terminal_kodu'] as String? ?? '',
      subeId: r['sube_id'] as int?,
    );
    return _onbellek;
  }

  /// Bu cihaz henüz bir Terminal olarak kayıtlı değilse, buluta bir
  /// tane kaydedip yerelde saklar. Kayıtlıysa doğrudan onu döner.
  /// İdempotent: `terminal_kodu` üzerinde on_conflict kullanıldığı
  /// için aynı kod tekrar gönderilirse hata vermez, mevcut satırı döner
  /// (ör. cihaz verisi silinip yerel kayıt kaybolduysa, aynı cihaz
  /// kimliğinden üretilen kod ile eski Terminal satırı yeniden bulunur).
  Future<YerelTerminal> terminalGarantiEt() async {
    final mevcut = await mevcutTerminal();
    if (mevcut != null) return mevcut;

    final url = await SupabaseAyarlari.urlOku();
    final key = await SupabaseAyarlari.keyOku();
    if (url == null || url.isEmpty || key == null || key.isEmpty) {
      throw Exception(
          'Terminal kaydı için önce Ayarlar > Bulut Senkronizasyon\'da '
          'Supabase bağlantısı yapılandırılmalı.');
    }

    final cihazId = await SupabaseSyncServisi.cihazId();
    // Cihaz kimliğinin kısa, okunabilir bir türevi — insanın elle
    // ayırt edebileceği ama çakışma ihtimali çok düşük bir kod.
    final kisaKod = cihazId.replaceAll(RegExp(r'[^0-9]'), '');
    final terminalKodu =
        'TERMINAL-${kisaKod.length >= 6 ? kisaKod.substring(kisaKod.length - 6) : kisaKod}';
    final subeId = AktifSubeServisi().subeId;

    final saglayici = SupabaseSaglayici(url: url, key: key);
    final satir = await saglayici.insertVeDondur(
      'terminaller',
      {
        'terminal_kodu': terminalKodu,
        'terminal_adi': terminalKodu,
        'sube_id': subeId,
        'kayit_cihaz_id': cihazId,
        'aktif': true,
      },
      onConflict: 'terminal_kodu',
    );
    if (satir == null || satir['id'] == null) {
      throw Exception('Terminal kaydı buluttan beklenmeyen bir yanıt aldı.');
    }

    final terminal = YerelTerminal(
      terminalId: satir['id'] as int,
      terminalKodu: satir['terminal_kodu'] as String? ?? terminalKodu,
      subeId: satir['sube_id'] as int?,
    );
    await _yerelKaydet(terminal);
    _onbellek = terminal;
    return terminal;
  }

  Future<void> _yerelKaydet(YerelTerminal t) async {
    final db = await Veritabani().db;
    await db.insert(
      'yerel_terminal',
      {
        'id': 1,
        'terminal_id': t.terminalId,
        'terminal_kodu': t.terminalKodu,
        'sube_id': t.subeId,
        'kayit_tarihi': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
