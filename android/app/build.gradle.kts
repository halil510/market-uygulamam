import java.util.Properties
import java.io.FileInputStream

// ── Release imzalama bilgileri ──────────────────────────────────────────
// android/key.properties dosyasından okunur. Bu dosya GİZLİDİR, git'e
// eklenmemeli (bkz. .gitignore). Dosya yoksa (ör. CI/CD ortamı, ya da
// başka bir geliştirici) release build debug anahtarına düşer — böylece
// build tamamen kırılmaz, ama Play Store'a yüklenemeyecek bir APK üretir.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val keystoreVar = if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    true
} else false

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.barkodhalkmarket.marketplus"

    compileSdk = 36

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
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties varsa gerçek release anahtarıyla, yoksa
            // (ör. bu dosyayı görmeyen bir CI ortamı) debug anahtarıyla
            // imzalar — böylece build asla çökmez.
            signingConfig = if (keystoreVar) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.mlkit:text-recognition:16.0.1")
}

flutter {
    source = "../.."
}
