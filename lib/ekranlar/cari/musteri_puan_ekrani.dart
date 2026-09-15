// lib/ekranlar/cari/musteri_puan_ekrani.dart
//
// Müşteri puan paneli — bakiye, hareket geçmişi, puan kullanma
// Cari detay ekranından açılır: context.push('/cari/puan', extra: cariId)
import 'package:flutter/foundation.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../servisler/puan_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../cekirdek/utils/hata_utils.dart';
import '../../tasarim_sistemi/ts_kart.dart';

class MusteriPuanEkrani extends ConsumerStatefulWidget {
  final int cariId;
  final String cariUnvan;
  const MusteriPuanEkrani({
    super.key,
    required this.cariId,
    required this.cariUnvan,
  });
  @override
  ConsumerState<MusteriPuanEkrani> createState() => _MusteriPuanEkraniState();
}

class _MusteriPuanEkraniState extends ConsumerState<MusteriPuanEkrani> {
  final _puan = PuanServisi();
  final _fmt  = DateFormat('dd.MM.yyyy HH:mm');

  double _bakiye = 0;
  List<Map<String, dynamic>> _gecmis = [];
  bool _yukleniyor = true;
  // 🔴 Derin denetimde bulundu (P2): Puan Ekle/Puan Kullan akışlarında
  // hiç çift-dokunma koruması yoktu — hızlı art arda dokunma mükerrer
  // puan ekleme/kullanma riski taşıyordu. Ayrıca yazma çağrıları
  // (puanKullan/puanEkle) try/catch'siz — bir hata kullanıcıya hiç
  // gösterilmiyordu.
  bool _islemAktif = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (mounted) setState(() => _yukleniyor = true);
    try {
      final results = await Future.wait([
        _puan.puanBakiyesi(widget.cariId),
        _puan.puanGecmisi(widget.cariId),
      ]);
      if (mounted) {
        setState(() {
          _bakiye = results[0] as double;
          _gecmis = results[1] as List<Map<String, dynamic>>;
          _yukleniyor = false;
        });
      }
    } catch (e) {
      // 🔴 DÜZELTME: Hata durumunda _yukleniyor hiç false yapılmıyordu
      // — puan bilgisi çekilemezse ekran SONSUZA KADAR "yükleniyor"
      // durumunda kalıyordu.
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) {
        setState(() => _yukleniyor = false);
        BildirimServisi.hata(context, 'Puan bilgisi yüklenemedi: $e');
      }
    }
  }

  Future<void> _puanHarca() async {
    if (_islemAktif) return;
    if (_bakiye <= 0) {
      BildirimServisi.uyari(context, 'Kullanılabilir puan yok');
      return;
    }
    final ctrl = TextEditingController(
        text: _bakiye.toStringAsFixed(0));

    final istenen = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Puan Kullan'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Mevcut bakiye: ${_bakiye.toStringAsFixed(0)} puan'),
          Text('= ${ParaUtils.formatla(_puan.puanTL(_bakiye))} değerinde'),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Kullanılacak puan',
              suffixText: 'puan',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              final v = ParaUtils.sayiCoz(ctrl.text);
              if (v == null || v <= 0 || v > _bakiye) {
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Kullan'),
          ),
        ],
      ),
    );

    if (istenen == null || !mounted) return;
    setState(() => _islemAktif = true);
    try {
      await _puan.puanKullan(
        cariId:       widget.cariId,
        istenenPuan:  istenen,
        satisId:      0, // Manuel kullanım
      );
      if (mounted) {
        BildirimServisi.basari(context,
            '${istenen.toStringAsFixed(0)} puan kullanıldı');
        await _yukle();
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Puan kullanılamadı: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: '${widget.cariUnvan} - Puan',
      ),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 6,
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Puan Ekle'),
        onPressed: () async {
          if (_islemAktif) return;
          final ctrl = TextEditingController();
          final puan = await showDialog<double>(
            context: context,
            builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Manuel Puan Ekle'),
              content: TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Eklenecek puan miktarı',
                  suffixText: 'puan',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
                FilledButton(
                  onPressed: () {
                    final v = ParaUtils.sayiCoz(ctrl.text);
                    if (v != null && v > 0) Navigator.pop(ctx, v);
                  },
                  child: const Text('Ekle'),
                ),
              ],
            ),
          );
          if (puan != null && puan > 0 && mounted) {
            setState(() => _islemAktif = true);
            try {
              await _puan.puanEkle(
                cariId: widget.cariId, tutar: puan, satisId: 0, puanOrani: 1.0);
              await _yukle();
              if (mounted) basariMesaji(context, '${puan.toStringAsFixed(0)} puan eklendi ✓');
            } catch (e) {
              if (mounted) hataMesaji(context, 'Puan eklenemedi: ${kullaniciyaHataMetni(e)}');
            } finally {
              if (mounted) setState(() => _islemAktif = false);
            }
          }
        },
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : RefreshIndicator(
              onRefresh: _yukle,
              child: ListView(children: [
                // Bakiye kartı
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.shade700, Colors.orange.shade500],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(children: [
                    const Text('Puan Bakiyesi',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text(
                      _bakiye.toStringAsFixed(0),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 52,
                          fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '= ${ParaUtils.formatla(_puan.puanTL(_bakiye))}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _bakiye > 0 ? _puanHarca : null,
                      icon: const Icon(Icons.redeem),
                      label: const Text('Puan Kullan'),
                      style: FilledButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withAlpha(50),
                      ),
                    ),
                  ]),
                ),
                // Nasıl çalışır bilgisi
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TsKart(
                      child: Row(children: const [
                        Icon(Icons.info_outline,
                            color: Colors.blue, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Her 1 ₺ alışverişte 1 puan kazanılır. '
                            '100 puan = 1 ₺ indirim.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ]),
                    ),
                ),
                const SizedBox(height: 8),
                // Geçmiş başlık
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Text('Puan Geçmişi',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                if (_gecmis.isEmpty)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Henüz puan hareketi yok',
                          style: TextStyle(color: context.textSecondary)),
                    ),
                  )
                else
                  ..._gecmis.map((h) {
                    final puan = (h['puan'] as num?)?.toDouble() ?? 0;
                    final kazandi = puan > 0;
                    final tarih = h['tarih'] as String? ?? '';
                    DateTime? tarihDt;
                    try { tarihDt = DateTime.parse(tarih); } catch (e) { /* ignore */ }

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: kazandi
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        child: Icon(
                          kazandi ? Icons.add : Icons.remove,
                          color: kazandi ? Colors.green : Colors.red,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        h['aciklama'] as String? ?? h['islem_tipi'] as String? ?? '',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        tarihDt != null ? _fmt.format(tarihDt) : tarih,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        '${kazandi ? '+' : ''}${puan.toStringAsFixed(0)} puan',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kazandi ? Colors.green : Colors.red,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 24),
              ]),
            ),
    );
  }
}
