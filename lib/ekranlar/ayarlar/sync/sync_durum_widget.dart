// lib/ekranlar/ayarlar/sync/sync_durum_widget.dart
// Bağımsız StatelessWidget — state değişkenleri parametre olarak gelir
import 'package:flutter/material.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';

class SyncProgressWidget extends StatelessWidget {
  final int progress;
  const SyncProgressWidget({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LinearProgressIndicator(
          value: progress / 100,
          minHeight: 12,
          backgroundColor: TsRenk.ayirac(context),
          valueColor: AlwaysStoppedAnimation<Color>(TsRenk.primary),
        ),
      ),
      const SizedBox(height: 6),
      Text('$progress%',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700,
            color: TsRenk.primary, fontSize: 15)),
    ]);
  }
}

class SyncDurumWidget extends StatelessWidget {
  final String durum;
  const SyncDurumWidget({super.key, required this.durum});

  @override
  Widget build(BuildContext context) {
    final basari = durum.startsWith('✅');
    final hata   = durum.startsWith('❌');
    final renk = basari ? TsRenk.basarili : hata ? TsRenk.hata : TsRenk.metinIkincil(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: renk.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: renk.withAlpha(60)),
      ),
      child: Text(durum, style: TextStyle(fontSize: 13, color: renk)),
    );
  }
}

class SyncStatKutu extends StatelessWidget {
  final String baslik, deger;
  final Color renk;
  const SyncStatKutu({super.key, required this.baslik, required this.deger, required this.renk});

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: renk.withAlpha(20),
        borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(deger, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: renk)),
        Text(baslik, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
      ]),
    ));
  }
}
