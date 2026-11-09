// lib/servisler/masa/qr_menu_servisi.dart
import 'dart:convert';
import '../../depolar/masa_deposu.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/log_servisi.dart';
import '../../modeller/urun_model.dart';

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
  //
  // 🔴 DERİN DENETİM (2026-11-09, #74): eşleşmeyen ürün urun_id=0/bulut id
  // ile ekleniyordu — FK açık olduğu için kalem düşüyor, hata yutuluyor ve
  // sipariş "alındı" dönüyordu. Artık ürünler ÖNCE çözülür; hiçbiri
  // eşleşmezse hiçbir şey yazılmadan Exception fırlatılır (masa boş kalır,
  // çağıran hatayı gösterir/buluta geri bırakır). Kısmen eşleşmede
  // eşleşenler eklenir, atlanan ürün adları DÖNDÜRÜLÜR (çağıran gösterir).
  Future<List<String>> musteriSiparisKaydet({
    required int masaId,
    required List<Map<String, dynamic>> kalemler,
    required String musteriAdi,
    required String musteriTel,
    String? not,
  }) async {
    final masaDepo = MasaDeposu();
    final db = await Veritabani().db;
    final atlanan = <String>[];
    final cozulen = <({Map<String, dynamic> k, int urunId, String urunAdi})>[];

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
    for (final k in kalemler) {
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
          // #74: eşleşmeyen ürün FK'yı ihlal eder — atlanır ve bildirilir.
          atlanan.add(urunAdi);
          continue;
        }
        cozulen.add((k: k, urunId: lokalUrunId, urunAdi: urunAdi));
    }

    if (cozulen.isEmpty) {
      LogServisi().uyari('QrMenu: masa $masaId siparişindeki hiçbir ürün '
          'bu cihazda bulunamadı: ${atlanan.join(', ')}');
      throw Exception('Sipariş kaydedilemedi: ürünler bulunamadı '
          '(${atlanan.join(', ')}). Menü güncel değil olabilir.');
    }

    final siparis = await masaDepo.siparisAcVeyaGetir(masaId);
    int eklenen = 0;
    for (final c in cozulen) {
      final k = c.k;
      try {
        // 🔴🔴 KRİTİK GÜVENLİK AÇIĞI (derin analizde bulundu): birimFiyat/
        // kdvOran doğrudan istemcinin gönderdiği JSON'dan alınıyordu —
        // bu sunucu (qr_menu_sunucu_servisi.dart) kimlik doğrulaması
        // yapmıyor, aynı WiFi ağındaki HERKES doğrudan POST atabiliyor.
        // Artık fiyat/KDV HER ZAMAN yerel 'urunler' tablosundan okunuyor;
        // istemcinin gönderdiği tutar hiç güvenilmiyor.
        double birimFiyat = 0;
        double kdvOran = 18;
        final urunSatir = await db.query('urunler',
            columns: ['satis_fiyati', 'kdv_oran'], where: 'id = ?', whereArgs: [c.urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          birimFiyat = (urunSatir.first['satis_fiyati'] as num?)?.toDouble() ?? 0;
          kdvOran = UrunModel.kdvOranCoz(urunSatir.first['kdv_oran']);
        }

        final notDeger = k['not']?.toString();
        await masaDepo.kalemEkle(
          siparis.id!,
          urunId:     c.urunId,
          urunAdi:    c.urunAdi,
          birimFiyat: birimFiyat,
          kdvOran:    kdvOran,
          miktar:     (k['miktar'] as num?)?.toDouble() ?? 1,
          not_:       (notDeger == null || notDeger.trim().isEmpty) ? null : notDeger,
        );
        eklenen++;
      } catch (e, st) {
        LogServisi().hata('QrMenu kalem hatası (atlandı) — kalem: $k', hata: e, yigin: st);
        atlanan.add(c.urunAdi);
      }
    }
    if (eklenen == 0) {
      throw Exception('Sipariş kaydedilemedi: hiçbir kalem eklenemedi.');
    }
    if (atlanan.isNotEmpty) {
      LogServisi().uyari('QrMenu: masa $masaId → ${atlanan.length} kalem '
          'atlandı: ${atlanan.join(', ')}');
    }
    return atlanan;
  }
}
