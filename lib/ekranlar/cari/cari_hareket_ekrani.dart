// lib/ekranlar/cari/cari_hareket_ekrani.dart
import 'package:flutter/foundation.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:uuid/uuid.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/kasa_deposu.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/cari_hareket_model.dart';
import '../../modeller/kasa_hareket_model.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../veri/database/veritabani.dart';
import 'fis_detay_ekrani.dart';
import '../../tasarim_sistemi/ts_kart.dart';

class CariHareketEkrani extends ConsumerStatefulWidget {
  final int cariId;
  const CariHareketEkrani({super.key, required this.cariId});
  @override
  ConsumerState<CariHareketEkrani> createState() => _CariHareketEkraniState();
}

class _CariHareketEkraniState extends ConsumerState<CariHareketEkrani> {
  final _depo = CariDeposu();
  final _db = Veritabani();
  final _fmt = DateFormat('dd.MM.yyyy');
  final _fmtT = DateFormat('dd.MM.yyyy HH:mm');

  CariModel? _cari;
  List<CariHareketModel> _tumHareketler = [];
  List<CariHareketModel> _filtreli = [];
  bool _yukleniyor = true;
  String? _filtreTip;
  DateTimeRange? _tarihAralik;
  double _toplamBorc = 0, _toplamAlacak = 0, _bakiye = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Color _bakiyeRenk() {
    if (_bakiye == 0) return context.textSecondary;
    final musteri = _cari?.cariTipi == 'Müşteri' ||
        _cari?.cariTipi == 'Hem Müşteri Hem Tedarikçi';
    if (musteri) {
      return _bakiye > 0 ? Colors.green.shade700 : Colors.blue.shade700;
    } else {
      return _bakiye < 0 ? Colors.red.shade700 : Colors.blue.shade700;
    }
  }

  Future<void> _yukle() async {
    _yukleniyor = true;

    if (mounted) setState(() {});
    try {
      final cari = await _depo.idileGetir(widget.cariId);
      final hareketler = await _hareketleriGetir();
      if (!mounted) return;
      setState(() {
        _cari = cari;
        _tumHareketler = hareketler;
        _filtrele();
        _yukleniyor = false;
      });
    } catch (e) {
      if (mounted) {
        _yukleniyor = false;
        BildirimServisi.hata(context, 'Hata: $e');
      }
    }
  }

  Future<List<CariHareketModel>> _hareketleriGetir() async {
    final db = await _db.db;
    final rows = await db.rawQuery(
      'SELECT * FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0 ORDER BY tarih DESC',
      [widget.cariId],
    );
    return rows.map(CariHareketModel.fromMap).toList();
  }

  void _filtrele() {
    var list = List<CariHareketModel>.from(_tumHareketler);
    if (_filtreTip != null) {
      list = list.where((h) => h.fisTipi == _filtreTip).toList();
    }
    if (_tarihAralik != null) {
      list = list
          .where((h) =>
              h.tarih.isAfter(
                  _tarihAralik!.start.subtract(const Duration(days: 1))) &&
              h.tarih.isBefore(_tarihAralik!.end.add(const Duration(days: 1))))
          .toList();
    }
    _filtreli = list;
    _toplamBorc = _filtreli.fold(0.0, (s, h) => s + h.borc);
    _toplamAlacak = _filtreli.fold(0.0, (s, h) => s + h.alacak);
    _bakiye = _toplamBorc - _toplamAlacak;
  }

  Future<void> _tarihSec() async {
    try {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        initialDateRange: _tarihAralik,
      );
      if (r != null)
        setState(() {
          _tarihAralik = r;
          _filtrele();
        });
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

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
  Future<void> _silHareket(CariHareketModel h) async {
    if (h.id == null) return;
    final gercekParaOlabilir = h.fisTipi == 'Tahsilat' || h.fisTipi == 'Ödeme';
    final otomatikTersCevrilebilir =
        gercekParaOlabilir && h.odemeTuru == 'Nakit';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hareketi İptal Et'),
        content: Text(!gercekParaOlabilir
            ? '${h.aciklama} hareketi iptal edilecek. Devam edilsin mi?'
            : otomatikTersCevrilebilir
                ? '${h.aciklama} hareketi iptal edilecek. Bağlı kasa hareketi '
                    'de otomatik olarak tersine çevrilecek. Devam edilsin mi?'
                : '${h.aciklama} hareketi iptal edilecek.\n\n'
                    'Bu bir Banka/Kredi Kartı hareketiyse, bağlı kayıt OTOMATİK '
                    'OLARAK GERİ ALINMAZ — gerekiyorsa o tarafı elle düzeltin. '
                    'Devam edilsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final db = await Veritabani().db;
      String? tersCariGid;
      int? tersKasaId;
      await db.transaction((txn) async {
        final guncelRows =
            await txn.query('cari_hareket', where: 'id = ?', whereArgs: [h.id]);
        if (guncelRows.isEmpty) throw Exception('Hareket bulunamadı');
        final guncel = guncelRows.first;
        if ((guncel['is_deleted'] as int? ?? 0) == 1) {
          throw Exception('Bu hareket zaten iptal edilmiş');
        }
        final now = DateTime.now().toIso8601String();

        // 1. Orijinal kayıt KORUNUR — sadece soft-delete işaretlenir.
        await txn.update('cari_hareket', {'is_deleted': 1, 'last_updated': now},
            where: 'id = ?', whereArgs: [h.id]);

        // 2. Ters cari_hareket (borç/alacak yer değiştirir), orijinali
        // fis_id ile referans olarak taşır.
        final tersGid = const Uuid().v4();
        await txn.insert('cari_hareket', {
          'global_id': tersGid,
          'cari_id': h.cariId,
          'tarih': now,
          'fis_tipi': '${h.fisTipi} İptali',
          'fis_id': h.id,
          'fis_no': h.fisNo,
          'aciklama': 'İptal: ${h.aciklama}',
          'borc': h.alacak,
          'alacak': h.borc,
          'odeme_turu': h.odemeTuru,
          'kullanici': AuthServisi().aktifAd,
          'last_updated': now,
          'is_deleted': 0,
        });
        tersCariGid = tersGid;

        // 3. Cari bakiyeyi hareketlerden yeniden hesapla.
        await txn.rawUpdate('''
          UPDATE cari SET bakiye = (
            SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0)
            FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0
          ), last_updated = ?
          WHERE id = ?
        ''', [h.cariId, now, h.cariId]);

        // 4. Bağlı (referans_turu='cari_hareket') kasa hareketi varsa
        // ters çevir. Yoksa (eski kayıt veya Banka/Kredi Kartı) sessizce
        // atlanır — güvenli fallback.
        final kasaRows = await txn.query('kasa_hareketleri',
            where:
                'referans_turu = ? AND referans_id = ? AND deleted_at IS NULL',
            whereArgs: ['cari_hareket', h.id]);
        if (kasaRows.isNotEmpty) {
          final orijinalKasa = kasaRows.first;
          final orijinalTip = orijinalKasa['hareket_tipi'] as String? ?? '';
          final orijinalTutar =
              (orijinalKasa['tutar'] as num?)?.toDouble() ?? 0;
          // Tahsilat (giriş) → İptali çıkış olur (girisTipleri'nde yok,
          // varsayılan olarak çıkış sayılır). Ödeme (çıkış) → Girişi
          // zaten girisTipleri'nde tanımlı bir giriş tipidir.
          final tersTip = orijinalTip == 'Tahsilat'
              ? 'Tahsilat İptali'
              : orijinalTip == 'Ödeme'
                  ? 'Ödeme Girişi'
                  : null;
          if (tersTip != null && orijinalTutar > 0) {
            tersKasaId = await KasaDeposu().hareketEkleTxn(
                txn,
                KasaHareketModel(
                  hareketTipi: tersTip,
                  tutar: orijinalTutar,
                  referansId: h.id,
                  referansTuru: 'cari_hareket_iptal',
                  tarih: DateTime.parse(now),
                  aciklama: 'İptal: ${h.aciklama}',
                ));
          }
        }
      });

      // Transaction kalıcı oldu — şimdi buluta bildir (bu çağrı zaten
      // AuditLogServisi'ni de otomatik tetikliyor).
      final db2 = await Veritabani().db;
      final orijinalSatir = await db2.query('cari_hareket',
          where: 'id = ?', whereArgs: [h.id], limit: 1);
      if (orijinalSatir.isNotEmpty)
        BulutManager().upsert(
            'cari_hareket', Map<String, dynamic>.from(orijinalSatir.first));
      if (tersCariGid != null) {
        final satir = await db2.query('cari_hareket',
            where: 'global_id = ?', whereArgs: [tersCariGid], limit: 1);
        if (satir.isNotEmpty)
          BulutManager()
              .upsert('cari_hareket', Map<String, dynamic>.from(satir.first));
      }
      final cariSatir = await db2.query('cari',
          where: 'id = ?', whereArgs: [widget.cariId], limit: 1);
      if (cariSatir.isNotEmpty)
        BulutManager()
            .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
      if (tersKasaId != null) {
        final kasaSatir = await db2.query('kasa_hareketleri',
            where: 'id = ?', whereArgs: [tersKasaId], limit: 1);
        if (kasaSatir.isNotEmpty)
          BulutManager().upsert(
              'kasa_hareketleri', Map<String, dynamic>.from(kasaSatir.first));
      }

      if (!mounted) return;
      await _yukle();
      if (mounted) BildirimServisi.basari(context, 'Hareket iptal edildi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<void> _hareketEkle() async {
    String tipi = 'Tahsilat';
    final ctrl = TextEditingController();
    final acCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Hareket Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: tipi,
                decoration: const InputDecoration(
                  labelText: 'Hareket Tipi',
                  border: OutlineInputBorder(),
                ),
                items: ['Tahsilat', 'Ödeme', 'İskonto', 'İade', 'Düzeltme']
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
    final tutar = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
    if (tutar <= 0) {
      BildirimServisi.uyari(context, 'Geçerli tutar girin');
      return;
    }

    final isTahsilat = tipi == 'Tahsilat' || tipi == 'İskonto';
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

  Future<void> _exportExcel() async {
    if (_filtreli.isEmpty) {
      BildirimServisi.uyari(context, 'Veri yok');
      return;
    }
    try {
      final ex = Excel.createExcel();
      final sh = ex['Cari Hareketler'];
      ex.delete('Sheet1');
      sh.appendRow([
        TextCellValue('Tarih'),
        TextCellValue('Tip'),
        TextCellValue('Fiş No'),
        TextCellValue('Açıklama'),
        TextCellValue('Borç'),
        TextCellValue('Alacak'),
        TextCellValue('Bakiye')
      ]);
      double runBak = 0;
      for (final h in _filtreli.reversed.toList()) {
        runBak += h.borc - h.alacak;
        sh.appendRow([
          TextCellValue(_fmtT.format(h.tarih)),
          TextCellValue(h.fisTipi),
          TextCellValue(h.fisNo ?? ''),
          TextCellValue(h.aciklama),
          DoubleCellValue(h.borc),
          DoubleCellValue(h.alacak),
          DoubleCellValue(runBak),
        ]);
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/${_cari?.unvan ?? 'cari'}_hareketler_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      File(path).writeAsBytesSync(ex.encode()!);
      await Share.shareXFiles([XFile(path)],
          text: '${_cari?.unvan ?? ''} Hareketleri');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  Future<void> _exportCSV() async {
    if (_filtreli.isEmpty) {
      BildirimServisi.uyari(context, 'Veri yok');
      return;
    }
    try {
      final buf = StringBuffer()..write('\uFEFF');
      buf.writeln('Tarih,Tip,Fiş No,Açıklama,Borç,Alacak,Bakiye');
      double runBak = 0;
      for (final h in _filtreli.reversed.toList()) {
        runBak += h.borc - h.alacak;
        final row = [
          _fmtT.format(h.tarih),
          h.fisTipi,
          h.fisNo ?? '',
          h.aciklama,
          h.borc.toStringAsFixed(2),
          h.alacak.toStringAsFixed(2),
          runBak.toStringAsFixed(2)
        ];
        buf.writeln(row.map((v) => v.contains(',') ? '"$v"' : v).join(','));
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${_cari?.unvan ?? 'cari'}_hareketler.csv';
      File(path).writeAsStringSync(buf.toString());
      await Share.shareXFiles([XFile(path)], text: 'CSV');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'CSV hatası: $e');
    }
  }

  Future<void> _exportPDF() async {
    if (_filtreli.isEmpty) {
      BildirimServisi.uyari(context, 'Veri yok');
      return;
    }
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (ctx) => [
        pw.Text('${_cari?.unvan ?? ''} — Cari Hareket Raporu',
            style: pw.TextStyle(font: boldFont, fontSize: 16)),
        pw.Text('Tarih: ${_fmt.format(DateTime.now())}',
            style:
                pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(
          headers: ['Tarih', 'Tip', 'Açıklama', 'Borç', 'Alacak', 'Bakiye'],
          headerStyle:
              pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 9),
          headerDecoration: pw.BoxDecoration(color: PdfColors.grey700),
          cellStyle: pw.TextStyle(font: font, fontSize: 8),
          data: () {
            double runBak = 0;
            return _filtreli.reversed.map((h) {
              runBak += h.borc - h.alacak;
              return [
                _fmtT.format(h.tarih),
                h.fisTipi,
                h.aciklama,
                h.borc > 0 ? h.borc.toStringAsFixed(2) : '',
                h.alacak > 0 ? h.alacak.toStringAsFixed(2) : '',
                runBak.toStringAsFixed(2)
              ];
            }).toList();
          }(),
        ),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Toplam Borç: ${_toplamBorc.toStringAsFixed(2)} ₺',
                style: pw.TextStyle(
                    font: boldFont, fontSize: 10, color: PdfColors.red)),
            pw.Text('Toplam Alacak: ${_toplamAlacak.toStringAsFixed(2)} ₺',
                style: pw.TextStyle(
                    font: boldFont, fontSize: 10, color: PdfColors.green)),
            pw.Text('Bakiye: ${_bakiye.toStringAsFixed(2)} ₺',
                style: pw.TextStyle(font: boldFont, fontSize: 11)),
          ]),
        ]),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  Widget _bakiyeItem(String label, double val, Color renk) {
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      const SizedBox(height: 4),
      Text(ParaUtils.formatla(val),
          style: TextStyle(
              color: renk, fontSize: 14, fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _tipChip(String label, String? tip) {
    return GestureDetector(
      onTap: () => setState(() {
        _filtreTip = tip;
        _filtrele();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _filtreTip == tip ? TsRenk.primary : context.borderColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              color: _filtreTip == tip ? Colors.white : context.textSecondary,
              fontWeight: _filtreTip == tip ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final musteri = _cari?.cariTipi == 'Müşteri' ||
        _cari?.cariTipi == 'Hem Müşteri Hem Tedarikçi';
    final fistipler = _tumHareketler.map((h) => h.fisTipi).toSet().toList()
      ..sort();

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: Text(_cari?.unvan ?? 'Cari Hareketleri'),
        aksiyonlar: [
          IconButton(
              icon: const Icon(Icons.date_range),
              tooltip: 'Tarih Filtresi',
              onPressed: _tarihSec),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'excel') _exportExcel();
              if (v == 'csv') _exportCSV();
              if (v == 'pdf') _exportPDF();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'excel',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.download, color: AppRenkler.primary),
                      title: Text('Excel'))),
              PopupMenuItem(
                  value: 'csv',
                  child: ListTile(
                      dense: true,
                      leading:
                          Icon(Icons.table_chart, color: AppRenkler.primary),
                      title: Text('CSV'))),
              PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                      dense: true,
                      leading:
                          Icon(Icons.picture_as_pdf, color: AppRenkler.primary),
                      title: Text('PDF'))),
            ],
          ),
          IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Hareket Ekle',
              onPressed: _hareketEkle),
        ],
        gradyanli: false,
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              gradient:
                  LinearGradient(colors: [TsRenk.primary, TsRenk.primaryKoyu]),
              borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(child: _bakiyeItem('Borç', _toplamBorc, Colors.redAccent)),
            Expanded(
                child:
                    _bakiyeItem('Alacak', _toplamAlacak, Colors.greenAccent)),
            Expanded(child: _bakiyeItem('Bakiye', _bakiye, _bakiyeRenk())),
          ]),
        ),
        if (fistipler.length > 1 || _tarihAralik != null)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              _tipChip('Tümü', null),
              ...fistipler.map((t) => Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _tipChip(t, t))),
              if (_tarihAralik != null) ...[
                const SizedBox(width: 8),
                Chip(
                    label: Text(
                        '${_fmt.format(_tarihAralik!.start)} - ${_fmt.format(_tarihAralik!.end)}',
                        style: const TextStyle(fontSize: 11)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setState(() {
                          _tarihAralik = null;
                          _filtrele();
                        })),
              ],
            ]),
          ),
        Expanded(
            child: _yukleniyor
                ? const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: Color(0xFF4361EE)))
                : RefreshIndicator(
                    onRefresh: _yukle,
                    child: _filtreli.isEmpty
                        ? Center(
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                Icon(Icons.swap_vert,
                                    size: 56, color: context.textHint),
                                const SizedBox(height: 12),
                                Text('Hareket kaydı yok',
                                    style: TextStyle(
                                        color: context.textSecondary)),
                              ]))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: _filtreli.length,
                            itemBuilder: (_, i) {
                              final h = _filtreli[i];

                              final bool pozitif;
                              final double tutar;
                              final Color renk;
                              final IconData ikonVeri;
                              // 🔥 ÖNCEDEN "borc > 0" / "alacak > 0" kontrolü, TEK bir
                              // alanın dolu olduğunu varsayıyordu. Ama Nakit/Kredi
                              // Kartı ile (cariye veresiye YAZILMADAN) yapılan satış/
                              // alımlar artık borc VE alacak'ı AYNI tutarda yazıyor
                              // (bakiyeyi etkilememek için, kasıtlı olarak net sıfır).
                              // Bu kontrol olmadan, bu kayıtlar YANLIŞLIKLA "veresiye
                              // artışı" gibi yeşil/kırmızı gösterilirdi — oysa
                              // gerçekte bakiyeye HİÇ dokunmuyorlar. Artık ayrı,
                              // nötr bir görsel durumla gösteriliyorlar.
                              if ((h.borc - h.alacak).abs() < 0.01 &&
                                  h.borc > 0) {
                                // Net sıfır — bakiyeyi etkilemeyen (Nakit/Kart) kayıt
                                pozitif = true;
                                tutar = h.borc;
                                renk = context.textSecondary;
                                ikonVeri = Icons.check_circle_outline;
                              } else if (musteri) {
                                // MÜŞTERİ
                                if (h.borc > 0) {
                                  // Veresiye satış - POZİTİF göster (+)
                                  pozitif = true;
                                  tutar = h.borc;
                                  renk = Colors.green.shade700;
                                  ikonVeri = Icons.arrow_downward;
                                } else {
                                  // Tahsilat - NEGATİF göster (-)
                                  pozitif = false;
                                  tutar = h.alacak;
                                  renk = Colors.red.shade700;
                                  ikonVeri = Icons.arrow_upward;
                                }
                              } else {
                                // TEDARİKÇİ
                                if (h.alacak > 0) {
                                  // Alım / Borçlandık → kırmızı - (borcumuz arttı)
                                  pozitif = false;
                                  tutar = h.alacak;
                                  renk = Colors.red.shade700;
                                  ikonVeri = Icons.arrow_upward;
                                } else {
                                  // Ödeme yaptık / Borcumuz azaldı → yeşil +
                                  pozitif = true;
                                  tutar = h.borc;
                                  renk = Colors.green.shade700;
                                  ikonVeri = Icons.arrow_downward;
                                }
                              }

                              return Dismissible(
                                key: ValueKey('ch_${h.id}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(12)),
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  child: const Icon(Icons.delete,
                                      color: Colors.white),
                                ),
                                confirmDismiss: (_) async =>
                                    await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                        title: const Text('Hareketi Sil'),
                                        content: Text(
                                            '${h.aciklama} silinecek. Emin misiniz?'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('İptal')),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            style: FilledButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                backgroundColor: Colors.red),
                                            child: const Text('Sil'),
                                          ),
                                        ],
                                      ),
                                    ) ??
                                    false,
                                onDismissed: (_) => _silHareket(h),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: TsKart(
                                    padding: EdgeInsets.zero,
                                    onTap: () => _fisDetayinaGit(h),
                                    child: ListTile(
                                      leading: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Color.fromARGB(26, renk.red,
                                              renk.green, renk.blue),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(ikonVeri,
                                            color: renk, size: 20),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              h.aciklama,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (h.fisId != null && h.fisId! > 0)
                                            IconButton(
                                              icon: Icon(Icons.receipt_long,
                                                  size: 18,
                                                  color: Colors.blue.shade600),
                                              onPressed: () =>
                                                  _fisDetayinaGit(h),
                                              tooltip: 'Fiş Detayı',
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                        ],
                                      ),
                                      subtitle: Row(
                                        children: [
                                          Text(_fmtT.format(h.tarih),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      context.textSecondary)),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(6)),
                                            child: Text(h.fisTipi,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color:
                                                        Colors.blue.shade700)),
                                          ),
                                        ],
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${pozitif ? "+" : "-"}${ParaUtils.formatla(tutar)}',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                                color: renk),
                                          ),
                                          if (h.fisNo != null &&
                                              h.fisNo!.isNotEmpty)
                                            Text(h.fisNo!,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color:
                                                        context.textSecondary)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  )),
      ]),
    );
  }
}
