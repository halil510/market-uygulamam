// lib/ekranlar/cari/cari_liste_ekrani.dart — Modern v2
import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/bulut_durum_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../modeller/cari_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../widgetlar/ortak/yukleniyor_widget.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/gib_servisi.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/bekleyen_siparis_deposu.dart';

class CariListeEkrani extends ConsumerStatefulWidget {
  /// AI Chat'ten "cari X'e git" gibi bir komutla gelindiğinde, ekran
  /// açılır açılmaz bu terimle otomatik arama yapılması için.
  final String? baslangicArama;
  const CariListeEkrani({super.key, this.baslangicArama});
  @override
  ConsumerState<CariListeEkrani> createState() => _CariListeEkraniState();
}

class _CariListeEkraniState extends ConsumerState<CariListeEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _araCtrl = TextEditingController();
  Timer? _debounce;
  String _bakiyeFiltre = 'Tümü';
  static const _filtreler = ['Tümü', 'Alacaklı', 'Borçlu', 'Dengede'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _araCtrl.addListener(_aramaChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(carilerProvider.notifier).yukle();
      if (widget.baslangicArama != null && widget.baslangicArama!.trim().isNotEmpty) {
        _araCtrl.text = widget.baslangicArama!.trim();
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _debounce?.cancel();
    _araCtrl.dispose();
    super.dispose();
  }

  void _aramaChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(cariFiltresiProvider.notifier).aramaGuncelle(_araCtrl.text);
    });
  }

  Future<void> _sil(CariModel c) async {
    // 🔴 DÜZELTME (Madde 19 — Silme Mantığı denetimi, 2026-09-16): bu
    // diyalog carinin AÇIK (durum='bekliyor') bekleyen siparişi olup
    // olmadığını hiç kontrol etmiyordu — cari silindiğinde (soft-delete)
    // fiziksel kayıt bozulmuyor ama cari artık dropdown/arama
    // sonuçlarında görünmediğinden, o siparişi kapatmak için cari
    // tekrar seçilemiyordu. Bakiye uyarısıyla aynı desende, doluysa
    // net bir uyarı ekleniyor.
    var bekleyenSiparisSayisi = 0;
    if (c.id != null) {
      try {
        final bekleyenler = await BekleyenSiparisDeposu()
            .bekleyenSiparisleriGetir(cariId: c.id, durum: 'bekliyor');
        bekleyenSiparisSayisi = bekleyenler.length;
      } catch (_) {
        // Sayım başarısız olursa sessizce geç — silme akışını bloklamasın.
      }
    }
    if (!mounted) return;
    final onay = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
            child: const Icon(Icons.delete_outline, color: Colors.red, size: 20)),
          const SizedBox(width: 10),
          const Text('Cari Sil', style: TextStyle(fontSize: 16)),
        ]),
        // 🔴 Derin denetimde bulundu (P2): bu diyalog carinin bakiyesini
        // hiç göstermiyordu — borçlu/alacaklı bir cari (soft-delete
        // olduğu için veri kaybolmasa da) is_deleted=0 filtresi
        // kullanan TÜM ekran/rapordan kaybolur, işletme o parayı
        // unutabilir. Bakiye sıfır değilse net bir uyarı ekleniyor.
        content: RichText(text: TextSpan(
          style: TextStyle(color: TsRenk.metinBirincil(ctx), fontSize: 14),
          children: [
            TextSpan(text: c.unvan, style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' adlı cari silinecek.\nBu işlem geri alınamaz.'),
            if (c.bakiye.abs() > 0.005)
              TextSpan(
                text: c.bakiye > 0
                    ? '\n\n⚠️ Bu carinin ${ParaUtils.formatla(c.bakiye)} alacağı var — '
                      'silindikten sonra raporlarda görünmeyecek.'
                    : '\n\n⚠️ Bu carinin ${ParaUtils.formatla(c.bakiye.abs())} borcu var — '
                      'silindikten sonra raporlarda görünmeyecek.',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
            if (bekleyenSiparisSayisi > 0)
              TextSpan(
                text: '\n\n⚠️ Bu carinin $bekleyenSiparisSayisi bekleyen siparişi var — '
                    'cari silindikten sonra arama/seçim listelerinde görünmeyeceği için '
                    'bu siparişleri kapatmak zorlaşacak.',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
          ],
        )),
        actions: [
              const BulutDurumIkonu(),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil')),
        ],
      ));
    if (onay != true || !mounted) return;
    try {
      await ref.read(carilerProvider.notifier).sil(c.id!);
      if (mounted) BildirimServisi.basari(context, '${c.unvan} silindi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  List<CariModel> _filtrele(List<CariModel> liste) {
    if (_bakiyeFiltre == 'Tümü') return liste;
    return liste.where((c) {
      switch (_bakiyeFiltre) {
        case 'Alacaklı': return c.bakiye > 0;
        case 'Borçlu':   return c.bakiye < 0;
        case 'Dengede':  return c.bakiye == 0;
        default:         return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final durum  = ref.watch(carilerProvider);
    final filtre = ref.watch(cariFiltresiProvider);

    // Filtreleme - memoize için durum değişmeden hesaplamayı atla
    final aramaMetni = filtre.aramaMetni.toLowerCase();
    // 🔴 DÜZELTME (cari ekranları derin analizi, 2026-09-14): "Tümü"
    // sekmesi ünvan/telefon/cari kodu ÜÇÜNÜ de kontrol ederken, "Müşteri"
    // ve "Tedarikçi" sekmeleri SADECE ünvanı kontrol ediyordu — AYNI arama
    // terimini yazan kullanıcı "Tümü"de sonuç görüp sekme değiştirince
    // (ör. bir telefon numarası aratılınca) boş liste görüyordu. Artık her
    // üç sekme de AYNI eşleşme kuralını kullanıyor.
    bool aramaEslesiyor(CariModel c) =>
        aramaMetni.isEmpty ||
        c.unvan.toLowerCase().contains(aramaMetni) ||
        (c.telefon?.contains(aramaMetni) ?? false) ||
        (c.cariKodu?.toLowerCase().contains(aramaMetni) ?? false);
    final hepsi = [...durum.musteriler,
      ...durum.tedarikciler.where((t) => !durum.musteriler.any((m) => m.id == t.id))];
    final tum = _filtrele(hepsi.where(aramaEslesiyor).toList());
    final musteriler   = _filtrele(durum.musteriler.where(aramaEslesiyor).toList());
    final tedarikciler = _filtrele(durum.tedarikciler.where(aramaEslesiyor).toList());
    final toplamAlacak = durum.toplamAlacak;
    final toplamBorc   = durum.toplamBorc;

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslikWidget: const Text('Cariler',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => ref.read(carilerProvider.notifier).yukle()),
        ],
        alt: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(children: [
            // Arama
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                    color: Color(0x26FFFFFF),
                    borderRadius: BorderRadius.circular(20)),
                child: TextField(
                  controller: _araCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ad, kod, telefon ara...',
                    hintStyle: TextStyle(color: Color(0xB2FFFFFF), fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 18),
                    suffixIcon: _araCtrl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, color: Colors.white70, size: 16),
                            onPressed: () { _araCtrl.clear(); ref.read(cariFiltresiProvider.notifier).aramaGuncelle(''); })
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ),
            // Tab bar
            TabBar(
              controller: _tab,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: TsMetin.kucukVurgu,
              tabs: [
                Tab(text: 'Tümü (${tum.length})'),
                Tab(text: 'Müşteri (${musteriler.length})'),
                Tab(text: 'Tedarikçi (${tedarikciler.length})'),
              ],
            ),
          ]),
        ),
        geriTusu: false,
      ),
      body: Column(children: [
        // Özet + Filtre şeridi
        Container(
          color: context.cardBg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            // Alacak chip
            if (toplamAlacak > 0) _OzetChip(
              ikon: Icons.arrow_downward_rounded,
              renk: Colors.green.shade600,
              etiket: 'Alacak',
              tutar: toplamAlacak),
            if (toplamAlacak > 0) const SizedBox(width: 8),
            // Borç chip
            if (toplamBorc > 0) _OzetChip(
              ikon: Icons.arrow_upward_rounded,
              renk: Colors.red.shade600,
              etiket: 'Borç',
              tutar: toplamBorc),
            const Spacer(),
            // Bakiye filtre
            PopupMenuButton<String>(
              initialValue: _bakiyeFiltre,
              onSelected: (v) => setState(() => _bakiyeFiltre = v),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: _bakiyeFiltre != 'Tümü'
                        ? AppRenkler.primary.withAlpha(26) : context.borderColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _bakiyeFiltre != 'Tümü'
                        ? AppRenkler.primary : context.borderColor)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.filter_list, size: 14),
                  const SizedBox(width: 4),
                  Text(_bakiyeFiltre, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
              itemBuilder: (_) => _filtreler.map((f) => PopupMenuItem(
                value: f, child: Text(f))).toList(),
            ),
          ]),
        ),

        Expanded(
          child: durum.yukleniyor
              ? const SatirYukleniyorWidget(satirSayisi: 7)
              : TabBarView(controller: _tab, children: [
                  _CariTab(cariler: tum, onSil: _sil,
                      onRefresh: () => ref.read(carilerProvider.notifier).yukle()),
                  _CariTab(cariler: musteriler, onSil: _sil,
                      onRefresh: () => ref.read(carilerProvider.notifier).yukle()),
                  _CariTab(cariler: tedarikciler, onSil: _sil,
                      onRefresh: () => ref.read(carilerProvider.notifier).yukle()),
                ]),
        ),
      ]),
      floatingActionButton: TsYetkili(child: FloatingActionButton.extended(
        elevation: 6,
        backgroundColor: AppRenkler.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Cari Ekle'),
        onPressed: () => context.push('/cari/ekle').then((_) =>
            ref.read(carilerProvider.notifier).yukle()),
      )),
    );
  }
}

class _OzetChip extends StatelessWidget {
  final IconData ikon; final Color renk; final String etiket; final double tutar;
  const _OzetChip({required this.ikon, required this.renk, required this.etiket, required this.tutar});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: renk.withAlpha(20), borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ikon, size: 12, color: renk),
      const SizedBox(width: 4),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(etiket, style: TextStyle(fontSize: 9, color: renk, fontWeight: FontWeight.w600)),
        Text(ParaUtils.formatla(tutar),
            style: TextStyle(fontSize: 11, color: renk, fontWeight: FontWeight.w800)),
      ]),
    ]),
  );
}

class _CariTab extends StatelessWidget {
  final List<CariModel> cariler;
  final Future<void> Function(CariModel) onSil;
  final Future<void> Function() onRefresh;
  const _CariTab({required this.cariler, required this.onSil, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (cariler.isEmpty) return const TsBosDurum(
      ikon: Icons.people_outline,
      baslik: 'Kayıt bulunamadı',
    );
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
        itemCount: cariler.length,
        itemBuilder: (_, i) => _CariKart(cari: cariler[i], onSil: () => onSil(cariler[i])),
      ),
    );
  }
}

class _CariKart extends ConsumerWidget {
  final CariModel cari; final VoidCallback onSil;
  const _CariKart({required this.cari, required this.onSil});

  Future<void> _mukellefSorgula(BuildContext context, WidgetRef ref) async {
    final vknTckn = (cari.vergiNo?.trim().isNotEmpty ?? false)
        ? cari.vergiNo!.trim()
        : cari.tcKimlik?.trim();
    if (vknTckn == null || vknTckn.isEmpty || cari.id == null) return;

    BildirimServisi.bilgi(context, 'GİB\'de sorgulanıyor...');
    final sonuc = await GibServisi().mukellefSorgula(vknTckn);
    if (!context.mounted) return;

    if (sonuc == null) {
      BildirimServisi.uyari(context,
          'Sorgu yapılamadı — entegratör ayarlarını (Ayarlar > GİB E-Fatura) kontrol edin.');
      return;
    }
    await CariDeposu().mukellefDurumuGuncelle(cari.id!, sonuc);
    ref.invalidate(carilerProvider);
    if (context.mounted) {
      BildirimServisi.basari(context,
          sonuc == 'efatura' ? '✅ e-Fatura mükellefi' : 'ℹ️ e-Arşiv kesilmeli (GİB\'de kayıtlı değil)');
    }
  }

  // NOT: getter'dan metoda çevrildi — gövdesi context.textSecondary
  // kullanıyor, ama _CariKart bir ConsumerWidget (State değil), bu yüzden
  // getter'ın context'e erişimi yok. Çağrı yerlerinin hepsi build() içinde.
  Color _renk(BuildContext context) {
    if (cari.bakiye == 0) return context.textSecondary;
    final mst = cari.cariTipi.contains('Müşteri');
    if (mst) return cari.bakiye > 0 ? Colors.green.shade600 : Colors.blue.shade600;
    return cari.bakiye < 0 ? Colors.red.shade600 : Colors.blue.shade600;
  }

  String get _etiket {
    if (cari.bakiye == 0) return 'Dengede';
    final mst = cari.cariTipi.contains('Müşteri');
    if (mst) return cari.bakiye > 0 ? 'Alacak' : 'Fazla Ödedi';
    return cari.bakiye < 0 ? 'Borç' : 'Fazla Ödedik';
  }

  // ÖNCEDEN BURADA CİDDİ BİR UYUMLULUK HATASI VARDI: rozet, "VKN(10 hane)
  // varsa = e-Fatura mükellefi" diye TAHMİN ediyordu (kod yorumunda bile
  // "GİB'e canlı sorgu yapılmaz" yazıyordu). Bu YANLIŞ bir varsayımdı —
  // 10 haneli VKN'ye sahip OLMAK, o firmanın e-Fatura'ya KAYITLI olduğu
  // anlamına gelmez; birçok küçük firma VKN'si olsa da e-Fatura
  // mükellefi DEĞİLDİR ve yasal olarak e-Arşiv alması gerekir. Bu yanlış
  // tahmine güvenerek yanlış belge türü (e-Fatura yerine olması gereken
  // yerde) kesilebilirdi — ciddi bir uyumluluk riski. Artık GERÇEK GİB
  // sorgusu sonucu (önbelleğe alınmış `cari.mukellefDurumu`) kullanılıyor;
  // hiç sorgulanmadıysa rozet HİÇ gösterilmiyor (belirsizken tahmin
  // yürütmüyor).
  Color? get _eFaturaDurumRengi => switch (cari.mukellefDurumu) {
    'efatura' => const Color(0xFF2E7D32),
    'earsiv'  => const Color(0xFF9E9E9E),
    _ => null,
  };

  String? get _eFaturaDurumEtiketi => switch (cari.mukellefDurumu) {
    'efatura' => 'e-Fatura Mükellefi (GİB\'de kayıtlı)',
    'earsiv'  => 'e-Arşiv Kesilmeli (GİB\'de kayıtlı değil)',
    _ => null,
  };

  Color get _avatarRenk {
    final tip = cari.cariTipi;
    if (tip.contains('Müşteri') && !tip.contains('Tedarikçi')) return const Color(0xFF1565C0);
    if (tip.contains('Tedarikçi') && !tip.contains('Müşteri')) return const Color(0xFF6A1B9A);
    return const Color(0xFF00695C);
  }

  /// Kullanıcının anlaşılır bulacağı tip rozeti: Müşteri / Tedarikçi /
  /// Bayi / Toptan Müşteri / Müşteri+Tedarikçi — ham cari kodu yerine.
  Widget _tipEtiketi(CariModel cari) {
    final tip = cari.cariTipi;
    final musteriMi = tip.contains('Müşteri');
    final tedarikciMi = tip.contains('Tedarik');
    String etiket;
    Color renk;
    if (musteriMi && tedarikciMi) {
      etiket = 'Müşteri + Tedarikçi'; renk = const Color(0xFF00695C);
    } else if (tedarikciMi) {
      etiket = 'Tedarikçi'; renk = const Color(0xFF6A1B9A);
    } else if (cari.musteriTipi == 'Bayi') {
      etiket = 'Bayi'; renk = const Color(0xFFEF6C00);
    } else if (cari.musteriTipi == 'Toptan') {
      etiket = 'Toptan Müşteri'; renk = const Color(0xFF1565C0);
    } else {
      etiket = 'Müşteri'; renk = const Color(0xFF1565C0);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: renk.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(etiket,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: renk)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final silYetkisiVar = ref.watch(authProvider.select((s) => s.isMudur));
    return Dismissible(
    key: ValueKey('cari_${cari.id}'),
    direction: silYetkisiVar ? DismissDirection.endToStart : DismissDirection.none,
    background: Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: Colors.red.shade400, borderRadius: BorderRadius.circular(16)),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.delete_outline, color: Colors.white),
        Text('Sil', style: TextStyle(color: Colors.white, fontSize: 11)),
      ])),
    confirmDismiss: (_) async { onSil(); return false; },
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TsKart(
        onTap: () => context.push('/cari/detay/${cari.id}'),
        padding: EdgeInsets.zero,
        child: Row(children: [
          // Renkli sol çizgi
          Container(width: 4, height: 68,
              decoration: BoxDecoration(
                  color: _renk(context), borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)))),
          const SizedBox(width: 12),
          // Avatar (+ e-Fatura/e-Arşiv durum noktası)
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: _avatarRenk.withAlpha(31), shape: BoxShape.circle),
              child: Center(child: Text(
                cari.unvan.isNotEmpty ? cari.unvan[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _avatarRenk))),
            ),
          ]),
          const SizedBox(width: 10),
          // İsim + bilgiler
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(cari.unvan,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (_eFaturaDurumRengi != null) ...[
                  const SizedBox(width: 5),
                  Tooltip(
                    message: _eFaturaDurumEtiketi!,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _eFaturaDurumRengi!.withAlpha(31),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        (_eFaturaDurumRengi == const Color(0xFF2E7D32)) ? 'e-Fatura' : 'e-Arşiv',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _eFaturaDurumRengi)),
                    ),
                  ),
                ] else if (cari.vergiNo != null || cari.tcKimlik != null) ...[
                  const SizedBox(width: 5),
                  Tooltip(
                    message: 'GİB\'de e-Fatura mükellefi mi diye henüz sorgulanmadı — sorgulamak için dokunun',
                    child: InkWell(
                      onTap: () => _mukellefSorgula(context, ref),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: context.borderColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.help_outline, size: 10, color: context.textSecondary),
                          const SizedBox(width: 2),
                          Text('Sorgula',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: context.textSecondary)),
                        ]),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Row(children: [
                // 🔴 DÜZELTME (kullanıcı bulgusu): Burada ham cari kodu
                // (ör. "M001") gösteriliyordu — bu bilgi çoğu kullanıcı
                // için anlamsız/teknikti. Artık kullanıcının daha
                // anlamlı bulacağı bir TİP ETİKETİ gösteriliyor:
                // Müşteri / Tedarikçi / Bayi / Toptan Müşteri.
                _tipEtiketi(cari),
                const SizedBox(width: 8),
                if (cari.telefon != null) ...[
                  Icon(Icons.phone_outlined, size: 11, color: context.textSecondary),
                  const SizedBox(width: 2),
                  Text(cari.telefon!, style: TextStyle(fontSize: 11, color: context.textSecondary)),
                ],
              ]),
            ]),
          )),
          // Bakiye sağ taraf
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(ParaUtils.formatla(cari.bakiye.abs()),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _renk(context))),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: _renk(context).withAlpha(26), borderRadius: BorderRadius.circular(12)),
                child: Text(_etiket,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _renk(context)))),
            ]),
          ),
        ]),
      ),
    ),
  );
  }
}
