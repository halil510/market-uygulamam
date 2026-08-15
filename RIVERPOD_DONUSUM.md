# MarketPlus — Riverpod Dönüşüm Kılavuzu

## Genel Bakış

Bu döküman, MarketPlus uygulamasının `provider` paketinden `flutter_riverpod`'a
geçişini adım adım açıklar. Dönüşüm kademeli yapılmıştır; eski ve yeni kod
aynı anda çalışabilir, böylece risk minimuma indirilmiştir.

---

## 1. Hazırlık — pubspec.yaml güncellemesi

```bash
# Yeni paketleri ekle
flutter pub add flutter_riverpod riverpod_annotation hooks_riverpod

# Dev bağımlılıkları ekle
flutter pub add --dev riverpod_generator custom_lint riverpod_lint

# Eski provider paketini kaldır (Riverpod'a tamamen geçince)
flutter pub remove provider
```

Code generation başlatmak için:
```bash
dart run build_runner watch --delete-conflicting-outputs
```

---

## 2. Uygulama kök yapısı değişikliği

### ÖNCE (ana.dart):
```dart
runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthSaglayici()),
      ChangeNotifierProvider(create: (_) => SepetSaglayici()),
      // ... 13 provider daha
    ],
    child: const MarketPlusApp(),
  ),
);
```

### SONRA (ana.dart):
```dart
runApp(
  ProviderScope(
    observers: [if (kDebugMode) _RiverpodLogger()],
    child: MarketPlusApp(baslangicTema: baslangicTema),
  ),
);
```

**Fark:** ProviderScope ile tüm provider'lar lazy (ihtiyaç duyulduğunda)
yüklenir. 13 ayrı ChangeNotifierProvider tanımı kaldırıldı.

---

## 3. Widget Dönüşüm Şablonları

### StatelessWidget → ConsumerWidget
```dart
// ÖNCE
class UrunListeEkrani extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final notifier = context.read<UrunListeNotifier>();
    final urunler  = context.watch<UrunListeNotifier>().urunler;
    ...
  }
}

// SONRA
class UrunListeEkrani extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durum  = ref.watch(urunlerProvider);
    final urunler = durum.urunler;
    ...
  }
}
```

### StatefulWidget → ConsumerStatefulWidget
```dart
// ÖNCE
class DashboardEkrani extends StatefulWidget { ... }
class _DashboardEkraniState extends State<DashboardEkrani> {
  @override
  Widget build(BuildContext context) {
    final data = context.watch<DashboardSaglayici>().gunlukCiro;
    ...
  }
}

// SONRA
class DashboardEkrani extends ConsumerStatefulWidget { ... }
class _DashboardEkraniState extends ConsumerState<DashboardEkrani> {
  @override
  Widget build(BuildContext context) {
    final dashAsync = ref.watch(dashboardProvider);
    ...
  }
}
```

---

## 4. Provider Okuma / Yazma

### context.read() → ref.read()
```dart
// ÖNCE
context.read<HizliSatisNotifier>().sepeteEkle(urun);

// SONRA
ref.read(sepetProvider.notifier).ekle(urun);
```

### context.watch() → ref.watch()
```dart
// ÖNCE
final sepet = context.watch<SepetSaglayici>();
final tutar = sepet.genelToplam;

// SONRA
final sepet = ref.watch(sepetProvider);
final tutar = sepet.genelToplam;
```

### AsyncValue ile loading/error/data
```dart
// Riverpod ile async provider'lar AsyncValue döner
ref.watch(dashboardProvider).when(
  loading: () => const CircularProgressIndicator(),
  error:   (e, st) => Text('Hata: $e'),
  data:    (veri) => DashboardIcerik(veri: veri),
);
```

---

## 5. GoRouter — refreshListenable

### ÖNCE:
```dart
GoRouter(
  refreshListenable: AuthNotifier(), // singleton ChangeNotifier
  redirect: (context, state) {
    final auth = AuthServisi();
    if (!auth.girisYapilmis && state.location != '/giris') return '/giris';
    return null;
  },
)
```

### SONRA:
```dart
// _AuthListenable GoRouter'ı authProvider değişince yeniler
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(WidgetRef ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}

GoRouter(
  refreshListenable: _AuthListenable(ref),
  redirect: (context, state) {
    final auth = ref.read(authProvider);
    if (!auth.girisYapildi && state.location != '/giris') return '/giris';
    return null;
  },
)
```

---

## 6. Dönüşüm Sırası (Önerilen)

| Aşama | Dosyalar | Neden önce? |
|-------|----------|-------------|
| 1 | `pubspec.yaml`, `ana.dart` | Temel altyapı |
| 2 | `auth_provider.dart`, `uygulama_router.dart` | Router auth'a bağlı |
| 3 | `sepet_provider.dart`, `hizli_satis_ekrani.dart` | Satış kritik |
| 4 | `urun_provider.dart`, `urun_liste_ekrani.dart` | Çok kullanılan |
| 5 | `dashboard_provider.dart`, `dashboard_ekrani.dart` | Ana ekran |
| 6 | Diğer tüm notifier'lar | Kademeli |

---

## 7. Sıkça Yapılan Hatalar

### ❌ Provider.of kullanmak
```dart
// YANLIŞ — Riverpod'da çalışmaz
final x = Provider.of<SepetSaglayici>(context);

// DOĞRU
final x = ref.watch(sepetProvider);
```

### ❌ ref.read() ile UI build etmek
```dart
// YANLIŞ — değişince yenilenmez
final urunler = ref.read(urunlerProvider).urunler;

// DOĞRU — build içinde watch kullan
final urunler = ref.watch(urunlerProvider).urunler;
```

### ❌ initState içinde ref.watch
```dart
// YANLIŞ
@override
void initState() {
  super.initState();
  ref.watch(someProvider); // initState'te watch olmaz
}

// DOĞRU — ref.listen veya addPostFrameCallback
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(urunlerProvider.notifier).yukle();
  });
}
```

---

## 8. Yeni Ekranlar (Riverpod ile)

Bu versiyonda eklenen yeni ekranlar:

| Ekran | Yol | Açıklama |
|-------|-----|----------|
| `PersonelListeEkrani` | `/personel` | Personel yönetimi (yeni) |
| `BildirimMerkeziEkrani` | `/bildirimler` | Uygulama bildirimleri (yeni) |
| `KasaRaporEkrani` | `/kasa/rapor` | Kasa hareket raporu (yeni) |

---

## 9. DB Migration v5 — Yeni Tablolar

```sql
-- bildirim_tercihleri
CREATE TABLE bildirim_tercihleri (
  id INTEGER PRIMARY KEY,
  kullanici_id INTEGER,
  olay_turu TEXT NOT NULL,
  aktif INTEGER DEFAULT 1,
  esik_deger REAL,
  bildirim_saati TEXT
);

-- urunler — yeni kolonlar
ALTER TABLE urunler ADD COLUMN max_stok REAL DEFAULT 0;

-- satislar — yeni kolon
ALTER TABLE satislar ADD COLUMN servis_ucreti REAL DEFAULT 0;

-- vardiya_detay
CREATE TABLE vardiya_detay (
  id INTEGER PRIMARY KEY,
  vardiya_id INTEGER NOT NULL,
  saat INTEGER NOT NULL,
  satis_sayisi INTEGER DEFAULT 0,
  toplam_ciro REAL DEFAULT 0
);

-- personel — yeni kolonlar
ALTER TABLE personel ADD COLUMN maas REAL DEFAULT 0;
ALTER TABLE personel ADD COLUMN calisma_saati REAL DEFAULT 0;
ALTER TABLE personel ADD COLUMN ise_baslama_tarihi TEXT;
ALTER TABLE personel ADD COLUMN departman TEXT;

-- favori_urunler
CREATE TABLE favori_urunler (
  id INTEGER PRIMARY KEY,
  kullanici_id INTEGER NOT NULL,
  urun_id INTEGER NOT NULL,
  sira INTEGER DEFAULT 0,
  UNIQUE(kullanici_id, urun_id)
);
```

---

## 10. Build Runner

Riverpod code generation için:

```bash
# Tek seferlik
dart run build_runner build --delete-conflicting-outputs

# Otomatik izleme (geliştirme sırasında)
dart run build_runner watch --delete-conflicting-outputs
```

Her `@riverpod` annotated dosya için `*.g.dart` oluşturulur.
Bu dosyaları `.gitignore`'a eklemeyin — CI/CD'de yeniden üretilmeleri gerekir.

---

*MarketPlus v2.2.0 — Riverpod dönüşümü tamamlandı*
