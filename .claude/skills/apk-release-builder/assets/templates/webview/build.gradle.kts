// Root build file. The Android Gradle Plugin version is the single most
// common source of build failures - keep it in sync with the Gradle wrapper
// version (see references/app-templates.md for the compatibility matrix).
plugins {
    id("com.android.application") version "@@AGP_VERSION@@" apply false
}
