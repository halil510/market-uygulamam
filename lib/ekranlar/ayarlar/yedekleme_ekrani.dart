// lib/ekranlar/ayarlar/yedekleme_ekrani.dart
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../servisler/yedekleme_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../veri/database/veritabani.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class YedeklemeEkrani extends ConsumerStatefulWidget {
  const YedeklemeEkrani({super.key});
  @override
  ConsumerState<YedeklemeEkrani> createState() => _YedeklemeEkraniState();
}

class _YedeklemeEkraniState extends ConsumerState<YedeklemeEkrani> {
  final _servis = YedeklemeServisi();

  List<YedekBilgi> _yedekler     = [];
  DateTime?        _sonOtomatik;
  bool             _yukleniyor   = true;
  bool             _isleniyor    = false;
  String           _sikligi      = 'gunluk';

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final liste = await _servis.yedekListesi();
      final son   = await _servis.sonOtomatikYedekTarihi();
      final db    = await Veritabani().db;
      final rows  = await db.query('ayarlar',
          where: "anahtar = 'yedek_sikligi'");
      final sikligi = rows.isEmpty
          ? 'gunluk' : rows.first['deger'] as String? ?? 'gunluk';
      if (!mounted) return;
      setState(() {
        _yedekler    = liste;
        _sonOtomatik = son;
        _sikligi     = sikligi;
        _yukleniyor  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _yedekAl() async {
    if (_isleniyor) return;
    setState(() => _isleniyor = true);
    try {
      final yol = await _servis.yedekAl();
      await _yukle();
      if (!mounted) return;
      BildirimServisi.basari(context, 'Yedek alındı ✓');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Yedek Alındı'),
          content: const Text('Yedeği paylaşmak ister misiniz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hayır')),
            FilledButton.icon(
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Paylaş'),
              onPressed: () { Navigator.pop(ctx); _servis.paylasYedek(yol); },
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yedek alınamadı: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  Future<void> _sikligiFDegistir(String deger) async {
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      await db.rawInsert(
        'INSERT OR REPLACE INTO ayarlar(anahtar, deger, guncelleme, last_updated) VALUES(?,?,?,?)',
        ['yedek_sikligi', deger, now, now],
      );
      // 🔴 Derin analizde bulundu: 'ayarlar' tablosu senkron
      // sisteminde olduğu halde bu yazım BulutManager'ı hiç çağırmıyordu.
      final satir = await db.query('ayarlar', where: 'anahtar = ?', whereArgs: ['yedek_sikligi'], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('ayarlar', Map<String, dynamic>.from(satir.first));
      if (!mounted) return;
      setState(() => _sikligi = deger);
      BildirimServisi.basari(context, 'Yedek sıklığı kaydedildi');
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _geriYukle(YedekBilgi y) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.orange), const SizedBox(width: 8),
          Text('Geri Yükle'),
        ]),
        content: Text('${y.tarihStr} tarihli yedek geri yüklenecek.\n\nMevcut veriler silinecek. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.orange),
            child: const Text('Geri Yükle'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    try {
      await _servis.yedekiGeriYukle(y.yol);
      if (mounted) BildirimServisi.basari(context,
          'Geri yükleme tamamlandı. Uygulamayı yeniden başlatın.');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<void> _sil(YedekBilgi y) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Yedeği Sil'),
        content: Text(y.dosyaAdi),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    try { await File(y.yol).delete(); } catch (e) { /* ignore */ }
    await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Yedekleme',
        aksiyonlar: [IconButton(icon: const Icon(Icons.refresh), onPressed: _yukle)],
        geriTusu: false,
        gradyanli: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : ListView(padding: const EdgeInsets.all(16), children: [

              // Durum + yedek al butonu
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade700, Colors.blue.shade900],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.backup, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Son Otomatik Yedek',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(
                        _sonOtomatik != null
                            ? DateFormat('dd.MM.yyyy HH:mm').format(_sonOtomatik!)
                            : 'Henüz yedek alınmadı',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ])),
                    Column(children: [
                      Text('${_yedekler.length}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const Text('yedek', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ]),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isleniyor ? null : _yedekAl,
                      icon: _isleniyor
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue))
                          : const Icon(Icons.backup),
                      label: Text(_isleniyor ? 'Yedekleniyor...' : 'Şimdi Yedek Al'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // Sıklık seçimi
              Container(
                decoration: BoxDecoration(
                  color: TsRenk.kart(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: TsRenk.ayirac(context)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Otomatik Yedek Sıklığı',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Her gece 23:30\'da kontrol edilir',
                        style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _siklikBtn('gunluk',   'Günlük',   Icons.today)),
                      const SizedBox(width: 10),
                      Expanded(child: _siklikBtn('haftalik', 'Haftalık', Icons.calendar_view_week)),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // Yedek listesi
              if (_yedekler.isEmpty)
                Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(children: [
                    Icon(Icons.folder_open, size: 56, color: TsRenk.ayirac(context)),
                    const SizedBox(height: 12),
                    Text('Henüz yedek yok',
                        style: TextStyle(color: TsRenk.metinIkincil(context))),
                  ]),
                ))
              else ...[
                Text('Yedekler (${_yedekler.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                ..._yedekler.map((y) => _yedekKarti(y)),
              ],
            ]),
    );
  }

  Widget _siklikBtn(String deger, String etiket, IconData ikon) {
    final secili = _sikligi == deger;
    return GestureDetector(
      onTap: () => _sikligiFDegistir(deger),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: secili ? Colors.blue.shade600 : TsRenk.arkaplan(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: secili ? Colors.blue.shade600 : TsRenk.ayirac(context)),
        ),
        child: Column(children: [
          Icon(ikon, color: secili ? Colors.white : TsRenk.metinIkincil(context), size: 22),
          const SizedBox(height: 4),
          Text(etiket, style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 12,
              color: secili ? Colors.white : TsRenk.metinIkincil(context))),
        ]),
      ),
    );
  }

  Widget _yedekKarti(YedekBilgi y) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: TsRenk.ayirac(context)),
    ),
    child: ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: y.otomatik ? Colors.green.shade50 : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          y.otomatik ? Icons.auto_mode : Icons.backup,
          color: y.otomatik ? Colors.green.shade600 : Colors.blue.shade600,
          size: 20,
        ),
      ),
      title: Text(y.tarihStr,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Row(children: [
        Text(y.otomatik ? 'Otomatik' : 'Manuel',
            style: TextStyle(fontSize: 11,
                color: y.otomatik ? Colors.green.shade600 : Colors.blue.shade600)),
        Text(' • ', style: TextStyle(fontSize: 11, color: context.textSecondary)),
        Text(y.boyutStr, style: TextStyle(fontSize: 11, color: context.textSecondary)),
      ]),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (v) {
          if (v == 'paylas') _servis.paylasYedek(y.yol);
          if (v == 'geri')   _geriYukle(y);
          if (v == 'sil')    _sil(y);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'paylas', child: Row(children: [
            Icon(Icons.share, size: 18), const SizedBox(width: 8), Text('Paylaş')])),
          const PopupMenuItem(value: 'geri', child: Row(children: [
            Icon(Icons.restore, size: 18, color: Colors.orange), const SizedBox(width: 8),
            Text('Geri Yükle', style: TextStyle(color: Colors.orange))])),
          const PopupMenuItem(value: 'sil', child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: Colors.red), const SizedBox(width: 8),
            Text('Sil', style: TextStyle(color: Colors.red))])),
        ],
      ),
    ),
  );
}
