// lib/ekranlar/ayarlar/veri_sagligi_ekrani.dart
//
// VERİ SAĞLIĞI MERKEZİ (protokol §13) — SQLite/FK/mutabakat/negatif
// stok/mükerrer barkod/yetim kayıt/sync kuyruğu-çakışması/yedekleme
// durumunu tek ekranda YEŞİL/SARI/KIRMIZI olarak gösterir. Düzeltmesi
// güvenli (kanıtlanmış mutabakat fonksiyonu olan) kontrollerde bir
// "Düzelt" butonu sunar — hiçbir kontrol kullanıcı onayı olmadan veri
// değiştirmez.
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/veri_sagligi_servisi.dart';
import '../../widgetlar/ortak/onay_dialog.dart';

class VeriSagligiEkrani extends StatefulWidget {
  const VeriSagligiEkrani({super.key});

  @override
  State<VeriSagligiEkrani> createState() => _VeriSagligiEkraniState();
}

class _VeriSagligiEkraniState extends State<VeriSagligiEkrani> {
  final _servis = VeriSagligiServisi();
  List<SaglikKontrolSonucu> _sonuclar = [];
  bool _yukleniyor = true;
  String? _duzeltilenId;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final liste = await _servis.tumKontrolleriCalistir();
      if (!mounted) return;
      setState(() { _sonuclar = liste; _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Color _renk(SaglikDurum d) => switch (d) {
    SaglikDurum.yesil => Colors.green,
    SaglikDurum.sari => Colors.orange,
    SaglikDurum.kirmizi => Colors.red,
  };

  IconData _ikon(SaglikDurum d) => switch (d) {
    SaglikDurum.yesil => Icons.check_circle,
    SaglikDurum.sari => Icons.warning_amber_rounded,
    SaglikDurum.kirmizi => Icons.error,
  };

  Future<void> _duzeltUygula(SaglikKontrolSonucu k) async {
    if (k.duzelt == null) return;
    final onay = await OnayDialog.goster(context,
        baslik: '${k.baslik} düzeltilsin mi?',
        icerik: '${k.mesaj}\n\nBu işlem, uyuşmayan kayıtları hareket '
            'geçmişinden yeniden hesaplayarak düzeltir. Geri alınamaz '
            'ama güvenlidir — mevcut hareket kayıtlarına dokunmaz, '
            'sadece özet alanları (bakiye/stok) yeniden hesaplar.',
        onayYazi: 'Evet, düzelt', ikon: Icons.build_outlined);
    if (!onay) return;

    setState(() => _duzeltilenId = k.id);
    try {
      final duzeltilenSayi = await k.duzelt!();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$duzeltilenSayi kayıt düzeltildi ✓'),
        backgroundColor: Colors.green.shade700,
      ));
      await _yukle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Düzeltme başarısız: $e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    } finally {
      if (mounted) setState(() => _duzeltilenId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kirmizi = _sonuclar.where((s) => s.durum == SaglikDurum.kirmizi).length;
    final sari = _sonuclar.where((s) => s.durum == SaglikDurum.sari).length;
    final yesil = _sonuclar.where((s) => s.durum == SaglikDurum.yesil).length;

    final gruplu = <String, List<SaglikKontrolSonucu>>{};
    for (final s in _sonuclar) {
      gruplu.putIfAbsent(s.kategori, () => []).add(s);
    }

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Veri Sağlığı Merkezi',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yeniden kontrol et',
            onPressed: _yukleniyor ? null : _yukle,
          ),
        ],
        gradyanli: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : RefreshIndicator(
              onRefresh: _yukle,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Row(children: [
                    Expanded(child: _OzetKart(sayi: yesil, renk: Colors.green, etiket: 'Sağlıklı')),
                    const SizedBox(width: 8),
                    Expanded(child: _OzetKart(sayi: sari, renk: Colors.orange, etiket: 'Uyarı')),
                    const SizedBox(width: 8),
                    Expanded(child: _OzetKart(sayi: kirmizi, renk: Colors.red, etiket: 'Kritik')),
                  ]),
                  const SizedBox(height: 16),
                  for (final kategori in gruplu.keys) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6, top: 6),
                      child: Text(kategori,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: context.textHint, letterSpacing: 0.5)),
                    ),
                    for (final k in gruplu[kategori]!)
                      _KontrolKarti(
                        kontrol: k,
                        renk: _renk(k.durum),
                        ikon: _ikon(k.durum),
                        duzeltiliyor: _duzeltilenId == k.id,
                        onDuzelt: k.duzelt != null ? () => _duzeltUygula(k) : null,
                      ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
    );
  }
}

class _OzetKart extends StatelessWidget {
  final int sayi;
  final Color renk;
  final String etiket;
  const _OzetKart({required this.sayi, required this.renk, required this.etiket});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: renk.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: renk.withAlpha(60)),
      ),
      child: Column(children: [
        Text('$sayi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: renk)),
        const SizedBox(height: 2),
        Text(etiket, style: TextStyle(fontSize: 11, color: renk)),
      ]),
    );
  }
}

class _KontrolKarti extends StatelessWidget {
  final SaglikKontrolSonucu kontrol;
  final Color renk;
  final IconData ikon;
  final bool duzeltiliyor;
  final VoidCallback? onDuzelt;

  const _KontrolKarti({
    required this.kontrol,
    required this.renk,
    required this.ikon,
    required this.duzeltiliyor,
    this.onDuzelt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4)],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ikon, color: renk, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kontrol.baslik,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary)),
            const SizedBox(height: 2),
            Text(kontrol.mesaj, style: TextStyle(fontSize: 12, color: context.textSecondary)),
          ]),
        ),
        if (onDuzelt != null) ...[
          const SizedBox(width: 8),
          duzeltiliyor
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : OutlinedButton(
                  onPressed: onDuzelt,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: renk, padding: const EdgeInsets.symmetric(horizontal: 10)),
                  child: const Text('Düzelt', style: TextStyle(fontSize: 12)),
                ),
        ],
      ]),
    );
  }
}
