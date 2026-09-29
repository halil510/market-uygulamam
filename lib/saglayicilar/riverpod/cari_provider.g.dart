// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cari_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CariFiltresi)
final cariFiltresiProvider = CariFiltresiProvider._();

final class CariFiltresiProvider
    extends $NotifierProvider<CariFiltresi, CariFiltre> {
  CariFiltresiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cariFiltresiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cariFiltresiHash();

  @$internal
  @override
  CariFiltresi create() => CariFiltresi();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CariFiltre value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CariFiltre>(value),
    );
  }
}

String _$cariFiltresiHash() => r'd268cb56a4ae06503da0f45205a12812a9b665ad';

abstract class _$CariFiltresi extends $Notifier<CariFiltre> {
  CariFiltre build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CariFiltre, CariFiltre>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CariFiltre, CariFiltre>,
              CariFiltre,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(Cariler)
final carilerProvider = CarilerProvider._();

final class CarilerProvider extends $NotifierProvider<Cariler, CariListeDurum> {
  CarilerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'carilerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$carilerHash();

  @$internal
  @override
  Cariler create() => Cariler();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CariListeDurum value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CariListeDurum>(value),
    );
  }
}

String _$carilerHash() => r'9469e3f97334c0c2d5e091c44e73a2079f7b98de';

abstract class _$Cariler extends $Notifier<CariListeDurum> {
  CariListeDurum build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CariListeDurum, CariListeDurum>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CariListeDurum, CariListeDurum>,
              CariListeDurum,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(filtreliMusteriler)
final filtreliMusterilerProvider = FiltreliMusterilerProvider._();

final class FiltreliMusterilerProvider
    extends
        $FunctionalProvider<List<CariModel>, List<CariModel>, List<CariModel>>
    with $Provider<List<CariModel>> {
  FiltreliMusterilerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filtreliMusterilerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filtreliMusterilerHash();

  @$internal
  @override
  $ProviderElement<List<CariModel>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<CariModel> create(Ref ref) {
    return filtreliMusteriler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CariModel> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CariModel>>(value),
    );
  }
}

String _$filtreliMusterilerHash() =>
    r'd229c534a8d9889d53b91eda40c6521ff9089307';

@ProviderFor(filtreliTedarikciler)
final filtreliTedarikcilerProvider = FiltreliTedarikcilerProvider._();

final class FiltreliTedarikcilerProvider
    extends
        $FunctionalProvider<List<CariModel>, List<CariModel>, List<CariModel>>
    with $Provider<List<CariModel>> {
  FiltreliTedarikcilerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filtreliTedarikcilerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filtreliTedarikcilerHash();

  @$internal
  @override
  $ProviderElement<List<CariModel>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<CariModel> create(Ref ref) {
    return filtreliTedarikciler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CariModel> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CariModel>>(value),
    );
  }
}

String _$filtreliTedarikcilerHash() =>
    r'28e6384cb1780614433b8e5dd687cbc899f6edb4';

@ProviderFor(cariDetay)
final cariDetayProvider = CariDetayFamily._();

final class CariDetayProvider
    extends
        $FunctionalProvider<
          AsyncValue<CariModel?>,
          CariModel?,
          FutureOr<CariModel?>
        >
    with $FutureModifier<CariModel?>, $FutureProvider<CariModel?> {
  CariDetayProvider._({
    required CariDetayFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'cariDetayProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cariDetayHash();

  @override
  String toString() {
    return r'cariDetayProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CariModel?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<CariModel?> create(Ref ref) {
    final argument = this.argument as int;
    return cariDetay(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CariDetayProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cariDetayHash() => r'130fa4fcd23bb17e21d1e3d6fadb256dc1217dc2';

final class CariDetayFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<CariModel?>, int> {
  CariDetayFamily._()
    : super(
        retry: null,
        name: r'cariDetayProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CariDetayProvider call(int id) =>
      CariDetayProvider._(argument: id, from: this);

  @override
  String toString() => r'cariDetayProvider';
}

@ProviderFor(cariYukleniyor)
final cariYukleniyorProvider = CariYukleniyorProvider._();

final class CariYukleniyorProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  CariYukleniyorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cariYukleniyorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cariYukleniyorHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return cariYukleniyor(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$cariYukleniyorHash() => r'7bcbb8f03bb64972473af6b9d6d7c77d3fe01756';
