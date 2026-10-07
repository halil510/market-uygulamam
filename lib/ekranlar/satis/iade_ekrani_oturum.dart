// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: `part of 'iade_ekrani.dart'` + `extension ... on _IadeEkraniState`
// (bkz. iade_ekrani_fis.dart başındaki açıklama).
// lib/ekranlar/satis/iade_ekrani_oturum.dart
//
// Bu oturumdaki iade listesi satırları üzerindeki işlemler: sil, düzenle,
// düzenleme modunda (geçmişten açılan fişe) kalem ekleme. 2026-10-07
// refactor — iade_ekrani_gecmis.dart'tan davranış birebir korunarak taşındı.
part of 'iade_ekrani.dart';

extension _IadeOturumExt on _IadeEkraniState {
  /// Tedarikçi/bayi iadesi satırında bu ekranın müşteri iadesi eylemleri
  /// kullanılamıyorsa sebebi, kullanılabiliyorsa null.
  /// - Tedarikçi iadesi `tedarikci_iadeler` tablosundadır: buradaki silme
  ///   `iade` tablosunda aynı id'li İLGİSİZ bir müşteri iadesini tersine
  ///   çevirirdi → silme ve düzenleme kapalı.
  /// - Bayi iadesi `iade` tablosundadır, silme doğru çalışır; düzenleme
  ///   fiyatı serbest bıraktığı için bayi fiyat kuralını delerdi → kapalı.
  String? _cariIadeKisiti(Map<String, dynamic> iade, {required bool silme}) {
    switch (iade['cari_iade_turu']) {
      case 'tedarikci':
        return 'Tedarikçi iadesi bu listeden ${silme ? 'silinemez' : 'düzenlenemez'}.';
      case 'bayi' when !silme:
        return 'Bayi iadesinin fiyatı bayi fiyat kuralından gelir — düzenlenemez; '
            'gerekirse silip yeniden iade alın.';
      default:
        return null;
    }
  }

  // ── Oturum iade silme onayı ─────────────────────────────────────────────
  Future<bool> _oturumIadeSilOnay(Map<String, dynamic> iade) async {
    final kisit = _cariIadeKisiti(iade, silme: true);
    if (kisit != null) {
      _msg(kisit, err: true);
      return false;
    }
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
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
    final kisit = _cariIadeKisiti(iade, silme: false);
    if (kisit != null) {
      _msg(kisit, err: true);
      return;
    }
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
                color: TsRenk.zemin(TsRenk.basarili),
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

    dialogSonrasiBirak([miktarCtrl, fiyatCtrl, iskCtrl, aciklamaCtrl]);

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
        yeniIskontoOran: yeniIsk,
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
        odemeYontemi: _iadeOdemeYontemi,
        iskontoOran: iskontoOran,
        iskontoTutar: iskontoTutar,
      );

      // 6. Lokal listeye ekle
      if (!mounted) return;
      setState(() {
        // 🔴 DÜZELTME (kullanıcı bulgusu: "önceki 2 idi, 4 ilave ettim, 6
        // olacak"): veritabanı aynı ürünün kalemini TOPLAYARAK güncelliyor
        // (2+4=6) ama ekrandaki liste her seferinde YENİ satır ekleyip yalnız
        // eklenen 4'ü gösteriyordu. Sonradan o satır düzenlenince yanlış
        // "eski miktar" servise gidip stok/cari farkı bozuluyordu. Artık
        // aynı ürün satırı birleştirilir (Odoo/ERPNext'teki gibi).
        final mevcutIdx = _iadeListesi.indexWhere((x) =>
            x['urun_id'] == _secilenUrun!.id && x['iade_id'] == iadeId);
        if (mevcutIdx != -1) {
          final m = _iadeListesi.removeAt(mevcutIdx);
          _iadeListesi.insert(0, {
            ...m,
            'miktar': ((m['miktar'] as num?)?.toDouble() ?? 0) + _miktar,
            'toplam_tutar': ((m['toplam_tutar'] as num?)?.toDouble() ?? 0) + toplam,
            'iskonto_tutar': ((m['iskonto_tutar'] as num?)?.toDouble() ?? 0) + iskontoTutar,
          });
          return;
        }
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

      _msg('${_secilenUrun!.urunAdi} → $_duzenlemeModu_fisNo fişine eklendi ✓', err: false);
      _formSifirla();
    } catch (e) {
      _msg('Hata: $e', err: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }
}
