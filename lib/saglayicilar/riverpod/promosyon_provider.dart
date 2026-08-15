// lib/saglayicilar/riverpod/promosyon_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/promosyon_deposu.dart';
import '../../modeller/promosyon_model.dart';

part 'promosyon_provider.g.dart';

class PromosyonFiltre {
  final String aramaMetni, durum;
  const PromosyonFiltre({this.aramaMetni='', this.durum='Tümü'});
  PromosyonFiltre copyWith({String? aramaMetni, String? durum}) =>
      PromosyonFiltre(aramaMetni: aramaMetni ?? this.aramaMetni, durum: durum ?? this.durum);
}

@riverpod
class PromosyonFiltresi extends _$PromosyonFiltresi {
  @override PromosyonFiltre build() => const PromosyonFiltre();
  void aramaGuncelle(String v) => state = state.copyWith(aramaMetni: v);
  void durumAyarla(String v)   => state = state.copyWith(durum: v);
  void sifirla()               => state = const PromosyonFiltre();
}

@riverpod
Future<List<PromosyonModel>> promosyonlar(PromosyonlarRef ref) =>
    PromosyonDeposu().tumunuGetir();

@riverpod
List<PromosyonModel> filtreliPromosyonlar(FiltreliPromosyonlarRef ref) {
  final f     = ref.watch(promosyonFiltresiProvider);
  final async = ref.watch(promosyonlarProvider);
  final now   = DateTime.now();
  return async.when(
    loading: () => [],
    error: (_, __) => [],
    data: (liste) {
      var s = liste;
      if (f.aramaMetni.length >= 2) {
        final q = f.aramaMetni.toLowerCase();
        s = s.where((p) =>
          p.promosyonAdi.toLowerCase().contains(q) ||
          p.urunAdi.toLowerCase().contains(q)).toList();
      }
      return switch (f.durum) {
        // 🔴 DÜZELTME: Önceden sadece 'p.aktif && bitisTarihi kontrolü'
        // yapılıyordu — başlangıç tarihi HİÇ kontrol edilmiyordu. Bu
        // yüzden henüz BAŞLAMAMIŞ (ileri tarihli) bir promosyon bile
        // "Aktif" sekmesinde yanlışlıkla görünüyordu. Model'in zaten
        // sahip olduğu kanonik 'gecerli' getter'ı (hem başlangıç hem
        // bitiş tarihini doğru kontrol eden) kullanılıyor artık.
        'Aktif'         => s.where((p) => p.aktif && p.gecerli).toList(),
        'Pasif'         => s.where((p) => !p.aktif).toList(),
        'Süresi Dolmuş' => s.where((p) => p.bitisTarihi != null && p.bitisTarihi!.isBefore(now)).toList(),
        _               => s,
      };
    },
  );
}

@riverpod
int aktifPromosyonSayisi(AktifPromosyonSayisiRef ref) =>
    // 🔴 DÜZELTME: Sadece 'p.aktif' bakıyordu — süresi dolmuş veya
    // henüz başlamamış bir promosyon bile (aktif=true olduğu sürece)
    // "aktif promosyon sayısı"na dahil ediliyordu. Artık kanonik
    // 'gecerli' kontrolü de aranıyor.
    ref.watch(promosyonlarProvider).valueOrNull?.where((p) => p.aktif && p.gecerli).length ?? 0;
