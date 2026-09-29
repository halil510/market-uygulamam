// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Auth)
final authProvider = AuthProvider._();

final class AuthProvider extends $NotifierProvider<Auth, AuthState> {
  AuthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authHash();

  @$internal
  @override
  Auth create() => Auth();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthState>(value),
    );
  }
}

String _$authHash() => r'88a727731206408d0a7915f8de900e3c69a016f7';

abstract class _$Auth extends $Notifier<AuthState> {
  AuthState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AuthState, AuthState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AuthState, AuthState>,
              AuthState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(aktifKullanici)
final aktifKullaniciProvider = AktifKullaniciProvider._();

final class AktifKullaniciProvider
    extends
        $FunctionalProvider<KullaniciModel?, KullaniciModel?, KullaniciModel?>
    with $Provider<KullaniciModel?> {
  AktifKullaniciProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aktifKullaniciProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aktifKullaniciHash();

  @$internal
  @override
  $ProviderElement<KullaniciModel?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  KullaniciModel? create(Ref ref) {
    return aktifKullanici(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KullaniciModel? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KullaniciModel?>(value),
    );
  }
}

String _$aktifKullaniciHash() => r'25d2a7698549817451bea99625e8b4fd290c25ea';

@ProviderFor(girisYapildiMi)
final girisYapildiMiProvider = GirisYapildiMiProvider._();

final class GirisYapildiMiProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  GirisYapildiMiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'girisYapildiMiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$girisYapildiMiHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return girisYapildiMi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$girisYapildiMiHash() => r'0241521ceead8e75a1c8ad583f30b2eb69b96990';

@ProviderFor(isAdmin)
final isAdminProvider = IsAdminProvider._();

final class IsAdminProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  IsAdminProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isAdminProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isAdminHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return isAdmin(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isAdminHash() => r'752d7e15978376ea6d64670c3e3fe7bca17407a0';
