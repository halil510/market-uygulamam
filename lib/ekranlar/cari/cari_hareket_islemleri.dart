// ignore_for_file: invalid_use_of_protected_member
// lib/ekranlar/cari/cari_hareket_islemleri.dart
//
// cari_hareket_ekrani.dart'ın parçası (part/part of) — hareket kökeni tespiti, silme, yeni hareket ekleme, fiş detayına gitme.
// Davranış BİREBİR aynı: State üzerine extension (setState aynı State
// örneği üzerinde çağrılır; analizci yalnızca extension içinden "korumalı
// üye" uyarısı verir).
part of 'cari_hareket_ekrani.dart';

extension _CariHareketIslemleri on _CariHareketEkraniState {
  // 🔴🔴 FAZ 1 madde 5 (kullanıcı onayıyla uygulandı): gerçek silme yerine
  // ERP standardı ORİJİNAL → REVERSAL → AUDIT LOG zinciri. Orijinal kayıt
  // hiçbir zaman silinmiyor/değiştirilmiyor (sadece is_deleted=1) — ters
  // (borç/alacak yer değiştirmiş) bir cari_hareket ekleniyor. Bu hareket
  // tahsilat_odeme_ekrani.dart üzerinden NAKİT olarak oluşturulmuş ve
  // ilgili kasa hareketine referans_id/referans_turu ile bağlanmışsa
  // (bkz. o dosyadaki değişiklik), bağlı kasa hareketi de AYNI
  // transaction içinde otomatik tersine çevriliyor. Audit log ayrıca
  // yazılmıyor — BulutManager().upsert() zaten HER çağrıda
  // AuditLogServisi'ni tetikliyor (kim/ne zaman/hangi cihaz otomatik
  // kaydediliyor).
  //
  // Banka/Kredi Kartı hareketlerinde (banka_hareketler, kredi_karti_
  // hareket) aynı referans_id/referans_turu sütunu ŞEMADA YOK — bunu
  // eklemek bir migration gerektirir ve onay alınmadı (bkz. FAZ 1
  // raporu). O yüzden bu iki ödeme türü için hâlâ sadece uyarı
  // gösteriliyor; kayıtlar arasında YANLIŞ bir eşleştirme riski almak
  // yerine güvenli (dokunmama) tarafta kalındı.
  /// Swipe-silme akışındaki TEK onay diyaloğunun (bkz. Dismissible.confirmDismiss
  /// aşağıda) içeriği — hareketin türüne göre bağlı kasa hareketinin ne
  /// olacağını açıklar.
  bool _satisKokenliMi(CariHareketModel h) =>
      (h.fisTipi == 'Satış' ||
          h.fisTipi == 'Toptan Satış' ||
          h.fisTipi == 'Toptan Satış (Sipariş)') &&
      h.fisId != null &&
      h.fisId! > 0;

  // 🆕 (kullanıcı bulgusu, 2026-09-22): 'Alım' (tedarikçiden mal alımı)
  // da satış-kökenli hareketle AYNI sorunu taşıyordu — sadece cari
  // kaydını iptal etmek asıl alımı (Alım Listesi'ndeki 'teslim_alindi'
  // kaydı) etkilenmemiş bırakırdı: stok geri düşmez, kasa/banka geri
  // gelmez, silinen alım Alım Listesi'nde AYNEN görünmeye devam ederdi.
  bool _alimKokenliMi(CariHareketModel h) =>
      h.fisTipi == 'Alım' && h.fisId != null && h.fisId! > 0;

  // 🆕 (kullanıcı bulgusu, 2026-09-22): 'İade'/'Alım İadesi' de AYNI
  // sorunu taşıyordu — genel amaçlı hareketIptalEt() İade kavramından
  // habersiz (stok geri düşmez, kasa referans_turu='cari_hareket' arar
  // ama iade referans_turu='iade' ile yazar — asla eşleşmez).
  bool _iadeKokenliMi(CariHareketModel h) =>
      (h.fisTipi == 'İade' || h.fisTipi == 'Alım İadesi') &&
      h.fisId != null &&
      h.fisId! > 0;

  String _silHareketMesaji(CariHareketModel h) {
    // 🔴 DÜZELTME (kullanıcı isteği, 2026-09-21): bir satıştan otomatik
    // türeyen hareket önceden SADECE cari kaydını iptal ediyordu — asıl
    // satış Satış Listesi'nde aktif kalıyor, stok/kasa/ciro hiç
    // etkilenmiyordu ("bedava satış" tutarsızlığı). Artık bu hareketi
    // silmek asıl satışı da siler (stok geri yükleme + kasa/banka
    // tersine çevirme + cari ters kaydı hep birlikte, tek işlemde) —
    // hangi taraftan silinirse silinsin sonuç aynı ve tutarlı olur.
    if (_satisKokenliMi(h)) {
      return 'Bu hareket "${h.fisNo ?? h.fisId}" numaralı satıştan geliyor. '
          'Silersen bağlı SATIŞ da iptal edilecek: stok geri yüklenecek, '
          'ödeme yöntemine göre kasa/banka tersine çevrilecek ve bu satış '
          'Satış Listesi\'nden de kalkacak. Emin misiniz?';
    }
    if (_alimKokenliMi(h)) {
      return 'Bu hareket "${h.fisNo ?? h.fisId}" numaralı alımdan geliyor. '
          'Silersen bağlı ALIM da iptal edilecek: stok geri düşülecek, '
          'ödeme yöntemine göre kasa/banka tersine çevrilecek ve bu alım '
          'Alım Listesi\'nde "İptal" olarak işaretlenecek. Emin misiniz?';
    }
    if (_iadeKokenliMi(h)) {
      return 'Bu hareket "${h.fisNo ?? h.fisId}" numaralı iadeden geliyor. '
          'Silersen bağlı İADE de iptal edilecek: stok geri düşülecek, '
          'nakit iadeyse kasa tersine çevrilecek ve bu iade İade '
          'Geçmişi\'nde "İptal" olarak işaretlenecek. Emin misiniz?';
    }
    final gercekParaOlabilir = h.fisTipi == 'Tahsilat' || h.fisTipi == 'Ödeme';
    final otomatikTersCevrilebilir =
        gercekParaOlabilir && h.odemeTuru == 'Nakit';
    if (!gercekParaOlabilir) return '${h.aciklama} silinecek. Emin misiniz?';
    if (otomatikTersCevrilebilir) {
      return '${h.aciklama} silinecek. Bağlı kasa hareketi de otomatik '
          'olarak tersine çevrilecek. Emin misiniz?';
    }
    return '${h.aciklama} silinecek.\n\n'
        'Bu bir Banka/Kredi Kartı hareketiyse, bağlı kayıt OTOMATİK OLARAK '
        'GERİ ALINMAZ — gerekiyorsa o tarafı elle düzeltin. Emin misiniz?';
  }

  // 🔴 DÜZELTME (kullanıcı bulgusu — "cari fiş silme işlemi çalışmıyor"):
  // ÖNCEDEN burada Dismissible.confirmDismiss'in gösterdiği onay
  // diyaloğundan SONRA, _silHareket kendi İKİNCİ bir onay diyaloğu daha
  // gösteriyordu (aynı işlem için art arda 2 diyalog). Kullanıcı ikinci
  // diyaloğun dışına dokunduğunda (varsayılan barrier-dismiss davranışı)
  // veya onu fark etmeden kapattığında, `ok != true` olduğu için fonksiyon
  // SESSİZCE hiçbir hata/bildirim göstermeden geri dönüyordu — "silme
  // yapmıyor" hissi tam olarak buradan kaynaklanıyordu. Artık TEK onay
  // diyaloğu var (Dismissible.confirmDismiss, _silHareketMesaji ile) —
  // buraya ulaşıldığında kullanıcı zaten onaylamış demektir.
  Future<void> _silHareket(CariHareketModel h) async {
    if (h.id == null) return;
    try {
      if (_satisKokenliMi(h)) {
        // Satış-kökenli hareket: sadece cari_hareket'i silmek satışı
        // (dolayısıyla stok/kasa/ciroyu) etkilenmemiş bırakırdı. Asıl
        // satış SatisIptalServisi ile silinir — satis_detay_ekrani.dart
        // ile AYNI kod yolu (e-Fatura/GİB kontrolü dahil).
        final silindi = await SatisIptalServisi.guvenliSil(
            context, h.fisId!,
            neden: 'Cari hareketinden silindi');
        if (!silindi) return;
        if (!mounted) return;
        ref.invalidate(cariDetayProvider(widget.cariId));
        ref.read(carilerProvider.notifier).yukle();
        ref.read(satislarProvider.notifier).yukle();
        await _yukle();
        if (mounted) BildirimServisi.basari(context, 'Satış iptal edildi');
        return;
      }

      if (_alimKokenliMi(h)) {
        // Alım-kökenli hareket: sadece cari_hareket'i silmek alımı
        // (dolayısıyla stok/kasa/bankayı) etkilenmemiş bırakırdı. Asıl
        // alım AlimIslemServisi().sil() ile silinir — stok geri düşme +
        // kasa/banka tersine çevirme + cari ters kaydı tek transaction'da.
        await AlimIslemServisi().sil(h.fisId!, neden: 'Cari hareketinden silindi');
        if (!mounted) return;
        ref.invalidate(cariDetayProvider(widget.cariId));
        ref.read(carilerProvider.notifier).yukle();
        await _yukle();
        if (mounted) BildirimServisi.basari(context, 'Alım iptal edildi');
        return;
      }

      if (_iadeKokenliMi(h)) {
        // İade-kökenli hareket: sadece cari_hareket'i silmek iadeyi
        // (dolayısıyla stok/kasayı) etkilenmemiş bırakırdı. Asıl iade
        // IadeIslemServisi().gecmisFisIadeSil() ile silinir — o metod
        // TÜM kalemlerini iade_kalem'den kendi sorguluyor, burada sadece
        // iadeId/toplam/cariId/fisNo gerekiyor (bkz. o metodun doc yorumu).
        // Madde 2 sertleştirmesi (2026-09-22): doğrudan Veritabani().db
        // erişimi kaldırıldı — IadeDeposu üzerinden.
        final iadeDepo = IadeDeposu();
        final iadeSatiri = await iadeDepo.idileGetir(h.fisId!);
        if (iadeSatiri == null) {
          throw Exception('Bu iade bulunamadı (silinmiş olabilir).');
        }
        final kalemler = await iadeDepo.kalemleriGetir(h.fisId!);
        await IadeIslemServisi().gecmisFisIadeSil(
          iadeId: h.fisId!,
          kalemler: kalemler,
          toplamTutar: (iadeSatiri['toplam_tutar'] as num?)?.toDouble() ?? 0,
          cariId: h.cariId,
          fisNo: h.fisNo,
        );
        if (!mounted) return;
        ref.invalidate(cariDetayProvider(widget.cariId));
        ref.read(carilerProvider.notifier).yukle();
        await _yukle();
        if (mounted) BildirimServisi.basari(context, 'İade iptal edildi');
        return;
      }

      // Tüm iptal mantığı (soft-delete + audit ters kayıt + bakiye
      // yeniden hesaplama + bağlı kasa hareketi ters çevirme + bulut
      // senkron) artık CariDeposu.hareketIptalEt'te — bkz. o metodun
      // doc yorumu, davranış birebir korundu.
      await _depo.hareketIptalEt(h);

      if (!mounted) return;
      // 🔴 DÜZELTME (kullanıcı bulgusu, 2026-09-22): bu dal (Tahsilat/
      // Ödeme/İskonto/vb.) satış-kökenli daldan farklı olarak
      // cariDetayProvider'ı hiç invalidate ETMİYORDU — bu ekranın kendi
      // _yukle()'si taze okuduğu için BURADA doğru görünse de, kullanıcı
      // sildikten sonra ana Cari Detay ekranına dönerse orada bayat
      // (silme öncesi) bakiye görünebiliyordu.
      ref.invalidate(cariDetayProvider(widget.cariId));
      ref.read(carilerProvider.notifier).yukle();
      await _yukle();
      if (mounted) BildirimServisi.basari(context, 'Hareket iptal edildi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  // 🔴🔴 FAZ 1 madde 4 (kullanıcı onayıyla): bu dialog eskiden 'Tahsilat' ve
  // 'Ödeme' seçeneklerini de içeriyordu — ama bunlar tahsilat_odeme_ekrani.dart'ın
  // yaptığı gibi kasa/banka/kredi kartı hareketi OLUŞTURMUYORDU, sadece
  // cari_hareket ekliyordu. Yani biri buradan "Tahsilat" seçip para tahsil
  // ettiğini kaydettiğinde, cari bakiyesi düşüyor ama kasa/banka'ya hiç para
  // girmiyordu — mutabakatı bozan sessiz bir tutarsızlık. O yüzden bu iki
  // seçenek kaldırıldı; gerçek para hareketi için Tahsilat/Ödeme ekranı
  // kullanılmalı. Kalan üç seçenek (İskonto/İade/Düzeltme) hiçbir zaman
  // kasa/banka hareketi yaratmıyordu — bunlar kasadan/bankadan bağımsız, saf
  // cari bakiye düzeltmeleri olduğu için (meşru kullanım) korundu.
  Future<void> _hareketEkle() async {
    String tipi = 'İskonto';
    final ctrl = TextEditingController();
    final acCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Manuel Cari Düzeltme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Bu ekran sadece cari bakiyesinde para hareketi '
                    'yaratmayan düzeltmeler içindir. Nakit/kart/banka '
                    'tahsilat veya ödeme için Tahsilat/Ödeme ekranını kullanın.',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: tipi,
                decoration: const InputDecoration(
                  labelText: 'Düzeltme Tipi',
                  border: OutlineInputBorder(),
                ),
                items: ['İskonto', 'İade', 'Düzeltme']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => ss(() => tipi = v!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tutar (₺)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: acCtrl,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final tutar = ParaUtils.sayiCoz(ctrl.text) ?? 0;
    if (tutar <= 0) {
      BildirimServisi.uyari(context, 'Geçerli tutar girin');
      return;
    }

    final isTahsilat = tipi == 'İskonto';
    if (!mounted) return;
    await _depo.hareketEkle(CariHareketModel(
      cariId: widget.cariId,
      fisTipi: tipi,
      tarih: DateTime.now(),
      aciklama: acCtrl.text.trim().isEmpty ? tipi : acCtrl.text.trim(),
      borc: isTahsilat ? 0 : tutar,
      alacak: isTahsilat ? tutar : 0,
    ));
    await _yukle();
    // ÖNCEDEN BURADA sadece bu ekranın kendi listesi (_yukle) tazeleniyordu
    // — kullanıcı sonra Cari Detay/Liste ekranına dönünce hâlâ ESKİ
    // bakiyeyi görüyordu. Artık paylaşılan provider'lar da tazeleniyor.
    ref.invalidate(cariDetayProvider(widget.cariId));
    ref.read(carilerProvider.notifier).yukle();
    if (mounted) BildirimServisi.basari(context, '$tipi kaydedildi');
  }

  void _fisDetayinaGit(CariHareketModel hareket) {
    if (hareket.fisId == null || hareket.fisId == 0) {
      BildirimServisi.uyari(context, 'Bu harekete ait fiş detayı bulunamadı');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FisDetayEkrani(
          fisId: hareket.fisId!,
          fisTipi: hareket.fisTipi,
          cariUnvan: _cari?.unvan ?? '',
        ),
      ),
    ).then((_) => _yukle());
  }
}
