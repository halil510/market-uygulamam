// lib/ekranlar/ayarlar/log_ekrani.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/log_servisi.dart';
import '../../servisler/bildirim_servisi.dart';

class LogEkrani extends ConsumerStatefulWidget {
  const LogEkrani({super.key});
  @override
  ConsumerState<LogEkrani> createState() => _LogEkraniState();
}

class _LogEkraniState extends ConsumerState<LogEkrani> {
  List<Map<String, dynamic>> _loglar = [];
  bool _yukleniyor = true;
  String _filtre = 'Tümü';
  static const _seviyeler = ['Tümü', 'bilgi', 'uyari', 'hata', 'kritik'];
  final _fmt = DateFormat('dd.MM.yy HH:mm:ss');

  @override
  void initState() { 
    super.initState(); 
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle()); 
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final loglar = await LogServisi().dbdenGetir(
        seviye: _filtre == 'Tümü' ? null : LogSeviye.values.firstWhere((s) => s.name == _filtre),
        limit: 200,
      );
      if (!mounted) return;
      setState(() { _loglar = loglar; _yukleniyor = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('Log yükleme hatası: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _temizle() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (bCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logları Temizle'),
        content: const Text('Tüm log kayıtları silinecek. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(bCtx, false), child: const Text('Hayır')),
          FilledButton(
            onPressed: () => Navigator.pop(bCtx, true),
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _yukleniyor = true);
    try {
      await LogServisi().temizle();
      if (mounted) {
        BildirimServisi.basari(context, 'Loglar temizlendi');
        await _yukle();
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Temizleme hatası: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  /// 🔥 Tüm logları panoya kopyala (formatlı)
  Future<void> _kopyalaTumLoglar() async {
    if (_loglar.isEmpty) {
      _snack('Kopyalanacak log yok', Colors.orange);
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('MarketPlus Log Raporu - ${DateTime.now().toLocal()}');
    buffer.writeln('─' * 50);
    buffer.writeln('Filtre: $_filtre');
    buffer.writeln('Toplam: ${_loglar.length} kayıt');
    buffer.writeln('─' * 50);
    buffer.writeln('');
    
    for (final r in _loglar) {
      final seviye = r['seviye']?.toString() ?? '?';
      final zaman = r['zaman'] != null 
          ? _fmt.format(DateTime.tryParse(r['zaman'].toString()) ?? DateTime.now())
          : '-';
      final mesaj = r['mesaj']?.toString() ?? '-';
      buffer.writeln('[$zaman] $seviye | $mesaj');
      if (r['hata'] != null) {
        buffer.writeln('  HATA: ${r['hata']}');
      }
      if (r['yigin'] != null) {
        buffer.writeln('  STACK: ${r['yigin']}');
      }
      buffer.writeln('');
    }
    
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    _snack('${_loglar.length} log kaydı panoya kopyalandı', Colors.green);
  }

  /// 🔥 Sadece hata ve kritik logları kopyala
  Future<void> _kopyalaHatalar() async {
    final hataLoglar = _loglar.where((r) {
      final seviye = r['seviye']?.toString();
      return seviye == 'hata' || seviye == 'kritik';
    }).toList();
    
    if (hataLoglar.isEmpty) {
      _snack('Hata/kritik log bulunamadı', Colors.orange);
      return;
    }
    
    final buffer = StringBuffer();
    buffer.writeln('MarketPlus Hata Logları - ${DateTime.now().toLocal()}');
    buffer.writeln('─' * 50);
    buffer.writeln('Toplam ${hataLoglar.length} hata/kritik kaydı');
    buffer.writeln('─' * 50);
    buffer.writeln('');
    
    for (final r in hataLoglar) {
      final seviye = r['seviye']?.toString() ?? 'hata';
      final zaman = r['zaman'] != null 
          ? _fmt.format(DateTime.tryParse(r['zaman'].toString()) ?? DateTime.now())
          : '-';
      final mesaj = r['mesaj']?.toString() ?? '-';
      buffer.writeln('[$zaman] $seviye | $mesaj');
      if (r['hata'] != null) {
        buffer.writeln('  HATA: ${r['hata']}');
      }
      if (r['yigin'] != null) {
        buffer.writeln('  STACK: ${r['yigin']}');
      }
      buffer.writeln('');
    }
    
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    _snack('${hataLoglar.length} hata/kritik log panoya kopyalandı', Colors.green);
  }

  void _snack(String mesaj, Color renk) {
    if (!mounted) return;
    // 🔴 UX TUTARLILIK DÜZELTMESİ: bkz. aynı düzeltme diğer ekranlarda —
    // artık paylaşılan BildirimServisi kullanılıyor.
    if (renk == Colors.red) {
      BildirimServisi.hata(context, mesaj);
    } else if (renk == Colors.orange) {
      BildirimServisi.uyari(context, mesaj);
    } else {
      BildirimServisi.basari(context, mesaj);
    }
  }

  Color _renk(String? seviye) {
    switch (seviye) {
      case 'bilgi':  return Colors.blue;
      case 'uyari':  return Colors.orange;
      case 'hata':   return Colors.red;
      case 'kritik': return Colors.purple;
      default:       return context.textSecondary;
    }
  }

  IconData _ikon(String? seviye) {
    switch (seviye) {
      case 'bilgi':  return Icons.info_outline;
      case 'uyari':  return Icons.warning_amber;
      case 'hata':   return Icons.error_outline;
      case 'kritik': return Icons.bug_report;
      default:       return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Uygulama Logları',
        aksiyonlar: [
          // 🔥 Kopyala menüsü
          PopupMenuButton<String>(
            icon: const Icon(Icons.copy),
            tooltip: 'Kopyala',
            onSelected: (value) {
              if (value == 'tum') _kopyalaTumLoglar();
              if (value == 'hatalar') _kopyalaHatalar();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'tum', child: ListTile(
                dense: true, leading: Icon(Icons.copy_all, color: AppRenkler.primary), title: Text('Tüm Logları Kopyala'),
              )),
              const PopupMenuItem(value: 'hatalar', child: ListTile(
                dense: true, leading: Icon(Icons.error_outline, color: Colors.red), title: Text('Sadece Hataları Kopyala'),
              )),
            ],
          ),
          IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _temizle, tooltip: 'Temizle'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _yukle, tooltip: 'Yenile'),
        ],
        geriTusu: false,
      ),
      body: Column(children: [
        // Filtre
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(10),
          child: Row(children: _seviyeler.map((s) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(s.toUpperCase(), style: const TextStyle(fontSize: 11)),
              selected: _filtre == s,
              selectedColor: _renk(s == 'Tümü' ? null : s).withAlpha(51),
              onSelected: (_) { setState(() => _filtre = s); _yukle(); },
            ),
          )).toList()),
        ),
        // Liste
        Expanded(
          child: _yukleniyor
              ? const TsYukleniyor(iskelet: true)
              : _loglar.isEmpty
                  ? const TsBosDurum(
                      ikon: Icons.check_circle_outline,
                      baslik: 'Log yok — uygulama temiz çalışıyor',
                      renk: TsRenk.basarili,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemCount: _loglar.length,
                      itemBuilder: (_, i) {
                        final r = _loglar[i];
                        final seviye = r['seviye']?.toString();
                        final renk = _renk(seviye);
                        final zaman = r['zaman'] != null
                            ? DateTime.tryParse(r['zaman'].toString())
                            : null;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: TsRenk.kart(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: renk.withAlpha(76)),
                          ),
                          child: ExpansionTile(
                            leading: Icon(_ikon(seviye), color: renk, size: 20),
                            title: Text(r['mesaj']?.toString() ?? '-',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${seviye?.toUpperCase() ?? ''} • ${zaman != null ? _fmt.format(zaman) : '-'}',
                              style: TextStyle(fontSize: 10, color: renk),
                            ),
                            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            children: [
                              if (r['hata'] != null) _detayTile('Hata', r['hata'].toString(), renk),
                              if (r['yigin'] != null) _detayTile('Stack Trace', r['yigin'].toString(), context.textSecondary),
                              if (r['ek'] != null) _detayTile('Ek Bilgi', r['ek'].toString(), context.textSecondary),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  Widget _detayTile(String baslik, String icerik, Color renk) => Container(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(baslik, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
      const SizedBox(height: 4),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: TsRenk.arkaplan(context), borderRadius: BorderRadius.circular(6)),
        child: Text(icerik, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
      ),
    ]),
  );
}