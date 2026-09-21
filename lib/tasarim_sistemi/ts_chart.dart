// lib/tasarim_sistemi/ts_chart.dart
//
// DEEP_AUDIT_REPORT FAZ 6 (UX/UI, P3) — madde 25, kullanıcı onayıyla
// (sadece tasarım bileşenleri): "Design System'de TsDialog/TsBottomSheet/
// TsChart bileşenleri yok". Rapor ekranlarında (satis_rapor_ekrani.dart,
// stok_rapor_ekrani.dart, kar_zarar_ekrani.dart, kasa_rapor_ekrani.dart,
// vb.) her grafik için AYNI "kart çerçevesi" (başlık + kart arka planı +
// radius + gölge + boş-veri durumu) elle tekrarlanıyordu — bu sınıf
// gerçek grafik çizim mantığına (fl_chart/syncfusion) DOKUNMUYOR, sadece
// TsDialog'un dialog'lar için sağladığı standart çerçeveyi grafikler için
// sağlıyor; grafiğin kendisi [child] olarak verilir.
//
// BİLİNÇLİ KAPSAM: mevcut rapor ekranlarındaki onlarca elle-çizilmiş
// grafik kartını buna taşımak (geniş, görsel doğrulama gerektiren, riskli
// bir retrofit) bu turun kapsamı DIŞINDA bırakıldı — bu sadece BUNDAN
// SONRA yazılacak yeni grafikler için tutarlı bir temel sağlıyor.
import 'package:flutter/material.dart';
import 'ts_token.dart';

class TsChart extends StatelessWidget {
  final String baslik;
  final Widget child;
  final double? yukseklik;
  final bool bosMu;
  final String bosMesaj;

  const TsChart({
    super.key,
    required this.baslik,
    required this.child,
    this.yukseklik,
    this.bosMu = false,
    this.bosMesaj = 'Veri yok',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(baslik, style: TsMetin.baslikM),
        const SizedBox(height: TsBosluk.md),
        Container(
          height: yukseklik,
          padding: const EdgeInsets.all(TsBosluk.lg),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(TsRadius.lg),
            boxShadow: TsGolge.yumusak,
          ),
          child: bosMu
              ? Center(
                  child: Text(bosMesaj,
                      style: TextStyle(color: TsRenk.metinIkincil(context))))
              : child,
        ),
      ],
    );
  }
}
