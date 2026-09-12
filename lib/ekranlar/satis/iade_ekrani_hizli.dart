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
// lib/ekranlar/satis/iade_ekrani_hizli.dart
//
// "Hızlı" (Hızlı Barkod İade) sekmesinin mantığı buraya taşındı — aynı
// part/part of yöntemiyle. Davranış/mantık AYNEN korunuyor.
part of 'iade_ekrani.dart';

extension _HizliTabExt on _IadeEkraniState {
  Future<void> _hizliBarkod() async {
    final barkod = await _barkodSrv.barkodTara(context);
    if (barkod == null || barkod.isEmpty) return;
    final urun = await _urunDepo.barkodlaGetir(barkod);
    if (!mounted) return;
    if (urun != null) {
      setState(() {
        // Aynı barkod tekrar gelirse üstüne ilave et
        if (_hizliMap.containsKey(urun.id)) {
          _hizliMap[urun.id]!.adet++;
          _msg('${urun.urunAdi} — toplam adet: ${_hizliMap[urun.id]!.adet}',
              err: false);
        } else {
          _hizliMap[urun.id!] = _HizliItem(urun: urun);
          _msg('${urun.urunAdi} eklendi', err: false);
        }
      });
    } else {
      _msg('Ürün bulunamadı', err: true);
    }
  }

  Future<void> _hizliKaydet() async {
    if (_hizliMap.isEmpty) {
      _msg('Liste boş', err: true);
      return;
    }
    if (!mounted) return;

    // 🔴🔴 FAZ 1 madde 1 (kullanıcı onayıyla): bu akışın belirli bir
    // orijinal satışa bağlantısı yok (barkod ile serbest iade), bu
    // yüzden "orijinal ödeme yöntemi" bilinmiyor — kullanıcı iade
    // ödeme yöntemini burada seçiyor (varsayılan: Nakit).
    String secilenYontem = 'Nakit';
    final toplamOnizleme = _hizliMap.values
        .fold<double>(0.0, (s, i) => s + i.adet * i.urun.satisFiyati);
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text('Toplu İade Onayla'),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${_hizliMap.length} kalem, toplam ${ParaUtils.formatla(toplamOnizleme)} iade edilecek.'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: secilenYontem,
                        decoration: const InputDecoration(
                            labelText: 'İade Ödeme Yöntemi',
                            border: OutlineInputBorder(),
                            isDense: true),
                        items: const [
                          DropdownMenuItem(
                              value: 'Nakit', child: Text('Nakit (kasadan)')),
                          DropdownMenuItem(
                              value: 'Kart/Banka',
                              child: Text('Kart/Banka (POS\'tan)')),
                        ],
                        onChanged: (v) =>
                            setS(() => secilenYontem = v ?? secilenYontem),
                      ),
                      if (secilenYontem != 'Nakit') ...[
                        const SizedBox(height: 8),
                        Text(
                          'Bu seçenekte kasadan nakit çıkışı OLUŞTURULMAZ — iade '
                          'tutarını POS cihazından ayrıca müşteriye iade etmeniz gerekir.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.orange.shade800),
                        ),
                      ],
                    ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('İptal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('İade Et')),
                ],
              )),
    );
    if (onay != true || !mounted) return;
    final nakitIade = secilenYontem == 'Nakit';

    setState(() => _yukleniyor = true);
    final db = await Veritabani().db;
    try {
      final fisNo = await Veritabani()
          .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);
      final iadeGlobalId = const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      final kullaniciId = AuthServisi().aktifId;
      final toplamIade = _hizliMap.values
          .fold<double>(0.0, (s, i) => s + i.adet * i.urun.satisFiyati);
      late final int iadeId;

      // 🔴 Derin analizde bulundu: bu akış ÖNCEDEN her ürün için AYRI
      // bir transaction açan StokDeposu.stokGir()'i döngü içinde
      // çağırıyordu, sonra kasa/cari güncellemeleri de kendi ayrı
      // transaction'larında yapılıyordu. Liste 5 üründen oluşuyorsa ve
      // uygulama 3'üncü üründen sonra kapanırsa: 'iade' kaydı TÜM 5
      // ürünün toplamını gösteriyor ama sadece 3'ünün stoğu geri
      // eklenmiş, kasaya hiç para işlenmemiş oluyordu — yarım kalan,
      // tutarsız bir durum. Artık iade + tüm kalemler + stok + kasa +
      // cari TEK transaction içinde; ya hep birden yazılır ya hiç.
      await db.transaction((txn) async {
        iadeId = await txn.insert('iade', {
          'global_id': iadeGlobalId,
          'cari_id': _secilenCari?.id,
          'fis_no': fisNo,
          'tarih': now,
          'toplam_tutar': toplamIade,
          'iade_nedeni': 'Toplu iade',
          'durum': 'tamamlandi',
          'kasiyer_id': kullaniciId,
        });

        for (final item in _hizliMap.values) {
          final fiyat = item.urun.satisFiyati;
          final toplam = item.adet * fiyat;

          await txn.insert('iade_kalem', {
            'global_id': const Uuid().v4(),
            'iade_id': iadeId,
            'urun_id': item.urun.id,
            'urun_adi': item.urun.urunAdi,
            'miktar': item.adet.toDouble(),
            'birim_fiyat': fiyat,
            'toplam': toplam,
          });

          final urunRows = await txn.query('urunler',
              columns: ['stok'], where: 'id = ?', whereArgs: [item.urun.id]);
          if (urunRows.isNotEmpty) {
            final onceki = (urunRows.first['stok'] as num).toDouble();
            await txn.update(
                'urunler', {'stok': onceki + item.adet, 'last_updated': now},
                where: 'id = ?', whereArgs: [item.urun.id]);
            await txn.insert('stok_hareket', {
              'global_id': const Uuid().v4(),
              'urun_id': item.urun.id,
              'hareket_turu': 'Iade Giris',
              'miktar': item.adet.toDouble(),
              'onceki_stok': onceki,
              'sonraki_stok': onceki + item.adet,
              'tarih': now,
              'referans_id': iadeId,
              'referans_turu': 'iade',
              'kullanici_id': kullaniciId,
              'aciklama': 'Toplu iade: $fisNo',
            });
          }
        }

        // Kasa — SADECE Nakit iade seçildiyse oluşturulur (bkz.
        // iade_ekrani_fis.dart'taki aynı düzeltme/gerekçe).
        if (nakitIade && toplamIade > 0) {
          final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) - toplamIade;
          await txn.insert('kasa_hareketleri', {
            'global_id': const Uuid().v4(),
            'hareket_tipi': 'İade',
            'tutar': toplamIade,
            'bakiye_sonrasi': kasaBakiye,
            'referans_id': iadeId,
            'referans_turu': 'iade',
            'tarih': now,
            'sube_id': AktifSubeServisi().subeId,
            'aciklama': 'Toplu iade: $fisNo',
            'kullanici_id': kullaniciId,
          });
        }

        if (_secilenCari != null && toplamIade > 0) {
          await txn.insert('cari_hareket', {
            'global_id': const Uuid().v4(),
            'cari_id': _secilenCari!.id,
            'tarih': now,
            'fis_tipi': 'İade',
            'fis_id': iadeId,
            'fis_no': fisNo,
            'aciklama': 'Toplu iade: $fisNo',
            'borc': 0,
            'alacak': toplamIade,
            'odeme_turu': 'Nakit',
            'kullanici': AuthServisi().aktifAd,
          });
          await txn.rawUpdate(
              'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=?) WHERE id=?',
              [_secilenCari!.id, _secilenCari!.id]);
        }
      }); // transaction sonu

      // Transaction kalıcı olduktan sonra buluta bildir.
      try {
        final iadeSatir = await db.query('iade',
            where: 'id = ?', whereArgs: [iadeId], limit: 1);
        if (iadeSatir.isNotEmpty)
          BulutManager()
              .upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
        for (final item in _hizliMap.values) {
          final kalemSatir = await db.query('iade_kalem',
              where: 'iade_id = ? AND urun_id = ?',
              whereArgs: [iadeId, item.urun.id],
              limit: 1);
          if (kalemSatir.isNotEmpty)
            BulutManager().upsert(
                'iade_kalem', Map<String, dynamic>.from(kalemSatir.first));
          final urunSatir = await db.query('urunler',
              where: 'id = ?', whereArgs: [item.urun.id], limit: 1);
          if (urunSatir.isNotEmpty)
            BulutManager()
                .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
          final stokSatir = await db.query('stok_hareket',
              where: 'referans_id = ? AND referans_turu = ? AND urun_id = ?',
              whereArgs: [iadeId, 'iade', item.urun.id],
              orderBy: 'id DESC',
              limit: 1);
          if (stokSatir.isNotEmpty)
            BulutManager().upsert(
                'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
          _iadeListesi.add({
            'tarih': DateTime.now(),
            'urun_adi': item.urun.urunAdi,
            'barkod': item.urun.barkod ?? '',
            'miktar': item.adet.toDouble(),
            'birim_fiyat': item.urun.satisFiyati,
            'toplam_tutar': item.adet * item.urun.satisFiyati,
            'musteri_adi': _secilenCari?.unvan ?? 'Perakende',
            'aciklama': 'Toplu iade - $fisNo',
          });
        }
        if (toplamIade > 0) {
          final kasaSatir = await db.query('kasa_hareketleri',
              where: 'referans_id = ? AND referans_turu = ?',
              whereArgs: [iadeId, 'iade'],
              orderBy: 'id DESC',
              limit: 1);
          if (kasaSatir.isNotEmpty)
            BulutManager().upsert(
                'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
        }
        if (_secilenCari != null && toplamIade > 0) {
          final cariHareketSatir = await db.query('cari_hareket',
              where: "fis_id = ? AND cari_id = ? AND fis_tipi = 'İade'",
              whereArgs: [iadeId, _secilenCari!.id],
              limit: 1);
          if (cariHareketSatir.isNotEmpty) {
            BulutManager().upsert('cari_hareket',
                Map<String, dynamic>.from(cariHareketSatir.first));
          }
          final cariSatir = await db.query('cari',
              where: 'id = ?', whereArgs: [_secilenCari!.id], limit: 1);
          if (cariSatir.isNotEmpty)
            BulutManager()
                .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Toplu iade bulut bildirimi hatası: $e');
      }

      final n = _hizliMap.length;
      if (!mounted) return;
      _hizliMap.clear();
      if (mounted) setState(() {});
      await _verileriYukle();
      // Cari/Kasa bakiyeleri değişti — başka ekranlarda (Cari Detay/
      // Liste, Kasa Raporu) eski veri kalmasın.
      if (_secilenCari != null) {
        ref.invalidate(cariDetayProvider(_secilenCari!.id!));
        ref.read(carilerProvider.notifier).yukle();
      }
      ref.invalidate(kasaRaporProvider);
      _msg(nakitIade
          ? '$n ürün iade edildi (kasadan nakit ödendi)'
          : '$n ürün iade edildi — tutarı POS cihazından ayrıca müşteriye iade edin');
    } catch (e) {
      _msg('Hata: $e', err: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Widget _hizliTab() => Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                  child: FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Barkod Okut'),
                style: FilledButton.styleFrom(
                    backgroundColor: _R.primary, foregroundColor: Colors.white),
                onPressed: _hizliBarkod,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Ürün Ara'),
                onPressed: () {
                  _tab.animateTo(0);
                  _aramaFocus.requestFocus();
                },
              )),
            ])),
        if (_hizliMap.isEmpty)
          Expanded(
              child: Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: Color.fromARGB(
                            20, _R.blue.red, _R.blue.green, _R.blue.blue),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.add_shopping_cart,
                        size: 52, color: _R.blue)),
                const SizedBox(height: 16),
                const Text('Hızlı iade listesi boş',
                    style: TextStyle(fontSize: 15, color: _R.textL)),
                const SizedBox(height: 6),
                const Text('Barkod okutarak veya arama yaparak ürün ekleyin',
                    style: TextStyle(fontSize: 12, color: _R.textL),
                    textAlign: TextAlign.center),
              ])))
        else
          Expanded(
              child: Column(children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_hizliMap.length} çeşit ürün',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextButton.icon(
                          icon: const Icon(Icons.delete_sweep, size: 16),
                          label: const Text('Temizle'),
                          onPressed: () {
                            _hizliMap.clear();
                            if (mounted) setState(() {});
                          }),
                    ])),
            Expanded(
                child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _hizliMap.length,
              itemBuilder: (_, i) {
                final item = _hizliMap.values.toList()[i];
                return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                        color: TsRenk.kart(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: TsRenk.ayirac(context))),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(item.urun.urunAdi,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              Text(item.urun.barkod ?? '',
                                  style: const TextStyle(
                                      fontSize: 11, color: _R.textL)),
                            ])),
                        Row(children: [
                          IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 32),
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 22),
                              onPressed: () => setState(() {
                                    if (item.adet <= 1)
                                      _hizliMap.remove(item.urun.id);
                                    else
                                      item.adet--;
                                  })),
                          Text('${item.adet}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18)),
                          IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 32),
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 22),
                              onPressed: () => setState(() => item.adet++)),
                        ]),
                      ]),
                    ));
              },
            )),
            Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _yukleniyor ? null : _hizliKaydet,
                      style: FilledButton.styleFrom(
                          backgroundColor: _R.orange,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.assignment_return),
                      label: Text('${_hizliMap.length} Ürünü İade Et',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ))),
          ])),
      ]);
}
