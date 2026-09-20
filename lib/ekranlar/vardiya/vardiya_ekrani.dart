// lib/ekranlar/vardiya/vardiya_ekrani.dart — Geliştirilmiş
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../depolar/kasa_deposu.dart';
import '../../depolar/vardiya_deposu.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';

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
      final gecmis = await _depo.gecmisVardiyalarGetir(subeId: subeId);

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
      });
    } catch (e) {
      if (kDebugMode) debugPrint('VardiyaEkrani _yukle hata: $e');
      if (mounted) setState(() => _yukleniyor = false);
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
          const SizedBox(width: 8),
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
                  double.tryParse(kasaCtrl.text.replaceAll(',', '.')) ?? 0;
              Navigator.pop(ctx, v);
            },
            child: const Text('Aç'),
          ),
        ],
      ),
    );
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
      if (mounted)
        BildirimServisi.basari(context,
            '✓ Vardiya açıldı (Başlangıç: ${ParaUtils.formatla(bas)})');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
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
        final sayim = double.tryParse(sayimCtrl.text.replaceAll(',', '.')) ?? 0;
        final fark = sayim - beklenenNakit;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.lock_rounded, color: Colors.orange),
            const SizedBox(width: 8),
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
                  _OzetSatir('Başlangıç Kasası', ParaUtils.formatla(basBakiye)),
                  _OzetSatir('Nakit Satışlar', ParaUtils.formatla(nakit)),
                  // Madde 12 denetimi (2026-09-16): ÖNCEDEN tek bir "Diğer
                  // Nakit Hareketler" satırında toplanıyordu — artık
                  // Tahsilat/Gider/Ödeme/Virman AYRI kalemler olarak
                  // gösteriliyor (sıfır olan kategori gizlenir).
                  for (final kategori in ['Tahsilat', 'Gider', 'Ödeme', 'Virman', 'Diğer'])
                    if ((kirilim[kategori] ?? 0).abs() > 0.005)
                      _OzetSatir(kategori, ParaUtils.formatla(kirilim[kategori]!)),
                  _OzetSatir('Beklenen Kasa', ParaUtils.formatla(beklenenNakit),
                      bold: true),
                  _OzetSatir('Anlık Kasa Bak.', ParaUtils.formatla(kasaBak)),
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
                      ? Colors.green.shade50
                      : fark > 0
                          ? Colors.blue.shade50
                          : Colors.red.shade50,
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
                    double.tryParse(sayimCtrl.text.replaceAll(',', '.')) ?? 0,
                'fark': fark,
              }),
              child: const Text('Kapat'),
            ),
          ],
        );
      }),
    );

    if (sonuc == null || !mounted) return;
    setState(() => _islemAktif = true);
    try {
      final vardiyaId = _aktif!['id'] as int;
      await _depo.kapat(
        vardiyaId: vardiyaId,
        sayim: (sonuc['sayim'] as num).toDouble(),
        fark: (sonuc['fark'] as num).toDouble(),
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
    final pdf = pw.Document();
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    final basTxt = v['acilis_tarihi'] != null
        ? fmt.format(DateTime.parse(v['acilis_tarihi']))
        : '—';
    final bitTxt = v['kapanis_tarihi'] != null
        ? fmt.format(DateTime.parse(v['kapanis_tarihi']))
        : '—';
    final sure = _sureTxt(
        v['acilis_tarihi']?.toString(), v['kapanis_tarihi']?.toString());

    // Satış verisi
    final ozet = await _depo.pdfSatisOzetiGetir(v['acilis_tarihi'].toString());

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) =>
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Center(
            child: pw.Text('VARDİYA RAPORU',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 4),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Personel:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(v['ad_soyad']?.toString() ?? '—'),
        ]),
        pw.SizedBox(height: 4),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Açılış:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(basTxt),
        ]),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Kapanış:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(bitTxt),
        ]),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Süre:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(sure),
        ]),
        pw.SizedBox(height: 12),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Text('SATIŞ ÖZETİ',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 6),
        _pdfSatir('Toplam Satış', '${ozet['sayi']} adet'),
        _pdfSatir('Toplam Ciro',
            ParaUtils.formatla((ozet['ciro'] as num?)?.toDouble() ?? 0)),
        _pdfSatir('Nakit',
            ParaUtils.formatla((ozet['nakit'] as num?)?.toDouble() ?? 0)),
        _pdfSatir('Kredi Kartı',
            ParaUtils.formatla((ozet['kart'] as num?)?.toDouble() ?? 0)),
        _pdfSatir('Cari',
            ParaUtils.formatla((ozet['cari_toplam'] as num?)?.toDouble() ?? 0)),
        _pdfSatir('İskonto',
            ParaUtils.formatla((ozet['iskonto'] as num?)?.toDouble() ?? 0)),
        pw.SizedBox(height: 12),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Text('KASA',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 6),
        _pdfSatir(
            'Başlangıç',
            ParaUtils.formatla(
                (v['baslangic_bakiye'] as num?)?.toDouble() ?? 0)),
        _pdfSatir('Nakit Satış',
            ParaUtils.formatla((ozet['nakit'] as num?)?.toDouble() ?? 0)),
        _pdfSatir('Sayım',
            ParaUtils.formatla((v['nakit_sayim'] as num?)?.toDouble() ?? 0)),
        _pdfSatir(
            'Fark', ParaUtils.formatla((v['fark'] as num?)?.toDouble() ?? 0),
            bold: true),
        pw.SizedBox(height: 20),
        pw.Center(
            child: pw.Text('MarketPlus © ${DateTime.now().year}',
                style: const pw.TextStyle(fontSize: 9))),
      ]),
    ));

    await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'vardiya_raporu_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  pw.Widget _pdfSatir(String etiket, String deger, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(etiket),
              pw.Text(deger,
                  style: bold
                      ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                      : null),
            ]),
      );

  String _sureTxt(String? bas, String? bit) {
    final b = DateTime.tryParse(bas ?? '');
    final e = DateTime.tryParse(bit ?? '');
    if (b == null) return '—';
    final sure = (e ?? DateTime.now()).difference(b);
    return '${sure.inHours}s ${sure.inMinutes.remainder(60)}dk';
  }

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
        _VardiyaDurumKart(
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
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              _VardiyaKpi('Satış', '${_satisOzet['satis_sayisi'] ?? 0} adet',
                  Icons.receipt_outlined, Colors.blue.shade700),
              _VardiyaKpi(
                  'Ciro',
                  ParaUtils.formatla(
                      (_satisOzet['toplam_ciro'] as num?)?.toDouble() ?? 0),
                  Icons.trending_up,
                  Colors.green.shade700),
              _VardiyaKpi(
                  'Nakit',
                  ParaUtils.formatla(
                      (_satisOzet['nakit'] as num?)?.toDouble() ?? 0),
                  Icons.payments_outlined,
                  Colors.purple.shade700),
              _VardiyaKpi(
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
              boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 6)],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kasa Durumu',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 10),
              _OzetSatir(
                  'Başlangıç Kasası',
                  ParaUtils.formatla(
                      (_aktif!['baslangic_bakiye'] as num?)?.toDouble() ?? 0)),
              _OzetSatir(
                  'Nakit Satışlar',
                  ParaUtils.formatla(
                      (_satisOzet['nakit'] as num?)?.toDouble() ?? 0)),
              const Divider(),
              _OzetSatir(
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
                  color: Colors.red.shade50,
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
    if (_gecmis.isEmpty)
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history_outlined, size: 64, color: context.textSecondary),
        const SizedBox(height: 12),
        Text('Geçmiş vardiya yok',
            style: TextStyle(color: context.textSecondary)),
      ]));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _gecmis.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final v = _gecmis[i];
        final bas = DateTime.tryParse(v['acilis_tarihi']?.toString() ?? '');
        final bit = DateTime.tryParse(v['kapanis_tarihi']?.toString() ?? '');
        final fark = (v['fark'] as num?)?.toDouble() ?? 0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.person_outline,
                  size: 16, color: context.textSecondary),
              const SizedBox(width: 4),
              Text(v['ad_soyad']?.toString() ?? '—',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined,
                    size: 20, color: Colors.red),
                tooltip: 'PDF Rapor',
                onPressed: () => _pdfRapor(v),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
                '${bas != null ? _fmt.format(bas) : '—'}  →  ${bit != null ? _fmt.format(bit) : '—'}',
                style:
                    TextStyle(fontSize: 11, color: TsRenk.arkaplan(context))),
            const SizedBox(height: 8),
            Row(children: [
              _gecmisChip(
                  _sureTxt(v['acilis_tarihi']?.toString(),
                      v['kapanis_tarihi']?.toString()),
                  Icons.timer_outlined,
                  Colors.blue.shade700),
              const SizedBox(width: 6),
              _gecmisChip(
                  ParaUtils.formatla(
                      (v['bitis_bakiye'] as num?)?.toDouble() ?? 0),
                  Icons.account_balance_wallet_outlined,
                  Colors.green.shade700),
              const SizedBox(width: 6),
              if (fark.abs() > 0.01)
                _gecmisChip(
                    '${fark > 0 ? '+' : ''}${ParaUtils.formatla(fark)}',
                    fark > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    fark > 0 ? Colors.blue.shade700 : Colors.red.shade700),
            ]),
          ]),
        );
      },
    );
  }

  Widget _gecmisChip(String metin, IconData ikon, Color renk) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Color.fromARGB(20, renk.red, renk.green, renk.blue),
            borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon, size: 12, color: renk),
          const SizedBox(width: 3),
          Text(metin,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: renk)),
        ]),
      );
}

// ── Yardımcı Widgetlar ────────────────────────────────────────────────────────

class _OzetSatir extends StatelessWidget {
  final String etiket, deger;
  final bool bold;
  const _OzetSatir(this.etiket, this.deger, {this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(etiket,
              style:
                  TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
          const Spacer(),
          Text(deger,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );
}

class _VardiyaKpi extends StatelessWidget {
  final String baslik, deger;
  final IconData ikon;
  final Color renk;
  const _VardiyaKpi(this.baslik, this.deger, this.ikon, this.renk);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ikon, color: renk, size: 16),
            const SizedBox(width: 4),
            Text(baslik,
                style: TextStyle(
                    fontSize: 11, color: TsRenk.metinIkincil(context))),
          ]),
          const Spacer(),
          Text(deger,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: renk)),
        ]),
      );
}

class _VardiyaDurumKart extends StatelessWidget {
  final Map<String, dynamic>? aktif;
  final DateFormat fmt;
  final String sure;
  final VoidCallback onAc, onKapat;
  const _VardiyaDurumKart(
      {required this.aktif,
      required this.fmt,
      required this.sure,
      required this.onAc,
      required this.onKapat});

  @override
  Widget build(BuildContext context) {
    final acik = aktif != null;
    final bas = DateTime.tryParse(aktif?['acilis_tarihi']?.toString() ?? '');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: acik
                ? [Colors.green.shade700, Colors.green.shade500]
                : [context.textSecondary, TsRenk.arkaplan(context)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Color.fromARGB(
                  76,
                  (acik ? Colors.green : context.textSecondary).red,
                  (acik ? Colors.green : context.textSecondary).green,
                  (acik ? Colors.green : context.textSecondary).blue),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(acik ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: Colors.white, size: 28),
          const SizedBox(width: 10),
          Text(acik ? 'Vardiya Açık' : 'Vardiya Kapalı',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(20)),
            child: Text(acik ? '🟢 Aktif' : '🔴 Kapalı',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ]),
        if (acik && bas != null) ...[
          const SizedBox(height: 12),
          Text('Başlangıç: ${fmt.format(bas)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text('Süre: $sure',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (aktif?['ad_soyad'] != null)
            Text('Personel: ${aktif!['ad_soyad']}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: acik ? onKapat : onAc,
            icon: Icon(acik ? Icons.lock_rounded : Icons.lock_open_rounded),
            label: Text(acik ? 'Vardiyayı Kapat' : 'Vardiya Aç',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: acik ? Colors.orange : Colors.green,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}
