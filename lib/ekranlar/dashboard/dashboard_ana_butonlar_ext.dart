// lib/ekranlar/dashboard/dashboard_ana_butonlar_ext.dart
// dashboard_ekrani.dart'ın parçası — "Ana Menü" sayfasındaki 12 büyük
// buton ızgarası (god-class sertleştirmesi, 2026-09-22). Davranış
// birebir korundu.
part of 'dashboard_ekrani.dart';

extension _DashboardAnaButonlarExt on _DashboardEkraniState {
  // ── Ana Butonlar Sayfası (12 Büyük Buton) ─────────────────────────────────
  Widget _anaButonlarSayfasi() {
    final masaModu = ref.watch(masaModuProvider);
    final liste = _anaButonlar
        .where((b) => masaModu || !_masaModulOgesi(b.rota))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: TsResponsive.izgaraKolonSayisi(context,
              telefon: 2, tablet: 3, genis: 4),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.2,
        ),
        itemCount: liste.length,
        itemBuilder: (_, i) => _buyukMenuKarti(liste[i]),
      ),
    );
  }

  // ── Büyük Menü Kartı ──────────────────────────────────────────────────────
  Widget _buyukMenuKarti(_AnaButon item) {
    final masaSayisi = item.rota == '/masa'
        ? ref.watch(masaListesiProvider).maybeWhen(
            data: (m) => m.where((x) => x.durum != 'bos').length,
            orElse: () => 0)
        : 0;
    final mutfakSayisi = item.rota == '/mutfak'
        ? ref.watch(mutfakProvider).maybeWhen(
            data: (d) => d.siparisler
                .expand((s) => s.kalemler)
                .where(
                    (k) => k.durum == 'beklemede' || k.durum == 'hazirlaniyor')
                .length,
            orElse: () => 0)
        : 0;
    final rozetSayisi = item.rota == '/masa' ? masaSayisi : mutfakSayisi;

    return TapScale(
      onTap: () {
        try {
          context.push(item.rota);
        } catch (_) {
          context.go(item.rota);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              item.renk,
              Color.fromARGB(
                  204, item.renk.red, item.renk.green, item.renk.blue),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Color.fromARGB(
                  76, item.renk.red, item.renk.green, item.renk.blue),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Arka plan deseni
            Positioned(
              bottom: 0,
              right: 0,
              child: Opacity(
                opacity: 0.08,
                child: Icon(item.ikon, size: 80, color: Colors.white),
              ),
            ),
            // İçerik
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(item.ikon, size: 24, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.ad,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Masa/Mutfak badge
            if (rozetSayisi > 0)
              Positioned(
                  top: 8, right: 8, child: _rozet(rozetSayisi, Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Ortak yardımcılar
// ──────────────────────────────────────────────────────────────────────────────

Widget _rozet(int sayi, Color renk) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
      ),
      child: Text(sayi > 99 ? '99+' : '$sayi',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
    );
