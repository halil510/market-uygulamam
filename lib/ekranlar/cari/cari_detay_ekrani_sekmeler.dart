// ignore_for_file: invalid_use_of_protected_member
//
// cari_detay_ekrani.dart parçası (god-class bölme, 2026-09-29) — kod
// birebir taşındı, davranış değişmedi. setState extension içinden
// çağrıldığı için protected uyarısı dosya bazında muaf (bkz.
// fatura_detay_islemler_ext.dart'taki açıklama).
// Bilgi / Hareketler / Analiz sekmeleri, e-Fatura rozeti ve alt widget'lar.
part of 'cari_detay_ekrani.dart';

extension _CariDetaySekmelerExt on _CariDetayIcerikState {
  /// e-Fatura / e-Arşiv durumu — YALNIZ gerçek GİB sorgusunun sonucu
  /// (`cari.mukellefDurumu`).
  ///
  /// 🔴 DÜZELTME (kullanıcı bulgusu 2026-09-28 — "rastgele TC girdim
  /// e-Fatura yazdı"): önceden numaranın hane sayısından TAHMİN ediliyordu
  /// (10 hane → e-Fatura, 11 hane → e-Arşiv). İkisi de yanlış olabilir: VKN'si
  /// olan birçok firma e-Fatura mükellefi değildir, TC ile kayıtlı şahıs
  /// şirketleri ise e-Fatura mükellefi olabilir. Cari Listesi zaten gerçek
  /// sonucu kullanıyordu; iki ekran çelişiyordu. Sorgulanmamışsa "bilinmiyor"
  /// yazılır ve buradan GİB'e sorulabilir.
  Widget _eFaturaRozeti(CariModel c) {
    final numara = (c.vergiNo?.trim().isNotEmpty ?? false) ? c.vergiNo!.trim() : c.tcKimlik?.trim();
    if (numara == null || numara.isEmpty) return const SizedBox.shrink();

    final (String etiket, IconData ikon, Color renk, String aciklama) = switch (c.mukellefDurumu) {
      'efatura' => ('e-Fatura mükellefi', Icons.verified_outlined, const Color(0xFF2E7D32),
          'GİB e-Fatura kayıtlı kullanıcı listesinde bulundu — faturası e-Fatura olarak kesilir.'),
      'earsiv' => ('e-Arşiv', Icons.receipt_long_outlined, const Color(0xFF1565C0),
          'GİB e-Fatura listesinde kayıtlı değil — faturası e-Arşiv olarak kesilir.'),
      _ => ('Mükellefiyet bilinmiyor · Sorgula', Icons.help_outline, TsRenk.metinIkincil(context),
          'Bu carinin e-Fatura mükellefi olup olmadığı henüz GİB\'den sorgulanmadı. '
          'Sorgulamak için dokunun.'),
    };
    final sorgu = c.mukellefSorguTarihi == null
        ? ''
        : '\nSon sorgu: ${DateTime.tryParse(c.mukellefSorguTarihi!)?.toLocal().toString().substring(0, 16) ?? c.mukellefSorguTarihi}';
    return Tooltip(
      message: '$aciklama$sorgu',
      child: InkWell(
        onTap: _mukellefSorguluyor ? null : () => _mukellefSorgula(c, numara),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: renk.withAlpha(28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: renk.withAlpha(90)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _mukellefSorguluyor
                ? SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: renk))
                : Icon(ikon, size: 13, color: renk),
            const SizedBox(width: 3),
            Text(etiket, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: renk)),
          ]),
        ),
      ),
    );
  }

  /// GİB (entegratör) üzerinden e-Fatura mükellefiyetini sorgular ve sonucu
  /// cariye kaydeder. Entegratör ayarlı değilse açıkça söyler — tahmin YAPMAZ.
  Future<void> _mukellefSorgula(CariModel c, String numara) async {
    if (c.id == null) return;
    setState(() => _mukellefSorguluyor = true);
    try {
      final gib = GibServisi();
      await gib.ayarlariYukle();
      if (!gib.ayarliMi) {
        if (mounted) {
          BildirimServisi.uyari(context,
              'GİB sorgusu için önce Ayarlar > GİB E-Fatura\'da entegratör bilgilerini girin.');
        }
        return;
      }
      final sonuc = await gib.mukellefSorgula(numara);
      if (!mounted) return;
      if (sonuc == null) {
        BildirimServisi.uyari(context, 'GİB\'den yanıt alınamadı — daha sonra tekrar deneyin.');
        return;
      }
      await CariDeposu().mukellefDurumuGuncelle(c.id!, sonuc);
      ref.invalidate(cariDetayProvider(c.id!));
      ref.invalidate(carilerProvider);
      if (mounted) {
        BildirimServisi.basari(context,
            sonuc == 'efatura' ? 'e-Fatura mükellefi ✓' : 'e-Fatura listesinde yok — e-Arşiv kesilir');
      }
    } finally {
      if (mounted) setState(() => _mukellefSorguluyor = false);
    }
  }

  Widget _bilgiTab(BuildContext ctx, CariModel c) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // Bakiye kartı
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_bakiyeRenk, Color.fromARGB(178, _bakiyeRenk.red, _bakiyeRenk.green, _bakiyeRenk.blue)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
              color: Color.fromARGB(76, _bakiyeRenk.red, _bakiyeRenk.green, _bakiyeRenk.blue), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Column(children: [
          Text(_bakiyeEtiket, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 4),
          Text(ParaUtils.formatla(c.bakiye.abs()),
              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
        ]),
      ),
      const SizedBox(height: 16),
      _Kart(children: [
        _Satir('Cari Tipi', c.cariTipi),
        if (c.cariKodu != null) _Satir('Cari Kodu', c.cariKodu!),
        if (c.telefon != null) _Satir('Telefon', c.telefon!),
        if (c.email != null) _Satir('E-Posta', c.email!),

        if (c.vergiNo != null) _Satir('Vergi No', c.vergiNo!),
        if (c.tcKimlik != null) _Satir('TC Kimlik No', c.tcKimlik!),
        if (c.vergiDairesi != null) _Satir('Vergi Dairesi', c.vergiDairesi!),
        if (c.limitTutari > 0)
          _Satir('Kredi Limiti', ParaUtils.formatla(c.limitTutari)),
      ]),
      const SizedBox(height: 80),
    ],
  );

  Widget _hareketTab() {
    if (_yukl) return const Center(child: const AppYukleniyor());
    if (_hareketler.isEmpty) return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_outlined, size: 48, color: context.textSecondary),
        const SizedBox(height: 8),
        Text('Hareket yok', style: TextStyle(color: context.textSecondary)),
      ]));
    return RefreshIndicator(
      onRefresh: _hareketYukle,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _hareketler.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final h = _hareketler[i];
          final borc = (h.borc);
          final alacak = (h.alacak);
          final giris = alacak > 0;
          final satisMi = h.fisTipi == 'Satış' && h.fisId != null;

          // 🔴 DÜZELTME (kullanıcı bulgusu — "hangi ürün olduğu belli
          // mi artık"): Toptan satış / bekleyen sipariş onayı / masa
          // satışı hareketlerine dokununca HİÇBİR ŞEY olmuyordu —
          // `onTap` sadece BİREBİR 'Satış' fisTipi'nde tetikleniyordu.
          // Kullanıcı hangi ürünlerin satıldığını göremiyordu.
          //
          // 'Satış' fisTipi'nin mevcut davranışına (dokununca doğrudan
          // faturalandırma akışını başlatması) DOKUNULMADI — bu turun
          // kapsamı sadece eksik olan görüntüleme yolu.
          final detayGorulebilirMi = h.fisId != null && !satisMi && (
              h.fisTipi == 'Toptan Satış' ||
              h.fisTipi == 'Toptan Satış (Sipariş)' ||
              h.fisTipi == 'Masa Satış');
          final yazdirilabilir = _CariDetayIcerikState._yazdirilabilirTipler.contains(h.fisTipi);
          final secili = _seciliHareket == h;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12),
              border: secili ? Border.all(color: AppRenkler.primary, width: 2) : null,
              boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: satisMi
                  ? () => _hareketFaturalandir(h)
                  : detayGorulebilirMi
                      ? () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => FisDetayEkrani(
                            fisId: h.fisId!,
                            fisTipi: h.fisTipi,
                            cariUnvan: widget.cari.unvan,
                          ),
                        ))
                      : null,
              // 🆕 Uzun bas → seç (hızlı satıştaki manuel yazdırma
              // butonuyla aynı fikir): sadece gerçek bir belgesi olan
              // tipler (Satış/Toptan Satış/Tahsilat/Odeme) seçilebilir.
              onLongPress: !yazdirilabilir
                  ? () => BildirimServisi.hata(context, 'Bu hareket türü yazdırılamaz')
                  : () => setState(() => _seciliHareket = secili ? null : h),
              child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (giris ? Colors.green : Colors.red).withAlpha(26),
                  shape: BoxShape.circle),
                child: Icon(
                  giris ? Icons.add : Icons.remove,
                  color: giris ? Colors.green : Colors.red, size: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.fisTipi, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                Text(h.aciklama, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                Text(_fmt.format(h.tarih), style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (borc > 0) Text('+${ParaUtils.formatla(borc)}',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 13)),
                if (alacak > 0) Text('+${ParaUtils.formatla(alacak)}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              if (satisMi) ...[
                const SizedBox(width: 6),
                Icon(Icons.receipt_long_outlined, size: 18, color: TsRenk.metinIkincil(context)),
              ],
              // 🆕 Doğrudan görünür yazdır ikonu (kullanıcı isteği,
              // 2026-09-22 sabah): uzun-basıp-seçme gizli bir jest olduğu
              // için keşfedilmiyordu — artık her yazdırılabilir satırda
              // tek dokunuşla doğrudan yazdırma var, uzun-bas+seç akışı
              // (çoklu satırdan hızlı seçim için) AYNEN korunuyor.
              if (yazdirilabilir) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: _yazdiriliyor && secili
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.print_outlined, size: 18, color: AppRenkler.primary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Yazdır',
                  onPressed: _yazdiriliyor
                      ? null
                      : () {
                          setState(() => _seciliHareket = h);
                          _seciliYazdir(h);
                        },
                ),
              ],
            ]),
            ),
          );
        },
      ),
    );
  }

  Widget _analizTab(BuildContext ctx, CariModel c) {
    if (!c.cariTipi.contains('Müşteri')) {
      return Center(
        child: Text('360° analiz şu an sadece müşteriler için hesaplanıyor',
            style: TextStyle(color: context.textSecondary)),
      );
    }
    if (_analizYukl) return const Center(child: AppYukleniyor());
    final istat = _istatistik;
    if (istat == null || istat.islemSayisi == 0) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.insights_outlined, size: 48, color: context.textSecondary),
          const SizedBox(height: 8),
          Text('Henüz satış geçmişi yok', style: TextStyle(color: context.textSecondary)),
        ]),
      );
    }
    final riskOrani = c.limitTutari > 0 ? (c.bakiye / c.limitTutari) : 0.0;
    return RefreshIndicator(
      onRefresh: _analizYukle,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_segment != null) _segmentRozeti(ctx, _segment!),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'Toplam Ciro',
                    deger: ParaUtils.formatla(istat.toplamCiro),
                    ikon: const Icon(Icons.payments_outlined),
                    vurguRenk: TsRenk.basarili)),
            const SizedBox(width: 12),
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'İşlem Sayısı',
                    deger: '${istat.islemSayisi}',
                    ikon: const Icon(Icons.receipt_long_outlined))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'Ortalama Sepet',
                    deger: ParaUtils.formatla(istat.ortalamaSepet),
                    ikon: const Icon(Icons.shopping_cart_outlined))),
            const SizedBox(width: 12),
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'Alışveriş Sıklığı',
                    deger: istat.ortalamaGunAraligi == null
                        ? '—'
                        : '${istat.ortalamaGunAraligi!.round()} günde bir',
                    ikon: const Icon(Icons.event_repeat_outlined))),
          ]),
          if (c.limitTutari > 0) ...[
            const SizedBox(height: 12),
            _Kart(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Risk Limiti Kullanımı',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary)),
                      const Spacer(),
                      Text('%${(riskOrani * 100).clamp(0, 999).toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: riskOrani >= 0.9
                                  ? TsRenk.hata
                                  : riskOrani >= 0.6
                                      ? TsRenk.uyari
                                      : TsRenk.basarili)),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                          value: riskOrani.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: TsRenk.ayirac(ctx),
                          color: riskOrani >= 0.9
                              ? TsRenk.hata
                              : riskOrani >= 0.6
                                  ? TsRenk.uyari
                                  : TsRenk.basarili),
                    ),
                  ],
                ),
              ),
            ]),
          ],
          if (istat.enCokAlinanUrunler.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('En Çok Alınan Ürünler',
                style: TsMetin.baslikM.copyWith(color: TsRenk.metinBirincil(ctx))),
            const SizedBox(height: 8),
            ...istat.enCokAlinanUrunler.map((u) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TsKart.liste(
                    baslik: u.urunAdi,
                    altBaslik: '${_miktarStr(u.miktar)} adet/birim',
                    deger: ParaUtils.formatla(u.tutar),
                  ),
                )),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String _miktarStr(double m) =>
      m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(2);

  Widget _segmentRozeti(BuildContext ctx, MusteriSegmenti s) {
    final (renk, ikon) = switch (s) {
      MusteriSegmenti.vip => (TsRenk.accent, Icons.workspace_premium_outlined),
      MusteriSegmenti.sadik => (TsRenk.basarili, Icons.favorite_outline),
      MusteriSegmenti.riskli => (TsRenk.hata, Icons.warning_amber_outlined),
      MusteriSegmenti.kaybedilmekUzere => (TsRenk.uyari, Icons.trending_down_outlined),
      MusteriSegmenti.yeni => (TsRenk.bilgi, Icons.fiber_new_outlined),
      MusteriSegmenti.standart => (TsRenk.notr, Icons.person_outline),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TsRenk.zemin(renk),
        borderRadius: BorderRadius.circular(TsRadius.lg),
        border: Border.all(color: TsRenk.zemin(renk, opaklik: 0.4)),
      ),
      child: Row(children: [
        Icon(ikon, color: renk, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Müşteri Segmenti',
                  style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(ctx))),
              Text(s.etiket,
                  style: TsMetin.baslikL.copyWith(color: renk)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Kart extends StatelessWidget {
  final List<Widget> children;
  const _Kart({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 6)]),
    child: Column(children: children),
  );
}

class _Satir extends StatelessWidget {
  final String etiket, deger;
  const _Satir(this.etiket, this.deger);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.borderColor))),
    child: Row(children: [
      Text(etiket, style: TextStyle(fontSize: 13, color: context.textSecondary)),
      const Spacer(),
      Flexible(child: Text(deger,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          textAlign: TextAlign.right)),
    ]),
  );
}
