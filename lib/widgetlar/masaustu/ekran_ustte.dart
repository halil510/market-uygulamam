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

//
// Kök Navigator'da açılan diyalog (showDialog varsayılanı) da kabuk ekranını
// isCurrent=false yapmaz ve saydam olduğu için TickerMode'u da kapatmaz. Bu
// yüzden ayrıca kök Navigator'daki en üst açılır rota ([UstRotaGozlemci])
// kontrol edilir. Canlı test 2026-10-11: pencere kapatma diyaloğu açıkken
// Hızlı Satış odağı 400 ms'de bir barkod kutusuna geri çekiyor, Enter
// diyaloğa ulaşmıyordu (F tuşları da arkada çalışabiliyordu).
bool ekranUstte(BuildContext context) {
  if (!TickerMode.valuesOf(context).enabled) return false;
  final rota = ModalRoute.of(context);
  if (rota?.isCurrent == false) return false;
  final ust = UstRotaGozlemci.i.enUstPopup;
  if (ust != null && ust != rota && ust.isCurrent) return false;
  return true;
}

/// Kök Navigator'daki açık diyalog/menü/alt sayfaları (PopupRoute) izler.
/// GoRouter(observers: [UstRotaGozlemci.i]) ile bağlanır.
class UstRotaGozlemci extends NavigatorObserver {
  UstRotaGozlemci._();
  static final i = UstRotaGozlemci._();

  final _popuplar = <Route<dynamic>>[];

  Route<dynamic>? get enUstPopup => _popuplar.isEmpty ? null : _popuplar.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _popuplar.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _popuplar.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _popuplar.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _popuplar.remove(oldRoute);
    if (newRoute is PopupRoute) _popuplar.add(newRoute);
  }
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
