// lib/ekranlar/masa/masa_liste_ekrani.dart
// Masa / Restoran modülü — ana ekran.
// Tıklama → MasaDetayEkrani'na yönlendirir
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../servisler/masa/qr_siparis_cekici_servisi.dart';
import '../../servisler/masa/masa_qr_yazdir_servisi.dart';

import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../widgetlar/ortak/bulut_durum_widget.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../cekirdek/utils/hata_utils.dart';
import '../../modeller/masa_model.dart';
import '../../saglayicilar/riverpod/masa_provider.dart';
import '../../depolar/masa_deposu.dart';
import 'masa_detay_ekrani.dart';
import '../../tasarim_sistemi/ts_yetki.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../widgetlar/ortak/onay_dialog.dart';

class MasaListeEkrani extends ConsumerStatefulWidget {
  /// true: Ayarlar'dan açılan yönetim görünümü (masa ekleme + QR yazdırma).
  final bool yonetim;
  const MasaListeEkrani({super.key, this.yonetim = false});
  @override
  ConsumerState<MasaListeEkrani> createState() => _MasaListeEkraniState();
}

class _MasaListeEkraniState extends ConsumerState<MasaListeEkrani> {
  String _kategori = 'Tümü';

  /// Masaüstü ana-detay görünümünde sağ panelde açık masa (yoksa null).
  int? _seciliMasaId;

  /// Geniş pencerede (diğer masaüstü ekranlarıyla aynı 1100 px eşiği) liste +
  /// sağda gömülü detay paneli; yönetim modu her zaman sade liste.
  bool get _masaustu => !widget.yonetim && MediaQuery.sizeOf(context).width > 1100;

  @override
  void initState() {
    super.initState();
    // QR menü siparişlerini periyodik çeken servisi burada başlatıyoruz
    // çünkü ref'e ihtiyacı var (masa listesini yenilemek için).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      QrSiparisCekiciServisi().baslatRef(ref);
    });
  }

  @override
  void dispose() {
    QrSiparisCekiciServisi().ekranKapandi();
    super.dispose();
  }

  // Durum renkleri
  Color _durumRenk(String durum) => switch (durum) {
    'dolu'          => const Color(0xFFF57C00),      // Turuncu
    'hesap_istendi' => const Color(0xFFD32F2F),      // Kırmızı
    'rezerve'       => const Color(0xFF1976D2),      // Mavi
    _               => const Color(0xFF2E7D32),      // Yeşil (boş)
  };

  // Durum ikonları
  IconData _durumIkon(String durum) => switch (durum) {
    'dolu'          => Icons.restaurant_menu,
    'hesap_istendi' => Icons.notifications_active,
    'rezerve'       => Icons.event_busy,
    _               => Icons.table_restaurant_outlined,
  };

  // Durum etiketleri
  String _durumEtiket(String durum) => switch (durum) {
    'dolu'          => 'Dolu',
    'hesap_istendi' => 'Hesap İstendi',
    'rezerve'       => 'Rezerve',
    _               => 'Boş',
  };

  @override
  Widget build(BuildContext context) {
    final durum = ref.watch(masaListesiProvider);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: widget.yonetim ? 'Masa Yönetimi' : 'Masalar',
        aksiyonlar: [
          const BulutDurumIkonu(),
          // Kullanıcı isteği: 400 üründen QR menüde hangilerinin
          // görüneceğini seçebileceği ekrana erişim.
          IconButton(
            icon: const Icon(Icons.checklist_rtl),
            tooltip: 'QR Menü Ürünlerini Seç',
            onPressed: () => context.push('/masa/qr-urun-secim'),
          ),
          if (widget.yonetim) IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Tüm Masaların QR Kartlarını Yazdır',
            onPressed: _tumQrYazdir,
          ),
          if (widget.yonetim) PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            tooltip: 'Masa Ekle',
            onSelected: (v) {
              if (v == 'tek') _masaEkleDialog();
              if (v == 'toplu') _topluMasaEkleDialog();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'tek', child: Row(children: [
                Icon(Icons.add_box_outlined, size: 18), SizedBox(width: 8), Text('Tek Masa Ekle'),
              ])),
              PopupMenuItem(value: 'toplu', child: Row(children: [
                Icon(Icons.grid_view_outlined, size: 18), SizedBox(width: 8), Text('Toplu Masa Ekle (10, 20...)'),
              ])),
            ],
          ),
        ],
        modul: TsModul.masa,
      ),
      body: durum.when(
        loading: () => const Center(child: AppYukleniyor()),
        error: (e, _) => Center(child: Text('Hata: ${bildirimMetniniSadelestir(e.toString())}')),
        data: (masalar) {
          if (masalar.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.table_restaurant_outlined, size: 64, color: context.textHint),
              const SizedBox(height: 12),
              Text('Henüz masa eklenmedi', style: TextStyle(color: context.textSecondary)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: widget.yonetim
                    ? _masaEkleDialog
                    : () => context.push('/masa/yonet'),
                icon: const Icon(Icons.add),
                label: Text(widget.yonetim ? 'İlk Masayı Ekle' : 'Ayarlar\'dan Masa Ekle'),
              ),
            ]));
          }

          final kategoriler = ['Tümü', ...{for (final m in masalar) m.kategori}];
          final gosterilen = _kategori == 'Tümü'
              ? masalar : masalar.where((m) => m.kategori == _kategori).toList();

          final doluSayi  = masalar.where((m) => m.durum == 'dolu').length;
          final hesapSayi = masalar.where((m) => m.durum == 'hesap_istendi').length;
          final rezerveSayi = masalar.where((m) => m.durum == 'rezerve').length;

          final sol = Column(children: [
            // Özet bandı
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)]),
              child: Row(children: [
                _ozetItem('Toplam', '${masalar.length}', Icons.table_restaurant, const Color(0xFF455A64)),
                _ozetItem('Dolu', '$doluSayi', Icons.restaurant_menu, const Color(0xFFF57C00)),
                _ozetItem('Hesap İstendi', '$hesapSayi', Icons.notifications_active, const Color(0xFFD32F2F)),
                if (rezerveSayi > 0) _ozetItem('Rezerve', '$rezerveSayi', Icons.event_busy, const Color(0xFF1976D2)),
              ]),
            ),

            // Kategori filtre çipleri
            if (kategoriler.length > 1)
              SizedBox(height: 40, child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: kategoriler.map((k) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(k, style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _kategori == k ? Colors.white : context.textPrimary)),
                    selected: _kategori == k,
                    selectedColor: TsRenk.masaAcik,
                    backgroundColor: context.cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: _kategori == k ? TsRenk.masaAcik : context.borderColor),
                    ),
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _kategori = k),
                  ),
                )).toList(),
              )),
            const SizedBox(height: 8),

            // Masa grid
            Expanded(child: RefreshIndicator(
              onRefresh: () => ref.read(masaListesiProvider.notifier).yukle(),
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                // Telefonda 2 kolon; tablet/PC'de sığdığı kadar (sabit 2 idi).
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200, mainAxisExtent: 226,
                    mainAxisSpacing: 10, crossAxisSpacing: 10),
                itemCount: gosterilen.length,
                itemBuilder: (_, i) {
                  final m = gosterilen[i];
                  final renk = _durumRenk(m.durum);
                  final secili = _masaustu && m.id == _seciliMasaId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    // ✅ TIKLAMA → mobilde MasaDetayEkrani'na yönlendir,
                    // masaüstünde sağ panelde aç.
                    onTap: () async {
                      if (_masaustu) {
                        setState(() => _seciliMasaId = m.id);
                        return;
                      }
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MasaDetayEkrani(masa: m),
                        ),
                      );
                      if (mounted) ref.read(masaListesiProvider.notifier).yukle();
                    },
                    onLongPress: () => _masaMenusu(m),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: secili
                            ? Border.all(color: TsRenk.masaAcik, width: 2.5)
                            : Border.all(color: Color.fromARGB(80, renk.red, renk.green, renk.blue), width: 1.5),
                        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)]),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Color.fromARGB(31, renk.red, renk.green, renk.blue),
                                borderRadius: BorderRadius.circular(10)),
                              child: Icon(_durumIkon(m.durum), color: renk, size: 22),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Color.fromARGB(31, renk.red, renk.green, renk.blue),
                                borderRadius: BorderRadius.circular(8)),
                              child: Text(_durumEtiket(m.durum),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: renk)),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Text(m.ad, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text('${m.kategori} • ${m.kapasite} kişi',
                              style: TextStyle(fontSize: 11, color: context.textSecondary)),
                          const Spacer(),
                          if (m.durum != 'bos') ...[
                            if (m.aktifOzet != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(m.aktifOzet!,
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: context.textSecondary,
                                        fontWeight: FontWeight.w500)),
                              ),
                            Text(ParaUtils.formatla(m.aktifToplam),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18,
                                    color: TsRenk.primaryKoyu)),
                            if (m.acilisZamani != null)
                              Text(_gecenSure(m.acilisZamani!),
                                  style: TextStyle(fontSize: 10, color: context.textSecondary)),
                          ] else
                            Text('Sipariş almak için dokunun',
                                style: TextStyle(fontSize: 11, color: context.textSecondary)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            )),
          ]);

          if (!_masaustu) return sol;

          // ── Masaüstü: sol liste + sağ gömülü detay paneli ──────────────
          MasaModel? secilen;
          for (final m in masalar) {
            if (m.id == _seciliMasaId) secilen = m;
          }
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.f5): () =>
                  ref.read(masaListesiProvider.notifier).yukle(),
            },
            child: Focus(
              autofocus: secilen == null,
              child: Row(children: [
                Expanded(child: sol),
                VerticalDivider(width: 1, color: context.borderColor),
                SizedBox(
                  width: 460,
                  child: secilen == null
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.touch_app_outlined, size: 56, color: context.textHint),
                            const SizedBox(height: 12),
                            Text('Sipariş için soldan bir masa seçin',
                                style: TextStyle(color: context.textSecondary)),
                            const SizedBox(height: 4),
                            Text('F5: yenile',
                                style: TextStyle(fontSize: 11, color: context.textHint)),
                          ]),
                        )
                      : MasaDetayEkrani(
                          key: ValueKey(secilen.id),
                          masa: secilen,
                          gomulu: true,
                          onKapat: () {
                            if (mounted) setState(() => _seciliMasaId = null);
                            ref.read(masaListesiProvider.notifier).yukle();
                          },
                        ),
                ),
              ]),
            ),
          );
        },
      ),
      floatingActionButton: !widget.yonetim ? null : TsYetkili(child: FloatingActionButton.extended(
        elevation: 6,
        backgroundColor: TsRenk.masaAcik,
        foregroundColor: Colors.white,
        onPressed: _masaEkleDialog,
        icon: const Icon(Icons.add),
        label: const Text('Masa Ekle'),
      )),
    );
  }

  Widget _ozetItem(String etiket, String deger, IconData ikon, Color renk) => Expanded(
    child: Column(children: [
      Icon(ikon, color: renk, size: 20),
      const SizedBox(height: 4),
      Text(deger, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: renk)),
      Text(etiket, style: TextStyle(fontSize: 10, color: context.textSecondary), textAlign: TextAlign.center),
    ]),
  );

  String _gecenSure(DateTime acilis) {
    final fark = DateTime.now().difference(acilis);
    if (fark.inMinutes < 60) return '${fark.inMinutes} dk önce açıldı';
    return '${fark.inHours} sa ${fark.inMinutes % 60} dk önce açıldı';
  }

  void _masaMenusu(MasaModel m) {
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Masayı Düzenle'),
          onTap: () { Navigator.pop(ctx); _masaEkleDialog(duzenle: m); },
        ),
        if (m.durum == 'hesap_istendi')
          ListTile(
            leading: Icon(Icons.notifications_off_outlined, color: context.textSecondary),
            title: const Text('"Hesap İstendi"yi Kaldır'),
            subtitle: const Text('Yanlışlıkla işaretlendiyse geri al'),
            onTap: () async {
              Navigator.pop(ctx);
              await MasaDeposu().masaDurumGuncelle(m.id!, 'dolu');
              ref.read(masaListesiProvider.notifier).yukle();
              if (mounted) {
                BildirimServisi.uyari(context, '"Hesap İstendi" durumu kaldırıldı');
              }
            },
          ),
        if (m.durum == 'rezerve')
          ListTile(
            leading: const Icon(Icons.event_available, color: Colors.green),
            title: const Text('Rezervasyonu İptal Et'),
            onTap: () async {
              Navigator.pop(ctx);
              final onay = await OnayDialog.goster(context,
                  baslik: 'Rezervasyonu İptal Et',
                  icerik: '"${m.ad}" rezervasyonu iptal edilip masa boşa alınacak. Emin misiniz?',
                  onayYazi: 'İptal Et', onayRengi: Colors.red);
              if (!onay || !mounted) return;
              await MasaDeposu().masaDurumGuncelle(m.id!, 'bos');
              ref.read(masaListesiProvider.notifier).yukle();
            },
          ),
        if (m.durum == 'bos')
          TsYetkili(child: ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Masayı Sil', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(ctx);
              final onay = await OnayDialog.goster(context,
                  baslik: 'Masayı Sil',
                  icerik: '"${m.ad}" masası silinecek. Emin misiniz?',
                  onayYazi: 'Sil', onayRengi: Colors.red);
              if (!onay || !mounted) return;
              try {
                await MasaDeposu().masaSil(m.id!);
                ref.read(masaListesiProvider.notifier).yukle();
              } catch (e) {
                if (mounted) BildirimServisi.hata(context, kullaniciyaHataMetni(e));
              }
            },
          ),
          ),
      ]),
    ));
  }

  Future<void> _tumQrYazdir() async {
    final masalar = ref.read(masaListesiProvider).value ?? const <MasaModel>[];
    final liste = [
      for (final m in masalar)
        if (m.id != null) (id: m.id!, ad: m.ad),
    ];
    if (liste.isEmpty) {
      BildirimServisi.hata(context, 'Yazdırılacak masa yok');
      return;
    }
    final ok = await MasaQrYazdirServisi.yazdir(liste);
    if (!ok && mounted) {
      BildirimServisi.hata(context, 'QR adresi üretilemedi (WiFi yok)');
    }
  }

  void _masaEkleDialog({MasaModel? duzenle}) {
    final adCtrl = TextEditingController(text: duzenle?.ad ?? '');
    final kapasiteCtrl = TextEditingController(text: (duzenle?.kapasite ?? 4).toString());
    String kategori = duzenle?.kategori ?? 'Salon';
    const presetler = ['Salon', 'Bahçe', 'Teras', 'Veranda'];

    // Enter / Kaydet ortak yolu. Hata (ör. aynı adlı masa) diyaloğu kapatmaz.
    Future<void> kaydet(BuildContext ctx) async {
      final ad = adCtrl.text.trim();
      if (ad.isEmpty) return;
      final kapasite = ParaUtils.tamSayiCoz(kapasiteCtrl.text) ?? 4;
      try {
        if (duzenle == null) {
          await MasaDeposu().masaEkle(MasaModel(
              ad: ad, kategori: kategori, kapasite: kapasite, durum: 'bos', sira: 0));
        } else {
          // Yalnız ad/kategori/kapasite — durum bayat kopyadan ezilmez.
          await MasaDeposu().masaBilgiGuncelle(duzenle.id!,
              ad: ad, kategori: kategori, kapasite: kapasite);
        }
      } catch (e) {
        if (mounted) BildirimServisi.hata(context, kullaniciyaHataMetni(e));
        return;
      }
      if (ctx.mounted) Navigator.pop(ctx);
      ref.read(masaListesiProvider.notifier).yukle();
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(duzenle == null ? 'Masa Ekle' : 'Masayı Düzenle'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: adCtrl, autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => kaydet(ctx),
            decoration: const InputDecoration(labelText: 'Masa Adı', hintText: 'Örn: Masa 1, Bahçe 3',
                border: OutlineInputBorder())),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft,
              child: Text('Kategori', style: TsMetin.kucukVurgu.copyWith(color: context.textSecondary))),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in {...presetler, kategori})
              ChoiceChip(
                label: Text(k, style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kategori == k ? Colors.white : context.textPrimary)),
                selected: kategori == k,
                selectedColor: TsRenk.masaAcik,
                backgroundColor: context.borderColor,
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: kategori == k ? TsRenk.masaAcik : context.borderColor),
                ),
                onSelected: (_) => setLocal(() => kategori = k),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(controller: kapasiteCtrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Kapasite (kişi)', border: OutlineInputBorder())),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(onPressed: () => kaydet(ctx), child: const Text('Kaydet')),
        ],
      ),
    ));
  }

  void _topluMasaEkleDialog() {
    final onekCtrl = TextEditingController(text: 'Salon');
    final adetCtrl = TextEditingController(text: '10');
    final baslangicCtrl = TextEditingController(text: '1');
    final kapasiteCtrl = TextEditingController(text: '4');
    String kategori = 'Salon';
    const presetler = ['Salon', 'Bahçe', 'Teras', 'Veranda'];
    Future<void> baslangicGuncelle() async {
      final n = await MasaDeposu().sonrakiNo(onekCtrl.text);
      baslangicCtrl.text = n.toString();
    }
    baslangicGuncelle();

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.grid_view_outlined, color: TsRenk.masaAcik),
          SizedBox(width: 8), Text('Toplu Masa Ekle'),
        ]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Örn: "Salon" + 10 → Salon 1, Salon 2 ... Salon 10 olarak '
               '10 ayrı masa kalıcı şekilde oluşturulur.',
              style: TextStyle(fontSize: 12, color: context.textSecondary)),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft,
              child: Text('Kategori', style: TsMetin.kucukVurgu.copyWith(color: context.textSecondary))),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in presetler)
              ChoiceChip(
                label: Text(k, style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kategori == k ? Colors.white : context.textPrimary)),
                selected: kategori == k,
                selectedColor: TsRenk.masaAcik,
                backgroundColor: context.borderColor,
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: kategori == k ? TsRenk.masaAcik : context.borderColor),
                ),
                onSelected: (_) => setLocal(() {
                  kategori = k;
                  onekCtrl.text = k;
                  baslangicGuncelle();
                }),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(controller: onekCtrl,
            onChanged: (_) => baslangicGuncelle(),
            decoration: const InputDecoration(labelText: 'Masa Önek Adı', hintText: 'Örn: Salon, Bahçe Masası',
                border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: adetCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Kaç Masa?', border: OutlineInputBorder()))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: baslangicCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Başlangıç No', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: kapasiteCtrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Kapasite (kişi)', border: OutlineInputBorder())),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.masaAcik),
            onPressed: () async {
              final adet = ParaUtils.tamSayiCoz(adetCtrl.text) ?? 0;
              final onek = onekCtrl.text.trim();
              if (adet <= 0 || adet > 200 || onek.isEmpty) return;
              await MasaDeposu().topluMasaEkle(
                onek: onek,
                adet: adet,
                kategori: kategori,
                kapasite: ParaUtils.tamSayiCoz(kapasiteCtrl.text) ?? 4,
                baslangic: ParaUtils.tamSayiCoz(baslangicCtrl.text) ?? 1,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              ref.read(masaListesiProvider.notifier).yukle();
              if (mounted) {
                BildirimServisi.basari(context, '$adet masa eklendi: $onek ${baslangicCtrl.text}.. ');
              }
            },
            child: const Text('Oluştur'),
          ),
        ],
      ),
    ));
  }
}