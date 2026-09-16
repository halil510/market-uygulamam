// lib/servisler/arsiv_veritabani_yoneticisi.dart
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — arşiv okuma
// altyapısı (2026-09-16, kullanıcı onaylı mimari plan raporu §1b).
//
// 🔴 DÜRÜSTLÜK NOTU: Bu sınıf SADECE geçmiş yıl arşiv dosyalarını
// AÇMA/OKUMA yeteneği sağlar — hiçbir şekilde arşiv dosyası ÜRETMEZ
// (aktif veriyi arşive TAŞIMAZ, aktif tablolardan SİLMEZ). "Gerçek
// arşivleme" (üretim verisini taşıma/silme) BİLİNÇLİ olarak KAPSAM
// DIŞI — bu, mimari plan raporundaki §1b/§3'ün öngördüğü, çok daha
// dikkatli ve AYRI bir onay gerektiren sonraki adım. Şu an hiçbir
// arşiv dosyası üretilmediğinden [arsivAc] pratikte her zaman null
// döner — bu BEKLENEN bir durumdur, hata değildir.
//
// Tasarım (mimari plan §1b — onaylandı): aktif `market.db`'den TAMAMEN
// AYRI, ikinci bir sqflite `Database` bağlantısı, `readOnly: true` ile
// açılır (ATTACH DATABASE DEĞİL — mevcut `Veritabani` singleton'ının
// tek-bağlantı varsayımını bozmaz). Aynı anda en fazla [_maxAcikBaglanti]
// bağlantı açık tutulur (basit FIFO tahliye — kullanıcı arka arkaya
// çok sayıda farklı yıl raporuna bakarsa dosya tanıtıcısı sızıntısını
// önlemek için).
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'log_servisi.dart';

class ArsivVeritabaniYoneticisi {
  static final ArsivVeritabaniYoneticisi _instance = ArsivVeritabaniYoneticisi._();
  factory ArsivVeritabaniYoneticisi() => _instance;
  ArsivVeritabaniYoneticisi._() : _dizinSaglayici = getApplicationDocumentsDirectory;

  /// SADECE testler için — path_provider platform kanalına ihtiyaç
  /// duymadan, gerçek (geçici) bir dizine karşı FIFO tahliye/salt-okunur
  /// açma mantığını doğrulamak amacıyla ayrı bir örnek oluşturur. Üretim
  /// kodu her zaman singleton factory'yi ( ArsivVeritabaniYoneticisi() )
  /// kullanmalı.
  ArsivVeritabaniYoneticisi.test({required Directory Function() dizinSaglayici})
      : _dizinSaglayici = (() async => dizinSaglayici());

  final Future<Directory> Function() _dizinSaglayici;

  static const _maxAcikBaglanti = 2;

  // Ekleme sırasını koruyan basit bir harita — FIFO tahliye için.
  final Map<int, Database> _acikBaglantilar = {};

  /// [donemYili] için arşiv dosyasının OLMASI GEREKEN yolu — dosya
  /// gerçekten var olmayabilir (henüz arşivlenmemiş dönem).
  Future<String> arsivDosyaYolu(int donemYili) async {
    final dir = await _dizinSaglayici();
    return '${dir.path}/arsiv/$donemYili/barkopro_$donemYili.db';
  }

  Future<bool> arsivVarMi(int donemYili) async {
    final yol = await arsivDosyaYolu(donemYili);
    return File(yol).exists();
  }

  /// [donemYili] arşivini salt-okunur açar. Dosya yoksa null döner —
  /// bu şu an (gerçek arşivleme kurulmadan) HER ZAMAN null demektir,
  /// çağıranlar bunu normal bir durum olarak ele almalı (ör. "Bu yıl
  /// için arşiv henüz oluşturulmadı" mesajı), hata olarak değil.
  Future<Database?> arsivAc(int donemYili) async {
    final mevcut = _acikBaglantilar[donemYili];
    if (mevcut != null) return mevcut;

    final yol = await arsivDosyaYolu(donemYili);
    final dosya = File(yol);
    if (!await dosya.exists()) return null;

    if (_acikBaglantilar.length >= _maxAcikBaglanti) {
      final enEskiYil = _acikBaglantilar.keys.first;
      final kapatilacak = _acikBaglantilar.remove(enEskiYil);
      try {
        await kapatilacak?.close();
      } catch (e, st) {
        LogServisi().hata('ArsivVeritabaniYoneticisi.arsivAc (eski bağlantı kapatma)',
            hata: e, yigin: st);
      }
    }

    try {
      final db = await openDatabase(yol, readOnly: true);
      _acikBaglantilar[donemYili] = db;
      return db;
    } catch (e, st) {
      LogServisi().hata('ArsivVeritabaniYoneticisi.arsivAc', hata: e, yigin: st);
      return null;
    }
  }

  /// Belirli bir yılın bağlantısını kapatır (ör. ekran kapanırken).
  Future<void> kapat(int donemYili) async {
    final db = _acikBaglantilar.remove(donemYili);
    if (db != null) {
      try {
        await db.close();
      } catch (e, st) {
        LogServisi().hata('ArsivVeritabaniYoneticisi.kapat', hata: e, yigin: st);
      }
    }
  }

  /// TÜM açık arşiv bağlantılarını kapatır (ör. uygulama arka plana
  /// alınırken kaynak tasarrufu için).
  Future<void> hepsiniKapat() async {
    final baglantilar = List<Database>.from(_acikBaglantilar.values);
    _acikBaglantilar.clear();
    for (final db in baglantilar) {
      try {
        await db.close();
      } catch (e, st) {
        LogServisi().hata('ArsivVeritabaniYoneticisi.hepsiniKapat', hata: e, yigin: st);
      }
    }
  }
}
