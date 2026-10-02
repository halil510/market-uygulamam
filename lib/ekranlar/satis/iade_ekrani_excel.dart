// ignore_for_file: invalid_use_of_protected_member
// lib/ekranlar/satis/iade_ekrani_excel.dart
//
// İade ekranı — "İADE ALMA" Excel dışarı verme ve içeri alma.
// Başlıklar örnek "İADE ALMA.xlsx" ile birebir aynıdır (bkz.
// ExcelServisi.iadeExcelDisaAl / iadeExcelIceAl); ek sütun eklenebilir.
part of 'iade_ekrani.dart';

extension _IadeExcelExt on _IadeEkraniState {
  UrunModel? _urunBul(int? id) {
    if (id == null) return null;
    for (final u in _tumUrunler) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// Excel koduna (barkod / ürün kodu / alternatif barkod) göre ürün bulur.
  UrunModel? _excelUrunuBul(String kod, String barkod) {
    final adaylar = {kod, barkod}..remove('');
    if (adaylar.isEmpty) return null;
    for (final u in _tumUrunler) {
      if (adaylar.contains(u.barkod) || adaylar.contains(u.kod)) return u;
    }
    for (final u in _tumUrunler) {
      final ek = (u.barkodlar ?? '').split(',').map((e) => e.trim());
      if (ek.any(adaylar.contains)) return u;
    }
    return null;
  }

  // ── Dışarı ver ────────────────────────────────────────────────────────────
  Future<void> _excelDisaVer() async {
    if (_iadeListesi.isEmpty) {
      _msg('İade kaydı yok', err: true);
      return;
    }
    try {
      final satirlar = _iadeListesi.map((i) {
        final u = _urunBul(i['urun_id'] as int?);
        return <String, dynamic>{
          ...i,
          'kod': u?.kod ?? i['barkod'],
          'birim_adi': u?.birimAdi ?? 'ADET',
          'kdv_oran': double.tryParse(u?.kdvOran ?? '') ?? 0.0,
          'kart_satis_fiyati': u?.satisFiyat,
        };
      }).toList();
      final path = await _excelSrv.iadeExcelDisaAl(satirlar);
      await _excelSrv.paylasExcel(path);
    } catch (e) {
      _msg('Excel hatası: $e', err: true);
    }
  }

  // ── İçeri al ──────────────────────────────────────────────────────────────
  Future<void> _excelIceAl() async {
    if (_duzenlemeModu_iadeId != null) {
      _msg('Mevcut bir iade düzenleniyor — önce "Yeni" ile yeni iade başlatın',
          err: true);
      return;
    }
    final secilen = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['xlsx']);
    if (secilen == null || !mounted) return;
    final List<Map<String, dynamic>> satirlar;
    try {
      satirlar = await _excelSrv.iadeExcelIceAl(await secilen.readAsBytes());
    } catch (e) {
      _msg('Excel okunamadı: $e', err: true);
      return;
    }
    if (satirlar.isEmpty) {
      _msg('Excel dosyasında iade edilecek satır bulunamadı', err: true);
      return;
    }

    final eslesen = <({UrunModel urun, double miktar, double fiyat})>[];
    final bulunamayan = <String>[];
    for (final s in satirlar) {
      final u = _excelUrunuBul(s['kod'] as String, s['barkod'] as String);
      if (u == null) {
        bulunamayan.add('Satır ${s['satir']}: ${s['barkod'] != '' ? s['barkod'] : s['kod']}');
        continue;
      }
      final fiyat = ((s['birim_fiyat'] as num?)?.toDouble() ?? 0) > 0
          ? (s['birim_fiyat'] as num).toDouble()
          : u.satisFiyat;
      eslesen.add((urun: u, miktar: (s['miktar'] as num).toDouble(), fiyat: fiyat));
    }
    if (eslesen.isEmpty) {
      _msg('Excel\'deki hiçbir ürün sistemde bulunamadı', err: true);
      return;
    }

    final toplam = eslesen.fold<double>(0, (t, e) => t + e.miktar * e.fiyat);
    if (!mounted) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excel\'den İade Al'),
        content: Text(
          '${eslesen.length} kalem iade alınacak (toplam ${ParaUtils.formatla(toplam)}).\n'
          'Ödeme yöntemi: $_iadeOdemeYontemi'
          '${_secilenCari != null ? '\nCari: ${_secilenCari!.unvan}' : ''}\n'
          '${bulunamayan.isNotEmpty ? '\n${bulunamayan.length} satır sistemde bulunamadı, atlanacak.\n' : ''}'
          '\nStok artar ve kasa/cari hareketi oluşur. Devam edilsin mi?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İade Al')),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    setState(() => _yukleniyor = true);
    var basarili = 0;
    final hatalar = <String>[];
    try {
      if (_oturumFisNo.isEmpty) _oturumFisNo = await BelgeNoServisi().uret('iade');
      for (final e in eslesen) {
        try {
          final toplamKalem = e.miktar * e.fiyat;
          final iadeId = await IadeIslemServisi().manuelKalemEkle(
            oturumIadeId: _oturumIadeId,
            cariId: _secilenCari?.id,
            cariTipi: _secilenCari?.cariTipi,
            fisNo: _oturumFisNo,
            urunId: e.urun.id!,
            urunAdi: e.urun.urunAdi,
            miktar: e.miktar,
            fiyat: e.fiyat,
            toplam: toplamKalem,
            neden: 'Excel iade',
            odemeYontemi: _iadeOdemeYontemi,
            kullaniciId: AuthServisi().aktifId,
            kullaniciAdi: AuthServisi().aktifAd,
          );
          _oturumIadeId ??= iadeId;
          final idx = _iadeListesi.indexWhere((x) => x['urun_id'] == e.urun.id);
          if (idx != -1) {
            final m = _iadeListesi.removeAt(idx);
            _iadeListesi.insert(0, {
              ...m,
              'miktar': (m['miktar'] as double) + e.miktar,
              'toplam_tutar': (m['toplam_tutar'] as double) + toplamKalem,
            });
          } else {
            _iadeListesi.insert(0, {
              'iade_id': iadeId,
              'urun_id': e.urun.id,
              'tarih': DateTime.now(),
              'urun_adi': e.urun.urunAdi,
              'barkod': e.urun.barkod ?? '',
              'miktar': e.miktar,
              'birim_fiyat': e.fiyat,
              'iskonto_oran': 0.0,
              'iskonto_tutar': 0.0,
              'toplam_tutar': toplamKalem,
              'musteri_adi': _secilenCari?.unvan ?? 'Kayıtsız Müşteri',
              'cari_id': _secilenCari?.id,
              'fis_no': _oturumFisNo,
            });
          }
          final si = _tumUrunler.indexWhere((u) => u.id == e.urun.id);
          if (si != -1) {
            _tumUrunler[si] = _tumUrunler[si].copyWith(stok: _tumUrunler[si].stok + e.miktar);
          }
          basarili++;
        } catch (err) {
          hatalar.add('${e.urun.urunAdi}: $err');
        }
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
    _gecmisYukle();
    final ozet = '$basarili kalem iade alındı'
        '${hatalar.isNotEmpty ? ', ${hatalar.length} hata' : ''}'
        '${bulunamayan.isNotEmpty ? ', ${bulunamayan.length} satır bulunamadı' : ''}';
    _msg(ozet, err: hatalar.isNotEmpty && basarili == 0);
  }
}
