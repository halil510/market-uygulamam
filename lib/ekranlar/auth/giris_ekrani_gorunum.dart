// lib/ekranlar/auth/giris_ekrani_gorunum.dart
//
// Giriş ekranının saf görsel parçaları (logo, kullanıcı seçici, PIN
// göstergesi, numpad, giriş/parmak izi butonları) — giris_ekrani.dart'tan
// ayrıldı (2026-10-07 refactor). Şifre/kilit/biyometrik mantığı ekranda.
part of 'giris_ekrani.dart';

extension _GirisGorunum on _GirisEkraniState {
  Widget _buildGlowBlob(Color renk, double boyut) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: Container(
          width: boyut,
          height: boyut,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: renk.withAlpha(90),
          ),
        ),
      ),
    );
  }

  // ─── ALT PANEL (entegre numerik klavye) ─────────────────────────────────
  // Ekranın en alt kenarına KAYNAŞMIŞ, sadece üst köşeleri yuvarlatılmış,
  // hafif buzlu-cam (Glassmorphism) tek bir panel — üstteki bölümle AYNI
  // koyu gradyan arka planın devamı gibi görünür, ayrı bir "kart" DEĞİL.
  Widget _buildAltPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: const Border(
              top: BorderSide(color: Colors.white12, width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // PIN göstergesi + hata mesajı tuş takımının HEMEN ÜSTÜNDE:
                  // kısa ekranlarda (ör. 914 dp telefon) kaydırılabilir üst
                  // bölümün dibinde kalıp panelin altında kesiliyordu.
                  _buildPinGosterge(),
                  const SizedBox(height: 8),
                  _buildHataMesaji(),
                  const SizedBox(height: 10),
                  _buildNumPad(),
                  const SizedBox(height: 16),
                  _buildGirisButonu(),
                  const SizedBox(height: 12),
                  _buildBiometricButton(),
                  const SizedBox(height: 6),
                  const Text(
                    'v${UygSabitler.versiyon}',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── LOGO ──────────────────────────────────────────────────────────────────
  // 🔴 KULLANICI İSTEĞİ (2026-09-16): "ekran hareketli olmasın" — sürekli
  // tekrar eden (infinite repeat) nabız animasyonu kaldırıldı, statik bir
  // halka ile değiştirildi. Tek seferlik açılış animasyonu (fade/scale)
  // ve hatalı şifrede sallanma KORUNDU — bunlar "sürekli hareket" değil.
  Widget _buildLogo() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0x004361EE),
            Color(0xB44361EE),
            Color(0xB43A0CA3),
            Color(0x004361EE),
          ],
          stops: [0.0, 0.35, 0.65, 1.0],
        ),
      ),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4361EE), Color(0xFF3A0CA3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4361EE).withAlpha(90),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }

  // ─── KULLANICI SEÇİCİ ──────────────────────────────────────────────────
  Widget _buildKullaniciSecici() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: _kullanicilar,
      builder: (_, liste, _) {
        if (liste.isEmpty) return const SizedBox.shrink();
        return ValueListenableBuilder<String>(
          valueListenable: _seciliKullanici,
          builder: (_, secili, _) => Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withAlpha(35)),
            ),
            child: DropdownButtonFormField<String>(
              value: liste.contains(secili) ? secili : liste.first,
              isExpanded: true,
              icon: const Icon(Icons.expand_more, color: Colors.white70),
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                // Global tema filled:true + neredeyse beyaz dolgu uygular; beyaz
                // yazı görünmez olurdu — dolgu bilinçli kapatıldı.
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                prefixIcon: Icon(Icons.person_outline, color: Color(0xFF4361EE)),
              ),
              items: liste.map((k) {
                return DropdownMenuItem(
                  value: k,
                  child: Text(k, style: const TextStyle(color: Colors.white)),
                );
              }).toList(),
              // 🔴 KULLANICI BULGUSU (2026-09-16): kapalı haldeki (seçili)
              // metin bazı Flutter/Material sürümlerinde 'style'
              // parametresini değil, ortamdaki (genelde koyu/siyah) form
              // temasını kullanıyordu — koyu arka plan üzerinde görünmez
              // hale geliyordu. selectedItemBuilder, kapalı haldeki
              // gösterimi tema/ortamdan bağımsız, açıkça beyaz olarak
              // sabitler.
              selectedItemBuilder: (context) => liste
                  .map((k) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          k,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  _seciliKullanici.value = v;
                  _sifre.value = '';
                  _hata.value = '';
                }
              },
            ),
          ),
        );
      },
    );
  }

  // ─── PIN GÖSTERGESİ ──────────────────────────────────────────────────────
  Widget _buildPinGosterge() {
    return ValueListenableBuilder<String>(
      valueListenable: _sifre,
      builder: (_, pin, _) => AnimatedBuilder(
        animation: _shakeAnim,
        builder: (_, child) => Transform.translate(
          offset: Offset(_shakeAnim.value * (pin.isEmpty ? 0 : 1), 0),
          child: child,
        ),
        child: ValueListenableBuilder<String>(
          valueListenable: _hata,
          builder: (_, hata, _) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: hata.isNotEmpty
                  ? TsRenk.zemin(TsRenk.hata, opaklik: 0.18)
                  : Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hata.isNotEmpty
                    ? TsRenk.hata.withAlpha(140)
                    : Colors.white.withAlpha(30),
                width: hata.isNotEmpty ? 1.5 : 1,
              ),
            ),
            child: pin.isEmpty
                ? const Text(
                    'Şifrenizi girin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      pin.length,
                      (i) => TweenAnimationBuilder<double>(
                        key: ValueKey('pin_dot_$i'),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        builder: (_, deger, child) => Transform.scale(
                          scale: deger,
                          child: child,
                        ),
                        child: Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4361EE),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4361EE).withAlpha(60),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
      ),
    );
  }

  // ─── HATA MESAJI ──────────────────────────────────────────────────────────
  Widget _buildHataMesaji() {
    return ValueListenableBuilder<String>(
      valueListenable: _hata,
      builder: (_, hata, _) {
        if (hata.isEmpty) return const SizedBox.shrink();
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: TsRenk.zemin(TsRenk.hata),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TsRenk.hata.withAlpha(120)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: TsRenk.hata, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hata,
                  style: const TextStyle(
                    color: TsRenk.hata,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── NUM PAD ──────────────────────────────────────────────────────────────
  Widget _buildNumPad() {
    const tuslar = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];

    return ValueListenableBuilder<bool>(
      valueListenable: _kilitli,
      builder: (_, kilitli, _) => Opacity(
        opacity: kilitli ? 0.4 : 1.0,
        child: Column(
          children: tuslar.map((satir) {
            return Row(
              children: satir.map((t) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _buildNumTusu(t, kilitli),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNumTusu(String t, bool kilitli) {
    final isSil = t == '⌫';
    final isTemizle = t == 'C';

    return Material(
      color: isTemizle
          ? TsRenk.zemin(TsRenk.hata, opaklik: 0.18)
          : isSil
              ? TsRenk.zemin(Colors.orange, opaklik: 0.18)
              : Colors.white.withAlpha(16),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: kilitli
            ? null
            : () {
                HapticFeedback.lightImpact();
                if (isSil) {
                  _silSon();
                } else if (isTemizle) _temizle();
                else _rakamEkle(t);
              },
        child: Container(
          // 58 → 50: PIN göstergesi panele taşınınca panel yükselip üstteki
          // kullanıcı seçiciyi örtüyordu (914 dp telefon).
          height: 50,
          alignment: Alignment.center,
          child: isSil
              ? const Icon(Icons.backspace_outlined,
                  color: Colors.orange, size: 24)
              : isTemizle
                  ? const Text('C',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: TsRenk.hata,
                      ))
                  : Text(t,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      )),
        ),
      ),
    );
  }

  // ─── GİRİŞ BUTONU ────────────────────────────────────────────────────────
  Widget _buildGirisButonu() {
    return ValueListenableBuilder<bool>(
      valueListenable: _yukleniyor,
      builder: (_, yukleniyor, _) => ValueListenableBuilder<bool>(
        valueListenable: _kilitli,
        builder: (_, kilitli, _) => ValueListenableBuilder<String>(
          valueListenable: _sifre,
          builder: (_, pin, _) {
            final aktif = !(yukleniyor || kilitli || pin.isEmpty);
            return SizedBox(
              width: double.infinity,
              height: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: aktif
                      ? const LinearGradient(
                          colors: [Color(0xFF4361EE), Color(0xFF3A0CA3)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  color: aktif ? null : Colors.white.withAlpha(20),
                  boxShadow: aktif
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4361EE).withAlpha(90),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: FilledButton(
                  onPressed: aktif ? _girisYap : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                    disabledBackgroundColor: Colors.transparent,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  child: yukleniyor
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('Giriş Yap'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── PARMAK İZİ BUTONU ──────────────────────────────────────────────────
  Widget _buildBiometricButton() {
    if (_biyometrikMevcut) {
      return Column(
        children: [
          const Divider(height: 24, thickness: 0.5, color: Colors.white24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF4361EE),
                    width: 1.5,
                  ),
                ),
                child: Material(
                  color: Colors.white.withAlpha(18),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _biyometrikGirisYap,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Icon(
                        Icons.fingerprint,
                        size: 28,
                        color: Color(0xFF4361EE),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Parmak İzi ile Giriş',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      );
    } else if (_biyometrikDestekli) {
      // Henüz kayıt yoksa bilgi mesajı
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fingerprint, size: 18, color: Colors.white54),
            const SizedBox(width: 8),
            Text(
              'Şifreyle giriş yapın, parmak izi aktifleşsin',
              style: TsMetin.kucuk.copyWith(color: Colors.white60),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
