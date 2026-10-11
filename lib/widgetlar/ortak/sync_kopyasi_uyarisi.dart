// lib/widgetlar/ortak/sync_kopyasi_uyarisi.dart
//
// Satış Listesi ve Gün Sonu Raporu'ndan gizlenen senkron-çakışması kopyası
// satışlar varsa, kullanıcıyı Sync Çakışmaları ekranına yönlendiren uyarı.
//
// Önceden iki ekranda ayrı (private) kopyaları vardı ve her ikisi de
// FutureBuilder'a `future: SatisDeposu().syncKopyalariGetir()` veriyordu:
// üst widget her yeniden çizildiğinde TÜM kopya satışlar cari join'iyle
// yeniden çekiliyordu — sadece adet göstermek için. Artık sorgu bir kez,
// COUNT(*) ile çalışır.
import '../../tasarim_sistemi/ts_token.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../depolar/satis_deposu.dart';

class SyncKopyasiUyarisi extends StatefulWidget {
  /// Adetin ardından gelen metin (ör. "… satış gizlendi").
  final String mesaj;

  /// true: kenarlıklı, yuvarlatılmış kart (liste içine gömülü);
  /// false: tam genişlikte şerit.
  final bool kart;

  const SyncKopyasiUyarisi({super.key, required this.mesaj, this.kart = false});

  @override
  State<SyncKopyasiUyarisi> createState() => _SyncKopyasiUyarisiState();
}

class _SyncKopyasiUyarisiState extends State<SyncKopyasiUyarisi> {
  late final Future<int> _adet = SatisDeposu().syncKopyaSayisi();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _adet,
      builder: (context, snapshot) {
        final adet = snapshot.data ?? 0;
        if (adet == 0) return const SizedBox.shrink();
        const turuncu = TsRenk.uyari;
        return InkWell(
          onTap: () => context.push('/ayarlar/sync-cakismalari'),
          child: Container(
            width: widget.kart ? null : double.infinity,
            margin: widget.kart ? const EdgeInsets.only(bottom: 10) : null,
            padding: EdgeInsets.symmetric(horizontal: widget.kart ? 12 : 16, vertical: 10),
            decoration: BoxDecoration(
              color: TsRenk.zemin(turuncu, opaklik: 0.08),
              borderRadius: widget.kart ? BorderRadius.circular(10) : null,
              border: widget.kart ? Border.all(color: turuncu.withValues(alpha: 0.35)) : null,
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: turuncu),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$adet ${widget.mesaj}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: turuncu,
                        fontWeight: FontWeight.w600)),
              ),
              const Icon(Icons.chevron_right, size: 18, color: turuncu),
            ]),
          ),
        );
      },
    );
  }
}
