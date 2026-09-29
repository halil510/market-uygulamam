// lib/servisler/belge_no_servisi.dart
//
// Ekranların fiş/belge numarası aldığı tek yer — Veritabani.fisNoUret()'e
// doğrudan erişim yerine (DEEP_AUDIT madde 24: katman ihlali). Numara
// kuralları (kasa bazlı seri, şube doğrulama, bulut uyumu) fisNoUret'te.
import '../veri/database/veritabani.dart';
import 'aktif_sube_servisi.dart';

class BelgeNoServisi {
  static final BelgeNoServisi _i = BelgeNoServisi._();
  factory BelgeNoServisi() => _i;
  BelgeNoServisi._();

  /// [tip] için sıradaki numara ('iade', 'irsaliye', 'masa', 'siparis',
  /// 'cari_satis', 'tahsilat', 'tediye' …). [subeId] verilmezse aktif şube.
  Future<String> uret(String tip, {int? subeId}) => Veritabani()
      .fisNoUret(tip, subeId: subeId ?? AktifSubeServisi().subeId ?? 1);
}
