// lib/ekranlar/satis/iade/iade_cari_dialog.dart
import 'package:flutter/material.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../modeller/cari_model.dart';
class CariSecDialog extends ConsumerStatefulWidget {
  final List<CariModel> cariler;
  const CariSecDialog({super.key, required this.cariler});
  @override
  ConsumerState<CariSecDialog> createState() => CariSecDialogState();
}

class CariSecDialogState extends ConsumerState<CariSecDialog> {
  final _ctrl = TextEditingController();
  List<CariModel> _filtreli = [];

  @override
  void initState() { super.initState(); _filtreli = widget.cariler; }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Müşteri Seç'),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 440,
        child: Column(children: [
          // Kayıtsız müşteri seçeneği
          InkWell(
            onTap: () {
              // Kayıtsız = null cari id ama özel marker
              Navigator.pop(context, CariModel(
                id: null, unvan: 'Kayıtsız Müşteri',
                bakiye: 0, cariTipi: 'Müşteri',
              ));
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                Icon(Icons.person_outline, color: Colors.orange.shade700),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Kayıtsız / Perakende Müşteri',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('Sadece kasa hareketi yapılır',
                      style: TextStyle(fontSize: 11, color: context.textSecondary)),
                ])),
                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.orange),
              ]),
            ),
          ),
          // Cari arama
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextField(
              controller: _ctrl,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Kayıtlı cari ara...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (q) {
                final ql = q.toLowerCase();
                setState(() {
                  _filtreli = q.isEmpty
                      ? widget.cariler
                      : widget.cariler.where((c) =>
                          c.unvan.toLowerCase().contains(ql) ||
                          (c.telefon?.contains(q) ?? false)).toList();
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _filtreli.isEmpty
                ? const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Cari bulunamadı')
                : ListView.builder(
                    itemCount: _filtreli.length,
                    itemBuilder: (_, i) {
                      final cari = _filtreli[i];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Color.fromARGB(31, 67, 97, 238),
                          child: Text(
                            cari.unvan.isNotEmpty ? cari.unvan[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF4361EE)),
                          ),
                        ),
                        title: Text(cari.unvan, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: cari.telefon != null
                            ? Text(cari.telefon!, style: const TextStyle(fontSize: 11))
                            : null,
                        onTap: () => Navigator.pop(context, cari),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
      ],
    );
  }
}
