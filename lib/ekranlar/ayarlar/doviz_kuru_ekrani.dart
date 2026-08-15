// lib/ekranlar/ayarlar/doviz_kuru_ekrani.dart
//
// Kullanıcı isteği: "çoklu para birimini merkez bankasından gelsin,
// para birimi ekle olsun, güncelle dediğimizde merkez bankasından
// para birimlerini çeker" — TCMB entegrasyonu ile tamamen yeniden
// yazıldı. Profesyonel muhasebe programları gibi: TCMB'den GERÇEK
// kurları çeker, kullanıcı hangi dövizleri takip edeceğini seçer.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../saglayicilar/riverpod/doviz_provider.dart';
import '../../depolar/doviz_deposu.dart';
import '../../modeller/doviz_model.dart';
import '../../servisler/tcmb_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

/// Yaygın döviz kodları için sembol eşlemesi — TCMB sembol vermez,
/// sadece kod+isim verir, sembolü biz ekliyoruz (görsel amaçlı).
const Map<String, String> _dovizSembolleri = {
  'USD': '\$', 'EUR': '€', 'GBP': '£', 'JPY': '¥', 'CHF': 'Fr',
  'CAD': 'C\$', 'AUD': 'A\$', 'SEK': 'kr', 'NOK': 'kr', 'DKK': 'kr',
  'RUB': '₽', 'CNY': '¥', 'SAR': '﷼', 'KWD': 'د.ك', 'BGN': 'лв',
  'RON': 'lei', 'AED': 'د.إ', 'AZN': '₼', 'GEL': '₾', 'PKR': '₨',
  'QAR': '﷼', 'KRW': '₩', 'XDR': 'SDR',
};

class DovizKuruEkrani extends ConsumerStatefulWidget {
  const DovizKuruEkrani({super.key});

  @override
  ConsumerState<DovizKuruEkrani> createState() => _DovizKuruEkraniState();
}

class _DovizKuruEkraniState extends ConsumerState<DovizKuruEkrani> {
  bool _guncelleniyor = false;

  Future<void> _tcmbdenGuncelle() async {
    setState(() => _guncelleniyor = true);
    try {
      final tcmbKurlari = await TcmbServisi().guncelKurlariGetir();
      final adet = await DovizDeposu().tcmbdenTopluGuncelle(tcmbKurlari);
      ref.invalidate(dovizKurlariProvider);
      if (mounted) {
        BildirimServisi.basari(context,
            adet > 0 ? '✅ $adet para birimi TCMB\'den güncellendi' : 'Güncellenecek para birimi yok — önce "Para Birimi Ekle" ile ekleyin');
      }
    } catch (e) {
      if (mounted) {
        BildirimServisi.hata(context,
            'TCMB\'ye bağlanılamadı. İnternet bağlantınızı kontrol edin. ($e)');
      }
    } finally {
      if (mounted) setState(() => _guncelleniyor = false);
    }
  }

  Future<void> _paraBirimiEkle() async {
    List<TcmbDovizSonuc>? tcmbListesi;
    try {
      tcmbListesi = await TcmbServisi().guncelKurlariGetir();
    } catch (e) {
      if (mounted) {
        BildirimServisi.hata(context, 'TCMB listesi alınamadı: $e');
      }
      return;
    }
    if (!mounted) return;

    final mevcutKodlar = (await DovizDeposu().tumunuGetir(sadeceAktif: false))
        .map((d) => d.kod).toSet();

    // Yukarıdaki mounted kontrolü DovizDeposu await'inden ÖNCEydi;
    // bu await'ten sonra tekrar gerekli.
    if (!mounted) return;
    final secilen = await showModalBottomSheet<TcmbDovizSonuc>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ParaBirimiSecSheet(
        tumDovizler: tcmbListesi!,
        mevcutKodlar: mevcutKodlar,
      ),
    );
    if (secilen == null || !mounted) return;

    await DovizDeposu().paraBirimiEkle(
      secilen,
      sembol: _dovizSembolleri[secilen.kod] ?? secilen.kod,
    );
    ref.invalidate(dovizKurlariProvider);
    if (mounted) {
      BildirimServisi.basari(context, '${secilen.kod} eklendi ve güncel kuru alındı ✓');
    }
  }

  Future<void> _kaldir(DovizModel k) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Para Birimini Kaldır'),
        content: Text('${k.kod} takip listesinden kaldırılsın mı? '
            '(Geçmiş kayıtlar etkilenmez, sadece bu listeden kalkar.)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaldır')),
        ],
      ),
    );
    if (onay != true) return;
    await DovizDeposu().pasifYap(k.kod);
    ref.invalidate(dovizKurlariProvider);
  }

  @override
  Widget build(BuildContext context) {
    final kurlarAsync = ref.watch(dovizKurlariProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Döviz Kurları',
        aksiyonlar: [
          IconButton(
            icon: _guncelleniyor
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync, color: Colors.white),
            tooltip: 'TCMB\'den Güncelle',
            onPressed: _guncelleniyor ? null : _tcmbdenGuncelle,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _paraBirimiEkle,
        icon: const Icon(Icons.add),
        label: const Text('Para Birimi Ekle'),
      ),
      body: kurlarAsync.when(
        loading: () => const TsYukleniyor(iskelet: true),
        error: (e, _) => TsBosDurum(
            ikon: Icons.error_outline, baslik: 'Yüklenemedi: $e', renk: TsRenk.hata),
        data: (kurlar) => ListView(
          padding: const EdgeInsets.all(TsBosluk.lg),
          children: [
            TsKart(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.account_balance, color: TsRenk.bilgi),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kurlar Türkiye Cumhuriyet Merkez Bankası\'nın (TCMB) '
                    'resmi günlük döviz kuru listesinden çekilir. '
                    'Sağ üstteki 🔄 ile güncelleyin, "Para Birimi Ekle" ile '
                    'yeni bir döviz takip listesine ekleyin.',
                    style: TextStyle(fontSize: 12, color: TsRenk.bilgi),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: TsBosluk.xl),
            if (kurlar.isEmpty)
              const TsBosDurum(
                ikon: Icons.currency_exchange,
                baslik: 'Henüz para birimi eklenmedi',
                altyazi: 'Sağ alttaki "Para Birimi Ekle" butonuyla başlayın',
              )
            else
              ...kurlar.map((k) => Padding(
                padding: const EdgeInsets.only(bottom: TsBosluk.md),
                child: _KurKarti(
                  kur: k,
                  onGuncelle: () => ref.invalidate(dovizKurlariProvider),
                  onKaldir: () => _kaldir(k),
                ),
              )),
            const SizedBox(height: 80), // FAB için boşluk
          ],
        ),
      ),
    );
  }
}

/// TCMB'nin tüm döviz listesinden, henüz eklenmemiş olanları seçtiren
/// alt sayfa.
class _ParaBirimiSecSheet extends StatefulWidget {
  final List<TcmbDovizSonuc> tumDovizler;
  final Set<String> mevcutKodlar;
  const _ParaBirimiSecSheet({required this.tumDovizler, required this.mevcutKodlar});

  @override
  State<_ParaBirimiSecSheet> createState() => _ParaBirimiSecSheetState();
}

class _ParaBirimiSecSheetState extends State<_ParaBirimiSecSheet> {
  String _ara = '';

  @override
  Widget build(BuildContext context) {
    final eklenebilir = widget.tumDovizler
        .where((d) => !widget.mevcutKodlar.contains(d.kod))
        .where((d) => _ara.isEmpty ||
            d.kod.toLowerCase().contains(_ara.toLowerCase()) ||
            d.ad.toLowerCase().contains(_ara.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('Para Birimi Seç (TCMB Listesi)',
              style: TsMetin.baslikM.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Ara (USD, Euro, İngiliz...)',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _ara = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: eklenebilir.isEmpty
                ? const Center(child: Text('Eklenebilecek yeni para birimi bulunamadı'))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: eklenebilir.length,
                    itemBuilder: (_, i) {
                      final d = eklenebilir[i];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(_dovizSembolleri[d.kod] ?? d.kod.substring(0, 1)),
                        ),
                        title: Text('${d.kod} — ${d.ad}'),
                        subtitle: Text('Satış: ${d.birimForexSatis.toStringAsFixed(4)} ₺'),
                        onTap: () => Navigator.pop(context, d),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class _KurKarti extends StatefulWidget {
  final DovizModel kur;
  final VoidCallback onGuncelle;
  final VoidCallback onKaldir;
  const _KurKarti({required this.kur, required this.onGuncelle, required this.onKaldir});

  @override
  State<_KurKarti> createState() => _KurKartiState();
}

class _KurKartiState extends State<_KurKarti> {
  late final TextEditingController _alisCtrl;
  late final TextEditingController _satisCtrl;
  bool _kaydediliyor = false;
  bool _elleDuzenle = false;

  @override
  void initState() {
    super.initState();
    _alisCtrl = TextEditingController(
        text: widget.kur.alisKuru > 0 ? widget.kur.alisKuru.toStringAsFixed(4) : '');
    _satisCtrl = TextEditingController(
        text: widget.kur.satisKuru > 0 ? widget.kur.satisKuru.toStringAsFixed(4) : '');
  }

  @override
  void dispose() {
    _alisCtrl.dispose();
    _satisCtrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final alis = double.tryParse(_alisCtrl.text.replaceAll(',', '.'));
    final satis = double.tryParse(_satisCtrl.text.replaceAll(',', '.'));
    if (satis == null || satis <= 0) {
      BildirimServisi.uyari(context, 'Geçerli bir satış kuru girin');
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      await DovizDeposu().kuruGuncelle(widget.kur.kod,
          alisKuru: alis ?? satis, satisKuru: satis);
      if (mounted) {
        BildirimServisi.basari(context, '${widget.kur.kod} kuru elle güncellendi');
        widget.onGuncelle();
        setState(() => _elleDuzenle = false);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kur;
    return TsKart(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: TsRenk.zemin(TsRenk.primary),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(k.sembol,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: TsRenk.primary)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${k.kod} — ${k.ad}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              if (k.guncellemeTarihi != null)
                Text(
                  'Son güncelleme: ${DateFormat('dd.MM.yyyy HH:mm').format(k.guncellemeTarihi!)}',
                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
                )
              else
                const Text('Henüz kur girilmedi — 🔄 ile güncelleyin', style: TextStyle(fontSize: 11, color: TsRenk.uyari)),
            ]),
          ),
          Text('${k.satisKuru.toStringAsFixed(4)} ₺',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: TsRenk.metinIkincil(context), size: 20),
            onSelected: (v) {
              if (v == 'duzenle') setState(() => _elleDuzenle = !_elleDuzenle);
              if (v == 'kaldir') widget.onKaldir();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'duzenle', child: Text('Elle Düzenle')),
              const PopupMenuItem(value: 'kaldir', child: Text('Kaldır')),
            ],
          ),
        ]),
        if (_elleDuzenle) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TsInput(
                etiket: 'Alış Kuru (₺)',
                controller: _alisCtrl,
                klavyeTuru: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TsInput(
                etiket: 'Satış Kuru (₺)',
                controller: _satisCtrl,
                klavyeTuru: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TsButon(
              metin: 'Elle Kaydet',
              ikon: Icons.save_outlined,
              yukleniyor: _kaydediliyor,
              onPressed: _kaydediliyor ? null : _kaydet,
            ),
          ),
        ],
      ]),
    );
  }
}
