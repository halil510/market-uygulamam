// ignore_for_file: invalid_use_of_protected_member
//
// Geçmiş sekmesi. 2026-10-07 refactor; 2026-10-13: tedarikçi iadelerinin
// UNION ile gösterimi + bugünkü tedarikçi/bayi iadesine "Kalem Ekle".
part of 'iade_ekrani.dart';

extension _GecmisTabExt on _IadeEkraniState {
  Widget _gecmisTab() => IadeGecmisSekmesi(
        baslangic: _gecmisTarihBaslangic,
        bitis: _gecmisTarihBitis,
        cariFiltre: _gecmisCariFiltre,
        yukleniyor: _gecmisYukleniyor,
        iadeler: _gecmisIadeler,
        onBaslangicSec: () => _gecmisTarihSec(baslangic: true),
        onBitisSec: () => _gecmisTarihSec(baslangic: false),
        onCariSec: _gecmisCariSec,
        onFiltreTemizle: _gecmisFiltreTemizle,
        onYenile: _gecmisYukle,
        onSilOnay: _gecmisSilOnay,
        onSil: _gecmisIadeSil,
        onDetay: _gecmisIadeDetay,
        onYazdir: _gecmisIadeYazdir,
      );

  /// 🆕 Geçmiş listesindeki iadenin FİŞİNİ yazdırır (kaynak 'tedarikci' →
  /// TEDARIKCIYE IADE FISI; 'iade' → cari tipine göre BAYI / MUSTERI IADE
  /// FISI). Cari ekstresindeki yazdır ikonuyla AYNI kod yolu.
  Future<void> _gecmisIadeYazdir(Map<String, dynamic> iade) async {
    final id = (iade['id'] as num?)?.toInt();
    if (id == null) return;
    final tedarikciMi = iade['kaynak'] == 'tedarikci';
    try {
      await IadeFisiYazdirici.fisten(
        fisId: id,
        fisTipi: tedarikciMi ? 'Tedarikçi İadesi' : 'İade',
        cariUnvan: iade['cari_adi']?.toString(),
      );
      _msg('İade fişi yazdırılıyor…', err: false);
    } catch (e) {
      _msg('Yazıcı hatası: ${kullaniciyaHataMetni(e)}', err: true);
    }
  }

  Future<void> _gecmisTarihSec({required bool baslangic}) async {
    final d = await showDatePicker(
        context: context,
        initialDate:
            (baslangic ? _gecmisTarihBaslangic : _gecmisTarihBitis) ??
                DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (!mounted || d == null) return;
    setState(() =>
        baslangic ? _gecmisTarihBaslangic = d : _gecmisTarihBitis = d);
    _gecmisYukle();
  }

  Future<void> _gecmisCariSec() async {
    final secilen = await showDialog<CariModel>(
        context: context, builder: (bCtx) => CariSecDialog(cariler: _cariler));
    if (!mounted || secilen == null) return;
    setState(() => _gecmisCariFiltre = secilen);
    _gecmisYukle();
  }

  void _gecmisFiltreTemizle() {
    setState(() {
      _gecmisTarihBaslangic = null;
      _gecmisTarihBitis = null;
      _gecmisCariFiltre = null;
    });
    _gecmisYukle();
  }

  Future<bool> _gecmisSilOnay(Map<String, dynamic> r) async {
    final tedarikciMi = r['kaynak'] == 'tedarikci';
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tedarikciMi ? 'Tedarikçi İadesini İptal Et' : 'Fisi Sil'),
        content: Text(tedarikciMi
            ? '${r['fis_no'] ?? 'Bu tedarikçi iadesi'} iptal edilsin mi?\n\n'
                '• Stok geri alınacak\n'
                '• Tedarikçiye olan borcumuz eski hâline dönecek'
            : '${r['fis_no'] ?? 'Bu iade'} silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hayir')),
          FilledButton(
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tedarikciMi ? 'İptal Et' : 'Sil'),
          ),
        ],
      ),
    );
    return onay == true;
  }

  // ── Düzenleme modu (MÜŞTERİ iadesi) ──────────────────────────────────────
  Future<void> _gecmisIadeyiDevamEt(Map<String, dynamic> iade) async {
    if (iade['kaynak'] == 'tedarikci') {
      _msg('Tedarikçi iadeleri düzenlenemez — gerekirse silip yeniden iade alın.',
          err: true);
      return;
    }
    final iadeId = iade['id'] as int?;
    if (iadeId == null) return;

    // Bayi kontrolü
    final cariIdRaw = iade['cari_id'] as int?;
    if (cariIdRaw != null && await IadeDeposu().cariBayiMi(cariIdRaw)) {
      _msg('Bayi iadesinin fiyatı bayi fiyat kuralından gelir — düzenlenemez; '
          'gerekirse silip yeniden iade alın.', err: true);
      return;
    }

    final kalemler = await IadeDeposu().kalemleriGetir(iadeId);

    CariModel? cari;
    if (cariIdRaw != null) {
      cari = _cariler.firstWhere(
        (c) => c.id == cariIdRaw,
        orElse: () => CariModel(
            id: cariIdRaw,
            unvan: iade['cari_adi']?.toString() ?? '-',
            bakiye: 0),
      );
    }

    String orjYontem = 'Nakit';
    if (cariIdRaw != null) {
      orjYontem = await IadeDeposu().iadeOdemeYontemiGetir(iadeId, cariIdRaw);
    }

    if (!mounted) return;

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.edit_note, color: TsRenk.uyari),
          SizedBox(width: 8),
          Expanded(
              child: Text('İadeyi Düzenle', style: TextStyle(fontSize: 16))),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TsRenk.zemin(TsRenk.uyari),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fiş: ${iade['fis_no'] ?? '-'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      if (cari != null)
                        Text('Cari: ${cari.unvan}',
                            style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondary)),
                      Text(
                          'Tutar: ${ParaUtils.formatla((iade['toplam_tutar'] as num?)?.toDouble() ?? 0)}',
                          style: const TextStyle(fontSize: 12)),
                      Text('Ödeme: $orjYontem',
                          style: TextStyle(
                              fontSize: 12, color: context.textSecondary)),
                    ]),
              ),
              const SizedBox(height: 10),
              Text(
                'Bu iade fise eklenecek veya mevcut kalemler düzenlenecek. '
                'Cari ve stok otomatik güncellenir.',
                style: TextStyle(
                    fontSize: 12,
                    color: TsRenk.metinIkincil(context),
                    height: 1.5),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton.icon(
            icon: const Icon(Icons.edit, size: 16, color: Colors.white),
            label: const Text('Düzenlemeye Geç'),
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: TsRenk.uyari),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (onay != true || !mounted) return;

    setState(() {
      _duzenlemeModuIadeId = iadeId;
      _duzenlemeModuFisNo = iade['fis_no']?.toString();
      _secilenCari = cari;
      _oturumIadeId = iadeId;
      _oturumFisNo = iade['fis_no']?.toString() ?? '';
      _iadeOdemeYontemi = orjYontem;
      // Düzenleme modu müşteri iadesi içindir — tedarikçi/bayi oturumunu sıfırla.
      _cariOturumIadeId = null;
      _cariOturumFisNo = '';
      _cariOturumTuru = null;
      _cariOturumCariId = null;
      _cariOturumTarih = null;

      _iadeListesi.clear();
      for (final k in kalemler) {
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        final birimFiyat = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
        _iadeListesi.add({
          'iade_id': iadeId,
          'kalem_id': k['id'],
          'urun_id': k['urun_id'],
          'tarih': DateTime.now(),
          'urun_adi': k['urun_adi'],
          'barkod': '',
          'miktar': miktar,
          'birim_fiyat': birimFiyat,
          'iskonto_oran': (k['iskonto_oran'] as num?)?.toDouble() ?? 0.0,
          'iskonto_tutar': (k['iskonto_tutar'] as num?)?.toDouble() ?? 0.0,
          'toplam_tutar':
              (k['toplam'] as num?)?.toDouble() ?? miktar * birimFiyat,
          'musteri_adi': cari?.unvan ?? 'Perakende',
          'cari_id': cariIdRaw,
          'aciklama': iade['iade_nedeni']?.toString() ?? '',
          'fis_no': iade['fis_no']?.toString() ?? '',
          'mevcut_kalem': true,
        });
      }
    });

    _gecmisYukle();
    _tab.animateTo(0);
    _msg(
        'Düzenleme modu: ${iade['fis_no']} — ürün ekleyebilir veya mevcut kalemleri düzenleyebilirsiniz',
        err: false);
  }

  // ── 🆕 BUGÜNKÜ TEDARİKÇİ/BAYİ İADESİNE KALEM EKLE ────────────────────────
  /// 🔴 YENİ (2026-10-13, kullanıcı isteği): Geçmişteki bir tedarikçi/bayi
  /// iadesi BUGÜN açılmışsa, ona yeni kalem ekleyebiliriz. Belge açılmaz;
  /// `_cariOturumIadeId` o belgeye kilitlenir; iade sekmesinde yeni ürün
  /// seçilip Kaydet denince AYNI belgeye kalem eklenir
  /// (tedarikciIadeyeKalemEkle / bayiIadeyeKalemEkle).
  ///
  /// 🚫 Eski tarihli iadelere ekleme YAPILAMAZ (ERP kuralı: kapanmış dönem).
  Future<void> _cariIadeyeDevamEt(Map<String, dynamic> iade) async {
    final tedarikciMi = iade['kaynak'] == 'tedarikci';
    final iadeId = iade['id'] as int?;
    if (iadeId == null) return;

    // Tarih kontrolü — sadece bugünkü iadelere kalem eklenebilir.
    final tarihStr = iade['tarih']?.toString();
    final tarih = tarihStr != null ? DateTime.tryParse(tarihStr) : null;
    if (tarih == null || !_ayniGunMu(tarih, DateTime.now())) {
      _msg(
          'Yalnız bugün oluşturulan iadelere kalem eklenebilir. '
          'Bu iade kapanmış — istersen silip yeniden oluştur.',
          err: true);
      return;
    }

    final cariId = iade['cari_id'] as int?;
    if (cariId == null) return;
    final cari = _cariler.firstWhere(
      (c) => c.id == cariId,
      orElse: () => CariModel(
          id: cariId,
          unvan: iade['cari_adi']?.toString() ?? '-',
          bakiye: 0),
    );

    final tur = tedarikciMi ? CariIadeTuru.tedarikci : CariIadeTuru.bayi;

    // Onay
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.add_circle_outline, color: TsRenk.bilgi),
          SizedBox(width: 8),
          Expanded(
              child: Text('İadeye Kalem Ekle',
                  style: TextStyle(fontSize: 16))),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TsRenk.zemin(TsRenk.bilgi),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fiş: ${iade['fis_no'] ?? '-'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('Cari: ${cari.unvan}',
                          style: TextStyle(
                              fontSize: 12, color: context.textSecondary)),
                      Text('Tür: ${tedarikciMi ? "Tedarikçi İadesi" : "Bayi İadesi"}',
                          style: TextStyle(
                              fontSize: 12, color: context.textSecondary)),
                    ]),
              ),
              const SizedBox(height: 10),
              Text(
                'Aynı fişe yeni ürün kalemleri ekleyebilirsiniz. '
                'Stok ve cari bakiye otomatik güncellenir.',
                style: TextStyle(
                    fontSize: 12,
                    color: TsRenk.metinIkincil(context),
                    height: 1.5),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton.icon(
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('İade Ekranına Git'),
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: TsRenk.bilgi),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    // Kalemleri yükle — eski + yeni görünsün
    final List<Map<String, dynamic>> kalemler;
    if (tedarikciMi) {
      final ham = await IadeDeposu().tedarikciKalemleriGetir(iadeId);
      kalemler = ham.map((k) {
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        final birim = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
        final toplam = (k['toplam_tutar'] as num?)?.toDouble() ??
            miktar * birim;
        return {
          'iade_id': iadeId,
          'kalem_id': k['id'],
          'urun_id': k['urun_id'],
          'tarih': DateTime.now(),
          'urun_adi': k['urun_adi'],
          'barkod': k['barkod'] ?? '',
          'miktar': miktar,
          'birim_fiyat': birim,
          'iskonto_oran': 0.0,
          'iskonto_tutar': 0.0,
          'toplam_tutar': toplam,
          'musteri_adi': cari.unvan,
          'cari_id': cariId,
          'aciklama': iade['iade_nedeni']?.toString() ?? '',
          'fis_no': iade['fis_no']?.toString() ?? '',
          'mevcut_kalem': true,
          'cari_iade_turu': 'tedarikci',
        };
      }).toList();
    } else {
      final ham = await IadeDeposu().kalemleriUrunBilgisiyleGetir(iadeId);
      kalemler = ham.map((k) {
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
        final birim = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
        final toplam =
            (k['toplam'] as num?)?.toDouble() ?? miktar * birim;
        return {
          'iade_id': iadeId,
          'kalem_id': k['id'],
          'urun_id': k['urun_id'],
          'tarih': DateTime.now(),
          'urun_adi': k['urun_adi'] ?? k['urun_adi_db'],
          'barkod': k['barkod'] ?? '',
          'miktar': miktar,
          'birim_fiyat': birim,
          'iskonto_oran': (k['iskonto_oran'] as num?)?.toDouble() ?? 0.0,
          'iskonto_tutar': (k['iskonto_tutar'] as num?)?.toDouble() ?? 0.0,
          'toplam_tutar': toplam,
          'musteri_adi': cari.unvan,
          'cari_id': cariId,
          'aciklama': iade['iade_nedeni']?.toString() ?? '',
          'fis_no': iade['fis_no']?.toString() ?? '',
          'mevcut_kalem': true,
          'cari_iade_turu': 'bayi',
        };
      }).toList();
    }

    if (!mounted) return;
    setState(() {
      // Oturumu geçmişteki belgeye kilitle — sonraki Kaydet bu belgeye ekler.
      _cariOturumIadeId = iadeId;
      _cariOturumFisNo = iade['fis_no']?.toString() ?? '';
      _cariOturumTuru = tur;
      _cariOturumCariId = cariId;
      _cariOturumTarih = DateTime.now(); // bugün olarak işaretle
      _secilenCari = cari;
      // Müşteri düzenleme modu kapalı (karışmasın)
      _duzenlemeModuIadeId = null;
      _duzenlemeModuFisNo = null;
      _oturumIadeId = null;
      _oturumFisNo = '';

      _iadeListesi.clear();
      _iadeListesi.addAll(kalemler);
    });

    _tab.animateTo(0);
    _msg(
        'Fiş: ${iade['fis_no']} — yeni kalem eklemek için ürün seçip Kaydet deyin',
        err: false);
  }

  // ── Geçmiş fişi sil ─────────────────────────────────────────────────────
  Future<void> _gecmisIadeSil(Map<String, dynamic> iade) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: TsRenk.hata),
          SizedBox(width: 8),
          Text('Fişi Sil'),
        ]),
        content: Text(
            '${iade['fis_no'] ?? 'Bu iade'} silinecek.\nStok, kasa ve cari kayıtları geri alınacak.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    try {
      final iadeId = iade['id'] as int?;
      if (iadeId == null) return;

      if (iade['kaynak'] == 'tedarikci') {
        await IadeIslemServisi().tedarikciIadesiniIptalEt(
          iadeId,
          neden: 'İade Geçmişi\'nden iptal edildi',
        );
      } else {
        final kalemler = await IadeDeposu().kalemleriGetir(iadeId);
        await IadeIslemServisi().gecmisFisIadeSil(
          iadeId: iadeId,
          kalemler: kalemler,
          toplamTutar: (iade['toplam_tutar'] as num?)?.toDouble() ?? 0,
          cariId: iade['cari_id'] as int?,
          fisNo: iade['fis_no']?.toString(),
        );
      }

      // Oturum belgesi silindiyse sıfırla
      if (mounted) {
        setState(() {
          if (_cariOturumIadeId == iadeId) {
            _cariOturumIadeId = null;
            _cariOturumFisNo = '';
            _cariOturumTuru = null;
            _cariOturumCariId = null;
            _cariOturumTarih = null;
          }
        });
      }

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
      final rows = await IadeDeposu().gecmisListesiGetir(
        baslangic: _gecmisTarihBaslangic,
        bitis: _gecmisTarihBitis,
        cariId: _gecmisCariFiltre?.id,
      );
      if (!mounted) return;
      _gecmisIadeler = rows;
      _gecmisYukleniyor = false;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        _gecmisYukleniyor = false;
        setState(() {});
      }
    }
  }

  Future<void> _iadeyiFaturalandir(
      Map<String, dynamic> iade, List<Map<String, dynamic>> kalemler) async {
    if (iade['kaynak'] == 'tedarikci') {
      _msg('Tedarikçi iadeleri için iade faturası bu ekrandan kesilmez.',
          err: true);
      return;
    }
    final cariId = iade['cari_id'] as int?;
    if (cariId == null) {
      _msg('Bu iadede cari secilmemis.', err: true);
      return;
    }
    if (kalemler.isEmpty) {
      _msg('Faturalandirilacak kalem bulunamadi.', err: true);
      return;
    }

    setState(() => _yukleniyor = true);
    try {
      final mevcutId =
          await FaturalandirmaServisi.mevcutFaturaId(iadeId: iade['id'] as int?);
      if (mevcutId != null) {
        if (!mounted) return;
        _msg('Bu iade için zaten bir fatura mevcut.', err: false);
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: TsRenk.uyari),
              SizedBox(width: 8),
              Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      "${kontrol.cari.unvan.isEmpty ? 'Bu cari' : kontrol.cari.unvan} icin "
                      "fatura kesilebilmesi icin asagidaki bilgiler eksik:"),
                  const SizedBox(height: 10),
                  ...kontrol.eksikAlanlar.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          const Icon(Icons.circle,
                              size: 6, color: TsRenk.uyari),
                          const SizedBox(width: 8),
                          Text(e),
                        ]),
                      )),
                ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgec')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Cari Duzenle')),
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
        final kdvOran = (k['urun_kdv_oran'] as num?)?.toDouble() ?? 20.0;
        final kdvDahilToplam =
            (k['toplam'] as num?)?.toDouble() ?? miktar * birimFiyat;
        return FaturaDetayModel.kdvDahilKalemden(
          urunId: k['urun_id'] as int?,
          urunAdi: (k['urun_adi'] ?? k['urun_adi_db'] ?? '-').toString(),
          miktar: miktar,
          birimFiyat: birimFiyat,
          kdvOrani: kdvOran,
          kdvDahilToplam: kdvDahilToplam,
        );
      }).toList();

      final tarih =
          DateTime.tryParse(iade['tarih']?.toString() ?? '') ?? DateTime.now();
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

  // ── Geçmiş detay diyaloğu ───────────────────────────────────────────────
  Future<void> _gecmisIadeDetay(Map<String, dynamic> iade) async {
    final tedarikciMi = iade['kaynak'] == 'tedarikci';
    final kalemler = tedarikciMi
        ? await IadeDeposu().tedarikciKalemleriGetir(iade['id'] as int)
        : await IadeDeposu().kalemleriUrunBilgisiyleGetir(iade['id'] as int);

    // Bayi tespiti
    bool bayiMi = false;
    final cariIdRaw = iade['cari_id'];
    if (!tedarikciMi && cariIdRaw != null) {
      final cari = _cariler.firstWhere(
        (c) => c.id == cariIdRaw,
        orElse: () => CariModel(
            id: cariIdRaw,
            unvan: iade['cari_adi']?.toString() ?? '-',
            bakiye: 0),
      );
      bayiMi = CariIadeTuru.belirle(cari) == CariIadeTuru.bayi;
    }

    // 🔴 Bugünkü iade mi? → "Kalem Ekle" butonu göster
    final tarihStr = iade['tarih']?.toString();
    final tarih = tarihStr != null ? DateTime.tryParse(tarihStr) : null;
    final bugunkuMu = tarih != null && _ayniGunMu(tarih, DateTime.now());
    final kalemEklenebilir = (tedarikciMi || bayiMi) && bugunkuMu;
    final duzenlenebilir = !tedarikciMi && !bayiMi;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 320),
        title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  tedarikciMi
                      ? 'Tedarikçi İadesi #${iade['fis_no'] ?? iade['id']}'
                      : 'İade #${iade['fis_no'] ?? iade['id']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (duzenlenebilir)
                IconButton(
                  icon: const Icon(Icons.edit, color: TsRenk.uyari),
                  tooltip: 'Düzenle',
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
              ListTile(
                dense: true,
                leading: const Icon(Icons.person,
                    size: 18, color: AppRenkler.primary),
                title: Text(iade['cari_adi'].toString()),
                subtitle: (tedarikciMi || bayiMi)
                    ? Text(
                        tedarikciMi
                            ? 'Tedarikçi iadesi — tedarikçiye borcumuz'
                            : 'Bayi iadesi — bayinin borcu düşer',
                        style: const TextStyle(fontSize: 11))
                    : null,
              ),
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
                  return ListTile(
                    dense: true,
                    title: Text(
                        k['urun_adi']?.toString() ??
                            k['urun_adi_db']?.toString() ??
                            '-',
                        style: const TextStyle(fontSize: 13)),
                    trailing: Text(
                        '${m.toStringAsFixed(m % 1 == 0 ? 0 : 2)} × ${ParaUtils.formatla(bf)}',
                        style: const TextStyle(fontSize: 12)),
                  );
                },
              ),
            ),
            const Divider(),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOPLAM',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                      ParaUtils.formatla(
                          (iade['toplam_tutar'] as num?)?.toDouble() ?? 0),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: TsRenk.uyari,
                          fontSize: 16)),
                ]),
          ]),
        ),
        actions: [
          // ⋮ menü — sil, faturalandır, notu düzelt
          PopupMenuButton<String>(
            tooltip: 'Diğer işlemler',
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'sil',
                child: Row(children: [
                  Icon(
                      tedarikciMi
                          ? Icons.cancel_outlined
                          : Icons.delete_outline,
                      size: 18,
                      color: TsRenk.hata),
                  const SizedBox(width: 8),
                  Text(tedarikciMi ? 'İptal Et' : 'Fişi Sil',
                      style: const TextStyle(color: TsRenk.hata)),
                ]),
              ),
              if (!tedarikciMi && iade['cari_id'] != null)
                const PopupMenuItem(
                  value: 'faturalandir',
                  child: Row(children: [
                    Icon(Icons.receipt_long_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Faturalandır'),
                  ]),
                ),
              if (!tedarikciMi)
                const PopupMenuItem(
                  value: 'notu_duzelt',
                  child: Row(children: [
                    Icon(Icons.edit_note_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Notu Düzelt'),
                  ]),
                ),
            ],
            onSelected: (v) {
              Navigator.pop(ctx);
              switch (v) {
                case 'sil':
                  _gecmisIadeSil(iade);
                case 'faturalandir':
                  _iadeyiFaturalandir(iade, kalemler);
                case 'notu_duzelt':
                  _gecmisIadeDuzelt(iade, kalemler);
              }
            },
          ),
          // 🆕 Bugünkü tedarikçi/bayi iadesine "Kalem Ekle"
          if (kalemEklenebilir)
            FilledButton.icon(
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('Kalem Ekle'),
              style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: TsRenk.bilgi),
              onPressed: () {
                Navigator.pop(ctx);
                _cariIadeyeDevamEt(iade);
              },
            ),
          // Müşteri iadesi için "Düzenle"
          if (duzenlenebilir)
            FilledButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Düzenle'),
              style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: TsRenk.uyari),
              onPressed: () {
                Navigator.pop(ctx);
                _gecmisIadeyiDevamEt(iade);
              },
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        ],
      ),
    );
  }

  Future<void> _gecmisIadeDuzelt(
      Map<String, dynamic> iade, List<Map<String, dynamic>> kalemler) async {
    final notCtrl =
        TextEditingController(text: iade['iade_nedeni']?.toString() ?? '');
    try {
      await _gecmisIadeDuzeltIc(iade, notCtrl);
    } finally {
      dialogSonrasiBirak([notCtrl]);
    }
  }

  Future<void> _gecmisIadeDuzeltIc(
      Map<String, dynamic> iade, TextEditingController notCtrl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('İadeyi Düzelt'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('İade nedeni ve notunu düzenleyebilirsiniz.',
              style:
                  TextStyle(fontSize: 12, color: context.textSecondary)),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: TsRenk.uyari),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
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