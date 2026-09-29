// Top-level build.gradle.kts file

allprojects {
    repositories {
        google()
        mavenCentral()
        // usb_serial'in yerel kütüphanesi (felHR85/UsbSerial) yalnız JitPack'te.
        maven("https://jitpack.io") {
            content { includeGroup("com.github.felHR85") }
        }
    }
    // androidx core/activity/lifecycle için eski sürüm zorlamaları (1.13.1 /
    // 1.9.3 / 2.8.7) kaldırıldı (2026-09-29): güncel eklentiler daha yeni
    // androidx istiyor, zorlama onları geriye çekip derleme/çalışma zamanı
    // uyumsuzluğu yaratıyordu.
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}