// lib/tasarim_sistemi/ts_app_bar.dart
//
// TEK ÜST BAR BİLEŞENİ.
//
// ─────────────────────────────────────────────────────────────────────────
// NEDEN GENİŞLETİLDİ (derin analiz bulgusu)
//
// Projede 80 dosyada 95 adet HAM `AppBar(...)` vardı ve her biri kendi
// gradyanını, ikon temasını, elevation'ını elle kuruyordu. Sonuç:
//   • 16 FARKLI gradyan paleti — 12'si yalnızca BİR ekranda kullanılıyor
//     (sync mavi, fatura mor, kullanıcı pembe, irsaliye teal, iade
//      kırmızı, stok arduvaz...). Bunlar tasarım kararı değil, kazaydı.
//   • Aynı modülün iki ekranı farklı renkte (cari_liste #0D47A1,
//     cari_detay #1A237E)
//   • Her ekranda 5-6 satır tekrar eden şablon kod
//
// Eski TsAppBar bunları karşılayamıyordu: tek gradyan, `bottom:` (TabBar)
// desteği yok, modül rengi ifade edilemiyor. Bu yüzden ekranlar ona
// geçemiyordu — sorun ekranlarda değil, bileşendeydi.
//
// ARTIK: 5 modül rengi (her birinin net kuralı var) + TabBar + tüm
// yaygın AppBar özellikleri.
// ─────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'ts_token.dart';

/// Modül renk kodlaması.
///
/// KURAL: Varsayılan her zaman [ana]. Bir modülün kendi rengi olması için
/// KULLANICI İÇİN anlamlı bir bağlam farkı gerekir — "güzel dursun" diye
/// yeni renk EKLENMEZ. Beş renk bilinçli olarak azdır.
enum TsModul {
  /// Uygulamanın ana rengi. Ürün, satış, cari, rapor, ayarlar, banka,
  /// kasa, stok... — yani ekranların büyük çoğunluğu.
  ana,

  /// Restoran/masa modülü. Kullanıcı bunu "farklı bir işletme modu"
  /// olarak algılar; renk ayrımı bu yüzden anlamlı.
  masa,

  /// Mutfak ekranı. Duvara asılan, uzaktan bakılan, aciliyet bildiren
  /// bir ekran — ayrı renk fonksiyonel.
  mutfak,

  /// Resmi belge ekranları (fatura, irsaliye). GİB'e giden/yasal
  /// belgeler; "bu ekran resmi evrak üretiyor" ayrımı bilinçli.
  belge,

  /// Geri alma / iade gibi para-çıkışı işlemleri. Dikkat rengi.
  uyari,
}

class TsModulRenk {
  const TsModulRenk._();

  /// (koyu, açık) gradyan çifti
  static const Map<TsModul, (Color, Color)> _palet = {
    TsModul.ana:    (TsRenk.primaryKoyu, TsRenk.primary),
    TsModul.masa:   (TsRenk.masaKoyu, TsRenk.masaAcik),
    TsModul.mutfak: (Color(0xFFBF360C), Color(0xFFE64A19)),
    TsModul.belge:  (Color(0xFF00695C), Color(0xFF00796B)),
    TsModul.uyari:  (Color(0xFFC62828), Color(0xFFE53935)),
  };

  static (Color, Color) cift(TsModul m) => _palet[m] ?? _palet[TsModul.ana]!;
  static Color koyu(TsModul m) => cift(m).$1;
  static Color acik(TsModul m) => cift(m).$2;

  static LinearGradient gradyan(TsModul m) {
    final (k, a) = cift(m);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [k, a],
    );
  }
}

class TsAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Başlık metni. [baslikWidget] verilirse yok sayılır.
  final String? baslik;

  /// Metin yerine özel bir widget (arama kutusu, seçim sayacı vb.).
  final Widget? baslikWidget;

  final String? altBaslik;
  final List<Widget>? aksiyonlar;

  /// Modül rengi — varsayılan [TsModul.ana].
  final TsModul modul;

  /// Gradyanlı mı, düz tema rengi mi.
  final bool gradyanli;

  final Widget? lider;
  final bool geriTusu;

  /// TabBar gibi alt bileşen.
  final PreferredSizeWidget? alt;

  final bool? ortalaBaslik;
  final double? araclarYuksekligi;
  final ShapeBorder? sekil;

  const TsAppBar({
    super.key,
    this.baslik,
    this.baslikWidget,
    this.altBaslik,
    this.aksiyonlar,
    this.modul = TsModul.ana,
    this.gradyanli = true,
    this.lider,
    this.geriTusu = true,
    this.alt,
    this.ortalaBaslik,
    this.araclarYuksekligi,
    this.sekil,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        (araclarYuksekligi ?? kToolbarHeight) +
            (alt?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final Widget? baslikIcerik = baslikWidget ??
        (baslik == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    baslik!,
                    style: TsMetin.baslikL.copyWith(
                        color: gradyanli
                            ? Colors.white
                            : TsRenk.metinBirincil(context)),
                  ),
                  if (altBaslik != null)
                    Text(
                      altBaslik!,
                      style: TsMetin.kucuk.copyWith(
                          color: gradyanli
                              ? Colors.white70
                              : TsRenk.metinIkincil(context)),
                    ),
                ],
              ));

    if (!gradyanli) {
      return AppBar(
        title: baslikIcerik,
        actions: aksiyonlar,
        leading: lider,
        automaticallyImplyLeading: geriTusu,
        bottom: alt,
        centerTitle: ortalaBaslik,
        toolbarHeight: araclarYuksekligi,
        shape: sekil,
      );
    }

    return AppBar(
      title: baslikIcerik,
      actions: aksiyonlar,
      leading: lider,
      automaticallyImplyLeading: geriTusu,
      bottom: alt,
      centerTitle: ortalaBaslik,
      toolbarHeight: araclarYuksekligi,
      shape: sekil,
      elevation: 0,
      // 🔴 DÜZELTME (kullanıcı bulgusu — "ikonlar beyaz olduğu için
      // görünmüyor"): ÖNCEDEN backgroundColor hiç set edilmiyordu.
      // AppBar'ın "resmi" zemin rengi hâlâ temanın appBarTheme.
      // backgroundColor'ı (AppRenkler.surface — açık/beyaz) olarak
      // kalıyordu; gradyan sadece flexibleSpace ile ÜSTÜNE bindiriliyordu.
      //
      // Bu iki şekilde beyaz-üstüne-beyaz'a yol açar:
      //   1) Material 3'te scrolledUnderElevation aktifken
      //      surfaceTintColor otomatik karışıp zemini açık bir tona
      //      kaydırabilir.
      //   2) flexibleSpace render sırasına bağlı bir "görsel" katmandır;
      //      AppBar'ın kendi backgroundColor'ı her zaman asıl zemindir.
      //
      // foregroundColor/iconTheme KOŞULSUZ beyaza sabitlenmişti — zemin
      // açık kalırsa ikonlar görünmez oluyordu. Artık backgroundColor da
      // gradyanın koyu tonuyla açıkça veriliyor; flexibleSpace zaten
      // aynı gradyanı üstüne bindirdiği için görsel fark yok, ama artık
      // zemin HİÇBİR senaryoda açık kalamaz. surfaceTintColor da
      // transparent yapıldı ki M3 otomatik karıştırması bunu bir daha
      // bozamasın.
      backgroundColor: TsModulRenk.koyu(modul),
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(gradient: TsModulRenk.gradyan(modul)),
      ),
    );
  }
}
