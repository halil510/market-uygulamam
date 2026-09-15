# ============================================================
# ProGuard/R8 Kuralları — Flutter + Bu Projenin Kullandığı Eklentiler
# ============================================================
# 2026-09-16: build.gradle.kts'te isMinifyEnabled = true yapılarak bu
# dosya ARTIK AKTİF. `flutter build apk --release` başarıyla derlendi
# ama bu makinede gerçek Android cihaz/emulatör YOK — yani aşağıdaki
# kurallar SADECE derleme zamanında doğrulandı, çalışma zamanında
# (runtime) DOĞRULANMADI. Production'a güvenmeden önce release APK'yı
# gerçek bir cihazda MUTLAKA elle test edin — özellikle: barkod/metin
# tarama (mobile_scanner, mlkit), yazdırma (Bluetooth/USB termal
# yazıcı: flutter_blue_plus, usb_serial), biyometrik giriş (local_auth),
# bildirimler (flutter_local_notifications), senkronizasyon (sqflite +
# http/dio), GİB e-Fatura, PDF/Excel dışa aktarma, Sentry crash
# reporting. Bir özellik release'de (debug'da değil) çöküyor/sessizce
# çalışmıyorsa, önce bu dosyaya ilgili paket için -keep kuralı eklemeyi
# deneyin — R8 genelde reflection/native köprü kullanan sınıfları
# silerek bu tür sessiz hatalara yol açar.

# Flutter'ın kendi motoru
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# sqflite (veritabanı) — reflection kullanabilir
-keep class com.tekartik.sqflite.** { *; }

# Google ML Kit (barkod/metin tanıma)
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# flutter_local_notifications — Android sistemi zamanlanmış bildirim
# receiver/service sınıflarını reflection ile örnekliyor; bilinen,
# yaygın bir R8 tuzağı (bkz. paketin kendi dokümantasyonu).
-keep class com.dexterous.** { *; }

# 🔴 Derin analizde bulundu: flutter_secure_storage (biyometrik/GİB
# şifreleri, oturum token'ları için kullanılıyor), AndroidX Security
# Crypto üzerinden Google Tink'i kullanır — Tink kendi sınıflarını
# reflection ile örnekler, R8 bu keep kuralı olmadan şifreleme
# sınıflarını silebilir ve release'de secure storage sessizce
# bozulabilir (yazma/okuma hatası ya da veri kaybı).
-keep class com.google.crypto.tink.** { *; }
-keep interface com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# JSON serileştirme kullanan modeller — Dart tarafında olduğu için
# genelde etkilenmez, ama native köprü sınıfları korunmalı
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Play Core (Flutter'ın deferred components için opsiyonel olarak
# beklediği, ama bu projede kullanılmayan sınıflar — R8 uyarı
# vermesin diye)
-dontwarn com.google.android.play.core.**

# Genel güvenlik: hata ayıklama bilgilerini SAKLAMA (release'de stack
# trace'lerin okunabilir olmasını istemiyorsanız bu satırı silin,
# tersine mühendisliği zorlaştırır ama sizin de hata ayıklamanızı
# zorlaştırır — bilinçli bir tercih).
-keepattributes SourceFile,LineNumberTable
