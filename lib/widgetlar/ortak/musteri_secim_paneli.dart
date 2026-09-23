// lib/widgetlar/ortak/musteri_secim_paneli.dart
//
// Cari seçim alt paneli (arama + liste) — Hızlı Satış ve Masa detayında
// ortak kullanılır. Hangi carilerin listeleneceğine çağıran karar verir
// (ör. masa yalnızca müşteri tipindekileri verir).
import 'package:flutter/material.dart';
import '../../modeller/cari_model.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

/// "Müşteri" veya "Hem Müşteri Hem Tedarikçi" tipindeki cariler için true.
bool cariMusteriMi(CariModel c) => c.cariTipi.toLowerCase().contains('üşteri');

class MusteriSecimPaneli extends StatefulWidget {
  final List<CariModel> cariler;
  final String baslik;
  const MusteriSecimPaneli({
    super.key,
    required this.cariler,
    this.baslik = 'Müşteri / Tedarikçi Seç',
  });

  @override
  State<MusteriSecimPaneli> createState() => _MusteriSecimPaneliState();
}

class _MusteriSecimPaneliState extends State<MusteriSecimPaneli> {
  final _araCtrl = TextEditingController();
  List<CariModel> _filtreli = [];

  @override
  void initState() {
    super.initState();
    _filtreli = widget.cariler;
    _araCtrl.addListener(_filtrele);
  }

  @override
  void dispose() { _araCtrl.dispose(); super.dispose(); }

  void _filtrele() {
    final q = _araCtrl.text.toLowerCase();
    setState(() {
      _filtreli = q.isEmpty
          ? widget.cariler
          : widget.cariler.where((c) =>
              c.unvan.toLowerCase().contains(q) ||
              (c.telefon?.contains(q) ?? false)).toList();
    });
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.7,
    minChildSize: 0.4,
    maxChildSize: 0.95,
    expand: false,
    builder: (_, ctrl) => DecoratedBox(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(color: context.borderColor,
                borderRadius: BorderRadius.circular(2))),
        Text(widget.baslik,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _araCtrl,
            decoration: const InputDecoration(
              hintText: 'Müşteri ara…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(child: _filtreli.isEmpty
            ? Center(child: Text('Cari bulunamadı',
                style: TextStyle(color: context.textHint)))
            : ListView.builder(
          controller: ctrl,
          itemCount: _filtreli.length,
          itemBuilder: (_, i) {
            final c = _filtreli[i];
            return ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF43A047)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(
                  c.unvan.isNotEmpty ? c.unvan[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: Colors.white),
                )),
              ),
              title: Row(children: [
                Flexible(child: Text(c.unvan, overflow: TextOverflow.ellipsis)),
                if (c.cariTipi.contains('edarik')) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x1A009688),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Tedarikçi',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: Color(0xFF00796B))),
                  ),
                ],
              ]),
              subtitle: Text(c.telefon ?? ''),
              onTap: () => Navigator.pop(context, c),
            );
          },
        )),
      ]),
    ),
  );
}
