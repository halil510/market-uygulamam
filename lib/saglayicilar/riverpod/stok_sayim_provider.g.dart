// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stok_sayim_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(sayimGecmis)
final sayimGecmisProvider = SayimGecmisProvider._();

final class SayimGecmisProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Map<String, dynamic>>>,
          List<Map<String, dynamic>>,
          FutureOr<List<Map<String, dynamic>>>
        >
    with
        $FutureModifier<List<Map<String, dynamic>>>,
        $FutureProvider<List<Map<String, dynamic>>> {
  SayimGecmisProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sayimGecmisProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sayimGecmisHash();

  @$internal
  @override
  $FutureProviderElement<List<Map<String, dynamic>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Map<String, dynamic>>> create(Ref ref) {
    return sayimGecmis(ref);
  }
}

String _$sayimGecmisHash() => r'656b41fc91886a37efeb25fa7ede6e754d640ffa';

@ProviderFor(StokSayim)
final stokSayimProvider = StokSayimProvider._();

final class StokSayimProvider
    extends $NotifierProvider<StokSayim, StokSayimDurum> {
  StokSayimProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'stokSayimProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$stokSayimHash();

  @$internal
  @override
  StokSayim create() => StokSayim();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StokSayimDurum value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StokSayimDurum>(value),
    );
  }
}

String _$stokSayimHash() => r'10ae933f5b16d32493bfcd7ebafb15e0b5107056';

abstract class _$StokSayim extends $Notifier<StokSayimDurum> {
  StokSayimDurum build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StokSayimDurum, StokSayimDurum>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StokSayimDurum, StokSayimDurum>,
              StokSayimDurum,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(sayilanSayisi)
final sayilanSayisiProvider = SayilanSayisiProvider._();

final class SayilanSayisiProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  SayilanSayisiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sayilanSayisiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sayilanSayisiHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return sayilanSayisi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$sayilanSayisiHash() => r'070e0594d52426cacee2e8e7c23807f9332f5b34';
