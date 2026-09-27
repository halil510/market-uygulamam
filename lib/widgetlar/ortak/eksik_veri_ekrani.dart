// lib/widgetlar/ortak/eksik_veri_ekrani.dart
//
// Başka bir ekrandan veriyle (GoRouter `extra`) açılması gereken bir rota,
// o veri OLMADAN açıldığında (uygulama arka planda kapatılıp geri
// yüklendiğinde, bağlantıyla açıldığında) kırmızı hata ekranı yerine
// gösterilir. (2026-09-28, uygulama robotu buldu: /satis/fis-onizleme ve
// /tedarik/siparis-olustur doğrudan açılınca çöküyordu.)
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EksikVeriEkrani extends StatelessWidget {
  final String baslik;
  final String aciklama;
  const EksikVeriEkrani({super.key, required this.baslik, required this.aciklama});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(baslik)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.info_outline, size: 48),
              const SizedBox(height: 12),
              Text(aciklama, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Ana sayfa'),
              ),
            ]),
          ),
        ),
      );
}
