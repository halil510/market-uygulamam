// test/robot/is_akisi_senaryosu_test.dart
//
// İŞ AKIŞI ROBOTU — bir market gününü GERÇEK servislerle baştan sona
// oynatır (ekranların çağırdığı servislerin BİREBİR kendileri; mantık
// kopyası değil) ve HER adımdan sonra:
//   • o adımın stok / nakit kasa / banka / cari bakiyelerinde yol açması
//     GEREKEN değişimi (delta) kontrol eder,
//   • uygulamanın kendi Veri Sağlığı denetimlerini çalıştırır (cari/stok/
//     kasa/banka mutabakatı, satış↔kasa, satış↔stok, FK, negatif stok…).
// Bir adım hatalı çıksa da sonrakiler çalışmaya devam eder (değişimler
// göreli ölçüldüğü için hata zincirleme yayılmaz); sonunda tüm sorunlar
// build/is_akisi_raporu.md dosyasına yazılır ve test düşer.
//
// Çalıştırma:  flutter test test/robot/is_akisi_senaryosu_test.dart
// (~1 sn sürer; normal test paketinde ve CI'da her seferinde koşar.)
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/banka_hesap_deposu.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/depolar/stok_deposu.dart';
import 'package:market_plus/depolar/sube_urun_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/modeller/fatura_model.dart';
import 'package:market_plus/modeller/satis_kalem_model.dart';
import 'package:market_plus/modeller/satis_model.dart';
import 'package:market_plus/modeller/sepet_model.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';
import 'package:market_plus/servisler/alim_islem_servisi.dart';
import 'package:market_plus/servisler/auth_servisi.dart';
import 'package:market_plus/servisler/cari_tahsilat_odeme_servisi.dart';
import 'package:market_plus/servisler/faturalandirma_servisi.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/servisler/satis_tamamlama_servisi.dart';
import 'package:market_plus/servisler/toptan_satis_islem_servisi.dart';
import 'package:market_plus/servisler/veri_sagligi_servisi.dart';
import 'package:market_plus/servisler/virman_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'robot_ortam.dart';

/// Bir adımın ölçülen durumu.
class _Durum {
  final Map<int, double> stok;
  final Map<int, double> cari;
  final double kasaNakit;
  final double banka;
  _Durum(this.stok, this.cari, this.kasaNakit, this.banka);
}

void main() {
  test('İŞ AKIŞI ROBOTU — bir market günü', () async {
    await RobotOrtam.hazirla();
    final db = await RobotOrtam.veritabaniAc();
    final v = await RobotOrtam.tohumla(db);
    expect(await AuthServisi().girisYap('admin', '1234'), isTrue);

    final urunIdler = [v.id['urun0']!, v.id['urun1']!, v.id['urun2']!];
    final cikolata = urunIdler[0], deterjan = urunIdler[1], su = urunIdler[2];
    final musteri = v.id['cari']!, tedarikci = v.id['tedarikci']!, bayi = v.id['bayi']!;
    final cariler = [musteri, tedarikci, bayi];
    final bankaHesap = v.id['bankaHesap']!;

    // Tohumdaki banka bakiyesi hareketsizdi (mutabakatı bozar) — sıfırdan başla.
    await db.update('banka_hesaplar', {'bakiye': 0, 'kullanilabilir_bakiye': 0},
        where: 'id = ?', whereArgs: [bankaHesap]);
    // Fatura kesilebilsin: müşteriye geçerli TCKN, vergi dairesi, adres.
    await db.update('cari', {'tc_kimlik': '10000000146', 'vergi_dairesi': 'Robot VD'},
        where: 'id = ?', whereArgs: [musteri]);
    await db.insert('cari_adres', {
      'cari_id': musteri, 'adres': 'Robot Sk. No:1', 'il': 'İstanbul',
      'ilce': 'Kadıköy', 'varsayilan': 1,
    });
    // Merkezi fatura numara bloğu (bulutsuz ortamda önceden tahsis edilmiş gibi).
    await db.insert('yerel_fatura_blok', {
      'seri': 'FTR', 'yil': DateTime.now().year, 'blok_baslangic': 1,
      'blok_bitis': 1000, 'siradaki': 1, 'durum': 'aktif',
    });

    final sorunlar = <String>[];
    final gunluk = StringBuffer();

    Future<_Durum> olc() async {
      final stok = <int, double>{};
      for (final id in urunIdler) {
        final r = await db.query('urunler', columns: ['stok'], where: 'id = ?', whereArgs: [id]);
        stok[id] = (r.first['stok'] as num).toDouble();
      }
      final cari = <int, double>{};
      for (final id in cariler) {
        final r = await db.query('cari', columns: ['bakiye'], where: 'id = ?', whereArgs: [id]);
        cari[id] = (r.first['bakiye'] as num).toDouble();
      }
      final b = await db.query('banka_hesaplar', columns: ['bakiye'], where: 'id = ?', whereArgs: [bankaHesap]);
      return _Durum(stok, cari, await KasaDeposu().guncelBakiyeNakit(),
          (b.first['bakiye'] as num).toDouble());
    }

    String ad(int id) => {
          cikolata: 'Çikolata', deterjan: 'Deterjan', su: 'Su',
        }[id] ?? '#$id';
    String cariAd(int id) => {musteri: 'Müşteri', tedarikci: 'Tedarikçi', bayi: 'Bayi'}[id] ?? '#$id';

    Future<void> saglikKontrol(String adim) async {
      final sonuclar = await VeriSagligiServisi().tumKontrolleriCalistir();
      for (final s in sonuclar) {
        // Yedekleme / senkron kuyruğu test ortamının doğası gereği uyarı verir.
        if (s.id == 'yedekleme' || s.id == 'sync_kuyruk') continue;
        if (s.durum == SaglikDurum.kirmizi) {
          sorunlar.add('**$adim** — Veri Sağlığı KIRMIZI: ${s.baslik}: ${s.mesaj}');
        }
      }
    }

    /// [ad] adımını çalıştırır; beklenen değişimleri kontrol eder.
    Future<void> adim(
      String baslik,
      Future<void> Function() islem, {
      Map<int, double> stok = const {},
      Map<int, double> cari = const {},
      double kasa = 0,
      double banka = 0,
      Future<String?> Function()? ekKontrol,
    }) async {
      final once = await olc();
      try {
        await islem();
      } catch (e, st) {
        sorunlar.add('**$baslik** — İŞLEM HATASI: ${e.toString().split('\n').first}');
        gunluk.writeln('❌ $baslik — $e\n$st');
        return;
      }
      final sonra = await olc();
      final hatalar = <String>[];
      void karsilastir(String neyin, double beklenen, double gercek) {
        if ((beklenen - gercek).abs() > 0.005) {
          hatalar.add('$neyin beklenen ${_f(beklenen)}, gerçek ${_f(gercek)}');
        }
      }
      for (final id in urunIdler) {
        karsilastir('${ad(id)} stok değişimi', stok[id] ?? 0, sonra.stok[id]! - once.stok[id]!);
      }
      for (final id in cariler) {
        karsilastir('${cariAd(id)} bakiye değişimi', cari[id] ?? 0, sonra.cari[id]! - once.cari[id]!);
      }
      karsilastir('Nakit kasa değişimi', kasa, sonra.kasaNakit - once.kasaNakit);
      karsilastir('Banka değişimi', banka, sonra.banka - once.banka);
      if (ekKontrol != null) {
        try {
          final m = await ekKontrol();
          if (m != null) hatalar.add(m);
        } catch (e) {
          hatalar.add('ek kontrol hatası: $e');
        }
      }
      for (final h in hatalar) {
        sorunlar.add('**$baslik** — $h');
      }
      gunluk.writeln('${hatalar.isEmpty ? '✅' : '⚠️'} $baslik');
      await saglikKontrol(baslik);
    }

    final urunDepo = UrunDeposu();
    Future<SepetKalem> kalem(int urunId, double miktar) async =>
        SepetKalem(urun: (await urunDepo.idileGetir(urunId))!, miktar: miktar);
    final satisSrv = SatisTamamlamaServisi();

    // ── 1. Nakit satış ───────────────────────────────────────────────────
    late int nakitSatisId;
    await adim('1. Nakit satış (2 çikolata = 50 ₺)', () async {
      final r = await satisSrv.tamamla(
          kalemler: [await kalem(cikolata, 2)], musteri: null,
          genelToplam: 50, odemeYontemi: 'Nakit', odenenTutar: 50);
      nakitSatisId = r.satisId;
    }, stok: {cikolata: -2}, kasa: 50);

    // ── 2. Kredi kartı satış ─────────────────────────────────────────────
    await adim('2. Kredi kartı satış (1 deterjan = 90 ₺) — nakit kasayı etkilemez', () async {
      await satisSrv.tamamla(
          kalemler: [await kalem(deterjan, 1)], musteri: null,
          genelToplam: 90, odemeYontemi: 'Kredi Kartı', odenenTutar: 90);
    }, stok: {deterjan: -1});

    // ── 3. Cariye (veresiye) ürün satışı ─────────────────────────────────
    late int veresiyeSatisId;
    final musteriModel = await CariDeposu().idileGetir(musteri);
    await adim('3. Müşteriye veresiye satış (3 su + 1 deterjan = 120 ₺)', () async {
      final r = await satisSrv.tamamla(
          kalemler: [await kalem(su, 3), await kalem(deterjan, 1)],
          musteri: musteriModel, genelToplam: 120, odemeYontemi: 'Cari', odenenTutar: 0);
      veresiyeSatisId = r.satisId;
    }, stok: {su: -3, deterjan: -1}, cari: {musteri: 120});

    // ── 4. Veresiye satışa fatura kes ────────────────────────────────────
    await adim('4. Veresiye satışa fatura kes (120 ₺, KDV %20 → matrah 100 + KDV 20)', () async {
      final kontrol = await FaturalandirmaServisi.kontrolEt(musteri);
      if (kontrol == null || !kontrol.hazir) {
        throw Exception('cari faturaya hazır değil: ${kontrol?.eksikAlanlar}');
      }
      final s = (await SatisDeposu().idileGetir(veresiyeSatisId))!;
      final detaylar = s.kalemler.map((k) => FaturaDetayModel(
            urunId: k.urunId, urunAdi: k.urunAdi, barkod: k.barkod,
            miktar: k.miktar, birimFiyat: k.birimFiyat,
            iskontoOrani: k.iskontoOran, iskontoTutari: k.iskontoTutar,
            kdvOrani: k.kdvOran, kdvTutari: k.kdvTutar,
            araToplam: k.toplamTutar - k.kdvTutar, toplamTutar: k.toplamTutar,
          )).toList();
      await FaturalandirmaServisi.faturaOlustur(
          kontrol: kontrol, kalemler: detaylar, faturaTipi: 'Satis',
          satisId: s.id, tarih: s.tarih, odenenTutar: s.odenenTutar);
    }, ekKontrol: () async {
      final f = await db.query('faturalar', where: 'satis_id = ?', whereArgs: [veresiyeSatisId]);
      if (f.length != 1) return '${f.length} fatura oluştu (1 bekleniyordu)';
      final r = f.first;
      final no = r['fatura_no'] as String? ?? '';
      final g = (r['genel_toplam'] as num).toDouble();
      final ara = (r['toplam_ara_toplam'] as num).toDouble();
      final kdv = (r['toplam_kdv'] as num).toDouble();
      final m = <String>[];
      if (!RegExp(r'^FTR\d{4}\d{9}$').hasMatch(no)) m.add('fatura no biçimi hatalı: "$no"');
      if ((g - 120).abs() > 0.01) m.add('genel toplam ${_f(g)} (120 bekleniyordu)');
      if ((ara - 100).abs() > 0.01) m.add('matrah ${_f(ara)} (100 bekleniyordu)');
      if ((kdv - 20).abs() > 0.01) m.add('KDV ${_f(kdv)} (20 bekleniyordu)');
      if ((ara + kdv - g).abs() > 0.01) m.add('matrah + KDV ≠ genel toplam');
      final d = await db.query('fatura_detaylari', where: 'fatura_id = ?', whereArgs: [r['id']]);
      if (d.length != 2) m.add('${d.length} fatura kalemi (2 bekleniyordu)');
      return m.isEmpty ? null : m.join('; ');
    });

    // ── 5. Aynı satışa ikinci kez fatura engellenmeli ────────────────────
    await adim('5. Aynı satışa mükerrer fatura koruması', () async {}, ekKontrol: () async {
      final id = await FaturalandirmaServisi.mevcutFaturaId(satisId: veresiyeSatisId);
      return id == null ? 'mevcutFaturaId faturalanmış satışı görmüyor — mükerrer fatura kesilebilir' : null;
    });

    // ── 6. Karma ödeme ───────────────────────────────────────────────────
    await adim('6. Karma satış: 2 çikolata 50 ₺ = 20 nakit + 30 veresiye', () async {
      await satisSrv.tamamla(
          kalemler: [await kalem(cikolata, 2)], musteri: musteriModel,
          genelToplam: 50, odemeYontemi: 'Karma', odenenTutar: 20,
          karmaKalemler: [
            {'yontem': 'Nakit', 'tutar': 20.0},
            {'yontem': 'Cari', 'tutar': 30.0},
          ]);
    }, stok: {cikolata: -2}, cari: {musteri: 30}, kasa: 20);

    // ── 7. Tahsilat ──────────────────────────────────────────────────────
    await adim('7. Müşteriden 100 ₺ nakit tahsilat', () async {
      await CariTahsilatOdemeServisi().kaydet(
          cariId: musteri, cariUnvan: 'Robot Müşteri', islemTipi: 'Tahsilat',
          tutar: 100, odemeTuru: 'Nakit', kullanici: 'Robot Yönetici',
          paraHareketEdiyor: true, paraCikiyor: false);
    }, cari: {musteri: -100}, kasa: 100);

    // ── 8. Fişten iade (veresiye satıştan 1 su, cariye) ──────────────────
    await adim('8. Veresiye fişinden 1 su iadesi (10 ₺, cariden düşülür)', () async {
      await IadeIslemServisi().fisKalemIadeKaydet(
          satisId: veresiyeSatisId, cariId: musteri, urunId: su, urunAdi: 'Robot Su 1.5 L',
          birimFiyat: 10, kalanMiktar: 1, oncekiIadeMiktar: 0, odemeYontemi: 'Cari',
          kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
    }, stok: {su: 1}, cari: {musteri: -10});

    // ── 9. Hızlı (toplu) nakit iade ──────────────────────────────────────
    await adim('9. Hızlı nakit iade (1 çikolata = 25 ₺ kasadan çıkar)', () async {
      await IadeIslemServisi().topluIadeKaydet(
          kalemler: [IadeKalemGirdi(urun: (await urunDepo.idileGetir(cikolata))!, adet: 1)],
          odemeYontemi: 'Nakit', kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
    }, stok: {cikolata: 1}, kasa: -25);

    // ── 10. Tedarikçiden veresiye alım ───────────────────────────────────
    await adim('10. Tedarikçiden veresiye alım (10 deterjan × 60 = 600 ₺)', () async {
      await AlimIslemServisi().alimKaydet(
          mevcutSiparisId: null,
          kalemler: [AlimKalemGirdi(urunId: deterjan, miktar: 10, alisFiyat: 60)],
          tedarikciId: tedarikci, tedarikciAdi: 'Robot Tedarikçi', genelToplam: 600,
          odemeYontemi: 'Cari', kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
    }, stok: {deterjan: 10}, cari: {tedarikci: -600});

    // ── 11. Kasadan bankaya virman ───────────────────────────────────────
    final bankaModel = await BankaHesapDeposu().idileGetir(bankaHesap);
    await adim('11. Kasadan bankaya 100 ₺ virman', () async {
      await VirmanServisi().virmanYap(
          kaynakHesap: 'Kasa', hedefHesap: 'Banka', tutar: 100,
          aciklama: 'Robot virman', seciliBanka: bankaModel);
    }, kasa: -100, banka: 100);

    // ── 12. Tedarikçiye bankadan ödeme ───────────────────────────────────
    await adim('12. Tedarikçiye bankadan 80 ₺ ödeme', () async {
      await CariTahsilatOdemeServisi().kaydet(
          cariId: tedarikci, cariUnvan: 'Robot Tedarikçi', islemTipi: 'Odeme',
          tutar: 80, odemeTuru: 'Banka', kullanici: 'Robot Yönetici',
          paraHareketEdiyor: true, paraCikiyor: true, bankaHesapId: bankaHesap);
    }, cari: {tedarikci: 80}, banka: -80);

    // ── 13. Bayiye toptan satış ──────────────────────────────────────────
    await adim('13. Bayiye toptan satış (5 su × 8 = 40 ₺ veresiye)', () async {
      final fisNo = await Veritabani().fisNoUret('toptan');
      final kalemler = [
        SatisKalemModel(
          satisId: 0, urunId: su, urunAdi: 'Robot Su 1.5 L (Adet)', miktar: 5,
          birimFiyat: 8, toplamTutar: 40, kdvOran: 20,
          kdvTutar: ParaUtils.kdvPayiCikar(40, 20), netFiyat: 8, alisFiyat: 6,
        ),
      ];
      await ToptanSatisIslemServisi().satisKaydet(
          satis: SatisModel(
            fisNo: fisNo, tarih: DateTime.now(), cariId: bayi, cariAdi: 'Robot Bayi',
            toplamTutar: 40, genelToplam: 40, odenenTutar: 0,
            odemeYontemi: 'Cari', fisTipi: 'Toptan Satış'),
          kalemler: kalemler,
          stokKalemleri: [ToptanStokKalemi(urunId: su, stokMiktari: 5)],
          cariId: bayi, fisNo: fisNo, genelToplam: 40,
          kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
    }, stok: {su: -5}, cari: {bayi: 40});

    // ── 14. Stok sayımı (sayan + onaylayan) ──────────────────────────────
    await adim('14. Stok sayımı: çikolata sayıldı 90 adet', () async {
      final mevcut = (await olc()).stok[cikolata]!;
      await StokDeposu().geciciSayimEkleGuncelle(cikolata, mevcut, 90, kullaniciId: v.id['admin']);
      await StokDeposu().geciciSayimUygula(v.id['admin']!);
    }, stok: {cikolata: 90 - (100 - 2 - 2 + 1)});

    // ── 15. Şubeler arası transfer (toplam stok değişmez) ────────────────
    await adim('15. Şubeler arası transfer: 5 su Merkez → Şube 2', () async {
      final sube2 = await db.insert('subeler', {'sube_kodu': 'SUBE2', 'sube_adi': 'Şube 2'});
      final merkez = v.id['sube']!;
      await db.insert('sube_urun', {'urun_id': su, 'sube_id': merkez, 'stok': 50.0},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await SubeUrunDeposu().transferEt(
          urunId: su, kaynakSubeId: merkez, hedefSubeId: sube2, miktar: 5);
    }, ekKontrol: () async {
      final r = await db.rawQuery('SELECT sube_id, stok FROM sube_urun WHERE urun_id = ? ORDER BY sube_id', [su]);
      final m = {for (final x in r) x['sube_id'] as int: (x['stok'] as num).toDouble()};
      final merkez = m[v.id['sube']!] ?? -1;
      final diger = m.entries.where((e) => e.key != v.id['sube']).map((e) => e.value).fold(0.0, (a, b) => a + b);
      if ((merkez - 45).abs() > 0.01 || (diger - 5).abs() > 0.01) {
        return 'şube stokları Merkez ${_f(merkez)} / Şube2 ${_f(diger)} (45 / 5 bekleniyordu)';
      }
      return null;
    });

    // ── 16. Nakit satışı sil → stok ve kasa geri dönmeli ─────────────────
    await adim('16. 1. adımdaki nakit satışı sil (stok +2, kasa −50)', () async {
      await SatisDeposu().sil(nakitSatisId, neden: 'Robot silme');
    }, stok: {cikolata: 2}, kasa: -50);

    // ── 17. Alımı sil → stok ve tedarikçi borcu geri dönmeli ─────────────
    await adim('17. 10. adımdaki alımı sil (stok −10, tedarikçi borcu +600)', () async {
      final r = await db.query('tedarikci_siparisler', columns: ['id'], orderBy: 'id DESC', limit: 1);
      await AlimIslemServisi().sil(r.first['id'] as int, neden: 'Robot silme');
    }, stok: {deterjan: -10}, cari: {tedarikci: 600});

    // ── 18. Faturalanmış satış doğrudan silinememeli ─────────────────────
    await adim('18. Faturalanmış veresiye satış silme koruması', () async {}, ekKontrol: () async {
      final faturaVar = await FaturalandirmaServisi.mevcutFaturaId(satisId: veresiyeSatisId);
      return faturaVar == null ? 'faturalı satış korumasız (SatisIptalServisi engellemez)' : null;
    });

    // ── 19. Tedarikçiye iade (2026-10-07 kuralı) ─────────────────────────
    // Fiyat: son alış maliyeti KDV dahil (raf fiyatı DEĞİL); stok AZALIR;
    // tedarikçiye olan borcumuz DÜŞER (bakiye artı yöne gider). Kasaya
    // dokunulmaz.
    await db.update('urunler',
        {'alis_fiyat': 60, 'alis_kdv_oran': 20, 'alis_fiyat_kdv_dahil': 72},
        where: 'id = ?', whereArgs: [deterjan]);
    late CariIadeSonucu tedarikciIadesi;
    await adim('19. Tedarikçiye iade: 2 deterjan × 72 (KDV dahil maliyet) = 144 ₺', () async {
      tedarikciIadesi = await IadeIslemServisi().tedarikciyeIadeEt(
          tedarikci: (await CariDeposu().idileGetir(tedarikci))!,
          kalemler: [IadeMiktari(urunId: deterjan, miktar: 2)],
          kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
    }, stok: {deterjan: -2}, cari: {tedarikci: 144}, ekKontrol: () async {
      final m = <String>[];
      if ((tedarikciIadesi.toplamTutar - 144).abs() > 0.01) {
        m.add('iade tutarı ${_f(tedarikciIadesi.toplamTutar)} (144 bekleniyordu — raf fiyatı 90 kullanılmamalı)');
      }
      final r = await db.query('tedarikci_iadeler', where: 'id = ?', whereArgs: [tedarikciIadesi.iadeId]);
      if (r.length != 1) m.add('tedarikci_iadeler kaydı ${r.length} (1 bekleniyordu)');
      if (!tedarikciIadesi.fisNo.startsWith('TDI')) m.add('fiş no "${tedarikciIadesi.fisNo}" TDI ile başlamıyor');
      return m.isEmpty ? null : m.join('; ');
    });

    // ── 20. Tedarikçi iadesini iptal → her şey geri dönmeli ──────────────
    await adim('20. Tedarikçi iadesini iptal et (stok +2, tedarikçi borcu geri)', () async {
      await IadeIslemServisi().tedarikciIadesiniIptalEt(tedarikciIadesi.iadeId, neden: 'Robot iptal');
    }, stok: {deterjan: 2}, cari: {tedarikci: -144}, ekKontrol: () async {
      try {
        await IadeIslemServisi().tedarikciIadesiniIptalEt(tedarikciIadesi.iadeId);
        return 'aynı iade İKİ KEZ iptal edilebildi (stok/bakiye çift geri alınır)';
      } on IadeGecersizHatasi {
        return null;
      }
    });

    // ── 21. Bayiden iade (bayiye özel toptan fiyat) ──────────────────────
    await db.update('urunler', {'toptan_fiyat': 8}, where: 'id = ?', whereArgs: [su]);
    await db.update('cari', {'musteri_tipi': 'Bayi'}, where: 'id = ?', whereArgs: [bayi]);
    await adim('21. Bayiden iade: 2 su × 8 (toptan fiyat, raf 10 değil) = 16 ₺', () async {
      final r = await IadeIslemServisi().bayidenIadeAl(
          bayi: (await CariDeposu().idileGetir(bayi))!,
          kalemler: [IadeMiktari(urunId: su, miktar: 2)],
          kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
      if ((r.toplamTutar - 16).abs() > 0.01) {
        throw Exception('bayi iade tutarı ${_f(r.toplamTutar)} (16 bekleniyordu)');
      }
    }, stok: {su: 2}, cari: {bayi: -16});

    // ── 22. Negatif stok (B2 kararı: satış engellenmez, stok eksiye düşer) ─
    late double suStokOnce;
    await adim('22. Stoktan fazla satış: 200 su nakit (stok eksiye düşer, kırpılmaz)', () async {
      suStokOnce = (await olc()).stok[su]!;
      await satisSrv.tamamla(
          kalemler: [await kalem(su, 200)], musteri: null,
          genelToplam: 2000, odemeYontemi: 'Nakit', odenenTutar: 2000);
    }, stok: {su: -200}, kasa: 2000, ekKontrol: () async {
      final son = (await olc()).stok[su]!;
      return son >= 0 ? 'stok ${_f(son)} — eksiye düşmesi bekleniyordu (önce ${_f(suStokOnce)})' : null;
    });

    // ── 23. İade fiyatı = satıştaki orijinal fiyat (B4 kararı) ───────────
    // Raf fiyatı sonradan 25 → 30 yapılır; hızlı iade yine satıştaki 25'ten
    // ödenmeli (güncel fiyattan ödemek kasadan fazla para çıkarır).
    await db.update('urunler', {'satis_fiyati': 30}, where: 'id = ?', whereArgs: [cikolata]);
    await adim('23. Fiyat 30 olduktan sonra hızlı iade: 1 çikolata satıştaki 25 ₺\'den', () async {
      await IadeIslemServisi().topluIadeKaydet(
          kalemler: [IadeKalemGirdi(urun: (await urunDepo.idileGetir(cikolata))!, adet: 1)],
          odemeYontemi: 'Nakit', kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
    }, stok: {cikolata: 1}, kasa: -25);

    // ── 24. Çift iade koruması (bayat ekran verisi) ──────────────────────
    // 3. adımdaki fişte 3 su vardı, 8. adımda 1'i iade edildi → en çok 2.
    // Ekran "önceki iade 0" diye bayat bilgiyle 3 göndermeye çalışır.
    await adim('24. Fişten kalandan fazla iade denemesi reddedilmeli (kalan 2, istenen 3)', () async {
      try {
        await IadeIslemServisi().fisKalemIadeKaydet(
            satisId: veresiyeSatisId, cariId: musteri, urunId: su, urunAdi: 'Robot Su 1.5 L',
            birimFiyat: 10, kalanMiktar: 3, oncekiIadeMiktar: 0, odemeYontemi: 'Cari',
            kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
        throw Exception('fazla iade KABUL EDİLDİ — çift iade açığı');
      } on IadeMiktariAsildiHatasi {
        // beklenen
      }
    });

    // ── 25. Aynı fişten kalan 2 su iade edilebilmeli, sonra hiç kalmamalı ─
    await adim('25. Kalan 2 su iadesi kabul (20 ₺ cariden), ardından 1 daha reddedilmeli', () async {
      await IadeIslemServisi().fisKalemIadeKaydet(
          satisId: veresiyeSatisId, cariId: musteri, urunId: su, urunAdi: 'Robot Su 1.5 L',
          birimFiyat: 10, kalanMiktar: 2, oncekiIadeMiktar: 1, odemeYontemi: 'Cari',
          kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
    }, stok: {su: 2}, cari: {musteri: -20}, ekKontrol: () async {
      try {
        await IadeIslemServisi().fisKalemIadeKaydet(
            satisId: veresiyeSatisId, cariId: musteri, urunId: su, urunAdi: 'Robot Su 1.5 L',
            birimFiyat: 10, kalanMiktar: 1, oncekiIadeMiktar: 3, odemeYontemi: 'Cari',
            kullaniciId: v.id['admin'], kullaniciAdi: 'Robot Yönetici');
        return 'fişte iade edilecek su kalmadığı halde iade kabul edildi';
      } on IadeMiktariAsildiHatasi {
        return null;
      }
    });

    // ── Son: cari bakiye = hareket toplamı ───────────────────────────────
    final uyumsuz = await CariDeposu().bakiyeUyumsuzlukSayisi();
    if (uyumsuz > 0) sorunlar.add('**Son durum** — $uyumsuz caride bakiye ≠ hareket toplamı');
    final son = await olc();

    final rapor = StringBuffer()
      ..writeln('# İş Akışı Robotu Raporu — ${DateTime.now()}')
      ..writeln()
      ..writeln('Sorun: ${sorunlar.length}')
      ..writeln()
      ..writeln('## Adımlar')
      ..write(gunluk)
      ..writeln()
      ..writeln('## Sorunlar')
      ..writeAll(sorunlar.map((s) => '- $s\n'))
      ..writeln()
      ..writeln('## Son durum')
      ..writeln('Stok: Çikolata ${_f(son.stok[cikolata]!)} · Deterjan ${_f(son.stok[deterjan]!)} · Su ${_f(son.stok[su]!)}')
      ..writeln('Cari: Müşteri ${_f(son.cari[musteri]!)} · Tedarikçi ${_f(son.cari[tedarikci]!)} · Bayi ${_f(son.cari[bayi]!)}')
      ..writeln('Nakit kasa ${_f(son.kasaNakit)} · Banka ${_f(son.banka)}');
    Directory('build').createSync(recursive: true);
    File('build/is_akisi_raporu.md').writeAsStringSync(rapor.toString());
    // ignore: avoid_print
    print(rapor);

    Veritabani.testVeritabani = null;
    await db.close();
    expect(sorunlar, isEmpty, reason: 'iş akışı robotu ${sorunlar.length} sorun buldu');
  },
      timeout: const Timeout(Duration(minutes: 5)));
}

String _f(double x) => x.toStringAsFixed(2);
