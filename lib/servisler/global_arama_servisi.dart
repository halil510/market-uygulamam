// lib/servisler/global_arama_servisi.dart
//
// erp_roadmap_yeni_ekranlar.md madde 23 — "Global Arama": ürün, cari,
// satış, fatura, masa tek bir arama kutusundan bulunabilsin. Önceki
// oturumlarda bu madde hiç doğrulanmamıştı; kontrol edilince tek modül
// içi arama kutularının (ürün ara, cari ara vb.) DIŞINDA gerçek bir
// "her yerde ara" özelliği hiç yoktu — bu dosya onu ekliyor.
//
// Salt-okunur, migration yok. Her kategori kendi tablosunda LIKE ile
// aranır, sonuçlar hafif/UI-dostu bir kayıt (GlobalAramaSonucu) olarak
// döner — tam model nesnesi kurmuyoruz, sadece listede göstermek ve
// doğru detay ekranına yönlendirmek için gereken alanlar.
import '../veri/database/veritabani.dart';

enum GlobalAramaTuru { urun, cari, satis, fatura, masa }

class GlobalAramaSonucu {
  final GlobalAramaTuru tur;
  final int id;
  final String baslik;
  final String altBaslik;
  const GlobalAramaSonucu({
    required this.tur,
    required this.id,
    required this.baslik,
    required this.altBaslik,
  });
}

class GlobalAramaServisi {
  static const _kategoriBasinaLimit = 6;

  Future<List<GlobalAramaSonucu>> ara(String sorguHam) async {
    final sorgu = sorguHam.trim();
    if (sorgu.length < 2) return [];
    final db = await Veritabani().db;
    final q = '%$sorgu%';

    final sonuclar = <GlobalAramaSonucu>[];

    // 🔴 Kullanıcı bulgusu: ürünün alternatif barkodları (`barkodlar`)
    // Global Arama'da da hiç taranmıyordu — bkz. UrunDeposu.ara()
    // üzerindeki aynı düzeltme notu.
    final urunler = await db.rawQuery(
      '''SELECT id, urun_adi, barkod, satis_fiyati FROM urunler
         WHERE (urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?)
           AND is_deleted = 0
         ORDER BY urun_adi ASC LIMIT ?''',
      [q, q, q, q, _kategoriBasinaLimit],
    );
    sonuclar.addAll(urunler.map((r) => GlobalAramaSonucu(
          tur: GlobalAramaTuru.urun,
          id: r['id'] as int,
          baslik: (r['urun_adi'] as String?) ?? '',
          altBaslik: (r['barkod'] as String?)?.isNotEmpty == true
              ? 'Barkod: ${r['barkod']}'
              : 'Ürün',
        )));

    final cariler = await db.rawQuery(
      '''SELECT id, unvan, cari_kodu, telefon, cari_tipi FROM cari
         WHERE (unvan LIKE ? OR cari_kodu LIKE ? OR telefon LIKE ? OR vergi_no LIKE ?)
           AND is_deleted = 0 AND aktif = 1
         ORDER BY unvan ASC LIMIT ?''',
      [q, q, q, q, _kategoriBasinaLimit],
    );
    sonuclar.addAll(cariler.map((r) => GlobalAramaSonucu(
          tur: GlobalAramaTuru.cari,
          id: r['id'] as int,
          baslik: (r['unvan'] as String?) ?? '',
          altBaslik: (r['cari_tipi'] as String?) ?? 'Cari',
        )));

    final satislar = await db.rawQuery(
      '''SELECT id, fis_no, genel_toplam, tarih, iptal FROM satislar
         WHERE fis_no LIKE ? AND is_deleted = 0
         ORDER BY tarih DESC LIMIT ?''',
      [q, _kategoriBasinaLimit],
    );
    sonuclar.addAll(satislar.map((r) => GlobalAramaSonucu(
          tur: GlobalAramaTuru.satis,
          id: r['id'] as int,
          baslik: 'Fiş #${r['fis_no']}',
          altBaslik: (r['iptal'] as int? ?? 0) == 1 ? 'Satış — İptal Edildi' : 'Satış',
        )));

    final faturalar = await db.rawQuery(
      '''SELECT id, fatura_no, cari_id FROM faturalar
         WHERE fatura_no LIKE ? AND durum != 'silindi'
         ORDER BY tarih DESC LIMIT ?''',
      [q, _kategoriBasinaLimit],
    );
    sonuclar.addAll(faturalar.map((r) => GlobalAramaSonucu(
          tur: GlobalAramaTuru.fatura,
          id: r['id'] as int,
          baslik: 'Fatura ${r['fatura_no']}',
          altBaslik: 'Fatura',
        )));

    final masalar = await db.rawQuery(
      '''SELECT id, ad, durum FROM masalar
         WHERE ad LIKE ? AND is_deleted = 0
         ORDER BY ad ASC LIMIT ?''',
      [q, _kategoriBasinaLimit],
    );
    sonuclar.addAll(masalar.map((r) => GlobalAramaSonucu(
          tur: GlobalAramaTuru.masa,
          id: r['id'] as int,
          baslik: (r['ad'] as String?) ?? '',
          altBaslik: (r['durum'] as String?) == 'dolu' ? 'Masa — Dolu' : 'Masa',
        )));

    return sonuclar;
  }
}
