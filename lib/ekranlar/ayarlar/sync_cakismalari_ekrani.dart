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
import '../../depolar/satis_deposu.dart';
import '../../modeller/sync_cakisma_model.dart';
import '../../modeller/satis_model.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
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
  final _satisDepo = SatisDeposu();
  List<SyncCakismaModel> _cakismalar = [];
  // 🔴 EKLENDİ (kullanıcı bulgusu, 2026-09-21): 'satislar' fis_no
  // çakışması bir '-SYNC' kopyası yarattığında (bkz. Veritabani.
  // _cakismaKorumasiUygula) bu satış artık Satış Listesi/Gün Sonu'ndan
  // gizleniyor — kullanıcının onu HİÇBİR yerde kaybetmemesi için burada,
  // aynı "sync incelemesi" ekranında AYRI bir bölümde gösteriliyor.
  List<SatisModel> _syncKopyalari = [];
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
      final syncKopyalari = await _satisDepo.syncKopyalariGetir();
      if (!mounted) return;
      setState(() {
        _cakismalar = liste;
        _syncKopyalari = syncKopyalari;
        _yukleniyor = false;
      });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _syncKopyasiGercek(SatisModel s) async {
    final onay = await OnayDialog.goster(context,
        baslik: 'Bu gerçek bir satış mı?',
        icerik: '${ParaUtils.kisaFisNo(s.fisNo)} (${ParaUtils.formatla(s.genelToplam)}) '
            'artık normal bir satış olarak Satış Listesi\'nde ve Gün Sonu '
            'Raporu\'nda görünecek.',
        onayYazi: 'Evet, gerçek satış', ikon: Icons.check_circle_outline);
    if (!onay || s.id == null) return;
    await _satisDepo.syncKopyasiGercekOlarakIsaretle(s.id!);
    if (!mounted) return;
    BildirimServisi.basari(context, 'Satış normal listelere eklendi');
    _yukle();
  }

  Future<void> _syncKopyasiSil(SatisModel s) async {
    // 🔴 DÜZELTME (kritik — derin denetimde bulundu): bu buton codebase'in
    // her yerinde uygulanan "faturalandırılmış bir satış doğrudan
    // silinemez" kuralını hiç kontrol etmiyordu.
    if (s.id != null) {
      final faturaId = await FaturalandirmaServisi.mevcutFaturaId(satisId: s.id);
      if (faturaId != null) {
        if (!mounted) return;
        await OnayDialog.goster(context,
            baslik: 'Bu Satış Faturalandırılmış',
            icerik: 'Bu kopya için zaten bir fatura kesilmiş — doğrudan '
                'silinemez. Düzeltme yapmak için "İade Et" kullanın.',
            onayYazi: 'Tamam', ikon: Icons.info_outline, iptalGoster: false);
        return;
      }
    }
    if (!mounted) return;
    final onay = await OnayDialog.goster(context,
        baslik: 'Bu kopya silinsin mi?',
        icerik: '${ParaUtils.kisaFisNo(s.fisNo)} (${ParaUtils.formatla(s.genelToplam)}) '
            'silinecek; stok, kasa ve cari etkisi otomatik olarak geri '
            'alınacak. Bu işlem geri alınamaz.',
        onayYazi: 'Evet, sil', onayRengi: Colors.red, ikon: Icons.delete_outline);
    if (!onay || s.id == null) return;
    try {
      await _satisDepo.sil(s.id!, neden: 'Senkron çakışması kopyası — kullanıcı onayıyla silindi');
      if (!mounted) return;
      BildirimServisi.basari(context, 'Kopya silindi, stok/kasa/cari geri alındı');
      _yukle();
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  String _tabloAdi(String tablo) => _tabloEtiketleri[tablo] ?? tablo;

  Future<void> _cozGelen(SyncCakismaModel c) async {
    // 🔴 FAZ 3 (madde 4, 2026-09-21): "işlem verisi" (satış/stok/kasa/
    // banka hareketi vb.) tablolarında artık otomatik LWW üzerine yazma
    // yok — bu buton ARTIK GERÇEKTEN veri değiştiriyor (bkz.
    // SyncCakismaDeposu.gelenIleCoz). "Master veri"de (urunler/cari vb.)
    // zaten uygulanmıştı, tekrar yazmak zararsız — metin artık ikisi
    // için de doğru, tek/genel bir ifadeyle.
    final onay = await OnayDialog.goster(context,
        baslik: 'Buluttaki değer uygulansın mı?',
        icerik: 'Onaylarsanız bu kayıt buluttan gelen değerle güncellenir '
            '(bu cihazdaki değişikliğiniz kaybolur) ve çakışma "çözüldü" '
            'olarak işaretlenir.',
        onayYazi: 'Evet, buluttaki değeri uygula', ikon: Icons.cloud_done_outlined);
    if (!onay || c.id == null) return;
    await _depo.gelenIleCoz(c.id!, kullanici: AuthServisi().aktifAd);
    if (mounted) _yukle();
  }

  Future<void> _cozYerel(SyncCakismaModel c) async {
    // 🔴 FAZ 3 (madde 4, 2026-09-21): metin artık "üzerine yazılmıştı"
    // diye VARSAYMIYOR — "işlem verisi" tablolarında artık hiç otomatik
    // üzerine yazma olmuyor (yerel zaten korunmuş durumda olabilir), bu
    // eylem yine de güvenli/idempotent: yerel_kayit'i tabloya yazar.
    final onay = await OnayDialog.goster(context,
        baslik: 'Bu cihazdaki değer kalsın mı?',
        icerik: 'Onaylarsanız bu kayıt bu cihazdaki (yerel) değerle '
            'güncellenir/korunur ve bir sonraki senkronda buluta '
            'gönderilir.',
        onayYazi: 'Evet, bu cihazdaki değeri uygula',
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
          : (_cakismalar.isEmpty && _syncKopyalari.isEmpty)
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
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (_syncKopyalari.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 2),
                          child: Text(
                            'Senkron Kopyası Şüpheli Satışlar (${_syncKopyalari.length})',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, left: 2),
                          child: Text(
                            'Bu satışlar bulut senkronunda aynı fiş numarasıyla ama '
                            'farklı bir kayıtla çakıştığı için Satış Listesi ve Gün '
                            'Sonu Raporu\'ndan gizlendi. Genellikle "Veritabanını '
                            'Temizle" sonrası buluttaki eski veri tam silinmediğinde '
                            'oluşur — gerçek bir satışsa "Gerçek satış", eski bir '
                            'kopyaysa "Kopya, sil" seçin.',
                            style: TextStyle(fontSize: 11, color: context.textSecondary),
                          ),
                        ),
                        ..._syncKopyalari.map((s) => _SyncKopyasiKarti(
                              satis: s,
                              onGercek: () => _syncKopyasiGercek(s),
                              onSil: () => _syncKopyasiSil(s),
                            )),
                        if (_cakismalar.isNotEmpty) const Divider(height: 28),
                      ],
                      ..._cakismalar.map((c) => _CakismaKarti(
                            cakisma: c,
                            tabloAdi: _tabloAdi(c.tablo),
                            onGelen: () => _cozGelen(c),
                            onYerel: () => _cozYerel(c),
                            onManuel: () => _cozManuel(c),
                          )),
                    ],
                  ),
                ),
    );
  }
}

class _SyncKopyasiKarti extends StatelessWidget {
  final SatisModel satis;
  final VoidCallback onGercek;
  final VoidCallback onSil;

  const _SyncKopyasiKarti({
    required this.satis,
    required this.onGercek,
    required this.onSil,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade400),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(ParaUtils.kisaFisNo(satis.fisNo),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary)),
          ),
          Text(DateFormat('dd.MM.yyyy HH:mm').format(satis.tarih),
              style: TextStyle(fontSize: 11, color: context.textHint)),
        ]),
        const SizedBox(height: 6),
        Text(
          '${satis.cariAdi ?? satis.odemeYontemi} — ${ParaUtils.formatla(satis.genelToplam)}',
          style: TextStyle(fontSize: 13, color: context.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
            onPressed: onGercek,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Gerçek satış'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade800),
          ),
          OutlinedButton.icon(
            onPressed: onSil,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Kopya, sil'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade800),
          ),
        ]),
      ]),
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
