// lib/servisler/donem_devir_servisi.dart
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — FAZ 3 (2026-09-16,
// kullanıcı onaylı mimari plan raporu). Bu dosya devir motorunun İLK
// YEDİ fazını (Madde 17: Kontrol, Backup, Archive hazırlama, Stok/Cari/
// Kasa/Banka Snapshot) gerçek olarak uygular.
//
// 🔴 DÜRÜSTLÜK NOTU: Madde 17'nin tanımladığı 10 faz vardır. Bu dosya
// SADECE ilk yedisini içerir — Açılış Kayıtları/Dönem Kapanışı/
// Doğrulama (8-10) İLERİKİ bir fazda eklenecek. devirBaslatVeyaDevamEt()
// bilerek FAZ 7'den SONRA durur; checkpoint.durum='COMPLETED' asla
// burada set edilmez (Madde 28: bu alan SADECE tüm devir bittiğinde
// 'tamamlandı' anlamına gelmeli).
//
// Resumable state-machine ilkesi (Madde 17/27): her faz kendi işini
// BİTİRDİKTEN SONRA checkpoint'i ilerletir. Böylece bir kesinti (uygulama
// çökmesi/güç kesintisi) olursa, bir sonraki çağrı kaldığı fazdan devam
// eder — daha önce tamamlanmış bir faz TEKRAR çalıştırılmaz. Snapshot
// fazları AYRICA kendi içlerinde idempotent'tir (ConflictAlgorithm.replace,
// UNIQUE kısıtına göre) — aynı faz iki kez çalışsa bile veri çoğalmaz.
//
// 🔴 BİLİNÇLİ TASARIM SINIRLAMASI (cari/banka company-wide fazlar):
// devirBaslatVeyaDevamEt() TEK bir [subeId] alır ve TEK bir checkpoint
// üzerinden ilerler. Ancak cari ve banka bakiyeleri bu uygulamada ŞUBE
// BAZLI DEĞİL (cari_hareket/banka_hesaplar'da sube_id yok — bkz.
// donem_semasi.dart baş yorumu) — yani CariSnapshot/BankaSnapshot
// fazları kavramsal olarak "şirket geneli"dir. Çok şubeli bir devirde
// (her şube için ayrı ayrı devirBaslatVeyaDevamEt çağrılırsa) bu iki faz
// BİRDEN FAZLA KEZ çalışabilir — ama UPSERT (ConflictAlgorithm.replace)
// idempotent olduğundan bu ZARARSIZDIR, sadece gereksiz tekrar
// hesaplamadır. Tam bir "şirket geneli tek checkpoint" ayrımı (ayrı bir
// devir_checkpoint.sube_id=0 akışı) İLERİKİ bir fazda değerlendirilebilir.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../depolar/donem_deposu.dart';
import '../depolar/devir_checkpoint_deposu.dart';
import '../depolar/vardiya_deposu.dart';
import '../depolar/banka_hesap_deposu.dart';
import '../depolar/cari_deposu.dart';
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

    // ── FAZ 3: ARCHIVE HAZIRLAMA ────────────────────────────────────
    // 🔴 DÜRÜSTLÜK NOTU: gerçek arşivleme (Supabase _arsiv tabloları,
    // SQLite ikinci salt-okunur bağlantı) henüz kurulmadı (mimari plan
    // raporundaki §1b/§3 — İLERİKİ bir fazda). Bu faz şu an SADECE
    // FAZ 2'nin ürettiği tam yedeği "bu dönemin arşiv temeli" olarak
    // işaretler — kayıt taşıma/silme YAPMAZ, kaynak veriye DOKUNMAZ.
    if (checkpoint.mevcutFaz < DevirFaz.arsivHazirlama) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.archiving);
      await _checkpointDepo.guncelle(checkpoint);
      await _donemDepo.donemGuncelle(
          kaynakDonem.copyWith(arsivDurumu: AltDurum.devamEdiyor));
      checkpoint = checkpoint.copyWith(mevcutFaz: DevirFaz.arsivHazirlama);
      await _checkpointDepo.guncelle(checkpoint);
    }

    // ── FAZ 4: STOK SNAPSHOT ────────────────────────────────────────
    if (checkpoint.mevcutFaz < DevirFaz.stokSnapshot) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.snapshotStok);
      await _checkpointDepo.guncelle(checkpoint);
      try {
        await _stokSnapshotAl(
            devirId: checkpoint.devirId, donemId: kaynakDonem.id!, subeId: subeId);
        checkpoint = checkpoint.copyWith(mevcutFaz: DevirFaz.stokSnapshot);
        await _checkpointDepo.guncelle(checkpoint);
      } catch (e, st) {
        LogServisi().hata('DonemDevirServisi.fazStokSnapshot', hata: e, yigin: st);
        checkpoint = checkpoint.copyWith(
            durum: DevirDurumu.failed, hataMesaji: 'Stok snapshot başarısız: $e');
        await _checkpointDepo.guncelle(checkpoint);
        return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
      }
    }

    // ── FAZ 5: CARİ SNAPSHOT (şirket geneli — bkz. dosya baş yorumu) ──
    if (checkpoint.mevcutFaz < DevirFaz.cariSnapshot) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.snapshotCari);
      await _checkpointDepo.guncelle(checkpoint);
      try {
        await _cariSnapshotAl(devirId: checkpoint.devirId, donemId: kaynakDonem.id!);
        checkpoint = checkpoint.copyWith(mevcutFaz: DevirFaz.cariSnapshot);
        await _checkpointDepo.guncelle(checkpoint);
      } catch (e, st) {
        LogServisi().hata('DonemDevirServisi.fazCariSnapshot', hata: e, yigin: st);
        checkpoint = checkpoint.copyWith(
            durum: DevirDurumu.failed, hataMesaji: 'Cari snapshot başarısız: $e');
        await _checkpointDepo.guncelle(checkpoint);
        return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
      }
    }

    // ── FAZ 6: KASA SNAPSHOT ────────────────────────────────────────
    if (checkpoint.mevcutFaz < DevirFaz.kasaSnapshot) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.snapshotKasa);
      await _checkpointDepo.guncelle(checkpoint);
      try {
        await _kasaSnapshotAl(
            devirId: checkpoint.devirId, donemId: kaynakDonem.id!, subeId: subeId);
        checkpoint = checkpoint.copyWith(mevcutFaz: DevirFaz.kasaSnapshot);
        await _checkpointDepo.guncelle(checkpoint);
      } catch (e, st) {
        LogServisi().hata('DonemDevirServisi.fazKasaSnapshot', hata: e, yigin: st);
        checkpoint = checkpoint.copyWith(
            durum: DevirDurumu.failed, hataMesaji: 'Kasa snapshot başarısız: $e');
        await _checkpointDepo.guncelle(checkpoint);
        return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
      }
    }

    // ── FAZ 7: BANKA SNAPSHOT (şirket geneli — bkz. dosya baş yorumu) ─
    if (checkpoint.mevcutFaz < DevirFaz.bankaSnapshot) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.snapshotBanka);
      await _checkpointDepo.guncelle(checkpoint);
      try {
        await _bankaSnapshotAl(devirId: checkpoint.devirId, donemId: kaynakDonem.id!);
        checkpoint = checkpoint.copyWith(mevcutFaz: DevirFaz.bankaSnapshot);
        await _checkpointDepo.guncelle(checkpoint);
      } catch (e, st) {
        LogServisi().hata('DonemDevirServisi.fazBankaSnapshot', hata: e, yigin: st);
        checkpoint = checkpoint.copyWith(
            durum: DevirDurumu.failed, hataMesaji: 'Banka snapshot başarısız: $e');
        await _checkpointDepo.guncelle(checkpoint);
        return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
      }
    }

    // 🔴 FAZ 8-10 (Açılış Kayıtları, Dönem Kapanışı, Doğrulama) İLERİKİ
    // fazlarda eklenecek. Checkpoint şu an mevcut_faz=7 (BANKA SNAPSHOT
    // tamamlandı) durumunda bırakılıyor. durum'u BİLEREK COMPLETED
    // yapmıyoruz.
    return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
  }

  // ── FAZ 4 detay: stok snapshot ──────────────────────────────────────
  // sube_urun (şube bazlı stok payı) tablosundan okur. NOT: bir ürünün
  // bu şubede hiç sube_urun satırı yoksa (o şubeye hiç transfer/stok
  // hareketi işlenmemişse) bu ürün snapshot'a DAHİL EDİLMEZ — bilinen,
  // dokümante edilmiş bir sınırlama (çok şubeli kurulumlarda nadir).
  Future<void> _stokSnapshotAl(
      {required String devirId, required int donemId, required int subeId}) async {
    final db = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT su.urun_id AS urun_id, su.stok AS miktar
      FROM sube_urun su
      JOIN urunler u ON u.id = su.urun_id
      WHERE su.sube_id = ? AND u.is_deleted = 0
    ''', [subeId]);

    await db.transaction((txn) async {
      for (final r in rows) {
        await txn.insert(
          'stok_kapanis_snapshot',
          {
            'global_id': const Uuid().v4(),
            'devir_id': devirId,
            'donem_id': donemId,
            'sube_id': subeId,
            'urun_id': r['urun_id'],
            'miktar': (r['miktar'] as num?)?.toDouble() ?? 0,
            'olusturma_tarihi': DateTime.now().toIso8601String(),
            'last_updated': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ── FAZ 5 detay: cari snapshot ──────────────────────────────────────
  Future<void> _cariSnapshotAl({required String devirId, required int donemId}) async {
    // Yüksek bir limit — "tümü" anlamına gelmesi için (varsayılan limit
    // 500'dü, büyük cari defterlerinde sessizce kesilirdi).
    final cariler = await CariDeposu().tumunuGetir(limit: 1000000);
    final db = await Veritabani().db;
    await db.transaction((txn) async {
      for (final c in cariler) {
        if (c.id == null) continue;
        await txn.insert(
          'cari_kapanis_snapshot',
          {
            'global_id': const Uuid().v4(),
            'devir_id': devirId,
            'donem_id': donemId,
            'cari_id': c.id,
            'bakiye': c.bakiye,
            'olusturma_tarihi': DateTime.now().toIso8601String(),
            'last_updated': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ── FAZ 6 detay: kasa snapshot ──────────────────────────────────────
  // KasaDeposu.guncelBakiye() KASITLI olarak kullanılmadı — o metod
  // AktifSubeServisi().subeId'ye (o anki seçili şube) bağımlı, ama devir
  // BAŞKA bir şube için çalışıyor olabilir. Aynı formül (bakiye_sonrasi
  // zincirinin son satırı) burada [subeId] parametresiyle açıkça
  // tekrarlanıyor — bkz. KasaDeposu._sonBakiyeTxn ile AYNI mantık.
  Future<void> _kasaSnapshotAl(
      {required String devirId, required int donemId, required int subeId}) async {
    final db = await Veritabani().db;
    final rows = await db.rawQuery(
      'SELECT bakiye_sonrasi FROM kasa_hareketleri '
      'WHERE deleted_at IS NULL AND sube_id = ? ORDER BY tarih DESC, id DESC LIMIT 1',
      [subeId],
    );
    final bakiye =
        rows.isEmpty ? 0.0 : ((rows.first['bakiye_sonrasi'] as num?)?.toDouble() ?? 0.0);

    await db.insert(
      'kasa_kapanis_snapshot',
      {
        'global_id': const Uuid().v4(),
        'devir_id': devirId,
        'donem_id': donemId,
        'sube_id': subeId,
        'bakiye': bakiye,
        'olusturma_tarihi': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── FAZ 7 detay: banka snapshot ─────────────────────────────────────
  Future<void> _bankaSnapshotAl({required String devirId, required int donemId}) async {
    final hesaplar = await BankaHesapDeposu().tumunuGetir();
    final db = await Veritabani().db;
    await db.transaction((txn) async {
      for (final h in hesaplar) {
        if (h.id == null) continue;
        await txn.insert(
          'banka_kapanis_snapshot',
          {
            'global_id': const Uuid().v4(),
            'devir_id': devirId,
            'donem_id': donemId,
            'banka_hesap_id': h.id,
            'bakiye': h.bakiye,
            'olusturma_tarihi': DateTime.now().toIso8601String(),
            'last_updated': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
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
