// lib/servisler/donem_devir_servisi.dart
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — FAZ 5 (2026-09-16,
// kullanıcı onaylı mimari plan raporu). Bu dosya devir motorunun 10
// fazının HEPSİNİ içerir (Madde 17) — ama son üçü (Açılış/Kapanış/
// Doğrulama) BİLİNÇLİ olarak sınırlı bir kapsamda uygulanıyor, aşağıya bkz.
//
// FAZ 3 (Arşivleme) artık GERÇEK bir kopyalama yapıyor (DonemArsivServisi
// — bkz. o dosyanın başı) — ama SADECE kopyalama, aktif tablolardan
// SİLME YOK. Bu yüzden aşağıdaki kritik bulgu HÂLÂ tam olarak geçerli.
//
// 🔴🔴 KRİTİK MİMARİ BULGU (FAZ 4'te tespit edildi, kod yazmadan ÖNCE
// düşünüldü): Madde 8/9/10/11 "açılış kaydı" için STOK_DEVIR/CARI_DEVIR/
// KASA_DEVIR/BANKA_DEVIR gibi YENİ bir hareket satırı yazılmasını
// örnekliyor. Ama bu uygulamada stok/cari/kasa/banka bakiyeleri
// event-sourcing ile (stok_hareket/cari_hareket/kasa_hareketleri/
// banka_hareketler toplamından) hesaplanıyor — TEK, sürekli büyüyen bir
// defter, dönem sınırı YOK. Eski yılın satırları aktif tablodan HENÜZ
// ÇIKARILMADIĞI (sadece kopyalandığı) sürece, buraya "yeni dönem açılış
// hareketi" diye YENİ bir satır eklenirse, mutabakat SUM'u bu satırı da
// sayar → bakiye ÇİFT SAYILIR (ör. 125 adet stok, +125'lik bir
// "STOK_DEVIR" satırıyla birlikte 250 görünür). Bu, tam olarak bu
// oturumun önceki fazlarında bulup düzelttiğimiz sınıf bir hata olurdu
// — bilerek YAPILMADI.
//
// Bunun yerine: FAZ 4-7'nin snapshot'ları (kapanis_snapshot tabloları)
// ZATEN kalıcı "bu tarihte bakiye buydu" kaydını taşıyor — canlı
// deftere dokunmadan. FAZ 8 (Açılış Kayıtları) bu mimaride SADECE
// ilerleme işaretler, ledger'a YENİ satır YAZMAZ. Gerçek arşivleme
// (eski satırların aktif tablodan çıkarılması) kurulduğunda, o taşıma
// işleminin KENDİSİ zaten "yeni dönemin temiz başlangıcı" anlamına
// gelecek — ayrıca bir "devir hareketi" icat etmeye gerek kalmayacak.
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
import '../depolar/sube_deposu.dart';
import '../modeller/donem_model.dart';
import '../modeller/devir_checkpoint_model.dart';
import 'donem_arsiv_servisi.dart';
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

  /// Devri BAŞLATMADAN, sadece FAZ 1'in kontrol listesini çalıştırır —
  /// Dönem Yönetimi ekranındaki "Yıl Sonu Kontrolü" butonu için (Madde
  /// 3): kullanıcı devri başlatmadan önce durumu görebilmeli.
  Future<List<DevirKontrolSonucu>> kontrolleriCalistir({required int subeId}) =>
      _fazKontrolCalistir(subeId: subeId);

  /// Kaynak dönemden (şu an açık olan) bir sonraki yıla devri başlatır
  /// veya (yarıda kalmış bir checkpoint varsa) kaldığı yerden devam
  /// ettirir. [subeId] devir-özgü, şube bazlı kontroller (açık vardiya,
  /// açık masa siparişi) için kullanılır — stok/kasa snapshot fazları
  /// da aynı [subeId] ile çalışır.
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

    // FAZ 9'daki "tüm şubeler kapandı mı" kontrolünün doğru
    // çalışabilmesi için TÜM aktif şubeler adına (sadece bu çağrının
    // [subeId]'si değil) bir donem_sube_durumlari satırı var olduğundan
    // emin olunur — idempotent (subeDurumlariniBaslat var olanı atlar).
    final aktifSubeler = await SubeDeposu().aktifOlanlariGetir();
    final aktifSubeIdleri = aktifSubeler
        .map((s) => s['id'] as int?)
        .whereType<int>()
        .toList();
    if (aktifSubeIdleri.isNotEmpty) {
      await _donemDepo.subeDurumlariniBaslat(kaynakDonem.id!, aktifSubeIdleri);
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

    // ── FAZ 3: GERÇEK ARŞİVLEME — SADECE KOPYALAMA ─────────────────────
    // (2026-09-16, kullanıcı onayı: "aktif verinin arşive kopyalanmasını
    // — SADECE kopyalama, silme yok — tasarlayıp kodlamaya başla").
    // 🔴 KAPSAM: satislar/stok_hareket/cari_hareket/kasa_hareketleri/
    // banka_hareketler tablolarından bu dönemin tarih aralığına düşen
    // satırlar arsiv/<YIL>/barkopro_<YIL>.db dosyasına KOPYALANIR ve
    // Madde 19'a göre (satır sayısı + toplam tutar) DOĞRULANIR. AKTİF
    // TABLODAN HİÇBİR SATIR SİLİNMEZ/ÇIKARILMAZ — silme/taşıma alt-fazı
    // (mimari plan §3b, DB şişmesini GERÇEKTEN azaltan adım) BİLİNÇLİ
    // olarak KAPSAM DIŞI, ayrı bir onay turu bekliyor. Doğrulama
    // başarısız olursa devir FAILED olur, "arşiv tamamlandı" işareti
    // konmaz — bkz. DonemArsivServisi dosya başı yorumu.
    if (checkpoint.mevcutFaz < DevirFaz.arsivHazirlama) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.archiving);
      await _checkpointDepo.guncelle(checkpoint);
      await _donemDepo.donemGuncelle(
          kaynakDonem.copyWith(arsivDurumu: AltDurum.devamEdiyor));
      try {
        final sonuclar = await DonemArsivServisi().arsivleVeDogrula(
          donemYili: kaynakDonem.donemYili,
          subeId: subeId,
          baslangic: kaynakDonem.baslangicTarihi,
          bitis: kaynakDonem.bitisTarihi,
        );
        LogServisi().bilgi(
          'DonemDevirServisi.fazArsiv tamamlandı (yıl ${kaynakDonem.donemYili}, şube $subeId)',
          ek: sonuclar.map((s) => '${s.tablo}:${s.kopyalanan}').join(', '),
        );
        await _donemDepo.donemGuncelle(
            kaynakDonem.copyWith(arsivDurumu: AltDurum.tamamlandi));
        checkpoint = checkpoint.copyWith(mevcutFaz: DevirFaz.arsivHazirlama);
        await _checkpointDepo.guncelle(checkpoint);
      } catch (e, st) {
        LogServisi().hata('DonemDevirServisi.fazArsiv', hata: e, yigin: st);
        await _donemDepo.donemGuncelle(
            kaynakDonem.copyWith(arsivDurumu: AltDurum.hatali));
        checkpoint = checkpoint.copyWith(
            durum: DevirDurumu.failed, hataMesaji: 'Arşivleme başarısız: $e');
        await _checkpointDepo.guncelle(checkpoint);
        return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
      }
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

    // ── FAZ 8: AÇILIŞ KAYITLARI ─────────────────────────────────────
    // 🔴 Dosya başındaki KRİTİK MİMARİ BULGU'ya bkz.: bu faz canlı
    // deftere (stok_hareket/cari_hareket/kasa_hareketleri/
    // banka_hareketler) YENİ bir "devir" satırı YAZMAZ — bunu yapmak
    // (gerçek arşivleme, yani eski satırların çıkarılması olmadan)
    // event-sourced bakiyeleri ÇİFT SAYARDI. FAZ 4-7'nin snapshot'ları
    // zaten kalıcı "açılış referansı" görevi görüyor. Bu faz sadece
    // ilerlemeyi işaretler.
    if (checkpoint.mevcutFaz < DevirFaz.acilisKayitlari) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.opening);
      await _checkpointDepo.guncelle(checkpoint);
      checkpoint = checkpoint.copyWith(mevcutFaz: DevirFaz.acilisKayitlari);
      await _checkpointDepo.guncelle(checkpoint);
    }

    // ── FAZ 9: DÖNEM KAPANIŞI ───────────────────────────────────────
    // Bu şubenin durumunu CLOSED yapar; TÜM şubeler CLOSED ise (Madde
    // 29) genel dönemi de CLOSED yapar. Ledger'a dokunmaz — sadece
    // durum alanları.
    if (checkpoint.mevcutFaz < DevirFaz.donemKapanisi) {
      try {
        await _fazDonemKapanisi(kaynakDonem: kaynakDonem, subeId: subeId);
        checkpoint = checkpoint.copyWith(mevcutFaz: DevirFaz.donemKapanisi);
        await _checkpointDepo.guncelle(checkpoint);
      } catch (e, st) {
        LogServisi().hata('DonemDevirServisi.fazDonemKapanisi', hata: e, yigin: st);
        checkpoint = checkpoint.copyWith(
            durum: DevirDurumu.failed, hataMesaji: 'Dönem kapanışı başarısız: $e');
        await _checkpointDepo.guncelle(checkpoint);
        return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
      }
    }

    // ── FAZ 10: DOĞRULAMA ───────────────────────────────────────────
    // 🔴 KAPSAM NOTU: Madde 19'un istediği asıl arşiv doğrulaması (aktif
    // DB satır sayısı == arşiv satır sayısı + toplam tutar eşleşmesi)
    // artık FAZ 3 içinde, kopyalama SIRASINDA yapılıyor (bkz.
    // DonemArsivServisi.arsivleVeDogrula — eşleşmezse zaten orada devir
    // FAILED olur, buraya hiç gelinmez). Checksum/hash tabanlı doğrulama
    // henüz YOK (basit COUNT+SUM kullanılıyor). Bu faz (FAZ 10) ONUN
    // YERİNE GEÇMİYOR — ayrıca FAZ 4-7'nin snapshot'larının GERÇEKTEN
    // yazıldığını (satır sayıları makul mü) doğrulayan, tamamlayıcı
    // hafif bir öz-tutarlılık kontrolü.
    if (checkpoint.mevcutFaz < DevirFaz.dogrulama) {
      checkpoint = checkpoint.copyWith(durum: DevirDurumu.verifying);
      await _checkpointDepo.guncelle(checkpoint);
      try {
        await _fazDogrulama(donemId: kaynakDonem.id!, subeId: subeId);
        checkpoint = checkpoint.copyWith(
          mevcutFaz: DevirFaz.dogrulama,
          durum: DevirDurumu.completed,
          tamamlanmaZamani: DateTime.now(),
        );
        await _checkpointDepo.guncelle(checkpoint);
      } catch (e, st) {
        LogServisi().hata('DonemDevirServisi.fazDogrulama', hata: e, yigin: st);
        checkpoint = checkpoint.copyWith(
            durum: DevirDurumu.failed, hataMesaji: 'Doğrulama başarısız: $e');
        await _checkpointDepo.guncelle(checkpoint);
        return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
      }
    }

    return DevirSonucu(checkpoint: checkpoint, kontroller: kontroller);
  }

  // ── FAZ 9 detay: dönem kapanışı ─────────────────────────────────────
  Future<void> _fazDonemKapanisi({required DonemModel kaynakDonem, required int subeId}) async {
    final subeDurumlari = await _donemDepo.subeDurumlariGetir(kaynakDonem.id!);
    final now = DateTime.now();
    final mevcut = subeDurumlari.where((d) => d.subeId == subeId);
    if (mevcut.isNotEmpty && mevcut.first.id != null) {
      await _donemDepo.subeDurumuGuncelle(mevcut.first.copyWith(
        durum: DonemDurumu.kapali,
        kapanisTarihi: now,
        backupDurumu: AltDurum.tamamlandi,
        arsivDurumu: AltDurum.tamamlandi,
        devirDurumu: AltDurum.tamamlandi,
      ));
    } else {
      // Beklenmedik durum (subeDurumlariniBaslat başta çalıştı ama bu
      // şube o listede yoktu — ör. pasif/silinmiş bir şube) — yine de
      // kaydı burada oluştur, devir sonucu kaybolmasın.
      await _donemDepo.subeDurumlariniBaslat(kaynakDonem.id!, [subeId]);
      final guncel = await _donemDepo.subeDurumlariGetir(kaynakDonem.id!);
      final satir = guncel.where((d) => d.subeId == subeId);
      if (satir.isNotEmpty && satir.first.id != null) {
        await _donemDepo.subeDurumuGuncelle(satir.first.copyWith(
          durum: DonemDurumu.kapali,
          kapanisTarihi: now,
          backupDurumu: AltDurum.tamamlandi,
          arsivDurumu: AltDurum.tamamlandi,
          devirDurumu: AltDurum.tamamlandi,
        ));
      }
    }

    // Madde 29: genel şirket dönemi ancak TÜM şubeler kapandığında kapanır.
    final tumuKapandi = await _donemDepo.tumSubelerKapandiMi(kaynakDonem.id!);
    if (tumuKapandi) {
      await _donemDepo.donemGuncelle(kaynakDonem.copyWith(
        durum: DonemDurumu.kapali,
        kapanisTarihi: now,
        devirDurumu: AltDurum.tamamlandi,
      ));
    }
  }

  // ── FAZ 10 detay: hafif öz-tutarlılık doğrulaması ────────────────────
  Future<void> _fazDogrulama({required int donemId, required int subeId}) async {
    final db = await Veritabani().db;

    final stokSayimi = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM stok_kapanis_snapshot WHERE donem_id = ? AND sube_id = ?',
      [donemId, subeId],
    );
    final stokBeklenen = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM sube_urun su JOIN urunler u ON u.id = su.urun_id '
      'WHERE su.sube_id = ? AND u.is_deleted = 0',
      [subeId],
    );
    final stokN = (stokSayimi.first['n'] as int?) ?? 0;
    final stokBeklenenN = (stokBeklenen.first['n'] as int?) ?? 0;
    if (stokN != stokBeklenenN) {
      throw StateError(
          'Stok snapshot satır sayısı ($stokN) beklenenle ($stokBeklenenN) uyuşmuyor.');
    }

    final kasaSayimi = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM kasa_kapanis_snapshot WHERE donem_id = ? AND sube_id = ?',
      [donemId, subeId],
    );
    if (((kasaSayimi.first['n'] as int?) ?? 0) < 1) {
      throw StateError('Kasa snapshot kaydı bulunamadı.');
    }

    // Cari/banka (şirket geneli) — en az bir satır beklenir (hiç cari/
    // banka hesabı yoksa 0 da geçerli sayılır, o yüzden sadece sorgu
    // hatasız çalışıyor mu diye bakılır, sayım zorunlu tutulmaz).
    await db.rawQuery(
        'SELECT COUNT(*) AS n FROM cari_kapanis_snapshot WHERE donem_id = ?', [donemId]);
    await db.rawQuery(
        'SELECT COUNT(*) AS n FROM banka_kapanis_snapshot WHERE donem_id = ?', [donemId]);
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

  // 🔴 DÜZELTME (Yıl Sonu Devir denetimi, 2026-09-20 — "devir hiç
  // olmuyor" kök nedeni): bu kontrol ÖNCEDEN CRITICAL (kirmizi)
  // döndüğünde FAZ 1 devri anında `failed` yapıp durduruyordu (bkz.
  // _fazKontrolCalistir çağıranı, satır ~182: sadece kirmizi = engelliyorMu).
  // Gerçek POS kullanımında kasiyer günü vardiya AÇARAK başlar ve bu
  // uygulamada satış yapmak için vardiya açık olma ZORUNLULUĞU bile
  // yoktur — yani NEREDEYSE HER ZAMAN açık bir vardiya vardır ve devir
  // sihirbazı HER TIKLANDIĞINDA aynı noktada, "Kritik kontrol(ler)
  // başarısız: Açık Vardiya" ile hemen bitiyordu. Kullanıcı bunu "sistem
  // çalışmıyor" olarak deneyimliyordu. Artık _acikMasaSiparisiKontrol
  // ile AYNI desen kullanılıyor: bilgilendirme amaçlı WARNING (sari) —
  // devri ENGELLEMEZ, ama kullanıcı bilinçli olsun diye gösterilir
  // (kasa mutabakatı gerçekten etkilenebilir, bu risk mesajda kalıyor).
  Future<DevirKontrolSonucu> _acikVardiyaKontrol(int subeId) async {
    try {
      final vardiya = await VardiyaDeposu()
          .aktifVardiyaGetir(subeId: subeId > 0 ? subeId : null);
      final acik = vardiya != null;
      return DevirKontrolSonucu(
        id: 'acik_vardiya',
        baslik: 'Açık Vardiya',
        durum: acik ? SaglikDurum.sari : SaglikDurum.yesil,
        mesaj: acik
            ? 'Kapatılmamış bir vardiya var — kasa mutabakatı güvenilir olmayabilir. Mümkünse devirden önce vardiyayı kapatın (zorunlu değil).'
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
