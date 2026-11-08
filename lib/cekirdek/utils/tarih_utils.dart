// lib/cekirdek/utils/tarih_utils.dart
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';

class TarihUtils {
  static final _gmt  = DateFormat('dd.MM.yyyy', 'tr_TR');
  static final _gtm  = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');
  static final _saat = DateFormat('HH:mm', 'tr_TR');

  static String tarihFormatla(DateTime? dt) =>
      dt == null ? '-' : _gmt.format(dt);

  static String tarihSaatFormatla(DateTime? dt) =>
      dt == null ? '-' : _gtm.format(dt);

  static String saatFormatla(DateTime? dt) =>
      dt == null ? '-' : _saat.format(dt);

  static DateTime bugunBaslangic() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime bugunBitis() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  static DateTime haftaBaslangici() =>
      DateTime.now().subtract(const Duration(days: 6));

  static DateTime ayBaslangici() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  /// showDateRangePicker'ın başlangıç aralığını [ilk]–[son] sınırına kırpar
  /// (gün bazında). "Bu Ay / Bu Yıl" filtresi bitişi ileri bir tarihe
  /// koyuyordu; aralık lastDate'i aşınca tarih seçici çöküyordu.
  static DateTimeRange? secimAraligiKirp(
      DateTimeRange? aralik, DateTime ilk, DateTime son) {
    if (aralik == null) return null;
    DateTime gun(DateTime d) => DateTime(d.year, d.month, d.day);
    DateTime kirp(DateTime d) {
      final g = gun(d);
      if (g.isBefore(gun(ilk))) return gun(ilk);
      if (g.isAfter(gun(son))) return gun(son);
      return g;
    }
    final bas = kirp(aralik.start);
    final bit = kirp(aralik.end);
    return DateTimeRange(start: bas.isAfter(bit) ? bit : bas, end: bit);
  }

  /// Rapor/liste sorgularında tarih aralığı koşulunun TEK biçimi
  /// (CLAUDE.md §4.6). [kolon] yerel saatle yazılmış ISO tarih sütunu
  /// (DateTime.now().toIso8601String()); iki `?` parametresi de Dart'tan
  /// yerel ISO metniyle verilmelidir (bas, bit). İki taraf da yerel olduğu
  /// için 'localtime' GEREKMEZ — SQLite'ın 'now'u (UTC) burada kullanılmaz;
  /// "gece 00:00–03:00 satışları kayboluyor" hatası bu karışımdan çıkmıştı.
  ///
  /// Faz D (performans, 2026-11-08): `datetime(kolon)` sütunu fonksiyona
  /// sardığı için SQLite tarih index'ini KULLANAMIYOR, her rapor tabloyu
  /// baştan sona tarıyordu. Asıl koşul AYNEN korunup önüne ham sütun
  /// üzerinde gün payı bırakan bir ön süzgeç eklendi (index ile aranır).
  /// Pay neden ±1 gün: buluttan dönen TIMESTAMPTZ metinleri "+00:00"
  /// gibi dilim ekiyle gelebiliyor; datetime() dilimi uygulayınca saat en
  /// fazla 24 saat kayar. Metin önekinin gün kısmı bu yüzden asıl aralığın
  /// en fazla bir gün dışında olabilir — ön süzgeç hiçbir satırı eksiltmez
  /// (bkz. test/unit/tarih_aralik_sql_test.dart, eski/yeni karşılaştırması).
  /// [bas]/[bit], `?` parametrelerine verilen değerlerle AYNI olmalı.
  static String aralikSql(String kolon, DateTime bas, DateTime bit) =>
      '(${_altSinirSql(kolon, bas)} AND ${_ustSinirSql(kolon, bit)} AND '
      'datetime($kolon) BETWEEN datetime(?) AND datetime(?))';

  /// Tek taraflı "şu andan sonra" koşulu (`datetime(kolon) >= datetime(?)`),
  /// [aralikSql] ile aynı index ön süzgeciyle. [bas] null ise (ör. metin
  /// ayrıştırılamadı) yalnız eski koşul döner.
  static String sonrasiSql(String kolon, DateTime? bas) => bas == null
      ? 'datetime($kolon) >= datetime(?)'
      : '(${_altSinirSql(kolon, bas)} AND datetime($kolon) >= datetime(?))';

  /// Tek taraflı "şu ana kadar" koşulu (`datetime(kolon) <= datetime(?)`).
  static String oncesiSql(String kolon, DateTime? bit) => bit == null
      ? 'datetime($kolon) <= datetime(?)'
      : '(${_ustSinirSql(kolon, bit)} AND datetime($kolon) <= datetime(?))';

  static String _altSinirSql(String kolon, DateTime bas) =>
      "$kolon >= '${_gunMetni(DateTime(bas.year, bas.month, bas.day - 1))}'";

  static String _ustSinirSql(String kolon, DateTime bit) =>
      "$kolon < '${_gunMetni(DateTime(bit.year, bit.month, bit.day + 2))}'";

  static String _gunMetni(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String kacGunOnce(DateTime dt) {
    final fark = DateTime.now().difference(dt).inDays;
    if (fark == 0) return 'Bugün';
    if (fark == 1) return 'Dün';
    if (fark < 7) return '$fark gün önce';
    return tarihFormatla(dt);
  }
}
