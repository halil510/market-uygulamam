import 'package:go_router/go_router.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
// lib/ekranlar/fatura/fatura_detay_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart' as bc;
import 'package:intl/intl.dart';
import '../../cekirdek/utils/sayi_yaziya_cevir.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/fatura_deposu.dart';
import '../../modeller/fatura_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/gib_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';

class FaturaDetayEkrani extends ConsumerStatefulWidget {
  final int faturaId;
  const FaturaDetayEkrani({super.key, required this.faturaId});
  @override
  ConsumerState<FaturaDetayEkrani> createState() => _FaturaDetayEkraniState();
}

class _FaturaDetayEkraniState extends ConsumerState<FaturaDetayEkrani> {
  final _depo = FaturaDeposu();
  FaturaModel? _fatura;
  bool _yukleniyor = true;
  // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): ne ödeme kaydetme ne
  // de e-Fatura gönderme butonunda çift-tıklama koruması vardı. e-Fatura
  // gönderiminde durum ('gonderildi') ancak ağ çağrısı DÖNDÜKTEN sonra
  // güncelleniyordu — hızlı bir çift dokunma, ilk gönderim hâlâ
  // sürerken İKİNCİ bir GİB gönderimini (yasal bağlayıcılığı olan bir
  // e-belge için) başlatabilirdi. Tek bir bayrak, ilk await'ten ÖNCE
  // set edilip her iki işlemi de korur.
  bool _islemDevam = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final f = await _depo.idileGetir(widget.faturaId);
      if (!mounted) return;
      setState(() { _fatura = f; _yukleniyor = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _yukleniyor = false);
        BildirimServisi.hata(context, 'Fatura yüklenemedi: $e');
      }
    }
  }

  // ── Ödeme kaydet ────────────────────────────────────────────────────────
  Future<void> _odemeKaydet() async {
    if (_fatura == null || !mounted || _islemDevam) return;
    setState(() => _islemDevam = true);
    final ctrl = TextEditingController();

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

  // Fatura GİB'e (bir kez) başarıyla iletildi mi — 'gonderildi' (henüz
  // GİB onayı sorgulanmamış) VEYA 'onaylandi' (GİB onayı sorgulanmış ve
  // onaylanmış) ikisi de "artık tekrar gönderilemez" anlamına gelir.
  bool _eFaturaGonderilmis(String? durum) =>
      durum == 'gonderildi' || durum == 'onaylandi';

  // ── Durum Sorgula ──────────────────────────────────────────────────────────
  Future<void> _durumSorgula() async {
    if (_fatura?.eFaturaUuid == null) {
      BildirimServisi.uyari(context, 'Henüz gönderim yapılmamış');
      return;
    }
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(color: Color(0xFF4361EE), strokeWidth: 3),
          const SizedBox(width: 16),
          Text('GİB sorgulanıyor...'),
        ])));
    try {
      final gib = GibServisi();
      await gib.ayarlariYukle();
      final durum = await gib.durumSorgula(_fatura!.eFaturaUuid!);
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('GİB Durum'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(durum == 'onaylandi' ? Icons.check_circle : Icons.info_outline,
              color: durum == 'onaylandi' ? Colors.green : Colors.orange, size: 40),
          const SizedBox(height: 12),
          Text(durum ?? 'Bilinmiyor', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text('UUID: ${_fatura!.eFaturaUuid!.substring(0, 8)}...',
              style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
      ));
      // Durumu güncelle
      if (durum != null) {
        await _depo.eFaturaDurumGuncelle(_fatura!.id!, durum, uuid: _fatura!.eFaturaUuid);
        await _yukle();
      }
    } catch (e) {
      if (mounted) { Navigator.pop(context); BildirimServisi.hata(context, 'Hata: $e'); }
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
    final gib = GibServisi();
    await gib.ayarlariYukle();
    
    if (!gib.ayarliMi) {
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
            onPressed: () { Navigator.pop(ctx); context.push('/ayarlar/icerik'); },
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
    final bilinenDurum = _fatura!.cariMukellefDurumu;
    final onerilenTip = bilinenDurum == 'efatura' ? EFaturaTipi.eFatura
        : bilinenDurum == 'earsiv' ? EFaturaTipi.eArsiv : null;
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

    // Gönder
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(color: Color(0xFF4361EE), strokeWidth: 3),
          const SizedBox(width: 16),
          Text('GİB sistemine gönderiliyor...'),
        ])));

    try {
      final sonuc = await gib.gonder(fatura: _fatura!, tip: tip);
      if (!mounted) return;
      Navigator.pop(context); // loading dialog kapat

      if (sonuc.basarili) {
        // DB güncelle
        await _depo.eFaturaDurumGuncelle(
          _fatura!.id!, 'gonderildi',
          uuid: sonuc.uuid,
        );
        await _yukle();
        if (mounted) BildirimServisi.basari(context,
            '${tip == EFaturaTipi.eFatura ? "e-Fatura" : "e-Arşiv"} gönderildi ✓');
      } else {
        // 🔴 DÜZELTME (erp_roadmap madde 38 — e-Belge durum makinesi):
        // ÖNCEDEN gönderim başarısız olduğunda DB'ye HİÇBİR ŞEY
        // yazılmıyordu — fatura sessizce 'hazir' (Beklemede) görünmeye
        // devam ediyordu, tek iz sadece o an gösterilen ve kapanan bir
        // diyalogdu. Fatura listesi zaten 'hata' durumunu kırmızı
        // "Gönderim Hatası" rozetiyle göstermeye HAZIRDI (bkz.
        // fatura_liste_ekrani.dart) — sadece bu yazma adımı eksikti.
        // efatura_log tablosu zaten (gib_servisi.dart içinde) bu
        // başarısız denemeyi kaydediyordu, ama fatura kaydının kendisi
        // hiç işaretlenmiyordu.
        await _depo.eFaturaDurumGuncelle(_fatura!.id!, 'hata');
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
      if (!mounted) return;
      Navigator.pop(context);
      BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  // ── Firma (satıcı) bilgilerini al ───────────────────────────────────────
  Future<Map<String, String>> _firmaBilgileri() async {
    final out = <String, String>{
      'adi': 'MarketPlus', 'adres': '', 'vergiNo': '', 'vergiDairesi': '',
      'logoYolu': '', 'imzaYolu': '', 'imzaGoster': 'true',
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      out['adi']          = prefs.getString('firma_adi') ?? out['adi']!;
      out['adres']        = prefs.getString('firma_adres') ?? '';
      out['vergiNo']      = prefs.getString('firma_vergi_no') ?? '';
      out['vergiDairesi'] = prefs.getString('firma_vergi_dairesi') ?? '';
      out['logoYolu']     = prefs.getBool('fatura_logo') == true
          ? (prefs.getString('fatura_logo_yolu') ?? '') : '';
      out['imzaGoster']   = (prefs.getBool('fatura_imza') ?? true).toString();
      out['imzaYolu']     = prefs.getString('fatura_imza_yolu') ?? '';
      out['qrGoster']     = (prefs.getBool('fatura_barkod') ?? true).toString();
      if (out['vergiNo']!.isEmpty || out['adres']!.isEmpty) {
        final db = await Veritabani().db;
        final rows = await db.query('ayarlar', where:
            "anahtar IN ('firma_adi','firma_adres','firma_vergi_no','firma_vergi_dairesi')");
        final m = {for (final r in rows) r['anahtar'] as String: (r['deger'] ?? '') as String};
        if (out['adres']!.isEmpty) out['adres'] = m['firma_adres'] ?? '';
        if (out['vergiNo']!.isEmpty) out['vergiNo'] = m['firma_vergi_no'] ?? '';
        if (out['vergiDairesi']!.isEmpty) out['vergiDairesi'] = m['firma_vergi_dairesi'] ?? '';
        if (m['firma_adi'] != null && m['firma_adi']!.isNotEmpty) out['adi'] = m['firma_adi']!;
      }
    } catch (_) {/* varsayılanlarla devam */}
    return out;
  }

  // ── PDF oluştur — GİB e-Fatura/e-Arşiv görünümüne uygun ────────────────
  Future<void> _pdfGoster() async {
    if (_fatura == null || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final format = prefs.getString('fatura_yazdirma_format') ?? 'a4';
      if (format == '80mm') {
        await _pdf80mmGoster();
        return;
      }
      final bytes = await _pdfBytes();
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'PDF hatasi: $e');
    }
  }

  /// Varsayılan ayar ne olursa olsun A4 yazdırır ("⋮ Diğer" menüsü için).
  Future<void> _pdfGosterA4() async {
    if (_fatura == null || !mounted) return;
    try {
      final bytes = await _pdfBytes();
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'PDF hatasi: $e');
    }
  }

  /// PDF'i geçici dosyaya yazıp paylaşım sayfası (e-posta dahil) açar.
  Future<void> _epostaGonder() async {
    if (_fatura == null || !mounted) return;
    try {
      final bytes = await _pdfBytes();
      final dir = await getTemporaryDirectory();
      final dosya = File('${dir.path}/Fatura_${_fatura!.faturaNo ?? "fatura"}.pdf');
      await dosya.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(dosya.path, mimeType: 'application/pdf')],
        subject: '${_fatura!.faturaTipi ?? "Fatura"} - ${_fatura!.faturaNo ?? ""}',
        text: 'Sayın ${_fatura!.cariUnvan ?? ""},\n\n'
              '${_fatura!.faturaNo ?? "Fatura"} numaralı faturanız ekte yer almaktadır.\n\n'
              'İyi çalışmalar dileriz.',
      );
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Paylaşım hatası: $e');
    }
  }

  /// 80mm termal yazıcı / fiş yazdırma formatında PDF üretir.
  Future<void> _pdf80mmGoster() async {
    if (_fatura == null || !mounted) return;
    try {
      // Bağlı bir termal yazıcı varsa RAW ESC/POS gönder — PDF'in 80mm
      // sayfası bazı yazıcılarda küçük/yanlış ölçekte basılıyor.
      final yazdirma = YazdirmaServisi();
      if (yazdirma.bagliMi) {
        await yazdirma.faturaYazdir(_fatura!);
        if (mounted) BildirimServisi.basari(context, 'Fatura yazıcıya gönderildi');
        return;
      }
      final bytes = await _pdfBytes80mm();
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        format: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity,
            marginAll: 3 * PdfPageFormat.mm),
      );
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'PDF hatasi: $e');
    }
  }

  Future<Uint8List> _pdfBytes80mm() async {
    final f        = _fatura!;
    final font     = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final fmt      = DateFormat('dd.MM.yyyy HH:mm');
    final firma    = await _firmaBilgileri();
    final genislik = 80 * PdfPageFormat.mm;
    final vkn80    = f.cariVergiNo ?? '';
    final eArsivMi80 = vkn80.length == 11;

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(genislik, double.infinity, marginAll: 3 * PdfPageFormat.mm),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (firma['logoYolu']!.isNotEmpty && File(firma['logoYolu']!).existsSync())
          pw.Container(
            width: 48, height: 48,
            margin: const pw.EdgeInsets.only(bottom: 4),
            decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle),
            child: pw.ClipOval(child: pw.Image(
                pw.MemoryImage(File(firma['logoYolu']!).readAsBytesSync()),
                fit: pw.BoxFit.cover)),
          ),
        pw.Text(firma['adi']!, textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: boldFont, fontSize: 12)),
        if (firma['adres']!.isNotEmpty)
          pw.Text(firma['adres']!, textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: font, fontSize: 7)),
        if (firma['vergiDairesi']!.isNotEmpty || firma['vergiNo']!.isNotEmpty)
          pw.Text('VD: ${firma['vergiDairesi']}  VKN: ${firma['vergiNo']}',
              style: pw.TextStyle(font: font, fontSize: 7)),
        pw.SizedBox(height: 4),
        pw.Container(width: double.infinity, height: 0.5, color: PdfColors.black),
        pw.SizedBox(height: 4),
        _gibMuhru(font, boldFont, eArsivMi80, f.faturaTipi ?? 'Fatura'),
        pw.SizedBox(height: 4),
        pw.Text((f.faturaTipi ?? 'Fatura').toUpperCase(),
            style: pw.TextStyle(font: boldFont, fontSize: 11)),
        pw.Text('No: ${f.faturaNo ?? "-"}', style: pw.TextStyle(font: font, fontSize: 8)),
        pw.Text(fmt.format(f.duzenlenmeTarihi ?? f.tarih), style: pw.TextStyle(font: font, fontSize: 8)),
        if (f.eFaturaUuid != null)
          pw.Text('ETTN: ${f.eFaturaUuid}', style: pw.TextStyle(font: font, fontSize: 6)),
        if (f.odemeSekli != null)
          pw.Text('Ödeme Şekli: ${f.odemeSekli}', style: pw.TextStyle(font: font, fontSize: 6.5)),
        pw.SizedBox(height: 4),
        pw.Container(width: double.infinity, height: 0.5, color: PdfColors.black),
        pw.SizedBox(height: 4),
        pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('SAYIN',
            style: pw.TextStyle(font: boldFont, fontSize: 7))),
        pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text(f.cariUnvan ?? '-',
            style: pw.TextStyle(font: boldFont, fontSize: 9))),
        if (f.cariAdres != null && f.cariAdres!.isNotEmpty)
          pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text(f.cariAdres!,
              style: pw.TextStyle(font: font, fontSize: 6.5))),
        pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text(
            'VD: ${f.cariVergiDairesi ?? "-"}  VKN/TC: ${f.cariVergiNo ?? "-"}',
            style: pw.TextStyle(font: font, fontSize: 6.5))),
        pw.SizedBox(height: 4),
        pw.Container(width: double.infinity, height: 0.5, color: PdfColors.black),
        pw.SizedBox(height: 4),
        // Kalemler — kompakt
        ...f.detaylar.map((d) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(d.urunAdi, style: pw.TextStyle(font: font, fontSize: 8)),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(
                '${d.miktar.toStringAsFixed(d.miktar == d.miktar.roundToDouble() ? 0 : 2)} x '
                '${ParaUtils.formatla(d.birimFiyat)} (KDV %${d.kdvOrani.toStringAsFixed(0)})',
                style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey700)),
              pw.Text(ParaUtils.formatla(d.toplamTutar),
                  style: pw.TextStyle(font: boldFont, fontSize: 8)),
            ]),
          ]),
        )),
        pw.Container(width: double.infinity, height: 0.5, color: PdfColors.black),
        pw.SizedBox(height: 4),
        _termalToplamSatir('Ara Toplam', f.toplamAraToplam, font, boldFont),
        if (f.toplamIskonto > 0) _termalToplamSatir('İndirim', -f.toplamIskonto, font, boldFont),
        _termalToplamSatir('KDV', f.toplamKdv, font, boldFont),
        pw.SizedBox(height: 2),
        _termalToplamSatir('GENEL TOPLAM', f.genelToplam, font, boldFont, vurgu: true),
        pw.SizedBox(height: 6),
        pw.Text('Yalnız, ${tutariYaziyaCevir(f.genelToplam)}',
            textAlign: pw.TextAlign.center, style: pw.TextStyle(font: font, fontSize: 7)),
        pw.SizedBox(height: 8),
        if (firma['qrGoster'] == 'true')
          pw.BarcodeWidget(
            barcode: bc.Barcode.qrCode(),
            data: f.eFaturaUuid ?? f.faturaNo ?? 'MarketPlus',
            width: 80, height: 80,
          ),
        pw.SizedBox(height: 6),
        pw.Text('Bizi tercih ettiğiniz için teşekkür ederiz.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
      ]),
    ));
    return doc.save();
  }

  pw.Widget _termalToplamSatir(String label, double val, pw.Font font, pw.Font boldFont,
      {bool vurgu = false}) =>
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(label, style: pw.TextStyle(font: vurgu ? boldFont : font, fontSize: vurgu ? 9 : 7.5)),
      pw.Text('${ParaUtils.formatla(val)} TL',
          style: pw.TextStyle(font: vurgu ? boldFont : font, fontSize: vurgu ? 9 : 7.5)),
    ]);


  Future<Uint8List> _pdfBytes() async {
      final f        = _fatura!;
      final font     = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();
      final pdf      = pw.Document();
      final fmt      = DateFormat('dd-MM-yyyy');
      final fmtSaat  = DateFormat('HH:mm:ss');
      final firma    = await _firmaBilgileri();

      final iadeMi   = (f.faturaTipi ?? '').toLowerCase().contains('iade') ||
                        (f.faturaTipi ?? '').toLowerCase().contains('ade');
      // VKN 10 hane → e-Fatura (kurumsal alıcı), TC 11 hane → e-Arşiv (bireysel)
      // ÖNCEDEN BURADA AYNI YANLIŞ VARSAYIM VARDI (Cari kartındaki sahte
      // rozette bulup düzelttiğim sorunun aynısı): "VKN 10 hane = e-Fatura
      // mükellefi" TAHMİNİ kullanılıyordu. VKN sahibi olmak, GİB'e KAYITLI
      // olmak anlamına gelmez — bu, GERÇEK basılan/PDF belgede yanlış
      // belge türü ("e-Fatura" yazıp aslında e-Arşiv olması gerekirken,
      // ya da tersi) yazılmasına yol açabilirdi, ki bu resmi bir belgede
      // ciddi bir hatadır. Artık ÖNCELİKLE GİB'de gerçekten sorgulanmış
      // sonuç (`cariMukellefDurumu`) kullanılıyor; hiç sorgulanmamışsa
      // (null) VKN uzunluğu SADECE YEDEK tahmin olarak kullanılıyor —
      // ekranda da bu durumda kullanıcı Cari Listesi'nden "Sorgula"
      // yapmaya teşvik ediliyor (bkz. fatura detay ekranındaki uyarı).
      final vkn      = f.cariVergiNo ?? '';
      final eArsivMi = f.cariMukellefDurumu != null
          ? f.cariMukellefDurumu == 'earsiv'
          : vkn.length == 11;
      final belgeAdi = iadeMi
          ? 'İade Faturası'
          : (eArsivMi ? 'e-Arşiv Fatura' : 'e-Fatura');

      // KDV oranlarına göre grupla (Hesaplanan KDV (%X))
      final kdvGruplari = <double, double>{}; // oran -> tutar
      for (final d in f.detaylar) {
        kdvGruplari[d.kdvOrani] = (kdvGruplari[d.kdvOrani] ?? 0) + d.kdvTutari;
      }
      final vergilerHaric = f.toplamAraToplam - f.toplamIskonto;

      // ÖNCEDEN "kdv_musaf" ve "tevkifat" ayarları (Ayarlar > Fatura
      // Ayarları'nda kaydediliyordu) HİÇBİR YERDE okunmuyordu — kullanıcı
      // bu anahtarları açsa bile faturada HİÇBİR etkisi olmuyordu. Artık
      // gerçekten faturaya yansıtılıyor.
      // ⚠️ ÖNEMLİ HUKUKİ NOT: Bu, sadece GÖRÜNÜM/PDF seviyesinde bir
      // düzeltmedir (fatura tutarları/veritabanı değişmiyor). Tevkifat
      // için GİB'in kesin kod listesinde onlarca farklı oran/sektör kodu
      // var (İnşaat, Temizlik, Güvenlik vb. hizmetlere göre değişir) —
      // gerçek GİB gönderiminde (e-Fatura XML) doğru tevkifat kodunun
      // kullanılması İÇİN MALİ MÜŞAVİRİNİZLE DOĞRULAMANIZI ÖNERİRİM.
      final prefsKdv = await SharedPreferences.getInstance();
      final kdvMuaf = prefsKdv.getBool('kdv_musaf') ?? false;
      final tevkifatVar = prefsKdv.getBool('tevkifat') ?? false;
      final tevkifatOrani = prefsKdv.getString('tevkifat_orani') ?? '';

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          // ── Üst bilgi kutusu: Özelleştirme No / Senaryo / Tip / Fatura No / Tarih ──
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (firma['logoYolu']!.isNotEmpty && File(firma['logoYolu']!).existsSync()) ...[
                pw.Container(
                  width: 56, height: 56,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(width: 0.7, color: PdfColors.grey400),
                  ),
                  child: pw.ClipOval(
                    child: pw.Image(pw.MemoryImage(File(firma['logoYolu']!).readAsBytesSync()),
                        width: 54, height: 54, fit: pw.BoxFit.cover),
                  ),
                ),
                pw.SizedBox(width: 10),
              ],
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(firma['adi']!,
                  style: pw.TextStyle(font: boldFont, fontSize: 16)),
              if (firma['adres']!.isNotEmpty)
                pw.Text(firma['adres']!,
                    style: pw.TextStyle(font: font, fontSize: 8.5),
                    maxLines: 2),
              if (firma['vergiDairesi']!.isNotEmpty || firma['vergiNo']!.isNotEmpty)
                pw.Text('Vergi Dairesi: ${firma['vergiDairesi']} | VKN: ${firma['vergiNo']}',
                    style: pw.TextStyle(font: font, fontSize: 8.5)),
            ]),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(belgeAdi.toUpperCase(),
                  style: pw.TextStyle(font: boldFont, fontSize: 14)),
              pw.SizedBox(height: 4),
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (firma['qrGoster'] == 'true') ...[
                  pw.BarcodeWidget(
                    barcode: bc.Barcode.qrCode(),
                    data: f.eFaturaUuid ?? f.faturaNo ?? 'MarketPlus',
                    width: 56, height: 56,
                  ),
                  pw.SizedBox(width: 6),
                ],
                _gibMuhru(font, boldFont, eArsivMi, belgeAdi),
                pw.SizedBox(width: 6),
                pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  _pdfEtiket('Özelleştirme No', 'TR1.2.1', font, boldFont),
                  _pdfEtiket('Fatura Tipi', f.faturaTipi ?? belgeAdi, font, boldFont),
                  _pdfEtiket('Fatura Numarası', f.faturaNo ?? '-', font, boldFont),
                  _pdfEtiket('Düzenlenme Tarihi', fmt.format(f.duzenlenmeTarihi ?? f.tarih), font, boldFont),
                  _pdfEtiket('Düzenlenme Zamanı', fmtSaat.format(f.duzenlenmeTarihi ?? f.tarih), font, boldFont),
                  if (f.eFaturaUuid != null)
                    _pdfEtiket('ETTN', f.eFaturaUuid!, font, boldFont),
                ]),
              ),
              ]),
            ]),
          ]),
          pw.SizedBox(height: 14),
          // ── Toplamlar özeti (üstte, GİB formatına benzer) ──────────────
          pw.Align(alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _pdfTutarSatir('Ara Toplam', f.toplamAraToplam, font, boldFont),
                if (f.toplamIskonto > 0)
                  _pdfTutarSatir('Toplam İndirim', f.toplamIskonto, font, boldFont),
                _pdfTutarSatir('Vergiler Hariç Toplam', vergilerHaric, font, boldFont),
                if (kdvMuaf)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Text('KDV Muaf', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  )
                else ...[
                  for (final entry in kdvGruplari.entries)
                    if (entry.value > 0)
                      _pdfTutarSatir('Hesaplanan KDV (%${entry.key.toStringAsFixed(0)})',
                          entry.value, font, boldFont),
                  if (tevkifatVar && tevkifatOrani.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Text('Tevkifat Oranı: $tevkifatOrani',
                          style: pw.TextStyle(font: font, fontSize: 8)),
                    ),
                ],
                _pdfTutarSatir('Vergiler Dahil Toplam', f.genelToplam, font, boldFont, vurgu: true),
                _pdfTutarSatir('Ödenecek Toplam', f.genelToplam, font, boldFont, vurgu: true),
              ]),
            ),
          ),
          pw.SizedBox(height: 14),
          // ── SAYIN: Alıcı bilgileri ───────────────────────────────────────
          pw.Text('SAYIN', style: pw.TextStyle(font: boldFont, fontSize: 9)),
          pw.SizedBox(height: 2),
          pw.Text(f.cariUnvan ?? '-',
              style: pw.TextStyle(font: boldFont, fontSize: 11)),
          if (f.cariAdres != null && f.cariAdres!.isNotEmpty)
            pw.Text(f.cariAdres!, style: pw.TextStyle(font: font, fontSize: 9)),
          pw.Text(
            'Vergi Dairesi: ${f.cariVergiDairesi ?? "-"}'
            '${vkn.isEmpty ? "" : (eArsivMi ? " | TC Kimlik Numarası: $vkn" : " | Vergi Numarası: $vkn")}',
            style: pw.TextStyle(font: font, fontSize: 9)),
          pw.SizedBox(height: 12),
          // ── Kalemler tablosu ─────────────────────────────────────────────
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(3.2),
              2: const pw.FlexColumnWidth(0.8),
              3: const pw.FlexColumnWidth(0.9),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.1),
              6: const pw.FlexColumnWidth(1.1),
              7: const pw.FlexColumnWidth(0.9),
              8: const pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey200),
                children: ['Sıra', 'Açıklama', 'Stok Kodu', 'Miktar', 'Birim Fiyat',
                            'Tutar', 'Net Tutar', 'KDV Oranı', 'Tutar']
                    .map((h) => pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Text(h,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: boldFont, fontSize: 8))))
                    .toList(),
              ),
              ...f.detaylar.asMap().entries.map((e) {
                final i = e.key + 1;
                final d = e.value;
                final netTutar = d.araToplam - d.iskontoTutari;
                return pw.TableRow(children: [
                  _pdfHucre('$i', font, align: pw.TextAlign.center),
                  _pdfHucre(d.urunAdi, font),
                  _pdfHucre(d.barkod ?? '', font, align: pw.TextAlign.center),
                  _pdfHucre('${d.miktar.toStringAsFixed(d.miktar == d.miktar.roundToDouble() ? 0 : 2)} Adet',
                      font, align: pw.TextAlign.center),
                  _pdfHucre(ParaUtils.formatla(d.birimFiyat), font, align: pw.TextAlign.right),
                  _pdfHucre(ParaUtils.formatla(d.araToplam), font, align: pw.TextAlign.right),
                  _pdfHucre(ParaUtils.formatla(netTutar), font, align: pw.TextAlign.right),
                  _pdfHucre('%${d.kdvOrani.toStringAsFixed(d.kdvOrani == d.kdvOrani.roundToDouble() ? 0 : 2)}',
                      font, align: pw.TextAlign.center),
                  _pdfHucre(ParaUtils.formatla(d.toplamTutar), font, align: pw.TextAlign.right),
                ]);
              }),
            ],
          ),
          pw.SizedBox(height: 14),
          // ── Yazıyla tutar ────────────────────────────────────────────────
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Not:', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                  pw.Text('Yalniz, ' + tutariYaziyaCevir(f.genelToplam),
                      style: pw.TextStyle(font: font, fontSize: 9)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    eArsivMi
                        ? "e-Arsiv izni kapsaminda elektronik ortamda iletilmistir."
                        : "Bu fatura 397 Sira No'lu VUK Genel Tebligi kapsaminda e-Fatura olarak duzenlenmistir.",
                    style: pw.TextStyle(font: font, fontSize: 8)),
                ]),
              ),
            ),
            if (firma['imzaGoster'] == 'true' && firma['imzaYolu']!.isNotEmpty
                && File(firma['imzaYolu']!).existsSync()) ...[
              pw.SizedBox(width: 10),
              pw.Container(
                width: 130, height: 70,
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Column(children: [
                  pw.Expanded(child: pw.Image(
                      pw.MemoryImage(File(firma['imzaYolu']!).readAsBytesSync()),
                      fit: pw.BoxFit.contain)),
                  pw.Text('Imza / Kase', style: pw.TextStyle(font: font, fontSize: 7)),
                ]),
              ),
            ],
          ]),
        ],
      ));

    return pdf.save();
  }

  /// GİB (Gelir İdaresi Başkanlığı) tarzı yuvarlak mühür — referans
  /// faturalardaki "T.C. Hazine ve Maliye Bakanlığı / Gelir İdaresi
  /// Başkanlığı" amblemine benzer, jenerik olarak üretilmiş bir rozet.
  /// Gerçek GİB logosu değildir (telif/lisans), ancak resmi belge
  /// görünümünü tamamlar.
  pw.Widget _gibMuhru(pw.Font font, pw.Font boldFont, bool eArsivMi, String belgeAdi) {
    return pw.Container(
      width: 64, height: 64,
      decoration: const pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border(
          top: pw.BorderSide(width: 1.2, color: PdfColors.red800),
          bottom: pw.BorderSide(width: 1.2, color: PdfColors.red800),
          left: pw.BorderSide(width: 1.2, color: PdfColors.red800),
          right: pw.BorderSide(width: 1.2, color: PdfColors.red800),
        ),
      ),
      padding: const pw.EdgeInsets.all(3),
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          border: pw.Border(
            top: pw.BorderSide(width: 0.5, color: PdfColors.red800),
            bottom: pw.BorderSide(width: 0.5, color: PdfColors.red800),
            left: pw.BorderSide(width: 0.5, color: PdfColors.red800),
            right: pw.BorderSide(width: 0.5, color: PdfColors.red800),
          ),
        ),
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.all(3),
        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          pw.Text('T.C.', style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.red800)),
          pw.Text('HAZİNE ve MALİYE', style: pw.TextStyle(font: font, fontSize: 3.8, color: PdfColors.red800), textAlign: pw.TextAlign.center),
          pw.Text('BAKANLIĞI', style: pw.TextStyle(font: font, fontSize: 3.8, color: PdfColors.red800)),
          pw.SizedBox(height: 2),
          pw.Text('GELİR İDARESİ', style: pw.TextStyle(font: boldFont, fontSize: 4.2, color: PdfColors.red800)),
          pw.Text('BAŞKANLIĞI', style: pw.TextStyle(font: boldFont, fontSize: 4.2, color: PdfColors.red800)),
          pw.SizedBox(height: 2),
          pw.Text(eArsivMi ? 'e-ARŞİV' : 'e-FATURA',
              style: pw.TextStyle(font: boldFont, fontSize: 5, color: PdfColors.red800)),
        ]),
      ),
    );
  }

  pw.Widget _pdfHucre(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.left}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text, textAlign: align,
          style: pw.TextStyle(font: font, fontSize: 8)));

  pw.Widget _pdfEtiket(String label, String deger, pw.Font font, pw.Font boldFont) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
        pw.SizedBox(width: 110, child: pw.Text('$label:',
            style: pw.TextStyle(font: font, fontSize: 8))),
        pw.Text(deger, style: pw.TextStyle(font: boldFont, fontSize: 8)),
      ]),
    );

  pw.Widget _pdfTutarSatir(String label, double val, pw.Font font, pw.Font boldFont,
      {bool vurgu = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label, style: pw.TextStyle(
            font: vurgu ? boldFont : font, fontSize: vurgu ? 10 : 9)),
        pw.Text('${ParaUtils.formatla(val)} TL', style: pw.TextStyle(
            font: vurgu ? boldFont : font, fontSize: vurgu ? 10 : 9)),
      ]),
    );

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Scaffold(
          body: Center(child: const CircularProgressIndicator(color: Color(0xFF4361EE), strokeWidth: 3)));
    }
    if (_fatura == null) {
      return Scaffold(
appBar: TsAppBar(
        baslik: 'Fatura Detay',
        gradyanli: false,
      ),
        body: const Center(child: Text('Fatura bulunamadi')),
      );
    }

    final f   = _fatura!;
    final fmt = DateFormat('dd.MM.yyyy');

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Text(f.faturaNo ?? 'Fatura'),
        aksiyonlar: [
          IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Önizleme',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _FaturaOnizlemeEkrani(
                    pdfBytes: _pdfBytes, faturaNo: f.faturaNo ?? 'Fatura'),
              ))),
          IconButton(
              icon: Image.asset("assets/images/pdf_icon.png", width: 22, height: 22, errorBuilder: (_, __, ___) => const Icon(Icons.picture_as_pdf)),
              tooltip: 'PDF',
              onPressed: _pdfGoster),
          IconButton(
              icon: const Icon(Icons.payment),
              tooltip: 'Odeme Kaydet',
              onPressed: (f.kalanTutar > 0 && !_islemDevam) ? _odemeKaydet : null),
          // 🔴 DÜZELTME (erp_roadmap madde 38 — e-Belge durum makinesi,
          // GERÇEK BULGU): "Durum Sorgula" GİB'den 'onaylandi' dönüp bunu
          // kaydettiğinde (eFaturaDurumGuncelle), bu iki buton SADECE
          // 'gonderildi' değerine bakıyordu — 'onaylandi' o kontrolden
          // GEÇMİYORDU. Sonuç: GİB tarafından ONAYLANMIŞ bir fatura,
          // "e-Fatura Gönder" butonu tekrar AKTİFLEŞTİĞİ için yanlışlıkla
          // İKİNCİ KEZ GİB'e gönderilebiliyordu — mükerrer gönderim riski.
          IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: _eFaturaGonderilmis(f.eFaturaDurum) ? _durumSorgula : null,
              tooltip: 'Durum Sorgula',
            ),
            IconButton(
              icon: Icon(
                _eFaturaGonderilmis(f.eFaturaDurum)
                    ? Icons.check_circle_outline
                    : Icons.send_outlined,
                color: _eFaturaGonderilmis(f.eFaturaDurum)
                    ? Colors.green : Colors.blue),
              tooltip: f.eFaturaDurum == 'onaylandi'
                  ? 'e-Fatura GİB Onayladı'
                  : _eFaturaGonderilmis(f.eFaturaDurum)
                      ? 'e-Fatura Gönderildi' : 'e-Fatura Gönder',
              onPressed: (_eFaturaGonderilmis(f.eFaturaDurum) || _islemDevam) ? null : _efaturaGonder),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Diğer',
            onSelected: (v) {
              if (v == 'eposta') _epostaGonder();
              if (v == '80mm') _pdf80mmGoster();
              if (v == 'a4') _pdfGosterA4();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'eposta', child: Row(children: [
                Icon(Icons.email_outlined, size: 18), SizedBox(width: 8),
                Text('E-posta ile Gönder'),
              ])),
              PopupMenuItem(value: '80mm', child: Row(children: [
                Icon(Icons.receipt_long_outlined, size: 18), SizedBox(width: 8),
                Text('80mm Fiş Yazdır'),
              ])),
              PopupMenuItem(value: 'a4', child: Row(children: [
                Icon(Icons.description_outlined, size: 18), SizedBox(width: 8),
                Text('A4 Yazdır'),
              ])),
            ],
          ),
        ],
        gradyanli: false,
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        // Fatura başlık kartı
        Container(
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: TsRenk.ayirac(context))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                Text(f.faturaNo ?? '-',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                _durumuChip(f.odemeDurumu),
              ]),
              const SizedBox(height: 8),
              _bilgiSatiri('Tarih', fmt.format(f.tarih)),
              if (f.vadeTarihi != null)
                _bilgiSatiri('Vade', fmt.format(f.vadeTarihi!)),
              _bilgiSatiri('Tip', f.faturaTipi ?? '-'),
              _bilgiSatiri('Cari', f.cariUnvan ?? '-'),
              if (f.cariVergiNo != null)
                _bilgiSatiri('VKN', f.cariVergiNo!),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Kalemler
        ...f.detaylar.map((d) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))),
          child: ListTile(
            dense: true,
            title: Text(d.urunAdi,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${d.miktar.toStringAsFixed(0)} x '
                '${ParaUtils.formatla(d.birimFiyat)}  KDV:%${d.kdvOrani.toStringAsFixed(0)}'),
            trailing: Text(ParaUtils.formatla(d.toplamTutar),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        )),
        const SizedBox(height: 12),

        // Toplam
        Container(
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: TsRenk.ayirac(context))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _toplamSatir('Ara Toplam', f.toplamAraToplam),
              if (f.toplamIskonto > 0)
                _toplamSatir('Iskonto', -f.toplamIskonto, renk: Colors.red),
              _toplamSatir('KDV', f.toplamKdv),
              const Divider(height: 16),
              _toplamSatir('GENEL TOPLAM', f.genelToplam,
                  bold: true, renk: TsRenk.primaryKoyu),
              if (f.odenenTutar > 0) ...[
                const SizedBox(height: 4),
                _toplamSatir('Odenen', f.odenenTutar, renk: Colors.green),
                _toplamSatir('Kalan', f.kalanTutar,
                    bold: true,
                    renk: f.kalanTutar > 0 ? Colors.red : Colors.green),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 24),

        // Ödeme butonu
        if (f.kalanTutar > 0)
          FilledButton.icon(
            onPressed: _islemDevam ? null : _odemeKaydet,
            icon: const Icon(Icons.payment),
            label: Text('Odeme Kaydet (${ParaUtils.formatla(f.kalanTutar)})'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
      ]),
    );
  }

  Widget _bilgiSatiri(String lbl, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      SizedBox(width: 60,
          child: Text(lbl,
              style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context)))),
      Text(val,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _durumuChip(String durum) {
    Color renk;
    String etiket;
    switch (durum) {
      case 'odendi':    renk = Colors.green; etiket = 'Odendi'; break;
      case 'kismi':     renk = Colors.orange; etiket = 'Kismi'; break;
      default:          renk = Colors.red; etiket = 'Beklemede';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: Color.fromARGB(26, renk.red, renk.green, renk.blue),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color.fromARGB(102, renk.red, renk.green, renk.blue))),
      child: Text(etiket,
          style: TextStyle(color: renk, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _toplamSatir(String lbl, double val,
      {bool bold = false, Color? renk}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
        Text(lbl, style: TextStyle(
            fontSize: bold ? 14 : 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
        Text(ParaUtils.formatla(val), style: TextStyle(
            fontSize: bold ? 15 : 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: renk)),
      ]),
    );
}

// ── Fatura Önizleme Ekranı ──────────────────────────────────────────────
// "E-Fatura Ön İzleme" — yazdırmadan/göndermeden önce GİB formatındaki
// PDF çıktısının tam ekran önizlemesi.
class _FaturaOnizlemeEkrani extends StatelessWidget {
  final Future<Uint8List> Function() pdfBytes;
  final String faturaNo;
  const _FaturaOnizlemeEkrani({required this.pdfBytes, required this.faturaNo});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.borderColor,
    appBar: TsAppBar(
        baslik: 'e-Fatura Ön İzleme',
      ),
    body: PdfPreview(
      build: (format) => pdfBytes(),
      pdfFileName: 'Fatura_$faturaNo.pdf',
      canChangePageFormat: false,
      canChangeOrientation: false,
      allowPrinting: true,
      allowSharing: true,
      useActions: true,
    ),
  );
}
