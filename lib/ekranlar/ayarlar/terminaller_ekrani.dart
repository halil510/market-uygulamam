// lib/ekranlar/ayarlar/terminaller_ekrani.dart
//
// Terminaller — merkezi fatura numaralandırmada her cihaz bir "terminal".
// Cihazlar ilk faturada kendiliğinden kaydolur; bu ekran onları
// adlandırmak ve kaybolan/çalınan bir cihazı PASİFE almak içindir (pasif
// terminale sunucu yeni numara bloğu vermez — bkz.
// supabase_terminal_aktif_kontrolu.sql).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/fatura_seri/terminal_servisi.dart';

class TerminallerEkrani extends StatefulWidget {
  const TerminallerEkrani({super.key});

  @override
  State<TerminallerEkrani> createState() => _TerminallerEkraniState();
}

class _TerminallerEkraniState extends State<TerminallerEkrani> {
  final _servis = TerminalYonetimServisi();
  List<BulutTerminal> _liste = [];
  int? _buCihazId;
  bool _yukleniyor = true;
  bool _islemDevam = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() { _yukleniyor = true; _hata = null; });
    try {
      final buCihaz = await TerminalServisi().mevcutTerminal();
      final liste = await _servis.listele();
      if (!mounted) return;
      setState(() {
        _liste = liste;
        _buCihazId = buCihaz?.terminalId;
        _yukleniyor = false;
      });
    } catch (e) {
      if (mounted) setState(() { _hata = '$e'; _yukleniyor = false; });
    }
  }

  Future<void> _adDegistir(BulutTerminal t) async {
    final ctrl = TextEditingController(text: t.ad);
    final yeniAd = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terminal Adı'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Ad (ör. Kasa 1, Depo Tableti)',
            helperText: 'Kod: ${t.kod}',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Kaydet')),
        ],
      ),
    );
    ctrl.dispose();
    if (yeniAd == null || yeniAd.isEmpty || yeniAd == t.ad) return;
    await _guncelle(t, ad: yeniAd, basari: 'Ad güncellendi');
  }

  Future<void> _aktifDegistir(BulutTerminal t, bool aktif) async {
    if (!aktif) {
      final buCihaz = t.id == _buCihazId;
      final onay = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Terminali Pasife Al'),
          content: Text(
            '"${t.ad}" artık yeni fatura numarası bloğu alamayacak.\n\n'
            'Cihazda önceden alınmış blokta kalan numaralar (en fazla birkaç '
            'tane) kullanılabilir; sonrasında o cihazdan fatura kesilemez.'
            '${buCihaz ? '\n\n⚠️ Bu, ŞU AN KULLANDIĞINIZ cihaz.' : ''}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pasife Al'),
            ),
          ],
        ),
      );
      if (onay != true) return;
    }
    await _guncelle(t, aktif: aktif, basari: aktif ? 'Terminal aktif edildi' : 'Terminal pasife alındı');
  }

  Future<void> _guncelle(BulutTerminal t,
      {String? ad, bool? aktif, required String basari}) async {
    if (_islemDevam) return;
    setState(() => _islemDevam = true);
    try {
      await _servis.guncelle(t.id, ad: ad, aktif: aktif);
      if (!mounted) return;
      BildirimServisi.basari(context, basari);
      await _yukle();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Güncellenemedi: $e');
    } finally {
      if (mounted) setState(() => _islemDevam = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Terminaller',
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Yenile', onPressed: _yukle),
        ],
        gradyanli: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : _hata != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Terminaller okunamadı: $_hata',
                      textAlign: TextAlign.center, style: TextStyle(color: context.textHint))))
              : _liste.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Henüz kayıtlı terminal yok.\n'
                        'Her cihaz ilk faturasında kendiliğinden kaydolur.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textHint))))
                  : RefreshIndicator(
                      onRefresh: _yukle,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: _liste.map(_kart).toList(),
                      ),
                    ),
    );
  }

  Widget _kart(BulutTerminal t) {
    final buCihaz = t.id == _buCihazId;
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: t.aktif ? null : Border.all(color: Colors.red.withAlpha(120)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4)],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Icon(Icons.point_of_sale_outlined,
              color: t.aktif ? Colors.indigo : Colors.red),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(t.ad,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                      color: context.textPrimary))),
              if (buCihaz) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.indigo.withAlpha(30),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('Bu cihaz',
                      style: TextStyle(fontSize: 10, color: Colors.indigo,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
            Text(t.kod, style: TextStyle(fontSize: 11, color: context.textHint)),
            const SizedBox(height: 4),
            Text(
              '${t.blokSayisi} numara bloğu'
              '${t.sonTahsis != null ? ' · son: ${fmt.format(t.sonTahsis!)}' : ''}',
              style: TextStyle(fontSize: 12, color: context.textSecondary)),
            if (!t.aktif)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('PASİF — yeni numara alamaz',
                    style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Adı değiştir',
          onPressed: _islemDevam ? null : () => _adDegistir(t),
        ),
        Switch(
          value: t.aktif,
          onChanged: _islemDevam ? null : (v) => _aktifDegistir(t, v),
        ),
      ]),
    );
  }
}
