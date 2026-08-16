// lib/servisler/log_servisi.dart
// Merkezi log ve crash analytics sistemi
// FlutterError + Zone hatalarını yakalar, DB'ye kaydeder, console'a yazar

import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../veri/database/veritabani.dart';

enum LogSeviye { bilgi, uyari, hata, kritik }

class LogServisi {
  static final LogServisi _instance = LogServisi._();
  factory LogServisi() => _instance;
  LogServisi._();

  bool _initialized = false;
  final List<_LogEntry> _buffer = [];
  static const int _maxBuffer = 200;

  // ── Başlat ────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    final srv = LogServisi();
    if (srv._initialized) return;
    srv._initialized = true;

    // Flutter framework hataları
    FlutterError.onError = (details) {
      srv.kritik(
        'FlutterError',
        hata: details.exception,
        yigin: details.stack,
        ek: details.context?.toStringDeep(),
      );
      FlutterError.presentError(details);
    };

    // Async/Zone hataları PlatformDispatcher yerine runZonedGuarded ile yakalanıyor (ana.dart)

    if (kDebugMode) debugPrint('[LogServisi] Başlatıldı ✓');
  }

  // ── Log yaz ───────────────────────────────────────────────────────────────
  void bilgi(String mesaj, {String? ek}) =>
      _yaz(LogSeviye.bilgi, mesaj, ek: ek);

  void uyari(String mesaj, {Object? hata, StackTrace? yigin, String? ek}) =>
      _yaz(LogSeviye.uyari, mesaj, hata: hata, yigin: yigin, ek: ek);

  void hata(String mesaj, {Object? hata, StackTrace? yigin, String? ek}) =>
      _yaz(LogSeviye.hata, mesaj, hata: hata, yigin: yigin, ek: ek);

  void kritik(String mesaj, {Object? hata, StackTrace? yigin, String? ek}) =>
      _yaz(LogSeviye.kritik, mesaj, hata: hata, yigin: yigin, ek: ek);

  void _yaz(LogSeviye seviye, String mesaj,
      {Object? hata, StackTrace? yigin, String? ek}) {
    final entry = _LogEntry(
      seviye: seviye,
      mesaj: mesaj,
      hata: hata?.toString(),
      yigin: yigin?.toString().split('\n').take(8).join('\n'),
      ek: ek,
      zaman: DateTime.now(),
    );

    // Console çıktısı
    final prefix = _prefix(seviye);
    if (kDebugMode) debugPrint('$prefix ${entry.zaman.toIso8601String()} | $mesaj');
    if (kDebugMode) if (hata != null) debugPrint('  Hata: $hata');

    // Buffer'a ekle
    if (_buffer.length >= _maxBuffer) _buffer.removeAt(0);
    _buffer.add(entry);

    // DB'ye asenkron yaz
    _dbYaz(entry);
  }

  Future<void> _dbYaz(_LogEntry e) async {
    try {
      final db = await Veritabani().db;
      await db.insert('app_log', {
        'seviye': e.seviye.name,
        'mesaj': e.mesaj,
        'hata': e.hata,
        'yigin': e.yigin,
        'ek': e.ek,
        'zaman': e.zaman.toIso8601String(),
      });
    } catch (e) { /* ignore */ } // DB yoksa sessizce geç
  }

  String _prefix(LogSeviye s) {
    switch (s) {
      case LogSeviye.bilgi:   return '[ℹ️ BİLGİ]';
      case LogSeviye.uyari:   return '[⚠️ UYARI]';
      case LogSeviye.hata:    return '[❌ HATA ]';
      case LogSeviye.kritik:  return '[💥 KRİTİK]';
    }
  }

  // ── Son logları getir ─────────────────────────────────────────────────────
  List<_LogEntry> get sonLoglar => List.unmodifiable(_buffer.reversed.take(50).toList());

  Future<List<Map<String, dynamic>>> dbdenGetir({
    LogSeviye? seviye,
    int limit = 100,
  }) async {
    try {
      final db = await Veritabani().db;
      final where = seviye != null ? 'seviye = ?' : null;
      final args  = seviye != null ? [seviye.name] : null;
      return await db.query('app_log',
          where: where, whereArgs: args,
          orderBy: 'id DESC', limit: limit);
    } catch (_) {
      return [];
    }
  }

  // ── Log ekranı için temizle ───────────────────────────────────────────────
  Future<void> temizle() async {
    _buffer.clear();
    try {
      final db = await Veritabani().db;
      await db.delete('app_log');
    } catch (e) { /* ignore */ }
  }
}

class _LogEntry {
  final LogSeviye seviye;
  final String mesaj;
  final String? hata;
  final String? yigin;
  final String? ek;
  final DateTime zaman;
  const _LogEntry({
    required this.seviye,
    required this.mesaj,
    this.hata,
    this.yigin,
    this.ek,
    required this.zaman,
  });
}
