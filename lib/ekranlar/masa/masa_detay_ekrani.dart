// lib/ekranlar/masa/masa_detay_ekrani.dart
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../saglayicilar/riverpod/kasa_rapor_provider.dart';
import 'package:go_router/go_router.dart';

import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../cekirdek/utils/hata_utils.dart';
import '../../modeller/masa_model.dart';
import '../../modeller/masa_siparis_model.dart';
import '../../saglayicilar/riverpod/masa_provider.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/masa_odeme_servisi.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../satis/coklu_odeme_ekrani.dart';
import '../../depolar/cari_deposu.dart';
import '../../modeller/cari_model.dart';
import '../../widgetlar/ortak/musteri_secim_paneli.dart';
import '../../servisler/masa/masa_adisyon_servisi.dart';
import 'widgets/masa_detay_icerik.dart';
import 'widgets/masa_durum_rozeti.dart';

class MasaDetayEkrani extends ConsumerStatefulWidget {
  final MasaModel masa;

  /// true: masaüstü ana-detay görünümünde sağ panel olarak gömülür — kendi
  /// Scaffold/AppBar'ını çizmez, iş bitince (ödeme, taşıma, iptal) sayfayı
  /// kapatmak yerine [onKapat]'ı çağırır.
  final bool gomulu;
  final VoidCallback? onKapat;
  const MasaDetayEkrani({
    super.key,
    required this.masa,
    this.gomulu = false,
    this.onKapat,
  });

  @override
  ConsumerState<MasaDetayEkrani> createState() => _MasaDetayEkraniState();
}

class _MasaDetayEkraniState extends ConsumerState<MasaDetayEkrani> {
  bool _islemAktif = false;
  final _cariDepo = CariDeposu();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(masaSiparisProvider(widget.masa.id!).notifier).yukle();
    });
  }

  /// İş bitince ekranı kapatır: tam sayfada geri gider, gömülü panelde
  /// (masaüstü) seçimi bırakır.
  void _kapat() {
    if (widget.gomulu) {
      widget.onKapat?.call();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _adisyonYazdir(MasaSiparisModel siparis) async {
    if (siparis.kalemler.isEmpty) {
      BildirimServisi.uyari(context, 'Sepet boş, adisyon yazdırılamaz');
      return;
    }

    setState(() => _islemAktif = true);
    try {
      final fis = await MasaAdisyonServisi.fisOlustur(siparis, masaAdi: widget.masa.ad);
      await YazdirmaServisi().fisYazdir(fis);
      
      await MasaAdisyonServisi.logKaydet(siparis.id!);
      
      if (mounted) {
        BildirimServisi.basari(context, 'Adisyon yazdırıldı');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yazdırma hatası: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  // 🔴 YENİ (kullanıcı isteği: "2. maddeyi yap"): Backend'de
  // (MasaDeposu.masaTasi) hazır olan işlem — sektör standardı
  // (Odoo/Lightspeed/Eats365'te "Transfer/Merge") desene göre: masa
  // seçici göster, hedef doluysa AÇIKÇA birleştirme onayı iste.
  Future<void> _masayiTasi(MasaSiparisModel siparis) async {
    final tumMasalar = await ref.read(masaDeposuProvider).masalariGetir();
    final digerMasalar = tumMasalar.where((m) => m.id != widget.masa.id).toList();
    if (!mounted) return;
    if (digerMasalar.isEmpty) {
      BildirimServisi.uyari(context, 'Taşınacak başka masa yok');
      return;
    }

    final hedefMasa = await showModalBottomSheet<MasaModel>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Hangi masaya taşınsın?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TsRenk.metinBirincil(ctx))),
          ),
          Expanded(
            child: GridView.builder(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, childAspectRatio: 1.1, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: digerMasalar.length,
              itemBuilder: (c, i) {
                final m = digerMasalar[i];
                // Açık siparişi olan her masa (dolu / hesap istendi) birleşir;
                // önceden yalnız durum=='dolu' sayılıyor, 'hesap_istendi' masa
                // boş sanılıp onaysız birleştiriliyordu.
                final dolu = m.aktifSiparisId != null;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(ctx, m),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dolu ? Colors.red.withAlpha(25) : Colors.green.withAlpha(25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: dolu ? Colors.red.withAlpha(100) : Colors.green.withAlpha(100)),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(dolu ? Icons.event_seat : Icons.check_circle_outline,
                          color: dolu ? Colors.red : Colors.green, size: 22),
                      const SizedBox(height: 4),
                      Text(m.ad, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      if (dolu) const Text('Dolu — birleşir', style: TextStyle(fontSize: 9, color: Colors.red)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
    if (hedefMasa == null || !mounted) return;

    // Hedef masa DOLU ise, sektör standardına göre (Lightspeed: "you
    // will be asked if you want to Merge receipts") AÇIKÇA onay iste.
    if (hedefMasa.aktifSiparisId != null) {
      final onay = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Siparişler Birleştirilsin mi?'),
          content: Text('"${hedefMasa.ad}" zaten dolu. Bu masadaki tüm '
              'ürünler o masanın siparişiyle BİRLEŞTİRİLECEK. Devam edilsin mi?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, Birleştir')),
          ],
        ),
      );
      if (onay != true) return;
    }

    if (_islemAktif) return;
    setState(() => _islemAktif = true);
    try {
      await ref.read(masaDeposuProvider).masaTasi(siparis.id!, hedefMasa.id!);
      ref.read(masaListesiProvider.notifier).yukle();
      if (mounted) {
        BildirimServisi.basari(context, '${widget.masa.ad} → ${hedefMasa.ad} taşındı ✓');
        _kapat();
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Taşınamadı: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  // 🔴 YENİ (kullanıcı isteği: "2. maddeyi yap"): Yanlış açılan bir
  // masayı/siparişi tamamen iptal etme — geri alınamaz bir işlem
  // olduğu için (sektör standardı: void/iptal işlemleri genelde
  // yönetici yetkisi gerektirir) güçlü bir onay isteniyor.
  Future<void> _siparisiIptalEt(MasaSiparisModel siparis) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red), SizedBox(width: 8),
          Text('Siparişi İptal Et'),
        ]),
        content: Text('"${widget.masa.ad}" masasındaki TÜM sipariş '
            '(${siparis.kalemler.length} kalem) iptal edilecek. Bu işlem '
            'GERİ ALINAMAZ. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, İptal Et'),
          ),
        ],
      ),
    );
    if (onay != true) return;

    if (_islemAktif) return;
    setState(() => _islemAktif = true);
    try {
      await ref.read(masaDeposuProvider).siparisIptal(siparis.id!, widget.masa.id!);
      ref.read(masaListesiProvider.notifier).yukle();
      if (mounted) {
        BildirimServisi.basari(context, 'Sipariş iptal edildi');
        _kapat();
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'İptal edilemedi: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  // 🔴 Derin analizde bulundu (P2): bu fonksiyon kardeşlerinin (
  // _adisyonYazdir, _masayiTasi, _siparisIptal, _odemeAl) hepsinde olan
  // _islemAktif çift-dokunma korumasını VE try/catch'i hiç içermiyordu
  // — art arda dokunma tekrar tekrar gereksiz DB/bulut yazımına yol
  // açabiliyordu, bir hata da (ör. DB kilidi) kullanıcıya hiç
  // bildirilmiyordu.
  Future<void> _hesapIstendi(MasaSiparisModel siparis) async {
    if (_islemAktif) return;
    setState(() => _islemAktif = true);
    try {
      await ref.read(masaDeposuProvider).hesapIstendi(widget.masa.id!);
      ref.read(masaListesiProvider.notifier).yukle();
      if (mounted) {
        BildirimServisi.uyari(context, 'Hesap istendi olarak işaretlendi');
      }
    } catch (e) {
      if (mounted) {
        BildirimServisi.hata(context, 'İşaretlenemedi: ${kullaniciyaHataMetni(e)}');
      }
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  // ── Masaya müşteri (cari) bağla ────────────────────────────────────────────
  // Altyapı (masa_siparisleri.cari_id + MasaDeposu.musteriBagla) vardı ama
  // hiçbir ekrandan çağrılmıyordu — masada cari seçilemiyor, dolayısıyla
  // ödemede 'Cari' (veresiye) yöntemi hiç çıkmıyordu. Yalnızca müşteri
  // tipindeki cariler listelenir (tedarikçiler hariç).
  Future<void> _musteriSec(MasaSiparisModel siparis) async {
    if (_islemAktif) return;
    try {
      final cariler = (await _cariDepo.tumunuGetir()).where(cariMusteriMi).toList();
      if (!mounted) return;
      final secilen = await showModalBottomSheet<CariModel>(
        context: context,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 560),
        backgroundColor: Colors.transparent,
        builder: (_) => MusteriSecimPaneli(cariler: cariler, baslik: 'Müşteri Seç'),
      );
      if (secilen == null || !mounted) return;
      await ref.read(masaSiparisProvider(widget.masa.id!).notifier)
          .musteriBagla(secilen.id, secilen.unvan);
      if (mounted) BildirimServisi.basari(context, 'Müşteri bağlandı: ${secilen.unvan}');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, kullaniciyaHataMetni(e));
    }
  }

  Future<void> _musteriKaldir() async {
    if (_islemAktif) return;
    try {
      await ref.read(masaSiparisProvider(widget.masa.id!).notifier).musteriBagla(null, null);
      if (mounted) BildirimServisi.uyari(context, 'Müşteri masadan kaldırıldı');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, kullaniciyaHataMetni(e));
    }
  }

  Future<void> _odemeAl(MasaSiparisModel siparis) async {
    if (_islemAktif) return;
    setState(() => _islemAktif = true);

    try {
      final sonuc = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        // Windows: geniş pencerede ödeme ekranı iki sütuna geçer (tuş takımı sığar).
        constraints: BoxConstraints(maxWidth: Platform.isWindows ? 860 : 640),
        backgroundColor: Colors.transparent,
        builder: (_) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: CokluOdemeEkrani(
            toplamTutar: siparis.hesaplananToplam,
            cariMevcut: siparis.cariId != null,
          ),
        ),
      );

      if (!mounted) return;
      // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): _islemAktif burada,
      // GERÇEK ödeme çağrısından (MasaOdemeServisi().odemeYap — satış +
      // stok düş + kasa/cari hareket) ÖNCE false'a çevriliyordu. O await
      // sürerken "Ödeme Al" butonu yeniden etkinleşiyordu — hızlı bir
      // çift dokunma (veya yavaş bir cihazda ilk çağrı hâlâ sürerken)
      // aynı siparişin İKİNCİ KEZ ödenmesine (mükerrer satış + stok
      // düşümü + kasa/cari kaydı) yol açabilirdi. Bayrak artık fonksiyon
      // gerçekten bitene kadar (aşağıdaki finally) true kalıyor.
      if (sonuc == null) return;

      final kalemler = (sonuc['kalemler'] as List).cast<Map<String, dynamic>>();
      final paraUstu = (sonuc['para_ustu'] as num?)?.toDouble() ?? 0.0;

      // 🔴 Derin denetimde bulundu (P1): kredi limiti kontrolü
      // (CariDeposu.limitKontrolEt) sadece Toptan Satış'ta çağrılıyordu
      // — masadan 'Cari' (veresiye) ödemede müşterinin kredi limiti
      // aşımı HİÇ kontrol edilmiyordu/uyarılmıyordu. Toptan Satış'taki
      // AYNI desen (limit aşılıyorsa net onay iste, engelleme) burada
      // da uygulandı.
      final cariTutar = kalemler
          .where((k) => k['yontem'] == 'Cari')
          .fold(0.0, (s, k) => s + (k['tutar'] as num).toDouble());
      final efektifCariId = siparis.cariId;
      if (efektifCariId != null && cariTutar > 0.005) {
        final limitSonuc = await _cariDepo.limitKontrolEt(efektifCariId, cariTutar);
        if (limitSonuc.asildi) {
          if (!mounted) return;
          final devam = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: TsRenk.uyari),
                SizedBox(width: 8),
                Text('Kredi Limiti Aşılıyor'),
              ]),
              content: Text(
                'Tanımlı kredi limiti: ${ParaUtils.formatla(limitSonuc.limit)}\n'
                'Mevcut bakiye: ${ParaUtils.formatla(limitSonuc.mevcutBakiye)}\n'
                'Bu ödemeyle birlikte: ${ParaUtils.formatla(limitSonuc.mevcutBakiye + cariTutar)}\n\n'
                'Limit ${ParaUtils.formatla(limitSonuc.asimTutari)} kadar aşılacak. '
                'Yine de devam etmek istiyor musunuz?',
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Vazgeç')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TsRenk.uyari),
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Yine de Devam Et'),
                ),
              ],
            ),
          );
          if (devam != true) return;
        }
      }

      final odemeSonuc = await MasaOdemeServisi().odemeYap(
        siparis: siparis,
        masaAdi: widget.masa.ad,
        odemeKalemleri: kalemler,
        paraUstu: paraUstu,
        cariId: siparis.cariId,
        cariAdi: siparis.cariAdi,
      );

      ref.read(masaSiparisProvider(widget.masa.id!).notifier).yukle();
      ref.read(masaListesiProvider.notifier).yukle();
      // Masa ödemesi kasa bakiyesini etkiler, cariye bağlıysa cari
      // bakiyesini de etkiler — diğer ekranlarda eski veri kalmasın.
      ref.invalidate(kasaRaporProvider);
      if (siparis.cariId != null) {
        ref.invalidate(cariDetayProvider(siparis.cariId!));
        ref.read(carilerProvider.notifier).yukle();
      }

      if (mounted) {
        BildirimServisi.basari(context, paraUstu > 0.005
            ? 'Ödeme alındı ✓ (Fiş: ${odemeSonuc.fisNo}) Para üstü: ${ParaUtils.formatla(paraUstu)}'
            : 'Ödeme alındı ✓ (Fiş: ${odemeSonuc.fisNo})');
        _kapat();
      }
    } catch (e) {
      if (e is MasaSiparisDegistiHatasi) {
        // Ekranı güncel siparişle yenile; tutar yeniden kontrol edilsin.
        ref.read(masaSiparisProvider(widget.masa.id!).notifier).yukle();
        ref.read(masaListesiProvider.notifier).yukle();
      }
      if (mounted) BildirimServisi.hata(context, 'Ödeme hatası: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  /// Masanın CANLI hali (liste sağlayıcısından). Ekrana ilk girişte verilen
  /// [MasaDetayEkrani.masa] kopyası, ekran açıkken değişen durumu (ör.
  /// "Hesap İstendi", başka cihazdan açılma) göstermiyordu.
  MasaModel _canliMasa() {
    final liste = ref.watch(masaListesiProvider).value;
    if (liste == null) return widget.masa;
    for (final m in liste) {
      if (m.id == widget.masa.id) return m;
    }
    return widget.masa;
  }

  List<Widget> _aksiyonlar(MasaModel masa, AsyncValue<MasaSiparisModel?> siparisAsync) => [
        IconButton(
          icon: const Icon(Icons.qr_code_2),
          // Kullanıcı isteği: müşteriler kendi telefonuyla QR
          // okutup sipariş versin. Bu, o GERÇEK, taranabilir QR
          // kodun gösterildiği yeni ekrana gidiyor.
          tooltip: 'Müşteri İçin QR Kodu Göster',
          onPressed: () => context.push(
            '/masa/qr-goster/${widget.masa.id!}/${Uri.encodeComponent(masa.ad)}',
          ),
        ),
        IconButton(
          icon: const Icon(Icons.tablet_mac),
          // ÖNCEDEN bu buton "QR Menü Göster" olarak adlandırılmıştı
          // ama aslında gerçek bir QR kod göstermiyor — uygulama
          // İÇİNDEN gidilen bir menü tarayıcısı (personelin, elindeki
          // tablet/telefonla müşteri adına sipariş girmesi için).
          // Kafa karışıklığını önlemek için adı netleştirildi.
          tooltip: 'Menüden Sipariş Gir (Bu Cihazdan)',
          onPressed: () => context.push(
            '/qr-menu/${widget.masa.id!}/${Uri.encodeComponent(masa.ad)}',
          ),
        ),
        // 🔴 YENİ (kullanıcı isteği: "2. maddeyi yap" — Masa Taşıma /
        // Sipariş İptali): Backend'de (masaTasi, siparisIptal) hazır
        // olan ama HİÇ UI'ı olmayan bu iki işlem artık burada.
        // Sektör araştırması (Odoo, Lightspeed, Eats365): standart
        // desen "Actions" menüsünden "Transfer/Merge" seçimi.
        if (siparisAsync.value != null)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Diğer İşlemler',
            onSelected: (v) {
              final s = siparisAsync.value;
              if (s == null) return;
              if (v == 'tasi') _masayiTasi(s);
              if (v == 'iptal') _siparisiIptalEt(s);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'tasi', child: Row(children: [
                Icon(Icons.swap_horiz, size: 20), SizedBox(width: 10), Text('Masayı Taşı / Birleştir'),
              ])),
              const PopupMenuItem(value: 'iptal', child: Row(children: [
                Icon(Icons.cancel_outlined, size: 20, color: Colors.red),
                SizedBox(width: 10),
                Text('Siparişi İptal Et', style: TextStyle(color: Colors.red)),
              ])),
            ],
          ),
        MasaDurumRozeti(durum: masa.durum),
      ];

  @override
  Widget build(BuildContext context) {
    final siparisAsync = ref.watch(masaSiparisProvider(widget.masa.id!));
    final masa = _canliMasa();

    final govde = siparisAsync.when(
      loading: () => const Center(child: AppYukleniyor()),
      error: (e, _) => Center(child: Text('Hata: ${bildirimMetniniSadelestir(e.toString())}')),
      data: (siparis) => MasaDetayIcerik(
        masa: masa,
        siparis: siparis,
        onAdisyon: () => _adisyonYazdir(siparis!),
        onHesapIstendi: () => _hesapIstendi(siparis!),
        onOdeme: () => _odemeAl(siparis!),
        onMusteriSec: () => _musteriSec(siparis!),
        onMusteriKaldir: _musteriKaldir,
        islemAktif: _islemAktif,
      ),
    );

    if (widget.gomulu) return _gomuluDuzen(masa, siparisAsync, govde);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: '${masa.ad} - Masa Detayı',
        aksiyonlar: _aksiyonlar(masa, siparisAsync),
        modul: TsModul.masa,
      ),
      body: govde,
    );
  }

  /// Masaüstü ana-detay görünümünün sağ paneli: başlık şeridi + içerik +
  /// klavye kısayolları (F2 ürün ekle, F3 adisyon, F4 hesap istendi,
  /// F9 ödeme al). Esc BİLİNÇLİ bağlanmadı: uygulama genelinde "Esc = Geri"
  /// işleyicisi var (masaustu_yan_menu.dart); ayrıca bağlamak çift çalışır.
  Widget _gomuluDuzen(MasaModel masa, AsyncValue<MasaSiparisModel?> siparisAsync, Widget govde) {
    final siparis = siparisAsync.value;
    final aktif = siparis != null && siparis.kalemler.isNotEmpty;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () =>
            context.push('/masa/urun-ekle/${widget.masa.id}'),
        if (aktif) ...{
          const SingleActivator(LogicalKeyboardKey.f3): () => _adisyonYazdir(siparis),
          const SingleActivator(LogicalKeyboardKey.f4): () => _hesapIstendi(siparis),
          const SingleActivator(LogicalKeyboardKey.f9): () => _odemeAl(siparis),
        },
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: TsRenk.arkaplan(context),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              decoration: BoxDecoration(
                color: TsRenk.kart(context),
                border: Border(bottom: BorderSide(color: TsRenk.ayirac(context))),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(masa.ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                ..._aksiyonlar(masa, siparisAsync),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Paneli kapat',
                  onPressed: _kapat,
                ),
              ]),
            ),
            Expanded(child: govde),
          ]),
        ),
      ),
    );
  }

}
