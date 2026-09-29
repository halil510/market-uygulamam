// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'satis_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SatisFiltresi)
final satisFiltresiProvider = SatisFiltresiProvider._();

final class SatisFiltresiProvider
    extends $NotifierProvider<SatisFiltresi, SatisFiltre> {
  SatisFiltresiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'satisFiltresiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$satisFiltresiHash();

  @$internal
  @override
  SatisFiltresi create() => SatisFiltresi();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SatisFiltre value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SatisFiltre>(value),
    );
  }
}

String _$satisFiltresiHash() => r'fd049e433cfbf97fd37a27e083700c6a4d323cf1';

abstract class _$SatisFiltresi extends $Notifier<SatisFiltre> {
  SatisFiltre build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SatisFiltre, SatisFiltre>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SatisFiltre, SatisFiltre>,
              SatisFiltre,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(Satislar)
final satislarProvider = SatislarProvider._();

final class SatislarProvider
    extends $NotifierProvider<Satislar, SatisListeDurum> {
  SatislarProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'satislarProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$satislarHash();

  @$internal
  @override
  Satislar create() => Satislar();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SatisListeDurum value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SatisListeDurum>(value),
    );
  }
}

String _$satislarHash() => r'841dc056fe77eee1e6faac87ec3e159d07963958';

abstract class _$Satislar extends $Notifier<SatisListeDurum> {
  SatisListeDurum build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SatisListeDurum, SatisListeDurum>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SatisListeDurum, SatisListeDurum>,
              SatisListeDurum,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(gunlukSatisOzeti)
final gunlukSatisOzetiProvider = GunlukSatisOzetiProvider._();

final class GunlukSatisOzetiProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, dynamic>>,
          Map<String, dynamic>,
          FutureOr<Map<String, dynamic>>
        >
    with
        $FutureModifier<Map<String, dynamic>>,
        $FutureProvider<Map<String, dynamic>> {
  GunlukSatisOzetiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gunlukSatisOzetiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gunlukSatisOzetiHash();

  @$internal
  @override
  $FutureProviderElement<Map<String, dynamic>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, dynamic>> create(Ref ref) {
    return gunlukSatisOzeti(ref);
  }
}

String _$gunlukSatisOzetiHash() => r'8a72dc0da7f37d9445010d4270e8ac26d1e0b408';

@ProviderFor(satisDetayi)
final satisDetayiProvider = SatisDetayiFamily._();

final class SatisDetayiProvider
    extends
        $FunctionalProvider<
          AsyncValue<SatisModel?>,
          SatisModel?,
          FutureOr<SatisModel?>
        >
    with $FutureModifier<SatisModel?>, $FutureProvider<SatisModel?> {
  SatisDetayiProvider._({
    required SatisDetayiFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'satisDetayiProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$satisDetayiHash();

  @override
  String toString() {
    return r'satisDetayiProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<SatisModel?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SatisModel?> create(Ref ref) {
    final argument = this.argument as int;
    return satisDetayi(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SatisDetayiProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$satisDetayiHash() => r'833bb1a5c1b09ce4e6a3704986e96a5b4539b6f3';

final class SatisDetayiFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<SatisModel?>, int> {
  SatisDetayiFamily._()
    : super(
        retry: null,
        name: r'satisDetayiProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SatisDetayiProvider call(int id) =>
      SatisDetayiProvider._(argument: id, from: this);

  @override
  String toString() => r'satisDetayiProvider';
}
