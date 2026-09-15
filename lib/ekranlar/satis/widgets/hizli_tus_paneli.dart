// lib/ekranlar/satis/widgets/hizli_tus_paneli.dart
//
// 🆕 YENİ EKRAN — HIZLI TUŞ PANELİ
//
// NEDEN: Bir markette en çok satılan kalemlerin çoğunun barkodu ya yoktur
// ya da okutulamaz — ekmek, poşet, açık çay, gazete, tek sigara, su.
// Bu projede `favori_urunler` tablosu ZATEN vardı ama hiçbir arayüzü
// yoktu; kasiyer bu ürünleri satmak için PLU ekranını açıp aramak
// zorundaydı. Profesyonel POS'larda (Barkomatik, BarkoPOS, Nebim) bunun
// karşılığı "hızlı tuş" panelidir.
//
// TASARIM NOTU: Bu dosya, projedeki tasarım sistemini (TsRenk / TsBosluk
// / TsRadius / TsMetin) ve tema uzantılarını (context.cardBg,
// context.textPrimary...) kullanır — sabit renk yazılmaz. Böylece koyu
// temada da doğru görünür. (Analizde çıkan 85 ekranlık "sabit renk"
// sorununun tekrarlanmaması için.)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../modeller/urun_model.dart';
import '../../../depolar/favori_urun_deposu.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../cekirdek/utils/para_utils.dart';

/// Ürün adının baş harflerinden istikrarlı bir renk üretir — her tuş
/// farklı ama her açılışta AYNI renkte görünür (kasiyer kas hafızası
/// oluşturabilsin diye; rastgele renk olsaydı her açılışta değişirdi).
const _tusPaleti = [
  Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFC62828),
  Color(0xFF6A1B9A), Color(0xFF00695C), Color(0xFFE65100),
  Color(0xFF37474F), Color(0xFF558B2F), Color(0xFF4527A0),
  Color(0xFF00838F), Color(0xFF283593), Color(0xFF880E4F),
];

Color tusRengi(String s) =>
    _tusPaleti[s.codeUnits.fold(0, (a, b) => a + b) % _tusPaleti.length];

class HizliTusPaneli extends ConsumerStatefulWidget {
  /// Tuşa basılınca çağrılır. Sepete ekleme sorumluluğu ÇAĞIRAN ekrana
  /// bırakılır — böylece kg'lı ürün için miktar sorma, promosyon
  /// uygulama gibi mevcut mantık tek yerde kalır, burada kopyalanmaz.
  final void Function(UrunModel urun) onUrunSec;

  /// "Düzenle" butonuna basılınca çağrılır (yönetim ekranını açar).
  final VoidCallback? onDuzenle;

  const HizliTusPaneli({super.key, required this.onUrunSec, this.onDuzenle});

  @override
  ConsumerState<HizliTusPaneli> createState() => _HizliTusPaneliState();
}

class _HizliTusPaneliState extends ConsumerState<HizliTusPaneli> {
  final _depo = FavoriUrunDeposu();

  List<UrunModel> _urunler = [];
  bool _yukleniyor = true;

  // Çift dokunma koruması. Kasiyer hızlı basınca aynı ürünün iki kez
  // sepete düşmesi, mevcut PLU ekranında da yaşanmış bir sorundu.
  bool _isleniyor = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final liste = await _depo.favorileriGetir();
      if (!mounted) return;
      setState(() {
        _urunler = liste;
        _yukleniyor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _sec(UrunModel u) {
    if (_isleniyor) return;
    _isleniyor = true;
    HapticFeedback.lightImpact();
    widget.onUrunSec(u);
    // Panel açık kalıyorsa (kasiyer arka arkaya birden çok hızlı tuşa
    // basabilsin diye) kısa bir süre sonra tekrar basılabilir olsun.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _isleniyor = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(TsRadius.xl)),
      ),
      child: Column(children: [
        // ── Tutma çubuğu ──────────────────────────────────────────────
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 2),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // ── Başlık ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
              TsBosluk.xs, 0, TsBosluk.md, TsBosluk.xs),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.close, color: context.textSecondary),
              tooltip: 'Kapat',
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Hızlı Tuşlar',
                      style: TsMetin.baslikL
                          .copyWith(color: context.textPrimary)),
                  Text(
                    _urunler.isEmpty
                        ? 'Henüz tuş tanımlanmadı'
                        : '${_urunler.length} ürün • tek dokunuşla sepete',
                    style:
                        TsMetin.kucuk.copyWith(color: context.textSecondary),
                  ),
                ],
              ),
            ),
            if (widget.onDuzenle != null)
              TextButton.icon(
                onPressed: widget.onDuzenle,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Düzenle'),
                style: TextButton.styleFrom(
                  foregroundColor: TsRenk.primary,
                  textStyle: TsMetin.kucukVurgu,
                ),
              ),
          ]),
        ),

        // ── İçerik ────────────────────────────────────────────────────
        Expanded(
          child: _yukleniyor
              ? const TsYukleniyor()
              : _urunler.isEmpty
                  ? _bosDurum(context)
                  : LayoutBuilder(builder: (ctx, kisit) {
                      // Tablet/geniş ekranda daha çok sütun — mevcut
                      // ts_responsive mantığıyla aynı eşikler.
                      final genislik = kisit.maxWidth;
                      final sutun = genislik > 900
                          ? 6
                          : genislik > 600
                              ? 4
                              : 3;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            TsBosluk.md, TsBosluk.xs, TsBosluk.md, TsBosluk.xxxl),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: sutun,
                          mainAxisSpacing: TsBosluk.sm,
                          crossAxisSpacing: TsBosluk.sm,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: _urunler.length,
                        itemBuilder: (_, i) => _tus(_urunler[i]),
                      );
                    }),
        ),
      ]),
    );
  }

  // ── Tek bir hızlı tuş ────────────────────────────────────────────────
  Widget _tus(UrunModel u) {
    final renk = tusRengi(u.urunAdi);
    // Stok uyarısı: kasiyer stoksuz ürünü satarken görsün ama
    // ENGELLENMESİN (markette negatif stok normaldir — sayım öncesi).
    final stokYok = u.stok <= 0;

    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(TsRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _sec(u),
        // Container yerine DecoratedBox — sadece dekorasyon var, ekstra
        // layout katmanı gereksiz (analizör: use_decorated_box)
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TsRadius.md),
            border: Border.all(color: renk.withValues(alpha: 0.28), width: 1.2),
          ),
          child: Column(children: [
            // Üst renk şeridi — tuşlar birbirinden ayırt edilsin
            Container(height: 4, color: renk),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(TsBosluk.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: renk.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(TsRadius.sm),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _basHarfler(u.urunAdi),
                        style: TsMetin.kucukVurgu.copyWith(color: renk),
                      ),
                    ),
                    const SizedBox(height: TsBosluk.xs + 2),
                    Text(
                      u.urunAdi,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TsMetin.kucukVurgu
                          .copyWith(color: context.textPrimary, height: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ParaUtils.formatla(u.satisFiyati),
                      style: TsMetin.kucukVurgu.copyWith(color: renk),
                    ),
                    if (stokYok)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('stok yok',
                            style: TsMetin.etiket
                                .copyWith(color: TsRenk.uyari, fontSize: 9)),
                      ),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Ürün adından 1-2 harflik rozet metni üretir.
  /// NOT: `characters` paketine bilerek bağımlılık kurulmadı; Türkçe
  /// harfler (İ, Ş, Ğ) tek kod birimi olduğu için substring güvenli.
  static String _basHarfler(String ad) {
    final parcalar =
        ad.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parcalar.isEmpty) return '?';
    if (parcalar.length == 1) {
      final tek = parcalar.first;
      return (tek.length >= 2 ? tek.substring(0, 2) : tek).toUpperCase();
    }
    return (parcalar[0].substring(0, 1) + parcalar[1].substring(0, 1))
        .toUpperCase();
  }

  Widget _bosDurum(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(TsBosluk.xxl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.primary),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt_rounded,
                  size: 38, color: TsRenk.primary),
            ),
            const SizedBox(height: TsBosluk.lg),
            Text('Hızlı tuş tanımlanmamış',
                style: TsMetin.baslikM.copyWith(color: context.textPrimary)),
            const SizedBox(height: TsBosluk.sm),
            Text(
              'Barkodu olmayan ya da sürekli satılan ürünleri '
              '(ekmek, poşet, çay, su, gazete) buraya ekleyin — '
              'kasada tek dokunuşla sepete düşer.',
              textAlign: TextAlign.center,
              style: TsMetin.kucuk.copyWith(
                  color: context.textSecondary, height: 1.45),
            ),
            const SizedBox(height: TsBosluk.xl),
            if (widget.onDuzenle != null)
              FilledButton.icon(
                onPressed: widget.onDuzenle,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Tuş Ekle'),
                style: FilledButton.styleFrom(
                  backgroundColor: TsRenk.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: TsBosluk.xxl, vertical: TsBosluk.md),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(TsRadius.md)),
                ),
              ),
          ]),
        ),
      );
}
