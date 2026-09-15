// ignore_for_file: invalid_use_of_protected_member
// lib/ekranlar/satis/hizli_satis_ekrani_widgets.dart
// hizli_satis_ekrani.dart'ın parçası — bkz.
// hizli_satis_ekrani_barkod.dart başındaki not. Bu dosya: build()'in
// kullandığı küçük widget yardımcıları + bağımsız (State'e ait
// OLMAYAN) yardımcı widget sınıfları (ödeme seçim sheet'i, müşteri
// seçim paneli, appbar butonu).
part of 'hizli_satis_ekrani.dart';

extension _HizliSatisWidgetExt on _HizliSatisEkraniState {
  Widget _aramaPaneli() => HizliSatisAramaPaneli(
    araCtrl:  _araCtrl,
    araFocus: _araFocus,
    onDegisti: (v) {
      _aramaDegisti(v);
      setState(() {});
    },
    onPluAc: _pluAc,
    onHizliTusAc: _hizliTusAc,
  );

  Widget _kameraPaneli() => SatisKameraPaneli(
    controller: _scanCtrl,
    flash: _flash,
    onBarkod: _barkodOkutIsle,
    onKapat: () => setState(() => _kameraAcik = false),
    onFlashToggle: () {
      setState(() => _flash = !_flash);
      _scanCtrl.toggleTorch();
    },
  );

  Widget _koseAksesuari(Alignment konum) {
    final isTop  = konum == Alignment.topLeft  || konum == Alignment.topRight;
    final isLeft = konum == Alignment.topLeft  || konum == Alignment.bottomLeft;
    const c = BorderSide(color: Colors.greenAccent, width: 3);
    const n = BorderSide.none;
    return Positioned(
      top: isTop ? -1 : null, bottom: !isTop ? -1 : null,
      left: isLeft ? -1 : null, right: !isLeft ? -1 : null,
      child: Container(width: 20, height: 20,
        decoration: BoxDecoration(border: Border(
          top: isTop ? c : n, bottom: !isTop ? c : n,
          left: isLeft ? c : n, right: !isLeft ? c : n,
        ))),
    );
  }

  Widget _aramaSonucListesi() => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 220),
    child: Container(
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(TsRadius.lg),
        border: Border.all(color: TsRenk.ayirac(context)),
        boxShadow: TsGolge.yumusak,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _aramaSonuclari.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final u = _aramaSonuclari[i];
          final indirimVar = u.indirimliFiyatKayitli > 0 &&
              u.indirimliFiyatKayitli < u.satisFiyati;
          return ListTile(
            dense: true,
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4361EE), Color(0xFF3A0CA3)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(
                u.urunAdi.isNotEmpty ? u.urunAdi[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: Colors.white),
              )),
            ),
            title: Text(u.urunAdi,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(u.barkod ?? '',
                style: const TextStyle(fontSize: 11)),
            trailing: Text(
              indirimVar
                  ? ParaUtils.formatla(u.indirimliFiyatKayitli)
                  : ParaUtils.formatla(u.satisFiyati),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: indirimVar ? Colors.orange : null,
              ),
            ),
            onTap: () { _urunSepeteEkleAkilli(u); },
          );
        },
      ),
    ),
  );

  Widget _sepetListesi() => HizliSatisSepetListesi(
    scrollController: _sepetScroll,
    kgMiMi: _kgBirimMi,
    onKalemTap: _sepetKalemMiktarDuzenle,
    onIndirimDuzenle: _indirimDuzenle,
    onKgEkle: _kgIleEkle,
  );

  Widget _altPanel(SepetDurum sepet) => SatisAltPanel(
    sepet: sepet,
    onOdeme: _odemeYontemiSec,
  );
}

// ── Ödeme Seçim Sheet ────────────────────────────────────────────────────────
class _OdemeSecimSheet extends StatelessWidget {
  final double toplam;
  final bool musteriSecili;
  const _OdemeSecimSheet({required this.toplam, this.musteriSecili = false});

  @override
  Widget build(BuildContext context) {
    const yontemler = [
      (ikon: Icons.payments,        label: 'Nakit',        renk: Color(0xFF4CAF50), deger: 'Nakit'),
      (ikon: Icons.credit_card,     label: 'Kredi Kartı',  renk: Color(0xFF2196F3), deger: 'Kredi Kartı'),
      (ikon: Icons.account_balance, label: 'Banka/Havale', renk: Color(0xFF9C27B0), deger: 'Havale'),
      (ikon: Icons.people_outline,  label: 'Cari Hesap',   renk: Color(0xFFFF9800), deger: 'Cari'),
      (ikon: Icons.qr_code,         label: 'QR Kod',       renk: Color(0xFF00BCD4), deger: 'QR'),
      (ikon: Icons.tune,            label: 'Karma Ödeme',  renk: Color(0xFF607D8B), deger: 'Karma'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('Toplam: ${ParaUtils.formatla(toplam)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Ödeme yöntemi seçin',
            style: TextStyle(color: context.textSecondary, fontSize: 13)),
        const SizedBox(height: 20),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: List.generate(yontemler.length, (i) {
            final y = yontemler[i];
            final kilitli = y.deger == 'Cari' && !musteriSecili;
            return GestureDetector(
              onTap: kilitli
                  ? null
                  : () => Navigator.pop(context, y.deger),
              child: Opacity(
                opacity: kilitli ? 0.35 : 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Color.fromARGB(36, y.renk.red, y.renk.green, y.renk.blue),
                    border: Border.all(color: Color.fromARGB(120, y.renk.red, y.renk.green, y.renk.blue), width: 1.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(y.ikon, color: y.renk, size: 28),
                      const SizedBox(height: 6),
                      Text(y.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: y.renk)),
                      if (kilitli)
                        Text('Müşteri seç',
                            style: TextStyle(
                                fontSize: 9, color: context.textSecondary)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }
}

class _MusteriSecimPaneli extends ConsumerStatefulWidget {
  final List<CariModel> cariler;
  const _MusteriSecimPaneli({required this.cariler});

  @override
  ConsumerState<_MusteriSecimPaneli> createState() => _MusteriSecimPaneliState();
}

class _MusteriSecimPaneliState extends ConsumerState<_MusteriSecimPaneli> {
  final _araCtrl = TextEditingController();
  List<CariModel> _filtreli = [];

  @override
  void initState() {
    super.initState();
    _filtreli = widget.cariler;
    _araCtrl.addListener(_filtrele);
  }

  @override
  void dispose() { _araCtrl.dispose(); super.dispose(); }

  void _filtrele() {
    final q = _araCtrl.text.toLowerCase();
    setState(() {
      _filtreli = q.isEmpty
          ? widget.cariler
          : widget.cariler.where((c) =>
              c.unvan.toLowerCase().contains(q) ||
              (c.telefon?.contains(q) ?? false)).toList();
    });
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.7,
    minChildSize: 0.4,
    maxChildSize: 0.95,
    expand: false,
    builder: (_, ctrl) => Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(color: context.borderColor,
                borderRadius: BorderRadius.circular(2))),
        const Text('Müşteri / Tedarikçi Seç',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _araCtrl,
            decoration: const InputDecoration(
              hintText: 'Müşteri ara…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(child: ListView.builder(
          controller: ctrl,
          itemCount: _filtreli.length,
          itemBuilder: (_, i) {
            final c = _filtreli[i];
            return ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF43A047)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(
                  c.unvan.isNotEmpty ? c.unvan[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: Colors.white),
                )),
              ),
              title: Row(children: [
                Flexible(child: Text(c.unvan, overflow: TextOverflow.ellipsis)),
                if (c.cariTipi.contains('edarik')) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x1A009688),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Tedarikçi',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: Color(0xFF00796B))),
                  ),
                ],
              ]),
              subtitle: Text(c.telefon ?? ''),
              onTap: () => Navigator.pop(context, c),
            );
          },
        )),
      ]),
    ),
  );
}

// ── Modern AppBar İkon Butonu (nullable onTap desteği) ──────────────────────
class _AppBarButon extends StatefulWidget {
  final IconData icon;
  final Color renk;
  final String tooltip;
  final VoidCallback? onTap;

  const _AppBarButon({
    required this.icon,
    required this.renk,
    required this.tooltip,
    this.onTap,
  });

  @override
  State<_AppBarButon> createState() => _AppBarButonState();
}

class _AppBarButonState extends State<_AppBarButon> {
  // 🔴 Kullanıcı isteği: ikonlara dokunma geri bildirimi — önceden bu
  // buton çıplak bir GestureDetector'dı, hiç ripple/animasyon yoktu.
  // Artık InkWell (ripple) + basılıyken kısa bir büzülme + arka plan
  // koyulaşması ekleniyor. onHighlightChanged InkWell'in KENDİ basılı/
  // bırakıldı durumunu bildirdiği için ayrı bir jest algılayıcısına
  // gerek yok.
  bool _basili = false;

  @override
  Widget build(BuildContext context) {
    final temelRenk = widget.renk == Colors.white
        ? Colors.white.withAlpha(25)
        : Colors.white.withAlpha(40);
    return Tooltip(
      message: widget.tooltip,
      child: Opacity(
        opacity: widget.onTap == null ? 0.4 : 1.0,
        child: AnimatedScale(
          scale: _basili ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: 38, height: 38,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: _basili ? Colors.black.withAlpha(60) : temelRenk,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withAlpha(50)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap, // null ise tıklama olmaz
                onHighlightChanged: widget.onTap == null
                    ? null
                    : (v) {
                        if (mounted) setState(() => _basili = v);
                      },
                child: Icon(widget.icon, size: 20,
                    color: widget.onTap == null ? Colors.grey : Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}