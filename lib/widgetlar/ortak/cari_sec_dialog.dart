// lib/widgetlar/ortak/cari_sec_dialog.dart
//
// Ortak cari seçim diyaloğu (CLAUDE.md §4.7). Önceden İade
// (ekranlar/satis/iade/iade_cari_dialog.dart) ve Alım (_tedarikciSec içinde
// StatefulBuilder + elle yazılmış Türkçe normalize kopyası) ayrı ayrı
// yazıyordu. Alt panel biçimli seçici: [MusteriSecimPaneli]; ikisi de
// aramada [cariFiltrele]'yi kullanır.
import 'package:flutter/material.dart';
import 'package:market_plus/cekirdek/utils/metin_arama.dart';
import '../../modeller/cari_model.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'app_widgetlar.dart';

/// Cari arama süzgeci — ünvanda Türkçe karakter/büyük-küçük harf duyarsız
/// ([aramaNormalize]), telefonda düz içerme. Boş/boşluk sorgu → tüm liste.
List<CariModel> cariFiltrele(List<CariModel> cariler, String sorgu) {
  final q = sorgu.trim();
  if (q.isEmpty) return cariler;
  final qn = aramaNormalize(q);
  return cariler
      .where((c) =>
          aramaNormalize(c.unvan).contains(qn) ||
          (c.telefon?.contains(q) ?? false))
      .toList();
}

/// "Kayıtsız / Perakende Müşteri" seçildiğinde dönen işaretçi model
/// (id == null).
const kayitsizMusteri = CariModel(
  id: null, unvan: 'Kayıtsız Müşteri', bakiye: 0, cariTipi: 'Müşteri',
);

class CariSecDialog extends StatefulWidget {
  final List<CariModel> cariler;
  final String baslik;
  final IconData? baslikIkonu;
  final String aramaIpucu;
  /// Listenin üstünde "Kayıtsız / Perakende Müşteri" seçeneği gösterilsin
  /// mi (seçilirse [kayitsizMusteri] döner).
  final bool kayitsizSecenegi;
  /// Hiç cari yokken arama kutusu yerine gösterilecek mesaj; null ise
  /// arama kutusu her zaman gösterilir.
  final String? bosListeMesaji;
  final String eslesmeYokMesaji;
  final Color vurguRengi;
  final double yukseklik;

  const CariSecDialog({
    super.key,
    required this.cariler,
    this.baslik = 'Müşteri Seç',
    this.baslikIkonu = Icons.person_search_outlined,
    this.aramaIpucu = 'Kayıtlı cari ara...',
    this.kayitsizSecenegi = true,
    this.bosListeMesaji,
    this.eslesmeYokMesaji = 'Cari bulunamadı',
    this.vurguRengi = TsRenk.primary,
    this.yukseklik = 440,
  });

  @override
  State<CariSecDialog> createState() => _CariSecDialogState();
}

class _CariSecDialogState extends State<CariSecDialog> {
  final _ctrl = TextEditingController();
  List<CariModel> _filtreli = [];

  @override
  void initState() { super.initState(); _filtreli = widget.cariler; }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Widget _kayitsizKarti() => InkWell(
        onTap: () => Navigator.pop(context, kayitsizMusteri),
        child: Container(
          margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: TsRenk.uyari.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TsRenk.uyari.withAlpha(70)),
          ),
          child: Row(children: [
            const Icon(Icons.person_outline, color: TsRenk.uyari),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kayıtsız / Perakende Müşteri',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text('Sadece kasa hareketi yapılır',
                  style: TextStyle(fontSize: 11, color: context.textSecondary)),
            ])),
            const Icon(Icons.arrow_forward_ios, size: 14, color: TsRenk.uyari),
          ]),
        ),
      );

  Widget _liste() => _filtreli.isEmpty
      ? BosEkran(ikon: Icons.inbox_outlined, baslik: widget.eslesmeYokMesaji)
      : ListView.builder(
          itemCount: _filtreli.length,
          itemBuilder: (_, i) {
            final cari = _filtreli[i];
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: widget.vurguRengi.withAlpha(31),
                child: Text(
                  cari.unvan.isNotEmpty ? cari.unvan[0].toUpperCase() : '?',
                  style: TsMetin.kucukVurgu.copyWith(color: widget.vurguRengi),
                ),
              ),
              title: Text(cari.unvan,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: cari.telefon != null
                  ? Text(cari.telefon!, style: const TextStyle(fontSize: 11))
                  : null,
              onTap: () => Navigator.pop(context, cari),
            );
          },
        );

  @override
  Widget build(BuildContext context) {
    final bos = widget.cariler.isEmpty && widget.bosListeMesaji != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: widget.baslikIkonu == null
          ? Text(widget.baslik)
          : Row(children: [
              Icon(widget.baslikIkonu, color: widget.vurguRengi, size: 20),
              const SizedBox(width: 8),
              Text(widget.baslik),
            ]),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: widget.yukseklik,
        child: Column(children: [
          if (widget.kayitsizSecenegi) _kayitsizKarti(),
          if (bos)
            Expanded(child: Center(
                child: Text(widget.bosListeMesaji!, textAlign: TextAlign.center)))
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _ctrl,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: widget.aramaIpucu,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10))),
                  isDense: true,
                ),
                onChanged: (q) =>
                    setState(() => _filtreli = cariFiltrele(widget.cariler, q)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _liste()),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
      ],
    );
  }
}
