plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.emergencia.aegis_node"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.emergencia.aegis_node"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 1. Agrega este bloque para extraer librerías nativas (.so) en dispositivos modernos
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // 2. Busca tu bloque buildTypes y déjalo exactamente así:
    buildTypes {
        release {
            // Mantiene las firmas de depuración por defecto para pruebas locales
            signingConfig = signingConfigs.getByName("debug")
            
            // Evita que Android recorte o renombre las clases C++ de Kiwix al compilar
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
} 

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
dependencies {
    implementation("org.kiwix:libkiwix:2.7.0")
}
