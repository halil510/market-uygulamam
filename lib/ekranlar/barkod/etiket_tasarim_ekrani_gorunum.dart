// ignore_for_file: invalid_use_of_protected_member
//
// etiket_tasarim_ekrani.dart parçası — Etiket Listesi ve Tasarım ve Yazıcı sekmeleri. setState extension
// içinden çağrıldığı için protected uyarısı dosya bazında muaf.
part of 'etiket_tasarim_ekrani.dart';

extension _EtiketTasarimGorunumExt on _EtiketTasarimEkraniState {
  // ── Etiket Listesi ────────────────────────────────────────────────────────
  Widget _listesiTab() {
    return Column(children: [
      _secimSeridi(),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
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
          if (!Platform.isWindows) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _kameraToggle,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kameraAcik ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.qr_code_scanner, color: _kameraAcik ? Colors.white : Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ]),
      ),
      if (_kameraAcik && _scanCtrl != null) _kameraPaneli(),
      if (_aramaSonuclari.isNotEmpty && !_kameraAcik) _aramaSonucListesi(),
      if (_sepet.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(children: [
            Text('${_sepet.length} çeşit • $_toplamEtiket etiket', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: const Text('Temizle', style: TextStyle(fontSize: 12)),
              onPressed: () => setState(() => _sepet.clear()),
            ),
          ]),
        ),
      Expanded(
        child: _sepet.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.qr_code_2, size: 64, color: TsRenk.metinIkincil(context)),
                  const SizedBox(height: 14),
                  Text('Ürün arayın veya barkod okutun', style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 14)),
                  const SizedBox(height: 6),
                  Text('Birden fazla ürün ve adet seçebilirsiniz', style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 12)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                itemCount: _sepet.length,
                itemBuilder: (_, i) => _sepetKalemKarti(i),
              ),
      ),
    ]);
  }

  /// Seçili tasarım ve yazıcı — dokununca "Tasarım ve Yazıcı" sekmesine geçer.
  Widget _secimSeridi() {
    final cs = Theme.of(context).colorScheme;
    final bagli = _yazdirma.bagliMi ? _yazdirma.baglantiDurumu : null;
    return Material(
      color: cs.primaryContainer.withValues(alpha: 0.35),
      child: InkWell(
        onTap: () => _tab.animateTo(1),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(children: [
            const Icon(Icons.label_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_secili.ad} · ${_secili.olcu}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(_ayar?.ozet(bagliYazici: bagli) ?? '…',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const Text('Değiştir', style: TextStyle(fontSize: 12)),
            const Icon(Icons.chevron_right, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _kameraPaneli() {
    return Container(
      height: 180,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.black),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          MobileScanner(
            controller: _scanCtrl,
            onDetect: (capture) {
              final barkod = capture.barcodes.firstOrNull?.rawValue;
              if (barkod != null && barkod.isNotEmpty) _barkodIleEkle(barkod);
            },
          ),
          Center(
            child: Container(
              width: 200,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: const Text('Barkodu çerçeve içine getirin', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

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
        child: Material(
          type: MaterialType.transparency,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _aramaSonuclari.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final u = _aramaSonuclari[i];
              return ListTile(
                dense: true,
                title: Text(u.urunAdi, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(u.barkod ?? '-', style: const TextStyle(fontSize: 11)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(ParaUtils.formatla(u.satisFiyati),
                      style: TsMetin.kucukVurgu.copyWith(color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add, size: 18, color: Theme.of(context).colorScheme.primary),
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

  Widget _sepetKalemKarti(int i) {
    final k = _sepet[i];
    final u = k.urun;
    final veri = etiketVerisi(u);
    final d = etiketDenetle(_secili, [veri]);
    final not = d.atlanan.isNotEmpty
        ? (d.atlanan.first.split(' — ').last, TsRenk.hata)
        : d.birimFiyatsiz.isNotEmpty
            ? ('birim fiyat boş kalacak', TsRenk.uyari)
            : null;
    final ekran = MediaQuery.sizeOf(context).width;
    final onizlemeG = ekran >= 700 ? 150.0 : 104.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: not?.$2 == TsRenk.hata ? TsRenk.hata.withAlpha(120) : TsRenk.ayirac(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          // Gerçek çıktıyla aynı küçük resim (seçili tasarım)
          Opacity(
            opacity: d.atlanan.isNotEmpty ? 0.35 : 1,
            child: EtiketOnizleme(sablon: _secili, veri: veri, mensei: _ayar?.mensei ?? 'Türkiye', firma: _firma, genislik: onizlemeG),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.urunAdi, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(u.barkod ?? '-', style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context), fontFamily: 'monospace')),
              const SizedBox(height: 2),
              Text(ParaUtils.formatla(u.satisFiyati),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
              if (not != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    d.atlanan.isNotEmpty ? 'Basılmaz: ${not.$1}' : not.$1,
                    style: TextStyle(fontSize: 11, color: not.$2, fontWeight: FontWeight.w600),
                  ),
                ),
            ]),
          ),
          Column(children: [
            GestureDetector(
              onTap: () => _adetDialogu(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(76)),
                ),
                child: Text('${k.adet} adet',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _adetBtn(Icons.remove, () => _adetDegistir(i, k.adet - 1)),
              const SizedBox(width: 4),
              _adetBtn(Icons.add, () => _adetDegistir(i, k.adet + 1)),
              const SizedBox(width: 4),
              _adetBtn(Icons.delete_outline, () => _adetDegistir(i, 0), renk: TsRenk.hata),
            ]),
          ]),
        ]),
      ),
    );
  }

  Widget _adetBtn(IconData icon, VoidCallback onTap, {Color? renk}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: (renk ?? Theme.of(context).colorScheme.primary).withAlpha(20),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: renk ?? Theme.of(context).colorScheme.primary),
        ),
      );

  Future<void> _adetDialogu(int i) async {
    final yeni = await etiketAdediSor(context, _sepet[i].urun.urunAdi, baslangic: _sepet[i].adet);
    if (yeni != null && mounted && i < _sepet.length) _adetDegistir(i, yeni);
  }

  // ── Tasarım ve Yazıcı ─────────────────────────────────────────────────────
  Widget _ayarTab() {
    final kendi = _tasarimlar.where((s) => s.kendi).toList();
    final hazir = _tasarimlar.where((s) => !s.kendi).toList();
    final genis = MediaQuery.sizeOf(context).width >= 1000;

    final tasarimBolumu = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _baslik('Etiket tasarımı')),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Yeni tasarım'),
          onPressed: _yeniTasarim,
        ),
      ]),
      Text('Seçili tasarım etiket listesinde ve ürün ekranlarındaki yazdır düğmesinde kullanılır.',
          style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
      const SizedBox(height: 10),
      _altBaslik('Kendi tasarımlarım'),
      if (kendi.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Henüz yok. "Yeni tasarım" ile başlayın ya da aşağıdaki hazır şablonlardan birinin kopyasını düzenleyin.',
              style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
        ),
      for (final s in kendi) _tasarimKarti(s),
      const SizedBox(height: 8),
      _altBaslik('Hazır şablonlar (BarTender)'),
      for (final s in hazir) _tasarimKarti(s),
    ]);

    final yaziciBolumu = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _baslik('Etiket yazıcısı'),
      const Card(
        margin: EdgeInsets.zero,
        child: Padding(padding: EdgeInsets.fromLTRB(14, 14, 14, 4), child: EtiketYaziciPaneli()),
      ),
    ]);

    if (genis) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [tasarimBolumu])),
        SizedBox(width: 460, child: ListView(padding: const EdgeInsets.all(16), children: [yaziciBolumu])),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      tasarimBolumu,
      const SizedBox(height: 20),
      yaziciBolumu,
      const SizedBox(height: 40),
    ]);
  }

  Widget _tasarimKarti(EtiketSablonu s) {
    final secili = s.id == _secili.id;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: secili ? cs.primary : TsRenk.ayirac(context), width: secili ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _tasarimSec(s),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Icon(secili ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: secili ? cs.primary : null, size: 20),
            const SizedBox(width: 10),
            EtiketOnizleme(sablon: s, veri: _ornekVeri, mensei: _ayar?.mensei ?? 'Türkiye', firma: _firma, genislik: 120),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.ad, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${s.olcu}${s.indirimli ? ' · indirimli' : ''}', style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                if (secili)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Seçili', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary)),
                  ),
              ]),
            ),
            if (s.kendi)
              IconButton(tooltip: 'Düzenle', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _tasarimDuzenle(s)),
            PopupMenuButton<String>(
              tooltip: 'Diğer',
              onSelected: (v) {
                switch (v) {
                  case 'duzenle':
                    _tasarimDuzenle(s);
                  case 'kopya':
                    _tasarimKopyala(s);
                  case 'sil':
                    _tasarimSil(s);
                }
              },
              itemBuilder: (_) => [
                if (s.kendi) const PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
                PopupMenuItem(value: 'kopya', child: Text(s.kendi ? 'Kopyala' : 'Kopyasını düzenle')),
                if (s.kendi) const PopupMenuItem(value: 'sil', child: Text('Sil')),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _baslik(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
      );

  Widget _altBaslik(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TsRenk.metinIkincil(context))),
      );
}
