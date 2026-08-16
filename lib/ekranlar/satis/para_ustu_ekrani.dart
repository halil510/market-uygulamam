import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
// lib/ekranlar/satis/para_ustu_ekrani.dart
// Para üstü hesaplama + animasyonlu geri bildirim
//
// 🔴 DÜZELTME (derin analiz bulgusu): Bu ekran '/satis/para-ustu'
// rotasında kayıtlıydı ama uygulamanın HİÇBİR YERİNDEN çağrılmıyordu —
// 186 satırlık ölü bir ekrandı. Kasiyer nakit alırken düz bir metin
// kutusuna tutar yazıyordu; oysa burada hazır banknot butonları ve
// büyük puntolu para üstü göstergesi zaten yazılmıştı.
//
// Artık Hızlı Satış'taki nakit ödeme akışına bağlandı. Ekran, alınan
// tutarı Navigator.pop ile GERİ DÖNDÜRÜR (önceden hiçbir şey
// döndürmüyordu). Bağımsız hesaplayıcı olarak açıldığında dönen değer
// yok sayılabilir — geriye dönük uyumlu.
import "package:flutter/material.dart";
import "../../cekirdek/utils/para_utils.dart";

class ParaUstuEkrani extends ConsumerStatefulWidget {
  final double odenmesiGereken;
  const ParaUstuEkrani({super.key, required this.odenmesiGereken});
  @override
  ConsumerState<ParaUstuEkrani> createState() => _ParaUstuEkraniState();
}

class _ParaUstuEkraniState extends ConsumerState<ParaUstuEkrani>
    with TickerProviderStateMixin {
  double _alinan = 0;
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  final _hazirMiktarlar = [5.0, 10.0, 20.0, 50.0, 100.0, 200.0];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut));
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  void _setAlinan(double deger) {
    _alinan = deger;
    if (!mounted) return;
    if (mounted) setState(() {});
    if (deger >= widget.odenmesiGereken) {
      _animCtrl.forward(from: 0);
    }
  }

  double get _ustu => (_alinan - widget.odenmesiGereken).clamp(0, double.infinity);

  String _ustaText() {
    if (_alinan == 0) return "-";
    if (_alinan < widget.odenmesiGereken) return "Eksik: ${ParaUtils.formatla(widget.odenmesiGereken - _alinan)}";
    return ParaUtils.formatla(_ustu);
  }

  Color _renk() {
    if (_alinan == 0) return context.textSecondary;
    if (_alinan < widget.odenmesiGereken) return Colors.red;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: "Para Üstü",
      ),
      body: Column(children: [
        // Tutar kartı
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.green.shade700, Colors.green.shade500]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            const Text("Ödenecek", style: TextStyle(color: Colors.white70, fontSize: 13)),
            Text(ParaUtils.formatla(widget.odenmesiGereken),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          ]),
        ),
        // Alınan para girişi
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            const Text("Alınan Para", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            // Hazır miktarlar
            Wrap(spacing: 8, runSpacing: 8,
              children: _hazirMiktarlar.map((m) {
                final selected = _alinan == m;
                return InkWell(
                  onTap: () => _setAlinan(m),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? TsRenk.basarili : TsRenk.arkaplan(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? TsRenk.basarili : TsRenk.ayirac(context)),
                    ),
                    child: Text(ParaUtils.formatla(m),
                        style: TextStyle(fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : TsRenk.metinBirincil(context))),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Manuel giriş
            TextField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: "Manuel tutar girin...",
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.monetization_on, color: Colors.green),
                suffixText: "₺",
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v.replaceAll(",", ".")) ?? 0;
                _setAlinan(parsed);
              },
            ),
          ]),
        ),
        const Spacer(),
        // Para üstü göstergesi
        ScaleTransition(
          scale: _alinan >= widget.odenmesiGereken ? _scaleAnim : const AlwaysStoppedAnimation(1.0),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _renk().withAlpha(26),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _renk(), width: 2),
            ),
            child: Column(children: [
              Icon(
                _alinan == 0 ? Icons.touch_app
                    : _alinan < widget.odenmesiGereken ? Icons.warning_amber
                    : Icons.check_circle,
                color: _renk(), size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                _alinan >= widget.odenmesiGereken ? "PARA ÜSTÜ" : "DURUM",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: _renk(), letterSpacing: 1.2),
              ),
              Text(
                _ustaText(),
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: _renk()),
              ),
            ]),
          ),
        ),
        // Kapat butonu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: SizedBox(
            width: double.infinity, height: 52,
            child: FilledButton.icon(
              // Alınan tutar yetersizken onaylatmıyoruz — kasiyer
              // yanlışlıkla eksik tahsilatla satışı kapatmasın.
              onPressed: (_alinan > 0 && _alinan < widget.odenmesiGereken)
                  ? null
                  : () => Navigator.pop(context, _alinan == 0 ? null : _alinan),
              style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.green.shade700),
              icon: const Icon(Icons.check, color: Colors.white),
              label: Text(
                  _alinan == 0
                      ? "Tam Tutar"
                      : _alinan < widget.odenmesiGereken
                          ? "Tutar Eksik"
                          : "Onayla",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ),
      ]),
    );
  }
}
