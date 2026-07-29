import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.exists()) {
    releasePropertiesFile.inputStream().use(releaseProperties::load)
}

val releaseStoreFile = releaseProperties.getProperty("storeFile")
    ?: System.getenv("STUDIOFLOW_KEYSTORE_PATH")
val releaseStorePassword = releaseProperties.getProperty("storePassword")
    ?: System.getenv("STUDIOFLOW_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseProperties.getProperty("keyAlias")
    ?: System.getenv("STUDIOFLOW_KEY_ALIAS")
val releaseKeyPassword = releaseProperties.getProperty("keyPassword")
    ?: System.getenv("STUDIOFLOW_KEY_PASSWORD")
val releaseSigningAvailable = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.example.studioflow"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Mantido para preservar atualizações das instalações existentes.
        applicationId = "com.example.studioflow"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningAvailable) {
            create("studioflowRelease") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    lint {
        // O flutter analyze é a validação estática oficial deste projeto.
        // Evita consulta remota do Android Lint durante um release offline.
        checkReleaseBuilds = false
    }

    buildTypes {
        release {
            // Release AOT sem R8: evita falhas de disco/memória no ambiente de build.
            isMinifyEnabled = false
            isShrinkResources = false
            // Credenciais vêm de key.properties local ou variáveis de ambiente.
            // O fallback debug mantém builds de validação instaláveis sem gravar segredos.
            signingConfig = if (releaseSigningAvailable) {
                signingConfigs.getByName("studioflowRelease")
            } else {
                signingConfigs.getByName("debug")
            }
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