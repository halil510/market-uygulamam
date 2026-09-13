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
// lib/ekranlar/satis/iade_ekrani_fis.dart
//
// "Fiş" (Fiş No ile İade) sekmesinin mantığı buraya taşındı — aynı
// part/part of yöntemiyle (bkz. iade_ekrani_gecmis.dart'taki not).
// Davranış/mantık AYNEN korunuyor, sadece organizasyon değişti.
part of 'iade_ekrani.dart';

extension _FisTabExt on _IadeEkraniState {
  Future<void> _fisBul() async {
    final no = _fisNoCtrl.text.trim();
    if (no.isEmpty) return;
    _bulunanSatis = null;
    _fisIadeEdilenMiktar = {};
    if (mounted) setState(() {});
    final satislar = await _satisDepo.bugunkunSatislar();
    final satis = satislar
        .where((s) => s.fisNo == no || s.id?.toString() == no)
        .firstOrNull;
    _bulunanSatis = satis;
    if (satis != null)
      _fisIadeEdilenMiktar = await _fisIadeliMiktarlariGetir(satis.id!);
    if (mounted) setState(() {});
    if (satis == null && mounted) _msg('Fiş bulunamadı: $no', err: true);
  }

  /// Bu satıştan daha önce iade edilmiş miktarları ürün bazında toplar
  /// (satis_id ile ilişkili tüm 'iade' kayıtlarındaki 'iade_kalem' satırları).
  Future<Map<int, double>> _fisIadeliMiktarlariGetir(int satisId) async {
    final db = await Veritabani().db;
    final rows = await db.rawQuery('''
      SELECT ik.urun_id AS urun_id, SUM(ik.miktar) AS toplam
      FROM iade_kalem ik
      JOIN iade i ON ik.iade_id = i.id
      WHERE i.satis_id = ?
      GROUP BY ik.urun_id
    ''', [satisId]);
    return {
      for (final r in rows)
        (r['urun_id'] as num).toInt(): (r['toplam'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<void> _fisKalemIade(SatisKalemModel kalem) async {
    if (_bulunanSatis == null) return;

    // Çift iade koruması: bu kalemden daha önce ne kadar iade edilmiş?
    final oncekiIadeMiktar = _fisIadeEdilenMiktar[kalem.urunId] ?? 0;
    final kalanMiktar = kalem.miktar - oncekiIadeMiktar;
    if (kalanMiktar <= 0) {
      _msg('${kalem.urunAdi} bu fişten zaten tamamen iade edilmiş', err: true);
      return;
    }

    // 🔴🔴 FAZ 1 madde 1 (kullanıcı onayıyla): iade artık orijinal
    // satışın ödeme yöntemini dikkate alıyor — kart/banka ile ödenmiş
    // bir satışın iadesi kasadan nakit ÇIKARMIYOR (POS cihazından ayrıca
    // iade edilmesi gerekiyor), sadece Nakit seçiliyse kasa hareketi
    // oluşuyor. Varsayılan, orijinal ödeme yöntemidir; kullanıcı
    // isterse değiştirebilir.
    String secilenYontem =
        _bulunanSatis!.odemeYontemi == 'Nakit' ? 'Nakit' : 'Kart/Banka';
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text('İade Onayla'),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${kalem.urunAdi} ($kalanMiktar adet) iade edilecek.'),
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
                          'tutarını POS cihazından ayrıca müşterinin kartına iade '
                          'etmeniz gerekir.',
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
                      style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: _R.orange),
                      child: const Text('İade Et')),
                ],
              )),
    );
    if (onay != true) return;
    final nakitIade = secilenYontem == 'Nakit';

    final db = await Veritabani().db;
    final fisNo = await Veritabani()
        .fisNoUret('iade', subeId: AktifSubeServisi().subeId ?? 1);
    // Kısmen daha önce iade edilmiş olabileceği için toplam, KALAN
    // miktar üzerinden hesaplanıyor (kalem.toplamTutar'ın tamamı değil).
    final oranli = kalem.miktar == 0 ? 0.0 : kalanMiktar / kalem.miktar;
    final toplam = kalem.toplamTutar * oranli;
    final now = DateTime.now().toIso8601String();
    final kullaniciId = AuthServisi().aktifId;
    late final int iadeId;
    final guncellenenLotIdleri = <int>{};
    // FAZ: iade → lot geri ekleme. Bu ekran (diğer iki iade ekranından
    // farklı olarak) orijinal satışa (satis_id) referans veriyor, bu
    // yüzden SADECE burada orijinal stok_hareket kayıtlarından (FAZ 5
    // FEFO tüketiminin bıraktığı lot_id'li satırlar) hangi lot(lar)ın
    // tüketildiği bulunup iade miktarı aynı lotlara geri eklenebiliyor.
    // Aşağıda oluşturulan HER stok_hareket satırının global_id'si, commit
    // sonrası tek tek buluta bildirilmek üzere toplanıyor (bkz.
    // satis_tamamlama_servisi.dart'taki stokHareketGidleri ile AYNI desen).
    final stokHareketGidleri = <String>[];

    // ── TEK TRANSACTION: iade + kalem + stok + kasa + cari ──────────────
    // 🔴 Derin analizde bulundu: bu fonksiyon ÖNCEDEN 4 AYRI işlem
    // yapıyordu (iade insert'i + StokDeposu.stokGir + KasaDeposu
    // .hareketEkle + CariDeposu.hareketEkle, her biri kendi transaction'ı
    // içinde) — aralarında uygulama kapanır/güç kesilirse, iade kaydı
    // oluşup stok/kasa/cari güncellenmemiş yarım bir durum kalabiliyordu.
    // Ayrıca AYNI kalem sınırsız kez "İade Et" ile tekrar tekrar iade
    // edilebiliyordu (kasadan mükerrer para çıkışı + stok şişmesi) çünkü
    // hangi kalemlerin zaten iade edildiğine dair hiçbir kontrol yoktu.
    await db.transaction((txn) async {
      iadeId = await txn.insert('iade', {
        'global_id': const Uuid().v4(),
        'satis_id': _bulunanSatis!.id,
        'cari_id': _bulunanSatis!.cariId,
        'fis_no': fisNo,
        'tarih': now,
        'toplam_tutar': toplam,
        'iade_nedeni': 'Fiş iadesi',
        'durum': 'tamamlandi',
        'kasiyer_id': kullaniciId,
      });

      await txn.insert('iade_kalem', {
        'global_id': const Uuid().v4(),
        'iade_id': iadeId,
        'urun_id': kalem.urunId,
        'urun_adi': kalem.urunAdi,
        'miktar': kalanMiktar,
        'birim_fiyat': kalem.birimFiyat,
        'toplam': toplam,
      });

      // Stok geri ekle
      final urunRows = await txn.query('urunler',
          columns: ['stok', 'lot_takibi'],
          where: 'id = ?', whereArgs: [kalem.urunId]);
      if (urunRows.isNotEmpty) {
        final onceki = (urunRows.first['stok'] as num).toDouble();
        final lotTakibi =
            (urunRows.first['lot_takibi'] as int? ?? 0) == 1;

        // (lotId veya null, miktar) — lot_takibi=0 ürünlerde davranış
        // BİREBİR eskisiyle aynı: tek satır, lot_id yok.
        final dagilim = <MapEntry<int?, double>>[];
        if (lotTakibi) {
          final tuketimSatirlari = await txn.query('stok_hareket',
              where: 'referans_id = ? AND referans_turu = ? AND urun_id = ?',
              whereArgs: [_bulunanSatis!.id, 'satis', kalem.urunId],
              orderBy: 'id ASC');
          // Daha önce bu üründen kısmen iade edilmiş olabilir — ledger'da
          // o kadarlık kısmı zaten "geri eklenmiş" sayıp atlıyoruz, aynı
          // lota mükerrer geri ekleme yapılmasın diye.
          var atla = oncekiIadeMiktar;
          var kalanDagitilacak = kalanMiktar;
          for (final satir in tuketimSatirlari) {
            if (kalanDagitilacak <= 0.005) break;
            var tSatirMiktar = (satir['miktar'] as num?)?.toDouble() ?? 0;
            if (atla > 0.005) {
              final atlanan = atla < tSatirMiktar ? atla : tSatirMiktar;
              tSatirMiktar -= atlanan;
              atla -= atlanan;
              if (tSatirMiktar <= 0.005) continue;
            }
            final buSatirdanIadeEdilecek =
                kalanDagitilacak < tSatirMiktar ? kalanDagitilacak : tSatirMiktar;
            if (buSatirdanIadeEdilecek <= 0.005) continue;
            dagilim.add(MapEntry(satir['lot_id'] as int?, buSatirdanIadeEdilecek));
            kalanDagitilacak -= buSatirdanIadeEdilecek;
          }
          // Orijinal tüketim ledger'ı eksik/yetersizse (ör. satış lot
          // özelliğinden ÖNCE yapılmış) kalanı lot bilgisi olmadan ekle —
          // iade ASLA engellenmez.
          if (kalanDagitilacak > 0.005) {
            dagilim.add(MapEntry(null, kalanDagitilacak));
          }
        } else {
          dagilim.add(MapEntry(null, kalanMiktar));
        }

        var su = onceki;
        for (final girdi in dagilim) {
          final miktar = girdi.value;
          final yeniSu = su + miktar;
          final gid = const Uuid().v4();
          await txn.insert('stok_hareket', {
            'global_id': gid,
            'urun_id': kalem.urunId,
            'hareket_turu': 'Iade Giris',
            'miktar': miktar,
            'onceki_stok': su,
            'sonraki_stok': yeniSu,
            'tarih': now,
            'referans_id': iadeId,
            'referans_turu': 'iade',
            'kullanici_id': kullaniciId,
            'aciklama': 'Fiş iadesi: $fisNo',
            if (girdi.key != null) 'lot_id': girdi.key,
          });
          stokHareketGidleri.add(gid);
          if (girdi.key != null) {
            await txn.rawUpdate(
                'UPDATE lot_seri SET miktar = miktar + ?, last_updated = ? WHERE id = ?',
                [miktar, now, girdi.key]);
            guncellenenLotIdleri.add(girdi.key!);
          }
          su = yeniSu;
        }
        await txn.update('urunler', {'stok': su, 'last_updated': now},
            where: 'id = ?', whereArgs: [kalem.urunId]);
      }

      // Kasa — SADECE Nakit iade seçildiyse oluşturulur. Kart/Banka
      // iadesinde fiziksel kasadan hiç para çıkmıyor (POS'tan ayrıca
      // iade ediliyor), bu yüzden burada kasa_hareketleri'ne HİÇ
      // yazılmaz — aksi halde kasa gerçekte olmayan bir nakit çıkışı
      // gösterirdi.
      if (nakitIade) {
        // KasaDeposu ile aynı güvenli bakiye sorgusu (bkz. manuel
        // sekmedeki aynı düzeltme: deleted_at IS NULL + tarih DESC).
        final kasaBakiye = await _kasaDepo.sonBakiyeTxn(txn) - toplam;
        await txn.insert('kasa_hareketleri', {
          'global_id': const Uuid().v4(),
          'hareket_tipi': 'İade',
          'tutar': toplam,
          'bakiye_sonrasi': kasaBakiye,
          'referans_id': iadeId,
          'referans_turu': 'iade',
          'tarih': now,
          'sube_id': AktifSubeServisi().subeId,
          'aciklama': 'Fiş iadesi: $fisNo',
          'kullanici_id': kullaniciId,
        });
      }

      // Cari
      if (_bulunanSatis!.cariId != null) {
        await txn.insert('cari_hareket', {
          'global_id': const Uuid().v4(),
          'cari_id': _bulunanSatis!.cariId,
          'tarih': now,
          'fis_tipi': 'İade',
          'fis_id': iadeId,
          'fis_no': fisNo,
          'aciklama': 'Fiş iadesi: $fisNo',
          'borc': 0,
          'alacak': toplam,
          'odeme_turu': 'Nakit',
          'kullanici': AuthServisi().aktifAd,
        });
        await txn.rawUpdate(
            'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=?) WHERE id=?',
            [_bulunanSatis!.cariId, _bulunanSatis!.cariId]);
      }
    }); // transaction sonu

    // Transaction başarıyla kapandıktan sonra buluta bildir (senkron
    // sistemi projede her yerde bu şekilde: önce kalıcı yaz, sonra
    // bildir — bkz. manuel sekmedeki aynı desen).
    try {
      final iadeSatir = await db.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (iadeSatir.isNotEmpty)
        BulutManager()
            .upsert('iade', Map<String, dynamic>.from(iadeSatir.first));
      final kalemSatir = await db.query('iade_kalem',
          where: 'iade_id = ? AND urun_id = ?',
          whereArgs: [iadeId, kalem.urunId],
          limit: 1);
      if (kalemSatir.isNotEmpty)
        BulutManager()
            .upsert('iade_kalem', Map<String, dynamic>.from(kalemSatir.first));
      final urunSatir = await db.query('urunler',
          where: 'id = ?', whereArgs: [kalem.urunId], limit: 1);
      if (urunSatir.isNotEmpty)
        BulutManager()
            .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
      // Lot-farkındalıklı iadede BİRDEN FAZLA stok_hareket satırı açılmış
      // olabilir (her tüketilen lot için ayrı) — hepsi tek tek bildirilir.
      for (final gid in stokHareketGidleri) {
        final s = await db.query('stok_hareket',
            where: 'global_id = ?', whereArgs: [gid], limit: 1);
        if (s.isNotEmpty) {
          BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(s.first));
        }
      }
      for (final lotId in guncellenenLotIdleri) {
        final l = await db.query('lot_seri',
            where: 'id = ?', whereArgs: [lotId], limit: 1);
        if (l.isNotEmpty) {
          BulutManager().upsert('lot_seri', Map<String, dynamic>.from(l.first));
        }
      }
      final kasaSatir = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?',
          whereArgs: [iadeId, 'iade'],
          orderBy: 'id DESC',
          limit: 1);
      if (kasaSatir.isNotEmpty)
        BulutManager().upsert(
            'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
      if (_bulunanSatis!.cariId != null) {
        final cariHareketSatir = await db.query('cari_hareket',
            where: "fis_id = ? AND cari_id = ? AND fis_tipi = 'İade'",
            whereArgs: [iadeId, _bulunanSatis!.cariId],
            limit: 1);
        if (cariHareketSatir.isNotEmpty) {
          BulutManager().upsert('cari_hareket',
              Map<String, dynamic>.from(cariHareketSatir.first));
        }
        final cariSatir = await db.query('cari',
            where: 'id = ?', whereArgs: [_bulunanSatis!.cariId], limit: 1);
        if (cariSatir.isNotEmpty)
          BulutManager()
              .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Fiş iadesi bulut bildirimi hatası: $e');
    }

    if (_bulunanSatis!.cariId != null) {
      ref.invalidate(cariDetayProvider(_bulunanSatis!.cariId!));
      ref.read(carilerProvider.notifier).yukle();
    }
    ref.invalidate(kasaRaporProvider);

    // Bu kalemin artık ne kadarının iade edildiğini güncelle — aynı
    // kalemin tekrar "İade Et" ile mükerrer iade edilmesini önler.
    _fisIadeEdilenMiktar = {
      ..._fisIadeEdilenMiktar,
      kalem.urunId: oncekiIadeMiktar + kalanMiktar,
    };

    _iadeListesi.add({
      'tarih': DateTime.now(),
      'urun_adi': kalem.urunAdi,
      'miktar': kalanMiktar,
      'birim_fiyat': kalem.birimFiyat,
      'toplam_tutar': toplam,
      'musteri_adi': _bulunanSatis!.cariAdi ?? 'Perakende',
      'aciklama': 'Fiş iadesi - ${_bulunanSatis!.fisNo ?? _bulunanSatis!.id}',
    });
    // FAZ 9 — Onay Merkezi (bildirim tipi): iade ENGELLENMEDİ, zaten
    // tamamlandı — sadece kalem tutarı eşiği aşıyorsa sonradan
    // incelenebilsin diye kayda düşülüyor.
    OnayMerkeziServisi().kaydet(
      tur: OnayTuru.yuksekIade,
      tutar: toplam,
      esikTutar: OnayEsikleri.yuksekIadeTutari,
      referansTuru: 'iade',
      referansId: iadeId,
      aciklama: '${kalem.urunAdi} (Fiş: ${_bulunanSatis!.fisNo ?? _bulunanSatis!.id})',
    );
    _msg(nakitIade
        ? '${kalem.urunAdi} iade edildi (kasadan nakit ödendi)'
        : '${kalem.urunAdi} iade edildi — tutarı POS cihazından ayrıca müşteriye iade edin');
    setState(() {});
  }

  Widget _fisTab() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: TextField(
              controller: _fisNoCtrl,
              decoration: const InputDecoration(
                  hintText: 'Fiş numarası girin…',
                  prefixIcon: Icon(Icons.receipt),
                  border: OutlineInputBorder(),
                  isDense: true),
              onSubmitted: (_) => _fisBul(),
            )),
            const SizedBox(width: 8),
            FilledButton(onPressed: _fisBul, child: const Text('Ara')),
          ]),
          const SizedBox(height: 16),
          if (_bulunanSatis != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: TsRenk.kart(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: TsRenk.ayirac(context)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x10000000), blurRadius: 6)
                  ]),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              'Fiş: ${_bulunanSatis!.fisNo ?? _bulunanSatis!.id}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          Chip(
                              label: Text(_bulunanSatis!.odemeYontemi),
                              backgroundColor: Colors.blue.shade50),
                        ]),
                    if (_bulunanSatis!.cariAdi != null)
                      Text('Müşteri: ${_bulunanSatis!.cariAdi}',
                          style: TextStyle(
                              color: TsRenk.metinIkincil(context),
                              fontSize: 12)),
                    Text(
                        DateFormat('dd.MM.yyyy HH:mm')
                            .format(_bulunanSatis!.tarih),
                        style: TextStyle(
                            color: TsRenk.metinIkincil(context), fontSize: 12)),
                    const Divider(height: 24),
                    const Text('Kalemler:',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ...(_bulunanSatis!.kalemler.map((k) {
                      final oncekiIade = _fisIadeEdilenMiktar[k.urunId] ?? 0;
                      final kalanMiktar = k.miktar - oncekiIade;
                      final tamIadeEdildi = kalanMiktar <= 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: TsRenk.arkaplan(context),
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(k.urunAdi,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                Text(
                                    '${k.miktar} × ${ParaUtils.formatla(k.birimFiyat)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: TsRenk.metinIkincil(context))),
                                if (oncekiIade > 0)
                                  Text(
                                    tamIadeEdildi
                                        ? 'Tamamı iade edildi'
                                        : '$oncekiIade adet iade edildi',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: TsRenk.hata,
                                        fontWeight: FontWeight.w600),
                                  ),
                              ])),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(ParaUtils.formatla(k.toplamTutar),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                const SizedBox(height: 4),
                                if (tamIadeEdildi)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    child: Icon(Icons.check_circle,
                                        size: 16, color: Colors.green),
                                  )
                                else
                                  TextButton.icon(
                                    icon: const Icon(Icons.assignment_return,
                                        size: 14),
                                    label: const Text('İade',
                                        style: TextStyle(fontSize: 12)),
                                    style: TextButton.styleFrom(
                                        foregroundColor: _R.orange,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero),
                                    onPressed: () => _fisKalemIade(k),
                                  ),
                              ]),
                        ]),
                      );
                    })),
                    const Divider(),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOPLAM',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(ParaUtils.formatla(_bulunanSatis!.genelToplam),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: _R.primary)),
                        ]),
                  ]),
            ),
          ] else
            Center(
                child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(children: [
                Icon(Icons.receipt_long,
                    size: 64, color: TsRenk.ayirac(context)),
                const SizedBox(height: 12),
                Text('Fiş numarasını girin ve arayın',
                    style: TextStyle(color: context.textSecondary)),
              ]),
            )),
        ]),
      );
}
