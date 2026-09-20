// lib/ekranlar/cari/cari_detay_ekrani.dart
import 'package:flutter/foundation.dart';
import 'fis_detay_ekrani.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/cari_hareket_model.dart';
import '../../modeller/fatura_model.dart';
import '../../depolar/satis_deposu.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../depolar/cari_deposu.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/musteri_360_servisi.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../modeller/kullanici_model.dart';
import '../../cekirdek/utils/sifre_hash.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../servisler/onay_merkezi_servisi.dart';
import '../../widgetlar/ortak/yonetici_sifre_dialogu.dart';

/// Karma ödemeli bir satışta hem Cari hem Cari-dışı (Nakit/Kart/Havale)
/// payı varsa, SatisTamamlamaServisi.tamamla() AYNI satış (fis_id) için
/// 2 ayrı cari_hareket satırı yazar: gerçek Cari borcu (borc>0, alacak=0)
/// + bakiyeyi etkilemeyen bilgi amaçlı satır (borc=alacak, self-
/// cancelling — o payın Nakit/Kart/Havale ile ANINDA ödendiğini
/// kaydeder). Kullanıcı bulgusu (2026-09-20): bu, Cari Hareketler
/// listesinde AYNI satışın 2 ayrı "Satış" kartı gibi görünmesine yol
/// açıyordu — kafa karıştırıcı.
///
/// Bu SAF fonksiyon, aynı fis_id + fis_tipi='Satış' satırlarını TEK bir
/// karta birleştirir. borc/alacak toplanır — bu, net bakiye etkisini
/// DOĞRU tutar (self-cancelling satırın borc=alacak'ı zaten birbirini
/// götürür), ama HAM toplamları (100 borç + 50 alacak gibi) DEĞİL,
/// sadece NET etkiyi (borç YA DA alacak, ikisi asla aynı anda değil)
/// gösterir — iki ayrı tutarın aynı kartta görünmesi kafa karıştırırdı.
/// Tam ödeme dağılımı (50 Nakit + 50 Cari gibi) artık Satış Detayı
/// ekranında gösteriliyor — bu liste sadece NET etkiyi özetler.
/// 'Satış' olmayan hareketler (Tahsilat, Ödeme, Toptan Satış vb.) ve
/// tek satırlı 'Satış' kayıtları DEĞİŞTİRİLMEDEN geçer.
List<CariHareketModel> cariHareketleriniGrupla(List<CariHareketModel> ham) {
  final gruplar = <int, List<CariHareketModel>>{};
  for (final h in ham) {
    if (h.fisTipi == 'Satış' && h.fisId != null) {
      (gruplar[h.fisId!] ??= []).add(h);
    }
  }

  final sonuc = <CariHareketModel>[];
  final islenmisFisIdler = <int>{};
  for (final h in ham) {
    if (h.fisTipi != 'Satış' || h.fisId == null) {
      sonuc.add(h);
      continue;
    }
    final fisId = h.fisId!;
    if (islenmisFisIdler.contains(fisId)) continue;
    islenmisFisIdler.add(fisId);

    final grup = gruplar[fisId]!;
    if (grup.length == 1) {
      sonuc.add(h);
      continue;
    }

    final borcToplam = grup.fold(0.0, (s, g) => s + g.borc);
    final alacakToplam = grup.fold(0.0, (s, g) => s + g.alacak);
    final net = borcToplam - alacakToplam;
    sonuc.add(CariHareketModel(
      id: h.id,
      cariId: h.cariId,
      tarih: h.tarih,
      fisTipi: h.fisTipi,
      fisId: fisId,
      fisNo: h.fisNo,
      // 🔴 DÜZELTME (Cari/Fiş denetimi, 2026-09-20): metin ÖNCEDEN "ödeme
      // dağılımı için dokunun" diyordu ama bu karta dokunmak (satisMi ==
      // true dalı, aşağıda _hareketFaturalandir) HER ZAMAN faturalama
      // akışını başlatıyordu — ödeme dağılımı hiç gösterilmiyordu (o
      // sadece Satış Detayı ekranında var). Metin artık gerçek davranışı
      // yansıtıyor.
      aciklama: 'Karma Satış: ${h.fisNo ?? fisId} (fatura oluşturmak için dokunun)',
      borc: net > 0 ? net : 0,
      alacak: net < 0 ? -net : 0,
      odemeTuru: 'Karma',
      kullanici: h.kullanici,
    ));
  }
  return sonuc;
}

class CariDetayEkrani extends ConsumerWidget {
  final int cariId;
  const CariDetayEkrani({super.key, required this.cariId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cariDetayProvider(cariId));
    return async.when(
      loading: () => const Scaffold(body: Center(child: const AppYukleniyor())),
      error: (e, _) => Scaffold(
        appBar: TsAppBar(
        baslik: 'Hata',
        gradyanli: false,
      ),
        body: BosEkran(ikon: Icons.inbox_outlined, baslik: '$e')),
      data: (cari) {
        if (cari == null) return Scaffold(
          appBar: TsAppBar(
        baslik: 'Bulunamadı',
        gradyanli: false,
      ),
          body: const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Cari bulunamadı'));
        return _CariDetayIcerik(cari: cari);
      },
    );
  }
}

class _CariDetayIcerik extends ConsumerStatefulWidget {
  final CariModel cari;
  const _CariDetayIcerik({required this.cari});
  @override
  ConsumerState<_CariDetayIcerik> createState() => _CariDetayIcerikState();
}

class _CariDetayIcerikState extends ConsumerState<_CariDetayIcerik>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<CariHareketModel> _hareketler = [];
  bool _yukl = false;
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  MusteriIstatistik? _istatistik;
  MusteriSegmenti? _segment;
  bool _analizYukl = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _hareketYukle();
    if (widget.cari.cariTipi.contains('Müşteri')) _analizYukle();
  }

  // 🔴 DÜZELTME (derin analizde bulundu): "Düzenle"/"Tahsilat-Ödeme"
  // sonrası dışarıdan (CariDetayEkrani.build) cariDetayProvider
  // invalidate edilip YENİ bir `cari` bu State'e widget.cari olarak
  // geliyordu, ama _analizYukle() SADECE initState()'te çağrıldığı için
  // (Flutter aynı State nesnesini koruyor) 360° sekmesi tahsilat/
  // düzenleme sonrası ESKİ risk oranını/segmenti göstermeye devam
  // ediyordu — ör. bir tahsilat müşteriyi "Riskli"den çıkarsa bile.
  @override
  void didUpdateWidget(covariant _CariDetayIcerik oldWidget) {
    super.didUpdateWidget(oldWidget);
    final degisti = oldWidget.cari.bakiye != widget.cari.bakiye ||
        oldWidget.cari.limitTutari != widget.cari.limitTutari ||
        oldWidget.cari.cariTipi != widget.cari.cariTipi;
    if (degisti && widget.cari.cariTipi.contains('Müşteri')) _analizYukle();
  }

  Future<void> _analizYukle() async {
    if (!mounted) return;
    setState(() => _analizYukl = true);
    try {
      final servis = Musteri360Servisi();
      final c = widget.cari;
      final istat = await servis.istatistikGetir(c.id!);
      final segment = await servis.segmentGetir(c.id!,
          istatistik: istat, bakiye: c.bakiye, limitTutari: c.limitTutari);
      if (mounted) {
        setState(() {
          _istatistik = istat;
          _segment = segment;
          _analizYukl = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CariDetay analizYukle hata: $e');
      if (mounted) setState(() => _analizYukl = false);
    }
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _hareketYukle() async {
    if (!mounted) return;
    setState(() => _yukl = true);
    try {
      final h = await CariDeposu().hareketleriniGetir(widget.cari.id!);
      // 🔴 DÜZELTME (kullanıcı bulgusu, 2026-09-20): Karma ödemeli bir
      // satışta hem Cari hem Cari-dışı (Nakit/Kart/Havale) payı varsa,
      // SatisTamamlamaServisi.tamamla() AYNI satış için 2 ayrı
      // cari_hareket satırı yazıyor (gerçek Cari borcu + bakiyeyi
      // etkilemeyen bilgi amaçlı satır — bkz. o dosyanın yorumu). Bu,
      // burada AYNI satışın 2 ayrı "Satış" kartı gibi görünmesine yol
      // açıyordu — kullanıcı: "listeye bakınca 2 tane fiş görünce kafa
      // karışıklığı oluyor". cariHareketleriniGrupla() aynı fis_id'ye
      // sahip 'Satış' satırlarını TEK karta birleştirir (net bakiye
      // etkisi korunur); tam ödeme dağılımı artık Satış Detayı'nda
      // gösteriliyor (bkz. satis_detay_ekrani.dart).
      if (mounted) setState(() { _hareketler = cariHareketleriniGrupla(h); _yukl = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('CariDetay hareketYukle hata: $e');
      if (mounted) setState(() => _yukl = false);
    }
  }

  Future<void> _hareketFaturalandir(CariHareketModel h) async {
    if (h.fisId == null) return;
    setState(() => _yukl = true);
    try {
      final satis = await SatisDeposu().idileGetir(h.fisId!);
      if (satis == null || satis.kalemler == null || satis.kalemler!.isEmpty) {
        if (mounted) BildirimServisi.hata(context, 'Satış kalemleri bulunamadı.');
        return;
      }

      // Bu satış için daha önce fatura kesildiyse tekrar oluşturma
      final mevcutId = await FaturalandirmaServisi.mevcutFaturaId(satisId: h.fisId);
      if (mevcutId != null) {
        if (!mounted) return;
        BildirimServisi.basari(context, 'Bu satış için zaten bir fatura mevcut, ona yönlendiriliyorsunuz.');
        context.push('/fatura/detay/$mevcutId');
        return;
      }

      final kontrol = await FaturalandirmaServisi.kontrolEt(widget.cari.id!);
      if (kontrol == null) return;

      if (!kontrol.hazir) {
        if (!mounted) return;
        final git = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${widget.cari.unvan} için fatura kesilebilmesi için "
                  "aşağıdaki bilgiler eksik:"),
              const SizedBox(height: 10),
              ...kontrol.eksikAlanlar.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(e),
                    ]),
                  )),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cari Düzenle')),
            ],
          ),
        );
        if (git == true && mounted) {
          await context.push('/cari/ekle', extra: widget.cari);
        }
        return;
      }

      // 🔴 DÜZELTME (Madde 21 — GİB/fatura araToplam bulgusu devamı,
      // 2026-09-16): araToplam KDV DAHİL (brüt) doluyordu — bkz.
      // satis_detay_ekrani.dart'taki aynı düzeltme. Net (matrah) olmalı.
      final detaylar = satis.kalemler!.map((k) => FaturaDetayModel(
        urunId: k.urunId, urunAdi: k.urunAdi, barkod: k.barkod,
        miktar: k.miktar, birimFiyat: k.birimFiyat,
        iskontoOrani: k.iskontoOran, iskontoTutari: k.iskontoTutar,
        kdvOrani: k.kdvOran, kdvTutari: k.kdvTutar,
        araToplam: k.toplamTutar - k.kdvTutar, toplamTutar: k.toplamTutar,
      )).toList();

      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol, kalemler: detaylar, faturaTipi: 'Satis',
        satisId: satis.id, tarih: satis.tarih, odenenTutar: satis.odenenTutar,
      );

      if (!mounted) return;
      BildirimServisi.basari(context, 'Fatura oluşturuldu');
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Faturalandırma hatası: $e');
    } finally {
      if (mounted) setState(() => _yukl = false);
    }
  }

  // Bayi Portalı (erp_roadmap madde 39, kullanıcı onayıyla): bir Bayi
  // tipi cari için self-servis giriş hesabı oluşturur/yönetir. Sadece
  // admin/müdür görebilir/kullanabilir (route seviyesinde 'kullanici'
  // yetkisiyle zaten korunan kullanici_ekle_ekrani.dart'tan BİLİNÇLİ
  // OLARAK ayrı, sade bir akış — bayi hesabının rol/yetki seçimine
  // ihtiyacı yok, erişimi tamamen bayi_cari_id ile router seviyesinde
  // kısıtlanıyor).
  Future<void> _bayiGirisiYonet(BuildContext context, CariModel c) async {
    final mevcut = await KullaniciDeposu().bayiCariIleGetir(c.id!);

    if (mevcut != null) {
      final k = mevcut;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Bayi Girişi'),
          content: Text(
            'Bu bayinin zaten bir portal girişi var.\n\n'
            'Kullanıcı adı: ${k.kullaniciAdi}\n'
            'Durum: ${k.aktif ? 'Aktif' : 'Pasif'}\n\n'
            'Şifreyi sıfırlamak için kullanıcı yönetimi ekranından bu '
            'kullanıcıyı düzenleyin.',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
          ],
        ),
      );
      return;
    }

    final kullaniciAdiCtrl = TextEditingController(
        text: c.unvan.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim());
    final sifreCtrl = TextEditingController();
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Bayi Girişi Oluştur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.unvan} bu bilgilerle uygulamaya kendi başına giriş yapıp '
                'ürünleri görüp sipariş verebilecek.',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: kullaniciAdiCtrl,
              decoration: const InputDecoration(
                  labelText: 'Kullanıcı Adı', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sifreCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Şifre (en az 4 karakter)', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oluştur')),
        ],
      ),
    );
    if (ok != true) return;
    final kullaniciAdi = kullaniciAdiCtrl.text.trim();
    final sifre = sifreCtrl.text.trim();
    if (kullaniciAdi.isEmpty || sifre.length < 4) {
      if (context.mounted) {
        BildirimServisi.uyari(context, 'Kullanıcı adı ve en az 4 karakterli şifre girin');
      }
      return;
    }
    try {
      final tuz = SifreHash.tuzUret();
      final model = KullaniciModel(
        kullaniciAdi: kullaniciAdi,
        sifreHash: SifreHash.hashleTuzlu(sifre, tuz),
        tuz: tuz,
        adSoyad: c.unvan,
        rol: 'personel',
        bayiCariId: c.id,
      );
      await KullaniciDeposu().ekle(model);
      if (context.mounted) {
        // Derin analizde bulundu: bayi oturumu (router kilidi sayesinde)
        // hiçbir otomatik senkron TETİKLEMİYOR — bu, kurulmamış/sıfır
        // bir cihazda bayinin kendi hesabının hiç inmemiş olması,
        // GİRİŞ BİLE YAPAMAMASI anlamına gelir. Bu tek seferlik kurulum
        // adımı olmadan bayi portalı yeni bir cihazda çalışmaz.
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Text('Bayi Girişi Oluşturuldu'),
            ]),
            content: Text(
              'Kullanıcı adı: $kullaniciAdi\n\n'
              'ÖNEMLİ — bayinin kendi cihazında İLK kullanımdan önce:\n'
              'Ayarlar → Bulut Sync → "Buluttan Al" bir kez çalıştırılmalı. '
              'Aksi halde bayinin hesabı ve ürün kataloğu cihaza hiç '
              'inmediği için giriş yapamaz.',
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anladım')),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) BildirimServisi.hata(context, 'Oluşturulamadı: $e');
    }
  }

  // Kullanıcı isteği (2026-09-13): "Borç Silme" — uygulamada borç sadece
  // ödeme ile azalıyordu, tahsil edilemeyen/hatayla girilmiş bir bakiyeyi
  // KAPATACAK bir yol hiç yoktu. Kanonik bakiye formülü
  // (SUM(borc)-SUM(alacak), bkz. CariDeposu.bakiyeYenidenHesapla) hiç
  // bozulmuyor — ters yönde (alacak) bir cari_hareket eklenir, hiçbir
  // geçmiş kayıt silinmez/değiştirilmez (ORİJİNAL→REVERSAL deseni,
  // FAZ 1 madde 5 ile aynı felsefe). Riskli/kötüye kullanılabilir bir
  // işlem olduğu için: (1) sadece müdür/admin görebilir/çalıştırabilir,
  // (2) hemen öncesinde kendi şifresini yeniden girmesi istenir, (3) her
  // zaman Onay Merkezi'ne kayıt düşer (OnayTuru.borcSilme zaten
  // onay_merkezi_servisi.dart'ta tanımlıydı ama hiçbir ekran bağlamıyordu).
  Future<void> _borcSil(BuildContext context, CariModel c) async {
    if (!ref.read(authProvider).isMudur) return;

    final tutarCtrl = TextEditingController(text: c.bakiye.toStringAsFixed(2));
    final sebepCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.money_off, color: Colors.red),
          SizedBox(width: 8),
          Text('Borç Sil'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.unvan} — güncel borç: ${ParaUtils.formatla(c.bakiye)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Bu işlem GERİ ALINAMAZ. Hatayla girilmiş veya tahsil '
              'edilemeyen bir borcu kapatmak için kullanın — cari hareket '
              'geçmişinde izlenebilir kalır, hiçbir kayıt silinmez.',
              style: TextStyle(fontSize: 11, color: Colors.orange),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tutarCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Silinecek Tutar (₺)', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sebepCtrl,
              decoration: const InputDecoration(
                  labelText: 'Sebep (zorunlu)', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final tutar = double.tryParse(tutarCtrl.text.replaceAll(',', '.')) ?? 0;
    final sebep = sebepCtrl.text.trim();
    if (tutar <= 0 || tutar > c.bakiye + 0.01) {
      if (context.mounted) {
        BildirimServisi.uyari(context, 'Geçerli bir tutar girin (0 - ${ParaUtils.formatla(c.bakiye)} arası)');
      }
      return;
    }
    if (sebep.isEmpty) {
      if (context.mounted) BildirimServisi.uyari(context, 'Sebep girilmesi zorunludur');
      return;
    }

    if (!context.mounted) return;
    final onaylandi = await yoneticiSifresiIleOnayIste(
      context,
      baslik: 'Borç Silme Onayı',
      aciklama: '${c.unvan} carisinden ${ParaUtils.formatla(tutar)} tutarında '
          'borç silinecek. Devam etmek için şifrenizi girin.',
    );
    if (!onaylandi) return;
    if (!context.mounted) return;
    if (!ref.read(authProvider).isMudur) return; // savunma: eylem anında ikinci kez doğrula

    try {
      await CariDeposu().hareketEkle(CariHareketModel(
        cariId: c.id!,
        fisTipi: 'Borç Silme',
        tarih: DateTime.now(),
        aciklama: 'Borç Silindi: $sebep',
        borc: 0,
        alacak: tutar,
        kullanici: ref.read(authProvider).aktifAd,
      ));
      await OnayMerkeziServisi().kaydet(
        tur: OnayTuru.borcSilme,
        tutar: tutar,
        esikTutar: OnayEsikleri.borcSilmeTutari,
        referansTuru: 'cari',
        referansId: c.id,
        aciklama: '${c.unvan}: $sebep',
      );
      if (context.mounted) {
        BildirimServisi.basari(context, 'Borç silindi: ${ParaUtils.formatla(tutar)}');
        ref.invalidate(cariDetayProvider(c.id!));
        ref.read(carilerProvider.notifier).yukle();
      }
    } catch (e) {
      if (context.mounted) BildirimServisi.hata(context, 'Silinemedi: $e');
    }
  }

  Color get _bakiyeRenk {
    final c = widget.cari;
    if (c.bakiye == 0) return context.textSecondary;
    final musteri = c.cariTipi.contains('Müşteri');
    if (musteri) return c.bakiye > 0 ? Colors.green.shade700 : Colors.blue.shade700;
    return c.bakiye < 0 ? Colors.red.shade700 : Colors.blue.shade700;
  }

  String get _bakiyeEtiket {
    final c = widget.cari;
    if (c.bakiye == 0) return 'Dengede';
    final musteri = c.cariTipi.contains('Müşteri');
    if (musteri) return c.bakiye > 0 ? 'Alacağımız' : 'Fazla Ödedi';
    return c.bakiye < 0 ? 'Borcumuz' : 'Fazla Ödedik';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cari;
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(c.unvan, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          _eFaturaRozeti(c),
        ]),
        aksiyonlar: [
          if (c.cariTipi.contains('Müşteri'))
            IconButton(
              icon: const Icon(Icons.stars_outlined, color: Colors.amber),
              tooltip: 'Puanlar',
              onPressed: () => context.push('/cari/puan/${c.id}',
                  extra: {'unvan': c.unvan}),
            ),
          if (c.musteriTipi == 'Bayi' && ref.read(authProvider).isMudur)
            IconButton(
              icon: const Icon(Icons.badge_outlined, color: Colors.white),
              tooltip: 'Bayi Girişi',
              onPressed: () => _bayiGirisiYonet(context, c),
            ),
          if (c.cariTipi.contains('Müşteri') && c.bakiye > 0 && ref.read(authProvider).isMudur)
            IconButton(
              icon: const Icon(Icons.money_off, color: Colors.white),
              tooltip: 'Borç Sil',
              onPressed: () => _borcSil(context, c),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Düzenle',
            onPressed: () => context.push('/cari/ekle', extra: c).then((_) {
              ref.invalidate(cariDetayProvider(c.id!));
              ref.read(carilerProvider.notifier).yukle();
            }),
          ),
        ],
        alt: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Bilgi'),
            Tab(text: 'Hareketler'),
            Tab(text: '360°'),
          ],
        ),
      ),
      body: TabBarView(controller: _tab, children: [
        _bilgiTab(context, c),
        _hareketTab(),
        _analizTab(context, c),
      ]),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'hareket',
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            child: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/cari/hareket/${c.id}'),
            tooltip: 'Hareket Ekle',
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
        elevation: 6,
            heroTag: 'tahsilat',
            backgroundColor: AppRenkler.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Tahsilat/Ödeme'),
            onPressed: () async {
              await context.push('/cari/tahsilat/${c.id}');
              ref.invalidate(cariDetayProvider(c.id!));
              ref.read(carilerProvider.notifier).yukle();
              _hareketYukle();
            },
          ),
        ],
      ),
    );
  }

  /// VKN (10 hane) → e-Fatura mükellefi (kurumsal), TC (11 hane) → e-Arşiv (bireysel).
  /// GİB canlı sorgusu yapılmaz; format bazlı tahmindir, tooltip'te belirtilir.
  Widget _eFaturaRozeti(CariModel c) {
    final vkn = c.vergiNo?.trim();
    final tc  = c.tcKimlik?.trim();
    String etiket; IconData ikon; Color renk;
    if (vkn != null && vkn.length == 10) {
      etiket = 'e-Fatura'; ikon = Icons.verified_outlined; renk = const Color(0xFF2E7D32);
    } else if (tc != null && tc.length == 11) {
      etiket = 'e-Arşiv'; ikon = Icons.description_outlined; renk = const Color(0xFF1565C0);
    } else {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: vkn != null && vkn.length == 10
          ? 'VKN (10 hane) — Kurumsal mükellef. Fatura kesilirken e-Fatura olarak '
            'düzenlenir (GİB üzerinden gerçek mükellefiyet teyidi yapılmaz).'
          : 'TC Kimlik No (11 hane) — Bireysel müşteri. Fatura kesilirken '
            'e-Arşiv Fatura olarak düzenlenir.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Color.fromARGB(40, renk.red, renk.green, renk.blue),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Color.fromARGB(90, renk.red, renk.green, renk.blue)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon, size: 13, color: renk),
          const SizedBox(width: 3),
          Text(etiket, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: renk)),
        ]),
      ),
    );
  }

  Widget _bilgiTab(BuildContext ctx, CariModel c) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // Bakiye kartı
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_bakiyeRenk, Color.fromARGB(178, _bakiyeRenk.red, _bakiyeRenk.green, _bakiyeRenk.blue)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
              color: Color.fromARGB(76, _bakiyeRenk.red, _bakiyeRenk.green, _bakiyeRenk.blue), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Column(children: [
          Text(_bakiyeEtiket, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 4),
          Text(ParaUtils.formatla(c.bakiye.abs()),
              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
        ]),
      ),
      const SizedBox(height: 16),
      _Kart(children: [
        _Satir('Cari Tipi', c.cariTipi),
        if (c.cariKodu != null) _Satir('Cari Kodu', c.cariKodu!),
        if (c.telefon != null) _Satir('Telefon', c.telefon!),
        if (c.email != null) _Satir('E-Posta', c.email!),

        if (c.vergiNo != null) _Satir('Vergi No', c.vergiNo!),
        if (c.tcKimlik != null) _Satir('TC Kimlik No', c.tcKimlik!),
        if (c.vergiDairesi != null) _Satir('Vergi Dairesi', c.vergiDairesi!),
        if (c.limitTutari != null && c.limitTutari! > 0)
          _Satir('Kredi Limiti', ParaUtils.formatla(c.limitTutari!)),
      ]),
      const SizedBox(height: 80),
    ],
  );

  Widget _hareketTab() {
    if (_yukl) return const Center(child: const AppYukleniyor());
    if (_hareketler.isEmpty) return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_outlined, size: 48, color: context.textSecondary),
        const SizedBox(height: 8),
        Text('Hareket yok', style: TextStyle(color: context.textSecondary)),
      ]));
    return RefreshIndicator(
      onRefresh: _hareketYukle,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _hareketler.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final h = _hareketler[i];
          final borc = (h.borc ?? 0.0) as double;
          final alacak = (h.alacak ?? 0.0) as double;
          final giris = alacak > 0;
          final satisMi = h.fisTipi == 'Satış' && h.fisId != null;

          // 🔴 DÜZELTME (kullanıcı bulgusu — "hangi ürün olduğu belli
          // mi artık"): Toptan satış / bekleyen sipariş onayı / masa
          // satışı hareketlerine dokununca HİÇBİR ŞEY olmuyordu —
          // `onTap` sadece BİREBİR 'Satış' fisTipi'nde tetikleniyordu.
          // Kullanıcı hangi ürünlerin satıldığını göremiyordu.
          //
          // 'Satış' fisTipi'nin mevcut davranışına (dokununca doğrudan
          // faturalandırma akışını başlatması) DOKUNULMADI — bu turun
          // kapsamı sadece eksik olan görüntüleme yolu.
          final detayGorulebilirMi = h.fisId != null && !satisMi && (
              h.fisTipi == 'Toptan Satış' ||
              h.fisTipi == 'Toptan Satış (Sipariş)' ||
              h.fisTipi == 'Masa Satış');
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: satisMi
                  ? () => _hareketFaturalandir(h)
                  : detayGorulebilirMi
                      ? () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => FisDetayEkrani(
                            fisId: h.fisId!,
                            fisTipi: h.fisTipi,
                            cariUnvan: widget.cari.unvan,
                          ),
                        ))
                      : null,
              child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (giris ? Colors.green : Colors.red).withAlpha(26),
                  shape: BoxShape.circle),
                child: Icon(
                  giris ? Icons.add : Icons.remove,
                  color: giris ? Colors.green : Colors.red, size: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.fisTipi ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                if (h.aciklama != null)
                  Text(h.aciklama!, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                Text(_fmt.format(h.tarih), style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (borc > 0) Text('+${ParaUtils.formatla(borc)}',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 13)),
                if (alacak > 0) Text('+${ParaUtils.formatla(alacak)}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              if (satisMi) ...[
                const SizedBox(width: 6),
                Icon(Icons.receipt_long_outlined, size: 18, color: TsRenk.metinIkincil(context)),
              ],
            ]),
            ),
          );
        },
      ),
    );
  }

  Widget _analizTab(BuildContext ctx, CariModel c) {
    if (!c.cariTipi.contains('Müşteri')) {
      return Center(
        child: Text('360° analiz şu an sadece müşteriler için hesaplanıyor',
            style: TextStyle(color: context.textSecondary)),
      );
    }
    if (_analizYukl) return const Center(child: AppYukleniyor());
    final istat = _istatistik;
    if (istat == null || istat.islemSayisi == 0) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.insights_outlined, size: 48, color: context.textSecondary),
          const SizedBox(height: 8),
          Text('Henüz satış geçmişi yok', style: TextStyle(color: context.textSecondary)),
        ]),
      );
    }
    final riskOrani = c.limitTutari > 0 ? (c.bakiye / c.limitTutari) : 0.0;
    return RefreshIndicator(
      onRefresh: _analizYukle,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_segment != null) _segmentRozeti(ctx, _segment!),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'Toplam Ciro',
                    deger: ParaUtils.formatla(istat.toplamCiro),
                    ikon: const Icon(Icons.payments_outlined),
                    vurguRenk: TsRenk.basarili)),
            const SizedBox(width: 12),
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'İşlem Sayısı',
                    deger: '${istat.islemSayisi}',
                    ikon: const Icon(Icons.receipt_long_outlined))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'Ortalama Sepet',
                    deger: ParaUtils.formatla(istat.ortalamaSepet),
                    ikon: const Icon(Icons.shopping_cart_outlined))),
            const SizedBox(width: 12),
            Expanded(
                child: TsKart.istatistik(
                    baslik: 'Alışveriş Sıklığı',
                    deger: istat.ortalamaGunAraligi == null
                        ? '—'
                        : '${istat.ortalamaGunAraligi!.round()} günde bir',
                    ikon: const Icon(Icons.event_repeat_outlined))),
          ]),
          if (c.limitTutari > 0) ...[
            const SizedBox(height: 12),
            _Kart(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Risk Limiti Kullanımı',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary)),
                      const Spacer(),
                      Text('%${(riskOrani * 100).clamp(0, 999).toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: riskOrani >= 0.9
                                  ? TsRenk.hata
                                  : riskOrani >= 0.6
                                      ? TsRenk.uyari
                                      : TsRenk.basarili)),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                          value: riskOrani.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: TsRenk.ayirac(ctx),
                          color: riskOrani >= 0.9
                              ? TsRenk.hata
                              : riskOrani >= 0.6
                                  ? TsRenk.uyari
                                  : TsRenk.basarili),
                    ),
                  ],
                ),
              ),
            ]),
          ],
          if (istat.enCokAlinanUrunler.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('En Çok Alınan Ürünler',
                style: TsMetin.baslikM.copyWith(color: TsRenk.metinBirincil(ctx))),
            const SizedBox(height: 8),
            ...istat.enCokAlinanUrunler.map((u) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TsKart.liste(
                    baslik: u.urunAdi,
                    altBaslik: '${_miktarStr(u.miktar)} adet/birim',
                    deger: ParaUtils.formatla(u.tutar),
                  ),
                )),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String _miktarStr(double m) =>
      m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(2);

  Widget _segmentRozeti(BuildContext ctx, MusteriSegmenti s) {
    final (renk, ikon) = switch (s) {
      MusteriSegmenti.vip => (TsRenk.accent, Icons.workspace_premium_outlined),
      MusteriSegmenti.sadik => (TsRenk.basarili, Icons.favorite_outline),
      MusteriSegmenti.riskli => (TsRenk.hata, Icons.warning_amber_outlined),
      MusteriSegmenti.kaybedilmekUzere => (TsRenk.uyari, Icons.trending_down_outlined),
      MusteriSegmenti.yeni => (TsRenk.bilgi, Icons.fiber_new_outlined),
      MusteriSegmenti.standart => (TsRenk.notr, Icons.person_outline),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TsRenk.zemin(renk),
        borderRadius: BorderRadius.circular(TsRadius.lg),
        border: Border.all(color: TsRenk.zemin(renk, opaklik: 0.4)),
      ),
      child: Row(children: [
        Icon(ikon, color: renk, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Müşteri Segmenti',
                  style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(ctx))),
              Text(s.etiket,
                  style: TsMetin.baslikL.copyWith(color: renk)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Kart extends StatelessWidget {
  final List<Widget> children;
  const _Kart({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 6)]),
    child: Column(children: children),
  );
}

class _Satir extends StatelessWidget {
  final String etiket, deger;
  const _Satir(this.etiket, this.deger);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.borderColor))),
    child: Row(children: [
      Text(etiket, style: TextStyle(fontSize: 13, color: context.textSecondary)),
      const Spacer(),
      Flexible(child: Text(deger,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          textAlign: TextAlign.right)),
    ]),
  );
}
