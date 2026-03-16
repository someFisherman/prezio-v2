plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ch.soleco.prezio_v2"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "ch.soleco.prezio_v2"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (System.getenv("CI").toBoolean()) {
                storeFile = file(System.getenv("CM_KEYSTORE_PATH") ?: "/tmp/keystore.jks")
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD") ?: ""
                keyAlias = System.getenv("CM_KEY_ALIAS") ?: ""
                keyPassword = System.getenv("CM_KEY_PASSWORD") ?: ""
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("CI").toBoolean()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
