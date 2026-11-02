import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = providers.environmentVariable("LETSCOOK_SIGNING_PROPERTIES")
    .orElse(providers.systemProperty("user.home").map {
        "$it/.letscook/secrets/android-signing.properties"
    })
    .map(::file)
    .get()
val hasReleaseSigning = releaseSigningPropertiesFile.isFile
if (hasReleaseSigning) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

android {
    namespace = "world.letscook.lets_cook_mobile"
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
        applicationId = "world.letscook.lets_cook_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appAuthRedirectScheme"] = "world.letscook.app"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Flutter/AGP clean builds currently lose several legacy plugin
            // classes during R8 graph construction. Keep release packaging
            // deterministic until those plugins migrate to the new API.
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

flutter {
    source = "../.."
}

// Keep these legacy Java/Kotlin plugins on javac's compile classpath during a
// fully clean release build. Flutter's generated registrant references their
// concrete classes before the normal runtime plugin wiring is assembled.
dependencies {
    implementation(project(":flutter_appauth"))
    implementation(project(":flutter_background"))
}
