# ============================================================
# ProGuard/R8 Kuralları — Flutter + Bu Projenin Kullandığı Eklentiler
# ============================================================
# NOT: Bu dosya hazırlandı ama şu an build.gradle.kts'te
# isMinifyEnabled = false olduğu için AKTİF DEĞİL — yani şu an
# hiçbir riski yok. İleride kod küçültme/gizleme (minification) açmak
# isterseniz, önce bu kuralları etkinleştirip, MUTLAKA gerçek bir
# release APK ile TÜM özellikleri (yazdırma, tarama, senkronizasyon,
# GİB, PDF/Excel dışa aktarma) elle test etmeniz gerekir — ben bunu
# derleyip çalıştıramadığım için bu kuralların eksiksiz olduğunu
# garanti edemem, sadece Flutter ekosisteminde YAYGIN olarak
# kullanılan, bilinen standart kuralları içeriyor.

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
