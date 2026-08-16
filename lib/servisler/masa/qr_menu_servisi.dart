// lib/servisler/masa/qr_menu_servisi.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../depolar/masa_deposu.dart';
import '../../veri/database/veritabani.dart';

class QrMenuServisi {
  static final QrMenuServisi _instance = QrMenuServisi._();
  factory QrMenuServisi() => _instance;
  QrMenuServisi._();

  /// Masa için QR kod URL'i oluştur
  String qrKodUrlOlustur(int masaId, String subeKodu) {
    // QR kod içeriği - müşteri bu URL'i okuduğunda masa sipariş ekranı açılır
    return 'marketplus://masa/$masaId?sube=$subeKodu';
  }

  /// QR kod içeriğini oluştur (web view için)
  String qrKodIcerik(int masaId, String masaAdi) {
    return jsonEncode({
      'tip': 'masa_qr',
      'masa_id': masaId,
      'masa_adi': masaAdi,
      'url': 'marketplus://masa/$masaId',
    });
  }

  /// Müşteri QR ile gelen siparişi kaydet
  //
  // ÖNCEDEN bu fonksiyon ham SQL ile doğrudan "masa_siparis_kalem"
  // tablosuna satır ekliyordu — bu, MasaDeposu.kalemEkle()'nin sahip
  // olduğu TÜM güvenlik önlemlerini atlıyordu:
  //   1. global_id HİÇ ATANMIYORDU (tablo UNIQUE global_id gerektiriyor
  //      — senkronizasyonu bozabilirdi)
  //   2. Aynı ürün tekrar sipariş edilirse (aynı not ile) miktarı
  //      artırmak yerine YENİ, ayrı bir satır oluşturuyordu
  //   3. EN ÖNEMLİSİ: sipariş toplam tutarı (toplam_tutar) HİÇ
  //      GÜNCELLENMİYORDU — müşteri QR ile sipariş verdiğinde, o
  //      siparişin toplamı sıfırda/eski değerde kalıyordu, kasiyer
  //      ekranında yanlış/eksik tutar görünebiliyordu.
  // Artık MasaDeposu'nun ZATEN kanıtlanmış, güvenli fonksiyonları
  // (siparisAcVeyaGetir, kalemEkle) kullanılıyor — bu üç sorun da
  // otomatik olarak ortadan kalkıyor.
  Future<void> musteriSiparisKaydet({
    required int masaId,
    required List<Map<String, dynamic>> kalemler,
    required String musteriAdi,
    required String musteriTel,
    String? not,
  }) async {
    final masaDepo = MasaDeposu();
    final siparis = await masaDepo.siparisAcVeyaGetir(masaId);
    final db = await Veritabani().db;

    // 🔴🔴 KÖK NEDEN DÜZELTMESİ ("masa dolu ama ürün yok" — 2. tur):
    // HTML menü sayfası ürünleri SUPABASE'den çekiyor — yani sipariş
    // kalemindeki urun_id aslında ürünün BULUT id'si (BIGSERIAL).
    // Uygulama bunu LOKAL SQLite id'si sanıyordu. İki id ancak şans
    // eseri örtüşür. Çözüm — üç aşamalı sağlam eşleştirme zinciri:
    //   1) Kalemde urun_gid (global_id) varsa → lokalde onunla bul
    //      (yeni HTML bunu gönderiyor; kesin eşleşme)
    //   2) Yoksa: gelen id lokalde GERÇEKTEN VAR MI doğrula
    //   3) O da yoksa: ürün ADIYLA eşleştir (eski HTML için kurtarma)
    // Ayrıca her kalem KENDİ try-catch'inde — önceden tek kalemdeki
    // bir hata TÜM siparişi iptal ediyordu (sipariş sonsuz döngüde
    // tekrar deneniyor, masa hep dolu-boş kalıyordu).
    int eklenen = 0;
    for (final k in kalemler) {
      try {
        final adRaw = k['urun_adi'];
        final urunAdi = adRaw?.toString() ?? 'Ürün';
        int? lokalUrunId;

        // 1) global_id ile kesin eşleşme
        final gid = k['urun_gid']?.toString();
        if (gid != null && gid.isNotEmpty) {
          final r = await db.query('urunler',
              columns: ['id'], where: 'global_id = ?', whereArgs: [gid], limit: 1);
          if (r.isNotEmpty) lokalUrunId = (r.first['id'] as num).toInt();
        }

        // 2) gelen id'yi lokalde doğrula
        if (lokalUrunId == null) {
          final gelenId = (k['urun_id'] as num?)?.toInt();
          if (gelenId != null) {
            final r = await db.query('urunler',
                columns: ['id'], where: 'id = ?', whereArgs: [gelenId], limit: 1);
            if (r.isNotEmpty) lokalUrunId = gelenId;
          }
        }

        // 3) ad ile kurtarma eşleşmesi
        if (lokalUrunId == null) {
          final r = await db.query('urunler',
              columns: ['id'], where: 'urun_adi = ? AND is_deleted = 0',
              whereArgs: [urunAdi], limit: 1);
          if (r.isNotEmpty) lokalUrunId = (r.first['id'] as num).toInt();
        }

        if (lokalUrunId == null) {
          // Eşleşme yok — kalemi yine de gelen id ile ekle ki
          // müşterinin siparişi KAYBOLMASIN (ad, kalemde saklı olduğu
          // için ekranda yine görünür; personel düzeltebilir).
          lokalUrunId = (k['urun_id'] as num?)?.toInt() ?? 0;
          if (kDebugMode) {
            debugPrint('QrMenu: "$urunAdi" lokalde eşleşmedi, '
                'gelen id ($lokalUrunId) ile kaydedildi');
          }
        }

        final notDeger = k['not']?.toString();
        await masaDepo.kalemEkle(
          siparis.id!,
          urunId:     lokalUrunId,
          urunAdi:    urunAdi,
          birimFiyat: (k['birim_fiyat'] as num?)?.toDouble() ?? 0,
          kdvOran:    (k['kdv_oran'] as num?)?.toDouble() ?? 18,
          miktar:     (k['miktar'] as num?)?.toDouble() ?? 1,
          not_:       (notDeger == null || notDeger.trim().isEmpty) ? null : notDeger,
        );
        eklenen++;
      } catch (e) {
        if (kDebugMode) debugPrint('QrMenu kalem hatası (atlandı): $e — kalem: $k');
      }
    }
    if (kDebugMode) {
      debugPrint('QrMenu: masa $masaId → ${kalemler.length} kalemden $eklenen eklendi');
    }
  }
}
