// lib/ekranlar/cari/cari_secim_baglami.dart
//
// Cariler listesini "seçim modunda" kullanmak için (Windows Hızlı Satış:
// müşteri seçimi). Liste bu bağlamın altında açılırsa, bir cariye
// dokunmak detay sayfasına gitmek yerine [onSec]'i çağırır.
import 'package:flutter/material.dart';
import '../../modeller/cari_model.dart';

class CariSecimBaglami extends InheritedWidget {
  final void Function(CariModel cari) onSec;
  const CariSecimBaglami({super.key, required this.onSec, required super.child});

  static CariSecimBaglami? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CariSecimBaglami>();

  @override
  bool updateShouldNotify(CariSecimBaglami old) => false;
}

/// Seçim modundaki listenin üstündeki bilgi çubuğu.
class CariSecimCubugu extends StatelessWidget {
  final String mesaj;
  final VoidCallback onKapat;
  const CariSecimCubugu({super.key, required this.mesaj, required this.onKapat});

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SizedBox(
          height: 44,
          child: Row(children: [
            const SizedBox(width: 12),
            Text(mesaj, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: onKapat,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Kapat'),
            ),
            const SizedBox(width: 8),
          ]),
        ),
      );
}

/// Cariler listesini TAM EKRAN bir pencerede açar; seçilen cariyi döndürür.
Future<CariModel?> cariListesindenSec(BuildContext context, Widget cariListesi) {
  return showDialog<CariModel>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      child: CariSecimBaglami(
        onSec: (c) => Navigator.of(ctx).pop(c),
        child: Column(children: [
          CariSecimCubugu(
            mesaj: 'Müşteri seç — listeden bir cariye tıklayın',
            onKapat: () => Navigator.of(ctx).pop(),
          ),
          Expanded(child: cariListesi),
        ]),
      ),
    ),
  );
}
