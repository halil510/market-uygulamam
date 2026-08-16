// lib/saglayicilar/riverpod/doviz_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../depolar/doviz_deposu.dart';
import '../../modeller/doviz_model.dart';

final dovizKurlariProvider = FutureProvider<List<DovizModel>>((ref) async {
  return await DovizDeposu().tumunuGetir();
});

final dovizKuruProvider = FutureProvider.family<DovizModel?, String>((ref, kod) async {
  if (kod == 'TRY') return null;
  return await DovizDeposu().koduIleGetir(kod);
});

/// Bir yabancı para birimi tutarını TRY karşılığına çevirir. Kur
/// girilmemişse (0) null döner — çağıran taraf bu durumda "kur girin"
/// uyarısı göstermeli, asla varsayılan/tahmini bir kur kullanmamalıyız.
double? dovizToTry(double tutar, DovizModel? kur) {
  if (kur == null || kur.satisKuru <= 0) return null;
  return tutar * kur.satisKuru;
}
