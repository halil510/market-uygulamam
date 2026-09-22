// lib/ekranlar/toptan/cari_detay_genel_ozet_ext.dart
// cari_detay_paneli.dart'ın parçası — "GENEL" (bilgi/adres/irsaliye) ve
// "ÖZET" (bakiye+rapor+grafik) sekmeleri (god-class sertleştirmesi,
// 2026-09-22). Davranış birebir korundu.
part of 'cari_detay_paneli.dart';

extension _CariDetayGenelOzetExt on _CariDetayPaneliState {
  // ══════════════════ 2) GENEL (Logo: cari hesabın detay bilgileri) ═════
  Widget _genelSekmesi() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _genelSatir(Icons.storefront_outlined, 'Unvan', widget.cari.unvan),
            _genelSatir(Icons.category_outlined, 'Müşteri Tipi', widget.cari.musteriTipi),
            if (_fiyatGrubu != null) _genelSatir(Icons.local_offer_outlined, 'Fiyat Grubu', _fiyatGrubu!.ad),
            if (widget.cari.telefon != null) _genelSatir(Icons.phone_outlined, 'Telefon', widget.cari.telefon!),
            if (widget.cari.email != null) _genelSatir(Icons.email_outlined, 'E-posta', widget.cari.email!),
            if (widget.cari.vergiNo != null) _genelSatir(Icons.badge_outlined, 'Vergi No', widget.cari.vergiNo!),
            if (widget.cari.vergiDairesi != null) _genelSatir(Icons.account_balance_outlined, 'Vergi Dairesi', widget.cari.vergiDairesi!),
            if (widget.cari.vadeGun > 0) _genelSatir(Icons.event_outlined, 'Vade', '${widget.cari.vadeGun} gün'),
            if (widget.cari.limitTutari > 0) _genelSatir(Icons.account_balance_wallet_outlined, 'Kredi Limiti', ParaUtils.formatla(widget.cari.limitTutari), sonSatir: true),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Text('SEVKİYAT ADRESLERİ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: context.textSecondary)),
          const Spacer(),
          TextButton.icon(onPressed: _adresEkle, icon: const Icon(Icons.add, size: 16), label: const Text('Ekle', style: TextStyle(fontSize: 12))),
        ]),
        const SizedBox(height: 4),
        ..._adresler.map((a) => _adresSatiri(a)),
        if (_adresler.isEmpty) Text('Kayıtlı adres yok', style: TextStyle(fontSize: 12, color: context.textHint)),
        const SizedBox(height: 16),
        Text('İRSALİYELER (${_irsaliyeler.length})', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: context.textSecondary)),
        const SizedBox(height: 8),
        _irsaliyeSekmesiIcerik(),
      ],
    );
  }

  Widget _genelSatir(IconData ikon, String etiket, String deger, {bool sonSatir = false}) => Padding(
        padding: EdgeInsets.only(bottom: sonSatir ? 0 : 10),
        child: Row(children: [
          Icon(ikon, size: 16, color: context.textHint),
          const SizedBox(width: 10),
          Text(etiket, style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
          const Spacer(),
          Flexible(child: Text(deger, textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary))),
        ]),
      );

  Widget _adresSatiri(Map<String, dynamic> a) {
    final varsayilan = (a['varsayilan'] as int?) == 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.cardBg, borderRadius: BorderRadius.circular(10),
        border: varsayilan ? Border.all(color: AppRenkler.primary.withAlpha(120)) : null,
      ),
      child: Row(children: [
        Icon(Icons.place_outlined, color: varsayilan ? AppRenkler.primary : context.textHint, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['adres_tipi']?.toString() ?? 'Sevkiyat', style: TsMetin.kucukVurgu.copyWith(color: context.textPrimary)),
            Text('${a['adres']}${a['ilce'] != null ? ', ${a['ilce']}' : ''}${a['il'] != null ? '/${a['il']}' : ''}',
                style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
          ]),
        ),
        IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _adresSil(a['id'] as int)),
      ]),
    );
  }

  // ══════════════════ SEVKİYAT ADRESLERİ (artık _genelSekmesi içinde gömülü) ══════════════════
  Future<void> _adresEkle() async {
    final adresCtrl = TextEditingController();
    final ilceCtrl = TextEditingController();
    final ilCtrl = TextEditingController();
    String tip = 'Sevkiyat';

    final kaydet = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
        title: const Text('Yeni Sevkiyat Adresi'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: tip,
            decoration: const InputDecoration(labelText: 'Adres Tipi'),
            items: const [
              DropdownMenuItem(value: 'Sevkiyat', child: Text('Sevkiyat')),
              DropdownMenuItem(value: 'Fatura', child: Text('Fatura')),
              DropdownMenuItem(value: 'Depo', child: Text('Depo')),
            ],
            onChanged: (v) => setD(() => tip = v ?? 'Sevkiyat'),
          ),
          const SizedBox(height: 10),
          TextField(controller: adresCtrl, decoration: const InputDecoration(labelText: 'Adres'), maxLines: 2, autofocus: true),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: IlceAlani(controller: ilceCtrl, ilController: ilCtrl)),
            const SizedBox(width: 8),
            Expanded(child: IlAlani(controller: ilCtrl)),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      )),
    );
    if (kaydet != true || adresCtrl.text.trim().isEmpty) return;

    final varsayilan = _adresler.isEmpty; // ilk eklenen adres otomatik varsayılan
    await _adresDepo.ekle(
      cariId: widget.cari.id!,
      adresTipi: tip,
      adres: adresCtrl.text.trim(),
      ilce: ilceCtrl.text.trim(),
      il: ilCtrl.text.trim(),
      varsayilanMi: varsayilan,
    );
    if (mounted) BildirimServisi.basari(context, 'Adres eklendi');
    _yukle();
  }

  Future<void> _adresSil(int id) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Adresi Sil'),
        content: const Text('Bu sevkiyat adresi silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
              onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    // Madde 2 sertleştirmesi: silme artık CariAdresDeposu.sil() üzerinden
    // — bu, önceki (bildirimsiz hard-delete) haliyle karşılaştırınca
    // buluta da bildiriyor (bkz. o metodun kendi yorumu).
    await _adresDepo.sil(id);
    if (mounted) BildirimServisi.basari(context, 'Adres silindi');
    _yukle();
  }

  // ══════════════════ İRSALİYE ══════════════════
  Widget _irsaliyeSekmesiIcerik() {
    if (_irsaliyeler.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Bu cariye ait irsaliye yok', style: TextStyle(fontSize: 12, color: context.textHint)),
      );
    }
    return Column(children: _irsaliyeler.map((irs) {
      final tarih = DateTime.tryParse(irs['tarih']?.toString() ?? '');
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.teal.withAlpha(30), shape: BoxShape.circle),
            child: const Icon(Icons.local_shipping_outlined, color: Colors.teal, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(irs['irsaliye_no']?.toString() ?? '—', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary)),
              Text(tarih != null ? DateFormat('dd.MM.yyyy').format(tarih) : '—', style: TextStyle(fontSize: 11, color: context.textHint)),
            ]),
          ),
          Text(ParaUtils.formatla((irs['toplam_tutar'] as num?)?.toDouble() ?? 0),
              style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
        ]),
      );
    }).toList());
  }

  // ══════════════════ 3) ÖZET (Logo: bakiye+rapor+grafik) ═══════════════
  Widget _ozetSekmesi() {
    final yaslandirma = _vadeYaslandirma();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (yaslandirma.values.any((v) => v > 0)) ...[
          Text('BORÇ TAKİP (VADE YAŞLANDIRMA)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: context.textSecondary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(14)),
            child: Row(children: yaslandirma.entries.map((e) {
              final renk = switch (e.key) {
                'Vadesi Gelmemiş' => Colors.green,
                '1-30 Gün' => Colors.amber.shade700,
                '31-60 Gün' => Colors.orange,
                _ => Colors.red,
              };
              return Expanded(
                child: Column(children: [
                  Text(ParaUtils.formatla(e.value), style: TextStyle(color: renk, fontSize: 12, fontWeight: FontWeight.w800),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(e.key, style: TextStyle(color: context.textHint, fontSize: 8.5), textAlign: TextAlign.center, maxLines: 1),
                ]),
              );
            }).toList()),
          ),
          const SizedBox(height: 16),
        ],
        ..._ozetIcerik(),
      ]),
    );
  }

  // ══════════════════ VADE YAŞLANDIRMA (Borç Takip) ══════════════════
  /// Kullanıcı isteği: "Borç Takip / Vade Yaşlandırma (30-60-90 gün)".
  /// FIFO mantığıyla: tahsilatlar EN ESKİ borçtan başlayarak düşülür,
  /// kalan bakiyeler vade tarihine (satış tarihi + cari.vadeGun) göre
  /// yaş gruplarına ayrılır — Logo/Netsis'teki "Borç Takip Toplamları"
  /// ile aynı mantık.
  Map<String, double> _vadeYaslandirma() {
    final sonuc = <String, double>{
      'Vadesi Gelmemiş': 0, '1-30 Gün': 0, '31-60 Gün': 0, '90+ Gün': 0,
    };
    if (_satislar.isEmpty) return sonuc;

    // En eskiden en yeniye sırala (FIFO tahsis için).
    final kronolojik = List<SatisModel>.from(_satislar.reversed);
    var kullanilabilirTahsilat = _tahsilatlar
        .where((t) => !t.fisTipi.contains('İptal'))
        .fold<double>(0, (s, t) => s + (t.alacak > 0 ? t.alacak : 0));

    final bugun = DateTime.now();
    for (final s in kronolojik) {
      var kalan = s.genelToplam;
      if (kullanilabilirTahsilat > 0) {
        final dusulen = kullanilabilirTahsilat >= kalan ? kalan : kullanilabilirTahsilat;
        kalan -= dusulen;
        kullanilabilirTahsilat -= dusulen;
      }
      if (kalan <= 0.01) continue;

      final vadeTarihi = s.tarih.add(Duration(days: widget.cari.vadeGun));
      final gecikme = bugun.difference(vadeTarihi).inDays;
      if (gecikme <= 0) {
        sonuc['Vadesi Gelmemiş'] = sonuc['Vadesi Gelmemiş']! + kalan;
      } else if (gecikme <= 30) {
        sonuc['1-30 Gün'] = sonuc['1-30 Gün']! + kalan;
      } else if (gecikme <= 60) {
        sonuc['31-60 Gün'] = sonuc['31-60 Gün']! + kalan;
      } else {
        sonuc['90+ Gün'] = sonuc['90+ Gün']! + kalan;
      }
    }
    return sonuc;
  }

  // ══════════════════ RAPORLAR / GRAFİKLER ══════════════════
  List<Widget> _ozetIcerik() {
    if (_satislar.isEmpty) {
      return [
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bar_chart_outlined, size: 44, color: context.textHint),
          const SizedBox(height: 8),
          Text('Rapor oluşturmak için henüz yeterli veri yok', style: TextStyle(color: context.textHint)),
        ])),
      ];
    }

    // Ödeme performansı: vade yaşlandırmadaki "vadesi gelmemiş" oranına
    // bakarak yaklaşık bir "zamanında ödeme" göstergesi.
    final yaslandirma = _vadeYaslandirma();
    final toplamAcikBakiye = yaslandirma.values.fold(0.0, (a, b) => a + b);
    final zamanindaOran = toplamAcikBakiye <= 0.01
        ? 1.0
        : (yaslandirma['Vadesi Gelmemiş'] ?? 0) / toplamAcikBakiye;
    final ortalamaSepet = _satislar.isEmpty
        ? 0.0
        : _satislar.fold(0.0, (s, x) => s + x.genelToplam) / _satislar.length;

    return [
      // ── Özet istatistik kartları ──────────────────────────────
      Row(children: [
        Expanded(child: _raporKarti('Toplam İşlem', '${_satislar.length}', Icons.receipt_long_outlined, AppRenkler.primary)),
        const SizedBox(width: 8),
        Expanded(child: _raporKarti('Ort. Sepet', ParaUtils.formatla(ortalamaSepet), Icons.shopping_basket_outlined, Colors.blue)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _raporKarti('Zamanında Ödeme', '%${(zamanindaOran * 100).toStringAsFixed(0)}',
            Icons.verified_outlined, zamanindaOran > 0.7 ? Colors.green : Colors.orange)),
        const SizedBox(width: 8),
        Expanded(child: _raporKarti('Açık Bakiye', ParaUtils.formatla(toplamAcikBakiye), Icons.account_balance_wallet_outlined, Colors.red)),
      ]),

      // ── Aylık satış grafiği (Logo Mobile Sales: "Haftalık/Aylık Satış") ──
      if (_aylikSatis.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('SON 6 AY SATIŞ TRENDİ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
            letterSpacing: 0.4, color: context.textSecondary)),
        const SizedBox(height: 12),
        Container(
          height: 160,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(14)),
          child: _aylikSatisGrafigi(),
        ),
      ],

      // ── En çok alınan ürünler (Logo Mobile Sales: "En Çok Satılan 10 Ürün") ──
      if (_enCokAlinanlar.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('EN ÇOK ALINAN ÜRÜNLER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
            letterSpacing: 0.4, color: context.textSecondary)),
        const SizedBox(height: 8),
        ..._enCokAlinanlar.map((u) {
          final maxTutar = (_enCokAlinanlar.first['toplam_tutar'] as num).toDouble();
          final buTutar = (u['toplam_tutar'] as num).toDouble();
          final oran = maxTutar <= 0 ? 0.0 : buTutar / maxTutar;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(u['urun_adi']?.toString() ?? '—',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(ParaUtils.formatla(buTutar), style: TsMetin.kucukVurgu.copyWith(color: context.textPrimary)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: oran, minHeight: 5,
                    backgroundColor: context.inputFill, color: AppRenkler.primary),
              ),
              const SizedBox(height: 3),
              Text('${(u['toplam_miktar'] as num).toStringAsFixed(0)} adet/birim alındı',
                  style: TextStyle(fontSize: 10, color: context.textHint)),
            ]),
          );
        }),
      ],
    ];
  }

  Widget _raporKarti(String baslik, String deger, IconData ikon, Color renk) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ikon, size: 14, color: renk),
            const SizedBox(width: 5),
            Expanded(child: Text(baslik, style: TextStyle(fontSize: 10, color: context.textHint), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Text(deger, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary)),
        ]),
      );

  Widget _aylikSatisGrafigi() {
    final maxY = _aylikSatis.fold(0.0, (m, e) => (e['toplam'] as num).toDouble() > m ? (e['toplam'] as num).toDouble() : m);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY <= 0 ? 1 : maxY * 1.15,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final idx = group.x.toInt();
              final ay = idx >= 0 && idx < _aylikSatis.length ? _aylikSatis[idx]['ay'].toString() : '';
              return BarTooltipItem('$ay\n${ParaUtils.formatla(rod.toY)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11));
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, _) {
                final idx = val.toInt();
                if (idx < 0 || idx >= _aylikSatis.length) return const SizedBox.shrink();
                final ay = _aylikSatis[idx]['ay'].toString();
                final kisa = ay.length >= 7 ? ay.substring(5) : ay; // "2026-03" -> "03"
                return Text(kisa, style: TextStyle(fontSize: 9, color: context.textSecondary, fontWeight: FontWeight.w500));
              },
            ),
          ),
        ),
        gridData: FlGridData(drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: context.borderColor, strokeWidth: 0.5)),
        borderData: FlBorderData(show: false),
        barGroups: _aylikSatis.asMap().entries.map((e) {
          final toplam = (e.value['toplam'] as num?)?.toDouble() ?? 0;
          return BarChartGroupData(x: e.key, barRods: [
            BarChartRodData(
              toY: toplam, width: 20,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF6D4C41), Color(0xFFA1887F)],
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }
}
