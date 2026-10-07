// lib/ekranlar/promosyon/promosyon_form_sheet.dart
//
// Promosyon ekleme/düzenleme formu — promosyon_ekrani.dart'tan ayrıldı
// (2026-10-07 refactor).
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../modeller/promosyon_model.dart';
import '../../modeller/urun_model.dart';
import '../../depolar/promosyon_deposu.dart';
import '../../depolar/urun_deposu.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/barkod_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'widgets/promosyon_kart_widgetlari.dart';

class PromosyonFormSheet extends ConsumerStatefulWidget {
  /// Doluysa form DÜZENLEME modunda açılır (alanlar mevcut değerle dolu).
  final PromosyonModel? duzenlenecek;
  const PromosyonFormSheet({this.duzenlenecek});
  @override
  ConsumerState<PromosyonFormSheet> createState() => PromosyonFormSheetState();
}
class PromosyonFormSheetState extends ConsumerState<PromosyonFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _adCtrl  = TextEditingController();
  final _oranCtrl = TextEditingController(text: '10');
  final _minMiktarCtrl  = TextEditingController(text: '1');
  final _araCtrl        = TextEditingController();
  final _indirimliCtrl  = TextEditingController();
  final _toplamCtrl     = TextEditingController(); // toplam tutar girişi
  Timer? _araDebounce;

  /// "Toplam fiyat"tan hesaplanan TAM HASSASİYETLİ oran (ör. 16,6666…).
  /// Kutuda 3 ondalık gösterilir; kayıtta bu ham değer kullanılır ki
  /// 2 × 60 = 120 → 100 yazınca fiyat tam 100,00 çıksın (99,96 değil).
  double? _oranHam;

  /// Kayıt/önizleme için geçerli oran: kutu hâlâ hesaplanan değeri
  /// gösteriyorsa ham değer, kullanıcı elle değiştirdiyse yazdığı değer.
  double get _oranDeger {
    final yazilan = ParaUtils.sayiCoz(_oranCtrl.text) ?? 0;
    final ham = _oranHam;
    if (ham != null && (yazilan - ham).abs() < 0.0015) return ham;
    return yazilan;
  }

  /// Önizlemedeki "Toplam": kullanıcı elle toplam girdiyse o, girmediyse
  /// indirimli birim × min. miktar (önceden boşken "—" görünüyordu).
  String get _toplamOnizleme {
    if (_toplamCtrl.text.isNotEmpty) {
      return ParaUtils.formatla(ParaUtils.sayiCoz(_toplamCtrl.text) ?? 0);
    }
    final urun = _seciliUrun;
    if (urun == null || _oranCtrl.text.isEmpty) return '—';
    final adet = ParaUtils.sayiCoz(_minMiktarCtrl.text) ?? 1;
    return ParaUtils.formatla(urun.satisFiyati * (1 - _oranDeger / 100) * (adet <= 0 ? 1 : adet));
  }

  UrunModel? _seciliUrun;
  List<UrunModel> _aramaSonuclari = [];
  DateTime? _baslangic, _bitis;
  bool _kayit = false;
  bool _aktif = true;

  bool get _duzenleme => widget.duzenlenecek != null;

  @override
  void initState() {
    super.initState();
    final p = widget.duzenlenecek;
    if (p == null) return;
    _adCtrl.text = p.promosyonAdi;
    _oranHam = p.iskontoOran; // kayıtlı tam hassasiyetli oran korunur
    _oranCtrl.text = promosyonOranMetni(p.iskontoOran);
    _minMiktarCtrl.text = p.minMiktar == p.minMiktar.truncateToDouble()
        ? p.minMiktar.toStringAsFixed(0)
        : p.minMiktar.toString().replaceAll('.', ',');
    _baslangic = p.baslangicTarihi;
    _bitis = p.bitisTarihi;
    _aktif = p.aktif;
    // Ürün bilgisini yükle → önizleme ve toplam fiyat hesaplanır.
    UrunDeposu().idileGetir(p.urunId).then((u) {
      if (u == null || !mounted) return;
      setState(() {
        _seciliUrun = u;
        _araCtrl.text = u.urunAdi;
        final adet = p.minMiktar <= 0 ? 1 : p.minMiktar;
        _toplamCtrl.text = (u.satisFiyati * (1 - p.iskontoOran / 100) * adet).toStringAsFixed(2);
      });
    });
  }

  /// Tarih yenileme kısayolları (yeni kayıt gibi): bugünden başlat, süreyi
  /// uzat, süresiz yap.
  void _tarihleriYenile() {
    final bugun = DateTime.now();
    final gun = DateTime(bugun.year, bugun.month, bugun.day);
    // Önceki süre kadar (yoksa 30 gün) bugünden itibaren
    var sure = 30;
    if (_baslangic != null && _bitis != null && !_bitis!.isBefore(_baslangic!)) {
      sure = _bitis!.difference(_baslangic!).inDays;
      if (sure < 1) sure = 1;
    }
    setState(() {
      _baslangic = gun;
      _bitis = gun.add(Duration(days: sure));
    });
  }

  void _sureyiUzat(int gun) {
    final bugun = DateTime.now();
    final bas = DateTime(bugun.year, bugun.month, bugun.day);
    // Süresi dolmuşsa bugünden, değilse mevcut bitişten uzat.
    final temel = (_bitis == null || _bitis!.isBefore(bas)) ? bas : _bitis!;
    setState(() => _bitis = temel.add(Duration(days: gun)));
  }

  @override
  void dispose() {
    _adCtrl.dispose(); _oranCtrl.dispose(); _minMiktarCtrl.dispose();
    _araCtrl.dispose(); _araDebounce?.cancel(); _indirimliCtrl.dispose(); _toplamCtrl.dispose();
    super.dispose();
  }

  void _aramaChanged(String q) {
    _araDebounce?.cancel();
    if (q.trim().length < 2) { setState(() => _aramaSonuclari = []); return; }
    _araDebounce = Timer(const Duration(milliseconds: 300), () async {
      final sonuclar = await UrunDeposu().ara(q.trim(), limit: 10);
      if (mounted) setState(() => _aramaSonuclari = sonuclar);
    });
  }

  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) return;
    if (_seciliUrun == null) {
      BildirimServisi.uyari(context, 'Ürün seçin');
      return;
    }
    // 🔴 Derin analizde bulundu: bitiş tarihi seçici sadece başlangıç
    // ÖNCE seçilmişse ('firstDate: _baslangic') geçersiz aralığı
    // engelliyordu — kullanıcı önce bitişi, sonra bitişten SONRAKİ bir
    // başlangıcı seçerse hiçbir kontrol yoktu; ters bir tarih aralığı
    // kaydedilip aktif/süresi-dolmuş filtrelemesini bozabiliyordu.
    if (_baslangic != null && _bitis != null && _baslangic!.isAfter(_bitis!)) {
      BildirimServisi.uyari(context, 'Başlangıç tarihi bitiş tarihinden sonra olamaz');
      return;
    }
    setState(() => _kayit = true);
    try {
      final yeni = PromosyonModel(
        id:              widget.duzenlenecek?.id,
        urunId:          _seciliUrun!.id!,
        urunAdi:         _seciliUrun!.urunAdi,
        promosyonAdi:    _adCtrl.text.trim(),
        iskontoOran:     _oranDeger,
        minMiktar:       ParaUtils.sayiCoz(_minMiktarCtrl.text) ?? 1,
        baslangicTarihi: _baslangic,
        bitisTarihi:     _bitis,
        aktif:           _duzenleme ? _aktif : true,
      );
      if (_duzenleme) {
        await PromosyonDeposu().guncelle(yeni);
      } else {
        await PromosyonDeposu().ekle(yeni);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(_duzenleme ? 'Promosyonu Düzenle' : 'Yeni Promosyon',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),

          // Ürün arama
          TextFormField(
            controller: _araCtrl,
            decoration: InputDecoration(
              labelText: 'Ürün Ara *',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_seciliUrun != null)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                  tooltip: 'Barkod Tara',
                  onPressed: () async {
                    final b = await BarkodServisi().barkodTara(context);
                    if (b != null && mounted) {
                      _araCtrl.text = b;
                      _aramaChanged(b);
                    }
                  }),
              ]),
            ),
            onChanged: _aramaChanged,
          ),

          if (_seciliUrun != null) ...[
            Container(
              margin: const EdgeInsets.only(top: 6, bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [TsRenk.zemin(TsRenk.bilgi), TsRenk.zemin(TsRenk.basarili)]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: TsRenk.zemin(TsRenk.bilgi, opaklik: 0.4))),
              child: Column(children: [
                // FittedBox: dar ekranda (420 px) önizleme satırı taşmasın.
                FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
                  PromosyonHesapKutu('Normal Birim', ParaUtils.formatla(_seciliUrun!.satisFiyati), Colors.blue),
                  Icon(Icons.arrow_forward, size: 14, color: context.textSecondary),
                  PromosyonHesapKutu('İndirimli Birim',
                    _oranCtrl.text.isNotEmpty
                      ? ParaUtils.formatla(_seciliUrun!.satisFiyati * (1 - _oranDeger / 100))
                      : '—',
                    Colors.orange),
                  Icon(Icons.close, size: 14, color: context.textSecondary),
                  PromosyonHesapKutu('Min Miktar', _minMiktarCtrl.text.isEmpty ? '1' : _minMiktarCtrl.text, Colors.purple),
                  Icon(Icons.drag_handle, size: 14, color: context.textSecondary),
                  PromosyonHesapKutu('Toplam', _toplamOnizleme, Colors.green),
                ])),
                if (_oranCtrl.text.isNotEmpty && ParaUtils.sayiCoz(_oranCtrl.text) != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_minMiktarCtrl.text.isEmpty ? "1" : _minMiktarCtrl.text} adet alımda '
                    '%${_oranCtrl.text} indirim → '
                    '$_toplamOnizleme ödenecek',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade700,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ]),
            ),
          ],
          if (_seciliUrun != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: TsRenk.zemin(TsRenk.basarili),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200)),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_seciliUrun!.urunAdi,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                TextButton(onPressed: () => setState(() { _seciliUrun = null; _araCtrl.clear(); }),
                    child: const Text('Değiştir')),
              ]),
            ),

          if (_aramaSonuclari.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                  border: Border.all(color: context.borderColor),
                  borderRadius: BorderRadius.circular(12)),
              // Şeffaf Material: sonuçlara dokunma dalgası görünsün.
              child: Material(
                type: MaterialType.transparency,
                child: ListView.builder(
                shrinkWrap: true,
                itemCount: _aramaSonuclari.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(_aramaSonuclari[i].urunAdi),
                  subtitle: Text(ParaUtils.formatla(_aramaSonuclari[i].satisFiyati)),
                  onTap: () => setState(() {
                    _seciliUrun = _aramaSonuclari[i];
                    _aramaSonuclari = [];
                    _araCtrl.text = _aramaSonuclari.isEmpty ? '' : _araCtrl.text;
                    if (_adCtrl.text.isEmpty) {
                      _adCtrl.text = '${_seciliUrun!.urunAdi} İndirimi';
                    }
                  }),
                ),
              ),
              ),
            ),
          const SizedBox(height: 12),

          // Promosyon adı
          TextFormField(
            controller: _adCtrl,
            decoration: const InputDecoration(
                labelText: 'Promosyon Adı *', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
          ),
          const SizedBox(height: 12),

          // İskonto % ↔ Toplam Tutar (iki yönlü)
          Row(children: [
            Expanded(child: TextFormField(
              controller: _oranCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(
                labelText: 'İskonto %', border: OutlineInputBorder(), suffixText: '%'),
              onChanged: (v) {
                _oranHam = null; // elle yazıldı
                if (_seciliUrun == null) return;
                final oran = ParaUtils.sayiCoz(v) ?? 0;
                if (oran > 0 && oran <= 100) {
                  final minMik = ParaUtils.sayiCoz(_minMiktarCtrl.text) ?? 1;
                  final indirimliB = _seciliUrun!.satisFiyati * (1 - oran / 100);
                  _toplamCtrl.text = (minMik * indirimliB).toStringAsFixed(2);
                  setState(() {});
                }
              },
              validator: (v) {
                final d = ParaUtils.sayiCoz(v);
                if (d == null || d <= 0 || d > 100) return '0-100 arası';
                return null;
              },
            )),
            const SizedBox(width: 8),
            // Ok ikonu
            Icon(Icons.sync_alt, color: context.textSecondary, size: 18),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(
              controller: _toplamCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Toplam Fiyat ₺',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: TsRenk.zemin(TsRenk.basarili),
                prefixText: '₺ ',
              ),
              onChanged: (v) {
                if (_seciliUrun == null) return;
                final toplam = ParaUtils.sayiCoz(v) ?? 0;
                final minMik = ParaUtils.sayiCoz(_minMiktarCtrl.text) ?? 1;
                final maxToplam = _seciliUrun!.satisFiyati * minMik;
                if (toplam > 0 && toplam < maxToplam) {
                  final birimIndirimli = toplam / minMik;
                  final oran = (1 - birimIndirimli / _seciliUrun!.satisFiyati) * 100;
                  if (oran >= 0 && oran <= 100) {
                    _oranHam = oran;
                    _oranCtrl.text = promosyonOranMetni(oran);
                    setState(() {});
                  }
                }
              },
            )),
          ]),
          const SizedBox(height: 10),
          TextFormField(
            controller: _minMiktarCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(
                labelText: 'Min Miktar (Eşik)', 
                border: OutlineInputBorder(),
                helperText: 'Bu miktar ve üzeri alımda indirim uygulanır',
                prefixIcon: Icon(Icons.production_quantity_limits, size: 18)),
            onChanged: (v) {
              if (_seciliUrun == null) return;
              final minMik = ParaUtils.sayiCoz(v) ?? 1;
              final oran = _oranDeger;
              if (oran > 0 && minMik > 0) {
                final indirimliB = _seciliUrun!.satisFiyati * (1 - oran / 100);
                _toplamCtrl.text = (minMik * indirimliB).toStringAsFixed(2);
                setState(() {});
              }
            },
          ),
          const SizedBox(height: 12),

          // Tarih aralığı
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(_baslangic != null ? fmt.format(_baslangic!) : 'Başlangıç',
                  style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final dt = await showDatePicker(context: context,
                    initialDate: _baslangic ?? DateTime.now(),
                    firstDate: DateTime(2020), lastDate: DateTime(2035));
                if (dt != null) setState(() => _baslangic = dt);
              },
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.event_available, size: 16),
              label: Text(_bitis != null ? fmt.format(_bitis!) : 'Bitiş',
                  style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final dt = await showDatePicker(context: context,
                    initialDate: _bitis ?? _baslangic ?? DateTime.now(),
                    firstDate: DateTime(2020), lastDate: DateTime(2035));
                if (dt != null) setState(() => _bitis = dt);
              },
            )),
          ]),
          const SizedBox(height: 8),
          // Tarih yenileme kısayolları
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              ActionChip(
                avatar: const Icon(Icons.refresh, size: 16),
                label: const Text('Bugünden yenile', style: TextStyle(fontSize: 11)),
                onPressed: _tarihleriYenile,
                visualDensity: VisualDensity.compact,
              ),
              ActionChip(
                label: const Text('+7 gün', style: TextStyle(fontSize: 11)),
                onPressed: () => _sureyiUzat(7),
                visualDensity: VisualDensity.compact,
              ),
              ActionChip(
                label: const Text('+30 gün', style: TextStyle(fontSize: 11)),
                onPressed: () => _sureyiUzat(30),
                visualDensity: VisualDensity.compact,
              ),
              ActionChip(
                avatar: const Icon(Icons.all_inclusive, size: 16),
                label: const Text('Süresiz', style: TextStyle(fontSize: 11)),
                onPressed: () => setState(() { _baslangic = null; _bitis = null; }),
                visualDensity: VisualDensity.compact,
              ),
            ]),
          ),
          if (_duzenleme)
            // Şeffaf Material: renkli kutu içinde dokunma efekti görünsün.
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                title: const Text('Aktif', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                value: _aktif,
                onChanged: (v) => setState(() => _aktif = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.green,
              ),
            ),
          const SizedBox(height: 20),

          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            )),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(
              onPressed: _kayit ? null : _kaydet,
              style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: AppRenkler.primary),
              child: _kayit
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_duzenleme ? 'Güncelle' : 'Kaydet'),
            )),
          ]),
        ])),
      ),
    );
  }
}

// ── Promosyon Kartı ──────────────────────────────────────────────────────────

