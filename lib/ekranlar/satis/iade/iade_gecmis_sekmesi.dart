// lib/ekranlar/satis/iade/iade_gecmis_sekmesi.dart
//
// İade ekranının "Geçmiş" sekmesi ARAYÜZÜ (iade_ekrani_gecmis.dart'tan
// ayrıldı, 2026-10-07). Yalnız gösterir; tarih/cari seçimi, silme onayı ve
// yükleme ekranın kendisinde (bkz. _GecmisTabExt).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/cari_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';

class IadeGecmisSekmesi extends StatelessWidget {
  final DateTime? baslangic;
  final DateTime? bitis;
  final CariModel? cariFiltre;
  final bool yukleniyor;
  final List<Map<String, dynamic>> iadeler;
  final VoidCallback onBaslangicSec;
  final VoidCallback onBitisSec;
  final VoidCallback onCariSec;
  final VoidCallback onFiltreTemizle;
  final VoidCallback onYenile;
  final Future<bool> Function(Map<String, dynamic> iade) onSilOnay;
  final ValueChanged<Map<String, dynamic>> onSil;
  final ValueChanged<Map<String, dynamic>> onDetay;

  const IadeGecmisSekmesi({
    super.key,
    required this.baslangic,
    required this.bitis,
    required this.cariFiltre,
    required this.yukleniyor,
    required this.iadeler,
    required this.onBaslangicSec,
    required this.onBitisSec,
    required this.onCariSec,
    required this.onFiltreTemizle,
    required this.onYenile,
    required this.onSilOnay,
    required this.onSil,
    required this.onDetay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _GecmisFiltreleri(
        baslangic: baslangic,
        bitis: bitis,
        cariFiltre: cariFiltre,
        onBaslangicSec: onBaslangicSec,
        onBitisSec: onBitisSec,
        onCariSec: onCariSec,
        onTemizle: onFiltreTemizle,
        onYenile: onYenile,
      ),
      Expanded(child: _liste(context)),
    ]);
  }

  Widget _liste(BuildContext context) {
    if (yukleniyor) return const TsYukleniyor();
    if (iadeler.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.assignment_return, size: 56, color: TsRenk.ayirac(context)),
          const SizedBox(height: 12),
          Text('İade bulunamadı', style: TextStyle(color: context.textSecondary)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: iadeler.length,
      itemBuilder: (_, i) {
        final r = iadeler[i];
        return _GecmisSatiri(
          key: ValueKey('gecmis_${r['id']}'),
          iade: r,
          onSilOnay: () => onSilOnay(r),
          onSil: () => onSil(r),
          onTap: () => onDetay(r),
        );
      },
    );
  }
}

class _GecmisFiltreleri extends StatelessWidget {
  final DateTime? baslangic;
  final DateTime? bitis;
  final CariModel? cariFiltre;
  final VoidCallback onBaslangicSec;
  final VoidCallback onBitisSec;
  final VoidCallback onCariSec;
  final VoidCallback onTemizle;
  final VoidCallback onYenile;

  const _GecmisFiltreleri({
    required this.baslangic,
    required this.bitis,
    required this.cariFiltre,
    required this.onBaslangicSec,
    required this.onBitisSec,
    required this.onCariSec,
    required this.onTemizle,
    required this.onYenile,
  });

  static final _kisaTarih = DateFormat('dd.MM.yy');

  @override
  Widget build(BuildContext context) {
    const yazi = TextStyle(fontSize: 12);
    return Container(
      padding: const EdgeInsets.all(12),
      color: TsRenk.arkaplan(context),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(baslangic == null ? 'Başlangıç Tarihi' : _kisaTarih.format(baslangic!),
                  style: yazi),
              onPressed: onBaslangicSec,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month, size: 16),
              label: Text(bitis == null ? 'Bitiş Tarihi' : _kisaTarih.format(bitis!), style: yazi),
              onPressed: onBitisSec,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.person_search, size: 16),
              label: Text(cariFiltre?.unvan ?? 'Müşteri Filtre',
                  overflow: TextOverflow.ellipsis, style: yazi),
              onPressed: onCariSec,
            ),
          ),
          const SizedBox(width: 8),
          if (baslangic != null || cariFiltre != null)
            OutlinedButton(onPressed: onTemizle, child: const Text('Temizle', style: yazi)),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: onYenile),
        ]),
      ]),
    );
  }
}

/// Kaydırınca (onaylı) silinen tek bir geçmiş iade satırı.
class _GecmisSatiri extends StatelessWidget {
  final Map<String, dynamic> iade;
  final Future<bool> Function() onSilOnay;
  final VoidCallback onSil;
  final VoidCallback onTap;

  const _GecmisSatiri({
    super.key,
    required this.iade,
    required this.onSilOnay,
    required this.onSil,
    required this.onTap,
  });

  static final _uzunTarih = DateFormat('dd.MM.yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final r = iade;
    final tarih = DateTime.tryParse(r['tarih']?.toString() ?? '');
    final ikincil = TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context));
    return Dismissible(
      key: ValueKey('gecmis_${r['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration:
            BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.delete_outline, color: Colors.white, size: 26),
          Text('Sil', style: TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      ),
      confirmDismiss: (_) => onSilOnay(),
      onDismissed: (_) => onSil(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TsRenk.ayirac(context))),
        child: ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.uyari), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.assignment_return, color: Colors.orange, size: 22),
          ),
          title: Text(r['fis_no']?.toString() ?? 'İade #${r['id']}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (r['cari_adi'] != null) Text(r['cari_adi'].toString(), style: ikincil),
            if (tarih != null) Text(_uzunTarih.format(tarih), style: ikincil),
          ]),
          trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(ParaUtils.formatla((r['toplam_tutar'] as num?)?.toDouble() ?? 0),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13, color: Colors.orange)),
                Text('${r['kalem_sayisi'] ?? 0} kalem',
                    style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
              ]),
          onTap: onTap,
        ),
      ),
    );
  }
}
