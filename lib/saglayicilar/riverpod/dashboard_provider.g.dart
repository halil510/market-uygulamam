// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Dashboard)
final dashboardProvider = DashboardProvider._();

final class DashboardProvider
    extends $AsyncNotifierProvider<Dashboard, DashboardVeri> {
  DashboardProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dashboardProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dashboardHash();

  @$internal
  @override
  Dashboard create() => Dashboard();
}

String _$dashboardHash() => r'b1343216f2aff45582b0ab94cac837e43527e749';

abstract class _$Dashboard extends $AsyncNotifier<DashboardVeri> {
  FutureOr<DashboardVeri> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<DashboardVeri>, DashboardVeri>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<DashboardVeri>, DashboardVeri>,
              AsyncValue<DashboardVeri>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(gunlukCiro)
final gunlukCiroProvider = GunlukCiroProvider._();

final class GunlukCiroProvider
    extends $FunctionalProvider<double, double, double>
    with $Provider<double> {
  GunlukCiroProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gunlukCiroProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gunlukCiroHash();

  @$internal
  @override
  $ProviderElement<double> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  double create(Ref ref) {
    return gunlukCiro(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$gunlukCiroHash() => r'ad1657e8c728f792ec264f9b21c2d3f1dbc86c6e';
