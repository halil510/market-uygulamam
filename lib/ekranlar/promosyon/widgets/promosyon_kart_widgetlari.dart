// lib/ekranlar/promosyon/widgets/promosyon_kart_widgetlari.dart
//
// Promosyon listesi kartı ve küçük rozetler — promosyon_ekrani.dart'tan
// ayrıldı (2026-10-07 refactor).
import 'package:flutter/foundation.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../modeller/promosyon_model.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';

/// İndirim oranını en çok 3 ondalıkla (gereksiz sıfırsız, virgüllü) gösterir:
/// 16.6667 → "16,667", 10.0 → "10".
String promosyonOranMetni(double o) {
  var t = o.toStringAsFixed(3);
  if (t.contains('.')) {
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return t.replaceAll('.', ',');
}

class PromosyonKarti extends StatelessWidget {
  final PromosyonModel promosyon;
  final VoidCallback onToggle, onSil, onDuzenle;
  const PromosyonKarti({super.key, required this.promosyon, required this.onToggle, required this.onSil, required this.onDuzenle});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');
    final now = DateTime.now();
    final suresiDoldu = promosyon.bitisTarihi != null && promosyon.bitisTarihi!.isBefore(now);
    final renk = suresiDoldu ? context.textSecondary
        : promosyon.aktif ? Colors.green.shade700 : Colors.orange.shade700;
    final etiket = suresiDoldu ? 'Süresi Doldu' : promosyon.aktif ? 'Aktif' : 'Pasif';

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: promosyon.aktif && !suresiDoldu
            ? Colors.green.shade200 : context.borderColor),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: GestureDetector(
        onTap: onDuzenle,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(promosyon.promosyonAdi,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (promosyon.urunAdi.isNotEmpty)
              Text('Ürün: ${promosyon.urunAdi}',
                  style: TextStyle(fontSize: 12, color: context.textSecondary)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: renk.withAlpha(26), borderRadius: BorderRadius.circular(12)),
            child: Text(etiket, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
          ),
          const SizedBox(width: 4),
          TsYetkili(child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) {
              if (v == 'duzenle') onDuzenle();
              if (v == 'toggle') onToggle();
              if (v == 'sil') onSil();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'duzenle',
                  child: Row(children: [Icon(Icons.edit_outlined, size: 16, color: Colors.blue), SizedBox(width: 8), Text('Düzenle')])),
              PopupMenuItem(value: 'toggle',
                  child: Text(promosyon.aktif ? 'Pasife Al' : 'Aktife Al')),
              const PopupMenuItem(value: 'sil',
                  child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8), Text('Sil', style: TextStyle(color: Colors.red))])),
            ],
          )),
        ]),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(children: [
          PromosyonBilgiChip(Icons.discount, '%${promosyonOranMetni(promosyon.iskontoOran)} İndirim', Colors.orange.shade700),
          const SizedBox(width: 8),
          PromosyonBilgiChip(Icons.production_quantity_limits, 'Min: ${promosyon.minMiktar.toStringAsFixed(0)}', Colors.blue.shade700),
        ]),
        if (promosyon.baslangicTarihi != null || promosyon.bitisTarihi != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.calendar_today, size: 12, color: context.textSecondary),
            const SizedBox(width: 4),
            Text(
              [
                if (promosyon.baslangicTarihi != null) fmt.format(promosyon.baslangicTarihi!),
                if (promosyon.bitisTarihi != null) fmt.format(promosyon.bitisTarihi!),
              ].join(' – '),
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ]),
        ],
      ]),
      ),
    );
  }
}

class PromosyonBilgiChip extends StatelessWidget {
  final IconData ikon; final String metin; final Color renk;
  const PromosyonBilgiChip(this.ikon, this.metin, this.renk, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: renk.withAlpha(20), borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ikon, size: 12, color: renk),
      const SizedBox(width: 4),
      Text(metin, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: renk)),
    ]),
  );
}

class PromosyonChip extends StatelessWidget {
  final String metin; final Color renk;
  const PromosyonChip(this.metin, this.renk, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: renk.withAlpha(26), borderRadius: BorderRadius.circular(12)),
    child: Text(metin, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: renk)),
  );
}

class PromosyonHesapKutu extends StatelessWidget {
  final String baslik, deger; final Color renk;
  const PromosyonHesapKutu(this.baslik, this.deger, this.renk, {super.key});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(baslik, style: TextStyle(fontSize: 9, color: renk.withAlpha(180))),
    Text(deger, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: renk)),
  ]);
}
