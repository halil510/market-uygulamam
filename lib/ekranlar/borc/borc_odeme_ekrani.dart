// lib/ekranlar/borc/borc_odeme_ekrani.dart
//
// Bağımsız ödeme rotası (/borc-odeme/:id). Artık borc_dashboard_ekrani.dart
// ve borc_detay_ekrani.dart ile AYNI, eksiksiz ödeme bileşenini
// (BorcOdemeBottomSheet) kullanıyor — banka hesabı/kredi kartı seçimi ve
// otomatik Gider kaydı dahil. Önceden burada ödeme yöntemi sadece görsel
// bir etiketti, hiçbir yere kaydedilmiyordu.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modeller/borc_model.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'widgets/borc_odeme_bottom_sheet.dart';

class BorcOdemeEkrani extends ConsumerStatefulWidget {
  final BorcModel borc;
  const BorcOdemeEkrani({super.key, required this.borc});

  @override
  ConsumerState<BorcOdemeEkrani> createState() => _BorcOdemeEkraniState();
}

class _BorcOdemeEkraniState extends ConsumerState<BorcOdemeEkrani> {
  @override
  void initState() {
    super.initState();
    // Ekran açılır açılmaz ödeme bileşenini göster; kapatılınca bu ekrandan
    // da geri dönülür (bu ekran sadece rota giriş noktası).
    WidgetsBinding.instance.addPostFrameCallback((_) => _sheetGoster());
  }

  Future<void> _sheetGoster() async {
    final bankaHesaplari = await ref.read(bankaHesaplarProvider(null).future);
    final krediKartlari = await ref.read(krediKartlariProvider(null).future);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BorcOdemeBottomSheet(
        borc: widget.borc,
        bankaHesaplari: bankaHesaplari,
        krediKartlari: krediKartlari,
        onOdemeYapildi: () {
          if (mounted) context.pop(true);
        },
      ),
    );
    // Kullanıcı sheet'i kapatıp ödeme yapmadan vazgeçtiyse ekrandan da çık.
    if (mounted) context.pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Ödeme Yap - ${widget.borc.baslik}',
        gradyanli: false,
      ),
      body: const TsYukleniyor(),
    );
  }
}
