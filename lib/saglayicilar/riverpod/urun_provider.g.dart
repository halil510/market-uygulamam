// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'urun_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(UrunFiltresi)
final urunFiltresiProvider = UrunFiltresiProvider._();

final class UrunFiltresiProvider
    extends $NotifierProvider<UrunFiltresi, UrunFiltre> {
  UrunFiltresiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'urunFiltresiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$urunFiltresiHash();

  @$internal
  @override
  UrunFiltresi create() => UrunFiltresi();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UrunFiltre value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UrunFiltre>(value),
    );
  }
}

String _$urunFiltresiHash() => r'4d1862d646580569503162e945cbcd2b137044e1';

abstract class _$UrunFiltresi extends $Notifier<UrunFiltre> {
  UrunFiltre build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UrunFiltre, UrunFiltre>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UrunFiltre, UrunFiltre>,
              UrunFiltre,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(Urunler)
final urunlerProvider = UrunlerProvider._();

final class UrunlerProvider extends $NotifierProvider<Urunler, UrunListeDurum> {
  UrunlerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'urunlerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$urunlerHash();

  @$internal
  @override
  Urunler create() => Urunler();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UrunListeDurum value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UrunListeDurum>(value),
    );
  }
}

String _$urunlerHash() => r'a08fa0ba5460824b064bd48d631845720b54ae02';

abstract class _$Urunler extends $Notifier<UrunListeDurum> {
  UrunListeDurum build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UrunListeDurum, UrunListeDurum>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UrunListeDurum, UrunListeDurum>,
              UrunListeDurum,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(urunYukleniyor)
final urunYukleniyorProvider = UrunYukleniyorProvider._();

final class UrunYukleniyorProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  UrunYukleniyorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'urunYukleniyorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$urunYukleniyorHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return urunYukleniyor(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$urunYukleniyorHash() => r'23c29c66cfdbb73031ab5e5bdd55b2fcb7be707b';

@ProviderFor(urunSecimModu)
final urunSecimModuProvider = UrunSecimModuProvider._();

final class UrunSecimModuProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  UrunSecimModuProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'urunSecimModuProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$urunSecimModuHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return urunSecimModu(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$urunSecimModuHash() => r'82b5ec609099c8ad98fbea677c6934d921e00e7b';

@ProviderFor(urunSeciliSayisi)
final urunSeciliSayisiProvider = UrunSeciliSayisiProvider._();

final class UrunSeciliSayisiProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  UrunSeciliSayisiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'urunSeciliSayisiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$urunSeciliSayisiHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return urunSeciliSayisi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$urunSeciliSayisiHash() => r'907996388ddb8feee153c93d9776354af75c2a36';

@ProviderFor(kritikStokSayisi)
final kritikStokSayisiProvider = KritikStokSayisiProvider._();

final class KritikStokSayisiProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  KritikStokSayisiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'kritikStokSayisiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$kritikStokSayisiHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return kritikStokSayisi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$kritikStokSayisiHash() => r'ae47ca9f3c88ff364faf00612c663332c7f87871';

@ProviderFor(urunDetay)
final urunDetayProvider = UrunDetayFamily._();

final class UrunDetayProvider
    extends
        $FunctionalProvider<
          AsyncValue<UrunModel?>,
          UrunModel?,
          FutureOr<UrunModel?>
        >
    with $FutureModifier<UrunModel?>, $FutureProvider<UrunModel?> {
  UrunDetayProvider._({
    required UrunDetayFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'urunDetayProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$urunDetayHash();

  @override
  String toString() {
    return r'urunDetayProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<UrunModel?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<UrunModel?> create(Ref ref) {
    final argument = this.argument as int;
    return urunDetay(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UrunDetayProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$urunDetayHash() => r'db75bc247cd02278c87dd9faae0493e57cecbb91';

final class UrunDetayFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<UrunModel?>, int> {
  UrunDetayFamily._()
    : super(
        retry: null,
        name: r'urunDetayProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UrunDetayProvider call(int id) =>
      UrunDetayProvider._(argument: id, from: this);

  @override
  String toString() => r'urunDetayProvider';
}

@ProviderFor(barkodileUrunBul)
final barkodileUrunBulProvider = BarkodileUrunBulFamily._();

final class BarkodileUrunBulProvider
    extends
        $FunctionalProvider<
          AsyncValue<UrunModel?>,
          UrunModel?,
          FutureOr<UrunModel?>
        >
    with $FutureModifier<UrunModel?>, $FutureProvider<UrunModel?> {
  BarkodileUrunBulProvider._({
    required BarkodileUrunBulFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'barkodileUrunBulProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$barkodileUrunBulHash();

  @override
  String toString() {
    return r'barkodileUrunBulProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<UrunModel?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<UrunModel?> create(Ref ref) {
    final argument = this.argument as String;
    return barkodileUrunBul(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is BarkodileUrunBulProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$barkodileUrunBulHash() => r'd06323bb5169b4c1a8a5182e710ea7c3829e85f1';

final class BarkodileUrunBulFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<UrunModel?>, String> {
  BarkodileUrunBulFamily._()
    : super(
        retry: null,
        name: r'barkodileUrunBulProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  BarkodileUrunBulProvider call(String barkod) =>
      BarkodileUrunBulProvider._(argument: barkod, from: this);

  @override
  String toString() => r'barkodileUrunBulProvider';
}
