// lib/ekranlar/vardiya/widgets/vardiya_kartlari.dart
//
// Vardiya ekranının durum kartı, KPI kutusu ve özet satırı —
// vardiya_ekrani.dart'tan ayrıldı (2026-10-07 refactor).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';

class VardiyaOzetSatir extends StatelessWidget {
  final String etiket, deger;
  final bool bold;
  const VardiyaOzetSatir(this.etiket, this.deger, {super.key, this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(etiket,
              style:
                  TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
          const Spacer(),
          Text(deger,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );
}

class VardiyaKpi extends StatelessWidget {
  final String baslik, deger;
  final IconData ikon;
  final Color renk;
  const VardiyaKpi(this.baslik, this.deger, this.ikon, this.renk, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ikon, color: renk, size: 16),
            const SizedBox(width: 4),
            Text(baslik,
                style: TextStyle(
                    fontSize: 11, color: TsRenk.metinIkincil(context))),
          ]),
          const Spacer(),
          Text(deger,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: renk)),
        ]),
      );
}

class VardiyaDurumKart extends StatelessWidget {
  final Map<String, dynamic>? aktif;
  final DateFormat fmt;
  final String sure;
  final VoidCallback onAc, onKapat;
  const VardiyaDurumKart(
      {super.key,
      required this.aktif,
      required this.fmt,
      required this.sure,
      required this.onAc,
      required this.onKapat});

  @override
  Widget build(BuildContext context) {
    final acik = aktif != null;
    final bas = DateTime.tryParse(aktif?['acilis_tarihi']?.toString() ?? '');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: acik
                ? [Colors.green.shade700, Colors.green.shade500]
                : [context.textSecondary, TsRenk.arkaplan(context)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: (acik ? Colors.green : context.textSecondary).withAlpha(76),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(acik ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: Colors.white, size: 28),
          const SizedBox(width: 10),
          Text(acik ? 'Vardiya Açık' : 'Vardiya Kapalı',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(20)),
            child: Text(acik ? '🟢 Aktif' : '🔴 Kapalı',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ]),
        if (acik && bas != null) ...[
          const SizedBox(height: 12),
          Text('Başlangıç: ${fmt.format(bas)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text('Süre: $sure',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (aktif?['ad_soyad'] != null)
            Text('Personel: ${aktif!['ad_soyad']}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: acik ? onKapat : onAc,
            icon: Icon(acik ? Icons.lock_rounded : Icons.lock_open_rounded),
            label: Text(acik ? 'Vardiyayı Kapat' : 'Vardiya Aç',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: acik ? Colors.orange : Colors.green,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}
