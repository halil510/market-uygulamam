// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kar_zarar_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(KarZararFiltresi)
final karZararFiltresiProvider = KarZararFiltresiProvider._();

final class KarZararFiltresiProvider
    extends $NotifierProvider<KarZararFiltresi, KarZararFiltre> {
  KarZararFiltresiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'karZararFiltresiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$karZararFiltresiHash();

  @$internal
  @override
  KarZararFiltresi create() => KarZararFiltresi();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KarZararFiltre value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KarZararFiltre>(value),
    );
  }
}

String _$karZararFiltresiHash() => r'aa3783aa288d6b9c9d096754f4dec4434ef82622';

abstract class _$KarZararFiltresi extends $Notifier<KarZararFiltre> {
  KarZararFiltre build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<KarZararFiltre, KarZararFiltre>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<KarZararFiltre, KarZararFiltre>,
              KarZararFiltre,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(karZarar)
final karZararProvider = KarZararProvider._();

final class KarZararProvider
    extends
        $FunctionalProvider<
          AsyncValue<KarZararVeri>,
          KarZararVeri,
          FutureOr<KarZararVeri>
        >
    with $FutureModifier<KarZararVeri>, $FutureProvider<KarZararVeri> {
  KarZararProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'karZararProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$karZararHash();

  @$internal
  @override
  $FutureProviderElement<KarZararVeri> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<KarZararVeri> create(Ref ref) {
    return karZarar(ref);
  }
}

String _$karZararHash() => r'de698fc30d1f4671adc09824b08b566666a9e99a';
