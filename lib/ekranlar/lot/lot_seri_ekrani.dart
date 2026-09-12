// lib/ekranlar/lot/lot_seri_ekrani.dart
// Lot ve seri numarası takibi — ürün bazlı lot listesi, stok detayı
import 'package:flutter/material.dart';
import '../../cekirdek/utils/para_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../servisler/bildirim_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../veri/database/veritabani.dart';
import 'package:uuid/uuid.dart';

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

  static const _durumlar = ['Tümü', 'Aktif', 'Tükendi', 'SKT Yakın', 'SKT Geçti'];

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
      final db = await Veritabani().db;
      final rows = await db.rawQuery('''
        SELECT ls.*, u.urun_adi, u.barkod as urun_barkod
        FROM lot_seri ls
        JOIN urunler u ON ls.urun_id = u.id
        ${widget.urunId != null ? "WHERE ls.urun_id = ?" : ""}
        ORDER BY ls.son_kullanma_tarihi ASC, ls.lot_no ASC
      ''', widget.urunId != null ? [widget.urunId] : []);
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
    final lotCtrl = TextEditingController(text: lot?['lot_no']?.toString() ?? '');
    final sktCtrl = TextEditingController(text: lot?['son_kullanma_tarihi']?.toString().split('T').first ?? '');
    final miktCtrl = TextEditingController(text: lot?['miktar']?.toString() ?? '');
    final notCtrl = TextEditingController(text: lot?['aciklama']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: Text(lot == null ? 'Yeni Lot/Seri' : 'Lot Düzenle'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TsInput(etiket: 'Lot/Seri No *', controller: lotCtrl, oncilIkon: Icons.tag),
          const SizedBox(height: TsBosluk.md),
          TsInput(etiket: 'Son Kullanma Tarihi (YYYY-AA-GG)', controller: sktCtrl, oncilIkon: Icons.calendar_today),
          const SizedBox(height: TsBosluk.md),
          TsInput(etiket: 'Mevcut Miktar', controller: miktCtrl, oncilIkon: Icons.inventory, klavyeTuru: TextInputType.number),
          const SizedBox(height: TsBosluk.md),
          TsInput(etiket: 'Not', controller: notCtrl, oncilIkon: Icons.note, maksSatir: 2),
        ])),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(ctx, false)),
          TsButon(metin: 'Kaydet', onPressed: () {
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
      final db = await Veritabani().db;
      final skt = sktCtrl.text.trim().isNotEmpty
          ? DateTime.tryParse(sktCtrl.text.trim())?.toIso8601String()
          : null;
      final data = {
        'lot_no': lotCtrl.text.trim(),
        'son_kullanma_tarihi': skt,
        'miktar': miktar,
        'aciklama': notCtrl.text.trim(),
      };
      int lotId;
      if (lot == null) {
        if (widget.urunId == null) {
          // `Veritabani().db` await'i sonrası — yukarıdaki mounted kontrolü
          // o await'ten ÖNCEydi, burada tekrar gerekli.
          if (mounted) BildirimServisi.uyari(context, 'Ürün seçilmedi');
          return;
        }
        final gid = const Uuid().v4();
        lotId = await db.insert('lot_seri', {
          ...data,
          'global_id': gid,
          'urun_id': widget.urunId,
          'kayit_tarihi': DateTime.now().toIso8601String(),
          'last_updated': DateTime.now().toIso8601String(),
        });
      } else {
        lotId = lot['id'] as int;
        data['last_updated'] = DateTime.now().toIso8601String();
        await db.update('lot_seri', data, where: 'id=?', whereArgs: [lotId]);
      }
      // 🔴 Derin analizde bulundu: bu ekran (lot_seri senkron sisteminde
      // olduğu halde) global_id atamıyordu ve BulutManager'ı hiç
      // çağırmıyordu — lot/SKT takibi (çok şubeli işletmelerde kritik)
      // hiç senkronize olmuyordu.
      final satir = await db.query('lot_seri', where: 'id = ?', whereArgs: [lotId], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('lot_seri', Map<String, dynamic>.from(satir.first));
      await _yukle();
      if (!mounted) return;
      BildirimServisi.basari(context, lot == null ? 'Lot eklendi ✓' : 'Lot güncellendi ✓');
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
            IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: () => _lotDialog(), tooltip: 'Yeni Lot'),
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
                            label: Text(d, style: const TextStyle(fontSize: 12)),
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
                  if (skt != null) 'SKT: ${_fmt.format(DateTime.tryParse(skt) ?? DateTime.now())}',
                ].where((s) => s.isNotEmpty).join(' · '),
                deger: '${miktar.toStringAsFixed(miktar % 1 == 0 ? 0 : 2)} adet',
                onTap: () => _lotDialog(lot: r),
              );
            },
          ),
        ),
      ]),
    );
  }
}
