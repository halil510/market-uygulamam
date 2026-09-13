// lib/ekranlar/stok/stok_hareket_ekrani.dart
// Stok giriş/çıkış kayıtları - filtreli, excel export

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../depolar/stok_deposu.dart';
import '../../modeller/stok_hareket_model.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';

class StokHareketEkrani extends ConsumerStatefulWidget {
  const StokHareketEkrani({super.key});
  @override
  ConsumerState<StokHareketEkrani> createState() => _StokHareketEkraniState();
}

class _StokHareketEkraniState extends ConsumerState<StokHareketEkrani> {
  final _depo = StokDeposu();

  List<StokHareketModel> _hareketler = [];
  List<StokHareketModel> _filtreli   = [];
  bool _yukleniyor = true;
  String? _filtreTur; // 'Giriş', 'Çıkış', 'Sayım', null=tümü
  DateTime? _filtreBas, _filtreBit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    _yukleniyor = true;

    if (mounted) setState(() {});
    try {
      final list = await _depo.tumHareketler(limit: 500);
      if (!mounted) return;
      setState(() { _hareketler = list; _filtrele(); _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _filtrele() {
    var list = List<StokHareketModel>.from(_hareketler);
    if (_filtreTur != null) list = list.where((h) => h.hareketTuru == _filtreTur).toList();
    if (_filtreBas != null && _filtreBit != null) {
      list = list.where((h) =>
          h.tarih.isAfter(_filtreBas!.subtract(const Duration(days: 1))) &&
          h.tarih.isBefore(_filtreBit!.add(const Duration(days: 1)))).toList();
    }
    _filtreli = list;
  }

  Future<void> _tarihSec(bool baslangicMi) async {
    final d = await showDatePicker(context: context,
      initialDate: (baslangicMi ? _filtreBas : _filtreBit) ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d == null) return;
    if (!mounted) return;
    setState(() {
      if (baslangicMi) _filtreBas = DateTime(d.year, d.month, d.day);
      else _filtreBit = DateTime(d.year, d.month, d.day, 23, 59, 59);
      _filtrele();
    });
  }

  Future<void> _excelExport() async {
    if (_filtreli.isEmpty) return;
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Stok Hareketleri'];
      excel.delete('Sheet1');
      sheet.appendRow([
        TextCellValue('Tarih'), TextCellValue('Ürün'),
        TextCellValue('Hareket'), TextCellValue('Miktar'),
        TextCellValue('Önceki Stok'), TextCellValue('Yeni Stok'),
      ]);
      final fmt = DateFormat('dd.MM.yyyy HH:mm');
      for (final h in _filtreli) {
        sheet.appendRow([
          TextCellValue(fmt.format(h.tarih)),
          TextCellValue(h.urunAdi ?? ''),
          TextCellValue(h.hareketTuru),
          DoubleCellValue(h.miktar),
          DoubleCellValue(h.oncekiStok),
          DoubleCellValue(h.sonrakiStok),
        ]);
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/stok_hareketleri_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      File(path).writeAsBytesSync(excel.encode()!);
      await Share.shareXFiles([XFile(path)], text: 'Stok Hareketleri');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Stok Hareketleri',
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.download, color: Colors.white), tooltip: 'Excel', onPressed: _excelExport),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _yukle),
        ],
        geriTusu: false,
      ),
      body: Column(children: [
        // Filtreler
        Container(color: context.borderColor,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(children: [
            // Tür filtresi
            SingleChildScrollView(scrollDirection: Axis.horizontal,
              child: Row(children: [
                _turChip('Tümü', null),
                const SizedBox(width: 8),
                _turChip('Giriş', 'Giriş', color: Colors.green),
                const SizedBox(width: 8),
                _turChip('Çıkış', 'Çıkış', color: Colors.red),
                const SizedBox(width: 8),
                _turChip('Sayım', 'Sayım', color: Colors.blue),
                const SizedBox(width: 16),
                Text('${_filtreli.length} kayıt',
                    style: TextStyle(fontSize: 12, color: context.textSecondary)),
              ]),
            ),
            const SizedBox(height: 8),
            // Tarih filtresi
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(_filtreBas != null
                    ? DateFormat('dd.MM.yyyy').format(_filtreBas!)
                    : 'Başlangıç', style: const TextStyle(fontSize: 12)),
                onPressed: () => _tarihSec(true),
              )),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(_filtreBit != null
                    ? DateFormat('dd.MM.yyyy').format(_filtreBit!)
                    : 'Bitiş', style: const TextStyle(fontSize: 12)),
                onPressed: () => _tarihSec(false),
              )),
              if (_filtreBas != null || _filtreBit != null)
                IconButton(icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() { _filtreBas = null; _filtreBit = null; _filtrele(); })),
            ]),
          ]),
        ),
        Expanded(child: _yukleniyor
          ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: TsRenk.primary))
          : RefreshIndicator(
              onRefresh: _yukle,
              child: _filtreli.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.swap_vert, size: 56, color: context.textHint),
                      const SizedBox(height: 12),
                      Text('Hareket kaydı bulunamadı',
                          style: TextStyle(color: context.textSecondary)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _filtreli.length,
                      itemBuilder: (_, i) {
                        final h = _filtreli[i];
                        final giris = h.hareketTuru == 'Giriş';
                        final sayim = h.hareketTuru == 'Sayım';
                        final renk = sayim ? Colors.blue : giris ? Colors.green : Colors.red;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: TsKart.liste(
                            ikon: Icon(sayim ? Icons.calculate : giris ? Icons.arrow_downward : Icons.arrow_upward, color: renk),
                            baslik: h.urunAdi,
                            altBaslik: [
                              DateFormat('dd.MM.yyyy HH:mm').format(h.tarih),
                              if (h.aciklama != null && h.aciklama!.isNotEmpty) h.aciklama!,
                            ].join(' · '),
                            sagAksiyon: Column(mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: Color.fromARGB(31, renk.red, renk.green, renk.blue), borderRadius: BorderRadius.circular(12)),
                                child: Text('${giris ? '+' : h.miktar > 0 ? '-' : ''}${h.miktar.toStringAsFixed(0)}',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: renk))),
                              const SizedBox(height: 2),
                              Text('${h.oncekiStok.toStringAsFixed(0)} → ${h.sonrakiStok.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 10, color: context.textSecondary)),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
        ),
      ]),
    );
  }

  Widget _turChip(String label, String? tur, {Color? color}) => GestureDetector(
    onTap: () => setState(() { _filtreTur = tur; _filtrele(); }),
    child: AnimatedContainer(duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _filtreTur == tur ? Color.fromARGB(38, (color ?? context.textSecondary).red, (color ?? context.textSecondary).green, (color ?? context.textSecondary).blue) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _filtreTur == tur ? (color ?? context.textSecondary) : context.borderColor,
            width: _filtreTur == tur ? 1.5 : 1)),
      child: Text(label, style: TextStyle(fontSize: 12,
          color: _filtreTur == tur ? (color ?? context.textSecondary) : context.textSecondary,
          fontWeight: _filtreTur == tur ? FontWeight.w700 : FontWeight.w500)),
    ),
  );
}
