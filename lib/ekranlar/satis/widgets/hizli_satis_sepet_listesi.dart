// lib/ekranlar/satis/widgets/hizli_satis_sepet_listesi.dart
// SRP: Sadece sepet listesi sorumluluğu
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../modeller/sepet_model.dart';
import '../../../modeller/urun_model.dart';
import '../../../saglayicilar/riverpod/sepet_provider.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import 'sepet_kalem_karti.dart';

class HizliSatisSepetListesi extends ConsumerWidget {
  final ScrollController scrollController;
  final bool Function(String birim) kgMiMi;
  final void Function(SepetKalem kalem, int index) onKalemTap;
  final void Function(SepetKalem kalem, int index) onIndirimDuzenle;
  final void Function(UrunModel urun) onKgEkle;

  const HizliSatisSepetListesi({
    super.key,
    required this.scrollController,
    required this.kgMiMi,
    required this.onKalemTap,
    required this.onIndirimDuzenle,
    required this.onKgEkle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sepet = ref.watch(sepetProvider);

    if (sepet.bos) return _bosGorunum(context);

    return Column(children: [
      _baslik(context, ref, sepet),
      _tabloBasligi(context),
      Expanded(
        child: ListView.builder(
          controller: scrollController,
          itemCount: sepet.kalemler.length,
          itemBuilder: (_, i) {
            final k = sepet.kalemler[i];
            return SepetKalemKarti(
              kalem: k, index: i,
              onTap:       () => onKalemTap(k, i),
              onLongPress: () => onIndirimDuzenle(k, i),
              onSil:       () => ref.read(sepetProvider.notifier).sil(i),
              onAzalt: () {
                if (kgMiMi(k.urun.birimAdi)) { onKgEkle(k.urun); return; }
                ref.read(sepetProvider.notifier).miktarGuncelle(i, k.miktar - 1);
              },
              onArttir: () {
                if (kgMiMi(k.urun.birimAdi)) { onKgEkle(k.urun); return; }
                ref.read(sepetProvider.notifier).miktarGuncelle(i, k.miktar + 1);
              },
              kgMiMi: kgMiMi,
            );
          },
        ),
      ),
    ]);
  }

  // Kullanıcı isteği: "Logo gibi profesyonel yazılımlar gibi ekranlar
  // olsun." Toptan modülündeki fatura ızgarası başlığıyla aynı dil —
  // sepet artık kolon başlıklı, gridli bir tablo hissi veriyor.
  Widget _tabloBasligi(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 4),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Text('ÜRÜN', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800,
                letterSpacing: 0.3, color: TsRenk.metinIkincil(context))),
          ),
          Expanded(
            flex: 3,
            child: Text('MİKTAR', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5,
                fontWeight: FontWeight.w800, letterSpacing: 0.3, color: TsRenk.metinIkincil(context))),
          ),
          SizedBox(
            width: 64,
            child: Text('TUTAR', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5,
                fontWeight: FontWeight.w800, letterSpacing: 0.3, color: TsRenk.metinIkincil(context))),
          ),
        ]),
      );

  Widget _bosGorunum(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 100, height: 100,
        decoration: BoxDecoration(
          color: TsRenk.primary.withAlpha(10),
          shape: BoxShape.circle,
          border: Border.all(color: TsRenk.primary.withAlpha(26), width: 2),
        ),
        child: Icon(Icons.shopping_cart_outlined,
            size: 50, color: TsRenk.primary.withAlpha(102)),
      ),
      const SizedBox(height: 20),
      Text('Sepet Boş',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
              color: TsRenk.metinBirincil(context))),
      const SizedBox(height: 8),
      Text('Ürün aramak için arama yapın veya barkod okutun',
          textAlign: TextAlign.center,
          style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 13, height: 1.4)),
    ]),
  );

  Widget _baslik(BuildContext context, WidgetRef ref, SepetDurum sepet) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${sepet.kalemler.length} çeşit • ${sepet.toplamAdet} adet',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            GestureDetector(
              // 🔴 Derin denetimde bulundu (P2): sepeti TAMAMEN boşaltan
              // bu buton hiç onay diyaloğu içermiyordu — tek dokunuşla,
              // geri alma seçeneği olmadan tüm sepet siliniyordu. Küçük
              // (14px ikon) bir hedef, yoğun bir POS ortamında yanlışlıkla
              // dokunma riski gerçek; kardeş akışların (satış tamamlama,
              // fiş güncelleme vb.) hepsi onay/geri bildirim içeriyor.
              onTap: () async {
                if (sepet.kalemler.isEmpty) return;
                final onay = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Sepeti Temizle'),
                    content: Text('${sepet.kalemler.length} çeşit ürün sepetten tamamen silinecek. Emin misiniz?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Temizle'),
                      ),
                    ],
                  ),
                );
                if (onay == true) {
                  ref.read(sepetProvider.notifier).temizle();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x1AE53935),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x33E53935)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_sweep_rounded, size: 14, color: Color(0xFFE53935)),
                  SizedBox(width: 4),
                  Text('Temizle', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: Color(0xFFE53935))),
                ]),
              ),
            ),
          ],
        ),
      );
}
