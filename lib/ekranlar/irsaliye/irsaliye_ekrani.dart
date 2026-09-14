// lib/ekranlar/irsaliye/irsaliye_ekrani.dart  (Riverpod v2.2)
//
// DEĞIŞIKLIKLER:
//   - import provider kaldırıldı
//   - context.read<IrsaliyeNotifier>().listYukle() → ref.invalidate(irsaliyeListesiProvider)
//   - StatefulWidget → ConsumerStatefulWidget

import 'dart:async';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../veri/database/veritabani.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../saglayicilar/riverpod/irsaliye_provider.dart';
import '../../tasarim_sistemi/ts_yetki.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../servisler/gib_servisi.dart';

class IrsaliyeEkrani extends ConsumerWidget {
  const IrsaliyeEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final irsaliyelerAsync = ref.watch(irsaliyeListesiProvider);
    final fmt = DateFormat('dd.MM.yyyy');

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'İrsaliyeler',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(irsaliyeListesiProvider),
          ),
        ],
        geriTusu: false,
        modul: TsModul.belge,
      ),
      floatingActionButton: TsYetkili(child: FloatingActionButton.extended(
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IrsaliyeEkleEkrani()),
          );
          ref.invalidate(irsaliyeListesiProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('Yeni İrsaliye'),
      )),
      body: irsaliyelerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 3, color: TsRenk.primary)),
        error: (e, _) => BosEkran(ikon: Icons.inbox_outlined, baslik: 'Hata: $e'),
        data: (irsaliyeler) {
          if (irsaliyeler.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_shipping_outlined, size: 60, color: context.textSecondary),
                const SizedBox(height: 12),
                Text('Henüz irsaliye yok'),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(irsaliyeListesiProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: irsaliyeler.length,
              itemBuilder: (_, i) {
                final r     = irsaliyeler[i];
                final tarih = r['tarih'] != null
                    ? fmt.format(
                        DateTime.tryParse(r['tarih'].toString()) ?? DateTime.now())
                    : '-';
                final durum = r['durum']?.toString() ?? 'Bekliyor';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: context.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor)),
                  child: ListTile(
                    leading: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.local_shipping,
                          color: Colors.teal, size: 22),
                    ),
                    title: Text(r['irsaliye_no']?.toString() ?? '-',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(
                      '${r['cari_adi'] ?? 'Müşteri yok'} • $tarih',
                      style: TextStyle(
                          fontSize: 12, color: context.textSecondary)),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          ParaUtils.formatla(
                              (r['toplam_tutar'] as num?)?.toDouble() ?? 0),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: durum == 'Teslim Edildi'
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(durum,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: durum == 'Teslim Edildi'
                                      ? Colors.green
                                      : Colors.orange)),
                        ),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => IrsaliyeDetayEkrani(
                              irsaliyeId: r['id'] as int),
                        ),
                      );
                      ref.invalidate(irsaliyeListesiProvider);
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ── İrsaliye Ekle ─────────────────────────────────────────────────────────────

class IrsaliyeEkleEkrani extends ConsumerStatefulWidget {
  const IrsaliyeEkleEkrani({super.key});

  @override
  ConsumerState<IrsaliyeEkleEkrani> createState() => _IrsaliyeEkleEkraniState();
}

class _IrsaliyeEkleEkraniState extends ConsumerState<IrsaliyeEkleEkrani> {
  final _urunDepo = UrunDeposu();
  final _cariDepo = CariDeposu();
  final _araCtrl  = TextEditingController();
  Timer? _debounce;

  CariModel? _seciliCari;
  List<_IrsKalem> _kalemler = [];
  List<UrunModel> _aramaSonuclari = [];
  bool _kayit = false;
  DateTime _tarih = DateTime.now();
  String _tip = 'Çıkış';

  @override
  void dispose() {
    _araCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _aramaChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (q.trim().length < 2) {
        if (mounted) setState(() => _aramaSonuclari = []);
        return;
      }
      final s = await _urunDepo.ara(q.trim(), limit: 10);
      if (mounted) setState(() => _aramaSonuclari = s);
    });
  }

  void _urunEkle(UrunModel u) {
    final mevcut = _kalemler.indexWhere((k) => k.urunId == u.id!);
    setState(() {
      if (mevcut >= 0) {
        _kalemler[mevcut] = _IrsKalem(
          urunId:     u.id!,
          urunAdi:    u.urunAdi,
          barkod:     u.barkod,
          miktar:     _kalemler[mevcut].miktar + 1,
          birimAdi:   u.birimAdi,
          birimFiyat: u.satisFiyati,
        );
      } else {
        _kalemler.add(_IrsKalem(
          urunId:     u.id!,
          urunAdi:    u.urunAdi,
          barkod:     u.barkod,
          miktar:     1,
          birimAdi:   u.birimAdi,
          birimFiyat: u.satisFiyati,
        ));
      }
      _aramaSonuclari = [];
      _araCtrl.clear();
    });
  }

  Future<void> _cariSec() async {
    final cariler = await _cariDepo.tumunuGetir(tip: 'Müşteri');
    if (!mounted) return;
    final secilen = await showDialog<CariModel>(
      context: context,
      builder: (bCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Text('Müşteri Seç'),
        content: SizedBox(
          width: 360, height: 400,
          child: ListView.builder(
            itemCount: cariler.length,
            itemBuilder: (_, i) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.teal.shade50,
                child: Text(cariler[i].unvan.isNotEmpty
                    ? cariler[i].unvan[0].toUpperCase() : '?',
                    style: TextStyle(color: Colors.teal.shade700,
                        fontWeight: FontWeight.w700)),
              ),
              title: Text(cariler[i].unvan),
              subtitle: cariler[i].telefon != null
                  ? Text(cariler[i].telefon!) : null,
              onTap: () => Navigator.pop(bCtx, cariler[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(bCtx),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
    if (secilen != null) setState(() => _seciliCari = secilen);
  }

  Future<void> _kaydet() async {
    if (_kayit) return; // 🔴 DÜZELTME: çift tıklama koruması hiç yoktu —
    // hızlı çift tıklamada aynı irsaliye iki kez oluşturulabiliyordu.
    if (_kalemler.isEmpty) {
      BildirimServisi.uyari(context, 'En az 1 ürün ekleyin');
      return;
    }
    setState(() => _kayit = true);
    try {
      final db     = await Veritabani().db;
      // ÖNCEDEN burada zaman damgası tabanlı ("IRS" + yıl + zaman
      // damgasının son haneleri) bir numara üretiliyordu — bu, fatura/
      // cari numarasında bulup düzelttiğim AYNI çakışma riskini
      // taşıyordu. Meğer doğru, GİB-standardı, kalıcı sayaç tabanlı
      // fonksiyon (fisNoUret) ZATEN varmış, sadece kullanılmıyormuş.
      final no     = await Veritabani().fisNoUret('irsaliye', subeId: AktifSubeServisi().subeId ?? 1);
      final toplam = _kalemler.fold(0.0, (s, k) => s + k.miktar * k.birimFiyat);
      final now = DateTime.now().toIso8601String();
      final irsaliyeGid = const Uuid().v4();
      late int irsaliyeId;
      final kalemGidler = <String>[];
      final stokHareketGidler = <String>[];
      final etkilenenUrunIdler = <int>{};

      await db.transaction((txn) async {
        irsaliyeId = await txn.insert('irsaliyeler', {
          'global_id':    irsaliyeGid,
          'irsaliye_no':  no,
          'cari_id':      _seciliCari?.id,
          'tarih':        _tarih.toIso8601String(),
          'tip':          _tip,
          'toplam_tutar': toplam,
          'durum':        'Hazırlanıyor',
          'kullanici_id': AuthServisi().aktifId,
          'created_at':   now,
          'last_updated': now,
        });
        for (final k in _kalemler) {
          final kalemGid = const Uuid().v4();
          kalemGidler.add(kalemGid);
          await txn.insert('irsaliye_kalem', {
            'global_id':    kalemGid,
            'irsaliye_id':  irsaliyeId,
            'urun_id':      k.urunId,
            'urun_adi':     k.urunAdi,
            'miktar':       k.miktar,
            'birim_fiyat':  k.birimFiyat,
            'toplam_tutar': k.miktar * k.birimFiyat,
            'last_updated': now,
          });
          // Stok hareketi — ÖNCEDEN hareket kaydı hiç oluşturulmuyordu.
          final hareketMiktar = _tip == 'Çıkış' ? -k.miktar : k.miktar;
          final urunRows = await txn.query('urunler',
              columns: ['stok'], where: 'id = ?', whereArgs: [k.urunId]);
          if (urunRows.isNotEmpty) {
            final onceki = (urunRows.first['stok'] as num).toDouble();
            final sonraki = onceki + hareketMiktar;
            await txn.update('urunler', {'stok': sonraki, 'last_updated': now}, where: 'id = ?', whereArgs: [k.urunId]);
            etkilenenUrunIdler.add(k.urunId);
            final stokGid = const Uuid().v4();
            stokHareketGidler.add(stokGid);
            await txn.insert('stok_hareket', {
              'global_id': stokGid,
              'urun_id': k.urunId,
              'hareket_turu': 'İrsaliye $_tip',
              'miktar': k.miktar,
              'onceki_stok': onceki,
              'sonraki_stok': sonraki,
              'tarih': now,
              'last_updated': now,
              'referans_id': irsaliyeId,
              'referans_turu': 'irsaliye',
            });
          }
        }
      });

      // 🔴🔴 Derin analizde bulundu: bu ekran (irsaliyeler, irsaliye_kalem,
      // urunler, stok_hareket — 4 tablo) hiçbir yerde global_id atamıyordu
      // ve BulutManager'ı HİÇ çağırmıyordu — irsaliyeler (resmi sevk
      // belgeleri) sadece manuel senkronla buluta gidiyordu. Transaction
      // kapandıktan (veri kalıcı olduktan) SONRA bildiriliyor.
      try {
        final irsSatir = await db.query('irsaliyeler', where: 'id = ?', whereArgs: [irsaliyeId], limit: 1);
        if (irsSatir.isNotEmpty) BulutManager().upsert('irsaliyeler', Map<String, dynamic>.from(irsSatir.first));
        for (final gid in kalemGidler) {
          final s = await db.query('irsaliye_kalem', where: 'global_id = ?', whereArgs: [gid], limit: 1);
          if (s.isNotEmpty) BulutManager().upsert('irsaliye_kalem', Map<String, dynamic>.from(s.first));
        }
        for (final urunId in etkilenenUrunIdler) {
          final s = await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
          if (s.isNotEmpty) BulutManager().upsert('urunler', Map<String, dynamic>.from(s.first));
        }
        for (final gid in stokHareketGidler) {
          final s = await db.query('stok_hareket', where: 'global_id = ?', whereArgs: [gid], limit: 1);
          if (s.isNotEmpty) BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(s.first));
        }
      } catch (e) {
        // Bulut bildirimi hatası asıl işlemi engellemez
      }

      if (!mounted) return;
      BildirimServisi.basari(context, 'İrsaliye oluşturuldu ✓');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  double get _toplam =>
      _kalemler.fold(0, (s, k) => s + k.miktar * k.birimFiyat);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TsAppBar(
        baslik: 'Yeni İrsaliye',
        aksiyonlar: [
          if (!_kayit)
            TextButton(
              onPressed: _kayit ? null : _kaydet,
              child: const Text('Kaydet',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (_kayit)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: TsRenk.primary),
                ),
              ),
            ),
        ],
        gradyanli: false,
      ),
      body: Column(children: [
        // Üst bilgiler
        Container(
          padding: const EdgeInsets.all(14),
          color: Color.fromARGB(76, Theme.of(context).colorScheme.surfaceVariant.red, Theme.of(context).colorScheme.surfaceVariant.green, Theme.of(context).colorScheme.surfaceVariant.blue),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _tip,
                isDense: true,
                decoration: const InputDecoration(
                    labelText: 'Tip', border: OutlineInputBorder()),
                items: ['Çıkış', 'Giriş', 'Transfer']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) { if (v != null) setState(() => _tip = v); },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cariSec,
                icon: const Icon(Icons.person_search, size: 16),
                label: Text(
                  _seciliCari?.unvan ?? 'Müşteri Seç',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ]),
        ),

        // Ürün arama
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _araCtrl,
            decoration: const InputDecoration(
              hintText: 'Ürün ara ve ekle...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: _aramaChanged,
          ),
        ),

        if (_aramaSonuclari.isNotEmpty)
          SizedBox(
            height: 160,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: ListView.builder(
                itemCount: _aramaSonuclari.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(_aramaSonuclari[i].urunAdi),
                  subtitle: Text(ParaUtils.formatla(_aramaSonuclari[i].satisFiyati)),
                  trailing: Text('${_aramaSonuclari[i].stok.toStringAsFixed(0)} stok',
                      style: TextStyle(
                          fontSize: 11,
                          color: _aramaSonuclari[i].stok > 0
                              ? Colors.green : Colors.red)),
                  onTap: () => _urunEkle(_aramaSonuclari[i]),
                ),
              ),
            ),
          ),

        // Kalem listesi
        Expanded(
          child: _kalemler.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 48, color: context.textSecondary),
                      const SizedBox(height: 8),
                      Text('Ürün ekleyin',
                          style: TextStyle(color: context.textSecondary)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _kalemler.length,
                  itemBuilder: (_, i) {
                    final k = _kalemler[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.inventory_2_outlined,
                              color: Colors.teal, size: 18),
                        ),
                        title: Text(k.urunAdi,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(
                            '${k.birimAdi} • ${ParaUtils.formatla(k.birimFiyat)}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 20, color: Colors.red),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () {
                              setState(() {
                                if (k.miktar <= 1) {
                                  _kalemler.removeAt(i);
                                } else {
                                  _kalemler[i] = _IrsKalem(
                                    urunId:     k.urunId,
                                    urunAdi:    k.urunAdi,
                                    barkod:     k.barkod,
                                    miktar:     k.miktar - 1,
                                    birimAdi:   k.birimAdi,
                                    birimFiyat: k.birimFiyat,
                                  );
                                }
                              });
                            },
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              k.miktar.toStringAsFixed(
                                  k.miktar % 1 == 0 ? 0 : 2),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                size: 20, color: Colors.green),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () {
                              setState(() {
                                _kalemler[i] = _IrsKalem(
                                  urunId:     k.urunId,
                                  urunAdi:    k.urunAdi,
                                  barkod:     k.barkod,
                                  miktar:     k.miktar + 1,
                                  birimAdi:   k.birimAdi,
                                  birimFiyat: k.birimFiyat,
                                );
                              });
                            },
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),

        // Toplam bar
        if (_kalemler.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              Text('${_kalemler.length} kalem',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text(
                ParaUtils.formatla(_toplam),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _IrsKalem {
  final int    urunId;
  final String urunAdi;
  final String? barkod;
  final double miktar;
  final String birimAdi;
  final double birimFiyat;

  const _IrsKalem({
    required this.urunId,
    required this.urunAdi,
    this.barkod,
    required this.miktar,
    required this.birimAdi,
    required this.birimFiyat,
  });
}

// ── İrsaliye Detay ────────────────────────────────────────────────────────────

class IrsaliyeDetayEkrani extends ConsumerStatefulWidget {
  final int irsaliyeId;
  const IrsaliyeDetayEkrani({super.key, required this.irsaliyeId});

  @override
  ConsumerState<IrsaliyeDetayEkrani> createState() => _IrsaliyeDetayEkraniState();
}

class _IrsaliyeDetayEkraniState extends ConsumerState<IrsaliyeDetayEkrani> {
  Map<String, dynamic>? _irsaliye;
  List<Map<String, dynamic>> _kalemler = [];
  bool _yukleniyor = true;
  bool _islemDevam = false;
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final db = await Veritabani().db;
      final rows = await db.rawQuery('''
        SELECT i.*, c.unvan as cari_adi,
          COALESCE(NULLIF(c.vergi_no, ''), c.tc_kimlik) as cari_vergi_no,
          c.vergi_dairesi as cari_vergi_dairesi,
          ca.adres as cari_adres
        FROM irsaliyeler i
        LEFT JOIN cari c ON i.cari_id = c.id
        LEFT JOIN cari_adres ca ON ca.cari_id = i.cari_id AND ca.varsayilan = 1
        WHERE i.id = ?
      ''', [widget.irsaliyeId]);
      final kalemler = await db.rawQuery('''
        SELECT ik.*, u.urun_adi as urun_adi_db FROM irsaliye_kalem ik
        LEFT JOIN urunler u ON ik.urun_id = u.id
        WHERE ik.irsaliye_id = ?
      ''', [widget.irsaliyeId]);
      if (!mounted) return;
      setState(() {
        _irsaliye  = rows.isNotEmpty ? rows.first : null;
        _kalemler  = kalemler;
        _yukleniyor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _durumGuncelle(String yeniDurum) async {
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      await db.update('irsaliyeler', {'durum': yeniDurum, 'last_updated': now},
          where: 'id=?', whereArgs: [widget.irsaliyeId]);
      // 🔴 Derin analizde bulundu: last_updated hiç ayarlanmıyordu,
      // BulutManager hiç çağrılmıyordu.
      final satir = await db.query('irsaliyeler', where: 'id = ?', whereArgs: [widget.irsaliyeId], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('irsaliyeler', Map<String, dynamic>.from(satir.first));
      await _yukle();
      if (!mounted) return;
      BildirimServisi.basari(context, 'Durum güncellendi: $yeniDurum');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  bool get _eIrsaliyeGonderilmis {
    final d = _irsaliye?['e_irsaliye_durum']?.toString();
    return d == 'gonderildi' || d == 'onaylandi' || d == 'gib_iptal';
  }

  // ── e-İrsaliye Gönder ────────────────────────────────────────────────────
  // Ayarlar > Fatura Ayarları'ndaki "e-İrsaliye Aktif" anahtarı ÖNCEDEN hiçbir
  // koda bağlı değildi (bkz. gib_servisi.dart'taki geniş not) — bu, o
  // eksikliği kapatan ilk gerçek gönderim noktası.
  Future<void> _eIrsaliyeGonder() async {
    if (_irsaliye == null || !mounted || _islemDevam || _eIrsaliyeGonderilmis) return;
    final onay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('e-İrsaliye Gönder'),
        content: Text(
          '${_irsaliye!['irsaliye_no'] ?? "İrsaliye"} GİB sistemine '
          'e-İrsaliye olarak gönderilecek.\n\nOnaylıyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gönder')),
        ],
      ));
    if (onay != true || !mounted) return;

    setState(() => _islemDevam = true);
    try {
      final db = await Veritabani().db;
      // Reddedilmiş bir denemeden sonra yeniden gönderiliyorsa deneme
      // sayacını artır (bkz. gib_servisi.dart'taki ETTN notu — faturalar
      // ile AYNI mantık).
      if (_irsaliye!['e_irsaliye_durum'] == 'reddedildi') {
        final mevcut = (_irsaliye!['e_irsaliye_deneme_no'] as int?) ?? 0;
        await db.update('irsaliyeler', {'e_irsaliye_deneme_no': mevcut + 1},
            where: 'id = ?', whereArgs: [widget.irsaliyeId]);
        await _yukle();
      }
      await db.update('irsaliyeler', {'e_irsaliye_durum': 'gonderiliyor'},
          where: 'id = ?', whereArgs: [widget.irsaliyeId]);

      final gib = GibServisi();
      await gib.ayarlariYukle();
      final sonuc = await gib.irsaliyeGonder(irsaliye: _irsaliye!, kalemler: _kalemler);
      final now = DateTime.now().toIso8601String();
      if (sonuc.basarili) {
        await db.update('irsaliyeler', {
          'e_irsaliye_durum': 'gonderildi',
          'e_irsaliye_uuid': sonuc.uuid,
          'e_irsaliye_gonderim_tarihi': now,
          'last_updated': now,
        }, where: 'id = ?', whereArgs: [widget.irsaliyeId]);
      } else {
        await db.update('irsaliyeler', {'e_irsaliye_durum': 'hata', 'last_updated': now},
            where: 'id = ?', whereArgs: [widget.irsaliyeId]);
      }
      final satir = await db.query('irsaliyeler', where: 'id = ?', whereArgs: [widget.irsaliyeId], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('irsaliyeler', Map<String, dynamic>.from(satir.first));
      await _yukle();
      if (!mounted) return;
      if (sonuc.basarili) {
        BildirimServisi.basari(context, 'e-İrsaliye gönderildi ✓');
      } else {
        BildirimServisi.hata(context, sonuc.hata ?? 'Gönderim başarısız');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islemDevam = false);
    }
  }

  Future<void> _eIrsaliyeDurumSorgula() async {
    final uuid = _irsaliye?['e_irsaliye_uuid']?.toString();
    if (uuid == null || uuid.isEmpty) return;
    setState(() => _islemDevam = true);
    try {
      final gib = GibServisi();
      await gib.ayarlariYukle();
      final durum = await gib.durumSorgula(uuid);
      if (durum != null) {
        final db = await Veritabani().db;
        final now = DateTime.now().toIso8601String();
        await db.update('irsaliyeler', {'e_irsaliye_durum': durum, 'last_updated': now},
            where: 'id = ?', whereArgs: [widget.irsaliyeId]);
        final satir = await db.query('irsaliyeler', where: 'id = ?', whereArgs: [widget.irsaliyeId], limit: 1);
        if (satir.isNotEmpty) BulutManager().upsert('irsaliyeler', Map<String, dynamic>.from(satir.first));
        await _yukle();
      }
      if (mounted) BildirimServisi.basari(context, 'Durum: ${durum ?? "Bilinmiyor"}');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islemDevam = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Scaffold(body: Center(child: const AppYukleniyor()));
    }
    if (_irsaliye == null) {
      return Scaffold(
        appBar: TsAppBar(
        gradyanli: false,
      ),
        body: const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Bulunamadı'),
      );
    }

    final durum  = _irsaliye!['durum']?.toString() ?? 'Bekliyor';
    final tarih  = DateTime.tryParse(_irsaliye!['tarih']?.toString() ?? '');
    final toplam = (_irsaliye!['toplam_tutar'] as num?)?.toDouble() ?? 0;
    final eDurum = _irsaliye!['e_irsaliye_durum']?.toString() ?? 'hazir';
    final eRenk  = eDurum == 'onaylandi' ? Colors.teal
                 : eDurum == 'gonderildi' ? Colors.green
                 : eDurum == 'gonderiliyor' ? Colors.blue
                 : eDurum == 'reddedildi' ? Colors.red
                 : eDurum == 'gib_iptal' ? Colors.grey
                 : eDurum == 'hata' ? Colors.red : Colors.orange;
    final eEtiket = eDurum == 'onaylandi' ? 'GİB Onayladı'
                  : eDurum == 'gonderildi' ? 'e-İrsaliye Gönderildi'
                  : eDurum == 'gonderiliyor' ? 'Gönderiliyor'
                  : eDurum == 'reddedildi' ? 'GİB Reddetti'
                  : eDurum == 'gib_iptal' ? 'GİB\'de İptal'
                  : eDurum == 'hata' ? 'Gönderim Hatası' : 'e-İrsaliye Gönderilmedi';

    return Scaffold(
      appBar: TsAppBar(
        baslikWidget: Text(_irsaliye!['irsaliye_no']?.toString() ?? 'İrsaliye'),
        aksiyonlar: [
          if (_irsaliye!['e_irsaliye_uuid'] != null)
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'GİB Durum Sorgula',
              onPressed: _islemDevam ? null : _eIrsaliyeDurumSorgula,
            ),
          IconButton(
            icon: Icon(
              eDurum == 'onaylandi' ? Icons.verified_outlined
                  : eDurum == 'gonderildi' ? Icons.cloud_done_outlined
                  : eDurum == 'reddedildi' ? Icons.cancel_outlined
                  : Icons.send_outlined,
              color: eRenk,
            ),
            tooltip: _eIrsaliyeGonderilmis ? eEtiket : 'e-İrsaliye Gönder',
            onPressed: (_islemDevam || _eIrsaliyeGonderilmis) ? null : _eIrsaliyeGonder,
          ),
          PopupMenuButton<String>(
            onSelected: _durumGuncelle,
            itemBuilder: (_) => ['Hazırlanıyor', 'Yolda', 'Teslim Edildi', 'İptal']
                .map((d) => PopupMenuItem(value: d, child: Text(d)))
                .toList(),
          ),
        ],
        gradyanli: false,
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Color.fromARGB(76, Theme.of(context).colorScheme.surfaceVariant.red, Theme.of(context).colorScheme.surfaceVariant.green, Theme.of(context).colorScheme.surfaceVariant.blue),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Müşteri',
                    style: TextStyle(fontSize: 11, color: context.textSecondary)),
                Text(_irsaliye!['cari_adi']?.toString() ?? 'Belirtilmemiş',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Tarih',
                    style: TextStyle(fontSize: 11, color: context.textSecondary)),
                Text(tarih != null ? _fmt.format(tarih) : '-',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Wrap(spacing: 6, children: [
                Chip(
                  label: Text(durum),
                  backgroundColor: durum == 'Teslim Edildi'
                      ? Colors.green.shade100 : Colors.orange.shade100,
                ),
                Chip(
                  label: Text(eEtiket, style: TextStyle(fontSize: 11, color: eRenk)),
                  backgroundColor: Color.fromARGB(26, eRenk.red, eRenk.green, eRenk.blue),
                  side: BorderSide(color: Color.fromARGB(102, eRenk.red, eRenk.green, eRenk.blue)),
                ),
              ]),
              Text(ParaUtils.formatla(toplam),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18)),
            ]),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _kalemler.length,
            itemBuilder: (_, i) {
              final k      = _kalemler[i];
              final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
              final bf     = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: ListTile(
                  title: Text(
                    k['urun_adi']?.toString() ??
                        k['urun_adi_db']?.toString() ?? '-',
                  ),
                  subtitle: Text(
                      '${miktar.toStringAsFixed(2)} adet × ${ParaUtils.formatla(bf)}'),
                  trailing: Text(
                    ParaUtils.formatla(miktar * bf),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
