// lib/ekranlar/bayi/bayi_ana_ekrani.dart
//
// Bayi Portalı MVP (erp_roadmap madde 39, kullanıcı onayıyla "aynı
// uygulama içinde Bayi rolü"). Bir bayi hesabıyla giriş yapıldığında
// router (uygulama_router.dart._redirect) HER ZAMAN buraya yönlendirir
// — bayi normal personel ekranlarına asla erişemez.
//
// BİLİNÇLİ MVP KAPSAMI: Ürünler/Sipariş Ver, Siparişlerim, basit Hesap
// Özeti (bakiye). Faturalarım ve daha zengin hesap ekstresi sonraki bir
// iş olarak bırakıldı — bkz. memory.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../depolar/cari_deposu.dart';
import '../../modeller/cari_model.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'bayi_siparis_ekrani.dart';
import 'bayi_siparislerim_ekrani.dart';
import 'bayi_faturalarim_ekrani.dart';

class BayiAnaEkrani extends ConsumerStatefulWidget {
  const BayiAnaEkrani({super.key});
  @override
  ConsumerState<BayiAnaEkrani> createState() => _BayiAnaEkraniState();
}

class _BayiAnaEkraniState extends ConsumerState<BayiAnaEkrani> {
  CariModel? _bayi;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final cariId = ref.read(authProvider).bayiCariId;
    if (cariId == null) return;
    final c = await CariDeposu().idileGetir(cariId);
    if (mounted) setState(() { _bayi = c; _yukleniyor = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: _bayi?.unvan ?? 'Bayi Portalı',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Çıkış Yap',
            onPressed: () async {
              await ref.read(authProvider.notifier).cikisYap();
            },
          ),
        ],
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : RefreshIndicator(
              onRefresh: _yukle,
              child: ListView(
                padding: const EdgeInsets.all(TsBosluk.lg),
                children: [
                  if (_bayi != null)
                    TsKart(
                      tur: TsKartTuru.vurgulu,
                      baslik: _bayi!.bakiye > 0 ? 'Borcunuz' : 'Hesap Bakiyeniz',
                      deger: ParaUtils.formatla(_bayi!.bakiye.abs()),
                    ),
                  const SizedBox(height: TsBosluk.lg),
                  _menuKarti(
                    context,
                    ikon: Icons.add_shopping_cart_outlined,
                    baslik: 'Sipariş Ver',
                    altBaslik: 'Ürünleri inceleyin, sipariş oluşturun',
                    renk: TsRenk.primary,
                    onTap: () {
                      if (_bayi == null) return;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => BayiSiparisEkrani(bayi: _bayi!),
                      ));
                    },
                  ),
                  const SizedBox(height: TsBosluk.md),
                  _menuKarti(
                    context,
                    ikon: Icons.receipt_long_outlined,
                    baslik: 'Siparişlerim',
                    altBaslik: 'Geçmiş ve bekleyen siparişleriniz',
                    renk: TsRenk.bilgi,
                    onTap: () {
                      if (_bayi == null) return;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => BayiSiparislerimEkrani(cariId: _bayi!.id!),
                      ));
                    },
                  ),
                  const SizedBox(height: TsBosluk.md),
                  _menuKarti(
                    context,
                    ikon: Icons.description_outlined,
                    baslik: 'Faturalarım',
                    altBaslik: 'Kesilmiş faturalarınız',
                    renk: TsRenk.basarili,
                    onTap: () {
                      if (_bayi == null) return;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => BayiFaturalarimEkrani(cariId: _bayi!.id!),
                      ));
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _menuKarti(
    BuildContext context, {
    required IconData ikon,
    required String baslik,
    required String altBaslik,
    required Color renk,
    required VoidCallback onTap,
  }) {
    return TsKart(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(TsBosluk.lg),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(TsBosluk.md),
            decoration: BoxDecoration(
              color: TsRenk.zemin(renk),
              borderRadius: BorderRadius.circular(TsRadius.md),
            ),
            child: Icon(ikon, color: renk, size: 28),
          ),
          const SizedBox(width: TsBosluk.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik, style: TsMetin.baslikM.copyWith(color: TsRenk.metinBirincil(context))),
                const SizedBox(height: TsBosluk.xs),
                Text(altBaslik, style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: TsRenk.metinIkincil(context)),
        ]),
      ),
    );
  }
}
