// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sepet_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$aktifPromosyonlarHash() => r'd9c8c49286222b81d520d356ce8d68654b1bf229';

/// See also [aktifPromosyonlar].
@ProviderFor(aktifPromosyonlar)
final aktifPromosyonlarProvider =
    AutoDisposeFutureProvider<Map<int, List<PromosyonModel>>>.internal(
  aktifPromosyonlar,
  name: r'aktifPromosyonlarProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$aktifPromosyonlarHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AktifPromosyonlarRef
    = AutoDisposeFutureProviderRef<Map<int, List<PromosyonModel>>>;
String _$sepetKalemSayisiHash() => r'af5c8b2b8c43da6cc9719313cdbfe28f02f4f3f2';

/// See also [sepetKalemSayisi].
@ProviderFor(sepetKalemSayisi)
final sepetKalemSayisiProvider = AutoDisposeProvider<int>.internal(
  sepetKalemSayisi,
  name: r'sepetKalemSayisiProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sepetKalemSayisiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SepetKalemSayisiRef = AutoDisposeProviderRef<int>;
String _$sepetToplamTutarHash() => r'96f9c9bcbc115403fab78e02899ec0d4d385c5c3';

/// See also [sepetToplamTutar].
@ProviderFor(sepetToplamTutar)
final sepetToplamTutarProvider = AutoDisposeProvider<double>.internal(
  sepetToplamTutar,
  name: r'sepetToplamTutarProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sepetToplamTutarHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SepetToplamTutarRef = AutoDisposeProviderRef<double>;
String _$sepetBosHash() => r'bd157fa7b336d3ddc9da006ed9af073f18012934';

/// See also [sepetBos].
@ProviderFor(sepetBos)
final sepetBosProvider = AutoDisposeProvider<bool>.internal(
  sepetBos,
  name: r'sepetBosProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$sepetBosHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SepetBosRef = AutoDisposeProviderRef<bool>;
String _$sepetMusteriHash() => r'4be910479c42055ebb7db5e10a47c217eb1285f8';

/// See also [sepetMusteri].
@ProviderFor(sepetMusteri)
final sepetMusteriProvider = AutoDisposeProvider<CariModel?>.internal(
  sepetMusteri,
  name: r'sepetMusteriProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$sepetMusteriHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SepetMusteriRef = AutoDisposeProviderRef<CariModel?>;
String _$sepetHash() => r'04e553fb6d72748180d611839c44f92ade3f206b';

/// See also [Sepet].
@ProviderFor(Sepet)
final sepetProvider = NotifierProvider<Sepet, SepetDurum>.internal(
  Sepet.new,
  name: r'sepetProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$sepetHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Sepet = Notifier<SepetDurum>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
