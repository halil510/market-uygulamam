// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'irsaliye_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(irsaliyeListesi)
final irsaliyeListesiProvider = IrsaliyeListesiProvider._();

final class IrsaliyeListesiProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Map<String, dynamic>>>,
          List<Map<String, dynamic>>,
          FutureOr<List<Map<String, dynamic>>>
        >
    with
        $FutureModifier<List<Map<String, dynamic>>>,
        $FutureProvider<List<Map<String, dynamic>>> {
  IrsaliyeListesiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'irsaliyeListesiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$irsaliyeListesiHash();

  @$internal
  @override
  $FutureProviderElement<List<Map<String, dynamic>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Map<String, dynamic>>> create(Ref ref) {
    return irsaliyeListesi(ref);
  }
}

String _$irsaliyeListesiHash() => r'f46485553384639b1e5f5309b7ae0f9953d7ae6f';
