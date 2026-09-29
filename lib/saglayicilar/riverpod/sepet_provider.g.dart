// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sepet_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aktifPromosyonlar)
final aktifPromosyonlarProvider = AktifPromosyonlarProvider._();

final class AktifPromosyonlarProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<int, List<PromosyonModel>>>,
          Map<int, List<PromosyonModel>>,
          FutureOr<Map<int, List<PromosyonModel>>>
        >
    with
        $FutureModifier<Map<int, List<PromosyonModel>>>,
        $FutureProvider<Map<int, List<PromosyonModel>>> {
  AktifPromosyonlarProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aktifPromosyonlarProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aktifPromosyonlarHash();

  @$internal
  @override
  $FutureProviderElement<Map<int, List<PromosyonModel>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<int, List<PromosyonModel>>> create(Ref ref) {
    return aktifPromosyonlar(ref);
  }
}

String _$aktifPromosyonlarHash() => r'd9c8c49286222b81d520d356ce8d68654b1bf229';

@ProviderFor(Sepet)
final sepetProvider = SepetProvider._();

final class SepetProvider extends $NotifierProvider<Sepet, SepetDurum> {
  SepetProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sepetProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sepetHash();

  @$internal
  @override
  Sepet create() => Sepet();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SepetDurum value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SepetDurum>(value),
    );
  }
}

String _$sepetHash() => r'8b542eb2b8b431a82422f7c384a69b058e951139';

abstract class _$Sepet extends $Notifier<SepetDurum> {
  SepetDurum build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SepetDurum, SepetDurum>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SepetDurum, SepetDurum>,
              SepetDurum,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(sepetKalemSayisi)
final sepetKalemSayisiProvider = SepetKalemSayisiProvider._();

final class SepetKalemSayisiProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  SepetKalemSayisiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sepetKalemSayisiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sepetKalemSayisiHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return sepetKalemSayisi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$sepetKalemSayisiHash() => r'af5c8b2b8c43da6cc9719313cdbfe28f02f4f3f2';

@ProviderFor(sepetToplamTutar)
final sepetToplamTutarProvider = SepetToplamTutarProvider._();

final class SepetToplamTutarProvider
    extends $FunctionalProvider<double, double, double>
    with $Provider<double> {
  SepetToplamTutarProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sepetToplamTutarProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sepetToplamTutarHash();

  @$internal
  @override
  $ProviderElement<double> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  double create(Ref ref) {
    return sepetToplamTutar(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$sepetToplamTutarHash() => r'96f9c9bcbc115403fab78e02899ec0d4d385c5c3';

@ProviderFor(sepetBos)
final sepetBosProvider = SepetBosProvider._();

final class SepetBosProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  SepetBosProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sepetBosProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sepetBosHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return sepetBos(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$sepetBosHash() => r'bd157fa7b336d3ddc9da006ed9af073f18012934';

@ProviderFor(sepetMusteri)
final sepetMusteriProvider = SepetMusteriProvider._();

final class SepetMusteriProvider
    extends $FunctionalProvider<CariModel?, CariModel?, CariModel?>
    with $Provider<CariModel?> {
  SepetMusteriProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sepetMusteriProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sepetMusteriHash();

  @$internal
  @override
  $ProviderElement<CariModel?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CariModel? create(Ref ref) {
    return sepetMusteri(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CariModel? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CariModel?>(value),
    );
  }
}

String _$sepetMusteriHash() => r'4be910479c42055ebb7db5e10a47c217eb1285f8';
