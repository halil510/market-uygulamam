// lib/ekranlar/dashboard/dashboard_tum_uygulamalar_ext.dart
// dashboard_ekrani.dart'ın parçası — kategori bazlı "Tüm Uygulamalar"
// arama sayfası (god-class sertleştirmesi, 2026-09-22). Davranış
// birebir korundu.
part of 'dashboard_ekrani.dart';

extension _DashboardTumUygulamalarExt on _DashboardEkraniState {
  // ── Tüm Uygulamalar Sayfası (Kategori Bazlı) ───────────────────────────────
  Widget _tumUygulamalarSayfasi() {
    final masaModu = ref.watch(masaModuProvider);

    final kategoriler = masaModu
        ? _tumKategoriler
        : _tumKategoriler.where((k) => k.ad != 'Masa & Restoran').toList();

    final toplamEslesme = _aramaMetni.isEmpty
        ? -1
        : kategoriler
            .expand((k) => k.uygulamalar)
            .where((u) => u.ad.toLowerCase().contains(_aramaMetni))
            .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Arama kutusu
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _aramaCtrl,
              decoration: InputDecoration(
                hintText: 'Uygulama ara...',
                prefixIcon:
                    Icon(Icons.search, color: context.textSecondary, size: 20),
                suffixIcon: _aramaMetni.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: context.textSecondary, size: 18),
                        onPressed: () => _aramaCtrl.clear(),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          // Sonuç bulunamadı durumu
          if (toplamEslesme == 0)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: TsBosDurum(
                ikon: Icons.search_off,
                baslik: '"$_aramaMetni" için sonuç bulunamadı',
              ),
            ),

          // Kategori listesi
          ...kategoriler.map((kategori) {
            final filtrelenmis = kategori.uygulamalar
                .where((u) =>
                    _aramaMetni.isEmpty ||
                    u.ad.toLowerCase().contains(_aramaMetni))
                .toList();
            if (filtrelenmis.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Row(children: [
                    Icon(kategori.ikon, size: 20, color: AppRenkler.primary),
                    const SizedBox(width: 8),
                    Text(kategori.ad,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2)),
                  ]),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: filtrelenmis.length,
                  itemBuilder: (_, i) => _kucukUygulamaKarti(filtrelenmis[i]),
                ),
              ],
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Küçük Uygulama Kartı ──────────────────────────────────────────────────
  Widget _kucukUygulamaKarti(_UygulamaItem item) {
    return TapScale(
      onTap: () {
        try {
          context.push(item.rota);
        } catch (_) {
          context.go(item.rota);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color.fromARGB(
                    26, item.renk.red, item.renk.green, item.renk.blue),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.ikon, size: 24, color: item.renk),
            ),
            const SizedBox(height: 8),
            Text(
              item.ad,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
