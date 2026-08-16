// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stok_sayim_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sayimGecmisHash() => r'656b41fc91886a37efeb25fa7ede6e754d640ffa';

/// See also [sayimGecmis].
@ProviderFor(sayimGecmis)
final sayimGecmisProvider =
    AutoDisposeFutureProvider<List<Map<String, dynamic>>>.internal(
  sayimGecmis,
  name: r'sayimGecmisProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$sayimGecmisHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SayimGecmisRef
    = AutoDisposeFutureProviderRef<List<Map<String, dynamic>>>;
String _$sayilanSayisiHash() => r'070e0594d52426cacee2e8e7c23807f9332f5b34';

/// See also [sayilanSayisi].
@ProviderFor(sayilanSayisi)
final sayilanSayisiProvider = AutoDisposeProvider<int>.internal(
  sayilanSayisi,
  name: r'sayilanSayisiProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sayilanSayisiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SayilanSayisiRef = AutoDisposeProviderRef<int>;
String _$stokSayimHash() => r'613c7277dcbd82d3c68681690f34e87dd99cfbce';

/// See also [StokSayim].
@ProviderFor(StokSayim)
final stokSayimProvider =
    AutoDisposeNotifierProvider<StokSayim, StokSayimDurum>.internal(
  StokSayim.new,
  name: r'stokSayimProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$stokSayimHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$StokSayim = AutoDisposeNotifier<StokSayimDurum>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
