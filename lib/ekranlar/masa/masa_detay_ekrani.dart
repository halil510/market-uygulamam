// lib/ekranlar/masa/masa_detay_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../saglayicilar/riverpod/kasa_rapor_provider.dart';
import 'package:go_router/go_router.dart';

import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../cekirdek/utils/hata_utils.dart';
import '../../modeller/masa_model.dart';
import '../../modeller/masa_siparis_model.dart';
import '../../modeller/satis_model.dart';
import '../../modeller/satis_kalem_model.dart';
import '../../saglayicilar/riverpod/masa_provider.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/masa_odeme_servisi.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';
import '../../veri/database/veritabani.dart';
import '../satis/coklu_odeme_ekrani.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../depolar/cari_deposu.dart';

class MasaDetayEkrani extends ConsumerStatefulWidget {
  final MasaModel masa;
  const MasaDetayEkrani({super.key, required this.masa});

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

  // 🔥 DÜZELTİLDİ: Adisyon fiş no geçerli karakterlerle oluşturuldu
  String _temizFisNo(String s) {
    // Sadece alfanumerik karakterler ve tire kalır
    return s.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
  }

  Future<void> _adisyonYazdir(MasaSiparisModel siparis) async {
    if (siparis.kalemler.isEmpty) {
      BildirimServisi.uyari(context, 'Sepet boş, adisyon yazdırılamaz');
      return;
    }

    setState(() => _islemAktif = true);
    try {
      final fis = await _adisyonFisOlustur(siparis);
      await YazdirmaServisi().fisYazdir(fis);
      
      await _adisyonLogKaydet(siparis.id!);
      
      if (mounted) {
        BildirimServisi.basari(context, 'Adisyon yazdırıldı');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yazdırma hatası: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  Future<void> _adisyonLogKaydet(int siparisId) async {
    try {
      final db = await Veritabani().db;
      final temizNo = _temizFisNo('ADY-${DateTime.now().millisecondsSinceEpoch}');
      final gid = const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      await db.insert('adisyon_log', {
        'global_id': gid,
        'siparis_id': siparisId,
        'adisyon_no': temizNo,
        'yazdiran_kullanici_id': AuthServisi().aktifId,
        'yazdirma_zamani': now,
        'last_updated': now,
      });
      // 🔴 Derin analizde bulundu: global_id/last_updated hiç
      // ayarlanmıyordu, BulutManager hiç çağrılmıyordu.
      final satir = await db.query('adisyon_log', where: 'global_id = ?', whereArgs: [gid], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('adisyon_log', Map<String, dynamic>.from(satir.first));
    } catch (e) {
      // Log hatasını görmezden gel, asıl işlem devam etsin
    }
  }

  // 🔥 DÜZELTİLDİ: Fiş no temizlendi
  // ÖNCEDEN burada da zaman damgası tabanlı bir fiş no üretiliyordu —
  // çok terminalli bir restoranda (birden fazla tablet/kasa aynı anda
  // adisyon kapatırsa) fatura/cari'de bulduğum aynı çakışma riskini
  // taşıyordu. Artık satış fişleriyle AYNI, sağlam, kalıcı sayaç
  // tabanlı fonksiyon kullanılıyor.
  Future<SatisModel> _adisyonFisOlustur(MasaSiparisModel siparis) async {
    final kalemler = siparis.kalemler.map((k) => SatisKalemModel(
      satisId: 0,
      urunId: k.urunId,
      urunAdi: k.urunAdi,
      barkod: null,
      miktar: k.miktar,
      birimFiyat: k.birimFiyat,
      toplamTutar: k.toplam,
      iskontoOran: 0,
      iskontoTutar: 0,
      kdvOran: k.kdvOran,
      kdvTutar: k.toplam - (k.toplam / (1 + k.kdvOran / 100)),
      netFiyat: k.toplam / (1 + k.kdvOran / 100),
      alisFiyat: 0,
      alisFiyatKdv: 0,
    )).toList();

    final temizFisNo = await Veritabani().fisNoUret('masa', subeId: AktifSubeServisi().subeId ?? 1);

    return SatisModel(
      fisNo: temizFisNo,
      tarih: DateTime.now(),
      genelToplam: siparis.hesaplananToplam,
      odemeYontemi: 'Adisyon',
      kalemler: kalemler,
      aciklama: 'Masa: ${widget.masa.ad} - Adisyon',
    );
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
                final dolu = m.durum == 'dolu';
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(ctx, m),
                  child: Container(
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
    if (hedefMasa.durum == 'dolu') {
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
        context.pop();
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
        title: Row(children: const [
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
        context.pop();
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

  Future<void> _odemeAl(MasaSiparisModel siparis) async {
    if (_islemAktif) return;
    setState(() => _islemAktif = true);

    try {
      final sonuc = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
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
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Ödeme hatası: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final siparisAsync = ref.watch(masaSiparisProvider(widget.masa.id!));

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: '${widget.masa.ad} - Masa Detayı',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            // Kullanıcı isteği: müşteriler kendi telefonuyla QR
            // okutup sipariş versin. Bu, o GERÇEK, taranabilir QR
            // kodun gösterildiği yeni ekrana gidiyor.
            tooltip: 'Müşteri İçin QR Kodu Göster',
            onPressed: () => context.push(
              '/masa/qr-goster/${widget.masa.id!}/${Uri.encodeComponent(widget.masa.ad)}',
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
              '/qr-menu/${widget.masa.id!}/${Uri.encodeComponent(widget.masa.ad)}',
            ),
          ),
          // 🔴 YENİ (kullanıcı isteği: "2. maddeyi yap" — Masa Taşıma /
          // Sipariş İptali): Backend'de (masaTasi, siparisIptal) hazır
          // olan ama HİÇ UI'ı olmayan bu iki işlem artık burada.
          // Sektör araştırması (Odoo, Lightspeed, Eats365): standart
          // desen "Actions" menüsünden "Transfer/Merge" seçimi.
          if (siparisAsync.valueOrNull != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Diğer İşlemler',
              onSelected: (v) {
                final s = siparisAsync.valueOrNull;
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _durumRenk(widget.masa.durum).withAlpha(51),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_durumIkon(widget.masa.durum), size: 14, color: _durumRenk(widget.masa.durum)),
              const SizedBox(width: 4),
              Text(_durumEtiket(widget.masa.durum),
                  style: TextStyle(fontSize: 12, color: _durumRenk(widget.masa.durum))),
            ]),
          ),
        ],
        modul: TsModul.masa,
      ),
      body: siparisAsync.when(
        loading: () => const Center(child: AppYukleniyor()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (siparis) => _MasaDetayIcerik(
          masa: widget.masa,
          siparis: siparis,
          onAdisyon: () => _adisyonYazdir(siparis!),
          onHesapIstendi: () => _hesapIstendi(siparis!),
          onOdeme: () => _odemeAl(siparis!),
          islemAktif: _islemAktif,
        ),
      ),
    );
  }

  Color _durumRenk(String durum) {
    switch (durum) {
      case 'bos': return const Color(0xFF2E7D32);
      case 'dolu': return const Color(0xFFF57C00);
      case 'hesap_istendi': return const Color(0xFFD32F2F);
      case 'rezerve': return const Color(0xFF1976D2);
      default: return context.textSecondary;
    }
  }

  IconData _durumIkon(String durum) {
    switch (durum) {
      case 'bos': return Icons.check_circle_outline;
      case 'dolu': return Icons.restaurant_menu;
      case 'hesap_istendi': return Icons.notifications_active;
      case 'rezerve': return Icons.event_busy;
      default: return Icons.table_restaurant;
    }
  }

  String _durumEtiket(String durum) {
    switch (durum) {
      case 'bos': return 'Boş';
      case 'dolu': return 'Dolu';
      case 'hesap_istendi': return 'Hesap İstendi';
      case 'rezerve': return 'Rezerve';
      default: return durum;
    }
  }
}

// ==================== MASA DETAY İÇERİK ====================
class _MasaDetayIcerik extends StatelessWidget {
  final MasaModel masa;
  final MasaSiparisModel? siparis;
  final VoidCallback onAdisyon;
  final VoidCallback onHesapIstendi;
  final VoidCallback onOdeme;
  final bool islemAktif;

  const _MasaDetayIcerik({
    required this.masa,
    required this.siparis,
    required this.onAdisyon,
    required this.onHesapIstendi,
    required this.onOdeme,
    required this.islemAktif,
  });

  @override
  Widget build(BuildContext context) {
    final aktifSiparis = siparis != null && siparis!.kalemler.isNotEmpty;
    final toplam = siparis?.hesaplananToplam ?? 0;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8)],
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(masa.ad, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${masa.kategori} • ${masa.kapasite} Kişi',
                    style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                if (siparis?.acilisZamani != null)
                  Text('Açılış: ${_formatSaat(siparis!.acilisZamani)}',
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
              ]),
            ),
            if (aktifSiparis)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TsRenk.masaAcik.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  Text('Toplam',
                      style: TextStyle(fontSize: 11, color: context.textSecondary)),
                  Text(ParaUtils.formatla(toplam),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: TsRenk.masaAcik)),
                ]),
              ),
          ]),
        ),

        Expanded(
          child: !aktifSiparis
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.receipt_long_outlined, size: 64, color: TsRenk.ayirac(context)),
                    const SizedBox(height: 12),
                    Text('Bu masada sipariş yok',
                        style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 15)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/masa/urun-ekle/${masa.id}'),
                      icon: const Icon(Icons.add),
                      label: const Text('Sipariş Başlat'),
                    ),
                  ]),
                )
              : _SiparisKalemListesi(
                  siparis: siparis!,
                  masaId: masa.id!,
                ),
        ),

        if (aktifSiparis)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  _ActionButton(
                    icon: Icons.add,
                    label: 'Ürün Ekle',
                    onTap: () => context.push('/masa/urun-ekle/${masa.id}'),
                    outlined: true,
                  ),
                  _ActionButton(
                    icon: Icons.receipt_long_outlined,
                    label: 'Adisyon',
                    onTap: onAdisyon,
                    isLoading: islemAktif,
                    outlined: true,
                  ),
                  _ActionButton(
                    icon: Icons.notifications_active_outlined,
                    label: 'Hesap İstendi',
                    onTap: onHesapIstendi,
                    outlined: true,
                    color: Colors.orange,
                  ),
                  _ActionButton(
                    icon: Icons.payments_outlined,
                    label: 'Ödeme Al',
                    onTap: onOdeme,
                    isLoading: islemAktif,
                    filled: true,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _formatSaat(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final bool outlined;
  final bool filled;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.outlined = false,
    this.filled = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? const Color(0xFF6D4C41);
    final width = (MediaQuery.of(context).size.width - 60) / (filled ? 2 : 3);

    if (filled) {
      return SizedBox(
        width: width,
        child: FilledButton.icon(
          onPressed: isLoading ? null : onTap,
          icon: isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: btnColor,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }

    return SizedBox(
      width: width,
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onTap,
        icon: isLoading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: btnColor,
          side: BorderSide(color: btnColor),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ==================== SİPARİŞ KALEM LİSTESİ ====================
class _SiparisKalemListesi extends ConsumerStatefulWidget {
  final MasaSiparisModel siparis;
  final int masaId;

  const _SiparisKalemListesi({required this.siparis, required this.masaId});

  @override
  ConsumerState<_SiparisKalemListesi> createState() => _SiparisKalemListesiState();
}

class _SiparisKalemListesiState extends ConsumerState<_SiparisKalemListesi> {
  @override
  Widget build(BuildContext context) {
    final kalemler = widget.siparis.kalemler;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: kalemler.length,
      itemBuilder: (_, i) {
        final k = kalemler[i];
        final durumRenk = _durumRenk(k.durum);
        
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TsRenk.ayirac(context)),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4)],
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF6D4C41).withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  k.miktar == k.miktar.roundToDouble()
                      ? k.miktar.toInt().toString()
                      : k.miktar.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF6D4C41)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k.urunAdi,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${ParaUtils.formatla(k.birimFiyat)} TL',
                    style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                if (k.not_ != null && k.not_!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(k.not_!,
                        style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
                  ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(ParaUtils.formatla(k.toplam),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: TsRenk.masaAcik)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: durumRenk.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_durumEtiket(k.durum),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: durumRenk)),
              ),
            ]),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: () => _kalemSil(k.id!),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ]),
        );
      },
    );
  }

  Color _durumRenk(String durum) {
    switch (durum) {
      case 'beklemede': return const Color(0xFFD32F2F);
      case 'hazirlaniyor': return const Color(0xFFEF6C00);
      case 'hazir': return const Color(0xFF2E7D32);
      case 'servis_edildi': return const Color(0xFF9E9E9E);
      default: return context.textSecondary;
    }
  }

  String _durumEtiket(String durum) {
    switch (durum) {
      case 'beklemede': return 'Bekliyor';
      case 'hazirlaniyor': return 'Hazırlanıyor';
      case 'hazir': return 'Hazır';
      case 'servis_edildi': return 'Servis Edildi';
      default: return durum;
    }
  }

  Future<void> _kalemSil(int kalemId) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ürünü Sil'),
        content: const Text('Bu ürünü siparişten silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay == true) {
      await ref.read(masaSiparisProvider(widget.masaId).notifier).kalemSil(kalemId);
    }
  }
}