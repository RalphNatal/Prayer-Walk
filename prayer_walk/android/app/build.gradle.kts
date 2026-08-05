import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Real credentials live in `android/key.properties`, which is
// git-ignored — see `key.properties.example` for the four keys it needs and
// the `keytool` command that generates the keystore.
//
// Deliberately no fallback to the debug key for a release build: a release
// build with no keystore fails the Gradle configuration below rather than
// silently shipping something Google Play will reject. Debug and profile
// builds are untouched by any of this and keep working with zero setup.
val keyPropertiesFile = rootProject.file("key.properties")
val hasKeyProperties = keyPropertiesFile.exists()
val keyProperties = Properties()
if (hasKeyProperties) {
    FileInputStream(keyPropertiesFile).use { keyProperties.load(it) }
}

android {
    namespace = "com.calledpresentations.prayer_walk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.calledpresentations.prayer_walk"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Credential Manager (google_sign_in v7) requires API 23+; never go below
        // Flutter's own floor either.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeyProperties) {
            create("release") {
                // Resolved against the root project (`android/`), not this
                // module (`android/app/`) — that's where key.properties itself
                // lives, and where key.properties.example tells people to put
                // the .jks. `rootProject.file` still honours an absolute path
                // unchanged, so both forms of storeFile work.
                val storeFilePath = keyProperties.getProperty("storeFile")
                val resolvedStoreFile = rootProject.file(storeFilePath)
                if (!resolvedStoreFile.exists()) {
                    throw GradleException(
                        "Cannot build release: the keystore named by storeFile in " +
                            "android/key.properties does not exist.\n" +
                            "storeFile=$storeFilePath\n" +
                            "Resolved to: ${resolvedStoreFile.absolutePath}\n\n" +
                            "storeFile is resolved relative to android/, not " +
                            "android/app/. Either put the .jks directly in " +
                            "android/, or set storeFile to an absolute path.\n" +
                            "See android/key.properties.example for details."
                    )
                }
                storeFile = resolvedStoreFile
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeyProperties) {
                signingConfigs.getByName("release")
            } else {
                throw GradleException(
                    "Cannot build release: android/key.properties is missing.\n" +
                        "A release build must be signed with a real upload key — " +
                        "this build type never falls back to the debug key.\n\n" +
                        "1. Generate an upload keystore (once):\n" +
                        "   keytool -genkey -v -keystore prayer-walk-upload.jks " +
                        "-keyalg RSA -keysize 2048 -validity 10000 " +
                        "-alias prayer_walk_upload\n" +
                        "2. Copy android/key.properties.example to " +
                        "android/key.properties and fill in the four values.\n" +
                        "See android/key.properties.example for details."
                )
            }

            // Run R8. Without the keep rules in proguard-rules.pro, R8 strips
            // Credential Manager's reflectively-loaded Play Services backend and
            // Google sign-in fails in release builds only.
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
