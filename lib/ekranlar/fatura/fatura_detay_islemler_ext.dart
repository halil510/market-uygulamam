// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: Bu dosya `part of 'fatura_detay_ekrani.dart'` ve içeriği
// `extension ... on _FaturaDetayEkraniState` olarak yazılmış — projenin
// diğer ekranlarında zaten kullanılan, ÇALIŞAN bir desen (bkz.
// iade_ekrani_hizli.dart). Dart analizcisi `setState`'i @protected
// gördüğü için, extension içinden çağrıyı "korumalı üyeye dışarıdan
// erişim" sayıyor. Derlemeyi engellemez; sadece analiz uyarısıdır
// (analysis_options.yaml'da bu kural bilinçli olarak `error` seviyesine
// çıkarıldı — başka yerlerde gerçek hataları yakalasın diye. Burada
// dosya bazında muaf tutuluyor).
// lib/ekranlar/fatura/fatura_detay_islemler_ext.dart
// fatura_detay_ekrani.dart'ın parçası — ödeme kaydetme + e-Fatura/GİB
// durum makinesi diyalogları (god-class sertleştirmesi, 2026-09-22).
// Davranış birebir korundu.
part of 'fatura_detay_ekrani.dart';

extension _FaturaDetayIslemlerExt on _FaturaDetayEkraniState {
  // ── Ödeme kaydet ────────────────────────────────────────────────────────
  Future<void> _odemeKaydet() async {
    if (_fatura == null || !mounted || _islemDevam) return;
    setState(() => _islemDevam = true);
    final ctrl = TextEditingController();
    // 🔴 DÜZELTME (komple derin analizde bulundu): bu controller hiçbir
    // zaman dispose edilmiyordu — dış try/finally ile artık her çıkış
    // yolunda (erken dönüş, hata, başarı) garanti altına alındı.
    try {
      await _odemeKaydetIc(ctrl);
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _odemeKaydetIc(TextEditingController ctrl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ödeme Kaydet'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Kalan: ${ParaUtils.formatla(_fatura!.kalanTutar)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Ödenen Tutar',
                suffixText: 'TL',
                border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet')),
        ],
      ),
    );

    if (ok != true || !mounted) { setState(() => _islemDevam = false); return; }

    try {
      final odenen = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
      if (odenen <= 0) {
        if (mounted) BildirimServisi.uyari(context, 'Geçerli tutar girin');
        return;
      }
      // 🔴 DÜZELTME: Girilen tutar "Kalan"dan fazlaysa hiçbir uyarı
      // yoktu — kayıt katmanı fazlayı sessizce yok sayıyor (kalanTutar
      // hiç negatif olmuyor), yani bir yazım hatasıyla girilen fazla
      // tutar hiçbir yerde İZ BIRAKMADAN kayboluyordu. Artık kullanıcı
      // önce uyarılıp onaylıyor.
      if (odenen > _fatura!.kalanTutar + 0.01 && mounted) {
        final devamEt = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Fazla Tutar'),
            content: Text('Girilen tutar (${ParaUtils.formatla(odenen)}), kalan tutardan '
                '(${ParaUtils.formatla(_fatura!.kalanTutar)}) fazla. Devam edilsin mi?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Devam Et')),
            ],
          ),
        );
        if (devamEt != true) return;
      }
      await _depo.odemeKaydet(widget.faturaId, odenen);
      await _yukle();
      if (mounted) BildirimServisi.basari(context, 'Ödeme kaydedildi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islemDevam = false);
    }
  }


  IconData _durumIkonu(String? durum) => switch (durum) {
        'onaylandi' => Icons.verified_outlined,
        'gonderildi' => Icons.cloud_done_outlined,
        'gonderiliyor' => Icons.cloud_upload_outlined,
        'reddedildi' => Icons.cancel_outlined,
        'gib_iptal' => Icons.block_outlined,
        'hata' => Icons.error_outline,
        _ => Icons.schedule_outlined,
      };

  Color _durumRengi(String? durum) => switch (durum) {
        'onaylandi' => Colors.teal,
        'gonderildi' => Colors.green,
        'gonderiliyor' => Colors.blue,
        'reddedildi' => Colors.red,
        'gib_iptal' => Colors.grey,
        'hata' => Colors.red,
        _ => Colors.orange,
      };

  String _durumEtiketi(String? durum) => switch (durum) {
        'onaylandi' => 'GİB Onayladı',
        'gonderildi' => 'Gönderildi',
        'gonderiliyor' => 'Gönderiliyor',
        'reddedildi' => 'GİB Reddetti',
        'gib_iptal' => 'GİB\'de İptal Edildi',
        'hata' => 'Gönderim Hatası',
        _ => 'Beklemede',
      };

  // ── Durum Sorgula ──────────────────────────────────────────────────────────
  Future<void> _durumSorgula() async {
    // 🔴 DÜZELTME (Madde 23 denetimi, 2026-09-20): 'gonderiliyor'
    // durumundaki bir faturanın eFaturaUuid'si DB'de null olabilir (bkz.
    // eFaturaDurumGuncelle(..., 'gonderiliyor') çağrısının UUID'siz
    // yapılması) — ama ETTN DETERMİNİSTİK olduğundan (GibServisi.
    // ettnHesapla), hiç saklanmamış olsa bile yeniden hesaplanabilir.
    // Sadece GERÇEKTEN hiç gönderilmemiş (durum='hazir'/null) faturalar
    // için "Henüz gönderim yapılmamış" uyarısı hâlâ doğru.
    final ettn = _fatura != null ? _eBelge.ettnBelirle(_fatura!) : null;
    if (ettn == null) {
      BildirimServisi.uyari(context, 'Henüz gönderim yapılmamış');
      return;
    }
    // 🔴 DÜZELTME (GİB Fatura denetimi, 2026-09-20 — loading dialog
    // sızıntısı): ÖNCEDEN diyalog kapatma `if (!mounted) return;`
    // ardından `Navigator.pop(context)` ile yapılıyordu — kullanıcı ağ
    // isteği sürerken bu ekrandan geri giderse (widget unmount olur),
    // `mounted=false` olduğu için pop HİÇ ÇAĞRILMIYOR ve barrierDismissible:
    // false olan "GİB sorgulanıyor..." diyaloğu ekranda ASILI KALABİLİYORDU.
    // Artık kök navigator'a bu widget'ın mounted durumundan BAĞIMSIZ bir
    // referans tutuluyor — dialog her koşulda kapatılabiliyor.
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(color: Color(0xFF4361EE), strokeWidth: 3),
          const SizedBox(width: 16),
          Text('GİB sorgulanıyor...'),
        ])));
    try {
      // Durumu sorgular VE (varsa) DB'ye yazar — [ettn] burada da AYRICA
      // persist edilir: 'gonderiliyor' durumunda DB'de hâlâ null olabilen
      // eFaturaUuid, bu sorgulamayla birlikte kalıcı olarak doldurulmuş
      // olur (bir daha yeniden hesaplamaya gerek kalmaz).
      final sonuc = await _eBelge.durumSorgula(_fatura!, ettn);
      final durum = sonuc?.durum;
      final aciklama = sonuc?.aciklama;
      if (navigator.mounted) navigator.pop();
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('GİB Durum'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(_durumIkonu(durum), color: _durumRengi(durum), size: 40),
          const SizedBox(height: 12),
          Text(_durumEtiketi(durum), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (aciklama != null) ...[
            const SizedBox(height: 8),
            Text(durum == 'reddedildi' ? 'Red sebebi: $aciklama' : aciklama,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13,
                    color: durum == 'reddedildi' ? Colors.red : null)),
          ],
          Text('UUID: ${ettn.substring(0, 8)}...',
              style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
      ));
      if (durum != null) {
        await _yukle();
      }
    } on GibBelgeBulunamadi {
      if (navigator.mounted) navigator.pop();
      if (!mounted) return;
      await _yukle();
      if (!mounted) return;
      BildirimServisi.uyari(context,
          'Bu fatura GİB\'e hiç ulaşmamış. Durumu "Gönderim Hatası" olarak '
          'güncellendi — güvenle yeniden gönderebilirsiniz (aynı ETTN '
          'kullanılır, mükerrer belge oluşmaz).');
    } catch (e) {
      if (navigator.mounted) navigator.pop();
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  // ── GİB'de İptal Et ──────────────────────────────────────────────────────
  // GİB'e ulaşmış (gonderildi/onaylandi) bir e-Belgeyi entegratör üzerinden
  // iptal eder. GİB'in izin verdiği iptal penceresi (genelde e-Arşiv için
  // aynı gün) ve tam istek formatı entegratöre göre değişir — bkz.
  // GibServisi.iptalEt'teki uyarı.
  Future<void> _gibIptalEt() async {
    if (_fatura == null || !mounted || _islemDevam) return;
    if (_fatura!.eFaturaUuid == null) return;
    final onay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('GİB\'de İptal Et'),
        ]),
        content: Text(
          '${_fatura!.faturaNo ?? "Fatura"} GİB\'e gönderilmiş bir e-Belge. '
          'İptal işlemi GİB kurallarına göre sadece belirli bir süre içinde '
          'geçerli olabilir ve entegratörünüze bağlıdır. Devam edilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('İptal Et')),
        ],
      ));
    if (onay != true || !mounted) return;

    setState(() => _islemDevam = true);
    // bkz. _durumSorgula() üzerindeki loading-dialog sızıntısı notu — aynı
    // düzeltme burada da uygulanıyor.
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(color: Color(0xFF4361EE), strokeWidth: 3),
          SizedBox(width: 16),
          Text('GİB\'e iptal isteği gönderiliyor...'),
        ])));
    try {
      final basarili = await _eBelge.iptalEt(_fatura!);
      if (navigator.mounted) navigator.pop();
      if (!mounted) return;
      if (basarili) {
        await _yukle();
        if (mounted) BildirimServisi.basari(context, 'GİB\'de iptal edildi');
      } else {
        if (mounted) BildirimServisi.hata(context,
            'İptal başarısız — entegratörünüzün iptal süresini/desteğini kontrol edin');
      }
    } catch (e) {
      if (navigator.mounted) navigator.pop();
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islemDevam = false);
    }
  }

  // ── e-Fatura Gönder ──────────────────────────────────────────────────────
  // Bu fonksiyonun içinde çok sayıda erken 'return' noktası var (ayarlar
  // eksik, tip seçilmedi, onaylanmadı vb.) — her birini tek tek bayrakla
  // korumak yerine, tüm gövde bir iç fonksiyona taşınıp try/finally ile
  // sarıldı: hangi yoldan çıkarsa çıksın _islemDevam doğru sıfırlanır.
  Future<void> _efaturaGonder() async {
    if (_fatura == null || !mounted || _islemDevam) return;
    setState(() => _islemDevam = true);
    try {
      await _efaturaGonderIc();
    } finally {
      if (mounted) setState(() => _islemDevam = false);
    }
  }

  Future<void> _efaturaGonderIc() async {
    final ayarliMi = await _eBelge.ayarlariYukleVeKontrolEt();

    if (!ayarliMi) {
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.settings_outlined, color: Colors.orange),
          const SizedBox(width: 8),
          Text('GİB Ayarları Eksik'),
        ]),
        content: const Text(
          'e-Fatura göndermek için GİB entegrasyon ayarlarını yapılandırmanız gerekiyor.\n\n'
          'Ayarlar → GİB Entegrasyon ekranına gidiniz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () { Navigator.pop(ctx); context.push('/ayarlar/gib'); },
            child: const Text('Ayarlara Git')),
        ],
      ));
      return;
    }

    // Hangi tip?
    // 🔴 DÜZELTME (derin analizde bulundu): Bu diyalog kullanıcıya HER
    // SEFERİNDE e-Fatura/e-Arşiv'i elle, ezbere seçtiriyordu — oysa
    // müşterinin GİB'de sorgulanmış mükellefiyet durumu
    // (cariMukellefDurumu) fatura oluşturulurken zaten kaydedilmiş
    // olabilir. Artık biliniyorsa önerilen seçenek vurgulanıyor;
    // kullanıcı yine de istediğini seçebilir (mükellefiyet durumu
    // değişmiş olabilir, bu yüzden otomatik/sessiz karar VERİLMİYOR).
    final onerilenTip = _eBelge.onerilenTip(_fatura!);
    if (!mounted) return;   // mükellef sorgusu await'i sonrası
    final tip = await showDialog<EFaturaTipi>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('e-Fatura Tipi'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (onerilenTip != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'GİB sorgusuna göre önerilen: '
                '${onerilenTip == EFaturaTipi.eFatura ? "e-Fatura" : "e-Arşiv"}',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: context.textSecondary),
              ),
            ),
          ListTile(
            leading: Icon(Icons.receipt_long,
                color: onerilenTip == EFaturaTipi.eFatura ? Colors.blue : Colors.blue.withAlpha(150)),
            title: Text('e-Fatura',
                style: TextStyle(fontWeight: onerilenTip == EFaturaTipi.eFatura ? FontWeight.w800 : null)),
            subtitle: const Text('GİB kayıtlı mükellefler için'),
            trailing: onerilenTip == EFaturaTipi.eFatura ? const Icon(Icons.check_circle, color: Colors.blue, size: 18) : null,
            onTap: () => Navigator.pop(ctx, EFaturaTipi.eFatura)),
          ListTile(
            leading: Icon(Icons.receipt_outlined,
                color: onerilenTip == EFaturaTipi.eArsiv ? Colors.green : Colors.green.withAlpha(150)),
            title: Text('e-Arşiv',
                style: TextStyle(fontWeight: onerilenTip == EFaturaTipi.eArsiv ? FontWeight.w800 : null)),
            subtitle: const Text('Diğer alıcılar için'),
            trailing: onerilenTip == EFaturaTipi.eArsiv ? const Icon(Icons.check_circle, color: Colors.green, size: 18) : null,
            onTap: () => Navigator.pop(ctx, EFaturaTipi.eArsiv)),
        ]),
      ));
    if (tip == null || !mounted) return;

    // Onay
    final onay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${tip == EFaturaTipi.eFatura ? "e-Fatura" : "e-Arşiv"} Gönder'),
        content: Text(
          '${_fatura!.faturaNo ?? "Fatura"} numaralı fatura\n'
          'GİB sistemine gönderilecek.\n\n'
          'Tutar: ${ParaUtils.formatla(_fatura!.genelToplam)}\n\n'
          'Onaylıyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.blue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gönder')),
        ],
      ));
    if (onay != true || !mounted) return;

    // Gönder — bkz. _durumSorgula() üzerindeki loading-dialog sızıntısı
    // notu, aynı düzeltme.
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(color: Color(0xFF4361EE), strokeWidth: 3),
          const SizedBox(width: 16),
          Text('GİB sistemine gönderiliyor...'),
        ])));

    try {
      // Reddedilmişse yeniden gönderime hazırlar, ağ isteğinden ÖNCE
      // 'gonderiliyor' işaretler, sonucu DB'ye yazar — hepsi
      // FaturaEBelgeServisi.gonder() içinde (bkz. o metodun yorumu).
      final sonuc = await _eBelge.gonder(_fatura!, tip);
      if (navigator.mounted) navigator.pop(); // loading dialog kapat
      if (!mounted) return;

      if (sonuc.basarili) {
        await _yukle();
        if (mounted) BildirimServisi.basari(context,
            '${tip == EFaturaTipi.eFatura ? "e-Fatura" : "e-Arşiv"} gönderildi ✓');
      } else {
        await _yukle();
        if (mounted) showDialog(context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 8),
              Text('Gönderim Hatası'),
            ]),
            content: Text(sonuc.hata ?? 'Bilinmeyen hata'),
            actions: [FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tamam'))],
          ));
      }
    } catch (e) {
      if (navigator.mounted) navigator.pop();
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }
}
