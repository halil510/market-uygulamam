// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kasa_rapor_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$kasaRaporHash() => r'4a4897377835d2c8a9ad6a7a7624ace685bb55af';

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

/// See also [kasaRapor].
@ProviderFor(kasaRapor)
const kasaRaporProvider = KasaRaporFamily();

/// See also [kasaRapor].
class KasaRaporFamily extends Family<AsyncValue<KasaRaporVeri>> {
  /// See also [kasaRapor].
  const KasaRaporFamily();

  /// See also [kasaRapor].
  KasaRaporProvider call(
    DateTimeRange<DateTime> aralik,
  ) {
    return KasaRaporProvider(
      aralik,
    );
  }

  @override
  KasaRaporProvider getProviderOverride(
    covariant KasaRaporProvider provider,
  ) {
    return call(
      provider.aralik,
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
  String? get name => r'kasaRaporProvider';
}

/// See also [kasaRapor].
class KasaRaporProvider extends AutoDisposeFutureProvider<KasaRaporVeri> {
  /// See also [kasaRapor].
  KasaRaporProvider(
    DateTimeRange<DateTime> aralik,
  ) : this._internal(
          (ref) => kasaRapor(
            ref as KasaRaporRef,
            aralik,
          ),
          from: kasaRaporProvider,
          name: r'kasaRaporProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$kasaRaporHash,
          dependencies: KasaRaporFamily._dependencies,
          allTransitiveDependencies: KasaRaporFamily._allTransitiveDependencies,
          aralik: aralik,
        );

  KasaRaporProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.aralik,
  }) : super.internal();

  final DateTimeRange<DateTime> aralik;

  @override
  Override overrideWith(
    FutureOr<KasaRaporVeri> Function(KasaRaporRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: KasaRaporProvider._internal(
        (ref) => create(ref as KasaRaporRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        aralik: aralik,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<KasaRaporVeri> createElement() {
    return _KasaRaporProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is KasaRaporProvider && other.aralik == aralik;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, aralik.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin KasaRaporRef on AutoDisposeFutureProviderRef<KasaRaporVeri> {
  /// The parameter `aralik` of this provider.
  DateTimeRange<DateTime> get aralik;
}

class _KasaRaporProviderElement
    extends AutoDisposeFutureProviderElement<KasaRaporVeri> with KasaRaporRef {
  _KasaRaporProviderElement(super.provider);

  @override
  DateTimeRange<DateTime> get aralik => (origin as KasaRaporProvider).aralik;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
