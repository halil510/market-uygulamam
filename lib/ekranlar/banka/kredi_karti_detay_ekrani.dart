// lib/ekranlar/banka/kredi_karti_detay_ekrani.dart
import 'package:flutter/material.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../saglayicilar/riverpod/borc_provider.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../depolar/kredi_karti_deposu.dart';
import '../../modeller/kredi_karti_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/ts_yetki.dart';

class KrediKartiDetayEkrani extends ConsumerStatefulWidget {
  final int kartId;
  const KrediKartiDetayEkrani({super.key, required this.kartId});

  @override
  ConsumerState<KrediKartiDetayEkrani> createState() => _KrediKartiDetayEkraniState();
}

class _KrediKartiDetayEkraniState extends ConsumerState<KrediKartiDetayEkrani> {
  Future<void> _silOnayDialog(BuildContext context, WidgetRef ref, KrediKartiModel kart) async {
    final bakiyeVar = kart.kullanilanLimit > 0.005;
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          const Text('Kartı Sil'),
        ]),
        content: Text(
          '"${kart.kartAdi}" kartını silmek istediğinize emin misiniz?\n\n'
          'Kart listeden kaldırılacak, ama geçmiş işlemleri (hareketler) '
          'korunacaktır.'
          '${bakiyeVar ? '\n\n⚠️ Bu kartta hâlâ ${kart.kullanilanLimit.toStringAsFixed(2)} '
              'TL ödenmemiş bakiye var. Silmeden önce ödemeyi kaydetmeniz önerilir.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, Sil'),
          ),
        ],
      ),
    );
    if (onay != true || !context.mounted) return;

    try {
      await KrediKartiDeposu().sil(kart.id!);
      ref.invalidate(tumKrediKartlariProvider);
      ref.invalidate(borcDashboardProvider);
      if (context.mounted) {
        BildirimServisi.basari(context, 'Kart silindi');
        context.pop();
      }
    } catch (e) {
      if (context.mounted) BildirimServisi.hata(context, 'Silinemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kartAsync = ref.watch(krediKartiDetayProvider(widget.kartId));

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: kartAsync.when(
          data: (kart) => Text(kart?.kartAdi ?? 'Kredi Kartı'),
          loading: () => const Text('Yükleniyor...'),
          error: (_, __) => const Text('Hata'),
        ),
        aksiyonlar: [
          kartAsync.when(
            data: (kart) {
              if (kart == null) return const SizedBox.shrink();
              return Row(mainAxisSize: MainAxisSize.min, children: [
                TsYetkili(child: IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  tooltip: 'Düzenle',
                  onPressed: () async {
                    final guncellendi = await context.push<bool>('/kredi-karti/ekle', extra: kart);
                    if (guncellendi == true) {
                      ref.invalidate(krediKartiDetayProvider(kart.id!));
                      ref.invalidate(tumKrediKartlariProvider);
                      ref.invalidate(borcDashboardProvider);
                    }
                  },
                )),
                // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu): Bu depoda/
                // ekranda hiç silme eylemi YOKTU — bir kart eklendikten
                // sonra asla kaldırılamıyordu. Gerçek silme yerine
                // deaktivasyon kullanılıyor (kredi_karti_hareket bu
                // karta FK ile bağlı — geçmiş işlemleri bozmamak için).
                TsYetkili(child: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Sil',
                  onPressed: () => _silOnayDialog(context, ref, kart),
                )),
              ]);
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: kartAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF4361EE)),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 12),
              Text('Hata: $e', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(krediKartiDetayProvider(widget.kartId)),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
        data: (kart) {
          if (kart == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.credit_card_off_outlined, size: 64, color: context.textSecondary),
                  SizedBox(height: 12),
                  Text('Kart bulunamadı', style: TextStyle(color: context.textSecondary)),
                ],
              ),
            );
          }
          return _KartDetayIcerik(kart: kart);
        },
      ),
    );
  }
}

class _KartDetayIcerik extends ConsumerWidget {
  final KrediKartiModel kart;
  const _KartDetayIcerik({required this.kart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limitDoluluk = kart.kartLimit > 0 ? (kart.kullanilanLimit / kart.kartLimit * 100) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Kart başlık kartı
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppRenkler.primary, AppRenkler.primary.withAlpha(179)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cardBg,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.credit_card, color: AppRenkler.primary, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kart.kartAdi,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                Text('No: ${kart.kartNoMaskeli}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: kart.aktif ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                kart.aktif ? 'Aktif' : 'Pasif',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Limit kartı
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8)],
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Limit Bilgisi', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('${limitDoluluk.toStringAsFixed(0)}% kullanıldı',
                  style: TextStyle(
                    color: limitDoluluk > 80 ? Colors.red : Colors.orange,
                    fontWeight: FontWeight.w600,
                  )),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (limitDoluluk / 100).clamp(0, 1),
              backgroundColor: context.borderColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                limitDoluluk > 80 ? Colors.red : Colors.orange,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _LimitItem(context, 'Limit', kart.kartLimit.toStringAsFixed(2)),
              ),
              Expanded(
                child: _LimitItem(context, 'Kullanılan', kart.kullanilanLimit.toStringAsFixed(2)),
              ),
              Expanded(
                child: _LimitItem(context, 'Kalan', kart.kalanLimit.toStringAsFixed(2)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),

        // Detaylar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8)],
          ),
          child: Column(children: [
            _BilgiSatiri(context, 'Kart Tipi', kart.kartTipi),
            _BilgiSatiri(context, 'Faiz Oranı', '%${kart.faizOrani.toStringAsFixed(2)}'),
            _BilgiSatiri(context, 'Taksit Sayısı', '${kart.taksitSayisi}'),
            if (kart.sonKullanma != null) _BilgiSatiri(context, 'Son Kullanma', kart.sonKullanma!),
            if (kart.kesimTarihi != null)
              _BilgiSatiri(context, 'Kesim Tarihi', _formatTarih(kart.kesimTarihi!)),
            if (kart.sonOdemeTarihi != null)
              _BilgiSatiri(context, 'Son Ödeme', _formatTarih(kart.sonOdemeTarihi!)),
          ]),
        ),

        const SizedBox(height: 24),

        // İşlem butonları
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/banka-hareket',
                  extra: {'krediKartiId': kart.id}),
              icon: const Icon(Icons.history_outlined),
              label: const Text('Hareketler'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _odemeYapDialog(context, ref, kart),
              icon: const Icon(Icons.payment_outlined, color: Colors.white),
              label: const Text('Ödeme Yap'),
            ),
          ),
        ]),
      ],
    );
  }

  String _formatTarih(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';

  // context parametresi eklendi — _KartDetayIcerik bir ConsumerWidget.
  Widget _LimitItem(BuildContext context, String label, String deger) => Column(children: [
    Text(deger,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppRenkler.primary)),
    Text(label,
        style: TextStyle(fontSize: 11, color: context.textSecondary)),
  ]);

  Widget _BilgiSatiri(BuildContext context, String label, String deger) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.borderColor))),
    child: Row(children: [
      Text(label,
          style: TextStyle(fontSize: 13, color: context.textSecondary)),
      const Spacer(),
      Text(deger,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );

  void _odemeYapDialog(BuildContext context, WidgetRef ref, KrediKartiModel kart) {
    final ctrl = TextEditingController(
        text: kart.kullanilanLimit > 0 ? kart.kullanilanLimit.toStringAsFixed(2) : '');
    bool isleniyor = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(Icons.payment_outlined, color: AppRenkler.primary),
            const SizedBox(width: 8),
            const Text('Karta Ödeme Yap'),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Güncel borç: ${kart.kullanilanLimit.toStringAsFixed(2)} TL',
                style: TextStyle(fontSize: 13, color: context.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Ödeme Tutarı (TL) *',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: isleniyor ? null : () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: isleniyor ? null : () async {
                final tutar = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
                if (tutar == null || tutar <= 0) {
                  BildirimServisi.uyari(context, 'Geçerli bir tutar girin');
                  return;
                }
                setStateDialog(() => isleniyor = true);
                try {
                  // Ödeme = kullanılan limitten DÜŞÜŞ, yani negatif delta.
                  await KrediKartiDeposu().limitDegistir(kart.id!, -tutar,
                      aciklama: 'Elle ödeme girişi');
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.invalidate(krediKartiDetayProvider(kart.id!));
                  if (context.mounted) {
                    BildirimServisi.basari(context,
                        '${tutar.toStringAsFixed(2)} TL ödeme yapıldı');
                  }
                } catch (e) {
                  setStateDialog(() => isleniyor = false);
                  if (context.mounted) BildirimServisi.hata(context, 'Hata: $e');
                }
              },
              child: isleniyor
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Ödemeyi Onayla'),
            ),
          ],
        ),
      ),
    );
  }
}