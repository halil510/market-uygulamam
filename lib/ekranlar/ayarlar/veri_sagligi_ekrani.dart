// lib/ekranlar/ayarlar/veri_sagligi_ekrani.dart
//
// VERİ SAĞLIĞI MERKEZİ (protokol §13) — SQLite/FK/mutabakat/negatif
// stok/mükerrer barkod/yetim kayıt/sync kuyruğu-çakışması/yedekleme
// durumunu tek ekranda YEŞİL/SARI/KIRMIZI olarak gösterir. Düzeltmesi
// güvenli (kanıtlanmış mutabakat fonksiyonu olan) kontrollerde bir
// "Düzelt" butonu sunar — hiçbir kontrol kullanıcı onayı olmadan veri
// değiştirmez.
//
// 🔴 DÜZELTME (derin analiz 2026-10-07): ekran 20 kontrolün TAMAMI bitene
// kadar boş "yükleniyor" gösteriyordu; tek bir kontrol hata atınca liste
// boş kalıp "0 / 0 / 0" yazıyor, kullanıcıya hiçbir şey söylenmiyordu.
// Artık sonuçlar geldikçe listelenir (ilerleme çubuğuyla), çalıştırılamayan
// kontroller nedeniyle birlikte gösterilir, yenileme eski çalıştırmayı iptal eder.
import 'package:flutter/material.dart';

import '../../cekirdek/utils/hata_utils.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/veri_sagligi_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../widgetlar/ortak/onay_dialog.dart';

const _varsayilanDuzeltAciklama =
    'Bu işlem, uyuşmayan kayıtları hareket geçmişinden yeniden hesaplayarak '
    'düzeltir. Geri alınamaz ama güvenlidir — mevcut hareket kayıtlarına '
    'dokunmaz, sadece özet alanları (bakiye/stok) yeniden hesaplar.';

class VeriSagligiEkrani extends StatefulWidget {
  const VeriSagligiEkrani({super.key});

  @override
  State<VeriSagligiEkrani> createState() => _VeriSagligiEkraniState();
}

class _VeriSagligiEkraniState extends State<VeriSagligiEkrani> {
  final _servis = VeriSagligiServisi();
  List<SaglikKontrolSonucu> _sonuclar = const [];
  bool _calisiyor = false;
  String? _duzeltilenId;

  /// Her yeni çalıştırmada artar; eski çalıştırmanın geç gelen sonuçları
  /// (ör. kullanıcı Yenile'ye bastıysa) yok sayılır.
  int _calistirmaNo = 0;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    final no = ++_calistirmaNo;
    setState(() {
      _sonuclar = const [];
      _calisiyor = true;
    });
    try {
      await for (final sonuc in _servis.kontrolleriAkisla()) {
        // return, akışın aboneliğini iptal eder: kalan kontroller çalışmaz.
        if (!mounted || no != _calistirmaNo) return;
        setState(() => _sonuclar = [..._sonuclar, sonuc]);
      }
    } finally {
      if (mounted && no == _calistirmaNo) setState(() => _calisiyor = false);
    }
  }

  Future<void> _duzeltUygula(SaglikKontrolSonucu k) async {
    final duzelt = k.duzelt;
    if (duzelt == null) return;
    final onay = await OnayDialog.goster(context,
        baslik: '${k.baslik} düzeltilsin mi?',
        icerik: '${k.mesaj}\n\n${k.duzeltAciklama ?? _varsayilanDuzeltAciklama}',
        onayYazi: 'Evet, düzelt',
        ikon: Icons.build_outlined);
    if (!onay || !mounted) return;

    setState(() => _duzeltilenId = k.id);
    try {
      final duzeltilenSayi = await duzelt();
      if (!mounted) return;
      BildirimServisi.basari(context, '$duzeltilenSayi kayıt düzeltildi ✓');
    } catch (e) {
      if (mounted) {
        BildirimServisi.hata(context, 'Düzeltme başarısız: ${kullaniciyaHataMetni(e)}');
      }
    } finally {
      if (mounted) setState(() => _duzeltilenId = null);
    }
    if (mounted) await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final duzeltmeKilitli = _calisiyor || _duzeltilenId != null;
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Veri Sağlığı Merkezi',
        gradyanli: false,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yeniden kontrol et',
            onPressed: duzeltmeKilitli ? null : _yukle,
          ),
        ],
      ),
      body: _sonuclar.isEmpty && _calisiyor
          ? const TsYukleniyor()
          : RefreshIndicator(
              onRefresh: _yukle,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  if (_calisiyor)
                    _IlerlemeCubugu(
                        tamamlanan: _sonuclar.length, toplam: _servis.kontrolSayisi),
                  _OzetSatiri(sonuclar: _sonuclar),
                  const SizedBox(height: 16),
                  ..._kategoriBolumleri(duzeltmeKilitli),
                ],
              ),
            ),
    );
  }

  List<Widget> _kategoriBolumleri(bool duzeltmeKilitli) {
    final gruplu = <String, List<SaglikKontrolSonucu>>{};
    for (final s in _sonuclar) {
      gruplu.putIfAbsent(s.kategori, () => []).add(s);
    }
    return [
      for (final MapEntry(key: kategori, value: kontroller) in gruplu.entries) ...[
        _KategoriBasligi(kategori),
        for (final k in kontroller)
          _KontrolKarti(
            kontrol: k,
            duzeltiliyor: _duzeltilenId == k.id,
            onDuzelt: k.duzelt == null || duzeltmeKilitli ? null : () => _duzeltUygula(k),
          ),
        const SizedBox(height: 8),
      ],
    ];
  }
}

Color _durumRengi(SaglikDurum d) => switch (d) {
      SaglikDurum.yesil => Colors.green,
      SaglikDurum.sari => Colors.orange,
      SaglikDurum.kirmizi => Colors.red,
    };

IconData _durumIkonu(SaglikDurum d) => switch (d) {
      SaglikDurum.yesil => Icons.check_circle,
      SaglikDurum.sari => Icons.warning_amber_rounded,
      SaglikDurum.kirmizi => Icons.error,
    };

class _IlerlemeCubugu extends StatelessWidget {
  final int tamamlanan;
  final int toplam;

  const _IlerlemeCubugu({required this.tamamlanan, required this.toplam});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Kontroller çalışıyor… $tamamlanan / $toplam',
            style: TextStyle(fontSize: 12, color: context.textSecondary)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: toplam == 0 ? null : tamamlanan / toplam),
      ]),
    );
  }
}

class _OzetSatiri extends StatelessWidget {
  final List<SaglikKontrolSonucu> sonuclar;

  const _OzetSatiri({required this.sonuclar});

  int _say(SaglikDurum d) => sonuclar.where((s) => s.durum == d).length;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _OzetKart(sayi: _say(SaglikDurum.yesil), renk: Colors.green, etiket: 'Sağlıklı')),
      const SizedBox(width: 8),
      Expanded(child: _OzetKart(sayi: _say(SaglikDurum.sari), renk: Colors.orange, etiket: 'Uyarı')),
      const SizedBox(width: 8),
      Expanded(child: _OzetKart(sayi: _say(SaglikDurum.kirmizi), renk: Colors.red, etiket: 'Kritik')),
    ]);
  }
}

class _OzetKart extends StatelessWidget {
  final int sayi;
  final Color renk;
  final String etiket;

  const _OzetKart({required this.sayi, required this.renk, required this.etiket});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: renk.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: renk.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(children: [
          Text('$sayi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: renk)),
          const SizedBox(height: 2),
          Text(etiket, style: TextStyle(fontSize: 11, color: renk)),
        ]),
      ),
    );
  }
}

class _KategoriBasligi extends StatelessWidget {
  final String kategori;

  const _KategoriBasligi(this.kategori);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6, top: 6),
      child: Text(kategori,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.textHint,
              letterSpacing: 0.5)),
    );
  }
}

class _KontrolKarti extends StatelessWidget {
  final SaglikKontrolSonucu kontrol;
  final bool duzeltiliyor;
  final VoidCallback? onDuzelt;

  const _KontrolKarti({
    required this.kontrol,
    required this.duzeltiliyor,
    this.onDuzelt,
  });

  @override
  Widget build(BuildContext context) {
    final renk = _durumRengi(kontrol.durum);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4)],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(kontrol.calistirilamadi ? Icons.help_outline : _durumIkonu(kontrol.durum),
            color: renk, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kontrol.baslik,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary)),
            const SizedBox(height: 2),
            Text(kontrol.mesaj, style: TextStyle(fontSize: 12, color: context.textSecondary)),
          ]),
        ),
        if (kontrol.duzelt != null) ...[
          const SizedBox(width: 8),
          if (duzeltiliyor)
            const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            OutlinedButton(
              onPressed: onDuzelt,
              style: OutlinedButton.styleFrom(
                  foregroundColor: renk,
                  padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: const Text('Düzelt', style: TextStyle(fontSize: 12)),
            ),
        ],
      ]),
    );
  }
}
