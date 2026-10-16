import java.util.Properties

plugins {
    id("com.android.application")
}

// Signing material is read from keystore.properties (never committed) or from
// environment variables, in that order. When neither exists the release build
// falls back to the debug signature so the build still produces an APK.
val keystorePropsFile = rootProject.file("keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) {
        keystorePropsFile.inputStream().use { load(it) }
    }
}

fun signingValue(key: String, envKey: String): String? =
    keystoreProps.getProperty(key)?.takeIf { it.isNotBlank() }
        ?: System.getenv(envKey)?.takeIf { it.isNotBlank() }

val releaseStoreFile: String? = signingValue("storeFile", "RELEASE_STORE_FILE")
val releaseStorePassword: String? = signingValue("storePassword", "RELEASE_STORE_PASSWORD")
val releaseKeyAlias: String? = signingValue("keyAlias", "RELEASE_KEY_ALIAS")
val releaseKeyPassword: String? = signingValue("keyPassword", "RELEASE_KEY_PASSWORD")
val hasReleaseSigning = !releaseStoreFile.isNullOrBlank() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "@@PACKAGE@@"
    compileSdk = @@COMPILE_SDK@@

    defaultConfig {
        applicationId = "@@PACKAGE@@"
        minSdk = @@MIN_SDK@@
        targetSdk = @@TARGET_SDK@@
        versionCode = @@VERSION_CODE@@
        versionName = "@@VERSION_NAME@@"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Keep minification off by default: R8 needs rules for every
            // reflection/JS-bridge path and is the #1 cause of "built fine but
            // crashes on device". Turn both on once the app is stable.
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // A release build should never die on a lint warning. Reports are still
    // generated under app/build/reports/lint-results-release.html.
    lint {
        abortOnError = false
        checkReleaseBuilds = true
        warningsAsErrors = false
    }

    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "/META-INF/DEPENDENCIES"
            )
        }
    }
}

dependencies {
    // Intentionally empty. The default template is framework-only (WebView +
    // Activity), which keeps the dependency download small and the build fast.
    // Add AndroidX/Compose/Material deps here when the app needs them, and set
    // android.useAndroidX=true in gradle.properties.
}
