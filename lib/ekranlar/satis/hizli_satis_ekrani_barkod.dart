// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: bu dosya extension ile _HizliSatisEkraniState'e metod ekliyor —
// setState() gerçekten kendi State sınıfının üzerinde çağrılıyor, ama
// analizci extension içinden çağrıyı "korumalı üyeye dışarıdan erişim"
// sayıyor (bkz. iade_ekrani_hizli.dart'taki aynı, doğrulanmış not).
// lib/ekranlar/satis/hizli_satis_ekrani_barkod.dart
//
// hizli_satis_ekrani.dart'ın parçası (part/part of) — dosya çok
// büyümüştü (1855 satır, uygulamanın ana SATIŞ/KASA ekranı), davranış
// BİREBİR AYNI kalacak şekilde sorumluluk alanına göre 3 dosyaya
// bölündü. Bu dosya: barkod okuma/işleme, PLU, hızlı tuş, fiş geri
// çağırma, kg'lı ürün ekleme, arama, sepete akıllı ekleme, kamera.
part of 'hizli_satis_ekrani.dart';

extension _HizliSatisBarkodExt on _HizliSatisEkraniState {
  // ── İşlem Kontrol ───────────────────────────────────────────────────────────
  void _islemBasladi() {
    _islemAktif = true;
    if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }
  }

  void _islemBitti() {
    _islemAktif = false;
    _dialogAcik = false;
    if (_kameraAcik && mounted) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    _kuyruktakiBarkodlariIsle();
  }

  // ── Barkod Kontrol ───────────────────────────────────────────────────────────
  Future<void> _barkodOkutIsle(String barkod) async {
    if (_islemAktif || _dialogAcik) {
      _barkodKuyrugu.add(barkod);
      _kuyruktakiBarkodlariIsle();
      return;
    }
    if (_sonIslenenBarkod == barkod && _sonIslenenZaman != null &&
        DateTime.now().difference(_sonIslenenZaman!) <
            _HizliSatisEkraniState._ayniBarkodMinAralik) return;
    if (_scannerKilitli || _barkodIsleniyor) {
      _barkodKuyrugu.add(barkod);
      _kuyruktakiBarkodlariIsle();
      return;
    }
    await _barkodIsle(barkod);
  }

  Future<void> _barkodIsle(String barkod) async {
    _barkodIsleniyor = true;
    _sonIslenenBarkod = barkod;
    _sonIslenenZaman = DateTime.now();
    _scannerKilitli = true;
    _scannerKilitAcmaTimer = Timer(const Duration(milliseconds: 300), () {
      _scannerKilitli = false;
      _kuyruktakiBarkodlariIsle();
    });
    _bipSes();
    try {
      await _barkodIleEkle(barkod);
    } catch (e) {
      if (kDebugMode) debugPrint('Barkod işleme hatası: $e');
      if (mounted) {
        BildirimServisi.hata(context, 'Ürün eklenemedi: $barkod bulunamadı veya bir hata oluştu');
      }
    } finally {
      _barkodIsleniyor = false;
    }
  }

  void _kuyruktakiBarkodlariIsle() {
    _barkodIslemeTimer?.cancel();
    if (_barkodKuyrugu.isEmpty || _islemAktif || _dialogAcik) return;
    _barkodIslemeTimer = Timer(const Duration(milliseconds: 150), () async {
      if (_barkodKuyrugu.isNotEmpty && !_islemAktif && !_dialogAcik && !_barkodIsleniyor) {
        final barkod = _barkodKuyrugu.removeFirst();
        await _barkodIsle(barkod);
        if (_barkodKuyrugu.isNotEmpty) _kuyruktakiBarkodlariIsle();
      }
    });
  }

  void _bipSes() {
    if (_islemAktif || _dialogAcik) return;
    _player.stop().then((_) {
      _player.play(AssetSource('sounds/bip.mp3'), volume: 0.5);
    }).catchError((_) {});
    Vibration.hasVibrator().then((has) {
      if (has ?? false) Vibration.vibrate(duration: 50);
    }).catchError((_) {});
  }

  // ── PLU / Barkod İşleme ──────────────────────────────────────────────────────
  Future<void> _pluAc() async {
    try {  
      _araFocus.unfocus();
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useRootNavigator: true,
        builder: (sheetCtx) => PluEkrani(
          onUrunSec: (urun) {
            ref.read(sepetProvider.notifier).ekleAsync(urun);
            Navigator.pop(sheetCtx);
          },
        ),
      );
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  // ── 🆕 HIZLI TUŞ (FAVORİ ÜRÜN) PANELİ ────────────────────────────────────────
  Future<void> _hizliTusAc() async {
    var tekrarAc = true;
    while (tekrarAc && mounted) {
      tekrarAc = false;
      try {
        if (!mounted) return;
        _araFocus.unfocus();
        final sonuc = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          useRootNavigator: true,
          builder: (sheetCtx) => HizliTusPaneli(
            onUrunSec: (urun) async {
              Navigator.pop(sheetCtx, 'secildi');
              if (!mounted) return;
              if (_kgBirimMi(urun.birimAdi)) {
                await _kgIleEkle(urun);
              } else {
                await ref.read(sepetProvider.notifier).ekleAsync(urun);
              }
              if (!mounted) return;
              _bipSes();
              if (_sepetScroll.hasClients) _sepetScroll.jumpTo(0);
            },
            onDuzenle: () => Navigator.pop(sheetCtx, 'duzenle'),
          ),
        );

        if (sonuc == 'duzenle' && mounted) {
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const HizliTusYonetimEkrani()),
          );
          tekrarAc = true;
        }
      } catch (e) {
        if (kDebugMode) if (mounted) debugPrint('Hızlı tuş hatası: $e');
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 FİŞ BARKODU TANIMA
  static final _fisNoDeseni = RegExp(r'^(MKP|CRI|MSA)\d{13}$');
  bool _fisBarkoduMu(String b) => _fisNoDeseni.hasMatch(b.toUpperCase());

  // ══════════════════════════════════════════════════════════════════════
  // 🆕 FİŞ GERİ ÇAĞIRMA
  Future<void> _fisGeriCagir(String fisNo) async {
    try {
      final satis = await _satisDepo.fisNoIleGetir(fisNo);
      if (!mounted) return;

      if (satis == null) {
        BildirimServisi.uyari(context,
            'Fiş bulunamadı veya iptal edilmiş: $fisNo');
        return;
      }

      final mevcutSepet = ref.read(sepetProvider).kalemler;
      if (mevcutSepet.isNotEmpty) {
        final devam = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)),
              SizedBox(width: 8),
              Expanded(child: Text('Sepet Dolu', style: TextStyle(fontSize: 15))),
            ]),
            content: Text(
              'Sepetinizde ${mevcutSepet.length} ürün var.\n\n'
              'Fiş geri çağrılırsa bu ürünler SİLİNECEK.',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade800),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sepeti Boşalt, Devam Et'),
              ),
            ],
          ),
        );
        if (devam != true || !mounted) return;
      }

      final onay = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.receipt_long_rounded, color: Color(0xFF4361EE)),
            SizedBox(width: 8),
            Expanded(child: Text('Fiş Bulundu', style: TextStyle(fontSize: 15))),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fisOzetSatiri('Fiş No', satis.fisNo ?? '-'),
              _fisOzetSatiri('Tarih',
                  DateFormat('dd.MM.yyyy HH:mm').format(satis.tarih)),
              if ((satis.cariAdi ?? '').isNotEmpty)
                _fisOzetSatiri('Cari', satis.cariAdi!),
              _fisOzetSatiri('Ürün', '${satis.kalemler.length} kalem'),
              _fisOzetSatiri('Tutar', ParaUtils.formatla(satis.genelToplam)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TsRenk.zemin(TsRenk.uyari),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: Colors.orange.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fişin ürünleri sepete yüklenecek. Miktar '
                      'değiştirebilir, kalem silebilir, yeni ürün '
                      'ekleyebilirsiniz.\n\n'
                      'Tamamladığınızda FİŞ GÜNCELLENECEK — müşterideki '
                      'basılı fiş ile sistemdeki kayıt farklı olacaktır.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton.icon(
              icon: const Icon(Icons.edit_rounded, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('Fişi Düzenle'),
            ),
          ],
        ),
      );
      if (onay != true || !mounted) return;

      // 🔴 DÜZELTME (kritik — derin denetimde bulundu): fiş geri çağrılıp
      // "Tamamla" ile güncellenince kalemler/tutar SESSİZCE değişiyordu —
      // bu satış için zaten bir fatura kesilmişse, basılı/GİB'e gönderilmiş
      // faturayla sistemdeki kayıt burada diverjans yaşayabiliyordu.
      // Codebase'in her yerinde uygulanan "faturalandırılmış bir satış
      // doğrudan düzenlenemez" kuralı bu girişte hiç kontrol edilmiyordu.
      final faturaId = await FaturalandirmaServisi.mevcutFaturaId(satisId: satis.id);
      if (faturaId != null) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(child: Text('Bu Satış Faturalandırılmış')),
            ]),
            content: const Text(
                'Bu fiş için zaten bir fatura kesilmiş — kalemleri/tutarı '
                'değiştirmek üzere geri çağrılamaz. Düzeltme yapmak için '
                'Satış Detayı\'ndan "İade Et" ile ters kayıt oluşturun.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
            ],
          ),
        );
        return;
      }

      ref.read(sepetProvider.notifier).temizle();

      final bulunamayan = <String>[];
      for (final k in satis.kalemler) {
        final urun = await _urunDepo.idileGetir(k.urunId);
        if (urun == null) {
          bulunamayan.add(k.urunAdi);
          continue;
        }
        ref.read(sepetProvider.notifier).ekle(
          urun,
          miktar: k.miktar,
          fiyatOverride: k.birimFiyat,
        );
      }
      if (!mounted) return;

      setState(() {
        _guncellenenSatis = satis;
      });

      if (bulunamayan.isNotEmpty) {
        BildirimServisi.uyari(context,
            '${bulunamayan.length} ürün artık kayıtlı değil ve sepete '
            'yüklenemedi: ${bulunamayan.take(3).join(", ")}'
            '${bulunamayan.length > 3 ? "…" : ""}');
      } else {
        BildirimServisi.basari(context,
            'Fiş ${satis.fisNo} sepete yüklendi — düzeltme yapıp '
            'veya ürün ekleyip tamamlayın');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Fiş çağrılamadı: $e');
    }
  }

  Widget _fisOzetSatiri(String etiket, String deger) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
            width: 62,
            child: Text('$etiket:',
                style: TextStyle(
                    fontSize: 12, color: context.textSecondary)),
          ),
          Expanded(
            child: Text(deger,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Future<void> _barkodIleEkle(String barkod) async {
    if (!mounted) return;
    final b = barkod.trim();

    if (_fisBarkoduMu(b)) {
      await _fisGeriCagir(b.toUpperCase());
      return;
    }

    // 🔴 DÜZELTME (Madde 34 — Barkod/POS denetimi, 2026-09-20): burada
    // ÖNCEDEN barkod_servisi.dart'taki KANONİK tartimBarkodCoz()'un
    // BAĞIMSIZ, kontrol basamağı doğrulaması OLMAYAN bir kopyası vardı.
    // Sonuç: bozuk/hatalı bir taramadan gelen (ör. tarayıcı bir hane
    // yanlış okudu) 13 haneli, prefix 20-29 ile başlayan HERHANGİ bir
    // dizi, EAN-13 kontrol basamağı hiç doğrulanmadan ağırlık/ürün kodu
    // olarak GÜVENİLİYOR ve doğrudan sepete ekleniyordu — bu miktar
    // stok_hareket/kasa/cari'yi gerçek bir satışta etkiler. Artık
    // BarkodServisi.tartimBarkodCoz() kullanılıyor (ean13Gecerli()
    // kontrolü dahil) — geçersiz kontrol basamaklı bir tarama artık
    // SESSİZCE kabul edilmiyor, aşağıdaki normal barkod arama yoluna
    // düşüyor (muhtemelen "Ürün Bulunamadı" — bu, YANLIŞ bir miktarı
    // sessizce kabul etmekten çok daha güvenli bir başarısızlık şekli).
    if (b.length == 13) {
      final tartim = BarkodServisi.tartimBarkodCoz(b);
      if (tartim != null) {
        final urun = await _urunDepo.barkodlaGetir(tartim.urunKodu);
        if (!mounted) return;
        if (urun != null) {
          ref.read(sepetProvider.notifier).ekleAsync(urun, miktar: tartim.miktarKg);
          return;
        }
      }
    }

    // 🔴 EKLENDİ (Madde 34 — Barkod/POS denetimi, 2026-09-20): GS1-128/
    // GS1-DataMatrix çözücü (barkod_servisi.dart gs1128Coz/barkodTurunuBul)
    // ZATEN yazılmıştı ama HİÇ ÇAĞRILMIYORDU — gerçek bir GS1 barkodu
    // (ör. "(01)08691234567890(17)261231(10)LOT123") literal bir dize
    // olarak urunler.barkod'a karşı aranıyordu, hiçbir zaman eşleşmez ve
    // "Ürün Bulunamadı" verirdi. Artık AI(01) (GTIN) ayıklanıp aranıyor
    // — GTIN-14, EAN-13 kökenli ürünlerde baştaki dolgu sıfırıyla
    // birlikte 14 hane olduğundan, hem tam GTIN hem son-13-hane (EAN-13
    // karşılığı) denenir.
    if (BarkodServisi.barkodTurunuBul(b) == BarkodTuru.gs1128) {
      final ai = BarkodServisi.gs1128Coz(b);
      final gtin = ai['AI_01'] ?? ai['AI_02'];
      if (gtin != null && gtin.isNotEmpty) {
        var gs1Urun = await _urunDepo.barkodlaGetir(gtin);
        if (gs1Urun == null && gtin.length == 14) {
          gs1Urun = await _urunDepo.barkodlaGetir(gtin.substring(1));
        }
        if (!mounted) return;
        if (gs1Urun != null) {
          if (_kgBirimMi(gs1Urun.birimAdi)) {
            await _kgIleEkle(gs1Urun);
          } else {
            await ref.read(sepetProvider.notifier).ekleAsync(gs1Urun);
          }
          Future.microtask(() {
            if (_sepetScroll.hasClients) _sepetScroll.jumpTo(0);
          });
          return;
        }
      }
    }

    final urun = await _urunDepo.barkodlaGetir(b);
    if (!mounted) return;
    if (urun != null) {
      if (_kgBirimMi(urun.birimAdi)) {
        await _kgIleEkle(urun);
      } else {
        await ref.read(sepetProvider.notifier).ekleAsync(urun);
      }
      Future.microtask(() {
        if (_sepetScroll.hasClients) _sepetScroll.jumpTo(0);
      });
      return;
    }
    if (!mounted) return;
    final kayitYap = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.search_off_rounded, color: Color(0xFFE65100)),
          SizedBox(width: 8),
          Text('Ürün Bulunamadı', style: TextStyle(fontSize: 15)),
        ]),
        content: Text('$b\n\nBu barkodla ürün kaydı yok.\nŞimdi eklemek ister misiniz?',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hayır'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ürün Ekle'),
          ),
        ],
      ),
    );
    if (kayitYap != true || !mounted) return;
    final eklendi = await context.push<bool>(
      '/urun/ekle',
      extra: {'barkod': b, 'kaynak': 'hizli_satis'},
    );
    if (!mounted) return;
    if (eklendi == true) {
      final yeniUrun = await _urunDepo.barkodlaGetir(b);
      if (!mounted) return;
      if (yeniUrun != null) {
        ref.read(sepetProvider.notifier).ekle(yeniUrun);
        BildirimServisi.basari(context, '${yeniUrun.urunAdi} sepete eklendi');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sepetScroll.hasClients) {
            _sepetScroll.animateTo(0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
          }
        });
      }
    }
  }

  bool _kgBirimMi(String birimAdi) {
    final b = birimAdi.toLowerCase()
        .replaceAll('ı', 'i').replaceAll('İ'.toLowerCase(), 'i');
    return b == 'kg' || b == 'kilogram' || b == 'gr' || b == 'gram' ||
        b == 'lt' || b == 'litre' || b == 'ml' || b == 'mt' || b == 'metre';
  }

  Future<void> _kgIleEkle(UrunModel urun) async {
    if (!mounted) return;
    _dialogAcik = true;
    _islemAktif = true;
    if (_kameraAcik) { try { _scanCtrl.stop(); } catch (e) { /* ignore */ } }

    final ctrl = TextEditingController();
    double m = 0;

    final miktar = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            const Icon(Icons.scale_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(urun.urunAdi,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Miktar (${urun.birimAdi})',
                prefixIcon: const Icon(Icons.scale_rounded, color: Colors.orange),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                m = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                ss(() {});
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: m > 0 ? TsRenk.zemin(TsRenk.basarili) : TsRenk.arkaplan(ctx),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: m > 0 ? Colors.green.shade300 : TsRenk.ayirac(ctx)),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  // 🔴 DÜZELTME (hızlı satış derin analizi, 2026-09-14):
                  // '\$' (kaçışlı dolar) kullanıldığı için bu iki metin
                  // hiç interpolasyon YAPMIYORDU — ekranda kelimenin tam
                  // anlamıyla "${m.toStringAsFixed(3)} ${urun.birimAdi}"
                  // yazıyordu, gerçek miktar/birim fiyat GÖRÜNMÜYORDU.
                  Text('${m.toStringAsFixed(3)} ${urun.birimAdi}',
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(ctx))),
                  Text('@${ParaUtils.formatla(urun.indirimliFiyat)}/${urun.birimAdi}',
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(ctx))),
                ]),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Tutar:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(m > 0 ? ParaUtils.formatla(m * urun.indirimliFiyat) : '—',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                        color: m > 0 ? Colors.green.shade700 : context.textSecondary)),
                ]),
              ]),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () { _dialogAcik = false; _islemAktif = false; Navigator.pop(ctx); },
              child: const Text('İptal'),
            ),
            FilledButton.icon(
              onPressed: () {
                final mv = double.tryParse(ctrl.text.replaceAll(',', '.'));
                if (mv == null || mv <= 0) return;
                _dialogAcik = false;
                _islemAktif = false;
                Navigator.pop(ctx, mv);
              },
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Ekle'),
              style: FilledButton.styleFrom(foregroundColor: Colors.white,
                  backgroundColor: Colors.orange),
            ),
          ],
        ),
      ),
    );

    if (_kameraAcik && mounted) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    if (!mounted || miktar == null || miktar <= 0) return;
    ref.read(sepetProvider.notifier).ekle(urun, miktar: miktar);
    Future.microtask(() {
      if (_sepetScroll.hasClients) _sepetScroll.jumpTo(0);
    });
    _kuyruktakiBarkodlariIsle();
  }

  // ── Arama ────────────────────────────────────────────────────────────────────
  void _aramaDegisti(String q) {
    _araDebounce?.cancel();
    final temiz = q.trim();
    if (temiz.isEmpty) {
      setState(() => _aramaSonuclari = []);
      return;
    }
    if (temiz.length < 2) return;
    final aramaId = ++_aramaId;
    _araDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final sonuclar = await _urunDepo.ara(temiz, limit: 20);
        if (!mounted || aramaId != _aramaId) return;
        setState(() => _aramaSonuclari = sonuclar);
      } catch (e) { /* ignore */ }
    });
  }

  Future<void> _urunSepeteEkleAkilli(UrunModel urun) async {
    try {
      if (_kgBirimMi(urun.birimAdi)) {
        _kgIleEkle(urun);
      } else {
        await ref.read(sepetProvider.notifier).ekleAsync(urun);
      }
      _araCtrl.clear();
      setState(() => _aramaSonuclari = []);
      Future.microtask(() {
        if (_sepetScroll.hasClients && _sepetScroll.position.pixels > 0) {
          _sepetScroll.jumpTo(0);
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Ürün ekleme hatası: $e');
      if (mounted) {
        BildirimServisi.hata(context, '${urun.urunAdi} sepete eklenemedi: $e');
      }
    }
  }

  // ── Kamera Toggle ────────────────────────────────────────────────────────────
  void _kameraToggle() {
    final yeni = !_kameraAcik;
    if (yeni) {
      if (!_islemAktif && !_dialogAcik) { try { _scanCtrl.start(); } catch (e) { /* ignore */ } }
    } else {
      try { _scanCtrl.stop(); } catch (e) { /* ignore */ }
    }
    setState(() => _kameraAcik = yeni);
  }

}
