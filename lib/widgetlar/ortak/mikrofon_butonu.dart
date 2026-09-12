// lib/widgetlar/ortak/mikrofon_butonu.dart
//
// Herhangi bir TextField'a "suffixIcon" olarak eklenebilen, dinlerken
// görsel geri bildirim veren mikrofon butonu. Konuşma bitince tanınan
// metni [onMetin] ile geri döndürür.
import 'package:flutter/material.dart';
import '../../servisler/ses_tanima_servisi.dart';
import '../../servisler/bildirim_servisi.dart';

class MikrofonButonu extends StatefulWidget {
  final void Function(String metin) onMetin;
  final String ipucu;
  const MikrofonButonu({super.key, required this.onMetin, this.ipucu = 'Konuşun...'});

  @override
  State<MikrofonButonu> createState() => _MikrofonButonuState();
}

class _MikrofonButonuState extends State<MikrofonButonu> with SingleTickerProviderStateMixin {
  final _ses = SesTanimaServisi();
  bool _dinliyor = false;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    // 🔴 Derin analizde bulundu: kullanıcı mikrofonu açıp dinleme devam
    // ederken bu widget'tan uzaklaşırsa (ör. ekranı kapatırsa), konuşma
    // tanıma oturumu ve alttaki platform mikrofon akışı hiç durdurulmadan
    // arka planda çalışmaya devam ediyordu.
    if (_dinliyor) _ses.durdur();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _baslatDurdur() async {
    if (_dinliyor) {
      await _ses.durdur();
      if (mounted) setState(() => _dinliyor = false);
      return;
    }
    final hazir = await _ses.hazirla();
    if (!hazir) {
      if (mounted) {
        BildirimServisi.uyari(context,
            'Mikrofon kullanılamıyor. Cihaz ayarlarından mikrofon iznini kontrol edin.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _dinliyor = true);
    await _ses.dinlemeyeBasla(
      onSonuc: (_) {}, // canlı önizleme istemiyoruz, sadece final sonuç yeterli
      onBitti: (metin) {
        if (mounted) setState(() => _dinliyor = false);
        if (metin.trim().isNotEmpty) widget.onMetin(metin.trim());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _dinliyor ? 'Dinleniyor... (durdurmak için dokun)' : widget.ipucu,
      icon: _dinliyor
          ? ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.15).animate(
                  CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut)),
              child: const Icon(Icons.mic, color: Colors.red),
            )
          : const Icon(Icons.mic_none_outlined),
      onPressed: _baslatDurdur,
    );
  }
}
