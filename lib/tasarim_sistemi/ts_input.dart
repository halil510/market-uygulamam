// lib/tasarim_sistemi/ts_input.dart
import 'package:flutter/material.dart';
import 'ts_token.dart';

/// Tek metin girişi bileşeni — tüm formlarda (ürün ekle, cari ekle,
/// personel ekle…) aynı görünüm ve doğrulama davranışı.
class TsInput extends StatelessWidget {
  final String etiket;
  final String? ipucu;
  final TextEditingController? controller;
  final String? Function(String?)? dogrula;
  final void Function(String)? degisti;
  final TextInputType? klavyeTuru;
  final bool sifreGizli;
  final int? maksSatir;
  final IconData? oncilIkon;
  final Widget? sonIkon;
  final bool aktif;
  final String? baslangicDegeri;
  final FocusNode? odakDugumu;

  const TsInput({
    super.key,
    required this.etiket,
    this.ipucu,
    this.controller,
    this.dogrula,
    this.degisti,
    this.klavyeTuru,
    this.sifreGizli = false,
    this.maksSatir = 1,
    this.oncilIkon,
    this.sonIkon,
    this.aktif = true,
    this.baslangicDegeri,
    this.odakDugumu,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? baslangicDegeri : null,
      validator: dogrula,
      onChanged: degisti,
      keyboardType: klavyeTuru,
      obscureText: sifreGizli,
      maxLines: sifreGizli ? 1 : maksSatir,
      enabled: aktif,
      focusNode: odakDugumu,
      style: TsMetin.govde.copyWith(color: TsRenk.metinBirincil(context)),
      decoration: InputDecoration(
        labelText: etiket,
        hintText: ipucu,
        prefixIcon: oncilIkon != null ? Icon(oncilIkon, size: 20) : null,
        suffixIcon: sonIkon,
        filled: true,
        fillColor: TsRenk.arkaplan(context),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: TsBosluk.md, vertical: TsBosluk.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TsRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TsRadius.md),
          borderSide: BorderSide(color: TsRenk.ayirac(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TsRadius.md),
          borderSide: const BorderSide(color: TsRenk.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TsRadius.md),
          borderSide: const BorderSide(color: TsRenk.hata),
        ),
      ),
    );
  }
}
