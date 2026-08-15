// lib/tasarim_sistemi/ts_kart.dart
//
// TEK KART SİSTEMİ
// ------------------------------------------------------------------
// Projede daha önce 40 farklı yerde ayrı "Kart" sınıfı tanımlıydı
// (uygulama_card.dart, app_widgetlar.dart, urun_karti.dart,
// istatistik_karti.dart, banka/borç/masa/cari ekranlarındaki özel kartlar…).
// Bundan sonra TÜM kartlar TsKart üzerinden, varyant (TsKartTuru) ile üretilir.
// Yeni bir "kart görünümü" gerektiğinde yeni sınıf yazmak yerine burada
// varyant eklenir.
// ------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'ts_token.dart';

enum TsKartTuru {
  /// Standart içerik kartı (varsayılan, çoğu ekranda kullanılır).
  standart,

  /// Dashboard/istatistik kutucuğu — büyük sayı + ikon + trend.
  istatistik,

  /// Liste satırı kartı — sol ikon/görsel, başlık+alt yazı, sağ değer/aksiyon.
  liste,

  /// Vurgulu / gradyanlı öne çıkan kart (örn. bakiye özeti, kampanya).
  vurgulu,
}

/// Uygulamadaki TEK kart bileşeni. Her ekran (ürün, cari, banka, borç,
/// masa, personel, rapor…) bunu kullanır; kendi kart sınıfını yazmaz.
class TsKart extends StatelessWidget {
  final TsKartTuru tur;
  final Widget? child;

  // --- liste & istatistik türleri için ortak alanlar ---
  final Widget? ikon;
  final String? baslik;
  final String? altBaslik;
  final String? deger;
  final String? altDeger;
  final Color? vurguRenk;
  final Widget? sagAksiyon;
  final List<Widget>? etiketler; // durum badge'leri (TsBadge)

  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool secili;

  const TsKart({
    super.key,
    this.tur = TsKartTuru.standart,
    this.child,
    this.ikon,
    this.baslik,
    this.altBaslik,
    this.deger,
    this.altDeger,
    this.vurguRenk,
    this.sagAksiyon,
    this.etiketler,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.secili = false,
  });

  /// Dashboard istatistik kutucuğu kısayolu.
  const TsKart.istatistik({
    super.key,
    required this.baslik,
    required this.deger,
    this.altDeger,
    this.ikon,
    this.vurguRenk,
    this.onTap,
  })  : tur = TsKartTuru.istatistik,
        child = null,
        altBaslik = null,
        sagAksiyon = null,
        etiketler = null,
        padding = null,
        onLongPress = null,
        secili = false;

  /// Liste satırı kısayolu (ürün, cari, personel, banka hesabı vb. listeler).
  const TsKart.liste({
    super.key,
    required this.baslik,
    this.altBaslik,
    this.deger,
    this.ikon,
    this.sagAksiyon,
    this.etiketler,
    this.onTap,
    this.onLongPress,
    this.secili = false,
  })  : tur = TsKartTuru.liste,
        child = null,
        altDeger = null,
        vurguRenk = null,
        padding = null;

  @override
  Widget build(BuildContext context) {
    switch (tur) {
      case TsKartTuru.istatistik:
        return _istatistikKart(context);
      case TsKartTuru.liste:
        return _listeKart(context);
      case TsKartTuru.vurgulu:
        return _vurguluKart(context);
      case TsKartTuru.standart:
        return _standartKart(context);
    }
  }

  BoxDecoration _govdeDekorasyon(BuildContext context) => BoxDecoration(
        color: secili
            ? TsRenk.zemin(TsRenk.primary, opaklik: 0.06)
            : TsRenk.kart(context),
        borderRadius: BorderRadius.circular(TsRadius.lg),
        border: Border.all(
          color: secili ? TsRenk.primary : TsRenk.ayirac(context),
          width: secili ? 1.4 : 1,
        ),
      );

  Widget _saril(BuildContext context, Widget icerik) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(TsRadius.lg),
          child: Container(
            decoration: _govdeDekorasyon(context),
            padding: padding ?? const EdgeInsets.all(TsBosluk.lg),
            child: icerik,
          ),
        ),
      );

  Widget _standartKart(BuildContext context) =>
      _saril(context, child ?? const SizedBox.shrink());

  Widget _istatistikKart(BuildContext context) {
    final renk = vurguRenk ?? TsRenk.primary;
    return _saril(
      context,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ikon != null)
            Container(
              padding: const EdgeInsets.all(TsBosluk.sm),
              decoration: BoxDecoration(
                color: TsRenk.zemin(renk),
                borderRadius: BorderRadius.circular(TsRadius.sm),
              ),
              child: IconTheme(
                data: IconThemeData(color: renk, size: 20),
                child: ikon!,
              ),
            ),
          const SizedBox(width: TsBosluk.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik ?? '',
                    style: TsMetin.kucuk
                        .copyWith(color: TsRenk.metinIkincil(context))),
                const SizedBox(height: TsBosluk.xs),
                Text(deger ?? '',
                    style: TsMetin.baslikL
                        .copyWith(color: TsRenk.metinBirincil(context))),
                if (altDeger != null) ...[
                  const SizedBox(height: TsBosluk.xs),
                  Text(altDeger!,
                      style: TsMetin.kucuk.copyWith(color: renk)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listeKart(BuildContext context) => _saril(
        context,
        Row(
          children: [
            if (ikon != null) ...[
              CircleAvatar(
                radius: 20,
                backgroundColor: TsRenk.zemin(TsRenk.primary),
                child: IconTheme(
                  data: const IconThemeData(color: TsRenk.primary, size: 20),
                  child: ikon!,
                ),
              ),
              const SizedBox(width: TsBosluk.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(baslik ?? '',
                      style: TsMetin.govdeVurgu
                          .copyWith(color: TsRenk.metinBirincil(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (altBaslik != null) ...[
                    const SizedBox(height: 2),
                    Text(altBaslik!,
                        style: TsMetin.kucuk
                            .copyWith(color: TsRenk.metinIkincil(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (etiketler != null && etiketler!.isNotEmpty) ...[
                    const SizedBox(height: TsBosluk.xs),
                    Wrap(spacing: TsBosluk.xs, children: etiketler!),
                  ],
                ],
              ),
            ),
            if (deger != null) ...[
              const SizedBox(width: TsBosluk.sm),
              Text(deger!,
                  style: TsMetin.baslikM
                      .copyWith(color: TsRenk.metinBirincil(context))),
            ],
            if (sagAksiyon != null) ...[
              const SizedBox(width: TsBosluk.xs),
              sagAksiyon!,
            ] else if (onTap != null)
              Icon(Icons.chevron_right,
                  color: TsRenk.metinIkincil(context), size: 20),
          ],
        ),
      );

  Widget _vurguluKart(BuildContext context) {
    final renk = vurguRenk ?? TsRenk.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TsRadius.lg),
        child: Container(
          padding: padding ?? const EdgeInsets.all(TsBosluk.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [renk, TsRenk.primaryKoyu],
            ),
            borderRadius: BorderRadius.circular(TsRadius.lg),
            boxShadow: TsGolge.renkli(renk),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: child ??
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (baslik != null)
                      Text(baslik!,
                          style: TsMetin.govde
                              .copyWith(color: Colors.white70)),
                    if (deger != null) ...[
                      const SizedBox(height: TsBosluk.xs),
                      Text(deger!,
                          style: TsMetin.baslikXL
                              .copyWith(color: Colors.white)),
                    ],
                  ],
                ),
          ),
        ),
      ),
    );
  }
}
