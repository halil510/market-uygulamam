// lib/ekranlar/lot/lot_seri_ekrani.dart
// Lot ve seri numarası takibi — ürün bazlı lot listesi, stok detayı
import 'package:flutter/material.dart';
import '../../cekirdek/utils/para_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/lot_deposu.dart';
import '../../servisler/onay_merkezi_servisi.dart';

class LotSeriEkrani extends ConsumerStatefulWidget {
  final int? urunId;
  const LotSeriEkrani({super.key, this.urunId});
  @override
  ConsumerState<LotSeriEkrani> createState() => _LotSeriEkraniState();
}

class _LotSeriEkraniState extends ConsumerState<LotSeriEkrani> {
  final _fmt = DateFormat('dd.MM.yyyy');
  List<Map<String, dynamic>> _lotlar = [];
  List<Map<String, dynamic>> _filtrelenmis = [];
  bool _yukleniyor = true;
  String _durum = 'Tümü';

  static const _durumlar = [
    'Tümü',
    'Aktif',
    'Tükendi',
    'SKT Yakın',
    'SKT Geçti'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    _yukleniyor = true;
    if (mounted) setState(() {});
    try {
      final rows = await LotDeposu().tumunuGetir(urunId: widget.urunId);
      if (!mounted) return;
      setState(() {
        _lotlar = rows;
        _filtrele('');
        _yukleniyor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _filtrele(String aramaMetni) {
    final now = DateTime.now();
    final uyari = now.add(const Duration(days: 30));
    setState(() {
      _filtrelenmis = _lotlar.where((r) {
        final q = aramaMetni.toLowerCase();
        if (q.isNotEmpty) {
          final urunAdi = r['urun_adi']?.toString().toLowerCase() ?? '';
          final lotNo = r['lot_no']?.toString().toLowerCase() ?? '';
          if (!urunAdi.contains(q) && !lotNo.contains(q)) return false;
        }
        if (_durum == 'Tümü') return true;
        final miktar = (r['miktar'] as num?)?.toDouble() ?? 0;
        final sktStr = r['son_kullanma_tarihi']?.toString();
        final skt = sktStr != null ? DateTime.tryParse(sktStr) : null;
        switch (_durum) {
          case 'Aktif':
            return miktar > 0 && (skt == null || skt.isAfter(now));
          case 'Tükendi':
            return miktar <= 0;
          case 'SKT Yakın':
            return skt != null && skt.isAfter(now) && skt.isBefore(uyari);
          case 'SKT Geçti':
            return skt != null && skt.isBefore(now);
          default:
            return true;
        }
      }).toList();
    });
  }

  Color _sktRenk(String? sktStr) {
    if (sktStr == null) return TsRenk.notr;
    final skt = DateTime.tryParse(sktStr);
    if (skt == null) return TsRenk.notr;
    final now = DateTime.now();
    if (skt.isBefore(now)) return TsRenk.hata;
    if (skt.isBefore(now.add(const Duration(days: 30)))) return TsRenk.uyari;
    return TsRenk.basarili;
  }

  Future<void> _lotDialog({Map<String, dynamic>? lot}) async {
    final lotCtrl =
        TextEditingController(text: lot?['lot_no']?.toString() ?? '');
    final sktCtrl = TextEditingController(
        text: lot?['son_kullanma_tarihi']?.toString().split('T').first ?? '');
    final miktCtrl =
        TextEditingController(text: lot?['miktar']?.toString() ?? '');
    final notCtrl =
        TextEditingController(text: lot?['aciklama']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: Text(lot == null ? 'Yeni Lot/Seri' : 'Lot Düzenle'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TsInput(
              etiket: 'Lot/Seri No *',
              controller: lotCtrl,
              oncilIkon: Icons.tag),
          const SizedBox(height: TsBosluk.md),
          TsInput(
              etiket: 'Son Kullanma Tarihi (YYYY-AA-GG)',
              controller: sktCtrl,
              oncilIkon: Icons.calendar_today),
          const SizedBox(height: TsBosluk.md),
          TsInput(
              etiket: 'Mevcut Miktar',
              controller: miktCtrl,
              oncilIkon: Icons.inventory,
              klavyeTuru: TextInputType.number),
          const SizedBox(height: TsBosluk.md),
          TsInput(
              etiket: 'Not',
              controller: notCtrl,
              oncilIkon: Icons.note,
              maksSatir: 2),
        ])),
        actions: [
          TsButon(
              tur: TsButonTuru.metin,
              metin: 'İptal',
              onPressed: () => Navigator.pop(ctx, false)),
          TsButon(
              metin: 'Kaydet',
              onPressed: () {
                if (lotCtrl.text.trim().isNotEmpty) Navigator.pop(ctx, true);
              }),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // 🔴 Derin analizde bulundu: miktar alanı ayrıştırma (parse)
    // başarısız olursa sessizce 0'a düşüyordu — kullanıcı "12,5" yerine
    // yanlışlıkla geçersiz bir şey yazarsa (ör. klavye hatası), lot
    // miktarı hiç uyarı vermeden sıfırlanıp kaydediliyordu. Ayrıca
    // negatif miktar da hiç engellenmiyordu.
    final miktar = ParaUtils.sayiCoz(miktCtrl.text.trim());
    if (miktar == null || miktar < 0) {
      BildirimServisi.uyari(context, 'Geçerli bir miktar girin (0 veya üzeri)');
      return;
    }
    try {
      final skt = sktCtrl.text.trim().isNotEmpty
          ? DateTime.tryParse(sktCtrl.text.trim())?.toIso8601String()
          : null;

      // 🔴🔴 FAZ 1 madde 3 (kullanıcı onayıyla, Seçenek A): lot miktarı
      // ARTIK bağımsız düzenlenemiyor — buradaki her miktar değişikliği
      // StokDeposu üzerinden stok_hareket'e "Lot Düzeltme" olarak
      // işleniyor ve urunler.stok AYNI transaction içinde güncelleniyor.
      // Öncesinde bu ekran lot_seri.miktar'ı doğrudan yazıyordu — bu,
      // lotların TOPLAMI ile urunler.stok'un birbirinden sessizce
      // sapmasına yol açabiliyordu (stok mutabakatı stok_hareket'i tek
      // doğru kaynak sayıyor, bu ekran ona hiç dokunmuyordu).
      final urunId = lot == null ? widget.urunId : lot['urun_id'] as int;
      if (urunId == null) {
        if (mounted) BildirimServisi.uyari(context, 'Ürün seçilmedi');
        return;
      }
      final eskiMiktar =
          lot == null ? 0.0 : (lot['miktar'] as num?)?.toDouble() ?? 0.0;

      // Tüm transaction + bulut senkron mantığı artık LotDeposu.kaydet'te
      // — bkz. o metodun doc yorumu, davranış birebir korundu.
      final (lotId, fark) = await LotDeposu().kaydet(
        existingLotId: lot == null ? null : lot['id'] as int,
        urunId: urunId,
        eskiMiktar: eskiMiktar,
        lotNo: lotCtrl.text.trim(),
        sktIso: skt,
        miktar: miktar,
        aciklama: notCtrl.text.trim(),
        kullaniciId: AuthServisi().aktifId,
      );

      // FAZ 9 — Onay Merkezi (bildirim tipi): stok düzeltmesi ENGELLENMEDİ,
      // zaten uygulandı — sadece miktar eşiği aşılıyorsa sonradan
      // incelenebilsin diye kayda düşülüyor.
      if (fark != 0) {
        OnayMerkeziServisi().kaydet(
          tur: OnayTuru.stokDuzeltme,
          tutar: fark.abs(),
          esikTutar: OnayEsikleri.stokDuzeltmeMiktari,
          referansTuru: 'lot_seri',
          referansId: lotId,
          aciklama: 'Lot Düzeltme: ${fark > 0 ? '+' : ''}${fark.toStringAsFixed(0)} birim',
        );
      }
      await _yukle();
      if (!mounted) return;
      BildirimServisi.basari(
          context, lot == null ? 'Lot eklendi ✓' : 'Lot güncellendi ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: widget.urunId != null ? 'Lot/Seri Takibi' : 'Tüm Lot/Seriler',
        gradyanli: true,
        aksiyonlar: [
          if (widget.urunId != null)
            IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: () => _lotDialog(),
                tooltip: 'Yeni Lot'),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(TsBosluk.md),
          child: Column(children: [
            TsInput(
              etiket: 'Ara',
              ipucu: 'Lot No veya ürün adı ara...',
              oncilIkon: Icons.search,
              degisti: _filtrele,
            ),
            const SizedBox(height: TsBosluk.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _durumlar
                    .map((d) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label:
                                Text(d, style: const TextStyle(fontSize: 12)),
                            selected: _durum == d,
                            onSelected: (_) {
                              setState(() => _durum = d);
                              _filtrele('');
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),
          ]),
        ),
        Expanded(
          child: TsListe<Map<String, dynamic>>(
            yukleniyor: _yukleniyor,
            ogeler: _filtrelenmis,
            bosBaslik: 'Lot/seri bulunamadı',
            bosIkon: Icons.inventory_2_outlined,
            kartOlustur: (context, r, i) {
              final skt = r['son_kullanma_tarihi']?.toString();
              final sktRenk = _sktRenk(skt);
              final miktar = (r['miktar'] as num?)?.toDouble() ?? 0;
              return TsKart.liste(
                ikon: Icon(Icons.inventory_2, color: sktRenk),
                baslik: r['lot_no']?.toString() ?? '-',
                altBaslik: [
                  if (widget.urunId == null) r['urun_adi']?.toString() ?? '',
                  if (skt != null)
                    'SKT: ${_fmt.format(DateTime.tryParse(skt) ?? DateTime.now())}',
                ].where((s) => s.isNotEmpty).join(' · '),
                deger:
                    '${miktar.toStringAsFixed(miktar % 1 == 0 ? 0 : 2)} adet',
                onTap: () => _lotDialog(lot: r),
              );
            },
          ),
        ),
      ]),
    );
  }
}
