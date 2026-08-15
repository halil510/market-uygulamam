// lib/ekranlar/masa/mutfak_ekrani.dart
// Mutfak / Bar Ekranı (Kitchen Display System)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../saglayicilar/riverpod/masa_provider.dart';

class MutfakEkrani extends ConsumerWidget {
  const MutfakEkrani({super.key});

  static const _durumSira = ['beklemede', 'hazirlaniyor', 'hazir', 'servis_edildi'];

  Color _durumRenk(String d) => switch (d) {
    'hazirlaniyor' => const Color(0xFFEF6C00),
    'hazir' => const Color(0xFF2E7D32),
    'servis_edildi' => const Color(0xFF9E9E9E),
    _ => const Color(0xFFD32F2F),
  };

  String _durumEtiket(String d) => switch (d) {
    'hazirlaniyor' => 'Hazırlanıyor',
    'hazir' => 'Hazır',
    'servis_edildi' => 'Servis Edildi',
    _ => 'Bekliyor',
  };

  IconData _durumIkon(String d) => switch (d) {
    'hazirlaniyor' => Icons.local_fire_department,
    'hazir' => Icons.check_circle_outline,
    'servis_edildi' => Icons.done_all,
    _ => Icons.notifications_active_outlined,
  };

  String _sonraki(String d) {
    final i = _durumSira.indexOf(d);
    return _durumSira[(i + 1).clamp(0, _durumSira.length - 1)];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durum = ref.watch(mutfakProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: const Row(children: [
          Icon(Icons.soup_kitchen_outlined, size: 22),
          SizedBox(width: 8),
          Text('Mutfak / Bar'),
        ]),
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(mutfakProvider.notifier).yukle(),
          ),
        ],
        modul: TsModul.mutfak,
      ),
      body: durum.when(
        loading: () => const Center(child: AppYukleniyor()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (d) {
          final aktifSiparisler = d.siparisler.where((s) =>
              s.kalemler.any((k) => k.durum != 'servis_edildi')).toList();

          if (aktifSiparisler.isEmpty) {
            return const TsBosDurum(
              ikon: Icons.local_cafe_outlined,
              baslik: 'Bekleyen sipariş yok',
              altyazi: 'Yeni sipariş geldiğinde burada görünecek',
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(mutfakProvider.notifier).yukle(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Önceki sabit-oranlı GridView her karta AYNI yüksekliği
                // veriyordu — 1 kalemlik sipariş de, 12 kalemlik sipariş
                // de aynı kutuydu (biri boşlukla dolu, diğeri kendi
                // içinde kaydırma gerektiriyordu). MasonryGridView her
                // kartın kendi içeriğine göre boy vermesini sağlar.
                final kolonSayisi = (constraints.maxWidth / 380).floor().clamp(1, 6);
                return MasonryGridView.count(
                  padding: const EdgeInsets.all(12),
                  crossAxisCount: kolonSayisi,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  itemCount: aktifSiparisler.length,
                  itemBuilder: (_, i) {
                    final s = aktifSiparisler[i];
                    final masaAdi = d.masaAdlari[s.masaId] ?? 'Masa #${s.masaId}';
                    final aktifKalemler = s.kalemler.where((k) => k.durum != 'servis_edildi').toList();
                    final fark = DateTime.now().difference(s.acilisZamani);
                    final beklenenUzun = fark.inMinutes > 20;

                    return Container(
                      decoration: BoxDecoration(
                        color: TsRenk.kart(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: beklenenUzun ? Colors.red.shade300 : TsRenk.ayirac(context),
                          width: beklenenUzun ? 1.5 : 1,
                        ),
                        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        // Başlık
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: beklenenUzun ? Colors.red.shade700 : const Color(0xFF6D4C41),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.table_restaurant, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Expanded(child: Text(masaAdi,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: beklenenUzun ? Colors.red.shade400 : Colors.white24,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${fark.inMinutes} dk',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        ),
                        // Kalemler — sabit yükseklikli Expanded+ListView yerine
                        // içeriğe göre boy veren ListView (shrinkWrap).
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(8),
                          itemCount: aktifKalemler.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, j) {
                            final k = aktifKalemler[j];
                            final renk = _durumRenk(k.durum);
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              leading: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: renk.withAlpha(26),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(child: Text(
                                  k.miktar.toStringAsFixed(k.miktar == k.miktar.roundToDouble() ? 0 : 1),
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: renk),
                                )),
                              ),
                              title: Text(k.urunAdi,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              subtitle: k.not_ != null && k.not_!.isNotEmpty
                                  ? Text('Not: ${k.not_}',
                                      style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontStyle: FontStyle.italic))
                                  : null,
                              trailing: GestureDetector(
                                onTap: () => ref.read(mutfakProvider.notifier).kalemDurumGuncelle(k.id!, _sonraki(k.durum)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: renk.withAlpha(26),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(_durumIkon(k.durum), size: 14, color: renk),
                                    const SizedBox(width: 4),
                                    Text(_durumEtiket(k.durum),
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
                      ]),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}