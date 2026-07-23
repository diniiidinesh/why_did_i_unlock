import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()
if (hasKeystoreProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.whydidiunlock.why_did_i_unlock"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.whydidiunlock.why_did_i_unlock"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        //
        // minSdk/targetSdk are PINNED, not inherited from `flutter.*`
        // (T8, docs/PLAY_SUBMISSION.md §3b.3, sign-off 2026-07-24):
        // - minSdk 29 (Android 10) matches the documented baseline
        //   (CLAUDE.md §8) — the overlay + foreground-service stack has only
        //   ever been tested at API 29+. Left as `flutter.minSdkVersion`
        //   (currently 24), sideloading hid a real gap: shipping to versions
        //   below the app's actual tested floor, which a Play listing would
        //   not hide.
        // - targetSdk 36 is today's `flutter.targetSdkVersion` resolved
        //   value, pinned explicitly so a future `flutter upgrade` can't
        //   silently move it — intentional version bumps should be a
        //   deliberate edit here, not a side effect of the toolchain
        //   updating. Revisit if Play's compliance floor moves past 36.
        minSdk = 29
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystoreProperties) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file("app/${keystoreProperties["storeFile"]}")
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Uses the real release keystore (android/key.properties) when present.
            // Falls back to the debug key so the project still builds on a fresh
            // clone before key.properties exists (it's gitignored, never committed).
            signingConfig = if (hasKeystoreProperties) {
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
