// lib/widgetlar/ortak/kredi_limiti_onay_dialog.dart
//
// Veresiye (Cari) satış/ödeme öncesi kredi limiti onayı — TEK kaynak.
// ÖNCEDEN aynı AlertDialog Masa Detay ve Toptan Satış ekranlarında ayrı
// ayrı kopyalanmıştı; Hızlı Satış'ta ise hiç yoktu (2026-11-06).
//
// Kural (CariDeposu.limitKontrolEt ile aynı): limit SERT engel değildir,
// aşılıyorsa kullanıcıdan açık onay istenir.
import 'package:flutter/material.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../depolar/cari_deposu.dart';
import '../../tasarim_sistemi/ts_token.dart';

/// CariDeposu.limitKontrolEt dönüş tipi.
typedef LimitSonucu = ({
  bool asildi,
  double mevcutBakiye,
  double limit,
  double asimTutari,
});

/// Limit aşılıyorsa onay diyaloğu gösterir. Limit aşılmıyorsa ya da
/// kullanıcı "Yine de Devam Et" derse `true`, vazgeçerse (veya ekran
/// kapanmışsa) `false` döner.
///
/// [unvan] verilirse metin "`unvan` için tanımlı kredi limiti" diye başlar.
/// [birlikteEtiketi]: "Bu satışla" / "Bu ödemeyle" gibi.
Future<bool> krediLimitiOnayla(
  BuildContext context, {
  required LimitSonucu sonuc,
  required double eklenecekTutar,
  String? unvan,
  String birlikteEtiketi = 'Bu satışla',
}) async {
  if (!sonuc.asildi) return true;
  if (!context.mounted) return false;
  final limitSatiri = unvan != null
      ? '$unvan için tanımlı kredi limiti: '
      : 'Tanımlı kredi limiti: ';
  final devam = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: TsRenk.uyari),
        SizedBox(width: 8),
        Text('Kredi Limiti Aşılıyor'),
      ]),
      content: Text(
        '$limitSatiri${ParaUtils.formatla(sonuc.limit)}\n'
        'Mevcut bakiye: ${ParaUtils.formatla(sonuc.mevcutBakiye)}\n'
        '$birlikteEtiketi birlikte: '
        '${ParaUtils.formatla(sonuc.mevcutBakiye + eklenecekTutar)}\n\n'
        'Limit ${ParaUtils.formatla(sonuc.asimTutari)} kadar aşılacak. '
        'Yine de devam etmek istiyor musunuz?',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TsRenk.uyari),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Yine de Devam Et'),
        ),
      ],
    ),
  );
  return devam == true;
}

/// Kısayol: limiti sorgular ve gerekirse onay ister. [cariId] null veya
/// [eklenecekTutar] ≈ 0 ise kontrol yapılmaz (`true`).
Future<bool> cariLimitiKontrolVeOnay(
  BuildContext context, {
  required int? cariId,
  required double eklenecekTutar,
  String? unvan,
  String birlikteEtiketi = 'Bu satışla',
}) async {
  if (cariId == null || eklenecekTutar <= 0.005) return true;
  final sonuc = await CariDeposu().limitKontrolEt(cariId, eklenecekTutar);
  if (!context.mounted) return false;
  return krediLimitiOnayla(context,
      sonuc: sonuc,
      eklenecekTutar: eklenecekTutar,
      unvan: unvan,
      birlikteEtiketi: birlikteEtiketi);
}
