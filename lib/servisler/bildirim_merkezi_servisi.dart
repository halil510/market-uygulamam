// lib/servisler/bildirim_merkezi_servisi.dart
//
// Kullanıcı isteği: "bildirim merkezi — stok azaldı, borç günü geldi,
// son kullanma, kasada açık var." Projede ZATEN VAR OLAN bir
// "bildirimler" tablosu ve görüntüleme ekranı vardı (/bildirimler) —
// ama HİÇBİR YERDEN otomatik olarak doldurulmuyordu (tamamen boş
// kalıyordu). Bu servis, o var olan tabloyu GERÇEK, canlı koşullardan
// (kritik stok, vadesi gelen borç, son kullanma tarihi yaklaşan
// ürünler, uzun süredir açık kalan kasa) otomatik olarak besliyor —
// paralel, ayrı bir bildirim sistemi KURMUYOR, var olanı tamamlıyor.
import 'dart:async';
import '../veri/database/veritabani.dart';
import '../depolar/urun_deposu.dart';
import '../depolar/borc_deposu.dart';

class BildirimMerkeziServisi {
  static final BildirimMerkeziServisi _instance = BildirimMerkeziServisi._();
  factory BildirimMerkeziServisi() => _instance;
  BildirimMerkeziServisi._();

  Timer? _timer;

  /// Uygulama açılışında bir kez, sonra periyodik olarak (30 dakikada
  /// bir) canlı koşulları kontrol edip yeni bildirimleri ekler.
  void baslat() {
    _timer?.cancel();
    tazele();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => tazele());
  }

  void durdur() {
    _timer?.cancel();
    _timer = null;
  }

  /// Tüm canlı koşulları kontrol edip, henüz bildirim olarak
  /// eklenmemiş olanları "bildirimler" tablosuna ekler. Aynı koşul
  /// için (hedef_id + hedef_turu eşleşmesiyle) TEKRAR bildirim
  /// oluşturmaz — kullanıcı bir bildirimi okuyup kapatana kadar (veya
  /// koşul gerçekten değişene kadar) tekrar tekrar eklenmez.
  Future<void> tazele() async {
    try {
      await _kritikStokKontrol();
      await _sonKullanmaKontrol();
      await _borcKontrol();
      await _acikKasaKontrol();
    } catch (_) {
      // Bir kategori hata verirse dahi diğerleri denenmeye devam
      // etsin diye her alt-kontrol kendi try/catch'ine sahip.
    }
  }

  Future<void> _ekle({
    required String baslik,
    required String mesaj,
    required String tip,
    required String hedefTuru,
    required int hedefId,
  }) async {
    final db = await Veritabani().db;
    // 🔴 DÜZELTME: Önceden, aynı koşul için (hedef_turu+hedef_id) zaten
    // okunmamış bir bildirim varsa SESSİZCE ATLANIYORDU — bu, koşulun
    // şiddeti değişse bile (ör. "stok azaldı" iken "stok tükendi"
    // hâline gelse bile) bildirimin ESKİ/güncel olmayan mesajla
    // kalmasına yol açıyordu. Artık mevcut bildirim varsa İÇERİĞİ
    // güncelleniyor (tekrar "okunmamış" gibi öne çıkmasın diye tarih
    // değiştirilmiyor), yoksa yeni ekleniyor.
    final mevcut = await db.query('bildirimler',
        where: 'hedef_turu = ? AND hedef_id = ? AND okundu = 0',
        whereArgs: [hedefTuru, hedefId], limit: 1);
    if (mevcut.isNotEmpty) {
      final eskiBaslik = mevcut.first['baslik'] as String?;
      final eskiMesaj  = mevcut.first['mesaj'] as String?;
      final eskiTip    = mevcut.first['tip'] as String?;
      if (eskiBaslik == baslik && eskiMesaj == mesaj && eskiTip == tip) return;
      await db.update('bildirimler', {'baslik': baslik, 'mesaj': mesaj, 'tip': tip},
          where: 'id = ?', whereArgs: [mevcut.first['id']]);
      return;
    }
    await db.insert('bildirimler', {
      'baslik': baslik,
      'mesaj': mesaj,
      'tip': tip,
      'okundu': 0,
      'tarih': DateTime.now().toIso8601String(),
      'hedef_id': hedefId,
      'hedef_turu': hedefTuru,
    });
  }

  Future<void> _kritikStokKontrol() async {
    try {
      final urunler = await UrunDeposu().kritikStoklar(limit: 30);
      for (final u in urunler) {
        if (u.id == null) continue;
        await _ekle(
          baslik: 'Stok Azaldı: ${u.urunAdi}',
          mesaj: 'Mevcut stok: ${u.stok.toStringAsFixed(0)} '
              '(minimum: ${u.minimumStok.toStringAsFixed(0)})',
          tip: u.stok <= 0 ? 'kritik' : 'uyari',
          hedefTuru: 'urun_stok',
          hedefId: u.id!,
        );
      }
    } catch (_) { /* bildirim üretimi kritik değil — hata olursa sessizce geç, uygulamayı bloklama */ }
  }

  Future<void> _sonKullanmaKontrol() async {
    try {
      final db = await Veritabani().db;
      final hedefTarih = DateTime.now().add(const Duration(days: 14)).toIso8601String().split('T').first;
      final rows = await db.rawQuery(
        'SELECT id, urun_adi, son_kullanma_tarihi FROM urunler '
        'WHERE is_deleted = 0 AND aktif = 1 '
        '  AND son_kullanma_tarihi IS NOT NULL AND son_kullanma_tarihi != \'\' '
        '  AND son_kullanma_tarihi <= ? '
        'ORDER BY son_kullanma_tarihi ASC LIMIT 30',
        [hedefTarih],
      );
      final bugun = DateTime.now();
      for (final r in rows) {
        final id = r['id'] as int?;
        if (id == null) continue;
        final tarihStr = r['son_kullanma_tarihi'] as String;
        final tarih = DateTime.tryParse(tarihStr);
        final gecmisMi = tarih != null && tarih.isBefore(bugun);
        await _ekle(
          baslik: gecmisMi
              ? 'Son Kullanma Geçti: ${r['urun_adi']}'
              : 'Son Kullanma Yaklaşıyor: ${r['urun_adi']}',
          mesaj: 'Tarih: $tarihStr',
          tip: gecmisMi ? 'kritik' : 'uyari',
          hedefTuru: 'urun_skt',
          hedefId: id,
        );
      }
    } catch (_) { /* bildirim üretimi kritik değil — hata olursa sessizce geç, uygulamayı bloklama */ }
  }

  Future<void> _borcKontrol() async {
    try {
      final depo = BorcDeposu();
      final gecmis = await depo.vadesiGecenleriGetir();
      final yaklasan = await depo.yaklasanlariGetir(gun: 7);
      for (final b in gecmis) {
        if (b.id == null) continue;
        await _ekle(
          baslik: 'Vadesi Geçen Borç: ${b.baslik}',
          mesaj: 'Tutar: ${(b.tutar - b.odenenTutar).toStringAsFixed(2)} ₺',
          tip: 'kritik',
          hedefTuru: 'borc',
          hedefId: b.id!,
        );
      }
      for (final b in yaklasan) {
        if (b.id == null) continue;
        await _ekle(
          baslik: 'Borç Günü Yaklaşıyor: ${b.baslik}',
          mesaj: 'Son ödeme: ${b.sonOdemeTarihi.toString().split(' ').first}',
          tip: 'uyari',
          hedefTuru: 'borc',
          hedefId: b.id!,
        );
      }
    } catch (_) { /* bildirim üretimi kritik değil — hata olursa sessizce geç, uygulamayı bloklama */ }
  }

  Future<void> _acikKasaKontrol() async {
    try {
      final db = await Veritabani().db;
      final rows = await db.query('vardiyalar',
          where: "durum = 'acik'", orderBy: 'acilis_tarihi ASC', limit: 5);
      final simdi = DateTime.now();
      for (final v in rows) {
        final id = v['id'] as int?;
        if (id == null) continue;
        final acilis = DateTime.tryParse(v['acilis_tarihi']?.toString() ?? '');
        if (acilis == null) continue;
        final fark = simdi.difference(acilis);
        // 16 saatten uzun süredir açık kalan vardiya — muhtemelen
        // kapatılması unutulmuş.
        if (fark.inHours >= 16) {
          await _ekle(
            baslik: 'Kasa Uzun Süredir Açık',
            mesaj: '${fark.inHours} saattir kapatılmamış bir vardiya var',
            tip: 'uyari',
            hedefTuru: 'vardiya_acik',
            hedefId: id,
          );
        }
      }
    } catch (_) { /* bildirim üretimi kritik değil — hata olursa sessizce geç, uygulamayı bloklama */ }
  }
}
