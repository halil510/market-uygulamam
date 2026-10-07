// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: `part of 'iade_ekrani.dart'` + `extension ... on _IadeEkraniState`
// (bkz. iade_ekrani_fis.dart başındaki açıklama).
// lib/ekranlar/satis/iade_ekrani_kaydet.dart
//
// İade sekmesinin KAYIT akışı (2026-10-07 refactor — iade_ekrani.dart'tan
// davranış birebir korunarak taşındı). Asıl iş mantığı servislerde
// (IadeIslemServisi); burası kaydı başlatıp ekran durumunu günceller:
//   _kaydet ─┬─ düzenleme modu   → _duzenlemeModuKalemEkle (geçmiş parçası)
//            ├─ tedarikçi / bayi → _cariIadesiKaydet (kural fiyatı, ayrı belge)
//            └─ müşteri          → _musteriIadesiKaydet (oturum fişine kalem)
part of 'iade_ekrani.dart';

extension _IadeKaydetExt on _IadeEkraniState {
  Future<void> _kaydet() async {
    if (_secilenUrun == null) {
      _msg('Ürün seçin', err: true);
      return;
    }
    if (_miktar <= 0) {
      _msg('Geçerli miktar girin', err: true);
      return;
    }
    if (!await _cariSecimiTamamla() || !mounted) return;

    // Düzenleme modunda mevcut fişe kalem ekle
    if (_duzenlemeModuIadeId != null) {
      final (:fiyat, :isk, :toplam) = _formTutarlari();
      await _duzenlemeModuKalemEkle(fiyat, isk,
          ParaUtils.yuvarla(_miktar * fiyat * (isk / 100)), fiyat * (1 - isk / 100), toplam);
      return;
    }

    // Tedarikçiye / bayiden iade: fiyatı ve yönü kural belirler, ayrı akış.
    final tur = _cariIadeTuru;
    if (tur.fiyatKuralli) {
      await _cariIadesiKaydet(tur);
    } else {
      await _musteriIadesiKaydet();
    }
  }

  /// Cari seçilmemişse sorar (kayıtsız müşteri dahil). Vazgeçilirse false.
  ///
  /// 🔴 DÜZELTME (2026-09-28, kullanıcı bulgusu — "müşteriden iade aldım,
  /// bakiye azalmadı"): kayıtlı cari BURADA seçilince iade yöntemi hiç
  /// sorulmadan 'Nakit' ile kaydediliyordu. Artık açıkça soruluyor.
  /// Tedarikçi/bayi iadesi her zaman cariye işlenir — sorulmaz.
  Future<bool> _cariSecimiTamamla() async {
    if (_secilenCari != null) return true;
    final sec = await _cariSecimDialog();
    if (sec == null || !mounted) return false;
    setState(() => _secilenCari = sec);
    if (sec.id != null && _cariIadeTuru == CariIadeTuru.musteri) {
      final yontem = await _cariIadeYontemiSor(sec.unvan);
      if (yontem == null || !mounted) return false;
      setState(() => _iadeOdemeYontemi = yontem);
    }
    return true;
  }

  /// Formdaki birim fiyat, iskonto % ve iskontolu satır toplamı.
  ({double fiyat, double isk, double toplam}) _formTutarlari() {
    final fiyat = ParaUtils.sayiCoz(_fiyatCtrl.text) ?? _orijinalFiyat;
    final isk = ParaUtils.sayiCoz(_iskontoCtrl.text) ?? 0;
    return (fiyat: fiyat, isk: isk, toplam: ParaUtils.yuvarla(_miktar * fiyat * (1 - isk / 100)));
  }

  String? get _formAciklamasi {
    final a = _aciklamaCtrl.text.trim();
    return a.isEmpty ? null : a;
  }

  // ── Müşteri iadesi (oturum fişine kalem) ─────────────────────────────────
  Future<void> _musteriIadesiKaydet() async {
    final urun = _secilenUrun!;
    final miktar = _miktar;
    setState(() => _yukleniyor = true);
    try {
      final (:fiyat, :isk, :toplam) = _formTutarlari();
      // Fiş no transaction dışında (sequence güncelleme ayrı transaction gerektirir)
      if (_oturumFisNo.isEmpty) {
        _oturumFisNo = await BelgeNoServisi().uret('iade');
      }
      // Transaction + bulut senkron: IadeIslemServisi.manuelKalemEkle.
      final iadeId = await IadeIslemServisi().manuelKalemEkle(
        oturumIadeId: _oturumIadeId,
        cariId: _secilenCari?.id,
        cariTipi: _secilenCari?.cariTipi,
        fisNo: _oturumFisNo,
        urunId: urun.id!,
        urunAdi: urun.urunAdi,
        miktar: miktar,
        fiyat: fiyat,
        toplam: toplam,
        neden: _formAciklamasi ?? 'Iade',
        odemeYontemi: _iadeOdemeYontemi,
        kullaniciId: AuthServisi().aktifId,
        kullaniciAdi: AuthServisi().aktifAd,
        iskontoOran: isk,
      );
      _oturumIadeId ??= iadeId;

      // Aynı ürün oturum fişinde zaten varsa satır birleştirilir, öne taşınır.
      final mevcutIdx = _iadeListesi.indexWhere((x) => x['urun_id'] == urun.id);
      if (mevcutIdx != -1) {
        final m = _iadeListesi.removeAt(mevcutIdx);
        _iadeListesi.insert(0, {
          ...m,
          'miktar': (m['miktar'] as double) + miktar,
          'toplam_tutar': (m['toplam_tutar'] as double) + toplam,
        });
      } else {
        _iadeListesi.insert(
            0,
            _oturumSatiri(
              iadeId: iadeId,
              urun: urun,
              miktar: miktar,
              birimFiyat: fiyat,
              iskontoOran: isk,
              iskontoTutar: ParaUtils.yuvarla(miktar * fiyat * (isk / 100)),
              toplam: toplam,
              musteriAdi: _secilenCari?.unvan ?? 'Kayıtsız Müşteri',
              fisNo: _oturumFisNo,
            ));
      }
      _yerelStoguDegistir(urun.id!, miktar);
      _msg('${urun.urunAdi} iade edildi ✓', err: false);
      _kayitSonrasi();
    } catch (e) {
      _msg('Hata: $e', err: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // ── Tedarikçiye iade / bayiden iade ──────────────────────────────────────
  /// Her kayıt kendi belgesini açar (IadeIslemServisi.tedarikciyeIadeEt /
  /// bayidenIadeAl). Fiyat formdaki alandan değil, servisteki kuraldan gelir;
  /// ekranda gösterilen önizlemedir.
  Future<void> _cariIadesiKaydet(CariIadeTuru tur) async {
    final cari = _secilenCari!;
    final urun = _secilenUrun!;
    final miktar = _miktar;
    setState(() => _yukleniyor = true);
    try {
      final kalem = [IadeMiktari(urunId: urun.id!, miktar: miktar)];
      final servis = IadeIslemServisi();
      final sonuc = tur == CariIadeTuru.tedarikci
          ? await servis.tedarikciyeIadeEt(
              tedarikci: cari,
              kalemler: kalem,
              kullaniciId: AuthServisi().aktifId,
              kullaniciAdi: AuthServisi().aktifAd,
              aciklama: _formAciklamasi)
          : await servis.bayidenIadeAl(
              bayi: cari,
              kalemler: kalem,
              kullaniciId: AuthServisi().aktifId,
              kullaniciAdi: AuthServisi().aktifAd,
              aciklama: _formAciklamasi);
      if (!mounted) return;

      _iadeListesi.insert(
          0,
          _oturumSatiri(
            iadeId: sonuc.iadeId,
            urun: urun,
            miktar: miktar,
            birimFiyat: sonuc.birimFiyatlar[urun.id] ?? 0,
            toplam: sonuc.toplamTutar,
            musteriAdi: cari.unvan,
            fisNo: sonuc.fisNo,
            // Oturum listesinin müşteri iadesine özel sil/düzenle eylemleri bu
            // satırlarda kısıtlanır (bkz. iade_ekrani_gecmis.dart _cariIadeKisiti).
            cariIadeTuru: tur,
          ));
      _yerelStoguDegistir(urun.id!, tur.stokAzalir ? -miktar : miktar);
      ref.invalidate(cariDetayProvider(cari.id!));
      ref.read(carilerProvider.notifier).yukle();

      final tutar = ParaUtils.formatla(sonuc.toplamTutar);
      _msg(
          tur.stokAzalir
              ? '${urun.urunAdi} tedarikçiye iade edildi — $tutar borcumuzdan düşüldü (${sonuc.fisNo})'
              : '${urun.urunAdi} bayiden iade alındı — $tutar bayi borcundan düşüldü (${sonuc.fisNo})',
          err: false);
      _kayitSonrasi();
    } on IadeGecersizHatasi catch (e) {
      _msg(e.mesaj, err: true);
    } catch (e) {
      _msg('İade kaydedilemedi: ${kullaniciyaHataMetni(e)}', err: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // ── Ortak yardımcılar ────────────────────────────────────────────────────
  /// Oturum listesine (ekrandaki "bu iadede yapılanlar") eklenecek satır.
  Map<String, dynamic> _oturumSatiri({
    required int iadeId,
    required UrunModel urun,
    required double miktar,
    required double birimFiyat,
    required double toplam,
    required String musteriAdi,
    required String fisNo,
    double iskontoOran = 0,
    double iskontoTutar = 0,
    CariIadeTuru? cariIadeTuru,
  }) =>
      {
        'iade_id': iadeId,
        'urun_id': urun.id,
        'tarih': DateTime.now(),
        'urun_adi': urun.urunAdi,
        'barkod': urun.barkod ?? '',
        'miktar': miktar,
        'birim_fiyat': birimFiyat,
        'iskonto_oran': iskontoOran,
        'iskonto_tutar': iskontoTutar,
        'toplam_tutar': toplam,
        'musteri_adi': musteriAdi,
        'cari_id': _secilenCari?.id,
        'fis_no': fisNo,
        if (cariIadeTuru != null) 'cari_iade_turu': cariIadeTuru.name,
      };

  /// Ekrandaki ürün listesinin stoğunu yerelde günceller (yeniden yüklemeden).
  void _yerelStoguDegistir(int urunId, double fark) {
    final i = _tumUrunler.indexWhere((u) => u.id == urunId);
    if (i != -1) _tumUrunler[i] = _tumUrunler[i].copyWith(stok: _tumUrunler[i].stok + fark);
  }

  /// Kullanıcı isteği: "iade alımı yaptığımızda o ekran kapanacak" — yalnız
  /// toptan cari panelinden açılan tek-ürünlük akışta; normal çok-kalemli
  /// akışta ekran açık kalır, form sıfırlanır.
  void _kayitSonrasi() {
    if (widget.otomatikKapat) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    _formSifirla();
    _gecmisYukle();
  }
}
