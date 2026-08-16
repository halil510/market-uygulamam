// lib/ekranlar/urun/widgets/urun_form_alanlari.dart
//
// Bağımsız widget'lar — setState gerektiren alanlar callback ile yönetilir.
// Ürün ekleme formunun yeniden kullanılabilir parçaları.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_plus/tasarim_sistemi/tasarim_sistemi.dart';
// ── Bölüm başlığı ──────────────────────────────────────────────────────────
class FormBolum extends StatelessWidget {
  final String baslik;
  final IconData ikon;
  const FormBolum({super.key, required this.baslik, required this.ikon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(children: [
        Icon(ikon, size: 16, color: TsRenk.primaryKoyu),
        const SizedBox(width: 6),
        Text(baslik, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: TsRenk.primaryKoyu, letterSpacing: 0.5)),
        const Expanded(child: Divider(indent: 8)),
      ]),
    );
  }
}

// ── Metin alanı ─────────────────────────────────────────────────────────────
class FormMetinAlani extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool zorunlu;
  final Widget? suffix;

  const FormMetinAlani({
    super.key,
    required this.controller,
    required this.label,
    this.zorunlu = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: suffix,
        ),
        validator: zorunlu
            ? (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null
            : null,
      ),
    );
  }
}

// ── Sayı alanı ──────────────────────────────────────────────────────────────
class FormSayiAlani extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool zorunlu;
  final Widget? suffix;

  const FormSayiAlani({
    super.key,
    required this.controller,
    required this.label,
    this.zorunlu = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: suffix,
        ),
        validator: zorunlu
            ? (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null
            : null,
      ),
    );
  }
}

// ── Birim seçim ─────────────────────────────────────────────────────────────
class FormBirimSecim extends StatelessWidget {
  final List<String> birimler;
  final String secilenBirim;
  final void Function(String) onDegisti;

  const FormBirimSecim({
    super.key,
    required this.birimler,
    required this.secilenBirim,
    required this.onDegisti,
  });

  @override
  Widget build(BuildContext context) {
    final gecerliDeger = birimler.contains(secilenBirim)
        ? secilenBirim
        : (birimler.isNotEmpty ? birimler.first : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        value: gecerliDeger,
        decoration: const InputDecoration(
          labelText: 'Birim',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: birimler
            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
            .toList(),
        onChanged: (v) { if (v != null) onDegisti(v); },
      ),
    );
  }
}

// ── Alış KDV seçim ──────────────────────────────────────────────────────────
class FormAlisKdvSecim extends StatelessWidget {
  final String secilenKdv;
  final void Function(String) onDegisti;

  const FormAlisKdvSecim({
    super.key,
    required this.secilenKdv,
    required this.onDegisti,
  });

  static const _oranlar = ['0', '1', '8', '10', '18', '20'];

  @override
  Widget build(BuildContext context) {
    final gecerli = _oranlar.contains(secilenKdv) ? secilenKdv : '18';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        value: gecerli,
        decoration: const InputDecoration(
          labelText: 'Alış KDV%',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: _oranlar
            .map((v) => DropdownMenuItem(value: v, child: Text('%$v')))
            .toList(),
        onChanged: (v) { if (v != null) onDegisti(v); },
      ),
    );
  }
}

// ── Otomatik tamamlamalı alan ────────────────────────────────────────────────
class FormOtomatikAlan extends StatelessWidget {
  final TextEditingController controller;
  final List<String> secenekler;
  final String label;
  final String? ipucu;
  final void Function(String) onDegisti;

  const FormOtomatikAlan({
    super.key,
    required this.controller,
    required this.secenekler,
    required this.label,
    required this.onDegisti,
    this.ipucu,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Autocomplete<String>(
        initialValue: TextEditingValue(text: controller.text),
        optionsBuilder: (tv) {
          if (tv.text.isEmpty) return secenekler;
          return secenekler.where(
              (a) => a.toLowerCase().contains(tv.text.toLowerCase()));
        },
        fieldViewBuilder: (ctx, ctrl, fn, onSub) {
          // Senkronize et
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ctrl.text != controller.text) ctrl.text = controller.text;
          });
          return TextFormField(
            controller: ctrl,
            focusNode: fn,
            onChanged: (v) {
              controller.text = v;
              onDegisti(v);
            },
            decoration: InputDecoration(
              labelText: label,
              hintText: ipucu ?? 'Yaz veya listeden seç',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onFieldSubmitted: (_) => onSub(),
          );
        },
        onSelected: (v) {
          controller.text = v;
          onDegisti(v);
        },
        optionsViewBuilder: (ctx, onSel, opts) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(
                shrinkWrap: true, padding: EdgeInsets.zero,
                children: opts
                    .map((a) => ListTile(
                          dense: true,
                          title: Text(a),
                          onTap: () => onSel(a),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Grup seçim (ana/alt) ─────────────────────────────────────────────────────
class FormGrupSecim extends StatelessWidget {
  final List<String> gruplar;
  final String? secilenGrup;
  final String label;
  final void Function(String?) onDegisti;

  const FormGrupSecim({
    super.key,
    required this.gruplar,
    required this.secilenGrup,
    required this.label,
    required this.onDegisti,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Autocomplete<String>(
        initialValue: TextEditingValue(text: secilenGrup ?? ''),
        optionsBuilder: (tv) {
          if (tv.text.isEmpty) return gruplar;
          return gruplar.where(
              (g) => g.toLowerCase().contains(tv.text.toLowerCase()));
        },
        fieldViewBuilder: (ctx, ctrl, fn, onSub) {
          return TextFormField(
            controller: ctrl,
            focusNode: fn,
            onChanged: (v) {
              final val = v.trim().isEmpty ? null : v.trim();
              onDegisti(val);
            },
            decoration: InputDecoration(
              labelText: label,
              hintText: 'Yaz veya listeden seç',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_drop_down, size: 22),
                onPressed: () { ctrl.clear(); fn.requestFocus(); },
                padding: EdgeInsets.zero,
              ),
            ),
            onFieldSubmitted: (_) => onSub(),
          );
        },
        onSelected: (v) => onDegisti(v),
        optionsViewBuilder: (ctx, onSel, opts) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true, padding: EdgeInsets.zero,
                children: opts
                    .map((g) => ListTile(
                          dense: true,
                          title: Text(g),
                          onTap: () => onSel(g),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
