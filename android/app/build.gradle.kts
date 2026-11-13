import java.util.Properties
import java.io.FileInputStream

// ── Release imzalama bilgileri ──────────────────────────────────────────
// Telefondaki uygulamanın "Güncelle" ile VERİSİ KORUNARAK güncellenmesi için
// her release APK AYNI anahtarla imzalanmalı. Anahtar GİT'E GİRMEZ.
// Aranan yerler, sırasıyla:
//   1) android/key.properties
//   2) <kullanıcı klasörü>/.barkodhalkmarket/key.properties  (yedek kopya)
// storeFile göreliyse önce key.properties'in klasörüne, sonra app modülüne
// göre çözülür. Anahtar bulunamazsa RELEASE derleme DURUR (aşağıda): debug
// anahtarıyla imzalı APK telefonda "Uygulama yüklenmedi" verir, tek çare
// uygulamayı silmektir = veri kaybı.
val keystorePropertiesFile: File? = listOf(
    rootProject.file("key.properties"),
    File(System.getProperty("user.home"), ".barkodhalkmarket/key.properties"),
).firstOrNull { it.exists() }
val keystoreProperties = Properties()
val keystoreVar = if (keystorePropertiesFile != null) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
    true
} else false

fun anahtarDosyasiCoz(yol: String): File {
    val f = File(yol)
    if (f.isAbsolute) return f
    val klasor = keystorePropertiesFile!!.parentFile
    return listOf(File(klasor, yol), project.file(yol)).firstOrNull { it.exists() } ?: File(klasor, yol)
}

// Anahtar yoksa release APK/AAB üretme (debug/robot derlemesi etkilenmez).
gradle.taskGraph.whenReady {
    val releaseUretiliyor = allTasks.any {
        it.name.contains("Release") && (it.name.startsWith("package") || it.name.startsWith("assemble") || it.name.startsWith("bundle"))
    }
    if (releaseUretiliyor && !keystoreVar) {
        throw GradleException(
            "\n\nİMZA ANAHTARI BULUNAMADI — release APK üretilmedi.\n" +
            "'.barkodhalkmarket' klasörünü (barkopro-release.jks + key.properties) yedeğinden\n" +
            "  ${System.getProperty("user.home")}${File.separator}.barkodhalkmarket\n" +
            "konumuna kopyalayın.\n"
        )
    }
}

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("io.sentry.android.gradle")
}

// AGP 9: eski `android { }` erişimcisi (BaseAppModuleExtension) kaldırılıyor —
// genel ApplicationExtension DSL tipiyle yapılandırılır.
configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.barkodhalkmarket.marketplus"

    // 37: permission_handler 13 en az 37 ile derlenmeyi istiyor (targetSdk ayrı, 36).
    compileSdk = 37

    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.barkodhalkmarket.marketplus"

        // DÜZELTME: "local_auth" (parmak izi/biyometrik giriş) paketi
        // minimum Android 6.0 (API 23) gerektiriyor — Flutter'ın kendi
        // varsayılan minSdkVersion'ı bunun altında kalabiliyordu, bu da
        // biyometrik kontrolün sessizce (hata vermeden) başarısız
        // olmasına yol açabilirdi. Artık açıkça 23'e sabitlendi.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = 36

        // DÜZELTME: Önceden sabit "1" / "1.0" yazıyordu — pubspec.yaml'daki
        // gerçek sürümle hiç senkron değildi. Artık Flutter'ın kendi
        // mekanizmasından otomatik alınıyor; pubspec.yaml'da version
        // güncellendiğinde burada hiçbir şey elle değiştirmeniz gerekmez.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreVar) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = anahtarDosyasiCoz(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        // Debug/robot yapısı gerçek uygulamayla YAN YANA kurulur (farklı paket
        // adı): test kurulumu gerçek uygulamayı/verisini silmez.
        debug {
            applicationIdSuffix = ".robot"
        }
        release {
            // key.properties varsa gerçek release anahtarıyla imzalar. Yoksa
            // release paketleme zaten yukarıdaki kontrolde DURUR; debug
            // dalı yalnızca APK üretmeyen görevler (ör. analiz) için.
            signingConfig = if (keystoreVar) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 🔴 Denemesi 2026-09-16'da yapıldı (protokol P1 maddesi):
            // önceden APK boyutu/native-plugin keep-rule riski nedeniyle
            // bilinçli olarak kapalıydı. proguard-rules.pro daha önceki
            // bir oturumda hazırlanmış ama hiç etkin olmamıştı — şimdi
            // devreye alınıyor. flutter build apk --release BAŞARIYLA
            // tamamlandı ama bu makinede gerçek Android cihaz/emulatör
            // YOK — yani release APK'nın çalışma zamanı davranışı (barkod
            // tarama, Bluetooth/USB yazdırma, biyometrik giriş, bildirim,
            // senkron) HİÇ doğrulanamadı. Gerçek cihazda test edilmeden
            // production'a güvenilmemeli.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

}

// Kotlin 2.3+: kotlinOptions kaldırıldı, compilerOptions DSL kullanılır.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("com.google.mlkit:text-recognition:16.0.1")
}

// ── Sentry native (ProGuard/R8) mapping yükleme ─────────────────────────
// 🔴 DÜZELTME (bu depoda gerçek bir release build ile doğrulandı):
// autoUploadProguardMapping=true'yu KOŞULSUZ açmak YANLIŞTI — plugin,
// kimlik bilgisi (SENTRY_AUTH_TOKEN / sentry.properties) yoksa YÜKLEMEYİ
// SESSİZCE ATLAMIYOR, ':app:uploadSentryProguardMappingsRelease'
// task'ı hata verip TÜM release build'i başarısız kılıyor — bu depoda
// (ve muhtemelen kullanıcının makinesinde de, kimlik bilgisi
// eklenmeden) BUGÜN tam olarak bu şekilde denendi ve doğrulandı.
// Bu yüzden yükleme, kimlik bilgisi GERÇEKTEN VARSA (SENTRY_AUTH_TOKEN
// ortam değişkeni ya da git'e eklenmemiş sentry.properties — bkz.
// .gitignore) etkinleştiriliyor; yoksa plugin'in upload task'ı build
// zincirine hiç eklenmiyor, `flutter build apk --release` eskisi gibi
// sorunsuz tamamlanıyor. Kimlik bilgisi eklendiğinde bir sonraki
// release build'de otomatik devreye girer — CrashServisi'nin
// runtime'da okuduğu Sentry DSN'inden (Ayarlar > Hata İzleme,
// kullanıcının kendi Sentry projesi) AYRI bir kimlik bilgisidir; bu,
// sadece mapping dosyasını YÜKLEMEK için CLI/API erişimidir.
val sentryTokenVar = !System.getenv("SENTRY_AUTH_TOKEN").isNullOrBlank() ||
        file("sentry.properties").exists() ||
        rootProject.file("sentry.properties").exists()

sentry {
    autoUploadProguardMapping = sentryTokenVar
    includeProguardMapping = true
    // Performans/oturum izleme bu üründe kullanılmıyor (bkz.
    // crash_servisi.dart — tracesSampleRate = 0.0); Sentry plugin'in bu
    // amaçla otomatik ekleyebileceği native/NDK bileşenlerine gerek yok.
    tracingInstrumentation {
        enabled.set(false)
    }
}

flutter {
    source = "../.."
}
