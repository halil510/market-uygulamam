// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kasa_rapor_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(kasaRapor)
final kasaRaporProvider = KasaRaporFamily._();

final class KasaRaporProvider
    extends
        $FunctionalProvider<
          AsyncValue<KasaRaporVeri>,
          KasaRaporVeri,
          FutureOr<KasaRaporVeri>
        >
    with $FutureModifier<KasaRaporVeri>, $FutureProvider<KasaRaporVeri> {
  KasaRaporProvider._({
    required KasaRaporFamily super.from,
    required DateTimeRange<DateTime> super.argument,
  }) : super(
         retry: null,
         name: r'kasaRaporProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$kasaRaporHash();

  @override
  String toString() {
    return r'kasaRaporProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<KasaRaporVeri> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<KasaRaporVeri> create(Ref ref) {
    final argument = this.argument as DateTimeRange<DateTime>;
    return kasaRapor(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is KasaRaporProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$kasaRaporHash() => r'4a4897377835d2c8a9ad6a7a7624ace685bb55af';

final class KasaRaporFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<KasaRaporVeri>,
          DateTimeRange<DateTime>
        > {
  KasaRaporFamily._()
    : super(
        retry: null,
        name: r'kasaRaporProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  KasaRaporProvider call(DateTimeRange<DateTime> aralik) =>
      KasaRaporProvider._(argument: aralik, from: this);

  @override
  String toString() => r'kasaRaporProvider';
}
