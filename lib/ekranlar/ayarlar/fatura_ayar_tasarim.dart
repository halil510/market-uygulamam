// lib/ekranlar/ayarlar/fatura_ayar_tasarim.dart
//
// Tasarım sekmesi, logo/imza alanı ve ortak form parçaları — fatura_ayar_ekrani.dart'tan ayrıldı (2026-10-07 refactor).
// ignore_for_file: invalid_use_of_protected_member
part of 'fatura_ayar_ekrani.dart';

extension _FaturaAyarTasarim on _FaturaAyarEkraniState {
  // ── Logo / İmza yükleme alanı (kart) ────────────────────────────────────
  Widget _gorselAlani({required bool logoMu}) {
    final yol = logoMu ? _logoYolu : _imzaYolu;
    final var_ = yol != null && File(yol).existsSync();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: context.cardBg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor)),
      child: Row(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: context.dividerColor,
            borderRadius: BorderRadius.circular(8),
            image: var_ ? DecorationImage(image: FileImage(File(yol)), fit: BoxFit.contain) : null,
          ),
          child: !var_
              ? Icon(logoMu ? Icons.image_outlined : Icons.draw_outlined,
                  color: context.textSecondary, size: 28)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(logoMu ? 'Firma Logosu' : 'İmza / Kaşe Görseli',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            var_
                ? 'Yüklendi — faturalarda görünecek'
                : (logoMu
                    ? 'PNG/JPG — şeffaf arkaplan önerilir'
                    : 'Islak imza/kaşe taraması veya dijital imza'),
            style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ])),
        TextButton(
          onPressed: () => _gorselSec(logoMu),
          child: Text(var_ ? 'Değiştir' : 'Yükle'),
        ),
        if (var_)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: () => _gorselKaldir(logoMu),
          ),
      ]),
    );
  }

  // ── Fatura Tasarımı ───────────────────────────────────────────────────────
  Widget _tasarimTab() => ListView(padding: const EdgeInsets.all(16), children: [
    const _Baslik('Logo ve İmza/Kaşe'),
    _gorselAlani(logoMu: true),
    const SizedBox(height: 8),
    _gorselAlani(logoMu: false),
    const SizedBox(height: 12),
    const _Baslik('Görünüm'),
    _Kart(children: [
      _SwitchSatir('Logo Göster', 'Fatura başlığında firma logosu',
          _logoGoster, (v) => setState(() => _logoGoster = v),
          Icons.image_outlined, Colors.blue),
      _SwitchSatir('İmza/Kaşe Alanı', 'Fatura altında imza ve kaşe alanı',
          _imzaGoster, (v) => setState(() => _imzaGoster = v),
          Icons.draw_outlined, Colors.indigo),
      _SwitchSatir('KDV Ayrı Göster', 'Her satırda KDV tutarını ayrıca belirt',
          _kdvAyri, (v) => setState(() => _kdvAyri = v),
          Icons.percent_outlined, Colors.teal),
      _SwitchSatir('Barkod/QR Göster', 'Fatura altında barkod veya QR kod',
          _barkodGoster, (v) => setState(() => _barkodGoster = v),
          Icons.qr_code_outlined, Colors.purple),
    ]),
    const SizedBox(height: 12),
    const _Baslik('Numaralandırma ve İskonto'),
    Row(children: [
      Expanded(child: _Alan('Fatura No Ön Eki', _faturaOnEkCtrl,
          hint: 'Örn: HLF (e-Fatura), HLA (e-Arşiv)')),
      const SizedBox(width: 12),
      Expanded(child: _Alan('Başlangıç Sıra No', _baslangicNoCtrl,
          hint: '1', keyboardType: TextInputType.number)),
    ]),
    _Alan('Varsayılan İskonto %', _iskontoCtrl,
        hint: '0', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'Örnek: Ön ek "HLF", Başlangıç No "18" ise ilk fatura '
        '"HLF2026000000018" olur. Sayaç bu numaradan devam eder.',
        style: TextStyle(fontSize: 11, color: context.textSecondary)),
    ),
    // 🔴 DÜZELTME (kritik — derin denetimde bulundu): Fatura numarası
    // SADECE bu cihazdaki yerel verilere bakılarak (MAX+1) üretilir —
    // buluttan/diğer cihazlardan KONTROL EDİLMEZ. Birden fazla cihaz
    // (ör. iki kasa, iki şube) faturayı BURADAN kesiyorsa ve AYNI ön eki
    // kullanıyorsa, iki cihaz AYNI ANDA AYNI fatura numarasını üretebilir
    // — bu, GİB nezdinde ciddi bir mükerrer/sıra hatası riskidir. Önceden
    // bu risk hiç belirtilmiyordu.
    Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Birden fazla cihazdan/şubeden fatura kesiyorsanız her cihaza '
            'FARKLI bir ön ek verin (ör. Merkez: "HLF", Şube: "HLS"). Aynı '
            'ön ek kullanılırsa, iki cihaz aynı anda aynı fatura numarasını '
            'üretebilir — bu GİB\'e karşı mükerrer/sıra hatası riski taşır.',
            style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900),
          ),
        ),
      ]),
    ),
    const SizedBox(height: 4),
    const _Baslik('Yazdırma Formatı'),
    _Kart(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Fatura "Yazdır" butonuna basınca varsayılan format',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _formatSecimi('A4 (e-Fatura/e-Arşiv)', 'a4',
                Icons.description_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _formatSecimi('80mm Fiş', '80mm',
                Icons.receipt_long_outlined)),
          ]),
          const SizedBox(height: 6),
          Text(
            'Diğer format ve e-posta gönderimi her zaman fatura ekranındaki '
            '"⋮" menüsünden de seçilebilir.',
            style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ]),
      ),
    ]),
    const SizedBox(height: 4),
    const _Baslik('Yazı Boyutu'),
    _Kart(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Faturanın PDF çıktısındaki tüm yazıların boyutu',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0.85, label: Text('Kompakt')),
              ButtonSegment(value: 1.0, label: Text('Normal')),
              ButtonSegment(value: 1.15, label: Text('Büyük')),
            ],
            selected: {_fontOlcek},
            onSelectionChanged: (s) => setState(() => _fontOlcek = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            'Daha fazla ürün satırını tek sayfaya sığdırmak için "Kompakt", '
            'göz yorgunluğu az olsun diye "Büyük" seçebilirsiniz.',
            style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ]),
      ),
    ]),
    const SizedBox(height: 4),
    const _Baslik('Fatura Notları'),
    _Alan('Fatura Notları', _faturaNotCtrl,
        hint: 'Her faturada görünecek notlar...', maxLines: 3),
    _Alan('Dipnot', _dipnotCtrl,
        hint: 'Fatura alt bilgisi...', maxLines: 2),
    const SizedBox(height: 12),
    // Önizleme kartı
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: context.cardBg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Fatura Önizleme',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              border: Border.all(color: context.borderColor),
              borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_logoGoster) Container(
              width: 60, height: 30,
              decoration: BoxDecoration(color: context.dividerColor, borderRadius: BorderRadius.circular(4)),
              child: Center(child: Text('LOGO', style: TextStyle(fontSize: 10, color: context.textSecondary)))),
            Text(_firmaAdiCtrl.text.isEmpty ? 'Firma Adı' : _firmaAdiCtrl.text,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (_vergiNoCtrl.text.isNotEmpty)
              Text('VKN: ${_vergiNoCtrl.text}', style: TextStyle(fontSize: 10, color: context.textSecondary)),
            const Divider(height: 12),
            Row(children: [
              const Text('FATURA', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
              const Spacer(),
              Text('No: FAT-2024-0001', style: TextStyle(fontSize: 10, color: context.textSecondary)),
            ]),
            const SizedBox(height: 6),
            Container(height: 1, color: context.borderColor),
            const SizedBox(height: 4),
            const Row(children: [
              Expanded(flex: 3, child: Text('Ürün Adı', style: TextStyle(fontSize: 9))),
              Expanded(child: Text('Adet', style: TextStyle(fontSize: 9), textAlign: TextAlign.right)),
              Expanded(child: Text('Fiyat', style: TextStyle(fontSize: 9), textAlign: TextAlign.right)),
              Expanded(child: Text('Tutar', style: TextStyle(fontSize: 9), textAlign: TextAlign.right)),
            ]),
            const SizedBox(height: 4),
            if (_faturaNotCtrl.text.isNotEmpty)
              Text(_faturaNotCtrl.text, style: TextStyle(fontSize: 8, color: context.textSecondary)),
            if (_imzaGoster) const SizedBox(height: 20),
            if (_imzaGoster) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('İmza / Kaşe', style: TextStyle(fontSize: 9, color: context.textSecondary)),
                Text('Alınan / Teslim Alan', style: TextStyle(fontSize: 9, color: context.textSecondary)),
              ]),
            if (_dipnotCtrl.text.isNotEmpty)
              Text(_dipnotCtrl.text,
                  style: TextStyle(fontSize: 8, color: context.textSecondary,
                      fontStyle: FontStyle.italic)),
          ]),
        ),
      ]),
    ),
    const SizedBox(height: 80),
  ]);

  Widget _Alan(String label, TextEditingController ctrl, {
    String? hint, int maxLines = 1, TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters, bool obscure = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: context.textSecondary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
}

class _Baslik extends StatelessWidget {
  final String metin;
  const _Baslik(this.metin);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(metin, style: TextStyle(
        fontWeight: FontWeight.w700, fontSize: 12,
        color: AppRenkler.primary.withAlpha(204),
        letterSpacing: 0.5)),
  );
}

class _Kart extends StatelessWidget {
  final List<Widget> children;
  const _Kart({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
        color: context.cardBg, borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)]),
    // Şeffaf Material: içteki ListTile/Switch dokunma dalgası görünsün.
    child: Material(
      type: MaterialType.transparency,
      child: Column(children: children),
    ),
  );
}

class _SwitchSatir extends StatelessWidget {
  final String baslik, aciklama; final bool deger;
  final ValueChanged<bool> onChanged; final IconData ikon; final Color renk;
  const _SwitchSatir(this.baslik, this.aciklama, this.deger,
      this.onChanged, this.ikon, this.renk);
  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: Container(padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: renk.withAlpha(26), borderRadius: BorderRadius.circular(12)),
        child: Icon(ikon, color: renk, size: 18)),
    title: Text(baslik, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    subtitle: Text(aciklama, style: TextStyle(fontSize: 11, color: context.textSecondary)),
    value: deger, onChanged: onChanged,
    activeThumbColor: renk,
    dense: true,
  );
}
