// ignore_for_file: invalid_use_of_protected_member
//
// etiket_tasarim_ekrani.dart parçası (god-class bölme, 2026-09-29) — kod
// birebir taşındı, davranış değişmedi. setState extension içinden
// çağrıldığı için protected uyarısı dosya bazında muaf (bkz.
// fatura_detay_islemler_ext.dart'taki açıklama).
// Liste ve Ayar sekmeleri, kamera paneli, arama sonuçları, sepet kartı ve mini önizleme.
part of 'etiket_tasarim_ekrani.dart';

extension _EtiketTasarimGorunumExt on _EtiketTasarimEkraniState {
  // ── Etiket Listesi Tab ────────────────────────────────────────────────────
  Widget _listesiTab() {
    return Column(children: [
      // Arama + barkod okuyucu satırı
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _araCtrl,
              focusNode: _araFocus,
              onChanged: _aramaDegisti,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _barkodIleEkle(v.trim());
              },
              decoration: InputDecoration(
                hintText: 'Ürün adı veya barkod ara…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _araCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _araCtrl.clear();
                          setState(() => _aramaSonuclari = []);
                        })
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          // Windows'ta kamera yok (USB okuyucu arama kutusuna yazar).
          if (!Platform.isWindows) const SizedBox(width: 8),
          // Barkod okuyucu butonu
          if (!Platform.isWindows)
          GestureDetector(
            onTap: _kameraToggle,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _kameraAcik
                    ? Theme.of(context).colorScheme.primary
                    : Color.fromARGB(26, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _kameraAcik ? Icons.qr_code_scanner : Icons.qr_code_scanner,
                color: _kameraAcik ? Colors.white : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ]),
      ),

      // Kamera önizleme
      if (_kameraAcik && _scanCtrl != null)
        _kameraPaneli(),

      // Arama sonuçları overlay
      if (_aramaSonuclari.isNotEmpty && !_kameraAcik)
        _aramaSonucListesi(),

      // Sepet başlığı
      if (_sepet.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(children: [
            Text('${_sepet.length} çeşit • $_toplamEtiket etiket',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: const Text('Temizle', style: TextStyle(fontSize: 12)),
              onPressed: () => setState(() => _sepet.clear()),
            ),
          ]),
        ),

      // Sepet listesi
      Expanded(
        child: _sepet.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.qr_code_2, size: 64, color: TsRenk.metinIkincil(context)),
                const SizedBox(height: 14),
                Text('Ürün arayın veya barkod okutun',
                    style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 14)),
                const SizedBox(height: 6),
                Text('Birden fazla ürün ve adet seçebilirsiniz',
                    style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 12)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                itemCount: _sepet.length,
                itemBuilder: (_, i) => _sepetKalemKarti(i),
              ),
      ),
    ]);
  }

  // ── Kamera paneli ─────────────────────────────────────────────────────────
  Widget _kameraPaneli() {
    return Container(
      height: 180,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          MobileScanner(
            controller: _scanCtrl!,
            onDetect: (capture) {
              final barkod = capture.barcodes.firstOrNull?.rawValue;
              if (barkod != null && barkod.isNotEmpty) {
                _barkodIleEkle(barkod);
              }
            },
          ),
          // Çerçeve
          Center(
            child: Container(
              width: 200, height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 8, left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Barkodu çerçeve içine getirin',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            )),
          ),
        ]),
      ),
    );
  }

  // ── Arama sonuç listesi ───────────────────────────────────────────────────
  Widget _aramaSonucListesi() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        decoration: BoxDecoration(
          color: TsRenk.kart(context),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        // Şeffaf Material: sonuca dokunma dalgası renkli kutunun altında kalmasın.
        child: Material(
          type: MaterialType.transparency,
          child: ListView.separated(
          shrinkWrap: true,
          itemCount: _aramaSonuclari.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final u = _aramaSonuclari[i];
            final barkodGecerli = u.barkod != null &&
                u.barkod!.isNotEmpty && u.barkod!.length >= 8;
            return ListTile(
              dense: true,
              leading: barkodGecerli
                  ? SizedBox(
                      width: 52, height: 36,
                      child: bw.BarcodeWidget(
                        barcode: u.barkod!.length == 13
                            ? bw.Barcode.ean13(drawEndChar: false)
                            : bw.Barcode.code128(),
                        data: u.barkod!,
                        style: const TextStyle(fontSize: 6),
                        errorBuilder: (_, __) =>
                            Icon(Icons.qr_code, size: 32, color: context.textSecondary),
                      ),
                    )
                  : Icon(Icons.qr_code, size: 36, color: context.textSecondary),
              title: Text(u.urunAdi,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(u.barkod ?? '-',
                  style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(ParaUtils.formatla(u.satisFiyati),
                    style: TsMetin.kucukVurgu.copyWith(color: Theme.of(context).colorScheme.primary)),
                const SizedBox(width: 8),
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(26, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.add, size: 18,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ]),
              onTap: () => _sepeteEkle(u),
            );
          },
        ),
        ),
      ),
    );
  }

  // ── Sepet kalem kartı ─────────────────────────────────────────────────────
  Widget _sepetKalemKarti(int i) {
    final k = _sepet[i];
    final u = k.urun;
    final barkodGecerli = u.barkod != null &&
        u.barkod!.isNotEmpty && u.barkod!.length >= 8;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TsRenk.ayirac(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          // Etiket önizleme (küçük)
          _miniEtiketOnizleme(u, barkodGecerli),
          const SizedBox(width: 12),
          // Ürün bilgileri
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.urunAdi,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(u.barkod ?? '-',
                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context),
                      fontFamily: 'monospace')),
              const SizedBox(height: 2),
              Text(ParaUtils.formatla(u.satisFiyati),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary)),
            ]),
          ),
          // Adet kontrol
          Column(children: [
            // Adet direkt düzenleme
            GestureDetector(
              onTap: () => _adetDialogu(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Color.fromARGB(20, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Color.fromARGB(76, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue)),
                ),
                child: Text('${k.adet} adet',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary)),
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _adetBtn(Icons.remove, () => _adetDegistir(i, k.adet - 1)),
              const SizedBox(width: 4),
              _adetBtn(Icons.add, () => _adetDegistir(i, k.adet + 1)),
              const SizedBox(width: 4),
              _adetBtn(Icons.delete_outline, () => _adetDegistir(i, 0),
                  renk: Colors.red),
            ]),
          ]),
        ]),
      ),
    );
  }

  Widget _miniEtiketOnizleme(UrunModel u, bool barkodGecerli) {
    final w = _efGenislik * 1.8;
    final h = _efYukseklik * 1.8;
    final f = _fontOlcek;
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        // Gerçek etiket her zaman beyaz sticker kağıdıdır — bu önizleme
        // bilinçli olarak temadan bağımsız, sabit beyaz tutuluyor (içindeki
        // koyu metinlerle tutarlı kalması için).
        color: Colors.white,
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(3),
        boxShadow: [BoxShadow(color: Color(0x0F000000),
            blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // NOT: Bu önizleme kutusunun arkaplanı bilinçli olarak sabit
          // beyaz (gerçek etiket kağıdı gibi) — bu yüzden İÇİNDEKİ TÜM
          // metinler de sabit koyu renkte olmalı. Önceden bazı metinler
          // hiç renk belirtmiyordu (karanlık modda tema varsayılanından
          // açık renk miras alıp beyaz zeminde kaybolurdu) ya da yanlışlıkla
          // tema-uyarlamalı renklere geçirilmişti (karanlık modda açık
          // griye dönüp yine kaybolurdu). Hepsi sabitlendi.
          if (_adGoster)
            Text(u.urunAdi,
                style: TextStyle(fontSize: w * 0.04 * f, fontWeight: FontWeight.bold, color: Colors.black),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          if (_anaGrupGoster && (u.anaGrup?.isNotEmpty ?? false))
            Text(u.anaGrup!,
                style: TextStyle(fontSize: w * 0.03 * f, color: Colors.black54),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          if (barkodGecerli && _barkodGoster)
            Flexible(child: bw.BarcodeWidget(
              barcode: u.barkod!.length == 13
                  ? bw.Barcode.ean13(drawEndChar: false)
                  : bw.Barcode.code128(),
              data: u.barkod!,
              style: TextStyle(fontSize: w * 0.025),
              errorBuilder: (_, __) => const SizedBox.shrink(),
            )),
          if (_lotNoGoster && (u.lotNo?.isNotEmpty ?? false))
            Text('Lot: ${u.lotNo}',
                style: TextStyle(fontSize: w * 0.025 * f, color: Colors.black54)),
          if (_sktGoster && (u.sonKullanmaTarihi?.isNotEmpty ?? false))
            Text('SKT: ${u.sonKullanmaTarihi}',
                style: TextStyle(fontSize: w * 0.025 * f, color: Colors.black54)),
          if (_aciklamaGoster && (u.lotAciklama?.isNotEmpty ?? false))
            Text(u.lotAciklama!,
                style: TextStyle(fontSize: w * 0.022 * f, color: Colors.black54),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          if (_fiyatGoster)
            // 🔴 DÜZELTME (kullanıcı bulgusu): "Birim Fiyatlı Mod" anahtarı
            // Ayarlar'da açılıp kapatılıyordu ama önizlemede HİÇBİR
            // görsel değişikliğe yol açmıyordu — termal yazdırma yolunda
            // (adet/kg + fiyat yan yana) çalışıyordu ama burada yok
            // sayılıyordu. Artık önizleme de aynı düzeni gösteriyor.
            Text('${ParaUtils.formatla(_onizlemeFiyat(u))} ₺',
                style: TextStyle(fontSize: w * 0.045 * f, fontWeight: FontWeight.w900,
                    color: Colors.red.shade700)),
          // Birim fiyat (1 KG / 1 LT) — termal ve ZPL çıktısıyla aynı hesap.
          if (_fiyatGoster && _birimFiyatliMod)
            Text(EtiketYardimci.birimFiyatMetni(u, _onizlemeFiyat(u)) ??
                    (u.birimAdi.isEmpty ? 'Adet' : u.birimAdi),
                style: TextStyle(fontSize: w * 0.028 * f, color: Colors.black87)),
          // 🔴 DÜZELTME (kullanıcı referans tasarımı — raf üstü fiyat
          // etiketi): firma/mağaza adı en altta basılmalı, ürün adının
          // ÜSTÜNDE değil — hem burada hem ZPL/termal çıktısında taşındı.
          if (_firmaBilgi)
            Text(_yazdirma.firmaAdiOnizleme,
                style: TextStyle(fontSize: w * 0.03 * f, color: Colors.black87),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          if (_ozelMetin.trim().isNotEmpty)
            Text(_ozelMetin.trim(),
                style: TextStyle(fontSize: w * 0.025 * f, fontStyle: FontStyle.italic),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _adetBtn(IconData icon, VoidCallback onTap, {Color? renk}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: Color.fromARGB(20, (renk ?? Theme.of(context).colorScheme.primary).red, (renk ?? Theme.of(context).colorScheme.primary).green, (renk ?? Theme.of(context).colorScheme.primary).blue),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16,
              color: renk ?? Theme.of(context).colorScheme.primary),
        ),
      );

  // Adet dialog - klavye ile hızlı giriş
  Future<void> _adetDialogu(int i) async {
    final ctrl = TextEditingController(text: '${_sepet[i].adet}');
    final yeni = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: Text(_sepet[i].urun.urunAdi,
            style: const TextStyle(fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(
            labelText: 'Kaç adet etiket?',
            border: OutlineInputBorder(), isDense: true),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ParaUtils.tamSayiCoz(ctrl.text)),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    if (yeni != null) _adetDegistir(i, yeni);
  }

  // ── Ayarlar Tab ───────────────────────────────────────────────────────────
  Widget _ayarTab() => ListView(padding: const EdgeInsets.all(16), children: [
    _baslik('Şablon'),
    DropdownButtonFormField<String>(
      value: _secilenSablon,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        helperText: 'Şablon, ürün türüne uygun alanları otomatik açar/kapatır',
        helperMaxLines: 2,
      ),
      items: _sablonlar.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: (v) { if (v != null) _sablonUygula(v); },
    ),
    const Divider(height: 24),
    _baslik('Etiket Boyutu'),
    ...EtiketBoyut.values.map((b) => RadioListTile<EtiketBoyut>(
      title: Text(b.etiket),
      subtitle: Text('${b.w.toInt()}×${b.h.toInt()} mm · '
          '${b.kagit == PaperSize.mm58 ? "58mm kağıt" : "80mm kağıt"}'),
      value: b, groupValue: _ozelBoyutAktif ? null : _boyut,
      onChanged: (v) { if (v != null) setState(() { _boyut = v; _ozelBoyutAktif = false; }); },
    )),
    SwitchListTile(
      title: const Text('Özel Boyut'),
      subtitle: const Text('Kendi mm ölçünüzü girin (ZPL/etiket önizlemesi için)'),
      value: _ozelBoyutAktif,
      onChanged: (v) => setState(() => _ozelBoyutAktif = v),
    ),
    if (_ozelBoyutAktif)
      Padding(
        padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ozelGenislikCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Genişlik (mm)', border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ozelYukseklikCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Yükseklik (mm)', border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
      ),
    const Divider(height: 24),
    _baslik('Yazı Boyutu'),
    SegmentedButton<double>(
      segments: const [
        ButtonSegment(value: 0.85, label: Text('Kompakt')),
        ButtonSegment(value: 1.0, label: Text('Normal')),
        ButtonSegment(value: 1.2, label: Text('Büyük')),
        ButtonSegment(value: 1.4, label: Text('Ekstra')),
      ],
      selected: {_fontOlcek},
      onSelectionChanged: (s) => setState(() => _fontOlcek = s.first),
    ),
    const Divider(height: 24),
    _baslik('İçerik'),
    SwitchListTile(
        title: const Text('Ürün Adı'), value: _adGoster,
        onChanged: (v) => setState(() => _adGoster = v)),
    SwitchListTile(
        title: const Text('Barkod'), value: _barkodGoster,
        onChanged: (v) => setState(() => _barkodGoster = v)),
    SwitchListTile(
        title: const Text('Fiyat'), value: _fiyatGoster,
        onChanged: (v) => setState(() => _fiyatGoster = v)),
    SwitchListTile(
        title: const Text('KDV Dahil Fiyat'),
        subtitle: const Text('Kapalıysa KDV hariç (net) fiyat basılır'),
        value: _kdvDahilGoster,
        onChanged: (v) => setState(() => _kdvDahilGoster = v)),
    SwitchListTile(
        title: const Text('Firma Adı'), value: _firmaBilgi,
        onChanged: (v) => setState(() => _firmaBilgi = v)),
    SwitchListTile(
        title: const Text('Ana Grup / Kategori'), value: _anaGrupGoster,
        onChanged: (v) => setState(() => _anaGrupGoster = v)),
    SwitchListTile(
        title: const Text('Lot No'),
        subtitle: const Text('Ürünün Lot/Seri numarası varsa gösterilir'),
        value: _lotNoGoster,
        onChanged: (v) => setState(() => _lotNoGoster = v)),
    SwitchListTile(
        title: const Text('Son Kullanma Tarihi (SKT)'), value: _sktGoster,
        onChanged: (v) => setState(() => _sktGoster = v)),
    SwitchListTile(
        title: const Text('Açıklama'),
        subtitle: const Text('Üründeki lot açıklaması varsa gösterilir'),
        value: _aciklamaGoster,
        onChanged: (v) => setState(() => _aciklamaGoster = v)),
    SwitchListTile(
        title: const Text('Birim Fiyatlı Mod'),
        subtitle: const Text('Adet/KG + fiyat yan yana'),
        value: _birimFiyatliMod,
        onChanged: (v) => setState(() => _birimFiyatliMod = v)),
    const SizedBox(height: 8),
    TextField(
      controller: _ozelMetinCtrl,
      maxLength: 40,
      decoration: InputDecoration(
        labelText: 'Özel Metin (opsiyonel)',
        hintText: 'Örn: "Kampanya Ürünü", "Yeni"',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      onChanged: (v) => setState(() => _ozelMetin = v),
    ),
    const SizedBox(height: 16),
    Row(children: [
      Expanded(child: _baslik('Kayıtlı Şablonlarım')),
      TextButton.icon(
        icon: const Icon(Icons.save_outlined, size: 16),
        label: const Text('Şu Anki Ayarları Kaydet', style: TextStyle(fontSize: 12)),
        onPressed: _ozelSablonKaydet,
      ),
    ]),
    if (_ozelSablonlar.isEmpty)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('Henüz kayıtlı özel şablon yok. İçerik/boyut/yazı ayarlarını '
            'dilediğiniz gibi düzenleyip "Şu Anki Ayarları Kaydet" ile adlandırıp saklayabilirsiniz.',
            style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 12)),
      )
    else
      ..._ozelSablonlar.map((s) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: TsRenk.ayirac(context))),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.bookmark_outline, size: 20),
          title: Text('${s['ad']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 20),
              tooltip: 'Uygula',
              onPressed: () => _ayarlariUygula(s),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              tooltip: 'Sil',
              onPressed: () => _ozelSablonSil('${s['ad']}'),
            ),
          ]),
        ),
      )),
    const SizedBox(height: 8),
    _baslik('Sepet Özeti'),
    if (_sepet.isEmpty)
      Text('Henüz ürün eklenmedi.',
          style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 13))
    else
      ..._sepet.map((k) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k.urun.urunAdi,
              style: const TextStyle(fontSize: 13), maxLines: 1,
              overflow: TextOverflow.ellipsis)),
          Text('${k.adet} adet',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      )),
    if (_sepet.isNotEmpty) ...[
      const Divider(height: 20),
      Text('Toplam: $_toplamEtiket etiket',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  ]);

  Widget _baslik(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary)),
  );
}
