// lib/ekranlar/ayarlar/fatura_ayar_sekmeleri.dart
//
// Firma, e-Fatura ve KDV sekmeleri — fatura_ayar_ekrani.dart'tan ayrıldı (2026-10-07 refactor).
// ignore_for_file: invalid_use_of_protected_member
part of 'fatura_ayar_ekrani.dart';

extension _FaturaAyarSekmeleri on _FaturaAyarEkraniState {
  // ── Firma Bilgileri ────────────────────────────────────────────────────────
  Widget _firmaTab() => ListView(padding: const EdgeInsets.all(16), children: [
    const _Baslik('Temel Bilgiler'),
    _alan('Firma Adı *', _firmaAdiCtrl, hint: 'ABC Ticaret A.Ş.'),
    _alan('Vergi No *', _vergiNoCtrl, hint: '1234567890',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]),
    _alan('Vergi Dairesi *', _vergiDairesiCtrl, hint: 'Kadıköy Vergi Dairesi'),
    _alan('MERSİS No', _mersisCtrl, hint: '0123456789012345',
        keyboardType: TextInputType.number),
    _alan('Ticaret Sicil No', _ticaretSicilCtrl, hint: '12345'),
    const SizedBox(height: 8),
    const _Baslik('Adres'),
    _alan('Adres', _adresCtrl, hint: 'Mevlana Cad. No:1 Daire:5', maxLines: 2),
    Row(children: [
      Expanded(child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IlAlani(controller: _ilCtrl, onSecildi: (_) => setState(() {})),
      )),
      const SizedBox(width: 10),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IlceAlani(controller: _ilceCtrl, ilController: _ilCtrl),
      )),
    ]),
    const SizedBox(height: 8),
    const _Baslik('İletişim'),
    _alan('Telefon', _telefonCtrl, hint: '0212 555 44 33',
        keyboardType: TextInputType.phone),
    _alan('Faks', _faxCtrl, hint: '0212 555 44 34',
        keyboardType: TextInputType.phone),
    _alan('E-Posta', _emailCtrl, hint: 'info@firma.com',
        keyboardType: TextInputType.emailAddress),
    _alan('Web Sitesi', _webCtrl, hint: 'www.firma.com'),
    const SizedBox(height: 80),
  ]);

  // ── e-Fatura / GIB ────────────────────────────────────────────────────────
  Widget _eFaturaTab() => ListView(padding: const EdgeInsets.all(16), children: [
    // Aktiflik toggle'ları
    _Kart(children: [
      _SwitchSatir('e-Fatura Aktif', 'GIB kayıtlı mükellefler için zorunlu',
          _eFaturaAktif, (v) => setState(() => _eFaturaAktif = v),
          Icons.receipt_long_outlined, Colors.blue),
      _SwitchSatir('e-Arşiv Aktif', 'Diğer alıcılar için fatura',
          _eArsivAktif, (v) => setState(() => _eArsivAktif = v),
          Icons.archive_outlined, Colors.green),
      _SwitchSatir('e-İrsaliye Aktif', 'Taşıma irsaliyesi düzenleme',
          _eIrsaliyeAktif, (v) => setState(() => _eIrsaliyeAktif = v),
          Icons.local_shipping_outlined, Colors.orange),
    ]),
    const SizedBox(height: 16),

    // GİB bağlantı bilgileri (API URL/kullanıcı/şifre/VKN/test-canlı) TEK
    // bir yerde yönetilir — burada AYRICA toplanmaz (bkz. dosya başındaki
    // not: önceden burada aynı bilgiler için gerçek servisin hiç okumadığı,
    // ölü bir kopya vardı).
    const _Baslik('GİB Bağlantı Ayarları'),
    _Kart(children: [
      ListTile(
        leading: const Icon(Icons.settings_outlined, color: Colors.red),
        title: const Text('GİB e-Fatura Entegrasyonu',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: const Text(
            'API URL, kullanıcı adı/şifre, VKN, test/canlı modu',
            style: TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/ayarlar/gib'),
      ),
    ]),
    const SizedBox(height: 8),
    // GIB bilgi kutusu
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: TsRenk.zemin(TsRenk.bilgi), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200)),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.info_outline, color: Colors.blue, size: 16),
          SizedBox(width: 6),
          Text('Türkiye e-Fatura (2026)', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.blue)),
        ]),
        SizedBox(height: 6),
        Text(
          '• e-Fatura: GIB onaylı Mali Mühür veya e-İmza zorunludur\n'
          '• e-İmza: Kamu SM (kamusm.gov.tr) üzerinden temin edilir\n'
          '• Mali Mühür: TÜBİTAK-BİLGEM CA üzerinden alınır\n'
          '• e-Arşiv: 2026 itibarıyla tüm B2C satışlar zorunlu\n'
          '• Ciro 3M TL üzeri → e-Fatura mükellefi (2024 sınırı)\n'
          '• GIB Portal: efatura.gov.tr\n'
          '• Entegratör API bilgilerini yukarıya giriniz',
          style: TextStyle(fontSize: 11, height: 1.6, color: Colors.blue)),
      ]),
    ),
    const SizedBox(height: 80),
  ]);

  // ── KDV Ayarları ──────────────────────────────────────────────────────────
  Widget _kdvTab() => ListView(padding: const EdgeInsets.all(16), children: [
    const _Baslik('Türkiye KDV Oranları (2024)'),
    _Kart(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Varsayılan KDV Oranı',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: ['0', '1', '10', '20'].map((oran) {
            final secili = _varsayilanKdv == oran;
            return GestureDetector(
              onTap: () => setState(() => _varsayilanKdv = oran),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: secili ? AppRenkler.primary : TsRenk.arkaplan(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: secili ? AppRenkler.primary : TsRenk.ayirac(context)),
                ),
                child: Column(children: [
                  Text('%$oran',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16,
                          color: secili ? Colors.white : TsRenk.metinBirincil(context))),
                  Text(_kdvAciklama(oran),
                      style: TextStyle(fontSize: 10,
                          color: secili ? Colors.white70 : context.textSecondary)),
                ]),
              ),
            );
          }).toList()),
        ]),
      ),
    ]),
    const SizedBox(height: 12),
    _Kart(children: [
      _SwitchSatir('KDV Muafiyeti', 'Belirli mal/hizmetler KDV\'den muaf',
          _kdvMusaf, (v) => setState(() => _kdvMusaf = v),
          Icons.no_meals_outlined, Colors.orange),
    ]),
    const SizedBox(height: 12),
    _Kart(children: [
      _SwitchSatir('Tevkifat (KDV Stopajı)', 'Belirli hizmetlerde KDV tevkifatı',
          _tevkifat, (v) => setState(() => _tevkifat = v),
          Icons.calculate_outlined, Colors.purple),
      if (_tevkifat) Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tevkifat Oranı', style: TextStyle(fontSize: 12, color: context.textSecondary)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6,
            children: ['1/2', '2/3', '3/4', '4/5', '5/6', '7/10', '9/10'].map((o) =>
              ChoiceChip(label: Text(o), selected: _tevkifatOrani == o,
                onSelected: (_) => setState(() => _tevkifatOrani = o))).toList()),
        ]),
      ),
    ]),
    const SizedBox(height: 12),
    // KDV bilgi kutusu
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: TsRenk.zemin(TsRenk.uyari), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade300)),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.info_outline, color: Colors.amber, size: 16),
          SizedBox(width: 6),
          Text('Güncel KDV Oranları (2026)', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.amber)),
        ]),
        SizedBox(height: 6),
        Text(
          '• %20 — Standart oran (2023\'ten itibaren %18→%20)\n'
          '• %10 — İndirimli oran (gıda, bazı hizmetler)\n'
          '• %1  — Özel indirimli (temel gıda, tarım)\n'
          '• %0  — KDV\'den muaf',
          style: TextStyle(fontSize: 11, height: 1.6, color: Colors.amber)),
      ]),
    ),
    const SizedBox(height: 80),
  ]);

  String _kdvAciklama(String oran) {
    switch (oran) {
      case '20': return 'Standart';
      case '10': return 'İndirimli';
      case '1':  return 'Özel';
      case '0':  return 'Muaf';
      default:   return '';
    }
  }

  Widget _formatSecimi(String etiket, String deger, IconData ikon) {
    final secili = _yazdirmaFormat == deger;
    return InkWell(
      onTap: () => setState(() => _yazdirmaFormat = deger),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: secili ? AppRenkler.primary.withAlpha(26) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: secili ? AppRenkler.primary : context.borderColor),
        ),
        child: Column(children: [
          Icon(ikon, color: secili ? AppRenkler.primary : context.textSecondary, size: 22),
          const SizedBox(height: 4),
          Text(etiket, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: secili ? AppRenkler.primary : context.textSecondary)),
          if (secili) ...[
            const SizedBox(height: 2),
            const Icon(Icons.check_circle, size: 14, color: AppRenkler.primary),
          ],
        ]),
      ),
    );
  }
}
