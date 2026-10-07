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
    if (_duzenlemeModuIadeId != null) {
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

    final eslesen = <({UrunModel urun, double miktar, double fiyat, double iskonto})>[];
    final bulunamayan = <String>[];
    for (final s in satirlar) {
      final u = _excelUrunuBul(s['kod'] as String, s['barkod'] as String);
      if (u == null) {
        bulunamayan.add('Satır ${s['satir']}: ${s['barkod'] != '' ? s['barkod'] : s['kod']}');
        continue;
      }
      // 🔴 DÜZELTME (kullanıcı bulgusu: "excelden içe alırken iskonto var ama
      // alınmamış"): fiyat olarak Excel'deki İNDİRİMSİZ (brüt) birim fiyat ve
      // indirim oranı ayrı ayrı alınır; kayıt manuel iadedeki gibi
      // brüt × (1 − indirim) ile yapılır ve listede indirim görünür. Excel'de
      // fiyat yoksa ürün kartı fiyatına yine Excel'deki indirim uygulanır.
      final brut = (s['brut_fiyat'] as num?)?.toDouble() ?? 0;
      final birim = (s['birim_fiyat'] as num?)?.toDouble() ?? 0;
      final fiyat = brut > 0 ? brut : (birim > 0 ? birim : u.satisFiyat);
      final iskonto = (s['iskonto_oran'] as num?)?.toDouble() ?? 0;
      eslesen.add((
        urun: u,
        miktar: (s['miktar'] as num).toDouble(),
        fiyat: fiyat,
        iskonto: iskonto > 0 && iskonto < 100 ? iskonto : 0.0,
      ));
    }
    if (eslesen.isEmpty) {
      _msg('Excel\'deki hiçbir ürün sistemde bulunamadı', err: true);
      return;
    }

    final toplam = eslesen.fold<double>(
        0, (t, e) => t + ParaUtils.yuvarla(e.miktar * e.fiyat * (1 - e.iskonto / 100)));
    final iskontoluKalem = eslesen.where((e) => e.iskonto > 0).length;
    if (!mounted) return;

    // 🔴 DÜZELTME (kullanıcı bulgusu: "excelden iade aldım, cari seçtim, cariye
    // yazmadı"): bu akış manuel akıştaki gibi iade YÖNTEMİNİ sormuyordu —
    // cari seçili olsa bile yöntem varsayılan "Nakit" kalıyor, cari hareketi
    // "bakiyeyi etkilemez" (nötr) yazılıyor ve para KASADAN çıkıyordu.
    // Artık onay penceresinde cari seçilir/değiştirilir ve yöntem seçilir;
    // kayıtlı cari seçilince varsayılan 'Cari' (borcundan düşülür).
    var cari = _secilenCari;
    var yontem = _iadeOdemeYontemi;
    if (cari?.id != null && yontem == 'Nakit') yontem = 'Cari';
    if (cari?.id == null && yontem == 'Cari') yontem = 'Nakit';

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Excel’den İade Al'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${eslesen.length} kalem iade alınacak (toplam ${ParaUtils.formatla(toplam)}).'),
              if (iskontoluKalem > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$iskontoluKalem kalemde Excel’deki indirim uygulandı.',
                      style: const TextStyle(fontSize: 12, color: Colors.green)),
                ),
              if (bulunamayan.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${bulunamayan.length} satır sistemde bulunamadı, atlanacak.',
                      style: const TextStyle(fontSize: 12, color: Colors.orange)),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_outline, size: 18),
                label: Text(cari?.id != null ? 'Cari: ${cari!.unvan}' : 'Cari seç (isteğe bağlı)'),
                onPressed: () async {
                  final sec = await _cariSecimDialog();
                  if (sec == null) return;
                  ss(() {
                    cari = sec;
                    if (sec.id != null) {
                      yontem = 'Cari';
                    } else if (yontem == 'Cari') {
                      yontem = 'Nakit';
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: yontem,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'İade Ödeme Yöntemi', border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem(value: 'Nakit', child: Text('Nakit (kasadan)')),
                  const DropdownMenuItem(value: 'Kart/Banka', child: Text('Kart/Banka (POS’tan)')),
                  if (cari?.id != null)
                    const DropdownMenuItem(value: 'Cari', child: Text('Veresiye / Cari (borca yaz)')),
                ],
                onChanged: (v) => ss(() => yontem = v ?? yontem),
              ),
              const SizedBox(height: 8),
              Text(
                yontem == 'Cari'
                    ? 'Kasadan nakit çıkışı OLMAZ — tutar ${cari?.unvan ?? ''} cari bakiyesine gerçekten işlenir.'
                    : yontem == 'Nakit'
                        ? 'Tutar kasadan nakit çıkışı olarak yazılır${cari?.id != null ? ' (cari bakiyesi DEĞİŞMEZ)' : ''}.'
                        : 'Kasadan çıkış yazılmaz — tutarı POS’tan ayrıca iade etmeniz gerekir.',
                style: TextStyle(
                    fontSize: 12,
                    color: yontem == 'Cari' ? Colors.blue.shade800 : Colors.orange.shade800,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text('Stok artar. Devam edilsin mi?', style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İade Al')),
          ],
        ),
      ),
    );
    if (onay != true || !mounted) return;

    // Seçilen cari ve yöntem, kalem kaydı sırasında kullanılan alanlara yazılır.
    _secilenCari = cari;
    _iadeOdemeYontemi = yontem;
    setState(() => _yukleniyor = true);
    var basarili = 0;
    final hatalar = <String>[];
    try {
      if (_oturumFisNo.isEmpty) _oturumFisNo = await BelgeNoServisi().uret('iade');
      for (final e in eslesen) {
        try {
          final iskontoTutar = ParaUtils.yuvarla(e.miktar * e.fiyat * (e.iskonto / 100));
          final toplamKalem = ParaUtils.yuvarla(e.miktar * e.fiyat) - iskontoTutar;
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
            iskontoOran: e.iskonto,
          );
          _oturumIadeId ??= iadeId;
          final idx = _iadeListesi.indexWhere((x) => x['urun_id'] == e.urun.id);
          if (idx != -1) {
            final m = _iadeListesi.removeAt(idx);
            _iadeListesi.insert(0, {
              ...m,
              'miktar': (m['miktar'] as double) + e.miktar,
              'toplam_tutar': (m['toplam_tutar'] as double) + toplamKalem,
              'iskonto_tutar': ((m['iskonto_tutar'] as num?)?.toDouble() ?? 0) + iskontoTutar,
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
              'iskonto_oran': e.iskonto,
              'iskonto_tutar': iskontoTutar,
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
    // Cari/Kasa bakiyeleri değişti — başka ekranlarda eski veri kalmasın
    // (hızlı iade akışındaki AYNI yenileme; Excel akışında eksikti).
    if (_secilenCari?.id != null) {
      ref.invalidate(cariDetayProvider(_secilenCari!.id!));
      ref.read(carilerProvider.notifier).yukle();
    }
    ref.invalidate(kasaRaporProvider);
    final ozet = '$basarili kalem iade alındı'
        '${hatalar.isNotEmpty ? ', ${hatalar.length} hata' : ''}'
        '${bulunamayan.isNotEmpty ? ', ${bulunamayan.length} satır bulunamadı' : ''}';
    _msg(ozet, err: hatalar.isNotEmpty && basarili == 0);
  }
}
