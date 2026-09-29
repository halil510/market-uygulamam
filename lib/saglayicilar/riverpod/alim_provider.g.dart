// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alim_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Alim)
final alimProvider = AlimProvider._();

final class AlimProvider extends $NotifierProvider<Alim, AlimDurum> {
  AlimProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'alimProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$alimHash();

  @$internal
  @override
  Alim create() => Alim();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AlimDurum value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AlimDurum>(value),
    );
  }
}

String _$alimHash() => r'7e9ed080dfe9b86ce0b62d4cfe3b0836c60da24e';

abstract class _$Alim extends $Notifier<AlimDurum> {
  AlimDurum build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AlimDurum, AlimDurum>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AlimDurum, AlimDurum>,
              AlimDurum,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
