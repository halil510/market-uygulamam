// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cari_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$filtreliMusterilerHash() =>
    r'd229c534a8d9889d53b91eda40c6521ff9089307';

/// See also [filtreliMusteriler].
@ProviderFor(filtreliMusteriler)
final filtreliMusterilerProvider =
    AutoDisposeProvider<List<CariModel>>.internal(
  filtreliMusteriler,
  name: r'filtreliMusterilerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$filtreliMusterilerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef FiltreliMusterilerRef = AutoDisposeProviderRef<List<CariModel>>;
String _$filtreliTedarikcilerHash() =>
    r'28e6384cb1780614433b8e5dd687cbc899f6edb4';

/// See also [filtreliTedarikciler].
@ProviderFor(filtreliTedarikciler)
final filtreliTedarikcilerProvider =
    AutoDisposeProvider<List<CariModel>>.internal(
  filtreliTedarikciler,
  name: r'filtreliTedarikcilerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$filtreliTedarikcilerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef FiltreliTedarikcilerRef = AutoDisposeProviderRef<List<CariModel>>;
String _$cariDetayHash() => r'130fa4fcd23bb17e21d1e3d6fadb256dc1217dc2';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [cariDetay].
@ProviderFor(cariDetay)
const cariDetayProvider = CariDetayFamily();

/// See also [cariDetay].
class CariDetayFamily extends Family<AsyncValue<CariModel?>> {
  /// See also [cariDetay].
  const CariDetayFamily();

  /// See also [cariDetay].
  CariDetayProvider call(
    int id,
  ) {
    return CariDetayProvider(
      id,
    );
  }

  @override
  CariDetayProvider getProviderOverride(
    covariant CariDetayProvider provider,
  ) {
    return call(
      provider.id,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'cariDetayProvider';
}

/// See also [cariDetay].
class CariDetayProvider extends AutoDisposeFutureProvider<CariModel?> {
  /// See also [cariDetay].
  CariDetayProvider(
    int id,
  ) : this._internal(
          (ref) => cariDetay(
            ref as CariDetayRef,
            id,
          ),
          from: cariDetayProvider,
          name: r'cariDetayProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$cariDetayHash,
          dependencies: CariDetayFamily._dependencies,
          allTransitiveDependencies: CariDetayFamily._allTransitiveDependencies,
          id: id,
        );

  CariDetayProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.id,
  }) : super.internal();

  final int id;

  @override
  Override overrideWith(
    FutureOr<CariModel?> Function(CariDetayRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: CariDetayProvider._internal(
        (ref) => create(ref as CariDetayRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        id: id,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<CariModel?> createElement() {
    return _CariDetayProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is CariDetayProvider && other.id == id;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, id.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin CariDetayRef on AutoDisposeFutureProviderRef<CariModel?> {
  /// The parameter `id` of this provider.
  int get id;
}

class _CariDetayProviderElement
    extends AutoDisposeFutureProviderElement<CariModel?> with CariDetayRef {
  _CariDetayProviderElement(super.provider);

  @override
  int get id => (origin as CariDetayProvider).id;
}

String _$cariYukleniyorHash() => r'7bcbb8f03bb64972473af6b9d6d7c77d3fe01756';

/// See also [cariYukleniyor].
@ProviderFor(cariYukleniyor)
final cariYukleniyorProvider = AutoDisposeProvider<bool>.internal(
  cariYukleniyor,
  name: r'cariYukleniyorProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$cariYukleniyorHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CariYukleniyorRef = AutoDisposeProviderRef<bool>;
String _$cariFiltresiHash() => r'd268cb56a4ae06503da0f45205a12812a9b665ad';

/// See also [CariFiltresi].
@ProviderFor(CariFiltresi)
final cariFiltresiProvider =
    AutoDisposeNotifierProvider<CariFiltresi, CariFiltre>.internal(
  CariFiltresi.new,
  name: r'cariFiltresiProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$cariFiltresiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CariFiltresi = AutoDisposeNotifier<CariFiltre>;
String _$carilerHash() => r'9469e3f97334c0c2d5e091c44e73a2079f7b98de';

/// See also [Cariler].
@ProviderFor(Cariler)
final carilerProvider =
    AutoDisposeNotifierProvider<Cariler, CariListeDurum>.internal(
  Cariler.new,
  name: r'carilerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$carilerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Cariler = AutoDisposeNotifier<CariListeDurum>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
