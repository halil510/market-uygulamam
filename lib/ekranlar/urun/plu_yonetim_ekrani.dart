// lib/ekranlar/urun/plu_yonetim_ekrani.dart
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../veri/database/veritabani.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class PluYonetimEkrani extends ConsumerStatefulWidget {
  const PluYonetimEkrani({super.key});
  @override
  ConsumerState<PluYonetimEkrani> createState() => _PluYonetimEkraniState();
}

class _PluYonetimEkraniState extends ConsumerState<PluYonetimEkrani>
    with SingleTickerProviderStateMixin {
  
  late TabController _tabCtrl;
  final _depo    = UrunDeposu();
  final _araCtrl = TextEditingController();

  List<UrunModel> _pluUrunler  = [];
  List<UrunModel> _aramaUrunler = [];
  bool   _yukleniyor = true;
  String _aramaQ     = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _dbKolonEkle().then((_) => _yukle());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _araCtrl.dispose();
    super.dispose();
  }

  // DB'de plu kolonu yoksa ekle (migration çalışmamış olabilir)
  Future<void> _dbKolonEkle() async {
    try {
      final db = await Veritabani().db;
      try {
        await db.execute(
          'ALTER TABLE urunler ADD COLUMN plu INTEGER NOT NULL DEFAULT 0');
      } catch (e) { /* ignore */ }
      try {
        await db.execute(
          'ALTER TABLE urunler ADD COLUMN plu_kart_boyut INTEGER NOT NULL DEFAULT 2');
      } catch (e) { /* ignore */ }
    } catch (e) { /* ignore */ }
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final db   = await Veritabani().db;
      final rows = await db.rawQuery(
        'SELECT * FROM urunler WHERE plu = 1 AND is_deleted = 0 '
        'ORDER BY plu_sira ASC, urun_adi',
      );
      final liste = rows.map(UrunModel.fromMap).toList();
      if (!mounted) return;
      setState(() { _pluUrunler = liste; _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _aramaYap(String q) async {
    try {  
      setState(() => _aramaQ = q);
      if (q.trim().isEmpty) {
        setState(() => _aramaUrunler = []);
        return;
      }
      final sonuc = await _depo.ara(q.trim(), limit: 50);
      if (!mounted) return;
      setState(() => _aramaUrunler = sonuc);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _pluEkle(UrunModel u) async {
    try {
      final db = await Veritabani().db;
      // Yeni eklenen ürün listenin SONUNA gitsin diye mevcut en yüksek
      // sıradan bir fazlası atanıyor (aksi halde varsayılan 0 ile en öne
      // atlardı).
      final maxRow = await db.rawQuery(
          'SELECT MAX(plu_sira) as m FROM urunler WHERE plu = 1');
      final yeniSira = ((maxRow.first['m'] as num?)?.toInt() ?? -1) + 1;
      final now = DateTime.now().toIso8601String();
      await db.update('urunler',
        {'plu': 1, 'plu_kart_boyut': 2, 'plu_sira': yeniSira, 'last_updated': now},
        where: 'id = ?', whereArgs: [u.id]);
      final satir = await db.query('urunler', where: 'id = ?', whereArgs: [u.id], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('urunler', Map<String, dynamic>.from(satir.first));
      await _yukle();
      if (mounted) BildirimServisi.basari(context, '${u.urunAdi} PLU paneline eklendi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<void> _pluCikar(UrunModel u) async {
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      await db.update('urunler', {'plu': 0, 'last_updated': now},
          where: 'id = ?', whereArgs: [u.id]);
      final satir = await db.query('urunler', where: 'id = ?', whereArgs: [u.id], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('urunler', Map<String, dynamic>.from(satir.first));
      await _yukle();
      if (mounted) BildirimServisi.basari(context, '${u.urunAdi} çıkarıldı');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<void> _boyutDegistir(UrunModel u, int boyut) async {
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      await db.update('urunler', {'plu_kart_boyut': boyut, 'last_updated': now},
          where: 'id = ?', whereArgs: [u.id]);
      final satir = await db.query('urunler', where: 'id = ?', whereArgs: [u.id], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('urunler', Map<String, dynamic>.from(satir.first));
      await _yukle();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'PLU Panel Yönetimi',
        alt: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: 'Panelde (${_pluUrunler.length})'),
            const Tab(text: 'Ürün Ekle'),
          ],
        ),
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : TabBarView(
              controller: _tabCtrl,
              children: [_pluTab(), _ekleTab()],
            ),
    );
  }

  // ── PLU listesi ───────────────────────────────────────────────────────────
  Widget _pluTab() {
    if (_pluUrunler.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.grid_off, size: 64, color: TsRenk.ayirac(context)),
          const SizedBox(height: 16),
          Text('PLU panelinde ürün yok',
              style: TextStyle(fontSize: 15, color: context.textSecondary)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => _tabCtrl.animateTo(1),
            child: const Text('Ürün Ekle'),
          ),
        ]),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _pluUrunler.length,
      onReorder: _siralamaKaydet,
      itemBuilder: (_, i) => _pluKarti(_pluUrunler[i]),
    );
  }

  // ÖNCEDEN BURADA CİDDİ BİR HATA VARDI: sürükle-bırak ile sıralama sadece
  // ekranda (setState) değişiyordu, veritabanına HİÇ kaydedilmiyordu —
  // ekran yeniden açıldığında sıralama tamamen kayboluyordu. Artık yeni
  // sıra, `plu_sira` sütununa kalıcı olarak yazılıyor.
  Future<void> _siralamaKaydet(int eski, int yeni) async {
    setState(() {
      if (yeni > eski) yeni--;
      final u = _pluUrunler.removeAt(eski);
      _pluUrunler.insert(yeni, u);
    });
    try {
      // TEK transaction'da atomik yazım + her ürün için bulut bildirimi
      // artık UrunDeposu.pluSiralamaKaydet'te — bkz. o metodun doc
      // yorumu, davranış birebir korundu.
      await UrunDeposu()
          .pluSiralamaKaydet(_pluUrunler.map((u) => u.id!).toList());
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Sıralama kaydedilemedi: $e');
    }
  }

  Widget _pluKarti(UrunModel u) => Container(
    key: ValueKey(u.id),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: TsRenk.ayirac(context)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        ReorderableDragStartListener(
          index: _pluUrunler.indexOf(u),
          child: Icon(Icons.drag_handle, color: context.textSecondary),
        ),
        const SizedBox(width: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _resim(u, 52),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(u.urunAdi,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(u.barkod ?? '',
                style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context),
                    fontFamily: 'monospace')),
            const SizedBox(height: 6),
            Row(children: [
              Text('Boyut:', style: TextStyle(fontSize: 11, color: context.textSecondary)),
              const SizedBox(width: 6),
              _boyutBtn(u, 1, 'Küçük'),
              const SizedBox(width: 4),
              _boyutBtn(u, 2, 'Orta'),
              const SizedBox(width: 4),
              _boyutBtn(u, 3, 'Büyük'),
              const Spacer(),
              Text(ParaUtils.formatla(u.satisFiyati),
                  style: TsMetin.kucukVurgu),
            ]),
          ],
        )),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.red, size: 20),
          onPressed: () => _pluCikar(u),
          tooltip: 'Çıkar',
        ),
      ]),
    ),
  );

  Widget _boyutBtn(UrunModel u, int deger, String etiket) {
    final secili = u.pluKartBoyut == deger;
    return GestureDetector(
      onTap: () => _boyutDegistir(u, deger),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: secili ? TsRenk.primaryKoyu : TsRenk.arkaplan(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: secili ? TsRenk.primaryKoyu : TsRenk.ayirac(context)),
        ),
        child: Text(etiket,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                color: secili ? Colors.white : TsRenk.metinIkincil(context))),
      ),
    );
  }

  // ── Ürün ekle ─────────────────────────────────────────────────────────────
  Widget _ekleTab() {
    final ekliIds = _pluUrunler.map((u) => u.id).toSet();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _araCtrl,
          onChanged: _aramaYap,
          decoration: InputDecoration(
            hintText: 'Ürün adı veya barkod ara...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _aramaQ.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear),
                    onPressed: () { _araCtrl.clear(); _aramaYap(''); })
                : null,
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: TsRenk.ayirac(context))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: TsRenk.ayirac(context))),
            isDense: true,
          ),
        ),
      ),
      Expanded(
        child: _aramaQ.isEmpty
            ? Center(child: Text('Ürün adı veya barkod girin',
                style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 14)))
            : _aramaUrunler.isEmpty
                ? Center(child: Text('Ürün bulunamadı',
                    style: TextStyle(color: TsRenk.metinIkincil(context))))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: _aramaUrunler.length,
                    itemBuilder: (_, i) {
                      final u = _aramaUrunler[i];
                      final ekli = ekliIds.contains(u.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                            color: TsRenk.kart(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: TsRenk.ayirac(context))),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _resim(u, 44),
                          ),
                          title: Text(u.urunAdi,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text(u.barkod ?? '-',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 11)),
                          trailing: ekli
                              ? Chip(
                                  label: const Text('Eklendi',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.green)),
                                  backgroundColor: Colors.green.shade50,
                                  side: BorderSide(color: Colors.green.shade200),
                                )
                              : FilledButton(
                                  onPressed: () => _pluEkle(u),
                                  style: FilledButton.styleFrom(
                                      foregroundColor: Colors.white,
          backgroundColor: TsRenk.primaryKoyu,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 6)),
                                  child: const Text('Ekle',
                                      style: TextStyle(fontSize: 12)),
                                ),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  // ── Yardımcılar ───────────────────────────────────────────────────────────
  Widget _resim(UrunModel u, double boyut) {
    final yol = u.resimYolu;
    if (yol != null && yol.isNotEmpty) {
      final f = File(yol);
      if (f.existsSync()) {
        // 🔴 DÜZELTME (performans denetimi): cacheWidth/cacheHeight
        // yoktu — kamera fotoğrafı $boyut px'lik bir kutuda tam
        // çözünürlükte decode ediliyordu.
        final px = (boyut * MediaQuery.of(context).devicePixelRatio).round();
        return Image.file(f, width: boyut, height: boyut, fit: BoxFit.cover,
            cacheWidth: px, cacheHeight: px,
            errorBuilder: (_, __, ___) => _harf(u, boyut));
      }
    }
    return _harf(u, boyut);
  }

  Widget _harf(UrunModel u, double boyut) {
    const renkler = [
      TsRenk.primaryKoyu, Color(0xFF2E7D32), Color(0xFFC62828),
      Color(0xFF6A1B9A), Color(0xFF00695C), Color(0xFFE65100),
    ];
    final renk = renkler[u.urunAdi.codeUnits.fold(0, (a, b) => a + b) % renkler.length];
    return Container(
      width: boyut, height: boyut, color: renk.withAlpha(31),
      child: Center(child: Text(
        u.urunAdi.isNotEmpty ? u.urunAdi[0].toUpperCase() : '?',
        style: TextStyle(fontSize: boyut * 0.38,
            fontWeight: FontWeight.w900, color: renk),
      )),
    );
  }
}
