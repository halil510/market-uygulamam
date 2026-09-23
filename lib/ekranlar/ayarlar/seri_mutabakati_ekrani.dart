// lib/ekranlar/ayarlar/seri_mutabakati_ekrani.dart
//
// Fatura Seri Mutabakatı — bu cihaza verilmiş merkezi numara bloklarının
// kullanım durumu ve boşluk (tüketilmiş ama faturası olmayan numara)
// tespiti. Salt okunur. Bkz. SeriMutabakatServisi.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/fatura_seri/seri_mutabakat_servisi.dart';

class SeriMutabakatiEkrani extends StatefulWidget {
  const SeriMutabakatiEkrani({super.key});

  @override
  State<SeriMutabakatiEkrani> createState() => _SeriMutabakatiEkraniState();
}

class _SeriMutabakatiEkraniState extends State<SeriMutabakatiEkrani> {
  SeriMutabakatRaporu? _rapor;
  bool _yukleniyor = true;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() { _yukleniyor = true; _hata = null; });
    try {
      final r = await SeriMutabakatServisi().raporGetir();
      if (!mounted) return;
      setState(() { _rapor = r; _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() { _hata = '$e'; _yukleniyor = false; });
    }
  }

  String _no(String seri, int yil, int n) => '$seri$yil${n.toString().padLeft(9, '0')}';

  String _numaraListesi(BlokMutabakati b, List<int> liste) {
    const enFazla = 10;
    final ilk = liste.take(enFazla).map((n) => _no(b.seri, b.yil, n)).join(', ');
    return liste.length > enFazla ? '$ilk … (+${liste.length - enFazla})' : ilk;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Fatura Seri Mutabakatı',
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
                  child: Text('Rapor alınamadı: $_hata',
                      textAlign: TextAlign.center, style: TextStyle(color: context.textHint))))
              : _icerik(_rapor!),
    );
  }

  Widget _icerik(SeriMutabakatRaporu r) {
    if (r.bloklar.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Bu cihaza henüz merkezi fatura numara bloğu verilmemiş.\n'
          'İlk otomatik faturada kendiliğinden alınır.',
          textAlign: TextAlign.center, style: TextStyle(color: context.textHint)),
      ));
    }
    return RefreshIndicator(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _ozetKarti(r),
          const SizedBox(height: 8),
          ...r.bloklar.map(_blokKarti),
          if (r.blokDisiFaturalar.isNotEmpty) _blokDisiKarti(r.blokDisiFaturalar),
        ],
      ),
    );
  }

  Widget _kart({required Widget child, Color? kenar}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: kenar != null ? Border.all(color: kenar.withAlpha(120)) : null,
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4)],
        ),
        child: child,
      );

  Widget _ozetKarti(SeriMutabakatRaporu r) {
    final temiz = r.toplamBosluk == 0;
    final renk = temiz ? Colors.green : Colors.red;
    return _kart(
      kenar: renk,
      child: Row(children: [
        Icon(temiz ? Icons.verified_outlined : Icons.warning_amber_rounded, color: renk),
        const SizedBox(width: 12),
        Expanded(child: Text(
          temiz
              ? 'Tüm tüketilmiş numaraların faturası mevcut — boşluk yok.'
              : '${r.toplamBosluk} numara tüketilmiş ama faturası bulunamadı. '
                'Bu numaralar GİB sıra kontrolünde boşluk olarak görünebilir; '
                'nedenini (kalıcı silme vb.) inceleyin.',
          style: TextStyle(fontSize: 13, color: context.textPrimary),
        )),
      ]),
    );
  }

  Widget _blokKarti(BlokMutabakati b) {
    final tarih = DateTime.tryParse(b.tahsisZamani ?? '');
    final durumEtiket = b.kalan > 0 ? 'Aktif' : 'Tükendi';
    final durumRenk = b.sorunlu ? Colors.red : (b.kalan > 0 ? Colors.blue : Colors.grey);
    return _kart(
      kenar: b.sorunlu ? Colors.red : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${b.seri} ${b.yil} · ${b.baslangic}–${b.bitis}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: durumRenk.withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: Text(durumEtiket, style: TextStyle(fontSize: 11, color: durumRenk, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _deger('Kullanılan', '${b.kullanilan}'),
          _deger('Kalan', '${b.kalan}'),
          if (b.silinmis.isNotEmpty) _deger('Silinmiş', '${b.silinmis.length}'),
          if (b.bosluklar.isNotEmpty) _deger('Boşluk', '${b.bosluklar.length}', renk: Colors.red),
        ]),
        if (b.bosluklar.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Faturası olmayan: ${_numaraListesi(b, b.bosluklar)}',
              style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
        if (b.silinmis.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Silinmiş: ${_numaraListesi(b, b.silinmis)}',
              style: TextStyle(fontSize: 12, color: context.textSecondary)),
        ],
        if (tarih != null) ...[
          const SizedBox(height: 4),
          Text('Tahsis: ${DateFormat('dd.MM.yyyy HH:mm').format(tarih)}',
              style: TextStyle(fontSize: 11, color: context.textHint)),
        ],
      ]),
    );
  }

  Widget _deger(String etiket, String deger, {Color? renk}) => Text.rich(TextSpan(children: [
        TextSpan(text: '$etiket: ', style: TextStyle(fontSize: 12, color: context.textHint)),
        TextSpan(text: deger, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: renk ?? context.textPrimary)),
      ]));

  Widget _blokDisiKarti(List<String> liste) {
    const enFazla = 10;
    final metin = liste.take(enFazla).join(', ') +
        (liste.length > enFazla ? ' … (+${liste.length - enFazla})' : '');
    return _kart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Blok dışı faturalar (${liste.length})',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary)),
        const SizedBox(height: 4),
        Text('Merkezi sistem öncesi oluşturulmuş ya da elle numara girilmiş faturalar. '
            'Hata değildir; bilgi amaçlıdır.',
            style: TextStyle(fontSize: 12, color: context.textHint)),
        const SizedBox(height: 4),
        Text(metin, style: TextStyle(fontSize: 12, color: context.textSecondary)),
      ]),
    );
  }
}
