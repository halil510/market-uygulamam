// lib/ekranlar/satis/iade/iade_kaydet_butonu.dart
//
// İade sekmesinin gradyanlı "İade Et" butonu (iade_ekrani.dart'tan ayrıldı).
import 'package:flutter/material.dart';

import '../../../tasarim_sistemi/tasarim_sistemi.dart';

class IadeKaydetButonu extends StatelessWidget {
  final bool yukleniyor;
  final VoidCallback onTap;

  const IadeKaydetButonu({super.key, required this.yukleniyor, required this.onTap});

  static const _renk = TsRenk.uyari;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: yukleniyor
            ? null
            : LinearGradient(
                colors: [_renk, _renk.withAlpha(200)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: yukleniyor ? _renk.withAlpha(150) : null,
        boxShadow: yukleniyor
            ? const []
            : [BoxShadow(color: _renk.withAlpha(90), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: yukleniyor ? null : onTap,
          child: Center(
            child: yukleniyor
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.assignment_return, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('İade Et',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2)),
                  ]),
          ),
        ),
      ),
    );
  }
}
