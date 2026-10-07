// lib/ekranlar/masa/masa_urun_ekle_ekrani.dart
import 'dart:async';
import 'package:market_plus/cekirdek/utils/metin_arama.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../cekirdek/utils/hata_utils.dart';
import '../../modeller/urun_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/promosyon_deposu.dart';
import '../../modeller/promosyon_model.dart';
import '../../servisler/urun_fiyat_hesaplayici.dart';
import '../../saglayicilar/riverpod/masa_provider.dart';
import '../../servisler/barkod_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../widgetlar/ortak/donanim_barkod_dinleyici.dart';

class MasaUrunEkleEkrani extends ConsumerStatefulWidget {
  final int masaId;
  const MasaUrunEkleEkrani({super.key, required this.masaId});

  @override
  ConsumerState<MasaUrunEkleEkrani> createState() => _MasaUrunEkleEkraniState();
}

class _MasaUrunEkleEkraniState extends ConsumerState<MasaUrunEkleEkrani> {
  final _araCtrl = TextEditingController();
  final _depo = UrunDeposu();
  List<UrunModel> _urunler = [];
  List<UrunModel> _aramaSonuclari = [];
  bool _yukleniyor = true;
  bool _islemAktif = false;
  String _kategori = 'Tümü';
  Timer? _debounce;
  int _aramaId = 0;
  final _araOdak = FocusNode();

  /// Geniş pencerede (diğer masaüstü ekranlarıyla aynı 1100 px eşiği):
  /// ürün ekledikçe ekran KAPANMAZ, sağda canlı adisyon paneli görünür —
  /// garson/kasiyer tek oturumda çok ürün girebilir. Telefon/tabletteki
  /// "tek ürün ekle → geri dön" davranışı aynen korunur.
  bool get _masaustu => MediaQuery.sizeOf(context).width > 1100;

  @override
  void initState() {
    super.initState();
    _yukle();
    _araCtrl.addListener(_aramaChanged);
    // Arama kutusundayken Esc: doluysa önce aramayı temizler. Boşken olay
    // işlenmez; uygulama genelindeki "Esc = Geri" (masaustu_yan_menu.dart)
    // sayfayı kapatır. Esc'i burada ayrıca Shortcuts ile bağlamak, genel
    // işleyiciyle ÇİFT çalışıp iki sayfa geri atıyordu.
    _araOdak.onKeyEvent = (node, olay) {
      if (olay is KeyDownEvent &&
          olay.logicalKey == LogicalKeyboardKey.escape &&
          _araCtrl.text.isNotEmpty) {
        setState(() => _araCtrl.clear());
        _aramaChanged();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _araCtrl.dispose();
    _araOdak.dispose();
    super.dispose();
  }

  /// Aktif promosyonlar (urunId → liste): kartta, adisyona girecek GERÇEK fiyat
  /// gösterilsin diye (MasaDeposu.kalemEkle aynı kuralı uygular).
  Map<int, List<PromosyonModel>> _promolar = {};

  /// Ürünün 1 adet için masada uygulanacak fiyatı.
  double _fiyat(UrunModel u) =>
      UrunFiyatHesaplayici.hesapla(u, 1, _promolar[u.id]);

  Future<void> _promolariYukle() async {
    try {
      final tum = await PromosyonDeposu().tumunuGetir(sadecaAktif: true);
      final harita = <int, List<PromosyonModel>>{};
      for (final p in tum.where((p) => p.aktif && p.gecerli)) {
        (harita[p.urunId] ??= []).add(p);
      }
      if (mounted) setState(() => _promolar = harita);
    } catch (_) { /* promosyon okunamazsa liste fiyatı gösterilir */ }
  }

  Future<void> _yukle() async {
    _promolariYukle();
    try {
      final u = await _depo.tumunuGetir(sadecaAktif: true);
      if (mounted) setState(() { _urunler = u; _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _aramaChanged() {
    _debounce?.cancel();
    final q = _araCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _aramaSonuclari = []);
      return;
    }
    if (q.length < 2) return;
    final aramaId = ++_aramaId;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final s = await _depo.ara(q, limit: 20);
        if (!mounted || aramaId != _aramaId) return;
        setState(() => _aramaSonuclari = s);
      } catch (_) { /* arama iptal edildi veya sorgu hatası — eski sonuçlar korunur */ }
    });
  }

  List<UrunModel> get _filtrelenmis {
    final q = aramaNormalize(_araCtrl.text).trim();
    var liste = _urunler;
    if (_kategori != 'Tümü') {
      liste = liste.where((u) => (u.anaGrup ?? 'Diğer') == _kategori).toList();
    }
    if (q.isEmpty) return liste;
    return liste.where((u) =>
        aramaNormalize(u.urunAdi).contains(q) ||
        aramaNormalize(u.barkod ?? '').contains(q)).toList();
  }

  List<String> get _kategoriler =>
      ['Tümü', ...{for (final u in _urunler) u.anaGrup ?? 'Diğer'}];

  Future<void> _urunEkle(UrunModel urun, {double miktar = 1}) async {
    if (_islemAktif) return;
    setState(() => _islemAktif = true);
    try {
      await ref.read(masaSiparisProvider(widget.masaId).notifier).urunEkle(
        urunId: urun.id!,
        urunAdi: urun.urunAdi,
        birimFiyat: urun.satisFiyati,
        kdvOran: double.tryParse(urun.kdvOran) ?? 18,
        miktar: miktar,
      );
      // 🔴 Bulundu: bu ekran masaya İLK ürün eklendiğinde masanın
      // durumunu 'dolu' yapıyordu (veritabanında doğru), ama masa
      // LİSTESİ (kat planı) ekranına hiç haber vermiyordu. O ekran
      // kendi önbelleğindeki eski listeyi göstermeye devam ediyor,
      // masa hâlâ "boş" görünüyordu — ta ki başka bir işlem (masa
      // açma/kapama vb.) o listeyi tazeleyene kadar. Artık ürün
      // eklenir eklenmez masa listesi de anında tazeleniyor.
      if (mounted) ref.read(masaListesiProvider.notifier).yukle();
      if (mounted) {
        HapticFeedback.lightImpact();
        if (_masaustu) {
          // Ekranda kal: aramayı temizle, bir sonraki ürün için odaklan.
          setState(() => _araCtrl.clear());
          _aramaChanged();
          _araOdak.requestFocus();
        } else if (context.mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Ürün eklenemedi: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _islemAktif = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sol = Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _araCtrl,
                focusNode: _araOdak,
                autofocus: true,
                textInputAction: TextInputAction.search,
                // El terminali / USB okuyucu barkodu yazıp Enter'a basar —
                // önceden karşılığı yoktu, ürün eklenmiyordu.
                onSubmitted: (q) async {
                  final b = q.trim();
                  if (b.isEmpty) return;
                  final urun = await _depo.barkodlaGetir(b);
                  if (!mounted) return;
                  if (urun != null) {
                    setState(() => _araCtrl.clear());
                    _aramaChanged();
                    _urunEkle(urun);
                  } else if (barkodaBenziyor(b)) {
                    BildirimServisi.uyari(context, 'Barkod bulunamadı: $b');
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Ürün ara veya barkod okut...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_araCtrl.text.isNotEmpty)
                      IconButton(icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _araCtrl.clear())),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                      tooltip: 'Barkod Tara',
                      onPressed: () async {
                        final b = await BarkodServisi().barkodTara(context);
                        if (b != null && mounted) {
                          final urun = await _depo.barkodlaGetir(b);
                          if (urun != null) {
                            _urunEkle(urun);
                          } else {
                            _araCtrl.text = b;
                            _aramaChanged();
                          }
                        }
                      }),
                  ]),
                  filled: true,
                  fillColor: TsRenk.kart(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ]),
        ),

        if (_kategoriler.length > 1)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _kategoriler.map((k) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(k),
                  selected: _kategori == k,
                  onSelected: (_) => setState(() => _kategori = k),
                  selectedColor: const Color(0xFF6D4C41),
                  labelStyle: TextStyle(color: _kategori == k ? Colors.white : TsRenk.metinIkincil(context)),
                ),
              )).toList(),
            ),
          ),

        Expanded(
          child: _yukleniyor
              ? const Center(child: AppYukleniyor())
              : Builder(builder: (_) {
                  // Filtre/normalizasyon TEK kez hesaplanır (önceden her kart için
                  // tüm katalog yeniden süzülüyordu — büyük listede O(n²)).
                  final liste = _filtrelenmis;
                  return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    // Telefonda 2 kolon; tablet/PC’de sığdığı kadar (sabit 2 idi).
                    maxCrossAxisExtent: 200,
                    mainAxisExtent: 204,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: liste.length,
                  itemBuilder: (_, i) {
                    final u = liste[i];
                    return _UrunEkleKarti(
                      urun: u,
                      fiyat: _fiyat(u),
                      onTap: () => _urunEkle(u),
                      yukleniyor: _islemAktif,
                    );
                  },
                );
                }),
        ),

        if (_aramaSonuclari.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: TsRenk.kart(context),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              // Şeffaf Material: sonuca dokunma dalgası renkli kutunun altında kalmasın.
              child: Material(
                type: MaterialType.transparency,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _aramaSonuclari.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final u = _aramaSonuclari[i];
                    return ListTile(
                      dense: true,
                      leading: _UrunKareGorseli(urun: u, boyut: 36, koseYari: 10, harfBoyut: 13),
                      title: Text(u.urunAdi, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(u.barkod ?? '', style: const TextStyle(fontSize: 11)),
                      trailing: Text(ParaUtils.formatla(_fiyat(u)),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onTap: () => _urunEkle(u),
                    );
                  },
                ),
              ),
            ),
          ),
      ]);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(
        baslik: 'Ürün Ekle',
        modul: TsModul.masa,
      ),
      body: !_masaustu
          ? sol
          : Row(children: [
              Expanded(child: sol),
              VerticalDivider(width: 1, color: TsRenk.ayirac(context)),
              SizedBox(
                width: 380,
                child: _AdisyonOzetPaneli(
                  masaId: widget.masaId,
                  onBitti: () => Navigator.pop(context),
                ),
              ),
            ]),
    );
  }
}

// ==================== MASAÜSTÜ: CANLI ADİSYON PANELİ ====================
/// Ürün ekleme ekranının sağındaki panel: masanın açık siparişini canlı
/// gösterir, miktar +/- ile düzenlenir (0'a inen kalem silinir).
class _AdisyonOzetPaneli extends ConsumerWidget {
  final int masaId;
  final VoidCallback onBitti;
  const _AdisyonOzetPaneli({required this.masaId, required this.onBitti});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final siparis = ref.watch(masaSiparisProvider(masaId)).value;
    final kalemler = siparis?.kalemler ?? const [];
    final notifier = ref.read(masaSiparisProvider(masaId).notifier);

    return ColoredBox(
      color: TsRenk.kart(context),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Adisyon',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Text('${kalemler.length} kalem',
                style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: kalemler.isEmpty
              ? Center(
                  child: Text('Henüz ürün eklenmedi',
                      style: TextStyle(color: TsRenk.metinIkincil(context))))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: kalemler.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final k = kalemler[i];
                    return ListTile(
                      dense: true,
                      title: Text(k.urunAdi,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(ParaUtils.formatla(k.toplam)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                          tooltip: 'Azalt',
                          onPressed: () => notifier.miktarGuncelle(k.id!, k.miktar - 1),
                        ),
                        Text(
                          k.miktar == k.miktar.roundToDouble()
                              ? k.miktar.toInt().toString()
                              : k.miktar.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          tooltip: 'Artır',
                          onPressed: () => notifier.miktarGuncelle(k.id!, k.miktar + 1),
                        ),
                      ]),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              const Expanded(
                child: Text('Toplam',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Text(ParaUtils.formatla(siparis?.hesaplananToplam ?? 0),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, color: TsRenk.masaAcik)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBitti,
                icon: const Icon(Icons.check),
                label: const Text('Bitti — Adisyona Dön (Esc)'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ==================== ÜRÜN EKLEME KARTI ====================
class _UrunEkleKarti extends StatelessWidget {
  final UrunModel urun;
  final VoidCallback onTap;
  final bool yukleniyor;

  /// Masada uygulanacak (promosyonlu) birim fiyat.
  final double fiyat;

  const _UrunEkleKarti({required this.urun, required this.fiyat, required this.onTap, this.yukleniyor = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: yukleniyor ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _UrunKareGorseli(urun: urun),
              const SizedBox(height: 8),
              Text(urun.urunAdi,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (fiyat < urun.satisFiyati - 0.005) ...[
                  Text(ParaUtils.formatla(urun.satisFiyati),
                      style: TextStyle(
                          fontSize: 11,
                          decoration: TextDecoration.lineThrough,
                          color: context.textHint)),
                  const SizedBox(width: 6),
                ],
                Text(ParaUtils.formatla(fiyat),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: TsRenk.masaAcik)),
              ]),
              const SizedBox(height: 4),
              if (!yukleniyor)
                Container(
                  width: 32, height: 32,
                  decoration: const BoxDecoration(color: Color(0xFF6D4C41), shape: BoxShape.circle),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                )
              else
                const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6D4C41))),
            ],
          ),
        ),
      ),
    );
  }
}
// ==================== ÜRÜN KARE GÖRSELİ (foto varsa foto, yoksa harf) ====================
class _UrunKareGorseli extends StatelessWidget {
  final UrunModel urun;
  final double boyut;
  final double koseYari;
  final double harfBoyut;

  const _UrunKareGorseli({
    required this.urun,
    this.boyut = 56,
    this.koseYari = 16,
    this.harfBoyut = 24,
  });

  @override
  Widget build(BuildContext context) {
    final yol = urun.resimYolu;
    final dosyaVar = yol != null && yol.isNotEmpty && File(yol).existsSync();

    return Container(
      height: boyut, width: boyut,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: dosyaVar ? null : LinearGradient(
          colors: [const Color(0xFF6D4C41).withAlpha(51), const Color(0xFF6D4C41).withAlpha(13)]),
        borderRadius: BorderRadius.circular(koseYari),
      ),
      child: dosyaVar
          ? Image.file(File(yol), fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _harfRozeti())
          : _harfRozeti(),
    );
  }

  Widget _harfRozeti() => Center(
    child: Text(
      urun.urunAdi.isNotEmpty ? urun.urunAdi[0].toUpperCase() : '?',
      style: TextStyle(fontSize: harfBoyut, fontWeight: FontWeight.w600, color: const Color(0xFF6D4C41)),
    ),
  );
}
