// lib/ekranlar/satis/iade/iade_gecmis_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';

class IadeGecmisWidget extends StatelessWidget {
  final List<Map<String, dynamic>> iadeListesi;
  final int? duzenlemeModu_iadeId;
  final String? duzenlemeModu_fisNo;
  final Future<bool?> Function(Map<String, dynamic>) onSilOnay;
  final void Function(int, Map<String, dynamic>) onSil;
  final void Function(int, Map<String, dynamic>) onDuzenle;
  final VoidCallback onExcel;

  const IadeGecmisWidget({
    super.key,
    required this.iadeListesi,
    required this.duzenlemeModu_iadeId,
    required this.duzenlemeModu_fisNo,
    required this.onSilOnay,
    required this.onSil,
    required this.onDuzenle,
    required this.onExcel,
  });

  static const _green = TsRenk.basarili;

  @override
  Widget build(BuildContext context) {
    // ÖNCEDEN BURADA CİDDİ BİR KARANLIK MOD HATASI VARDI: metin renkleri
    // (_textD/_textL) ve kart arkaplanı (_card = beyaz) sabit/açık-mod
    // renkleriydi. Karanlık modda, koyu metin koyu arkaplan üzerinde
    // neredeyse görünmez oluyor, kart da parlak beyaz bir kutu olarak
    // uygulamanın geri kalanından kopuk görünüyordu. Artık context'e
    // duyarlı TsRenk tokenları kullanılıyor.
    final textD = TsRenk.metinBirincil(context);
    final textL = TsRenk.metinIkincil(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(
          duzenlemeModu_iadeId != null
              ? 'Fiş: $duzenlemeModu_fisNo Kalemleri (${iadeListesi.length})'
              : 'Bu Oturumdaki İadeler (${iadeListesi.length})',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textD)),
        TextButton.icon(
          icon: const Icon(Icons.download, size: 14),
          label: const Text('Excel', style: TextStyle(fontSize: 12)),
          onPressed: onExcel,
        ),
      ]),
      const SizedBox(height: 8),
      if (iadeListesi.isEmpty)
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(children: [
            Icon(Icons.inbox_outlined, size: 28, color: textL.withAlpha(150)),
            const SizedBox(height: 8),
            Text(
              duzenlemeModu_iadeId != null
                  ? 'Fişe kalem eklemek için yukarıdan ürün seçin'
                  : 'Bu oturumda henüz iade yapılmadı',
              style: TextStyle(fontSize: 12, color: textL),
              textAlign: TextAlign.center,
            ),
          ]),
        ))
      else
        ...iadeListesi.asMap().entries.map((entry) {
          final idx  = entry.key;
          final iade = entry.value;
          return Dismissible(
            key: ValueKey('${iade['iade_id'] ?? ''}_${iade['kalem_id'] ?? idx}_$idx'),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.delete_outline, color: Colors.white, size: 26),
                SizedBox(height: 2),
                Text('Sil', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
            confirmDismiss: (_) => onSilOnay(iade),
            onDismissed: (_) => onSil(idx, iade),
            child: GestureDetector(
              onTap: () => onDuzenle(idx, iade),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TsKart(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _green.withAlpha(26),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.assignment_return, color: _green, size: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(iade['urun_adi'] as String? ?? '',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textD)),
                    Text(
                      '${iade['musteri_adi']} • '
                      '${DateFormat('HH:mm').format(iade['tarih'] as DateTime)} • '
                      '${iade['fis_no'] ?? ''}',
                      style: TextStyle(fontSize: 11, color: textL)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('+${(iade['miktar'] as double).toStringAsFixed(0)} adet',
                        style: const TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w600)),
                    Text(ParaUtils.formatla(iade['toplam_tutar'] as double? ?? 0),
                        style: TextStyle(fontSize: 11, color: textL)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit_outlined, size: 12, color: textL),
                      const SizedBox(width: 2),
                      Text('Düzenle', style: TextStyle(fontSize: 10, color: textL)),
                    ]),
                  ]),
                ]),
              ),
              ),
            ),
          );
        }),
    ]);
  }
}
