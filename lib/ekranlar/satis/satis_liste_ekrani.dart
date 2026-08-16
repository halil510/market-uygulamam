// lib/ekranlar/satis/satis_liste_ekrani.dart  (Riverpod versiyonu)
//
// DEĞIŞIKLIKLER:
//   - StatefulWidget → ConsumerStatefulWidget
//   - SatisListeNotifier → satislarProvider
//   - context.read/watch → ref.read/watch

import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../widgetlar/ortak/bulut_durum_widget.dart';
import '../../servisler/bildirim_servisi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../saglayicilar/riverpod/satis_provider.dart';
import '../../modeller/satis_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class SatisListeEkrani extends ConsumerStatefulWidget {
  const SatisListeEkrani({super.key});

  @override
  ConsumerState<SatisListeEkrani> createState() => _SatisListeEkraniState();
}

class _SatisListeEkraniState extends ConsumerState<SatisListeEkrani> {
  final _araCtrl = TextEditingController();
  Timer? _araDebounce;

  @override
  void initState() {
    super.initState();
    _araCtrl.addListener(_aramaChanged);
  }

  @override
  void dispose() {
    _araDebounce?.cancel();
    _araCtrl.dispose();
    super.dispose();
  }

  void _aramaChanged() {
    _araDebounce?.cancel();
    _araDebounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(satisFiltresiProvider.notifier)
          .aramaGuncelle(_araCtrl.text);
    });
  }

  Future<void> _tarihSec() async {
    final filtre  = ref.read(satisFiltresiProvider);
    final secilen = await showDateRangePicker(
      context:     context,
      firstDate:   DateTime(2020),
      lastDate:    DateTime.now(),
      initialDateRange: DateTimeRange(
          start: filtre.basTarih, end: filtre.bitTarih),
      locale: const Locale('tr', 'TR'),
    );
    if (secilen != null) {
      ref.read(satisFiltresiProvider.notifier)
          .tarihAyarla(secilen.start, secilen.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final durum   = ref.watch(satislarProvider);
    final filtre  = ref.watch(satisFiltresiProvider);
    final fmt     = DateFormat('dd.MM.yyyy');

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Satış Listesi',
        aksiyonlar: [
              const BulutDurumIkonu(),
          if (durum.secimModu) ...[
            TextButton.icon(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              label: Text('${durum.seciliSayisi} seçili',
                  style: const TextStyle(color: Colors.white)),
              onPressed: () =>
                  ref.read(satislarProvider.notifier).secimTemizle(),
            ),
            TsYetkili(child: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Seçilenleri Sil',
              onPressed: () async {
                final onay = await showDialog<bool>(context: context,
                  builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Satışları İptal Et'),
                    content: Text('${durum.seciliSayisi} satış iptal edilecek. Devam?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Onayla')),
                    ],
                  ));
                if (onay == true && mounted) {
                  await ref.read(satislarProvider.notifier).seciliSil();
                  if (mounted) BildirimServisi.basari(context, 'Satışlar iptal edildi');
                }
              }),
            ),
          ]
          else ...[
            IconButton(
              icon: const Icon(Icons.date_range),
              onPressed: _tarihSec,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  ref.read(satislarProvider.notifier).yukle(),
            ),
          ],
        ],
      ),
      body: Column(children: [
        // Tarih + Arama bar
        Container(
          color: context.cardBg,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            // Tarih aralığı
            GestureDetector(
              onTap: _tarihSec,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Color.fromARGB(15, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: AppRenkler.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${fmt.format(filtre.basTarih)} – ${fmt.format(filtre.bitTarih)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500,
                        color: AppRenkler.primary),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_drop_down, color: AppRenkler.primary),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            // Arama
            TextField(
              controller: _araCtrl,
              decoration: InputDecoration(
                hintText: 'Fiş no veya müşteri ara...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _araCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _araCtrl.clear();
                          ref.read(satisFiltresiProvider.notifier)
                              .aramaGuncelle('');
                        })
                    : null,
                filled:    true,
                fillColor: context.inputFill,
                border:    OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ]),
        ),

        // İstatistik şeridi
        if (!durum.yukleniyor && durum.satislar.isNotEmpty)
          _IstatistikSeridi(satislar: durum.satislar),

        // Seçim modu özet
        if (durum.secimModu)
          Container(
            color: Color.fromARGB(20, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Text('Seçili toplam: ${ParaUtils.formatla(durum.seciliToplam)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppRenkler.primary)),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(satislarProvider.notifier).tumunuSec(),
                child: const Text('Tümünü Seç'),
              ),
            ]),
          ),

        // Liste
        Expanded(
          child: durum.yukleniyor
              ? const Center(child: const AppYukleniyor())
              : durum.satislar.isEmpty
                  ? _BosEkran()
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.read(satislarProvider.notifier).yukle(),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        itemCount: durum.satislar.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) => _SatisKarti(
                          satis:    durum.satislar[i],
                          secili:   durum.seciliIds.contains(durum.satislar[i].id),
                          secimModu: durum.secimModu,
                          onTap: () {
                            if (durum.secimModu) {
                              ref.read(satislarProvider.notifier)
                                  .secimToggle(durum.satislar[i].id!);
                            } else {
                              context.push('/satis/detay/${durum.satislar[i].id}');
                            }
                          },
                          onLongPress: () => ref
                              .read(satislarProvider.notifier)
                              .secimToggle(durum.satislar[i].id!),
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ── İstatistik Şeridi ─────────────────────────────────────────────────────────

class _IstatistikSeridi extends StatelessWidget {
  final List<SatisModel> satislar;
  const _IstatistikSeridi({required this.satislar});

  @override
  Widget build(BuildContext context) {
    final toplam = satislar.fold(0.0, (s, m) => s + m.genelToplam);
    final iptalli = satislar.where((s) => s.iptal).length;

    return Container(
      // 🔴 DÜZELTME: sabit beyazdı — koyu temada beyaz şerit oluşuyordu.
      color: context.cardBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        _StatBadge('${satislar.length} Satış', Colors.blue.shade700),
        const SizedBox(width: 8),
        _StatBadge(ParaUtils.formatla(toplam), Colors.green.shade700),
        if (iptalli > 0) ...[
          const SizedBox(width: 8),
          _StatBadge('$iptalli İptal', Colors.red.shade700),
        ],
      ]),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String metin;
  final Color renk;
  const _StatBadge(this.metin, this.renk);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Color.fromARGB(26, renk.red, renk.green, renk.blue),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(metin,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: renk)),
  );
}

// ── Satış Kartı ───────────────────────────────────────────────────────────────

class _SatisKarti extends StatelessWidget {
  final SatisModel satis;
  final bool       secili;
  final bool       secimModu;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SatisKarti({
    required this.satis,
    required this.secili,
    required this.secimModu,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final fmt    = DateFormat('dd.MM.yyyy HH:mm');
    final iptal  = satis.iptal;

    return TsKart(
      onTap: onTap,
      onLongPress: onLongPress,
      secili: secili,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
            // Checkbox (seçim modu)
            if (secimModu) ...[
              Icon(
                secili ? Icons.check_circle : Icons.radio_button_unchecked,
                color: secili ? AppRenkler.primary : context.textSecondary,
                size: 22,
              ),
              const SizedBox(width: 10),
            ],

            // Sol ikon
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: iptal
                    ? Colors.red.shade50
                    : Color.fromARGB(20, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                iptal ? Icons.cancel_outlined : Icons.receipt_outlined,
                color: iptal ? Colors.red.shade600 : AppRenkler.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Ortada bilgi
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  // Fiş tipi ikonu
                  Container(
                    padding: const EdgeInsets.all(3),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: iptal ? Colors.red.shade50
                          : (satis.fisTipi == 'İade' ? Colors.orange.shade50
                              : Colors.blue.shade50),
                      borderRadius: BorderRadius.circular(4)),
                    child: Icon(
                      iptal ? Icons.cancel_outlined
                          : (satis.fisTipi == 'İade' ? Icons.undo_outlined
                              : Icons.receipt_outlined),
                      size: 12,
                      color: iptal ? Colors.red.shade700
                          : (satis.fisTipi == 'İade' ? Colors.orange.shade700
                              : Colors.blue.shade700)),
                  ),
                  // Fiş no - kısa format
                  Flexible(child: Text(
                    ParaUtils.kisaFisNo(satis.fisNo),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    overflow: TextOverflow.ellipsis)),
                  if (iptal) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text('İPTAL',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                              color: Colors.red.shade700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(fmt.format(satis.tarih),
                    style: TextStyle(
                        fontSize: 11, color: context.textSecondary)),
                if (satis.cariAdi != null && satis.cariAdi!.isNotEmpty)
                  Text(satis.cariAdi!,
                      style: TextStyle(
                          fontSize: 11, color: context.textSecondary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            )),

            // Sağda tutar
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                ParaUtils.formatla(satis.genelToplam),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: iptal ? context.textSecondary : AppRenkler.primary,
                ),
              ),
              Text(satis.odemeYontemi ?? '',
                  style: TextStyle(
                      fontSize: 11, color: context.textSecondary)),
            ]),
          ]),
    );
  }
}

// ── Boş Ekran ─────────────────────────────────────────────────────────────────

class _BosEkran extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const TsBosDurum(
    ikon: Icons.receipt_long_outlined,
    baslik: 'Bu tarih aralığında satış yok',
  );
}
