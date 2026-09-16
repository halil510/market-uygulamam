// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: Bu dosya `part of 'iade_ekrani.dart'` ve içeriği
// `extension ... on _IadeEkraniState` olarak yazılmış. Bu desen 3000
// satırlık iade ekranını okunabilir parçalara bölmek için bilinçli
// seçilmiş ve ÇALIŞIYOR — `setState` gerçekten kendi State sınıfının
// üzerinde çağrılıyor.
//
// Ama Dart analizcisi `setState`'i @protected gördüğü için, extension
// içinden çağrıyı "korumalı üyeye dışarıdan erişim" sayıyor. Derlemeyi
// engellemez; sadece analiz uyarısıdır.
//
// (analysis_options.yaml'da bu kural bilinçli olarak `error` seviyesine
// çıkarıldı — başka yerlerde gerçek hataları yakalasın diye. Burada
// dosya bazında muaf tutuluyor.)
// lib/ekranlar/satis/iade_ekrani_gecmis.dart
//
// "Geçmiş" (İade Geçmişi) sekmesinin TÜM mantığı buraya taşındı —
// iade_ekrani.dart'ın 2273 satırlık, tek dosyada aşırı büyümüş
// yapısını daha yönetilebilir hale getirmek için. Bu, Dart'ın
// part/part of mekanizmasıyla yapıldı: bu dosya, iade_ekrani.dart ile
// AYNI "kütüphane" kapsamındadır — hiçbir mantık/davranış DEĞİŞMEDİ,
// sadece kod organizasyonu değişti. TabBar/TabBarView yapısı,
// kullanıcı deneyimi (navigasyon) AYNEN korundu — kullanıcı hiçbir
// fark görmeyecek, sadece kod artık daha kolay bakım yapılabilir.
part of 'iade_ekrani.dart';

extension _GecmisTabExt on _IadeEkraniState {
  Widget _gecmisTab() {
    return Column(children: [
      // Filtreler
      Container(
        padding: const EdgeInsets.all(12),
        color: _R.bg(context),
        child: Column(children: [
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                _gecmisTarihBaslangic == null ? 'Başlangıç Tarihi'
                    : DateFormat('dd.MM.yy').format(_gecmisTarihBaslangic!),
                style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _gecmisTarihBaslangic ?? DateTime.now(),
                    firstDate: DateTime(2020), lastDate: DateTime.now());
                if (!mounted) return;
                if (d != null) { setState(() => _gecmisTarihBaslangic = d); _gecmisYukle(); }
              },
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month, size: 16),
              label: Text(
                _gecmisTarihBitis == null ? 'Bitiş Tarihi'
                    : DateFormat('dd.MM.yy').format(_gecmisTarihBitis!),
                style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _gecmisTarihBitis ?? DateTime.now(),
                    firstDate: DateTime(2020), lastDate: DateTime.now());
                if (!mounted) return;
                if (d != null) { setState(() => _gecmisTarihBitis = d); _gecmisYukle(); }
              },
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.person_search, size: 16),
              label: Text(_gecmisCariFiltre?.unvan ?? 'Müşteri Filtre',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final secilen = await showDialog<CariModel>(
                    context: context,
                    builder: (bCtx) => CariSecDialog(cariler: _cariler));
                if (!mounted) return;
                if (secilen != null) { setState(() => _gecmisCariFiltre = secilen); _gecmisYukle(); }
              },
            )),
            const SizedBox(width: 8),
            if (_gecmisTarihBaslangic != null || _gecmisCariFiltre != null)
              OutlinedButton(
                onPressed: () {
                  setState(() { _gecmisTarihBaslangic = null; _gecmisTarihBitis = null; _gecmisCariFiltre = null; });
                  _gecmisYukle();
                },
                child: const Text('Temizle', style: TextStyle(fontSize: 12)),
              ),
            IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _gecmisYukle),
          ]),
        ]),
      ),
      // Liste
      Expanded(
        child: _gecmisYukleniyor
            ? const TsYukleniyor()
            : _gecmisIadeler.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.assignment_return, size: 56, color: TsRenk.ayirac(context)),
                    const SizedBox(height: 12),
                    Text('İade bulunamadı', style: TextStyle(color: context.textSecondary)),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _gecmisIadeler.length,
                    itemBuilder: (_, i) {
                      final r = _gecmisIadeler[i];
                      final tarih = DateTime.tryParse(r['tarih']?.toString() ?? '');
                      return Dismissible(
                        key: ValueKey('gecmis_${r['id']}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            borderRadius: BorderRadius.circular(12)),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.delete_outline, color: Colors.white, size: 26),
                            Text('Sil', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ]),
                        ),
                        confirmDismiss: (_) async {
                          final onay = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: const Text('Fisi Sil'),
                              content: Text('${r['fis_no'] ?? 'Bu iade'} silinsin mi?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayir')),
                                FilledButton(
                                  style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Sil'),
                                ),
                              ],
                            ),
                          );
                          return onay == true;
                        },
                        onDismissed: (_) => _gecmisIadeSil(r),
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))),
                        child: ListTile(
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.assignment_return, color: Colors.orange, size: 22),
                          ),
                          title: Text(
                            r['fis_no']?.toString() ?? 'İade #${r['id']}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (r['cari_adi'] != null)
                              Text(r['cari_adi'].toString(),
                                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                            if (tarih != null)
                              Text(DateFormat('dd.MM.yyyy HH:mm').format(tarih),
                                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                          ]),
                          trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(ParaUtils.formatla((r['toplam_tutar'] as num?)?.toDouble() ?? 0),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.orange)),
                            Text('${r['kalem_sayisi'] ?? 0} kalem',
                                style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
                          ]),
                          onTap: () => _gecmisIadeDetay(r),
                        ),
                      )); // Card + Dismissible
                    },
                  ),
      ),
    ]);
  }

  // ── Oturum iade silme onayı ─────────────────────────────────────────────
  Future<bool> _oturumIadeSilOnay(Map<String, dynamic> iade) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 8),
          Text('İadeyi Sil'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${iade['urun_adi']} iadesi silinecek.'),
          const SizedBox(height: 8),
          const Text('- Stok geri alinacak\n- Kasa ve cari duzeltilecek',
              style: TextStyle(color: Colors.red, fontSize: 12, height: 1.5)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    return onay == true;
  }

  // ── Oturum iade sil ──────────────────────────────────────────────────────
  Future<void> _oturumIadeSil(int idx, Map<String, dynamic> iade) async {
    try {
      final iadeId  = iade['iade_id'] as int?;
      final urunId  = iade['urun_id'] as int?;
      final miktar  = (iade['miktar'] as double?) ?? 0;
      final toplam  = (iade['toplam_tutar'] as double?) ?? 0;
      final cariId  = iade['cari_id'] as int?;

      // Tüm transaction + bulut senkron mantığı artık
      // IadeIslemServisi.oturumIadeSil'de — bkz. o metodun doc yorumu,
      // davranış birebir korundu.
      await IadeIslemServisi().oturumIadeSil(
        iadeId: iadeId,
        urunId: urunId,
        miktar: miktar,
        toplam: toplam,
        cariId: cariId,
        fisNo: iade['fis_no']?.toString(),
      );

      if (!mounted) return;
      setState(() {
        _iadeListesi.removeAt(idx);
        // Eğer silinen iade oturum iadeiyse oturum ID'yi sıfırla
        if (iade['iade_id'] == _oturumIadeId) {
          _oturumIadeId = null;
        }
      });
      _msg('Iade silindi', err: false);
    } catch (e) {
      if (mounted) {
        setState(() {});
        _msg('Hata: $e', err: true);
      }
    }
  }

  // ── Oturum iade düzenleme ────────────────────────────────────────────────
  Future<void> _oturumIadeDuzenle(int idx, Map<String, dynamic> iade) async {
    final miktarCtrl  = TextEditingController(text: (iade['miktar'] as double).toStringAsFixed(0));
    final fiyatCtrl   = TextEditingController(text: (iade['birim_fiyat'] as double).toStringAsFixed(2));
    final iskCtrl     = TextEditingController(text: (iade['iskonto_oran'] as double? ?? 0).toStringAsFixed(0));
    final aciklamaCtrl = TextEditingController(text: iade['aciklama']?.toString() ?? '');

    double hesaplaToplam() {
      final m   = ParaUtils.sayiCoz(miktarCtrl.text) ?? 0;
      final f   = ParaUtils.sayiCoz(fiyatCtrl.text) ?? 0;
      final isk = ParaUtils.sayiCoz(iskCtrl.text) ?? 0;
      return m * f * (1 - isk / 100);
    }

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          
          title: Text('İade Düzenle — ${iade['urun_adi']}',
              style: const TextStyle(fontSize: 15)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Miktar
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Miktar', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                const SizedBox(height: 4),
                TextField(
                  controller: miktarCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(), isDense: true,
                    suffixText: 'adet'),
                  onChanged: (_) => ss(() {}),
                ),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Birim Fiyat', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                const SizedBox(height: 4),
                TextField(
                  controller: fiyatCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(), isDense: true,
                    suffixText: 'TL'),
                  onChanged: (_) => ss(() {}),
                ),
              ])),
            ]),
            const SizedBox(height: 12),
            // İskonto
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('İskonto %', style: TextStyle(fontSize: 12, color: context.textSecondary)),
              const SizedBox(height: 4),
              TextField(
                controller: iskCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true,
                  suffixText: '%'),
                onChanged: (_) => ss(() {}),
              ),
            ]),
            const SizedBox(height: 12),
            // Açıklama
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Açıklama/Neden', style: TextStyle(fontSize: 12, color: context.textSecondary)),
              const SizedBox(height: 4),
              TextField(
                controller: aciklamaCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true,
                  hintText: 'İade nedeni...'),
              ),
            ]),
            const SizedBox(height: 12),
            // Toplam önizleme
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Toplam:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(ParaUtils.formatla(hesaplaToplam()),
                      style: const TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 16, color: Colors.green)),
                ],
              ),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            FilledButton.icon(
              icon: const Icon(Icons.save, size: 16, color: Colors.white),
              label: const Text('Kaydet'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    // Değerleri dispose'dan ÖNCE oku
    final yeniMiktarStr = miktarCtrl.text;
    final yeniFiyatStr  = fiyatCtrl.text;
    final yeniIskStr    = iskCtrl.text;
    final yeniAciklama  = aciklamaCtrl.text.trim();

    miktarCtrl.dispose(); fiyatCtrl.dispose();
    iskCtrl.dispose(); aciklamaCtrl.dispose();

    if (onay != true || !mounted) return;

    try {
      final yeniMiktar  = double.tryParse(yeniMiktarStr) ?? (iade['miktar'] as double);
      final yeniFiyat   = double.tryParse(yeniFiyatStr)  ?? (iade['birim_fiyat'] as double);
      final yeniIsk     = double.tryParse(yeniIskStr)    ?? 0.0;
      final yeniToplam  = yeniMiktar * yeniFiyat * (1 - yeniIsk / 100);
      final eskiMiktar  = iade['miktar'] as double;
      final eskiToplam  = iade['toplam_tutar'] as double;
      final iadeId      = iade['iade_id'] as int?;
      final urunId      = iade['urun_id'] as int?;
      final cariId      = iade['cari_id'] as int?;

      // Tüm transaction + bulut senkron mantığı artık
      // IadeIslemServisi.oturumIadeDuzenle'de — bkz. o metodun doc
      // yorumu, davranış birebir korundu.
      await IadeIslemServisi().oturumIadeDuzenle(
        iadeId: iadeId,
        urunId: urunId,
        cariId: cariId,
        fisNo: iade['fis_no']?.toString(),
        urunAdi: iade['urun_adi']?.toString() ?? '',
        eskiMiktar: eskiMiktar,
        eskiToplam: eskiToplam,
        yeniMiktar: yeniMiktar,
        yeniFiyat: yeniFiyat,
        yeniToplam: yeniToplam,
        yeniAciklama: yeniAciklama,
      );

      if (!mounted) return;
      setState(() {
        _iadeListesi[idx] = {
          ..._iadeListesi[idx],
          'miktar': yeniMiktar,
          'birim_fiyat': yeniFiyat,
          'iskonto_oran': yeniIsk,
          'toplam_tutar': yeniToplam,
          'aciklama': yeniAciklama,
        };
      });
      _msg('İade güncellendi ✓', err: false);
    } catch (e) {
      if (mounted) _msg('Hata: $e', err: true);
    }
  }

  // ── Geçmiş iadeyi düzenleme moduna al ───────────────────────────────────
  // ── Düzenleme modunda mevcut iadeye kalem ekle ───────────────────────────
  Future<void> _duzenlemeModu_kalemEkle(
    double fiyat, double iskontoOran, double iskontoTutar,
    double netFiyat, double toplam) async {

    if (!mounted) return;
    setState(() => _yukleniyor = true);

    try {
      final iadeId = _duzenlemeModu_iadeId!;

      // Tüm transaction + bulut senkron mantığı artık
      // IadeIslemServisi.duzenlemeModuKalemEkle'de — bkz. o metodun doc
      // yorumu, davranış birebir korundu.
      await IadeIslemServisi().duzenlemeModuKalemEkle(
        iadeId: iadeId,
        urunId: _secilenUrun!.id!,
        urunAdi: _secilenUrun!.urunAdi,
        miktar: _miktar,
        fiyat: fiyat,
        toplam: toplam,
        fisNo: _duzenlemeModu_fisNo,
        cariId: _secilenCari?.id,
        cariTipi: _secilenCari?.cariTipi,
        kullaniciId: AuthServisi().aktifId,
        kullaniciAdi: AuthServisi().aktifAd,
      );

      // 6. Lokal listeye ekle
      if (!mounted) return;
      setState(() {
        _iadeListesi.insert(0, {
          'iade_id':      iadeId,
          'urun_id':      _secilenUrun!.id,
          'tarih':        DateTime.now(),
          'urun_adi':     _secilenUrun!.urunAdi,
          'barkod':       _secilenUrun!.barkod ?? '',
          'miktar':       _miktar,
          'birim_fiyat':  fiyat,
          'iskonto_oran': iskontoOran,
          'iskonto_tutar': iskontoTutar,
          'toplam_tutar': toplam,
          'musteri_adi':  _secilenCari?.unvan ?? 'Perakende',
          'cari_id':      _secilenCari?.id,
          'aciklama':     _aciklamaCtrl.text.trim(),
          'fis_no':       _duzenlemeModu_fisNo ?? '',
        });
      });

      // 7. Lokal stok güncelle
      final idx = _tumUrunler.indexWhere((u) => u.id == _secilenUrun!.id);
      if (idx != -1) {
        _tumUrunler[idx] = _tumUrunler[idx].copyWith(
            stok: _tumUrunler[idx].stok + _miktar);
      }
      // Cari/Kasa bakiyeleri değişti — başka ekranlarda eski veri kalmasın.
      if (_secilenCari != null) {
        ref.invalidate(cariDetayProvider(_secilenCari!.id!));
        ref.read(carilerProvider.notifier).yukle();
      }
      ref.invalidate(kasaRaporProvider);

      _msg('${_secilenUrun!.urunAdi} → ${_duzenlemeModu_fisNo} fişine eklendi ✓', err: false);
      _formSifirla();
    } catch (e) {
      _msg('Hata: $e', err: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _gecmisIadeyiDevamEt(Map<String, dynamic> iade) async {
    final iadeId = iade['id'] as int?;
    if (iadeId == null) return;

    // DB'den kalemleri çek
    final db     = await Veritabani().db;
    final kalemler = await db.rawQuery(
      'SELECT * FROM iade_kalem WHERE iade_id = ?', [iadeId]);

    // Cari bul
    CariModel? cari;
    final cariId = iade['cari_id'];
    if (cariId != null) {
      cari = _cariler.firstWhere(
        (c) => c.id == cariId,
        orElse: () => CariModel(id: cariId, unvan: iade['cari_adi']?.toString() ?? '-', bakiye: 0),
      );
    }

    if (!mounted) return;

    // Onay al
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: Row(children: const [
          Icon(Icons.edit_note, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text('İadeyi Düzenle', style: TextStyle(fontSize: 16))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Fiş: ${iade['fis_no'] ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              if (cari != null)
                Text('Cari: ${cari.unvan}',
                    style: TextStyle(fontSize: 12, color: context.textSecondary)),
              Text('Tutar: ${ParaUtils.formatla((iade['toplam_tutar'] as num?)?.toDouble() ?? 0)}',
                  style: const TextStyle(fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 10),
          Text(
            'Bu iade fise eklenecek. Yeni urun secip kaydedebilirsiniz.',
            style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context), height: 1.5),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton.icon(
            icon: const Icon(Icons.edit, size: 16, color: Colors.white),
            label: const Text('Düzenlemeye Geç'),
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (onay != true || !mounted) return;

    // İade sekmesine geç ve düzenleme modunu aç
    setState(() {
      _duzenlemeModu_iadeId  = iadeId;
      _duzenlemeModu_fisNo   = iade['fis_no']?.toString();
      _duzenlemeModu_cari    = cari;
      _secilenCari           = cari;
      _oturumIadeId          = iadeId;        // Devam modunda oturum ID set et
      _oturumFisNo           = iade['fis_no']?.toString() ?? '';

      // Mevcut kalemleri listeye yükle
      _iadeListesi.clear();
      for (final k in kalemler) {
        final miktar    = (k['miktar'] as num?)?.toDouble() ?? 0;
        final birimFiyat = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
        _iadeListesi.add({
          'iade_id':      iadeId,
          'kalem_id':     k['id'],
          'urun_id':      k['urun_id'],
          'tarih':        DateTime.now(),
          'urun_adi':     k['urun_adi'],
          'barkod':       '',
          'miktar':       miktar,
          'birim_fiyat':  birimFiyat,
          'iskonto_oran': 0.0,
          'iskonto_tutar': 0.0,
          'toplam_tutar': (k['toplam'] as num?)?.toDouble() ?? miktar * birimFiyat,
          'musteri_adi':  cari?.unvan ?? 'Perakende',
          'cari_id':      cariId,
          'aciklama':     iade['iade_nedeni']?.toString() ?? '',
          'fis_no':       iade['fis_no']?.toString() ?? '',
          'mevcut_kalem': true,  // DB kayitli kalem
        });
      }
    });

    // İade sekmesine git
    _gecmisYukle(); // Geçmişi güncelle
    _tab.animateTo(0);
    _msg('Düzenleme modu: ${iade['fis_no']} — Yeni ürün ekleyebilirsiniz', err: false);
  }

  Future<void> _gecmisIadeSil(Map<String, dynamic> iade) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 8),
          Text('Fişi Sil'),
        ]),
        content: Text('${iade['fis_no'] ?? 'Bu iade'} silinecek.\nStok, kasa ve cari kayıtları geri alınacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    try {
      final db      = await Veritabani().db;
      final iadeId  = iade['id'] as int?;
      if (iadeId == null) return;

      final kalemler = await db.query('iade_kalem', where: 'iade_id = ?', whereArgs: [iadeId]);

      // Tüm transaction + bulut senkron mantığı artık
      // IadeIslemServisi.gecmisFisIadeSil'de — bkz. o metodun doc
      // yorumu, davranış birebir korundu.
      await IadeIslemServisi().gecmisFisIadeSil(
        iadeId: iadeId,
        kalemler: kalemler,
        toplamTutar: (iade['toplam_tutar'] as num?)?.toDouble() ?? 0,
        cariId: iade['cari_id'] as int?,
        fisNo: iade['fis_no']?.toString(),
      );

      _gecmisYukle();
      if (mounted) _msg('Fis silindi: ${iade['fis_no']}', err: false);
    } catch (e) {
      if (mounted) _msg('Hata: $e', err: true);
    }
  }

  Future<void> _gecmisYukle() async {
    if (!mounted) return;
    _gecmisYukleniyor = true;
    if (mounted) setState(() {});
    try {
      final db = await Veritabani().db;
      String where = '1=1';
      List<dynamic> args = [];
      if (_gecmisTarihBaslangic != null) {
        where += ' AND ia.tarih >= ?';
        args.add(_gecmisTarihBaslangic!.toIso8601String());
      }
      if (_gecmisTarihBitis != null) {
        where += ' AND ia.tarih <= ?';
        final bitis = _gecmisTarihBitis!.add(const Duration(days: 1));
        args.add(bitis.toIso8601String());
      }
      if (_gecmisCariFiltre != null) {
        where += ' AND ia.cari_id = ?';
        args.add(_gecmisCariFiltre!.id);
      }
      final rows = await db.rawQuery('''
        SELECT ia.*,
          c.unvan as cari_adi,
          (SELECT COUNT(*) FROM iade_kalem WHERE iade_id = ia.id) as kalem_sayisi
        FROM iade ia
        LEFT JOIN cari c ON ia.cari_id = c.id
        WHERE ia.durum != 'iptal' AND $where
        ORDER BY ia.tarih DESC
        LIMIT 100
      ''', args);
      if (!mounted) return;
      _gecmisIadeler = rows;
      _gecmisYukleniyor = false;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) { _gecmisYukleniyor = false; setState(() {}); }
    }
  }

  Future<void> _iadeyiFaturalandir(
      Map<String, dynamic> iade, List<Map<String, dynamic>> kalemler) async {
    final cariId = iade['cari_id'] as int?;
    if (cariId == null) {
      _msg('Bu iadede cari secilmemis. Faturalandirma icin once carisini secmelisiniz.', err: true);
      return;
    }
    if (kalemler.isEmpty) {
      _msg('Faturalandirilacak kalem bulunamadi.', err: true);
      return;
    }

    setState(() => _yukleniyor = true);
    try {
      // Bu iade için daha önce fatura kesildiyse tekrar oluşturma
      final mevcutId = await FaturalandirmaServisi.mevcutFaturaId(iadeId: iade['id'] as int?);
      if (mevcutId != null) {
        if (!mounted) return;
        _msg('Bu iade için zaten bir fatura mevcut, ona yönlendiriliyorsunuz.', err: false);
        context.push('/fatura/detay/$mevcutId');
        return;
      }

      final kontrol = await FaturalandirmaServisi.kontrolEt(cariId);
      if (kontrol == null) {
        if (mounted) _msg('Cari bulunamadi.', err: true);
        return;
      }

      if (!kontrol.hazir) {
        if (!mounted) return;
        final git = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${kontrol.cari.unvan.isEmpty ? 'Bu cari' : kontrol.cari.unvan} icin "
                  "fatura kesilebilmesi icin asagidaki bilgiler eksik:"),
              const SizedBox(height: 10),
              ...kontrol.eksikAlanlar.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(e),
                    ]),
                  )),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgec')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cari Duzenle')),
            ],
          ),
        );
        if (git == true && mounted) {
          await context.push('/cari/ekle', extra: kontrol.cari);
        }
        return;
      }

      final detaylar = kalemler.map((k) {
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        final birimFiyat = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
        final araToplam = miktar * birimFiyat;
        // Ürünün gerçek KDV oranı kullanılır (urunler.kdv_oran); bulunamazsa %20 varsayılır.
        final kdvOran = (k['urun_kdv_oran'] as num?)?.toDouble() ?? 20.0;
        final kdvTutar = araToplam * kdvOran / (100 + kdvOran);
        // 🔴 DÜZELTME (Madde 21 — GİB/fatura araToplam bulgusu devamı,
        // 2026-09-16): araToplam (yerel değişken, satır 764) KDV DAHİL
        // (brüt) — kdvTutar burada zaten DOĞRU (bölme ile eşdeğer)
        // formülle ayıklanmıştı, ama FaturaDetayModel.araToplam alanına
        // brüt değer YAZILIYORDU; bu alan NET (matrah) olmalı (bkz.
        // satis_detay_ekrani.dart'taki aynı düzeltme). toplamTutar zaten
        // doğru (brüt).
        return FaturaDetayModel(
          urunId: k['urun_id'] as int?,
          urunAdi: (k['urun_adi'] ?? k['urun_adi_db'] ?? '-').toString(),
          miktar: miktar,
          birimFiyat: birimFiyat,
          kdvOrani: kdvOran,
          kdvTutari: kdvTutar,
          araToplam: araToplam - kdvTutar,
          toplamTutar: araToplam,
        );
      }).toList();

      final tarih = DateTime.tryParse(iade['tarih']?.toString() ?? '') ?? DateTime.now();
      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol,
        kalemler: detaylar,
        faturaTipi: 'Iade',
        iadeId: iade['id'] as int?,
        tarih: tarih,
      );

      if (!mounted) return;
      _msg('Iade faturasi olusturuldu', err: false);
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) _msg('Faturalandirma hatasi: $e', err: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _gecmisIadeDetay(Map<String, dynamic> iade) async {
    final db = await Veritabani().db;
    final kalemler = await db.rawQuery('''
      SELECT ik.*, u.urun_adi as urun_adi_db, u.kdv_oran as urun_kdv_oran
      FROM iade_kalem ik
      LEFT JOIN urunler u ON ik.urun_id = u.id
      WHERE ik.iade_id = ?
    ''', [iade['id']]);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('İade #${iade['fis_no'] ?? iade['id']}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.orange),
            tooltip: 'Düzelt',
            onPressed: () {
              Navigator.pop(ctx);
              _gecmisIadeyiDevamEt(iade);
            },
          ),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (iade['cari_adi'] != null)
              ListTile(dense: true, leading: const Icon(Icons.person, size: 18, color: AppRenkler.primary),
                  title: Text(iade['cari_adi'].toString())),
            const Divider(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: kalemler.length,
                itemBuilder: (_, i) {
                  final k = kalemler[i];
                  final m = (k['miktar'] as num?)?.toDouble() ?? 0;
                  final bf = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
                  return ListTile(dense: true,
                    title: Text(k['urun_adi']?.toString() ?? k['urun_adi_db']?.toString() ?? '-',
                        style: const TextStyle(fontSize: 13)),
                    trailing: Text('${m.toStringAsFixed(m%1==0?0:2)} × ${ParaUtils.formatla(bf)}',
                        style: const TextStyle(fontSize: 12)),
                  );
                },
              ),
            ),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('TOPLAM', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(ParaUtils.formatla((iade['toplam_tutar'] as num?)?.toDouble() ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)),
            ]),
          ]),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await _gecmisIadeSil(iade);
            },
            child: const Text('Fişi Sil'),
          ),
          if (iade['cari_id'] != null)
            TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Faturalandır'),
              onPressed: () {
                Navigator.pop(ctx);
                _iadeyiFaturalandir(iade, kalemler);
              },
            ),
          // 🔴 DÜZELTME (komple derin analizde bulundu): _gecmisIadeDuzelt()
          // tam/çalışan bir fonksiyondu (iade nedenini düzenleyip
          // BulutManager().upsert() ile senkronluyordu) ama hiçbir UI
          // tetikleyicisi yoktu — analyzer'ın "unused_element" uyarısı
          // vermemesi çağrılıyor sanılmasına yol açmıştı, oysa hiçbir yerde
          // çağrılmıyordu. "Düzenle" (kalem ekleme) ile karıştırılmaması
          // için ayrı, küçük bir ikon buton olarak bağlandı.
          TextButton.icon(
            icon: const Icon(Icons.edit_note_outlined, size: 18),
            label: const Text('Notu Düzelt'),
            onPressed: () {
              Navigator.pop(ctx);
              _gecmisIadeDuzelt(iade, kalemler);
            },
          ),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(ctx);
              _gecmisIadeyiDevamEt(iade);
            },
            child: const Text('Düzenle'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        ],
      ),
    );
  }

  Future<void> _gecmisIadeDuzelt(Map<String, dynamic> iade, List<Map<String, dynamic>> kalemler) async {
    // Düzeltme: sadece not/açıklama ve iade nedeni düzenlenebilir
    final notCtrl = TextEditingController(text: iade['iade_nedeni']?.toString() ?? '');
    // 🔴 DÜZELTME (komple derin analizde bulundu): notCtrl hiç dispose
    // edilmiyordu — dış try/finally ile garanti altına alındı.
    try {
      await _gecmisIadeDuzeltIc(iade, notCtrl);
    } finally {
      notCtrl.dispose();
    }
  }

  Future<void> _gecmisIadeDuzeltIc(
      Map<String, dynamic> iade, TextEditingController notCtrl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Text('İadeyi Düzelt'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('İade nedeni ve notunu düzenleyebilirsiniz.',
              style: TextStyle(fontSize: 12, color: context.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: notCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'İade Nedeni / Not',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.note_alt),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      // Madde 2 sertleştirmesi: doğrudan Veritabani().db erişimi
      // kaldırıldı — IadeDeposu repository katmanı üzerinden yazılıyor
      // (kuyruk kaydı business data ile aynı transaction'da atomik).
      await IadeDeposu().notGuncelle(
        iadeId: iade['id'] as int,
        iadeNedeni: notCtrl.text.trim(),
      );
      if (!mounted) return;
      BildirimServisi.basari(context, 'İade güncellendi ✓');
      _gecmisYukle();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }
}
