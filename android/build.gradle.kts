// Top-level build.gradle.kts file

allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // Güncel dependency çakışmalarını çözmek için force sürümler
    configurations.all {
        resolutionStrategy {
            force("androidx.core:core-ktx:1.13.1")
            force("androidx.activity:activity-ktx:1.9.3")
            force("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
        }
    }
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