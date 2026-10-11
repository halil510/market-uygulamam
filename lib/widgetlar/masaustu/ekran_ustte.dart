// lib/widgetlar/masaustu/ekran_ustte.dart
//
// Klavye kısayolu (HardwareKeyboard) dinleyen ekranlar "şu an kullanıcının
// gördüğü ekran ben miyim?" diye bununla sorar.
//
// Neden yalnız `ModalRoute.isCurrent` yetmiyor: Hızlı Satış / Ürün / Cari gibi
// ana kabuk (ShellRoute) ekranları kendi iç Navigator'larında HER ZAMAN "güncel"
// rotadır; üstüne kök Navigator'da açılan bir sayfa (Promosyon, Toptan...) onu
// `isCurrent=false` yapmaz. Sonuç: Promosyon'da F3'e basınca arkadaki Hızlı
// Satış'ın F3'ü (Stok) çalışıyor, F9 sepeti temizliyor, F1 nakit ödeme alıyordu.
// Opak bir sayfanın altında kalan ekran Flutter tarafından TickerMode=false ile
// işaretlenir; hem bunu hem de (diyalog gibi saydam üst rotalar için) isCurrent'i
// birlikte kontrol ediyoruz.
import 'package:flutter/widgets.dart';

bool ekranUstte(BuildContext context) {
  if (!TickerMode.valuesOf(context).enabled) return false;
  return ModalRoute.of(context)?.isCurrent != false;
}

/// Klavye odağı bir yazı alanında mı? (Ör. Ctrl+A orada metni seçmeli,
/// tablodaki tüm satırları değil.)
bool yaziAlaniOdakta() {
  final odak = FocusManager.instance.primaryFocus?.context;
  return odak != null &&
      (odak.widget is EditableText ||
          odak.findAncestorWidgetOfExactType<EditableText>() != null);
}

/// Masaüstünde Esc ve üst şeritteki "Geri", sayfayı kapatmadan ÖNCE ekranın
/// kendi iç geri adımına sorar (ör. Ayarlar'da aramayı temizle / kategoriden
/// tüm ayarlara dön). Genel Esc işleyicisi (masaustu_yan_menu.dart) GoRouter
/// ile doğrudan pop/go yaptığından ekranın PopScope'unu hiç görmüyordu.
/// İşleyici, adımı işlediyse true döner; kendi ekranı üstte değilse
/// ([ekranUstte]) false dönmelidir.
class IcGeri {
  IcGeri._();
  static final _isleyiciler = <bool Function()>[];

  static void ekle(bool Function() f) => _isleyiciler.add(f);
  static void cikar(bool Function() f) => _isleyiciler.remove(f);

  /// En son eklenenden başlayarak sorar; biri işlerse true.
  static bool dene() {
    for (final f in _isleyiciler.reversed.toList()) {
      if (f()) return true;
    }
    return false;
  }
}
