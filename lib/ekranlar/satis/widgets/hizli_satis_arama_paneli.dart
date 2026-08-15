// lib/ekranlar/satis/widgets/hizli_satis_arama_paneli.dart
// SRP: Sadece arama paneli sorumluluğu
import 'package:flutter/material.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';

class HizliSatisAramaPaneli extends StatelessWidget {
  final TextEditingController araCtrl;
  final FocusNode araFocus;
  final ValueChanged<String> onDegisti;
  final VoidCallback onPluAc;

  /// 🆕 Hızlı tuş (favori ürün) panelini açar. Opsiyonel bırakıldı ki
  /// bu widget'ı kullanan başka bir ekran varsa kırılmasın.
  final VoidCallback? onHizliTusAc;

  const HizliSatisAramaPaneli({
    super.key,
    required this.araCtrl,
    required this.araFocus,
    required this.onDegisti,
    required this.onPluAc,
    this.onHizliTusAc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: araCtrl,
            focusNode:  araFocus,
            onChanged:  onDegisti,
            decoration: InputDecoration(
              hintText:   'Ürün adı veya barkod ara…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: araCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        araCtrl.clear();
                        onDegisti('');
                      })
                  : null,
              border:     const OutlineInputBorder(),
              isDense:    true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'PLU - Hızlı Ürün',
          child: GestureDetector(
            onTap: onPluAc,
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(
                  color: Color(0x662E7D32),
                  blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: const Icon(Icons.grid_view_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ),

        // ── 🆕 HIZLI TUŞ (favori ürün) ────────────────────────────────
        // Barkodsuz satılan ürünler (ekmek, poşet, çay, su) için.
        if (onHizliTusAc != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'Hızlı Tuşlar',
            child: GestureDetector(
              onTap: onHizliTusAc,
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [TsRenk.primaryKoyu, TsRenk.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: TsGolge.renkli(TsRenk.primary),
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
