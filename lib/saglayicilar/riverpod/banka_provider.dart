// lib/saglayicilar/riverpod/banka_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../depolar/banka_deposu.dart';
import '../../depolar/banka_hesap_deposu.dart';
import '../../depolar/kredi_karti_deposu.dart';
import '../../depolar/banka_hareket_deposu.dart';
import '../../modeller/banka_model.dart';
import '../../modeller/banka_hesap_model.dart';
import '../../modeller/kredi_karti_model.dart';
import '../../modeller/banka_hareket_model.dart';

final bankalarProvider = FutureProvider<List<BankaModel>>((ref) async {
  try {
    return await BankaDeposu().tumunuGetir();
  } catch (e, st) {
    debugPrint('🔴 [banka_provider] Hata: $e\n$st');
    rethrow;
  }
});

final bankaDetayProvider = FutureProvider.family<BankaModel?, int>((ref, id) async {
  try {
    return await BankaDeposu().idileGetir(id);
  } catch (e, st) {
    debugPrint('🔴 [banka_provider] Hata: $e\n$st');
    rethrow;
  }
});

final bankaHesaplarProvider = FutureProvider.family<List<BankaHesapModel>, int?>((ref, bankaId) async {
  try {
    return await BankaHesapDeposu().tumunuGetir(bankaId: bankaId);
  } catch (e, st) {
    debugPrint('🔴 [banka_provider] Hata: $e\n$st');
    rethrow;
  }
});

final krediKartlariProvider = FutureProvider.family<List<KrediKartiModel>, int?>((ref, bankaId) async {
  try {
    return await KrediKartiDeposu().tumunuGetir(bankaId: bankaId);
  } catch (e, st) {
    debugPrint('🔴 [banka_provider] Hata: $e\n$st');
    rethrow;
  }
});

final krediKartiDetayProvider = FutureProvider.family<KrediKartiModel?, int>((ref, id) async {
  try {
    return await KrediKartiDeposu().idileGetir(id);
  } catch (e, st) {
    debugPrint('🔴 [banka_provider] Hata: $e\n$st');
    rethrow;
  }
});

class BankaHareketSorgu {
  final int? hesapId;
  final int? krediKartiId;
  final DateTime? baslangic;
  final DateTime? bitis;
  final int limit;

  const BankaHareketSorgu({
    this.hesapId,
    this.krediKartiId,
    this.baslangic,
    this.bitis,
    this.limit = 50,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BankaHareketSorgu &&
          hesapId == other.hesapId &&
          krediKartiId == other.krediKartiId &&
          baslangic == other.baslangic &&
          bitis == other.bitis &&
          limit == other.limit;

  @override
  int get hashCode => Object.hash(hesapId, krediKartiId, baslangic, bitis, limit);
}

// 🔴 Derin analizde bulundu: .autoDispose olmadan tanımlanmıştı — her
// farklı BankaHareketSorgu (tarih aralığı/hesap/kart kombinasyonu)
// uygulama ömrü boyunca önbellekte kalıcı olarak tutuluyordu. Projedeki
// @riverpod ile üretilen provider'ların hepsi varsayılan olarak
// autoDispose; tutarlılık ve gereksiz bellek büyümesini önlemek için
// burada da eklendi.
final bankaHareketlerProvider = FutureProvider.family
    .autoDispose<List<BankaHareketModel>, BankaHareketSorgu>((ref, sorgu) async {
  try {
    return await BankaHareketDeposu().hareketleriGetir(
      hesapId: sorgu.hesapId,
      krediKartiId: sorgu.krediKartiId,
      baslangic: sorgu.baslangic,
      bitis: sorgu.bitis,
      limit: sorgu.limit,
    );
  } catch (e, st) {
    debugPrint('🔴 [banka_provider] Hata: $e\n$st');
    rethrow;
  }
});