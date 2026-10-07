// ignore_for_file: invalid_use_of_protected_member
//
// cari_detay_ekrani.dart parçası (god-class bölme, 2026-09-29) — kod
// birebir taşındı, davranış değişmedi. setState extension içinden
// çağrıldığı için protected uyarısı dosya bazında muaf (bkz.
// fatura_detay_islemler_ext.dart'taki açıklama).
// Faturalandırma, seçili hareketi yazdırma, bayi girişi, borç silme.
part of 'cari_detay_ekrani.dart';

extension _CariDetayIslemlerExt on _CariDetayIcerikState {
  Future<void> _hareketFaturalandir(CariHareketModel h) async {
    if (h.fisId == null) return;
    setState(() => _yukl = true);
    try {
      final satis = await SatisDeposu().idileGetir(h.fisId!);
      if (satis == null || satis.kalemler.isEmpty) {
        if (mounted) BildirimServisi.hata(context, 'Satış kalemleri bulunamadı.');
        return;
      }

      // Bu satış için daha önce fatura kesildiyse tekrar oluşturma
      final mevcutId = await FaturalandirmaServisi.mevcutFaturaId(satisId: h.fisId);
      if (mevcutId != null) {
        if (!mounted) return;
        BildirimServisi.basari(context, 'Bu satış için zaten bir fatura mevcut, ona yönlendiriliyorsunuz.');
        context.push('/fatura/detay/$mevcutId');
        return;
      }

      final kontrol = await FaturalandirmaServisi.kontrolEt(widget.cari.id!);
      if (kontrol == null) return;

      if (!kontrol.hazir) {
        if (!mounted) return;
        final git = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${widget.cari.unvan} için fatura kesilebilmesi için "
                  "aşağıdaki bilgiler eksik:"),
              const SizedBox(height: 10),
              ...kontrol.eksikAlanlar.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(e),
                    ]),
                  )),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cari Düzenle')),
            ],
          ),
        );
        if (git == true && mounted) {
          await context.push('/cari/ekle', extra: widget.cari);
        }
        return;
      }

      // 🔴 DÜZELTME (Madde 21 — GİB/fatura araToplam bulgusu devamı,
      // 2026-09-16): araToplam KDV DAHİL (brüt) doluyordu — bkz.
      // satis_detay_ekrani.dart'taki aynı düzeltme. Net (matrah) olmalı.
      final detaylar = satis.kalemler.map((k) => FaturaDetayModel.kdvDahilKalemden(
          urunId: k.urunId, urunAdi: k.urunAdi, barkod: k.barkod,
          miktar: k.miktar, birimFiyat: k.birimFiyat,
          iskontoOrani: k.iskontoOran, kdvDahilIskontoTutari: k.iskontoTutar,
          kdvOrani: k.kdvOran, kdvDahilToplam: k.toplamTutar,
        )).toList();

      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol, kalemler: detaylar, faturaTipi: 'Satis',
        satisId: satis.id, tarih: satis.tarih, odenenTutar: satis.odenenTutar,
      );

      if (!mounted) return;
      BildirimServisi.basari(context, 'Fatura oluşturuldu');
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Faturalandırma hatası: $e');
    } finally {
      if (mounted) setState(() => _yukl = false);
    }
  }

  /// Seçili Cari satış fişlerini ürün listesindeki GÜNCEL satış fiyatına
  /// göre yeniden fiyatlar (önizleme + onay). Bkz. fisFiyatGuncelleAkisi.
  Future<void> _seciliFisleriFiyatGuncelle() async {
    final ids = _secimler
        .where((h) => h.fisTipi == 'Satış' && h.fisId != null)
        .map((h) => h.fisId!)
        .toList();
    final guncellendi = await fisFiyatGuncelleAkisi(context, ids,
        kullanici: ref.read(authProvider).kullanici?.adSoyad);
    if (!guncellendi || !mounted) return;
    setState(() => _secimler.clear());
    ref.invalidate(cariDetayProvider(widget.cari.id!));
    ref.read(carilerProvider.notifier).yukle();
    await _hareketYukle();
  }

  /// Uzun basılıp seçilen satırı yazdırır — Satış/Toptan Satış için
  /// termal FİŞ (YazdirmaServisi.fisYazdir, hızlı satıştaki AYNI kod
  /// yolu), Tahsilat/Ödeme için MAKBUZ (YazdirmaServisi.makbuzYazdir,
  /// tahsilat_odeme_ekrani.dart'taki AYNI kod yolu — orijinal makbuz
  /// numarası artık cari_hareket.fis_no'da saklı, yoksa geriye dönük
  /// eski kayıtlar için "Kopya" etiketiyle üretilir).
  Future<void> _seciliYazdir([CariHareketModel? hareket]) async {
    final h = hareket ?? _seciliHareket;
    if (h == null || _yazdiriliyor) return;
    setState(() => _yazdiriliyor = true);
    try {
      if (h.fisTipi == 'Satış' || h.fisTipi == 'Toptan Satış') {
        if (h.fisId == null) throw Exception('Bu satışın fiş bilgisi bulunamadı');
        final satis = await SatisDeposu().idileGetir(h.fisId!);
        if (satis == null) throw Exception('Satış bulunamadı (silinmiş olabilir)');
        double? cariOnceki, cariSon;
        if (satis.cariId != null) {
          final b = await CariDeposu().bakiyeHareketAninda(h);
          cariOnceki = b.oncekiBakiye;
          cariSon = b.sonBakiye;
        }
        await YazdirmaServisi().fisYazdir(satis,
            cariUnvan: widget.cari.unvan,
            cariOncekiBakiye: cariOnceki,
            cariSonBakiye: cariSon);
      } else if (h.fisTipi == 'Tahsilat' || h.fisTipi == 'Odeme') {
        final b = await CariDeposu().bakiyeHareketAninda(h);
        await YazdirmaServisi().makbuzYazdir(
          makbuzNo: h.fisNo ?? 'KOPYA-${h.id}',
          tarih: h.tarih,
          cariUnvan: widget.cari.unvan,
          tutar: h.fisTipi == 'Tahsilat' ? h.alacak : h.borc,
          odemeTuru: h.odemeTuru ?? '—',
          islemTipi: h.fisTipi,
          aciklama: h.aciklama.isEmpty ? null : h.aciklama,
          kesenKisi: h.kullanici,
          oncekiBakiye: b.oncekiBakiye,
          sonBakiye: b.sonBakiye,
        );
      } else {
        throw Exception('Bu hareket türü yazdırılamaz');
      }
      if (mounted) BildirimServisi.basari(context, 'Yazdırıldı');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yazıcı hatası: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) {
        setState(() {
        _yazdiriliyor = false;
        _seciliHareket = null;
      });
      }
    }
  }

  // Bayi Portalı (erp_roadmap madde 39, kullanıcı onayıyla): bir Bayi
  // tipi cari için self-servis giriş hesabı oluşturur/yönetir. Sadece
  // admin/müdür görebilir/kullanabilir (route seviyesinde 'kullanici'
  // yetkisiyle zaten korunan kullanici_ekle_ekrani.dart'tan BİLİNÇLİ
  // OLARAK ayrı, sade bir akış — bayi hesabının rol/yetki seçimine
  // ihtiyacı yok, erişimi tamamen bayi_cari_id ile router seviyesinde
  // kısıtlanıyor).
  Future<void> _bayiGirisiYonet(BuildContext context, CariModel c) async {
    final mevcut = await KullaniciDeposu().bayiCariIleGetir(c.id!);

    if (mevcut != null) {
      final k = mevcut;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Bayi Girişi'),
          content: Text(
            'Bu bayinin zaten bir portal girişi var.\n\n'
            'Kullanıcı adı: ${k.kullaniciAdi}\n'
            'Durum: ${k.aktif ? 'Aktif' : 'Pasif'}\n\n'
            'Şifreyi sıfırlamak için kullanıcı yönetimi ekranından bu '
            'kullanıcıyı düzenleyin.',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
          ],
        ),
      );
      return;
    }

    final kullaniciAdiCtrl = TextEditingController(
        text: c.unvan.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim());
    final sifreCtrl = TextEditingController();
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Bayi Girişi Oluştur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.unvan} bu bilgilerle uygulamaya kendi başına giriş yapıp '
                'ürünleri görüp sipariş verebilecek.',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: kullaniciAdiCtrl,
              decoration: const InputDecoration(
                  labelText: 'Kullanıcı Adı', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sifreCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Şifre (en az 4 karakter)', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oluştur')),
        ],
      ),
    ).whenComplete(() => dialogSonrasiBirak([kullaniciAdiCtrl, sifreCtrl]));
    if (ok != true) return;
    final kullaniciAdi = kullaniciAdiCtrl.text.trim();
    final sifre = sifreCtrl.text.trim();
    if (kullaniciAdi.isEmpty || sifre.length < 4) {
      if (context.mounted) {
        BildirimServisi.uyari(context, 'Kullanıcı adı ve en az 4 karakterli şifre girin');
      }
      return;
    }
    try {
      final tuz = SifreHash.tuzUret();
      final model = KullaniciModel(
        kullaniciAdi: kullaniciAdi,
        sifreHash: SifreHash.hashleTuzlu(sifre, tuz),
        tuz: tuz,
        adSoyad: c.unvan,
        rol: 'personel',
        bayiCariId: c.id,
      );
      await KullaniciDeposu().ekle(model);
      if (context.mounted) {
        // Derin analizde bulundu: bayi oturumu (router kilidi sayesinde)
        // hiçbir otomatik senkron TETİKLEMİYOR — bu, kurulmamış/sıfır
        // bir cihazda bayinin kendi hesabının hiç inmemiş olması,
        // GİRİŞ BİLE YAPAMAMASI anlamına gelir. Bu tek seferlik kurulum
        // adımı olmadan bayi portalı yeni bir cihazda çalışmaz.
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Text('Bayi Girişi Oluşturuldu'),
            ]),
            content: Text(
              'Kullanıcı adı: $kullaniciAdi\n\n'
              'ÖNEMLİ — bayinin kendi cihazında İLK kullanımdan önce:\n'
              'Ayarlar → Bulut Sync → "Buluttan Al" bir kez çalıştırılmalı. '
              'Aksi halde bayinin hesabı ve ürün kataloğu cihaza hiç '
              'inmediği için giriş yapamaz.',
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anladım')),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) BildirimServisi.hata(context, 'Oluşturulamadı: $e');
    }
  }

  // Kullanıcı isteği (2026-09-13): "Borç Silme" — uygulamada borç sadece
  // ödeme ile azalıyordu, tahsil edilemeyen/hatayla girilmiş bir bakiyeyi
  // KAPATACAK bir yol hiç yoktu. Kanonik bakiye formülü
  // (SUM(borc)-SUM(alacak), bkz. CariDeposu.bakiyeYenidenHesapla) hiç
  // bozulmuyor — ters yönde (alacak) bir cari_hareket eklenir, hiçbir
  // geçmiş kayıt silinmez/değiştirilmez (ORİJİNAL→REVERSAL deseni,
  // FAZ 1 madde 5 ile aynı felsefe). Riskli/kötüye kullanılabilir bir
  // işlem olduğu için: (1) sadece müdür/admin görebilir/çalıştırabilir,
  // (2) hemen öncesinde kendi şifresini yeniden girmesi istenir, (3) her
  // zaman Onay Merkezi'ne kayıt düşer (OnayTuru.borcSilme zaten
  // onay_merkezi_servisi.dart'ta tanımlıydı ama hiçbir ekran bağlamıyordu).
  Future<void> _borcSil(BuildContext context, CariModel c) async {
    if (!ref.read(authProvider).isMudur) return;

    final tutarCtrl = TextEditingController(text: c.bakiye.toStringAsFixed(2));
    final sebepCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.money_off, color: Colors.red),
          SizedBox(width: 8),
          Text('Borç Sil'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.unvan} — güncel borç: ${ParaUtils.formatla(c.bakiye)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Bu işlem GERİ ALINAMAZ. Hatayla girilmiş veya tahsil '
              'edilemeyen bir borcu kapatmak için kullanın — cari hareket '
              'geçmişinde izlenebilir kalır, hiçbir kayıt silinmez.',
              style: TextStyle(fontSize: 11, color: Colors.orange),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tutarCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Silinecek Tutar (₺)', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sebepCtrl,
              decoration: const InputDecoration(
                  labelText: 'Sebep (zorunlu)', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Devam Et'),
          ),
        ],
      ),
    ).whenComplete(() => dialogSonrasiBirak([tutarCtrl, sebepCtrl]));
    if (ok != true) return;

    final tutar = ParaUtils.sayiCoz(tutarCtrl.text) ?? 0;
    final sebep = sebepCtrl.text.trim();
    if (tutar <= 0 || tutar > c.bakiye + 0.01) {
      if (context.mounted) {
        BildirimServisi.uyari(context, 'Geçerli bir tutar girin (0 - ${ParaUtils.formatla(c.bakiye)} arası)');
      }
      return;
    }
    if (sebep.isEmpty) {
      if (context.mounted) BildirimServisi.uyari(context, 'Sebep girilmesi zorunludur');
      return;
    }

    if (!context.mounted) return;
    final onaylandi = await yoneticiSifresiIleOnayIste(
      context,
      baslik: 'Borç Silme Onayı',
      aciklama: '${c.unvan} carisinden ${ParaUtils.formatla(tutar)} tutarında '
          'borç silinecek. Devam etmek için şifrenizi girin.',
    );
    if (!onaylandi) return;
    if (!context.mounted) return;
    if (!ref.read(authProvider).isMudur) return; // savunma: eylem anında ikinci kez doğrula

    try {
      await CariDeposu().hareketEkle(CariHareketModel(
        cariId: c.id!,
        fisTipi: 'Borç Silme',
        tarih: DateTime.now(),
        aciklama: 'Borç Silindi: $sebep',
        borc: 0,
        alacak: tutar,
        kullanici: ref.read(authProvider).aktifAd,
      ));
      await OnayMerkeziServisi().kaydet(
        tur: OnayTuru.borcSilme,
        tutar: tutar,
        esikTutar: OnayEsikleri.borcSilmeTutari,
        referansTuru: 'cari',
        referansId: c.id,
        aciklama: '${c.unvan}: $sebep',
      );
      if (context.mounted) {
        BildirimServisi.basari(context, 'Borç silindi: ${ParaUtils.formatla(tutar)}');
        ref.invalidate(cariDetayProvider(c.id!));
        ref.read(carilerProvider.notifier).yukle();
      }
    } catch (e) {
      if (context.mounted) BildirimServisi.hata(context, 'Silinemedi: $e');
    }
  }
}
