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
  /// Madde 2 sertleştirmesi (2026-09-22): doğrudan Veritabani().db erişimi
  /// kaldırıldı — IadeDeposu.fisIadeliMiktarlariGetir() üzerinden.
  Future<Map<int, double>> _fisIadeliMiktarlariGetir(int satisId) =>
      IadeDeposu().fisIadeliMiktarlariGetir(satisId);

  Future<void> _fisKalemIade(SatisKalemModel kalem) async {
    if (_bulunanSatis == null) return;

    // Çift iade koruması: bu kalemden daha önce ne kadar iade edilmiş?
    final oncekiIadeMiktar = _fisIadeEdilenMiktar[kalem.urunId] ?? 0;
    final kalanMiktar = kalem.miktar - oncekiIadeMiktar;
    if (kalanMiktar <= 0) {
      _msg('${kalem.urunAdi} bu fişten zaten tamamen iade edilmiş', err: true);
      return;
    }

    // 🔴🔴 DÜZELTME (Madde 23 — Fatura/E-Belge denetimi, 2026-09-20):
    // satis_detay_ekrani.dart'taki "satış iptali" akışıyla AYNI kontrolün
    // simetriği — ÖNCEDEN fiş üzerinden iade, bu satışa ait GİB'e
    // GÖNDERİLMİŞ/ONAYLANMIŞ bir e-Fatura olup olmadığını hiç kontrol
    // etmiyordu. Bir kalemi iade etmek fişin tutarını/kalemlerini fiilen
    // değiştirir ama onaylı e-Fatura'ya hiç dokunmaz — kullanıcı resmi bir
    // iade faturası/düzeltme gerektiğini bilmeden sessizce devam edebilirdi.
    final faturaId =
        await FaturalandirmaServisi.mevcutFaturaId(satisId: _bulunanSatis!.id!);
    if (faturaId != null && mounted) {
      final fatura = await FaturaDeposu().idileGetir(faturaId);
      final gibeGonderildi = fatura != null &&
          (fatura.eFaturaDurum == 'gonderildi' || fatura.eFaturaDurum == 'onaylandi');
      if (gibeGonderildi && mounted) {
        final devamEt = await OnayDialog.goster(context,
            baslik: 'Bu Fişin Onaylı Bir e-Faturası Var',
            icerik:
                'Bu satış için GİB\'e gönderilmiş ve onaylanmış bir e-Fatura '
                '(${fatura.faturaNo ?? ''}) mevcut. Bu kalemi iade etmek '
                'faturayı OTOMATİK OLARAK düzeltmez/iptal ETMEZ — resmi bir '
                'iade faturası/düzeltme GİB tarafında ayrıca düzenlenmelidir. '
                'İadeye yine de devam etmek istiyor musunuz?',
            onayYazi: 'Yine de İade Et', onayRengi: _R.orange,
            ikon: Icons.warning_amber_rounded);
        if (!devamEt || !mounted) return;
      }
    }

    // 🔴🔴 FAZ 1 madde 1 (kullanıcı onayıyla): iade artık orijinal
    // satışın ödeme yöntemini dikkate alıyor — kart/banka ile ödenmiş
    // bir satışın iadesi kasadan nakit ÇIKARMIYOR (POS cihazından ayrıca
    // iade edilmesi gerekiyor), sadece Nakit seçiliyse kasa hareketi
    // oluşuyor. Varsayılan, orijinal ödeme yöntemidir; kullanıcı
    // isterse değiştirebilir.
    // Varsayılan, orijinal satışın ödeme yöntemidir — müşteri veresiye
    // almışsa (hiç nakit/kart ödemesi yapmamışsa) varsayılan da Cari
    // olmalı, aksi halde hiç verilmemiş bir nakit iadesi öneriliyordu.
    String secilenYontem = _bulunanSatis!.odemeYontemi == 'Nakit'
        ? 'Nakit'
        : (_bulunanSatis!.odemeYontemi == 'Cari' && _bulunanSatis!.cariId != null)
            ? 'Cari'
            : 'Kart/Banka';
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
                        items: [
                          const DropdownMenuItem(
                              value: 'Nakit', child: Text('Nakit (kasadan)')),
                          const DropdownMenuItem(
                              value: 'Kart/Banka',
                              child: Text('Kart/Banka (POS\'tan)')),
                          // Sadece bu fişin sahibi kayıtlı bir cari ise
                          // gösterilir (orijinal satış Veresiye/Cari ise
                          // müşteri zaten nakit/kart ödemesi yapmamıştı).
                          if (_bulunanSatis!.cariId != null)
                            const DropdownMenuItem(
                                value: 'Cari',
                                child: Text('Veresiye / Cari (borca yaz)')),
                        ],
                        onChanged: (v) =>
                            setS(() => secilenYontem = v ?? secilenYontem),
                      ),
                      if (secilenYontem == 'Cari') ...[
                        const SizedBox(height: 8),
                        Text(
                          'Kasadan nakit çıkışı OLUŞTURULMAZ — tutar '
                          '${_bulunanSatis!.cariAdi ?? 'cari'} hesabının bakiyesinden '
                          'gerçekten düşülecek/eklenecek.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.blue.shade800),
                        ),
                      ] else if (secilenYontem != 'Nakit') ...[
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

    // Tüm transaction + lot-farkındalıklı stok geri ekleme + bulut senkron
    // mantığı artık IadeIslemServisi.fisKalemIadeKaydet'te — bkz. o
    // metodun doc yorumu, davranış birebir korundu.
    final (iadeId, _, toplam) = await IadeIslemServisi().fisKalemIadeKaydet(
      satisId: _bulunanSatis!.id!,
      cariId: _bulunanSatis!.cariId,
      urunId: kalem.urunId,
      urunAdi: kalem.urunAdi,
      birimFiyat: kalem.birimFiyat,
      kalanMiktar: kalanMiktar,
      oncekiIadeMiktar: oncekiIadeMiktar,
      odemeYontemi: secilenYontem,
      kullaniciId: AuthServisi().aktifId,
      kullaniciAdi: AuthServisi().aktifAd,
    );

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
    _msg(switch (secilenYontem) {
      'Nakit' => '${kalem.urunAdi} iade edildi (kasadan nakit ödendi)',
      'Cari' =>
        '${kalem.urunAdi} iade edildi (${_bulunanSatis!.cariAdi ?? 'cari'} bakiyesine işlendi)',
      _ => '${kalem.urunAdi} iade edildi — tutarı POS cihazından ayrıca müşteriye iade edin',
    });
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
                              backgroundColor: TsRenk.zemin(TsRenk.bilgi)),
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
