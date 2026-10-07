// ignore_for_file: invalid_use_of_protected_member
//
// etiket_tasarim_ekrani.dart parçası (god-class bölme, 2026-09-29) — kod
// birebir taşındı, davranış değişmedi. setState extension içinden
// çağrıldığı için protected uyarısı dosya bazında muaf (bkz.
// fatura_detay_islemler_ext.dart'taki açıklama).
// Özel şablonlar, ayar uygulama, yazdırma, ZPL dışa aktarma ve Bluetooth durumu.
part of 'etiket_tasarim_ekrani.dart';

extension _EtiketTasarimIslemlerExt on _EtiketTasarimEkraniState {
  // ── Adlandırılmış özel şablonlar ─────────────────────────────────────────
  Future<void> _ozelSablonlariYukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('etiket_ozel_sablonlar');
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _ozelSablonlar = list);
    } catch (_) {/* bozuk kayıt varsa yok say */}
  }

  Map<String, dynamic> _mevcutAyarlar() => {
    'barkod': _barkodGoster, 'fiyat': _fiyatGoster, 'ad': _adGoster,
    'firma': _firmaBilgi, 'birimFiyatli': _birimFiyatliMod, 'lotNo': _lotNoGoster,
    'skt': _sktGoster, 'anaGrup': _anaGrupGoster, 'kdvDahil': _kdvDahilGoster,
    'aciklama': _aciklamaGoster, 'ozelMetin': _ozelMetin, 'fontOlcek': _fontOlcek,
    'boyutIndex': _boyut.index, 'ozelBoyutAktif': _ozelBoyutAktif,
    'ozelGenislik': _ozelGenislikCtrl.text, 'ozelYukseklik': _ozelYukseklikCtrl.text,
  };

  void _ayarlariUygula(Map<String, dynamic> a) {
    setState(() {
      _barkodGoster    = a['barkod'] ?? true;
      _fiyatGoster     = a['fiyat'] ?? true;
      _adGoster        = a['ad'] ?? true;
      _firmaBilgi      = a['firma'] ?? false;
      _birimFiyatliMod = a['birimFiyatli'] ?? false;
      _lotNoGoster     = a['lotNo'] ?? false;
      _sktGoster       = a['skt'] ?? false;
      _anaGrupGoster   = a['anaGrup'] ?? false;
      _kdvDahilGoster  = a['kdvDahil'] ?? true;
      _aciklamaGoster  = a['aciklama'] ?? false;
      _ozelMetin       = a['ozelMetin'] ?? '';
      _ozelMetinCtrl.text = _ozelMetin;
      _fontOlcek       = (a['fontOlcek'] as num?)?.toDouble() ?? 1.0;
      final bi = a['boyutIndex'] as int?;
      if (bi != null && bi >= 0 && bi < EtiketBoyut.values.length) _boyut = EtiketBoyut.values[bi];
      _ozelBoyutAktif  = a['ozelBoyutAktif'] ?? false;
      _ozelGenislikCtrl.text  = (a['ozelGenislik'] as String?) ?? _ozelGenislikCtrl.text;
      _ozelYukseklikCtrl.text = (a['ozelYukseklik'] as String?) ?? _ozelYukseklikCtrl.text;
    });
  }

  Future<void> _ozelSablonKaydet() async {
    final adCtrl = TextEditingController();
    final ad = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Şablonu Kaydet'),
        content: TextField(
          controller: adCtrl, autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Şablon adı', hintText: 'Örn: "Şarküteri Etiketi"',
              border: OutlineInputBorder(), isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, adCtrl.text.trim()),
              child: const Text('Kaydet')),
        ],
      ),
    ).whenComplete(() => dialogSonrasiBirak([adCtrl]));
    if (ad == null || ad.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _ozelSablonlar.removeWhere((s) => s['ad'] == ad);
    _ozelSablonlar.add({'ad': ad, ..._mevcutAyarlar()});
    await prefs.setString('etiket_ozel_sablonlar', jsonEncode(_ozelSablonlar));
    if (!mounted) return;
    setState(() {});
    BildirimServisi.basari(context, 'Şablon kaydedildi: $ad');
  }

  Future<void> _ozelSablonSil(String ad) async {
    final prefs = await SharedPreferences.getInstance();
    _ozelSablonlar.removeWhere((s) => s['ad'] == ad);
    await prefs.setString('etiket_ozel_sablonlar', jsonEncode(_ozelSablonlar));
    if (mounted) setState(() {});
  }

  Future<void> _btDurumKontrol() async {
    try {  
      final b = await _yazdirma.btBagliMi;
      if (mounted) setState(() => _btBagliMi = b);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  /// Şablon seçimi, o ürün türü için genelde anlamlı olan alanları otomatik
  /// açar/kapatır. Kullanıcı seçtikten sonra dilediği anahtarı yine elle
  /// değiştirebilir — şablon sadece bir başlangıç noktası sunar.
  void _sablonUygula(String sablon) {
    setState(() {
      _secilenSablon = sablon;
      switch (sablon) {
        case 'Gıda':
          _sktGoster = true;
          _lotNoGoster = true;
          _anaGrupGoster = false;
          _aciklamaGoster = false;
        case 'Tekstil':
          _sktGoster = false;
          _lotNoGoster = false;
          _anaGrupGoster = true;
          _aciklamaGoster = true;
        case 'Elektronik':
          _sktGoster = false;
          _lotNoGoster = true; // seri no amaçlı
          _anaGrupGoster = true;
          _aciklamaGoster = false;
        case 'Kargo':
          _sktGoster = false;
          _lotNoGoster = false;
          _anaGrupGoster = false;
          _aciklamaGoster = true;
        default: // Varsayılan
          _sktGoster = false;
          _lotNoGoster = false;
          _anaGrupGoster = false;
          _aciklamaGoster = false;
      }
    });
  }

  // ── Yazdır ────────────────────────────────────────────────────────────────
  Future<void> _yazdir() async {
    if (_sepet.isEmpty) { BildirimServisi.uyari(context, 'Ürün ekleyin'); return; }
    if (!_btBagliMi) {
      _showBtUyari();
      return;
    }

    showDialog(
      context: context, barrierDismissible: false,
      builder: (bCtx) => const ProgressDialog(mesaj: 'Etiketler yazdırılıyor...'),
    );

    try {
      int toplam = 0;
      for (final kalem in _sepet) {
        await _yazdirma.etiketYazdir(
          kalem.urun,
          barkodGoster:    _barkodGoster,
          fiyatGoster:     _fiyatGoster,
          adGoster:        _adGoster,
          birimFiyatliMod: _birimFiyatliMod,
          etiketBoy:       _efKagit,
          etiketGenislikMm: _efGenislik,
          adet:            kalem.adet,
          firmaGoster:     _firmaBilgi,
          lotNoGoster:     _lotNoGoster,
          sktGoster:       _sktGoster,
          anaGrupGoster:   _anaGrupGoster,
          kdvDahilFiyat:   _kdvDahilGoster,
          aciklamaGoster:  _aciklamaGoster,
          ozelMetin:       _ozelMetin,
        );
        toplam += kalem.adet;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      BildirimServisi.basari(context,
          '$toplam etiket gönderildi (${_sepet.length} çeşit)');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      BildirimServisi.hata(context, 'Yazıcı hatası: $e');
    }
  }

  /// Sepetteki etiketleri ZPL'e çevirip seçenek sunar:
  /// - Bağlı bir yazıcı (WiFi/BT) varsa: doğrudan gönder (BarTender'a gerek yok)
  /// - Yoksa veya kullanıcı isterse: .zpl dosyası olarak dışa aktar (BarTender vb.)
  Future<void> _zplDisaAktar() async {
    if (_sepet.isEmpty) { BildirimServisi.uyari(context, 'Ürün ekleyin'); return; }
    final zpl = ZplServisi.topluZpl(
      _sepet.map((k) => (urun: k.urun, adet: k.adet)).toList(),
      genislikMm: _efGenislik,
      yukseklikMm: _efYukseklik,
      barkodGoster: _barkodGoster,
      fiyatGoster: _fiyatGoster,
      adGoster: _adGoster,
      firmaGoster: _firmaBilgi,
      firmaAdi: _yazdirma.firmaAdiOnizleme,
      anaGrupGoster: _anaGrupGoster,
      lotNoGoster: _lotNoGoster,
      sktGoster: _sktGoster,
      aciklamaGoster: _aciklamaGoster,
      kdvDahilFiyat: _kdvDahilGoster,
      birimFiyatliMod: _birimFiyatliMod,
      ozelMetin: _ozelMetin,
      fontOlcek: _fontOlcek,
    );

    if (_yazdirma.bagliMi) {
      final secim = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16),
              child: Text('Etiketler nasıl gönderilsin?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          // ZPL önizleme — gönderilmeden önce küçük bir özet ve kod örneği
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TsRenk.arkaplan(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TsRenk.ayirac(context)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.label_outline, size: 16, color: TsRenk.metinIkincil(context)),
                  const SizedBox(width: 6),
                  Text('$_boyutEtiketMetni • ${_sepet.length} çeşit • '
                      '${_sepet.fold<int>(0, (t, k) => t + k.adet)} adet',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TsRenk.metinBirincil(context))),
                ]),
                const SizedBox(height: 6),
                Text(
                  zpl.length > 160 ? '${zpl.substring(0, 160)}...' : zpl,
                  maxLines: 4, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: TsRenk.metinIkincil(context)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.print, color: Colors.blue),
            title: const Text('Bağlı Yazıcıya Doğrudan Gönder (ZPL)'),
            subtitle: Text('Zebra/ZPL uyumlu — ${_yazdirma.baglantiDurumu}'),
            onTap: () => Navigator.pop(ctx, 'direkt'),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share, color: Colors.orange),
            title: const Text('.zpl Dosyası Olarak Paylaş'),
            subtitle: const Text('BarTender veya başka bir uygulamaya aktarın'),
            onTap: () => Navigator.pop(ctx, 'dosya'),
          ),
          const SizedBox(height: 8),
        ])),
      );
      if (secim == null) return;
      if (secim == 'direkt') {
        try {
          await _yazdirma.zplGonder(zpl);
          if (mounted) BildirimServisi.basari(context, 'Etiketler yazıcıya gönderildi (ZPL)');
        } catch (e) {
          if (mounted) BildirimServisi.hata(context, 'ZPL gönderim hatası: $e');
        }
        return;
      }
    }

    await _zplDosyaPaylas(zpl);
  }

  Future<void> _zplDosyaPaylas(String zpl) async {
    try {
      final dir = await getTemporaryDirectory();
      final dosya = File('${dir.path}/etiketler_${DateTime.now().millisecondsSinceEpoch}.zpl');
      await dosya.writeAsString(zpl);

      if (!mounted) return;
      await DosyaPaylasim.paylas(ShareParams(files: [XFile(dosya.path, mimeType: 'text/plain')],
        subject: 'BarkoPro Etiketler (ZPL)',
        text: 'Bu .zpl dosyasını BarTender veya Zebra/ZPL uyumlu '
              'bir etiket yazıcısına "Dosyadan Yazdır" ile gönderebilirsiniz.\n'
              'Etiket boyutu: $_boyutEtiketMetni, Toplam: '
              '${_sepet.fold<int>(0, (t, k) => t + k.adet)} adet.',
      ));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'ZPL dışa aktarma hatası: $e');
    }
  }

  void _showBtUyari() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Row(children: [
          Icon(Icons.print_disabled, color: Colors.red), SizedBox(width: 8),
          Text('Yazıcı Bağlı Değil'),
        ]),
        content: const Text('Etiket yazdırmak için önce Yazıcı Ayarları ekranından '
            'Bluetooth yazıcıya bağlanın.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }
}
