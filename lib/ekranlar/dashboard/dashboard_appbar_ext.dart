// ignore_for_file: invalid_use_of_protected_member
//
// NEDEN: Bu dosya `part of 'dashboard_ekrani.dart'` ve içeriği
// `extension ... on _DashboardEkraniState` olarak yazılmış — projenin
// diğer büyük ekranlarında (bkz. iade_ekrani_hizli.dart,
// urun_ekle_ekrani_ai_ses.dart) zaten kullanılan, ÇALIŞAN bir desen.
// Dart analizcisi `setState`'i @protected gördüğü için, extension
// içinden çağrıyı "korumalı üyeye dışarıdan erişim" sayıyor. Derlemeyi
// engellemez; sadece analiz uyarısıdır.
// lib/ekranlar/dashboard/dashboard_appbar_ext.dart
// dashboard_ekrani.dart'ın parçası — üst bar (SliverAppBar) inşası
// (god-class sertleştirmesi, 2026-09-22). Davranış birebir korundu.
part of 'dashboard_ekrani.dart';

extension _DashboardAppBarExt on _DashboardEkraniState {
  // ── Modern AppBar ──────────────────────────────────────────────────────────
  Widget _modernAppBar() {
    final saatTarih =
        DateFormat('HH:mm • dd MMMM yyyy', 'tr_TR').format(DateTime.now());
    final ad = ref.watch(authProvider).aktifAd;
    final selamlama = _selamlama();
    final masaModu = ref.watch(masaModuProvider);
    final masaDoluSayisi = masaModu
        ? ref.watch(masaListesiProvider).maybeWhen(
            data: (m) => m.where((x) => x.durum != 'bos').length,
            orElse: () => 0)
        : 0;

    return SliverAppBar(
      expandedHeight: 150,
      pinned: true,
      elevation: 0,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white, size: 22),
      actionsIconTheme: const IconThemeData(color: Colors.white, size: 22),
      backgroundColor: TsRenk.primary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [TsRenk.primary, TsRenk.primaryKoyu],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    // 🔴 DÜZELTME (kullanıcı isteği): logo + logo yazısı
                    // kaldırıldı — üst bar zaten marka rengiyle (primary
                    // gradyan) geliyor, ayrıca küçük bir logo/yazı ikilisi
                    // görsel gürültü yaratıyordu.
                    // 🔴 DÜZELTME: Bu 2 rozet (Tümü/Şube) Expanded/Flexible
                    // olmadan diziliyordu — uzun şube adında dar ekranlarda
                    // RenderFlex taşma hatası riski vardı. Artık gerekirse
                    // yatay kaydırılabilir.
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          // Tüm Uygulamalar butonu
                          GestureDetector(
                            onTap: () => setState(() =>
                                _tumUygulamalarGoster = !_tumUygulamalarGoster),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(20),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: Colors.white.withAlpha(40),
                                    width: 1),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        _tumUygulamalarGoster
                                            ? Icons.grid_view
                                            : Icons.apps,
                                        size: 16,
                                        color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                        _tumUygulamalarGoster
                                            ? 'Ana Sayfa'
                                            : 'Tümü',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                  ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Aktif Şube göstergesi — kilitli değilse tıklanınca
                          // şube değiştirme seçeneği sunuyor.
                          AnimatedBuilder(
                            animation: AktifSubeServisi(),
                            builder: (context, _) => GestureDetector(
                              onTap: AktifSubeServisi().kilitliMi
                                  ? null
                                  : () => _subeSecDialogGoster(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(20),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                      color: Colors.white.withAlpha(40),
                                      width: 1),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.store_outlined,
                                          size: 14, color: Colors.white),
                                      const SizedBox(width: 4),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 90),
                                        child: Text(AktifSubeServisi().subeAdi,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                      if (!AktifSubeServisi().kilitliMi) ...[
                                        const SizedBox(width: 2),
                                        const Icon(Icons.expand_more,
                                            size: 14, color: Colors.white70),
                                      ],
                                    ]),
                              ),
                            ),
                          ),
                          // 🔴 DÜZELTME (kullanıcı isteği): "Yazıcı Bağlı/
                          // Yazıcı Yok" rozeti kaldırıldı — diğer rozetlerle
                          // (Tümü/Şube) üst üste binip görsel karmaşa
                          // yaratıyordu. Yazıcı durumu zaten Ayarlar >
                          // Yazıcı Ayarları ekranından görülüp yönetilebiliyor.
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _kullaniciDegistirAc,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(
                          ad.isNotEmpty ? '$selamlama, $ad 👋' : selamlama,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.swap_horiz_rounded,
                          size: 18, color: Colors.white70),
                    ]),
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(
                      saatTarih,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Kullanıcı isteği: "buluta gönderme ve alma ana
                    // menüde ikon olsa, tarih/saatin yan tarafına"
                    // (araya boşluk: kullanıcı "çok yakın, basılmıyor"
                    // dediği için 10→16)
                    SyncMiniButon(ref: ref),
                  ]),
                  if (masaModu && masaDoluSayisi > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GestureDetector(
                        onTap: () => context.push('/masa'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(30),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withAlpha(60), width: 0.5),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.table_restaurant,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('$masaDoluSayisi masa dolu',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white),
          onPressed: () => context.push('/arama'),
          tooltip: 'Ara',
        ),
        Builder(builder: (context) {
          final sayi = ref.watch(okunmamisSayiProvider);
          return Stack(clipBehavior: Clip.none, children: [
            IconButton(
              icon:
                  const Icon(Icons.notifications_outlined, color: Colors.white),
              onPressed: () => context.push('/bildirimler'),
              tooltip: 'Bildirimler',
            ),
            if (sayi > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10)),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(sayi > 99 ? '99+' : '$sayi',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ),
          ]);
        }),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: () => ref.read(dashboardProvider.notifier).yenile(),
          tooltip: 'Yenile',
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: _cikisYap,
          tooltip: 'Çıkış',
        ),
      ],
    );
  }
}
