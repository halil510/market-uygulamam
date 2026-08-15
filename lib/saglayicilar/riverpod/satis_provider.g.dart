// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'satis_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$gunlukSatisOzetiHash() => r'8a72dc0da7f37d9445010d4270e8ac26d1e0b408';

/// See also [gunlukSatisOzeti].
@ProviderFor(gunlukSatisOzeti)
final gunlukSatisOzetiProvider =
    AutoDisposeFutureProvider<Map<String, dynamic>>.internal(
  gunlukSatisOzeti,
  name: r'gunlukSatisOzetiProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$gunlukSatisOzetiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GunlukSatisOzetiRef
    = AutoDisposeFutureProviderRef<Map<String, dynamic>>;
String _$satisDetayiHash() => r'833bb1a5c1b09ce4e6a3704986e96a5b4539b6f3';

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

/// See also [satisDetayi].
@ProviderFor(satisDetayi)
const satisDetayiProvider = SatisDetayiFamily();

/// See also [satisDetayi].
class SatisDetayiFamily extends Family<AsyncValue<SatisModel?>> {
  /// See also [satisDetayi].
  const SatisDetayiFamily();

  /// See also [satisDetayi].
  SatisDetayiProvider call(
    int id,
  ) {
    return SatisDetayiProvider(
      id,
    );
  }

  @override
  SatisDetayiProvider getProviderOverride(
    covariant SatisDetayiProvider provider,
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
  String? get name => r'satisDetayiProvider';
}

/// See also [satisDetayi].
class SatisDetayiProvider extends AutoDisposeFutureProvider<SatisModel?> {
  /// See also [satisDetayi].
  SatisDetayiProvider(
    int id,
  ) : this._internal(
          (ref) => satisDetayi(
            ref as SatisDetayiRef,
            id,
          ),
          from: satisDetayiProvider,
          name: r'satisDetayiProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$satisDetayiHash,
          dependencies: SatisDetayiFamily._dependencies,
          allTransitiveDependencies:
              SatisDetayiFamily._allTransitiveDependencies,
          id: id,
        );

  SatisDetayiProvider._internal(
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
    FutureOr<SatisModel?> Function(SatisDetayiRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SatisDetayiProvider._internal(
        (ref) => create(ref as SatisDetayiRef),
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
  AutoDisposeFutureProviderElement<SatisModel?> createElement() {
    return _SatisDetayiProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SatisDetayiProvider && other.id == id;
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
mixin SatisDetayiRef on AutoDisposeFutureProviderRef<SatisModel?> {
  /// The parameter `id` of this provider.
  int get id;
}

class _SatisDetayiProviderElement
    extends AutoDisposeFutureProviderElement<SatisModel?> with SatisDetayiRef {
  _SatisDetayiProviderElement(super.provider);

  @override
  int get id => (origin as SatisDetayiProvider).id;
}

String _$satisFiltresiHash() => r'fd049e433cfbf97fd37a27e083700c6a4d323cf1';

/// See also [SatisFiltresi].
@ProviderFor(SatisFiltresi)
final satisFiltresiProvider =
    AutoDisposeNotifierProvider<SatisFiltresi, SatisFiltre>.internal(
  SatisFiltresi.new,
  name: r'satisFiltresiProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$satisFiltresiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SatisFiltresi = AutoDisposeNotifier<SatisFiltre>;
String _$satislarHash() => r'1f73e84b6fe36e4e952cda039a840eabe9ef721a';

/// See also [Satislar].
@ProviderFor(Satislar)
final satislarProvider =
    AutoDisposeNotifierProvider<Satislar, SatisListeDurum>.internal(
  Satislar.new,
  name: r'satislarProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$satislarHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Satislar = AutoDisposeNotifier<SatisListeDurum>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
