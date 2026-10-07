// lib/ekranlar/vardiya/widgets/vardiya_gecmis_mobil_liste.dart
//
// Geçmiş vardiyaların telefon/tablet listesi — vardiya_ekrani.dart'tan
// ayrıldı (2026-10-07 refactor). Masaüstü karşılığı:
// masaustu/vardiya_gecmis_masaustu_gorunum.dart (aynı parametreler).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../cekirdek/utils/para_utils.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';

class VardiyaGecmisMobilListe extends StatelessWidget {
  final List<Map<String, dynamic>> vardiyalar;
  final String Function(String? bas, String? bit) sureMetni;
  final void Function(Map<String, dynamic> vardiya) onPdf;
  final bool dahaVarMi, dahaYukleniyor;
  final VoidCallback onDahaFazla;

  const VardiyaGecmisMobilListe({
    super.key,
    required this.vardiyalar,
    required this.sureMetni,
    required this.onPdf,
    required this.dahaVarMi,
    required this.dahaYukleniyor,
    required this.onDahaFazla,
  });

  static final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: vardiyalar.length + (dahaVarMi ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i >= vardiyalar.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: dahaYukleniyor
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton.icon(
                      onPressed: onDahaFazla,
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Daha Fazla Yükle'),
                    ),
            ),
          );
        }
        final v = vardiyalar[i];
        final bas = DateTime.tryParse(v['acilis_tarihi']?.toString() ?? '');
        final bit = DateTime.tryParse(v['kapanis_tarihi']?.toString() ?? '');
        final fark = (v['fark'] as num?)?.toDouble() ?? 0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.person_outline,
                  size: 16, color: context.textSecondary),
              const SizedBox(width: 4),
              Text(v['ad_soyad']?.toString() ?? '—',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined,
                    size: 20, color: Colors.red),
                tooltip: 'PDF Rapor',
                onPressed: () => onPdf(v),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
                '${bas != null ? _fmt.format(bas) : '—'}  →  ${bit != null ? _fmt.format(bit) : '—'}',
                style:
                    TextStyle(fontSize: 11, color: context.textSecondary)),
            // Madde 12 denetimi (2026-09-16) — Müdür Onayı: kapatan kişi
            // Müdür/Admin değilse burada kim onayladığı görünür.
            if (v['onaylayan_adi'] != null) ...[
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.verified_user_outlined, size: 12, color: Colors.deepPurple.shade300),
                const SizedBox(width: 4),
                Text('Onaylayan: ${v['onaylayan_adi']}',
                    style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade300)),
              ]),
            ],
            const SizedBox(height: 8),
            Row(children: [
              _chip(
                  sureMetni(v['acilis_tarihi']?.toString(),
                      v['kapanis_tarihi']?.toString()),
                  Icons.timer_outlined,
                  Colors.blue.shade700),
              const SizedBox(width: 6),
              _chip(
                  ParaUtils.formatla(
                      (v['bitis_bakiye'] as num?)?.toDouble() ?? 0),
                  Icons.account_balance_wallet_outlined,
                  Colors.green.shade700),
              const SizedBox(width: 6),
              if (fark.abs() > 0.01)
                _chip(
                    '${fark > 0 ? '+' : ''}${ParaUtils.formatla(fark)}',
                    fark > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    fark > 0 ? Colors.blue.shade700 : Colors.red.shade700),
            ]),
          ]),
        );
      },
    );
  }

  static Widget _chip(String metin, IconData ikon, Color renk) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: renk.withAlpha(20),
            borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon, size: 12, color: renk),
          const SizedBox(width: 3),
          Text(metin,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: renk)),
        ]),
      );
}
