# App templates and the version matrix

## Toolchain version matrix

The default template is pinned to a known-good pair. Change both together -
AGP and Gradle are the most common cause of a build that fails before compiling
a single line of your code.

| AGP | Gradle (minimum) | JDK | Build tools | Max compileSdk | Notes |
| --- | --- | --- | --- | --- | --- |
| **8.13.0** (default) | **8.13** | 17 | 36.0.0 | 36 | Battle-tested DSL, widest documentation |
| 9.4.0 | 9.6.0 | 17 | 36.0.0 | 37 | Current line; built-in Kotlin support for Android apps |
| 9.0.1 | 9.1.0 | 17 | 36.0.0 | 36.1 | First 9.x; Kotlin apps must use built-in Kotlin |
| 8.7.3 | 8.9 | 17 | 35.0.0 | 35 | Older machines/projects; **below Play's API 36 floor** |

Override at scaffold time:

```bash
scripts/scaffold.sh --agp 9.4.0 --gradle 9.6.0 --compile-sdk 36 --target-sdk 36 ...
```

Platform floors that do not move: `compileSdk = targetSdk = 36` (Play requirement
since 2026-08-31), `minSdk = 26` (the template's adaptive XML launcher icon has
no PNG fallback), JDK 17+.

## Choosing an app architecture

The default is a **framework-only WebView host**. Decide with this table before
writing code; switching later means a new project.

| The user wants | Use | Why |
| --- | --- | --- |
| Any tool, dashboard, game, clock, tracker, form app, content app | **WebView template (default)** | The whole product is HTML/CSS/JS. Fewest moving parts, builds in one pass, previewable in a browser before packaging |
| Camera, push notifications, background location, in-app purchases, native file pickers | WebView + **Capacitor** | Keeps the web code, adds a plugin ecosystem with the native bits already written |
| Widgets, background services, heavy animation, tight memory/perf budgets, deep OS integration | **Native Kotlin + Jetpack Compose** | WebView cannot do app widgets or foreground services well |
| An existing Flutter / React Native / .NET MAUI codebase | That framework's own Android host | Only the packaging/signing steps of this skill apply |

### WebView template: what to edit

- `app/src/main/assets/www/index.html`, `app.js`, `styles.css` - the product.
- `app/src/main/res/values/strings.xml` - the launcher label.
- `app/src/main/res/values/colors.xml` - accent, window background, icon background.
- `app/src/main/res/drawable/ic_launcher_foreground.xml` - the logo (vector;
  keep artwork inside the central 66dp of the 108dp canvas).
- `MainActivity.START_URL` - change to an `https://` URL to ship a hosted web app
  instead of a bundled one. Doing so also makes in-app http(s) navigation stay
  inside the WebView.
- `app/src/main/AndroidManifest.xml` - permissions, orientation, deep links.

### Adding AndroidX dependencies (Compose, Material, Lifecycle...)

```kotlin
// gradle.properties
android.useAndroidX=true

// app/build.gradle.kts
plugins {
    id("com.android.application")
    kotlin("android") version "2.2.10"     // AGP 8.x; AGP 9 has Kotlin built in
}
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.09.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
}
android { buildFeatures { compose = true } }
```

Adding Kotlin also means adding the Kotlin plugin to the root `build.gradle.kts`
with `apply false`, and keeping KGP/AGP/Gradle inside the compatibility ranges
(KGP 2.2.x works with AGP 7.3.1-8.11.x; KGP 2.4.x with AGP 8.5.2-9.3.1). Every
extra plugin is another version to get wrong - only add what the app needs.

### Capacitor (web app + native plugins)

```bash
npm init -y
npm install @capacitor/core @capacitor/cli @capacitor/android
npx cap init "App Name" com.acme.app --web-dir=www
npx cap add android
# put the web build in www/, then:
npx cap sync android
cd android && ./gradlew --no-daemon clean assembleRelease bundleRelease
```

Capacitor generates its own `android/` Gradle project: use it instead of this
skill's template, but keep this skill's signing, verification and CI steps -
`keystore.properties` is read the same way, and
`assets/ci/android-release.yml` works with `working-directory: android`.

### Flutter / React Native

```bash
flutter build appbundle --release          # -> build/app/outputs/bundle/release/app-release.aab
flutter build apk --release --split-per-abi
cd android && ./gradlew bundleRelease      # React Native (after npx react-native bundle ...)
```

Both still need the same release keystore wiring and the same Play checks.

## Launcher icons

The template uses an adaptive icon made of two XML drawables, so no binary
assets are needed. To use a real logo:

```bash
# 512x512 source PNG -> all densities (ImageMagick)
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  name="${d%%:*}"; size="${d##*:}"
  mkdir -p "app/src/main/res/mipmap-$name"
  convert logo-512.png -resize "${size}x${size}" "app/src/main/res/mipmap-$name/ic_launcher.png"
done
```

Keep `mipmap-anydpi-v26/ic_launcher.xml` for adaptive icons on API 26+; the PNGs
then only serve API 25 and below. Play's store listing icon is a separate
512x512 PNG uploaded in the console, not part of the APK.

## Versioning

```kotlin
versionCode = 2          // integer, must increase for every Play upload
versionName = "1.1"      // human readable, free form
```

Bump both in `app/build.gradle.kts`, or override at scaffold time with
`--version-code` / `--version-name`. A useful convention: `versionCode` from the
date (`26101601`) so it can never go backwards, `versionName` semantic.

## Permissions

Add only what the app uses - every entry shows up in the Play Data safety form
and in the install prompt.

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />   <!-- runtime prompt on API 33+ -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" /> <!-- needs a Play declaration -->
```

Runtime permissions must be requested from code, and the WebView host must
implement `WebChromeClient.onPermissionRequest` for camera/microphone used from
JavaScript. Sensitive permissions (location, SMS, contacts, accessibility,
`QUERY_ALL_PACKAGES`) trigger a Play Console declaration form and can block
release.
