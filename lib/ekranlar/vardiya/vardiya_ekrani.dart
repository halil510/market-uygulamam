// lib/ekranlar/vardiya/vardiya_ekrani.dart — Geliştirilmiş
import '../../cekirdek/utils/denetleyici_birak.dart';
import '../../cekirdek/utils/hata_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../servisler/vardiya/vardiya_rapor_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../depolar/kasa_deposu.dart';
import '../../depolar/vardiya_deposu.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../cekirdek/enumlar/kullanici_rolu.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';

import 'masaustu/vardiya_gecmis_masaustu_gorunum.dart';
import 'widgets/vardiya_gecmis_mobil_liste.dart';
import 'widgets/vardiya_kartlari.dart';

class VardiyaEkrani extends ConsumerStatefulWidget {
  final dynamic extra;
  const VardiyaEkrani({super.key, this.extra});
  @override
  ConsumerState<VardiyaEkrani> createState() => _VardiyaEkraniState();
}

class _VardiyaEkraniState extends ConsumerState<VardiyaEkrani>
    with SingleTickerProviderStateMixin {
  final _depo = VardiyaDeposu();
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');
  late TabController _tab;

  Map<String, dynamic>? _aktif;
  List<Map<String, dynamic>> _gecmis = [];
  Map<String, dynamic> _satisOzet = {};
  bool _yukleniyor = true;
  // FAZ 6 (DEEP_AUDIT_REPORT, 2026-09-21): "Geçmiş" sekmesi önceden
  // sadece en son 30 kaydı gösterip daha eskilere ulaşmanın hiçbir yolunu
  // sunmuyordu. Artık "Daha Fazla Yükle" ile sayfalanabiliyor.
  static const _gecmisSayfaBoyutu = 30;
  bool _gecmisDahaVarMi = true;
  bool _gecmisDahaYukleniyor = false;
  // 🔴 Derin denetimde bulundu (P2): vardiya aç/kapat, kod tabanındaki
  // neredeyse tek istisna olarak çift-dokunma korumasına sahip değildi
  // — hızlı art arda dokunma (onay diyaloğu render olmadan önce) aynı
  // terminal için iki 'vardiyalar' satırı açabilirdi.
  bool _islemAktif = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      // 🔴🔴 KRİTİK DÜZELTME (komple derin analizde bulundu): bu sorgular
      // ÖNCEDEN hiç sube_id filtresi içermiyordu — çok şubeli kurulumda
      // "aktif vardiya" TÜM şubeler arasından rastgele (en son açılan)
      // vardiyayı gösteriyordu. Şube B'deki kasiyer "Vardiyayı Kapat"a
      // basınca aslında Şube A'nın açık vardiyasını kapatabiliyordu.
      final subeId = AktifSubeServisi().subeId;
      final aktif = await _depo.aktifVardiyaGetir(subeId: subeId);
      final gecmis = await _depo.gecmisVardiyalarGetir(
          subeId: subeId, limit: _gecmisSayfaBoyutu);

      // Aktif vardiya satış özeti
      Map<String, dynamic> ozet = {};
      if (aktif != null) {
        final bas = aktif['acilis_tarihi']?.toString();
        if (bas != null) {
          ozet = await _depo.satisOzetiGetir(bas);

          // 🔴🔴 FAZ 1 madde 2 (kullanıcı onayıyla): ÖNCEDEN burada ham
          // 'bakiye_sonrasi' zinciri okunuyordu — bu, Nakit VE Kart
          // satışlarının karışımıydı (bkz. rapor), yani "Anlık Kasa Bak."
          // gerçek fiziksel nakitten sistematik olarak büyük görünüyordu
          // (tam olarak o vardiyadaki kart satış tutarı kadar). Artık
          // KasaDeposu.guncelBakiyeNakit() ile SADECE nakit karşılığı olan
          // hareketler toplanıyor — "Beklenen Kasa" (satislar tablosundan,
          // zaten doğruydu) ile artık tutarlı.
          ozet['kasa_bakiye'] = await KasaDeposu().guncelBakiyeNakit();
          // 🔴 DÜZELTME (derin analizde bulundu): "Beklenen Kasa" hesabı
          // sadece nakit SATIŞLARI (satislar tablosu) sayıyordu — vardiya
          // sırasındaki nakit tahsilat/gider/ödeme/virman hiç dahil
          // değildi. Artık KasaDeposu.nakitDegisimi() ile vardiya
          // açılışından bu yana TÜM nakit kasa hareketlerinin net etkisi
          // kullanılıyor (bkz. _vardiyaKapat()).
          ozet['nakit_degisimi'] =
              await KasaDeposu().nakitDegisimi(DateTime.parse(bas));
          // Madde 12 denetimi (2026-09-16): "Diğer Nakit Hareketler" artık
          // tek bir lump-sum satır değil, Tahsilat/Gider/Ödeme/Virman
          // olarak kalem kalem ayrılıyor (bkz. _vardiyaKapat dialog).
          ozet['nakit_kirilim'] =
              await KasaDeposu().nakitDegisimiKirilim(DateTime.parse(bas));
        }
      }

      if (!mounted) return;
      setState(() {
        _aktif = aktif;
        _gecmis = gecmis;
        _satisOzet = ozet;
        _yukleniyor = false;
        _gecmisDahaVarMi = gecmis.length >= _gecmisSayfaBoyutu;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('VardiyaEkrani _yukle hata: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _gecmisDahaFazlaYukle() async {
    if (_gecmisDahaYukleniyor || !_gecmisDahaVarMi) return;
    setState(() => _gecmisDahaYukleniyor = true);
    try {
      final subeId = AktifSubeServisi().subeId;
      final sonraki = await _depo.gecmisVardiyalarGetir(
          subeId: subeId, limit: _gecmisSayfaBoyutu, offset: _gecmis.length);
      if (!mounted) return;
      setState(() {
        _gecmis = [..._gecmis, ...sonraki];
        _gecmisDahaVarMi = sonraki.length >= _gecmisSayfaBoyutu;
        _gecmisDahaYukleniyor = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('VardiyaEkrani _gecmisDahaFazlaYukle hata: $e');
      if (mounted) setState(() => _gecmisDahaYukleniyor = false);
    }
  }

  Future<void> _vardiyaAc() async {
    if (_islemAktif) return;
    // Başlangıç kasasını gir
    final kasaCtrl = TextEditingController(text: '0');
    final bas = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.lock_open_rounded, color: Colors.green),
          SizedBox(width: 8),
          Text('Vardiya Aç'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Başlangıç kasa miktarını girin:',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: kasaCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            decoration: const InputDecoration(
              labelText: 'Başlangıç Kasası (₺)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
            autofocus: true,
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: Colors.green),
            onPressed: () {
              final v =
                  ParaUtils.sayiCoz(kasaCtrl.text) ?? 0;
              Navigator.pop(ctx, v);
            },
            child: const Text('Aç'),
          ),
        ],
      ),
    ).whenComplete(() => dialogSonrasiBirak([kasaCtrl]));
    if (bas == null || !mounted) return;
    setState(() => _islemAktif = true);
    try {
      final kullanici = await AuthServisi().mevcutKullanici();
      // 🔴 Komple derin analizde bulundu: sube_id hiç yazılmıyordu —
      // her vardiya kaydı şubesiz (NULL) oluşuyordu, çok şubeli
      // kurulumda "aktif vardiya" sorgusu şubeler arasında karışıyordu.
      // 🔴 Ayrıca: global_id atanmıyordu, BulutManager hiç çağrılmıyordu
      // — vardiya açma/kapatma (çok terminalli gün sonu mutabakatı için
      // kritik) hiç senkronize olmuyordu. Bkz. VardiyaDeposu.ac().
      await _depo.ac(
        kullaniciId: kullanici?.id ?? 1,
        subeId: AktifSubeServisi().subeId,
        baslangicKasa: bas,
      );
      await _yukle();
      if (mounted) {
        BildirimServisi.basari(context,
            '✓ Vardiya açıldı (Başlangıç: ${ParaUtils.formatla(bas)})');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  /// Madde 12 denetimi (2026-09-16) — "Müdür Onayı" adımı. Kapatan
  /// kişinin kendi hesabı DEĞİL, farklı bir Müdür/Admin'in kullanıcı
  /// adı+şifresi doğrulanır (KullaniciDeposu.girisKontrol — mevcut giriş
  /// mekanizmasıyla AYNI, oturum DEĞİŞTİRMEZ). Onaylayan kullanıcı Müdür/
  /// Admin değilse veya bilgiler yanlışsa kapanış GERÇEKLEŞMEZ. İptal
  /// edilirse veya onaylanamazsa null döner.
  Future<int?> _yoneticiOnayIste() async {
    final kadCtrl = TextEditingController();
    final sifreCtrl = TextEditingController();
    String? hata;
    bool dogrulaniyor = false;
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
          Future<void> dogrula() async {
            final kad = kadCtrl.text.trim();
            final sifre = sifreCtrl.text;
            if (kad.isEmpty || sifre.isEmpty) {
              setS(() => hata = 'Kullanıcı adı ve şifre gerekli.');
              return;
            }
            setS(() { dogrulaniyor = true; hata = null; });
            final kullanici = await KullaniciDeposu().girisKontrol(kad, sifre);
            if (kullanici == null) {
              setS(() { dogrulaniyor = false; hata = 'Kullanıcı adı veya şifre hatalı.'; });
              return;
            }
            if (kullanici.rol != KullaniciRolu.admin.label &&
                kullanici.rol != KullaniciRolu.mudur.label) {
              setS(() { dogrulaniyor = false; hata = '"${kullanici.adSoyad}" Müdür/Admin değil, onaylayamaz.'; });
              return;
            }
            if (ctx.mounted) Navigator.pop(ctx, kullanici.id);
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.admin_panel_settings_outlined, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text('Müdür Onayı Gerekli'),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'Vardiyayı kapatmak için bir Müdür/Admin kimlik bilgilerini girmeli.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: kadCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Kullanıcı Adı', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: sifreCtrl,
                obscureText: true,
                onSubmitted: (_) => dogrula(),
                decoration: const InputDecoration(
                    labelText: 'Şifre', border: OutlineInputBorder()),
              ),
              if (hata != null) ...[
                const SizedBox(height: 8),
                Text(hata!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('İptal')),
              FilledButton(
                style: FilledButton.styleFrom(
                    foregroundColor: Colors.white, backgroundColor: Colors.deepPurple),
                onPressed: dogrulaniyor ? null : dogrula,
                child: dogrulaniyor
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Onayla'),
              ),
            ],
          );
      }),
    ).whenComplete(() => dialogSonrasiBirak([kadCtrl, sifreCtrl]));
  }

  Future<void> _vardiyaKapat() async {
    if (_aktif == null || _islemAktif) return;
    final nakit = (_satisOzet['nakit'] as num?)?.toDouble() ?? 0;
    final kasaBak = (_satisOzet['kasa_bakiye'] as num?)?.toDouble() ?? 0;
    final basBakiye = (_aktif!['baslangic_bakiye'] as num?)?.toDouble() ?? 0;
    // 🔴 DÜZELTME (derin analizde bulundu): 'beklenenNakit' ÖNCEDEN
    // basBakiye + nakit SATIŞ toplamıydı — vardiya sırasındaki nakit
    // tahsilat/gider/ödeme/virman hiç sayılmıyordu, kasiyer hata
    // yapmadığı halde "fazla/eksik" çıkabiliyordu. Artık
    // KasaDeposu.nakitDegisimi() ile TÜM nakit kasa hareketlerinin net
    // etkisi kullanılıyor (bkz. _yukle()'deki 'nakit_degisimi').
    final nakitDegisimi =
        (_satisOzet['nakit_degisimi'] as num?)?.toDouble() ?? nakit;
    final beklenenNakit = basBakiye + nakitDegisimi;
    final kirilim = (_satisOzet['nakit_kirilim'] as Map<String, double>?) ?? const {};

    final sayimCtrl =
        TextEditingController(text: beklenenNakit.toStringAsFixed(2));

    final sonuc = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final sayim = ParaUtils.sayiCoz(sayimCtrl.text) ?? 0;
        final fark = sayim - beklenenNakit;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.lock_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Vardiya Kapat'),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Özet
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: TsRenk.arkaplan(context),
                    borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  VardiyaOzetSatir('Başlangıç Kasası', ParaUtils.formatla(basBakiye)),
                  VardiyaOzetSatir('Nakit Satışlar', ParaUtils.formatla(nakit)),
                  // Madde 12 denetimi (2026-09-16): ÖNCEDEN tek bir "Diğer
                  // Nakit Hareketler" satırında toplanıyordu — artık
                  // Tahsilat/Gider/Ödeme/Virman AYRI kalemler olarak
                  // gösteriliyor (sıfır olan kategori gizlenir).
                  for (final kategori in ['Tahsilat', 'Gider', 'Ödeme', 'Virman', 'Diğer'])
                    if ((kirilim[kategori] ?? 0).abs() > 0.005)
                      VardiyaOzetSatir(kategori, ParaUtils.formatla(kirilim[kategori]!)),
                  VardiyaOzetSatir('Beklenen Kasa', ParaUtils.formatla(beklenenNakit),
                      bold: true),
                  VardiyaOzetSatir('Anlık Kasa Bak.', ParaUtils.formatla(kasaBak)),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sayimCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
                decoration: const InputDecoration(
                  labelText: 'Sayım Yapılan Kasa (₺)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calculate_outlined),
                ),
                onChanged: (_) => setS(() {}),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: fark.abs() < 1
                      ? TsRenk.zemin(TsRenk.basarili)
                      : fark > 0
                          ? TsRenk.zemin(TsRenk.bilgi)
                          : TsRenk.zemin(TsRenk.hata),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: fark.abs() < 1
                          ? Colors.green.shade200
                          : fark > 0
                              ? Colors.blue.shade200
                              : Colors.red.shade200),
                ),
                child: Row(children: [
                  Icon(
                      fark.abs() < 1
                          ? Icons.check_circle_outline
                          : fark > 0
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                      color: fark.abs() < 1
                          ? Colors.green
                          : fark > 0
                              ? Colors.blue
                              : Colors.red,
                      size: 18),
                  const SizedBox(width: 8),
                  Text(
                    fark.abs() < 1
                        ? 'Kasa dengeli ✓'
                        : 'Fark: ${ParaUtils.formatla(fark.abs())} ${fark > 0 ? "(fazla)" : "(eksik)"}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: fark.abs() < 1
                            ? Colors.green
                            : fark > 0
                                ? Colors.blue
                                : Colors.red),
                  ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal')),
            FilledButton(
              style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, {
                'sayim':
                    ParaUtils.sayiCoz(sayimCtrl.text) ?? 0,
                'fark': fark,
              }),
              child: const Text('Kapat'),
            ),
          ],
        );
      }),
    ).whenComplete(() => dialogSonrasiBirak([sayimCtrl]));

    if (sonuc == null || !mounted) return;

    // 🔴 DÜZELTME (Madde 12 denetimi — Müdür Onayı, 2026-09-16, kullanıcı
    // onaylı UX: "Anında PIN onayı"): vardiyayı FİİLEN kapatan kişi
    // Müdür/Admin DEĞİLSE, kapanış burada bir yöneticinin kimlik
    // bilgileriyle onaylanmadan TAMAMLANMAZ. Kapatan zaten Müdür/Admin'se
    // (kendi yetkisi yeterli) bu adım atlanır — Sayım Onayı'ndaki AYNI
    // ilke ("yetkili kendi işini onaylamaz").
    int? onaylayanId;
    if (!AuthServisi().isMudur) {
      onaylayanId = await _yoneticiOnayIste();
      if (onaylayanId == null || !mounted) return; // onay verilmedi/iptal
    }

    setState(() => _islemAktif = true);
    try {
      final vardiyaId = _aktif!['id'] as int;
      await _depo.kapat(
        vardiyaId: vardiyaId,
        sayim: (sonuc['sayim'] as num).toDouble(),
        fark: (sonuc['fark'] as num).toDouble(),
        onaylayanKullaniciId: onaylayanId,
      );
      await _yukle();
      if (mounted) BildirimServisi.basari(context, '✓ Vardiya kapatıldı');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  Future<void> _pdfRapor(Map<String, dynamic> v) async {
    try {
      await VardiyaRaporServisi.pdfPaylas(v);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, kullaniciyaHataMetni(e));
    }
  }

  String _sureTxt(String? bas, String? bit) => VardiyaRaporServisi.sureMetni(bas, bit);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Vardiya Yönetimi',
        aksiyonlar: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _yukle)
        ],
        alt: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'Aktif Vardiya'), Tab(text: 'Geçmiş')],
        ),
        geriTusu: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : TabBarView(controller: _tab, children: [
              _aktifTab(),
              _gecmisTab(),
            ]),
    );
  }

  Widget _aktifTab() {
    final acik = _aktif != null;
    return RefreshIndicator(
      onRefresh: _yukle,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        // Durum kartı
        VardiyaDurumKart(
          aktif: _aktif,
          fmt: _fmt,
          sure: _sureTxt(_aktif?['acilis_tarihi']?.toString(), null),
          onAc: _vardiyaAc,
          onKapat: _vardiyaKapat,
        ),
        if (acik && _satisOzet.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Vardiya Satış Özeti',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          // KPI grid
          // 🔴 DEEP_AUDIT_REPORT FAZ 6 (UX/UI, 2026-09-21): sabit
          // crossAxisCount:2 tablet/yatay modda gereksiz boşluk
          // bırakıyordu — diğer ekranlarla (Dashboard) tutarlı hale
          // getirmek için TsResponsive'e taşındı.
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: TsResponsive.izgaraKolonSayisi(context),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              VardiyaKpi('Satış', '${_satisOzet['satis_sayisi'] ?? 0} adet',
                  Icons.receipt_outlined, Colors.blue.shade700),
              VardiyaKpi(
                  'Ciro',
                  ParaUtils.formatla(
                      (_satisOzet['toplam_ciro'] as num?)?.toDouble() ?? 0),
                  Icons.trending_up,
                  Colors.green.shade700),
              VardiyaKpi(
                  'Nakit',
                  ParaUtils.formatla(
                      (_satisOzet['nakit'] as num?)?.toDouble() ?? 0),
                  Icons.payments_outlined,
                  Colors.purple.shade700),
              VardiyaKpi(
                  'Kredi K.',
                  ParaUtils.formatla(
                      (_satisOzet['kart'] as num?)?.toDouble() ?? 0),
                  Icons.credit_card_outlined,
                  Colors.teal.shade700),
            ],
          ),
          const SizedBox(height: 12),
          // Kasa durumu
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 6)],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kasa Durumu',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 10),
              VardiyaOzetSatir(
                  'Başlangıç Kasası',
                  ParaUtils.formatla(
                      (_aktif!['baslangic_bakiye'] as num?)?.toDouble() ?? 0)),
              VardiyaOzetSatir(
                  'Nakit Satışlar',
                  ParaUtils.formatla(
                      (_satisOzet['nakit'] as num?)?.toDouble() ?? 0)),
              const Divider(),
              VardiyaOzetSatir(
                  'Anlık Kasa Bak.',
                  ParaUtils.formatla(
                      (_satisOzet['kasa_bakiye'] as num?)?.toDouble() ?? 0),
                  bold: true),
            ]),
          ),
          if ((_satisOzet['iptal_sayisi'] as int? ?? 0) > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: TsRenk.zemin(TsRenk.hata),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.cancel_outlined, color: Colors.red, size: 16),
                const SizedBox(width: 6),
                Text('${_satisOzet['iptal_sayisi']} iptal satış',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
              ]),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _gecmisTab() {
    if (_gecmis.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history_outlined, size: 64, color: context.textSecondary),
        const SizedBox(height: 12),
        Text('Geçmiş vardiya yok',
            style: TextStyle(color: context.textSecondary)),
      ]));
    }
    if (MediaQuery.sizeOf(context).width > 1100) {
      return VardiyaGecmisMasaustuGorunum(
        vardiyalar: _gecmis,
        sureMetni: _sureTxt,
        onPdf: _pdfRapor,
        dahaVarMi: _gecmisDahaVarMi,
        dahaYukleniyor: _gecmisDahaYukleniyor,
        onDahaFazla: _gecmisDahaFazlaYukle,
      );
    }
    return VardiyaGecmisMobilListe(
      vardiyalar: _gecmis,
      sureMetni: _sureTxt,
      onPdf: _pdfRapor,
      dahaVarMi: _gecmisDahaVarMi,
      dahaYukleniyor: _gecmisDahaYukleniyor,
      onDahaFazla: _gecmisDahaFazlaYukle,
    );
  }
}
