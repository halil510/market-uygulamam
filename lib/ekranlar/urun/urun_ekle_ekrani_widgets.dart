// ignore_for_file: invalid_use_of_protected_member
// lib/ekranlar/urun/urun_ekle_ekrani_widgets.dart
// urun_ekle_ekrani.dart'ın parçası — bkz. urun_ekle_ekrani_form.dart
// başındaki not. Bu dosya: build()'in kullandığı küçük yardımcı widget
// metodları + sesli komut/döviz hesaplama dialoglarının kendi (bağımsız,
// _UrunEkleEkraniState'e ait OLMAYAN) widget sınıfları.
part of 'urun_ekle_ekrani.dart';

// ---- YARDIMCI WIDGET METODLARI ----
extension _UrunEkleWidgetExt on _UrunEkleEkraniState {
  Widget _bolum(String title, IconData icon) => FormBolum(baslik: title, ikon: icon);

  Widget _alan(String key, String label, {bool zorunlu = false, Widget? suffix}) =>
      FormMetinAlani(controller: _c[key]!, label: label, zorunlu: zorunlu, suffix: suffix);

  Widget _alanSayi(String key, String label, {bool zorunlu = false, Widget? suffix}) =>
      FormSayiAlani(controller: _c[key]!, label: label, zorunlu: zorunlu, suffix: suffix);

  Widget _barkodAlani() => Padding(padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        controller: _c['barkod'],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Barkod',
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            onPressed: _barkodTara,
          ),
        ),
      ),
      if (_aiDoldurulanAlanlar.contains('barkod') || _aiDoldurulanAlanlar.contains('urunAdi'))
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_awesome, size: 14, color: Colors.amber.shade700),
            const SizedBox(width: 4),
            Text('AI ile dolduruldu',
                style: TextStyle(fontSize: 10, color: Colors.amber.shade800)),
          ]),
        ),
    ]),
  );

  Widget _birimSecim() => FormBirimSecim(
    birimler: _birimler,
    secilenBirim: _birim,
    onDegisti: (v) => setState(() {
      _birim  = v;
      _kgModu = v == 'KG' || v == 'GR' || v == 'LİTRE' || v == 'ML';
    }),
  );

  Widget _alisKdvSecim() => FormAlisKdvSecim(
    secilenKdv: _alisKdvOran,
    onDegisti: (v) {
      _c['alisKdvOran']?.text = v;
      setState(() => _alisKdvOran = v);
      _alisKdvOranHesapla();
    },
  );

  Widget _alan1Secim() => FormOtomatikAlan(
    controller: _c['alan1']!,
    secenekler: _alan1lar,
    label: 'Alan 1',
    onDegisti: (_) => setState(() {}),
  );

  Widget _grupSecim(bool ana) => FormGrupSecim(
    key: ValueKey('${ana ? 'ana' : 'alt'}-${ana ? _anaGrup : _altGrup}'),
    gruplar: ana ? _anaGruplar : _altGruplar,
    secilenGrup: ana ? _anaGrup : _altGrup,
    label: ana ? 'Ana Grup' : 'Alt Grup',
    onDegisti: (v) => setState(() { if (ana) _anaGrup = v; else _altGrup = v; }),
  );
}

/// Sesli komut dinlerken gösterilen alt sayfa — canlı önizleme + durdur/iptal.
class _SesliKomutSheet extends StatefulWidget {
  final SesTanimaServisi ses;
  final void Function(String metin) onSonuc;
  final VoidCallback onIptal;
  const _SesliKomutSheet({required this.ses, required this.onSonuc, required this.onIptal});

  @override
  State<_SesliKomutSheet> createState() => _SesliKomutSheetState();
}

class _SesliKomutSheetState extends State<_SesliKomutSheet> {
  String _canliMetin = '';
  bool _basladi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _dinlemeyeBasla());
  }

  Future<void> _dinlemeyeBasla() async {
    setState(() => _basladi = true);
    await widget.ses.dinlemeyeBasla(
      onSonuc: (metin) { if (mounted) setState(() => _canliMetin = metin); },
      onBitti: (metin) {
        if (mounted) Navigator.of(context).pop();
        widget.onSonuc(metin);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(26),
              shape: BoxShape.circle,
            ),
            child: Icon(_basladi ? Icons.mic : Icons.mic_none, color: Colors.red, size: 36),
          ),
          const SizedBox(height: 16),
          Text(_basladi ? 'Dinliyorum...' : 'Hazırlanıyor...',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            _canliMetin.isEmpty
                ? 'Örn: "ürün adı çikolata", "alış fiyat 25,50", "satış fiyat 35"'
                : _canliMetin,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _canliMetin.isEmpty ? context.textSecondary : context.textPrimary),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () async {
              await widget.ses.iptal();
              if (mounted) Navigator.of(context).pop();
              widget.onIptal();
            },
            child: const Text('İptal'),
          ),
        ]),
      ),
    );
  }
}

/// "2 dolar geldi, kur 45,90" senaryosu için: döviz seç, yabancı tutarı
/// gir, TL karşılığı canlı olarak hesaplanıp gösterilir.
class _DovizleHesaplaDialog extends StatefulWidget {
  final List<DovizModel> dovizler;
  const _DovizleHesaplaDialog({required this.dovizler});

  @override
  State<_DovizleHesaplaDialog> createState() => _DovizleHesaplaDialogState();
}

class _DovizSonuc {
  final double tlTutari;
  final String? dovizKodu;
  final double? dovizTutari;
  const _DovizSonuc(this.tlTutari, {this.dovizKodu, this.dovizTutari});
}

class _DovizleHesaplaDialogState extends State<_DovizleHesaplaDialog> {
  late DovizModel _secili;
  final _tutarCtrl = TextEditingController();
  double _sonuc = 0;
  bool _dovizBazliTakip = false;

  @override
  void initState() {
    super.initState();
    _secili = widget.dovizler.first;
    _tutarCtrl.addListener(_hesapla);
  }

  @override
  void dispose() {
    _tutarCtrl.dispose();
    super.dispose();
  }

  void _hesapla() {
    final tutar = double.tryParse(_tutarCtrl.text.replaceAll(',', '.')) ?? 0;
    setState(() => _sonuc = tutar * _secili.satisKuru);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Dövizle Hesapla'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<DovizModel>(
          value: _secili,
          decoration: const InputDecoration(labelText: 'Para Birimi', border: OutlineInputBorder()),
          items: widget.dovizler.map((d) => DropdownMenuItem(
              value: d, child: Text('${d.kod} (${d.satisKuru.toStringAsFixed(4)} ₺)'))).toList(),
          onChanged: (v) => setState(() { _secili = v!; _hesapla(); }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tutarCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: '${_secili.kod} Tutarı',
            prefixText: '${_secili.sembol} ',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text('TL Karşılığı', style: TextStyle(fontSize: 11, color: context.textSecondary)),
            Text('${_sonuc.toStringAsFixed(2)} ₺',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.green)),
          ]),
        ),
        const SizedBox(height: 8),
        // Kullanıcı sorusu: "kur değişti o zaman nasıl olacak?" — bu
        // seçenek işaretlenirse ürün, bu döviz tutarına "sabitlenir";
        // kur değiştiğinde Ürün Listesi > Toplu Döviz Güncelleme'den
        // TÜM bu tür ürünlerin TL fiyatı tek seferde yeniden hesaplanabilir.
        CheckboxListTile(
          value: _dovizBazliTakip,
          onChanged: (v) => setState(() => _dovizBazliTakip = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Bu ürünü döviz bazında takip et',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          subtitle: const Text(
              'Kur değiştiğinde "Toplu Döviz Güncelleme" ile bu ürünün '
              'TL fiyatını otomatik yeniden hesaplayabilirsiniz.',
              style: TextStyle(fontSize: 10)),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: _sonuc > 0
              ? () => Navigator.pop(context, _DovizSonuc(_sonuc,
                  dovizKodu: _dovizBazliTakip ? _secili.kod : null,
                  dovizTutari: _dovizBazliTakip
                      ? double.tryParse(_tutarCtrl.text.replaceAll(',', '.'))
                      : null))
              : null,
          child: const Text('Kullan'),
        ),
      ],
    );
  }
}