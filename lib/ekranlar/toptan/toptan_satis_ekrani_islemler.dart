// ignore_for_file: invalid_use_of_protected_member
//
// toptan_satis_ekrani.dart parçası (god-class bölme, 2026-09-29) — kod
// birebir taşındı, davranış değişmedi. setState extension içinden
// çağrıldığı için protected uyarısı dosya bazında muaf (bkz.
// fatura_detay_islemler_ext.dart'taki açıklama).
// Bayi seçimi, ürün arama/ekleme, eski siparişi çoğaltma, satışı tamamlama ve faturalandırma.
part of 'toptan_satis_ekrani.dart';

extension _ToptanSatisIslemlerExt on _ToptanSatisEkraniState {
  /// Kullanıcı isteği: "Çoğalt dedik mi eski siparişin kalemleri
  /// gelsin." Eski satışın kalemlerini okuyup, HER BİRİ İÇİN fiyatı
  /// YENİDEN (güncel fiyat/kademe/kredi durumuna göre) hesaplayarak
  /// sepete ekler — eski, artık geçersiz olabilecek bir fiyatı körü
  /// körüne kopyalamak yerine bilinçli olarak TAZE fiyat kullanılır.
  Future<void> _eskiSiparisiCogalt(int satisId) async {
    try {
      final eskiSatis = await SatisDeposu().idileGetir(satisId);
      final kalemler = eskiSatis?.kalemler ?? const [];
      for (final k in kalemler) {
        final urun = await _urunDepo.idileGetir(k.urunId);
        if (urun == null) continue;
        final miktar = k.miktar;
        final fiyatSonucu = await _fiyatServisi.hesapla(
          urun: urun,
          cari: _secilenBayi,
          miktar: miktar,
          birim: 'adet',
        );
        if (!mounted) return;
        setState(() {
          _sepet.add(_SepetKalemi(
              urun: urun,
              miktar: miktar,
              birim: 'adet',
              fiyatSonucu: fiyatSonucu));
        });
      }
      if (mounted && kalemler.isNotEmpty) {
        BildirimServisi.basari(
            context, 'Önceki sipariş kalemleri güncel fiyatlarla eklendi');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Sipariş çoğaltılamadı: $e');
    }
  }

  Future<void> _bayiSec() async {
    final tumCariler = await _cariDepo.tumunuGetir();
    // 🔴 DÜZELTME (kullanıcı bulgusu — "bayi/müşteri/tedarikçi doğru
    // mu"): Aynı düzeltme (bkz. toptan_dashboard_ekrani.dart) — saf
    // bir tedarikçi, musteriTipi yanlışlıkla "Bayi"/"Toptan" ise bu
    // satış listesinde görünmemeli.
    final bayiler = tumCariler
        .where((c) =>
            c.cariTipi.contains('Müşteri') &&
            (c.musteriTipi == 'Bayi' || c.musteriTipi == 'Toptan'))
        .toList();
    if (!mounted) return;
    if (bayiler.isEmpty) {
      BildirimServisi.hata(
          context,
          'Henüz "Bayi" veya "Toptan" tipinde cari yok. Cari kartından '
          'müşteri tipini "Bayi/Toptan" yapın.');
      return;
    }
    final secilen = await showModalBottomSheet<CariModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (c, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: TsRenk.arkaplan(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(TsRadius.xl)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(TsBosluk.lg),
              child: Text('Bayi / Toptan Müşteri Seç',
                  style: TsMetin.baslikM
                      .copyWith(color: TsRenk.metinBirincil(context))),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: TsBosluk.md),
                itemCount: bayiler.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: TsBosluk.sm),
                itemBuilder: (c, i) {
                  final b = bayiler[i];
                  return TsKart.liste(
                    baslik: b.unvan,
                    altBaslik:
                        '${b.musteriTipi} · Bakiye: ${ParaUtils.formatla(b.bakiye)}',
                    ikon: CircleAvatar(
                      backgroundColor: TsRenk.zemin(TsRenk.primary),
                      child: Text(
                          b.unvan.isNotEmpty ? b.unvan[0].toUpperCase() : '?',
                          style: TextStyle(
                              color: TsRenk.primary,
                              fontWeight: FontWeight.w700)),
                    ),
                    onTap: () => Navigator.pop(c, b),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
    if (secilen != null) {
      setState(() {
        _secilenBayi = secilen;
        _sepet.clear();
      });
    }
  }

  Future<void> _urunAra(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _aramaSonuclari = []);
      return;
    }
    final sonuc = await _urunDepo.ara(q.trim());
    if (mounted) setState(() => _aramaSonuclari = sonuc);
  }

  /// Arama kutusunda Enter ya da ekran genelinde okuyucu girişi (el
  /// terminali / USB okuyucu). Önceden Enter'ın karşılığı yoktu: okutulan
  /// ürün eklenmiyor, sadece arama listesi açılıyordu.
  Future<void> _aramaGonderildi(String q) async {
    final temiz = q.trim();
    if (temiz.isEmpty || _secilenBayi == null) return;
    final barkodlu = await _urunDepo.barkodlaGetir(temiz);
    if (!mounted) return;
    if (barkodlu != null) {
      await _urunEkle(barkodlu);
      return;
    }
    final sonuc = await _urunDepo.ara(temiz);
    if (!mounted) return;
    if (sonuc.length == 1) {
      await _urunEkle(sonuc.first);
    } else {
      setState(() => _aramaSonuclari = sonuc);
      if (sonuc.isEmpty) BildirimServisi.uyari(context, '"$temiz" için ürün bulunamadı');
    }
  }

  Future<void> _urunEkle(UrunModel urun) async {
    _aramaCtrl.clear();
    setState(() => _aramaSonuclari = []);

    String birim = urun.satisBirimiTipi == 'kg' ? 'kg' : 'adet';
    double miktar = 1;

    final sonuc = await showDialog<(double, String)>(
      context: context,
      builder: (c) => _MiktarBirimDialog(
          urun: urun, baslangicBirim: birim, baslangicMiktar: miktar),
    );
    if (sonuc == null) return;
    miktar = sonuc.$1;
    birim = sonuc.$2;
    if (miktar <= 0) return;

    final fiyatSonucu = await _fiyatServisi.hesapla(
      urun: urun,
      cari: _secilenBayi,
      miktar: miktar,
      birim: birim,
    );

    setState(() {
      final mevcutIdx =
          _sepet.indexWhere((k) => k.urun.id == urun.id && k.birim == birim);
      if (mevcutIdx >= 0) {
        _sepet[mevcutIdx].miktar += miktar;
      } else {
        _sepet.add(_SepetKalemi(
            urun: urun,
            miktar: miktar,
            birim: birim,
            fiyatSonucu: fiyatSonucu));
      }
    });
  }

  Future<void> _satisiTamamla() async {
    if (_secilenBayi == null || _sepet.isEmpty || _kaydediliyor) return;
    // 🔴 Derin analizde bulundu: guard bayrağı (_kaydediliyor) önceden
    // buradaki iki await'ten (limitKontrolEt + olası onay dialog'u)
    // SONRA true yapılıyordu — o sırada buton hâlâ etkin kalıyordu. Hızlı
    // bir çift dokunma, ikinci çağrının da guard'ı hâlâ false görmesine
    // ve aynı toptan satışın STOK ve CARİ BORCU İKİ KEZ işlenerek
    // mükerrer kaydedilmesine yol açabilirdi (diğer ekranlar — alim_ekrani,
    // bayi_siparis_al_ekrani — bayrağı doğru şekilde ilk await'ten önce
    // set ediyor). Artık en baştan, herhangi bir await'ten önce set
    // ediliyor.
    setState(() => _kaydediliyor = true);
    ({double tutar, double esik, String aciklama})? riskOnayBilgisi;
    try {
      final limitSonuc =
          await _cariDepo.limitKontrolEt(_secilenBayi!.id!, _genelToplam);
      if (limitSonuc.asildi && mounted) {
        final devam = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: TsRenk.uyari),
              SizedBox(width: 8),
              Text('Kredi Limiti Aşılıyor'),
            ]),
            content: Text(
              '${_secilenBayi!.unvan} için tanımlı kredi limiti: '
              '${ParaUtils.formatla(limitSonuc.limit)}\n'
              'Mevcut bakiye: ${ParaUtils.formatla(limitSonuc.mevcutBakiye)}\n'
              'Bu satışla birlikte: ${ParaUtils.formatla(limitSonuc.mevcutBakiye + _genelToplam)}\n\n'
              'Limit ${ParaUtils.formatla(limitSonuc.asimTutari)} kadar aşılacak. '
              'Yine de devam etmek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Vazgeç')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: TsRenk.uyari),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Yine de Devam Et'),
              ),
            ],
          ),
        );
        if (devam != true) return;
        // FAZ 9 — Onay Merkezi (bildirim tipi): satış ENGELLENMEDİ,
        // kullanıcı zaten "Yine de Devam Et" dedi. Kayıt burada HEMEN
        // düşürülMÜYOR — 🔴 DÜZELTME (derin analizde bulundu): önceden
        // buradan düşürülüyordu, yani satış transaction'ı SONRADAN
        // (stok yetersizliği/exception ile) başarısız olsa bile Onay
        // Merkezi'nde hiç gerçekleşmemiş bir satış için yanlış-pozitif
        // bir "risk aşımı" kaydı kalıyordu. Artık sadece bilgi
        // saklanıyor; gerçek kayıt aşağıda transaction BAŞARIYLA
        // bittikten sonra düşürülüyor (diğer 6 onay hook'uyla aynı desen).
        riskOnayBilgisi = (
          tutar: limitSonuc.mevcutBakiye + _genelToplam,
          esik: limitSonuc.limit,
          aciklama: '${_secilenBayi!.unvan}: limit ${ParaUtils.formatla(limitSonuc.limit)}, '
              'aşım ${ParaUtils.formatla(limitSonuc.asimTutari)}',
        );
      }

      final kullanici = AuthServisi().aktifKullanici;
      final tarih = DateTime.now();
      final fisNo = await BelgeNoServisi().uret('cari_satis');

      final satisKalemler = _sepet.map((k) {
        final kdvOran = double.tryParse(k.urun.kdvOran) ?? 18;
        // 🔴 DÜZELTME (Madde 21 — Para Hesaplamaları denetimi,
        // 2026-09-16): birim fiyat GERÇEKTEN KDV DAHİL (kullanıcı
        // onayıyla doğrulandı). 'toplamTutar' müşteriden tahsil edilen
        // tutarın ta kendisi (değişmedi) — kdvTutar artık bu tutarın
        // İÇİNDEN doğru şekilde (bölerek) ayıklanıyor, üzerine
        // eklenmiyor.
        final kdvTutar = ParaUtils.kdvPayiCikar(k.toplamTutar, kdvOran);
        final birimFiyatStokBazli = k.fiyatSonucu.birimFiyat /
            (k.birim == 'koli' && k.urun.koliIciMiktar > 0
                ? k.urun.koliIciMiktar
                : 1);
        return SatisKalemModel(
          satisId: 0,
          urunId: k.urun.id!,
          urunAdi: '${k.urun.urunAdi} (${_birimEtiket(k.birim)})',
          barkod: k.urun.barkod,
          miktar: k.stokMiktari, // stok her zaman ADET/KG cinsinden tutulur
          birimFiyat: birimFiyatStokBazli,
          toplamTutar: k.toplamTutar,
          iskontoOran: 0,
          iskontoTutar: 0,
          kdvOran: kdvOran,
          kdvTutar: kdvTutar,
          // NOT: bu alan KDV'den ayıklanmış değil, sadece koli/adet
          // birim dönüşümü uygulanmış (KDV DAHİL) birim fiyattır —
          // isim yanıltıcı ama diğer çağıranlarla (bkz. yazdirma_servisi.
          // dart'ta netFiyat kullanımı) aynı "iskontolu/dönüştürülmüş
          // görüntülenecek fiyat" anlamında kullanılıyor, davranış
          // korunuyor.
          netFiyat: birimFiyatStokBazli,
          alisFiyat: k.urun.alisFiyat,
          alisFiyatKdv: k.urun.alisFiyatKdvDahil,
        );
      }).toList();

      final satis = SatisModel(
        fisNo: fisNo,
        tarih: tarih,
        cariId: _secilenBayi!.id,
        cariAdi: _secilenBayi!.unvan,
        toplamTutar: _genelToplam,
        genelToplam: _genelToplam,
        odenenTutar: 0,
        odemeYontemi: 'Cari',
        fisTipi: 'Toptan Satış',
        kasiyerId: kullanici?.id,
        kullaniciId: kullanici?.id,
      );

      // Satış + stok (FEFO) + cari hareketi artık ToptanSatisIslemServisi
      // içinde TEK transaction'da atomik olarak yürütülüyor (uygulama
      // ortada kapanırsa satış kaydedilip stok düşülmemiş, bayinin
      // carisine borç yazılmamış olabiliyordu — bkz. o servisin doc
      // yorumu), davranış birebir korundu.
      final satisId = await ToptanSatisIslemServisi().satisKaydet(
        satis: satis,
        kalemler: satisKalemler,
        stokKalemleri: _sepet
            .map((k) => ToptanStokKalemi(
                urunId: k.urun.id!, stokMiktari: k.stokMiktari))
            .toList(),
        cariId: _secilenBayi!.id!,
        fisNo: fisNo,
        genelToplam: _genelToplam,
        kullaniciId: kullanici?.id,
        kullaniciAdi: kullanici?.adSoyad,
      );

      // ══════════════════════════════════════════════════════════════
      // 🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "toptan satış sonrası
      // Cari'de detay gözükmüyor")
      //
      // Bu ekran ConsumerState DEĞİL — düz State. Cari hareketi yukarıda
      // doğru yazılıyor (bakiye de doğru güncelleniyor), ama Genel Cari
      // modülündeki detay ekranı (cari_detay_ekrani.dart) bu veriyi
      // `cariDetayProvider` adlı bir Riverpod cache'inden okuyor.
      //
      // Uygulamadaki HER DİĞER cari-yazan ekran (iade x4, masa, cari
      // hareket, tahsilat/ödeme) yazdıktan hemen sonra
      // `ref.invalidate(cariDetayProvider(cariId))` çağırıyor. Bu ekran
      // ConsumerState olmadığı için o çağrıyı hiç yapmıyordu.
      //
      // Sonuç: kullanıcı toptan satışı bitirip Cari modülünden aynı
      // cariye bakınca (özellikle sekme/IndexedStack ile o ekran daha
      // önce açılıp bellekte kalmışsa) YENİ satış görünmüyordu — cache
      // bayatlamıştı. Tarayıcıyı/uygulamayı kapatıp açınca ya da o
      // ekranı zorla yeniden açınca fark edilmiyordu; asıl belirti,
      // ekranı kapatmadan tekrar bakınca eski veri görünmesiydi.
      //
      // ÇÖZÜM: `ProviderScope.containerOf` — bu ekranın ConsumerState'e
      // çevrilmesini gerektirmeyen, projede zaten kullanılan (bkz.
      // uygulama.dart) güvenli bir yöntem.
      // ══════════════════════════════════════════════════════════════
      if (mounted) {
        ProviderScope.containerOf(context, listen: false)
            .invalidate(cariDetayProvider(_secilenBayi!.id!));
      }

      // Tüm veritabanı yazmaları bitti — buradan sonrası arayüz.
      // FAZ 9 — Onay Merkezi (bildirim tipi): satış artık GERÇEKTEN
      // kalıcı olduğu için (transaction başarıyla bitti) risk aşımı
      // kaydı burada, satisId referansıyla düşürülüyor.
      if (riskOnayBilgisi != null) {
        OnayMerkeziServisi().kaydet(
          tur: OnayTuru.riskAsimi,
          tutar: riskOnayBilgisi.tutar,
          esikTutar: riskOnayBilgisi.esik,
          referansTuru: 'satis',
          referansId: satisId,
          aciklama: riskOnayBilgisi.aciklama,
        );
      }
      if (!mounted) return;

      // 🔴 DÜZELTME: aşağıdaki setState `_secilenBayi`'yi null yapıyor,
      // ama fatura kesme adımı (birkaç satır aşağıda) onu kullanıyordu.
      // Sonuç: kasiyer "Fatura Kes"e basınca _faturalandir() içindeki
      // `if (bayiSnapshot?.id == null) return;` sessizce çalışıyor,
      // hiçbir şey olmuyor, hata da gösterilmiyordu.
      // Parametrenin adı zaten `bayiSnapshot` — niyet kopya almaktı,
      // ama kopya hiç alınmamıştı. Artık alınıyor.
      final bayiSnapshot = _secilenBayi;
      final bayiUnvan = bayiSnapshot!.unvan;
      setState(() {
        _sepet.clear();
        _secilenBayi = null;
      });

      // Kullanıcı isteği: "e-Fatura/e-Arşiv ile entegre olsun." Satış
      // tamamlanınca, mevcut (kanıtlanmış) faturalandırma zincirine
      // (satış detay ekranıyla AYNI akış) hemen geçiş sunuluyor.
      if (!mounted) return;
      final faturaKes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.check_circle, color: TsRenk.basarili),
            SizedBox(width: 8),
            Text('Satış Tamamlandı'),
          ]),
          content: Text('$bayiUnvan için $fisNo numaralı toptan satış '
              'kaydedildi.\n\nŞimdi bu satış için fatura kesmek ister misiniz?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Şimdi Değil')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Fatura Kes')),
          ],
        ),
      );
      if (faturaKes == true) {
        await _faturalandir(satisId, bayiSnapshot, tarih, satisKalemler);
      } else if (mounted) {
        BildirimServisi.basari(context, 'Toptan satış tamamlandı: $fisNo');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Satış kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  /// Mevcut satış → fatura zincirini (satis_detay_ekrani.dart ile AYNI,
  /// kanıtlanmış FaturalandirmaServisi akışı) kullanarak fatura oluşturur.
  Future<void> _faturalandir(int satisId, CariModel? bayiSnapshot,
      DateTime tarih, List<SatisKalemModel> satisKalemler) async {
    if (bayiSnapshot?.id == null) return;
    try {
      final kontrol = await FaturalandirmaServisi.kontrolEt(bayiSnapshot!.id!);
      if (kontrol == null) {
        if (mounted) BildirimServisi.hata(context, 'Cari bulunamadı.');
        return;
      }
      if (!kontrol.hazir) {
        if (!mounted) return;
        final git = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TsRadius.xl)),
            title: Row(children: [
              Icon(Icons.warning_amber_rounded, color: TsRenk.uyari),
              const SizedBox(width: 8),
              const Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${kontrol.cari.unvan} için fatura kesilebilmesi için '
                      'aşağıdaki bilgiler eksik:'),
                  const SizedBox(height: 10),
                  ...kontrol.eksikAlanlar.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Icon(Icons.circle, size: 6, color: TsRenk.uyari),
                          const SizedBox(width: 8),
                          Text(e),
                        ]),
                      )),
                ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Cari Düzenle')),
            ],
          ),
        );
        if (git == true && mounted)
          await context.push('/cari/ekle', extra: kontrol.cari);
        return;
      }

      // 🔴 DÜZELTME (Madde 21 — GİB/fatura araToplam bulgusu devamı,
      // 2026-09-16): araToplam KDV DAHİL (brüt) doluyordu — bkz.
      // satis_detay_ekrani.dart'taki aynı düzeltme. Net (matrah) olmalı.
      final detaylar = satisKalemler
          .map((k) => FaturaDetayModel.kdvDahilKalemden(
          urunId: k.urunId, urunAdi: k.urunAdi, barkod: k.barkod,
          miktar: k.miktar, birimFiyat: k.birimFiyat,
          iskontoOrani: k.iskontoOran, kdvDahilIskontoTutari: k.iskontoTutar,
          kdvOrani: k.kdvOran, kdvDahilToplam: k.toplamTutar,
        ))
          .toList();

      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol,
        kalemler: detaylar,
        faturaTipi: 'Satis',
        satisId: satisId,
        tarih: tarih,
        odenenTutar: 0,
      );

      if (!mounted) return;
      BildirimServisi.basari(context, 'Fatura oluşturuldu ✓');
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Faturalandırma hatası: $e');
    }
  }
}
