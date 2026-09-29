// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'promosyon_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PromosyonFiltresi)
final promosyonFiltresiProvider = PromosyonFiltresiProvider._();

final class PromosyonFiltresiProvider
    extends $NotifierProvider<PromosyonFiltresi, PromosyonFiltre> {
  PromosyonFiltresiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'promosyonFiltresiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$promosyonFiltresiHash();

  @$internal
  @override
  PromosyonFiltresi create() => PromosyonFiltresi();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PromosyonFiltre value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PromosyonFiltre>(value),
    );
  }
}

String _$promosyonFiltresiHash() => r'9282175fcec18894ae1ea42c6a3d14fd1e89fae2';

abstract class _$PromosyonFiltresi extends $Notifier<PromosyonFiltre> {
  PromosyonFiltre build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PromosyonFiltre, PromosyonFiltre>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PromosyonFiltre, PromosyonFiltre>,
              PromosyonFiltre,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(promosyonlar)
final promosyonlarProvider = PromosyonlarProvider._();

final class PromosyonlarProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PromosyonModel>>,
          List<PromosyonModel>,
          FutureOr<List<PromosyonModel>>
        >
    with
        $FutureModifier<List<PromosyonModel>>,
        $FutureProvider<List<PromosyonModel>> {
  PromosyonlarProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'promosyonlarProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$promosyonlarHash();

  @$internal
  @override
  $FutureProviderElement<List<PromosyonModel>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<PromosyonModel>> create(Ref ref) {
    return promosyonlar(ref);
  }
}

String _$promosyonlarHash() => r'da4fee95c23b67b9ccba46060449520284f583ac';

@ProviderFor(filtreliPromosyonlar)
final filtreliPromosyonlarProvider = FiltreliPromosyonlarProvider._();

final class FiltreliPromosyonlarProvider
    extends
        $FunctionalProvider<
          List<PromosyonModel>,
          List<PromosyonModel>,
          List<PromosyonModel>
        >
    with $Provider<List<PromosyonModel>> {
  FiltreliPromosyonlarProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filtreliPromosyonlarProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filtreliPromosyonlarHash();

  @$internal
  @override
  $ProviderElement<List<PromosyonModel>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<PromosyonModel> create(Ref ref) {
    return filtreliPromosyonlar(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PromosyonModel> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PromosyonModel>>(value),
    );
  }
}

String _$filtreliPromosyonlarHash() =>
    r'18b98f1b858f1448f6f83068de2fa46975d691ca';

@ProviderFor(aktifPromosyonSayisi)
final aktifPromosyonSayisiProvider = AktifPromosyonSayisiProvider._();

final class AktifPromosyonSayisiProvider
    extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  AktifPromosyonSayisiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aktifPromosyonSayisiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aktifPromosyonSayisiHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return aktifPromosyonSayisi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$aktifPromosyonSayisiHash() =>
    r'3804945bf4793d15e5bb2bb18dc97644cbc44ec3';
