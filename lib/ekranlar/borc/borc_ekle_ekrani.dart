// lib/ekranlar/borc/borc_ekle_ekrani.dart
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../depolar/borc_deposu.dart';
import '../../modeller/borc_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../saglayicilar/riverpod/borc_provider.dart';

class BorcEkleEkrani extends ConsumerStatefulWidget {
  final BorcModel? duzenlenecekBorc;
  const BorcEkleEkrani({super.key, this.duzenlenecekBorc});

  @override
  ConsumerState<BorcEkleEkrani> createState() => _BorcEkleEkraniState();
}

class _BorcEkleEkraniState extends ConsumerState<BorcEkleEkrani> {
  final _formKey = GlobalKey<FormState>();
  final _depo = BorcDeposu();

  final _baslikCtrl = TextEditingController();
  final _tutarCtrl = TextEditingController();
  final _aciklamaCtrl = TextEditingController();
  final _dosyaNoCtrl = TextEditingController();
  final _referansNoCtrl = TextEditingController();
  final _notlarCtrl = TextEditingController();

  String _tur = 'kredi_karti';
  String? _altTur;
  DateTime _kesimTarihi = DateTime.now();
  DateTime _sonOdemeTarihi = DateTime.now().add(const Duration(days: 30));
  int _taksitSayisi = 1;
  int _oncelik = 2;
  bool _yukleniyor = false;
  bool _duzenleme = false;

  @override
void initState() {
  super.initState();
  if (widget.duzenlenecekBorc != null) {
    _duzenleme = true;
    _doldur(widget.duzenlenecekBorc!);
  } else {
    // 🔥 YENİ: Dashboard'dan gelen extra'yı kontrol et
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map<String, dynamic>) {
        final tutar = extra['tutar'] as double?;
        final aciklama = extra['aciklama'] as String?;
        if (tutar != null && tutar > 0) {
          _tutarCtrl.text = tutar.toStringAsFixed(2);
        }
        if (aciklama != null && aciklama.isNotEmpty) {
          _aciklamaCtrl.text = aciklama;
          _altTur = aciklama; // Kurum adı olarak kullan
        }
      }
    });
  }
}

  void _doldur(BorcModel b) {
    _baslikCtrl.text = b.baslik;
    _tutarCtrl.text = b.tutar.toStringAsFixed(2);
    _aciklamaCtrl.text = b.aciklama ?? '';
    _dosyaNoCtrl.text = b.dosyaNo ?? '';
    _referansNoCtrl.text = b.referansNo ?? '';
    _notlarCtrl.text = b.notlar ?? '';
    _tur = b.tur;
    _altTur = b.altTur;
    _kesimTarihi = b.kesimTarihi;
    _sonOdemeTarihi = b.sonOdemeTarihi;
    _taksitSayisi = b.taksitSayisi;
    _oncelik = b.oncelik;
  }

  @override
  void dispose() {
    _baslikCtrl.dispose();
    _tutarCtrl.dispose();
    _aciklamaCtrl.dispose();
    _dosyaNoCtrl.dispose();
    _referansNoCtrl.dispose();
    _notlarCtrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _yukleniyor = true);
    try {
      final borc = BorcModel(
        id: widget.duzenlenecekBorc?.id,
        baslik: _baslikCtrl.text.trim(),
        tur: _tur,
        altTur: _altTur,
        tutar: double.tryParse(_tutarCtrl.text.replaceAll(',', '.')) ?? 0,
        odenenTutar: widget.duzenlenecekBorc?.odenenTutar ?? 0,
        kesimTarihi: _kesimTarihi,
        sonOdemeTarihi: _sonOdemeTarihi,
        odemeTarihi: widget.duzenlenecekBorc?.odemeTarihi,
        taksitSayisi: _taksitSayisi,
        odenenTaksit: widget.duzenlenecekBorc?.odenenTaksit ?? 0,
        aciklama: _aciklamaCtrl.text.trim().isEmpty ? null : _aciklamaCtrl.text.trim(),
        dosyaNo: _dosyaNoCtrl.text.trim().isEmpty ? null : _dosyaNoCtrl.text.trim(),
        referansNo: _referansNoCtrl.text.trim().isEmpty ? null : _referansNoCtrl.text.trim(),
        odendi: widget.duzenlenecekBorc?.odendi ?? false,
        hatirlatmaGonderildi: widget.duzenlenecekBorc?.hatirlatmaGonderildi ?? false,
        oncelik: _oncelik,
        notlar: _notlarCtrl.text.trim().isEmpty ? null : _notlarCtrl.text.trim(),
      );

      if (_duzenleme) {
        await _depo.guncelle(borc);
        if (mounted) BildirimServisi.basari(context, 'Borç güncellendi');
      } else {
        await _depo.ekle(borc);
        if (mounted) BildirimServisi.basari(context, 'Borç eklendi');
      }
      // Kaydettikten sonra Borç Dashboard bayat kalıyordu — artık yenileniyor.
      ref.invalidate(borcDashboardProvider);
      ref.invalidate(borcOzetProvider);
      ref.invalidate(tumBorclarProvider);
      ref.invalidate(yaklasanBorclarProvider);
      ref.invalidate(gecmisBorclarProvider);
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _tarihSec({required bool kesim}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: kesim ? _kesimTarihi : _sonOdemeTarihi,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (d != null) {
      setState(() {
        if (kesim) _kesimTarihi = d;
        else _sonOdemeTarihi = d;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Text(_duzenleme ? 'Borç Düzenle' : 'Yeni Borç Ekle'),
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.white),
            onPressed: _yukleniyor ? null : _kaydet,
          ),
        ],
      ),
      body: TsResponsive.formSarmalayici(context: context, maxGenislik: 720, child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              value: _tur,
              decoration: const InputDecoration(
                labelText: 'Borç Türü *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'kredi_karti', child: Text('Kredi Kartı')),
                DropdownMenuItem(value: 'vergi', child: Text('Vergi / Maliye')),
                DropdownMenuItem(value: 'sgk', child: Text('SGK')),
                DropdownMenuItem(value: 'kira', child: Text('Kira')),
                DropdownMenuItem(value: 'fatura', child: Text('Fatura')),
                DropdownMenuItem(value: 'diger', child: Text('Diğer')),
              ],
              onChanged: (v) => setState(() => _tur = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _baslikCtrl,
              decoration: const InputDecoration(
                labelText: 'Borç Başlığı *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
                isDense: true,
                hintText: 'Örn: Vergi Dairesi, Kredi Kartı...',
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Zorunlu' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _aciklamaCtrl,
              decoration: const InputDecoration(
                labelText: 'Kurum / Banka Adı',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
                isDense: true,
                hintText: 'Örn: Türkiye Finans, Maliye Bakanlığı...',
              ),
              onChanged: (v) => _altTur = v.trim().isEmpty ? null : v.trim(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tutarCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tutar (TL) *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
                isDense: true,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Zorunlu';
                final val = double.tryParse(v.replaceAll(',', '.'));
                if (val == null || val <= 0) return 'Geçerli tutar girin';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () => _tarihSec(kesim: true),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Kesim Tarihi',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today, size: 16),
                      isDense: true,
                    ),
                    child: Text(DateFormat('dd.MM.yyyy').format(_kesimTarihi)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _tarihSec(kesim: false),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Son Ödeme *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.event, size: 16),
                      isDense: true,
                    ),
                    child: Text(DateFormat('dd.MM.yyyy').format(_sonOdemeTarihi)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _taksitSayisi,
                  decoration: const InputDecoration(
                    labelText: 'Taksit Sayısı',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timeline),
                    isDense: true,
                  ),
                  items: [1, 2, 3, 4, 6, 9, 12].map((t) => DropdownMenuItem(
                    value: t,
                    child: Text('$t Taksit'),
                  )).toList(),
                  onChanged: (v) => setState(() => _taksitSayisi = v!),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _oncelik,
                  decoration: const InputDecoration(
                    labelText: 'Öncelik',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Row(children: [
                      Icon(Icons.circle, color: Colors.red, size: 12),
                      SizedBox(width: 4),
                      Text('Kritik'),
                    ])),
                    DropdownMenuItem(value: 2, child: Row(children: [
                      Icon(Icons.circle, color: Colors.orange, size: 12),
                      SizedBox(width: 4),
                      Text('Orta'),
                    ])),
                    DropdownMenuItem(value: 3, child: Row(children: [
                      Icon(Icons.circle, color: Colors.green, size: 12),
                      SizedBox(width: 4),
                      Text('Düşük'),
                    ])),
                  ],
                  onChanged: (v) => setState(() => _oncelik = v!),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _dosyaNoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dosya No',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.folder_outlined),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _referansNoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referans No',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                    isDense: true,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notlarCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notlar',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note_add),
                isDense: true,
                hintText: 'Özel notlar, hatırlatmalar...',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _yukleniyor ? null : _kaydet,
                child: _yukleniyor
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _duzenleme ? 'Güncelle' : 'Borç Ekle',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      )),
    );
  }
}