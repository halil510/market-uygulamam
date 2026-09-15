pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false   // Kararlı sürüm
    // 🔴 Derin denetimde bulundu (P2): R8/ProGuard minification aktif
    // edildikten sonra (bkz. proguard-rules.pro) native (Kotlin/Java
    // katmanı) çökme raporları Sentry'de OKUNAMAZ hale gelebilirdi —
    // sınıf/metot isimleri karıştırılmış (mapping.txt olmadan
    // deobfuscate edilemez) gelirdi. Bu plugin release build'de
    // otomatik mapping yüklemeyi dener; SENTRY_AUTH_TOKEN/
    // android/sentry.properties YOKSA (varsayılan, bu depoda YOK)
    // sessizce atlar — build ASLA bundan etkilenmez, sadece token
    // eklenirse devreye girer.
    id("io.sentry.android.gradle") version "6.22.0" apply false
}

include(":app")