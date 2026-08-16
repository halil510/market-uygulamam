// lib/widgetlar/ortak/yetki_koruma.dart  (Riverpod versiyonu)
//
// DEĞIŞIKLIKLER:
//   - context.watch<AuthSaglayici>() → ref.watch(authProvider)
//   - 🔴 Derin analizde bulundu: dosyanın sonunda YEREL, EKSİK bir
//     'AppRenkler' kopyası vardı (sadece 'primary' alanı) — gerçek,
//     tam sınıf zaten lib/uygulama/tema/acik_tema.dart'ta tanımlıydı.
//     Bu, kafa karıştırıcı bir kod kokusuydu ve tema değişse bile bu
//     ekranın rengi hep sabit kalırdı. Ayrıca ekran karanlık modu hiç
//     desteklemiyordu (sabit gri metin renkleri, sabit Scaffold arka
//     planı) — düzeltildi.

import 'package:flutter/material.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../uygulama/tema/acik_tema.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

/// YetkiKoruma — belirtilen [yetkiKodu] yoksa erişimi engeller
class YetkiKoruma extends ConsumerWidget {
  final String yetkiKodu;
  final String ekranAdi;
  final Widget child;

  const YetkiKoruma({
    super.key,
    required this.yetkiKodu,
    required this.ekranAdi,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    // Admin veya müdür — her şeye erişebilir
    if (auth.isAdmin || auth.isMudur) return child;

    // Yetki kontrolü
    final yetkiVar = ref.watch(authProvider.notifier).yetkiVarSync(yetkiKodu);

    if (!yetkiVar) {
      return Scaffold(
        backgroundColor: context.scaffoldBg,
        appBar: TsAppBar(
        baslikWidget: Text(ekranAdi),
      ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(context.isDark ? 40 : 25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline,
                      color: Colors.red.shade700, size: 40),
                ),
                const SizedBox(height: 24),
                Text(
                  'Erişim Kısıtlı',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: context.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  '"$ekranAdi" ekranına erişim yetkiniz yok.\n'
                  'Yöneticinizle iletişime geçin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, color: context.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Ana Sayfaya Dön'),
                  style: FilledButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: AppRenkler.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return child;
  }
}
