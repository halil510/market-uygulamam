// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tema_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Tema)
final temaProvider = TemaProvider._();

final class TemaProvider extends $NotifierProvider<Tema, String> {
  TemaProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'temaProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$temaHash();

  @$internal
  @override
  Tema create() => Tema();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$temaHash() => r'107fc18d4dcd78855598902bfe4b552473b351ca';

abstract class _$Tema extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
