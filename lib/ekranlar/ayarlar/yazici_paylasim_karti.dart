// lib/ekranlar/ayarlar/yazici_paylasim_karti.dart
//
// Ürün Güncelleme'deki arayuz/yazici_paylasim_karti.dart'ın market sürümü.
// Ayarlar > Yazıcılar > Windows Yazıcı → "Yazıcıyı ağa aç": USB'deki etiket yazıcısına telefondan WiFi üzerinden basmak için.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../servisler/bildirim_servisi.dart';
import '../../servisler/yazici_paylasimi.dart';

class YaziciPaylasimKarti extends StatefulWidget {
  const YaziciPaylasimKarti({super.key});
  @override
  State<YaziciPaylasimKarti> createState() => _YaziciPaylasimKartiState();
}

class _YaziciPaylasimKartiState extends State<YaziciPaylasimKarti> {
  List<String> _yazicilar = const [];
  List<String> _adresler = const [];
  String? _secili;
  String? _listeHatasi;
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    List<String> y = const [];
    String? listeHatasi;
    try {
      y = [for (final p in await Printing.listPrinters()) p.name];
    } catch (e) {
      listeHatasi = 'Windows yazıcı listesi alınamadı: $e';
    }
    final kayitli = PaylasimYoneticisi.etkin.value?.yazici ?? await PaylasimYoneticisi.kayitliYazici();
    final a = await yerelAdresler();
    if (!mounted) return;
    setState(() {
      _yazicilar = y;
      _adresler = a;
      _listeHatasi = listeHatasi;
      _secili = kayitli ??
          y.where((e) => e.toLowerCase().contains('xp-490') || e.toLowerCase().contains('xprinter')).firstOrNull ??
          y.firstOrNull;
    });
  }

  Future<void> _ac() async {
    final y = _secili;
    if (y == null) return;
    setState(() => _mesgul = true);
    final ok = await PaylasimYoneticisi.ac(y);
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (ok) BildirimServisi.basari(context, '"$y" ağa açıldı');
  }

  Future<void> _kapat() async {
    setState(() => _mesgul = true);
    await PaylasimYoneticisi.kapat();
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _guvenlikDuvari() async {
    setState(() => _mesgul = true);
    final h = await PaylasimYoneticisi.guvenlikDuvarinaIzinVer();
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (h == null) {
      BildirimServisi.basari(context, 'Güvenlik duvarında $paylasimPortu portuna izin verildi');
    } else {
      BildirimServisi.hata(context, h);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<YaziciPaylasimi?>(
      valueListenable: PaylasimYoneticisi.etkin,
      builder: (context, p, _) => ValueListenableBuilder<String?>(
        valueListenable: PaylasimYoneticisi.baslatmaHatasi,
        builder: (context, baslatmaHatasi, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Bu bilgisayara USB ile takılı etiket yazıcısına telefondan (aynı WiFi ağından) basmak için açın. '
                  'Bu program açık kaldığı sürece telefondan gelen etiketler yazıcıya aktarılır.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (p == null) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(_yazicilar.join('|')),
                    initialValue: _yazicilar.contains(_secili) ? _secili : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Ağa açılacak yazıcı'),
                    items: [for (final y in _yazicilar) DropdownMenuItem(value: y, child: Text(y, overflow: TextOverflow.ellipsis))],
                    onChanged: _mesgul ? null : (v) => setState(() => _secili = v),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _mesgul || _secili == null ? null : _ac,
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Yazıcıyı ağa aç'),
                    ),
                  ),
                ] else ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.wifi_tethering, color: cs.primary),
                    title: Text('Açık: ${p.yazici}'),
                    subtitle: ListenableBuilder(
                      listenable: p,
                      builder: (context, _) => Text(
                        p.isSayisi == 0
                            ? 'Henüz telefondan iş gelmedi'
                            : '${p.isSayisi} iş basıldı · son: ${_saat(p.sonIs!)}',
                      ),
                    ),
                    trailing: TextButton(onPressed: _mesgul ? null : _kapat, child: const Text('Kapat')),
                  ),
                  const Text('Telefonda yazıcı adresi olarak yazın:'),
                  const SizedBox(height: 4),
                  if (_adresler.isEmpty)
                    Text('Bilgisayarın ağ adresi bulunamadı — ağa bağlı mı?', style: TextStyle(color: cs.error))
                  else
                    for (final a in _adresler)
                      Row(
                        children: [
                          SelectableText('$a:$paylasimPortu',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'Kopyala',
                            onPressed: () => Clipboard.setData(ClipboardData(text: a)),
                          ),
                        ],
                      ),
                  ListenableBuilder(
                    listenable: p,
                    builder: (context, _) => p.sonHata == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Son hata: ${p.sonHata}', style: TextStyle(color: cs.error)),
                          ),
                  ),
                ],
                if (_listeHatasi != null && p == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_listeHatasi!, style: TextStyle(color: cs.error)),
                  ),
                if (baslatmaHatasi != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(baslatmaHatasi, style: TextStyle(color: cs.error)),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Telefon bağlanamıyorsa: telefon ve bilgisayar aynı ağda olmalı; Windows güvenlik duvarı '
                  'bağlantıyı engelliyor olabilir.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _mesgul ? null : _guvenlikDuvari,
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('Güvenlik duvarında izin ver (yönetici onayı ister)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _saat(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
