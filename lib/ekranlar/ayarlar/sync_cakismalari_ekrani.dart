// lib/ekranlar/ayarlar/sync_cakismalari_ekrani.dart
//
// Protokol §12 — SYNC ÇAKIŞMALARI ekranı: iki cihaz aynı kaydı bağımsız
// değiştirdiğinde (ör. Cihaz A fiyatı 125, Cihaz B 129 yapmışsa), pull
// senkronu bunu artık sessizce ezmiyor — Veritabani._cakismaKaydetGerekirse
// tarafından buraya bir kayıt düşülüyor. Bu ekran o kayıtları listeler ve
// kullanıcıya üç seçenek sunar: gelen (buluttan gelen, zaten uygulanmış)
// değeri kabul et, yerel (üzerine yazılan) değeri geri yükle, ya da
// kaydı ilgili ekrandan manuel düzenleyip burada sadece kapat.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/sync_cakisma_deposu.dart';
import '../../modeller/sync_cakisma_model.dart';
import '../../servisler/auth_servisi.dart';
import '../../widgetlar/ortak/onay_dialog.dart';

const _tabloEtiketleri = {
  'urunler': 'Ürün', 'cari': 'Cari', 'satislar': 'Satış',
  'stok_hareket': 'Stok Hareketi', 'kasa_hareketleri': 'Kasa Hareketi',
  'borclar': 'Borç', 'faturalar': 'Fatura', 'masalar': 'Masa',
  'banka_hesaplar': 'Banka Hesabı', 'kredi_kartlari': 'Kredi Kartı',
};

class SyncCakismalariEkrani extends StatefulWidget {
  const SyncCakismalariEkrani({super.key});

  @override
  State<SyncCakismalariEkrani> createState() => _SyncCakismalariEkraniState();
}

class _SyncCakismalariEkraniState extends State<SyncCakismalariEkrani> {
  final _depo = SyncCakismaDeposu();
  List<SyncCakismaModel> _cakismalar = [];
  bool _yukleniyor = true;
  bool _sadeceCozulmemis = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final liste = await _depo.listele(sadeceCozulmemis: _sadeceCozulmemis);
      if (!mounted) return;
      setState(() { _cakismalar = liste; _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  String _tabloAdi(String tablo) => _tabloEtiketleri[tablo] ?? tablo;

  Future<void> _cozGelen(SyncCakismaModel c) async {
    final onay = await OnayDialog.goster(context,
        baslik: 'Buluttaki değer kalsın mı?',
        icerik: 'Bu kayıt zaten buluttan gelen değerle güncellenmiş durumda. '
            'Onaylarsanız çakışma "çözüldü" olarak işaretlenir, veri değişmez.',
        onayYazi: 'Evet, buluttaki değer kalsın', ikon: Icons.cloud_done_outlined);
    if (!onay || c.id == null) return;
    await _depo.gelenIleCoz(c.id!, kullanici: AuthServisi().aktifAd);
    if (mounted) _yukle();
  }

  Future<void> _cozYerel(SyncCakismaModel c) async {
    final onay = await OnayDialog.goster(context,
        baslik: 'Yerel (eski) değer geri yüklensin mi?',
        icerik: 'Buluttan gelen değer, bu cihazdaki değişikliğinizin üzerine '
            'yazmıştı. Onaylarsanız kaydınız geri yüklenir ve bir sonraki '
            'senkronda buluta gönderilir.',
        onayYazi: 'Evet, benim değerimi geri yükle',
        onayRengi: Colors.orange.shade800, ikon: Icons.history);
    if (!onay || c.id == null) return;
    await _depo.yerelIleCoz(c.id!, kullanici: AuthServisi().aktifAd);
    if (mounted) _yukle();
  }

  Future<void> _cozManuel(SyncCakismaModel c) async {
    final onay = await OnayDialog.goster(context,
        baslik: 'Manuel çözüldü olarak işaretle',
        icerik: 'Bu kaydı ilgili ekrandan kendiniz düzenlediyseniz, çakışmayı '
            'burada kapatabilirsiniz. Veri değiştirilmez.',
        onayYazi: 'Evet, kapat', ikon: Icons.edit_outlined);
    if (!onay || c.id == null) return;
    await _depo.manuelCoz(c.id!, kullanici: AuthServisi().aktifAd);
    if (mounted) _yukle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: 'Sync Çakışmaları',
        aksiyonlar: [
          IconButton(
            icon: Icon(_sadeceCozulmemis ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            tooltip: _sadeceCozulmemis ? 'Çözülmüşleri de göster' : 'Sadece çözülmemişler',
            onPressed: () {
              setState(() => _sadeceCozulmemis = !_sadeceCozulmemis);
              _yukle();
            },
          ),
        ],
        gradyanli: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : _cakismalar.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_outline, size: 48, color: context.textHint),
                    const SizedBox(height: 12),
                    Text(
                      _sadeceCozulmemis
                          ? 'Çözülmemiş senkron çakışması yok.'
                          : 'Hiç senkron çakışması kaydedilmemiş.',
                      style: TextStyle(color: context.textHint),
                    ),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _yukle,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _cakismalar.length,
                    itemBuilder: (c, i) => _CakismaKarti(
                      cakisma: _cakismalar[i],
                      tabloAdi: _tabloAdi(_cakismalar[i].tablo),
                      onGelen: () => _cozGelen(_cakismalar[i]),
                      onYerel: () => _cozYerel(_cakismalar[i]),
                      onManuel: () => _cozManuel(_cakismalar[i]),
                    ),
                  ),
                ),
    );
  }
}

class _CakismaKarti extends StatelessWidget {
  final SyncCakismaModel cakisma;
  final String tabloAdi;
  final VoidCallback onGelen;
  final VoidCallback onYerel;
  final VoidCallback onManuel;

  const _CakismaKarti({
    required this.cakisma,
    required this.tabloAdi,
    required this.onGelen,
    required this.onYerel,
    required this.onManuel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cakisma.cozuldu
              ? context.textHint.withAlpha(60)
              : Colors.orange.shade400,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            cakisma.cozuldu ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 18,
            color: cakisma.cozuldu ? Colors.green : Colors.orange.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$tabloAdi kaydında çakışma',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary)),
          ),
          Text(DateFormat('dd.MM.yyyy HH:mm').format(cakisma.tarih),
              style: TextStyle(fontSize: 11, color: context.textHint)),
        ]),
        const SizedBox(height: 10),
        ...cakisma.alanFarklari.entries.map((e) {
          final v = e.value;
          final yerel = v is Map ? v['yerel'] : null;
          final gelen = v is Map ? v['gelen'] : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(
                width: 90,
                child: Text(e.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textSecondary)),
              ),
              Expanded(
                child: Row(children: [
                  Expanded(
                    child: _degerKutusu('Sizde (kaybedildi)', yerel, TsRenk.zemin(TsRenk.uyari), Colors.orange.shade800),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _degerKutusu('Buluttan (uygulandı)', gelen, TsRenk.zemin(TsRenk.basarili), Colors.green.shade800),
                  ),
                ]),
              ),
            ]),
          );
        }),
        if (!cakisma.cozuldu) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: onYerel,
              icon: const Icon(Icons.history, size: 16),
              label: const Text('Benimkini kullan'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade800),
            ),
            OutlinedButton.icon(
              onPressed: onGelen,
              icon: const Icon(Icons.cloud_done_outlined, size: 16),
              label: const Text('Buluttakini kullan'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade800),
            ),
            TextButton.icon(
              onPressed: onManuel,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Manuel düzenledim'),
            ),
          ]),
        ] else ...[
          const SizedBox(height: 6),
          Text(
            '${cakisma.cozumTipi == 'yerel' ? 'Sizin değeriniz' : cakisma.cozumTipi == 'gelen' ? 'Buluttaki değer' : 'Manuel'} '
            'kabul edildi — ${cakisma.cozenKullanici ?? ''} '
            '${cakisma.cozumTarihi != null ? DateFormat('dd.MM.yyyy HH:mm').format(cakisma.cozumTarihi!) : ''}',
            style: TextStyle(fontSize: 11, color: context.textHint, fontStyle: FontStyle.italic),
          ),
        ],
      ]),
    );
  }

  Widget _degerKutusu(String etiket, dynamic deger, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(etiket, style: TextStyle(fontSize: 9, color: fg.withAlpha(200))),
        Text('${deger ?? '—'}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
