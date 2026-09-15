// ignore_for_file: invalid_use_of_protected_member
// lib/ekranlar/satis/hizli_satis_ekrani_odeme.dart
// hizli_satis_ekrani.dart'ın parçası — bkz.
// hizli_satis_ekrani_barkod.dart başındaki not. Bu dosya: indirim
// düzenleme, müşteri seçme, ödeme yöntemi seçme, nakit üstü hesabı,
// fiş güncelleme, SATIŞI TAMAMLAMA (_satisiTamamla — asıl checkout),
// sepet miktar düzenleme, tedarikçiye aktarma, askıya alma.
part of 'hizli_satis_ekrani.dart';

extension _HizliSatisOdemeExt on _HizliSatisEkraniState {
  // ── İndirim Dialog ───────────────────────────────────────────────────────────
  Future<void> _indirimDuzenle(SepetKalem k, int index) async {
    if (!mounted) return;
    _dialogAcik = true;
    _islemAktif = true;
    if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }

    final normalFiyat = k.urun.satisFiyati;
    final mevcutOran  = k.birimFiyat < normalFiyat - 0.01
        ? ((1 - k.birimFiyat / normalFiyat) * 100) : 0.0;
    final oranCtrl  = TextEditingController(
        text: mevcutOran > 0 ? mevcutOran.toStringAsFixed(1) : '');
    final fiyatCtrl = TextEditingController(
        text: k.birimFiyat.toStringAsFixed(2));

    final uygula = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        void oranDegisti(String v) {
          final oran = double.tryParse(v.replaceAll(',', '.'));
          if (oran != null && oran > 0 && oran < 100) {
            fiyatCtrl.text = (normalFiyat * (1 - oran / 100)).toStringAsFixed(2);
          } else if (oran == 0) {
            fiyatCtrl.text = normalFiyat.toStringAsFixed(2);
          }
          ss(() {});
        }
        void fiyatDegisti(String v) {
          final fiyat = double.tryParse(v.replaceAll(',', '.'));
          if (fiyat != null && fiyat > 0 && fiyat < normalFiyat) {
            oranCtrl.text = ((1 - fiyat / normalFiyat) * 100).toStringAsFixed(1);
          } else if (fiyat != null && fiyat >= normalFiyat) {
            oranCtrl.text = '';
          }
          ss(() {});
        }
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(k.urun.urunAdi,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: TextField(
                controller: oranCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'İndirim %', border: OutlineInputBorder()),
                onChanged: oranDegisti,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: fiyatCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Fiyat ₺', border: OutlineInputBorder()),
                onChanged: fiyatDegisti,
              )),
            ]),
          ]),
          actions: [
            TextButton(
              onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx, false); },
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx, true); },
              child: const Text('Uygula'),
            ),
          ],
        );
      }),
    );

    if (_kameraAcik && mounted) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    if (uygula != true || !mounted) return;
    final yeniFiyat = double.tryParse(fiyatCtrl.text.replaceAll(',', '.'));
    if (yeniFiyat != null && yeniFiyat > 0) {
      ref.read(sepetProvider.notifier).fiyatGuncelle(index, yeniFiyat);
    }
  }

  // ── Müşteri Seç ──────────────────────────────────────────────────────────────
  Future<void> _musteriSec() async {
    if (_islemAktif || _dialogAcik) return; // çift-tıklama koruması
    _islemBasladi();
    try {
      final cariler = await _cariDepo.tumunuGetir();
      if (!mounted) return;
      final secilen = await showModalBottomSheet<CariModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _MusteriSecimPaneli(cariler: cariler),
      );
      if (secilen == null || !mounted) return;

      final tedarikciMi = secilen.cariTipi.contains('edarik');
      if (tedarikciMi) {
        if (ref.read(sepetProvider).bos) {
          BildirimServisi.bilgi(context,
              '${secilen.unvan} bir Tedarikçi. Sepet boş olduğu için doğrudan Alım ekranına yönlendiriliyorsunuz.');
          if (mounted) context.push('/tedarik/alim', extra: secilen);
          return;
        }
        await _sepetiAlimaAktar(secilen);
        return;
      }

      ref.read(sepetProvider.notifier).musteriSec(secilen);
    } catch (e) {
      if (kDebugMode) debugPrint('Müşteri seçme hatası: $e');
      if (mounted) BildirimServisi.hata(context, 'Müşteri listesi yüklenemedi: $e');
    } finally {
      _islemBitti();
    }
  }

  // ── Ödeme Akışı ──────────────────────────────────────────────────────────────
  Future<void> _odemeYontemiSec() async {
    final sepet  = ref.read(sepetProvider);
    // 🔴🔴 KRİTİK DÜZELTME (hızlı satış derin analizi, 2026-09-14): bu
    // fonksiyon çift-tıklamaya karşı HİÇ korunmuyordu — barkod okutma
    // (_barkodOkutIsle) '_islemAktif'i zaten kontrol ediyordu ama "Ödeme
    // Al" butonu bunu hiç yapmıyordu. Aynı anda iki kez tetiklenirse AYNI
    // sepet için İKİ AYRI satış tamamlanabilir (çift stok düşümü, çift
    // kasa/cari hareketi) — bkz. satis_alt_panel.dart'taki eşlik eden
    // düzeltme (buton görsel olarak da devre dışı bırakılıyor artık).
    if (sepet.bos || _islemAktif || _dialogAcik) return;
    _islemBasladi();

    try {
      final yontem = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _OdemeSecimSheet(toplam: sepet.genelToplam, musteriSecili: sepet.musteri != null),
      );
      if (!mounted || yontem == null) return;

      if (yontem == 'Karma') {
        final sonuc = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => SizedBox(
            height: MediaQuery.of(context).size.height * 0.94,
            child: CokluOdemeEkrani(
              toplamTutar: sepet.genelToplam,
              cariMevcut: sepet.musteri != null,
            ),
          ),
        );
        if (!mounted || sonuc == null) return;
        final kalemler = (sonuc['kalemler'] as List).cast<Map<String, dynamic>>();
        final toplamOdenen = (sonuc['toplam_odenen'] as num?)?.toDouble() ?? sepet.genelToplam;
        final paraUstu = (sonuc['para_ustu'] as num?)?.toDouble() ?? 0.0;
        final odemeYontemiEtiketi = kalemler.length == 1
            ? (kalemler.first['yontem'] as String) : 'Karma';
        await _satisiTamamla(odemeYontemiEtiketi, toplamOdenen, paraUstu,
            karmaKalemler: kalemler);
      } else if (yontem == 'Nakit') {
        final alinan = await _nakitAlintiSor(sepet.genelToplam);
        if (!mounted || alinan == null) return;
        final paraUstu = alinan - sepet.genelToplam;
        await _satisiTamamla('Nakit', alinan, paraUstu > 0 ? paraUstu : 0.0);
      } else {
        await _satisiTamamla(yontem, sepet.genelToplam, 0.0);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Ödeme akışı hatası: $e');
      if (mounted) BildirimServisi.hata(context, 'Ödeme işlemi başarısız: $e');
    } finally {
      _islemBitti();
    }
  }

  Future<double?> _nakitAlintiSor(double toplam) async {
    _dialogAcik = true;
    final ctrl = TextEditingController();
    final sonuc = await showDialog<double?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) { _dialogAcik = false; _islemAktif = false; },
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Nakit Ödeme'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Toplam: ${ParaUtils.formatla(toplam)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(
                hintText: 'Boş → tam tutar',
                labelText: 'Alınan Tutar (₺)',
                prefixIcon: Icon(Icons.payments),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: const Text('Para Üstü Hesapla'),
                onPressed: () async {
                  final alinan = await Navigator.push<double>(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) =>
                          ParaUstuEkrani(odenmesiGereken: toplam),
                    ),
                  );
                  if (alinan != null) {
                    ctrl.text = alinan.toStringAsFixed(2);
                  }
                },
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx); },
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final txt = ctrl.text.trim().replaceAll(',', '.');
                final val = txt.isEmpty ? toplam : double.tryParse(txt);
                _dialogAcik = false; _islemAktif = false;
                Navigator.pop(ctx, val);
              },
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
    return sonuc;
  }

  // ── Satış Tamamla ────────────────────────────────────────────────────────────
  Future<void> _fisiGuncelle() async {
    final satis = _guncellenenSatis;
    if (satis == null || satis.id == null) return;

    final sepet    = ref.read(sepetProvider);
    final kalemler = List<SepetKalem>.from(sepet.kalemler);
    if (kalemler.isEmpty) {
      BildirimServisi.uyari(context,
          'Sepet boş. Fişi tamamen iptal etmek için Satışlar ekranını kullanın.');
      return;
    }

    _islemBasladi();
    try {
      final kullanici = await AuthServisi().mevcutKullanici();
      if (!mounted) return;

      // Kalemler + stok farkı + cari/kasa hareketi — hepsi
      // SatisTamamlamaServisi.fisiGuncelle()'de TEK transaction'da atomik
      // (protokol §6/§35 — önceden bu ekranda 4 ayrı, transaction'sız
      // çağrıydı; davranış birebir korunarak servise taşındı).
      final sonuc = await _satisTamamlamaServisi.fisiGuncelle(
        satis: satis,
        yeniKalemler: kalemler,
        yeniGenelToplam: sepet.genelToplam,
        kullanici: kullanici,
      );
      final tutarFarki = sonuc.tutarFarki;

      if (satis.cariId != null && mounted) {
        ProviderScope.containerOf(context, listen: false)
            .invalidate(cariDetayProvider(satis.cariId!));
      }

      if (!mounted) return;
      ref.read(sepetProvider.notifier).temizle();
      ref.read(dashboardProvider.notifier).yenile();

      // Güncellenmiş fiş bilgisini _sonSatis'e ata (manuel yazdırma için)
      setState(() {
        _sonSatis = sonuc.guncelSatis;
      });

      setState(() => _guncellenenSatis = null);

      final ozet = tutarFarki > 0
          ? '+${ParaUtils.formatla(tutarFarki)}'
          : tutarFarki < 0
              ? '-${ParaUtils.formatla(-tutarFarki)}'
              : 'tutar değişmedi';
      BildirimServisi.basari(context, 'Fiş ${satis.fisNo} güncellendi ($ozet)');

      // YAZDIRMA DİALOGU KALDIRILDI — manuel yazdırma butonu ile yapılacak.

    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Fiş güncellenemedi: ${kullaniciyaHataMetni(e)}');
    } finally {
      _islemBitti();
    }
  }

  Future<void> _satisiTamamla(
      String odemeYontemi, double odenenTutar, double paraUstu,
      {List<Map<String, dynamic>>? karmaKalemler}) async {
    if (!mounted) return;

    if (_guncellenenSatis != null) {
      await _fisiGuncelle();
      return;
    }

    _islemBasladi();
    ref.read(sepetProvider.notifier).satisBasladi();

    final sepet     = ref.read(sepetProvider);
    final musteri   = sepet.musteri;
    final kalemler  = List<SepetKalem>.from(sepet.kalemler);
    final genelTop  = sepet.genelToplam;

    try {
      final kullanici = await AuthServisi().mevcutKullanici();
      if (!mounted) return;

      // Satış kaydı + stok düşümü + kasa/cari hareketi + bulut senkronu +
      // puan — hepsi SatisTamamlamaServisi'nde (tek transaction, atomik).
      // Önceden bu mantık doğrudan bu ekranda yaşıyordu (protokol §6/§35
      // — mimari borç); davranış BİREBİR korunarak servise taşındı.
      final sonuc = await _satisTamamlamaServisi.tamamla(
        kalemler:      kalemler,
        musteri:       musteri,
        genelToplam:   genelTop,
        odemeYontemi:  odemeYontemi,
        odenenTutar:   odenenTutar,
        karmaKalemler: karmaKalemler,
        kullanici:     kullanici,
        subeId:        AktifSubeServisi().subeId,
      );
      final satisId = sonuc.satisId;
      final fisNo = sonuc.fisNo;
      final tarih = sonuc.tarih;
      final satisKalemler = sonuc.kalemler;

      // FAZ 9 — Onay Merkezi (bildirim tipi): satış ENGELLENMEDİ, zaten
      // tamamlandı — sadece genel iskonto oranı eşiği aşıyorsa sonradan
      // incelenebilsin diye kayda düşülüyor.
      OnayMerkeziServisi().kaydet(
        tur: OnayTuru.yuksekIskonto,
        tutar: sepet.genelIskontoYuzde,
        esikTutar: OnayEsikleri.yuksekIskontoOrani,
        referansTuru: 'satis',
        referansId: satisId,
        aciklama: 'Fiş $fisNo: %${sepet.genelIskontoYuzde.toStringAsFixed(0)} iskonto',
      );

      if (!mounted) return;

      // ── Son satış bilgisini sakla (manuel yazdırma için) ──
      setState(() {
        _sonSatis = SatisModel(
          id: satisId,
          fisNo: fisNo,
          tarih: tarih,
          odemeYontemi: odemeYontemi,
          genelToplam: genelTop,
          odenenTutar: odenenTutar,
          kalemler: satisKalemler,
          cariId: musteri?.id,
          cariAdi: musteri?.unvan,
        );
      });

      ref.read(sepetProvider.notifier).temizle();
      ref.read(dashboardProvider.notifier).yenile();
      setState(() {
        _bekleyenSayiFuture = BekleyenFislerEkrani.bekleyenSayi();
      });

      final mesaj = (odemeYontemi == 'Nakit' && paraUstu > 0.005)
          ? 'Satış tamamlandı ✓  Para üstü: ${ParaUtils.formatla(paraUstu)}'
          : 'Satış başarıyla tamamlandı ✓';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mesaj),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Fişi Gör',
            textColor: Colors.white,
            onPressed: () {
              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => FisOnizlemeEkrani(satis: SatisModel(
                  id:          satisId,
                  fisNo:       fisNo,
                  tarih:       tarih,
                  odemeYontemi: odemeYontemi,
                  genelToplam: genelTop,
                  odenenTutar: odenenTutar,
                  kalemler:    satisKalemler,
                  cariId:      musteri?.id,
                  cariAdi:     musteri?.unvan,
                )),
              ));
            },
          ),
        ));
      }

      // Yazdırma işlemi tamamen kaldırıldı. Kullanıcı appBar'daki yazıcı ikonu ile manuel olarak yazdıracak.

    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Satış hatası: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) ref.read(sepetProvider.notifier).satisGitti();
      _islemBitti();
    }
  }

  // ── Sepet Kalem Düzenleme ────────────────────────────────────────────────────
  Future<void> _sepetKalemMiktarDuzenle(SepetKalem k, int index) async {
    if (_kgBirimMi(k.urun.birimAdi)) { await _kgIleEkle(k.urun); return; }
    _dialogAcik = true;
    _islemAktif = true;
    if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }

    final ctrl = TextEditingController(text: k.miktar.toInt().toString());
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(k.urun.urunAdi,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: 'Miktar',
            border: const OutlineInputBorder(),
            suffixText: k.urun.birimAdi,
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx, false); },
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx, true); },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );

    if (_kameraAcik && mounted) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    if (ok != true || !mounted) return;
    final yeniMiktar = double.tryParse(ctrl.text.replaceAll(',', '.'));
    if (yeniMiktar == null || yeniMiktar <= 0) {
      ref.read(sepetProvider.notifier).sil(index);
    } else {
      ref.read(sepetProvider.notifier).miktarGuncelle(index, yeniMiktar);
    }
    _kuyruktakiBarkodlariIsle();
  }

  // ── Askıya Al ────────────────────────────────────────────────────────────────
  Future<void> _sepetiAlimaAktar(CariModel tedarikci) async {
    final sepet = ref.read(sepetProvider);
    if (sepet.bos || !mounted) return;

    final sepetKalemler = sepet.kalemler.map((k) => {
      'urunId':    k.urun.id,
      'urunAdi':   k.urun.urunAdi,
      'miktar':    k.miktar,
      'alisFiyat': k.urun.alisFiyat > 0 ? k.urun.alisFiyat : k.urun.satisFiyati,
    }).toList();

    ref.read(sepetProvider.notifier).temizle();
    if (!mounted) return;

    await context.push('/tedarik/alim',
        extra: {'tedarikci': tedarikci, 'kalemler': sepetKalemler});
    if (mounted) setState(() {});
  }

  Future<void> _tedarikciyeAktar() async {
    final sepet = ref.read(sepetProvider);
    if (sepet.bos || _islemAktif || _dialogAcik) return; // çift-tıklama koruması
    _islemBasladi();
    try {
      final list = await CariDeposu().tumunuGetir().then((l) => l.where((x) =>
          x.cariTipi.contains('edarik') || x.cariTipi.contains('Hem ')).toList());
      if (!mounted) { _islemBitti(); return; }
      final tedarikci = await showDialog<CariModel>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.shopping_basket_outlined, color: Colors.teal),
            const SizedBox(width: 8),
            Text('Tedarikçi Seç'),
          ]),
          contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          content: SizedBox(
            width: double.maxFinite, height: 360,
            child: list.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.person_off_outlined, size: 48, color: context.textSecondary),
                  const SizedBox(height: 8),
                  Text('Tedarikçi bulunamadı', style: TextStyle(color: context.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Cari menüsünden Tedarikçi ekleyin',
                      style: TextStyle(fontSize: 12, color: context.textSecondary), textAlign: TextAlign.center),
                ]))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final t = list[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(radius: 18,
                        backgroundColor: Colors.teal.shade50,
                        child: Text(t.unvan.isNotEmpty ? t.unvan[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.teal.shade700))),
                      title: Text(t.unvan, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: t.telefon != null ? Text(t.telefon!) : null,
                      onTap: () => Navigator.pop(ctx, t),
                    );
                  }),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal'))],
        ),
      );
      _islemBitti();
      if (tedarikci == null || !mounted) return;
      await _sepetiAlimaAktar(tedarikci);
    } catch (e) {
      _islemBitti();
      if (mounted) BildirimServisi.hata(context, kullaniciyaHataMetni(e));
    }
  }

  Future<void> _askiyaAl() async {
    final sepet = ref.read(sepetProvider);
    if (sepet.bos || _islemAktif || _dialogAcik) return; // çift-tıklama koruması
    _islemBasladi();

    try {
      await BekleyenFislerEkrani.askiyaAl(
        sepet:   sepet.kalemler,
        musteri: sepet.musteri,
      );

      ref.read(sepetProvider.notifier).temizle();
      if (mounted) setState(() => _bekleyenSayiFuture = BekleyenFislerEkrani.bekleyenSayi());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Satış askıya alındı'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Askıya alma hatası: $e');
      if (mounted) BildirimServisi.hata(context, 'Askıya alınamadı: $e');
    } finally {
      _islemBitti();
    }
  }

}
