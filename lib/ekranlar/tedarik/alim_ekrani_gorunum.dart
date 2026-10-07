// lib/ekranlar/tedarik/alim_ekrani_gorunum.dart
//
// Mal Alımı ekranının görsel parçaları (kamera, arama, sonuçlar, kalem kartı,
// alt toplam/ödeme paneli) — alim_ekrani.dart'taki tek parça build()
// metodundan ayrıldı (2026-10-07 refactor). İş mantığı ekranda.
// ignore_for_file: invalid_use_of_protected_member
part of 'alim_ekrani.dart';

extension _AlimGorunum on _AlimEkraniState {
  Widget _kameraPaneli() => SizedBox(
    height: 160,
    child: Stack(
      children: [
        MobileScanner(
          controller: _scanCtrl,
          onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull;
            if (barcode?.rawValue != null) {
              _barkodOkutInline(barcode!.rawValue!);
            }
          },
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _kameraToggle,
          ),
        ),
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Barkodu kameraya gösterin',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _aramaKutusu() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _araCtrl,
            decoration: InputDecoration(
              hintText: 'Ürün ara veya barkod yaz...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _araCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _araCtrl.clear();
                        _aramaSonuclari = [];
                        if (mounted) setState(() {});
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) _barkodIsleme(v.trim());
            },
          ),
        ),
        if (!Platform.isWindows) const SizedBox(width: 8),
        // Kamera toggle butonu (Windows'ta yok)
        if (!Platform.isWindows)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _kameraAcik
                  ? Theme.of(context).colorScheme.primary
                  : TsRenk.arkaplan(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _kameraAcik
                    ? Theme.of(context).colorScheme.primary
                    : TsRenk.ayirac(context),
              ),
            ),
            child: IconButton(
              icon: Icon(
                _kameraAcik ? Icons.qr_code_scanner : Icons.qr_code_2,
                color: _kameraAcik
                    ? Colors.white
                    : TsRenk.metinIkincil(context),
                size: 24,
              ),
              tooltip: _kameraAcik ? 'Kamerayı Kapat' : 'Barkod Okut',
              onPressed: _kameraToggle,
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    ),
  );

  Widget _aramaSonuclariListesi() => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 220),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      // Şeffaf Material: sonuca dokunma dalgası renkli kutunun altında kalmasın.
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
              title: Text(u.urunAdi, style: const TextStyle(fontSize: 13)),
              subtitle: Text(u.barkod ?? u.kod ?? ''),
              trailing: Text(
                'Alış: ${ParaUtils.formatla(u.alisFiyat)}',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => _urunEkle(u),
            );
          },
        ),
      ),
    ),
  );

  Widget _kalemKarti(_AlimKalem k, int i) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6, top: 2),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TsRenk.ayirac(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    k.urun.urunAdi,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 18),
                  onPressed: () => setState(() => _kalemler.removeAt(i)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: k.miktarCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Miktar (${k.urun.birimAdi})',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final m = ParaUtils.sayiCoz(v) ?? 0;
                      if (m > 0) {
                        setState(() => k.miktar = m);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: k.fiyatCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Alış Fiyatı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final f = ParaUtils.sayiCoz(v) ?? 0;
                      if (f > 0) {
                        setState(() => k.alisFiyat = f);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ParaUtils.formatla(k.kdvDahilTutar),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'KDV %${k.kdvOran.toStringAsFixed(k.kdvOran % 1 == 0 ? 0 : 1)} dahil',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (k.urun.lotTakibi) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: k.lotNoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Lot No (opsiyonel)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: k.sktCtrl,
                      decoration: const InputDecoration(
                        labelText: 'SKT (YYYY-AA-GG)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _altPanel() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      boxShadow: const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 8,
          offset: Offset(0, -2),
        ),
      ],
    ),
    child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ara Toplam (KDV hariç)',
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
              Text(
                ParaUtils.formatla(_araToplam),
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'KDV',
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
              Text(
                ParaUtils.formatla(_kdvToplam),
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Genel Toplam (KDV dahil)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                ParaUtils.formatla(_genelToplam),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // Tedarikçi seç
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _tedarikciSec,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _tedarikci != null
                      ? Colors.teal
                      : TsRenk.ayirac(context),
                ),
                borderRadius: BorderRadius.circular(12),
                color: _tedarikci != null ? TsRenk.zemin(Colors.teal) : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.business,
                    size: 18,
                    color: _tedarikci != null
                        ? Colors.teal
                        : context.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      // Tedarikçi artık zorunlu (bkz. _kaydet) — etiket "(opsiyonel)" diyordu.
                      _tedarikci != null
                          ? _tedarikci!.unvan
                          : 'Tedarikçi Seç *',
                      style: TextStyle(
                        fontSize: 13,
                        color: _tedarikci != null
                            ? Colors.teal.shade700
                            : TsRenk.metinIkincil(context),
                        fontWeight: _tedarikci != null
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (_tedarikci != null)
                    GestureDetector(
                      onTap: () => setState(() => _tedarikci = null),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: context.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _odemeYontemi,
            decoration: const InputDecoration(
              labelText: 'Ödeme',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Nakit', child: Text('Nakit')),
              DropdownMenuItem(value: 'Cari', child: Text('Cariye Yaz')),
              DropdownMenuItem(value: 'Havale', child: Text('Havale')),
            ],
            onChanged: (v) => setState(() => _odemeYontemi = v!),
          ),
          if (_odemeYontemi == 'Havale') ...[
            const SizedBox(height: 8),
            if (_bankaHesaplari.isNotEmpty)
              DropdownButtonFormField<BankaHesapModel>(
                initialValue: _secilenHesap,
                decoration: const InputDecoration(
                  labelText: 'Hangi Hesaptan?',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _bankaHesaplari
                    .map(
                      (h) => DropdownMenuItem(
                        value: h,
                        child: Text(
                          h.hesapAdi,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _secilenHesap = v),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TsRenk.zemin(TsRenk.uyari),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Banka hesabı bulunamadı. Önce bir hesap ekleyin veya "Nakit" seçin.',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                ),
              ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isleniyor ? null : _alimKaydet,
              icon: _isleniyor
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: const Text('Alımı Kaydet'),
            ),
          ),
        ],
      ),
    ),
  );
}
