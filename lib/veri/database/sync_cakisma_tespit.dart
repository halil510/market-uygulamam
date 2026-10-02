// lib/veri/database/sync_cakisma_tespit.dart
//
// Saf (DB'siz) fark tespit mantığı — Veritabani.supaKayitlariGuncelle()'dan
// ayrıldı ki DB/singleton'a bağımlı olmadan izole test edilebilsin.
class SyncCakismaTespit {
  /// Karşılaştırmadan hariç tutulan, iş verisi olmayan sütunlar.
  /// 'cihaz_id' kaydı OLUŞTURAN cihazın izidir (iş verisi değil); bir cihaz
  /// boş, öbürü dolu gönderse de gerçek çakışma sayılmaz.
  static const Set<String> metaAlanlari = {'id', 'global_id', 'last_updated', 'cihaz_id'};

  /// Yerel ve gelen (buluttan) satır arasındaki, metadata dışı gerçek
  /// alan farklarını döner: {alan: {'yerel': x, 'gelen': y}}.
  /// Boş map dönerse gerçek bir çakışma yoktur (ör. sadece last_updated
  /// bümlenmiş, veri aynı).
  static Map<String, dynamic> farklariBul(
    Map<String, dynamic> yerelSatir,
    Map<String, dynamic> gelenSatir,
  ) {
    final farklar = <String, dynamic>{};
    for (final alan in gelenSatir.keys) {
      if (metaAlanlari.contains(alan)) continue;
      final yerelDeger = yerelSatir[alan];
      final gelenDeger = gelenSatir[alan];
      if (!_esitMi(yerelDeger, gelenDeger)) {
        farklar[alan] = {'yerel': yerelDeger, 'gelen': gelenDeger};
      }
    }
    return farklar;
  }

  /// [a] ve [b]'yi tip-toleranslı karşılaştırır: her ikisi de sayıysa
  /// (int/double karışık olsa bile — SQLite ve JSON bunu sık karıştırır)
  /// sayısal olarak, aksi halde metin olarak karşılaştırır.
  static bool _esitMi(dynamic a, dynamic b) {
    // Ondalık gösterim farkı (0.8910891089108901 ↔ 0.89108910891089) sahte
    // çakışma üretmesin: ~1e-9 (göreli) altındaki fark eşit sayılır.
    if (a is num && b is num) {
      final x = a.toDouble(), y = b.toDouble();
      final olcek = x.abs() > y.abs() ? x.abs() : y.abs();
      return (x - y).abs() <= 1e-9 * (olcek < 1.0 ? 1.0 : olcek);
    }
    final sa = a?.toString() ?? '', sb = b?.toString() ?? '';
    if (sa == sb) return true;
    // Aynı anı farklı yazan tarih damgaları (yerelde dilimsiz, buluttan
    // '+00:00'/'Z' ekli) eşit sayılır; dilimsiz = UTC.
    final ta = _tarihCoz(sa), tb = _tarihCoz(sb);
    if (ta != null && tb != null) return ta.isAtSameMomentAs(tb);
    return false;
  }

  static final RegExp _isoTarih = RegExp(
      r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$');
  static final RegExp _dilimli = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  static DateTime? _tarihCoz(String s) {
    if (!_isoTarih.hasMatch(s)) return null;
    return DateTime.tryParse(_dilimli.hasMatch(s) ? s : '${s}Z');
  }

  static bool _bos(dynamic v) => v == null || v.toString().isEmpty;

  /// Tüm farklar "yerel boş, gelen dolu" ise yerelde kaybolacak bir değer
  /// yoktur — gelen değer sadece boşluğu doldurur, çakışma sayılmamalı
  /// (ör. cari sonradan inince satış/iade kaydının boş cari_id'sinin dolması).
  static bool sadeceBoslukDoldurma(Map<String, dynamic> farklar) =>
      farklar.isNotEmpty &&
      farklar.values.every((d) => _bos((d as Map)['yerel']) && !_bos(d['gelen']));

  /// farklariBul() ile bulunan bir "fark"ın GERÇEK bir çakışma mı,
  /// yoksa bu cihazın hiç dokunmadığı, başka bir cihazın DAHA ÖNCE
  /// yaptığı normal (tek yönlü) bir senkron güncellemesinin bu cihaza
  /// İLK KEZ ulaşması mı olduğunu ayırt eder.
  ///
  /// ÖNCEDEN bu ayrım hiç yapılmıyordu — yerelde duran ESKİ bir sürüm
  /// ile buluttan gelen YENİ sürüm arasındaki her fark, kullanıcıya
  /// "iki cihaz aynı kaydı bağımsız değiştirdi" gibi gösteriliyordu.
  /// Oysa bu cihaz o kaydı hiç düzenlememiş olabilir — sadece henüz bu
  /// güncellemeyi görmemişti. Gerçek bir çakışma için, yerel kaydın
  /// bu cihazda EN SON BAŞARIYLA BULUTA GÖNDERİLDİĞİ andan SONRA yine
  /// bu cihazda değişmiş olması gerekir (yani hâlâ buluta gitmemiş,
  /// kaybolma riski taşıyan bir yerel değişiklik olması gerekir).
  ///
  /// [sonBasariliGonderim] bilinmiyorsa (bu tablo bu cihazdan hiç
  /// gönderilmediyse) emin olunamaz — güvenli/muhafazakâr tarafta
  /// kalınır ve true (gerçek çakışma sayılır) döner.
  static bool gercekCakismaMi({
    required DateTime? yerelSonGuncelleme,
    required DateTime? sonBasariliGonderim,
  }) {
    if (sonBasariliGonderim == null || yerelSonGuncelleme == null) return true;
    return yerelSonGuncelleme.isAfter(sonBasariliGonderim);
  }

  // ── FAZ 3 (DEEP_AUDIT_REPORT, madde 4 — kullanıcı onayıyla,
  //    2026-09-21) ──────────────────────────────────────────────────
  // "İşlem/hareket verisi" — geri dönüşü olmayan tarihsel kayıtlar
  // (satış, stok/kasa/banka hareketi, iade, puan, audit log vb.).
  // "Master veri"nin (urunler, cari, kullanıcılar vb. — GÜNCEL DURUM
  // varlıkları, "en son düzenleyen kazanır" semantiği doğru olan)
  // AKSİNE, bu tablolarda "daha yeni" olan taraf "daha doğru" anlamına
  // GELMEZ — iki cihaz aynı satırı bağımsız zincirlerle (bakiye_sonrasi,
  // onceki_stok/sonraki_stok) hesaplamış olabilir; körü körüne üzerine
  // yazmak o zinciri sessizce tutarsız bırakabilir. Bu yüzden bu
  // tablolarda GERÇEK bir çakışma (gercekCakismaMi==true) tespit
  // edilirse Veritabani.supaKayitlariGuncelle() otomatik LWW üzerine
  // yazmayı UYGULAMAZ — yerel kayıt olduğu gibi kalır, çakışma yine
  // sync_cakismalar'a düşer (mevcut mekanizma DEĞİŞMEDİ), kullanıcı
  // "Sync Çakışmaları" ekranından (artık gerçekten veri değiştiren)
  // "Buluttaki değer kalsın" ile bilinçli olarak uygulayabilir.
  //
  // Kapsam kararı (madde madde gerekçe):
  // - satislar/satis_kalem/iade/iade_kalem: fiş/kalem — finansal olay.
  // - stok_hareket/kasa_hareketleri/banka_hareketler/kredi_karti_hareket:
  //   zincirli (chain) bakiye hesaplarına sahip ledger'lar — en riskli
  //   sınıf, madde 4'ün asıl hedefi.
  // - puan_hareket/borc_odemeler: aynı ledger deseni (sadakat puanı,
  //   borç ödeme geçmişi).
  // - audit_log/onay_talepleri/adisyon_log/garson_cagri_log/
  //   masa_hareket_log: saf ekleme-log'ları, üzerine yazma anlamsız.
  // - vardiyalar: açılış/kapanış kasa mutabakatı taşıyan bir olay kaydı
  //   (satislar/iade ile aynı sınıf — "fiş" niteliğinde).
  // BİLİNÇLİ OLARAK master sayılanlar: 'cari'/'borclar' (bakiye ALANI
  // ayrıca sürekli yeniden hesaplanan/mutabakat edilen bir toplam —
  // CariDeposu.bakiyeMutabakatYap gibi), 'masalar'/'masa_siparisleri'
  // (açık bir sepetin GÜNCEL durumu, tarihsel bir olay değil),
  // 'donem_kilit'/'devir_checkpoint'/kapanis_snapshot'lar (zaten
  // donem_kilit ile tek-cihaz korumalı, çakışma pratikte imkansıza
  // yakın).
  static const Set<String> islemTablolari = {
    'satislar', 'satis_kalem',
    'stok_hareket',
    'cari_hareket',
    'kasa_hareketleri',
    'banka_hareketler',
    'kredi_karti_hareket',
    'iade', 'iade_kalem',
    'puan_hareket',
    'borc_odemeler',
    'audit_log',
    'onay_talepleri',
    'adisyon_log',
    'garson_cagri_log',
    'masa_hareket_log',
    'vardiyalar',
    // Finansal belge başlık/kalemleri: iki cihazda bağımsız düzenlenen tutar
    // (toplam/kalem) sessizce LWW ile ezilmesin, Sync Çakışmaları'na düşsün.
    'faturalar', 'fatura_detaylari', 'giderler',
    'irsaliyeler', 'irsaliye_kalem',
    'tedarikci_siparisler', 'tedarikci_siparis_kalem',
  };

  static bool islemVerisiMi(String tablo) => islemTablolari.contains(tablo);
}
