// lib/servisler/donem_devir_servisi.dart
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — FAZ 2 (2026-09-16,
// kullanıcı onaylı mimari plan raporu). Bu dosya devir motorunun İLK İKİ
// fazını (Madde 17: Kontrol, Backup) gerçek olarak uygular.
//
// 🔴 DÜRÜSTLÜK NOTU: Madde 17'nin tanımladığı 10 faz vardır (Kontrol →
// Backup → Archive hazırlama → Stok/Cari/Kasa/Banka Snapshot → Açılış
// Kayıtları → Dönem Kapanışı → Doğrulama). Bu dosya SADECE ilk ikisini
// (Kontrol, Backup) içerir — 3-10 arası fazlar İLERİKİ fazlarda
// eklenecek. devirBaslatVeyaDevamEt() bilerek FAZ 2'den SONRA durur;
// checkpoint.durum='COMPLETED' asla burada set edilmez (Madde 28: bu
// alan SADECE tüm devir bittiğinde 'tamamlandı' anlamına gelmeli).
//
// Resumable state-machine ilkesi (Madde 17/27): her faz kendi işini
// BİTİRDİKTEN SONRA checkpoint'i ilerletir. Böylece bir kesinti (uygulama
// çökmesi/güç kesintisi) olursa, bir sonraki çağrı kaldığı fazdan devam
// eder — daha önce tamamlanmış bir faz TEKRAR çalıştırılmaz.
import '../depolar/donem_deposu.dart';
import '../depolar/devir_checkpoint_deposu.dart';
import '../depolar/vardiya_deposu.dart';
import '../modeller/donem_model.dart';
import '../modeller/devir_checkpoint_model.dart';
import 'log_servisi.dart';
import 'onay_merkezi_servisi.dart';
import 'veri_sagligi_servisi.dart';
import 'yedekleme_servisi.dart';
import '../veri/database/veritabani.dart';

/// FAZ 1 (Kontrol) sonucundaki tek bir kalem — VeriSagligiServisi'nin
/// SaglikKontrolSonucu'yla AYNI kategoriler (yesil/sari/kirmizi), ayrı
/// bir tip icat etmek yerine devir-özgü kontroller için de kullanılır.
class DevirKontrolSonucu {
  final String id;
  final String baslik;
  final SaglikDurum durum;
  final String mesaj;
  final int sayi;

  const DevirKontrolSonucu({
    required this.id,
    required this.baslik,
    required this.durum,
    required this.mesaj,
    required this.sayi,
  });

  bool get engelliyorMu => durum == SaglikDurum.kirmizi;
}

/// devirBaslatVeyaDevamEt()'in dönüş değeri — checkpoint + FAZ 1'in tüm
/// kontrol sonuçları (UI'da "🟢 Hazır / 🟡 Uyarı / 🔴 Kritik" listesi
/// olarak gösterilmek üzere, Madde 25).
class DevirSonucu {
  final DevirCheckpointModel checkpoint;
  final List<DevirKontrolSonucu> kontroller;

  const DevirSonucu({required this.checkpoint, required this.kontroller});

  bool get kontrolBasarisizMi => kontroller.any((k) => k.engelliyorMu);
}

class DonemDevirServisi {
  final _donemDepo = DonemDeposu();
  final _checkpointDepo = DevirCheckpointDeposu();
  final _veriSagligi = VeriSagligiServisi();

  /// Kaynak dönemden (şu an açık olan) bir sonraki yıla devri başlatır
  /// veya (yarıda kalmış bir checkpoint varsa) kaldığı yerden devam
  /// ettirir. [subeId] devir-özgü, şube bazlı kontroller (açık vardiya,
  /// açık masa siparişi) için kullanılır — stok/kasa snapshot fazları
  /// (İLERİKİ FAZ) da aynı [subeId] ile çalışacak.
  Future<DevirSonucu> devirBaslatVeyaDevamEt({required int subeId}) async {
    final kaynakDonem = await _donemDepo.aktifDonemGetir();
    if (kaynakDonem == null) {
      throw StateError(
          'Açık bir dönem bulunamadı — önce Dönem Yönetimi ekranından bir dönem açılmalı.');
    }
    if (kaynakDonem.id == null) {
      throw StateError('Kaynak dönem kaydı geçersiz (id yok).');
    }

    // Hedef dönem (bir sonraki yıl) henüz yoksa, checkpoint'in
    // referans verebilmesi için ÖNCEDEN oluşturulur — durum='OPEN' ile
    // başlar ama kaynak dönem CLOSED olana kadar "aktif çalışma dönemi"
    // anlamına gelmez (bu ayrım İLERİKİ fazlarda, FAZ 9 Dönem
    // Kapanışı'nda netleşir).
    var hedefDonem = await _donemDepo.yilaGoreGetir(kaynakDonem.donemYili + 1);
    if (hedefDonem == null) {
      final yeniYil = kaynakDonem.donemYili + 1;
      final hedefId = await _donemDepo.donemOlustur(DonemModel(
        donemYili: yeniYil,
        baslangicTarihi: DateTime(yeniYil, 1, 1),
        bitisTarihi: DateTime(yeniYil, 12, 31, 23, 59, 59),
      ));
      hedefDonem = await _donemDepo.yilaGoreGetir(yeniYil);
      if (hedefDonem == null || hedefDonem.id != hedefId) {
        // Beklenmeyen durum — yine de devam edebilmek için tekrar oku.
        hedefDonem = await _donemDepo.yilaGoreGetir(yeniYil);
      }
    }
    if (hedefDonem?.id == null) {
      throw StateError('Hedef dönem oluşturulamadı.');
    }

    var checkpoint = await _checkpointDepo.checkpointOlusturVeyaGetir(
      kaynakDonemId: kaynakDonem.id!,
      hedefDonemId: hedefDonem!.id!,
      subeId: subeId,
    );

    // Madde 28 (idempotency): zaten tamamlanmış bir devri sessizce
    // tekrar çalıştırmaz — olduğu gibi döner.
    if (checkpoint.tamamlandiMi) {
      return DevirSonucu(checkpoint: checkpoint, kontroller: const []);
    }

    // ── FAZ 1: KONTROL ──────────────────────────────────────────────
    List<DevirKontrolSonucu> kontroller = const [];
    if (checkpoint.mevcutFaz < DevirFaz.kontrol) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.checking);
      await _checkpointDepo.guncelle(checkpoint);

      kontroller = await _fazKontrolCalistir(subeId: subeId);
      final basarisizlar = kontroller.where((k) => k.engelliyorMu).toList();

      if (basarisizlar.isNotEmpty) {
        checkpoint = checkpoint.copyWith(
          durum: DevirDurumu.failed,
          hataMesaji: 'Kritik kontrol(ler) başarısız: '
              '${basarisizlar.map((k) => k.baslik).join(', ')}',
        );
        await _checkpointDepo.guncelle(checkpoint);
        return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
      }

      checkpoint = checkpoint.copyWith(mevcutFaz: DevirFaz.kontrol);
      await _checkpointDepo.guncelle(checkpoint);
    }

    // ── FAZ 2: BACKUP ───────────────────────────────────────────────
    if (checkpoint.mevcutFaz < DevirFaz.yedek) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.backup);
      await _checkpointDepo.guncelle(checkpoint);

      try {
        final yedekYolu = await YedeklemeServisi().yedekAl();
        await _donemDepo.donemGuncelle(
            kaynakDonem.copyWith(backupDurumu: AltDurum.tamamlandi));
        checkpoint = checkpoint.copyWith(
          mevcutFaz: DevirFaz.yedek,
          fazIlerlemeJson: '{"yedek_yolu":"$yedekYolu"}',
        );
        await _checkpointDepo.guncelle(checkpoint);
      } catch (e, st) {
        LogServisi().hata('DonemDevirServisi.fazYedek', hata: e, yigin: st);
        await _donemDepo.donemGuncelle(
            kaynakDonem.copyWith(backupDurumu: AltDurum.hatali));
        checkpoint = checkpoint.copyWith(
          durum: DevirDurumu.failed,
          hataMesaji: 'Yedekleme başarısız: $e',
        );
        await _checkpointDepo.guncelle(checkpoint);
        return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
      }
    }

    // 🔴 FAZ 3-10 (Archive hazırlama, Stok/Cari/Kasa/Banka Snapshot,
    // Açılış Kayıtları, Dönem Kapanışı, Doğrulama) İLERİKİ fazlarda
    // eklenecek. Checkpoint şu an mevcut_faz=2 (BACKUP tamamlandı)
    // durumunda bırakılıyor — bir sonraki çağrı (devir motoru
    // genişletildiğinde) buradan devam edecek. durum'u BİLEREK
    // COMPLETED yapmıyoruz.
    return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
  }

  // ── FAZ 1 detay: kontrol listesi ────────────────────────────────────
  Future<List<DevirKontrolSonucu>> _fazKontrolCalistir({required int subeId}) async {
    final sonuclar = <DevirKontrolSonucu>[];

    // Mevcut Veri Sağlığı Merkezi kontrolleri (Madde 4'ün büyük kısmı
    // zaten burada karşılanıyor: SQLite bütünlüğü, foreign key, cari/
    // stok/kasa/banka/kredi kartı mutabakatı, satış-kasa/satış-stok
    // tutarlılığı, negatif stok, sync kuyruğu, sync çakışmaları,
    // yedekleme durumu — bkz. VeriSagligiServisi.tumKontrolleriCalistir).
    final saglikSonuclari = await _veriSagligi.tumKontrolleriCalistir();
    for (final s in saglikSonuclari) {
      sonuclar.add(DevirKontrolSonucu(
        id: s.id, baslik: s.baslik, durum: s.durum, mesaj: s.mesaj, sayi: s.sayi,
      ));
    }

    // Devir-özgü ek kontroller (VeriSagligiServisi kapsamında OLMAYAN):
    sonuclar.add(await _acikVardiyaKontrol(subeId));
    sonuclar.add(await _acikMasaSiparisiKontrol(subeId));
    sonuclar.add(await _bekleyenOnayKontrol());

    // 🔴 DÜRÜSTLÜK NOTU: Madde 4'ün istediği "açık satış/açık fiş" ve
    // "açık transfer" kontrolleri buraya BİLEREK eklenmedi — bu
    // mimaride bir satış/transfer İŞLEM İÇİNDE (transaction) atomik
    // olarak tamamlanır, "yarım kalmış ama görünür" bir ara durum
    // veritabanında YOK (ya tam yazılır ya hiç). "Açık sayım" da aynı
    // sebeple ölçülemez — stok sayımı kalıcı bir taslak tablosunda
    // değil, sadece ekran belleğinde (stok_sayim_provider) tutulur,
    // onaylandığında doğrudan stok_hareket'e yazılır. Bu üçü için DB
    // seviyesinde anlamlı bir "açık mı" sinyali yok.
    return sonuclar;
  }

  Future<DevirKontrolSonucu> _acikVardiyaKontrol(int subeId) async {
    try {
      final vardiya = await VardiyaDeposu()
          .aktifVardiyaGetir(subeId: subeId > 0 ? subeId : null);
      final acik = vardiya != null;
      return DevirKontrolSonucu(
        id: 'acik_vardiya',
        baslik: 'Açık Vardiya',
        durum: acik ? SaglikDurum.kirmizi : SaglikDurum.yesil,
        mesaj: acik
            ? 'Kapatılmamış bir vardiya var — kasa mutabakatı güvenilir olmayabilir, devirden önce vardiyayı kapatın.'
            : 'Açık vardiya yok.',
        sayi: acik ? 1 : 0,
      );
    } catch (e) {
      return DevirKontrolSonucu(
        id: 'acik_vardiya', baslik: 'Açık Vardiya',
        durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1,
      );
    }
  }

  Future<DevirKontrolSonucu> _acikMasaSiparisiKontrol(int subeId) async {
    try {
      final db = await Veritabani().db;
      final subeSarti = subeId > 0 ? ' AND m.sube_id = ?' : '';
      final args = <Object?>['acik', if (subeId > 0) subeId];
      final rows = await db.rawQuery('''
        SELECT COUNT(*) AS n FROM masa_siparisleri ms
        JOIN masalar m ON m.id = ms.masa_id
        WHERE ms.durum = ? AND (ms.is_deleted IS NULL OR ms.is_deleted = 0)$subeSarti
      ''', args);
      final sayi = (rows.first['n'] as int?) ?? 0;
      return DevirKontrolSonucu(
        id: 'acik_masa_siparisi',
        baslik: 'Açık Masa Siparişi',
        // Bilgilendirme amaçlı (WARNING) — devam eden bir masa siparişi
        // devri ENGELLEMEMELİ (Madde 4: sadece CRITICAL engeller),
        // sadece kullanıcı bilinçli olsun diye gösterilir.
        durum: sayi == 0 ? SaglikDurum.yesil : SaglikDurum.sari,
        mesaj: sayi == 0
            ? 'Açık masa siparişi yok.'
            : '$sayi masa siparişi hâlâ açık (ödenmemiş).',
        sayi: sayi,
      );
    } catch (e) {
      return DevirKontrolSonucu(
        id: 'acik_masa_siparisi', baslik: 'Açık Masa Siparişi',
        durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1,
      );
    }
  }

  Future<DevirKontrolSonucu> _bekleyenOnayKontrol() async {
    try {
      final sayi = await OnayMerkeziServisi().gorulmemisSayisi();
      return DevirKontrolSonucu(
        id: 'bekleyen_onay',
        baslik: 'Bekleyen Onay',
        durum: sayi == 0 ? SaglikDurum.yesil : SaglikDurum.sari,
        mesaj: sayi == 0 ? 'Bekleyen onay yok.' : '$sayi görülmemiş onay talebi var.',
        sayi: sayi,
      );
    } catch (e) {
      return DevirKontrolSonucu(
        id: 'bekleyen_onay', baslik: 'Bekleyen Onay',
        durum: SaglikDurum.sari, mesaj: 'Kontrol edilemedi: $e', sayi: -1,
      );
    }
  }
}
