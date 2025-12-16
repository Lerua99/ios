allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.3.15")
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Fix pentru pluginuri fără `namespace` (AGP 8+)
// Setăm explicit pentru `flutter_app_badger` pentru a evita eroarea de configurare
subprojects {
    if (name == "flutter_app_badger") {
        afterEvaluate {
            val androidExt = extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val m = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    // Pachetul istoric al pluginului
                    m.invoke(androidExt, "fr.g123k.flutterappbadge")
                    println("[Gradle] Applied namespace for flutter_app_badger")
                } catch (_: Exception) {
                    // ignoră
                }
            }
        }
    }
}