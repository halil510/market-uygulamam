// lib/ekranlar/banka/banka_detay_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../modeller/banka_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../depolar/banka_deposu.dart';
import '../../tasarim_sistemi/ts_yetki.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class BankaDetayEkrani extends ConsumerStatefulWidget {
  final int bankaId;
  const BankaDetayEkrani({super.key, required this.bankaId});

  @override
  ConsumerState<BankaDetayEkrani> createState() => _BankaDetayEkraniState();
}

class _BankaDetayEkraniState extends ConsumerState<BankaDetayEkrani> {
  @override
  Widget build(BuildContext context) {
    final bankaAsync = ref.watch(bankaDetayProvider(widget.bankaId));

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Banka Detay',
        aksiyonlar: [
          TsYetkili(child: IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            tooltip: 'Düzenle',
            onPressed: () {
              bankaAsync.whenData((banka) async {
                if (banka != null) {
                  final guncellendi = await context.push<bool>('/banka/ekle', extra: banka);
                  if (guncellendi == true) {
                    ref.invalidate(bankaDetayProvider(widget.bankaId));
                  }
                }
              });
            },
          )),
        ],
      ),
      body: bankaAsync.when(
        loading: () => const TsYukleniyor(),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 12),
              Text('Hata: $e', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(bankaDetayProvider(widget.bankaId)),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
        data: (banka) {
          if (banka == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.business_outlined, size: 64, color: context.textSecondary),
                  SizedBox(height: 12),
                  Text('Banka bulunamadı', style: TextStyle(color: context.textSecondary)),
                ],
              ),
            );
          }
          return _BankaDetayIcerik(banka: banka);
        },
      ),
    );
  }
}

class _BankaDetayIcerik extends StatelessWidget {
  final BankaModel banka;
  const _BankaDetayIcerik({required this.banka});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Başlık kartı
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
              child: Icon(Icons.business, color: AppRenkler.primary, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(banka.ad,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                if (banka.kod != null)
                  Text('Kod: ${banka.kod}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: banka.aktif ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                banka.aktif ? 'Aktif' : 'Pasif',
                style: TsMetin.kucukVurgu.copyWith(color: Colors.white),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Bilgi kartı
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8)],
          ),
          child: Column(children: [
            _BilgiSatiri(context, 'Banka Adı', banka.ad),
            if (banka.kod != null) _BilgiSatiri(context, 'Banka Kodu', banka.kod!),
            if (banka.tel != null) _BilgiSatiri(context, 'Telefon', banka.tel!),
            if (banka.email != null) _BilgiSatiri(context, 'E-posta', banka.email!),
            if (banka.web != null) _BilgiSatiri(context, 'Web Sitesi', banka.web!),
            if (banka.adres != null) _BilgiSatiri(context, 'Adres', banka.adres!, maxLines: 3),
            if (banka.yetkili != null) _BilgiSatiri(context, 'Yetkili Kişi', banka.yetkili!),
          ]),
        ),
        const SizedBox(height: 16),

        // Hesaplar butonu
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/banka/hesaplar/${banka.id}'),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Banka Hesaplarını Gör'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Kredi Kartları butonu
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/kredi-karti', extra: banka.id),
            icon: const Icon(Icons.credit_card_outlined),
            label: const Text('Kredi Kartlarını Gör'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Sil butonu
        TsYetkili(child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _sil(context),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Bankayı Sil', style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // context parametresi eklendi — _BankaDetayIcerik bir StatelessWidget.
  Widget _BilgiSatiri(BuildContext context, String label, String deger, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 100,
        child: Text(label,
            style: TextStyle(fontSize: 13, color: context.textSecondary, fontWeight: FontWeight.w500)),
      ),
      Expanded(
        child: Text(deger,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis),
      ),
    ]),
  );

  void _sil(BuildContext context) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Bankayı Sil'),
        ]),
        content: Text('${banka.ad} bankasını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await BankaDeposu().sil(banka.id!);
      if (context.mounted) {
        BildirimServisi.basari(context, 'Banka silindi');
        context.pop();
      }
    } catch (e) {
      if (context.mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }
}