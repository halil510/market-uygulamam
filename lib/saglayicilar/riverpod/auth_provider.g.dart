// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$aktifKullaniciHash() => r'25d2a7698549817451bea99625e8b4fd290c25ea';

/// See also [aktifKullanici].
@ProviderFor(aktifKullanici)
final aktifKullaniciProvider = AutoDisposeProvider<KullaniciModel?>.internal(
  aktifKullanici,
  name: r'aktifKullaniciProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$aktifKullaniciHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AktifKullaniciRef = AutoDisposeProviderRef<KullaniciModel?>;
String _$girisYapildiMiHash() => r'0241521ceead8e75a1c8ad583f30b2eb69b96990';

/// See also [girisYapildiMi].
@ProviderFor(girisYapildiMi)
final girisYapildiMiProvider = AutoDisposeProvider<bool>.internal(
  girisYapildiMi,
  name: r'girisYapildiMiProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$girisYapildiMiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GirisYapildiMiRef = AutoDisposeProviderRef<bool>;
String _$isAdminHash() => r'752d7e15978376ea6d64670c3e3fe7bca17407a0';

/// See also [isAdmin].
@ProviderFor(isAdmin)
final isAdminProvider = AutoDisposeProvider<bool>.internal(
  isAdmin,
  name: r'isAdminProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$isAdminHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IsAdminRef = AutoDisposeProviderRef<bool>;
String _$authHash() => r'af52e09835cc1e4b2c2f13ddbaebdf1d3e10d369';

/// See also [Auth].
@ProviderFor(Auth)
final authProvider = AutoDisposeNotifierProvider<Auth, AuthState>.internal(
  Auth.new,
  name: r'authProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$authHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Auth = AutoDisposeNotifier<AuthState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
