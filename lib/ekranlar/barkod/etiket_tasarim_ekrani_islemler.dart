// ignore_for_file: invalid_use_of_protected_member
//
// etiket_tasarim_ekrani.dart parçası — yazdırma, önizleme, ZPL ve tasarım işlemleri (seç / yeni / kopyala /
// düzenle / sil). setState extension içinden çağrıldığı için protected uyarısı dosya bazında muaf.
part of 'etiket_tasarim_ekrani.dart';

extension _EtiketTasarimIslemlerExt on _EtiketTasarimEkraniState {
  // ── Yazdır ────────────────────────────────────────────────────────────────
  Future<void> _yazdir() async {
    if (_sepet.isEmpty) {
      BildirimServisi.uyari(context, 'Ürün ekleyin');
      return;
    }
    // Seçili tasarım + seçili yazıcı (ürün ekranlarındaki yazdır düğmesiyle aynı yol).
    await etiketleriBas(context, _kalemler, sablon: _secili);
  }

  Future<void> _onizle() async {
    if (_sepet.isEmpty) return;
    await rafEtiketPenceresiAc(context, _kalemler);
  }

  /// Seçili tasarımın ZPL (Zebra) karşılığı: bağlı yazıcıya doğrudan ya da .zpl dosyası olarak.
  Future<void> _zplDisaAktar() async {
    if (_sepet.isEmpty) {
      BildirimServisi.uyari(context, 'Ürün ekleyin');
      return;
    }
    final String zpl;
    try {
      zpl = await EtiketBaskiServisi.zpl(_kalemler, _secili, _ayar ?? await EtiketAyarlari.yaziciYukle());
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'ZPL hazırlanamadı: $e');
      return;
    }
    if (!mounted) return;
    if (zpl.isEmpty) {
      BildirimServisi.uyari(context, 'Basılacak etiket yok (fiyatı olmayan ürünler basılmaz)');
      return;
    }
    if (_yazdirma.bagliMi) {
      final secim = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${_secili.ad} · ${_secili.olcu} — ZPL nasıl gönderilsin?',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            ListTile(
              leading: const Icon(Icons.print, color: TsRenk.bilgi),
              title: const Text('Bağlı yazıcıya doğrudan gönder (ZPL)'),
              subtitle: Text('Zebra/ZPL uyumlu — ${_yazdirma.baglantiDurumu}'),
              onTap: () => Navigator.pop(ctx, 'direkt'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share, color: TsRenk.uyari),
              title: const Text('.zpl dosyası olarak paylaş'),
              subtitle: const Text('BarTender veya başka bir uygulamaya aktarın'),
              onTap: () => Navigator.pop(ctx, 'dosya'),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (secim == null || !mounted) return;
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
      await DosyaPaylasim.paylas(ShareParams(
        files: [XFile(dosya.path, mimeType: 'text/plain')],
        subject: 'Etiketler (ZPL)',
        text: 'Bu .zpl dosyasını Zebra/ZPL uyumlu bir etiket yazıcısına "Dosyadan Yazdır" ile gönderebilirsiniz.\n'
            'Tasarım: ${_secili.ad} (${_secili.olcu}), toplam $_toplamEtiket adet.',
      ));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'ZPL dışa aktarma hatası: $e');
    }
  }

  // ── Tasarımlar ────────────────────────────────────────────────────────────
  Future<void> _tasarimSec(EtiketSablonu s) async {
    setState(() => _secili = s);
    await EtiketAyarlari.tasarimSec(s.id);
  }

  Future<void> _tasarimDuzenle(EtiketSablonu s) async {
    final kaydedilen = await etiketTasarimciAc(context, s, ornek: _sepet.isEmpty ? null : _ornekVeri);
    if (kaydedilen != null && mounted) {
      await EtiketAyarlari.tasarimSec(kaydedilen.id); // yeni / düzenlenen tasarım seçili olsun
      if (mounted) BildirimServisi.basari(context, 'Tasarım kaydedildi ve seçildi: ${kaydedilen.ad}');
    }
  }

  Future<void> _tasarimKopyala(EtiketSablonu s) => _tasarimDuzenle(
        s.kopya(id: EtiketAyarlari.yeniKimlik(), ad: '${s.ad} (kopya)', dosya: ''),
      );

  Future<void> _tasarimSil(EtiketSablonu s) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tasarım silinsin mi?'),
        content: Text('"${s.ad}" silinecek. Bu geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    await EtiketAyarlari.tasarimSil(s.id);
    if (mounted) BildirimServisi.bilgi(context, 'Tasarım silindi: ${s.ad}');
  }

  /// Yeni tasarım: ad, ölçü ve başlangıç (seçilen alanlardan otomatik ya da boş) sorulur, tasarımcı açılır.
  Future<void> _yeniTasarim() async {
    final s = await showDialog<EtiketSablonu>(context: context, builder: (_) => const _YeniTasarimDialogu());
    if (s == null || !mounted) return;
    await _tasarimDuzenle(s);
  }
}

/// "Yeni tasarım" penceresi.
class _YeniTasarimDialogu extends StatefulWidget {
  const _YeniTasarimDialogu();
  @override
  State<_YeniTasarimDialogu> createState() => _YeniTasarimDialoguState();
}

class _YeniTasarimDialoguState extends State<_YeniTasarimDialogu> {
  final _adCtrl = TextEditingController(text: 'Etiketim');
  final _gCtrl = TextEditingController(text: '58');
  final _hCtrl = TextEditingController(text: '40');
  bool _otomatik = true;
  final Set<OtomatikAlan> _alanlar = {OtomatikAlan.ad, OtomatikAlan.fiyat, OtomatikAlan.barkod};

  @override
  void dispose() {
    _adCtrl.dispose();
    _gCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  double? _olcu(TextEditingController c) {
    final v = ParaUtils.sayiCoz(c.text);
    return v == null || v < enKucukOlcu || v > enBuyukOlcu ? null : v;
  }

  void _tamam() {
    final g = _olcu(_gCtrl), h = _olcu(_hCtrl);
    final ad = _adCtrl.text.trim();
    if (g == null || h == null || ad.isEmpty) {
      setState(() {}); // hata metinleri görünsün
      return;
    }
    final id = EtiketAyarlari.yeniKimlik();
    final s = _otomatik
        ? otomatikTasarim(id: id, ad: ad, genislik: g, yukseklik: h, alanlar: _alanlar)
        : EtiketSablonu(id: id, ad: ad, dosya: '', genislik: g, yukseklik: h, ogeler: const []);
    Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    final g = _olcu(_gCtrl), h = _olcu(_hCtrl);
    final olcuHata = 'mm, ${mmYaz(enKucukOlcu)}–${mmYaz(enBuyukOlcu)}';
    return AlertDialog(
      title: const Text('Yeni etiket tasarımı'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _adCtrl,
              decoration: InputDecoration(
                labelText: 'Tasarım adı',
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: _adCtrl.text.trim().isEmpty ? 'Ad verin' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _gCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Genişlik (mm)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: g == null ? olcuHata : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _hCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Yükseklik (mm)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: h == null ? olcuHata : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final o in hazirOlculer)
                ActionChip(
                  label: Text('${mmYaz(o.$1)}×${mmYaz(o.$2)}', style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _gCtrl.text = mmYaz(o.$1);
                    _hCtrl.text = mmYaz(o.$2);
                  }),
                ),
            ]),
            const SizedBox(height: 8),
            Text('Etiket rulonuzdaki BİR etiketin ölçüsünü girin (yazıcı sürücüsündeki kâğıt boyuyla aynı olmalı).',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Seçtiğim alanlarla hazır yerleştir'),
              subtitle: const Text('Kapalıysa boş etiketle başlar'),
              value: _otomatik,
              onChanged: (v) => setState(() => _otomatik = v),
            ),
            if (_otomatik)
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final a in OtomatikAlan.values)
                  FilterChip(
                    label: Text(otomatikAlanAdlari[a]!),
                    selected: _alanlar.contains(a),
                    onSelected: (v) => setState(() => v ? _alanlar.add(a) : _alanlar.remove(a)),
                  ),
              ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton.icon(onPressed: _tamam, icon: const Icon(Icons.design_services, size: 18), label: const Text('Tasarla')),
      ],
    );
  }
}
