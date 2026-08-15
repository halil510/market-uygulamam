// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'urun_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$urunYukleniyorHash() => r'23c29c66cfdbb73031ab5e5bdd55b2fcb7be707b';

/// See also [urunYukleniyor].
@ProviderFor(urunYukleniyor)
final urunYukleniyorProvider = AutoDisposeProvider<bool>.internal(
  urunYukleniyor,
  name: r'urunYukleniyorProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$urunYukleniyorHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UrunYukleniyorRef = AutoDisposeProviderRef<bool>;
String _$urunSecimModuHash() => r'82b5ec609099c8ad98fbea677c6934d921e00e7b';

/// See also [urunSecimModu].
@ProviderFor(urunSecimModu)
final urunSecimModuProvider = AutoDisposeProvider<bool>.internal(
  urunSecimModu,
  name: r'urunSecimModuProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$urunSecimModuHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UrunSecimModuRef = AutoDisposeProviderRef<bool>;
String _$urunSeciliSayisiHash() => r'907996388ddb8feee153c93d9776354af75c2a36';

/// See also [urunSeciliSayisi].
@ProviderFor(urunSeciliSayisi)
final urunSeciliSayisiProvider = AutoDisposeProvider<int>.internal(
  urunSeciliSayisi,
  name: r'urunSeciliSayisiProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$urunSeciliSayisiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UrunSeciliSayisiRef = AutoDisposeProviderRef<int>;
String _$kritikStokSayisiHash() => r'ae47ca9f3c88ff364faf00612c663332c7f87871';

/// See also [kritikStokSayisi].
@ProviderFor(kritikStokSayisi)
final kritikStokSayisiProvider = AutoDisposeProvider<int>.internal(
  kritikStokSayisi,
  name: r'kritikStokSayisiProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$kritikStokSayisiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef KritikStokSayisiRef = AutoDisposeProviderRef<int>;
String _$urunDetayHash() => r'db75bc247cd02278c87dd9faae0493e57cecbb91';

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

/// See also [urunDetay].
@ProviderFor(urunDetay)
const urunDetayProvider = UrunDetayFamily();

/// See also [urunDetay].
class UrunDetayFamily extends Family<AsyncValue<UrunModel?>> {
  /// See also [urunDetay].
  const UrunDetayFamily();

  /// See also [urunDetay].
  UrunDetayProvider call(
    int id,
  ) {
    return UrunDetayProvider(
      id,
    );
  }

  @override
  UrunDetayProvider getProviderOverride(
    covariant UrunDetayProvider provider,
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
  String? get name => r'urunDetayProvider';
}

/// See also [urunDetay].
class UrunDetayProvider extends AutoDisposeFutureProvider<UrunModel?> {
  /// See also [urunDetay].
  UrunDetayProvider(
    int id,
  ) : this._internal(
          (ref) => urunDetay(
            ref as UrunDetayRef,
            id,
          ),
          from: urunDetayProvider,
          name: r'urunDetayProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$urunDetayHash,
          dependencies: UrunDetayFamily._dependencies,
          allTransitiveDependencies: UrunDetayFamily._allTransitiveDependencies,
          id: id,
        );

  UrunDetayProvider._internal(
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
    FutureOr<UrunModel?> Function(UrunDetayRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UrunDetayProvider._internal(
        (ref) => create(ref as UrunDetayRef),
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
  AutoDisposeFutureProviderElement<UrunModel?> createElement() {
    return _UrunDetayProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UrunDetayProvider && other.id == id;
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
mixin UrunDetayRef on AutoDisposeFutureProviderRef<UrunModel?> {
  /// The parameter `id` of this provider.
  int get id;
}

class _UrunDetayProviderElement
    extends AutoDisposeFutureProviderElement<UrunModel?> with UrunDetayRef {
  _UrunDetayProviderElement(super.provider);

  @override
  int get id => (origin as UrunDetayProvider).id;
}

String _$barkodileUrunBulHash() => r'd06323bb5169b4c1a8a5182e710ea7c3829e85f1';

/// See also [barkodileUrunBul].
@ProviderFor(barkodileUrunBul)
const barkodileUrunBulProvider = BarkodileUrunBulFamily();

/// See also [barkodileUrunBul].
class BarkodileUrunBulFamily extends Family<AsyncValue<UrunModel?>> {
  /// See also [barkodileUrunBul].
  const BarkodileUrunBulFamily();

  /// See also [barkodileUrunBul].
  BarkodileUrunBulProvider call(
    String barkod,
  ) {
    return BarkodileUrunBulProvider(
      barkod,
    );
  }

  @override
  BarkodileUrunBulProvider getProviderOverride(
    covariant BarkodileUrunBulProvider provider,
  ) {
    return call(
      provider.barkod,
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
  String? get name => r'barkodileUrunBulProvider';
}

/// See also [barkodileUrunBul].
class BarkodileUrunBulProvider extends AutoDisposeFutureProvider<UrunModel?> {
  /// See also [barkodileUrunBul].
  BarkodileUrunBulProvider(
    String barkod,
  ) : this._internal(
          (ref) => barkodileUrunBul(
            ref as BarkodileUrunBulRef,
            barkod,
          ),
          from: barkodileUrunBulProvider,
          name: r'barkodileUrunBulProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$barkodileUrunBulHash,
          dependencies: BarkodileUrunBulFamily._dependencies,
          allTransitiveDependencies:
              BarkodileUrunBulFamily._allTransitiveDependencies,
          barkod: barkod,
        );

  BarkodileUrunBulProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.barkod,
  }) : super.internal();

  final String barkod;

  @override
  Override overrideWith(
    FutureOr<UrunModel?> Function(BarkodileUrunBulRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: BarkodileUrunBulProvider._internal(
        (ref) => create(ref as BarkodileUrunBulRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        barkod: barkod,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<UrunModel?> createElement() {
    return _BarkodileUrunBulProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is BarkodileUrunBulProvider && other.barkod == barkod;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, barkod.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin BarkodileUrunBulRef on AutoDisposeFutureProviderRef<UrunModel?> {
  /// The parameter `barkod` of this provider.
  String get barkod;
}

class _BarkodileUrunBulProviderElement
    extends AutoDisposeFutureProviderElement<UrunModel?>
    with BarkodileUrunBulRef {
  _BarkodileUrunBulProviderElement(super.provider);

  @override
  String get barkod => (origin as BarkodileUrunBulProvider).barkod;
}

String _$urunFiltresiHash() => r'631916fc9487496640e254b6d718ee0850b6ff33';

/// See also [UrunFiltresi].
@ProviderFor(UrunFiltresi)
final urunFiltresiProvider =
    AutoDisposeNotifierProvider<UrunFiltresi, UrunFiltre>.internal(
  UrunFiltresi.new,
  name: r'urunFiltresiProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$urunFiltresiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$UrunFiltresi = AutoDisposeNotifier<UrunFiltre>;
String _$urunlerHash() => r'b8c7e7dd1a4baa9df24b86fcdedf13c89980946a';

/// See also [Urunler].
@ProviderFor(Urunler)
final urunlerProvider =
    AutoDisposeNotifierProvider<Urunler, UrunListeDurum>.internal(
  Urunler.new,
  name: r'urunlerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$urunlerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Urunler = AutoDisposeNotifier<UrunListeDurum>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
