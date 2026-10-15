// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: `part of 'iade_ekrani.dart'` + `extension ... on _IadeEkraniState`
// (bkz. iade_ekrani_fis.dart başındaki açıklama).
// lib/ekranlar/satis/iade_ekrani_kaydet.dart
//
// İade sekmesinin KAYIT akışı. Asıl iş mantığı servislerde
// (IadeIslemServisi); burası kaydı başlatıp ekran durumunu günceller.
//
// 🔴 YENİ (2026-10-13, kullanıcı isteği): tedarikçi/bayi iadeleri ARTIK
// TEK BELGE altında birikir (müşteri iadesindeki `_oturumIadeId`
// deseninin aynısı). Aynı gün + aynı cari + aynı tür → mevcut belgeye
// kalem eklenir; aksi halde yeni belge açılır.
part of 'iade_ekrani.dart';

/// İki DateTime aynı takvim gününde mi? (Yıl-Ay-Gün karşılaştırması)
bool _ayniGunMu(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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
          ParaUtils.yuvarla(_miktar * fiyat * (isk / 100)),
          fiyat * (1 - isk / 100), toplam);
      return;
    }

    // Tedarikçiye / bayiden iade: fiyatı ve yönü kural belirler.
    final tur = _cariIadeTuru;
    if (tur.fiyatKuralli) {
      await _cariIadesiKaydet(tur);
    } else {
      await _musteriIadesiKaydet();
    }
  }

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

  ({double fiyat, double isk, double toplam}) _formTutarlari() {
    final fiyat = ParaUtils.sayiCoz(_fiyatCtrl.text) ?? _orijinalFiyat;
    final isk = ParaUtils.sayiCoz(_iskontoCtrl.text) ?? 0;
    return (
      fiyat: fiyat,
      isk: isk,
      toplam: ParaUtils.yuvarla(_miktar * fiyat * (1 - isk / 100))
    );
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
      if (_oturumFisNo.isEmpty) {
        _oturumFisNo = await BelgeNoServisi().uret('iade');
      }
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

  // ── Tedarikçiye iade / bayiden iade — TEK FİŞ MODELİ ────────────────────
  /// 🔴 YENİ MANTIK: İlk kayıtta belge açılır (tedarikciyeIadeEt /
  /// bayidenIadeAl). Sonraki kayıtlarda AYNI belgeye kalem eklenir
  /// (tedarikciIadeyeKalemEkle / bayiIadeyeKalemEkle). Böylece hem
  /// ekranda hem VERİTABANINDA tek fiş olur.
  ///
  /// Oturum şartları:
  ///   • Aynı cari (cari.id değişmezse)
  ///   • Aynı tür (tedarikçi ↔ bayi değişmezse)
  ///   • Aynı gün (uygulama gece açık kaldıysa otomatik yeni fiş)
  /// Şartlardan biri bozulursa yeni belge açılır.
  Future<void> _cariIadesiKaydet(CariIadeTuru tur) async {
    final cari = _secilenCari!;
    final urun = _secilenUrun!;
    final miktar = _miktar;
    setState(() => _yukleniyor = true);
    try {
      final servis = IadeIslemServisi();
      final kalem = [IadeMiktari(urunId: urun.id!, miktar: miktar)];

      // Oturum devam ediyor mu?
      final oturumGecerli = _cariOturumIadeId != null &&
          _cariOturumTuru == tur &&
          _cariOturumCariId == cari.id &&
          _cariOturumTarih != null &&
          _ayniGunMu(_cariOturumTarih!, DateTime.now());

      final CariIadeSonucu sonuc;
      if (oturumGecerli) {
        // Aynı belgeye kalem ekle
        sonuc = tur == CariIadeTuru.tedarikci
            ? await servis.tedarikciIadeyeKalemEkle(
                iadeId: _cariOturumIadeId!,
                tedarikci: cari,
                kalemler: kalem,
                kullaniciId: AuthServisi().aktifId,
                kullaniciAdi: AuthServisi().aktifAd,
                aciklama: _formAciklamasi)
            : await servis.bayiIadeyeKalemEkle(
                iadeId: _cariOturumIadeId!,
                bayi: cari,
                kalemler: kalem,
                kullaniciId: AuthServisi().aktifId,
                kullaniciAdi: AuthServisi().aktifAd,
                aciklama: _formAciklamasi);
      } else {
        // Yeni belge aç
        sonuc = tur == CariIadeTuru.tedarikci
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
        // Oturum belgesini kilitle
        _cariOturumIadeId = sonuc.iadeId;
        _cariOturumFisNo = sonuc.fisNo;
        _cariOturumTuru = tur;
        _cariOturumCariId = cari.id;
        _cariOturumTarih = DateTime.now();
      }
      if (!mounted) return;

      final birimFiyat = sonuc.birimFiyatlar[urun.id] ?? 0;

      // Listede aynı cari + aynı ürün + aynı tür satırı birleştir.
      final mevcutIdx = _iadeListesi.indexWhere((x) =>
          x['urun_id'] == urun.id &&
          x['cari_id'] == cari.id &&
          x['cari_iade_turu'] == tur.name);

      if (mevcutIdx != -1) {
        final m = _iadeListesi.removeAt(mevcutIdx);
        _iadeListesi.insert(0, {
          ...m,
          'miktar': ((m['miktar'] as num?)?.toDouble() ?? 0) + miktar,
          'toplam_tutar': ((m['toplam_tutar'] as num?)?.toDouble() ?? 0) +
              sonuc.toplamTutar,
          'iade_id': _cariOturumIadeId,
          'fis_no': _cariOturumFisNo,
        });
      } else {
        final satir = _oturumSatiri(
          iadeId: _cariOturumIadeId!,
          urun: urun,
          miktar: miktar,
          birimFiyat: birimFiyat,
          toplam: sonuc.toplamTutar,
          musteriAdi: cari.unvan,
          fisNo: _cariOturumFisNo,
          cariIadeTuru: tur,
        );
        _iadeListesi.insert(0, satir);
      }

      _yerelStoguDegistir(urun.id!, tur.stokAzalir ? -miktar : miktar);
      ref.invalidate(cariDetayProvider(cari.id!));
      ref.read(carilerProvider.notifier).yukle();

      final tutar = ParaUtils.formatla(sonuc.toplamTutar);
      _msg(
          tur.stokAzalir
              ? '${urun.urunAdi} tedarikçiye iade edildi — $tutar borcumuzdan düşüldü ($_cariOturumFisNo)'
              : '${urun.urunAdi} bayiden iade alındı — $tutar bayi borcundan düşüldü ($_cariOturumFisNo)',
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

  // ── İade fişi yazdırma ───────────────────────────────────────────────────
  /// Yazdırılacak oturum belgesi: seçili cari tedarikçi/bayi ise o oturumun
  /// belgesi, değilse müşteri oturumunun iadesi. Yoksa null (buton gizlenir).
  int? get _yazdirilacakIadeId {
    if (_duzenlemeModuIadeId != null) return _duzenlemeModuIadeId;
    if (_cariIadeTuru.fiyatKuralli) return _cariOturumIadeId;
    return _oturumIadeId;
  }

  /// 🆕 Oturumdaki iadenin FİŞİNİ basar — cari ekstresindeki yazdır ikonuyla
  /// AYNI kod yolu (IadeFisiYazdirici). Tür (müşteri/bayi/tedarikçi) belgenin
  /// cari tipinden otomatik belirlenir.
  Future<void> _oturumIadeFisiYazdir() async {
    final id = _yazdirilacakIadeId;
    if (id == null) return;
    final tedarikciMi = _duzenlemeModuIadeId == null &&
        _cariIadeTuru == CariIadeTuru.tedarikci;
    try {
      await IadeFisiYazdirici.fisten(
        fisId: id,
        fisTipi: tedarikciMi ? 'Tedarikçi İadesi' : 'İade',
        cariUnvan: _secilenCari?.unvan,
      );
      _msg('İade fişi yazdırılıyor…', err: false);
    } catch (e) {
      _msg('Yazıcı hatası: ${kullaniciyaHataMetni(e)}', err: true);
    }
  }

  // ── Ortak yardımcılar ────────────────────────────────────────────────────
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

  void _yerelStoguDegistir(int urunId, double fark) {
    final i = _tumUrunler.indexWhere((u) => u.id == urunId);
    if (i != -1) {
      _tumUrunler[i] = _tumUrunler[i].copyWith(stok: _tumUrunler[i].stok + fark);
    }
  }

  void _kayitSonrasi() {
    if (widget.otomatikKapat) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    _formSifirla();
    _gecmisYukle();
  }
}