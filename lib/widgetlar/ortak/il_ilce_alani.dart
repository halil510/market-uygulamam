// lib/widgetlar/ortak/il_ilce_alani.dart
//
// Kullanıcı isteği: "il ve ilçeler otomatik gelsin, denizli dediğimde
// denizli ilçeleri gelsin, profesyonellerde öyle... hem yazmalı hem de
// çıkan listeden seçmeli." Cari ve fatura (firma bilgileri) adres
// formlarında kullanılan, yazarak filtrelenen + listeden seçilebilen
// İl/İlçe alanları.
//
// Serbest metin girişini ENGELLEMEZ (validasyon zorunlu değil) — sadece
// listedeki 81 il/ilçeden birine yakınsa öneri gösterir. Kullanıcı farklı
// bir şey yazmak isterse (ör. yurt dışı adresi, köy adı) yazabilir.
import 'package:flutter/material.dart';
import '../../cekirdek/veri/turkiye_il_ilce.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

class IlAlani extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onSecildi;
  const IlAlani({super.key, required this.controller, this.onSecildi});
  @override
  State<IlAlani> createState() => _IlAlaniState();
}

class _IlAlaniState extends State<IlAlani> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AramaAlani(
        controller: widget.controller,
        focusNode: _focus,
        label: 'İl',
        ikon: Icons.map_outlined,
        oneriler: TurkiyeIlIlce.illeriAra,
        onSecildi: widget.onSecildi,
      );
}

class IlceAlani extends StatefulWidget {
  final TextEditingController controller;
  /// Seçilen ilçe listesini bu ile göre daraltmak için — dolu ve tanınan
  /// bir il ise SADECE o ile ait ilçeler önerilir, aksi halde Türkiye
  /// genelinde arama yapılır.
  final TextEditingController ilController;
  const IlceAlani({super.key, required this.controller, required this.ilController});
  @override
  State<IlceAlani> createState() => _IlceAlaniState();
}

class _IlceAlaniState extends State<IlceAlani> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AramaAlani(
        controller: widget.controller,
        focusNode: _focus,
        label: 'İlçe',
        ikon: Icons.location_city_outlined,
        oneriler: (q) => TurkiyeIlIlce.ilceleriAra(q, il: widget.ilController.text),
      );
}

/// Ortak, yeniden kullanılabilir "yaz + listeden seç" alanı. Dışarıdan
/// verilen [controller]'ı DOĞRUDAN kullanır (RawAutocomplete'in kendi
/// gölge controller'ı YOK) — bu sayede dışarıdan (ör. kayıtlı adres
/// yüklenince) `controller.text = ...` atanması otomatik yansır, ayrıca
/// senkronizasyon kodu/riski gerekmez.
class _AramaAlani extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final IconData ikon;
  final List<String> Function(String sorgu) oneriler;
  final ValueChanged<String>? onSecildi;
  const _AramaAlani({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.ikon,
    required this.oneriler,
    this.onSecildi,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return RawAutocomplete<String>(
        textEditingController: controller,
        focusNode: focusNode,
        optionsBuilder: (TextEditingValue v) {
          final q = v.text.trim();
          if (q.isEmpty) return const Iterable<String>.empty();
          return oneriler(q);
        },
        onSelected: onSecildi,
        fieldViewBuilder: (context, fieldCtrl, fieldFocus, onSubmit) => TextFormField(
          controller: fieldCtrl,
          focusNode: fieldFocus,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(ikon, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderColor),
            ),
          ),
          onFieldSubmitted: (_) => onSubmit(),
        ),
        optionsViewBuilder: (context, onSelectedOption, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: constraints.maxWidth).copyWith(
                maxHeight: 240,
                minHeight: 0,
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final o = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelectedOption(o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Text(o, style: const TextStyle(fontSize: 14)),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
  }
}
