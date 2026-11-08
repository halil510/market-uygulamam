// lib/ekranlar/irsaliye/irsaliye_ekrani.dart  (Riverpod v2.2)
//
// DEĞIŞIKLIKLER:
//   - import provider kaldırıldı
//   - context.read<IrsaliyeNotifier>().listYukle() → ref.invalidate(irsaliyeListesiProvider)
//   - StatefulWidget → ConsumerStatefulWidget

import '../../cekirdek/utils/hata_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../saglayicilar/riverpod/irsaliye_provider.dart';
import 'irsaliye_detay_ekrani.dart';
import 'irsaliye_ekle_ekrani.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../widgetlar/masaustu/basit_liste_masaustu.dart';
import '../../widgetlar/masaustu/masaustu_tablo.dart';

export 'irsaliye_detay_ekrani.dart' show IrsaliyeDetayEkrani, eIrsaliyeGonderilmisMi;
export 'irsaliye_ekle_ekrani.dart' show IrsaliyeEkleEkrani;

class IrsaliyeEkrani extends ConsumerWidget {
  const IrsaliyeEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final irsaliyelerAsync = ref.watch(irsaliyeListesiProvider);
    final fmt = DateFormat('dd.MM.yyyy');
    // Masaüstü: tablo + Enter Aç / F1 Yeni (mobil kart listesi yerine).
    final masaustu = MediaQuery.sizeOf(context).width > 1100;
    final yetkili = ref.watch(authProvider.select((s) => s.isMudur));

    Future<void> yeni() async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IrsaliyeEkleEkrani()),
      );
      // Kullanıcı bu arada başka ekrana geçtiyse liste kapanmıştır.
      if (context.mounted) ref.invalidate(irsaliyeListesiProvider);
    }

    Future<void> ac(Map<String, dynamic> r) async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IrsaliyeDetayEkrani(irsaliyeId: r['id'] as int)),
      );
      if (context.mounted) ref.invalidate(irsaliyeListesiProvider);
    }

    String tarihMetni(Map<String, dynamic> r) => r['tarih'] != null
        ? fmt.format(DateTime.tryParse(r['tarih'].toString()) ?? DateTime.now())
        : '-';

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'İrsaliyeler',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(irsaliyeListesiProvider),
          ),
        ],
        geriTusu: false,
        modul: TsModul.belge,
      ),
      floatingActionButton: masaustu ? null : TsYetkili(child: FloatingActionButton.extended(
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: yeni,
        icon: const Icon(Icons.add),
        label: const Text('Yeni İrsaliye'),
      )),
      body: irsaliyelerAsync.when(
        loading: () => const TsYukleniyor(),
        error: (e, _) => BosEkran(ikon: Icons.inbox_outlined, baslik: 'Hata: ${bildirimMetniniSadelestir(e.toString())}'),
        data: (irsaliyeler) {
          if (masaustu) {
            return BasitListeMasaustu<Map<String, dynamic>>(
              satirlar: irsaliyeler,
              kolonlar: [
                TabloKolon(
                    baslik: 'İrsaliye No',
                    genislik: 170,
                    deger: (r) => r['irsaliye_no']?.toString() ?? '-',
                    sirala: (r) => r['irsaliye_no']?.toString() ?? ''),
                TabloKolon(
                    baslik: 'Tarih',
                    genislik: 110,
                    deger: tarihMetni,
                    sirala: (r) => r['tarih']?.toString() ?? ''),
                TabloKolon(
                    baslik: 'Cari',
                    genislik: 260,
                    esnek: true,
                    deger: (r) => r['cari_adi']?.toString() ?? 'Müşteri yok',
                    sirala: (r) => (r['cari_adi']?.toString() ?? '').toLowerCase()),
                TabloKolon(
                    baslik: 'Durum',
                    genislik: 130,
                    deger: (r) => r['durum']?.toString() ?? 'Bekliyor',
                    sirala: (r) => r['durum']?.toString() ?? '',
                    renk: (r) => r['durum']?.toString() == 'Teslim Edildi'
                        ? TsRenk.basarili
                        : TsRenk.uyari),
                TabloKolon(
                    baslik: 'Tutar',
                    genislik: 130,
                    sagaYasli: true,
                    deger: (r) => ParaUtils.formatla((r['toplam_tutar'] as num?)?.toDouble() ?? 0),
                    sirala: (r) => (r['toplam_tutar'] as num?) ?? 0),
              ],
              aramaMetniAl: (r) => '${r['irsaliye_no'] ?? ''} ${r['cari_adi'] ?? ''}',
              kayitEtiketi: 'İrsaliye',
              bosMesaj: yetkili ? 'Henüz irsaliye yok — F1 ile ekleyin' : 'Henüz irsaliye yok',
              onAc: ac,
              acEtiketi: 'Detay',
              onEkle: yetkili ? yeni : null,
            );
          }
          if (irsaliyeler.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_shipping_outlined, size: 60, color: context.textSecondary),
                const SizedBox(height: 12),
                const Text('Henüz irsaliye yok'),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(irsaliyeListesiProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: irsaliyeler.length,
              itemBuilder: (_, i) {
                final r     = irsaliyeler[i];
                final tarih = tarihMetni(r);
                final durum = r['durum']?.toString() ?? 'Bekliyor';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: context.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor)),
                  // Şeffaf Material: karta dokunma dalgası görünsün.
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                    leading: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                          color: TsRenk.zemin(TsRenk.vurguTurkuaz),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.local_shipping,
                          color: TsRenk.vurguTurkuaz, size: 22),
                    ),
                    title: Text(r['irsaliye_no']?.toString() ?? '-',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(
                      '${r['cari_adi'] ?? 'Müşteri yok'} • $tarih',
                      style: TextStyle(
                          fontSize: 12, color: context.textSecondary)),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          ParaUtils.formatla(
                              (r['toplam_tutar'] as num?)?.toDouble() ?? 0),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: durum == 'Teslim Edildi'
                                ? TsRenk.zemin(TsRenk.basarili)
                                : TsRenk.zemin(TsRenk.uyari),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(durum,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: durum == 'Teslim Edildi'
                                      ? TsRenk.basarili
                                      : TsRenk.uyari)),
                        ),
                      ],
                    ),
                    onTap: () => ac(r),
                  ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
